/// Dart translation of src/utils/logging.js
///
/// Mirrors: yjs/src/utils/logging.js (v14.0.0-22)
library;

import '../y_type.dart';

/// Convenient helper to log type information.
///
/// Do not use in production systems as the output can be immense!
///
/// Mirrors: `logType` in logging.js
void logType(YType type) {
  final res = <Object?>[];
  var n = type.start;
  while (n != null) {
    res.add(n);
    n = n.right;
  }
  // ignore: avoid_print
  print('Children: $res');
  // ignore: avoid_print
  print('Children content: ${res.where((m) => m != null).toList()}');
}
