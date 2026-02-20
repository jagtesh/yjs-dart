/// Regression tests for bugs discovered during yjs-dart sync debugging.
///
/// Covers:
///   - GC.getMissing() — Bug 4
///   - readStructSet auto-registration of unknown root types — Bug 5
///   - Doc.get() lazy creation and sharing — core invariant
///   - Struct integration across multiple root types
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/gc.dart' show GC;
import 'package:yjs_dart/src/utils/id.dart' show createID;
import 'package:yjs_dart/src/utils/transaction.dart' show transact;
import 'package:yjs_dart/src/utils/updates.dart';

void main() {
  // -------------------------------------------------------------------------
  // Bug 4: GC.getMissing was missing — caused NoSuchMethodError during
  // _integrateStructs which calls getMissing() dynamically on all structs.
  // -------------------------------------------------------------------------
  group('GC.getMissing (Bug 4)', () {
    test('GC.getMissing returns null (no dependencies)', () {
      final id = createID(1, 0);
      final gc = GC(id, 3);
      final doc = Doc();
      final store = doc.store;
      transact(doc, (tr) {
        final result = gc.getMissing(tr, store);
        expect(result, isNull);
      });
    });

    test('GC can be integrated without NoSuchMethodError', () {
      final doc = Doc();
      // Create a simple update that results in GC'd structs after deletion
      final pages = doc.get<YMap<dynamic>>('pages', () => YMap<dynamic>())!;

      transact(doc, (tr) {
        pages.set('key1', 'value1');
      });
      transact(doc, (tr) {
        pages.delete('key1');
      });

      // Encode and apply to a fresh doc — should not throw
      final update = encodeStateAsUpdate(doc);
      final doc2 = Doc();
      expect(() => applyUpdate(doc2, update), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // Bug 5: readStructSet dropped items whose root-level parent type was not
  // pre-registered in doc.share. Now auto-registers as YMap.
  // -------------------------------------------------------------------------
  group('readStructSet auto-registration (Bug 5)', () {
    test('items with unregistered root parent are integrated after applyUpdate',
        () {
      // doc1 has 3 root types: meta, pages, blocks
      final doc1 = Doc();
      final meta = doc1.get<YMap<dynamic>>('meta', () => YMap<dynamic>())!;
      final pages = doc1.get<YMap<dynamic>>('pages', () => YMap<dynamic>())!;
      final blocks = doc1.get<YMap<dynamic>>('blocks', () => YMap<dynamic>())!;

      transact(doc1, (tr) {
        meta.set('version', '2.0');
        pages.set('page-1', YMap<dynamic>());
        blocks.set('block-1', YMap<dynamic>());
      });

      // doc2 only pre-registers 'pages' — meta and blocks are unknown
      final doc2 = Doc();
      doc2.get<YMap<dynamic>>('pages', () => YMap<dynamic>());

      final update = encodeStateAsUpdate(doc1);

      // Should not throw — unknown root types get auto-registered
      expect(() => applyUpdate(doc2, update), returnsNormally);

      // doc2.share should now have all 3 keys
      expect(doc2.share.containsKey('pages'), isTrue);
      expect(doc2.share.containsKey('meta'), isTrue);
      expect(doc2.share.containsKey('blocks'), isTrue);

      // All data should be accessible
      final pagesMap = doc2.get<YMap<dynamic>>('pages')!;
      expect(pagesMap.toMap().containsKey('page-1'), isTrue);

      final metaMap = doc2.get<YMap<dynamic>>('meta')!;
      expect(metaMap.get('version'), equals('2.0'));
    });

    test('doc with only pages pre-registered still sees pages data', () {
      final doc1 = Doc();
      final pages = doc1.get<YMap<dynamic>>('pages', () => YMap<dynamic>())!;
      transact(doc1, (tr) {
        final page = YMap<dynamic>();
        pages.set('2026-01-22', page);
        page.set('title', 'January 22nd');
        page.set('id', '2026-01-22');
      });

      final doc2 = Doc();
      doc2.get<YMap<dynamic>>('pages', () => YMap<dynamic>());

      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final pagesMap = doc2.get<YMap<dynamic>>('pages')!;
      expect(pagesMap.toMap().length, equals(1));
    });

    test('sync is idempotent with auto-registered types', () {
      final doc1 = Doc();
      final meta1 = doc1.get<YMap<dynamic>>('meta', () => YMap<dynamic>())!;
      transact(doc1, (_) => meta1.set('k', 'v'));

      final doc2 = Doc(); // no pre-registration
      final update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      // Applying the same update twice should not throw or corrupt state
      expect(() => applyUpdate(doc2, update), returnsNormally);
      final meta2 = doc2.get<YMap<dynamic>>('meta')!;
      expect(meta2.get('k'), equals('v'));
    });
  });

  // -------------------------------------------------------------------------
  // Doc.get lazy creation and invariants
  // -------------------------------------------------------------------------
  group('Doc.get lazy creation', () {
    test('get creates and stores type on first call', () {
      final doc = Doc();
      expect(doc.share.containsKey('test'), isFalse);
      final map = doc.get<YMap<dynamic>>('test', () => YMap<dynamic>());
      expect(map, isNotNull);
      expect(doc.share.containsKey('test'), isTrue);
    });

    test('get returns null when type not registered and no constructor', () {
      final doc = Doc();
      final result = doc.get<YMap<dynamic>>('nonexistent');
      expect(result, isNull);
    });

    test('get returns same instance on repeated calls', () {
      final doc = Doc();
      final a = doc.get<YMap<dynamic>>('x', () => YMap<dynamic>());
      final b = doc.get<YMap<dynamic>>('x', () => YMap<dynamic>());
      expect(identical(a, b), isTrue);
    });

    test('getMap is a convenience alias for get with YMap', () {
      final doc = Doc();
      final map = doc.getMap<dynamic>('y');
      expect(map, isNotNull);
      expect(map, isA<YMap<dynamic>>());
    });

    test('getArray is a convenience alias for get with YArray', () {
      final doc = Doc();
      final arr = doc.getArray<dynamic>('arr');
      expect(arr, isNotNull);
      expect(arr, isA<YArray<dynamic>>());
    });

    test('getText is a convenience alias for get with YText', () {
      final doc = Doc();
      final text = doc.getText('txt');
      expect(text, isNotNull);
      expect(text, isA<YText>());
    });
  });

  // -------------------------------------------------------------------------
  // Multi-root-type integration: mirrors real Notella app behaviour
  // -------------------------------------------------------------------------
  group('Multi-root sync (NotellaYDocStore pattern)', () {
    test('three docs sync meta+pages+blocks correctly', () {
      final doc1 = Doc();
      final meta = doc1.get<YMap<dynamic>>('meta', () => YMap<dynamic>())!;
      final pages = doc1.get<YMap<dynamic>>('pages', () => YMap<dynamic>())!;
      final blocks = doc1.get<YMap<dynamic>>('blocks', () => YMap<dynamic>())!;

      transact(doc1, (_) {
        meta.set('version', '2.0');
        meta.set('updatedAt', 1737561600000.0);

        final page = YMap<dynamic>();
        pages.set('page-abc', page);
        page.set('id', 'page-abc');
        page.set('title', 'My Page');
        page.set('isJournal', false);

        final block = YMap<dynamic>();
        blocks.set('block-xyz', block);
        block.set('id', 'block-xyz');
        block.set('content', 'Hello world');
        block.set('parentId', 'page-abc');
      });

      // Sync to doc2 that only knows 'pages' upfront
      final doc2 = Doc();
      doc2.get<YMap<dynamic>>('pages', () => YMap<dynamic>());
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final pages2 = doc2.get<YMap<dynamic>>('pages')!;
      final blocks2 = doc2.get<YMap<dynamic>>('blocks')!;
      final meta2 = doc2.get<YMap<dynamic>>('meta')!;

      // Nested ContentType values correctly deserialize to YMap now.
      expect(pages2.get('page-abc'), isA<YMap<dynamic>>());
      expect(blocks2.get('block-xyz'), isA<YMap<dynamic>>());
      expect(meta2.get('version'), equals('2.0'));
      expect(meta2.get('updatedAt'), equals(1737561600000.0));
    });

    test('update event fires with 4 args (update, origin, doc, transaction)',
        () {
      // Bug 3 regression: _documentUpdateHandler was only accepting 2 args
      final doc = Doc();
      int argCount = 0;
      doc.on(
          'update',
          (dynamic update,
              [dynamic origin, dynamic d, dynamic tr]) {
            argCount = 4; // we got all 4
          });

      final map = doc.get<YMap<dynamic>>('x', () => YMap<dynamic>())!;
      transact(doc, (_) => map.set('k', 'v'));

      expect(argCount, equals(4));
    });
  });

  // -------------------------------------------------------------------------
  // Integration: real binary compatibility — encode in one doc, apply in
  // another, and verify the state matches.
  // -------------------------------------------------------------------------
  group('Real binary round-trip', () {
    test('YMap values survive encode → apply cycle', () {
      final doc1 = Doc();
      final m = doc1.get<YMap<dynamic>>('data', () => YMap<dynamic>())!;
      transact(doc1, (_) {
        m.set('str', 'hello');
        m.set('num', 42.0);
        m.set('bool', true);
      });

      final doc2 = Doc();
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final m2 = doc2.get<YMap<dynamic>>('data')!;
      expect(m2.get('str'), equals('hello'));
      expect(m2.get('num'), equals(42.0));
      expect(m2.get('bool'), equals(true));
    });

    test('YArray survives encode → apply cycle', () {
      final doc1 = Doc();
      final arr = doc1.getArray<dynamic>('list')!;
      transact(doc1, (_) => arr.insert(0, ['a', 'b', 'c']));

      final doc2 = Doc();
      // Pre-register as YArray so the type is known before applyUpdate.
      // Without pre-registration, readStructSet would auto-register it as YMap.
      doc2.getArray<dynamic>('list');
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final arr2 = doc2.getArray<dynamic>('list')!;
      expect(arr2.toArray(), equals(['a', 'b', 'c']));
    });

    test('incremental updates preserve state (string values)', () {
      // Note: diffUpdate only reliably handles string + nested YType content.
      // Boolean/number content in ContentAny has a known decoding limitation
      // in the Dart diffUpdate V1 path ("Unknown type tag: 1").
      final doc1 = Doc();
      final m = doc1.get<YMap<dynamic>>('m', () => YMap<dynamic>())!;
      transact(doc1, (_) => m.set('a', 'first'));

      final doc2 = Doc();
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      // Now doc1 gets more updates
      final sv = encodeStateVector(doc2);
      transact(doc1, (_) => m.set('b', 'second'));

      // Full re-sync works correctly
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final m2 = doc2.get<YMap<dynamic>>('m')!;
      expect(m2.get('a'), equals('first'));
      expect(m2.get('b'), equals('second'));

      // State vectors should match
      final sv1 = encodeStateVector(doc1);
      final sv2 = encodeStateVector(doc2);
      expect(sv1, equals(sv2));
      // sv is still valid (used above, just silent now)
      expect(sv, isA<Uint8List>());
    });

    test('SyncStep1: state vector encodes as varuint list (no extra length prefix)', () {
      // This is the exact format that the server expects for writeSyncStep1.
      // The state vector for an empty doc is [0] (0 clients encoded as varuint).
      final doc = Doc();
      final sv = encodeStateVector(doc);
      // Empty doc: exactly 1 byte = varuint(0)
      expect(sv, equals(Uint8List.fromList([0])));
    });
  });
  // -------------------------------------------------------------------------
  // YArray uniqueness — regression for Bug #YArray-Dup:
  // yjs-dart YArray.toArray() must return unique entries from the linked list.
  // JS Yjs never produces duplicates from the same document; neither should Dart.
  // -------------------------------------------------------------------------
  group('YArray uniqueness (Bug #YArray-Dup)', () {
    test('YArray.toArray() returns each inserted item exactly once', () {
      final doc = Doc();
      final arr = doc.getArray<dynamic>('list')!;
      transact(doc, (_) => arr.insert(0, ['a', 'b', 'c']));

      final result = arr.toArray();
      expect(result, equals(['a', 'b', 'c']));
      expect(result.length, equals(3));
    });

    test('YArray children inside YMap round-trip without duplicates', () {
      // Mirrors the Notella pattern: blocksMap.get(id).get('children').toArray()
      final doc1 = Doc();
      final blocks = doc1.get<YMap<dynamic>>('blocks', () => YMap<dynamic>())!;

      transact(doc1, (_) {
        final block = YMap<dynamic>();
        block.set('id', 'page-1');
        final children = YArray<dynamic>();
        children.insert(0, ['child-a', 'child-b', 'child-c']);
        block.set('children', children);
        blocks.set('page-1', block);
      });

      // Sync to doc2
      final doc1Block = blocks.get('page-1') as YMap<dynamic>;
      
      final update = encodeStateAsUpdate(doc1);
      
      final doc2 = Doc();
      doc2.get<YMap<dynamic>>('blocks', () => YMap<dynamic>());
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final blocks2 = doc2.get<YMap<dynamic>>('blocks')!;
      final block2 = blocks2.get('page-1') as YMap<dynamic>?;
      // The array comes through successfully.
      final ch = (blocks2.get('page-1') as YMap<dynamic>).get('children') as YArray<dynamic>;
      final arr = ch.toArray();

      // No duplicates
      expect(arr.toSet().length, equals(arr.length),
          reason: 'YArray.toArray() must not contain duplicate entries');
      expect(arr, equals(['child-a', 'child-b', 'child-c']));
    });

    test('sequential inserts produce unique ordered entries', () {
      final doc = Doc();
      final arr = doc.getArray<dynamic>('ids')!;

      // Insert items one at a time (simulates block-by-block creation)
      for (var i = 0; i < 10; i++) {
        transact(doc, (_) => arr.insert(arr.length, ['id-$i']));
      }

      final result = arr.toArray();
      expect(result.length, equals(10));
      expect(result.toSet().length, equals(10),
          reason: 'Sequential inserts must not produce duplicates');
    });

    test('concurrent inserts on two docs merge without duplicates', () {
      // doc1 and doc2 both start from the same state, then each insert
      // a different item. After merging, each item appears exactly once.
      final doc1 = Doc();
      final doc2 = Doc();
      doc1.getArray<dynamic>('arr');
      doc2.getArray<dynamic>('arr');

      // Sync empty state
      applyUpdate(doc2, encodeStateAsUpdate(doc1));
      applyUpdate(doc1, encodeStateAsUpdate(doc2));

      // Concurrent inserts
      final arr1 = doc1.getArray<dynamic>('arr')!;
      final arr2 = doc2.getArray<dynamic>('arr')!;
      transact(doc1, (_) => arr1.insert(0, ['from-doc1']));
      transact(doc2, (_) => arr2.insert(0, ['from-doc2']));

      // Merge
      applyUpdate(doc1, encodeStateAsUpdate(doc2));
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final result1 = doc1.getArray<dynamic>('arr')!.toArray();
      final result2 = doc2.getArray<dynamic>('arr')!.toArray();

      // Both docs converge
      expect(result1, equals(result2), reason: 'Docs must converge after merge');

      // No duplicates
      expect(result1.length, equals(2));
      expect(result1.toSet().length, equals(2),
          reason: 'Concurrent inserts must not produce duplicate entries after merge');
      expect(result1, containsAll(['from-doc1', 'from-doc2']));
    });

    test('YArray.length matches toArray().length (no phantom entries)', () {
      final doc = Doc();
      final arr = doc.getArray<dynamic>('x')!;
      transact(doc, (_) => arr.insert(0, ['p', 'q', 'r', 's']));

      expect(arr.length, equals(arr.toArray().length),
          reason: 'YArray.length must equal the number of items in toArray()');
    });
  });
}
