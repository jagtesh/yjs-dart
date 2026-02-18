/// Tests for Phase 5: sync protocol, awareness protocol, meta ContentIds,
/// Doc helpers (cloneDoc, destroy, getSubdocs, toJSON).
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yjs_dart/src/protocols/sync.dart';
import 'package:yjs_dart/src/protocols/awareness.dart';
import 'package:yjs_dart/src/utils/doc.dart';
import 'package:yjs_dart/src/utils/meta.dart';
import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;
import 'package:yjs_dart/src/lib0/decoding.dart' as decoding;

void main() {
  // ---------------------------------------------------------------------------
  // Sync protocol
  // ---------------------------------------------------------------------------
  group('sync protocol', () {
    test('writeSyncStep1 produces a valid message', () {
      final doc = Doc();
      final encoder = encoding.createEncoder();
      writeSyncStep1(encoder, doc);
      final bytes = encoding.toUint8Array(encoder);
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      // First byte should be messageSyncStep1 (0)
      final decoder = decoding.createDecoder(bytes);
      expect(decoding.readVarUint(decoder), equals(messageSyncStep1));
    });

    test('writeSyncStep2 produces a valid message', () {
      final doc = Doc();
      final encoder = encoding.createEncoder();
      writeSyncStep2(encoder, doc);
      final bytes = encoding.toUint8Array(encoder);
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      final decoder = decoding.createDecoder(bytes);
      expect(decoding.readVarUint(decoder), equals(messageSyncStep2));
    });

    test('readSyncStep1 replies with SyncStep2', () {
      final doc1 = Doc();
      final doc2 = Doc();
      // doc1 sends SyncStep1
      final step1Encoder = encoding.createEncoder();
      writeSyncStep1(step1Encoder, doc1);
      final step1Bytes = encoding.toUint8Array(step1Encoder);

      // doc2 reads SyncStep1 and replies with SyncStep2
      final step1Decoder = decoding.createDecoder(step1Bytes);
      decoding.readVarUint(step1Decoder); // consume message type
      final replyEncoder = encoding.createEncoder();
      readSyncStep1(step1Decoder, replyEncoder, doc2);
      final replyBytes = encoding.toUint8Array(replyEncoder);
      expect(replyBytes.isNotEmpty, isTrue);
      // Reply should be SyncStep2
      final replyDecoder = decoding.createDecoder(replyBytes);
      expect(decoding.readVarUint(replyDecoder), equals(messageSyncStep2));
    });

    test('readSyncMessage dispatches correctly', () {
      final doc1 = Doc();
      final doc2 = Doc();

      // Send SyncStep1
      final encoder = encoding.createEncoder();
      writeSyncStep1(encoder, doc1);
      final bytes = encoding.toUint8Array(encoder);

      final decoder = decoding.createDecoder(bytes);
      final replyEncoder = encoding.createEncoder();
      final msgType = readSyncMessage(decoder, replyEncoder, doc2, null);
      expect(msgType, equals(messageSyncStep1));
    });

    test('writeUpdate produces a valid update message', () {
      final update = Uint8List.fromList([1, 2, 3]);
      final encoder = encoding.createEncoder();
      writeUpdate(encoder, update);
      final bytes = encoding.toUint8Array(encoder);
      final decoder = decoding.createDecoder(bytes);
      expect(decoding.readVarUint(decoder), equals(messageYjsUpdate));
    });

    test('full sync round-trip between two docs', () {
      final doc1 = Doc();
      final doc2 = Doc();

      // doc1 → doc2 sync
      final enc1 = encoding.createEncoder();
      writeSyncStep1(enc1, doc1);
      final step1 = encoding.toUint8Array(enc1);

      final dec1 = decoding.createDecoder(step1);
      final enc2 = encoding.createEncoder();
      final msgType = readSyncMessage(dec1, enc2, doc2, null);
      expect(msgType, equals(messageSyncStep1));

      // doc2's reply (SyncStep2) applied to doc1
      final step2 = encoding.toUint8Array(enc2);
      final dec2 = decoding.createDecoder(step2);
      final enc3 = encoding.createEncoder();
      expect(() => readSyncMessage(dec2, enc3, doc1, null), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // Awareness protocol
  // ---------------------------------------------------------------------------
  group('awareness protocol', () {
    test('Awareness initializes with empty local state', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      expect(awareness.getLocalState(), isNotNull);
      expect(awareness.states.containsKey(doc.clientID), isTrue);
    });

    test('setLocalState updates state', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState({'cursor': 42});
      expect(awareness.getLocalState(), equals({'cursor': 42}));
    });

    test('setLocalStateField updates a single field', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState({'a': 1, 'b': 2});
      awareness.setLocalStateField('a', 99);
      expect(awareness.getLocalState()!['a'], equals(99));
      expect(awareness.getLocalState()!['b'], equals(2));
    });

    test('setLocalState(null) removes local state', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState(null);
      expect(awareness.getLocalState(), isNull);
    });

    test('encodeAwarenessUpdate produces valid bytes', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState({'x': 1});
      final update = encodeAwarenessUpdate(awareness, [doc.clientID]);
      expect(update, isA<Uint8List>());
      expect(update.isNotEmpty, isTrue);
    });

    test('applyAwarenessUpdate round-trips state', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final a1 = Awareness(doc1);
      final a2 = Awareness(doc2);

      a1.setLocalState({'user': 'alice'});
      final update = encodeAwarenessUpdate(a1, [doc1.clientID]);
      applyAwarenessUpdate(a2, update, null);

      expect(a2.states[doc1.clientID], equals({'user': 'alice'}));
    });

    test('removeAwarenessStates removes clients', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState({'x': 1});
      expect(awareness.states.containsKey(doc.clientID), isTrue);
      removeAwarenessStates(awareness, [doc.clientID], 'test');
      expect(awareness.states.containsKey(doc.clientID), isFalse);
    });

    test('modifyAwarenessUpdate transforms state', () {
      final doc = Doc();
      final awareness = Awareness(doc);
      awareness.setLocalState({'value': 1});
      final update = encodeAwarenessUpdate(awareness, [doc.clientID]);
      final modified = modifyAwarenessUpdate(
          update, (state) => {...state, 'value': (state['value'] as int) + 1});
      // Apply modified update to a new awareness
      final doc2 = Doc();
      final a2 = Awareness(doc2);
      applyAwarenessUpdate(a2, modified, null);
      expect(a2.states[doc.clientID]?['value'], equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Meta ContentIds
  // ---------------------------------------------------------------------------
  group('meta ContentIds', () {
    test('createContentIds returns empty sets', () {
      final ids = createContentIds();
      expect(ids.inserts.clients, isEmpty);
      expect(ids.deletes.clients, isEmpty);
    });

    test('encodeContentIds / decodeContentIds round-trip', () {
      final ids = createContentIds();
      final encoded = encodeContentIds(ids);
      expect(encoded, isA<Uint8List>());
      final decoded = decodeContentIds(encoded);
      expect(decoded.inserts.clients, isEmpty);
      expect(decoded.deletes.clients, isEmpty);
    });

    test('createContentIdsFromDoc returns empty for empty doc', () {
      final doc = Doc();
      final ids = createContentIdsFromDoc(doc);
      expect(ids.inserts.clients, isEmpty);
      expect(ids.deletes.clients, isEmpty);
    });

    test('mergeContentIds merges multiple ContentIds', () {
      final a = createContentIds();
      final b = createContentIds();
      final merged = mergeContentIds([a, b]);
      expect(merged.inserts.clients, isEmpty);
      expect(merged.deletes.clients, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Doc helpers
  // ---------------------------------------------------------------------------
  group('Doc helpers', () {
    test('Doc.toJSON returns empty map for empty doc', () {
      final doc = Doc();
      expect(doc.toJSON(), isEmpty);
    });

    test('Doc.getSubdocs returns empty set initially', () {
      final doc = Doc();
      expect(doc.getSubdocs(), isEmpty);
    });

    test('Doc.getSubdocGuids returns empty set initially', () {
      final doc = Doc();
      expect(doc.getSubdocGuids(), isEmpty);
    });

    test('Doc.isDestroyed starts false', () {
      final doc = Doc();
      expect(doc.isDestroyed, isFalse);
    });

    test('Doc.destroy sets isDestroyed to true', () {
      final doc = Doc();
      doc.destroy();
      expect(doc.isDestroyed, isTrue);
    });

    test('Doc.destroy emits destroy event', () {
      final doc = Doc();
      var destroyed = false;
      doc.on('destroy', (_) => destroyed = true);
      doc.destroy();
      expect(destroyed, isTrue);
    });
  });
}
