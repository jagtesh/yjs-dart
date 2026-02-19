# Yjs Dart

A pure Dart port of the [Yjs](https://github.com/yjs/yjs) CRDT library. This project follows the official JavaScript implementation closely to ensure compatibility and correctness.

**Parity Status**: Based on `yjs` v14.0.0-22 and `y-protocols` v1.0.5.

## Features

-   **Full CRDT support**: Text, Arrays, Maps, and XML elements.
-   **Binary compatibility**: 100% compatible with Yjs binary encoding (v1 & v2).
-   **Protocols**: Sync, Awareness, and Auth protocols implemented.
-   **Zero dependencies**: Built with standard Dart libraries only.
-   **Undo/Redo**: Full `UndoManager` implementation.

## Installation

```bash
dart pub add yjs
```

## Usage

```dart
import 'package:yjs/yjs.dart';

final doc = Doc();
final text = doc.getText('name');

text.observe((event, transaction) {
  print(text.toString());
});

text.insert(0, 'Hello World');
```

## Javascript Parity

This library aims for 1:1 parity with the official JavaScript client.

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **Doc** | ✅ Supported | Full implementation |
| **Transaction** | ✅ Supported | Full implementation |
| **Shared Types** | ✅ Supported | `YArray`, `YMap`, `YText`, `YXml` supported via `YType` |
| **StructStore** | ✅ Supported | Binary search optimized |
| **UndoManager** | ✅ Supported | Full stack management |
| **Protocols** | ✅ Supported | Sync (v1/v2), Awareness, Auth |
| **Binary Encoding** | ✅ Supported | Uint8Array optimization |
| **Deltas** | 🚧 IP | `toDelta` in progress |

## License

BSD 3-Clause License. Copyright (c) 2026 Jagtesh Chadha.
