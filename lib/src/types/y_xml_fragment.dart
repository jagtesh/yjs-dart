library;

import '../utils/transaction.dart';
import 'abstract_type.dart';
 // for typeListSlice

/// A shared XML Fragment.
///
/// Mirrors: `YXmlFragment` in yjs/src/xml/xml-fragment.js
class YXmlFragment extends AbstractType<dynamic> {
  YXmlFragment() : super();

  /// Sets or updates an attribute.
  void setAttribute(String key, String value) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeMapSet(tr, this, key, value);
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Returns the attribute value for [key], or null if not set.
  String? getAttribute(String key) {
    return typeMapGet(this, key) as String?;
  }

  /// Inserts content at [index].
  void insert(int index, List<Object?> content) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListInsertGenerics(tr, this, index, content);
      });
    } else {
      warnPrematureAccess();
    }
  }
  
  /// Returns the list content as a List.
  List<Object?> toArray() {
    return typeListSlice(this, 0, length);
  }
  
  @override
  YXmlFragment clone() {
    final newType = YXmlFragment();
    // Clone children
    newType.insert(0, toArray().map((c) => c is AbstractType ? c.clone() : c).toList());
    // Clone attributes
    // Accessing internal map requires helper? 
    // we can use typeMapGetAll
    final attrs = typeMapGetAll(this);
    attrs.forEach((k, v) {
      newType.setAttribute(k, v is AbstractType ? v.clone() as String : v as String);
    });
    return newType;
  }

  @override
  Map<String, Object?> toJson() {
    return {}; // Placeholder
  }

  @override
  String toString() {
    return ''; // Placeholder
  }
}
