/// Dart translation of y-protocols/auth.js
///
/// Mirrors: y-protocols/auth.js (v1.0.5)
library;

import '../../lib0/encoding.dart' as encoding;
import '../../lib0/decoding.dart' as decoding;

/// Auth message type constants.
const int messagePermissionDenied = 0;

/// Write a permission denied message.
///
/// Mirrors: `writePermissionDenied` in auth.js
void writePermissionDenied(encoding.Encoder encoder, String reason) {
  encoding.writeVarUint(encoder, messagePermissionDenied);
  encoding.writeVarString(encoder, reason);
}

/// Read an auth message.
///
/// Mirrors: `readAuthMessage` in auth.js
void readAuthMessage(
  decoding.Decoder decoder,
  dynamic doc,
  void Function(dynamic doc, String reason) permissionDeniedHandler,
) {
  final messageType = decoding.readVarUint(decoder);
  if (messageType == messagePermissionDenied) {
    final reason = decoding.readVarString(decoder);
    permissionDeniedHandler(doc, reason);
  }
}
