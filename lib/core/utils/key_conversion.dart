import 'dart:convert';
import 'dart:typed_data';

/// Converts a BASE64-encoded string to a HEX string.
///
/// Used to convert identity privateKey (stored as BASE64) to the HEX format
/// required by the P2P node:start command.
String base64ToHex(String base64String) {
  final bytes = base64Decode(base64String);
  return bytesToHex(bytes);
}

/// Converts a HEX string to a BASE64-encoded string.
String hexToBase64(String hexString) {
  final bytes = hexToBytes(hexString);
  return base64Encode(bytes);
}

/// Converts a Uint8List to a HEX string.
String bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Converts a HEX string to a Uint8List.
Uint8List hexToBytes(String hexString) {
  final hex = hexString.toLowerCase();
  if (hex.length % 2 != 0) {
    throw ArgumentError('Hex string must have even length');
  }

  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return bytes;
}
