/// Dart translation of src/utils/IdMap.js (structural stub)
///
/// Mirrors: yjs/src/utils/IdMap.js (v14.0.0-22)
library;

import '../utils/id.dart';
import '../utils/id_set.dart';

/// A map of ID ranges to values, organized by client.
///
/// Mirrors: `IdMap` in IdMap.js
class IdMap<T> {
  final Map<int, List<({IdRange range, T value})>> clients = {};

  void insert(int client, int clock, int length, T value) {
    final list = clients.putIfAbsent(client, () => []);
    list.add((range: IdRange(clock, length), value: value));
  }

  T? get(int client, int clock) {
    final list = clients[client];
    if (list == null) return null;
    for (final entry in list) {
      if (entry.range.contains(clock)) return entry.value;
    }
    return null;
  }

  void forEach(void Function(int client, IdRange range, T value) f) {
    clients.forEach((client, entries) {
      for (final e in entries) {
        f(client, e.range, e.value);
      }
    });
  }
}

/// Create a new empty [IdMap].
IdMap<T> createIdMap<T>() => IdMap<T>();

/// Insert a range into an [IdMap].
void insertIntoIdMap<T>(IdMap<T> map, int client, int clock, int length, T value) {
  map.insert(client, clock, length, value);
}

/// Merge multiple [IdMap]s into one.
IdMap<T> mergeIdMaps<T>(List<IdMap<T>> maps) {
  final result = createIdMap<T>();
  for (final m in maps) {
    m.forEach((client, range, value) {
      result.insert(client, range.clock, range.length, value);
    });
  }
  return result;
}

/// Compute the difference between two [IdMap]s.
IdMap<T> diffIdMap<T>(IdMap<T> a, IdMap<T> b) {
  // TODO: implement full diff
  return createIdMap<T>();
}

/// Filter an [IdMap] by a predicate.
IdMap<T> filterIdMap<T>(IdMap<T> map, bool Function(int client, IdRange range, T value) f) {
  final result = createIdMap<T>();
  map.forEach((client, range, value) {
    if (f(client, range, value)) {
      result.insert(client, range.clock, range.length, value);
    }
  });
  return result;
}
