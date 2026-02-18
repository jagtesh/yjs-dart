/// Dart translation of src/utils/RelativePosition.js
///
/// Mirrors: yjs/src/utils/RelativePosition.js (v14.0.0-22)
library;

import '../utils/id.dart';

/// A position relative to a specific item in the document.
///
/// Mirrors: `RelativePosition` in RelativePosition.js
class RelativePosition {
  /// The type key (for root types) or null.
  final String? type;

  /// The ID of the item this position is relative to.
  final ID? item;

  /// The association: -1 = left, 0 = right.
  final int assoc;

  const RelativePosition({this.type, this.item, this.assoc = 0});
}

/// An absolute position in a type.
///
/// Mirrors: `AbsolutePosition` in RelativePosition.js
class AbsolutePosition {
  /// The type this position is in.
  final dynamic type; // YType

  /// The index within the type.
  final int index;

  /// The association: -1 = left, 0 = right.
  final int assoc;

  const AbsolutePosition(this.type, this.index, {this.assoc = 0});
}

/// Create a relative position from a type index.
///
/// Mirrors: `createRelativePositionFromTypeIndex` in RelativePosition.js
RelativePosition createRelativePositionFromTypeIndex(
  dynamic type,
  int index, [
  int assoc = 0,
]) {
  // TODO: implement full traversal
  return RelativePosition(assoc: assoc);
}

/// Create a relative position from JSON.
///
/// Mirrors: `createRelativePositionFromJSON` in RelativePosition.js
RelativePosition createRelativePositionFromJSON(Object? json) {
  if (json is Map) {
    return RelativePosition(
      type: json['type'] as String?,
      item: json['item'] != null
          ? createID(
              (json['item'] as Map)['client'] as int,
              (json['item'] as Map)['clock'] as int,
            )
          : null,
      assoc: (json['assoc'] as int?) ?? 0,
    );
  }
  return const RelativePosition();
}

/// Convert a relative position to JSON.
///
/// Mirrors: `relativePositionToJSON` in RelativePosition.js
Map<String, Object?> relativePositionToJSON(RelativePosition pos) {
  return {
    'type': pos.type,
    'item': pos.item != null
        ? {'client': pos.item!.client, 'clock': pos.item!.clock}
        : null,
    'assoc': pos.assoc,
  };
}

/// Create an absolute position from a relative position.
///
/// Mirrors: `createAbsolutePositionFromRelativePosition` in RelativePosition.js
AbsolutePosition? createAbsolutePositionFromRelativePosition(
  RelativePosition pos,
  dynamic doc,
) {
  // TODO: implement full resolution
  return null;
}

/// Compare two relative positions.
///
/// Mirrors: `compareRelativePositions` in RelativePosition.js
bool compareRelativePositions(RelativePosition a, RelativePosition b) {
  return a.type == b.type &&
      compareIDs(a.item, b.item) &&
      a.assoc == b.assoc;
}
