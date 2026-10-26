import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/friend_thought_card_registry.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/recording_fake_bridge.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool archived = false,
  bool blocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isArchived: archived,
    isBlocked: blocked,
  );
}

ChatMessage _message(
  String senderPeerId,
  String authorUsername, {
  String? postId,
  String? text,
  String mediaKind = 'none',
  String? confirmNonce,
  DateTime? created,
}) {
  final id = postId ?? 'post-$senderPeerId';
  final createdAt = (created ?? DateTime.now()).toUtc().toIso8601String();
  final expiresAt = DateTime.now()
      .toUtc()
      .add(const Duration(days: 3))
      .toIso8601String();
  final envelope = PostCreateEnvelope.fromPost(
    PostModel(
      id: id,
      eventId: 'evt-$id',
      senderPeerId: senderPeerId,
      authorPeerId: senderPeerId,
      authorUsername: authorUsername,
      text: text ?? 'A post from $authorUsername',
      audience: const PostAudience(kind: PostAudienceKind.allFriends),
      createdAt: createdAt,
      visibleAt: createdAt,
      expiresAt: expiresAt,
      mediaKind: mediaKind,
      media: [
        if (mediaKind != 'none')
          PostMediaAttachmentModel(
            mediaId: 'media-$id',
            postId: id,
            blobId: 'blob-$id',
            kind: mediaKind,
            mime: mediaKind == 'voice' ? 'audio/aac' : 'image/jpeg',
            sizeBytes: 10,
            createdAt: createdAt,
          ),
      ],
    ),
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: envelope.toJson(),
    timestamp: envelope.createdAt,
    isIncoming: true,
    confirmNonce: confirmNonce,
  );
}

ChatMessage _retract(String senderPeerId, String postId) {
  final now = DateTime.now().toUtc();
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: PostRetractEnvelope(
      eventId: 'evt-retract-$postId',
      createdAt: now,
      postId: postId,
      postCreatedAt: now.subtract(const Duration(minutes: 1)),
    ).toJson(),
    timestamp: now.toIso8601String(),
    isIncoming: true,
  );
}

/// A store whose write fails the way a locked or full database does.
class _FailingPostRepository extends InMemoryPostRepository {
  @override
  Future<void> savePost(PostModel post) async {
    throw StateError('database is locked');
  }
}

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
  late StreamController<ChatMessage> controller;
  late StreamController<ChatMessage> retracts;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late _CancellingNotificationService notifications;
  late RecentRemoteNotificationGate remoteGate;
  late RecordingFakeBridge bridge;
  late Directory cardsDir;
  late PostListener listener;
  var foreground = false;

  setUp(() {
    foreground = false;
    controller = StreamController<ChatMessage>.broadcast();
    retracts = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    notifications = _CancellingNotificationService();
    remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/post-listener-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    bridge = RecordingFakeBridge()
      ..whenCommand('message:confirm', (_) => '{"ok":true}');
    cardsDir = Directory.systemTemp.createTempSync(
      'post-listener-thought-cards-',
    );
    listener = PostListener(
      postCreateStream: controller.stream,
      postRetractStream: retracts.stream,
      postRepo: posts,
      contactRepo: contacts,
      bridge: bridge,
      notificationService: notifications,
      isAppForegroundActive: () async => foreground,
      remoteNotificationGate: remoteGate,
      friendThoughtCards: FriendThoughtCardRegistry(directory: cardsDir),
    )..start();
  });

  tearDown(() async {
    listener.dispose();
    posts.dispose();
    await controller.close();
    await retracts.close();
    await remoteGate.clear();
    if (cardsDir.existsSync()) cardsDir.deleteSync(recursive: true);
  });

  test('skips the card the background push already announced', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await remoteGate.markAnnouncement(
      payload: 'post:post-peer-bob',
      messageId: 'evt-post-peer-bob',
    );

    controller.add(_message('peer-bob', 'Bob'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownThoughts, isEmpty);
    expect(await posts.loadFeed(), hasLength(1));

    controller.add(_message('peer-bob', 'Bob', postId: 'bob-2'));
    // The card registry's file lock and the ack confirm make this path slower
    // than a fixed short delay; wait for the card instead.
    for (var i = 0; i < 40 && notifications.shownThoughts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(notifications.shownThoughts.map((n) => n.payload), ['post:bob-2']);
  });

  test(
    'titles the card with the contact name, never the claimed author',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      controller.add(
        _message('peer-bob', 'ATTACKER CLAIMED NAME', text: 'x' * 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final shown = notifications.shownThoughts.single;
      expect(shown.title, 'Bob shared a thought');
      expect(shown.body, 'x' * 140);
    },
  );

  test('shows post notifications for active direct contacts', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(_message('peer-bob', 'Bob'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownGeneric, isEmpty);
    final shown = notifications.shownThoughts.single;
    expect(shown.title, 'Bob shared a thought');
    expect(shown.body, 'A post from Bob');
    expect(shown.payload, 'post:post-peer-bob');
    expect((await posts.loadFeed()), hasLength(1));
  });

  test('the card is told when its thought expires', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final created = DateTime.now().toUtc().subtract(const Duration(hours: 1));

    controller.add(_message('peer-bob', 'Bob', created: created));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      notifications.shownThoughts.single.expiresAt,
      ThoughtLifetime.expiresAt(created),
    );
  });

  test('posts no notification while the app is in the foreground', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    foreground = true;
    final emitted = listener.incomingPostStream.first;

    controller.add(_message('peer-bob', 'Bob'));

    expect((await emitted).id, 'post-peer-bob');
    expect(notifications.shownThoughts, isEmpty);
    expect(notifications.shownGeneric, isEmpty);
  });

  test('a newer thought retires only that friend\'s older card', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cat', 'Cat'));

    Future<void> receive(String peerId, String name, String postId) async {
      final emitted = listener.incomingPostStream.first;
      controller.add(_message(peerId, name, postId: postId));
      expect((await emitted).id, postId);
    }

    await receive('peer-cat', 'Cat', 'cat-1');
    await receive('peer-bob', 'Bob', 'bob-1');
    notifications.cancelled.clear();
    foreground = true;
    await receive('peer-bob', 'Bob', 'bob-2');

    expect(notifications.cancelled, ['post:bob-1']);
    expect(notifications.shownThoughts.map((n) => n.payload), [
      'post:cat-1',
      'post:bob-1',
    ]);
  });

  test(
    'retires the card the background push showed for the same friend',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      // The headless isolate showed bob-0 while the app was closed. Its post
      // never reached the feed, so only the shared registry knows that card.
      await FriendThoughtCardRegistry(
        directory: cardsDir,
      ).claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-0');

      final emitted = listener.incomingPostStream.first;
      controller.add(_message('peer-bob', 'Bob', postId: 'bob-1'));
      expect((await emitted).id, 'bob-1');

      expect(notifications.cancelled, ['post:bob-0']);
      expect(notifications.shownThoughts.map((n) => n.payload), ['post:bob-1']);
    },
  );

  test(
    'draining thoughts the push already announced keeps the newest card',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final background = FriendThoughtCardRegistry(directory: cardsDir);
      for (final postId in ['bob-1', 'bob-2']) {
        await background.claim(
          senderPeerId: 'peer-bob',
          cardKey: 'post:$postId',
        );
        await remoteGate.markAnnouncement(
          payload: 'post:$postId',
          messageId: 'evt-$postId',
        );
      }

      for (final postId in ['bob-1', 'bob-2']) {
        final emitted = listener.incomingPostStream.first;
        controller.add(_message('peer-bob', 'Bob', postId: postId));
        expect((await emitted).id, postId);
      }

      expect(notifications.cancelled, isEmpty);
      expect(notifications.shownThoughts, isEmpty);
      // One live thought per friend: the newer one replaced the older one.
      expect((await posts.loadFeed()).map((p) => p.id), ['bob-2']);
    },
  );

  test(
    'draining announced thoughts nobody claimed retires the older banner',
    () async {
      // iOS: the notification extension showed both banners and marked the
      // gate, but it never touches the registry.
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      for (final postId in ['bob-1', 'bob-2']) {
        await remoteGate.markAnnouncement(
          payload: 'post:$postId',
          messageId: 'evt-$postId',
        );
      }

      for (final postId in ['bob-1', 'bob-2']) {
        final emitted = listener.incomingPostStream.first;
        controller.add(_message('peer-bob', 'Bob', postId: postId));
        expect((await emitted).id, postId);
      }

      expect(notifications.cancelled, ['post:bob-1']);
      expect(notifications.shownThoughts, isEmpty);
    },
  );

  test(
    'a thought behind the friend\'s newer card gets no card of its own',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final background = FriendThoughtCardRegistry(directory: cardsDir);
      await background.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1');
      await background.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2');

      for (final postId in ['bob-1', 'bob-2']) {
        final emitted = listener.incomingPostStream.first;
        controller.add(_message('peer-bob', 'Bob', postId: postId));
        expect((await emitted).id, postId);
      }

      expect(notifications.cancelled, isEmpty);
      expect(notifications.shownThoughts.map((n) => n.payload), ['post:bob-2']);
    },
  );

  test('a media-only thought names its media in the body', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    Future<void> cardsShown(int count) async {
      for (
        var i = 0;
        i < 300 && notifications.shownThoughts.length < count;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    controller.add(
      _message('peer-bob', 'Bob', postId: 'v', text: '', mediaKind: 'voice'),
    );
    await cardsShown(1);
    controller.add(
      _message('peer-bob', 'Bob', postId: 'p', text: '', mediaKind: 'image'),
    );
    await cardsShown(2);

    expect(notifications.shownThoughts.map((n) => n.body), [
      'Voice message',
      'Photo',
    ]);
  });

  test(
    'shows the card once the thought is stored, before its media downloads',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final download = Completer<PostMediaAttachmentModel>();
      PostMediaAttachmentModel? requested;
      final slow = PostListener(
        postCreateStream: controller.stream,
        postRepo: posts,
        contactRepo: contacts,
        notificationService: notifications,
        isAppForegroundActive: () async => false,
        hydratePostMediaFn: ({required attachment, required postId}) {
          requested = attachment;
          return download.future;
        },
      );
      listener.dispose();
      slow.start();
      addTearDown(slow.dispose);
      final emitted = slow.incomingPostStream.first;

      controller.add(
        _message(
          'peer-bob',
          'Bob',
          postId: 'photo',
          text: '',
          mediaKind: 'image',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(download.isCompleted, isFalse);
      expect(notifications.shownThoughts.map((n) => (n.payload, n.body)), [
        ('post:photo', 'Photo'),
      ]);

      download.complete(requested!.copyWith(downloadStatus: 'done'));
      expect((await emitted).media.single.downloadStatus, 'done');
      expect(notifications.shownThoughts, hasLength(1));
    },
  );

  test(
    'a thought that arrives expired takes the card its push showed with it',
    () async {
      contacts.addTestContact(_contact('peer-old', 'Old'));

      controller.add(
        _message(
          'peer-old',
          'Old',
          postId: 'stale',
          created: DateTime.now().subtract(const Duration(hours: 25)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.loadFeed(), isEmpty);
      expect(notifications.shownThoughts, isEmpty);
      expect(notifications.cancelled, ['post:stale']);
    },
  );

  test(
    'a retraction that outruns its thought keeps the deleted thought out',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      retracts.add(_retract('peer-bob', 'bob-gone'));
      await pumpEventQueue();
      controller.add(
        _message(
          'peer-bob',
          'Bob',
          postId: 'bob-gone',
          confirmNonce: 'nonce-gone',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.getPost('bob-gone'), isNull);
      expect(notifications.shownThoughts, isEmpty);
      expect(notifications.cancelled, ['post:bob-gone']);
      expect(bridge.payloadsFor('message:confirm'), [
        {'nonce': 'nonce-gone', 'ok': true},
      ]);
    },
  );

  test(
    "an early retraction from anyone but the author changes nothing",
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      retracts.add(_retract('peer-mallory', 'bob-1'));
      await pumpEventQueue();
      controller.add(_message('peer-bob', 'Bob', postId: 'bob-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await posts.getPost('bob-1'))?.id, 'bob-1');
      expect(notifications.shownThoughts.map((n) => n.payload), ['post:bob-1']);
    },
  );

  test(
    'suppresses notifications for archived senders but still persists',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob', archived: true));

      controller.add(_message('peer-bob', 'Bob'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifications.shownThoughts, isEmpty);
      expect((await posts.loadFeed()), hasLength(1));
    },
  );

  group('deferred direct ack', () {
    test('releases the ack once the thought is stored', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      controller.add(_message('peer-bob', 'Bob', confirmNonce: 'nonce-stored'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.loadFeed(), hasLength(1));
      expect(bridge.payloadsFor('message:confirm'), [
        {'nonce': 'nonce-stored', 'ok': true},
      ]);
    });

    test(
      'releases the ack once the media rows are saved, before the download',
      () async {
        contacts.addTestContact(_contact('peer-bob', 'Bob'));
        final download = Completer<PostMediaAttachmentModel>();
        final slow = PostListener(
          postCreateStream: controller.stream,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          hydratePostMediaFn: ({required attachment, required postId}) =>
              download.future,
        );
        listener.dispose();
        slow.start();
        addTearDown(slow.dispose);

        controller.add(
          _message(
            'peer-bob',
            'Bob',
            postId: 'photo',
            mediaKind: 'image',
            confirmNonce: 'nonce-media',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(download.isCompleted, isFalse);
        expect(
          (await posts.loadPostMediaAttachments(
            'photo',
          )).map((m) => m.downloadStatus),
          ['pending'],
        );
        expect(bridge.payloadsFor('message:confirm'), [
          {'nonce': 'nonce-media', 'ok': true},
        ]);

        download.completeError(StateError('offline'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bridge.payloadsFor('message:confirm'), hasLength(1));
      },
    );

    test('releases the ack for a duplicate thought', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      controller.add(_message('peer-bob', 'Bob'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.add(_message('peer-bob', 'Bob', confirmNonce: 'nonce-dup'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.loadFeed(), hasLength(1));
      expect(bridge.payloadsFor('message:confirm'), [
        {'nonce': 'nonce-dup', 'ok': true},
      ]);
    });

    test('releases the ack for thoughts rejected for good', () async {
      contacts.addTestContact(_contact('peer-eve', 'Eve', blocked: true));
      contacts.addTestContact(_contact('peer-old', 'Old'));

      controller.add(
        _message('peer-stranger', 'Stranger', confirmNonce: 'nonce-unknown'),
      );
      controller.add(
        _message('peer-eve', 'Eve', confirmNonce: 'nonce-blocked'),
      );
      controller.add(
        _message(
          'peer-old',
          'Old',
          confirmNonce: 'nonce-expired',
          created: DateTime.now().subtract(const Duration(hours: 25)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.loadFeed(), isEmpty);
      expect(bridge.payloadsFor('message:confirm'), [
        {'nonce': 'nonce-unknown', 'ok': true},
        {'nonce': 'nonce-blocked', 'ok': true},
        {'nonce': 'nonce-expired', 'ok': true},
      ]);
    });

    test('withholds the ack when the store fails', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final failingPosts = _FailingPostRepository();
      final failing = PostListener(
        postCreateStream: controller.stream,
        postRepo: failingPosts,
        contactRepo: contacts,
        bridge: bridge,
      )..start();
      listener.stop();
      addTearDown(() {
        failing.dispose();
        failingPosts.dispose();
      });

      controller.add(_message('peer-bob', 'Bob', confirmNonce: 'nonce-fail'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await failingPosts.loadFeed(), isEmpty);
      expect(bridge.payloadsFor('message:confirm'), [
        {'nonce': 'nonce-fail', 'ok': false},
      ]);
    });

    test('sends no confirm for a thought without a nonce', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      controller.add(_message('peer-bob', 'Bob'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await posts.loadFeed(), hasLength(1));
      expect(bridge.calledCommands, isEmpty);
    });
  });
}
