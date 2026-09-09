import 'dart:convert';

import 'package:flutter_app/core/media/private_media_policy.dart';

import 'conversation_message.dart';

/// Wire-format model for chat messages sent over P2P.
///
/// Follows the same envelope pattern as `contact_request`:
/// ```json
/// {
///   "type": "chat_message",
///   "version": "1",
///   "payload": { "id", "text", "senderPeerId", "senderUsername", "timestamp" }
/// }
/// ```
class MessagePayload {
  static const actionSend = 'send';
  static const actionEdit = 'edit';

  final String id;
  final String text;
  final String senderPeerId;
  final String senderUsername;
  final String timestamp;
  final String action;

  /// Immutable relay event identity for a same-message mutation such as edit.
  /// The authored message [id] remains the local mutation target.
  final String? eventId;
  final String? editedAt;
  final String? quotedMessageId;
  final List<Map<String, dynamic>>? media;

  /// F8 tier-2: wire-stamped propagated source-message id (survives a forward's
  /// id+timestamp re-mint). Rides the INNER (encrypted) JSON only. NULL for
  /// legacy senders → receiver falls back to timestamp-exact tier-1.
  final String? dedupKey;

  /// Direct-only forwarding marker. Rides v1 payload / encrypted v2 inner JSON.
  final bool isForwarded;

  /// Versioned private-media policy. This field is serialized only by
  /// [toInnerJson] and parsed only by [fromDecryptedJson].
  final PrivateMediaPolicy privateMediaPolicy;

  /// Optional diagnostic correlation carried inside the encrypted payload;
  /// never message or media authority.
  final String? diagnosticTraceId;

  static String? validatedDiagnosticTraceId(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)) {
      return null;
    }
    return value.toLowerCase();
  }

  const MessagePayload({
    required this.id,
    required this.text,
    required this.senderPeerId,
    required this.senderUsername,
    required this.timestamp,
    this.action = actionSend,
    this.eventId,
    this.editedAt,
    this.quotedMessageId,
    this.media,
    this.dedupKey,
    this.isForwarded = false,
    this.privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
    this.diagnosticTraceId,
  });

  bool get isEdit => action == actionEdit;

  /// Parses a JSON string into a MessagePayload, or returns null if invalid.
  ///
  /// Expects the full envelope: `{ "type": "chat_message", "version": "1", "payload": {...} }`.
  static MessagePayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'chat_message') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final id = payload['id'] as String?;
      final text = payload['text'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final senderUsername = payload['senderUsername'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          text == null ||
          senderPeerId == null ||
          senderUsername == null ||
          timestamp == null) {
        return null;
      }

      final action = payload['action'] as String? ?? actionSend;
      final eventId = payload['eventId'] as String?;
      final editedAt = payload['editedAt'] as String?;
      final quotedMessageId = payload['quotedMessageId'] as String?;
      final dedupKey = payload['dedupKey'] as String?;
      final isForwarded = payload['isForwarded'] == true;

      final rawMedia = payload['media'] as List<dynamic>?;
      final media = rawMedia
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return MessagePayload(
        id: id,
        text: text,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
        action: action,
        eventId: eventId,
        editedAt: editedAt,
        quotedMessageId: quotedMessageId,
        media: media,
        dedupKey: dedupKey,
        isForwarded: isForwarded,
        diagnosticTraceId: validatedDiagnosticTraceId(
          payload['diagnosticTraceId'],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes to the full JSON envelope string.
  String toJson() {
    final payload = {
      'id': id,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      if (action != actionSend) 'action': action,
      'eventId': ?eventId,
      if (editedAt != null) 'editedAt': editedAt,
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      if (media != null && media!.isNotEmpty) 'media': media,
      if (dedupKey != null) 'dedupKey': dedupKey,
      if (isForwarded) 'isForwarded': true,
    };
    final envelope = {
      'type': 'chat_message',
      'version': '1',
      'payload': payload,
    };
    return jsonEncode(envelope);
  }

  /// Builds a v2 encrypted envelope JSON string.
  ///
  /// The envelope contains the KEM ciphertext, AES ciphertext, and nonce
  /// alongside the sender's peer ID (cleartext for routing). The sender
  /// username and diagnostic correlation stay inside the encrypted inner
  /// payload. Relay custody requires the outer envelope's exact field set.
  static String buildEncryptedEnvelope({
    required String id,
    required String senderPeerId,
    required String senderUsername,
    required String kem,
    required String ciphertext,
    required String nonce,
    String? eventId,
  }) {
    final envelope = {
      'type': 'chat_message',
      'version': '2',
      'id': id,
      'eventId': ?eventId,
      'senderPeerId': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    };
    return jsonEncode(envelope);
  }

  /// Attempts to parse a JSON string as a v2 encrypted envelope.
  ///
  /// Returns the parsed envelope map if it's a v2 chat_message with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'chat_message') return null;
      if (json['version'] != '2') return null;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return null;
      if (encrypted['kem'] == null ||
          encrypted['ciphertext'] == null ||
          encrypted['nonce'] == null) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  /// Creates a MessagePayload from decrypted inner JSON string.
  ///
  /// The inner JSON contains: id, text, senderPeerId, senderUsername, timestamp.
  static MessagePayload? fromDecryptedJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      final id = payload['id'] as String?;
      final text = payload['text'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final senderUsername = payload['senderUsername'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          text == null ||
          senderPeerId == null ||
          senderUsername == null ||
          timestamp == null) {
        return null;
      }

      final action = payload['action'] as String? ?? actionSend;
      final eventId = payload['eventId'] as String?;
      final editedAt = payload['editedAt'] as String?;
      final quotedMessageId = payload['quotedMessageId'] as String?;
      final dedupKey = payload['dedupKey'] as String?;
      final isForwarded = payload['isForwarded'] == true;

      final rawMedia = payload['media'] as List<dynamic>?;
      final media = rawMedia
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final privateMediaPolicy = PrivateMediaPolicy.fromJson(
        payload['privateMedia'],
        eligibility: _privateMediaEligibility(
          text: text,
          action: action,
          isForwarded: isForwarded,
          media: media,
        ),
      );

      return MessagePayload(
        id: id,
        text: text,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
        action: action,
        eventId: eventId,
        editedAt: editedAt,
        quotedMessageId: quotedMessageId,
        media: media,
        dedupKey: dedupKey,
        isForwarded: isForwarded,
        privateMediaPolicy: privateMediaPolicy,
        diagnosticTraceId: validatedDiagnosticTraceId(
          payload['diagnosticTraceId'],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes only the inner payload fields (without envelope wrapper).
  ///
  /// Used as plaintext input for encryption in v2 flow.
  String toInnerJson() {
    final privateMedia = privateMediaPolicy.toJson();
    final inner = <String, Object?>{
      'id': id,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      if (action != actionSend) 'action': action,
      'eventId': ?eventId,
      if (editedAt != null) 'editedAt': editedAt,
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      if (media != null && media!.isNotEmpty) 'media': media,
      if (dedupKey != null) 'dedupKey': dedupKey,
      if (isForwarded) 'isForwarded': true,
    };
    if (privateMedia != null) inner['privateMedia'] = privateMedia;
    if (validatedDiagnosticTraceId(diagnosticTraceId) case final traceId?) {
      inner['diagnosticTraceId'] = traceId;
    }
    return jsonEncode(inner);
  }

  /// Converts this wire-format payload to a local ConversationMessage.
  ///
  /// [contactPeerId] is the peer ID of the contact the conversation is with.
  /// [isIncoming] indicates whether the message was received or sent.
  /// [wireEnvelope] is the serialized wire JSON for retry (outgoing only).
  ConversationMessage toConversationMessage({
    required String contactPeerId,
    required bool isIncoming,
    String status = 'sent',
    String? createdAt,
    String? editedAt,
    String? transport,
    String? wireEnvelope,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
      editedAt: editedAt ?? this.editedAt,
      quotedMessageId: quotedMessageId,
      transport: transport,
      wireEnvelope: wireEnvelope,
      dedupKey: dedupKey,
      isForwarded: isForwarded,
      privateMediaPolicy: privateMediaPolicy,
      privateMediaState: privateMediaPolicy.initialState,
    );
  }

  static PrivateMediaEligibility _privateMediaEligibility({
    required String text,
    required String action,
    required bool isForwarded,
    required List<Map<String, dynamic>>? media,
  }) {
    var kind = PrivateMediaAttachmentKind.unknown;
    if (media != null && media.length == 1) {
      final item = media.single;
      final mime = (item['mime'] as String? ?? '').toLowerCase();
      final mediaType = (item['mediaType'] as String? ?? '').toLowerCase();
      if (mime == 'image/gif' || mediaType == 'gif') {
        kind = PrivateMediaAttachmentKind.gif;
      } else if (mime.startsWith('image/') || mediaType == 'image') {
        kind = PrivateMediaAttachmentKind.image;
      } else if (mime.startsWith('video/') || mediaType == 'video') {
        kind = PrivateMediaAttachmentKind.video;
      } else if (mime.startsWith('audio/') || mediaType == 'audio') {
        kind = PrivateMediaAttachmentKind.audio;
      } else if (mime.isNotEmpty || mediaType == 'file') {
        kind = PrivateMediaAttachmentKind.file;
      }
    }
    return PrivateMediaEligibility(
      attachmentCount: media?.length ?? 0,
      attachmentKind: kind,
      hasTextOrCaption: text.trim().isNotEmpty,
      isEdit: action == actionEdit,
      isForward: isForwarded,
    );
  }
}
