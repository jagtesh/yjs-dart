/// Dart translation of src/ytype.js
///
/// Mirrors: yjs/src/ytype.js (v14.0.0-22)
///
/// Note: The JS version uses a unified YType class with lib0/delta for all
/// operations. This Dart translation preserves the same unified class while
/// using idiomatic Dart APIs.
library;

import 'dart:typed_data';

import 'structs/abstract_struct.dart';
import 'structs/content.dart';
import 'structs/item.dart';
import 'utils/event_handler.dart';
import 'utils/id.dart';
import 'utils/id_set.dart' show createIdSet;
import 'utils/struct_store.dart' show getState, getItemCleanStart;
import 'utils/transaction.dart'
    hide callEventHandlerListeners;
import 'utils/update_decoder.dart';
import 'utils/update_encoder.dart';
import 'utils/y_event.dart';

// ---------------------------------------------------------------------------
// Type reference IDs (mirrors ContentType.js)
// ---------------------------------------------------------------------------

const int typeRefArray = 0;
const int typeRefMap = 1;
const int typeRefText = 2;
const int typeRefXmlElement = 3;
const int typeRefXmlFragment = 4;
const int typeRefXmlHook = 5;
const int typeRefXmlText = 6;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void warnPrematureAccess() {
  // ignore: avoid_print
  print(
      'Invalid access: Add Yjs type to a document before reading data.');
}

bool equalAttrs(Object? a, Object? b) {
  if (a == b) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// ArraySearchMarker
// ---------------------------------------------------------------------------

int _globalSearchMarkerTimestamp = 0;
const int _maxSearchMarker = 80;

/// A search marker for fast position lookup in YType linked lists.
///
/// Mirrors: `ArraySearchMarker` in ytype.js
class ArraySearchMarker {
  Item p;
  int index;
  int timestamp;

  ArraySearchMarker(this.p, int index)
      : index = index,
        timestamp = _globalSearchMarkerTimestamp++ {
    p.marker = true;
  }
}

void _refreshMarkerTimestamp(ArraySearchMarker marker) {
  marker.timestamp = _globalSearchMarkerTimestamp++;
}

void _overwriteMarker(ArraySearchMarker marker, Item p, int index) {
  marker.p.marker = false;
  marker.p = p;
  p.marker = true;
  marker.index = index;
  marker.timestamp = _globalSearchMarkerTimestamp++;
}

ArraySearchMarker _markPosition(
    List<ArraySearchMarker> searchMarker, Item p, int index) {
  if (searchMarker.length >= _maxSearchMarker) {
    final marker = searchMarker.reduce(
        (a, b) => a.timestamp < b.timestamp ? a : b);
    _overwriteMarker(marker, p, index);
    return marker;
  } else {
    final pm = ArraySearchMarker(p, index);
    searchMarker.add(pm);
    return pm;
  }
}

/// Find or create a search marker for [yarray] at [index].
///
/// Mirrors: `findMarker` in ytype.js
ArraySearchMarker? findMarker(YType yarray, int index) {
  if (yarray._start == null ||
      index == 0 ||
      yarray._searchMarker == null) {
    return null;
  }
  final markers = yarray._searchMarker!;
  ArraySearchMarker? marker;
  if (markers.isNotEmpty) {
    marker = markers.reduce((a, b) =>
        (index - a.index).abs() < (index - b.index).abs() ? a : b);
  }
  var p = yarray._start!;
  var pindex = 0;
  if (marker != null) {
    p = marker.p;
    pindex = marker.index;
    _refreshMarkerTimestamp(marker);
  }
  // Iterate right
  while (p.right != null && pindex < index) {
    if (!p.deleted && p.countable) {
      if (index < pindex + p.length) break;
      pindex += p.length;
    }
    p = p.right as Item;
  }
  // Iterate left
  while (p.left != null && pindex > index) {
    p = p.left as Item;
    if (!p.deleted && p.countable) {
      pindex -= p.length;
    }
  }
  // Ensure p can't be merged with left
  while (p.left != null &&
      (p.left as Item).id.client == p.id.client &&
      (p.left as Item).id.clock + (p.left as Item).length == p.id.clock) {
    p = p.left as Item;
    if (!p.deleted && p.countable) {
      pindex -= p.length;
    }
  }
  if (marker != null &&
      (marker.index - pindex).abs() <
          (yarray._length / _maxSearchMarker)) {
    _overwriteMarker(marker, p, pindex);
    return marker;
  } else {
    return _markPosition(markers, p, pindex);
  }
}

/// Update search markers after a change at [index] with delta [len].
///
/// Mirrors: `updateMarkerChanges` in ytype.js
void updateMarkerChanges(
    List<ArraySearchMarker> searchMarker, int index, int len) {
  for (var i = searchMarker.length - 1; i >= 0; i--) {
    final m = searchMarker[i];
    if (len > 0) {
      var p = m.p;
      p.marker = false;
      while (p.left != null && ((p.left as Item).deleted || !(p.left as Item).countable)) {
        p = p.left as Item;
        if (!(p.deleted) && p.countable) {
          m.index -= p.length;
        }
      }
      if (p.marker == true) {
        searchMarker.removeAt(i);
        continue;
      }
      m.p = p;
      p.marker = true;
    }
    if (index < m.index || (len > 0 && index == m.index)) {
      m.index = index > m.index + len ? m.index + len : index < m.index ? m.index + len : index;
    }
  }
}

// ---------------------------------------------------------------------------
// YType
// ---------------------------------------------------------------------------

/// Abstract Yjs shared type.
///
/// Mirrors: `YType` in ytype.js
class YType<EventType> {
  /// The name of this type (for XML element types).
  String? name;

  /// The first item in the linked list of this type's content.
  Item? _start;

  /// The map of key → item for map-like types.
  final Map<String, Item> _map = {};

  /// The document this type belongs to.
  dynamic doc; // Doc — avoids circular import

  /// The item that contains this type (if it's a nested type).
  Item? _item;

  /// The length of this type's content.
  int _length = 0;

  /// Public accessor for the first item in the linked list.
  Item? get start => _start;

  /// Event handlers.
  final EventHandler<EventType, Transaction> _eH = createEventHandler();

  /// Deep event handlers.
  final EventHandler<List<YEvent<dynamic>>, Transaction> _dEH =
      createEventHandler();

  /// Search markers for fast position lookup.
  List<ArraySearchMarker>? _searchMarker;

  /// Whether this YText contains formatting attributes.
  bool _hasFormatting = false;

  /// The legacy type reference ID (for binary serialization).
  int _legacyTypeRef = typeRefXmlFragment;

  /// Preliminary delta to apply when integrated (before doc is set).
  Object? _prelim;

  YType([this.name]) {
    _searchMarker = [];
    _legacyTypeRef = name == null ? typeRefXmlFragment : typeRefXmlElement;
  }

  /// The length of this type's content.
  int get length {
    doc ?? warnPrematureAccess();
    return _length;
  }

  /// Returns the parent type, or null if this is a root type.
  YType<dynamic>? get parent {
    return _item != null ? _item!.parent as YType<dynamic>? : null;
  }

  /// Public accessor for the item that contains this type.
  Item? get item => _item;

  /// Integrate this type into the Yjs instance.
  ///
  /// Mirrors: `_integrate` in ytype.js
  void integrate(dynamic y, Item? item) {
    doc = y;
    _item = item;
    if (_prelim != null) {
      // Apply preliminary delta if any
      _prelim = null;
    }
  }

  /// Creates a copy of this type.
  YType<EventType> copy() => YType<EventType>(name);

  /// Creates YEvent and calls all type observers.
  ///
  /// Mirrors: `_callObserver` in ytype.js
  void callObserver(Transaction transaction, Set<String?> parentSubs) {
    final event = YEvent<dynamic>(this, transaction, parentSubs);
    callTypeObservers(this, transaction, event);
    if (!transaction.local && _searchMarker != null) {
      _searchMarker!.clear();
    }
    if (!transaction.local && _hasFormatting) {
      transaction.needFormattingCleanup = true;
    }
  }

  /// Observe changes to this type.
  void Function(EventType, Transaction) observe(
      void Function(EventType event, Transaction tr) f) {
    addEventHandlerListener(_eH, f);
    return f;
  }

  /// Stop observing changes to this type.
  void unobserve(void Function(EventType event, Transaction tr) f) {
    removeEventHandlerListener(_eH, f);
  }

  /// Observe changes to this type and all nested types.
  void Function(List<YEvent<dynamic>>, Transaction) observeDeep(
      void Function(List<YEvent<dynamic>> events, Transaction tr) f) {
    addEventHandlerListener(_dEH, f);
    return f;
  }

  /// Stop observing deep changes.
  void unobserveDeep(
      void Function(List<YEvent<dynamic>> events, Transaction tr) f) {
    removeEventHandlerListener(_dEH, f);
  }

  /// Write this type to [encoder].
  ///
  /// Mirrors: `_write` in ytype.js
  void write(dynamic encoder) {
    // ignore: avoid_dynamic_calls
    encoder.writeTypeRef(_legacyTypeRef);
    if (_legacyTypeRef == typeRefXmlElement ||
        _legacyTypeRef == typeRefXmlHook) {
      // ignore: avoid_dynamic_calls
      encoder.writeKey(name ?? '');
    }
  }

  /// Convert this type to JSON.
  Object? toJson() {
    final res = <String, Object?>{};
    if (name != null) res['name'] = name;
    if (_length > 0) {
      res['children'] = typeListSlice(this, 0, _length)
          .map((c) => c is YType ? c.toJson() : c)
          .toList();
    }
    final attrs = typeMapGetAll(this);
    if (attrs.isNotEmpty) {
      res['attrs'] = attrs.map((k, v) => MapEntry(k, v is YType ? v.toJson() : v));
    }
    return res;
  }

  @override
  String toString() {
    final children = typeListSlice(this, 0, _length)
        .map((c) => c is String ? c : c is YType ? c.toString() : c.toString())
        .join('');
    if (name == null) return children;
    if (_length == 0) return '<$name />';
    return '<$name>$children</$name>';
  }
}

// ---------------------------------------------------------------------------
// callTypeObservers
// ---------------------------------------------------------------------------

/// Call event listeners with an event, propagating to parent types.
///
/// Mirrors: `callTypeObservers` in ytype.js
void callTypeObservers(
    YType<dynamic> type, Transaction transaction, YEvent<dynamic> event) {
  final changedParentTypes = transaction.changedParentTypes;
  var t = type;
  while (true) {
    changedParentTypes.putIfAbsent(t, () => []).add(event);
    if (t._item == null) break;
    final parent = t._item!.parent;
    if (parent is YType) {
      t = parent;
    } else {
      break;
    }
  }
  callEventHandlerListeners(type._eH, event, transaction);
}

// ---------------------------------------------------------------------------
// typeListSlice
// ---------------------------------------------------------------------------

/// Return a slice of the list content from [start] to [end].
///
/// Mirrors: `typeListSlice` in ytype.js
List<Object?> typeListSlice(YType<dynamic> type, int start, int end) {
  type.doc ?? warnPrematureAccess();
  if (start < 0) start = type._length + start;
  if (end < 0) end = type._length + end;
  var len = end - start;
  final cs = <Object?>[];
  var n = type._start;
  while (n != null && len > 0) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      if (c.length <= start) {
        start -= c.length;
      } else {
        for (var i = start; i < c.length && len > 0; i++) {
          cs.add(c[i]);
          len--;
        }
        start = 0;
      }
    }
    n = n.right as Item?;
  }
  return cs;
}

// ---------------------------------------------------------------------------
// typeListGet
// ---------------------------------------------------------------------------

/// Get the element at [index] in the list.
///
/// Mirrors: `typeListGet` in ytype.js
Object? typeListGet(YType<dynamic> type, int index) {
  type.doc ?? warnPrematureAccess();
  final marker = findMarker(type, index);
  var n = type._start;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
  }
  while (n != null) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        return n.content.getContent()[index];
      }
      index -= n.length;
    }
    n = n.right as Item?;
  }
  return null;
}

// ---------------------------------------------------------------------------
// typeListInsertGenericsAfter
// ---------------------------------------------------------------------------

/// Insert [content] after [referenceItem] in [parent].
///
/// Mirrors: `typeListInsertGenericsAfter` in ytype.js
void typeListInsertGenericsAfter(Transaction transaction, YType<dynamic> parent,
    Item? referenceItem, List<Object?> content) {
  var left = referenceItem;
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  // ignore: avoid_dynamic_calls
  final store = doc.store;
  final right =
      referenceItem == null ? parent._start : referenceItem.right as Item?;

  var jsonContent = <Object?>[];

  void packJsonContent() {
    if (jsonContent.isNotEmpty) {
      final newItem = Item(
        id: createID(ownClientId, getState(store, ownClientId)),
        left: left,
        origin: left?.lastId,
        right: right,
        rightOrigin: right?.id,
        parent: parent,
        parentSub: null,
        content: ContentAny(jsonContent),
      );
      newItem.integrate(transaction, 0);
      left = newItem;
      jsonContent = [];
    }
  }

  for (final c in content) {
    if (c == null ||
        c is num ||
        c is bool ||
        c is String ||
        c is Map ||
        c is List) {
      jsonContent.add(c);
    } else {
      packJsonContent();
      if (c is Uint8List) {
        final newItem = Item(
          id: createID(ownClientId, getState(store, ownClientId)),
          left: left,
          origin: left?.lastId,
          right: right,
          rightOrigin: right?.id,
          parent: parent,
          parentSub: null,
          content: ContentBinary(c),
        );
        newItem.integrate(transaction, 0);
        left = newItem;
      } else if (c is YType) {
        final newItem = Item(
          id: createID(ownClientId, getState(store, ownClientId)),
          left: left,
          origin: left?.lastId,
          right: right,
          rightOrigin: right?.id,
          parent: parent,
          parentSub: null,
          content: ContentType(c),
        );
        newItem.integrate(transaction, 0);
        left = newItem;
      } else {
        throw ArgumentError('Unexpected content type: ${c.runtimeType}');
      }
    }
  }
  packJsonContent();
}

// ---------------------------------------------------------------------------
// typeListInsertGenerics
// ---------------------------------------------------------------------------

/// Insert [content] at [index] in [parent].
///
/// Mirrors: `typeListInsertGenerics` in ytype.js
void typeListInsertGenerics(Transaction transaction, YType<dynamic> parent,
    int index, List<Object?> content) {
  if (index > parent._length) {
    throw RangeError('Length exceeded!');
  }
  if (index == 0) {
    if (parent._searchMarker != null) {
      updateMarkerChanges(parent._searchMarker!, index, content.length);
    }
    return typeListInsertGenericsAfter(transaction, parent, null, content);
  }
  final startIndex = index;
  final marker = findMarker(parent, index);
  var n = parent._start;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
    if (index == 0) {
      n = n!.left as Item?;
      index += (n != null && n.countable && !n.deleted) ? n.length : 0;
    }
  }
  while (n != null) {
    if (!n.deleted && n.countable) {
      if (index <= n.length) {
        if (index < n.length) {
          getItemCleanStart(
              transaction, createID(n.id.client, n.id.clock + index));
        }
        break;
      }
      index -= n.length;
    }
    n = n.right as Item?;
  }
  if (parent._searchMarker != null) {
    updateMarkerChanges(parent._searchMarker!, startIndex, content.length);
  }
  return typeListInsertGenericsAfter(transaction, parent, n, content);
}

// ---------------------------------------------------------------------------
// typeListPushGenerics
// ---------------------------------------------------------------------------

/// Push [content] to the end of [parent].
///
/// Mirrors: `typeListPushGenerics` in ytype.js
void typeListPushGenerics(Transaction transaction, YType<dynamic> parent,
    List<Object?> content) {
  final markers = parent._searchMarker ?? [];
  Item? n = parent._start;
  if (markers.isNotEmpty) {
    final maxMarker = markers.reduce(
        (a, b) => a.index > b.index ? a : b);
    n = maxMarker.p;
  }
  if (n != null) {
    while (n!.right != null) {
      n = n.right as Item?;
    }
  }
  return typeListInsertGenericsAfter(transaction, parent, n, content);
}

// ---------------------------------------------------------------------------
// typeListDelete
// ---------------------------------------------------------------------------

/// Delete [length] elements starting at [index] in [parent].
///
/// Mirrors: `typeListDelete` in ytype.js
void typeListDelete(
    Transaction transaction, YType<dynamic> parent, int index, int length) {
  if (length == 0) return;
  final startIndex = index;
  final startLength = length;
  final marker = findMarker(parent, index);
  var n = parent._start;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
  }
  // Find first item to delete
  while (n != null && index > 0) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + index));
      }
      index -= n.length;
    }
    n = n.right as Item?;
  }
  // Delete items
  while (length > 0 && n != null) {
    if (!n.deleted) {
      if (length < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + length));
      }
      n.delete(transaction);
      length -= n.length;
    }
    n = n.right as Item?;
  }
  if (length > 0) {
    throw RangeError('Length exceeded!');
  }
  if (parent._searchMarker != null) {
    updateMarkerChanges(
        parent._searchMarker!, startIndex, -startLength + length);
  }
}

// ---------------------------------------------------------------------------
// typeMapDelete
// ---------------------------------------------------------------------------

/// Delete the entry at [key] in [parent].
///
/// Mirrors: `typeMapDelete` in ytype.js
void typeMapDelete(Transaction transaction, YType<dynamic> parent, String key) {
  final c = parent._map[key];
  if (c != null) {
    c.delete(transaction);
  }
}

// ---------------------------------------------------------------------------
// typeMapSet
// ---------------------------------------------------------------------------

/// Set [key] to [value] in [parent].
///
/// Mirrors: `typeMapSet` in ytype.js
void typeMapSet(
    Transaction transaction, YType<dynamic> parent, String key, Object? value) {
  final left = parent._map[key];
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  // ignore: avoid_dynamic_calls
  final store = doc.store;

  AbstractContent content;
  if (value == null ||
      value is num ||
      value is bool ||
      value is String ||
      value is Map ||
      value is List) {
    content = ContentAny([value]);
  } else if (value is Uint8List) {
    content = ContentBinary(value);
  } else if (value is YType) {
    content = ContentType(value);
  } else {
    throw ArgumentError('Unexpected content type: ${value.runtimeType}');
  }

  final newItem = Item(
    id: createID(ownClientId, getState(store, ownClientId)),
    left: left,
    origin: left?.lastId,
    right: null,
    rightOrigin: null,
    parent: parent,
    parentSub: key,
    content: content,
  );
  newItem.integrate(transaction, 0);
}

// ---------------------------------------------------------------------------
// typeMapGet
// ---------------------------------------------------------------------------

/// Get the value at [key] in [parent].
///
/// Mirrors: `typeMapGet` in ytype.js
Object? typeMapGet(YType<dynamic> parent, String key) {
  parent.doc ?? warnPrematureAccess();
  final val = parent._map[key];
  if (val == null || val.deleted) return null;
  final content = val.content.getContent();
  return content.isNotEmpty ? content[val.length - 1] : null;
}

// ---------------------------------------------------------------------------
// typeMapGetAll
// ---------------------------------------------------------------------------

/// Get all key-value pairs in [parent].
///
/// Mirrors: `typeMapGetAll` in ytype.js
Map<String, Object?> typeMapGetAll(YType<dynamic> parent) {
  parent.doc ?? warnPrematureAccess();
  final res = <String, Object?>{};
  parent._map.forEach((key, value) {
    if (!value.deleted) {
      final content = value.content.getContent();
      res[key] = content.isNotEmpty ? content[value.length - 1] : null;
    }
  });
  return res;
}

// ---------------------------------------------------------------------------
// typeMapHas
// ---------------------------------------------------------------------------

/// Check if [key] exists in [parent].
///
/// Mirrors: `typeMapHas` in ytype.js
bool typeMapHas(YType<dynamic> parent, String key) {
  parent.doc ?? warnPrematureAccess();
  final val = parent._map[key];
  return val != null && !val.deleted;
}

// ---------------------------------------------------------------------------
// typeMapGetSnapshot
// ---------------------------------------------------------------------------

/// Get the value at [key] in [parent] at [snapshot].
///
/// Mirrors: `typeMapGetSnapshot` in ytype.js
Object? typeMapGetSnapshot(
    YType<dynamic> parent, String key, dynamic snapshot) {
  Item? v = parent._map[key];
  // ignore: avoid_dynamic_calls
  final sv = snapshot.sv as Map<int, int>;
  while (v != null &&
      (!sv.containsKey(v.id.client) ||
          v.id.clock >= (sv[v.id.client] ?? 0))) {
    v = v.left as Item?;
  }
  if (v == null) return null;
  // ignore: avoid_dynamic_calls
  final isVis = isVisible(v, snapshot);
  if (!isVis) return null;
  final content = v.content.getContent();
  return content.isNotEmpty ? content[v.length - 1] : null;
}

/// Check if an item is visible in a snapshot.
///
/// Mirrors: `isVisible` in Snapshot.js
bool isVisible(Item item, dynamic snapshot) {
  // ignore: avoid_dynamic_calls
  final sv = snapshot.sv as Map<int, int>;
  // ignore: avoid_dynamic_calls
  final ds = snapshot.ds;
  final clock = sv[item.id.client] ?? 0;
  if (item.id.clock >= clock) return false;
  // ignore: avoid_dynamic_calls
  return !(ds.hasId(item.id) as bool);
}

// ---------------------------------------------------------------------------
// typeMapGetAllSnapshot
// ---------------------------------------------------------------------------

/// Get all key-value pairs in [parent] at [snapshot].
///
/// Mirrors: `typeMapGetAllSnapshot` in ytype.js
Map<String, Object?> typeMapGetAllSnapshot(
    YType<dynamic> parent, dynamic snapshot) {
  final res = <String, Object?>{};
  // ignore: avoid_dynamic_calls
  final sv = snapshot.sv as Map<int, int>;
  parent._map.forEach((key, value) {
    Item? v = value;
    while (v != null &&
        (!sv.containsKey(v.id.client) ||
            v.id.clock >= (sv[v.id.client] ?? 0))) {
      v = v.left as Item?;
    }
    if (v != null && isVisible(v, snapshot)) {
      final content = v.content.getContent();
      res[key] = content.isNotEmpty ? content[v.length - 1] : null;
    }
  });
  return res;
}

// ---------------------------------------------------------------------------
// getTypeChildren
// ---------------------------------------------------------------------------

/// Get all children of [t] as a list.
///
/// Mirrors: `getTypeChildren` in ytype.js
List<Item> getTypeChildren(YType<dynamic> t) {
  t.doc ?? warnPrematureAccess();
  var s = t._start;
  final arr = <Item>[];
  while (s != null) {
    arr.add(s);
    s = s.right as Item?;
  }
  return arr;
}

// ---------------------------------------------------------------------------
// ItemTextListPosition
// ---------------------------------------------------------------------------

/// A position in a text list, tracking left/right items and current attributes.
///
/// Mirrors: `ItemTextListPosition` in ytype.js
class ItemTextListPosition {
  Item? left;
  Item? right;
  int index;
  Map<String, Object?> currentAttributes;

  ItemTextListPosition(this.left, this.right, this.index, this.currentAttributes);

  /// Move forward one item.
  void forward() {
    if (right == null) throw StateError('Cannot forward past end');
    final r = right!;
    if (r.content is ContentFormat) {
      if (!r.deleted) {
        _updateCurrentAttributes(currentAttributes, r.content as ContentFormat);
      }
    } else {
      if (!r.deleted && r.countable) {
        index += r.length;
      }
    }
    left = r;
    right = r.right as Item?;
  }
}

void _updateCurrentAttributes(
    Map<String, Object?> currentAttributes, ContentFormat format) {
  if (format.value == null) {
    currentAttributes.remove(format.key);
  } else {
    currentAttributes[format.key] = format.value;
  }
}

// ---------------------------------------------------------------------------
// insertContent / deleteText helpers
// ---------------------------------------------------------------------------

/// Insert [content] at [currPos] in [parent].
///
/// Mirrors: `insertContent` in ytype.js
void insertContent(Transaction transaction, YType<dynamic> parent,
    ItemTextListPosition currPos, AbstractContent content,
    [Map<String, Object?> attributes = const {}]) {
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  // ignore: avoid_dynamic_calls
  final store = doc.store;
  final left = currPos.left;
  final right = currPos.right;
  if (parent._searchMarker != null) {
    updateMarkerChanges(
        parent._searchMarker!, currPos.index, content.length);
  }
  final newItem = Item(
    id: createID(ownClientId, getState(store, ownClientId)),
    left: left,
    origin: left?.lastId,
    right: right,
    rightOrigin: right?.id,
    parent: parent,
    parentSub: null,
    content: content,
  );
  newItem.integrate(transaction, 0);
  currPos.right = newItem;
  currPos.forward();
}

/// Delete [length] characters at [currPos].
///
/// Mirrors: `deleteText` in ytype.js
ItemTextListPosition deleteText(
    Transaction transaction, ItemTextListPosition currPos, int length) {
  final startLength = length;
  final start = currPos.right;
  while (length > 0 && currPos.right != null) {
    final item = currPos.right!;
    if (!item.deleted && item.countable) {
      if (length < item.length) {
        getItemCleanStart(
            transaction, createID(item.id.client, item.id.clock + length));
      }
      length -= item.length;
      item.delete(transaction);
    }
    currPos.forward();
  }
  if (start != null) {
    cleanupFormattingGap(transaction, start, currPos.right,
        Map.of(currPos.currentAttributes), currPos.currentAttributes);
  }
  final parent = (currPos.left ?? currPos.right)?.parent as YType<dynamic>?;
  if (parent?._searchMarker != null) {
    updateMarkerChanges(
        parent!._searchMarker!, currPos.index, -startLength + length);
  }
  return currPos;
}

// ---------------------------------------------------------------------------
// readYType
// ---------------------------------------------------------------------------

/// Read a YType from [decoder].
///
/// Mirrors: `readYType` in ytype.js
YType<dynamic> readYType(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final typeRef = decoder.readTypeRef() as int;
  // ignore: avoid_dynamic_calls
  final name = (typeRef == typeRefXmlElement || typeRef == typeRefXmlHook)
      ? decoder.readKey() as String
      : null;
  final ytype = YType<YEvent<dynamic>>(name);
  ytype._legacyTypeRef = typeRef;
  return ytype;
}

// ---------------------------------------------------------------------------
// noAttributionsManager stub
// ---------------------------------------------------------------------------

/// A no-op attribution manager.
///
/// Mirrors: `noAttributionsManager` in AttributionManager.js
final noAttributionsManager = _NoAttributionsManager();

class _NoAttributionsManager {
  int contentLength(Item item) {
    if (!item.deleted && item.countable) return item.length;
    return 0;
  }

  void readContent(List<Object?> cs, int client, int clock, bool deleted,
      AbstractContent content, int mode) {
    cs.add(_AttributedContent(client, clock, deleted, content, null, mode != 0));
  }
}

class _AttributedContent {
  final int client;
  final int clock;
  final bool deleted;
  final AbstractContent content;
  final Object? attrs;
  final bool render;

  _AttributedContent(this.client, this.clock, this.deleted, this.content,
      this.attrs, this.render);
}
