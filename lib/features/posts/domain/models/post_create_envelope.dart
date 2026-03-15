import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class PostCreateEnvelope {
  static const Duration _maxFutureClockSkew = Duration(minutes: 5);

  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String postId;
  final String authorPeerId;
  final String authorUsername;
  final String text;
  final PostAudience audience;
  final String expiresAt;
  final bool keepAvailable;

  const PostCreateEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.postId,
    required this.authorPeerId,
    required this.authorUsername,
    required this.text,
    required this.audience,
    required this.expiresAt,
    required this.keepAvailable,
  });

  factory PostCreateEnvelope.fromPost(PostModel post) {
    return PostCreateEnvelope(
      eventId: post.eventId,
      createdAt: post.createdAt,
      senderPeerId: post.senderPeerId,
      postId: post.id,
      authorPeerId: post.authorPeerId,
      authorUsername: post.authorUsername,
      text: post.text,
      audience: post.audience,
      expiresAt: post.expiresAt,
      keepAvailable: post.keepAvailable,
    );
  }

  static PostCreateEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_create') {
        return null;
      }
      if (json['version'] == '2') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final snapshot = payload?['snapshot'] as Map<String, dynamic>?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          payload == null ||
          snapshot == null) {
        return null;
      }
      final postId = payload['post_id'] as String?;
      final snapshotPostId = snapshot['post_id'] as String?;
      final authorPeerId = snapshot['author_peer_id'] as String?;
      final authorUsername = snapshot['author_username'] as String?;
      final text = snapshot['text'] as String?;
      final expiresAt = snapshot['expires_at'] as String?;
      if (postId == null ||
          snapshotPostId == null ||
          authorPeerId == null ||
          authorUsername == null ||
          text == null ||
          expiresAt == null) {
        return null;
      }
      if (snapshotPostId != postId || authorPeerId != senderPeerId) {
        return null;
      }
      if (!_isValidCreatedAt(createdAt)) {
        return null;
      }
      final audienceJson = snapshot['audience'] as Map<String, dynamic>?;
      final audienceKind = audienceJson?['kind'] as String? ?? 'all_friends';
      final selectedIds =
          (payload['selected_peer_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false);
      final audience = PostAudience(
        kind: audienceKind == 'pick_people'
            ? PostAudienceKind.pickPeople
            : PostAudienceKind.allFriends,
        selectedPeerIds: selectedIds,
        scopeLabel: audienceJson?['scope_label'] as String?,
      );
      return PostCreateEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        postId: postId,
        authorPeerId: authorPeerId,
        authorUsername: authorUsername,
        text: text,
        audience: audience,
        expiresAt: expiresAt,
        keepAvailable: (snapshot['keep_available'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_create' || json['version'] != '2') {
        return null;
      }
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null ||
          encrypted['kem'] == null ||
          encrypted['ciphertext'] == null ||
          encrypted['nonce'] == null) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  static Future<PostCreateEnvelope?> fromEncryptedJson({
    required String jsonString,
    required Bridge bridge,
    required String ownMlKemSecretKey,
  }) async {
    final envelope = parseEncryptedEnvelope(jsonString);
    if (envelope == null) {
      return null;
    }
    final encrypted = envelope['encrypted'] as Map<String, dynamic>;
    final decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );
    if (decryptResult['ok'] != true) {
      return null;
    }
    final payloadJson =
        jsonDecode(decryptResult['plaintext'] as String)
            as Map<String, dynamic>;
    return fromJson(
      jsonEncode({
        'type': 'post_create',
        'version': '1',
        'event_id': envelope['event_id'],
        'created_at': envelope['created_at'],
        'sender_peer_id': envelope['sender_peer_id'],
        'payload': payloadJson,
      }),
    );
  }

  String toJson({List<String>? selectedPeerIds}) {
    final payload = <String, Object?>{
      'post_id': postId,
      'snapshot': <String, Object?>{
        'post_id': postId,
        'author_peer_id': authorPeerId,
        'author_username': authorUsername,
        'post_created_at': createdAt,
        'audience': <String, Object?>{
          'kind': audience.kind.toWireValue(),
          'radius_m': null,
          'scope_label': audience.scopeLabel,
        },
        'text': text,
        'media_kind': 'none',
        'media': const <Object?>[],
        'keep_available': keepAvailable,
        'expires_at': expiresAt,
      },
      if (selectedPeerIds != null && selectedPeerIds.isNotEmpty)
        'selected_peer_ids': selectedPeerIds,
    };
    return jsonEncode({
      'type': 'post_create',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'payload': payload,
    });
  }

  String toInnerJson({List<String>? selectedPeerIds}) {
    return jsonEncode({
      'post_id': postId,
      'snapshot': <String, Object?>{
        'post_id': postId,
        'author_peer_id': authorPeerId,
        'author_username': authorUsername,
        'post_created_at': createdAt,
        'audience': <String, Object?>{
          'kind': audience.kind.toWireValue(),
          'radius_m': null,
          'scope_label': audience.scopeLabel,
        },
        'text': text,
        'media_kind': 'none',
        'media': const <Object?>[],
        'keep_available': keepAvailable,
        'expires_at': expiresAt,
      },
      if (selectedPeerIds != null && selectedPeerIds.isNotEmpty)
        'selected_peer_ids': selectedPeerIds,
    });
  }

  static String buildEncryptedEnvelope({
    required String eventId,
    required String createdAt,
    required String senderPeerId,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) {
    return jsonEncode({
      'type': 'post_create',
      'version': '2',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    });
  }

  PostModel toPostModel({
    required bool isIncoming,
    String deliveryStatus = 'available',
    bool isFocused = false,
  }) {
    return PostModel(
      id: postId,
      eventId: eventId,
      senderPeerId: senderPeerId,
      authorPeerId: authorPeerId,
      authorUsername: authorUsername,
      text: text,
      audience: audience,
      createdAt: createdAt,
      visibleAt: createdAt,
      expiresAt: expiresAt,
      keepAvailable: keepAvailable,
      isIncoming: isIncoming,
      isFocused: isFocused,
      deliveryStatus: deliveryStatus,
    );
  }

  static bool _isValidCreatedAt(String createdAt) {
    final timestamp = DateTime.tryParse(createdAt)?.toUtc();
    if (timestamp == null) {
      return false;
    }
    final latestAllowed = DateTime.now()
        .toUtc()
        .add(_maxFutureClockSkew);
    return !timestamp.isAfter(latestAllowed);
  }
}
