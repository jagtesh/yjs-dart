/// Dart translation of src/structs/GC.js
///
/// Mirrors: yjs/src/structs/GC.js (v14.0.0-22)
library;

import '../structs/abstract_struct.dart';
import '../utils/id.dart';
import '../utils/update_encoder.dart';
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
  void integrate(Transaction transaction, int offset) {
    if (offset > 0) {
      // Note: ID is immutable in Dart, so we create a new GC with adjusted id
      final newId = createID(id.client, id.clock + offset);
      final adjusted = GC(newId, length - offset);
      adjusted._integrateInto(transaction);
      return;
    }
    _integrateInto(transaction);
  }

  void _integrateInto(Transaction transaction) {
    transaction.deleteSet.addToIdSet(id.client, id.clock, length);
    transaction.insertSet.addStructToIdSet(this);
    transaction.doc.store.addStruct(this);
  }

  @override
  void write(AbstractUpdateEncoder encoder, int offset, int encodingRef) {
    if (encoder is UpdateEncoderV1) {
      encoder.writeInfo(structGCRefNumber);
      encoder.writeLen(length - offset - encodingRef);
    } else if (encoder is UpdateEncoderV2) {
      encoder.writeInfo(structGCRefNumber);
      encoder.writeLen(length - offset - encodingRef);
    }
  }

  @override
  GC splice(int diff) {
    final other = GC(createID(id.client, id.clock + diff), length - diff);
    length = diff;
    return other;
  }
}
