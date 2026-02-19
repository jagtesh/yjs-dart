/// Dart translation of src/utils/meta.js
///
/// Mirrors: yjs/src/utils/meta.js (v14.0.0-22)
library;

import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../utils/id_set.dart'
    show
        IdSet,
        createIdSet,
        writeIdSet,
        readIdSet,
        diffIdSet,
        mergeIdSets,
        intersectSets,
        createInsertSetFromStructStore,
        createDeleteSetFromStructStore;
import '../utils/update_decoder.dart' show IdSetDecoderV2;

/// Yjs version.
const String yjsVersion = '14.0.0-22'; // Hardcoding based on context, will verify with vendor file.
import '../utils/update_encoder.dart' show IdSetEncoderV2;

/// Version constant.
///
/// Mirrors: `version` in meta.js
const String version = '14.0.0-22';

// ---------------------------------------------------------------------------
// ContentIds — a pair of (inserts: IdSet, deletes: IdSet)
// ---------------------------------------------------------------------------

/// A pair of insert and delete IdSets describing document content.
///
/// Mirrors: `ContentIds` typedef in meta.js
typedef ContentIds = ({IdSet inserts, IdSet deletes});

/// Create a [ContentIds] from optional insert/delete sets.
///
/// Mirrors: `createContentIds` in meta.js
ContentIds createContentIds([IdSet? inserts, IdSet? deletes]) =>
    (inserts: inserts ?? createIdSet(), deletes: deletes ?? createIdSet());

/// Create [ContentIds] from a document's struct store.
///
/// Mirrors: `createContentIdsFromDoc` in meta.js
ContentIds createContentIdsFromDoc(dynamic doc) => createContentIds(
      // ignore: avoid_dynamic_calls
      createInsertSetFromStructStore(doc.store, false),
      // ignore: avoid_dynamic_calls
      createDeleteSetFromStructStore(doc.store),
    );

/// Create [ContentIds] representing the diff between two documents.
///
/// Mirrors: `createContentIdsFromDocDiff` in meta.js
ContentIds createContentIdsFromDocDiff(dynamic docPrev, dynamic docNext) =>
    excludeContentIds(
        createContentIdsFromDoc(docPrev), createContentIdsFromDoc(docNext));

/// Exclude [excludeContent] from [content].
///
/// Mirrors: `excludeContentIds` in meta.js
ContentIds excludeContentIds(ContentIds content, ContentIds excludeContent) =>
    createContentIds(
      diffIdSet(content.inserts, excludeContent.inserts),
      diffIdSet(content.deletes, excludeContent.deletes),
    );

/// Merge multiple [ContentIds] into one.
///
/// Mirrors: `mergeContentIds` in meta.js
ContentIds mergeContentIds(List<ContentIds> contents) => createContentIds(
      mergeIdSets(contents.map((c) => c.inserts).toList()),
      mergeIdSets(contents.map((c) => c.deletes).toList()),
    );

/// Intersect two [ContentIds].
///
/// Mirrors: `intersectContentIds` in meta.js
ContentIds intersectContentIds(ContentIds setA, ContentIds setB) =>
    createContentIds(
      intersectSets(setA.inserts, setB.inserts),
      intersectSets(setA.deletes, setB.deletes),
    );

/// Write [contentIds] to [encoder].
///
/// Mirrors: `writeContentIds` in meta.js
void writeContentIds(dynamic encoder, ContentIds contentIds) {
  writeIdSet(encoder, contentIds.inserts);
  writeIdSet(encoder, contentIds.deletes);
}

/// Encode [contentIds] to binary (V2 format).
///
/// Mirrors: `encodeContentIds` in meta.js
Uint8List encodeContentIds(ContentIds contentIds) {
  final encoder = IdSetEncoderV2();
  writeContentIds(encoder, contentIds);
  return encoder.toUint8Array();
}

/// Read [ContentIds] from [decoder].
///
/// Mirrors: `readContentIds` in meta.js
ContentIds readContentIds(dynamic decoder) =>
    createContentIds(readIdSet(decoder), readIdSet(decoder));

/// Decode binary [buf] into [ContentIds].
///
/// Mirrors: `decodeContentIds` in meta.js
ContentIds decodeContentIds(Uint8List buf) =>
    readContentIds(IdSetDecoderV2(decoding.createDecoder(buf)));
