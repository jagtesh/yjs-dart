# Changelog

## 1.1.13

-   **Fix**: Corrected RleEncoder and RleDecoder count-by-one encoding logic to perfectly map to JavaScript Yjs's precise wire format. Fixes a critical `RangeError (index): Index out of range` crash and sync halt that occurred when reading V2 updates with runs of `Skip` or `GC` structs from JS peers like Hocuspocus.
-   **Fix**: Implemented missing "Phase 2" integration logic for `splitItem` inside `readAndApplyDeleteSet`. Remote deletions within `YText` are now correctly processed, resolving a bug where deleted text fragments duplicated/re-appeared when refreshing from persistence or applying updates across transaction boundaries.
## 1.1.12

-   **Fix**: `YText.insert` incorrectly dispatched plain strings as `ContentAny` generic array containers rather than true `ContentString` CRDT objects. This caused `YText.length` to evaluate to the number of insertions rather than the true string length, causing exponential string duplication bugs in Flutter/React TipTap synchronization where JS clients would aggressively rewrite invalid string generic instances. `YText.insert` is now properly hardwired to use `ContentString`.

-   **Feature**: Added `_prelimContent` offline cache to `YMap` and `YArray` which allows nested insertion and setup of shared types before they are integrated into a `Doc`.
-   **Fix**: Added a `lastId` getter to `AbstractStruct` and enhanced `Item` constructor resolution logic to safely typecast `parent` as `AbstractType`, preventing dynamic cast failures.

## 1.1.10

-   **Fix**: Fixed a critical serialization bug where `YMap`, `YArray`, and `YText` failed to set their `legacyTypeRef` in the constructor, causing them to all be written to the binary stream as `YXmlFragment` (type ID 4). They now correctly serialize with `typeRefMap` (1), `typeRefArray` (0), and `typeRefText` (2).

-   **Fix**: Fixed an off by 1 bug that occured when removing an item from YArray.


## 1.1.8

-   **Fix**: `yjsReadUpdate` now executes the `pendingStructs` retry **outside** the `transact` callback. Previously calling `applyUpdateV2` inside the callback caused unbounded recursion (the nested call reused the same transaction via `doc.currentTransaction != null`, and if the retried update itself had unresolved deps it would set `retry=true` again and recurse infinitely — the root cause of the page-click hang).

## 1.1.7

-   **Fix**: `Skip.integrateInto` was calling `addToIdSet` as a method on `IdSet` — it is a free function. Fixed to call `addToIdSet(store.skips, client, clock, length)` correctly.

## 1.1.6

-   **Fix**: `encodeStateAsUpdateV2` no longer includes `store.pendingDs`/`pendingStructs` when using a V1 encoder. Both pending fields are stored in V2 format internally (via `mergeUpdatesV2`); mixing them into a V1 merge caused `readItemContent` to read garbage content refs (e.g. ref=24) and crash with a `RangeError`. `writeStateAsUpdate` already captures all integrated state, so the pending fields can be safely skipped for V1 snapshots.
-   **Resilience**: `readItemContent` now throws a human-readable `StateError` on out-of-range content refs instead of a bare `RangeError`.

## 1.1.5

-   **Resilience**: `readVarString` now uses `utf8.decode(..., allowMalformed: true)` to tolerate invalid UTF-8 sequences (common in cross-platform CRDT string handling), preventing `FormatException` crashes.
-   **Resilience**: `Observable.emit` catches and logs listener errors (e.g. signature mismatches) instead of crashing the app. This safeguards `Doc` update propogation.

## 1.1.4

-   **Fix**: `StructRange.refs` was created as a fixed-length list via `List.filled()`, causing `refs.clear()` to throw `"Cannot clear a fixed-length list"` inside `_integrateStructs.addStackToRestSS()`. This silently dropped specific update packets (e.g. certain journal pages would never sync). Fixed by adding `growable: true` and making `refs` non-final.
-   **Fix**: `ContentType.delete()` called nonexistent `store.gc` field → `NoSuchMethodError` when any nested YType item gets deleted. Now correctly adds already-deleted children to `transaction.mergeStructs` and calls `transaction.changed.remove(type)`.
-   **Fix**: `ContentType.gc()` now nulls `type.yStart`, traverses yMap entries via their full left-chain, and calls `type.yMap.clear()` — matching the JS Yjs source.
-   **Resilience**: `readSyncStep2` and `callEventHandlerListeners` now print a warning on failure instead of crashing the app or silently discarding the error.

## 1.1.3

-   **Fix**: `GC.getMissing()` added — was missing, causing `NoSuchMethodError` during struct integration (`_integrateStructs` calls it dynamically on all struct types).
-   **Fix**: `readStructSet` auto-registers unknown root-level parent types as `YMap` instead of silently dropping their items. Mirrors JS Yjs lazy type creation.
-   **Silent**: Commented out pre-existing library `print()` calls in `sync.dart`, `event_handler.dart`, and `abstract_type.dart` so Flutter apps stay clean in production.
-   **Tests**: Added `test/regression_test.dart` with 17 regression tests covering the above fixes, `Doc.get` lazy creation, multi-root sync, and binary round-trips.

## 1.1.2

-   **Exports**: Exposed `lib0` utilities (`Observable`, `encoding`, `decoding`) for advanced usage.

## 1.1.1

-   **Exports**: Exposed `y-protocols` (Sync, Awareness, Auth) via `yjs_dart.dart`.
    -   **Auth**: `writePermissionDenied`, `readAuthMessage`, `messagePermissionDenied`.
    -   **Awareness**: `Awareness`, `encodeAwarenessUpdate`, `applyAwarenessUpdate`, `removeAwarenessStates`, `modifyAwarenessUpdate`.
    -   **Sync**: `writeSyncStep1`, `writeSyncStep2`, `readSyncStep1`, `readSyncStep2`, `writeUpdate`, `readUpdate`, `readSyncMessage`.

## 1.1.0

-   **Refactor**: Replaced the monolithic `YType` with strict subclasses: `YArray`, `YMap`, `YText`, and `YXmlFragment`.
-   **Type Safety**: significantly improved type safety by removing `dynamic` calls in internal structures.
-   **API Update**: `Doc.get` now offers typed helpers: `getArray`, `getMap`, `getText`.
-   **Compatibility**: Maintained full binary compatibility with Yjs v14.0.0-22.
-   **Fix**: Resolved `avoid_dynamic_calls` lints in core structural classes.

## 1.0.0

-   Initial stable release.
-   Full implementation of Yjs CRDT algorithms (v14.0.0-22).
-   Support for `YText`, `YArray`, `YMap`, `YXml` via `YType`.
-   Binary compatibility with Yjs v1 & v2 encoding.
-   Complete Sync, Awareness, and Auth protocols.
-   Implemented `toDelta` for rich text export.
