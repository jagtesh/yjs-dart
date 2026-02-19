/// Dart translation of src/structs/Item.js
///
/// Mirrors: yjs/src/structs/Item.js (v14.0.0-22)
library;

import 'dart:convert' show jsonEncode;

import '../structs/abstract_struct.dart';
import '../structs/content.dart' show ContentType;
import '../structs/gc.dart';
import '../utils/id.dart';
import '../utils/id_set.dart' hide findIndexSS;
import '../types/utils.dart' show readYType;
import '../utils/transaction.dart';
import '../utils/struct_store.dart'
    show getState, getItem, getItemCleanStart, getItemCleanEnd, addStructToStore, findIndexSS;

// ---------------------------------------------------------------------------
// Binary bit constants (mirrors lib0/binary.js)
// ---------------------------------------------------------------------------

const int _bit1 = 1;       // keep
const int _bit2 = 2;       // countable
const int _bit3 = 4;       // deleted
const int _bit4 = 8;       // marker (fast-search)
const int _bit6 = 32;      // parentSub present
const int _bit7 = 64;      // rightOrigin present
const int _bit8 = 128;     // origin present
const int _bits5 = 31;     // lower 5 bits (content ref)

// ---------------------------------------------------------------------------
// AbstractContent
// ---------------------------------------------------------------------------

/// The content interface that all Content* classes implement.
///
/// Mirrors: `AbstractContent` in Item.js
abstract class AbstractContent {
  int get length;
  bool isCountable();
  List<Object?> getContent();
  AbstractContent copy();
  AbstractContent splice(int offset);
  bool mergeWith(AbstractContent right);
  void integrate(Transaction transaction, Item item);
  void delete(Transaction transaction);
  void gc(dynamic store);
  void write(dynamic encoder, int offset);
  int getRef();
}

// ---------------------------------------------------------------------------
// Top-level helper functions (mirrors Item.js exports)
// ---------------------------------------------------------------------------

/// Follow the redone chain from [id] until we reach the final item.
///
/// Mirrors: `followRedone` in Item.js
({Item item, int diff}) followRedone(dynamic store, ID id) {
  ID? nextID = id;
  var diff = 0;
  late Item item;
  do {
    if (diff > 0) {
      nextID = createID(nextID!.client, nextID.clock + diff);
    }
    // ignore: avoid_dynamic_calls
    item = getItem(store, nextID!) as Item;
    diff = nextID.clock - item.id.clock;
    nextID = item.redone;
  } while (nextID != null);
  return (item: item, diff: diff);
}

/// Make sure that neither [item] nor any of its parents is ever deleted.
///
/// Mirrors: `keepItem` in Item.js
void keepItem(Item? item, bool keep) {
  while (item != null && item.keep != keep) {
    item.keep = keep;
    // ignore: avoid_dynamic_calls
    final parentItem = (item.parent as dynamic)?.yItem as Item?;
    item = parentItem;
  }
}

/// Split [leftItem] into two items at [diff].
///
/// Mirrors: `splitItem` in Item.js
Item splitItem(Transaction? transaction, Item leftItem, int diff) {
  final client = leftItem.id.client;
  final clock = leftItem.id.clock;
  final rightItem = Item(
    id: createID(client, clock + diff),
    left: leftItem,
    origin: createID(client, clock + diff - 1),
    right: leftItem.right,
    rightOrigin: leftItem.rightOrigin,
    parent: leftItem.parent,
    parentSub: leftItem.parentSub,
    content: leftItem.content.splice(diff),
  );
  if (leftItem.deleted) {
    rightItem.markDeleted();
  }
  if (leftItem.keep) {
    rightItem.keep = true;
  }
  if (leftItem.redone != null) {
    rightItem.redone = createID(leftItem.redone!.client, leftItem.redone!.clock + diff);
  }
  if (transaction != null) {
    leftItem.right = rightItem;
    if (rightItem.right != null) {
      (rightItem.right as Item).left = rightItem;
    }
    transaction.mergeStructs.add(rightItem);
    if (rightItem.parentSub != null && rightItem.right == null) {
      // ignore: avoid_dynamic_calls
      (rightItem.parent as dynamic).yMap[rightItem.parentSub] = rightItem;
    }
  } else {
    rightItem.left = null;
    rightItem.right = null;
  }
  leftItem.length = diff;
  return rightItem;
}

/// Split [leftStruct] into two structs at [diff].
///
/// Mirrors: `splitStruct` in Item.js
AbstractStruct splitStruct(Transaction? transaction, AbstractStruct leftStruct, int diff) {
  if (leftStruct is Item) {
    return splitItem(transaction, leftStruct, diff);
  } else {
    final rightItem = leftStruct.splice(diff);
    transaction?.mergeStructs.add(rightItem);
    return rightItem;
  }
}

/// Check if [id] is deleted by any item in [stack].
///
/// Mirrors: `isDeletedByUndoStack` in Item.js
bool isDeletedByUndoStack(List<dynamic> stack, ID id) {
  // ignore: avoid_dynamic_calls
  return stack.any((s) => (s.deletes as IdSet).hasId(id));
}

/// Redo the effect of [item].
///
/// Mirrors: `redoItem` in Item.js
Item? redoItem(
  Transaction transaction,
  Item item,
  Set<Item> redoitems,
  IdSet itemsToDelete,
  bool ignoreRemoteMapChanges,
  dynamic um, // UndoManager
) {
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final store = doc.store;
  // ignore: avoid_dynamic_calls
  final ownClientID = doc.clientID as int;
  final redone = item.redone;
  if (redone != null) {
    return getItemCleanStart(transaction, redone) as Item?;
  }
  // ignore: avoid_dynamic_calls
  Item? parentItem = (item.parent as dynamic)?.yItem as Item?;
  Item? left;
  Item? right;

  if (parentItem != null && parentItem.deleted) {
    if (parentItem.redone == null &&
        (!redoitems.contains(parentItem) ||
            redoItem(transaction, parentItem, redoitems, itemsToDelete, ignoreRemoteMapChanges, um) == null)) {
      return null;
    }
    while (parentItem!.redone != null) {
      parentItem = getItemCleanStart(transaction, parentItem.redone!) as Item?;
    }
  }

  // ignore: avoid_dynamic_calls
  final parentType = parentItem == null
      ? item.parent
      : (parentItem.content as dynamic).type;

  if (item.parentSub == null) {
    left = item.left as Item?;
    right = item;
    while (left != null) {
      Item? leftTrace = left;
      // ignore: avoid_dynamic_calls
      while (leftTrace != null && (leftTrace.parent as dynamic)?.yItem != parentItem) {
        leftTrace = leftTrace.redone == null ? null : getItemCleanStart(transaction, leftTrace.redone!) as Item?;
      }
      // ignore: avoid_dynamic_calls
      if (leftTrace != null && (leftTrace.parent as dynamic)?.yItem == parentItem) {
        left = leftTrace;
        break;
      }
      left = left.left as Item?;
    }
    while (right != null) {
      Item? rightTrace = right;
      // ignore: avoid_dynamic_calls
      while (rightTrace != null && (rightTrace.parent as dynamic)?.yItem != parentItem) {
        rightTrace = rightTrace.redone == null ? null : getItemCleanStart(transaction, rightTrace.redone!) as Item?;
      }
      // ignore: avoid_dynamic_calls
      if (rightTrace != null && (rightTrace.parent as dynamic)?.yItem == parentItem) {
        right = rightTrace;
        break;
      }
      right = right.right as Item?;
    }
  } else {
    right = null;
    if (item.right != null && !ignoreRemoteMapChanges) {
      left = item;
      // ignore: avoid_dynamic_calls
      final undoStack = um.undoStack as List<dynamic>;
      // ignore: avoid_dynamic_calls
      final redoStack = um.redoStack as List<dynamic>;
      while (left != null &&
          left.right != null &&
          ((left.right as Item?)?.redone != null ||
              itemsToDelete.hasId((left.right as Item).id) ||
              isDeletedByUndoStack(undoStack, (left.right as Item).id) ||
              isDeletedByUndoStack(redoStack, (left.right as Item).id))) {
        left = left.right as Item?;
        while (left?.redone != null) {
          left = getItemCleanStart(transaction, left!.redone!) as Item?;
        }
      }
      if (left != null && left.right != null) {
        return null;
      }
    } else {
      // ignore: avoid_dynamic_calls
      left = (parentType as dynamic).yMap[item.parentSub] as Item?;
    }
  }

  // ignore: avoid_dynamic_calls
  final nextClock = getState(store, ownClientID);
  final nextId = createID(ownClientID, nextClock);
  final redoneItem = Item(
    id: nextId,
    left: left,
    origin: left?.lastId,
    right: right,
    rightOrigin: right?.id,
    parent: parentType,
    parentSub: item.parentSub,
    content: item.content.copy(),
  );
  item.redone = nextId;
  keepItem(redoneItem, true);
  redoneItem.integrate(transaction, 0);
  return redoneItem;
}

// ---------------------------------------------------------------------------
// Item
// ---------------------------------------------------------------------------

/// A CRDT item — the fundamental unit of Yjs.
///
/// Items form a doubly-linked list within each type.
///
/// Mirrors: `Item` in Item.js
class Item extends AbstractStruct {
  /// The item that was originally to the left of this item (origin).
  ID? origin;

  /// The item that is currently to the left of this item.
  AbstractStruct? left;

  /// The item that is currently to the right of this item.
  AbstractStruct? right;

  /// The item that was originally to the right of this item.
  ID? rightOrigin;

  /// The parent type this item belongs to (YType | ID | null).
  Object? parent;

  /// The key in the parent map (for map-like types), or null for sequences.
  String? parentSub;

  /// If this item's effect is redone, this refers to the redo item's ID.
  ID? redone;

  /// The content of this item.
  AbstractContent content;

  /// Bitmask: bit1=keep, bit2=countable, bit3=deleted, bit4=marker.
  int info;

  Item({
    required ID id,
    this.left,
    this.origin,
    this.right,
    this.rightOrigin,
    this.parent,
    this.parentSub,
    required this.content,
  })  : info = content.isCountable() ? _bit2 : 0,
        super(id, content.length);

  // ── Bit-flag accessors ──────────────────────────────────────────────────

  bool get marker => (info & _bit4) > 0;
  set marker(bool isMarked) {
    if (marker != isMarked) info ^= _bit4;
  }

  bool get keep => (info & _bit1) > 0;
  set keep(bool doKeep) {
    if (keep != doKeep) info ^= _bit1;
  }

  bool get countable => (info & _bit2) > 0;

  @override
  bool get deleted => (info & _bit3) > 0;
  set deleted(bool doDelete) {
    if (deleted != doDelete) info ^= _bit3;
  }

  void markDeleted() {
    info |= _bit3;
  }

  // ── Computed properties ─────────────────────────────────────────────────

  /// The last ID covered by this item.
  ID get lastId =>
      length == 1 ? id : createID(id.client, id.clock + length - 1);

  /// The next non-deleted item to the right.
  Item? get next {
    var n = right;
    while (n != null && n.deleted) {
      n = (n as Item).right;
    }
    return n as Item?;
  }

  /// The previous non-deleted item to the left.
  Item? get prev {
    var n = left;
    while (n != null && n.deleted) {
      n = (n as Item).left;
    }
    return n as Item?;
  }

  // ── getMissing ──────────────────────────────────────────────────────────

  /// Return the clientID of a missing dependency, or null if all are present.
  ///
  /// Also resolves origin/rightOrigin/parent references when all deps are met.
  ///
  /// Mirrors: `getMissing` in Item.js
  int? getMissing(Transaction transaction, dynamic store) {
    if (origin != null && (origin!.clock >= getState(store, origin!.client) || ((store as dynamic).skips.hasId(origin!) as bool))) {
      return origin!.client;
    }
    if (rightOrigin != null && (rightOrigin!.clock >= getState(store, rightOrigin!.client) || ((store as dynamic).skips.hasId(rightOrigin!) as bool))) {
      return rightOrigin!.client;
    }
    if (parent != null && parent is ID) {
      final parentId = parent as ID;
      if (parentId.clock >= getState(store, parentId.client) || ((store as dynamic).skips.hasId(parentId) as bool)) {
        return parentId.client;
      }
    }
    // All dependencies present — resolve references
    if (origin != null) {
      left = getItemCleanEnd(transaction, store, origin!) as AbstractStruct;
      origin = (left as Item).lastId;
    }
    if (rightOrigin != null) {
      right = getItemCleanStart(transaction, rightOrigin!) as AbstractStruct;
      rightOrigin = right!.id;
    }
    if ((left != null && left is GC) || (right != null && right is GC)) {
      parent = null;
    } else if (parent == null) {
      if (left != null && left is Item) {
        parent = (left as Item).parent;
        parentSub = (left as Item).parentSub;
      } else if (right != null && right is Item) {
        parent = (right as Item).parent;
        parentSub = (right as Item).parentSub;
      }
    } else if (parent is ID) {
      final parentItem = getItem(store as dynamic, parent as ID);
      if (parentItem is GC) {
        parent = null;
      } else {
        if (parentItem is Item) {
          final content = parentItem.content;
          parent = content is ContentType ? content.type : content;
        }
      }
    }
    return null;
  }

  // ── integrate ───────────────────────────────────────────────────────────

  /// Integrate this item into the document.
  ///
  /// Mirrors: `integrate` in Item.js
  @override
  void integrate(dynamic transaction, int offset) {
    final tr = transaction as Transaction;
    if (offset > 0) {
      id = createID(id.client, id.clock + offset);
      left = getItemCleanEnd(tr, tr.doc.store, createID(id.client, id.clock - 1)) as AbstractStruct;
      origin = (left as Item).lastId;
      content = content.splice(offset);
      length -= offset;
    }

    if (parent != null) {
      if ((left == null && (right == null || (right as Item?)?.left != null)) ||
          (left != null && (left as Item).right != right)) {
        AbstractStruct? o;
        var leftPtr = left as Item?;

        if (leftPtr != null) {
          o = leftPtr.right;
        } else if (parentSub != null) {
          // ignore: avoid_dynamic_calls
          o = (parent as dynamic).yMap[parentSub] as AbstractStruct?;
          while (o != null && (o as Item?)?.left != null) {
            o = (o as Item).left;
          }
        } else {
          // ignore: avoid_dynamic_calls
          o = (parent as dynamic).yStart as AbstractStruct?;
        }

        final conflictingItems = <Item>{};
        final itemsBeforeOrigin = <Item>{};

        while (o != null && o != right) {
          final oItem = o as Item;
          itemsBeforeOrigin.add(oItem);
          conflictingItems.add(oItem);
          if (compareIDs(origin, oItem.origin)) {
            // case 1
            if (oItem.id.client < id.client) {
              leftPtr = oItem;
              conflictingItems.clear();
            } else if (compareIDs(rightOrigin, oItem.rightOrigin)) {
              break;
            }
          } else if (oItem.origin != null &&
              itemsBeforeOrigin.contains(getItem(tr.doc.store, oItem.origin!))) {
            // case 2
            if (!conflictingItems.contains(getItem(tr.doc.store, oItem.origin!))) {
              leftPtr = oItem;
              conflictingItems.clear();
            }
          } else {
            break;
          }
          o = oItem.right;
        }
        left = leftPtr;
      }

      // Reconnect left/right + update parent map/start
      if (left != null) {
        final r = (left as Item).right;
        right = r;
        (left as Item).right = this;
      } else {
        AbstractStruct? r;
        if (parentSub != null) {
          // ignore: avoid_dynamic_calls
          r = (parent as dynamic).yMap[parentSub] as AbstractStruct?;
          while (r != null && (r as Item?)?.left != null) {
            r = (r as Item).left;
          }
        } else {
          // ignore: avoid_dynamic_calls
          r = (parent as dynamic).yStart as AbstractStruct?;
          // ignore: avoid_dynamic_calls
          (parent as dynamic).yStart = this;
        }
        right = r;
      }

      if (right != null) {
        (right as Item).left = this;
      } else if (parentSub != null) {
        // ignore: avoid_dynamic_calls
        (parent as dynamic).yMap[parentSub] = this;
        if (left != null) {
          (left as Item).delete(tr);
        }
      }

      // Adjust parent length
      if (parentSub == null && countable && !deleted) {
        // ignore: avoid_dynamic_calls
        (parent as dynamic).yLength += length;
      }

      addToIdSet(tr.insertSet, id.client, id.clock, length);
      addStructToStore(tr.doc.store, this);
      content.integrate(tr, this);
      addChangedTypeToTransaction(tr, parent as dynamic, parentSub);

      // ignore: avoid_dynamic_calls
      final parentItemDeleted = (parent as dynamic)?.yItem?.deleted == true;
      if (parentItemDeleted || (parentSub != null && right != null)) {
        delete(tr);
      }
    } else {
      // Parent is not defined — integrate as GC
      GC(id, length).integrate(tr, 0);
    }
  }

  // ── delete ──────────────────────────────────────────────────────────────

  /// Mark this item as deleted.
  ///
  /// Mirrors: `delete` in Item.js
  void delete(Transaction transaction) {
    if (!deleted) {
      final p = parent as dynamic;
      if (countable && parentSub == null) {
        // ignore: avoid_dynamic_calls
        p.yLength -= length;
      }
      markDeleted();
      addToIdSet(transaction.deleteSet, id.client, id.clock, length);
      addChangedTypeToTransaction(transaction, p, parentSub);
      content.delete(transaction);
    }
  }

  // ── gc ──────────────────────────────────────────────────────────────────

  /// Garbage-collect this item.
  ///
  /// Mirrors: `gc` in Item.js
  void gc(dynamic store, bool parentGCd) {
    if (!deleted) throw StateError('gc called on non-deleted item');
    content.gc(store);
    if (parentGCd) {
      // Replace this item with a GC in the struct store
      final structs = (store as dynamic).clients[id.client] as List<AbstractStruct>?;
      if (structs != null) {
        final index = findIndexSS(structs, id.clock);
        structs[index] = GC(id, length);
      }
    } else {
      content = _ContentDeleted(length);
    }
  }

  // ── write ───────────────────────────────────────────────────────────────

  /// Serialize this item to [encoder].
  ///
  /// Mirrors: `write` in Item.js
  @override
  void write(dynamic encoder, int offset, [int encodingRef = 0]) {
    final originToWrite = offset > 0
        ? createID(id.client, id.clock + offset - 1)
        : origin;
    final writeInfo = (content.getRef() & _bits5) |
        (originToWrite == null ? 0 : _bit8) |
        (rightOrigin == null ? 0 : _bit7) |
        (parentSub == null ? 0 : _bit6);
    // ignore: avoid_dynamic_calls
    encoder.writeInfo(writeInfo);
    if (originToWrite != null) {
      // ignore: avoid_dynamic_calls
      encoder.writeLeftID(originToWrite);
    }
    if (rightOrigin != null) {
      // ignore: avoid_dynamic_calls
      encoder.writeRightID(rightOrigin!);
    }
    if (originToWrite == null && rightOrigin == null) {
      final p = parent;
      if (p != null) {
        // ignore: avoid_dynamic_calls
        final parentItemDyn = (p as dynamic).yItem;
        if (parentItemDyn == null) {
          // ignore: avoid_dynamic_calls
          final ykey = findRootTypeKeyImpl(p);
          // ignore: avoid_dynamic_calls
          encoder.writeParentInfo(true);
          // ignore: avoid_dynamic_calls
          encoder.writeString(ykey);
        } else if (parentItemDyn is Item) {
          // ignore: avoid_dynamic_calls
          encoder.writeParentInfo(false);
          // ignore: avoid_dynamic_calls
          encoder.writeLeftID(parentItemDyn.id);
        }
      } else if (p is String) {
        // ignore: avoid_dynamic_calls
        encoder.writeParentInfo(true);
        // ignore: avoid_dynamic_calls
        encoder.writeString(p);
      } else if (p is ID) {
        // ignore: avoid_dynamic_calls
        encoder.writeParentInfo(false);
        // ignore: avoid_dynamic_calls
        encoder.writeLeftID(p);
      }
      if (parentSub != null) {
        // ignore: avoid_dynamic_calls
        encoder.writeString(parentSub!);
      }
    }
    content.write(encoder, offset);
  }

  // ── mergeWith ───────────────────────────────────────────────────────────

  /// Try to merge [right] into this item.
  ///
  /// Mirrors: `mergeWith` in Item.js
  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! Item) return false;
    if (runtimeType != right.runtimeType ||
        !compareIDs(right.origin, lastId) ||
        this.right != right ||
        !compareIDs(rightOrigin, right.rightOrigin) ||
        id.client != right.id.client ||
        id.clock + length != right.id.clock ||
        deleted != right.deleted ||
        redone != null ||
        right.redone != null ||
        content.runtimeType != right.content.runtimeType ||
        !content.mergeWith(right.content)) {
      return false;
    }
    // ignore: avoid_dynamic_calls
    final searchMarker = (parent as dynamic)?.searchMarker as List<dynamic>?;
    if (searchMarker != null) {
      for (final marker in searchMarker) {
        // ignore: avoid_dynamic_calls
        if (marker.p == right) {
          // ignore: avoid_dynamic_calls
          marker.p = this;
          if (!deleted && countable) {
            // ignore: avoid_dynamic_calls
            marker.index -= length;
          }
        }
      }
    }
    if (right.keep) keep = true;
    this.right = right.right;
    if (this.right != null) {
      (this.right as Item).left = this;
    }
    length += right.length;
    return true;
  }

  // ── splice ──────────────────────────────────────────────────────────────

  @override
  Item splice(int diff) => splitItem(null, this, diff);
}

// ---------------------------------------------------------------------------
// Internal placeholder for ContentDeleted (avoids circular import)
// ---------------------------------------------------------------------------

/// Minimal ContentDeleted used by gc() — the real one is in content.dart.
class _ContentDeleted implements AbstractContent {
  @override
  final int length;
  _ContentDeleted(this.length);
  @override bool isCountable() => false;
  @override List<Object?> getContent() => [];
  @override AbstractContent copy() => _ContentDeleted(length);
  @override AbstractContent splice(int offset) => _ContentDeleted(length - offset);
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction transaction, Item item) {
    // Mirrors: ContentDeleted.integrate in ContentDeleted.js
    addToIdSet(transaction.deleteSet, item.id.client, item.id.clock, length);
    item.markDeleted();
  }
  @override void delete(Transaction transaction) {}
  @override void gc(dynamic store) {}

  @override
  void write(dynamic encoder, int offset) {
    // Mirrors: ContentDeleted.write(encoder, offset, offsetEnd) = encoder.writeLen(len - offset - offsetEnd)
    // In Dart we only pass offset; offsetEnd is handled by Item.write's clock slicing above,
    // and for non-sliced writes offsetEnd = 0. So: writeLen(length - offset).
    // ignore: avoid_dynamic_calls
    encoder.writeLen(length - offset);
  }
  @override int getRef() => 1;
}

// ---------------------------------------------------------------------------
// Null-safety helper
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// readItemContent + contentRefs lookup table
// ---------------------------------------------------------------------------

/// Read item content from [decoder] using [info] to select the reader.
///
/// Mirrors: `readItemContent` in Item.js
AbstractContent readItemContent(dynamic decoder, int info) {
  return contentRefs[info & _bits5](decoder);
}

/// Lookup table for content readers, indexed by content ref number.
///
/// Mirrors: `contentRefs` in Item.js
final List<AbstractContent Function(dynamic)> contentRefs = [
  (_) => throw StateError('contentRefs[0]: GC is not ItemContent'), // 0
  readContentDeleted,   // 1
  readContentJSON,      // 2
  readContentBinary,    // 3
  readContentString,    // 4
  readContentEmbed,     // 5
  readContentFormat,    // 6
  readContentType,      // 7
  readContentAny,       // 8
  readContentDoc,       // 9
  (_) => throw StateError('contentRefs[10]: Skip is not ItemContent'), // 10
];

// ---------------------------------------------------------------------------
// Content reader stubs — real implementations are in content.dart.
// These are forward-declared here so item.dart can reference them;
// content.dart will override them via the contentRefs list at startup.
// ---------------------------------------------------------------------------

/// Read a deleted content block from [decoder].
AbstractContent readContentDeleted(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return _ContentDeleted(decoder.readLen() as int);
}

/// Read JSON content from [decoder].
AbstractContent readContentJSON(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final len = decoder.readLen() as int;
  final arr = <Object?>[];
  for (var i = 0; i < len; i++) {
    // ignore: avoid_dynamic_calls
    arr.add(decoder.readJSON());
  }
  return _ContentJSONStub(arr);
}

/// Read binary content from [decoder].
AbstractContent readContentBinary(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return _ContentBinaryStub(decoder.readBuf());
}

/// Read string content from [decoder].
AbstractContent readContentString(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return _ContentStringStub(decoder.readString() as String);
}

/// Read embed content from [decoder].
AbstractContent readContentEmbed(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return _ContentEmbedStub(decoder.readJSON());
}

/// Read format content from [decoder].
AbstractContent readContentFormat(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final key = decoder.readKey() as String;
  // ignore: avoid_dynamic_calls
  final value = decoder.readJSON();
  return _ContentFormatStub(key, value);
}

/// Read type content from [decoder].
/// Creates a real ContentType wrapping a real YType.
///
/// Mirrors: `readContentType` in ContentType.js
AbstractContent readContentType(dynamic decoder) {
  return ContentType(readYType(decoder));
}

/// Read any content from [decoder].
AbstractContent readContentAny(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final len = decoder.readLen() as int;
  final arr = <Object?>[];
  for (var i = 0; i < len; i++) {
    // ignore: avoid_dynamic_calls
    arr.add(decoder.readAny());
  }
  return _ContentAnyStub(arr);
}

/// Read doc content from [decoder].
AbstractContent readContentDoc(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  return _ContentDocStub(decoder.readAny());
}

// ---------------------------------------------------------------------------
// Minimal content stubs for the reader functions above.
// These are replaced by the real implementations from content.dart
// via the contentRefs list when the library is initialized.
// ---------------------------------------------------------------------------

class _ContentJSONStub implements AbstractContent {
  final List<Object?> arr;
  _ContentJSONStub(this.arr);
  @override int get length => arr.length;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => arr;
  @override AbstractContent copy() => _ContentJSONStub(List.of(arr));
  @override AbstractContent splice(int offset) => _ContentJSONStub(arr.sublist(offset));
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentJSON.write
    final len = arr.length - offset;
    // ignore: avoid_dynamic_calls
    encoder.writeLen(len);
    for (var i = offset; i < arr.length; i++) {
      final c = arr[i];
      // ignore: avoid_dynamic_calls
      encoder.writeString(c == null ? 'undefined' : jsonEncode(c));
    }
  }
  @override int getRef() => 2;
}

class _ContentBinaryStub implements AbstractContent {
  final dynamic buf;
  _ContentBinaryStub(this.buf);
  @override int get length => 1;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => [buf];
  @override AbstractContent copy() => _ContentBinaryStub(buf);
  @override AbstractContent splice(int offset) => _ContentBinaryStub(buf);
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentBinary.write
    // ignore: avoid_dynamic_calls
    encoder.writeBuffer(buf);
  }
  @override int getRef() => 3;
}

class _ContentStringStub implements AbstractContent {
  String str;
  _ContentStringStub(this.str);
  @override int get length => str.length;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => str.split('');
  @override AbstractContent copy() => _ContentStringStub(str);
  @override AbstractContent splice(int offset) => _ContentStringStub(str.substring(offset));
  @override bool mergeWith(AbstractContent right) {
    if (right is _ContentStringStub) {
      str = str + right.str;
      return true;
    }
    return false;
  }
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentString.write
    // ignore: avoid_dynamic_calls
    encoder.writeString(str.substring(offset));
  }
  @override int getRef() => 4;
}

class _ContentEmbedStub implements AbstractContent {
  final Object? embed;
  _ContentEmbedStub(this.embed);
  @override int get length => 1;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => [embed];
  @override AbstractContent copy() => _ContentEmbedStub(embed);
  @override AbstractContent splice(int offset) => _ContentEmbedStub(embed);
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentEmbed.write
    // ignore: avoid_dynamic_calls
    encoder.writeJSON(embed);
  }
  @override int getRef() => 5;
}

class _ContentFormatStub implements AbstractContent {
  final String key;
  final Object? value;
  _ContentFormatStub(this.key, this.value);
  @override int get length => 1;
  @override bool isCountable() => false;
  @override List<Object?> getContent() => [value];
  @override AbstractContent copy() => _ContentFormatStub(key, value);
  @override AbstractContent splice(int offset) => _ContentFormatStub(key, value);
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentFormat.write
    // ignore: avoid_dynamic_calls
    encoder.writeKey(key);
    // ignore: avoid_dynamic_calls
    encoder.writeJSON(value);
  }
  @override int getRef() => 6;
}



class _ContentAnyStub implements AbstractContent {
  List<Object?> arr;
  _ContentAnyStub(this.arr);
  @override int get length => arr.length;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => arr;
  @override AbstractContent copy() => _ContentAnyStub(List.of(arr));
  @override AbstractContent splice(int offset) {
    final right = _ContentAnyStub(arr.sublist(offset));
    arr = arr.sublist(0, offset);
    return right;
  }
  @override bool mergeWith(AbstractContent right) {
    if (right is _ContentAnyStub) {
      arr.addAll(right.arr);
      return true;
    }
    return false;
  }
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentAny.write
    final len = arr.length - offset;
    // ignore: avoid_dynamic_calls
    encoder.writeLen(len);
    for (var i = offset; i < arr.length; i++) {
      // ignore: avoid_dynamic_calls
      encoder.writeAny(arr[i]);
    }
  }
  @override int getRef() => 8;
}

class _ContentDocStub implements AbstractContent {
  final Object? doc;
  _ContentDocStub(this.doc);
  @override int get length => 1;
  @override bool isCountable() => true;
  @override List<Object?> getContent() => [doc];
  @override AbstractContent copy() => _ContentDocStub(doc);
  @override AbstractContent splice(int offset) => _ContentDocStub(doc);
  @override bool mergeWith(AbstractContent right) => false;
  @override void integrate(Transaction t, Item i) {}
  @override void delete(Transaction t) {}
  @override void gc(dynamic s) {}
  @override void write(dynamic encoder, int offset) {
    // Mirrors: ContentDoc.write
    // ignore: avoid_dynamic_calls
    encoder.writeAny(doc);
  }
  @override int getRef() => 9;
}

// ---------------------------------------------------------------------------
// findRootTypeKey — stub (real implementation in y_type.dart)
// ---------------------------------------------------------------------------

/// Find the root key for a YType in its parent document.
/// This is a stub — the real implementation is provided by y_type.dart
/// and registered via [setFindRootTypeKey].
///
/// Mirrors: `findRootTypeKey` in types/AbstractType.js
String Function(dynamic) _findRootTypeKeyFn = (type) {
  // ignore: avoid_dynamic_calls
  final doc = (type as dynamic).doc;
  if (doc == null) throw StateError('Type is not integrated into a document');
  // ignore: avoid_dynamic_calls
  for (final entry in (doc.share as Map).entries) {
    if (entry.value == type) return entry.key as String;
  }
  throw StateError('Type not found in document share map');
};

/// Find the root key for [type] in its document.
String findRootTypeKeyImpl(dynamic type) => _findRootTypeKeyFn(type);

/// Register a custom [findRootTypeKey] implementation (called from y_type.dart).
void setFindRootTypeKey(String Function(dynamic) fn) {
  _findRootTypeKeyFn = fn;
}
