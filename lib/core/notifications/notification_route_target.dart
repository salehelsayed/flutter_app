enum NotificationRouteTargetKind {
  conversation,
  contactRequest,
  group,
  intros,
  post,
  postComment,
}

class NotificationRouteTarget {
  final NotificationRouteTargetKind kind;
  final String? peerId;
  final String? groupId;
  final String? messageId;
  final String? postId;
  final String? commentId;

  const NotificationRouteTarget._({
    required this.kind,
    this.peerId,
    this.groupId,
    this.messageId,
    this.postId,
    this.commentId,
  });

  const NotificationRouteTarget.conversation(String peerId)
    : this._(kind: NotificationRouteTargetKind.conversation, peerId: peerId);

  const NotificationRouteTarget.contactRequest(String peerId)
    : this._(kind: NotificationRouteTargetKind.contactRequest, peerId: peerId);

  const NotificationRouteTarget.group(String groupId, {String? messageId})
    : this._(
        kind: NotificationRouteTargetKind.group,
        groupId: groupId,
        messageId: messageId,
      );

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
      NotificationRouteTargetKind.contactRequest =>
        'contact_request:${peerId ?? ''}',
      NotificationRouteTargetKind.group =>
        messageId == null || messageId!.isEmpty
        ? 'group:${groupId ?? ''}'
        : 'group:${groupId ?? ''}|message:${messageId!}',
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
    if (payload.startsWith('contact_request:')) {
      final peerId = payload.substring('contact_request:'.length).trim();
      return peerId.isEmpty
          ? null
          : NotificationRouteTarget.contactRequest(peerId);
    }
    if (payload.startsWith('group:')) {
      final remainder = payload.substring('group:'.length).trim();
      if (remainder.isEmpty) {
        return null;
      }

      const messageMarker = '|message:';
      final markerIndex = remainder.indexOf(messageMarker);
      if (markerIndex < 0) {
        return NotificationRouteTarget.group(remainder);
      }

      final groupId = remainder.substring(0, markerIndex).trim();
      final messageId = remainder
          .substring(markerIndex + messageMarker.length)
          .trim();
      if (groupId.isEmpty || messageId.isEmpty) {
        return null;
      }
      return NotificationRouteTarget.group(groupId, messageId: messageId);
    }
    if (payload.startsWith('post_comment:')) {
      final remainder = payload.substring('post_comment:'.length).trim();
      final segments = remainder.split(':');
      if (segments.length < 2) {
        return null;
      }
      final postId = segments.first.trim();
      final commentId = segments.sublist(1).join(':').trim();
      if (postId.isEmpty || commentId.isEmpty) {
        return null;
      }
      return NotificationRouteTarget.postComment(
        postId: postId,
        commentId: commentId,
      );
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
        // The relay sends "sender_id"; older relay versions sent "from".
        final peerId =
            _trimToNull(data['sender_id']?.toString()) ??
            _trimToNull(data['from']?.toString());
        return peerId == null
            ? null
            : NotificationRouteTarget.conversation(peerId);
      case 'contact_request':
        final peerId =
            _trimToNull(data['sender_id']?.toString()) ??
            _trimToNull(data['peer_id']?.toString()) ??
            _trimToNull(data['peerId']?.toString()) ??
            _trimToNull(data['from']?.toString()) ??
            _trimToNull(data['ns']?.toString());
        return peerId == null
            ? null
            : NotificationRouteTarget.contactRequest(peerId);
      case 'group_message':
        final groupId = _trimToNull(data['groupId']?.toString());
        if (groupId == null) {
          return null;
        }
        final messageId =
            _trimToNull(data['message_id']?.toString()) ??
            _trimToNull(data['messageId']?.toString()) ??
            _trimToNull(data['id']?.toString()) ??
            _trimToNull(data['msgId']?.toString());
        return NotificationRouteTarget.group(groupId, messageId: messageId);
      case 'intros':
        return const NotificationRouteTarget.intros();
      case 'post_create':
        final postId = _trimToNull(
          data['postId']?.toString() ?? data['post_id']?.toString(),
        );
        return postId == null ? null : NotificationRouteTarget.post(postId);
      case 'post_comment':
        final postId = _trimToNull(
          data['postId']?.toString() ?? data['post_id']?.toString(),
        );
        final commentId = _trimToNull(
          data['commentId']?.toString() ?? data['comment_id']?.toString(),
        );
        if (postId == null || commentId == null) {
          return null;
        }
        return NotificationRouteTarget.postComment(
          postId: postId,
          commentId: commentId,
        );
      case 'post_reaction':
      case 'post_comment_reaction':
        final postId = _trimToNull(
          data['postId']?.toString() ?? data['post_id']?.toString(),
        );
        return postId == null ? null : NotificationRouteTarget.post(postId);
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
