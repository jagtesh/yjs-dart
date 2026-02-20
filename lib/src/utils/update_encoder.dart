/// Dart translation of src/utils/UpdateEncoder.js
///
/// Mirrors: yjs/src/utils/UpdateEncoder.js (v14.0.0-22)
library;

import 'dart:convert';
import 'dart:typed_data';

import '../lib0/encoding.dart' as encoding;
import '../utils/id.dart';

// ─── RLE / Opt encoders (lib0 advanced encoders) ─────────────────────────────

/// Run-length encoder for uint8 values.
class RleEncoder {
  final encoding.Encoder _encoder = encoding.createEncoder();
  int? _s; // current run value
  int _count = 0;

  void write(int v) {
    if (_s == v) {
      _count++;
    } else {
      if (_s != null) {
        encoding.writeVarUint(_encoder, _count - 1);
      }
      _count = 1;
      _s = v;
      encoding.writeUint8(_encoder, v);
    }
  }

  Uint8List toUint8Array() {
    if (_s != null) {
      encoding.writeVarUint(_encoder, _count - 1);
    }
    return encoding.toUint8Array(_encoder);
  }
}

/// Uint optional RLE encoder.
class UintOptRleEncoder {
  final encoding.Encoder _encoder = encoding.createEncoder();
  int? _s;
  int _count = 0;

  void write(int v) {
    if (_s == v) {
      _count++;
    } else {
      if (_s != null) {
        // positive count means repeated, negative means single
        encoding.writeVarInt(_encoder, _count == 1 ? _s! : -_count);
        if (_count > 1) encoding.writeVarUint(_encoder, _s!);
      }
      _count = 1;
      _s = v;
    }
  }

  Uint8List toUint8Array() {
    if (_s != null) {
      encoding.writeVarInt(_encoder, _count == 1 ? _s! : -_count);
      if (_count > 1) encoding.writeVarUint(_encoder, _s!);
    }
    return encoding.toUint8Array(_encoder);
  }
}

/// Int diff optional RLE encoder.
class IntDiffOptRleEncoder {
  final encoding.Encoder _encoder = encoding.createEncoder();
  int _prev = 0;
  int? _diff;
  int _count = 0;

  void write(int v) {
    final diff = v - _prev;
    _prev = v;
    if (_diff == diff) {
      _count++;
    } else {
      if (_diff != null) {
        encoding.writeVarInt(_encoder, _count == 1 ? _diff! : -_count);
        if (_count > 1) encoding.writeVarInt(_encoder, _diff!);
      }
      _count = 1;
      _diff = diff;
    }
  }

  Uint8List toUint8Array() {
    if (_diff != null) {
      encoding.writeVarInt(_encoder, _count == 1 ? _diff! : -_count);
      if (_count > 1) encoding.writeVarInt(_encoder, _diff!);
    }
    return encoding.toUint8Array(_encoder);
  }
}

/// String encoder that deduplicates strings.
class StringEncoder {
  final Map<String, int> _sarr = {};
  int _spos = 0;
  final encoding.Encoder _encoder = encoding.createEncoder();
  final UintOptRleEncoder _lensEncoder = UintOptRleEncoder();

  int write(String s) {
    final existing = _sarr[s];
    if (existing != null) {
      _lensEncoder.write(existing);
      return existing;
    }
    final id = _spos++;
    _sarr[s] = id;
    final bytes = utf8.encode(s);
    encoding.writeVarUint(_encoder, bytes.length);
    encoding.writeUint8Array(_encoder, Uint8List.fromList(bytes));
    _lensEncoder.write(id);
    return id;
  }

  Uint8List toUint8Array() {
    final e = encoding.createEncoder();
    encoding.writeVarUint8Array(e, encoding.toUint8Array(_encoder));
    encoding.writeVarUint8Array(e, _lensEncoder.toUint8Array());
    return encoding.toUint8Array(e);
  }
}

// ─── Abstract encoder interface ───────────────────────────────────────────────

/// Abstract base for update encoders.
abstract class AbstractUpdateEncoder {
  encoding.Encoder get restEncoder;
  Uint8List toUint8Array();
  void resetIdSetCurVal();
  void writeIdSetClock(int clock);
  void writeIdSetLen(int len);
}

// ─── V1 Encoders ─────────────────────────────────────────────────────────────

/// IdSet encoder V1 (simple varUint encoding).
///
/// Mirrors: `IdSetEncoderV1` in UpdateEncoder.js
class IdSetEncoderV1 implements AbstractUpdateEncoder {
  final encoding.Encoder restEncoder = encoding.createEncoder();

  @override
  Uint8List toUint8Array() => encoding.toUint8Array(restEncoder);

  @override
  void resetIdSetCurVal() {
    // nop
  }

  @override
  void writeIdSetClock(int clock) {
    encoding.writeVarUint(restEncoder, clock);
  }

  @override
  void writeIdSetLen(int len) {
    encoding.writeVarUint(restEncoder, len);
  }
}

/// Update encoder V1.
///
/// Mirrors: `UpdateEncoderV1` in UpdateEncoder.js
class UpdateEncoderV1 extends IdSetEncoderV1 {
  void writeLeftID(ID id) {
    encoding.writeVarUint(restEncoder, id.client);
    encoding.writeVarUint(restEncoder, id.clock);
  }

  void writeRightID(ID id) {
    encoding.writeVarUint(restEncoder, id.client);
    encoding.writeVarUint(restEncoder, id.clock);
  }

  void writeClient(int client) {
    encoding.writeVarUint(restEncoder, client);
  }

  void writeInfo(int info) {
    encoding.writeUint8(restEncoder, info);
  }

  void writeString(String s) {
    encoding.writeVarString(restEncoder, s);
  }

  void writeParentInfo(bool isYKey) {
    encoding.writeVarUint(restEncoder, isYKey ? 1 : 0);
  }

  void writeTypeRef(int info) {
    encoding.writeVarUint(restEncoder, info);
  }

  void writeLen(int len) {
    encoding.writeVarUint(restEncoder, len);
  }

  void writeAny(Object? any) {
    encoding.writeAny(restEncoder, any);
  }

  void writeBuf(Uint8List buf) {
    encoding.writeVarUint8Array(restEncoder, buf);
  }

  void writeJSON(Object? embed) {
    encoding.writeVarString(restEncoder, jsonEncode(embed));
  }

  void writeKey(String key) {
    encoding.writeVarString(restEncoder, key);
  }
}

// ─── V2 Encoders ─────────────────────────────────────────────────────────────

/// IdSet encoder V2 (delta-encoded).
///
/// Mirrors: `IdSetEncoderV2` in UpdateEncoder.js
class IdSetEncoderV2 implements AbstractUpdateEncoder {
  final encoding.Encoder restEncoder = encoding.createEncoder();
  int dsCurrVal = 0;

  @override
  Uint8List toUint8Array() => encoding.toUint8Array(restEncoder);

  @override
  void resetIdSetCurVal() {
    dsCurrVal = 0;
  }

  @override
  void writeIdSetClock(int clock) {
    final diff = clock - dsCurrVal;
    dsCurrVal = clock;
    encoding.writeVarUint(restEncoder, diff);
  }

  @override
  void writeIdSetLen(int len) {
    if (len == 0) throw StateError('Unexpected case: len == 0');
    encoding.writeVarUint(restEncoder, len - 1);
    dsCurrVal += len;
  }
}

/// Update encoder V2 (highly compressed).
///
/// Mirrors: `UpdateEncoderV2` in UpdateEncoder.js
class UpdateEncoderV2 extends IdSetEncoderV2 {
  final Map<String, int> keyMap = {};
  int keyClock = 0;
  final IntDiffOptRleEncoder keyClockEncoder = IntDiffOptRleEncoder();
  final UintOptRleEncoder clientEncoder = UintOptRleEncoder();
  final IntDiffOptRleEncoder leftClockEncoder = IntDiffOptRleEncoder();
  final IntDiffOptRleEncoder rightClockEncoder = IntDiffOptRleEncoder();
  final RleEncoder infoEncoder = RleEncoder();
  final StringEncoder stringEncoder = StringEncoder();
  final RleEncoder parentInfoEncoder = RleEncoder();
  final UintOptRleEncoder typeRefEncoder = UintOptRleEncoder();
  final UintOptRleEncoder lenEncoder = UintOptRleEncoder();

  @override
  Uint8List toUint8Array() {
    final encoder = encoding.createEncoder();
    encoding.writeVarUint(encoder, 0); // feature flag
    encoding.writeVarUint8Array(encoder, keyClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, clientEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, leftClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, rightClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, infoEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, stringEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, parentInfoEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, typeRefEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, lenEncoder.toUint8Array());
    encoding.writeUint8Array(encoder, encoding.toUint8Array(restEncoder));
    return encoding.toUint8Array(encoder);
  }

  void writeLeftID(ID id) {
    clientEncoder.write(id.client);
    leftClockEncoder.write(id.clock);
  }

  void writeRightID(ID id) {
    clientEncoder.write(id.client);
    rightClockEncoder.write(id.clock);
  }

  void writeClient(int client) {
    clientEncoder.write(client);
  }

  void writeInfo(int info) {
    infoEncoder.write(info);
  }

  void writeString(String s) {
    stringEncoder.write(s);
  }

  void writeParentInfo(bool isYKey) {
    parentInfoEncoder.write(isYKey ? 1 : 0);
  }

  void writeTypeRef(int info) {
    typeRefEncoder.write(info);
  }

  void writeLen(int len) {
    lenEncoder.write(len);
  }

  void writeAny(Object? any) {
    encoding.writeAny(restEncoder, any);
  }

  void writeBuf(Uint8List buf) {
    encoding.writeVarUint8Array(restEncoder, buf);
  }

  void writeJSON(Object? embed) {
    encoding.writeVarString(restEncoder, jsonEncode(embed));
  }

  void writeKey(String key) {
    final existing = keyMap[key];
    if (existing != null) {
      keyClockEncoder.write(existing);
    } else {
      keyMap[key] = keyClock;
      keyClockEncoder.write(keyClock);
      keyClock++;
      stringEncoder.write(key);
    }
  }
}
