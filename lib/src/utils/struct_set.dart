/// Dart translation of src/utils/StructSet.js (structural stub)
///
/// Mirrors: yjs/src/utils/StructSet.js (v14.0.0-22)
library;

import '../structs/abstract_struct.dart';
import '../utils/id_set.dart';

/// A set of structs, organized by client.
///
/// Mirrors: `StructSet` in StructSet.js
class StructSet {
  final Map<int, List<AbstractStruct>> clients = {};

  void addStruct(AbstractStruct struct) {
    clients.putIfAbsent(struct.id.client, () => []).add(struct);
  }

  void forEach(void Function(int client, List<AbstractStruct> structs) f) {
    clients.forEach(f);
  }
}

/// Add a struct to an [IdSet] (insert set tracking).
///
/// Mirrors: `addStructToIdSet` in StructSet.js
void addStructToIdSet(IdSet idSet, AbstractStruct struct) {
  idSet.add(struct.id.client, struct.id.clock, struct.length);
}

/// Create an insert set from a struct store.
///
/// Mirrors: `createInsertSetFromStructStore` in StructSet.js
IdSet createInsertSetFromStructStore(dynamic store, bool includeDeleted) {
  final result = createIdSet();
  final s = store as dynamic;
  (s.clients as Map<int, List<AbstractStruct>>).forEach((client, structs) {
    for (final struct in structs) {
      if (!struct.deleted || includeDeleted) {
        result.add(client, struct.id.clock, struct.length);
      }
    }
  });
  return result;
}

/// Iterate over structs that fall within an [IdSet].
///
/// Mirrors: `iterateStructsByIdSet` in StructSet.js
void iterateStructsByIdSet(
  dynamic transaction,
  IdSet idSet,
  void Function(AbstractStruct struct) f,
) {
  // TODO: implement full iteration
}
