/// Dart translation of src/utils/Snapshot.js
///
/// Mirrors: yjs/src/utils/Snapshot.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;
import '../structs/item.dart' show Item;
import '../utils/id.dart' show createID;
import '../utils/id_set.dart'
    hide createDeleteSetFromStructStore, findIndexSS, iterateStructsByIdSet;
import '../utils/struct_store.dart'
    show
        StructStore,
        createDeleteSetFromStructStore,
        getStateVector,
        getState,
        getItemCleanStart,
        findIndexSS;
import '../utils/struct_set.dart' show iterateStructsByIdSet;
import '../utils/update_decoder.dart'
    show UpdateDecoderV1, UpdateDecoderV2, IdSetDecoderV1, IdSetDecoderV2;
import '../utils/update_encoder.dart'
    show UpdateEncoderV2, IdSetEncoderV1, IdSetEncoderV2;
import '../utils/doc.dart' show Doc;
import '../utils/updates.dart' show applyUpdateV2, LazyStructReader;

// ---------------------------------------------------------------------------
// Snapshot
// ---------------------------------------------------------------------------

/// A snapshot captures the state of a document at a point in time.
///
/// Mirrors: `Snapshot` in Snapshot.js
class Snapshot {
  /// The delete set at the time of the snapshot.
  final IdSet ds;

  /// The state vector at the time of the snapshot.
  final Map<int, int> sv;

  const Snapshot(this.ds, this.sv);

  @override
  bool operator ==(Object other) {
    if (other is! Snapshot) return false;
    if (sv.length != other.sv.length) return false;
    for (final entry in sv.entries) {
      if (other.sv[entry.key] != entry.value) return false;
    }
    return equalIdSets(ds, other.ds);
  }

  @override
  int get hashCode => Object.hash(ds, sv);
}

/// Create a snapshot from [ds] and [sv].
///
/// Mirrors: `createSnapshot` in Snapshot.js
Snapshot createSnapshot(IdSet ds, Map<int, int> sv) => Snapshot(ds, sv);

/// An empty snapshot (no deletions, no state).
final Snapshot emptySnapshot = Snapshot(createIdSet(), {});

/// Create a snapshot from a document.
///
/// Mirrors: `snapshot` in Snapshot.js
Snapshot snapshot(dynamic doc) {
  // ignore: avoid_dynamic_calls
  final store = doc.store as StructStore;
  return createSnapshot(
    createDeleteSetFromStructStore(store),
    getStateVector(store),
  );
}

/// Check if two snapshots are equal.
///
/// Mirrors: `equalSnapshots` in Snapshot.js
bool equalSnapshots(Snapshot a, Snapshot b) => a == b;

/// Check if [item] is visible under [snap].
///
/// If [snap] is null, visibility is determined by item.deleted.
///
/// Mirrors: `isVisible` in Snapshot.js
bool isVisible(Item item, Snapshot? snap) {
  if (snap == null) return !item.deleted;
  final clientClock = snap.sv[item.id.client] ?? 0;
  return clientClock > item.id.clock && !snap.ds.hasId(item.id);
}

/// Split structs at snapshot boundaries so they can be written correctly.
///
/// Mirrors: `splitSnapshotAffectedStructs` in Snapshot.js
void splitSnapshotAffectedStructs(dynamic transaction, Snapshot snap) {
  // ignore: avoid_dynamic_calls
  final meta = transaction.meta as Map;
  final splitFnKey = splitSnapshotAffectedStructs;
  final alreadySplit = meta.putIfAbsent(splitFnKey, () => <Snapshot>{}) as Set;
  if (alreadySplit.contains(snap)) return;
  // ignore: avoid_dynamic_calls
  final store = (transaction.doc as dynamic).store as StructStore;
  snap.sv.forEach((client, clock) {
    if (clock < getState(store, client)) {
      getItemCleanStart(transaction, createID(client, clock));
    }
  });
  iterateStructsByIdSet(transaction, snap.ds, (_) {});
  alreadySplit.add(snap);
}

// ---------------------------------------------------------------------------
// Encode / Decode
// ---------------------------------------------------------------------------

/// Encode a snapshot to binary (V2 format).
///
/// Mirrors: `encodeSnapshotV2` in Snapshot.js
Uint8List encodeSnapshotV2(Snapshot snap, [dynamic encoder]) {
  encoder ??= IdSetEncoderV2();
  writeIdSet(encoder, snap.ds);
  writeStateVector(encoder, snap.sv);
  // ignore: avoid_dynamic_calls
  return (encoder as dynamic).toUint8Array() as Uint8List;
}

/// Encode a snapshot to binary (V1 format).
///
/// Mirrors: `encodeSnapshot` in Snapshot.js
Uint8List encodeSnapshot(Snapshot snap) =>
    encodeSnapshotV2(snap, IdSetEncoderV1());

/// Decode a snapshot from binary (V2 format).
///
/// Mirrors: `decodeSnapshotV2` in Snapshot.js
Snapshot decodeSnapshotV2(Uint8List buf, [dynamic decoder]) {
  decoder ??= IdSetDecoderV2(decoding.createDecoder(buf));
  return Snapshot(readIdSet(decoder), readStateVector(decoder));
}

/// Decode a snapshot from binary (V1 format).
///
/// Mirrors: `decodeSnapshot` in Snapshot.js
Snapshot decodeSnapshot(Uint8List buf) =>
    decodeSnapshotV2(buf, IdSetDecoderV1(decoding.createDecoder(buf)));

// ---------------------------------------------------------------------------
// createDocFromSnapshot
// ---------------------------------------------------------------------------

/// Restore a document to the state captured in [snap].
///
/// Mirrors: `createDocFromSnapshot` in Snapshot.js
dynamic createDocFromSnapshot(dynamic originDoc, Snapshot snap,
    [dynamic newDoc]) {
  // ignore: avoid_dynamic_calls
  if (originDoc.gc as bool) {
    throw StateError(
        'Garbage-collection must be disabled in originDoc!');
  }
  // ignore: avoid_dynamic_calls
  newDoc ??= Doc();

  final sv = snap.sv;
  final ds = snap.ds;
  final encoder = UpdateEncoderV2();

  // ignore: avoid_dynamic_calls
  originDoc.transact((transaction) {
    var size = 0;
    sv.forEach((client, clock) {
      if (clock > 0) size++;
    });
    encoding.writeVarUint(encoder.restEncoder, size);
    // ignore: avoid_dynamic_calls
    final store = (transaction.doc as dynamic).store as StructStore;
    for (final entry in sv.entries) {
      final client = entry.key;
      final clock = entry.value;
      if (clock == 0) continue;
      if (clock < getState(store, client)) {
        getItemCleanStart(transaction, createID(client, clock));
      }
      final structs = store.clients[client] ?? [];
      final lastStructIndex = findIndexSS(structs, clock - 1);
      encoding.writeVarUint(encoder.restEncoder, lastStructIndex + 1);
      encoder.writeClient(client);
      encoding.writeVarUint(encoder.restEncoder, 0);
      for (var i = 0; i <= lastStructIndex; i++) {
        // ignore: avoid_dynamic_calls
        (structs[i] as dynamic).write(encoder, 0, 0);
      }
    }
    writeIdSet(encoder, ds);
  });

  applyUpdateV2(newDoc, encoder.toUint8Array(), 'snapshot');
  return newDoc;
}

// ---------------------------------------------------------------------------
// snapshotContainsUpdate
// ---------------------------------------------------------------------------

/// Check if [snap] contains all structs in [update] (V2 format).
///
/// Mirrors: `snapshotContainsUpdateV2` in Snapshot.js
bool snapshotContainsUpdateV2(Snapshot snap, Uint8List update,
    [Type? yDecoder]) {
  final decoder = yDecoder == UpdateDecoderV1
      ? UpdateDecoderV1(decoding.createDecoder(update))
      : UpdateDecoderV2(decoding.createDecoder(update));
  final lazyDecoder = LazyStructReader(decoder, false);
  for (var curr = lazyDecoder.curr;
      curr != null;
      curr = lazyDecoder.next()) {
    final clientClock = snap.sv[curr.id.client] ?? 0;
    if (clientClock < curr.id.clock + curr.length) {
      return false;
    }
  }
  final mergedDs = mergeIdSets([snap.ds, readIdSet(decoder)]);
  return equalIdSets(snap.ds, mergedDs);
}

/// Check if [snap] contains all structs in [update] (V1 format).
///
/// Mirrors: `snapshotContainsUpdate` in Snapshot.js
bool snapshotContainsUpdate(Snapshot snap, Uint8List update) =>
    snapshotContainsUpdateV2(snap, update, UpdateDecoderV1);

// ---------------------------------------------------------------------------
// Helpers re-exported from id_set / struct_store for convenience
// ---------------------------------------------------------------------------

void writeStateVector(dynamic encoder, Map<int, int> sv) {
  encoding.writeVarUint(
      // ignore: avoid_dynamic_calls
      (encoder as dynamic).restEncoder as encoding.Encoder,
      sv.length);
  sv.forEach((client, clock) {
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, client);
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, clock);
  });
}

Map<int, int> readStateVector(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final numClients =
      decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  final sv = <int, int>{};
  for (var i = 0; i < numClients; i++) {
    // ignore: avoid_dynamic_calls
    final client =
        decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final clock =
        decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    sv[client] = clock;
  }
  return sv;
}
