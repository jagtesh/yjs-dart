/// Native Dart implementation of lib0/random utilities.
///
/// Mirrors: lib0/random.js
library;

import 'dart:math';
import 'dart:typed_data';

final _rng = Random.secure();

/// Generate a random 32-bit unsigned integer.
int uint32() {
  return _rng.nextInt(0x100000000);
}

/// Generate a random float in [0, 1).
double float32() {
  return _rng.nextDouble();
}

/// Generate a UUID v4 string.
String uuidv4() {
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = _rng.nextInt(256);
  }
  // Set version 4
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set variant bits
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Generate a one-time random ID (uint32 as hex string).
String oneTimeId() => uint32().toRadixString(16);
