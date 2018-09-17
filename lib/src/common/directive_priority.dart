
class DirectivePriority {
  static const IMPORT_SDK = const DirectivePriority('IMPORT_SDK', 0);
  static const IMPORT_PKG = const DirectivePriority('IMPORT_PKG', 1);
  static const IMPORT_OTHER = const DirectivePriority('IMPORT_OTHER', 2);
  static const IMPORT_REL = const DirectivePriority('IMPORT_REL', 3);
  static const EXPORT_SDK = const DirectivePriority('EXPORT_SDK', 4);
  static const EXPORT_PKG = const DirectivePriority('EXPORT_PKG', 5);
  static const EXPORT_OTHER = const DirectivePriority('EXPORT_OTHER', 6);
  static const EXPORT_REL = const DirectivePriority('EXPORT_REL', 7);
  static const PART = const DirectivePriority('PART', 8);

  final String name;
  final int ordinal;

  const DirectivePriority(this.name, this.ordinal);

  @override
  String toString() => name;

  static DirectivePriority getDirectivePriority(String uriContent) {
    if (uriContent.startsWith('dart:')) {
      return DirectivePriority.IMPORT_SDK;
    } else if (uriContent.startsWith('package:')) {
      return DirectivePriority.IMPORT_PKG;
    } else if (uriContent.contains('://')) {
      return DirectivePriority.IMPORT_OTHER;
    }
    return DirectivePriority.IMPORT_REL;
  }
}