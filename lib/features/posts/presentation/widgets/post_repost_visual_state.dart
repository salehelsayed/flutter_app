import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class PostRepostVisualState {
  final int? count;
  final bool isActive;

  const PostRepostVisualState._({required this.count, required this.isActive});

  const PostRepostVisualState.none() : this._(count: null, isActive: false);

  bool get hasCount => count != null;
  bool get isPassiveReceiver => hasCount && !isActive;
}

PostRepostVisualState resolvePostRepostVisualState(
  PostModel post, {
  String? viewerPeerId,
}) {
  final isAuthorView =
      viewerPeerId != null && post.authorPeerId == viewerPeerId;
  if (isAuthorView && post.totalSharedToCount > 0) {
    return PostRepostVisualState._(
      count: post.totalSharedToCount,
      isActive: true,
    );
  }

  if (post.viewerHasPassed && post.viewerSharedToCount > 0) {
    return PostRepostVisualState._(
      count: post.viewerSharedToCount,
      isActive: true,
    );
  }

  final isPassedAlongReceiver =
      post.passedByUsername != null && post.totalSharedToCount > 0;
  if (isPassedAlongReceiver) {
    return PostRepostVisualState._(
      count: post.totalSharedToCount,
      isActive: false,
    );
  }

  return const PostRepostVisualState.none();
}
