import 'dart:convert';

import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

/// Wire-format model for emoji reactions on group messages.
///
/// Travels inside the encrypted portion of a v3 group_reaction envelope.
/// Go handles encryption/signing — Dart just builds the inner JSON.
///
/// Inner payload:
/// ```json
/// { "id", "messageId", "emoji", "action", "senderPeerId", "timestamp" }
/// ```
/// Action is either `"add"` or `"remove"`.
class GroupReactionPayload {
  static const actionAdd = 'add';
  static const actionRemove = 'remove';

  final String id;
  final String messageId;
  final String emoji;
  final String action; // 'add' | 'remove'
  final String senderPeerId;
  final String timestamp;

  const GroupReactionPayload({
    required this.id,
    required this.messageId,
    required this.emoji,
    required this.action,
    required this.senderPeerId,
    required this.timestamp,
  });

  /// Serializes the inner payload to a JSON string.
  ///
  /// This is what gets encrypted by Go inside the group_reaction envelope.
  String toInnerJson() {
    return jsonEncode({
      'id': id,
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
    });
  }

  /// Creates a GroupReactionPayload from a decrypted inner JSON string.
  ///
  /// Used on the receive side after Go decrypts the envelope.
  static GroupReactionPayload? fromDecryptedJson(String innerJson) {
    try {
      final decoded = jsonDecode(innerJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final payload = decoded;
      final id = _requiredString(payload['id']);
      final messageId = _requiredString(payload['messageId']);
      final emoji = _requiredString(payload['emoji']);
      final action = _requiredString(payload['action']);
      final senderPeerId = _requiredString(payload['senderPeerId']);
      final timestamp = _requiredString(payload['timestamp']);

      if (id == null ||
          messageId == null ||
          emoji == null ||
          action == null ||
          senderPeerId == null ||
          timestamp == null) {
        return null;
      }
      if (action != actionAdd && action != actionRemove) {
        return null;
      }
      if (DateTime.tryParse(timestamp) == null) {
        return null;
      }

      return GroupReactionPayload(
        id: id,
        messageId: messageId,
        emoji: emoji,
        action: action,
        senderPeerId: senderPeerId,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Converts this wire-format payload to a local [MessageReaction].
  MessageReaction toMessageReaction() {
    return MessageReaction(
      id: id,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: senderPeerId,
      timestamp: timestamp,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

String? _requiredString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
