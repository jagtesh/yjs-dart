/// Dart translation of src/utils/IdSet.js (partial - core IdSet class)
///
/// Mirrors: yjs/src/utils/IdSet.js (v14.0.0-22)
/// Note: Full implementation of IdSet with all operations is in this file.
library;

import '../utils/id.dart';

/// A range of IDs: [clock, clock + length).
class IdRange {
  int clock;
  int length;

  IdRange(this.clock, this.length);

  int get end => clock + length;

  bool contains(int c) => c >= clock && c < clock + length;
}

/// A set of ID ranges, organized by client.
///
/// Mirrors: `IdSet` in IdSet.js
class IdSet {
  /// Map from client id to sorted list of ID ranges.
  final Map<int, List<IdRange>> clients = {};

  /// Add a range [clock, clock + length) for [client].
  void addToIdSet(int client, int clock, int length) {
    final ranges = clients.putIfAbsent(client, () => []);
    // Try to merge with existing ranges
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      if (r.end == clock) {
        r.length += length;
        // Check if we can merge with the next range
        if (i + 1 < ranges.length && ranges[i + 1].clock == r.end) {
          r.length += ranges[i + 1].length;
          ranges.removeAt(i + 1);
        }
        return;
      } else if (r.clock == clock + length) {
        r.clock = clock;
        r.length += length;
        return;
      } else if (r.clock > clock) {
        ranges.insert(i, IdRange(clock, length));
        return;
      }
    }
    ranges.add(IdRange(clock, length));
  }

  /// Check if [client]:[clock] is in this set.
  bool has(int client, int clock) {
    final ranges = clients[client];
    if (ranges == null) return false;
    for (final r in ranges) {
      if (r.contains(clock)) return true;
      if (r.clock > clock) return false;
    }
    return false;
  }

  /// Delete a range [clock, clock + length) for [client].
  void delete(int client, int clock, int length) {
    final ranges = clients[client];
    if (ranges == null) return;
    final end = clock + length;
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      if (r.clock >= end) break;
      if (r.end <= clock) continue;
      // Overlap
      if (r.clock < clock && r.end > end) {
        // Split
        final newRange = IdRange(end, r.end - end);
        r.length = clock - r.clock;
        ranges.insert(i + 1, newRange);
        return;
      } else if (r.clock < clock) {
        r.length = clock - r.clock;
      } else if (r.end > end) {
        r.clock = end;
        r.length = r.end - end;
      } else {
        ranges.removeAt(i);
        i--;
      }
    }
    if (ranges.isEmpty) clients.remove(client);
  }

  /// Iterate over all ranges.
  void forEach(void Function(int client, List<IdRange> ranges) f) {
    clients.forEach(f);
  }

  /// Returns true if this set is empty.
  bool get isEmpty => clients.isEmpty;
}

/// Create a new empty [IdSet].
IdSet createIdSet() => IdSet();

/// Check if two [IdSet]s are equal.
bool equalIdSets(IdSet a, IdSet b) {
  if (a.clients.length != b.clients.length) return false;
  for (final entry in a.clients.entries) {
    final bRanges = b.clients[entry.key];
    if (bRanges == null || bRanges.length != entry.value.length) return false;
    for (var i = 0; i < entry.value.length; i++) {
      if (entry.value[i].clock != bRanges[i].clock ||
          entry.value[i].length != bRanges[i].length) {
        return false;
      }
    }
  }
  return true;
}

/// Merge multiple [IdSet]s into one.
IdSet mergeIdSets(List<IdSet> sets) {
  final result = createIdSet();
  for (final set in sets) {
    set.clients.forEach((client, ranges) {
      for (final r in ranges) {
        result.addToIdSet(client, r.clock, r.length);
      }
    });
  }
  return result;
}

/// Compute the difference: items in [a] not in [b].
IdSet diffIdSet(IdSet a, IdSet b) {
  final result = createIdSet();
  a.clients.forEach((client, ranges) {
    for (final r in ranges) {
      for (var c = r.clock; c < r.end; c++) {
        if (!b.has(client, c)) {
          result.addToIdSet(client, c, 1);
        }
      }
    }
  });
  return result;
}

/// Insert a range into an [IdSet].
void insertIntoIdSet(IdSet set, int client, int clock, int length) {
  set.addToIdSet(client, clock, length);
}
