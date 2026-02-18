/// Dart translation of y-protocols/sync.js
///
/// Mirrors: y-protocols/sync.js (v1.0.5)
library;

import 'dart:typed_data';

import '../lib0/encoding.dart' as encoding;
import '../lib0/decoding.dart' as decoding;
import '../utils/doc.dart';
import '../utils/updates.dart';

/// Message type constants.
const int messageSyncStep1 = 0;
const int messageSyncStep2 = 1;
const int messageYjsUpdate = 2;

/// Create a SyncStep1 message (state vector) from [doc].
///
/// Mirrors: `writeSyncStep1` in sync.js
void writeSyncStep1(encoding.Encoder encoder, Doc doc) {
  encoding.writeVarUint(encoder, messageSyncStep1);
  final sv = encodeStateVector(doc);
  encoding.writeVarUint8Array(encoder, sv);
}

/// Create a SyncStep2 message (state-as-update) from [doc].
///
/// Mirrors: `writeSyncStep2` in sync.js
void writeSyncStep2(encoding.Encoder encoder, Doc doc,
    [Uint8List? encodedStateVector]) {
  encoding.writeVarUint(encoder, messageSyncStep2);
  encoding.writeVarUint8Array(
      encoder, encodeStateAsUpdate(doc, encodedStateVector));
}

/// Read a SyncStep1 message and reply with SyncStep2.
///
/// Mirrors: `readSyncStep1` in sync.js
void readSyncStep1(
    decoding.Decoder decoder, encoding.Encoder encoder, Doc doc) {
  writeSyncStep2(encoder, doc, decoding.readVarUint8Array(decoder));
}

/// Read and apply a SyncStep2 message.
///
/// Mirrors: `readSyncStep2` in sync.js
void readSyncStep2(
    decoding.Decoder decoder, Doc doc, Object? transactionOrigin) {
  try {
    applyUpdate(doc, decoding.readVarUint8Array(decoder), transactionOrigin);
  } catch (e) {
    // Errors thrown by event handlers should not crash the sync loop.
    // ignore: avoid_print
    print('Caught error while handling a Yjs update: $e');
  }
}

/// Write a raw update message.
///
/// Mirrors: `writeUpdate` in sync.js
void writeUpdate(encoding.Encoder encoder, Uint8List update) {
  encoding.writeVarUint(encoder, messageYjsUpdate);
  encoding.writeVarUint8Array(encoder, update);
}

/// Read and apply a raw update message (alias for [readSyncStep2]).
///
/// Mirrors: `readUpdate` in sync.js
void readUpdate(
        decoding.Decoder decoder, Doc doc, Object? transactionOrigin) =>
    readSyncStep2(decoder, doc, transactionOrigin);

/// Dispatch a sync message based on its type.
///
/// Returns the message type that was processed.
///
/// Mirrors: `readSyncMessage` in sync.js
int readSyncMessage(decoding.Decoder decoder, encoding.Encoder encoder, Doc doc,
    Object? transactionOrigin) {
  final messageType = decoding.readVarUint(decoder);
  switch (messageType) {
    case messageSyncStep1:
      readSyncStep1(decoder, encoder, doc);
      break;
    case messageSyncStep2:
      readSyncStep2(decoder, doc, transactionOrigin);
      break;
    case messageYjsUpdate:
      readUpdate(decoder, doc, transactionOrigin);
      break;
    default:
      throw StateError('Unknown sync message type: $messageType');
  }
  return messageType;
}
