/// Dart translation of y-protocols/sync.js
///
/// Mirrors: y-protocols/sync.js (v1.0.5)
library;

import '../lib0/encoding.dart' as encoding;
import '../lib0/decoding.dart' as decoding;
import '../utils/doc.dart';

/// Message type constants.
const int messageSyncStep1 = 0;
const int messageSyncStep2 = 1;
const int messageUpdate = 2;

/// Write sync step 1 (send state vector).
///
/// Mirrors: `writeSyncStep1` in sync.js
void writeSyncStep1(encoding.Encoder encoder, Doc doc) {
  encoding.writeVarUint(encoder, messageSyncStep1);
  // TODO: encode state vector
}

/// Write sync step 2 (send update).
///
/// Mirrors: `writeSyncStep2` in sync.js
void writeSyncStep2(
  encoding.Encoder encoder,
  Doc doc,
  List<int>? encodedStateVector,
) {
  encoding.writeVarUint(encoder, messageSyncStep2);
  // TODO: encode state as update
}

/// Read sync step 1 and write sync step 2 response.
///
/// Mirrors: `readSyncStep1` in sync.js
void readSyncStep1(
  decoding.Decoder decoder,
  encoding.Encoder encoder,
  Doc doc,
) {
  // TODO: read state vector, write step 2
}

/// Read sync step 2 and apply the update.
///
/// Mirrors: `readSyncStep2` in sync.js
void readSyncStep2(
  decoding.Decoder decoder,
  Doc doc, [
  Object? transactionOrigin,
]) {
  // TODO: read and apply update
}

/// Read a sync message and dispatch to the appropriate handler.
///
/// Mirrors: `readSyncMessage` in sync.js
int readSyncMessage(
  decoding.Decoder decoder,
  encoding.Encoder encoder,
  Doc doc, [
  Object? transactionOrigin,
]) {
  final messageType = decoding.readVarUint(decoder);
  switch (messageType) {
    case messageSyncStep1:
      readSyncStep1(decoder, encoder, doc);
    case messageSyncStep2:
      readSyncStep2(decoder, doc, transactionOrigin);
    case messageUpdate:
      readSyncStep2(decoder, doc, transactionOrigin);
    default:
      throw StateError('Unknown sync message type: $messageType');
  }
  return messageType;
}
