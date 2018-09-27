class Settings{
  // Разрешает множественный экспорт одного и тогоже файла в разных местах
  final bool allowMultiExport;
  // Разрешить использовать прямые ссылки, если выключено то будет поиск файлов экспортов
  final bool allowSrcImport;
  // Принудительно заменять все файлы на места их экспорта, в других пакетах, исключая локальный пакет
  final bool forceExportFile;

  Settings({this.allowMultiExport : true, this.allowSrcImport : true, this.forceExportFile: false});

}