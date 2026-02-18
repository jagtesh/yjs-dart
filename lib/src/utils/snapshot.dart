/// Dart translation of src/utils/Snapshot.js
///
/// Mirrors: yjs/src/utils/Snapshot.js (v14.0.0-22)
library;

import '../utils/id_set.dart';
import '../utils/struct_store.dart';

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

/// Create a snapshot from a [StructStore].
///
/// Mirrors: `snapshot` in Snapshot.js
Snapshot snapshot(dynamic store) {
  final s = store as dynamic;
  return createSnapshot(
    createDeleteSetFromStructStore(s as dynamic),
    getStateVector(s as dynamic),
  );
}

/// An empty snapshot (no deletions, no state).
final Snapshot emptySnapshot = Snapshot(createIdSet(), {});

/// Check if two snapshots are equal.
///
/// Mirrors: `equalSnapshots` in Snapshot.js
bool equalSnapshots(Snapshot a, Snapshot b) => a == b;

/// Check if [snapshot] contains the update represented by [updateUint8Array].
///
/// Mirrors: `snapshotContainsUpdate` in Snapshot.js
bool snapshotContainsUpdate(Snapshot snap, List<int> updateUint8Array) {
  // TODO: implement full check
  return false;
}
