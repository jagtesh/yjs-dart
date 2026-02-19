/// Dart translation of y-protocols/awareness.js
///
/// Mirrors: y-protocols/awareness.js (v1.0.5)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;
import '../lib0/observable.dart';
import '../utils/doc.dart';

/// How long (ms) before an awareness state is considered outdated.
const int outdatedTimeout = 30000;

/// Metadata for a single client's awareness state.
typedef MetaClientState = ({int clock, int lastUpdated});

/// The Awareness class implements a simple shared state protocol for
/// non-persistent data like cursor positions, usernames, etc.
///
/// Mirrors: `Awareness` in awareness.js
class Awareness extends Observable<String> {
  /// The document this awareness is associated with.
  final Doc doc;

  /// Client ID (mirrors doc.clientID).
  int clientID;

  /// Map from client ID to state object.
  final Map<int, Map<String, Object?>> states = {};

  /// Map from client ID to metadata (clock, lastUpdated).
  final Map<int, MetaClientState> meta = {};

  /// Interval timer for pruning outdated states.
  Object? _checkInterval;

  Awareness(this.doc) : clientID = doc.clientID {
    // Register cleanup on doc destroy
    doc.on('destroy', (_) => destroy());
    // Set initial local state
    setLocalState({});
    // Start the outdated-state pruning interval
    _checkInterval = Timer.periodic(
        const Duration(milliseconds: outdatedTimeout ~/ 10), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (getLocalState() != null &&
          outdatedTimeout / 2 <= now - meta[clientID]!.lastUpdated) {
        // renew local clock
        setLocalState(getLocalState());
      }
      final remove = <int>[];
      meta.forEach((client, meta) {
        if (client != clientID &&
            outdatedTimeout <= now - meta.lastUpdated &&
            states.containsKey(client)) {
          remove.add(client);
        }
      });
      if (remove.isNotEmpty) {
        removeAwarenessStates(this, remove, 'timeout');
      }
    });
  }

  @override
  void destroy() {
    emit('destroy', [this]);
    setLocalState(null);
    (_checkInterval as Timer?)?.cancel();
    super.destroy();
  }

  /// Get the local awareness state (null if offline).
  ///
  /// Mirrors: `getLocalState` in awareness.js
  Map<String, Object?>? getLocalState() {
    return states[clientID];
  }

  /// Set the local awareness state.
  ///
  /// Mirrors: `setLocalState` in awareness.js
  void setLocalState(Map<String, Object?>? state) {
    final currLocalMeta = meta[clientID];
    final clock = currLocalMeta == null ? 0 : currLocalMeta.clock + 1;
    final prevState = states[clientID];
    if (state == null) {
      states.remove(clientID);
    } else {
      states[clientID] = state;
    }
    meta[clientID] = (
      clock: clock,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    final added = <int>[];
    final updated = <int>[];
    final filteredUpdated = <int>[];
    final removed = <int>[];
    if (state == null) {
      removed.add(clientID);
    } else if (prevState == null) {
      added.add(clientID);
    } else {
      updated.add(clientID);
      if (!_equalityDeep(prevState, state)) {
        filteredUpdated.add(clientID);
      }
    }
    if (added.isNotEmpty || filteredUpdated.isNotEmpty || removed.isNotEmpty) {
      emit('change', [
        {'added': added, 'updated': filteredUpdated, 'removed': removed},
        'local',
      ]);
    }
    emit('update', [
      {'added': added, 'updated': updated, 'removed': removed},
      'local',
    ]);
  }

  /// Set a single field in the local awareness state.
  ///
  /// Mirrors: `setLocalStateField` in awareness.js
  void setLocalStateField(String field, Object? value) {
    final state = getLocalState();
    if (state != null) {
      setLocalState({...state, field: value});
    }
  }

  /// Get all current awareness states.
  ///
  /// Mirrors: `getStates` in awareness.js
  Map<int, Map<String, Object?>> getStates() => states;
}

/// Mark remote clients as inactive and remove them from the active list.
///
/// Mirrors: `removeAwarenessStates` in awareness.js
void removeAwarenessStates(
    Awareness awareness, List<int> clients, Object? origin) {
  final removed = <int>[];
  for (final clientID in clients) {
    if (awareness.states.containsKey(clientID)) {
      awareness.states.remove(clientID);
      if (clientID == awareness.clientID) {
        final curMeta = awareness.meta[clientID]!;
        awareness.meta[clientID] = (
          clock: curMeta.clock + 1,
          lastUpdated: DateTime.now().millisecondsSinceEpoch,
        );
      }
      removed.add(clientID);
    }
  }
  if (removed.isNotEmpty) {
    awareness.emit('change', [
      {'added': <int>[], 'updated': <int>[], 'removed': removed},
      origin,
    ]);
    awareness.emit('update', [
      {'added': <int>[], 'updated': <int>[], 'removed': removed},
      origin,
    ]);
  }
}

/// Encode an awareness update for the given [clients].
///
/// Mirrors: `encodeAwarenessUpdate` in awareness.js
Uint8List encodeAwarenessUpdate(
  Awareness awareness,
  List<int> clients, [
  Map<int, Map<String, Object?>>? states,
]) {
  states ??= awareness.states;
  final encoder = encoding.createEncoder();
  encoding.writeVarUint(encoder, clients.length);
  for (final clientID in clients) {
    final state = states[clientID];
    final clock = awareness.meta[clientID]?.clock ?? 0;
    encoding.writeVarUint(encoder, clientID);
    encoding.writeVarUint(encoder, clock);
    encoding.writeVarString(encoder, jsonEncode(state));
  }
  return encoding.toUint8Array(encoder);
}

/// Modify an awareness update by transforming each state with [modify].
///
/// Mirrors: `modifyAwarenessUpdate` in awareness.js
Uint8List modifyAwarenessUpdate(
    Uint8List update, Map<String, Object?> Function(Map<String, Object?>) modify) {
  final decoder = decoding.createDecoder(update);
  final encoder = encoding.createEncoder();
  final len = decoding.readVarUint(decoder);
  encoding.writeVarUint(encoder, len);
  for (var i = 0; i < len; i++) {
    final clientID = decoding.readVarUint(decoder);
    final clock = decoding.readVarUint(decoder);
    final stateStr = decoding.readVarString(decoder);
    final state = (jsonDecode(stateStr) as Map).cast<String, Object?>();
    final modifiedState = modify(state);
    encoding.writeVarUint(encoder, clientID);
    encoding.writeVarUint(encoder, clock);
    encoding.writeVarString(encoder, jsonEncode(modifiedState));
  }
  return encoding.toUint8Array(encoder);
}

/// Apply an awareness update to [awareness].
///
/// Mirrors: `applyAwarenessUpdate` in awareness.js
void applyAwarenessUpdate(
    Awareness awareness, Uint8List update, Object? origin) {
  final decoder = decoding.createDecoder(update);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final added = <int>[];
  final updated = <int>[];
  final filteredUpdated = <int>[];
  final removed = <int>[];
  final len = decoding.readVarUint(decoder);
  for (var i = 0; i < len; i++) {
    final clientID = decoding.readVarUint(decoder);
    var clock = decoding.readVarUint(decoder);
    final stateStr = decoding.readVarString(decoder);
    final state = stateStr == 'null'
        ? null
        : (jsonDecode(stateStr) as Map).cast<String, Object?>();
    final clientMeta = awareness.meta[clientID];
    final prevState = awareness.states[clientID];
    final currClock = clientMeta?.clock ?? 0;
    if (currClock < clock ||
        (currClock == clock &&
            state == null &&
            awareness.states.containsKey(clientID))) {
      if (state == null) {
        // Never let a remote client remove our local state
        if (clientID == awareness.clientID &&
            awareness.getLocalState() != null) {
          clock++;
        } else {
          awareness.states.remove(clientID);
        }
      } else {
        awareness.states[clientID] = state;
      }
      awareness.meta[clientID] = (clock: clock, lastUpdated: timestamp);
      if (clientMeta == null && state != null) {
        added.add(clientID);
      } else if (clientMeta != null && state == null) {
        removed.add(clientID);
      } else if (state != null) {
        if (!_equalityDeep(state, prevState)) {
          filteredUpdated.add(clientID);
        }
        updated.add(clientID);
      }
    }
  }
  if (added.isNotEmpty || filteredUpdated.isNotEmpty || removed.isNotEmpty) {
    awareness.emit('change', [
      {'added': added, 'updated': filteredUpdated, 'removed': removed},
      origin,
    ]);
  }
  if (added.isNotEmpty || updated.isNotEmpty || removed.isNotEmpty) {
    awareness.emit('update', [
      {'added': added, 'updated': updated, 'removed': removed},
      origin,
    ]);
  }
}

/// Deep equality check for awareness states.
bool _equalityDeep(Object? a, Object? b) {
  if (a == b) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_equalityDeep(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_equalityDeep(a[i], b[i])) return false;
    }
    return true;
  }
  return false;
}
