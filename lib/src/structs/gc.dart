/// Dart translation of src/structs/GC.js
///
/// Mirrors: yjs/src/structs/GC.js (v14.0.0-22)
library;

import '../structs/abstract_struct.dart';
import '../utils/id.dart';
import '../utils/id_set.dart';
import '../utils/transaction.dart';

/// Reference number for GC structs in the binary encoding.
const int structGCRefNumber = 0;

/// A garbage-collected struct (tombstone for deleted content).
///
/// Mirrors: `GC` in GC.js
class GC extends AbstractStruct {
  GC(super.id, super.length);

  @override
  bool get deleted => true;

  void delete() {}

  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! GC) return false;
    length += right.length;
    return true;
  }

  @override
  void integrate(dynamic transaction, int offset) {
    if (offset > 0) {
      final newId = createID(id.client, id.clock + offset);
      final adjusted = GC(newId, length - offset);
      adjusted._integrateInto(transaction as Transaction);
      return;
    }
    _integrateInto(transaction as Transaction);
  }

  void _integrateInto(Transaction transaction) {
    addToIdSet(transaction.deleteSet, id.client, id.clock, length);
    addToIdSet(transaction.insertSet, id.client, id.clock, length);
    // ignore: avoid_dynamic_calls
    transaction.doc.store.addStruct(this);
  }

  @override
  void write(dynamic encoder, int offset, [int encodingRef = 0]) {
    // ignore: avoid_dynamic_calls
    encoder.writeInfo(structGCRefNumber);
    // ignore: avoid_dynamic_calls
    encoder.writeLen(length - offset);
  }

  @override
  GC splice(int diff) {
    final other = GC(createID(id.client, id.clock + diff), length - diff);
    length = diff;
    return other;
  }
}
