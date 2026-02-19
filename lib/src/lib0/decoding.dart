/// Native Dart implementation of lib0/decoding.
///
/// Provides a binary decoder that reads variable-length integers, strings,
/// and other primitives. Mirrors the API of lib0/decoding.js.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A binary decoder that reads from a [Uint8List].
///
/// Mirrors: lib0/decoding.Decoder
class Decoder {
  final Uint8List arr;
  int pos;

  Decoder(this.arr) : pos = 0;
}

/// Create a new [Decoder] from [uint8Array].
Decoder createDecoder(Uint8List uint8Array) => Decoder(uint8Array);

/// Returns true if the decoder has no more bytes to read.
bool hasContent(Decoder decoder) => decoder.pos < decoder.arr.length;

/// Clone the decoder at its current position.
Decoder clone(Decoder decoder, [int? newPos]) {
  final d = Decoder(decoder.arr);
  d.pos = newPos ?? decoder.pos;
  return d;
}

// ─── Primitive reads ─────────────────────────────────────────────────────────

/// Read a single byte.
int read(Decoder decoder) => decoder.arr[decoder.pos++];

/// Read a Uint8 (alias for [read]).
int readUint8(Decoder decoder) => read(decoder);

/// Read a Uint16 in little-endian order (matches JS lib0).
int readUint16(Decoder decoder) {
  final result = decoder.arr[decoder.pos] |
      (decoder.arr[decoder.pos + 1] << 8);
  decoder.pos += 2;
  return result;
}

/// Read a Uint32 in little-endian order (matches JS lib0).
int readUint32(Decoder decoder) {
  final result = (decoder.arr[decoder.pos] +
      (decoder.arr[decoder.pos + 1] << 8) +
      (decoder.arr[decoder.pos + 2] << 16) +
      (decoder.arr[decoder.pos + 3] << 24));
  decoder.pos += 4;
  return result >= 0 ? result : result + 0x100000000; // unsigned
}

/// Read a Uint32 in big-endian order.
int readUint32BigEndian(Decoder decoder) {
  final result = (decoder.arr[decoder.pos + 3] +
      (decoder.arr[decoder.pos + 2] << 8) +
      (decoder.arr[decoder.pos + 1] << 16) +
      (decoder.arr[decoder.pos] << 24));
  decoder.pos += 4;
  return result >= 0 ? result : result + 0x100000000; // unsigned
}

/// Read a variable-length unsigned integer (LEB128).
int readVarUint(Decoder decoder) {
  var num = 0;
  var shift = 0;
  while (true) {
    final byte = decoder.arr[decoder.pos++];
    num |= (byte & 0x7F) << shift;
    shift += 7;
    if ((byte & 0x80) == 0) break;
  }
  return num;
}

/// Read a variable-length signed integer.
///
/// Mirrors JS lib0/decoding.readVarInt:
///   First byte: [continue][sign][value × 6 bits]
///   Subsequent:  [continue][value × 7 bits]
int readVarInt(Decoder decoder) {
  var r = decoder.arr[decoder.pos++];
  var num = r & 0x3F; // 6 data bits (BITS6)
  var mult = 64;
  final sign = (r & 0x40) > 0 ? -1 : 1; // sign bit (BIT7)
  if ((r & 0x80) == 0) {
    // no continuation
    return sign * num;
  }
  final len = decoder.arr.length;
  while (decoder.pos < len) {
    r = decoder.arr[decoder.pos++];
    num = num + (r & 0x7F) * mult; // 7 data bits
    mult *= 128;
    if ((r & 0x80) == 0) { // no continuation
      return sign * num;
    }
  }
  throw StateError('Unexpected end of array');
}

/// Read a variable-length UTF-8 string.
String readVarString(Decoder decoder) {
  final len = readVarUint(decoder);
  final bytes = decoder.arr.sublist(decoder.pos, decoder.pos + len);
  decoder.pos += len;
  return utf8.decode(bytes);
}

/// Read a [Uint8List] prefixed with its length as a varUint.
Uint8List readVarUint8Array(Decoder decoder) {
  final len = readVarUint(decoder);
  final result = decoder.arr.sublist(decoder.pos, decoder.pos + len);
  decoder.pos += len;
  return result;
}

/// Read [len] bytes as a [Uint8List].
Uint8List readUint8Array(Decoder decoder, int len) {
  final result = decoder.arr.sublist(decoder.pos, decoder.pos + len);
  decoder.pos += len;
  return result;
}

/// Read a Float32 in big-endian order.
double readFloat32(Decoder decoder) {
  final bd = ByteData.sublistView(decoder.arr, decoder.pos, decoder.pos + 4);
  decoder.pos += 4;
  return bd.getFloat32(0);
}

/// Read a Float64 in big-endian order.
double readFloat64(Decoder decoder) {
  final bd = ByteData.sublistView(decoder.arr, decoder.pos, decoder.pos + 8);
  decoder.pos += 8;
  return bd.getFloat64(0);
}

/// Read a BigInt variable-length unsigned integer.
BigInt readBigUint64(Decoder decoder) {
  var result = BigInt.zero;
  var shift = 0;
  while (true) {
    final byte = decoder.arr[decoder.pos++];
    result |= BigInt.from(byte & 0x7F) << shift;
    shift += 7;
    if ((byte & 0x80) == 0) break;
  }
  return result;
}

/// Read a BigInt variable-length signed integer.
BigInt readBigInt64(Decoder decoder) {
  final n = readBigUint64(decoder);
  return (n & BigInt.one) == BigInt.one
      ? -((n >> 1) + BigInt.one)
      : n >> 1;
}

/// Read an arbitrary JSON-compatible value (lib0 "any" encoding).
///
/// Encoding table (matches lib0/encoding.js):
///   127: undefined, 126: null, 125: integer (readVarInt),
///   124: float32, 123: float64, 122: bigint, 121: false, 120: true,
///   119: string, 118: object, 117: array, 116: Uint8Array
Object? readAny(Decoder decoder) {
  final type = read(decoder);
  switch (type) {
    case 127: // undefined → treat as null in Dart
      return null;
    case 126: // null
      return null;
    case 125: // integer (readVarInt)
      return readVarInt(decoder);
    case 124: // float32
      return readFloat32(decoder);
    case 123: // float64
      return readFloat64(decoder);
    // case 122: bigint — not supported in Dart
    case 121: // false
      return false;
    case 120: // true
      return true;
    case 119: // string
      return readVarString(decoder);
    case 118: // object
      final len = readVarUint(decoder);
      final map = <String, Object?>{};
      for (var i = 0; i < len; i++) {
        final key = readVarString(decoder);
        map[key] = readAny(decoder);
      }
      return map;
    case 117: // array
      final len = readVarUint(decoder);
      return List.generate(len, (_) => readAny(decoder));
    case 116: // Uint8Array
      return readVarUint8Array(decoder);
    default:
      throw StateError('Unknown type tag: $type');
  }
}
