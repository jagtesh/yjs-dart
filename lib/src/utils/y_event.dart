/// Dart translation of src/utils/YEvent.js
///
/// Mirrors: yjs/src/utils/YEvent.js (v14.0.0-22)
library;

import '../structs/abstract_struct.dart';
import '../utils/transaction.dart';

/// Describes a change to a shared type.
///
/// Mirrors: `YEvent` in YEvent.js
class YEvent<T> {
  /// The type that this event was created on.
  final T target;

  /// The current target on which the observe callback is called.
  T currentTarget;

  /// The transaction that triggered this event.
  final Transaction transaction;

  /// Lazily computed delta.
  Object? _delta;

  /// Lazily computed deep delta.
  Object? _deltaDeep;

  /// Whether the child list changed.
  bool childListChanged = false;

  /// Set of all changed attribute keys.
  final Set<String> keysChanged = {};

  YEvent(this.target, this.transaction, [Set<Object?>? subs])
      : currentTarget = target {
    subs?.forEach((sub) {
      if (sub == null) {
        childListChanged = true;
      } else {
        keysChanged.add(sub as String);
      }
    });
  }

  /// Check if [struct] is deleted by this event.
  ///
  /// Mirrors: `deletes` in YEvent.js
  bool deletes(AbstractStruct struct) {
    return transaction.deleteSet.hasId(struct.id);
  }

  /// Check if [struct] is added by this event.
  ///
  /// Mirrors: `adds` in YEvent.js
  bool adds(AbstractStruct struct) {
    return transaction.insertSet.hasId(struct.id);
  }

  /// Compute the delta for this event.
  ///
  /// [am] is the attribution manager (defaults to noAttributionsManager).
  /// [deep] if true, includes deep changes.
  ///
  /// Mirrors: `getDelta` in YEvent.js
  Object? getDelta({Object? am, bool deep = false}) {
    // ignore: avoid_dynamic_calls
    return (target as dynamic).toDelta(am, {
      'itemsToRender': null,
      'retainDeletes': true,
      'deletedItems': transaction.deleteSet,
      'deep': deep,
      'modified': transaction.changed,
    });
  }

  /// The delta representation of this event (lazy, cached).
  ///
  /// Mirrors: `get delta` in YEvent.js
  Object? get delta => _delta ??= getDelta();

  /// The deep delta representation of this event (lazy, cached).
  ///
  /// Mirrors: `get deltaDeep` in YEvent.js
  Object? get deltaDeep => _deltaDeep ??= getDelta(deep: true);

  /// Returns the path from the root type to this event's target.
  ///
  /// Mirrors: `getPathTo` in YEvent.js
  List<Object> get path => _computePath();

  List<Object> _computePath() {
    // Walk up the parent chain from target to root
    final path = <Object>[];
    dynamic child = target;
    while (child != null) {
      // ignore: avoid_dynamic_calls
      final item = child.yItem;
      if (item == null) break;
      // ignore: avoid_dynamic_calls
      final parentSub = item.parentSub;
      if (parentSub != null) {
        // Map-like parent: key is the parentSub
        path.insert(0, parentSub as Object);
      } else {
        // Array-like parent: index requires absolute position resolution
        // Stub: insert 0 as placeholder until RelativePosition is complete
        path.insert(0, 0);
      }
      // ignore: avoid_dynamic_calls
      child = item.parent;
    }
    return path;
  }

  /// Returns the changes that occurred in this event.
  Map<String, Object?> get changes => _computeChanges();

  Map<String, Object?> _computeChanges() {
    // Stub — full implementation requires YType.toDelta
    return {};
  }
}
