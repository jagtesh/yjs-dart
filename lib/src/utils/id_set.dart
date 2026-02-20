/// Dart translation of src/utils/IdSet.js
///
/// Mirrors: yjs/src/utils/IdSet.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/encoding.dart' as encoding;
import '../lib0/decoding.dart' as decoding;
import '../structs/abstract_struct.dart';
import '../utils/id.dart';
import '../utils/update_encoder.dart';
import '../structs/item.dart';
import '../utils/transaction.dart';
import '../utils/struct_store.dart' as struct_store;

/// A single contiguous range of IDs: [clock, clock+len).
///
/// Mirrors: `IdRange` in IdSet.js
class IdRange {
  final int clock;
  int len;

  IdRange(this.clock, this.len);

  IdRange copyWith(int clock, int len) => IdRange(clock, len);

  /// Helper making this compatible with IdMap (returns empty attrs).
  List<Object> get attrs => const [];
}

/// A range that may or may not exist in an IdSet.
///
/// Mirrors: `MaybeIdRange` in IdSet.js
class MaybeIdRange {
  final int clock;
  final int len;
  final bool exists;

  MaybeIdRange(this.clock, this.len, this.exists);
}

MaybeIdRange createMaybeIdRange(int clock, int len, bool exists) =>
    MaybeIdRange(clock, len, exists);

/// A sorted, lazily-merged list of [IdRange]s.
///
/// Mirrors: `IdRanges` in IdSet.js
class IdRanges {
  bool sorted = false;

  /// True if the last item was exposed via [getIds] and must not be mutated.
  bool _lastIsUsed = false;

  final List<IdRange> _ids;

  IdRanges(this._ids);

  IdRanges copy() => IdRanges(List.of(_ids));

  void add(int clock, int length) {
    if (_ids.isNotEmpty) {
      final last = _ids.last;
      if (last.clock + last.len == clock) {
        if (_lastIsUsed) {
          _ids[_ids.length - 1] = IdRange(last.clock, last.len + length);
          _lastIsUsed = false;
        } else {
          _ids.last.len += length;
        }
        return;
      }
    }
    sorted = false;
    _ids.add(IdRange(clock, length));
  }

  /// Return the sorted, merged list of id ranges.
  List<IdRange> getIds() {
    _lastIsUsed = true;
    if (!sorted) {
      sorted = true;
      _ids.sort((a, b) => a.clock - b.clock);
      // Merge overlapping/adjacent ranges in-place
      var i = 1;
      var j = 1;
      while (i < _ids.length) {
        final left = _ids[j - 1];
        final right = _ids[i];
        if (left.clock + left.len >= right.clock) {
          final r = right.clock + right.len - left.clock;
          if (left.len < r) {
            _ids[j - 1] = IdRange(left.clock, r);
          }
        } else if (left.len == 0) {
          _ids[j - 1] = right;
        } else {
          if (j < i) _ids[j] = right;
          j++;
        }
        i++;
      }
      final newLen = (_ids.isNotEmpty && _ids[j - 1].len == 0) ? j - 1 : j;
      _ids.length = newLen;
    }
    return _ids;
  }
}

/// A set of ID ranges, keyed by client ID.
///
/// Mirrors: `IdSet` in IdSet.js
class IdSet {
  final Map<int, IdRanges> clients = {};

  bool isEmpty() => clients.isEmpty;

  void forEach(void Function(IdRange range, int client) f) {
    clients.forEach((client, ranges) {
      for (final range in ranges.getIds()) {
        f(range, client);
      }
    });
  }

  bool hasId(ID id) => has(id.client, id.clock);

  bool has(int client, int clock) {
    final dr = clients[client];
    if (dr != null) {
      return findIndexInIdRanges(dr.getIds(), clock) != null;
    }
    return false;
  }

  /// Return slices of ids that exist in this idset.
  List<MaybeIdRange> slice(int client, int clock, int len) {
    final dr = clients[client];
    final res = <MaybeIdRange>[];
    if (dr != null) {
      final ranges = dr.getIds();
      var index = findRangeStartInIdRanges(ranges, clock);
      if (index != null) {
        IdRange? prev;
        while (index! < ranges.length) {
          var r = ranges[index];
          if (r.clock < clock) {
            r = IdRange(clock, r.len - (clock - r.clock));
          }
          if (r.clock + r.len > clock + len) {
            r = IdRange(r.clock, clock + len - r.clock);
          }
          if (r.len <= 0) break;
          final prevEnd = prev != null ? prev.clock + prev.len : clock;
          if (prevEnd < r.clock) {
            res.add(createMaybeIdRange(prevEnd, r.clock - prevEnd, false));
          }
          prev = r;
          res.add(createMaybeIdRange(r.clock, r.len, true));
          index++;
        }
      }
    }
    if (res.isNotEmpty) {
      final last = res.last;
      final end = last.clock + last.len;
      if (end < clock + len) {
        res.add(createMaybeIdRange(end, clock + len - end, false));
      }
    } else {
      res.add(createMaybeIdRange(clock, len, false));
    }
    return res;
  }

  void add(int client, int clock, int len) =>
      addToIdSet(this, client, clock, len);

  void delete(int client, int clock, int len) =>
      deleteRangeFromIdSet(this, client, clock, len);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Delete a range [clock, clock+len) from [set].
///
/// Mirrors: `_deleteRangeFromIdSet` in IdSet.js
void deleteRangeFromIdSet(IdSet set, int client, int clock, int len) {
  final dr = set.clients[client];
  if (dr != null && len > 0) {
    final ids = dr.getIds();
    var index = findRangeStartInIdRanges(ids, clock);
    if (index != null) {
      while (index! < ids.length && ids[index].clock < clock + len) {
        final r = ids[index];
        if (r.clock < clock) {
          ids[index] = r.copyWith(r.clock, clock - r.clock);
          if (clock + len < r.clock + r.len) {
            ids.insert(index + 1, r.copyWith(clock + len, r.clock + r.len - clock - len));
          }
        } else if (clock + len < r.clock + r.len) {
          ids[index] = r.copyWith(clock + len, r.clock + r.len - clock - len);
        } else if (ids.length == 1) {
          set.clients.remove(client);
          return;
        } else {
          ids.removeAt(index--);
        }
        index++;
      }
    }
  }
}

/// Iterate over all structs mentioned by [ds].
///
/// Mirrors: `iterateStructsByIdSet` in IdSet.js
void iterateStructsByIdSet(
  dynamic transaction,
  IdSet ds,
  void Function(AbstractStruct) f,
) {
  ds.clients.forEach((clientid, idRanges) {
    final ranges = idRanges.getIds();
    // ignore: avoid_dynamic_calls
    final structs = transaction.doc.store.clients[clientid] as List<AbstractStruct>?;
    if (structs != null) {
      for (final del in ranges) {
        iterateStructs(transaction, structs, del.clock, del.len, f);
      }
    }
  });
}

/// Iterate structs in [structs] that overlap [clock, clock+len).
///
/// Mirrors: `iterateStructs` in StructStore.js
void iterateStructs(
  dynamic transaction,
  List<AbstractStruct> structs,
  int clock,
  int len,
  void Function(AbstractStruct) f,
) {
  if (len == 0) return;
  final clockEnd = clock + len;
  var index = findIndexSS(structs, clock);
  var struct = structs[index];
  // Split if necessary (requires transaction)
  if (struct.id.clock < clock) {
    // splitItem would be called here — deferred to Phase 2
  }
  while (index < structs.length) {
    struct = structs[index++];
    if (struct.id.clock < clockEnd) {
      f(struct);
    } else {
      break;
    }
  }
}

/// Binary search: find index of range containing [clock], or null.
///
/// Mirrors: `findIndexInIdRanges` in IdSet.js
int? findIndexInIdRanges(List<IdRange> dis, int clock) {
  var left = 0;
  var right = dis.length - 1;
  while (left <= right) {
    final midindex = (left + right) ~/ 2;
    final mid = dis[midindex];
    final midclock = mid.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.len) return midindex;
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
  }
  return null;
}

/// Binary search: find first range that contains or comes after [clock].
///
/// Mirrors: `findRangeStartInIdRanges` in IdSet.js
int? findRangeStartInIdRanges(List<IdRange> dis, int clock) {
  var left = 0;
  var right = dis.length - 1;
  while (left <= right) {
    final midindex = (left + right) ~/ 2;
    final mid = dis[midindex];
    final midclock = mid.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.len) return midindex;
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
  }
  return left < dis.length ? left : null;
}

/// Merge multiple IdSets into a fresh one.
///
/// Mirrors: `mergeIdSets` in IdSet.js
IdSet mergeIdSets(List<IdSet> idSets) {
  final merged = IdSet();
  for (var dssI = 0; dssI < idSets.length; dssI++) {
    idSets[dssI].clients.forEach((client, rangesLeft) {
      if (!merged.clients.containsKey(client)) {
        final ids = List<IdRange>.of(rangesLeft.getIds());
        for (var i = dssI + 1; i < idSets.length; i++) {
          final nextIds = idSets[i].clients[client];
          if (nextIds != null) {
            ids.addAll(nextIds.getIds());
          }
        }
        merged.clients[client] = IdRanges(ids);
      }
    });
  }
  return merged;
}

/// Insert all ranges from [src] into [dest].
///
/// Mirrors: `_insertIntoIdSet` in IdSet.js
void insertIntoIdSetInternal(IdSet dest, IdSet src) {
  src.clients.forEach((client, srcRanges) {
    final targetRanges = dest.clients[client];
    if (targetRanges != null) {
      targetRanges._ids.addAll(srcRanges.getIds());
      targetRanges.sorted = false;
    } else {
      final res = srcRanges.copy();
      res.sorted = true;
      dest.clients[client] = res;
    }
  });
}

/// Public alias for insertIntoIdSetInternal.
///
/// Mirrors: `insertIntoIdSet` in IdSet.js
void insertIntoIdSet(IdSet dest, IdSet src) => insertIntoIdSetInternal(dest, src);

/// Compute the diff: ranges in [set] that are NOT in [exclude].
///
/// Mirrors: `_diffSet` / `diffIdSet` in IdSet.js
IdSet diffIdSet(IdSet set, IdSet exclude) {
  final res = IdSet();
  set.clients.forEach((client, setRanges_) {
    final resRanges = <IdRange>[];
    final excludedRanges_ = exclude.clients[client];
    final setRanges = setRanges_.getIds();
    if (excludedRanges_ == null) {
      resRanges.addAll(setRanges);
    } else {
      final excludedRanges = excludedRanges_.getIds();
      var i = 0;
      var j = 0;
      IdRange? currRange = setRanges.isNotEmpty ? setRanges[0] : null;
      while (i < setRanges.length && j < excludedRanges.length && currRange != null) {
        final e = excludedRanges[j];
        if (currRange.clock + currRange.len <= e.clock) {
          if (currRange.len > 0) resRanges.add(currRange);
          currRange = ++i < setRanges.length ? setRanges[i] : null;
        } else if (e.clock + e.len <= currRange.clock) {
          j++;
        } else if (e.clock <= currRange.clock) {
          final newClock = e.clock + e.len;
          final newLen = currRange.clock + currRange.len - newClock;
          if (newLen > 0) {
            currRange = currRange.copyWith(newClock, newLen);
            j++;
          } else {
            currRange = ++i < setRanges.length ? setRanges[i] : null;
          }
        } else {
          final nextLen = e.clock - currRange.clock;
          resRanges.add(currRange.copyWith(currRange.clock, nextLen));
          final remaining = currRange.len - e.len - nextLen;
          currRange = remaining > 0
              ? currRange.copyWith(currRange.clock + e.len + nextLen, remaining)
              : (++i < setRanges.length ? setRanges[i] : null);
          if (remaining <= 0) {
            // currRange already advanced
          } else {
            j++;
          }
        }
      }
      if (currRange != null) resRanges.add(currRange);
      i++;
      while (i < setRanges.length) {
        resRanges.add(setRanges[i++]);
      }
    }
    if (resRanges.isNotEmpty) {
      res.clients[client] = IdRanges(resRanges);
    }
  });
  return res;
}

/// Compute the intersection of two IdSets.
///
/// Mirrors: `intersectSets` in IdSet.js
IdSet intersectSets(IdSet setA, IdSet setB) {
  final res = IdSet();
  setA.clients.forEach((client, aRanges_) {
    final resRanges = <IdRange>[];
    final bRanges_ = setB.clients[client];
    final aRanges = aRanges_.getIds();
    if (bRanges_ != null) {
      final bRanges = bRanges_.getIds();
      for (var a = 0, b = 0; a < aRanges.length && b < bRanges.length;) {
        final aRange = aRanges[a];
        final bRange = bRanges[b];
        final clock = aRange.clock > bRange.clock ? aRange.clock : bRange.clock;
        final aEnd = aRange.clock + aRange.len;
        final bEnd = bRange.clock + bRange.len;
        final len = (aEnd < bEnd ? aEnd : bEnd) - clock;
        if (len > 0) resRanges.add(IdRange(clock, len));
        if (aEnd < bEnd) {
          a++;
        } else {
          b++;
        }
      }
    }
    if (resRanges.isNotEmpty) {
      res.clients[client] = IdRanges(resRanges);
    }
  });
  return res;
}

/// Add a range to [idSet].
///
/// Mirrors: `addToIdSet` in IdSet.js
void addToIdSet(IdSet idSet, int client, int clock, int length) {
  if (length == 0) return;
  final idRanges = idSet.clients[client];
  if (idRanges != null) {
    idRanges.add(clock, length);
  } else {
    idSet.clients[client] = IdRanges([IdRange(clock, length)]);
  }
}

/// Create a fresh empty IdSet.
///
/// Mirrors: `createIdSet` in IdSet.js
IdSet createIdSet() => IdSet();

/// Create a delete set from all deleted structs in [store].
///
/// Mirrors: `createDeleteSetFromStructStore` in IdSet.js
IdSet createDeleteSetFromStructStore(dynamic store) {
  final ds = IdSet();
  // ignore: avoid_dynamic_calls
  (store.clients as Map<int, List<AbstractStruct>>).forEach((client, structs) {
    final dsitems = <IdRange>[];
    for (var i = 0; i < structs.length; i++) {
      final struct = structs[i];
      if (struct.deleted) {
        final clock = struct.id.clock;
        var len = struct.length;
        if (i + 1 < structs.length) {
          var next = structs[i + 1];
          while (i + 1 < structs.length && next.deleted) {
            len += next.length;
            i++;
            if (i + 1 < structs.length) next = structs[i + 1];
          }
        }
        dsitems.add(IdRange(clock, len));
      }
    }
    if (dsitems.isNotEmpty) {
      ds.clients[client] = IdRanges(dsitems);
    }
  });
  return ds;
}

/// Create an insert set from all non-deleted structs in [store].
///
/// Mirrors: `createInsertSetFromStructStore` in IdSet.js
IdSet createInsertSetFromStructStore(dynamic store, bool filterDeleted) {
  final idset = IdSet();
  // ignore: avoid_dynamic_calls
  (store.clients as Map<int, List<AbstractStruct>>).forEach((client, structs) {
    final iditems = <IdRange>[];
    for (var i = 0; i < structs.length; i++) {
      final struct = structs[i];
      if (!(filterDeleted && struct.deleted)) {
        final clock = struct.id.clock;
        var len = struct.length;
        if (i + 1 < structs.length) {
          var next = structs[i + 1];
          while (i + 1 < structs.length && !(filterDeleted && next.deleted)) {
            len += next.length;
            i++;
            if (i + 1 < structs.length) next = structs[i + 1];
          }
        }
        iditems.add(IdRange(clock, len));
      }
    }
    if (iditems.isNotEmpty) {
      idset.clients[client] = IdRanges(iditems);
    }
  });
  return idset;
}

/// Encode [idSet] to [encoder].
///
/// Mirrors: `writeIdSet` in IdSet.js
void writeIdSet(dynamic encoder, IdSet idSet) {
  // ignore: avoid_dynamic_calls
  encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, idSet.clients.length);
  // Write in deterministic order (descending client id)
  final entries = idSet.clients.entries.toList()
    ..sort((a, b) => b.key - a.key);
  for (final entry in entries) {
    final client = entry.key;
    final idRanges = entry.value.getIds();
    // ignore: avoid_dynamic_calls
    encoder.resetIdSetCurVal();
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, client);
    // ignore: avoid_dynamic_calls
    encoding.writeVarUint(encoder.restEncoder as encoding.Encoder, idRanges.length);
    for (final item in idRanges) {
      // ignore: avoid_dynamic_calls
      encoder.writeIdSetClock(item.clock);
      // ignore: avoid_dynamic_calls
      encoder.writeIdSetLen(item.len);
    }
  }
}

/// Decode an IdSet from [decoder].
///
/// Mirrors: `readIdSet` in IdSet.js
IdSet readIdSet(dynamic decoder) {
  final ds = IdSet();
  // ignore: avoid_dynamic_calls
  final numClients = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  for (var i = 0; i < numClients; i++) {
    // ignore: avoid_dynamic_calls
    decoder.resetDsCurVal();
    // ignore: avoid_dynamic_calls
    final client = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final numberOfDeletes = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    if (numberOfDeletes > 0) {
      final dsRanges = <IdRange>[];
      for (var j = 0; j < numberOfDeletes; j++) {
        // ignore: avoid_dynamic_calls
        dsRanges.add(IdRange(decoder.readDsClock() as int, decoder.readDsLen() as int));
      }
      ds.clients[client] = IdRanges(dsRanges);
    }
  }
  return ds;
}

/// Apply a delete set from [decoder] to [store] within [transaction].
/// Returns a v2 update with unapplied deletes, or null if all were applied.
///
/// Mirrors: `readAndApplyDeleteSet` in IdSet.js
Uint8List? readAndApplyDeleteSet(
  dynamic decoder,
  dynamic transaction,
  dynamic store,
) {
  final unappliedDS = IdSet();
  // ignore: avoid_dynamic_calls
  final numClients = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
  for (var i = 0; i < numClients; i++) {
    // ignore: avoid_dynamic_calls
    decoder.resetDsCurVal();
    // ignore: avoid_dynamic_calls
    final client = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final numberOfDeletes = decoding.readVarUint(decoder.restDecoder as decoding.Decoder);
    // ignore: avoid_dynamic_calls
    final structs = (store.clients[client] ?? <AbstractStruct>[]) as List<AbstractStruct>;
    // ignore: avoid_dynamic_calls
    final state = struct_store.getState(store, client);
    for (var j = 0; j < numberOfDeletes; j++) {
      // ignore: avoid_dynamic_calls
      final clock = decoder.readDsClock() as int;
      // ignore: avoid_dynamic_calls
      final clockEnd = clock + (decoder.readDsLen() as int);
      if (clock < state) {
        if (state < clockEnd) {
          addToIdSet(unappliedDS, client, state, clockEnd - state);
        }
        var index = findIndexSS(structs, clock);
        var struct = structs[index];
        if (!struct.deleted && struct.id.clock < clock) {
          structs.insert(index + 1, splitItem(transaction as Transaction, struct as Item, clock - struct.id.clock));
          index++; // increase index because we decreased length of struct
        }
        while (index < structs.length) {
          struct = structs[index++];
          if (struct.id.clock < clockEnd) {
            if (!struct.deleted) {
              if (clockEnd < struct.id.clock + struct.length) {
                structs.insert(index, splitItem(transaction as Transaction, struct as Item, clockEnd - struct.id.clock));
              }
              (struct as Item).delete(transaction as Transaction);
            }
          } else {
            break;
          }
        }
      } else {
        addToIdSet(unappliedDS, client, clock, clockEnd - clock);
      }
    }
  }
  if (unappliedDS.clients.isNotEmpty) {
    final ds = UpdateEncoderV2();
    encoding.writeVarUint(ds.restEncoder, 0); // 0 structs
    writeIdSet(ds, unappliedDS);
    return ds.toUint8Array();
  }
  return null;
}

/// Check equality of two IdSets.
///
/// Mirrors: `equalIdSets` in IdSet.js
bool equalIdSets(IdSet ds1, IdSet ds2) {
  if (ds1.clients.length != ds2.clients.length) return false;
  for (final entry in ds1.clients.entries) {
    final client = entry.key;
    final items1 = entry.value.getIds();
    final items2 = ds2.clients[client]?.getIds();
    if (items2 == null || items1.length != items2.length) return false;
    for (var i = 0; i < items1.length; i++) {
      if (items1[i].clock != items2[i].clock || items1[i].len != items2[i].len) {
        return false;
      }
    }
  }
  return true;
}

// Internal binary search used by iterateStructs.
// The canonical public version is in struct_store.dart.
int findIndexSS(List<AbstractStruct> structs, int clock) {
  var left = 0;
  var right = structs.length - 1;
  var mid = structs[right];
  var midclock = mid.id.clock;
  if (midclock == clock) return right;
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
  throw StateError('findIndexSS: unexpected case');
}
