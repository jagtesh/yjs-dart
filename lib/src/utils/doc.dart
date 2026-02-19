/// Dart translation of src/utils/Doc.js
///
/// Mirrors: yjs/src/utils/Doc.js (v14.0.0-22)
library;

import '../lib0/observable.dart';
import '../lib0/random.dart' as random;
import '../utils/struct_store.dart';
import '../utils/transaction.dart' as tr_lib;
import '../y_type.dart';
import 'y_structure.dart';
import '../structs/item.dart'; // Add import

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

  /// Optional deterministic client ID (for testing).
  final int? clientID;

  DocOpts({
    String? guid,
    this.collectionid,
    this.gc = true,
    bool Function(dynamic)? gcFilter,
    this.meta,
    this.autoLoad = false,
    this.shouldLoad = true,
    this.isSuggestionDoc = false,
    this.clientID,
  })  : guid = guid ?? random.uuidv4(),
        gcFilter = gcFilter ?? ((_) => true);
}

/// A Yjs Document.
///
/// Mirrors: `Doc` in Doc.js
class Doc extends Observable<String> implements YStructure {
  Item? _item;

  @override
  Item? get item => _item;

  @override
  Doc? get doc => this;

  @override
  tr_lib.Transaction? get transaction => _transaction;

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
  tr_lib.Transaction? _transaction;

  /// Pending transaction cleanups.
  final List<tr_lib.Transaction> _transactionCleanups = [];

  // Public accessors for cross-library access from transaction.dart
  tr_lib.Transaction? get currentTransaction => _transaction;
  set currentTransaction(tr_lib.Transaction? t) => _transaction = t;
  List<tr_lib.Transaction> get transactionCleanups => _transactionCleanups;

  /// Sub-documents.
  final Set<Doc> subdocs = {};

  /// The item that contains this doc (if it's a subdoc).
  dynamic yItem; // Item?

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

  /// Whether this document has been destroyed.
  bool isDestroyed = false;

  Doc([DocOpts? opts])
      : gc = opts?.gc ?? true,
        gcFilter = opts?.gcFilter ?? ((_) => true),
        clientID = opts?.clientID ?? generateNewClientId(),
        guid = opts?.guid ?? random.uuidv4(),
        collectionid = opts?.collectionid,
        isSuggestionDoc = opts?.isSuggestionDoc ?? false,
        cleanupFormatting = !(opts?.isSuggestionDoc ?? false),
        shouldLoad = opts?.shouldLoad ?? true,
        autoLoad = opts?.autoLoad ?? false,
        meta = opts?.meta;

  /// Get or create a shared type by [name].
  ///
  /// If [typeConstructor] is omitted, [T] must be a concrete type that can be instantiated,
  /// or one of the convenience methods ([getText], [getArray], [getMap]) should be used.
  ///
  /// Note: The default constructor `YType()` is no longer valid as `YType` is abstract.
  T get<T extends AbstractType<dynamic>>(String name, [T Function()? typeConstructor]) {
    final existing = share[name];
    if (existing != null) {
      if (existing is T) return existing;
      // If a generic AbstractType is requested, return the existing one
      // This cast might fail if T is specific and existing is different
      return existing as T;
    }
    
    if (typeConstructor == null) {
        // We cannot instantiate T directly if it's a generic variable without a constructor.
        // However, we can check T's type if possible, or throw.
        throw ArgumentError('typeConstructor is required for new types');
    }
    
    final type = typeConstructor();
    share[name] = type;
    type.integrate(this, null);
    return type;
  }

  /// Get or create a YText.
  YText getText(String name) => get<YText>(name, () => YText());

  /// Get or create a YArray.
  YArray<T> getArray<T>(String name) => get<YArray<T>>(name, () => YArray<T>());

  /// Get or create a YMap.
  YMap<T> getMap<T>(String name) => get<YMap<T>>(name, () => YMap<T>());

  /// Execute [f] in a transaction using the full cleanup pipeline.
  T transactFull<T>(T Function(tr_lib.Transaction tr) f, [Object? origin]) {
    return tr_lib.transact<T>(this, f, origin);
  }

  /// Execute [f] in a transaction (simple path for internal use).
  void transact(void Function(tr_lib.Transaction tr) f, [Object? origin]) {
    tr_lib.transact<void>(this, f, origin);
  }

  /// Load this document (fires the 'load' event).
  void load() {
    final item = yItem;
    if (item != null && !shouldLoad) {
      tr_lib.transact<void>(this, (tr) {
        tr.subdocsLoaded.add(this);
      }, null, true);
    }
    shouldLoad = true;
  }

  /// Get all sub-documents.
  ///
  /// Mirrors: `getSubdocs` in Doc.js
  Set<Doc> getSubdocs() => subdocs;

  /// Get the GUIDs of all sub-documents.
  ///
  /// Mirrors: `getSubdocGuids` in Doc.js
  Set<String> getSubdocGuids() => subdocs.map((d) => d.guid).toSet();

  /// Serialize all shared types to a JSON-compatible map.
  ///
  /// Mirrors: `toJSON` in Doc.js
  Map<String, Object?> toJSON() {
    final result = <String, Object?>{};
    share.forEach((key, value) {
      // ignore: avoid_dynamic_calls
      result[key] = (value as dynamic).toJSON();
    });
    return result;
  }

  /// Destroy this document and release resources.
  ///
  /// Mirrors: `destroy` in Doc.js
  @override
  void destroy() {
    isDestroyed = true;
    // Destroy all subdocs
    for (final subdoc in List.of(subdocs)) {
      subdoc.destroy();
    }
    final item = yItem;
    if (item != null) {
      yItem = null;
      // Replace the ContentDoc with a fresh unloaded doc
      // ignore: avoid_dynamic_calls
      final content = item.content;
      // ignore: avoid_dynamic_calls
      final newDoc = Doc(DocOpts(guid: guid, shouldLoad: false));
      // ignore: avoid_dynamic_calls
      content.doc = newDoc;
      // ignore: avoid_dynamic_calls
      newDoc.yItem = item;
      // ignore: avoid_dynamic_calls
      tr_lib.transact<void>(item.parent.doc as Doc, (tr) {
        if (!(item.deleted as bool)) {
          tr.subdocsAdded.add(newDoc);
        }
        tr.subdocsRemoved.add(this);
      }, null, true);
    }
    emit('destroyed', [true]); // deprecated but kept for compat
    emit('destroy', [this]);
    super.destroy();
  }
}

/// Create a clone of [ydoc] with optional [opts].
///
/// Mirrors: `cloneDoc` in Doc.js
Doc cloneDoc(Doc ydoc, [DocOpts? opts]) {
  final clone = Doc(opts);
  // Apply the full state by iterating shared types
  // For each shared type in the original, create a matching type in the clone
  ydoc.share.forEach((key, type) {
    final newType = type.clone();
    newType.integrate(clone, null);
    clone.share[key] = newType;
  });
  return clone;
}
