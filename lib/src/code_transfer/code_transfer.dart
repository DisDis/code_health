import 'dart:async';
import 'dart:io';

//import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_resolvers/build_resolvers.dart';
import 'package:build_runner/build_runner.dart';
import 'package:build_runner_core/build_runner_core.dart';
import 'package:build_runner_core/src/asset/cache.dart';
import 'package:code_health/code_transfer.dart';
import 'package:code_health/src/code_transfer/actions.dart';
import 'package:code_health/src/code_transfer/code_node.dart' as node;
import 'package:code_health/src/code_transfer/work_result.dart';
import 'package:code_health/src/common/resolver_helper.dart';
//import 'package:code_health/src/common/directive_info.dart';
//import 'package:code_health/src/common/directive_priority.dart';
import 'package:code_health/src/common/visitor/exported_elements_visitor.dart';
import 'package:code_health/src/common/visitor/used_imported_elements_visitor.dart';
//import 'package:code_health/src/common/visitor/used_imported_elements_visitor.dart';
import 'package:glob/glob.dart';
//import 'package:analyzer/dart/ast/ast.dart';
import 'package:build_resolvers/src/resolver.dart';
import 'package:build/src/builder/build_step_impl.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:logging/logging.dart' as log show Logger;
import 'package:package_resolver/package_resolver.dart';
import 'package:analyzer/src/generated/engine.dart';

class CodeTransfer{
  static final log.Logger _log = new log.Logger('CodeTransfer');
  static final _resolvers = new AnalyzerResolvers(new AnalysisOptionsImpl()..preserveComments = true);
  static final packageGraph = new PackageGraph.forThisPackage();

  final io = new IOEnvironment(packageGraph, assumeTty:true);
  final _resourceManager = new ResourceManager();
  final WorkResult _workResult;
  CachingAssetReader _reader;
  final Settings settings;
  node.Project _project;

  CodeTransfer(Settings settings): this.settings = settings, _workResult = new WorkResult(settings);

  run() async {
    _log.info('Run');
    var stopwatch = new Stopwatch()..start();
    final Map<String, node.PackageNode> sourcePackages = <String, node.PackageNode>{};
    _log.info('Total packages: ${packageGraph.allPackages.length}');
    var allFiles = <AssetId> [];
    var count = 0;
    for(var package in packageGraph.allPackages.keys) {
      if (settings.excludePackages.contains(package)){
        _log.info("  '$package' skip");
        continue;
      }
      try {
        allFiles.addAll(await io.reader.findAssets(new Glob('lib/**.dart'), package: package).toList());
      } catch (e) {}
      try {
        allFiles.addAll(await io.reader.findAssets(new Glob('web/**.dart'), package: package).toList());
      } catch (e) {}
      try {
        allFiles.addAll(await io.reader.findAssets(new Glob('test/**.dart'), package: package).toList());
      } catch (e) {}
      try {
        allFiles.addAll(await io.reader.findAssets(new Glob('bin/**.dart'), package: package).toList());
      } catch (e) {}
      _log.info("  '$package' (${allFiles.length - count})");
      count = allFiles.length;
      sourcePackages[package] = new node.PackageNode();
    };
    _project = new node.Project(sourcePackages, packageGraph,path.join(path.dirname(packageGraph.root.path),'new_packages'));
    await _runForFiles(allFiles);
    await _execTransmutation();
    stopwatch.stop();
    _log.info('Time: ${stopwatch.elapsed.toString()}');
  }

  _runForFiles(Iterable<AssetId> inputs) async {
    var count = inputs.length;
    _log.info('Total files: $count');
    _reader = new CachingAssetReader(io.reader);
    var index = 0;
    for (var input in inputs) {
      index++;
      _log.info('${index.toString().padLeft(6)}/$count $input');
      await _parseInput(input);
    }
    _log.info('Parsing completed');
//    _showReport();
  }

  static const String annotationName = 'CHTransfer';
  static const String annotationPackageParam = 'package';
  static const String _annotationExportParam = 'export';
  static const String annotationDestDirectory = 'directory';
  static const String _annotationDestFilename = 'filename';


  Future _parseInput(AssetId inputId) async {
    var buildStep = new BuildStepImpl(
        inputId,
        [],
        _reader,
        null,
        inputId.package,
        _resolvers,
        _resourceManager);
    Resolver resolver = await _resolvers.get(buildStep);
    try {
      var lib = await buildStep.inputLibrary;
      var usedImportedElementsVisitor = new UsedImportedElementsVisitor(lib);
      lib.unit.accept(usedImportedElementsVisitor);
      var usedElements = _getUsedElements(usedImportedElementsVisitor.usedElements);
      var optLibraries = await _getLibrariesForElemets(inputId, usedElements, resolver);
      var packageNode = _project.getOrCreatePackage(inputId.package);
      var fileNode = _libraryElementToFileNode(inputId, lib, optLibraries);
//      parseCompilationUnit(lib.source.contents.data)
      packageNode.files[inputId] = fileNode;


      for (var declaration in lib.unit.declarations) {
          var annotation = ResolverHelper.getAnnotation(declaration, annotationName);
          if (annotation != null){
            fileNode.transferAssetId = _annotationToAssetId(inputId, annotation);
          }
      }
      for (var declaration in lib.unit.directives) {
        var annotation = ResolverHelper.getAnnotation(declaration, annotationName);
        if (annotation != null){
          fileNode.transferAssetId = _annotationToAssetId(inputId, annotation);
        }
      }
      if (fileNode.transferAssetId != null && fileNode.transferAssetId != fileNode.assetId){
//        _log.info('${fileNode.assetId} -> ${fileNode.transferAssetId}');
        _project.addTransferInfo(new node.TransferInfo(fileNode.assetId, fileNode.transferAssetId));
      }

      

//      var output = _generateImportText(inputId, lib, optLibraries);
//      if (output.isNotEmpty) {
//        final stat = _workResult.statistics[inputId];
//        print('// FileName: "$inputId"  unique old: ${stat.sourceNode} -> new: ${stat.optNode}, agg old: ${stat.sourceAggNode} -> new: ${stat.optAggNode}');
//        print(output);
//        if (settings.applyImports) {
//          final firstImport = lib.unit.directives.firstWhere((dir) => dir.keyword.keyword == Keyword.IMPORT);
//          final lastImport = lib.unit.directives.lastWhere((dir) => dir.keyword.keyword == Keyword.IMPORT);
//
//          _replaceImportsInFile(inputId.path, output, firstImport.firstTokenAfterCommentAndMetadata.charOffset,
//              lastImport.endToken.charOffset);
//        }
//      }
    } catch(e,st){
      _log.fine("Skip '$inputId'", e, st);
    }
  }


  _parseLibraryStat(Iterable<LibraryElement> libImports){
    /*var imports = new Set<LibraryElement>();
    _parseLib(Iterable<LibraryElement> libImports) {
      for (var item in libImports) {
        _workResult.addStatisticLibrary(item);
        if (imports.add(item) && !item.isDartCore && !item.isInSdk) {
          _parseLib(item.importedLibraries);
          _parseLib(item.exportedLibraries);
        }
      }
    }
    _parseLib(libImports);*/
  }
  int _getNodeCount(Iterable<LibraryElement> libImports) {
    var imports = new Set<LibraryElement>();
    _parseLib(Iterable<LibraryElement> libImports) {
      for (var item in libImports) {
        if (imports.add(item) && !item.isDartCore && !item.isInSdk) {
          _parseLib(item.importedLibraries);
          _parseLib(item.exportedLibraries);
        }
      }
    }
    _parseLib(libImports);
    return imports.length;
  }

  Future<Iterable<LibraryElement>> _getLibrariesForElemets(AssetId inputId, Iterable<Element> elements, Resolver resolver) async {
    var libraries = new Map<LibraryElement, List<Element>>();
    for (var element in elements) {
      var source = element.source;
      var library = element.library;
      var optLibrary = library;
      if (source is AssetBasedSource) {
        var assetId = source.assetId;

        if (assetId.package != inputId.package && source.assetId.path.contains('/src/')){
//          if (settings.allowSrcImport){
            optLibrary = library;
//          } else {
//            optLibrary = await _getOptimumLibraryWhichExportsElement(element, resolver);
//          }
        }
      }
      if (libraries.containsKey(optLibrary)) {
        libraries[optLibrary].add(element);
      } else {
        var elementsImportedFromLibrary = new List<Element>();
        elementsImportedFromLibrary.add(element);
        libraries[optLibrary] = elementsImportedFromLibrary;
      }
    }
    // Remove library if another library exports all entities from this library which we use
    var unnecessaryDependentLibraries = new Set<LibraryElement>();
//    if (!settings.allowUnnecessaryDependenciesImports) {
//      for (var library in libraries.keys) {
//        var elementsImportedFromLibrary = libraries[library];
//        for (var anotherLibrary in libraries.keys) {
//          if (library != anotherLibrary) {
//            if (elementsImportedFromLibrary.every((element) => _isLibraryExportsElement(anotherLibrary, element))) {
//              unnecessaryDependentLibraries.add(library);
//            }
//          }
//        }
//      }
//    }
    return libraries.keys.where((lib)=> !unnecessaryDependentLibraries.contains(lib));
  }

  Future<LibraryElement> _getOptimumLibraryWhichExportsElement(Element element, Resolver resolverI) async {
    var source = element.library.source as AssetBasedSource;
    var result = element.library;
    var resultImportsCount = 99999999;
    var assets = await io.reader.findAssets(new Glob('**.dart'), package: source.assetId.package).toList();
    for (var assetId in assets) {
      if (!assetId.path.contains('/src/')) {

        try {
          var resolver = resolverI;
          if (!await resolver.isLibrary(assetId)){
            resolver = await _resolvers.get(new BuildStepImpl(assetId, [], _reader, null, assetId.package, _resolvers, _resourceManager));
          }
          if (!await resolver.isLibrary(assetId)){
            //skip
            continue;
          }
          var library = await resolver.libraryFor(assetId);
          var count = _getNodeCount(library.exportedLibraries);
          if (resultImportsCount > count) {
            if (_isLibraryExportsElement(library, element)) {
              result = library;
              resultImportsCount = count;
            }
          }
        }
        catch (e, s) {
          _log.fine('Error asset: "$assetId" for "${source.assetId}"', e, s);
        }
      }
    }
    return result;
  }

  int _getNodeCountAccumulate(Iterable<LibraryElement> libImports) {
    var sum = 0;
    for (var lib in  libImports){
      sum += _getNodeCount([lib]);
    }
    return sum;
  }

  String _generateImportText(AssetId inputId, LibraryElement sourceLibrary, Iterable<LibraryElement> libraries) {
    /*var sb = new StringBuffer();
    _parseLibraryStat(sourceLibrary.importedLibraries);
    var sourceAccNodeCount = _getNodeCountAccumulate(sourceLibrary.importedLibraries);
    var optAccNodeCount = _getNodeCountAccumulate(libraries);
    var sourceNodeCount = _getNodeCount(sourceLibrary.importedLibraries);
    var optNodeCount = _getNodeCount(libraries);
    _workResult.addStatisticFile(inputId, sourceNodeCount, optNodeCount, sourceAccNodeCount, optAccNodeCount);

    if ( sourceNodeCount > optNodeCount || sourceAccNodeCount > optAccNodeCount || (sourceNodeCount == optNodeCount  && optAccNodeCount > sourceAccNodeCount) || _hasDeprectatedAssets(sourceLibrary.importedLibraries) || settings.showImportNodes) {
      final directives = new List<DirectiveInfo>();
      for (final library in libraries) {
        final source = library.source;
        final importUri = (source is AssetBasedSource)
            ? 'package:${source.assetId.package}${source.assetId.path.substring(3)}'
            : source.uri.toString();

        if (importUri == 'dart:core') continue;

        final priority = DirectivePriority.getDirectivePriority(importUri);
        var importString = "import '$importUri';";
        if (settings.showImportNodes){
          importString += '// nodes: ${_getNodeCount([library])}';
        }
        List<ImportDirective> existedImportDirectives = sourceLibrary.unit.directives.where((dir) => dir.keyword.keyword == Keyword.IMPORT);
        var isAnyImportContainsImportUrl = existedImportDirectives.any((importToken) => importToken.toSource().contains(importUri));
        if (!isAnyImportContainsImportUrl) {
          directives.add(new DirectiveInfo(priority, importUri, importString));
        } else {
          var existedImportDirective = existedImportDirectives.firstWhere((importToken) => importToken.toSource().contains(importUri));
          var existedImportUri = existedImportDirective.uri.toSource().replaceAll("'", '');
          directives.add(new DirectiveInfo(priority, existedImportUri, existedImportDirective.toSource()));
        }
      }

      directives.sort();

      DirectivePriority currentPriority;
      for (final directiveInfo in directives) {
        if (currentPriority != directiveInfo.priority) {
          if (sb.length != 0) {
            sb.writeln();
          }
          currentPriority = directiveInfo.priority;
        }
        sb.writeln(directiveInfo.text);
      }
    }
    return sb.toString();*/
  }

  bool _isLibraryExportsElement(LibraryElement library, Element elem) {
    var visitor = new ExportedElementsVisitor(library);
    library.unit.accept(visitor);
    if (visitor.elements.any((element) => element.name == elem.name)) {
      return true;
    }
    return false;
  }

  Iterable<Element> _getUsedElements(UsedImportedElements usedElements) {
    var elements = new Set<Element>();
    usedElements.prefixMap.values.expand((i)=>i).forEach((element) {
      var library = element.library;
      if (library != null &&
          library.isPublic &&
          !library.source.uri.toString().contains(':_')
      ) {
        elements.add(element);
      }
    });

    usedElements.elements.forEach((element) {
      var library = element.library;
      if (library != null &&
          library.isPublic &&
          !library.source.uri.toString().contains(':_')
      ) {
        elements.add(element);
      }
    });
    return elements;
  }

  void _showReport() {
   /* _log.info('--------------------------------');
    _log.info('Report: ${new DateTime.now().toIso8601String()}');
    _log.info('--------------------------------');

    _log.info('Total aggregate old: ${_workResult.sourceAggNodesTotal} -> new: ${_workResult.optAggNodesTotal} (${-((1.0 - _workResult.optAggNodesTotal/_workResult.sourceAggNodesTotal)*100).truncate() }%)');
    _log.info('Total uniq old: ${_workResult.sourceNodesTotal} -> new: ${_workResult.optNodesTotal} (${-((1.0 - _workResult.optNodesTotal/_workResult.sourceNodesTotal)*100).truncate() }%)');
    if (_workResult.topFile != null) {
      _log.info('Top issue file: ${_workResult.topFile} nodes: ${_workResult.topNodeFile}');
    }
    if (_workResult.maxOptFile != null) {
      _log.info('Best optimization file: ${_workResult.maxOptFile} delta: ${_workResult.maxOptDelta}');
    }
    _log.info('Average nodes per file: old: ${_workResult.sourceNodesTotal ~/ _workResult.fileCount} -> new: ${_workResult.optNodesTotal ~/ _workResult.fileCount}');
    _log.info('--------------------------------');
    _log.info('Stat export over limit "${settings.limitExportsPerFile}>" :');
    _log.info(' ${'Exp COUNT'.padLeft(9)} | ${'USES'.padLeft(8)} | $AssetId');
    var packagesListExport = _workResult.statisticsPerExportOverLimit.keys.toList(growable: false);
    packagesListExport.sort((a,b){
      var bb = _workResult.statisticsPerExportOverLimit[b];
      var aa = _workResult.statisticsPerExportOverLimit[a];
      return (bb.exportCount * bb.uses).compareTo(aa.exportCount * aa.uses);
    });
    packagesListExport.forEach((item){
      final expStat = _workResult.statisticsPerExportOverLimit[item];
      _log.info(' ${expStat.exportCount.toString().padLeft(9)} | ${expStat.uses.toString().padLeft(8)} | $item');
    });
    _log.info('--------------------------------');
    _log.info('Stat import package in tree (${_workResult.statisticsPerPackages.length}):');
    _log.info(' COUNT    | Package');
    var packagesList = _workResult.statisticsPerPackages.keys.toList(growable: false);
    packagesList.sort((a,b){
      return _workResult.statisticsPerPackages[b].compareTo(_workResult.statisticsPerPackages[a]);
    });
    packagesList.forEach((package){
      final count = _workResult.statisticsPerPackages[package];
      _log.info(' ${count.toString().padLeft(8)} | $package ');
    });
    _log.info('--------------------------------');*/
  }


  bool _hasDeprectatedAssets(List<LibraryElement> importedLibraries) {
    return importedLibraries.any((library) {
      return library.hasDeprecated;
    });
  }

  node.FileNode _libraryElementToFileNode(AssetId assetId, LibraryElement lib, Iterable<LibraryElement> optLibraries) {
    var fNode = new node.FileNode(assetId, lib.unit);
    for (var part in lib.parts) {
      var source = part.source;
      if (source is AssetBasedSource) {
        fNode.parts.add(source.assetId);
      }
    }
    for (var library in lib.importedLibraries) {
      var source = library.source;
      if (source is AssetBasedSource) {
        fNode.directImports.add(source.assetId);
      }
    }
    for (var library in lib.exportedLibraries) {
      var source = library.source;
      if (source is AssetBasedSource) {
        fNode.exports.add(source.assetId);
      }
    }
    for (var library in optLibraries) {
      var source = library.source;
      if (source is AssetBasedSource) {
        fNode.needImports.add(source.assetId);
      }
    }
    return fNode;
  }

  AssetId _annotationToAssetId(AssetId assetId, Annotation annotation) {
    AssetId result = assetId;
    var newDirectory = ResolverHelper.getAnnotationStrParameter(annotation, annotationDestDirectory);
    var newFilename = ResolverHelper.getAnnotationStrParameter(annotation, _annotationDestFilename);
    var newPackage = ResolverHelper.getAnnotationStrParameter(annotation, annotationPackageParam);
    if (newFilename == null) {
      newFilename = path.basename(assetId.path);
    }
    if (newDirectory == null) {
      newDirectory = path.dirname(assetId.path);
    } else {
      newDirectory = path.join('lib', newDirectory);
    }
    result = new AssetId(newPackage != null ? newPackage : assetId.package, path.join(newDirectory, newFilename));
//    if (result.path == assetId.path && result.package == assetId.package){
//      return null;
//    }
    return result;
  }

  void _validateAsset(AssetId assetId){
    if (_project.newPackages.contains(assetId.package)){
      return;
    }
    if (packageGraph.allPackages[assetId.package].dependencyType != DependencyType.path) {
      _addError('Package "${assetId.package}" not override, code_transfer can not modify "$assetId"');
    }
  }

  List<String> _errorLog = <String>[];
  void _addError(String message){
    if (_errorLog.isEmpty){
      _log.severe('--------------------- First ERROR ---------------------');
      _log.severe(message);
    }
    _errorLog.add(message);
  }

  _execTransmutation() async {
    _log.info('Start transmutation...');
    _errorLog.clear();
    Map<AssetId, List<AssetId>> directImportsByAssetId = {};
    Map<AssetId, List<AssetId>> exportsByAssetId = {};
    Map<AssetId, List<AssetId>> needImportsByAssetId = {};
    _preparationDependencies(directImportsByAssetId, exportsByAssetId, needImportsByAssetId);
    Map<AssetId, List<Action>> actionsByFile = <AssetId, List<Action>>{};
    for (var transferInfo in _project.transferAssets) {
      var actions = actionsByFile.putIfAbsent(transferInfo.source, () {
        _validateAsset(transferInfo.source);
        return <Action>[];
      });
      actions.add(new MoveFileAction(transferInfo.source, transferInfo.dest));
      var changeExportAssets = exportsByAssetId[transferInfo.source];
      AssetId exportAssetId;
      if (changeExportAssets != null) {
        _createChangeExportAction(changeExportAssets, actionsByFile, transferInfo);
        exportAssetId = changeExportAssets.first;
      }
      var changeAssets = directImportsByAssetId[transferInfo.source];
      if (changeAssets != null) {
        _createChangeImportAction(changeAssets, exportAssetId, actionsByFile, transferInfo);
      }
    }
    _project.newPackages.forEach((newPackageName){
      var newPackageId = new AssetId(newPackageName, 'pubspec.yaml');
      List<Action> list = _getActionsByFile(actionsByFile, newPackageId);
      list.add(new CreatePubspecAction());
    });
    var totalActions = 0;
    for (var actions in actionsByFile.values) {
      totalActions += actions.length;
    }
    if (_errorLog.isNotEmpty){
      _log.severe('Transmutation interrupt');
      _log.warning('     -------------------------------');
      _log.severe('Please fix all(${_errorLog.length}) errors or change settings');
      _errorLog.forEach(_log.severe);
      _log.warning('     -------------------------------');
      if (_fixCode.isNotEmpty){
        _log.warning('---- Fix Code ----');
        _fixCode.forEach(_log.warning);
      }
      return;
    }
    if (settings.onlySimulation){
      _log.info('onlySimulation=true; All ok');
    }
    var currentAction = 0;
    actionsByFile.forEach((assetId, actions) {
      actions.sort((x, y) => x.priority.compareTo(y.priority));
      actions.forEach((action) {
        currentAction++;
        _log.info("${currentAction.toString().padLeft(6)}/${totalActions} ${action} -> ${assetId}");
        action.execute(_project, assetId);
      });
    });
  }

  void _createChangeExportAction(List<AssetId> changeAssets, Map<AssetId, List<Action>> actionsByFile, node.TransferInfo transferInfo) {
    if (!settings.allowMultiExport && changeAssets.length > 1) {
      StringBuffer sb = new StringBuffer();
      changeAssets.forEach((item){ sb.write('"${item.toString()}"'); sb.writeln();});
      _addError('"${transferInfo.source}" exported[${changeAssets.length}] from ${sb}');
    }
    changeAssets.forEach((changeAsset) {
      List<Action> list = _getActionsByFile(actionsByFile, changeAsset);
      var action = _getAction<ChangeExportAction>(list, new ChangeExportAction());
      action.replace(transferInfo.source, transferInfo.dest);
      _createChangePubspecAction(actionsByFile, transferInfo);
    });
  }

  void _createChangeImportAction(List<AssetId> changeAssets, AssetId exportAssetId, Map<AssetId, List<Action>> actionsByFile, node.TransferInfo transferInfo) {
    var isSrcDest = transferInfo.dest.path.contains('/src/');
    if (exportAssetId == null && settings.forceExportFile){
      if (isSrcDest){
        _addError('forceExportFile=true; File "${transferInfo.source}" move to "${transferInfo.dest}" not exported');
        return;
      }
    }
    var dest = transferInfo.dest;
    if (!settings.allowSrcImport && isSrcDest && exportAssetId != null){
      // get moved export file
      dest = _project.getDestAsset(exportAssetId);
    }
    var hasUsedOtherPackage = false;
    changeAssets.forEach((changeAsset) {
        List<Action> list = _getActionsByFile(actionsByFile, changeAsset);
        var action = _getAction<ChangeImportAction>(list, new ChangeImportAction());
        if(exportAssetId == changeAsset){
          action.replace(transferInfo.source, transferInfo.dest);
        } else {
          action.replace(transferInfo.source, dest);
          if (!settings.allowSrcImport && isSrcDest && transferInfo.dest.package != _project.getDestAsset(changeAsset).package ){
            hasUsedOtherPackage = true;
          }
        }
        _createChangePubspecAction(actionsByFile, transferInfo);
      });
    if (!settings.allowSrcImport && isSrcDest && exportAssetId == null && hasUsedOtherPackage){
      _addError('allowSrcImport=false; File "${transferInfo.source}" move to "${transferInfo.dest}" not exported and used other packages');
      if (settings.generateFixCode){
        _addFixCode('export \'package:${transferInfo.source.package}${transferInfo.source.path.substring(3)}\';');
      }
    }
  }

  List<Action> _getActionsByFile(Map<AssetId, List<Action>> actionsByFile, AssetId changeAsset) {
    var list = actionsByFile.putIfAbsent(changeAsset, () {
      _validateAsset(changeAsset);
      return <Action>[];
    });
    return list;
  }

  void _preparationDependencies(Map<AssetId, List<AssetId>> directImportsByAssetId, Map<AssetId, List<AssetId>> exportsByAssetId, Map<AssetId, List<AssetId>> needImportsByAssetId) {
    for (var sPackage in _project.sourcePackages) {
      var package = _project.getOrCreatePackage(sPackage);
      package.files.forEach((fName, node) {
        node.directImports.forEach((f) => directImportsByAssetId.putIfAbsent(f, () => <AssetId>[]).add(node.assetId));
        node.exports.forEach((f) => exportsByAssetId.putIfAbsent(f, () => <AssetId>[]).add(node.assetId));
        node.needImports.forEach((f) => needImportsByAssetId.putIfAbsent(f, () => <AssetId>[]).add(node.assetId));
      });
    }
  }

  T _getAction<T>(List<Action> list, Action defaultValue) {
    Action action = list.firstWhere((action) => action is T, orElse: () => null);
    if (action == null) {
      action = defaultValue;
      list.add(action);
    }
    return action as T;
  }

  void _createChangePubspecAction(Map<AssetId, List<Action>> actionsByFile, node.TransferInfo transferInfo) {
    if (transferInfo.source.package == transferInfo.dest.package){
      return;
    }
    AssetId pubspecId = new AssetId(transferInfo.source.package, 'pubspec.yaml');
    List<Action> list = _getActionsByFile(actionsByFile, pubspecId);
    ChangePubspec action = list.firstWhere((action) => action is ChangePubspec, orElse: () => null);
    if (action == null) {
      action = new ChangePubspec();
      list.add(action);
    }
    action.addDependence(transferInfo.dest.package);
    _project.getOrCreatePackage(transferInfo.dest.package);
  }

  List<String> _fixCode = <String>[];
  void _addFixCode(String fixCode) {
    _fixCode.add(fixCode);
  }

}