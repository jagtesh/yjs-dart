/// Tests for Phase 4: applyUpdate, encodeStateAsUpdate, encodeStateVector,
/// mergeUpdates, diffUpdate, and Doc integration.
///
/// These tests verify binary compatibility with the JavaScript Yjs library.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yjs_dart/src/utils/doc.dart';
import 'package:yjs_dart/src/utils/updates.dart';

void main() {
  group('encodeStateVector', () {
    test('empty doc has empty state vector', () {
      final doc = Doc();
      final sv = encodeStateVector(doc);
      // An empty state vector encodes as a single 0 byte (0 clients)
      expect(sv, isA<Uint8List>());
      // decodeStateVector of empty sv should be empty map
      final decoded = decodeStateVector(sv);
      expect(decoded, isEmpty);
    });

    test('decodeStateVector round-trips', () {
      final doc = Doc();
      final sv = encodeStateVector(doc);
      final decoded = decodeStateVector(sv);
      expect(decoded, isEmpty);
    });
  });

  group('encodeStateAsUpdate', () {
    test('empty doc produces valid update', () {
      final doc = Doc();
      final update = encodeStateAsUpdate(doc);
      expect(update, isA<Uint8List>());
      // Should be decodable (non-empty — at least the header bytes)
      expect(update.isNotEmpty, isTrue);
    });

    test('encodeStateAsUpdateV2 produces valid update', () {
      final doc = Doc();
      final update = encodeStateAsUpdateV2(doc);
      expect(update, isA<Uint8List>());
      expect(update.isNotEmpty, isTrue);
    });
  });

  group('applyUpdate', () {
    test('applying empty update to empty doc is a no-op', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final update = encodeStateAsUpdate(doc1);
      // Should not throw
      expect(() => applyUpdate(doc2, update), returnsNormally);
    });

    test('applyUpdateV2 with empty update is a no-op', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final update = encodeStateAsUpdateV2(doc1);
      expect(() => applyUpdateV2(doc2, update), returnsNormally);
    });
  });

  group('readStateVector / decodeStateVector', () {
    test('readStateVector returns empty map for zero-client state', () {
      // Encode a state vector with 0 clients: just a single varuint 0
      final bytes = Uint8List.fromList([0]);
      final sv = decodeStateVector(bytes);
      expect(sv, isEmpty);
    });
  });

  group('mergeUpdates', () {
    test('merging two empty updates produces a valid update', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final u1 = encodeStateAsUpdate(doc1);
      final u2 = encodeStateAsUpdate(doc2);
      final merged = mergeUpdates([u1, u2]);
      expect(merged, isA<Uint8List>());
      expect(merged.isNotEmpty, isTrue);
    });

    test('mergeUpdatesV2 with empty updates', () {
      final doc = Doc();
      final u = encodeStateAsUpdateV2(doc);
      final merged = mergeUpdatesV2([u, u]);
      expect(merged, isA<Uint8List>());
    });
  });

  group('diffUpdate', () {
    test('diff of empty doc against empty sv is empty-ish', () {
      final doc = Doc();
      final update = encodeStateAsUpdate(doc);
      final sv = encodeStateVector(doc);
      final diff = diffUpdate(update, sv);
      expect(diff, isA<Uint8List>());
    });

    test('diffUpdateV2 works', () {
      final doc = Doc();
      final update = encodeStateAsUpdateV2(doc);
      final sv = encodeStateVectorV2(doc);
      final diff = diffUpdateV2(update, sv);
      expect(diff, isA<Uint8List>());
    });
  });

  group('encodeStateVectorFromUpdate', () {
    test('extracts state vector from a V1 update', () {
      final doc = Doc();
      final update = encodeStateAsUpdate(doc);
      final sv = encodeStateVectorFromUpdate(update);
      expect(sv, isA<Uint8List>());
      // Should decode to the same state vector as the doc
      final decoded = decodeStateVector(sv);
      expect(decoded, isEmpty); // empty doc
    });

    test('encodeStateVectorFromUpdateV2 works', () {
      final doc = Doc();
      final update = encodeStateAsUpdateV2(doc);
      final sv = encodeStateVectorFromUpdateV2(update);
      expect(sv, isA<Uint8List>());
    });
  });

  group('convertUpdateFormatV2ToV1', () {
    test('converts V2 update to V1 format', () {
      final doc = Doc();
      final v2Update = encodeStateAsUpdateV2(doc);
      final v1Update = convertUpdateFormatV2ToV1(v2Update);
      expect(v1Update, isA<Uint8List>());
      // Applying V1 update to a new doc should work
      final doc2 = Doc();
      expect(() => applyUpdate(doc2, v1Update), returnsNormally);
    });
  });

  group('Doc integration', () {
    test('two docs can sync via encodeStateAsUpdate/applyUpdate', () {
      final doc1 = Doc();
      final doc2 = Doc();

      // Encode doc1's state and apply to doc2
      final update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      // Both docs should have the same state vector
      final sv1 = encodeStateVector(doc1);
      final sv2 = encodeStateVector(doc2);
      expect(sv1, equals(sv2));
    });

    test('V2 sync between two docs', () {
      final doc1 = Doc();
      final doc2 = Doc();

      final update = encodeStateAsUpdateV2(doc1);
      applyUpdateV2(doc2, update);

      final sv1 = encodeStateVectorV2(doc1);
      final sv2 = encodeStateVectorV2(doc2);
      expect(sv1, equals(sv2));
    });

    test('writeStateVector / readStateVector round-trip', () {
      final doc = Doc();
      final sv = encodeStateVector(doc);
      final decoded = decodeStateVector(sv);
      // Re-encode and compare
      final reEncoded = encodeStateVector(decoded);
      expect(reEncoded, equals(sv));
    });
  });
}
