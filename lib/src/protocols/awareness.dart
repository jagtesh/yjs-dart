/// Dart translation of y-protocols/awareness.js
///
/// Mirrors: y-protocols/awareness.js (v1.0.5)
library;

import 'dart:typed_data';

import '../lib0/observable.dart';
import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;
import '../utils/doc.dart';

/// Awareness state for a single client.
typedef AwarenessState = Map<String, Object?>;

/// Awareness protocol for sharing user presence information.
///
/// Mirrors: `Awareness` in awareness.js
class Awareness extends Observable<String> {
  /// The document this awareness is associated with.
  final Doc doc;

  /// Map from client ID to {clock, state}.
  final Map<int, ({int clock, AwarenessState? state})> states = {};

  /// The local state.
  AwarenessState? _localState = {};

  Awareness(this.doc) {
    states[doc.clientID] = (clock: 0, state: _localState);
  }

  /// Get the local awareness state.
  AwarenessState? get localState => _localState;

  /// Set the local awareness state.
  set localState(AwarenessState? state) {
    final prevState = _localState;
    _localState = state;
    final entry = states[doc.clientID];
    final clock = (entry?.clock ?? 0) + 1;
    states[doc.clientID] = (clock: clock, state: state);
    emit('change', [
      {
        'added': <int>[],
        'updated': [doc.clientID],
        'removed': <int>[],
      },
      'local',
    ]);
    emit('update', [
      {
        'added': <int>[],
        'updated': [doc.clientID],
        'removed': <int>[],
      },
      'local',
    ]);
  }

  /// Get all current states.
  Map<int, AwarenessState?> getStates() {
    return Map.fromEntries(
      states.entries.map((e) => MapEntry(e.key, e.value.state)),
    );
  }

  /// Destroy this awareness instance.
  @override
  void destroy() {
    emit('destroy', [this]);
    super.destroy();
  }
}

/// Encode an awareness update for the given [clientIds].
///
/// Mirrors: `encodeAwarenessUpdate` in awareness.js
encoding.Encoder encodeAwarenessUpdate(
  Awareness awareness,
  List<int> clientIds,
) {
  final encoder = encoding.createEncoder();
  encoding.writeVarUint(encoder, clientIds.length);
  for (final clientId in clientIds) {
    final entry = awareness.states[clientId];
    encoding.writeVarUint(encoder, clientId);
    encoding.writeVarUint(encoder, entry?.clock ?? 0);
    if (entry?.state == null) {
      encoding.writeVarString(encoder, 'null');
    } else {
      // Simple JSON-like encoding
      encoding.writeVarString(encoder, _encodeState(entry!.state!));
    }
  }
  return encoder;
}

String _encodeState(AwarenessState state) {
  final parts = state.entries.map((e) => '"${e.key}":${_encodeValue(e.value)}');
  return '{${parts.join(',')}}';
}

String _encodeValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return '"$value"';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  return '"$value"';
}

/// Apply an awareness update.
///
/// Mirrors: `applyAwarenessUpdate` in awareness.js
void applyAwarenessUpdate(
  Awareness awareness,
  List<int> update,
  Object? origin,
) {
  final decoder = decoding.createDecoder(Uint8List.fromList(update));
  // TODO: implement full awareness update decoding
}
