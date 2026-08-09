import 'dart:convert';

/// The exact app-owned event shapes stored in the shared physical v109 outbox.
enum DirectInboxEventEnvelopeKind { reaction, edit, deletion }

/// Strict outer-envelope classification for the shared v109 custody owner.
///
/// This parser intentionally sees only authenticated clear outer fields. It
/// never interprets encrypted mutation content or invents a local subtype key.
class DirectInboxEventEnvelope {
  const DirectInboxEventEnvelope({
    required this.kind,
    required this.eventId,
    required this.senderPeerId,
    this.targetMessageId,
    this.reactionAction,
  });

  final DirectInboxEventEnvelopeKind kind;
  final String eventId;
  final String senderPeerId;
  final String? targetMessageId;
  final String? reactionAction;

  bool get isMutation =>
      kind == DirectInboxEventEnvelopeKind.edit ||
      kind == DirectInboxEventEnvelopeKind.deletion;
}

DirectInboxEventEnvelope? classifyDirectInboxEventEnvelope(
  String wireEnvelope,
) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return null;
    final encrypted = decoded['encrypted'];
    if (encrypted is! Map<String, dynamic> ||
        !_hasExactKeys(encrypted, const <String>{
          'kem',
          'ciphertext',
          'nonce',
        }) ||
        !_isNonBlank(encrypted['kem']) ||
        !_isNonBlank(encrypted['ciphertext']) ||
        !_isNonBlank(encrypted['nonce']) ||
        decoded['version'] != '2' ||
        !_isNonBlank(decoded['senderPeerId']) ||
        !_isNonBlank(decoded['eventId'])) {
      return null;
    }

    final type = decoded['type'];
    if (type == 'message_reaction') {
      if (!_hasExactKeys(decoded, const <String>{
            'type',
            'version',
            'eventId',
            'action',
            'targetMessageId',
            'senderPeerId',
            'encrypted',
          }) ||
          !_isNonBlank(decoded['targetMessageId']) ||
          (decoded['action'] != 'add' && decoded['action'] != 'remove')) {
        return null;
      }
      return DirectInboxEventEnvelope(
        kind: DirectInboxEventEnvelopeKind.reaction,
        eventId: decoded['eventId'] as String,
        senderPeerId: decoded['senderPeerId'] as String,
        targetMessageId: decoded['targetMessageId'] as String,
        reactionAction: decoded['action'] as String,
      );
    }

    if (type == 'chat_message') {
      if (!_hasExactKeys(decoded, const <String>{
            'type',
            'version',
            'id',
            'eventId',
            'senderPeerId',
            'encrypted',
          }) ||
          !_isNonBlank(decoded['id'])) {
        return null;
      }
      return DirectInboxEventEnvelope(
        kind: DirectInboxEventEnvelopeKind.edit,
        eventId: decoded['eventId'] as String,
        senderPeerId: decoded['senderPeerId'] as String,
        targetMessageId: decoded['id'] as String,
      );
    }

    if (type == 'message_deletion') {
      if (!_hasExactKeys(decoded, const <String>{
        'type',
        'version',
        'eventId',
        'senderPeerId',
        'encrypted',
      })) {
        return null;
      }
      return DirectInboxEventEnvelope(
        kind: DirectInboxEventEnvelopeKind.deletion,
        eventId: decoded['eventId'] as String,
        senderPeerId: decoded['senderPeerId'] as String,
      );
    }
    return null;
  } on FormatException {
    return null;
  }
}

bool _hasExactKeys(Map<String, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);

bool _isNonBlank(Object? value) => value is String && value.trim().isNotEmpty;
