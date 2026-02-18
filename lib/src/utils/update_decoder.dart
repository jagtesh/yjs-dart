/// Dart translation of src/utils/UpdateDecoder.js
///
/// Mirrors: yjs/src/utils/UpdateDecoder.js (v14.0.0-22)
library;

import 'dart:convert';
import 'dart:typed_data';

import '../lib0/decoding.dart' as decoding;
import '../utils/id.dart';

// ─── RLE / Opt decoders (lib0 advanced decoders) ─────────────────────────────

/// Run-length decoder for uint8 values.
class RleDecoder {
  final decoding.Decoder _decoder;
  int? _s;
  int _count = 0;

  RleDecoder(Uint8List buf) : _decoder = decoding.createDecoder(buf);

  int read() {
    if (_count == 0) {
      _s = decoding.readUint8(_decoder);
      _count = decoding.readVarUint(_decoder);
    }
    _count--;
    return _s!;
  }
}

/// Uint optional RLE decoder.
class UintOptRleDecoder {
  final decoding.Decoder _decoder;
  int _s = 0;
  int _count = 0;

  UintOptRleDecoder(Uint8List buf) : _decoder = decoding.createDecoder(buf);

  int read() {
    if (_count == 0) {
      final v = decoding.readVarInt(_decoder);
      if (v < 0) {
        _count = -v;
        _s = decoding.readVarUint(_decoder);
      } else {
        _count = 1;
        _s = v;
      }
    }
    _count--;
    return _s;
  }
}

/// Int diff optional RLE decoder.
class IntDiffOptRleDecoder {
  final decoding.Decoder _decoder;
  int _s = 0;
  int _diff = 0;
  int _count = 0;

  IntDiffOptRleDecoder(Uint8List buf) : _decoder = decoding.createDecoder(buf);

  int read() {
    if (_count == 0) {
      final v = decoding.readVarInt(_decoder);
      if (v < 0) {
        _count = -v;
        _diff = decoding.readVarInt(_decoder);
      } else {
        _count = 1;
        _diff = v;
      }
    }
    _count--;
    _s += _diff;
    return _s;
  }
}

/// String decoder that deduplicates strings.
class StringDecoder {
  final decoding.Decoder _sDecoder;
  final UintOptRleDecoder _lensDecoder;
  final List<String> _keys = [];

  StringDecoder(Uint8List buf)
      : _sDecoder = decoding.createDecoder(decoding.readVarUint8Array(
            decoding.createDecoder(buf))),
        _lensDecoder = UintOptRleDecoder(
            decoding.readVarUint8Array(decoding.createDecoder(buf)));

  String read() {
    final id = _lensDecoder.read();
    if (id < _keys.length) {
      return _keys[id];
    }
    final len = decoding.readVarUint(_sDecoder);
    final bytes = decoding.readUint8Array(_sDecoder, len);
    final s = utf8.decode(bytes);
    _keys.add(s);
    return s;
  }
}

// ─── Abstract decoder interface ───────────────────────────────────────────────

/// Abstract base for update decoders.
abstract class AbstractUpdateDecoder {
  decoding.Decoder get restDecoder;
  void resetDsCurVal();
  int readDsClock();
  int readDsLen();
}

// ─── V1 Decoders ─────────────────────────────────────────────────────────────

/// IdSet decoder V1.
///
/// Mirrors: `IdSetDecoderV1` in UpdateDecoder.js
class IdSetDecoderV1 implements AbstractUpdateDecoder {
  @override
  final decoding.Decoder restDecoder;

  IdSetDecoderV1(this.restDecoder);

  @override
  void resetDsCurVal() {
    // nop
  }

  @override
  int readDsClock() => decoding.readVarUint(restDecoder);

  @override
  int readDsLen() => decoding.readVarUint(restDecoder);
}

/// Update decoder V1.
///
/// Mirrors: `UpdateDecoderV1` in UpdateDecoder.js
class UpdateDecoderV1 extends IdSetDecoderV1 {
  UpdateDecoderV1(super.restDecoder);

  ID readLeftID() => createID(
        decoding.readVarUint(restDecoder),
        decoding.readVarUint(restDecoder),
      );

  ID readRightID() => createID(
        decoding.readVarUint(restDecoder),
        decoding.readVarUint(restDecoder),
      );

  int readClient() => decoding.readVarUint(restDecoder);

  int readInfo() => decoding.readUint8(restDecoder);

  String readString() => decoding.readVarString(restDecoder);

  bool readParentInfo() => decoding.readVarUint(restDecoder) == 1;

  int readTypeRef() => decoding.readVarUint(restDecoder);

  int readLen() => decoding.readVarUint(restDecoder);

  Object? readAny() => decoding.readAny(restDecoder);

  Uint8List readBuf() => Uint8List.fromList(decoding.readVarUint8Array(restDecoder));

  Object? readJSON() => jsonDecode(decoding.readVarString(restDecoder));

  String readKey() => decoding.readVarString(restDecoder);
}

// ─── V2 Decoders ─────────────────────────────────────────────────────────────

/// IdSet decoder V2 (delta-encoded).
///
/// Mirrors: `IdSetDecoderV2` in UpdateDecoder.js
class IdSetDecoderV2 implements AbstractUpdateDecoder {
  @override
  final decoding.Decoder restDecoder;
  int _dsCurrVal = 0;

  IdSetDecoderV2(this.restDecoder);

  @override
  void resetDsCurVal() {
    _dsCurrVal = 0;
  }

  @override
  int readDsClock() {
    _dsCurrVal += decoding.readVarUint(restDecoder);
    return _dsCurrVal;
  }

  @override
  int readDsLen() {
    final diff = decoding.readVarUint(restDecoder) + 1;
    _dsCurrVal += diff;
    return diff;
  }
}

/// Update decoder V2 (highly compressed).
///
/// Mirrors: `UpdateDecoderV2` in UpdateDecoder.js
class UpdateDecoderV2 extends IdSetDecoderV2 {
  final List<String> keys = [];
  late final IntDiffOptRleDecoder keyClockDecoder;
  late final UintOptRleDecoder clientDecoder;
  late final IntDiffOptRleDecoder leftClockDecoder;
  late final IntDiffOptRleDecoder rightClockDecoder;
  late final RleDecoder infoDecoder;
  late final StringDecoder stringDecoder;
  late final RleDecoder parentInfoDecoder;
  late final UintOptRleDecoder typeRefDecoder;
  late final UintOptRleDecoder lenDecoder;

  UpdateDecoderV2(super.restDecoder) {
    decoding.readVarUint(restDecoder); // feature flag - currently unused
    keyClockDecoder = IntDiffOptRleDecoder(decoding.readVarUint8Array(restDecoder));
    clientDecoder = UintOptRleDecoder(decoding.readVarUint8Array(restDecoder));
    leftClockDecoder = IntDiffOptRleDecoder(decoding.readVarUint8Array(restDecoder));
    rightClockDecoder = IntDiffOptRleDecoder(decoding.readVarUint8Array(restDecoder));
    infoDecoder = RleDecoder(decoding.readVarUint8Array(restDecoder));
    stringDecoder = StringDecoder(decoding.readVarUint8Array(restDecoder));
    parentInfoDecoder = RleDecoder(decoding.readVarUint8Array(restDecoder));
    typeRefDecoder = UintOptRleDecoder(decoding.readVarUint8Array(restDecoder));
    lenDecoder = UintOptRleDecoder(decoding.readVarUint8Array(restDecoder));
  }

  ID readLeftID() => ID(clientDecoder.read(), leftClockDecoder.read());

  ID readRightID() => ID(clientDecoder.read(), rightClockDecoder.read());

  int readClient() => clientDecoder.read();

  int readInfo() => infoDecoder.read();

  String readString() => stringDecoder.read();

  bool readParentInfo() => parentInfoDecoder.read() == 1;

  int readTypeRef() => typeRefDecoder.read();

  int readLen() => lenDecoder.read();

  Object? readAny() => decoding.readAny(restDecoder);

  Uint8List readBuf() => decoding.readVarUint8Array(restDecoder);

  Object? readJSON() => decoding.readAny(restDecoder);

  String readKey() {
    final keyClock = keyClockDecoder.read();
    if (keyClock < keys.length) {
      return keys[keyClock];
    }
    final key = stringDecoder.read();
    keys.add(key);
    return key;
  }
}
