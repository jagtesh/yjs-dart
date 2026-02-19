/// Dart translation of src/utils/UndoManager.js
///
/// Mirrors: yjs/src/utils/UndoManager.js (v14.0.0-22)
library;

import '../lib0/observable.dart';
import '../structs/gc.dart' show GC;
import '../structs/item.dart' show Item, keepItem;
import '../utils/id.dart' show createID;
import '../utils/id_set.dart'
    show IdSet, mergeIdSets, diffIdSet;
import '../utils/is_parent_of.dart' show isParentOf;
import '../utils/struct_set.dart' show iterateStructsByIdSet;
import '../utils/transaction.dart' show Transaction, transact;
import '../utils/struct_store.dart' show getItemCleanStart;
import '../structs/item.dart' show followRedone, redoItem;
import '../y_type.dart' show YType;

// ---------------------------------------------------------------------------
// StackItem
// ---------------------------------------------------------------------------

/// A single undo/redo stack entry.
///
/// Mirrors: `StackItem` in UndoManager.js
class StackItem {
  /// Insertions captured in this stack item.
  IdSet inserts;

  /// Deletions captured in this stack item.
  IdSet deletes;

  /// Arbitrary metadata (e.g. selection range).
  final Map<Object, Object?> meta = {};

  StackItem(this.inserts, this.deletes);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

void _clearUndoManagerStackItem(
    Transaction tr, UndoManager um, StackItem stackItem) {
  iterateStructsByIdSet(tr, stackItem.deletes, (struct) {
    if (struct is Item &&
        um.scope.any((type) =>
            type == tr.doc ||
            (type is YType && isParentOf(type, struct)))) {
      keepItem(struct, false);
    }
  });
}

StackItem? _popStackItem(
    UndoManager undoManager, List<StackItem> stack, String eventType) {
  Transaction? lastTr;
  final doc = undoManager.doc;
  final scope = undoManager.scope;

  transact<void>(doc, (transaction) {
    while (stack.isNotEmpty && undoManager.currStackItem == null) {
      final store = (transaction.doc as dynamic).store;
      final stackItem = stack.removeLast();
      final itemsToRedo = <Item>{};
      final itemsToDelete = <Item>[];
      var performedChange = false;

      iterateStructsByIdSet(transaction, stackItem.inserts, (struct) {
        if (struct is Item) {
          var s = struct;
          if (s.redone != null) {
            final result = followRedone(store, s.id);
            var item = result.item;
            final diff = result.diff;
            s = item;
            if (diff > 0) {
              s = getItemCleanStart(
                transaction, createID(item.id.client, item.id.clock + diff))
                as Item;
            }
          }
          if (!s.deleted &&
              scope.any((type) =>
                  type == transaction.doc ||
                  (type is YType && isParentOf(type, s)))) {
            itemsToDelete.add(s);
          }
        }
      });

      iterateStructsByIdSet(transaction, stackItem.deletes, (struct) {
        if (struct is Item &&
            scope.any((type) =>
                type == transaction.doc ||
                (type is YType && isParentOf(type, struct))) &&
            !stackItem.inserts.hasId(struct.id)) {
          itemsToRedo.add(struct);
        }
      });

      for (final struct in itemsToRedo) {
        final result = redoItem(transaction, struct, itemsToRedo,
            stackItem.inserts, undoManager.ignoreRemoteMapChanges, undoManager);
        if (result != null) performedChange = true;
      }

      // Delete in reverse order so children are deleted before parents
      for (var i = itemsToDelete.length - 1; i >= 0; i--) {
        final item = itemsToDelete[i];
        if (undoManager.deleteFilter(item)) {
          item.delete(transaction);
          performedChange = true;
        }
      }

      undoManager.currStackItem = performedChange ? stackItem : null;
    }

    // Destroy search markers for changed types
    transaction.changed.forEach((subProps, type) {
      if (subProps.contains(null) as bool) {
        // ignore: avoid_dynamic_calls
        final searchMarker = (type as dynamic).searchMarker;
        if (searchMarker != null) {
          // ignore: avoid_dynamic_calls
          (searchMarker as dynamic).length = 0;
        }
      }
    });
    lastTr = transaction;
  }, undoManager);

  final res = undoManager.currStackItem;
  if (res != null && lastTr != null) {
    undoManager.emit('stack-item-popped', [
      {
        'stackItem': res,
        'type': eventType,
        'changedParentTypes': lastTr!.changedParentTypes,
        'origin': undoManager,
      },
      undoManager,
    ]);
    undoManager.currStackItem = null;
  }
  return res;
}

// ---------------------------------------------------------------------------
// UndoManager
// ---------------------------------------------------------------------------

/// Options for [UndoManager].
class UndoManagerOpts {
  /// Capture timeout in milliseconds (default: 500).
  final int captureTimeout;

  /// Filter function for transactions (return false to skip).
  final bool Function(Transaction tr) captureTransaction;

  /// Delete filter for items.
  final bool Function(dynamic item) deleteFilter;

  /// Tracked origins.
  final Set<Object?> trackedOrigins;

  /// Whether to ignore remote map changes.
  final bool ignoreRemoteMapChanges;

  UndoManagerOpts({
    this.captureTimeout = 500,
    bool Function(Transaction)? captureTransaction,
    bool Function(dynamic)? deleteFilter,
    Set<Object?>? trackedOrigins,
    this.ignoreRemoteMapChanges = false,
  })  : captureTransaction = captureTransaction ?? ((_) => true),
        deleteFilter = deleteFilter ?? ((_) => true),
        trackedOrigins = trackedOrigins ?? {null};
}

/// Manages undo/redo history for Yjs types.
///
/// Mirrors: `UndoManager` in UndoManager.js
class UndoManager extends Observable<String> {
  /// The document this manager operates on.
  final dynamic doc;

  /// The types being tracked.
  final List<dynamic> scope = [];

  /// Undo stack.
  List<StackItem> undoStack = [];

  /// Redo stack.
  List<StackItem> redoStack = [];

  /// Whether we are currently undoing.
  bool undoing = false;

  /// Whether we are currently redoing.
  bool redoing = false;

  /// The currently active stack item (during undo/redo).
  StackItem? currStackItem;

  /// Timestamp of the last change.
  int lastChange = 0;

  final int captureTimeout;
  final bool Function(Transaction) captureTransaction;
  final bool Function(dynamic) deleteFilter;
  final Set<Object?> trackedOrigins;
  final bool ignoreRemoteMapChanges;

  late final void Function(dynamic, [dynamic]) afterTransactionHandler;

  UndoManager(
    dynamic typeScope, [
    UndoManagerOpts? opts,
  ])  : doc = _resolveDoc(typeScope),
        captureTimeout = opts?.captureTimeout ?? 500,
        captureTransaction = opts?.captureTransaction ?? ((_) => true),
        deleteFilter = opts?.deleteFilter ?? ((_) => true),
        trackedOrigins = opts?.trackedOrigins ?? {null},
        ignoreRemoteMapChanges = opts?.ignoreRemoteMapChanges ?? false {
    trackedOrigins.add(this);
    addToScope(typeScope);

    afterTransactionHandler = (dynamic transactionArg, [dynamic _]) {
      final transaction = transactionArg as Transaction;
      if (!captureTransaction(transaction) ||
          !scope.any((type) =>
              transaction.changedParentTypes.containsKey(type) ||
              type == doc) ||
          (!trackedOrigins.contains(transaction.origin) &&
              (transaction.origin == null ||
                  !trackedOrigins.contains(
                      transaction.origin.runtimeType)))) {
        return;
      }

      final isUndoing = undoing;
      final isRedoing = redoing;
      final stack = isUndoing ? redoStack : undoStack;

      if (isUndoing) {
        stopCapturing();
      } else if (!isRedoing) {
        clear(false, true);
      }

      final insertions = transaction.insertSet;
      final now = DateTime.now().millisecondsSinceEpoch;
      var didAdd = false;

      if (lastChange > 0 &&
          now - lastChange < captureTimeout &&
          stack.isNotEmpty &&
          !isUndoing &&
          !isRedoing) {
        // Append to last stack item
        final lastOp = stack.last;
        lastOp.deletes =
            mergeIdSets([lastOp.deletes, transaction.deleteSet]);
        lastOp.inserts = mergeIdSets([lastOp.inserts, insertions]);
      } else {
        stack.add(StackItem(insertions, transaction.deleteSet));
        didAdd = true;
      }

      if (!isUndoing && !isRedoing) {
        lastChange = now;
      }

      // Keep deleted structs from being GC'd
      iterateStructsByIdSet(transaction, transaction.deleteSet, (item) {
        if (item is Item &&
            scope.any((type) =>
                type == transaction.doc ||
                (type is YType && isParentOf(type, item)))) {
          keepItem(item, true);
        }
      });

      final changeEvent = [
        {
          'stackItem': stack.last,
          'origin': transaction.origin,
          'type': isUndoing ? 'redo' : 'undo',
          'changedParentTypes': transaction.changedParentTypes,
        },
        this,
      ];
      if (didAdd) {
        emit('stack-item-added', changeEvent);
      } else {
        emit('stack-item-updated', changeEvent);
      }
    };

    // ignore: avoid_dynamic_calls
    doc.on('afterTransaction', afterTransactionHandler);
    // ignore: avoid_dynamic_calls
    doc.on('destroy', (_) => destroy());
  }

  static dynamic _resolveDoc(dynamic typeScope) {
    if (typeScope is List) {
      // ignore: avoid_dynamic_calls
      return (typeScope.first as dynamic).doc;
    }
    // ignore: avoid_dynamic_calls
    if ((typeScope as dynamic).runtimeType.toString() == 'Doc') {
      return typeScope;
    }
    // ignore: avoid_dynamic_calls
    return typeScope.doc;
  }

  /// Extend the scope with additional types.
  ///
  /// Mirrors: `addToScope` in UndoManager.js
  void addToScope(dynamic ytypes) {
    final tmpSet = Set.of(scope);
    final list = ytypes is List ? ytypes : [ytypes];
    for (final ytype in list) {
      if (!tmpSet.contains(ytype)) {
        tmpSet.add(ytype);
        scope.add(ytype);
      }
    }
  }

  /// Add a tracked origin.
  void addTrackedOrigin(Object? origin) => trackedOrigins.add(origin);

  /// Remove a tracked origin.
  void removeTrackedOrigin(Object? origin) => trackedOrigins.remove(origin);

  /// Stop capturing (force a new stack entry on next change).
  ///
  /// Mirrors: `stopCapturing` in UndoManager.js
  void stopCapturing() => lastChange = 0;

  /// Whether undo is available.
  bool canUndo() => undoStack.isNotEmpty;

  /// Whether redo is available.
  bool canRedo() => redoStack.isNotEmpty;

  /// Clear the undo/redo stacks.
  ///
  /// Mirrors: `clear` in UndoManager.js
  void clear([bool clearUndoStack = true, bool clearRedoStack = true]) {
    if ((clearUndoStack && canUndo()) || (clearRedoStack && canRedo())) {
      transact<void>(doc, (tr) {
        if (clearUndoStack) {
          for (final item in undoStack) {
            _clearUndoManagerStackItem(tr, this, item);
          }
          undoStack = [];
        }
        if (clearRedoStack) {
          for (final item in redoStack) {
            _clearUndoManagerStackItem(tr, this, item);
          }
          redoStack = [];
        }
        emit('stack-cleared', [
          {
            'undoStackCleared': clearUndoStack,
            'redoStackCleared': clearRedoStack,
          }
        ]);
      });
    }
  }

  /// Undo the last change.
  ///
  /// Mirrors: `undo` in UndoManager.js
  StackItem? undo() {
    undoing = true;
    try {
      return _popStackItem(this, undoStack, 'undo');
    } finally {
      undoing = false;
    }
  }

  /// Redo the last undone change.
  ///
  /// Mirrors: `redo` in UndoManager.js
  StackItem? redo() {
    redoing = true;
    try {
      return _popStackItem(this, redoStack, 'redo');
    } finally {
      redoing = false;
    }
  }

  @override
  void destroy() {
    trackedOrigins.remove(this);
    // ignore: avoid_dynamic_calls
    doc.off('afterTransaction', afterTransactionHandler);
    super.destroy();
  }
}

/// Undo a set of content IDs on [ydoc].
///
/// Mirrors: `undoContentIds` in UndoManager.js
void undoContentIds(dynamic ydoc, dynamic contentIds) {
  final um = UndoManager(ydoc);
  // ignore: avoid_dynamic_calls
  final inserts = contentIds.inserts as IdSet;
  // ignore: avoid_dynamic_calls
  final deletes = contentIds.deletes as IdSet;
  um.undoStack.add(StackItem(
    diffIdSet(inserts, deletes),
    diffIdSet(deletes, inserts),
  ));
  um.undo();
}
