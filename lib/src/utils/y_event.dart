/// Dart translation of src/utils/YEvent.js
///
/// Mirrors: yjs/src/utils/YEvent.js (v14.0.0-22)
library;

import '../utils/transaction.dart';

/// Describes a change to a shared type.
///
/// Mirrors: `YEvent` in YEvent.js
class YEvent<T> {
  /// The type that this event was created on.
  final T target;

  /// The transaction that triggered this event.
  final Transaction transaction;

  /// Lazily computed path from the root type to [target].
  List<Object>? _path;

  /// Lazily computed set of changes.
  Map<String, Object?>? _changes;

  /// Lazily computed set of keys that changed.
  Set<String?>? _keysChanged;

  YEvent(this.target, this.transaction);

  /// Returns the path from the root type to this event's target.
  List<Object> get path {
    return _path ??= _computePath();
  }

  List<Object> _computePath() {
    // TODO: implement path computation via parent chain
    return [];
  }

  /// Returns the changes that occurred in this event.
  Map<String, Object?> get changes {
    return _changes ??= _computeChanges();
  }

  Map<String, Object?> _computeChanges() {
    // TODO: implement change computation
    return {};
  }

  /// Returns the set of keys that changed (for YMap events).
  Set<String?> get keysChanged {
    return _keysChanged ??= {};
  }
}
