# Changelog

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
