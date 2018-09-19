import 'package:build/build.dart';

class Project{
  final Map<String, PackageNode> _sourcePackages;
  final Map<String, PackageNode> _newPackages = <String,PackageNode>{};
  final List<TransferInfo> _transferAssets = <TransferInfo>[];
  Iterable<TransferInfo> get transferAssets => _transferAssets;
  Iterable<String> get sourcePackages => _sourcePackages.keys;
  Iterable<String> get newPackages => _newPackages.keys;

  PackageNode getOrCreatePackage(String name){
    if (_sourcePackages.containsKey(name)){
      return _sourcePackages[name];
    }
    return _newPackages.putIfAbsent(name, ()=>new PackageNode());
  }

  Project(this._sourcePackages);

  void addTransferInfo(TransferInfo tInfo) {
    _transferAssets.add(tInfo);
  }
}

class PackageNode{
//  final String name;
  final Map<AssetId, FileNode> files = <AssetId, FileNode>{};
//  PackageNode(this.name);
}

class FileNode{
  final AssetId assetId;
  AssetId transferAssetId;
  final List<AssetId> directImports = <AssetId>[];
  final List<AssetId> needImports = <AssetId>[];
  final List<AssetId> exports = <AssetId>[];

  FileNode(this.assetId);
}

class TransferInfo{
  final AssetId source;
  final AssetId dest;

  TransferInfo(this.source, this.dest);
}