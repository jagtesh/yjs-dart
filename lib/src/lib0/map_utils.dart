/// Native Dart implementation of lib0/map utilities.
///
/// Mirrors: lib0/map.js
library;

/// Returns the value for [key] in [map], or sets it to [create()] if absent.
///
/// Equivalent to lib0's `map.setIfUndefined`.
V setIfUndefined<K, V>(Map<K, V> map, K key, V Function() create) {
  return map.putIfAbsent(key, create);
}

/// Create a new empty map.
Map<K, V> create<K, V>() => <K, V>{};

/// Copy all entries from [from] into [to].
void copy<K, V>(Map<K, V> from, Map<K, V> to) {
  from.forEach((key, value) => to[key] = value);
}

/// Returns a new map with all entries satisfying [predicate].
Map<K, V> filter<K, V>(Map<K, V> map, bool Function(K key, V value) predicate) {
  return Map.fromEntries(
    map.entries.where((e) => predicate(e.key, e.value)),
  );
}

/// Returns a new map with values transformed by [f].
Map<K, R> mapValues<K, V, R>(Map<K, V> map, R Function(V value) f) {
  return map.map((key, value) => MapEntry(key, f(value)));
}

/// Check if two maps are equal (shallow).
bool equalFlat<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Returns the value for [key] or null.
V? getOrNull<K, V>(Map<K, V> map, K key) => map[key];

/// Iterate over all entries.
void forEach<K, V>(Map<K, V> map, void Function(V value, K key) f) {
  map.forEach((key, value) => f(value, key));
}

/// Returns true if [map] has [key].
bool has<K, V>(Map<K, V> map, K key) => map.containsKey(key);
