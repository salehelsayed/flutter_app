enum NotificationRouteTargetKind {
  conversation,
  group,
  intros,
  post,
  postComment,
}

class NotificationRouteTarget {
  final NotificationRouteTargetKind kind;
  final String? peerId;
  final String? groupId;
  final String? postId;
  final String? commentId;

  const NotificationRouteTarget._({
    required this.kind,
    this.peerId,
    this.groupId,
    this.postId,
    this.commentId,
  });

  const NotificationRouteTarget.conversation(String peerId)
    : this._(kind: NotificationRouteTargetKind.conversation, peerId: peerId);

  const NotificationRouteTarget.group(String groupId)
    : this._(kind: NotificationRouteTargetKind.group, groupId: groupId);

  const NotificationRouteTarget.intros()
    : this._(kind: NotificationRouteTargetKind.intros);

  const NotificationRouteTarget.post(String postId)
    : this._(kind: NotificationRouteTargetKind.post, postId: postId);

  const NotificationRouteTarget.postComment({
    required String postId,
    required String commentId,
  }) : this._(
         kind: NotificationRouteTargetKind.postComment,
         postId: postId,
         commentId: commentId,
       );

  String toPayload() {
    return switch (kind) {
      NotificationRouteTargetKind.conversation => peerId ?? '',
      NotificationRouteTargetKind.group => 'group:${groupId ?? ''}',
      NotificationRouteTargetKind.intros => 'intros',
      NotificationRouteTargetKind.post => 'post:${postId ?? ''}',
      NotificationRouteTargetKind.postComment =>
        'post_comment:${postId ?? ''}:${commentId ?? ''}',
    };
  }

  static NotificationRouteTarget? fromPayload(String? rawPayload) {
    final payload = rawPayload?.trim();
    if (payload == null || payload.isEmpty) {
      return null;
    }
    if (payload == 'intros') {
      return const NotificationRouteTarget.intros();
    }
    if (payload.startsWith('group:')) {
      final groupId = payload.substring('group:'.length).trim();
      return groupId.isEmpty ? null : NotificationRouteTarget.group(groupId);
    }
    if (payload.startsWith('post_comment:')) {
      return null;
    }
    if (payload.startsWith('post:')) {
      final postId = payload.substring('post:'.length).trim();
      return postId.isEmpty ? null : NotificationRouteTarget.post(postId);
    }
    return NotificationRouteTarget.conversation(payload);
  }

  static NotificationRouteTarget? fromRemoteMessageData(
    Map<String, dynamic> data,
  ) {
    final type = _trimToNull(data['type']?.toString());
    switch (type) {
      case 'new_message':
        final peerId = _trimToNull(data['from']?.toString());
        return peerId == null
            ? null
            : NotificationRouteTarget.conversation(peerId);
      case 'group_message':
        final groupId = _trimToNull(data['groupId']?.toString());
        return groupId == null ? null : NotificationRouteTarget.group(groupId);
      case 'intros':
        return const NotificationRouteTarget.intros();
      case 'post_create':
        final postId = _trimToNull(
          data['postId']?.toString() ?? data['post_id']?.toString(),
        );
        return postId == null ? null : NotificationRouteTarget.post(postId);
      case 'post_comment':
        return null;
    }

    return fromPayload(
      data['payload']?.toString() ?? data['route']?.toString(),
    );
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
