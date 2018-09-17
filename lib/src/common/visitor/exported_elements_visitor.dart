
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';

/**
 * A visitor that visits ASTs and fills elements which exports current library including reexports from another library
 */
class ExportedElementsVisitor extends RecursiveAstVisitor {
  final LibraryElement library;
  final Set<Element> elements = new Set<Element>();
  ExportedElementsVisitor(this.library);
  @override
  void visitExportDirective(ExportDirective node) {
    ExportElement exportElement = node.element;
    if (exportElement != null) {
      LibraryElement library = exportElement.exportedLibrary;
      if (library != null) {
        // case when export statement use show/hide substatement
        if (node.combinators.length > 0) {
          for (Combinator combinator in node.combinators) {
            if (combinator is HideCombinator) {
              // TODO cover this case
            } else {
              var names = (combinator as ShowCombinator).shownNames;
              for (var name in names) {
                elements.add(name.staticElement);
              }
            }
          }
        } else {
          // case when exported all elements from library
          if (library.exportNamespace != null) {
            for (var element in library.exportNamespace.definedNames.values) {
              elements.add(element);
            }
          }
        }
      }
    }
    super.visitExportDirective(node);
  }
}

