import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Returns a process-stable, non-negative 31-bit Android notification id.
///
/// Dart's [String.hashCode] is not a cross-process persistence contract. Using
/// the first four SHA-256 bytes gives the foreground and headless isolates the
/// same conversation-card identity after a process restart.
int deterministicConversationNotificationId(String conversationKey) {
  final normalized = conversationKey.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      conversationKey,
      'conversationKey',
      'must not be empty',
    );
  }
  final bytes = sha256.convert(utf8.encode(normalized)).bytes;
  return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0) &
      0x7fffffff;
}

/// Cross-language reaction event/collapse identity, bounded to APNs' 64-byte
/// collapse-id limit. Go and Swift consume the same fixture vectors.
String boundedReactionEventIdentity(String eventId) {
  final normalized = eventId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(eventId, 'eventId', 'must not be empty');
  }
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return 'reaction:${digest.substring(0, 48)}';
}
