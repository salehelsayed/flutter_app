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

// ---------------------------------------------------------------------------
// Plan 360 (GAP-N01): pure-Dart Ed25519 public key -> libp2p peer ID.
// ---------------------------------------------------------------------------
//
// Mirrors the incumbent Go derivation used by `go-mknoon/identity` —
// `peer.IDFromPublicKey(libp2pPubKey)` — with no Go, native, or generated
// binding change. Plan 360 needs this OFFLINE, before `node:start`, so a
// linked installation can prove that
//   * its stored account public key really derives the logical account peer,
//   * its stored transport public key really derives the claimed transport
//     peer,
// and so a scanned QR's claimed peers can be proved against its carried keys.
// Trusting a self-declared peer string would let a tampered QR bind a device
// row to a peer nobody controls.
//
// The derivation is fully specified by libp2p and is not a re-implementation
// of any secret operation (no signing, no key agreement, no randomness):
//
//   1. Serialize the key as the libp2p `crypto.pb.PublicKey` protobuf —
//      field 1 (`Type`) varint = 1 (Ed25519), field 2 (`Data`) = the raw
//      32-byte key. That is a fixed 36-byte prefix-encoded blob.
//   2. Serialized length (36) <= 42, so libp2p uses the IDENTITY multihash
//      (code 0x00) rather than SHA-256: 0x00, length 36, then the 36 bytes.
//   3. Base58btc-encode the 38-byte multihash. Ed25519 identity hashes always
//      render with the familiar `12D3KooW…` prefix.
//
// `TC-360-01a` pins this against fixed vectors emitted by the real Go
// implementation, so a drift in either direction is a test failure rather
// than a silent addressing bug.

/// Length in bytes of a raw Ed25519 public key.
const int ed25519PublicKeyLengthBytes = 32;

/// libp2p `crypto.pb.KeyType.Ed25519`.
const int _libp2pKeyTypeEd25519 = 1;

/// Multihash code for the identity ("no hash") function.
const int _identityMultihashCode = 0x00;

/// Largest serialized public key libp2p inlines with the identity multihash.
const int _libp2pMaxInlineKeyLength = 42;

const String _base58BtcAlphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Thrown when a public key cannot be converted into a libp2p peer ID.
class PeerIdDerivationException implements Exception {
  const PeerIdDerivationException(this.message);

  final String message;

  @override
  String toString() => 'PeerIdDerivationException: $message';
}

/// Derives the libp2p peer ID for a BASE64-encoded Ed25519 public key.
///
/// [base64PublicKey] is the same standard-BASE64 encoding the bridge returns
/// for `identity.generate` / `identity.restore` and the same form persisted on
/// contacts and identities.
///
/// Throws [PeerIdDerivationException] for anything that is not a well-formed
/// 32-byte Ed25519 public key. Callers MUST fail closed on that exception:
/// an underivable key can never be allowed to keep a caller-supplied peer.
String ed25519PublicKeyToPeerId(String base64PublicKey) {
  final trimmed = base64PublicKey.trim();
  if (trimmed.isEmpty) {
    throw const PeerIdDerivationException('public key is empty');
  }

  final Uint8List rawKey;
  try {
    rawKey = base64Decode(trimmed);
  } catch (error) {
    throw PeerIdDerivationException('public key is not valid base64: $error');
  }

  return ed25519PublicKeyBytesToPeerId(rawKey);
}

/// Derives the libp2p peer ID for a raw 32-byte Ed25519 public key.
String ed25519PublicKeyBytesToPeerId(Uint8List rawKey) {
  if (rawKey.length != ed25519PublicKeyLengthBytes) {
    throw PeerIdDerivationException(
      'ed25519 public key must be $ed25519PublicKeyLengthBytes bytes, '
      'got ${rawKey.length}',
    );
  }

  // Step 1: libp2p crypto.pb.PublicKey protobuf.
  //   field 1 (Type, varint)  -> tag 0x08, value 0x01
  //   field 2 (Data,  bytes)  -> tag 0x12, length 0x20, then the key
  final protobuf = Uint8List(4 + ed25519PublicKeyLengthBytes);
  protobuf[0] = 0x08;
  protobuf[1] = _libp2pKeyTypeEd25519;
  protobuf[2] = 0x12;
  protobuf[3] = ed25519PublicKeyLengthBytes;
  protobuf.setRange(4, protobuf.length, rawKey);

  // Step 2: identity multihash. Guarded rather than assumed so a future key
  // type cannot silently take the inline path libp2p reserves for short keys.
  if (protobuf.length > _libp2pMaxInlineKeyLength) {
    throw PeerIdDerivationException(
      'serialized key length ${protobuf.length} exceeds the libp2p inline '
      'limit $_libp2pMaxInlineKeyLength',
    );
  }
  final multihash = Uint8List(2 + protobuf.length);
  multihash[0] = _identityMultihashCode;
  multihash[1] = protobuf.length;
  multihash.setRange(2, multihash.length, protobuf);

  // Step 3: base58btc.
  return _base58BtcEncode(multihash);
}

/// Returns true when [claimedPeerId] is exactly the peer ID [base64PublicKey]
/// derives to.
///
/// Returns false — never throws — for malformed input, so callers can treat
/// "cannot derive" and "does not match" as one fail-closed refusal.
bool ed25519PublicKeyMatchesPeerId({
  required String base64PublicKey,
  required String claimedPeerId,
}) {
  final expectedPeerId = claimedPeerId.trim();
  if (expectedPeerId.isEmpty) {
    return false;
  }
  try {
    return ed25519PublicKeyToPeerId(base64PublicKey) == expectedPeerId;
  } on PeerIdDerivationException {
    return false;
  }
}

/// Base58btc encoding (Bitcoin alphabet), matching multibase/libp2p output.
String _base58BtcEncode(Uint8List input) {
  if (input.isEmpty) {
    return '';
  }

  // Leading zero bytes each map to one leading '1'.
  var leadingZeros = 0;
  while (leadingZeros < input.length && input[leadingZeros] == 0) {
    leadingZeros++;
  }

  // Repeated big-number division by 58 over a mutable copy.
  final digits = <int>[];
  final buffer = Uint8List.fromList(input);
  var start = leadingZeros;
  while (start < buffer.length) {
    var remainder = 0;
    for (var i = start; i < buffer.length; i++) {
      final accumulator = (remainder << 8) + buffer[i];
      buffer[i] = accumulator ~/ 58;
      remainder = accumulator % 58;
    }
    digits.add(remainder);
    while (start < buffer.length && buffer[start] == 0) {
      start++;
    }
  }

  final encoded = StringBuffer();
  for (var i = 0; i < leadingZeros; i++) {
    encoded.write(_base58BtcAlphabet[0]);
  }
  for (var i = digits.length - 1; i >= 0; i--) {
    encoded.write(_base58BtcAlphabet[digits[i]]);
  }
  return encoded.toString();
}
