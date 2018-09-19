import 'dart:async';

import 'package:build/build.dart';

abstract class Action{
//  int priority;
  Future execute(AssetId assetId);
}

class ChangeImportAction extends Action{
  final AssetId source;
  final AssetId dest;
  ChangeImportAction(this.source, this.dest);

  @override
  Future execute(AssetId assetId) async{
  }
}

class ChangeExportAction extends Action{
  final AssetId source;
  final AssetId dest;
  ChangeExportAction(this.source, this.dest);

  @override
  Future execute(AssetId assetId) async{
  }
}

class MoveFileAction extends Action{
  final AssetId source;
  final AssetId dest;
  MoveFileAction(this.source, this.dest);

  @override
  Future execute(AssetId assetId) async{
  }
}