import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/ast/standard_ast_factory.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:build/build.dart';
import 'package:code_health/src/code_transfer/code_node.dart';
import 'package:build_resolvers/src/resolver.dart';
import 'package:analyzer/src/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/utilities.dart' show NodeReplacer;
import 'package:dart_style/dart_style.dart';

abstract class Action{
  int get priority;
  Future execute(Project project, AssetId assetId);

  @override
  String toString() {
    return '${this.runtimeType}';
  }
}

class _ChangeExportImportAction extends Action {
  static final dartFormatter = new DartFormatter();
  final int priority = 1;
  final Map<AssetId,AssetId> _replaceTo = <AssetId,AssetId>{};
  void replace(AssetId source, AssetId dest){
    _replaceTo[source] = dest;
  }
  _ChangeExportImportAction();
  @override
  Future execute(Project project, AssetId assetId) async{
    var fileNode = project.getOrCreatePackage(assetId.package).files[assetId];
    var compilationUnit = AstCloner.clone(fileNode.compilationUnit);
    (compilationUnit as CompilationUnit).directives.forEach((directive){
      if (directive is NamespaceDirective){
        var source = directive.uriSource;
        if (source is AssetBasedSource) {
          AssetId replaceAssetId = _replaceTo[source.assetId];
          if (replaceAssetId != null) {
            var importStr = '\'${replaceAssetId.uri.toString()}\'';
            var newUri = astFactory.simpleStringLiteral(
                new StringToken(TokenType.STRING, importStr, 0), importStr);
            directive.accept(new NodeReplacer(directive.uri, newUri));
          }
        }
      }
    });
    fileNode.compilationUnit = compilationUnit;
    var f = new File(path.join(project.packageGraph.allPackages[fileNode.assetId.package].path,fileNode.assetId.path));
    var source = fileNode.compilationUnit.toSource();
    await f.writeAsString(dartFormatter.format(source));
  }

}

class ChangeImportAction extends _ChangeExportImportAction{
  ChangeImportAction();
}

class ChangeExportAction extends _ChangeExportImportAction{
  ChangeExportAction();
}

class MoveFileAction extends Action{
  final int priority = 10;
  final AssetId source;
  final AssetId dest;
  MoveFileAction(this.source, this.dest);

  @override
  Future execute(Project project, AssetId assetId) async{

  }
}