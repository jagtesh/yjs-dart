/// Dart translation of src/utils/Transaction.js
///
/// Mirrors: yjs/src/utils/Transaction.js (v14.0.0-22)
library;

import '../utils/id_set.dart' hide findIndexSS;
import '../utils/struct_store.dart';
import '../structs/abstract_struct.dart';

/// A transaction groups changes to a Yjs document.
///
/// Mirrors: `Transaction` in Transaction.js
class Transaction {
  /// The document this transaction belongs to.
  final dynamic doc; // Doc - late binding to avoid circular import

  /// The delete set accumulated during this transaction.
  final IdSet deleteSet = createIdSet();

  /// The insert set accumulated during this transaction.
  final IdSet insertSet = createIdSet();

  /// Origin of this transaction (for filtering in observers).
  final Object? origin;

  /// Whether this is a local transaction.
  final bool local;

  /// Changed types and their changed keys.
  final Map<dynamic, Set<String?>> changed = {};

  /// Types that were deleted during this transaction.
  final Set<dynamic> deletedTypes = {};

  /// Structs that need to be merged after the transaction.
  final List<AbstractStruct> mergeStructs = [];

  /// Sub-documents added during this transaction.
  final Set<dynamic> subdocsAdded = {};

  /// Sub-documents removed during this transaction.
  final Set<dynamic> subdocsRemoved = {};

  /// Sub-documents loaded during this transaction.
  final Set<dynamic> subdocsLoaded = {};

  /// Whether this transaction was triggered by a remote update.
  bool get remote => !local;

  Transaction(this.doc, this.origin, this.local);

  /// Split [struct] at [diff] and insert the right part into the store.
  ///
  /// Used by getItemCleanStart/getItemCleanEnd.
  AbstractStruct _splitStruct(AbstractStruct struct, int diff) {
    final right = struct.splice(diff);
    mergeStructs.add(right);
    // Insert right into the store after struct
    // ignore: avoid_dynamic_calls
    final store = doc.store as StructStore;
    final structs = store.clients[struct.id.client]!;
    final index = findIndexSS(structs, struct.id.clock);
    structs.insert(index + 1, right);
    return right;
  }
}

/// Add [type] and [parentSub] to [transaction.changed].
///
/// Mirrors: `addChangedTypeToTransaction` in Transaction.js
void addChangedTypeToTransaction(Transaction transaction, dynamic type, String? parentSub) {
  final item = (type as dynamic)?._item;
  if (item == null || (transaction.doc as dynamic).store != null) {
    transaction.changed.putIfAbsent(type, () => {}).add(parentSub);
  }
}

/// Execute [f] in a transaction on [doc].
///
/// Mirrors: `transact` in Transaction.js
void transact(dynamic doc, void Function(Transaction) f, [Object? origin, bool local = true]) {
  // ignore: avoid_dynamic_calls
  if (doc._transaction != null) {
    // ignore: avoid_dynamic_calls
    f(doc._transaction as Transaction);
    return;
  }
  final tr = Transaction(doc, origin, local);
  // ignore: avoid_dynamic_calls
  doc._transaction = tr;
  try {
    f(tr);
  } finally {
    // ignore: avoid_dynamic_calls
    doc._transaction = null;
    _afterTransaction(tr);
  }
}

/// Post-transaction cleanup: merge structs, call observers.
///
/// Mirrors: `afterTransaction` in Transaction.js
void _afterTransaction(Transaction transaction) {
  // Merge structs that were split during the transaction
  final store = (transaction.doc as dynamic).store as StructStore;
  for (final struct in transaction.mergeStructs) {
    final structs = store.clients[struct.id.client];
    if (structs == null) continue;
    try {
      final index = findIndexSS(structs, struct.id.clock);
      if (index > 0) {
        final left = structs[index - 1];
        if (left.mergeWith(struct)) {
          structs.removeAt(index);
        }
      }
    } catch (_) {
      // struct may have been removed already
    }
  }
  // TODO: call type observers, afterTransaction hooks
}
