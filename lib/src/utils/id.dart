/// Dart translation of src/utils/ID.js
///
/// Mirrors: yjs/src/utils/ID.js (v14.0.0-22)
library;

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;

/// A unique identifier for a CRDT struct.
///
/// Each [ID] is a (client, clock) pair where:
/// - [client] is the unique client identifier (uint32)
/// - [clock] is a monotonically increasing counter per client
class ID {
  /// Client id.
  final int client;

  /// Unique per client id, continuous number.
  final int clock;

  const ID(this.client, this.clock);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ID && other.client == client && other.clock == clock;

  @override
  int get hashCode => Object.hash(client, clock);

  @override
  String toString() => 'ID($client, $clock)';
}

/// Compare two nullable IDs for equality.
///
/// Mirrors: `compareIDs` in ID.js
bool compareIDs(ID? a, ID? b) =>
    identical(a, b) ||
    (a != null && b != null && a.client == b.client && a.clock == b.clock);

/// Create a new [ID].
///
/// Mirrors: `createID` in ID.js
ID createID(int client, int clock) => ID(client, clock);

/// Write an [ID] to [encoder].
///
/// Mirrors: `writeID` in ID.js
void writeID(encoding.Encoder encoder, ID id) {
  encoding.writeVarUint(encoder, id.client);
  encoding.writeVarUint(encoder, id.clock);
}

/// Read an [ID] from [decoder].
///
/// Mirrors: `readID` in ID.js
ID readID(decoding.Decoder decoder) =>
    createID(decoding.readVarUint(decoder), decoding.readVarUint(decoder));
