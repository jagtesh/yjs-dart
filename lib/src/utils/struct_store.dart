/// Dart translation of src/utils/StructStore.js
///
/// Mirrors: yjs/src/utils/StructStore.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../structs/abstract_struct.dart';
import '../structs/gc.dart';
import '../structs/skip.dart';
import '../utils/id.dart';
import '../utils/id_set.dart';

/// Stores all CRDT structs, organized by client id.
///
/// Mirrors: `StructStore` in StructStore.js
class StructStore {
  /// Map from client id to sorted list of structs.
  final Map<int, List<AbstractStruct>> clients = {};

  /// Pending structs waiting for missing dependencies.
  ({Map<int, int> missing, Uint8List update})? pendingStructs;

  /// Pending delete set update.
  Uint8List? pendingDs;

  /// Skip ranges (gaps in the struct store).
  final IdSet skips = createIdSet();

  /// Computed delete set from all GC structs.
  IdSet get ds => createDeleteSetFromStructStore(this);

  /// Add a struct to the store.
  void addStruct(AbstractStruct struct) {
    addStructToStore(this, struct);
  }
}

/// Add a struct to [store] (typed implementation).
///
/// Mirrors: `addStruct` in StructStore.js
void addStructToStoreImpl(StructStore store, AbstractStruct struct) {
  var structs = store.clients[struct.id.client];
  if (structs == null) {
    structs = [];
    store.clients[struct.id.client] = structs;
  } else {
    final lastStruct = structs.last;
    if (lastStruct.id.clock + lastStruct.length != struct.id.clock) {
      // This replaces an integrated skip
      var index = findIndexSS(structs, struct.id.clock);
      final skip = structs[index];
      final diffStart = struct.id.clock - skip.id.clock;
      final diffEnd = skip.id.clock + skip.length - struct.id.clock - struct.length;
      if (diffStart > 0) {
        structs.insert(
          index++,
          Skip(createID(struct.id.client, skip.id.clock), diffStart),
        );
      }
      if (diffEnd > 0) {
        structs.insert(
          index + 1,
          Skip(createID(struct.id.client, struct.id.clock + struct.length), diffEnd),
        );
      }
      structs[index] = struct;
      store.skips.delete(struct.id.client, struct.id.clock, struct.length);
      return;
    }
  }
  structs.add(struct);
}

/// Add a struct to [store] (dynamic store, for use from item.dart).
void addStructToStore(dynamic store, AbstractStruct struct) {
  addStructToStoreImpl(store as StructStore, struct);
}

/// Return the state vector as a Map<client, clock>.
///
/// Note that clock refers to the next expected clock id.
///
/// Mirrors: `getStateVector` in StructStore.js
Map<int, int> getStateVector(StructStore store) {
  final sm = <int, int>{};
  store.clients.forEach((client, structs) {
    final struct = structs.last;
    sm[client] = struct.id.clock + struct.length;
  });
  store.skips.clients.forEach((client, ranges) {
    final ids = ranges.getIds();
    if (ids.isNotEmpty) {
      sm[client] = ids.first.clock;
    }
  });
  return sm;
}

/// Get the current clock for [client] in [store].
///
/// Mirrors: `getState` in StructStore.js
int getState(dynamic store, int client) {
  final structs = (store as StructStore).clients[client];
  if (structs == null || structs.isEmpty) return 0;
  final lastStruct = structs.last;
  return lastStruct.id.clock + lastStruct.length;
}

/// Perform a binary search on a sorted struct array to find the index
/// of the struct containing [clock].
///
/// Mirrors: `findIndexSS` in StructStore.js
int findIndexSS(List<AbstractStruct> structs, int clock) {
  var left = 0;
  var right = structs.length - 1;
  var mid = structs[right];
  var midclock = mid.id.clock;
  if (midclock == clock) return right;

  // Pivot the search
  var midindex = ((clock / (midclock + mid.length - 1)) * right).floor();
  while (left <= right) {
    mid = structs[midindex];
    midclock = mid.id.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.length) return midindex;
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
    midindex = ((left + right) / 2).floor();
  }
  throw StateError('StructStore: findIndexSS failed - unexpected case');
}

/// Get the struct at [id] from [store].
///
/// Mirrors: `getItem` in StructStore.js
AbstractStruct getItem(dynamic store, ID id) {
  final structs = (store as StructStore).clients[id.client];
  if (structs == null) throw StateError('No structs for client ${id.client}');
  return structs[findIndexSS(structs, id.clock)];
}


/// Create a delete set from all GC structs in [store].
///
/// Mirrors: `createDeleteSetFromStructStore` in IdSet.js
IdSet createDeleteSetFromStructStore(StructStore store) {
  final ds = createIdSet();
  store.clients.forEach((client, structs) {
    for (final struct in structs) {
      if (struct.deleted) {
        addToIdSet(ds, client, struct.id.clock, struct.length);
      }
    }
  });
  return ds;
}

/// Integrity check for the struct store.
///
/// Mirrors: `integrityCheck` in StructStore.js
void integrityCheck(StructStore store) {
  store.clients.forEach((_, structs) {
    for (var i = 1; i < structs.length; i++) {
      final l = structs[i - 1];
      final r = structs[i];
      if (l.id.clock + l.length != r.id.clock) {
        throw StateError('StructStore failed integrity check');
      }
    }
  });
}

/// Get the item at [id], splitting if necessary so that the returned item
/// starts exactly at [id.clock].
///
/// Mirrors: `getItemCleanStart` in StructStore.js
dynamic getItemCleanStart(dynamic transaction, ID id) {
  // ignore: avoid_dynamic_calls
  final store = transaction.doc.store as StructStore;
  final structs = store.clients[id.client]!;
  final index = findIndexSS(structs, id.clock);
  final struct = structs[index];
  if (struct.id.clock < id.clock && struct is _SplittableStruct) {
    // Need to split at id.clock
    final diff = id.clock - struct.id.clock;
    // ignore: avoid_dynamic_calls
    final right = (transaction as dynamic)._splitStruct(struct, diff);
    return right;
  }
  return struct;
}

/// Get the item at [id], splitting if necessary so that the returned item
/// ends exactly at [id.clock] (inclusive).
///
/// Mirrors: `getItemCleanEnd` in StructStore.js
dynamic getItemCleanEnd(dynamic transaction, dynamic store, ID id) {
  final structs = (store as StructStore).clients[id.client]!;
  final index = findIndexSS(structs, id.clock);
  final struct = structs[index];
  if (id.clock != struct.id.clock + struct.length - 1 && struct is! GC) {
    final diff = id.clock - struct.id.clock + 1;
    // ignore: avoid_dynamic_calls
    (transaction as dynamic)._splitStruct(struct, diff);
  }
  return struct;
}

/// Replace [struct] in the store with [newStruct].
///
/// Mirrors: `replaceStruct` in StructStore.js
void replaceStruct(dynamic transaction, AbstractStruct struct, AbstractStruct newStruct) {
  // ignore: avoid_dynamic_calls
  final store = transaction.doc.store as StructStore;
  final structs = store.clients[struct.id.client]!;
  structs[findIndexSS(structs, struct.id.clock)] = newStruct;
}

/// Find the index of the struct at [clock] in [structs], splitting if needed.
///
/// Mirrors: `findIndexCleanStart` in StructStore.js
int findIndexCleanStart(
    dynamic transaction, List<AbstractStruct> structs, int clock) {
  final index = findIndexSS(structs, clock);
  final struct = structs[index];
  if (struct.id.clock < clock) {
    final diff = clock - struct.id.clock;
    // ignore: avoid_dynamic_calls
    final right = struct.splice(diff);
    structs.insert(index + 1, right);
    if (transaction != null) {
      // ignore: avoid_dynamic_calls
      (transaction as dynamic).mergeStructs.add(right);
    }
    return index + 1;
  }
  return index;
}

// Marker interface for structs that can be split
abstract class _SplittableStruct {}
