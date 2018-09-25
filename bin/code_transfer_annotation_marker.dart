import 'dart:io';

import 'package:code_health/code_transfer.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

import 'package:logging/logging.dart' show Logger, Level, LogRecord;

/// Initialize logger.
void initLog() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    var message = new StringBuffer();
    message.write('${rec.level.name}: ${rec.time}: ${rec.loggerName}: ${rec.message}');
    if (rec.error != null) {
      message.write(' ${rec.error}');
    }
    print(message);
  });
}

main(List<String> arguments) {
  initLog();
  Logger.root.info('"package" "directory"');
  Logger.root.info('Current folder: "${path.current}"');
  new CodeTransferAnnotationMarker(arguments[0],arguments[1]).run();
}

class CodeTransferAnnotationMarker{
  static final Logger _log = new Logger('AnnotationMarker');
  final String package;
  final String directory;
  CodeTransferAnnotationMarker(this.package, this.directory){
    _log.info('Package: "${package}", directory: "${directory}"');
  }

  void run(){
    var glob = new Glob('*',recursive: true);
    int processingCount = 0;
    int skiptCount = 0;
    glob.listSync().forEach((file){
      if (file.statSync().type == FileSystemEntityType.directory){
        return;
      }
      if (file.path.contains('/.')){
        return;
      }
      if (path.extension(file.path)!='.dart'){
        return;
      }
      if (_processingFile(file.path)){
        _log.info('${file.path}');
        processingCount++;
      } else {
        skiptCount++;
        _log.info('Skip - ${file.path}');
      }
    });
    _log.info('Total changed: ${processingCount}, skip: ${skiptCount}');
  }

  bool _processingFile(String filePath) {
    var file = new File(filePath);
    var content = file.readAsStringSync();
    if (content.contains('@${CodeTransfer.annotationName}')) {
      return false;
    }
    if (content.contains('part of ')) {
      return false;
    }
    var startBodyIndex = content.indexOf('class');
    if (startBodyIndex == -1) {
      startBodyIndex = content.indexOf('enum');
    }
    var searchContent = content;
    if (startBodyIndex != -1) {
      searchContent = content.substring(0, startBodyIndex);
    }
    var startLibraryIndex = searchContent.indexOf('^library ');
    if (startLibraryIndex == -1) {
      startLibraryIndex = 0;
    } else {
      startLibraryIndex = searchContent.indexOf('\n', startLibraryIndex + 1);
    }
    var lastImportIndex = searchContent.lastIndexOf('import ');
    if (lastImportIndex == -1) {
      lastImportIndex = startLibraryIndex;
    }
    StringBuffer sb = new StringBuffer(content.substring(0, lastImportIndex));
    sb.writeln('import \'package:code_health_meta/code_health_meta.dart\';');
    sb.write('@${CodeTransfer.annotationName}(');
    if (package != '') {
      sb.write(CodeTransfer.annotationPackageParam);
      sb.write(': \'${package}\',');
    }
    sb.write(CodeTransfer.annotationDestDirectory);
    sb.write(': \'${path.normalize(path.join(directory,path.dirname(filePath)))}\'');

    sb.writeln(')');
    sb.writeln(content.substring(lastImportIndex));
    file.writeAsStringSync(sb.toString());
    return true;
  }
}