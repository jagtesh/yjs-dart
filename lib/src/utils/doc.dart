/// Dart translation of src/utils/Doc.js
///
/// Mirrors: yjs/src/utils/Doc.js (v14.0.0-22)
library;

import '../lib0/observable.dart';
import '../lib0/random.dart' as random;
import '../utils/struct_store.dart';
import '../utils/transaction.dart' as tr_lib;
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
  /// If [typeConstructor] is omitted, a plain `YType()` is created.
  T get<T extends YType<dynamic>>(String name, [T Function()? typeConstructor]) {
    final existing = share[name];
    if (existing != null) {
      if (existing is T) return existing;
      // If a generic YType is requested, return the existing one
      return existing as T;
    }
    final type = typeConstructor != null ? typeConstructor() : YType() as T;
    share[name] = type;
    type.integrate(this, null);
    return type;
  }

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
    final newType = clone.get(key, () => YType(type.name));
    // Copy array content
    final arr = type.toArray();
    if (arr.isNotEmpty) {
      // ignore: avoid_dynamic_calls
      newType.insert(0, arr.map((c) => c is YType ? (c as dynamic).clone() : c).toList());
    }
    // Copy map content
    type.forEachAttr((val, attrKey, _) {
      // ignore: avoid_dynamic_calls
      newType.setAttr(attrKey, val is YType ? (val as dynamic).clone() : val);
    });
  });
  return clone;
}
