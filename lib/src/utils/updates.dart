/// Dart translation of src/utils/encoding.js + src/utils/updates.js
///
/// Mirrors: yjs/src/utils/encoding.js (v14.0.0-22)
///          yjs/src/utils/updates.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;
import '../structs/abstract_struct.dart';
import '../structs/gc.dart';
import '../structs/item.dart';
import '../structs/skip.dart';
import '../utils/id.dart';
import '../utils/id_set.dart'
    show IdSet, writeIdSet, createIdSet, readAndApplyDeleteSet;
import '../utils/struct_set.dart'
    show StructSet, StructRange, readStructSet, removeRangesFromStructSet;
import '../utils/struct_store.dart'
    show
        StructStore,
        getState,
        getStateVector,
        findIndexSS;
import '../utils/transaction.dart' show transact, Transaction;
import '../utils/update_decoder.dart'
    show UpdateDecoderV1, UpdateDecoderV2, IdSetDecoderV1;
import '../utils/update_encoder.dart'
    show
        UpdateEncoderV1,
        UpdateEncoderV2,
        IdSetEncoderV1,
        IdSetEncoderV2;

// ---------------------------------------------------------------------------
// writeStructs (private helper)
// ---------------------------------------------------------------------------

/// Write a subset of [structs] for [client] defined by [idranges].
///
/// Mirrors: `writeStructs` in encoding.js
void _writeStructs(
  dynamic encoder,
  List<AbstractStruct> structs,
  int client,
  List<({int clock, int len})> idranges,
) {
  if (idranges.isEmpty) return;
  var structsToWrite = 0;
  final indexRanges = <({int start, int end, int startClock, int endClock})>[];
  final firstPossibleClock = structs.first.id.clock;
  final lastStruct = structs.last;
  final lastPossibleClock = lastStruct.id.clock + lastStruct.length;
  for (final idrange in idranges) {
    final startClock = idrange.clock > firstPossibleClock
        ? idrange.clock
        : firstPossibleClock;
    final endClock = (idrange.clock + idrange.len) < lastPossibleClock
        ? idrange.clock + idrange.len
        : lastPossibleClock;
    if (startClock >= endClock) continue;
    final start = findIndexSS(structs, startClock);
    final end = findIndexSS(structs, endClock - 1) + 1;
    structsToWrite += end - start;
    indexRanges.add((
      start: start,
      end: end,
      startClock: startClock,
      endClock: endClock,
    ));
  }
  if (indexRanges.isEmpty) return;
  structsToWrite += idranges.length - 1;
  var clock = indexRanges.first.startClock;
  // ignore: avoid_dynamic_calls
  encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, structsToWrite);
  // ignore: avoid_dynamic_calls
  encoder.writeClient(client);
  // ignore: avoid_dynamic_calls
  encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, clock);
  for (final indexRange in indexRanges) {
    final skipLen = indexRange.startClock - clock;
    if (skipLen > 0) {
      Skip(createID(client, clock), skipLen).write(encoder, 0);
      clock += skipLen;
    }
    for (var i = indexRange.start; i < indexRange.end; i++) {
      final struct = structs[i];
      final structEnd = struct.id.clock + struct.length;
      final offsetEnd = structEnd > indexRange.endClock
          ? structEnd - indexRange.endClock
          : 0;
      struct.write(encoder, clock - struct.id.clock);
      clock = structEnd - offsetEnd;
    }
  }
}

// ---------------------------------------------------------------------------
// writeClientsStructs
// ---------------------------------------------------------------------------

/// Write all structs newer than [sm] (state map) to [encoder].
///
/// Mirrors: `writeClientsStructs` in encoding.js
void writeClientsStructs(
    dynamic encoder, StructStore store, Map<int, int> sm) {
  // Filter to clients that have new data
  final filteredSm = <int, int>{};
  sm.forEach((client, clock) {
    if (getState(store, client) > clock) {
      filteredSm[client] = clock;
    }
  });
  getStateVector(store).forEach((client, _) {
    if (!sm.containsKey(client)) {
      filteredSm[client] = 0;
    }
  });
  // ignore: avoid_dynamic_calls
  encoding.writeVarUint(
      encoder.restEncoder as encoding.Encoder, filteredSm.length);
  // Write higher client ids first (improves conflict resolution)
  final sortedEntries = filteredSm.entries.toList()
    ..sort((a, b) => b.key - a.key);
  for (final entry in sortedEntries) {
    final client = entry.key;
    final clock = entry.value;
    final structs = store.clients[client]!;
    final lastStruct = structs.last;
    _writeStructs(encoder, structs, client, [
      (clock: clock, len: lastStruct.id.clock + lastStruct.length - clock)
    ]);
  }
}

// ---------------------------------------------------------------------------
// integrateStructs (private)
// ---------------------------------------------------------------------------

/// Integrate structs from [clientsStructRefs] into the document.
///
/// Returns `null` if all structs were applied, or a record with the
/// remaining update bytes and missing state vector if some structs
/// couldn't be applied yet.
///
/// Mirrors: `integrateStructs` in encoding.js
({Map<int, int> missing, Uint8List update})? _integrateStructs(
  Transaction transaction,
  StructStore store,
  StructSet clientsStructRefs,
) {
  final stack = <AbstractStruct>[];
  var clientsStructRefsIds =
      clientsStructRefs.clients.keys.toList()..sort((a, b) => a - b);
  if (clientsStructRefsIds.isEmpty) return null;

  StructRange? getNextStructTarget() {
    while (clientsStructRefsIds.isNotEmpty) {
      final nextTarget = clientsStructRefs
          .clients[clientsStructRefsIds.last]!;
      if (nextTarget.refs.length == nextTarget.i) {
        clientsStructRefsIds.removeLast();
      } else {
        return nextTarget;
      }
    }
    return null;
  }

  var curStructsTarget = getNextStructTarget();
  if (curStructsTarget == null) return null;

  final restStructs = StructStore();
  final missingSV = <int, int>{};

  void updateMissingSv(int client, int clock) {
    final mclock = missingSV[client];
    if (mclock == null || mclock > clock) {
      missingSV[client] = clock;
    }
  }

  AbstractStruct stackHead = curStructsTarget.refs[curStructsTarget.i++];
  final state = <int, int>{};

  void addStackToRestSS() {
    for (final item in stack) {
      final client = item.id.client;
      final inapplicableItems = clientsStructRefs.clients[client];
      if (inapplicableItems != null) {
        inapplicableItems.i--;
        restStructs.clients[client] =
            inapplicableItems.refs.sublist(inapplicableItems.i);
        clientsStructRefs.clients.remove(client);
        inapplicableItems.i = 0;
        inapplicableItems.refs.clear();
      } else {
        restStructs.clients[client] = [item];
      }
      clientsStructRefsIds =
          clientsStructRefsIds.where((c) => c != client).toList();
    }
    stack.clear();
  }

  while (true) {
    if (stackHead is! Skip) {
      final localClock = state.putIfAbsent(
          stackHead.id.client, () => getState(store, stackHead.id.client));
      final offset = localClock - stackHead.id.clock;
      // ignore: avoid_dynamic_calls
      final missing = (stackHead as dynamic).getMissing(transaction, store);
      if (missing != null) {
        stack.add(stackHead);
        final structRefs = clientsStructRefs.clients[missing as int] ??
            StructRange([]);
        if (structRefs.refs.length == structRefs.i ||
            missing == stackHead.id.client ||
            stack.any((s) => s.id.client == missing)) {
          updateMissingSv(missing, getState(store, missing));
          addStackToRestSS();
        } else {
          stackHead = structRefs.refs[structRefs.i++];
          continue;
        }
      } else {
        if (offset < 0) {
          final skip = Skip(
              createID(stackHead.id.client, localClock), -offset);
          skip.integrate(transaction, 0);
        }
        stackHead.integrate(transaction, 0);
        final newClock = stackHead.id.clock + stackHead.length;
        state[stackHead.id.client] =
            newClock > localClock ? newClock : localClock;
      }
    }
    // Advance to next struct
    if (stack.isNotEmpty) {
      stackHead = stack.removeLast();
    } else if (curStructsTarget != null &&
        curStructsTarget.i < curStructsTarget.refs.length) {
      stackHead = curStructsTarget.refs[curStructsTarget.i++];
    } else {
      curStructsTarget = getNextStructTarget();
      if (curStructsTarget == null) break;
      stackHead = curStructsTarget.refs[curStructsTarget.i++];
    }
  }

  if (restStructs.clients.isNotEmpty) {
    final encoder = UpdateEncoderV2();
    writeClientsStructs(encoder, restStructs, {});
    encoding.writeVarUint(encoder.restEncoder, 0); // empty delete set
    return (missing: missingSV, update: encoder.toUint8Array());
  }
  return null;
}

// ---------------------------------------------------------------------------
// readUpdateV2 / readUpdate
// ---------------------------------------------------------------------------

/// Read and apply a document update (V2 format).
///
/// Mirrors: `readUpdateV2` in encoding.js
void readUpdateV2(
  decoding.Decoder decoder,
  dynamic ydoc,
  Object? transactionOrigin, [
  dynamic structDecoder,
]) {
  structDecoder ??= UpdateDecoderV2(decoder);
  transact(
    ydoc,
    (transaction) {
      transaction.local = false;
      var retry = false;
      // ignore: avoid_dynamic_calls
      final store = transaction.doc.store as StructStore;
      final ss = readStructSet(structDecoder, transaction.doc);
      final knownState = createIdSet();
      ss.clients.forEach((client, structRange) {
        final storeStructs = store.clients[client];
        if (storeStructs != null) {
          final last = storeStructs.last;
          knownState.add(client, 0, last.id.clock + last.length);
          // Remove skip ranges from known state
          store.skips.clients[client]?.getIds().forEach((idrange) {
            knownState.delete(client, idrange.clock, idrange.len);
          });
        }
      });
      removeRangesFromStructSet(ss, knownState);
      final restStructs = _integrateStructs(transaction, store, ss);
      final pending = store.pendingStructs;
      if (pending != null) {
        for (final entry in pending.missing.entries) {
          if (ss.clients.containsKey(entry.key) ||
              entry.value < getState(store, entry.key)) {
            retry = true;
            break;
          }
        }
        if (restStructs != null) {
          for (final entry in restStructs.missing.entries) {
            final mclock = pending.missing[entry.key];
            if (mclock == null || mclock > entry.value) {
              pending.missing[entry.key] = entry.value;
            }
          }
          // Merge pending update with rest
          store.pendingStructs = (
            missing: pending.missing,
            update: mergeUpdatesV2([pending.update, restStructs.update]),
          );
        }
      } else {
        if (restStructs != null) {
          store.pendingStructs = (
            missing: restStructs.missing,
            update: restStructs.update,
          );
        }
      }
      final dsRest = readAndApplyDeleteSet(structDecoder, transaction, store);
      if (store.pendingDs != null) {
        final pendingDSUpdate =
            UpdateDecoderV2(decoding.createDecoder(store.pendingDs!));
        decoding.readVarUint(pendingDSUpdate.restDecoder); // read 0 structs
        final dsRest2 =
            readAndApplyDeleteSet(pendingDSUpdate, transaction, store);
        if (dsRest != null && dsRest2 != null) {
          store.pendingDs = mergeUpdatesV2([dsRest, dsRest2]);
        } else {
          store.pendingDs = dsRest ?? dsRest2;
        }
      } else {
        store.pendingDs = dsRest;
      }
      if (retry) {
        final update = store.pendingStructs!.update;
        store.pendingStructs = null;
        applyUpdateV2(transaction.doc, update);
      }
    },
    transactionOrigin,
    false,
  );
}

/// Read and apply a document update (V1 format).
///
/// Mirrors: `readUpdate` in encoding.js
void readUpdate(
    decoding.Decoder decoder, dynamic ydoc, Object? transactionOrigin) {
  readUpdateV2(decoder, ydoc, transactionOrigin, UpdateDecoderV1(decoder));
}

// ---------------------------------------------------------------------------
// applyUpdate / applyUpdateV2
// ---------------------------------------------------------------------------

/// Apply a binary update to [ydoc] (V2 format).
///
/// Mirrors: `applyUpdateV2` in encoding.js
void applyUpdateV2(
  dynamic ydoc,
  Uint8List update, [
  Object? transactionOrigin,
  dynamic Function(decoding.Decoder)? decoderFactory,
]) {
  final decoder = decoding.createDecoder(update);
  final structDecoder = decoderFactory != null
      ? decoderFactory(decoder)
      : UpdateDecoderV2(decoder);
  readUpdateV2(decoder, ydoc, transactionOrigin, structDecoder);
}

/// Apply a binary update to [ydoc] (V1 format).
///
/// Mirrors: `applyUpdate` in encoding.js
void applyUpdate(dynamic ydoc, Uint8List update,
    [Object? transactionOrigin]) {
  final decoder = decoding.createDecoder(update);
  readUpdateV2(
      decoder, ydoc, transactionOrigin, UpdateDecoderV1(decoder));
}

// ---------------------------------------------------------------------------
// writeStateAsUpdate / encodeStateAsUpdate
// ---------------------------------------------------------------------------

/// Write the full document state as an update to [encoder].
///
/// Mirrors: `writeStateAsUpdate` in encoding.js
void writeStateAsUpdate(
    dynamic encoder, dynamic doc, Map<int, int> targetStateVector) {
  // ignore: avoid_dynamic_calls
  writeClientsStructs(encoder, doc.store as StructStore, targetStateVector);
  // ignore: avoid_dynamic_calls
  writeIdSet(encoder, (doc.store as StructStore).ds);
}

/// Encode the full document state as a binary update (V2 format).
///
/// Mirrors: `encodeStateAsUpdateV2` in encoding.js
Uint8List encodeStateAsUpdateV2(
  dynamic doc, [
  Uint8List? encodedTargetStateVector,
  dynamic encoder,
]) {
  encodedTargetStateVector ??= Uint8List.fromList([0]);
  encoder ??= UpdateEncoderV2();
  final targetStateVector = decodeStateVector(encodedTargetStateVector);
  writeStateAsUpdate(encoder, doc, targetStateVector);
  // ignore: avoid_dynamic_calls
  final updates = [encoder.toUint8Array() as Uint8List];
  // ignore: avoid_dynamic_calls
  final store = doc.store as StructStore;
  if (store.pendingDs != null) {
    updates.add(store.pendingDs!);
  }
  if (store.pendingStructs != null) {
    updates.add(diffUpdateV2(
        store.pendingStructs!.update, encodedTargetStateVector));
  }
  if (updates.length > 1) {
    if (encoder is UpdateEncoderV1) {
      return mergeUpdates(updates.map((u, ) => u).toList());
    } else {
      return mergeUpdatesV2(updates);
    }
  }
  return updates[0];
}

/// Encode the full document state as a binary update (V1 format).
///
/// Mirrors: `encodeStateAsUpdate` in encoding.js
Uint8List encodeStateAsUpdate(dynamic doc,
    [Uint8List? encodedTargetStateVector]) {
  return encodeStateAsUpdateV2(
      doc, encodedTargetStateVector, UpdateEncoderV1());
}

// ---------------------------------------------------------------------------
// readStateVector / decodeStateVector / writeStateVector / encodeStateVector
// ---------------------------------------------------------------------------

/// Read a state vector from [decoder].
///
/// Mirrors: `readStateVector` in encoding.js
Map<int, int> readStateVector(dynamic decoder) {
  final ss = <int, int>{};
  // ignore: avoid_dynamic_calls
  final ssLength = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  for (var i = 0; i < ssLength; i++) {
    // ignore: avoid_dynamic_calls
    final client = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final clock = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    ss[client] = clock;
  }
  return ss;
}

/// Decode a binary state vector.
///
/// Mirrors: `decodeStateVector` in encoding.js
Map<int, int> decodeStateVector(Uint8List decodedState) {
  return readStateVector(IdSetDecoderV1(decoding.createDecoder(decodedState)));
}

/// Write a state vector to [encoder].
///
/// Mirrors: `writeStateVector` in encoding.js
void writeStateVector(dynamic encoder, Map<int, int> sv) {
  // ignore: avoid_dynamic_calls
  encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, sv.length);
  final sortedEntries = sv.entries.toList()..sort((a, b) => b.key - a.key);
  for (final entry in sortedEntries) {
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, entry.key);
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, entry.value);
  }
}

/// Write the document's state vector to [encoder].
///
/// Mirrors: `writeDocumentStateVector` in encoding.js
void writeDocumentStateVector(dynamic encoder, dynamic doc) {
  // ignore: avoid_dynamic_calls
  writeStateVector(encoder, getStateVector(doc.store as StructStore));
}

/// Encode the document's state vector as bytes (V2 format).
///
/// Mirrors: `encodeStateVectorV2` in encoding.js
Uint8List encodeStateVectorV2(dynamic doc, [dynamic encoder]) {
  encoder ??= IdSetEncoderV2();
  if (doc is Map<int, int>) {
    writeStateVector(encoder, doc);
  } else {
    writeDocumentStateVector(encoder, doc);
  }
  // ignore: avoid_dynamic_calls
  return encoder.toUint8Array() as Uint8List;
}

/// Encode the document's state vector as bytes (V1 format).
///
/// Mirrors: `encodeStateVector` in encoding.js
Uint8List encodeStateVector(dynamic doc) {
  return encodeStateVectorV2(doc, IdSetEncoderV1());
}

// ---------------------------------------------------------------------------
// mergeUpdates / mergeUpdatesV2 / diffUpdate / diffUpdateV2
// ---------------------------------------------------------------------------

/// Merge multiple V1 updates into one.
///
/// Mirrors: `mergeUpdates` in updates.js
Uint8List mergeUpdates(List<Uint8List> updates) {
  return mergeUpdatesV2(updates, UpdateDecoderV1.new, UpdateEncoderV1.new);
}

/// Merge multiple updates into one (V2 format by default).
///
/// Mirrors: `mergeUpdatesV2` in updates.js
Uint8List mergeUpdatesV2(
  List<Uint8List> updates, [
  dynamic Function(decoding.Decoder)? YDecoder,
  dynamic Function()? YEncoder,
]) {
  YDecoder ??= UpdateDecoderV2.new;
  YEncoder ??= UpdateEncoderV2.new;
  final encoder = YEncoder();
  final lazyWriters = <_LazyStructWriter>[];
  for (final update in updates) {
    final decoder = decoding.createDecoder(update);
    final structDecoder = YDecoder(decoder);
    lazyWriters.add(_LazyStructWriter(structDecoder));
  }
  // Simple merge: collect all structs, sort by client/clock, write
  // This is a simplified implementation — a full merge would handle
  // overlapping ranges with Skip structs.
  final allStructs = <int, List<AbstractStruct>>{};
  for (final writer in lazyWriters) {
    writer.structs.forEach((client, structs) {
      allStructs.putIfAbsent(client, () => []).addAll(structs);
    });
  }
  // Sort each client's structs by clock
  allStructs.forEach((client, structs) {
    structs.sort((a, b) => a.id.clock - b.id.clock);
  });
  // Write merged structs
  final sortedClients = allStructs.keys.toList()..sort((a, b) => b - a);
  encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, sortedClients.length);
  for (final client in sortedClients) {
    final structs = allStructs[client]!;
    encoding.writeVarUint(
        encoder.restEncoder as encoding.Encoder, structs.length);
    encoder.writeClient(client);
    encoding.writeVarUint(
        encoder.restEncoder as encoding.Encoder, structs.first.id.clock);
    for (final struct in structs) {
      struct.write(encoder, 0);
    }
  }
  // Merge delete sets
  final allDs = lazyWriters.map((w) => w.ds).toList();
  final mergedDs = _mergeIdSets(allDs);
  writeIdSet(encoder, mergedDs);
  return encoder.toUint8Array() as Uint8List;
}

/// Compute the diff of [update] relative to [sv] (V2 format).
///
/// Mirrors: `diffUpdateV2` in updates.js
Uint8List diffUpdateV2(
  Uint8List update,
  Uint8List sv, [
  dynamic Function(decoding.Decoder)? YDecoder,
  dynamic Function()? YEncoder,
]) {
  YDecoder ??= UpdateDecoderV2.new;
  YEncoder ??= UpdateEncoderV2.new;
  final state = decodeStateVector(sv);
  final encoder = YEncoder();
  final decoder = decoding.createDecoder(update);
  final structDecoder = YDecoder(decoder);
  final lazyWriter = _LazyStructWriter(structDecoder);
  // Filter structs newer than sv
  final filteredStructs = <int, List<AbstractStruct>>{};
  lazyWriter.structs.forEach((client, structs) {
    final clock = state[client] ?? 0;
    final filtered = structs.where((s) => s.id.clock >= clock).toList();
    if (filtered.isNotEmpty) {
      filteredStructs[client] = filtered;
    }
  });
  final sortedClients = filteredStructs.keys.toList()..sort((a, b) => b - a);
  encoding.writeVarUint(
      encoder.restEncoder as encoding.Encoder, sortedClients.length);
  for (final client in sortedClients) {
    final structs = filteredStructs[client]!;
    encoding.writeVarUint(
        encoder.restEncoder as encoding.Encoder, structs.length);
    encoder.writeClient(client);
    encoding.writeVarUint(
        encoder.restEncoder as encoding.Encoder, structs.first.id.clock);
    for (final struct in structs) {
      struct.write(encoder, 0);
    }
  }
  writeIdSet(encoder, lazyWriter.ds);
  return encoder.toUint8Array() as Uint8List;
}

/// Compute the diff of [update] relative to [sv] (V1 format).
///
/// Mirrors: `diffUpdate` in updates.js
Uint8List diffUpdate(Uint8List update, Uint8List sv) {
  return diffUpdateV2(update, sv, UpdateDecoderV1.new, UpdateEncoderV1.new);
}

/// Convert a V2 update to V1 format.
///
/// Mirrors: `convertUpdateFormatV2ToV1` in updates.js
Uint8List convertUpdateFormatV2ToV1(Uint8List update) {
  return diffUpdateV2(update, Uint8List.fromList([0]),
      UpdateDecoderV2.new, UpdateEncoderV1.new);
}

// ---------------------------------------------------------------------------
// encodeStateVectorFromUpdate
// ---------------------------------------------------------------------------

/// Extract the state vector from a binary update.
///
/// Mirrors: `encodeStateVectorFromUpdate` in updates.js
Uint8List encodeStateVectorFromUpdate(Uint8List update) {
  return encodeStateVectorFromUpdateV2(update, IdSetEncoderV1.new, UpdateDecoderV1.new);
}

/// Extract the state vector from a binary update (V2 format).
///
/// Mirrors: `encodeStateVectorFromUpdateV2` in updates.js
Uint8List encodeStateVectorFromUpdateV2(
  Uint8List update, [
  dynamic Function()? YEncoder,
  dynamic Function(decoding.Decoder)? YDecoder,
]) {
  YEncoder ??= IdSetEncoderV2.new;
  YDecoder ??= UpdateDecoderV2.new;
  final encoder = YEncoder();
  final decoder = decoding.createDecoder(update);
  final structDecoder = YDecoder(decoder);
  final lazyWriter = _LazyStructWriter(structDecoder);
  final sv = <int, int>{};
  lazyWriter.structs.forEach((client, structs) {
    if (structs.isNotEmpty) {
      final last = structs.last;
      sv[client] = last.id.clock + last.length;
    }
  });
  writeStateVector(encoder, sv);
  return encoder.toUint8Array() as Uint8List;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// A lazy struct reader that decodes all structs from an update.
class _LazyStructWriter {
  final Map<int, List<AbstractStruct>> structs = {};
  late final IdSet ds;

  _LazyStructWriter(dynamic decoder) {
    // ignore: avoid_dynamic_calls
    final numOfStateUpdates =
        decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    for (var i = 0; i < numOfStateUpdates; i++) {
      // ignore: avoid_dynamic_calls
      final numberOfStructs =
          decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
      // ignore: avoid_dynamic_calls
      final client = decoder.readClient() as int;
      // ignore: avoid_dynamic_calls
      var clock = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
      final clientStructs = <AbstractStruct>[];
      structs[client] = clientStructs;
      for (var j = 0; j < numberOfStructs; j++) {
        // ignore: avoid_dynamic_calls
        final info = decoder.readInfo() as int;
        if (info == 10) {
          // ignore: avoid_dynamic_calls
          final len =
              decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
          clientStructs.add(Skip(createID(client, clock), len));
          clock += len;
        } else if ((0x1f & info) != 0) {
          // ignore: avoid_dynamic_calls
          final content = readItemContent(decoder, info);
          clientStructs.add(Item(
            id: createID(client, clock),
            content: content,
          ));
          clock += content.length;
        } else {
          // GC
          // ignore: avoid_dynamic_calls
          final len = decoder.readLen() as int;
          clientStructs.add(GC(createID(client, clock), len));
          clock += len;
        }
      }
    }
    // ignore: avoid_dynamic_calls
    ds = _readIdSetFromDecoder(decoder);
  }
}

/// Read an IdSet from a decoder.
IdSet _readIdSetFromDecoder(dynamic decoder) {
  final idSet = createIdSet();
  // ignore: avoid_dynamic_calls
  final numClients =
      decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  for (var i = 0; i < numClients; i++) {
    // ignore: avoid_dynamic_calls
    final client =
        decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final numRanges =
        decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    for (var j = 0; j < numRanges; j++) {
      // ignore: avoid_dynamic_calls
      final clock =
          decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
      // ignore: avoid_dynamic_calls
      final len =
          decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
      idSet.add(client, clock, len);
    }
  }
  return idSet;
}

/// Merge multiple IdSets into one.
IdSet _mergeIdSets(List<IdSet> sets) {
  final result = createIdSet();
  for (final set in sets) {
    set.clients.forEach((client, range) {
      for (final idrange in range.getIds()) {
        result.add(client, idrange.clock, idrange.len);
      }
    });
  }
  return result;
}

// ---------------------------------------------------------------------------
// LazyStructReader
// ---------------------------------------------------------------------------

/// A streaming struct reader that reads one struct at a time from a decoder.
///
/// Mirrors: `LazyStructReader` in updates.js
class LazyStructReader {
  final dynamic _decoder;
  final bool _filterSkips;

  /// The current struct (null if exhausted).
  AbstractStruct? curr;

  bool _done = false;

  // State for iterating through the decoder
  int _numOfStateUpdates = 0;
  int _stateUpdateIndex = 0;
  int _numberOfStructs = 0;
  int _structIndex = 0;
  int _client = 0;
  int _clock = 0;

  LazyStructReader(this._decoder, this._filterSkips) {
    // ignore: avoid_dynamic_calls
    _numOfStateUpdates =
        decoding.readVarUint(_decoder.restDecoder as decoding.Decoder);
    _loadNextClient();
    next(); // advance to first struct
  }

  void _loadNextClient() {
    if (_stateUpdateIndex >= _numOfStateUpdates) {
      _done = true;
      return;
    }
    // ignore: avoid_dynamic_calls
    _numberOfStructs =
        decoding.readVarUint(_decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    _client = _decoder.readClient() as int;
    // ignore: avoid_dynamic_calls
    _clock = decoding.readVarUint(_decoder.restDecoder as decoding.Decoder);
    _structIndex = 0;
    _stateUpdateIndex++;
  }

  AbstractStruct? _readNextStruct() {
    while (true) {
      if (_done) return null;
      if (_structIndex >= _numberOfStructs) {
        _loadNextClient();
        continue;
      }
      // ignore: avoid_dynamic_calls
      final info = _decoder.readInfo() as int;
      AbstractStruct struct;
      if (info == 10) {
        // Skip
        // ignore: avoid_dynamic_calls
        final len =
            decoding.readVarUint(_decoder.restDecoder as decoding.Decoder);
        struct = Skip(createID(_client, _clock), len);
        _clock += len;
      } else if ((0x1f & info) != 0) {
        // Item
        // ignore: avoid_dynamic_calls
        final content = readItemContent(_decoder, info);
        struct = Item(id: createID(_client, _clock), content: content);
        _clock += content.length;
      } else {
        // GC
        // ignore: avoid_dynamic_calls
        final len = _decoder.readLen() as int;
        struct = GC(createID(_client, _clock), len);
        _clock += len;
      }
      _structIndex++;
      if (_filterSkips && struct is Skip) continue;
      return struct;
    }
  }

  /// Advance to the next struct and return it.
  AbstractStruct? next() {
    curr = _readNextStruct();
    return curr;
  }
}
