/// Dart translation of src/utils/RelativePosition.js
///
/// Mirrors: yjs/src/utils/RelativePosition.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;
import '../structs/content.dart' show ContentType;
import '../structs/item.dart' show Item, followRedone;
import '../utils/id.dart';
import '../utils/struct_store.dart' show getState, getItem;

// ---------------------------------------------------------------------------
// RelativePosition
// ---------------------------------------------------------------------------

/// A position relative to a specific item in the document.
///
/// Mirrors: `RelativePosition` in RelativePosition.js
class RelativePosition {
  /// The ID of the type item (for non-root types), or null.
  final ID? type;

  /// The root type name (for root-level types), or null.
  final String? tname;

  /// The ID of the item this position is relative to, or null (= end of type).
  final ID? item;

  /// Association: >= 0 = right of item, < 0 = left of item.
  final int assoc;

  const RelativePosition({this.type, this.tname, this.item, this.assoc = 0});
}

/// An absolute position in a type.
///
/// Mirrors: `AbsolutePosition` in RelativePosition.js
class AbsolutePosition {
  /// The type this position is in.
  final dynamic type; // YType

  /// The index within the type.
  final int index;

  /// Association.
  final int assoc;

  const AbsolutePosition(this.type, this.index, {this.assoc = 0});
}

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

/// Create an [AbsolutePosition].
///
/// Mirrors: `createAbsolutePosition` in RelativePosition.js
AbsolutePosition createAbsolutePosition(dynamic type, int index,
        [int assoc = 0]) =>
    AbsolutePosition(type, index, assoc: assoc);

/// Create a [RelativePosition] anchored to [type] and [item].
///
/// Mirrors: `createRelativePosition` in RelativePosition.js
RelativePosition createRelativePosition(dynamic type, ID? item, [int assoc = 0]) {
  ID? typeid;
  String? tname;
  // ignore: avoid_dynamic_calls
  if ((type as dynamic).yItem == null) {
    // Root type — use the share key
    // ignore: avoid_dynamic_calls
    tname = _findRootTypeKey(type);
  } else {
    // ignore: avoid_dynamic_calls
    final typeItem = type.yItem;
    // ignore: avoid_dynamic_calls
    typeid = createID(typeItem.id.client as int, typeItem.id.clock as int);
  }
  return RelativePosition(type: typeid, tname: tname, item: item, assoc: assoc);
}

String? _findRootTypeKey(dynamic type) {
  // ignore: avoid_dynamic_calls
  final doc = type.doc;
  if (doc == null) return null;
  // ignore: avoid_dynamic_calls
  final share = doc.share as Map;
  for (final entry in share.entries) {
    if (entry.value == type) return entry.key as String;
  }
  return null;
}

/// Create a relative position from a type index.
///
/// Mirrors: `createRelativePositionFromTypeIndex` in RelativePosition.js
RelativePosition createRelativePositionFromTypeIndex(
  dynamic type,
  int index, [
  int assoc = 0,
]) {
  // ignore: avoid_dynamic_calls
  dynamic t = (type as dynamic).yStart;
  if (assoc < 0) {
    if (index == 0) {
      return createRelativePosition(type, null, assoc);
    }
    index--;
  }
  while (t != null) {
    // ignore: avoid_dynamic_calls
    final deleted = t.deleted as bool;
    // ignore: avoid_dynamic_calls
    final countable = !deleted && (t.countable as bool);
    // ignore: avoid_dynamic_calls
    final len = countable ? (t.length as int) : 0;
    if (len > index) {
      // ignore: avoid_dynamic_calls
      final tId = t.id as ID;
      return createRelativePosition(
          type, createID(tId.client, tId.clock + index), assoc);
    }
    index -= len;
    // ignore: avoid_dynamic_calls
    final right = t.right;
    if (right == null && assoc < 0) {
      // ignore: avoid_dynamic_calls
      final lastId = t.lastId as ID;
      return createRelativePosition(type, lastId, assoc);
    }
    t = right;
  }
  return createRelativePosition(type, null, assoc);
}

// ---------------------------------------------------------------------------
// JSON serialization
// ---------------------------------------------------------------------------

/// Convert a [RelativePosition] to JSON.
///
/// Mirrors: `relativePositionToJSON` in RelativePosition.js
Map<String, Object?> relativePositionToJSON(RelativePosition pos) {
  final json = <String, Object?>{};
  if (pos.type != null) {
    json['type'] = {'client': pos.type!.client, 'clock': pos.type!.clock};
  }
  if (pos.tname != null) json['tname'] = pos.tname;
  if (pos.item != null) {
    json['item'] = {'client': pos.item!.client, 'clock': pos.item!.clock};
  }
  json['assoc'] = pos.assoc;
  return json;
}

/// Create a [RelativePosition] from JSON.
///
/// Mirrors: `createRelativePositionFromJSON` in RelativePosition.js
RelativePosition createRelativePositionFromJSON(Object? json) {
  if (json is Map) {
    final typeMap = json['type'] as Map?;
    final itemMap = json['item'] as Map?;
    return RelativePosition(
      type: typeMap != null
          ? createID(typeMap['client'] as int, typeMap['clock'] as int)
          : null,
      tname: json['tname'] as String?,
      item: itemMap != null
          ? createID(itemMap['client'] as int, itemMap['clock'] as int)
          : null,
      assoc: (json['assoc'] as int?) ?? 0,
    );
  }
  return const RelativePosition();
}

// ---------------------------------------------------------------------------
// Binary encode / decode
// ---------------------------------------------------------------------------

/// Write a [RelativePosition] to [encoder].
///
/// Mirrors: `writeRelativePosition` in RelativePosition.js
void writeRelativePosition(encoding.Encoder encoder, RelativePosition rpos) {
  final item = rpos.item;
  final tname = rpos.tname;
  final type = rpos.type;
  if (item != null) {
    encoding.writeVarUint(encoder, 0);
    _writeID(encoder, item);
  } else if (tname != null) {
    encoding.writeUint8(encoder, 1);
    encoding.writeVarString(encoder, tname);
  } else if (type != null) {
    encoding.writeUint8(encoder, 2);
    _writeID(encoder, type);
  } else {
    throw StateError('RelativePosition has no type, tname, or item');
  }
  encoding.writeVarInt(encoder, rpos.assoc);
}

/// Encode a [RelativePosition] to binary.
///
/// Mirrors: `encodeRelativePosition` in RelativePosition.js
Uint8List encodeRelativePosition(RelativePosition rpos) {
  final encoder = encoding.createEncoder();
  writeRelativePosition(encoder, rpos);
  return encoding.toUint8Array(encoder);
}

/// Read a [RelativePosition] from [decoder].
///
/// Mirrors: `readRelativePosition` in RelativePosition.js
RelativePosition readRelativePosition(decoding.Decoder decoder) {
  ID? type;
  String? tname;
  ID? itemID;
  final tag = decoding.readVarUint(decoder);
  switch (tag) {
    case 0:
      itemID = _readID(decoder);
      break;
    case 1:
      tname = decoding.readVarString(decoder);
      break;
    case 2:
      type = _readID(decoder);
      break;
  }
  final assoc = decoding.hasContent(decoder) ? decoding.readVarInt(decoder) : 0;
  return RelativePosition(type: type, tname: tname, item: itemID, assoc: assoc);
}

/// Decode a [RelativePosition] from binary.
///
/// Mirrors: `decodeRelativePosition` in RelativePosition.js
RelativePosition decodeRelativePosition(Uint8List bytes) =>
    readRelativePosition(decoding.createDecoder(bytes));

// ---------------------------------------------------------------------------
// createAbsolutePositionFromRelativePosition
// ---------------------------------------------------------------------------

/// Transform a relative position to an absolute position.
///
/// Mirrors: `createAbsolutePositionFromRelativePosition` in RelativePosition.js
AbsolutePosition? createAbsolutePositionFromRelativePosition(
  RelativePosition rpos,
  dynamic doc, [
  bool followUndoneDeletions = true,
]) {
  // ignore: avoid_dynamic_calls
  final store = (doc as dynamic).store;
  final rightID = rpos.item;
  final typeID = rpos.type;
  final tname = rpos.tname;
  final assoc = rpos.assoc;
  dynamic type;
  var index = 0;

  if (rightID != null) {
    if (getState(store, rightID.client) <= rightID.clock) {
      return null;
    }
    final res = followUndoneDeletions
        ? followRedone(store, rightID)
        : _getItemWithOffset(store, rightID);
    final right = res.item;
    type = right.parent;
    // ignore: avoid_dynamic_calls
    final typeItem = (type as dynamic).yItem;
    if (typeItem == null || !(typeItem.deleted as bool)) {
      // ignore: avoid_dynamic_calls
      final contentLen = right.countable && !right.deleted ? right.length : 0;
      index = contentLen == 0 ? 0 : (res.diff + (assoc >= 0 ? 0 : 1));
      dynamic n = right.left;
      while (n != null) {
        // ignore: avoid_dynamic_calls
        if (!(n.deleted as bool) && (n.countable as bool)) {
          // ignore: avoid_dynamic_calls
          index += n.length as int;
        }
        // ignore: avoid_dynamic_calls
        n = n.left;
      }
    }
  } else {
    if (tname != null) {
      // ignore: avoid_dynamic_calls
      type = (doc as dynamic).get(tname);
    } else if (typeID != null) {
      if (getState(store, typeID.client) <= typeID.clock) {
        return null;
      }
      final result = followUndoneDeletions
          ? followRedone(store, typeID)
          : _getItemWithOffset(store, typeID);
      final item = result.item;
      if (item.content is ContentType) {
        type = (item.content as ContentType).type;
      } else {
        return null;
      }
    } else {
      throw StateError('RelativePosition has no type, tname, or item');
    }
    // ignore: avoid_dynamic_calls
    index = assoc >= 0 ? ((type as dynamic).yLength as int) : 0;
  }
  return createAbsolutePosition(type, index, assoc);
}

/// Compare two relative positions for equality.
///
/// Mirrors: `compareRelativePositions` in RelativePosition.js
bool compareRelativePositions(RelativePosition? a, RelativePosition? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.tname == b.tname &&
      compareIDs(a.item, b.item) &&
      compareIDs(a.type, b.type) &&
      a.assoc == b.assoc;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

({Item item, int diff}) _getItemWithOffset(dynamic store, ID id) {
  final item = getItem(store, id) as Item;
  final diff = id.clock - item.id.clock;
  return (item: item, diff: diff);
}

void _writeID(encoding.Encoder encoder, ID id) {
  encoding.writeVarUint(encoder, id.client);
  encoding.writeVarUint(encoder, id.clock);
}

ID _readID(decoding.Decoder decoder) {
  final client = decoding.readVarUint(decoder);
  final clock = decoding.readVarUint(decoder);
  return createID(client, clock);
}
