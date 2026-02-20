/// Dart translation of src/structs/AbstractStruct.js
///
/// Mirrors: yjs/src/structs/AbstractStruct.js (v14.0.0-22)
library;

import '../utils/id.dart';

// Forward declaration - Transaction is defined in transaction.dart
// We use dynamic to avoid circular deps.
// ignore: unused_import
import '../utils/transaction.dart';

/// Abstract base class for all CRDT structs.
///
/// Mirrors: `AbstractStruct` in AbstractStruct.js
abstract class AbstractStruct {
  ID id;
  int length;

  AbstractStruct(this.id, this.length);

  /// The ID of the last element in this struct.
  ID get lastId => createID(id.client, id.clock + length - 1);

  /// Whether this struct has been deleted.
  bool get deleted;

  /// Merge this struct with the item to the right.
  ///
  /// This method assumes `this.id.clock + this.length === right.id.clock`.
  /// Does *not* remove [right] from StructStore.
  ///
  /// Returns whether this merged with [right].
  bool mergeWith(AbstractStruct right) => false;

  /// Write this struct to [encoder] at [offset].
  /// [encoder] is dynamic to avoid circular import with update_encoder.dart.
  void write(dynamic encoder, int offset, [int encodingRef = 0]);

  /// Integrate this struct into the document via [transaction] at [offset].
  void integrate(dynamic transaction, int offset);

  /// Split this struct at [diff], returning the right part.
  AbstractStruct splice(int diff);
}
