/// Dart translation of src/structs/AbstractStruct.js
///
/// Mirrors: yjs/src/structs/AbstractStruct.js (v14.0.0-22)
library;

import '../utils/id.dart';
import '../utils/update_encoder.dart';

// Forward declaration - Transaction is defined in transaction.dart
// We use a dynamic import pattern to avoid circular deps.
// ignore: unused_import
import '../utils/transaction.dart';

/// Abstract base class for all CRDT structs.
///
/// Mirrors: `AbstractStruct` in AbstractStruct.js
abstract class AbstractStruct {
  final ID id;
  int length;

  AbstractStruct(this.id, this.length);

  /// Whether this struct has been deleted.
  bool get deleted;

  /// Merge this struct with the item to the right.
  ///
  /// This method assumes `this.id.clock + this.length === right.id.clock`.
  /// Does *not* remove [right] from StructStore.
  ///
  /// Returns whether this merged with [right].
  bool mergeWith(AbstractStruct right) => false;

  /// Write this struct to [encoder] at [offset] with [encodingRef].
  void write(AbstractUpdateEncoder encoder, int offset, int encodingRef);

  /// Integrate this struct into the document via [transaction] at [offset].
  void integrate(Transaction transaction, int offset);

  /// Split this struct at [diff], returning the right part.
  AbstractStruct splice(int diff);
}
