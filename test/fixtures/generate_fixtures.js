/**
 * Generates reference byte fixtures from the JS Yjs implementation.
 * Run: node test/fixtures/generate_fixtures.js > test/fixtures/fixtures.json
 */
const Y = require('../../vendor/yjs/src/index.js');
const { YType } = require('../../vendor/yjs/src/ytype.js');

const fixtures = {};

// --------------------------------------------------------------------------
// Fixture 1: Simple array insert
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    arr.insert(0, ['a', 'b', 'c']);
    fixtures['array_insert'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        content: arr.toArray(),
    };
}

// --------------------------------------------------------------------------
// Fixture 2: Array push (extends insert)
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    arr.insert(0, ['a', 'b', 'c']);
    const sv_before = Y.encodeStateVector(doc);
    arr.push([42]);
    fixtures['array_push'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        inc_update: Array.from(Y.encodeStateAsUpdate(doc, sv_before)),
        content: arr.toArray(),
    };
}

// --------------------------------------------------------------------------
// Fixture 3: Array delete
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    arr.insert(0, ['a', 'b', 'c']);
    arr.delete(1, 1); // delete 'b'
    fixtures['array_delete'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        content: arr.toArray(), // ['a','c']
    };
}

// --------------------------------------------------------------------------
// Fixture 4: Array insert at index (split)
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    arr.insert(0, ['a', 'b', 'c']);
    arr.insert(1, ['x']); // insert 'x' after 'a'
    fixtures['array_insert_at'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        content: arr.toArray(), // ['a','x','b','c']
    };
}

// --------------------------------------------------------------------------
// Fixture 5: Map (attr) operations
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const map = doc.get('map');
    map.setAttr('key1', 'hello');
    map.setAttr('key2', 123);
    map.setAttr('flag', true);
    fixtures['map_attrs'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        attrs: map.getAttrs(),
    };
}

// --------------------------------------------------------------------------
// Fixture 6: Mixed array + map on same doc
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    const map = doc.get('map');
    arr.insert(0, [1, 2, 3]);
    map.setAttr('name', 'test');
    fixtures['mixed'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        arr_content: arr.toArray(),
        map_attrs: map.getAttrs(),
    };
}

// --------------------------------------------------------------------------
// Fixture 7: Nested type
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const map = doc.get('map');
    const inner = new YType();
    map.setAttr('child', inner);
    const child = map.getAttr('child');
    child.setAttr('deep', 'value');
    fixtures['nested_type'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        deep_value: child.getAttr('deep'),
    };
}

// --------------------------------------------------------------------------
// Fixture 8: Cross-doc sync (apply update from doc1 to doc2)
// --------------------------------------------------------------------------
{
    const doc1 = new Y.Doc(); doc1.clientID = 1;
    const arr1 = doc1.get('arr');
    arr1.insert(0, [10, 20, 30]);

    const update = Y.encodeStateAsUpdate(doc1);

    const doc2 = new Y.Doc(); doc2.clientID = 2;
    doc2.get('arr');
    Y.applyUpdate(doc2, update);
    const arr2 = doc2.get('arr');

    fixtures['cross_doc_sync'] = {
        doc1_sv: Array.from(Y.encodeStateVector(doc1)),
        doc1_update: Array.from(update),
        doc2_sv_after: Array.from(Y.encodeStateVector(doc2)),
        doc2_content: arr2.toArray(),
    };
}

// --------------------------------------------------------------------------
// Fixture 9: Bidirectional sync
// --------------------------------------------------------------------------
{
    const doc1 = new Y.Doc(); doc1.clientID = 1;
    const doc2 = new Y.Doc(); doc2.clientID = 2;

    const arr1 = doc1.get('arr');
    doc2.get('arr');

    arr1.insert(0, ['from_doc1']);
    Y.applyUpdate(doc2, Y.encodeStateAsUpdate(doc1));

    const arr2 = doc2.get('arr');
    arr2.push(['from_doc2']);

    const sv1 = Y.encodeStateVector(doc1);
    Y.applyUpdate(doc1, Y.encodeStateAsUpdate(doc2, sv1));

    fixtures['bidirectional_sync'] = {
        doc1_sv: Array.from(Y.encodeStateVector(doc1)),
        doc2_sv: Array.from(Y.encodeStateVector(doc2)),
        doc1_content: arr1.toArray(),
        doc2_content: arr2.toArray(),
    };
}

// --------------------------------------------------------------------------
// Fixture 10: Empty doc
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    fixtures['empty_doc'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
    };
}

// --------------------------------------------------------------------------
// Fixture 11: Various content types
// --------------------------------------------------------------------------
{
    const doc = new Y.Doc(); doc.clientID = 1;
    const arr = doc.get('arr');
    // String, number, boolean, null, array-as-any
    arr.insert(0, ['text', 42, true, false, null, 3.14]);
    fixtures['content_types'] = {
        sv: Array.from(Y.encodeStateVector(doc)),
        update: Array.from(Y.encodeStateAsUpdate(doc)),
        content: arr.toArray(),
    };
}

console.log(JSON.stringify(fixtures, null, 2));
