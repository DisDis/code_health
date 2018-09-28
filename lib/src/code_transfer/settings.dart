class Settings {
  // Разрешает множественный экспорт одного и тогоже файла в разных местах
  final bool allowMultiExport;

  // Разрешить использовать прямые ссылки, если выключено то будет поиск файлов экспортов
  final bool allowSrcImport;

  // Принудительно заменять все файлы на места их экспорта, в других пакетах, исключая локальный пакет
  final bool forceExportFile;

  final List<String> excludePackages = [
    '\$sdk', 'front_end', 'barback', 'analyzer', 'front_end', 'kernel', 'yaml', 'test', 'xml',
    'vm_service_client', 'stream_transform', 'stack_trace', 'quiver', 'protobuf', 'matcher', 'angular', 'crypto', 'angular_compiler', 'archive', 'grinder', 'dart_style'
  ];

  final bool onlySimulation;
  final bool generateFixCode;

  Settings({this.allowMultiExport: true, this.allowSrcImport: true, this.forceExportFile: false, this.onlySimulation: false, this.generateFixCode: true});
}