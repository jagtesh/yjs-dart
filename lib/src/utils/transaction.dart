/// Dart translation of src/utils/Transaction.js (stub)
///
/// Mirrors: yjs/src/utils/Transaction.js (v14.0.0-22)
/// Note: This is a structural stub - the full transaction logic is complex
/// and will be completed in subsequent iterations.
library;

import '../utils/id_set.dart';
import '../utils/struct_store.dart';

// Forward reference to Doc - resolved at runtime via late binding
// to avoid circular import issues.
class _DocRef {
  late final dynamic _doc;
  dynamic get doc => _doc;
}

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

  /// Whether this transaction was triggered by a remote update.
  bool get remote => !local;

  Transaction(this.doc, this.origin, this.local);
}

/// Execute [f] in a transaction on [doc].
///
/// Mirrors: `transact` in Transaction.js
void transact(dynamic doc, void Function(Transaction) f, [Object? origin, bool local = true]) {
  if (doc._transaction != null) {
    f(doc._transaction as Transaction);
    return;
  }
  final tr = Transaction(doc, origin, local);
  doc._transaction = tr;
  try {
    f(tr);
  } finally {
    doc._transaction = null;
    // TODO: cleanup, observer calls, afterTransaction hooks
  }
}
