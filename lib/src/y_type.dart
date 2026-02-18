/// Dart translation of src/ytype.js (structural stub)
///
/// Mirrors: yjs/src/ytype.js (v14.0.0-22)
/// Note: ytype.js is 64KB and contains YMap, YArray, YText, YXmlElement,
/// YXmlFragment, YXmlText, YXmlHook. This file provides the base YType class
/// and type stubs. Full implementations will be added in subsequent iterations.
library;

import 'utils/event_handler.dart';
import 'utils/id.dart';
import 'utils/y_event.dart';
import 'utils/transaction.dart';
import 'structs/item.dart';

/// Abstract base class for all Yjs shared types.
///
/// Mirrors: `YType` in ytype.js
abstract class YType<EventType extends YEvent<dynamic>> {
  /// The first item in the linked list of this type's content.
  Item? start;

  /// The map of key → item for map-like types.
  final Map<String, Item> map = {};

  /// The document this type belongs to.
  dynamic doc; // Doc - avoids circular import

  /// The item that contains this type (if it's a nested type).
  Item? _item;

  /// The event handler for this type.
  final EventHandler<EventType, Transaction> _eH = createEventHandler();

  /// The event handler for deep observers.
  final EventHandler<List<YEvent<dynamic>>, Transaction> _dEH =
      createEventHandler();

  /// Observe changes to this type.
  void observe(void Function(EventType event, Transaction tr) f) {
    addEventHandlerListener(_eH, f);
  }

  /// Stop observing changes to this type.
  void unobserve(void Function(EventType event, Transaction tr) f) {
    removeEventHandlerListener(_eH, f);
  }

  /// Observe changes to this type and all nested types.
  void observeDeep(
      void Function(List<YEvent<dynamic>> events, Transaction tr) f) {
    addEventHandlerListener(_dEH, f);
  }

  /// Stop observing deep changes.
  void unobserveDeep(
      void Function(List<YEvent<dynamic>> events, Transaction tr) f) {
    removeEventHandlerListener(_dEH, f);
  }

  /// Returns the parent type, or null if this is a root type.
  YType<dynamic>? get parent {
    final item = _item;
    if (item == null) return null;
    final p = item.parent;
    if (p is YType) return p;
    return null;
  }

  /// Returns the ID of the item that contains this type.
  ID? get _itemId => _item?.id;

  /// Public accessor for the item that contains this type.
  Item? get item => _item;

  /// Convert this type to JSON.
  Object? toJson();

  /// Returns the number of elements in this type.
  int get length;

  /// Called when this type is integrated into a document.
  void integrate(dynamic doc, Item? item) {
    this.doc = doc;
    _item = item;
  }

  /// Returns a copy of this type.
  YType<EventType> copy();
}

// ─── Type reference numbers ───────────────────────────────────────────────────

const int typeRefArray = 0;
const int typeRefMap = 1;
const int typeRefText = 2;
const int typeRefXmlElement = 3;
const int typeRefXmlFragment = 4;
const int typeRefXmlHook = 5;
const int typeRefXmlText = 6;
