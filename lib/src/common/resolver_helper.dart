import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';

class ResolverHelper {
  static String getAnnotationStrParameter(Annotation componentAnnotation, String paramName) {
    NamedExpression v = componentAnnotation.arguments.arguments.firstWhere((exp){
      return exp is NamedExpression && exp.name.label.name == paramName;
    }, orElse: ()=>null) as NamedExpression;
    if (v == null || !(v.expression is SimpleStringLiteral)){
      return null;
    }
    return (v.expression as SimpleStringLiteral).value;
  }

  static Annotation getAnnotation(AnnotatedNode element, String annotationName){
    return element.metadata.firstWhere((ann)=> ResolverHelper.isAstAnnotationByName(ann, annotationName),orElse: ()=>null);
  }

  static bool isAnnotationByName(ElementAnnotation annotation, String _className) {
    return annotation.constantValue?.type?.toString() == _className;
  }

  static bool isAstAnnotationByName(Annotation annotation, String _className) {
    return annotation.name.name == _className;
  }
}