/// Dart translations of all Content struct types.
///
/// Mirrors: yjs/src/structs/Content*.js (v14.0.0-22)
/// All content types are in one file for convenience since they share
/// the AbstractContent interface from item.dart.
library;

import 'dart:typed_data';
import '../structs/item.dart';
import '../utils/transaction.dart';
import '../utils/update_encoder.dart';

// ─── ContentAny ──────────────────────────────────────────────────────────────

const int contentAnyRefNumber = 8;

/// Content holding arbitrary JSON-compatible values.
///
/// Mirrors: `ContentAny` in ContentAny.js
class ContentAny implements AbstractContent {
  final List<Object?> arr;

  ContentAny(this.arr);

  @override
  int get length => arr.length;

  @override
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => arr;

  @override
  ContentAny copy() => ContentAny(List.of(arr));

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    final len = arr.length - offset;
    if (encoder is UpdateEncoderV1) {
      encoder.writeLen(len);
      for (var i = offset; i < arr.length; i++) {
        encoder.writeAny(arr[i]);
      }
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeLen(len);
      for (var i = offset; i < arr.length; i++) {
        encoder.writeAny(arr[i]);
      }
    }
  }

  @override
  int getRef() => contentAnyRefNumber;
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
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => [content];

  @override
  ContentBinary copy() => ContentBinary(Uint8List.fromList(content));

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeBuf(content);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeBuf(content);
    }
  }

  @override
  int getRef() => contentBinaryRefNumber;
}

// ─── ContentDeleted ───────────────────────────────────────────────────────────

const int contentDeletedRefNumber = 1;

/// Content representing a deleted range.
///
/// Mirrors: `ContentDeleted` in ContentDeleted.js
class ContentDeleted implements AbstractContent {
  @override
  final int length;

  ContentDeleted(this.length);

  @override
  bool get countable => false;

  @override
  bool get isDeleted => true;

  @override
  List<Object?> getContent() => [];

  @override
  ContentDeleted copy() => ContentDeleted(length);

  @override
  void integrate(Transaction transaction, Item item) {
    transaction.deleteSet.addToIdSet(item.id.client, item.id.clock, length);
    item._deleted = true;
  }

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeLen(length - offset);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeLen(length - offset);
    }
  }

  @override
  int getRef() => contentDeletedRefNumber;
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
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => [embed];

  @override
  ContentEmbed copy() => ContentEmbed(embed);

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeJSON(embed);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeJSON(embed);
    }
  }

  @override
  int getRef() => contentEmbedRefNumber;
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
  bool get countable => false;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => [value];

  @override
  ContentFormat copy() => ContentFormat(key, value);

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeKey(key);
      encoder.writeJSON(value);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeKey(key);
      encoder.writeJSON(value);
    }
  }

  @override
  int getRef() => contentFormatRefNumber;
}

// ─── ContentJSON ──────────────────────────────────────────────────────────────

const int contentJSONRefNumber = 2;

/// Content holding JSON values (legacy format).
///
/// Mirrors: `ContentJSON` in ContentJSON.js
class ContentJSON implements AbstractContent {
  final List<Object?> arr;

  ContentJSON(this.arr);

  @override
  int get length => arr.length;

  @override
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => arr;

  @override
  ContentJSON copy() => ContentJSON(List.of(arr));

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    final len = arr.length - offset;
    if (encoder is UpdateEncoderV1) {
      encoder.writeLen(len);
      for (var i = offset; i < arr.length; i++) {
        encoder.writeJSON(arr[i]);
      }
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeLen(len);
      for (var i = offset; i < arr.length; i++) {
        encoder.writeJSON(arr[i]);
      }
    }
  }

  @override
  int getRef() => contentJSONRefNumber;
}

// ─── ContentString ────────────────────────────────────────────────────────────

const int contentStringRefNumber = 4;

/// Content holding a string.
///
/// Mirrors: `ContentString` in ContentString.js
class ContentString implements AbstractContent {
  final String str;

  ContentString(this.str);

  @override
  int get length => str.length;

  @override
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => str.split('');

  @override
  ContentString copy() => ContentString(str);

  @override
  void integrate(Transaction transaction, Item item) {}

  @override
  void delete(Transaction transaction) {}

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeString(str.substring(offset));
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeString(str.substring(offset));
    }
  }

  @override
  int getRef() => contentStringRefNumber;
}

// ─── ContentType ──────────────────────────────────────────────────────────────

const int contentTypeRefNumber = 7;

/// Content holding a nested YType.
///
/// Mirrors: `ContentType` in ContentType.js
class ContentType implements AbstractContent {
  final dynamic type; // YType

  ContentType(this.type);

  @override
  int get length => 1;

  @override
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => [type];

  @override
  ContentType copy() => ContentType(type);

  @override
  void integrate(Transaction transaction, Item item) {
    // Integrate the nested type into the document
    (type as dynamic)._integrate(transaction.doc, item);
  }

  @override
  void delete(Transaction transaction) {
    // TODO: delete nested type content
  }

  @override
  void gc(dynamic store) {
    // TODO: GC nested type
  }

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeTypeRef((type as dynamic).typeRef as int);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeTypeRef((type as dynamic).typeRef as int);
    }
  }

  @override
  int getRef() => contentTypeRefNumber;
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
  bool get countable => true;

  @override
  bool get isDeleted => false;

  @override
  List<Object?> getContent() => [doc];

  @override
  ContentDoc copy() => ContentDoc(doc);

  @override
  void integrate(Transaction transaction, Item item) {
    // TODO: integrate subdoc
  }

  @override
  void delete(Transaction transaction) {
    // TODO: remove subdoc
  }

  @override
  void gc(dynamic store) {}

  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    // TODO: write doc opts
  }

  @override
  int getRef() => contentDocRefNumber;
}
