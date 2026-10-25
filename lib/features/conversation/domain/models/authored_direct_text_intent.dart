import 'conversation_message.dart';

/// Device-local authored text awaiting the existing encrypted custody commit.
/// Its token is never serialized onto the wire.
class AuthoredDirectTextIntent {
  const AuthoredDirectTextIntent({
    required this.id,
    required this.contactPeerId,
    required this.text,
    required this.timestamp,
    required this.token,
    this.quotedMessageId,
  });

  final String id;
  final String contactPeerId;
  final String text;
  final String timestamp;
  final String token;
  final String? quotedMessageId;

  factory AuthoredDirectTextIntent.fromMap(Map<String, Object?> row) =>
      AuthoredDirectTextIntent(
        id: row['id'] as String,
        contactPeerId: row['contact_peer_id'] as String,
        text: row['text'] as String,
        timestamp: row['timestamp'] as String,
        token: row['token'] as String,
        quotedMessageId: row['quoted_message_id'] as String?,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'contact_peer_id': contactPeerId,
    'text': text,
    'quoted_message_id': quotedMessageId,
    'timestamp': timestamp,
    'token': token,
  };

  ConversationMessage toMessage(String senderPeerId) => ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: timestamp,
    createdAt: timestamp,
    quotedMessageId: quotedMessageId,
    status: 'sending',
    isIncoming: false,
  );
}
