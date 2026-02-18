/// Dart translation of src/utils/isParentOf.js
///
/// Mirrors: yjs/src/utils/isParentOf.js (v14.0.0-22)
library;

import '../structs/item.dart';
import '../y_type.dart';

/// Check if [parent] is a parent of [child].
///
/// Mirrors: `isParentOf` in isParentOf.js
bool isParentOf(YType<dynamic> parent, Item? child) {
  var current = child;
  while (current != null) {
    if (current.parent == parent) return true;
    final p = current.parent;
    if (p is YType) {
      current = p._item;
    } else {
      break;
    }
  }
  return false;
}
