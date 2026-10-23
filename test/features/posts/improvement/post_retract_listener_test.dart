import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

class _CancellingNotificationService extends FakeNotificationService
    implements ConversationNotificationCancellation {
  final cancelled = <String>[];

  @override
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    cancelled.add(conversationKey);
  }
}

void main() {
  final createdAt = DateTime.utc(2026, 10, 23, 9);
  late StreamController<ChatMessage> retracts;
  late InMemoryPostRepository posts;
  late FakeMediaFileManager media;
  late _CancellingNotificationService notifications;
  late PostListener listener;
  late List<String> flowEvents;

  setUp(() async {
    retracts = StreamController<ChatMessage>.broadcast();
    posts = InMemoryPostRepository();
    media = FakeMediaFileManager();
    notifications = _CancellingNotificationService();
    flowEvents = <String>[];
    debugSetFlowEventSink((payload) {
      flowEvents.add(payload['event'] as String);
    });
    listener = PostListener(
      postCreateStream: const Stream<ChatMessage>.empty(),
      postRetractStream: retracts.stream,
      postRepo: posts,
      contactRepo: InMemoryContactRepository(),
      mediaFileManager: media,
      notificationService: notifications,
    )..start();
    await posts.savePost(
      PostModel(
        id: 'bob-1',
        eventId: 'evt-bob-1',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Hello from Bob',
        audience: PostAudience.allFriends(),
        createdAt: createdAt.toIso8601String(),
        visibleAt: createdAt.toIso8601String(),
        expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
        isIncoming: true,
        deliveryStatus: 'delivered',
      ),
    );
  });

  tearDown(() async {
    debugSetFlowEventSink(null);
    listener.dispose();
    await retracts.close();
    posts.dispose();
  });

  ChatMessage retractFrom(String sender, {String postId = 'bob-1'}) {
    return ChatMessage(
      from: sender,
      to: 'me',
      content: jsonEncode(<String, Object?>{
        'type': 'post_retract',
        'version': '1',
        'event_id': 'evt-retract-1',
        'created_at': '2026-10-23T11:00:00.000Z',
        'payload': <String, Object?>{
          'post_id': postId,
          'post_created_at': createdAt.toIso8601String(),
        },
      }),
      timestamp: '2026-10-23T11:00:00.000Z',
      isIncoming: true,
    );
  }

  Future<void> deliver(ChatMessage message) async {
    retracts.add(message);
    await pumpEventQueue();
  }

  test("the author's retraction deletes the copy, its media and its card", () async {
    await deliver(retractFrom('peer-bob'));

    expect(await posts.getPost('bob-1'), isNull);
    expect(media.deletedPostIds, ['bob-1']);
    expect(notifications.cancelled, ['post:bob-1']);
  });

  test('a retraction from anyone but the author is dropped', () async {
    await deliver(retractFrom('peer-mallory'));

    expect(await posts.getPost('bob-1'), isNotNull);
    expect(media.deletedPostIds, isEmpty);
    expect(notifications.cancelled, isEmpty);
    expect(flowEvents, contains('POST_RETRACT_DROP'));
  });

  test('a retraction for an unknown thought stores nothing', () async {
    await deliver(retractFrom('peer-bob', postId: 'never-seen'));

    expect(await posts.getPost('bob-1'), isNotNull);
    expect(media.deletedPostIds, isEmpty);
    expect(notifications.cancelled, isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(flowEvents, contains('POST_RETRACT_DROP'));
  });
}
