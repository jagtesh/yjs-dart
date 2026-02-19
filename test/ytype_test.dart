/// Tests for YType user-facing API methods.
///
/// These tests verify that the array, map, text, and clone operations
/// on YType work correctly, including cross-doc sync via update encoding.
library;

import 'package:test/test.dart';
import 'package:yjs_dart/src/utils/doc.dart';
import 'package:yjs_dart/src/utils/id.dart' show findRootTypeKey;
import 'package:yjs_dart/src/utils/updates.dart';
import 'package:yjs_dart/src/y_type.dart';

void main() {
  // -------------------------------------------------------------------------
  // Array operations
  // -------------------------------------------------------------------------

  group('YType array operations', () {
    test('insert and get', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 2, 3]);
      expect(arr.length, 3);
      expect(arr.get(0), 1);
      expect(arr.get(1), 2);
      expect(arr.get(2), 3);
    });

    test('insert at index', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, ['a', 'b', 'c']);
      arr.insert(1, ['x']);
      expect(arr.toArray(), ['a', 'x', 'b', 'c']);
    });

    test('push', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.push([1, 2]);
      arr.push([3]);
      expect(arr.toArray(), [1, 2, 3]);
    });

    test('unshift', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.push([2, 3]);
      arr.unshift([1]);
      expect(arr.toArray(), [1, 2, 3]);
    });

    test('delete', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 2, 3, 4, 5]);
      arr.delete(1, 2);
      expect(arr.toArray(), [1, 4, 5]);
      expect(arr.length, 3);
    });

    test('delete single element', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, ['a', 'b', 'c']);
      arr.delete(1);
      expect(arr.toArray(), ['a', 'c']);
    });

    test('slice', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 2, 3, 4, 5]);
      expect(arr.slice(1, 3), [2, 3]);
      expect(arr.slice(0, 2), [1, 2]);
      expect(arr.slice(3), [4, 5]);
    });

    test('slice with negative indices', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 2, 3]);
      expect(arr.slice(0, -1), [1, 2]);
    });

    test('toArray', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [10, 20, 30]);
      final a = arr.toArray();
      expect(a, [10, 20, 30]);
    });

    test('mapChildren', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 2, 3]);
      final doubled = arr.mapChildren<int>((v, _) => (v as int) * 2);
      expect(doubled, [2, 4, 6]);
    });

    test('forEachChild', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [10, 20, 30]);
      var sum = 0;
      arr.forEachChild((v, _) {
        sum += v as int;
      });
      expect(sum, 60);
    });

    test('length updates correctly', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      expect(arr.length, 0);
      arr.insert(0, [1, 2, 3]);
      expect(arr.length, 3);
      arr.delete(0, 2);
      expect(arr.length, 1);
      arr.push([4, 5]);
      expect(arr.length, 3);
    });

    test('insert mixed types', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      arr.insert(0, [1, 'hello', true, null, 3.14]);
      expect(arr.get(0), 1);
      expect(arr.get(1), 'hello');
      expect(arr.get(2), true);
      expect(arr.get(3), null);
      expect(arr.get(4), 3.14);
    });

    test('insert nested YType', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      final inner = YType();
      arr.insert(0, [inner]);
      final retrieved = arr.get(0);
      expect(retrieved, isA<YType>());
    });
  });

  // -------------------------------------------------------------------------
  // Map/attribute operations
  // -------------------------------------------------------------------------

  group('YType map/attribute operations', () {
    test('setAttr and getAttr', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('key1', 'value1');
      map.setAttr('key2', 42);
      expect(map.getAttr('key1'), 'value1');
      expect(map.getAttr('key2'), 42);
    });

    test('hasAttr', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('exists', true);
      expect(map.hasAttr('exists'), true);
      expect(map.hasAttr('missing'), false);
    });

    test('deleteAttr', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('key', 'value');
      expect(map.hasAttr('key'), true);
      map.deleteAttr('key');
      expect(map.hasAttr('key'), false);
      expect(map.getAttr('key'), null);
    });

    test('getAttrs', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('a', 1);
      map.setAttr('b', 2);
      map.setAttr('c', 3);
      final attrs = map.getAttrs();
      expect(attrs, {'a': 1, 'b': 2, 'c': 3});
    });

    test('clearAttrs', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('a', 1);
      map.setAttr('b', 2);
      expect(map.attrSize, 2);
      map.clearAttrs();
      expect(map.attrSize, 0);
      expect(map.getAttr('a'), null);
    });

    test('forEachAttr', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('x', 10);
      map.setAttr('y', 20);
      final collected = <String, Object?>{};
      map.forEachAttr((val, key, _) {
        collected[key] = val;
      });
      expect(collected, {'x': 10, 'y': 20});
    });

    test('attrKeys', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('a', 1);
      map.setAttr('b', 2);
      final keys = map.attrKeys.toList();
      expect(keys, contains('a'));
      expect(keys, contains('b'));
      expect(keys.length, 2);
    });

    test('attrValues', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('a', 10);
      map.setAttr('b', 20);
      final values = map.attrValues.toList();
      expect(values, containsAll([10, 20]));
    });

    test('attrEntries', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('x', 'hello');
      final entries = map.attrEntries.toList();
      expect(entries.length, 1);
      expect(entries[0].key, 'x');
      expect(entries[0].value, 'hello');
    });

    test('attrSize', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      expect(map.attrSize, 0);
      map.setAttr('a', 1);
      expect(map.attrSize, 1);
      map.setAttr('b', 2);
      expect(map.attrSize, 2);
      map.deleteAttr('a');
      expect(map.attrSize, 1);
    });

    test('setAttr overwrites', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('key', 'first');
      map.setAttr('key', 'second');
      expect(map.getAttr('key'), 'second');
      expect(map.attrSize, 1);
    });

    test('setAttr with null', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      map.setAttr('key', null);
      expect(map.hasAttr('key'), true);
      expect(map.getAttr('key'), null);
    });

    test('setAttr with nested types', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      final nested = YType();
      map.setAttr('nested', nested);
      final retrieved = map.getAttr('nested');
      expect(retrieved, isA<YType>());
    });

    test('nested map operations', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      final inner = YType();
      map.setAttr('inner', inner);
      final innerMap = map.getAttr('inner') as YType;
      innerMap.setAttr('deep', 'value');
      expect(innerMap.getAttr('deep'), 'value');
    });
  });

  // -------------------------------------------------------------------------
  // Combined array+map operations
  // -------------------------------------------------------------------------

  group('Combined operations', () {
    test('array of maps', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      for (var i = 0; i < 3; i++) {
        final m = YType();
        arr.push([m]);
        (arr.get(i) as YType).setAttr('value', i);
      }
      for (var i = 0; i < 3; i++) {
        expect((arr.get(i) as YType).getAttr('value'), i);
      }
    });

    test('toJson with array content', () {
      final doc = Doc();
      final arr = doc.get('test', () => YType());
      arr.insert(0, [1, 2, 3]);
      final json = arr.toJson();
      expect(json['children'], [1, 2, 3]);
    });

    test('toJson with map content', () {
      final doc = Doc();
      final map = doc.get('test', () => YType());
      map.setAttr('key', 'value');
      final json = map.toJson();
      expect((json['attrs'] as Map)['key'], 'value');
    });
  });

  // -------------------------------------------------------------------------
  // Cross-doc sync via updates
  // -------------------------------------------------------------------------

  group('Cross-doc sync', () {
    test('sync array insertions', () {
      final doc1 = Doc();
      final arr1 = doc1.get('array', () => YType());
      arr1.insert(0, [1, 2, 3]);

      // Encode doc1 state and apply to doc2
      final doc2 = Doc();
      doc2.get('array', () => YType());
      final update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      final arr2 = doc2.get('array', () => YType());
      expect(arr2.toArray(), [1, 2, 3]);
      expect(arr2.length, 3);
    });

    test('sync map operations', () {
      final doc1 = Doc();
      final map1 = doc1.get('map', () => YType());
      map1.setAttr('name', 'Alice');
      map1.setAttr('age', 30);

      final doc2 = Doc();
      doc2.get('map', () => YType());
      final update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      final map2 = doc2.get('map', () => YType());
      expect(map2.getAttr('name'), 'Alice');
      expect(map2.getAttr('age'), 30);
    });

    test('incremental sync', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final arr1 = doc1.get('array', () => YType());
      doc2.get('array', () => YType());

      // First sync
      arr1.insert(0, ['a', 'b']);
      var update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      // Second sync (diff)
      arr1.push(['c']);
      final sv = encodeStateVector(doc2);
      update = encodeStateAsUpdate(doc1, sv);
      applyUpdate(doc2, update);

      final arr2 = doc2.get('array', () => YType());
      expect(arr2.toArray(), ['a', 'b', 'c']);
    });

    test('bidirectional sync', () {
      final doc1 = Doc();
      final doc2 = Doc();
      final arr1 = doc1.get('array', () => YType());
      doc2.get('array', () => YType());

      // doc1 inserts
      arr1.insert(0, [1, 2, 3]);

      // Sync doc1 → doc2
      var update = encodeStateAsUpdate(doc1);
      applyUpdate(doc2, update);

      // doc2 pushes
      final arr2 = doc2.get('array', () => YType());
      arr2.push([4]);

      // Sync doc2 → doc1
      final sv1 = encodeStateVector(doc1);
      update = encodeStateAsUpdate(doc2, sv1);
      applyUpdate(doc1, update);

      // Both should have same content
      expect(arr1.length, arr2.length);
      // State vectors should match
      expect(
        encodeStateVector(doc1),
        encodeStateVector(doc2),
      );
    });

    test('sync state vectors match', () {
      final doc1 = Doc();
      final arr = doc1.get('test', () => YType());
      arr.insert(0, [1, 2, 3]);
      arr.setAttr('key', 'val');

      final doc2 = Doc();
      doc2.get('test', () => YType());
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      expect(
        encodeStateVector(doc1),
        encodeStateVector(doc2),
      );
    });

    test('sync with nested types', () {
      final doc1 = Doc();
      final map1 = doc1.get('map', () => YType());
      final inner = YType();
      map1.setAttr('child', inner);
      (map1.getAttr('child') as YType).setAttr('deep', 'value');

      final doc2 = Doc();
      doc2.get('map', () => YType());
      applyUpdate(doc2, encodeStateAsUpdate(doc1));

      final map2 = doc2.get('map', () => YType());
      final child2 = map2.getAttr('child');
      expect(child2, isA<YType>());
      expect((child2 as YType).getAttr('deep'), 'value');
    });
  });

  // -------------------------------------------------------------------------
  // Observer tests
  // -------------------------------------------------------------------------

  group('Observers', () {
    test('observe array insert', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      var eventReceived = false;
      arr.observe((event, tr) {
        eventReceived = true;
      });
      arr.insert(0, [1, 2, 3]);
      expect(eventReceived, true);
    });

    test('observe map set', () {
      final doc = Doc();
      final map = doc.get('map', () => YType());
      var eventReceived = false;
      map.observe((event, tr) {
        eventReceived = true;
      });
      map.setAttr('key', 'value');
      expect(eventReceived, true);
    });

    test('observe deep changes', () {
      final doc = Doc();
      final outer = doc.get('root', () => YType());
      var deepEventCount = 0;
      outer.observeDeep((events, tr) {
        deepEventCount++;
      });
      outer.setAttr('key', 'val');
      expect(deepEventCount, 1);
    });

    test('unobserve stops notifications', () {
      final doc = Doc();
      final arr = doc.get('array', () => YType());
      var count = 0;
      void handler(dynamic event, dynamic tr) {
        count++;
      }
      arr.observe(handler);
      arr.insert(0, [1]);
      expect(count, 1);
      arr.unobserve(handler);
      arr.insert(1, [2]);
      expect(count, 1); // should not have increased
    });
  });

  // -------------------------------------------------------------------------
  // Utility tests
  // -------------------------------------------------------------------------

  group('Utilities', () {
    test('cloneDoc', () {
      final doc1 = Doc();
      final arr = doc1.get('array', () => YType());
      arr.insert(0, [1, 2, 3]);
      final map = doc1.get('map', () => YType());
      map.setAttr('key', 'value');

      final doc2 = cloneDoc(doc1);
      final arr2 = doc2.get('array', () => YType());
      final map2 = doc2.get('map', () => YType());
      expect(arr2.toArray(), [1, 2, 3]);
      expect(map2.getAttr('key'), 'value');
    });

    test('toString for simple text', () {
      final doc = Doc();
      final text = doc.get('text', () => YType());
      text.insert(0, ['hello']);
      expect(text.toString(), 'hello');
    });

    test('findRootTypeKey', () {
      final doc = Doc();
      final t = doc.get('mytype', () => YType());
      expect(findRootTypeKey(t), 'mytype');
    });
  });
}
