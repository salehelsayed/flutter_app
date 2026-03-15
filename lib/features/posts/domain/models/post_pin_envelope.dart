import 'dart:convert';

import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

class PostPinSnapshot {
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

  const PostPinSnapshot({
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

  factory PostPinSnapshot.fromJson(Map<String, dynamic> json) {
    final postId = json['post_id'] as String?;
    final authorPeerId = json['author_peer_id'] as String?;
    final authorUsername = json['author_username'] as String?;
    final postCreatedAt = json['post_created_at'] as String?;
    final text = json['text'] as String?;
    final mediaKind = json['media_kind'] as String? ?? 'none';
    final expiresAt = json['expires_at'] as String?;
    final keepAvailable = json['keep_available'] as bool?;
    final audienceJson = json['audience'] as Map<String, dynamic>?;
    if (postId == null ||
        authorPeerId == null ||
        authorUsername == null ||
        postCreatedAt == null ||
        text == null ||
        expiresAt == null ||
        keepAvailable == null ||
        audienceJson == null) {
      throw const FormatException('invalid_pin_snapshot');
    }
    final audience = _parseAudience(audienceJson);
    final mediaJson = (json['media'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final media = <PostMediaAttachmentModel>[
      for (var index = 0; index < mediaJson.length; index++)
        PostMediaAttachmentModel.fromRenderableJson(
          mediaJson[index],
          postId: postId,
          position: index,
        ),
    ];
    if (!PostMediaAttachmentModel.isValidSnapshotMedia(
      mediaKind: mediaKind,
      media: media,
    )) {
      throw const FormatException('invalid_snapshot_media');
    }
    return PostPinSnapshot(
      postId: postId,
      authorPeerId: authorPeerId,
      authorUsername: authorUsername,
      postCreatedAt: postCreatedAt,
      audience: audience,
      text: text,
      mediaKind: mediaKind,
      media: media,
      keepAvailable: keepAvailable,
      expiresAt: expiresAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'post_id': postId,
      'author_peer_id': authorPeerId,
      'author_username': authorUsername,
      'post_created_at': postCreatedAt,
      'audience': <String, Object?>{
        'kind': audience.kind.toWireValue(),
        'radius_m': audience.radiusM,
        'scope_label': audience.scopeLabel,
      },
      'text': text,
      'media_kind': mediaKind,
      'media': media
          .map((attachment) => attachment.toRenderableJson())
          .toList(),
      'keep_available': keepAvailable,
      'expires_at': expiresAt,
    };
  }

  static PostAudience _parseAudience(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'all_friends';
    final scopeLabel = json['scope_label'] as String?;
    switch (kind) {
      case 'pick_people':
        final selectedPeerIds =
            (json['selected_peer_ids'] as List<dynamic>? ?? const <dynamic>[])
                .map((value) => value.toString())
                .toList(growable: false);
        return PostAudience(
          kind: PostAudienceKind.pickPeople,
          selectedPeerIds: selectedPeerIds,
          scopeLabel: scopeLabel,
        );
      case 'people_nearby':
        final radiusM = (json['radius_m'] as num?)?.toInt();
        if (radiusM == null) {
          throw const FormatException('invalid_nearby_audience');
        }
        return PostAudience(
          kind: PostAudienceKind.peopleNearby,
          radiusM: radiusM,
          scopeLabel: scopeLabel,
        );
      default:
        return PostAudience(
          kind: PostAudienceKind.allFriends,
          scopeLabel: scopeLabel,
        );
    }
  }
}

class PostPinUpdateEnvelope {
  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String pinEventId;
  final String postId;
  final String state;
  final String effectiveAt;
  final String pinnedAt;
  final PostPinSnapshot snapshot;

  const PostPinUpdateEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.pinEventId,
    required this.postId,
    required this.state,
    required this.effectiveAt,
    required this.pinnedAt,
    required this.snapshot,
  });

  static PostPinUpdateEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_pin_update') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final pinEventId = payload?['pin_event_id'] as String?;
      final postId = payload?['post_id'] as String?;
      final state = payload?['state'] as String?;
      final effectiveAt = payload?['effective_at'] as String? ?? createdAt;
      final pinnedAt = payload?['pinned_at'] as String?;
      final snapshotJson = payload?['snapshot'] as Map<String, dynamic>?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          pinEventId == null ||
          postId == null ||
          state == null ||
          effectiveAt == null ||
          pinnedAt == null ||
          snapshotJson == null) {
        return null;
      }
      final snapshot = PostPinSnapshot.fromJson(snapshotJson);
      if (snapshot.postId != postId) {
        return null;
      }
      return PostPinUpdateEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        pinEventId: pinEventId,
        postId: postId,
        state: state,
        effectiveAt: effectiveAt,
        pinnedAt: pinnedAt,
        snapshot: snapshot,
      );
    } catch (_) {
      return null;
    }
  }

  static String buildJson({
    required PostPinStateModel pinState,
    required PostModel post,
    required List<PostMediaAttachmentModel> media,
  }) {
    return jsonEncode(<String, Object?>{
      'type': 'post_pin_update',
      'version': '1',
      'event_id': pinState.eventId,
      'created_at': pinState.createdAt,
      'sender_peer_id': pinState.senderPeerId,
      'payload': <String, Object?>{
        'pin_event_id': pinState.pinEventId,
        'post_id': post.id,
        'state': pinState.state,
        'effective_at': pinState.effectiveAt,
        'pinned_at': pinState.pinnedAt,
        'snapshot': PostPinSnapshot(
          postId: post.id,
          authorPeerId: post.authorPeerId,
          authorUsername: post.authorUsername,
          postCreatedAt: post.createdAt,
          audience: post.audience,
          text: post.text,
          mediaKind: media.isEmpty
              ? post.mediaKind
              : PostMediaAttachmentModel.deriveMediaKind(media),
          media: media,
          keepAvailable: true,
          expiresAt: post.expiresAt,
        ).toJson(),
      },
    });
  }
}

class PostPinRemoveEnvelope {
  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String pinEventId;
  final String postId;
  final String removedAt;
  final String reason;

  const PostPinRemoveEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.pinEventId,
    required this.postId,
    required this.removedAt,
    required this.reason,
  });

  static PostPinRemoveEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_pin_remove') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final pinEventId = payload?['pin_event_id'] as String?;
      final postId = payload?['post_id'] as String?;
      final removedAt = payload?['removed_at'] as String?;
      final reason = payload?['reason'] as String?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          pinEventId == null ||
          postId == null ||
          removedAt == null ||
          reason == null) {
        return null;
      }
      return PostPinRemoveEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        pinEventId: pinEventId,
        postId: postId,
        removedAt: removedAt,
        reason: reason,
      );
    } catch (_) {
      return null;
    }
  }

  static String buildJson({required PostPinStateModel pinState}) {
    return jsonEncode(<String, Object?>{
      'type': 'post_pin_remove',
      'version': '1',
      'event_id': pinState.eventId,
      'created_at': pinState.createdAt,
      'sender_peer_id': pinState.senderPeerId,
      'payload': <String, Object?>{
        'pin_event_id': pinState.pinEventId,
        'post_id': pinState.postId,
        'removed_at': pinState.removedAt,
        'reason': pinState.reason,
      },
    });
  }
}
