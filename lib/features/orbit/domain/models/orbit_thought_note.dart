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
  final bool isRead;
  final DateTime expiresAt;

  const OrbitThoughtNote({
    required this.postId,
    required this.text,
    this.media,
    required this.isRead,
    required this.expiresAt,
  });

  factory OrbitThoughtNote.fromPost(PostModel post) => OrbitThoughtNote(
    postId: post.id,
    text: post.text,
    media: switch (post.mediaKind) {
      'image' || 'image_carousel' => MediaPreviewDescriptor(
        type: 'image',
        count: post.media.isEmpty ? 1 : post.media.length,
      ),
      'video' => const MediaPreviewDescriptor(type: 'video', count: 1),
      'voice' => const MediaPreviewDescriptor(type: 'audio', count: 1),
      _ => null,
    },
    isRead: post.isRead || !post.isIncoming,
    expiresAt: DateTime.parse(post.expiresAt),
  );
}
