/// Dart translation of src/utils/delta-helpers.js
///
/// Mirrors: yjs/src/utils/delta-helpers.js (v14.0.0-22)
library;

import '../structs/item.dart' show Item;
import '../utils/transaction.dart';
import '../utils/id_set.dart'
    show
        diffIdSet,
        mergeIdSets,
        createInsertSetFromStructStore,
        createDeleteSetFromStructStore;
import '../utils/struct_set.dart' show iterateStructsByIdSet;

/// Compute a delta representing the difference between two documents.
///
/// Returns a map of {typeName: delta} for each shared type that changed.
///
/// Mirrors: `diffDocsToDelta` in delta-helpers.js
Map<String, Object?> diffDocsToDelta(dynamic v1, dynamic v2,
    {Object? am}) {
  final result = <String, Object?>{};
  // ignore: avoid_dynamic_calls
  v2.transact((Transaction tr) {
    // ignore: avoid_dynamic_calls
    final v2Store = v2.store;
    // ignore: avoid_dynamic_calls
    final v1Store = v1.store;
    final insertDiff = diffIdSet(
      createInsertSetFromStructStore(v2Store, false),
      createInsertSetFromStructStore(v1Store, false),
    );
    final deleteDiff = diffIdSet(
      createDeleteSetFromStructStore(v2Store),
      createDeleteSetFromStructStore(v1Store),
    );
    // Items inserted and then deleted should not be rendered
    final insertsOnly = diffIdSet(insertDiff, deleteDiff);
    final deletesOnly = diffIdSet(deleteDiff, insertDiff);
    final itemsToRender = mergeIdSets([insertsOnly, deleteDiff]);

    // Collect changed types
    final changedTypes = <Object, Set<Object?>>{};
    iterateStructsByIdSet(tr, itemsToRender, (struct) {
      dynamic current = struct;
      while (current is Item) {
        final parent = current.parent;
        if (parent == null) break;
        final conf = changedTypes.putIfAbsent(parent, () => <Object?>{});
        if (conf.contains(current.parentSub)) break;
        conf.add(current.parentSub);
        // ignore: avoid_dynamic_calls
        current = (parent as dynamic).yItem;
      }
    });

    // Build delta for each changed shared type
    // ignore: avoid_dynamic_calls
    (v2.share as Map).forEach((typename, type) {
      final typeConf = changedTypes[type];
      if (typeConf != null) {
        // ignore: avoid_dynamic_calls
        final shareDelta = (type as dynamic).toDelta(am, {
          'itemsToRender': itemsToRender,
          'retainDeletes': true,
          'deletedItems': deletesOnly,
          'modified': changedTypes,
          'deep': true,
        });
        result[typename as String] = shareDelta;
      }
    });
  });
  return result;
}
