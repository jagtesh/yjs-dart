/// Dart translations of all Content struct types.
///
/// Mirrors: yjs/src/structs/Content*.js (v14.0.0-22)
/// All content types are in one file for convenience since they share
/// the AbstractContent interface from item.dart.
library;

import 'dart:convert';
import 'dart:typed_data';
import '../structs/item.dart';
import '../utils/id_set.dart' show addToIdSet;
import '../utils/transaction.dart';
import '../types/abstract_type.dart';
import '../types/utils.dart';
import '../utils/doc.dart';

// ─── ContentAny ──────────────────────────────────────────────────────────────

const int contentAnyRefNumber = 8;

/// Content holding arbitrary JSON-compatible values.
///
/// Mirrors: `ContentAny` in ContentAny.js
class ContentAny implements AbstractContent {
  List<Object?> arr;

  ContentAny(this.arr);

  @override
  int get length => arr.length;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => arr;

  @override
  ContentAny copy() => ContentAny(List.of(arr));

  @override
  ContentAny splice(int offset) {
    final right = ContentAny(arr.sublist(offset));
    arr = arr.sublist(0, offset);
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentAny) return false;
    arr.addAll(right.arr);
    return true;
  }

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    final len = arr.length - offset;
    // ignore: avoid_dynamic_calls
    encoder.writeLen(len);
    for (var i = offset; i < arr.length; i++) {
      // ignore: avoid_dynamic_calls
      encoder.writeAny(arr[i]);
    }
  }

  @override
  int getRef() => contentAnyRefNumber;
}

/// Read ContentAny from [decoder].
ContentAny readContentAny(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final len = decoder.readLen() as int;
  final arr = <Object?>[];
  for (var i = 0; i < len; i++) {
    // ignore: avoid_dynamic_calls
    arr.add(decoder.readAny());
  }
  return ContentAny(arr);
}

// ─── ContentBinary ────────────────────────────────────────────────────────────

const int contentBinaryRefNumber = 3;

/// Content holding a binary buffer.
///
/// Mirrors: `ContentBinary` in ContentBinary.js
class ContentBinary implements AbstractContent {
  final Uint8List content;

  ContentBinary(this.content);

  @override
  int get length => 1;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => [content];

  @override
  ContentBinary copy() => ContentBinary(Uint8List.fromList(content));

  @override
  AbstractContent splice(int offset) => throw StateError('ContentBinary cannot be spliced');

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeBuf(content);
  }

  @override
  int getRef() => contentBinaryRefNumber;
}

/// Read ContentBinary from [decoder].
ContentBinary readContentBinary(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return ContentBinary(decoder.readBuf() as Uint8List);
}

// ─── ContentDeleted ───────────────────────────────────────────────────────────

const int contentDeletedRefNumber = 1;

/// Content representing a deleted range.
///
/// Mirrors: `ContentDeleted` in ContentDeleted.js
class ContentDeleted implements AbstractContent {
  @override
  int length;

  ContentDeleted(this.length);

  @override
  bool isCountable() => false;

  @override
  List<Object?> getContent() => [];

  @override
  ContentDeleted copy() => ContentDeleted(length);

  @override
  ContentDeleted splice(int offset) {
    final right = ContentDeleted(length - offset);
    length = offset;
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentDeleted) return false;
    length += right.length;
    return true;
  }

  @override
  void integrate(Transaction transaction, Item item) {
    addToIdSet(transaction.deleteSet, item.id.client, item.id.clock, length);
    item.markDeleted();
  }

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeLen(length - offset);
  }

  @override
  int getRef() => contentDeletedRefNumber;
}

/// Read ContentDeleted from [decoder].
ContentDeleted readContentDeleted(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return ContentDeleted(decoder.readLen() as int);
}

// ─── ContentEmbed ─────────────────────────────────────────────────────────────

const int contentEmbedRefNumber = 5;

/// Content holding an embedded object (e.g., an image or custom type).
///
/// Mirrors: `ContentEmbed` in ContentEmbed.js
class ContentEmbed implements AbstractContent {
  final Object? embed;

  ContentEmbed(this.embed);

  @override
  int get length => 1;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => [embed];

  @override
  ContentEmbed copy() => ContentEmbed(embed);

  @override
  AbstractContent splice(int offset) => throw StateError('ContentEmbed cannot be spliced');

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeJSON(embed);
  }

  @override
  int getRef() => contentEmbedRefNumber;
}

/// Read ContentEmbed from [decoder].
ContentEmbed readContentEmbed(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return ContentEmbed(decoder.readJSON());
}

// ─── ContentFormat ────────────────────────────────────────────────────────────

const int contentFormatRefNumber = 6;

/// Content holding a text format mark (key/value pair).
///
/// Mirrors: `ContentFormat` in ContentFormat.js
class ContentFormat implements AbstractContent {
  final String key;
  final Object? value;

  ContentFormat(this.key, this.value);

  @override
  int get length => 1;

  @override
  bool isCountable() => false;

  @override
  List<Object?> getContent() => [value];

  @override
  ContentFormat copy() => ContentFormat(key, value);

  @override
  AbstractContent splice(int offset) => throw StateError('ContentFormat cannot be spliced');

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeKey(key);
    // ignore: avoid_dynamic_calls
    encoder.writeJSON(value);
  }

  @override
  int getRef() => contentFormatRefNumber;
}

/// Read ContentFormat from [decoder].
ContentFormat readContentFormat(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final key = decoder.readKey() as String;
  // ignore: avoid_dynamic_calls
  final value = decoder.readJSON();
  return ContentFormat(key, value);
}

// ─── ContentJSON ──────────────────────────────────────────────────────────────

const int contentJSONRefNumber = 2;

/// Content holding JSON values (legacy format).
///
/// Mirrors: `ContentJSON` in ContentJSON.js
class ContentJSON implements AbstractContent {
  List<Object?> arr;

  ContentJSON(this.arr);

  @override
  int get length => arr.length;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => arr;

  @override
  ContentJSON copy() => ContentJSON(List.of(arr));

  @override
  ContentJSON splice(int offset) {
    final right = ContentJSON(arr.sublist(offset));
    arr = arr.sublist(0, offset);
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentJSON) return false;
    arr.addAll(right.arr);
    return true;
  }

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    final len = arr.length - offset;
    // ignore: avoid_dynamic_calls
    encoder.writeLen(len);
    for (var i = offset; i < arr.length; i++) {
      // ignore: avoid_dynamic_calls
      encoder.writeJSON(arr[i]);
    }
  }

  @override
  int getRef() => contentJSONRefNumber;
}

/// Read ContentJSON from [decoder].
ContentJSON readContentJSON(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final len = decoder.readLen() as int;
  final arr = <Object?>[];
  for (var i = 0; i < len; i++) {
    // ignore: avoid_dynamic_calls
    arr.add(jsonDecode(decoder.readString() as String));
  }
  return ContentJSON(arr);
}

// ─── ContentString ────────────────────────────────────────────────────────────

const int contentStringRefNumber = 4;

/// Content holding a string.
///
/// Mirrors: `ContentString` in ContentString.js
class ContentString implements AbstractContent {
  String str;

  ContentString(this.str);

  @override
  int get length => str.length;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => str.split('');

  @override
  ContentString copy() => ContentString(str);

  @override
  ContentString splice(int offset) {
    final right = ContentString(str.substring(offset));
    str = str.substring(0, offset);
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentString) return false;
    str += right.str;
    return true;
  }

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeString(str.substring(offset));
  }

  @override
  int getRef() => contentStringRefNumber;
}

/// Read ContentString from [decoder].
ContentString readContentString(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return ContentString(decoder.readString() as String);
}

// ─── ContentType ──────────────────────────────────────────────────────────────

const int contentTypeRefNumber = 7;

/// Content holding a nested AbstractType.
///
/// Mirrors: `ContentType` in ContentType.js
class ContentType implements AbstractContent {
  AbstractType<dynamic> type;

  ContentType(this.type);

  @override
  int get length => 1;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => [type];

  @override
  ContentType copy() => ContentType(type.clone());

  @override
  AbstractContent splice(int offset) => throw StateError('ContentType cannot be spliced');

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(Transaction transaction, Item item) {
    type.integrate(transaction.doc as Doc, item);
  }

  @override
  void delete(Transaction transaction) {
    var item = type.yStart;
    while (item != null) {
      if (!item.deleted) {
        item.delete(transaction);
      } else if (!transaction.insertSet.hasId(item.id)) {
        // Already deleted, not in this transaction: add to mergeStructs so it
        // can be merged after the transaction (mirrors JS _mergeStructs.push).
        transaction.mergeStructs.add(item);
      }
      item = item.right as Item?;
    }
    type.yMap.forEach((_, mapItem) {
      if (!mapItem.deleted) {
        mapItem.delete(transaction);
      } else if (!transaction.insertSet.hasId(mapItem.id)) {
        transaction.mergeStructs.add(mapItem);
      }
    });
    // Remove this type from the changed set — it was deleted, not modified.
    transaction.changed.remove(type);
  }

  @override
  void gc(dynamic store) {
    // GC the linked list chain starting at yStart.
    var item = type.yStart;
    while (item != null) {
      item.gc(store, true);
      item = item.right as Item?;
    }
    type.yStart = null;
    // GC each yMap entry's full left-chain (newest → oldest).
    type.yMap.forEach((_, mapItem) {
      var m = mapItem as Item?;
      while (m != null) {
        m.gc(store, true);
        m = m.left as Item?;
      }
    });
    type.yMap.clear();
  }

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeTypeRef((type as dynamic).legacyTypeRef as int);
  }

  @override
  int getRef() => contentTypeRefNumber;
}

/// Read ContentType from [decoder].
ContentType readContentType(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final type = readYType(decoder);
  return ContentType(type);
}

// ─── ContentDoc ───────────────────────────────────────────────────────────────

const int contentDocRefNumber = 9;

/// Content holding a sub-document.
///
/// Mirrors: `ContentDoc` in ContentDoc.js
class ContentDoc implements AbstractContent {
  final dynamic doc; // Doc

  ContentDoc(this.doc);

  @override
  int get length => 1;

  @override
  bool isCountable() => true;

  @override
  List<Object?> getContent() => [doc];

  @override
  ContentDoc copy() => ContentDoc(doc);

  @override
  AbstractContent splice(int offset) => throw StateError('ContentDoc cannot be spliced');

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(Transaction transaction, Item item) {
    // ignore: avoid_dynamic_calls
    if (doc.shouldLoad as bool) {
      // ignore: avoid_dynamic_calls
      transaction.subdocsAdded.add(doc);
    }
  }

  @override
  void delete(Transaction transaction) {
    // ignore: avoid_dynamic_calls
    if (transaction.subdocsAdded.contains(doc)) {
      // ignore: avoid_dynamic_calls
      transaction.subdocsAdded.remove(doc);
    } else {
      // ignore: avoid_dynamic_calls
      transaction.subdocsRemoved.add(doc);
    }
  }

  @override
  void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // ignore: avoid_dynamic_calls
    encoder.writeAny(doc.guid);
    // ignore: avoid_dynamic_calls
    encoder.writeAny(doc.meta);
    // ignore: avoid_dynamic_calls
    encoder.writeBool(doc.shouldLoad as bool);
    // ignore: avoid_dynamic_calls
    encoder.writeBool(doc.autoLoad as bool);
  }

  @override
  int getRef() => contentDocRefNumber;
}

/// Read ContentDoc from [decoder].
ContentDoc readContentDoc(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final guid = decoder.readAny() as String;
  // ignore: avoid_dynamic_calls
  final meta = decoder.readAny();
  // ignore: avoid_dynamic_calls
  final shouldLoad = decoder.readBool() as bool;
  // ignore: avoid_dynamic_calls
  final autoLoad = decoder.readBool() as bool;
  return ContentDoc(_DocPlaceholder(guid, meta, shouldLoad, autoLoad));
}

/// Placeholder for a Doc that hasn't been constructed yet.
class _DocPlaceholder {
  final String guid;
  final Object? meta;
  final bool shouldLoad;
  final bool autoLoad;
  _DocPlaceholder(this.guid, this.meta, this.shouldLoad, this.autoLoad);
}

