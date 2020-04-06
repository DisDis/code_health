import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/error/imports_verifier.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step_impl.dart';
import 'package:build_resolvers/build_resolvers.dart';
import 'package:build_resolvers/src/resolver.dart';
import 'package:build_runner_core/build_runner_core.dart';
import 'package:build_runner_core/src/asset/cache.dart';
import 'package:code_health/import_optimizer.dart';
import 'package:code_health/src/common/directive_info.dart';
import 'package:code_health/src/common/directive_priority.dart';
import 'package:code_health/src/common/resolver_helper.dart';
import 'package:code_health/src/common/visitor/exported_elements_visitor.dart';
import 'package:code_health/src/common/visitor/used_imported_elements_visitor.dart';
import 'package:code_health/src/import_optimizer/work_result.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart' as log show Logger;
import 'package:path/path.dart' as path;

class ImportOptimizer{
  static final log.Logger _log = new log.Logger('ImportOptimizer');
  static final _resolvers = new AnalyzerResolvers();
  static final packageGraph = new PackageGraph.forThisPackage();

  final io = new IOEnvironment(packageGraph, assumeTty:true);
  final _resourceManager = new ResourceManager();
  final WorkResult _workResult;
  CachingAssetReader _reader;
  final ImportOptimizerSettings settings;

  ImportOptimizer(ImportOptimizerSettings settings): this.settings = settings, _workResult = new WorkResult(settings);

  optimizePackage(String package) async {
    _log.info("Optimization package: '$package'");

    var assets = (await io.reader.findAssets(new Glob('lib/**.dart'), package: package).toList()).map((item)=>item.toString())
        .toList();
    optimizeFiles(assets);
  }

  optimizeFiles(Iterable<String> inputs) async {
    var sw = new Stopwatch();
    sw.start();
    var count = inputs.length;
    _log.info('Optimization files: $count');
     _reader = new CachingAssetReader(io.reader);
     var index = 0;
     for (var input in inputs) {
       index++;
       _log.info('$index/$count $input');
       await _parseInput(input);
     }
    _log.info('Optimization completed');
     _showReport();
    sw.stop();
    _log.info('Duraction: ${sw.elapsed.toString()}');
   }

   Future _parseInput(String input) async {
     var inputId = new AssetId.parse(input);
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

       final libUnit = await ResolverHelper.getLibraryUnit(lib);

       libUnit.accept(usedImportedElementsVisitor);
       var usedElements = _getUsedElements(usedImportedElementsVisitor.usedElements);
       var optLibraries = await _getLibrariesForElemets(inputId, usedElements, resolver);
       var output = await _generateImportText(inputId, lib, optLibraries);
       if (output.isNotEmpty) {
         final stat = _workResult.statistics[inputId];
         print('// FileName: "$inputId"  unique old: ${stat.sourceNode} -> new: ${stat.optNode}, agg old: ${stat.sourceAggNode} -> new: ${stat.optAggNode}');
         print(output);
         if (settings.applyImports) {
           final firstImport = libUnit.directives.firstWhere((dir) => dir.keyword.keyword == Keyword.IMPORT);
           final lastImport = libUnit.directives.lastWhere((dir) => dir.keyword.keyword == Keyword.IMPORT);

           _replaceImportsInFile(inputId.path, output, firstImport.firstTokenAfterCommentAndMetadata.charOffset,
               lastImport.endToken.charOffset);
         }
       }
     } catch(e,st){
       _log.fine("Skip '$inputId'", e, st);
     }
   }

   void _replaceImportsInFile(String filename, String newImports, int fromOffset, int toOffset) {
     final fullname = path.join('.', filename);
     final str = new File(fullname).readAsStringSync();
     final res = new StringBuffer();
     res.write(str.substring(0, fromOffset));
     res.writeln(newImports);
     res.write(str.substring(toOffset+1).trimLeft());
     new File(fullname).writeAsStringSync(res.toString());
     _log.info("File '$fullname' patched!");
   }


   _parseLibraryStat(Iterable<LibraryElement> libImports){
     var imports = new Set<LibraryElement>();
     _parseLib(Iterable<LibraryElement> libImports) {
       for (var item in libImports) {
         _workResult.addStatisticLibrary(item);
         if (imports.add(item) && !item.isDartCore && !item.isInSdk) {
           _parseLib(item.importedLibraries);
           _parseLib(item.exportedLibraries);
         }
       }
     }
     _parseLib(libImports);
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
      if (!source.isInSystemLibrary) {
        var assetId = new AssetId.resolve(source.uri.toString());

        if (assetId.package != inputId.package && assetId.path.contains('/src/')){
          if (settings.allowSrcImport){
            optLibrary = library;
          } else {
            optLibrary = await _getOptimumLibraryWhichExportsElement(element, resolver);
          }
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
    if (!settings.allowUnnecessaryDependenciesImports) {
      for (var library in libraries.keys) {
        var elementsImportedFromLibrary = libraries[library];
        for (var anotherLibrary in libraries.keys) {
          if (library != anotherLibrary) {
            if (await elementsImportedFromLibrary.asyncEvery((element) async => await _isLibraryExportsElement(anotherLibrary, element))) {
              unnecessaryDependentLibraries.add(library);
            }
          }
        }
      }
    }
    return libraries.keys.where((lib)=> !unnecessaryDependentLibraries.contains(lib));
  }

  Future<LibraryElement> _getOptimumLibraryWhichExportsElement(Element element, Resolver resolverI) async {
    // var source = element.library.source as AssetBasedSource;
    var elementAssetId = new AssetId.resolve(element.library.source.uri.toString());;
    var result = element.library;
    var resultImportsCount = 99999999;
    var assets = await io.reader.findAssets(new Glob('**.dart'), package: elementAssetId.package).toList();
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
            if (await _isLibraryExportsElement(library, element)) {
              result = library;
              resultImportsCount = count;
            }
          }
        }
        catch (e, s) {
          _log.fine('Error asset: "$assetId" for "${elementAssetId}"', e, s);
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

  Future<String> _generateImportText(AssetId inputId, LibraryElement sourceLibrary, Iterable<LibraryElement> libraries) async {
    var sb = new StringBuffer();
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
        final assetId = new AssetId.resolve(source.uri.toString());
        final importUri = (!source.isInSystemLibrary)
            ? 'package:${assetId.package}${assetId.path.substring(3)}'
            : source.uri.toString();

        if (importUri == 'dart:core') continue;

        final priority = DirectivePriority.getDirectivePriority(importUri);
        var importString = "import '$importUri';";
        if (settings.showImportNodes){
          importString += '// nodes: ${_getNodeCount([library])}';
        }

        final libUnit = await ResolverHelper.getLibraryUnit(library);

        List<ImportDirective> existedImportDirectives = libUnit.directives.where((dir) => dir.keyword.keyword == Keyword.IMPORT);
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
    return sb.toString();
  }

  Future<bool> _isLibraryExportsElement(LibraryElement library, Element elem) async {
    var visitor = new ExportedElementsVisitor(library);

    final libUnit = await ResolverHelper.getLibraryUnit(library);

    libUnit.accept(visitor);
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
    _log.info('--------------------------------');
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
    _log.info('--------------------------------');
  }


  bool _hasDeprectatedAssets(List<LibraryElement> importedLibraries) {
    return importedLibraries.any((library) {
      return library.hasDeprecated;
    });
  }


}

extension on Iterable {
  Future<bool> asyncEvery(Future<bool> test(Element element)) async {
    for (final element in this) {
      if (!(await test(element))) return false;
    }
    return true;
  }
}
