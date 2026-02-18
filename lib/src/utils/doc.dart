/// Dart translation of src/utils/Doc.js
///
/// Mirrors: yjs/src/utils/Doc.js (v14.0.0-22)
library;

import '../lib0/observable.dart';
import '../lib0/random.dart' as random;
import '../utils/struct_store.dart';
import '../utils/transaction.dart';
import '../y_type.dart';

/// Generate a new unique client ID.
///
/// Mirrors: `generateNewClientId` in Doc.js
int generateNewClientId() => random.uint32();

/// Options for creating a [Doc].
class DocOpts {
  /// Globally unique identifier for this document.
  final String guid;

  /// Collection ID for provider grouping.
  final String? collectionid;

  /// Enable garbage collection (default: true).
  final bool gc;

  /// Filter function for GC (return false to keep an item).
  final bool Function(dynamic item) gcFilter;

  /// Arbitrary metadata.
  final Object? meta;

  /// Auto-load if this is a subdocument.
  final bool autoLoad;

  /// Whether the document should be synced by the provider.
  final bool shouldLoad;

  /// Whether this is a suggestion document.
  final bool isSuggestionDoc;

  DocOpts({
    String? guid,
    this.collectionid,
    this.gc = true,
    bool Function(dynamic)? gcFilter,
    this.meta,
    this.autoLoad = false,
    this.shouldLoad = true,
    this.isSuggestionDoc = false,
  })  : guid = guid ?? random.uuidv4(),
        gcFilter = gcFilter ?? ((_) => true);
}

/// A Yjs document - the root container for all shared data.
///
/// Mirrors: `Doc` in Doc.js
class Doc extends Observable<String> {
  /// Enable garbage collection.
  final bool gc;

  /// GC filter function.
  final bool Function(dynamic) gcFilter;

  /// Unique client ID (uint32).
  final int clientID;

  /// Globally unique document identifier.
  final String guid;

  /// Collection ID.
  final String? collectionid;

  /// Whether this is a suggestion document.
  final bool isSuggestionDoc;

  /// Whether to cleanup formatting (inverse of isSuggestionDoc).
  final bool cleanupFormatting;

  /// Shared types map (name → YType).
  final Map<String, YType<dynamic>> share = {};

  /// The struct store.
  final StructStore store = StructStore();

  /// Current transaction (null if not in a transaction).
  Transaction? _transaction;

  /// Pending transaction cleanups.
  final List<Transaction> _transactionCleanups = [];

  /// Sub-documents.
  final Set<Doc> subdocs = {};

  /// The item that contains this doc (if it's a subdoc).
  dynamic _item; // Item?

  /// Whether the document should be synced.
  bool shouldLoad;

  /// Whether to auto-load as a subdoc.
  final bool autoLoad;

  /// Arbitrary metadata.
  final Object? meta;

  /// Whether the document has been loaded from persistence.
  bool isLoaded = false;

  /// Whether the document has been synced with a backend.
  bool isSynced = false;

  Doc([DocOpts? opts])
      : gc = opts?.gc ?? true,
        gcFilter = opts?.gcFilter ?? ((_) => true),
        clientID = generateNewClientId(),
        guid = opts?.guid ?? random.uuidv4(),
        collectionid = opts?.collectionid,
        isSuggestionDoc = opts?.isSuggestionDoc ?? false,
        cleanupFormatting = !(opts?.isSuggestionDoc ?? false),
        shouldLoad = opts?.shouldLoad ?? true,
        autoLoad = opts?.autoLoad ?? false,
        meta = opts?.meta;

  /// Get or create a shared type by [name] using [typeConstructor].
  T get<T extends YType<dynamic>>(String name, T Function() typeConstructor) {
    final existing = share[name];
    if (existing != null) {
      if (existing is T) return existing;
      throw StateError(
          'Type mismatch: "$name" already exists as ${existing.runtimeType}');
    }
    final type = typeConstructor();
    share[name] = type;
    type.integrate(this, null);
    return type;
  }

  /// Execute [f] in a transaction.
  void transact(void Function(Transaction tr) f, [Object? origin]) {
    if (_transaction != null) {
      f(_transaction!);
      return;
    }
    final tr = Transaction(this, origin, true);
    _transaction = tr;
    emit('beforeTransaction', [tr, this]);
    try {
      f(tr);
    } finally {
      _transaction = null;
      // TODO: full cleanup, observer calls, afterTransaction hooks
      emit('afterTransaction', [tr, this]);
    }
  }

  /// Load this document (fires the 'load' event).
  void load() {
    final item = _item;
    if (item != null) {
      // TODO: load subdoc
    }
    if (!isLoaded) {
      isLoaded = true;
      emit('load', [this]);
    }
  }

  /// Destroy this document and release resources.
  void destroy() {
    // TODO: cleanup subdocs
    emit('destroy', [this]);
    super.destroy();
  }
}
