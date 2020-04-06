import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/error/imports_verifier.dart';

/**
 * A visitor that visits ASTs and fills [UsedImportedElements].
 */
class UsedImportedElementsVisitor extends RecursiveAstVisitor {
  final LibraryElement library;
  final UsedImportedElements usedElements = new UsedImportedElements();

  UsedImportedElementsVisitor(this.library);

  @override
  void visitExportDirective(ExportDirective node) {
    _visitDirective(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    //if (node!= null && node.element != null && node.element.library == library) {
    node.implementsClause?.accept(this);
    node.withClause?.accept(this);
    node.extendsClause?.accept(this);
    //}
    super.visitClassDeclaration(node);
  }

  @override
  void visitImplementsClause(ImplementsClause node) {
    if (node != null && node.interfaces!= null) {
      node.interfaces.accept(this);
      node.interfaces.forEach((interface) {
        interface.visitChildren(this);
        if (interface != null && interface.name != null && interface.name.staticElement != null) {
          usedElements.elements.add(interface.type.element);
        } else if (interface != null && interface.type != null && interface.type.element!=null) {
          usedElements.elements.add(interface.type.element);
        }
      });
    }
  }


  @override
  void visitImportDirective(ImportDirective node) {
    _visitDirective(node);
  }

  @override
  void visitLibraryDirective(LibraryDirective node) {
    _visitDirective(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _visitIdentifier(node, node.staticElement);
  }

  /**
   * If the given [identifier] is prefixed with a [PrefixElement], fill the
   * corresponding `UsedImportedElements.prefixMap` entry and return `true`.
   */
  bool _recordPrefixMap(SimpleIdentifier identifier, Element element) {
    bool recordIfTargetIsPrefixElement(Expression target) {
      if (target is SimpleIdentifier && target.staticElement is PrefixElement) {
        List<Element> prefixedElements = usedElements.prefixMap
            .putIfAbsent(target.staticElement, () => <Element>[]);
        prefixedElements.add(element);
        return true;
      }
      return false;
    }

    AstNode parent = identifier.parent;
    if (parent is MethodInvocation && parent.methodName == identifier) {
      return recordIfTargetIsPrefixElement(parent.target);
    }
    if (parent is PrefixedIdentifier && parent.identifier == identifier) {
      return recordIfTargetIsPrefixElement(parent.prefix);
    }
    return false;
  }

  /**
   * Visit identifiers used by the given [directive].
   */
  void _visitDirective(Directive directive) {
    directive.documentationComment?.accept(this);
    directive.metadata.accept(this);
  }

  void _visitIdentifier(SimpleIdentifier identifier, Element element) {
    if (element == null) {
      return;
    }
    // If the element is multiply defined then call this method recursively for
    // each of the conflicting elements.
    if (element is MultiplyDefinedElement) {
      List<Element> conflictingElements = element.conflictingElements;
      int length = conflictingElements.length;
      for (int i = 0; i < length; i++) {
        Element elt = conflictingElements[i];
        _visitIdentifier(identifier, elt);
      }
      return;
    }

    // Record `importPrefix.identifier` into 'prefixMap'.
    if (_recordPrefixMap(identifier, element)) {
      return;
    }

    if (element is PrefixElement) {
      usedElements.prefixMap.putIfAbsent(element, () => <Element>[]);
      return;
    } else if (element.enclosingElement is! CompilationUnitElement) {
      // Identifiers that aren't a prefix element and whose enclosing element
      // isn't a CompilationUnit are ignored- this covers the case the
      // identifier is a relative-reference, a reference to an identifier not
      // imported by this library.
      return;
    }
    // Ignore if an unknown library.
    LibraryElement containingLibrary = element.library;
    if (containingLibrary == null) {
      return;
    }
    // Ignore if a local element.
    if (library == containingLibrary) {
      return;
    }
    // Remember the element.
    usedElements.elements.add(element);
  }
}
