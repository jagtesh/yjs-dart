/// Dart translation of src/utils/Transaction.js
///
/// Mirrors: yjs/src/utils/Transaction.js (v14.0.0-22)
library;

import '../lib0/encoding.dart' as encoding;
import '../lib0/random.dart' as random;
import '../structs/abstract_struct.dart';
import '../structs/content.dart' show ContentFormat;
import '../structs/gc.dart';
import '../structs/item.dart';
import '../utils/id.dart';
import '../utils/id_set.dart' hide findIndexSS;
import '../utils/struct_store.dart';
import '../utils/update_encoder.dart';
import '../utils/y_event.dart' show YEvent;
import '../y_type.dart' show YType;

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------

/// A transaction groups changes to a Yjs document.
///
/// Mirrors: `Transaction` in Transaction.js
class Transaction {
  /// The Yjs document.
  final dynamic doc; // Doc — avoids circular import

  /// Describes the set of deleted items by IDs.
  final IdSet deleteSet = createIdSet();

  /// Describes the set of items that are cleaned up / deleted by IDs.
  /// It is a subset of [deleteSet].
  final IdSet cleanUps = createIdSet();

  /// Describes the set of inserted items by IDs.
  final IdSet insertSet = createIdSet();

  /// Holds the state before the transaction started (lazy).
  Map<int, int>? _beforeState;

  /// Holds the state after the transaction (lazy, only valid after _done).
  Map<int, int>? _afterState;

  /// All types that were directly modified.
  /// Maps from type to parentSubs (`null` for YArray).
  // ignore: avoid_dynamic_calls
  final Map<dynamic, Set<String?>> changed = {};

  /// Stores the events for types that observe child elements (observeDeep).
  // ignore: avoid_dynamic_calls
  final Map<dynamic, List<dynamic>> changedParentTypes = {};

  /// Structs that should be merged after the transaction.
  final List<AbstractStruct> mergeStructs = [];

  /// The origin of this transaction.
  final Object? origin;

  /// Stores meta information on the transaction.
  final Map<Object, Object?> meta = {};

  /// Whether this change originates from this doc.
  bool local;

  /// Sub-documents added in this transaction.
  final Set<dynamic> subdocsAdded = {};

  /// Sub-documents removed in this transaction.
  final Set<dynamic> subdocsRemoved = {};

  /// Sub-documents loaded in this transaction.
  final Set<dynamic> subdocsLoaded = {};

  /// Whether a YText formatting cleanup is needed after this transaction.
  bool needFormattingCleanup = false;

  /// Whether this transaction has been finalized.
  bool _done = false;

  Transaction(this.doc, this.origin, this.local);

  /// Holds the state before the transaction started.
  ///
  /// Mirrors: `beforeState` getter in Transaction.js
  Map<int, int> get beforeState {
    if (_beforeState == null) {
      // ignore: avoid_dynamic_calls
      final sv = Map<int, int>.from(getStateVector(doc.store as StructStore));
      insertSet.clients.forEach((client, ranges) {
        final ids = ranges.getIds();
        if (ids.isNotEmpty) {
          sv[client] = ids[0].clock;
        }
      });
      _beforeState = sv;
    }
    return _beforeState!;
  }

  /// Holds the state after the transaction.
  ///
  /// Mirrors: `afterState` getter in Transaction.js
  Map<int, int> get afterState {
    if (!_done) throw StateError('afterState called before transaction is done');
    if (_afterState == null) {
      // ignore: avoid_dynamic_calls
      final sv = Map<int, int>.from(getStateVector(doc.store as StructStore));
      insertSet.clients.forEach((client, ranges) {
        final ids = ranges.getIds();
        if (ids.isNotEmpty) {
          final d = ids[ids.length - 1];
          sv[client] = d.clock + d.len;
        }
      });
      _afterState = sv;
    }
    return _afterState!;
  }
}

// ---------------------------------------------------------------------------
// writeUpdateMessageFromTransaction
// ---------------------------------------------------------------------------

/// Write an update message from a transaction to [encoder].
/// Returns true if data was written.
///
/// Mirrors: `writeUpdateMessageFromTransaction` in Transaction.js
bool writeUpdateMessageFromTransaction(
    AbstractUpdateEncoder encoder, Transaction transaction) {
  if (transaction.deleteSet.clients.isEmpty &&
      transaction.insertSet.clients.isEmpty) {
    return false;
  }
  writeStructsFromTransaction(encoder, transaction);
  writeIdSet(encoder, transaction.deleteSet);
  return true;
}

/// Write structs from [transaction] to [encoder].
///
/// Mirrors: `writeStructsFromTransaction` in encoding.js
void writeStructsFromTransaction(
    AbstractUpdateEncoder encoder, Transaction transaction) {
  writeClientsStructs(encoder, transaction.doc.store as StructStore,
      transaction.beforeState);
}

/// Write all client structs newer than [sv] to [encoder].
///
/// Mirrors: `writeClientsStructs` in encoding.js
void writeClientsStructs(
    AbstractUpdateEncoder encoder, StructStore store, Map<int, int> sv) {
  // Write number of clients
  final clients = <int>[];
  store.clients.forEach((client, structs) {
    final clock = sv[client] ?? 0;
    if (getState(store, client) > clock) {
      clients.add(client);
    }
  });
  encoding.writeVarUint(encoder.restEncoder, clients.length);
  clients.sort();
  for (final client in clients) {
    final structs = store.clients[client]!;
    final startClock = sv[client] ?? 0;
    final startIndex = findIndexSS(structs, startClock);
    final len = structs.length - startIndex;
    encoding.writeVarUint(encoder.restEncoder, len);
    encoding.writeVarUint(encoder.restEncoder, client);
    encoding.writeVarUint(encoder.restEncoder, startClock);
    for (var i = startIndex; i < structs.length; i++) {
      structs[i].write(encoder, i == startIndex ? startClock - structs[i].id.clock : 0);
    }
  }
}

// ---------------------------------------------------------------------------
// nextID
// ---------------------------------------------------------------------------

/// Get the next ID for this transaction's document.
///
/// Mirrors: `nextID` in Transaction.js
ID nextID(Transaction transaction) {
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  return createID(doc.clientID as int, getState(doc.store, doc.clientID as int));
}

// ---------------------------------------------------------------------------
// addChangedTypeToTransaction
// ---------------------------------------------------------------------------

/// Add a changed type to the transaction.
///
/// If `type.parent` was added in current transaction, `type` technically
/// did not change, it was just added and we should not fire events for `type`.
///
/// Mirrors: `addChangedTypeToTransaction` in Transaction.js
void addChangedTypeToTransaction(
    Transaction transaction, dynamic type, String? parentSub) {
  // ignore: avoid_dynamic_calls
  final item = type.yItem as Item?;
  if (item == null ||
      (!item.deleted && !transaction.insertSet.hasId(item.id))) {
    transaction.changed.putIfAbsent(type, () => <String?>{}).add(parentSub);
  }
}

// ---------------------------------------------------------------------------
// tryToMergeWithLefts (private)
// ---------------------------------------------------------------------------

/// Try to merge structs at [pos] with their left neighbors.
/// Returns the number of merged structs.
///
/// Mirrors: `tryToMergeWithLefts` in Transaction.js
int _tryToMergeWithLefts(List<AbstractStruct> structs, int pos) {
  if (pos <= 0 || pos >= structs.length) return 0;
  var right = structs[pos];
  var left = structs[pos - 1];
  var i = pos;
  while (i > 0) {
    if (left.deleted == right.deleted &&
        left.runtimeType == right.runtimeType) {
      if (left.mergeWith(right)) {
        // If right was in a parent map, update the map to point to left
        if (right is Item &&
            right.parentSub != null &&
            (right.parent as dynamic)?.yMap[right.parentSub] == right) {
          // ignore: avoid_dynamic_calls
          (right.parent as dynamic).yMap[right.parentSub] = left;
        }
        i--;
        if (i > 0) {
          right = left;
          left = structs[i - 1];
        }
        continue;
      }
    }
    break;
  }
  final merged = pos - i;
  if (merged > 0) {
    structs.removeRange(pos + 1 - merged, pos + 1);
  }
  return merged;
}

// ---------------------------------------------------------------------------
// tryGcDeleteSet (private)
// ---------------------------------------------------------------------------

/// GC deleted items in [ds].
///
/// Mirrors: `tryGcDeleteSet` in Transaction.js
void _tryGcDeleteSet(
    Transaction tr, IdSet ds, bool Function(dynamic) gcFilter) {
  ds.clients.forEach((client, deleteItems_) {
    final deleteItems = deleteItems_.getIds();
    final structs = tr.doc.store.clients[client] as List<AbstractStruct>?;
    if (structs == null) return;
    for (var di = deleteItems.length - 1; di >= 0; di--) {
      final deleteItem = deleteItems[di];
      final endDeleteItemClock = deleteItem.clock + deleteItem.len;
      var si = findIndexSS(structs, deleteItem.clock);
      while (si < structs.length) {
        final struct = structs[si];
        if (struct.id.clock >= endDeleteItemClock) break;
        if (struct is Item &&
            struct.deleted &&
            !struct.keep &&
            gcFilter(struct)) {
          struct.gc(tr.doc.store, false);
        }
        si++;
      }
    }
  });
}

// ---------------------------------------------------------------------------
// tryMerge (private)
// ---------------------------------------------------------------------------

/// Try to merge deleted/GC'd items in [ds].
///
/// Mirrors: `tryMerge` in Transaction.js
void _tryMerge(IdSet ds, dynamic store) {
  ds.clients.forEach((client, deleteItems_) {
    final deleteItems = deleteItems_.getIds();
    final structs = (store as dynamic).clients[client] as List<AbstractStruct>?;
    if (structs == null) return;
    for (var di = deleteItems.length - 1; di >= 0; di--) {
      final deleteItem = deleteItems[di];
      final mostRightIndexToCheck = (structs.length - 1)
          .clamp(0, 1 + findIndexSS(structs, deleteItem.clock + deleteItem.len - 1));
      var si = mostRightIndexToCheck;
      while (si > 0 && structs[si].id.clock >= deleteItem.clock) {
        si -= 1 + _tryToMergeWithLefts(structs, si);
      }
    }
  });
}

// ---------------------------------------------------------------------------
// tryGc (exported)
// ---------------------------------------------------------------------------

/// GC and merge items in [idset].
///
/// Mirrors: `tryGc` in Transaction.js
void tryGc(Transaction tr, IdSet idset, bool Function(dynamic) gcFilter) {
  _tryGcDeleteSet(tr, idset, gcFilter);
  _tryMerge(idset, tr.doc.store);
}

// ---------------------------------------------------------------------------
// cleanupFormattingGap
// ---------------------------------------------------------------------------

/// Clean up formatting items in a gap between [start] and [curr].
/// Returns the number of formatting items deleted.
///
/// Mirrors: `cleanupFormattingGap` in Transaction.js
int cleanupFormattingGap(
  Transaction transaction,
  Item start,
  Item? curr,
  Map<String, Object?> startAttributes,
  Map<String, Object?> currAttributes,
) {
  // ignore: avoid_dynamic_calls
  if (transaction.doc.cleanupFormatting != true) return 0;
  Item? end = start;
  final endFormats = <String, ContentFormat>{};
  while (end != null && (!end.countable || end.deleted)) {
    if (!end.deleted && end.content is ContentFormat) {
      final cf = end.content as ContentFormat;
      endFormats[cf.key] = cf;
    }
    end = end.right as Item?;
  }
  var cleanups = 0;
  var reachedCurr = false;
  Item? s = start;
  while (s != null && s != end) {
    if (curr == s) reachedCurr = true;
    if (!s.deleted) {
      final content = s.content;
      if (content is ContentFormat) {
        final key = content.key;
        final value = content.value;
        final startAttrValue = startAttributes[key];
        if (endFormats[key] != content || startAttrValue == value) {
          s.delete(transaction);
          transaction.cleanUps.add(s.id.client, s.id.clock, s.length);
          cleanups++;
          if (!reachedCurr &&
              (currAttributes[key]) == value &&
              startAttrValue != value) {
            if (startAttrValue == null) {
              currAttributes.remove(key);
            } else {
              currAttributes[key] = startAttrValue;
            }
          }
        }
        if (!reachedCurr && !s.deleted) {
          _updateCurrentAttributes(currAttributes, content);
        }
      }
    }
    s = s.right as Item?;
  }
  return cleanups;
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
// cleanupYTextFormatting
// ---------------------------------------------------------------------------

/// Clean up all formatting attributes in a YText type.
/// Returns the number of formatting items deleted.
///
/// Mirrors: `cleanupYTextFormatting` in Transaction.js
int cleanupYTextFormatting(dynamic type) {
  // ignore: avoid_dynamic_calls
  if (type.doc?.cleanupFormatting != true) return 0;
  var res = 0;
  // ignore: avoid_dynamic_calls
  transact(type.doc, (transaction) {
    // ignore: avoid_dynamic_calls
    Item? start = type.yStart as Item?;
    Item? end = start;
    var startAttributes = <String, Object?>{};
    final currentAttributes = <String, Object?>{};
    while (end != null) {
      if (!end.deleted) {
        if (end.content is ContentFormat) {
          _updateCurrentAttributes(
              currentAttributes, end.content as ContentFormat);
        } else {
          res += cleanupFormattingGap(
              transaction, start!, end, startAttributes, currentAttributes);
          startAttributes = Map.of(currentAttributes);
          start = end;
        }
      }
      end = end.right as Item?;
    }
  });
  return res;
}

// ---------------------------------------------------------------------------
// cleanupYTextAfterTransaction
// ---------------------------------------------------------------------------

/// Clean up formatting after a transaction that may have inserted/deleted
/// formatting items.
///
/// Mirrors: `cleanupYTextAfterTransaction` in Transaction.js
void cleanupYTextAfterTransaction(Transaction transaction) {
  final needFullCleanup = <dynamic>{};
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // Check if a formatting item was inserted
  _iterateStructsByIdSet(transaction, transaction.insertSet, (item) {
    if (!item.deleted &&
        item is Item &&
        item.content is ContentFormat) {
      needFullCleanup.add(item.parent);
    }
  });
  // Cleanup in a new transaction
  transact(doc, (t) {
    _iterateStructsByIdSet(transaction, transaction.deleteSet, (item) {
      if (item is GC) return;
      // ignore: avoid_dynamic_calls
      final hasFormatting = (item as Item).parent != null &&
          ((item.parent as dynamic)?.hasFormatting == true);
      if (!hasFormatting || needFullCleanup.contains(item.parent)) return;
      if (item.content is ContentFormat) {
        needFullCleanup.add(item.parent);
      } else {
        _cleanupContextlessFormattingGap(t, item);
      }
    });
    for (final yText in needFullCleanup) {
      cleanupYTextFormatting(yText);
    }
  });
}

void _cleanupContextlessFormattingGap(Transaction transaction, Item? item) {
  // ignore: avoid_dynamic_calls
  if (transaction.doc.cleanupFormatting != true) return;
  while (item != null &&
      item.right != null &&
      ((item.right as Item?)?.deleted == true ||
          (item.right as Item?)?.countable == false)) {
    item = item.right as Item?;
  }
  final attrs = <String>{};
  while (item != null && (item.deleted || !item.countable)) {
    if (!item.deleted && item.content is ContentFormat) {
      final key = (item.content as ContentFormat).key;
      if (attrs.contains(key)) {
        item.delete(transaction);
        transaction.cleanUps.add(item.id.client, item.id.clock, item.length);
      } else {
        attrs.add(key);
      }
    }
    item = item.left as Item?;
  }
}

// ---------------------------------------------------------------------------
// _iterateStructsByIdSet (private helper)
// ---------------------------------------------------------------------------

void _iterateStructsByIdSet(
    Transaction transaction, IdSet idSet, void Function(AbstractStruct) f) {
  // ignore: avoid_dynamic_calls
  final store = transaction.doc.store as StructStore;
  idSet.clients.forEach((client, ranges_) {
    final ranges = ranges_.getIds();
    final structs = store.clients[client];
    if (structs == null) return;
    for (final range in ranges) {
      var si = findIndexSS(structs, range.clock);
      final endClock = range.clock + range.len;
      while (si < structs.length && structs[si].id.clock < endClock) {
        f(structs[si]);
        si++;
      }
    }
  });
}

// ---------------------------------------------------------------------------
// cleanupTransactions (private)
// ---------------------------------------------------------------------------

void _cleanupTransactions(List<Transaction> transactionCleanups, int i) {
  if (i >= transactionCleanups.length) return;
  final transaction = transactionCleanups[i];
  transaction._done = true;
  // ignore: avoid_dynamic_calls
  final doc = transaction.doc;
  // ignore: avoid_dynamic_calls
  final store = doc.store as StructStore;
  final ds = transaction.deleteSet;
  final mergeStructs = transaction.mergeStructs;

  try {
    // ignore: avoid_dynamic_calls
    doc.emit('beforeObserverCalls', [transaction, doc]);
    final fs = <void Function()>[];

    // Observe events on changed types
    transaction.changed.forEach((itemtype, subs) {
      fs.add(() {
        // ignore: avoid_dynamic_calls
        final typeItem = itemtype.yItem as Item?;
        if (typeItem == null || !typeItem.deleted) {
          // ignore: avoid_dynamic_calls
          itemtype.callObserver(transaction, subs);
        }
      });
    });

    fs.add(() {
      // Deep observe events
      transaction.changedParentTypes.forEach((type, events) {
        // ignore: avoid_dynamic_calls
        final dEH = type.dEH;
        // ignore: avoid_dynamic_calls
        final dEHLen = (dEH.l as List).length;
        // ignore: avoid_dynamic_calls
        final typeItem = type.yItem as Item?;
        if (dEHLen > 0 && (typeItem == null || !typeItem.deleted)) {
          // Find event whose target matches this type, or create a fallback
          // ignore: avoid_dynamic_calls
          final deepEvent = events.cast<YEvent<dynamic>>().firstWhere(
            (e) => e.target == type,
            orElse: () => YEvent(type as YType, transaction, {null}),
          );
          // ignore: avoid_dynamic_calls
          callEventHandlerListeners(dEH, deepEvent, transaction);
        }
      });
    });

    fs.add(() {
      // ignore: avoid_dynamic_calls
      doc.emit('afterTransaction', [transaction, doc]);
    });

    // Call all fs, even if some throw
    _callAll(fs);

    if (transaction.needFormattingCleanup &&
        // ignore: avoid_dynamic_calls
        doc.cleanupFormatting == true) {
      cleanupYTextAfterTransaction(transaction);
    }
  } finally {
    // GC deleted items
    // ignore: avoid_dynamic_calls
    if (doc.gc == true) {
      // ignore: avoid_dynamic_calls
      _tryGcDeleteSet(transaction, ds, doc.gcFilter as bool Function(dynamic));
    }
    _tryMerge(ds, store);

    // Merge inserted structs
    transaction.insertSet.clients.forEach((client, ids_) {
      final ids = ids_.getIds();
      if (ids.isEmpty) return;
      final firstClock = ids[0].clock;
      final structs = store.clients[client];
      if (structs == null) return;
      final firstChangePos = findIndexSS(structs, firstClock).clamp(1, structs.length);
      for (var j = structs.length - 1; j >= firstChangePos;) {
        j -= 1 + _tryToMergeWithLefts(structs, j);
      }
    });

    // Merge mergeStructs
    for (var j = mergeStructs.length - 1; j >= 0; j--) {
      final id = mergeStructs[j].id;
      final structs = store.clients[id.client];
      if (structs == null) continue;
      final replacedStructPos = findIndexSS(structs, id.clock);
      if (replacedStructPos + 1 < structs.length) {
        if (_tryToMergeWithLefts(structs, replacedStructPos + 1) > 1) {
          continue;
        }
      }
      if (replacedStructPos > 0) {
        _tryToMergeWithLefts(structs, replacedStructPos);
      }
    }

    // Check for client ID collision
    // ignore: avoid_dynamic_calls
    if (!transaction.local &&
        transaction.insertSet.clients.containsKey(doc.clientID)) {
      // ignore: avoid_dynamic_calls
      doc.clientID = generateNewClientId();
    }

    // ignore: avoid_dynamic_calls
    doc.emit('afterTransactionCleanup', [transaction, doc]);

    // Emit update events
    // ignore: avoid_dynamic_calls
    if (doc.hasObserver('update') as bool) {
      final encoder = UpdateEncoderV1();
      final hasContent = writeUpdateMessageFromTransaction(encoder, transaction);
      if (hasContent) {
        // ignore: avoid_dynamic_calls
        doc.emit('update',
            [encoder.toUint8Array(), transaction.origin, doc, transaction]);
      }
    }
    // ignore: avoid_dynamic_calls
    if (doc.hasObserver('updateV2') as bool) {
      final encoder = UpdateEncoderV2();
      final hasContent = writeUpdateMessageFromTransaction(encoder, transaction);
      if (hasContent) {
        // ignore: avoid_dynamic_calls
        doc.emit('updateV2',
            [encoder.toUint8Array(), transaction.origin, doc, transaction]);
      }
    }

    // Handle subdocs
    final subdocsAdded = transaction.subdocsAdded;
    final subdocsLoaded = transaction.subdocsLoaded;
    final subdocsRemoved = transaction.subdocsRemoved;
    if (subdocsAdded.isNotEmpty ||
        subdocsRemoved.isNotEmpty ||
        subdocsLoaded.isNotEmpty) {
      for (final subdoc in subdocsAdded) {
        // ignore: avoid_dynamic_calls
        subdoc.clientID = doc.clientID;
        // ignore: avoid_dynamic_calls
        if (subdoc.collectionid == null) {
          // ignore: avoid_dynamic_calls
          subdoc.collectionid = doc.collectionid;
        }
        // ignore: avoid_dynamic_calls
        doc.subdocs.add(subdoc);
      }
      for (final subdoc in subdocsRemoved) {
        // ignore: avoid_dynamic_calls
        doc.subdocs.remove(subdoc);
      }
      // ignore: avoid_dynamic_calls
      doc.emit('subdocs', [
        {
          'loaded': subdocsLoaded,
          'added': subdocsAdded,
          'removed': subdocsRemoved
        },
        doc,
        transaction
      ]);
      for (final subdoc in subdocsRemoved) {
        // ignore: avoid_dynamic_calls
        subdoc.destroy();
      }
    }

    if (transactionCleanups.length <= i + 1) {
      // ignore: avoid_dynamic_calls
      doc.transactionCleanups.clear();
      // ignore: avoid_dynamic_calls
      doc.emit('afterAllTransactions', [doc, transactionCleanups]);
    } else {
      _cleanupTransactions(transactionCleanups, i + 1);
    }
  }
}

void _callAll(List<void Function()> fs) {
  Object? firstError;
  for (final f in fs) {
    try {
      f();
    } catch (e) {
      firstError ??= e;
    }
  }
  if (firstError != null) throw firstError;
}

// ---------------------------------------------------------------------------
// transact
// ---------------------------------------------------------------------------

/// Execute [f] in a transaction on [doc].
///
/// Mirrors: `transact` in Transaction.js
T transact<T>(dynamic doc, T Function(Transaction) f,
    [Object? origin, bool local = true]) {
  // ignore: avoid_dynamic_calls
  final transactionCleanups =
      doc.transactionCleanups as List<Transaction>;
  var initialCall = false;
  T? result;
  // ignore: avoid_dynamic_calls
  if (doc.currentTransaction == null) {
    initialCall = true;
    // ignore: avoid_dynamic_calls
    doc.currentTransaction = Transaction(doc, origin, local);
    transactionCleanups.add(doc.currentTransaction as Transaction);
    if (transactionCleanups.length == 1) {
      // ignore: avoid_dynamic_calls
      doc.emit('beforeAllTransactions', [doc]);
    }
    // ignore: avoid_dynamic_calls
    doc.emit('beforeTransaction', [doc.currentTransaction, doc]);
  }
  try {
    // ignore: avoid_dynamic_calls
    result = f(doc.currentTransaction as Transaction);
  } finally {
    if (initialCall) {
      // ignore: avoid_dynamic_calls
      final finishCleanup =
          doc.currentTransaction == transactionCleanups[0];
      // ignore: avoid_dynamic_calls
      doc.currentTransaction = null;
      if (finishCleanup) {
        _cleanupTransactions(transactionCleanups, 0);
      }
    }
  }
  return result as T;
}

// ---------------------------------------------------------------------------
// callEventHandlerListeners (re-exported for use in cleanupTransactions)
// ---------------------------------------------------------------------------

/// Call all event handler listeners.
///
/// Mirrors: `callEventHandlerListeners` in EventHandler.js
void callEventHandlerListeners(dynamic eH, dynamic event, Transaction tr) {
  // ignore: avoid_dynamic_calls
  final listeners = eH.l as List;
  for (final listener in List.from(listeners)) {
    try {
      // ignore: avoid_dynamic_calls
      listener(event, tr);
    } catch (_) {
      // continue calling other listeners
    }
  }
}

// ---------------------------------------------------------------------------
// generateNewClientId
// ---------------------------------------------------------------------------

/// Generate a new unique client ID.
///
/// Mirrors: `generateNewClientId` in Doc.js
int generateNewClientId() => random.uint32();
