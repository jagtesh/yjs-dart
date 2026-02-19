# yjs-dart

A pure Dart port of [Yjs](https://github.com/yjs/yjs) v14.0.0-22 — a CRDT library for collaborative editing.

**No external runtime dependencies.** All `lib0` utilities are reimplemented natively in Dart.

## Quick Start

```bash
dart pub get
dart analyze
dart test
```

## Usage

```dart
import 'package:yjs_dart/yjs.dart';

final doc = Doc();
final arr = doc.get('arr', () => YType());
arr.insert(0, ['a', 'b', 'c']);

// Encode state as binary update
final update = encodeStateAsUpdate(doc);

// Apply update to another doc
final doc2 = Doc();
doc2.get('arr', () => YType());
applyUpdate(doc2, update);
```

## API Divergences from JavaScript

This port mirrors the JavaScript Yjs source 1:1 where possible. However, some APIs differ due to Dart naming conventions, visibility rules, or type system constraints.

### Functions Made File-Private (`_*` prefix)

These functions are **exported in JavaScript** but are Dart file-private (prefixed with `_`) because they are implementation details not intended for external use:

| JavaScript (public) | Dart (file-private) | File | Notes |
|---|---|---|---|
| `tryGcDeleteSet(tr, ds, gcFilter)` | `_tryGcDeleteSet(tr, ds, gcFilter)` | `transaction.dart` | Use `tryGc()` instead |
| `tryMerge(ds, store)` | `_tryMerge(ds, store)` | `transaction.dart` | Use `tryGc()` instead |
| `tryToMergeWithLefts(structs, pos)` | `_tryToMergeWithLefts(structs, pos)` | `transaction.dart` | Internal merge helper |
| `cleanupTransactions(cleanups, i)` | `_cleanupTransactions(cleanups, i)` | `transaction.dart` | Internal lifecycle |
| `writeStructs(encoder, structs, client, ranges)` | `_writeStructs(...)` | `updates.dart` | Internal encoding |
| `iterateStructsByIdSet(tr, idSet, f)` | `_iterateStructsByIdSet(tr, idSet, f)` | `transaction.dart` | Internal iteration |

### Method Renamed or Signature Changed

| JavaScript | Dart | Notes |
|---|---|---|
| `AbstractType._callObserver(tr, subs)` | `callObserver(tr, subs)` | Made non-private for Dart cross-file access |
| `content.getLength()` | `content.length` (getter) | Dart idiom for lengths |
| `content.write(encoder, offset, offsetEnd)` | `content.write(encoder, offset)` | `offsetEnd` omitted; handled by `Item.write` slice logic |
| `ContentDeleted.len` | `ContentDeleted.length` | Renamed to match Dart `length` convention |
| `Transaction.store` | `transaction.doc.store` | No direct `store` shortcut on `Transaction` |
| `findRootTypeKey(type)` | `findRootTypeKeyImpl(type)` | Injected via `setFindRootTypeKey()` to break circular imports |

### Behavior Differences

| Area | JavaScript | Dart | Notes |
|---|---|---|---|
| **Content stubs** | Native classes | `_Content*Stub` classes in `item.dart` | Forward-declared stubs break the `item.dart ↔ content.dart` circular import. Stubs hold identical data and serialize identically. |
| **GC default** | `doc.gc = true` | `Doc.gc = true` | Same default — GC runs after each transaction, converting deleted `ContentAny/String/etc` to `ContentDeleted`. |
| **Client ID** | `Math.random()`-based | Dart `Random()` UUID-based | Functionally equivalent; use `DocOpts(clientID: n)` for deterministic testing. |
| **`mergeWith` type check** | Duck-typed | Explicit `is` check | `content.mergeWith(right)` checks `right is ContentString` etc. |

### Kept Under Different Names in `content.dart`

The real `ContentDeleted` is in `content.dart`, but a minimal `_ContentDeleted` placeholder also exists in `item.dart` to avoid a circular import. Both implement `AbstractContent` identically.

## Translation Patterns

Refer to `GEMINI.md` for the full JS→Dart type mapping table and project conventions.

## Test Status

```
dart test   # 134 tests pass, 1 skipped
```

- **Skipped**: `nested type round-trip` — `readContentType` returns a structural stub (YType reconstruction is deferred)
