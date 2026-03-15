import 'dart:convert';

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
  });
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
  });

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
      );
    } catch (_) {
      return null;
    }
  }

  static String buildJson({
    required PostPassModel pass,
    required PostModel post,
  }) {
    return jsonEncode(<String, Object?>{
      'type': 'post_pass',
      'version': '1',
      'event_id': pass.eventId,
      'created_at': pass.createdAt,
      'sender_peer_id': pass.senderPeerId,
      'payload': <String, Object?>{
        'pass_id': pass.passId,
        'post_id': post.id,
        'passed_at': pass.passedAt,
        'passer_peer_id': pass.passerPeerId,
        'passer_username': pass.passerUsername,
        'original_snapshot': <String, Object?>{
          'post_id': post.id,
          'author_peer_id': post.authorPeerId,
          'author_username': post.authorUsername,
          'post_created_at': post.createdAt,
          'audience': <String, Object?>{
            'kind': post.audience.kind.toWireValue(),
            'radius_m': post.audience.radiusM,
            'scope_label': post.audience.scopeLabel,
          },
          'text': post.text,
          'media_kind': post.mediaKind,
          'media': post.media
              .map((attachment) => attachment.toRenderableJson())
              .toList(growable: false),
          'keep_available': post.keepAvailable,
          'expires_at': post.expiresAt,
        },
      },
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
    );
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
}
