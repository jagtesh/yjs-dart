library;

import '../structs/item.dart';
import 'doc.dart';
import 'transaction.dart';

/// Interface for structures that can contain Items (Doc and AbstractType).
abstract class YStructure {
  /// The item that contains this structure.
  /// Returns null if this structure is a [Doc].
  Item? get item;

  /// The root document of this structure.
  Doc? get doc;

  /// The transaction that is currently changing this structure.
  Transaction? get transaction;
}
