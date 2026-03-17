import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';

class RenderablePostSnapshot {
  final String postId;
  final String authorPeerId;
  final String authorUsername;
  final String postCreatedAt;
  final PostAudience audience;
  final String text;
  final String mediaKind;
  final List<PostMediaAttachmentModel> media;
  final bool keepAvailable;
  final String expiresAt;
  final String? originalAuthorAvatarBase64;

  const RenderablePostSnapshot({
    required this.postId,
    required this.authorPeerId,
    required this.authorUsername,
    required this.postCreatedAt,
    required this.audience,
    required this.text,
    required this.mediaKind,
    required this.media,
    required this.keepAvailable,
    required this.expiresAt,
    this.originalAuthorAvatarBase64,
  });
}

class PostMediaCryptoEntry {
  final String keyBase64;
  final String nonce;
  final String blobId;

  const PostMediaCryptoEntry({
    required this.keyBase64,
    required this.nonce,
    required this.blobId,
  });

  Map<String, Object?> toJson() => {
    'key_base64': keyBase64,
    'nonce': nonce,
    'blob_id': blobId,
  };

  static PostMediaCryptoEntry? fromJson(Map<String, dynamic> json) {
    final keyBase64 = json['key_base64'] as String?;
    final nonce = json['nonce'] as String?;
    final blobId = json['blob_id'] as String?;
    if (keyBase64 == null || nonce == null || blobId == null) {
      return null;
    }
    return PostMediaCryptoEntry(
      keyBase64: keyBase64,
      nonce: nonce,
      blobId: blobId,
    );
  }
}

class PostPassEnvelope {
  static const Duration _maxFutureClockSkew = Duration(minutes: 5);

  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String passId;
  final String postId;
  final String passedAt;
  final String passerPeerId;
  final String passerUsername;
  final RenderablePostSnapshot originalSnapshot;
  final List<String> participantPeerIds;
  final List<String> activeHeartPeerIds;
  final int? repostTotalBaseline;
  final Map<String, PostMediaCryptoEntry>? mediaKeys;

  const PostPassEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.passId,
    required this.postId,
    required this.passedAt,
    required this.passerPeerId,
    required this.passerUsername,
    required this.originalSnapshot,
    this.participantPeerIds = const <String>[],
    this.activeHeartPeerIds = const <String>[],
    this.repostTotalBaseline,
    this.mediaKeys,
  });

  factory PostPassEnvelope.fromPass({
    required PostPassModel pass,
    required PostModel post,
    List<String>? participantPeerIds,
    List<String>? activeHeartPeerIds,
    int? repostTotalBaseline,
    Map<String, PostMediaCryptoEntry>? mediaKeys,
    String? originalAuthorAvatarBase64,
  }) {
    final persistedInnerPayload = pass.innerPayloadJson;
    if (persistedInnerPayload != null && persistedInnerPayload.isNotEmpty) {
      final persistedEnvelope = PostPassEnvelope.fromInnerJson(
        innerJson: persistedInnerPayload,
        eventId: pass.eventId,
        createdAt: pass.createdAt,
        senderPeerId: pass.senderPeerId,
      );
      if (persistedEnvelope != null) {
        return persistedEnvelope;
      }
    }
    return PostPassEnvelope(
      eventId: pass.eventId,
      createdAt: pass.createdAt,
      senderPeerId: pass.senderPeerId,
      passId: pass.passId,
      postId: post.id,
      passedAt: pass.passedAt,
      passerPeerId: pass.passerPeerId,
      passerUsername: pass.passerUsername,
      originalSnapshot: RenderablePostSnapshot(
        postId: post.id,
        authorPeerId: post.authorPeerId,
        authorUsername: post.authorUsername,
        postCreatedAt: post.createdAt,
        audience: post.audience,
        text: post.text,
        mediaKind: post.mediaKind,
        media: post.media,
        keepAvailable: post.keepAvailable,
        expiresAt: post.expiresAt,
        originalAuthorAvatarBase64: originalAuthorAvatarBase64,
      ),
      participantPeerIds:
          participantPeerIds ??
          _sortedUniqueNonEmpty(<String>[post.authorPeerId, pass.passerPeerId]),
      activeHeartPeerIds: _sortedUniqueNonEmpty(
        activeHeartPeerIds ?? const <String>[],
      ),
      repostTotalBaseline: repostTotalBaseline ?? 0,
      mediaKeys: mediaKeys,
    );
  }

  static PostPassEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_pass' || json['version'] == '2') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final snapshotJson =
          payload?['original_snapshot'] as Map<String, dynamic>?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          payload == null ||
          snapshotJson == null) {
        return null;
      }
      if (!_isValidCreatedAt(createdAt)) {
        return null;
      }

      final passId = payload['pass_id'] as String?;
      final postId = payload['post_id'] as String?;
      final passedAt = payload['passed_at'] as String?;
      final passerPeerId = payload['passer_peer_id'] as String?;
      final passerUsername = payload['passer_username'] as String?;
      final participantPeerIds =
          (payload['participant_peer_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false);
      final heartBaseline = payload['heart_baseline'] as Map<String, dynamic>?;
      final activeHeartPeerIds =
          (heartBaseline?['active_peer_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false);
      final repostTotalBaseline =
          (payload['repost_total_baseline'] as num?)?.toInt() ?? 0;
      final rawMediaKeys = payload['media_keys'] as Map<String, dynamic>?;
      final mediaKeys = rawMediaKeys == null
          ? null
          : <String, PostMediaCryptoEntry>{
              for (final entry in rawMediaKeys.entries)
                if (PostMediaCryptoEntry.fromJson(
                      entry.value as Map<String, dynamic>,
                    ) !=
                    null)
                  entry.key: PostMediaCryptoEntry.fromJson(
                    entry.value as Map<String, dynamic>,
                  )!,
            };
      final snapshot = _parseOriginalSnapshot(snapshotJson);
      if (passId == null ||
          postId == null ||
          passedAt == null ||
          passerPeerId == null ||
          passerUsername == null ||
          snapshot == null) {
        return null;
      }
      if (passerPeerId != senderPeerId || snapshot.postId != postId) {
        return null;
      }
      if (snapshot.audience.kind == PostAudienceKind.pickPeople) {
        return null;
      }

      return PostPassEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        passId: passId,
        postId: postId,
        passedAt: passedAt,
        passerPeerId: passerPeerId,
        passerUsername: passerUsername,
        originalSnapshot: snapshot,
        participantPeerIds: _sortedUniqueNonEmpty(participantPeerIds),
        activeHeartPeerIds: _sortedUniqueNonEmpty(activeHeartPeerIds),
        repostTotalBaseline: repostTotalBaseline ?? 0,
        mediaKeys: mediaKeys,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_pass' || json['version'] != '2') {
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

  static Future<PostPassEnvelope?> fromEncryptedJson({
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
        'type': 'post_pass',
        'version': '1',
        'event_id': envelope['event_id'],
        'created_at': envelope['created_at'],
        'sender_peer_id': envelope['sender_peer_id'],
        'payload': payloadJson,
      }),
    );
  }

  static PostPassEnvelope? fromInnerJson({
    required String innerJson,
    required String eventId,
    required String createdAt,
    required String senderPeerId,
  }) {
    try {
      return fromJson(
        jsonEncode({
          'type': 'post_pass',
          'version': '1',
          'event_id': eventId,
          'created_at': createdAt,
          'sender_peer_id': senderPeerId,
          'payload': jsonDecode(innerJson) as Map<String, dynamic>,
        }),
      );
    } catch (_) {
      return null;
    }
  }

  static String buildJson({
    required PostPassModel pass,
    required PostModel post,
    List<String>? participantPeerIds,
    List<String>? activeHeartPeerIds,
    int? repostTotalBaseline,
  }) {
    return PostPassEnvelope.fromPass(
      pass: pass,
      post: post,
      participantPeerIds: participantPeerIds,
      activeHeartPeerIds: activeHeartPeerIds,
      repostTotalBaseline: repostTotalBaseline,
      originalAuthorAvatarBase64: _encodeAvatarBytes(
        post.originalAuthorAvatarBytes,
      ),
    ).toJson();
  }

  String toJson() {
    return jsonEncode(<String, Object?>{
      'type': 'post_pass',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'payload': _buildPayloadJson(),
    });
  }

  String toInnerJson() {
    return jsonEncode(_buildPayloadJson());
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
      'type': 'post_pass',
      'version': '2',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    });
  }

  PostModel toPostModel({
    bool isIncoming = true,
    String deliveryStatus = 'delivered',
  }) {
    return PostModel(
      id: postId,
      eventId: eventId,
      senderPeerId: passerPeerId,
      authorPeerId: originalSnapshot.authorPeerId,
      authorUsername: originalSnapshot.authorUsername,
      text: originalSnapshot.text,
      audience: originalSnapshot.audience,
      createdAt: originalSnapshot.postCreatedAt,
      visibleAt: passedAt,
      expiresAt: originalSnapshot.expiresAt,
      keepAvailable: originalSnapshot.keepAvailable,
      mediaKind: originalSnapshot.mediaKind,
      media: originalSnapshot.media,
      isIncoming: isIncoming,
      deliveryStatus: deliveryStatus,
      originalAuthorAvatarBytes: _decodeAvatarBytes(
        originalSnapshot.originalAuthorAvatarBase64,
      ),
    );
  }

  Map<String, Object?> _buildPayloadJson() {
    return <String, Object?>{
      'pass_id': passId,
      'post_id': postId,
      'passed_at': passedAt,
      'passer_peer_id': passerPeerId,
      'passer_username': passerUsername,
      if (participantPeerIds.isNotEmpty)
        'participant_peer_ids': participantPeerIds,
      'heart_baseline': <String, Object?>{
        'active_peer_ids': activeHeartPeerIds,
      },
      'repost_total_baseline': repostTotalBaseline,
      if (mediaKeys != null && mediaKeys!.isNotEmpty)
        'media_keys': <String, Object?>{
          for (final entry in mediaKeys!.entries)
            entry.key: entry.value.toJson(),
        },
      'original_snapshot': <String, Object?>{
        'post_id': originalSnapshot.postId,
        'author_peer_id': originalSnapshot.authorPeerId,
        'author_username': originalSnapshot.authorUsername,
        'post_created_at': originalSnapshot.postCreatedAt,
        'audience': <String, Object?>{
          'kind': originalSnapshot.audience.kind.toWireValue(),
          'radius_m': originalSnapshot.audience.radiusM,
          'scope_label': originalSnapshot.audience.scopeLabel,
        },
        'text': originalSnapshot.text,
        'media_kind': originalSnapshot.mediaKind,
        'media': originalSnapshot.media
            .map((attachment) => attachment.toRenderableJson())
            .toList(growable: false),
        'keep_available': originalSnapshot.keepAvailable,
        'expires_at': originalSnapshot.expiresAt,
        if (originalSnapshot.originalAuthorAvatarBase64 != null)
          'original_author_avatar_base64':
              originalSnapshot.originalAuthorAvatarBase64,
      },
    };
  }

  static RenderablePostSnapshot? _parseOriginalSnapshot(
    Map<String, dynamic> json,
  ) {
    final postId = json['post_id'] as String?;
    final authorPeerId = json['author_peer_id'] as String?;
    final authorUsername = json['author_username'] as String?;
    final postCreatedAt = json['post_created_at'] as String?;
    final text = json['text'] as String?;
    final expiresAt = json['expires_at'] as String?;
    final mediaKind = json['media_kind'] as String? ?? 'none';
    final audienceJson = json['audience'] as Map<String, dynamic>?;
    if (postId == null ||
        authorPeerId == null ||
        authorUsername == null ||
        postCreatedAt == null ||
        text == null ||
        expiresAt == null ||
        audienceJson == null) {
      return null;
    }
    final audience = _parseAudience(audienceJson);
    if (audience == null) {
      return null;
    }
    final media = <PostMediaAttachmentModel>[];
    final mediaJson = (json['media'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    for (var index = 0; index < mediaJson.length; index++) {
      media.add(
        PostMediaAttachmentModel.fromRenderableJson(
          mediaJson[index],
          postId: postId,
          position: index,
        ),
      );
    }
    if (!PostMediaAttachmentModel.isValidSnapshotMedia(
      mediaKind: mediaKind,
      media: media,
    )) {
      return null;
    }
    return RenderablePostSnapshot(
      postId: postId,
      authorPeerId: authorPeerId,
      authorUsername: authorUsername,
      postCreatedAt: postCreatedAt,
      audience: audience,
      text: text,
      mediaKind: mediaKind,
      media: media,
      keepAvailable: (json['keep_available'] as bool?) ?? false,
      expiresAt: expiresAt,
      originalAuthorAvatarBase64:
          json['original_author_avatar_base64'] as String?,
    );
  }

  static PostAudience? _parseAudience(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'all_friends';
    final radiusM = (json['radius_m'] as num?)?.toInt();
    final scopeLabel = json['scope_label'] as String?;
    return switch (kind) {
      'pick_people' => PostAudience(
        kind: PostAudienceKind.pickPeople,
        scopeLabel: scopeLabel,
      ),
      'people_nearby' when radiusM != null => PostAudience(
        kind: PostAudienceKind.peopleNearby,
        radiusM: radiusM,
        scopeLabel: scopeLabel,
      ),
      'all_friends' => PostAudience(
        kind: PostAudienceKind.allFriends,
        scopeLabel: scopeLabel,
      ),
      _ => null,
    };
  }

  static bool _isValidCreatedAt(String rawCreatedAt) {
    final createdAt = DateTime.tryParse(rawCreatedAt)?.toUtc();
    if (createdAt == null) {
      return false;
    }
    return createdAt.isBefore(DateTime.now().toUtc().add(_maxFutureClockSkew));
  }

  static String? _encodeAvatarBytes(Uint8List? avatarBytes) {
    if (avatarBytes == null) {
      return null;
    }
    return base64Encode(avatarBytes);
  }

  static Uint8List? _decodeAvatarBytes(String? avatarBase64) {
    if (avatarBase64 == null) {
      return null;
    }
    try {
      return base64Decode(avatarBase64);
    } catch (_) {
      return null;
    }
  }

  static List<String> _sortedUniqueNonEmpty(Iterable<String> peerIds) {
    final result =
        peerIds
            .where((peerId) => peerId.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return result;
  }
}
