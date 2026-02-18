/// Native Dart implementation of lib0/encoding.
///
/// Provides a binary encoder that writes variable-length integers, strings,
/// and other primitives. Mirrors the API of lib0/encoding.js.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A binary encoder that accumulates bytes.
///
/// Mirrors: lib0/encoding.Encoder
class Encoder {
  final _buf = BytesBuilder(copy: false);

  /// Returns the encoded bytes.
  Uint8List toUint8Array() => _buf.toBytes();

  /// Returns the number of bytes written.
  int get length => _buf.length;
}

/// Create a new [Encoder].
Encoder createEncoder() => Encoder();

/// Returns the encoded bytes from [encoder].
Uint8List toUint8Array(Encoder encoder) => encoder.toUint8Array();

// ─── Primitive writes ────────────────────────────────────────────────────────

/// Write a single byte.
void write(Encoder encoder, int num) {
  encoder._buf.addByte(num & 0xFF);
}

/// Write a Uint8 (alias for [write]).
void writeUint8(Encoder encoder, int num) => write(encoder, num);

/// Write a Uint16 in big-endian order.
void writeUint16(Encoder encoder, int num) {
  encoder._buf.addByte((num >>> 8) & 0xFF);
  encoder._buf.addByte(num & 0xFF);
}

/// Write a Uint32 in big-endian order.
void writeUint32(Encoder encoder, int num) {
  encoder._buf.addByte((num >>> 24) & 0xFF);
  encoder._buf.addByte((num >>> 16) & 0xFF);
  encoder._buf.addByte((num >>> 8) & 0xFF);
  encoder._buf.addByte(num & 0xFF);
}

/// Write a Uint32 in big-endian order (alias).
void writeUint32BigEndian(Encoder encoder, int num) =>
    writeUint32(encoder, num);

/// Write a variable-length unsigned integer (LEB128).
void writeVarUint(Encoder encoder, int num) {
  // Dart ints are 64-bit; handle as unsigned
  var n = num;
  while (n > 0x7F) {
    encoder._buf.addByte((n & 0x7F) | 0x80);
    n = n >>> 7;
  }
  encoder._buf.addByte(n & 0x7F);
}

/// Write a variable-length signed integer (zigzag + LEB128).
void writeVarInt(Encoder encoder, int num) {
  final isNegative = num < 0;
  final n = isNegative ? (-num - 1) * 2 + 1 : num * 2;
  writeVarUint(encoder, n);
}

/// Write a variable-length UTF-8 string.
void writeVarString(Encoder encoder, String str) {
  final bytes = utf8.encode(str);
  writeVarUint(encoder, bytes.length);
  encoder._buf.add(bytes);
}

/// Write a [Uint8List] prefixed with its length as a varUint.
void writeVarUint8Array(Encoder encoder, Uint8List arr) {
  writeVarUint(encoder, arr.length);
  encoder._buf.add(arr);
}

/// Write a [Uint8List] without a length prefix.
void writeUint8Array(Encoder encoder, Uint8List arr) {
  encoder._buf.add(arr);
}

/// Write a Float32 in big-endian order.
void writeFloat32(Encoder encoder, double num) {
  final bd = ByteData(4)..setFloat32(0, num);
  encoder._buf.add(bd.buffer.asUint8List());
}

/// Write a Float64 in big-endian order.
void writeFloat64(Encoder encoder, double num) {
  final bd = ByteData(8)..setFloat64(0, num);
  encoder._buf.add(bd.buffer.asUint8List());
}

/// Write a BigInt as a variable-length unsigned integer (64-bit).
void writeBigUint64(Encoder encoder, BigInt num) {
  var n = num;
  final mask = BigInt.from(0x7F);
  final cont = BigInt.from(0x80);
  while (n > mask) {
    encoder._buf.addByte(((n & mask) | cont).toInt());
    n = n >> 7;
  }
  encoder._buf.addByte(n.toInt());
}

/// Write a BigInt as a variable-length signed integer.
void writeBigInt64(Encoder encoder, BigInt num) {
  final isNegative = num < BigInt.zero;
  final n = isNegative ? (-num - BigInt.one) * BigInt.two + BigInt.one : num * BigInt.two;
  writeBigUint64(encoder, n);
}

/// Write an arbitrary JSON-compatible value using the lib0 "any" encoding.
///
/// Supports: null, bool, int, double, String, List, Map<String, dynamic>.
void writeAny(Encoder encoder, Object? value) {
  if (value == null) {
    write(encoder, 126); // null
  } else if (value is bool) {
    write(encoder, value ? 120 : 121); // true / false
  } else if (value is int) {
    if (value >= -2147483648 && value <= 2147483647) {
      write(encoder, 125); // int32
      writeUint32(encoder, value < 0 ? value + 0x100000000 : value);
    } else {
      write(encoder, 124); // float64 for large ints
      writeFloat64(encoder, value.toDouble());
    }
  } else if (value is double) {
    write(encoder, 124); // float64
    writeFloat64(encoder, value);
  } else if (value is String) {
    write(encoder, 119); // string
    writeVarString(encoder, value);
  } else if (value is List) {
    write(encoder, 117); // array
    writeVarUint(encoder, value.length);
    for (final item in value) {
      writeAny(encoder, item);
    }
  } else if (value is Map) {
    write(encoder, 118); // object
    writeVarUint(encoder, value.length);
    value.forEach((k, v) {
      writeVarString(encoder, k.toString());
      writeAny(encoder, v);
    });
  } else if (value is Uint8List) {
    write(encoder, 116); // Uint8Array
    writeVarUint8Array(encoder, value);
  } else {
    throw ArgumentError('Cannot encode value of type ${value.runtimeType}');
  }
}
