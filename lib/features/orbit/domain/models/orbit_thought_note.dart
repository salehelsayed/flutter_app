import 'dart:math' as math;

import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

/// The newest eligible live thought for one Orbit author: a friend, or the user.
///
/// The host owns author eligibility and read state; the surface additionally
/// enforces [expiresAt] so a delayed cleanup sweep cannot leave a stale note.
/// An outgoing thought is the user's own and is never unseen.
class OrbitThoughtNote {
  final String postId;
  final String text;
  final MediaPreviewDescriptor? media;
  final bool hasUnsupportedMedia;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime expiresAt;

  const OrbitThoughtNote({
    required this.postId,
    required this.text,
    this.media,
    this.hasUnsupportedMedia = false,
    required this.isRead,
    this.createdAt,
    required this.expiresAt,
  });

  factory OrbitThoughtNote.fromPost(PostModel post) => OrbitThoughtNote(
    postId: post.id,
    text: post.hasUnsupportedMedia ? '' : post.text,
    hasUnsupportedMedia: post.hasUnsupportedMedia,
    media: switch (post.mediaKind) {
      'image' || 'image_carousel' || 'image_voice' => MediaPreviewDescriptor(
        type: 'image',
        count: math.max(
          1,
          post.media.where((item) => item.kind != 'voice').length,
        ),
      ),
      'video' => const MediaPreviewDescriptor(type: 'video', count: 1),
      'voice' => const MediaPreviewDescriptor(type: 'audio', count: 1),
      _ => null,
    },
    isRead: post.isRead || !post.isIncoming,
    createdAt: DateTime.tryParse(post.createdAt),
    expiresAt: DateTime.parse(post.expiresAt),
  );
}
