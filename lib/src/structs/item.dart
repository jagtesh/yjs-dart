/// Dart translation of src/structs/Item.js (structural stub)
///
/// Mirrors: yjs/src/structs/Item.js (v14.0.0-22)
/// Note: Item.js is 24KB and is the core CRDT item. This is a structural
/// stub - full integration logic will be completed in subsequent iterations.
library;

import '../structs/abstract_struct.dart';
import '../utils/id.dart';
import '../utils/update_encoder.dart';
import '../utils/transaction.dart';

/// The content interface that all Content* classes implement.
abstract class AbstractContent {
  int get length;
  bool get countable;
  bool get isDeleted;
  List<Object?> getContent();
  AbstractContent copy();
  void integrate(Transaction transaction, Item item);
  void delete(Transaction transaction);
  void gc(dynamic store);
  void write(AbstractUpdateEncoder encoder, int offset);
  int getRef();
}

/// A CRDT item - the fundamental unit of Yjs.
///
/// Items form a doubly-linked list within each type.
///
/// Mirrors: `Item` in Item.js
class Item extends AbstractStruct {
  /// The item to the left of this item.
  Item? left;

  /// The ID of the item that was to the left when this item was created.
  final ID? leftOrigin;

  /// The item to the right of this item.
  Item? right;

  /// The ID of the item that was to the right when this item was created.
  final ID? rightOrigin;

  /// The parent type this item belongs to.
  Object? parent; // YType | null

  /// The key in the parent map (for map-like types), or null for sequence types.
  String? parentSub;

  /// The content of this item.
  AbstractContent content;

  /// Whether this item has been deleted.
  bool _deleted = false;

  /// Whether this item should be kept (not GC'd) even if deleted.
  bool keep = false;

  /// Whether this item is countable (contributes to length).
  bool get countable => content.countable;

  Item({
    required ID id,
    required int length,
    this.left,
    this.leftOrigin,
    this.right,
    this.rightOrigin,
    this.parent,
    this.parentSub,
    required this.content,
  }) : super(id, length);

  @override
  bool get deleted => _deleted;

  /// Mark this item as deleted.
  void delete(Transaction transaction) {
    if (!_deleted) {
      _deleted = true;
      // TODO: full deletion logic (update delete set, notify observers)
    }
  }

  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! Item) return false;
    if (rightOrigin != right.rightOrigin ||
        !compareIDs(right.leftOrigin, id) ||
        right.parentSub != null ||
        _deleted != right._deleted) {
      return false;
    }
    // TODO: content merging
    length += right.length;
    return true;
  }

  @override
  void integrate(Transaction transaction, int offset) {
    // TODO: full CRDT integration algorithm (conflict resolution)
    content.integrate(transaction, this);
  }

  @override
  void write(AbstractUpdateEncoder encoder, int offset, int encodingRef) {
    // TODO: full write logic
  }

  @override
  Item splice(int diff) {
    // TODO: full splice logic
    throw UnimplementedError('Item.splice not yet implemented');
  }
}
