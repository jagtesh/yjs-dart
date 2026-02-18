/// Dart translation of src/utils/StructSet.js
///
/// Mirrors: yjs/src/utils/StructSet.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/binary.dart' as binary;
import '../lib0/decoding.dart' as decoding;
import '../structs/abstract_struct.dart';
import '../structs/gc.dart';
import '../structs/item.dart' show Item, readItemContent;
import '../structs/skip.dart';
import '../utils/id.dart';
import '../utils/id_set.dart' hide findIndexSS;
import '../utils/struct_store.dart' show findIndexCleanStart, findIndexSS;
import '../utils/update_decoder.dart';

// ---------------------------------------------------------------------------
// StructRange — mirrors JS StructRange class
// ---------------------------------------------------------------------------

/// A range of structs with an iteration cursor [i].
///
/// Mirrors: `StructRange` in StructSet.js
class StructRange {
  int i = 0;
  final List<AbstractStruct> refs;
  StructRange(this.refs);
}

// ---------------------------------------------------------------------------
// StructSet
// ---------------------------------------------------------------------------

/// A set of struct ranges, organized by client.
///
/// Mirrors: `StructSet` in StructSet.js
class StructSet {
  final Map<int, StructRange> clients = {};
}

// ---------------------------------------------------------------------------
// readStructSet
// ---------------------------------------------------------------------------

/// Read a StructSet from [decoder], using [doc] to resolve parent references.
///
/// Mirrors: `readStructSet` in StructSet.js
StructSet readStructSet(dynamic decoder, dynamic doc) {
  final clientRefs = StructSet();
  // ignore: avoid_dynamic_calls
  final numOfStateUpdates = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  for (var i = 0; i < numOfStateUpdates; i++) {
    // ignore: avoid_dynamic_calls
    final numberOfStructs = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    final refs = List<AbstractStruct>.filled(numberOfStructs, GC(createID(0, 0), 0));
    // ignore: avoid_dynamic_calls
    final client = decoder.readClient() as int;
    // ignore: avoid_dynamic_calls
    var clock = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    clientRefs.clients[client] = StructRange(refs);
    for (var j = 0; j < numberOfStructs; j++) {
      // ignore: avoid_dynamic_calls
      final info = decoder.readInfo() as int;
      final bits5 = binary.BITS5 & info;
      if (bits5 == 0) {
        // GC
        // ignore: avoid_dynamic_calls
        final len = decoder.readLen() as int;
        refs[j] = GC(createID(client, clock), len);
        clock += len;
      } else if (bits5 == 10) {
        // Skip
        // ignore: avoid_dynamic_calls
        final len = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
        refs[j] = Skip(createID(client, clock), len);
        clock += len;
      } else {
        // Item with content
        final cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0;
        // ignore: avoid_dynamic_calls
        final origin = (info & binary.BIT8) == binary.BIT8
            ? decoder.readLeftID() as ID
            : null;
        // ignore: avoid_dynamic_calls
        final rightOrigin = (info & binary.BIT7) == binary.BIT7
            ? decoder.readRightID() as ID
            : null;
        Object? parent;
        if (cantCopyParentInfo) {
          // ignore: avoid_dynamic_calls
          final parentInfo = decoder.readParentInfo() as bool;
          if (parentInfo) {
            // ignore: avoid_dynamic_calls
            final key = decoder.readString() as String;
            // ignore: avoid_dynamic_calls
            parent = doc.get(key);
          } else {
            // ignore: avoid_dynamic_calls
            parent = decoder.readLeftID() as ID;
          }
        }
        // ignore: avoid_dynamic_calls
        final parentSub = cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6
            // ignore: avoid_dynamic_calls
            ? decoder.readString() as String
            : null;
        // ignore: avoid_dynamic_calls
        final content = readItemContent(decoder, info);
        final struct = Item(
          id: createID(client, clock),
          left: null,
          origin: origin,
          right: null,
          rightOrigin: rightOrigin,
          parent: parent,
          parentSub: parentSub,
          content: content,
        );
        refs[j] = struct;
        clock += struct.length;
      }
    }
  }
  return clientRefs;
}

// ---------------------------------------------------------------------------
// removeRangesFromStructSet
// ---------------------------------------------------------------------------

/// Remove item-ranges from [ss] that are already known (in [exclude]).
///
/// Mirrors: `removeRangesFromStructSet` in StructSet.js
void removeRangesFromStructSet(StructSet ss, IdSet exclude) {
  exclude.clients.forEach((client, range) {
    final structRange = ss.clients[client];
    if (structRange == null) return;
    final structs = structRange.refs;
    if (structs.isEmpty) return;
    final firstStruct = structs.first;
    final lastStruct = structs.last;
    final idranges = range.getIds();
    for (final idrange in idranges) {
      if (idrange.clock >= lastStruct.id.clock + lastStruct.length) continue;
      if (idrange.clock + idrange.len <= firstStruct.id.clock) continue;
      var startIndex = 0;
      if (idrange.clock > firstStruct.id.clock) {
        startIndex = findIndexCleanStart(null, structs, idrange.clock);
      }
      var endIndex = structs.length;
      if (idrange.clock + idrange.len < lastStruct.id.clock + lastStruct.length) {
        endIndex = findIndexCleanStart(null, structs, idrange.clock + idrange.len);
      }
      if (startIndex < endIndex) {
        structs[startIndex] = Skip(createID(client, idrange.clock), idrange.len);
        final d = endIndex - startIndex;
        if (d > 1) {
          structs.removeRange(startIndex + 1, startIndex + d);
        }
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Legacy helpers (kept for backward compatibility)
// ---------------------------------------------------------------------------

/// Add a struct to an [IdSet] (insert set tracking).
///
/// Mirrors: `addStructToIdSet` in StructSet.js
void addStructToIdSet(IdSet idSet, AbstractStruct struct) {
  idSet.add(struct.id.client, struct.id.clock, struct.length);
}

/// Create an insert set from a struct store.
///
/// Mirrors: `createInsertSetFromStructStore` in StructSet.js
IdSet createInsertSetFromStructStore(dynamic store, bool includeDeleted) {
  final result = createIdSet();
  // ignore: avoid_dynamic_calls
  (store.clients as Map<int, List<AbstractStruct>>).forEach((client, structs) {
    for (final struct in structs) {
      if (!struct.deleted || includeDeleted) {
        result.add(client, struct.id.clock, struct.length);
      }
    }
  });
  return result;
}

/// Iterate over structs that fall within an [IdSet].
///
/// Mirrors: `iterateStructsByIdSet` in StructSet.js
void iterateStructsByIdSet(
  dynamic transaction,
  IdSet idSet,
  void Function(AbstractStruct struct) f,
) {
  // ignore: avoid_dynamic_calls
  final store = transaction.doc.store;
  idSet.clients.forEach((client, range) {
    // ignore: avoid_dynamic_calls
    final structs = (store.clients as Map<int, List<AbstractStruct>>)[client];
    if (structs == null) return;
    for (final idrange in range.getIds()) {
      final startIndex = findIndexSS(structs, idrange.clock);
      final endClock = idrange.clock + idrange.len;
      for (var i = startIndex; i < structs.length; i++) {
        final s = structs[i];
        if (s.id.clock >= endClock) break;
        f(s);
      }
    }
  });
}
