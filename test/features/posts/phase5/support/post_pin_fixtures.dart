import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

ContactModel postPinContact(
  String peerId,
  String username, {
  bool blocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
  );
}

PostModel postPinBasePost({
  String postId = 'post-1',
  String authorPeerId = 'peer-bob',
  String authorUsername = 'Bob',
  String text = 'Original offer text.',
  String createdAt = '2026-03-15T10:15:30.000Z',
  String expiresAt = '2026-03-18T10:15:30.000Z',
  bool keepAvailable = false,
}) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: authorPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: createdAt,
    visibleAt: createdAt,
    expiresAt: expiresAt,
    keepAvailable: keepAvailable,
    isIncoming: true,
    deliveryStatus: 'delivered',
  );
}

ChatMessage postCreateMessage({
  String transportSender = 'peer-bob',
  PostModel? post,
}) {
  final renderablePost = post ?? postPinBasePost(authorPeerId: transportSender);
  final envelope = PostCreateEnvelope.fromPost(renderablePost);
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: envelope.toJson(recipientPeerIds: const <String>['peer-self']),
    timestamp: renderablePost.createdAt,
    isIncoming: true,
  );
}

ChatMessage postPinUpdateMessage({
  String transportSender = 'peer-bob',
  String eventId = 'evt-pin-1',
  String pinEventId = 'pin-evt-1',
  String postId = 'post-1',
  String createdAt = '2026-03-15T11:20:00.000Z',
  String? effectiveAt,
  String pinnedAt = '2026-03-15T11:20:00.000Z',
  String authorPeerId = 'peer-bob',
  String authorUsername = 'Bob',
  String text = 'Updated offer text.',
  String expiresAt = '2026-03-18T10:15:30.000Z',
}) {
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_pin_update',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': transportSender,
      'payload': <String, Object?>{
        'pin_event_id': pinEventId,
        'post_id': postId,
        'state': 'active',
        'effective_at': effectiveAt ?? createdAt,
        'pinned_at': pinnedAt,
        'snapshot': <String, Object?>{
          'post_id': postId,
          'author_peer_id': authorPeerId,
          'author_username': authorUsername,
          'post_created_at': '2026-03-15T10:15:30.000Z',
          'audience': <String, Object?>{
            'kind': 'all_friends',
            'radius_m': null,
            'scope_label': null,
          },
          'text': text,
          'media_kind': 'none',
          'media': const <Object?>[],
          'keep_available': true,
          'expires_at': expiresAt,
        },
      },
    }),
    timestamp: createdAt,
    isIncoming: true,
  );
}

ChatMessage postPinRemoveMessage({
  String transportSender = 'peer-bob',
  String eventId = 'evt-pin-remove-1',
  String pinEventId = 'pin-remove-1',
  String postId = 'post-1',
  String createdAt = '2026-03-15T11:25:00.000Z',
  String removedAt = '2026-03-15T11:25:00.000Z',
}) {
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_pin_remove',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': transportSender,
      'payload': <String, Object?>{
        'pin_event_id': pinEventId,
        'post_id': postId,
        'removed_at': removedAt,
        'reason': 'removed',
      },
    }),
    timestamp: createdAt,
    isIncoming: true,
  );
}
