import 'package:code_health/code_transfer.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

/// Initialize logger.
void initLog() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    var message = new StringBuffer();
    message.write('${rec.level.name}: ${rec.time}: ${rec.loggerName}: ${rec.message}');
    if (rec.error != null) {
      message.write(' ${rec.error}');
    }
    print(message);
  });
}

main(List<String> arguments) {
  new CodeTransfer(new Settings()).runForPackage(arguments[1]);
}
