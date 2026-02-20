library;

import '../utils/transaction.dart';
import 'abstract_type.dart';

/// A shared Map.
///
/// Mirrors: `YMap` in YMap.js
class YMap<T> extends AbstractType<dynamic> {
  Map<String, Object?> _prelimContent = {};

  YMap() : super() {
    legacyTypeRef = typeRefMap;
  }

  @override
  void integrate(dynamic doc, dynamic item) {
    super.integrate(doc, item);
    _prelimContent.forEach((key, value) {
      set(key, value as T);
    });
    _prelimContent = {};
  }

  /// Sets or updates an attribute.
  void set(String key, T value) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeMapSet(tr, this, key, value);
      });
    } else {
      _prelimContent[key] = value;
    }
  }

  /// Returns the attribute value for [key], or null if not set.
  T? get(String key) {
    return typeMapGet(this, key) as T?;
  }

  /// Removes an attribute.
  void delete(String key) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeMapDelete(tr, this, key);
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Returns whether an attribute exists.
  bool has(String key) {
    return typeMapHas(this, key);
  }

  /// Returns all attribute key-value pairs.
  Map<String, T> toMap() {
    return typeMapGetAll(this).cast<String, T>();
  }

  /// Removes all attributes.
  void clear() {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        // iterate and delete
        for (final key in keys) {
          delete(key);
        }
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Returns an iterable of attribute keys.
  Iterable<String> get keys sync* {
    for (final entry in yMap.entries) {
      if (!entry.value.deleted) yield entry.key;
    }
  }

  /// Returns an iterable of attribute values.
  Iterable<T> get values sync* {
    for (final key in keys) {
      yield get(key)!;
    }
  }

  /// Returns an iterable of key-value pairs.
  Iterable<MapEntry<String, T>> get entries sync* {
     for (final key in keys) {
       yield MapEntry(key, get(key)!);
     }
  }

  /// Number of stored attributes.
  int get size {
    var count = 0;
    for (final item in yMap.values) {
      if (!item.deleted) count++;
    }
    return count;
  }
  
  @override
  Map<String, Object?> toJson() {
    final res = <String, Object?>{};
    toMap().forEach((k, v) {
      res[k] = v is AbstractType ? v.toJson() : v;
    });
    return res;
  }

  @override
  String toString() {
    return toMap().toString();
  }
  
  @override
  YMap<T> clone() {
    final newType = YMap<T>();
    toMap().forEach((k, v) {
      newType.set(k, (v is AbstractType ? v.clone() : v) as T);
    });
    return newType;
  }
}
