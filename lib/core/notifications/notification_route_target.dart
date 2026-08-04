import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';

enum NotificationRouteTargetKind {
  conversation,
  contactRequest,
  group,
  intros,
  post,
  postComment,
}

class NotificationRouteTarget {
  static const _introsMessageMarker = '|message:';

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

  const NotificationRouteTarget.conversation(String peerId, {String? messageId})
    : this._(
        kind: NotificationRouteTargetKind.conversation,
        peerId: peerId,
        messageId: messageId,
      );

  const NotificationRouteTarget.contactRequest(String peerId)
    : this._(kind: NotificationRouteTargetKind.contactRequest, peerId: peerId);

  const NotificationRouteTarget.group(String groupId, {String? messageId})
    : this._(
        kind: NotificationRouteTargetKind.group,
        groupId: groupId,
        messageId: messageId,
      );

  /// An anchored Intros target carries the canonical introduction envelope
  /// `messageId` (`<introductionId>::<action>::<senderPeerId>`) so the
  /// notification-open flow can resolve an introducer acceptance to the
  /// originating recipient conversation. Bare `intros` remains the generic
  /// Orbit/Intros route.
  const NotificationRouteTarget.intros({String? messageId})
    : this._(kind: NotificationRouteTargetKind.intros, messageId: messageId);

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
      NotificationRouteTargetKind.intros =>
        messageId == null || messageId!.isEmpty
            ? 'intros'
            : 'intros$_introsMessageMarker${messageId!}',
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
    if (payload.startsWith('intros$_introsMessageMarker')) {
      // 252: anchored Intros payloads mirror the group `|message:` marker.
      // Anchor only a validated canonical introduction envelope ID; anything
      // else fails closed to the generic Intros route (never the conversation
      // catch-all below).
      final messageId = payload
          .substring('intros$_introsMessageMarker'.length)
          .trim();
      return IntroductionPayload.parseEnvelopeMessageId(messageId) == null
          ? const NotificationRouteTarget.intros()
          : NotificationRouteTarget.intros(messageId: messageId);
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
      case 'message_reaction':
        final action = _trimToNull(data['action']?.toString());
        final targetMessageId =
            _trimToNull(data['target_message_id']?.toString()) ??
            _trimToNull(data['targetMessageId']?.toString());
        final peerId =
            _trimToNull(data['sender_id']?.toString()) ??
            _trimToNull(data['from']?.toString());
        if (action != 'add' || targetMessageId == null || peerId == null) {
          return null;
        }
        return NotificationRouteTarget.conversation(
          peerId,
          messageId: targetMessageId,
        );
      case 'group_reaction':
        final action = _trimToNull(data['action']?.toString());
        final targetMessageId =
            _trimToNull(data['target_message_id']?.toString()) ??
            _trimToNull(data['targetMessageId']?.toString());
        final groupId = groupIdFromRemoteMessageData(data);
        final reactorPeerId =
            _trimToNull(data['reactor_peer_id']?.toString()) ??
            _trimToNull(data['sender_id']?.toString()) ??
            _trimToNull(data['from']?.toString());
        if (action != 'add' ||
            targetMessageId == null ||
            groupId == null ||
            reactorPeerId == null) {
          return null;
        }
        return NotificationRouteTarget.group(
          groupId,
          messageId: targetMessageId,
        );
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
        return _groupRouteFromRemoteMessageData(data);
      case 'group_invite':
        // Group invites are reviewed from the shared Intros surface, which
        // already renders pending invites alongside introductions.
        return const NotificationRouteTarget.intros();
      case 'intros':
        // 252: retain the canonical introduction envelope message ID so an
        // introducer acceptance tap can resolve to the recipient thread.
        // Non-canonical (legacy/malformed) IDs stay unanchored.
        final introMessageId = messageIdFromRemoteMessageData(data);
        return IntroductionPayload.parseEnvelopeMessageId(introMessageId) ==
                null
            ? const NotificationRouteTarget.intros()
            : NotificationRouteTarget.intros(messageId: introMessageId);
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

    if (isGroupMessageLikeRemoteData(data)) {
      return _groupRouteFromRemoteMessageData(data);
    }

    return fromPayload(
      data['payload']?.toString() ?? data['route']?.toString(),
    );
  }

  static bool isGroupMessageLikeRemoteData(Map<String, dynamic> data) {
    final type = _trimToNull(data['type']?.toString());
    if (type == 'group_invite') {
      return false;
    }

    final payloadType = _trimToNull(data['payloadType']?.toString());
    final kind = _trimToNull(data['kind']?.toString());
    return type == 'group_message' ||
        type == 'group_reaction' ||
        payloadType == 'group_message' ||
        payloadType == 'group_reaction' ||
        kind == 'group_message' ||
        kind == 'group_offline_replay';
  }

  static String? groupIdFromRemoteMessageData(Map<String, dynamic> data) {
    return _trimToNull(data['groupId']?.toString()) ??
        _trimToNull(data['group_id']?.toString()) ??
        _trimToNull(data['gid']?.toString()) ??
        _trimToNull(data['conversation_id']?.toString());
  }

  static String? messageIdFromRemoteMessageData(Map<String, dynamic> data) {
    return _trimToNull(data['message_id']?.toString()) ??
        _trimToNull(data['messageId']?.toString()) ??
        _trimToNull(data['id']?.toString()) ??
        _trimToNull(data['msgId']?.toString());
  }

  static Map<String, Object?> missingGroupIdTelemetryDetails(
    Map<String, dynamic> data,
  ) {
    return {
      'type': _trimToNull(data['type']?.toString()),
      'payloadType': _trimToNull(data['payloadType']?.toString()),
      'kind': _trimToNull(data['kind']?.toString()),
      'dataKeys': data.keys.toList(growable: false),
      'hasGroupId': _trimToNull(data['groupId']?.toString()) != null,
      'hasGroup_id': _trimToNull(data['group_id']?.toString()) != null,
      'hasGid': _trimToNull(data['gid']?.toString()) != null,
      'hasConversationId':
          _trimToNull(data['conversation_id']?.toString()) != null,
    };
  }

  static NotificationRouteTarget? _groupRouteFromRemoteMessageData(
    Map<String, dynamic> data,
  ) {
    final groupId = groupIdFromRemoteMessageData(data);
    if (groupId == null) {
      return null;
    }
    return NotificationRouteTarget.group(
      groupId,
      messageId: messageIdFromRemoteMessageData(data),
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
