import 'package:build/build.dart';

class Project{
  final Map<String, PackageNode> _sourcePackages;
  final Map<String, PackageNode> _newPackages = <String,PackageNode>{};

  PackageNode getOrCreatePackage(String name){
    if (_sourcePackages.containsKey(name)){
      return _sourcePackages[name];
    }
    return _newPackages.putIfAbsent(name, ()=>new PackageNode());
  }

  Project(this._sourcePackages);
}

class PackageNode{
//  final String name;
  final Map<AssetId, FileNode> files = <AssetId, FileNode>{};
//  PackageNode(this.name);
}

class FileNode{
  final AssetId assetId;
  final List<AssetId> directImports = <AssetId>[];
  final List<AssetId> needImports = <AssetId>[];
  final List<AssetId> exports = <AssetId>[];

  FileNode(this.assetId);
}