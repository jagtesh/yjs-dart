/// Dart translation of src/utils/StructStore.js
///
/// Mirrors: yjs/src/utils/StructStore.js (v14.0.0-22)
library;

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
  ({Map<int, int> missing, List<int> update})? pendingStructs;

  /// Pending delete set update.
  List<int>? pendingDs;

  /// Skip ranges (gaps in the struct store).
  final IdSet skips = createIdSet();

  /// Computed delete set from all GC structs.
  IdSet get ds => createDeleteSetFromStructStore(this);

  /// Add a struct to the store.
  void addStruct(AbstractStruct struct) {
    addStructToStore(this, struct);
  }
}

/// Add a struct to [store].
///
/// Mirrors: `addStruct` in StructStore.js
void addStructToStore(StructStore store, AbstractStruct struct) {
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
    if (ranges.isNotEmpty) {
      sm[client] = ranges.first.clock;
    }
  });
  return sm;
}

/// Get the current clock for [client] in [store].
///
/// Mirrors: `getState` in StructStore.js
int getState(StructStore store, int client) {
  final structs = store.clients[client];
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
AbstractStruct getItem(StructStore store, ID id) {
  final structs = store.clients[id.client];
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
        ds.addToIdSet(client, struct.id.clock, struct.length);
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
