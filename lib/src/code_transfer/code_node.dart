import 'package:build/build.dart';

class Project{
  final List<PackageNode> sourcePackages = <PackageNode>[];
  final List<PackageNode> destPackages = <PackageNode>[];
}

class PackageNode{
  final String name;
  final Map<AssetId, FileNode> files = <AssetId, FileNode>{};
  PackageNode(this.name);
}

class FileNode{
  final AssetId assetId;
  final List<AssetId> directImports = <AssetId>[];
  final List<AssetId> needImports = <AssetId>[];
  final List<AssetId> exports = <AssetId>[];

  FileNode(this.assetId);
}