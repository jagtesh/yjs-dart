/// Dart translation of src/structs/Skip.js
///
/// Mirrors: yjs/src/structs/Skip.js (v14.0.0-22)
library;

import '../structs/abstract_struct.dart';
import '../utils/id.dart';
import '../utils/id_set.dart';
import '../lib0/encoding.dart' as encoding;

/// Reference number for Skip structs in the binary encoding.
const int structSkipRefNumber = 10;

/// A skip struct - represents a gap in the struct store for pending structs.
///
/// Mirrors: `Skip` in Skip.js
class Skip extends AbstractStruct {
  Skip(super.id, super.length);

  @override
  bool get deleted => false;

  void delete() {}

  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! Skip) return false;
    length += right.length;
    return true;
  }

  @override
  void integrate(dynamic transaction, int offset) {
    if (offset > 0) {
      final newId = createID(id.client, id.clock + offset);
      final adjusted = Skip(newId, length - offset);
      adjusted._integrateInto(transaction);
      return;
    }
    _integrateInto(transaction);
  }

  void _integrateInto(dynamic transaction) {
    // ignore: avoid_dynamic_calls
    transaction.doc.store.skips.addToIdSet(id.client, id.clock, length);
    // ignore: avoid_dynamic_calls
    transaction.doc.store.addStruct(this);
  }

  @override
  void write(dynamic encoder, int offset, [int encodingRef = 0]) {
    // ignore: avoid_dynamic_calls
    encoder.writeInfo(structSkipRefNumber);
    // write as VarUint because Skips can't make use of predictable length-encoding
    // ignore: avoid_dynamic_calls
    final restEncoder = encoder.restEncoder;
    encoding.writeVarUint(restEncoder as encoding.Encoder, length - offset);
  }

  @override
  Skip splice(int diff) {
    final other = Skip(createID(id.client, id.clock + diff), length - diff);
    length = diff;
    return other;
  }
}
