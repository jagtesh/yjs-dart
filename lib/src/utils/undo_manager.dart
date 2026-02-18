/// Dart translation of src/utils/UndoManager.js (structural stub)
///
/// Mirrors: yjs/src/utils/UndoManager.js (v14.0.0-22)
library;

import '../lib0/observable.dart';
import '../utils/transaction.dart';
import '../y_type.dart';

/// Options for [UndoManager].
class UndoManagerOpts {
  /// Capture timeout in milliseconds (default: 500).
  final int captureTimeout;

  /// Filter function for transactions.
  final bool Function(Transaction tr)? captureTransaction;

  /// Delete filter for items.
  final bool Function(dynamic item)? deleteFilter;

  /// Tracked origins.
  final Set<Object?> trackedOrigins;

  UndoManagerOpts({
    this.captureTimeout = 500,
    this.captureTransaction,
    this.deleteFilter,
    Set<Object?>? trackedOrigins,
  }) : trackedOrigins = trackedOrigins ?? {};
}

/// Manages undo/redo history for Yjs types.
///
/// Mirrors: `UndoManager` in UndoManager.js
class UndoManager extends Observable<String> {
  /// The types being tracked.
  final List<YType<dynamic>> scope;

  /// Undo stack.
  final List<dynamic> undoStack = [];

  /// Redo stack.
  final List<dynamic> redoStack = [];

  /// Whether we are currently undoing/redoing.
  bool undoing = false;
  bool redoing = false;

  final UndoManagerOpts opts;

  UndoManager(
    dynamic scope, [
    UndoManagerOpts? opts,
  ])  : scope = scope is List
            ? List<YType<dynamic>>.from(scope as List)
            : [scope as YType<dynamic>],
        opts = opts ?? UndoManagerOpts();

  /// Undo the last change.
  dynamic undo() {
    // TODO: implement undo
    return null;
  }

  /// Redo the last undone change.
  dynamic redo() {
    // TODO: implement redo
    return null;
  }

  /// Stop capturing (force a new undo stack entry on next change).
  void stopCapturing() {
    // TODO: implement
  }

  /// Clear the undo/redo stacks.
  void clear([bool undoStackClear = true, bool redoStackClear = true]) {
    if (undoStackClear) undoStack.clear();
    if (redoStackClear) redoStack.clear();
  }

  @override
  void destroy() {
    // TODO: cleanup listeners
    super.destroy();
  }
}
