/// Dart translation of src/ytype.js
///
/// Mirrors: yjs/src/ytype.js (v14.0.0-22)
///
/// Note: The JS version uses a unified AbstractType class with lib0/delta for all
/// operations. This Dart translation preserves the same unified class while
/// using idiomatic Dart APIs.
library;

import 'dart:convert' show jsonEncode;

import 'dart:typed_data';

import '../lib0/observable.dart';
import '../structs/content.dart';
import '../structs/item.dart';
import '../utils/event_handler.dart';
import '../utils/doc.dart';
import '../utils/id.dart';
import '../utils/struct_store.dart'
    show getState, getItemCleanStart;
import '../utils/transaction.dart'
    hide callEventHandlerListeners;
import '../utils/y_event.dart';
import '../utils/y_structure.dart';

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
// Helper functions
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

/// A search marker for fast position lookup in AbstractType linked lists.
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
ArraySearchMarker? findMarker(AbstractType yarray, int index) {
  if (yarray.yStart == null ||
      index == 0 ||
      yarray.searchMarker == null) {
    return null;
  }
  final markers = yarray.searchMarker!;
  ArraySearchMarker? marker;
  if (markers.isNotEmpty) {
    marker = markers.reduce((a, b) =>
        (index - a.index).abs() < (index - b.index).abs() ? a : b);
  }
  var p = yarray.yStart!;
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
          (yarray.yLength / _maxSearchMarker)) {
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
// AbstractType
// ---------------------------------------------------------------------------

/// Abstract Yjs shared type.
///
/// Mirrors: `AbstractType` in ytype.js
abstract class AbstractType<EventType> extends Observable<EventType> implements YStructure {
  /// The name of this type (for XML element types).
  String? name;

  /// The first item in the linked list of this type's content.
  Item? yStart;

  /// The map of key → item for map-like types.
  final Map<String, Item> yMap = {};

  /// The document this type belongs to.
  Doc? _doc;

  /// The item that contains this type (if it's a nested type).
  Item? yItem;

  /// The length of this type's content.
  int yLength = 0;

  /// Public accessor for the first item in the linked list.
  Item? get start => yStart;

  /// Event handlers.
  final EventHandler<EventType, Transaction> eH = createEventHandler();

  /// Deep event handlers.
  final EventHandler<YEvent<dynamic>, Transaction> dEH =
      createEventHandler();

  /// Search markers for fast position lookup.
  List<ArraySearchMarker>? searchMarker;

  /// Whether this YText contains formatting attributes.
  bool hasFormatting = false;

  /// The legacy type reference ID (for binary serialization).
  int legacyTypeRef = typeRefXmlFragment;

  /// Preliminary delta to apply when integrated (before doc is set).
  Object? prelim;

  AbstractType([this.name]) {
    searchMarker = [];
    legacyTypeRef = name == null ? typeRefXmlFragment : typeRefXmlElement;
  }

  /// The document this type belongs to.
  @override
  Doc? get doc => _doc ?? (yItem?.parent as YStructure?)?.doc;

  /// Set the document this type belongs to.
  set doc(Doc? d) => _doc = d;

  /// The item that contains this type.
  @override
  Item? get item => yItem;

  /// The transaction that is currently changing this structure.
  @override
  Transaction? get transaction => doc?.transaction;

  /// The length of this type's content.
  int get length {
    if (doc == null) warnPrematureAccess();
    return yLength;
  }

  /// Returns the parent type, or null if this is a root type.
  AbstractType<dynamic>? get parent {
    return yItem != null ? yItem!.parent as AbstractType<dynamic>? : null;
  }

  /// Integrate this type into the Yjs instance.
  ///
  /// Mirrors: `integrate` in ytype.js
  void integrate(Doc y, Item? item) {
    _doc = y;
    yItem = item;
    if (prelim != null) {
      // Apply preliminary delta if any
      prelim = null;
    }
  }


  /// Creates YEvent and calls all type observers.
  ///
  /// Mirrors: `callObserver` in ytype.js
  void callObserver(Transaction transaction, Set<String?> parentSubs) {
    final event = YEvent<dynamic>(this, transaction, parentSubs);
    callTypeObservers(this, transaction, event);
    if (!transaction.local && searchMarker != null) {
      searchMarker!.clear();
    }
    if (!transaction.local && hasFormatting) {
      transaction.needFormattingCleanup = true;
    }
  }

  /// Observe changes to this type.
  void Function(EventType, Transaction) observe(
      void Function(EventType event, Transaction tr) f) {
    addEventHandlerListener(eH, f);
    return f;
  }

  /// Stop observing changes to this type.
  void unobserve(void Function(EventType event, Transaction tr) f) {
    removeEventHandlerListener(eH, f);
  }

  /// Observe changes to this type and all nested types.
  void Function(YEvent<dynamic>, Transaction) observeDeep(
      void Function(YEvent<dynamic> event, Transaction tr) f) {
    addEventHandlerListener(dEH, f);
    return f;
  }

  /// Stop observing deep changes.
  void unobserveDeep(
      void Function(YEvent<dynamic> event, Transaction tr) f) {
    removeEventHandlerListener(dEH, f);
  }

  /// Write this type to [encoder].
  ///
  /// Mirrors: `_write` in ytype.js
  void write(dynamic encoder) {
    // ignore: avoid_dynamic_calls
    encoder.writeTypeRef(legacyTypeRef);
    if (legacyTypeRef == typeRefXmlElement ||
        legacyTypeRef == typeRefXmlHook) {
      // ignore: avoid_dynamic_calls
      encoder.writeKey(name ?? '');
    }
  }

  /// Convert this type to JSON.
  Object toJson();

  @override
  String toString();

  /// Creates a copy of this type.
  AbstractType<EventType> clone();



}

// ---------------------------------------------------------------------------
// callTypeObservers
// ---------------------------------------------------------------------------

/// Call event listeners with an event, propagating to parent types.
///
/// Mirrors: `callTypeObservers` in ytype.js
void callTypeObservers(
    AbstractType<dynamic> type, Transaction transaction, YEvent<dynamic> event) {
  final changedParentTypes = transaction.changedParentTypes;
  var t = type;
  while (true) {
    changedParentTypes.putIfAbsent(t, () => []).add(event);
    if (t.yItem == null) break;
    final parent = t.yItem!.parent;
    if (parent is AbstractType) {
      t = parent;
    } else {
      break;
    }
  }
  callEventHandlerListeners(type.eH, event, transaction);
}

// ---------------------------------------------------------------------------
// typeListSlice
// ---------------------------------------------------------------------------

/// Return a slice of the list content from [start] to [end].
///
/// Mirrors: `typeListSlice` in ytype.js
List<Object?> typeListSlice(AbstractType<dynamic> type, int start, int end) {
  type.doc ?? warnPrematureAccess();
  if (start < 0) start = type.yLength + start;
  if (end < 0) end = type.yLength + end;
  var len = end - start;
  final cs = <Object?>[];
  var n = type.yStart;
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
Object? typeListGet(AbstractType<dynamic> type, int index) {
  type.doc ?? warnPrematureAccess();
  final marker = findMarker(type, index);
  var n = type.yStart;
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
void typeListInsertGenericsAfter(Transaction transaction, AbstractType<dynamic> parent,
    Item? referenceItem, List<Object?> content) {
  var left = referenceItem;
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  // ignore: avoid_dynamic_calls
  final store = doc.store;
  final right =
      referenceItem == null ? parent.yStart : referenceItem.right as Item?;

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
      } else if (c is AbstractType) {
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
void typeListInsertGenerics(Transaction transaction, AbstractType<dynamic> parent,
    int index, List<Object?> content) {
  if (index > parent.yLength) {
    throw RangeError('Length exceeded!');
  }
  if (index == 0) {
    if (parent.searchMarker != null) {
      updateMarkerChanges(parent.searchMarker!, index, content.length);
    }
    return typeListInsertGenericsAfter(transaction, parent, null, content);
  }
  final startIndex = index;
  final marker = findMarker(parent, index);
  var n = parent.yStart;
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
  if (parent.searchMarker != null) {
    updateMarkerChanges(parent.searchMarker!, startIndex, content.length);
  }
  return typeListInsertGenericsAfter(transaction, parent, n, content);
}

// ---------------------------------------------------------------------------
// typeListPushGenerics
// ---------------------------------------------------------------------------

/// Push [content] to the end of [parent].
///
/// Mirrors: `typeListPushGenerics` in ytype.js
void typeListPushGenerics(Transaction transaction, AbstractType<dynamic> parent,
    List<Object?> content) {
  final markers = parent.searchMarker ?? [];
  Item? n = parent.yStart;
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
    Transaction transaction, AbstractType<dynamic> parent, int index, int length) {
  if (length == 0) return;
  final startIndex = index;
  final startLength = length;
  final marker = findMarker(parent, index);
  var n = parent.yStart;
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
  if (parent.searchMarker != null) {
    updateMarkerChanges(
        parent.searchMarker!, startIndex, -startLength + length);
  }
}

// ---------------------------------------------------------------------------
// typeMapDelete
// ---------------------------------------------------------------------------

/// Delete the entry at [key] in [parent].
///
/// Mirrors: `typeMapDelete` in ytype.js
void typeMapDelete(Transaction transaction, AbstractType<dynamic> parent, String key) {
  final c = parent.yMap[key];
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
    Transaction transaction, AbstractType<dynamic> parent, String key, Object? value) {
  final left = parent.yMap[key];
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
  } else if (value is AbstractType) {
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
Object? typeMapGet(AbstractType<dynamic> parent, String key) {
  parent.doc ?? warnPrematureAccess();
  final val = parent.yMap[key];
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
Map<String, Object?> typeMapGetAll(AbstractType<dynamic> parent) {
  parent.doc ?? warnPrematureAccess();
  final res = <String, Object?>{};
  parent.yMap.forEach((key, value) {
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
bool typeMapHas(AbstractType<dynamic> parent, String key) {
  parent.doc ?? warnPrematureAccess();
  final val = parent.yMap[key];
  return val != null && !val.deleted;
}

// ---------------------------------------------------------------------------
// typeMapGetSnapshot
// ---------------------------------------------------------------------------

/// Get the value at [key] in [parent] at [snapshot].
///
/// Mirrors: `typeMapGetSnapshot` in ytype.js
Object? typeMapGetSnapshot(
    AbstractType<dynamic> parent, String key, dynamic snapshot) {
  Item? v = parent.yMap[key];
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
    AbstractType<dynamic> parent, dynamic snapshot) {
  final res = <String, Object?>{};
  // ignore: avoid_dynamic_calls
  final sv = snapshot.sv as Map<int, int>;
  parent.yMap.forEach((key, value) {
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
List<Item> getTypeChildren(AbstractType<dynamic> t) {
  t.doc ?? warnPrematureAccess();
  var s = t.yStart;
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

  /// Format [length] items at this position with [attributes].
  ///
  /// Mirrors: `formatText` in ytype.js
  void formatText(Transaction transaction, AbstractType<dynamic> parent,
      int length, Map<String, Object?> attributes) {
    _minimizeAttributeChanges(this, attributes);
    final negatedAttributes = _insertAttributes(transaction, parent, this, attributes);
    // iterate until first non-format or null is found
    while (right != null &&
        (length > 0 ||
            (negatedAttributes.isNotEmpty &&
                ((right!.deleted && right!.countable == false) ||
                    right!.content is ContentFormat)))) {
      if (right!.content is ContentFormat) {
        if (!right!.deleted) {
          final cf = right!.content as ContentFormat;
          final attr = attributes[cf.key];
          if (attributes.containsKey(cf.key)) {
            if (equalAttrs(attr, cf.value)) {
              negatedAttributes.remove(cf.key);
            } else {
              if (length == 0) break;
              negatedAttributes[cf.key] = cf.value;
            }
            right!.delete(transaction);
          } else {
            currentAttributes[cf.key] = cf.value;
          }
        }
      } else {
        if (length < right!.length) {
          getItemCleanStart(
              transaction,
              createID(right!.id.client, right!.id.clock + length));
        }
        length -= right!.length;
      }
      forward();
    }
    if (length > 0) throw StateError('Exceeded content range');
    _insertNegatedAttributes(transaction, parent, this, negatedAttributes);
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

// ---------------------------------------------------------------------------
// Text formatting helpers
// ---------------------------------------------------------------------------



/// Skip forward while the current attributes already match.
///
/// Mirrors: `minimizeAttributeChanges` in ytype.js
void _minimizeAttributeChanges(
    ItemTextListPosition currPos, Map<String, Object?> attributes) {
  while (true) {
    if (currPos.right == null) {
      break;
    } else if (currPos.right!.deleted ||
        (currPos.right!.content is ContentFormat &&
            !currPos.right!.deleted &&
            equalAttrs(
                attributes[(currPos.right!.content as ContentFormat).key],
                (currPos.right!.content as ContentFormat).value))) {
      // skip
    } else {
      break;
    }
    currPos.forward();
  }
}

/// Insert format-start items for [attributes], returning negated attributes.
///
/// Mirrors: `insertAttributes` in ytype.js
Map<String, Object?> _insertAttributes(Transaction transaction,
    AbstractType<dynamic> parent, ItemTextListPosition currPos,
    Map<String, Object?> attributes) {
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  final negatedAttributes = <String, Object?>{};
  for (final entry in attributes.entries) {
    final key = entry.key;
    final val = entry.value;
    final currentVal = currPos.currentAttributes[key];
    if (!equalAttrs(currentVal, val)) {
      negatedAttributes[key] = currentVal;
      final left = currPos.left;
      final right = currPos.right;
      // ignore: avoid_dynamic_calls
      currPos.right = Item(
        id: createID(ownClientId, getState(doc.store, ownClientId)),
        left: left,
        origin: left?.lastId,
        right: right,
        rightOrigin: right?.id,
        parent: parent,
        parentSub: null,
        content: ContentFormat(key, val),
      );
      currPos.right!.integrate(transaction, 0);
      currPos.forward();
    }
  }
  return negatedAttributes;
}

/// Insert format-end items for negated attributes.
///
/// Mirrors: `insertNegatedAttributes` in ytype.js
void _insertNegatedAttributes(Transaction transaction, AbstractType<dynamic> parent,
    ItemTextListPosition currPos, Map<String, Object?> negatedAttributes) {
  // Skip forward past deleted items and matching negated formats
  while (currPos.right != null &&
      (currPos.right!.deleted ||
          (currPos.right!.content is ContentFormat &&
              equalAttrs(
                  negatedAttributes[
                      (currPos.right!.content as ContentFormat).key],
                  (currPos.right!.content as ContentFormat).value)))) {
    if (!currPos.right!.deleted) {
      negatedAttributes
          .remove((currPos.right!.content as ContentFormat).key);
    }
    currPos.forward();
  }
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  negatedAttributes.forEach((key, val) {
    final left = currPos.left;
    final right = currPos.right;
    // ignore: avoid_dynamic_calls
    final nextFormat = Item(
      id: createID(ownClientId, getState(doc.store, ownClientId)),
      left: left,
      origin: left?.lastId,
      right: right,
      rightOrigin: right?.id,
      parent: parent,
      parentSub: null,
      content: ContentFormat(key, val),
    );
    nextFormat.integrate(transaction, 0);
    currPos.right = nextFormat;
    currPos.forward();
  });
}

// ---------------------------------------------------------------------------
// insertContent / deleteText helpers
// ---------------------------------------------------------------------------

/// Insert [content] at [currPos] in [parent] with optional text [attributes].
///
/// Mirrors: `insertContent` in ytype.js
void insertContent(Transaction transaction, AbstractType<dynamic> parent,
    ItemTextListPosition currPos, AbstractContent content,
    [Map<String, Object?> attributes = const {}]) {
  // Add any current attributes that aren't in the provided attributes
  final attrs = Map<String, Object?>.from(attributes);
  currPos.currentAttributes.forEach((key, _) {
    if (!attrs.containsKey(key)) {
      attrs[key] = null;
    }
  });
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final ownClientId = doc.clientID as int;
  // ignore: avoid_dynamic_calls
  final store = doc.store;
  _minimizeAttributeChanges(currPos, attrs);
  final negatedAttributes = _insertAttributes(
      transaction, parent, currPos, attrs);
  final left = currPos.left;
  final right = currPos.right;
  if (parent.searchMarker != null) {
    updateMarkerChanges(
        parent.searchMarker!, currPos.index, content.length);
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
  _insertNegatedAttributes(transaction, parent, currPos, negatedAttributes);
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
  final parent = (currPos.left ?? currPos.right)?.parent as AbstractType<dynamic>?;
  if (parent?.searchMarker != null) {
    updateMarkerChanges(
        parent!.searchMarker!, currPos.index, -startLength + length);
  }
  return currPos;
}

// ---------------------------------------------------------------------------
// readAbstractType
// ---------------------------------------------------------------------------


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
  _AttributedContent(this.client, this.clock, this.deleted, this.content,
      this.attrs, this.render);

  final int client;
  final int clock;
  final bool deleted;
  final AbstractContent content;
  final Object? attrs;
  final bool render;
}
