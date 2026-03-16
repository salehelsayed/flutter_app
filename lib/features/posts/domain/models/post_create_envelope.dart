import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
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
  final String mediaKind;
  final List<PostMediaAttachmentModel> media;
  final PostAudience audience;
  final String expiresAt;
  final bool keepAvailable;
  final int? nearbyDistanceM;
  final int? nearbySenderLatE3;
  final int? nearbySenderLngE3;
  final String? nearbySenderCapturedAt;
  final double? nearbySenderAccuracyM;
  final List<String> recipientPeerIds;

  const PostCreateEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.postId,
    required this.authorPeerId,
    required this.authorUsername,
    required this.text,
    required this.mediaKind,
    required this.media,
    required this.audience,
    required this.expiresAt,
    required this.keepAvailable,
    this.nearbyDistanceM,
    this.nearbySenderLatE3,
    this.nearbySenderLngE3,
    this.nearbySenderCapturedAt,
    this.nearbySenderAccuracyM,
    this.recipientPeerIds = const <String>[],
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
      mediaKind: post.mediaKind,
      media: post.media,
      audience: post.audience,
      expiresAt: post.expiresAt,
      keepAvailable: post.keepAvailable,
      nearbyDistanceM: post.nearbyDistanceM,
      nearbySenderLatE3: post.nearbySenderLatE3,
      nearbySenderLngE3: post.nearbySenderLngE3,
      nearbySenderCapturedAt: post.nearbySenderCapturedAt,
      nearbySenderAccuracyM: post.nearbySenderAccuracyM,
      recipientPeerIds: const <String>[],
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
      final mediaKind = snapshot['media_kind'] as String? ?? 'none';
      final mediaJson = (snapshot['media'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
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
      final radiusM = (audienceJson?['radius_m'] as num?)?.toInt();
      final selectedIds =
          (payload['selected_peer_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false);
      final recipientPeerIds =
          (payload['recipient_peer_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false);
      final audience = switch (audienceKind) {
        'pick_people' => PostAudience(
          kind: PostAudienceKind.pickPeople,
          selectedPeerIds: selectedIds,
          scopeLabel: audienceJson?['scope_label'] as String?,
        ),
        'people_nearby' when radiusM != null => PostAudience(
          kind: PostAudienceKind.peopleNearby,
          radiusM: radiusM,
          scopeLabel: audienceJson?['scope_label'] as String?,
        ),
        'all_friends' => PostAudience(
          kind: PostAudienceKind.allFriends,
          scopeLabel: audienceJson?['scope_label'] as String?,
        ),
        _ => throw const FormatException('invalid_audience'),
      };
      final nearbyContext = payload['nearby_context'] as Map<String, dynamic>?;
      final media = <PostMediaAttachmentModel>[];
      for (var index = 0; index < mediaJson.length; index++) {
        final attachment = PostMediaAttachmentModel.fromRenderableJson(
          mediaJson[index],
          postId: postId,
          position: index,
        );
        media.add(attachment);
      }
      if (!PostMediaAttachmentModel.isValidSnapshotMedia(
        mediaKind: mediaKind,
        media: media,
      )) {
        return null;
      }
      return PostCreateEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        postId: postId,
        authorPeerId: authorPeerId,
        authorUsername: authorUsername,
        text: text,
        mediaKind: mediaKind,
        media: media,
        audience: audience,
        expiresAt: expiresAt,
        keepAvailable: (snapshot['keep_available'] as bool?) ?? false,
        nearbyDistanceM: (nearbyContext?['distance_m'] as num?)?.toInt(),
        nearbySenderLatE3: nearbyContext?['sender_lat_e3'] as int?,
        nearbySenderLngE3: nearbyContext?['sender_lng_e3'] as int?,
        nearbySenderCapturedAt:
            nearbyContext?['sender_captured_at'] as String?,
        nearbySenderAccuracyM:
            (nearbyContext?['sender_accuracy_m'] as num?)?.toDouble(),
        recipientPeerIds: recipientPeerIds,
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

  String toJson({
    List<String>? selectedPeerIds,
    List<String>? recipientPeerIds,
    int? nearbyDistanceM,
  }) {
    final hasNearbyContext = nearbyDistanceM != null || _hasNearbyContext;
    final payload = <String, Object?>{
      'post_id': postId,
      'snapshot': <String, Object?>{
        'post_id': postId,
        'author_peer_id': authorPeerId,
        'author_username': authorUsername,
        'post_created_at': createdAt,
        'audience': <String, Object?>{
          'kind': audience.kind.toWireValue(),
          'radius_m': audience.radiusM,
          'scope_label': audience.scopeLabel,
        },
        'text': text,
        'media_kind': mediaKind,
        'media': media
            .map((attachment) => attachment.toRenderableJson())
            .toList(growable: false),
        'keep_available': keepAvailable,
        'expires_at': expiresAt,
      },
      if (selectedPeerIds != null && selectedPeerIds.isNotEmpty)
        'selected_peer_ids': selectedPeerIds,
      if (recipientPeerIds != null && recipientPeerIds.isNotEmpty)
        'recipient_peer_ids': recipientPeerIds,
      if (hasNearbyContext)
        'nearby_context': <String, Object?>{
          'distance_m': nearbyDistanceM ?? this.nearbyDistanceM,
          'sender_lat_e3': nearbySenderLatE3,
          'sender_lng_e3': nearbySenderLngE3,
          'sender_captured_at': nearbySenderCapturedAt,
          'sender_accuracy_m': nearbySenderAccuracyM,
        }..removeWhere((_, value) => value == null),
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

  String toInnerJson({
    List<String>? selectedPeerIds,
    List<String>? recipientPeerIds,
    int? nearbyDistanceM,
  }) {
    final hasNearbyContext = nearbyDistanceM != null || _hasNearbyContext;
    return jsonEncode({
      'post_id': postId,
      'snapshot': <String, Object?>{
        'post_id': postId,
        'author_peer_id': authorPeerId,
        'author_username': authorUsername,
        'post_created_at': createdAt,
        'audience': <String, Object?>{
          'kind': audience.kind.toWireValue(),
          'radius_m': audience.radiusM,
          'scope_label': audience.scopeLabel,
        },
        'text': text,
        'media_kind': mediaKind,
        'media': media
            .map((attachment) => attachment.toRenderableJson())
            .toList(growable: false),
        'keep_available': keepAvailable,
        'expires_at': expiresAt,
      },
      if (selectedPeerIds != null && selectedPeerIds.isNotEmpty)
        'selected_peer_ids': selectedPeerIds,
      if (recipientPeerIds != null && recipientPeerIds.isNotEmpty)
        'recipient_peer_ids': recipientPeerIds,
      if (hasNearbyContext)
        'nearby_context': <String, Object?>{
          'distance_m': nearbyDistanceM ?? this.nearbyDistanceM,
          'sender_lat_e3': nearbySenderLatE3,
          'sender_lng_e3': nearbySenderLngE3,
          'sender_captured_at': nearbySenderCapturedAt,
          'sender_accuracy_m': nearbySenderAccuracyM,
        }..removeWhere((_, value) => value == null),
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
      mediaKind: mediaKind,
      media: media,
      audience: audience,
      createdAt: createdAt,
      visibleAt: createdAt,
      expiresAt: expiresAt,
      keepAvailable: keepAvailable,
      nearbyDistanceM: nearbyDistanceM,
      nearbySenderLatE3: nearbySenderLatE3,
      nearbySenderLngE3: nearbySenderLngE3,
      nearbySenderCapturedAt: nearbySenderCapturedAt,
      nearbySenderAccuracyM: nearbySenderAccuracyM,
      isIncoming: isIncoming,
      isFocused: isFocused,
      deliveryStatus: deliveryStatus,
    );
  }

  bool get _hasNearbyContext =>
      nearbyDistanceM != null ||
      nearbySenderLatE3 != null ||
      nearbySenderLngE3 != null ||
      nearbySenderCapturedAt != null ||
      nearbySenderAccuracyM != null;

  static bool _isValidCreatedAt(String createdAt) {
    final timestamp = DateTime.tryParse(createdAt)?.toUtc();
    if (timestamp == null) {
      return false;
    }
    final latestAllowed = DateTime.now().toUtc().add(_maxFutureClockSkew);
    return !timestamp.isAfter(latestAllowed);
  }
}
