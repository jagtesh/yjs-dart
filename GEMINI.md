# Yjs Dart — Agent Guidelines

## Project Overview

A pure Dart translation of the [Yjs](https://github.com/yjs/yjs) CRDT library, pinned to:
- **Yjs**: `v14.0.0-22` (vendor/yjs)
- **y-protocols**: `v1.0.5` (vendor/y-protocols)

**No external runtime dependencies.** All `lib0` utilities are reimplemented natively.

## Quick Start

```bash
dart pub get
dart analyze
dart test
```

## Project Structure

```
lib/
  yjs.dart                    # Public barrel exports (mirrors src/index.js)
  src/
    internals.dart            # Internal barrel exports (mirrors src/internals.js)
    y_type.dart               # YType abstract base class
    lib0/                     # Native lib0 utilities (no external deps)
      binary.dart             # Bit constants
      decoding.dart           # Binary decoder (LEB128, strings, floats, any)
      encoding.dart           # Binary encoder (LEB128, strings, floats, any)
      map_utils.dart          # Map utilities
      math_utils.dart         # Math utilities
      observable.dart         # Event emitter
      random.dart             # Random numbers, UUID v4
    structs/
      abstract_struct.dart    # AbstractStruct base class
      content.dart            # All Content* types (9 types in one file)
      gc.dart                 # GC (garbage-collected tombstone)
      item.dart               # Item (core CRDT item, doubly-linked list)
      skip.dart               # Skip (gap placeholder)
    utils/
      delta_helpers.dart      # Delta computation utilities
      doc.dart                # Doc (root Yjs document)
      event_handler.dart      # EventHandler (typed event system)
      id.dart                 # ID (client, clock pair)
      id_map.dart             # IdMap (ID range → value map)
      id_set.dart             # IdSet (ID range set)
      is_parent_of.dart       # isParentOf utility
      logging.dart            # logType debug utility
      meta.dart               # Version constant
      relative_position.dart  # RelativePosition, AbsolutePosition
      snapshot.dart           # Snapshot (point-in-time capture)
      struct_set.dart         # StructSet utilities
      struct_store.dart       # StructStore (struct storage by client)
      transaction.dart        # Transaction (groups changes)
      undo_manager.dart       # UndoManager (undo/redo)
      update_decoder.dart     # UpdateDecoderV1/V2 with RLE decoders
      update_encoder.dart     # UpdateEncoderV1/V2 with RLE encoders
      updates.dart            # Update utilities (stub)
      y_event.dart            # YEvent (change descriptor)
    protocols/
      auth.dart               # y-protocols/auth.js
      awareness.dart          # y-protocols/awareness.js
      sync.dart               # y-protocols/sync.js
vendor/
  yjs/                        # Yjs source (git submodule, v14.0.0-22)
  y-protocols/                # y-protocols source (git submodule, v1.0.5)
```

## Translation Patterns

### JS → Dart Naming

| JavaScript | Dart |
|-----------|------|
| `PascalCase.js` | `snake_case.dart` |
| `camelCase` functions | `camelCase` functions |
| `class Foo` | `class Foo` |
| `export const X = 0` | `const int x = 0;` |
| `/** @type {Map<string, any>} */` | `Map<String, Object?>` |

### Type Mapping

| JavaScript | Dart |
|-----------|------|
| `number` | `int` or `double` |
| `string` | `String` |
| `boolean` | `bool` |
| `any` | `Object?` |
| `Uint8Array` | `Uint8List` |
| `Map<string, T>` | `Map<String, T>` |
| `Array<T>` | `List<T>` |
| `null \| T` | `T?` |

### Circular Dependencies

Yjs has circular imports (e.g., `Doc ↔ Transaction ↔ StructStore`). In Dart, we break these with:
- `dynamic` typed fields for cross-referencing types
- Late binding via method calls rather than direct field access
- The `internals.dart` barrel for shared access

This causes `avoid_dynamic_calls` lint warnings — these are **expected and intentional**.

### Struct Store Invariants

- `StructStore.clients` maps `clientId → sorted List<AbstractStruct>` by clock
- Structs must be contiguous: `structs[i].id.clock + structs[i].length == structs[i+1].id.clock`
- `findIndexSS` uses a pivoted binary search (mirrors JS implementation exactly)

### Content Types

All content types implement `AbstractContent` (from `item.dart`):

| Ref# | Class | Description |
|------|-------|-------------|
| 1 | `ContentDeleted` | Tombstone |
| 2 | `ContentJSON` | Legacy JSON |
| 3 | `ContentBinary` | Uint8List |
| 4 | `ContentString` | String |
| 5 | `ContentEmbed` | Embedded object |
| 6 | `ContentFormat` | Text format mark |
| 7 | `ContentType` | Nested YType |
| 8 | `ContentAny` | Any JSON-compatible |
| 9 | `ContentDoc` | Sub-document |

### Encoder/Decoder Architecture

V1 (simple varUint) and V2 (highly compressed) encoders/decoders:

| Codec | Purpose |
|-------|---------|
| `RleEncoder/Decoder` | Run-length encoding for uint8 |
| `UintOptRleEncoder/Decoder` | Optional RLE for unsigned ints |
| `IntDiffOptRleEncoder/Decoder` | Diff + optional RLE for signed ints |
| `StringEncoder/Decoder` | String deduplication |

## What Works ✅

- All `lib0` utilities (binary, encoding, decoding, observable, random, map, math)
- `ID`, `IdSet`, `IdMap` — core CRDT identity types
- `UpdateEncoderV1/V2` and `UpdateDecoderV1/V2` — binary protocol codecs
- `StructStore` — struct storage with binary search
- `GC`, `Skip` — simple struct types
- `Snapshot`, `RelativePosition`, `AbsolutePosition` — structural stubs
- `Doc` — document root with Observable, transaction support
- `Awareness`, `Sync`, `Auth` protocols — structural stubs
- `UndoManager` — structural stub

## What Needs Completion ⚠️

| Component | Status | Notes |
|-----------|--------|-------|
| `Item.integrate()` | Stub | Full CRDT conflict resolution algorithm |
| `Item.write()` | Stub | Binary serialization |
| `Item.splice()` | Stub | Split item at offset |
| `Transaction` cleanup | Stub | Observer calls, afterTransaction hooks |
| `YType` subclasses | Missing | YMap, YArray, YText, YXmlElement, etc. |
| `applyUpdate` | Missing | Apply binary update to Doc |
| `encodeStateAsUpdate` | Missing | Encode Doc state as binary |
| `readSyncStep1/2` | Stub | Full sync protocol |
| `UndoManager.undo/redo` | Stub | Full undo/redo logic |
| `Snapshot.snapshotContainsUpdate` | Stub | Snapshot comparison |
| `diffDocsToDelta` | Stub | Delta computation |

## Sync with Upstream

To update to a new Yjs version:

1. Update the submodule: `cd vendor/yjs && git fetch && git checkout <new-tag>`
2. Check the JS diff: `git -C vendor/yjs diff <old-tag> <new-tag> -- src/`
3. Apply corresponding changes to the Dart files (1:1 structural mapping)
4. Run `dart analyze && dart test`

## Analysis Status

```
dart analyze: 88 info-level issues (no errors, no warnings)
```

All infos are style lints:
- `sort_constructors_first` — constructor ordering
- `avoid_dynamic_calls` — intentional for circular dep workarounds
- `annotate_overrides` — missing @override annotations
