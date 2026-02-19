# Changelog

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
