// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/posts/application/load_orbit_thoughts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_thought_activity_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/posts/presentation/screens/thought_card_screen.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/bidi_layout_checks.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

void main() {
  final initialNow = DateTime.utc(2026, 10, 21, 12);
  late DateTime now;
  late _CardPostRepository posts;
  late FakeContactRepository contacts;
  late StreamController<void> eligibility;
  late GlobalKey<NavigatorState> navigator;
  late _RecordingNavigatorObserver navigationObserver;
  late JustAudioPlatform originalAudioPlatform;

  setUp(() {
    now = initialNow;
    posts = _CardPostRepository();
    contacts = FakeContactRepository()..seed([_alice]);
    eligibility = StreamController<void>.broadcast();
    navigator = GlobalKey<NavigatorState>();
    navigationObserver = _RecordingNavigatorObserver();
    originalAudioPlatform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
  });

  tearDown(() async {
    await eligibility.close();
    posts.dispose();
    JustAudioPlatform.instance = originalAudioPlatform;
  });

  Future<PostModel?> loadCurrentFriendThought(PostModel initialPost) async {
    final thoughts = await LoadOrbitThoughtsUseCase(
      postRepo: posts,
      contactRepo: contacts,
      nowProvider: () => now,
    ).execute(localPeerId: 'local-peer');
    return thoughts
        .where((post) => post.authorPeerId == initialPost.authorPeerId)
        .firstOrNull;
  }

  Future<void> openCard(
    WidgetTester tester,
    PostModel initialPost, {
    String authorName = 'Alice',
    bool messageable = true,
    void Function(String text, String postId)? onReply,
    Future<ThoughtReplyStatus> Function(String, String, String)? sendReply,
    Stream<ConversationMessage>? replyChanges,
    VoidCallback? onOpenChat,
    Future<void> Function(String)? onShown,
    Future<ThoughtActivity> Function(String)? loadActivity,
    Future<int> Function()? retryPosting,
    Future<void> Function(String postId)? onDelete,
    Future<PostModel?> Function()? loadCurrent,
    Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)?
    download,
    ValueChanged<ThoughtVoiceReply>? onVoiceReply,
    AudioRecorderService? recorder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [navigationObserver],
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('orbit-home')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'thought-card'),
          builder: (_) => ThoughtCardScreen(
            initialPost: initialPost,
            authorName: authorName,
            postRepo: posts,
            loadCurrentThought:
                loadCurrent ?? () => loadCurrentFriendThought(initialPost),
            onReply: !messageable
                ? null
                : sendReply ??
                      (text, postId, _) async {
                        onReply?.call(text, postId);
                        return ThoughtReplyStatus.sent;
                      },
            replyChanges: replyChanges,
            onOpenChat: onOpenChat,
            onShown: onShown,
            loadActivity: loadActivity,
            retryPosting: retryPosting,
            onDelete: onDelete,
            downloadMedia:
                download ??
                (_) async => throw StateError('Unexpected media download'),
            eligibilityChanges: eligibility.stream,
            nowProvider: () => now,
            onVoiceReply: onVoiceReply,
            audioRecorderService: recorder,
            micPermissionGateway: FakeMicPermissionGateway(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  /// The card removes a dropped recording with real file I/O.
  Future<void> waitForDeletion(WidgetTester tester, File file) =>
      tester.runAsync(() async {
        for (var i = 0; i < 50 && file.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pumpMediaFrames(WidgetTester tester) async {
    // These assertions cover downloaded metadata and viewer/retry controls.
    // File-image decoding can retain a loading ticker in a fake-async test;
    // bounded frames flush repository futures without waiting on that ticker.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'shows name, age and text, marks shown thought and exposes no engagement',
    (tester) async {
      final thought = _thought(initialNow);
      await posts.savePost(thought);

      await openCard(tester, thought);
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('2h ago · gone in 22 h'), findsOneWidget);
      expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
      expect(posts.focusedIds, ['thought-1']);
      expect((await posts.getPost('thought-1'))!.isRead, isTrue);
      expect(find.byType(PostCard), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.comment_outlined), findsNothing);
      expect(_replyField, findsOneWidget);
      expect(find.text('Reply to Alice…'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('an own thought card has no reply field and stays unread', (
    tester,
  ) async {
    final mine = _thought(initialNow).copyWith(
      senderPeerId: 'local-peer',
      authorPeerId: 'local-peer',
      authorUsername: 'Me',
      isIncoming: false,
    );
    await posts.savePost(mine);
    final query = LoadOrbitThoughtsUseCase(
      postRepo: posts,
      contactRepo: contacts,
      nowProvider: () => now,
    );

    await openCard(
      tester,
      mine,
      authorName: 'You',
      messageable: false,
      loadCurrent: () => query.executeOwn(localPeerId: 'local-peer'),
    );
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    expect(find.text('2h ago · gone in 22 h'), findsOneWidget);
    expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
    expect(_replyField, findsNothing);
    expect(find.byKey(const ValueKey('thought-react-love')), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(posts.focusedIds, isEmpty);
    expect((await posts.getPost('thought-1'))!.isRead, isFalse);
    expect(find.byKey(const ValueKey('thought-delete')), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'own posting retry stays in place and follows repository progress',
    (tester) async {
      final mine = _thought(initialNow).copyWith(
        senderPeerId: 'local-peer',
        authorPeerId: 'local-peer',
        authorUsername: 'Me',
        isIncoming: false,
        deliveryStatus: 'failed',
      );
      await posts.savePost(mine);
      final retry = Completer<int>();
      var retries = 0;
      await openCard(
        tester,
        mine,
        messageable: false,
        loadCurrent: () => posts.getPost(mine.id),
        retryPosting: () {
          retries++;
          return retry.future;
        },
      );
      expect(find.text('Send failed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('thought-posting-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thought-posting-retry')));
      expect(retries, 1);
      expect(find.byType(ThoughtCardScreen), findsOneWidget);
      await posts.savePost(mine.copyWith(deliveryStatus: 'sent'));
      retry.complete(1);
      await tester.pumpAndSettle();
      expect(find.text('sent'), findsOneWidget);
      expect(find.byKey(const ValueKey('thought-posting-retry')), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'own activity names viewers and groups distinct reaction actors',
    (tester) async {
      final mine = _thought(initialNow).copyWith(
        senderPeerId: 'local-peer',
        authorPeerId: 'local-peer',
        authorUsername: 'Me',
        isIncoming: false,
      );
      await posts.savePost(mine);
      await openCard(
        tester,
        mine,
        messageable: false,
        loadCurrent: () => posts.getPost(mine.id),
        loadActivity: (_) async => (
          viewers: [(peerId: 'sam', name: 'Sam'), (peerId: 'mo', name: 'Mo')],
          reactions: [
            (
              reaction: ThoughtReaction.love,
              participants: [
                (peerId: 'sam', name: 'Sam'),
                (peerId: 'mo', name: 'Mo'),
                (peerId: 'kim', name: 'Kim'),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seen by 2 friends'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('thought-activity-open')));
      await tester.pumpAndSettle();
      expect(find.text('Sam · Mo'), findsOneWidget);
      expect(find.text('Sam and 2 others reacted ❤️'), findsOneWidget);
      expect(find.text('Sam · Mo · Kim'), findsOneWidget);
      expect(posts.focusedIds, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('a photo-only placeholder is not a view before content arrives', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'thought-view-photo-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final photo = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
    final thought = _thought(initialNow).copyWith(text: '', mediaKind: 'image');
    await posts.savePost(thought);
    final media = PostMediaAttachmentModel(
      mediaId: 'view-photo',
      postId: thought.id,
      blobId: 'blob-photo',
      kind: 'image',
      mime: 'image/png',
      sizeBytes: 1,
      createdAt: initialNow.toIso8601String(),
    );
    await posts.savePostMediaAttachment(media);
    final downloaded = Completer<PostMediaAttachmentModel>();
    final views = <String>[];
    await openCard(
      tester,
      thought,
      download: (_) => downloaded.future,
      onShown: (id) async {
        views.add(id);
      },
    );
    await pumpMediaFrames(tester);
    expect(
      find.byKey(const ValueKey('thought-media-placeholder')),
      findsOneWidget,
    );
    expect(views, isEmpty);
    expect(posts.focusedIds, isEmpty);
    await posts.updatePostMediaLocalPath(
      media.mediaId,
      photo.path,
      postId: thought.id,
    );
    downloaded.complete(
      media.copyWith(localPath: photo.path, downloadStatus: 'done'),
    );
    await pumpMediaFrames(tester);
    expect(views, [thought.id]);
    expect(posts.focusedIds, [thought.id]);
    await finish(tester);
  });

  group('own card Delete', () {
    late PostModel mine;
    late LoadOrbitThoughtsUseCase query;
    var deletes = 0;

    setUp(() async {
      deletes = 0;
      mine = _thought(initialNow).copyWith(
        senderPeerId: 'local-peer',
        authorPeerId: 'local-peer',
        authorUsername: 'Me',
        isIncoming: false,
      );
      await posts.savePost(mine);
      query = LoadOrbitThoughtsUseCase(
        postRepo: posts,
        contactRepo: contacts,
        nowProvider: () => now,
      );
    });

    Future<void> openOwnCard(
      WidgetTester tester, {
      required Future<void> Function(String postId) onDelete,
    }) async {
      await openCard(
        tester,
        mine,
        authorName: 'You',
        messageable: false,
        loadCurrent: () => query.executeOwn(localPeerId: 'local-peer'),
        onDelete: onDelete,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('thought-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this thought?'), findsOneWidget);
    }

    testWidgets("a friend's card has no Delete", (tester) async {
      await posts.savePost(_thought(initialNow));
      await openCard(tester, _thought(initialNow));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thought-delete')), findsNothing);
      await finish(tester);
    });

    testWidgets('Cancel keeps the thought and the card', (tester) async {
      await openOwnCard(tester, onDelete: (_) async => deletes++);

      await tester.tap(find.byKey(const ValueKey('thought-delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this thought?'), findsNothing);
      expect(deletes, 0);
      expect(find.byType(ThoughtCardScreen), findsOneWidget);
      expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
      expect(await posts.getPost('thought-1'), isNotNull);
      await finish(tester);
    });

    testWidgets('confirming Delete deletes the thought and closes the card', (
      tester,
    ) async {
      final deletedIds = <String>[];
      await openOwnCard(
        tester,
        onDelete: (postId) async {
          deletedIds.add(postId);
          await posts.deletePostCascade(postId);
        },
      );

      await tester.tap(find.byKey(const ValueKey('thought-delete-confirm')));
      await tester.pumpAndSettle();

      expect(deletedIds, ['thought-1']);
      expect(await posts.getPost('thought-1'), isNull);
      expect(find.byType(ThoughtCardScreen), findsNothing);
      expect(navigationObserver.poppedNames, contains('thought-card'));
      expect(find.text('orbit-home'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a failed delete keeps the card and says so', (tester) async {
      await openOwnCard(
        tester,
        onDelete: (_) async => throw StateError('database closed'),
      );

      await tester.tap(find.byKey(const ValueKey('thought-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(ThoughtCardScreen), findsOneWidget);
      expect(find.text('Couldn’t delete. Try again.'), findsOneWidget);
      expect(await posts.getPost('thought-1'), isNotNull);
      await finish(tester);
    });
  });

  testWidgets('does not mark an unvalidated or blocked thought read', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    posts.feedGate = Completer<void>();

    await openCard(tester, thought);
    expect(posts.focusedIds, isEmpty);
    expect(find.text('Quiet thought', findRichText: true), findsNothing);

    await contacts.blockContact('alice');
    posts.feedGate!.complete();
    await tester.pumpAndSettle();

    expect(posts.focusedIds, isEmpty);
    expect(find.byType(ThoughtCardScreen), findsNothing);
    expect(find.text('orbit-home'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a typed reply sends once and opens chat without waiting', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    final replies = <(String, String)>[];
    var closedBeforeReply = false;
    var chatOpens = 0;
    final sending = Completer<ThoughtReplyStatus>();
    await openCard(
      tester,
      thought,
      sendReply: (text, postId, _) {
        replies.add((text, postId));
        closedBeforeReply = navigationObserver.poppedNames.contains(
          'thought-card',
        );
        return sending.future;
      },
      onOpenChat: () => chatOpens++,
    );

    await tester.tap(_replyField);
    await tester.pump();
    expect(find.byKey(const ValueKey('thought-react-love')), findsNothing);
    await tester.enterText(_replyField, '  count me in ');
    await tester.pump();
    await tester.tap(_replySend);
    await tester.tap(_replySend, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(replies, [('count me in', 'thought-1')]);
    expect(closedBeforeReply, isFalse);
    expect(chatOpens, 1);
    expect(find.byType(ThoughtCardScreen), findsNothing);
    sending.complete(ThoughtReplyStatus.failed);
    await tester.pump();
    expect(chatOpens, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a reaction is one tap and sends its glyph', (tester) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    final replies = <(String, String)>[];
    await openCard(
      tester,
      thought,
      onReply: (text, postId) => replies.add((text, postId)),
    );

    expect(tester.widget<GestureDetector>(_replySend).onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('thought-react-fire')));
    await tester.pumpAndSettle();

    expect(replies, [('🔥', 'thought-1')]);
    expect(find.byType(ThoughtCardScreen), findsOneWidget);
    expect(find.text('sent'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('reaction retry keeps the same ID and glyph', (tester) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    final attempts = <(String, String, String)>[];
    await openCard(
      tester,
      thought,
      sendReply: (text, postId, messageId) async {
        attempts.add((text, postId, messageId));
        return attempts.length == 1
            ? ThoughtReplyStatus.failed
            : ThoughtReplyStatus.sent;
      },
    );
    await tester.tap(find.byKey(const ValueKey('thought-react-fire')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thought-reply-retry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thought-reply-retry')));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts.last, attempts.first);
    expect(attempts.first.$1, '🔥');
    expect(find.text('sent'), findsOneWidget);
    expect(find.byType(ThoughtCardScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await finish(tester);
  });

  testWidgets(
    'a queued reply updates to Sent with no separate open-chat line',
    (tester) async {
      final thought = _thought(initialNow);
      await posts.savePost(thought);
      final changes = StreamController<ConversationMessage>.broadcast();
      addTearDown(changes.close);
      String? sentId;
      var chatOpens = 0;
      await openCard(
        tester,
        thought,
        sendReply: (_, _, id) async {
          sentId = id;
          return ThoughtReplyStatus.queued;
        },
        replyChanges: changes.stream,
        onOpenChat: () => chatOpens++,
      );
      await tester.tap(find.byKey(const ValueKey('thought-react-love')));
      await tester.pumpAndSettle();
      expect(find.text('Sending...'), findsOneWidget);
      expect(chatOpens, 0);
      changes.add(
        ConversationMessage(
          id: sentId!,
          contactPeerId: 'alice-peer',
          senderPeerId: 'local-peer',
          text: '❤️',
          timestamp: now.toIso8601String(),
          createdAt: now.toIso8601String(),
          isIncoming: false,
          status: 'inboxed',
          quotedMessageId: 'thought:thought-1',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('sent'), findsOneWidget);
      expect(find.byKey(const ValueKey('thought-reply-retry')), findsNothing);
      expect(find.byKey(const ValueKey('thought-open-chat')), findsNothing);
      expect(find.text('Open chat with Alice'), findsNothing);
      expect(chatOpens, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'initial stale item and later arrivals resolve to only the newest thought',
    (tester) async {
      final old = _thought(initialNow);
      final newest = old.copyWith(
        createdAt: initialNow
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        text: 'Newest thought',
      );
      await posts.savePost(old);
      await posts.savePost(_withId(newest, 'thought-2'));

      await openCard(tester, old);
      await tester.pumpAndSettle();
      expect(find.text('Newest thought', findRichText: true), findsOneWidget);
      expect(find.text('Quiet thought', findRichText: true), findsNothing);
      expect(posts.focusedIds, ['thought-2']);

      await posts.savePost(
        _withId(
          newest.copyWith(
            createdAt: initialNow.toIso8601String(),
            text: 'Latest arrival',
          ),
          'thought-3',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest arrival', findRichText: true), findsOneWidget);
      expect(find.text('Newest thought', findRichText: true), findsNothing);
      expect(posts.focusedIds, ['thought-2', 'thought-3']);
      await finish(tester);
    },
  );

  testWidgets('closes on deletion and on later contact ineligibility', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(
      _withId(
        thought.copyWith(
          createdAt: initialNow
              .subtract(const Duration(hours: 3))
              .toIso8601String(),
          expiresAt: initialNow
              .add(const Duration(hours: 21))
              .toIso8601String(),
          text: 'Older surviving thought',
        ),
        'older-thought',
      ),
    );
    await posts.savePost(thought);
    await openCard(tester, thought);

    await posts.deletePostCascade(thought.id);
    await tester.pumpAndSettle();
    expect(find.byType(ThoughtCardScreen), findsNothing);
    expect(await posts.getPost('older-thought'), isNotNull);

    await posts.savePost(thought);
    await openCard(tester, thought);
    await contacts.archiveContact('alice');
    eligibility.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ThoughtCardScreen), findsNothing);
    expect(await posts.getPost(thought.id), isNotNull);
    await finish(tester);
  });

  testWidgets(
    'expires at the exact deadline while persisted data remains unswept',
    (tester) async {
      final thought = _thought(initialNow).copyWith(
        expiresAt: initialNow
            .add(const Duration(seconds: 10))
            .toIso8601String(),
      );
      await posts.savePost(thought);
      await openCard(tester, thought);

      now = initialNow.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.byType(ThoughtCardScreen), findsNothing);
      expect(find.text('orbit-home'), findsOneWidget);
      expect(await posts.getPost(thought.id), isNotNull);
      await finish(tester);
    },
  );

  testWidgets(
    'expiry removes its own card beneath an unrelated route without popping it',
    (tester) async {
      final thought = _thought(initialNow).copyWith(
        expiresAt: initialNow
            .add(const Duration(seconds: 10))
            .toIso8601String(),
      );
      await posts.savePost(thought);
      await openCard(tester, thought);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('unrelated-route')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      now = initialNow.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('unrelated-route'), findsOneWidget);
      expect(find.byType(ThoughtCardScreen, skipOffstage: false), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('orbit-home'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'downloads encrypted photo metadata through the supplied existing downloader and shows the whole photo on the card',
    (tester) async {
      final photo = _tempFile('photo.png', pngBytes: true);
      final thought = _thought(initialNow).copyWith(mediaKind: 'image');
      final attachment = _attachment('image');
      final downloads = <PostMediaAttachmentModel>[];
      await posts.savePost(thought);
      await posts.savePostMediaAttachment(attachment);

      await openCard(
        tester,
        thought,
        download: (requested) async {
          downloads.add(requested);
          await posts.updatePostMediaLocalPath(
            requested.mediaId,
            photo.path,
            postId: requested.postId,
          );
          return requested.copyWith(
            localPath: photo.path,
            downloadStatus: 'done',
          );
        },
      );
      await pumpMediaFrames(tester);

      expect(downloads, hasLength(1));
      expect(downloads.single.encryptionKeyBase64, 'private-key');
      expect(downloads.single.encryptionNonce, 'nonce');
      final full = find.byKey(const ValueKey('thought-photo-full'));
      final image = tester.widget<Image>(full);
      expect((image.image, image.fit), (FileImage(photo), BoxFit.contain));
      expect(
        tester.getRect(full),
        tester.getRect(find.byKey(const ValueKey('thought-card-screen'))),
      );
      expect(find.byType(MediaGrid), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byKey(const ValueKey('thought-life-bar')), findsNothing);
      await tester.tap(full, warnIfMissed: false);
      await pumpMediaFrames(tester);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'download failure stops automatically and offers an explicit retry',
    (tester) async {
      final photo = _tempFile('retry.png', pngBytes: true);
      final thought = _thought(initialNow).copyWith(mediaKind: 'image');
      await posts.savePost(thought);
      await posts.savePostMediaAttachment(_attachment('image'));
      var attempts = 0;
      await openCard(
        tester,
        thought,
        download: (requested) async {
          attempts++;
          if (attempts == 1) {
            await posts.updatePostMediaDownloadStatus(
              requested.mediaId,
              'failed',
            );
            throw StateError('download failed');
          }
          await posts.updatePostMediaLocalPath(
            requested.mediaId,
            photo.path,
            postId: requested.postId,
          );
          return requested.copyWith(
            localPath: photo.path,
            downloadStatus: 'done',
          );
        },
      );
      await pumpMediaFrames(tester);
      expect(attempts, 1);
      final retry = find.byKey(
        const ValueKey('unavailable-media-retry-thought-1-blob-image'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await pumpMediaFrames(tester);
      expect(attempts, 2);
      expect(find.byKey(const ValueKey('thought-photo-full')), findsOneWidget);
      await finish(tester);
    },
  );

  for (final kind in ['video', 'voice']) {
    testWidgets(
      'renders $kind using the existing player after automatic download',
      (tester) async {
        final file = _tempFile(kind == 'voice' ? 'voice.m4a' : 'video.mp4');
        final thought = _thought(initialNow).copyWith(mediaKind: kind);
        await posts.savePost(thought);
        await posts.savePostMediaAttachment(_attachment(kind));
        await openCard(
          tester,
          thought,
          download: (requested) async {
            await posts.updatePostMediaLocalPath(
              requested.mediaId,
              file.path,
              postId: requested.postId,
            );
            return requested.copyWith(
              localPath: file.path,
              downloadStatus: 'done',
            );
          },
        );
        await tester.pumpAndSettle();

        if (kind == 'voice') {
          final player = tester.widget<AudioPlayerWidget>(
            find.byType(AudioPlayerWidget),
          );
          expect(player.attachment.mediaType, 'audio');
          expect(player.attachment.localPath, file.path);
          expect(player.attachment.downloadStatus, 'done');
        } else {
          final grid = tester.widget<MediaGrid>(find.byType(MediaGrid));
          expect(grid.media.single.mediaType, 'video');
          expect(grid.media.single.localPath, file.path);
          expect(grid.media.single.downloadStatus, 'done');
        }
        await finish(tester);
      },
    );
  }

  testWidgets(
    'a portrait video thought keeps its portrait frame, up to full screen',
    (tester) async {
      final file = _tempFile('portrait.mp4');
      final thought = _thought(initialNow).copyWith(mediaKind: 'video');
      await posts.savePost(thought);
      await posts.savePostMediaAttachment(
        _attachment('video').copyWith(width: 720, height: 1280),
      );
      await openCard(
        tester,
        thought,
        download: (requested) async {
          await posts.updatePostMediaLocalPath(
            requested.mediaId,
            file.path,
            postId: requested.postId,
          );
          return requested.copyWith(
            localPath: file.path,
            downloadStatus: 'done',
          );
        },
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      expect(rect.height / rect.width, closeTo(16 / 9, .01));
      expect(rect.height, lessThanOrEqualTo(600));
      await finish(tester);
    },
  );

  testWidgets('a failing seen-write keeps the thought on screen', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    posts.focusError = StateError('database locked');

    await openCard(tester, thought);
    await tester.pumpAndSettle();

    expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
    expect(_replyField, findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'media still on its way holds its place, not a spinner or Retry',
    (tester) async {
      final thought = _thought(initialNow).copyWith(mediaKind: 'image');
      await posts.savePost(thought);

      await openCard(tester, thought);
      await pumpMediaFrames(tester);

      expect(
        find.byKey(const ValueKey('thought-media-placeholder')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('a photo still downloading holds its own shape, not a spinner', (
    tester,
  ) async {
    final thought = _thought(initialNow).copyWith(mediaKind: 'image');
    await posts.savePost(thought);
    await posts.savePostMediaAttachment(
      _attachment('image').copyWith(width: 800, height: 600),
    );
    final download = Completer<PostMediaAttachmentModel>();

    await openCard(tester, thought, download: (_) => download.future);
    await pumpMediaFrames(tester);

    final placeholder = find.byKey(const ValueKey('thought-media-placeholder'));
    expect(placeholder, findsOneWidget);
    expect(
      tester
          .widget<AspectRatio>(
            find.descendant(
              of: placeholder,
              matching: find.byType(AspectRatio),
            ),
          )
          .aspectRatio,
      4 / 3,
    );
    expect(find.byType(MediaGrid), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    await finish(tester);
  });

  testWidgets(
    "a photo on its way shows the sender's preview blurred, then the whole photo",
    (tester) async {
      final thought = _thought(initialNow).copyWith(mediaKind: 'image');
      await posts.savePost(thought);
      final preview = base64Encode(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
      final pending = _attachment(
        'image',
      ).copyWith(width: 3000, height: 1000, previewBase64: preview);
      await posts.savePostMediaAttachment(pending);
      final download = Completer<PostMediaAttachmentModel>();

      await openCard(tester, thought, download: (_) => download.future);
      await pumpMediaFrames(tester);

      final placeholder = find.byKey(
        const ValueKey('thought-media-placeholder'),
      );
      expect(
        find.descendant(
          of: placeholder,
          matching: find.byKey(const ValueKey('thought-photo-preview')),
        ),
        findsOneWidget,
      );
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final photo = _tempFile('preview-loaded.png', pngBytes: true);
      await posts.updatePostMediaLocalPath(
        pending.mediaId,
        photo.path,
        postId: pending.postId,
      );
      download.complete(
        pending.copyWith(localPath: photo.path, downloadStatus: 'done'),
      );
      await pumpMediaFrames(tester);

      expect(placeholder, findsNothing);
      expect(find.byKey(const ValueKey('thought-photo-preview')), findsNothing);
      final full = tester.widget<Image>(
        find.byKey(const ValueKey('thought-photo-full')),
      );
      expect((full.image, full.fit), (FileImage(photo), BoxFit.contain));
      expect(find.byType(ImageFiltered), findsNothing);
      await finish(tester);
    },
  );

  Future<void> openPhotoCard(WidgetTester tester) async {
    final photo = _tempFile('immersive.png', pngBytes: true);
    final thought = _thought(initialNow).copyWith(mediaKind: 'image');
    await posts.savePost(thought);
    await posts.savePostMediaAttachment(
      _attachment(
        'image',
      ).copyWith(localPath: photo.path, downloadStatus: 'done'),
    );
    await openCard(tester, thought, onReply: (_, _) {});
    await pumpMediaFrames(tester);
  }

  testWidgets('the mic records a voice reply that goes to the chat', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    final recorder = FakeAudioRecorderService()
      ..fakeDurationMs = 1500
      ..fakeOutputPath = '/tmp/thought-reply.m4a';
    final voiceReplies = <ThoughtVoiceReply>[];
    await openCard(
      tester,
      thought,
      onReply: (_, _) {},
      onVoiceReply: voiceReplies.add,
      recorder: recorder,
    );

    final mic = find.descendant(
      of: find.byKey(const ValueKey('thought-reply-composer')),
      matching: find.byType(VoiceRecordButton),
    );
    expect(mic, findsOneWidget);
    await tester.tap(mic);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(recorder.startCallCount, 1);
    expect(voiceReplies, isEmpty);
    await tester.tap(mic);
    await tester.pumpAndSettle();

    expect(voiceReplies, hasLength(1));
    expect(voiceReplies.single.postId, 'thought-1');
    expect(voiceReplies.single.quotedMessageId, 'thought:thought-1');
    expect(voiceReplies.single.recording.filePath, '/tmp/thought-reply.m4a');
    expect(voiceReplies.single.autoStopped, isFalse);
    expect(find.byType(ThoughtCardScreen), findsNothing);
    expect(find.text('orbit-home'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'a call that cuts the recording leaves no file and no reply',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      final thought = _thought(initialNow);
      await posts.savePost(thought);
      final file = _tempFile('cut-by-call.m4a');
      final recorder = FakeAudioRecorderService()..fakeOutputPath = file.path;
      final voiceReplies = <ThoughtVoiceReply>[];
      await openCard(
        tester,
        thought,
        onReply: (_, _) {},
        onVoiceReply: voiceReplies.add,
        recorder: recorder,
      );
      await tester.tap(find.byType(VoiceRecordButton));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(recorder.isRecording, isTrue);

      var callGotMicrophone = false;
      unawaited(
        microphoneCaptureLeasesFor(
          recorder,
        ).prepareForCall().then((_) => callGotMicrophone = true),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await waitForDeletion(tester, file);

      expect(callGotMicrophone, isTrue);

      expect(voiceReplies, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(find.byType(ThoughtCardScreen), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'a recording that finishes after the card closed is removed',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      final thought = _thought(initialNow);
      await posts.savePost(thought);
      final file = _tempFile('after-close.m4a');
      final stopGate = Completer<void>();
      final recorder = FakeAudioRecorderService()
        ..fakeOutputPath = file.path
        ..stopGate = stopGate;
      final voiceReplies = <ThoughtVoiceReply>[];
      await openCard(
        tester,
        thought,
        onReply: (_, _) {},
        onVoiceReply: voiceReplies.add,
        recorder: recorder,
      );
      final mic = find.byType(VoiceRecordButton);
      await tester.tap(mic);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(mic);
      await tester.pump();

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ThoughtCardScreen), findsNothing);
      stopGate.complete();
      await tester.pump();
      await waitForDeletion(tester, file);

      expect(voiceReplies, isEmpty);
      expect(file.existsSync(), isFalse);
      await finish(tester);
    },
  );

  testWidgets('typing swaps the mic for Send, and no recorder means no mic', (
    tester,
  ) async {
    final thought = _thought(initialNow);
    await posts.savePost(thought);
    await openCard(
      tester,
      thought,
      onReply: (_, _) {},
      onVoiceReply: (_) {},
      recorder: FakeAudioRecorderService(),
    );
    expect(find.byType(VoiceRecordButton), findsOneWidget);
    await tester.enterText(_replyField, 'hi');
    await tester.pump();
    expect(find.byType(VoiceRecordButton), findsNothing);
    await finish(tester);

    await openCard(tester, thought, onReply: (_, _) {});
    expect(find.byType(VoiceRecordButton), findsNothing);
    await finish(tester);
  });

  testWidgets('the reply box is the chat composer without its +', (
    tester,
  ) async {
    await openPhotoCard(tester);

    final composer = find.byKey(const ValueKey('thought-reply-composer'));
    expect(tester.widget(composer), isA<ComposeArea>());
    expect(find.byKey(const ValueKey('composer-attach-button')), findsNothing);
    expect(
      find.descendant(of: composer, matching: find.text('Reply to Alice…')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('thought-open-chat')), findsNothing);
    await finish(tester);
  });

  testWidgets('a tap on the photo shows it alone, a second tap brings back '
      'the card', (tester) async {
    await openPhotoCard(tester);
    final photo = find.byKey(const ValueKey('thought-photo-full'));
    final chrome = [
      find.byKey(const ValueKey('thought-reply-composer')),
      find.byKey(const ValueKey('thought-age')),
      find.byKey(const ValueKey('thought-react-love')),
    ];
    for (final part in chrome) {
      expect(part, findsOneWidget);
    }

    await tester.tap(photo);
    await tester.pump();
    for (final part in chrome) {
      expect(part, findsNothing);
    }
    expect(photo, findsOneWidget);

    await tester.tap(photo);
    await tester.pump();
    for (final part in chrome) {
      expect(part, findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('a newer text Thought brings back the card hidden behind a '
      'photo', (tester) async {
    await openPhotoCard(tester);
    await tester.tap(find.byKey(const ValueKey('thought-photo-full')));
    await tester.pump();
    expect(find.byKey(const ValueKey('thought-reply-composer')), findsNothing);

    await posts.savePost(
      _withId(
        _thought(initialNow).copyWith(
          createdAt: initialNow.toIso8601String(),
          text: 'Words after the photo',
        ),
        'thought-2',
      ),
    );
    await pumpMediaFrames(tester);

    expect(
      find.text('Words after the photo', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('thought-photo-toggle')), findsNothing);
    expect(
      find.byKey(const ValueKey('thought-reply-composer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('thought-age')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('with the keyboard open a tap on the photo only closes it', (
    tester,
  ) async {
    await openPhotoCard(tester);
    await tester.tap(_replyField);
    await tester.pump();
    expect(tester.widget<TextField>(_replyField).focusNode!.hasFocus, isTrue);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('thought-photo-full'))),
    );
    await tester.pump();
    expect(tester.widget<TextField>(_replyField).focusNode!.hasFocus, isFalse);
    expect(
      find.byKey(const ValueKey('thought-reply-composer')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a panorama keeps its whole width instead of being cropped', (
    tester,
  ) async {
    final photo = _tempFile('pano.png', pngBytes: true);
    final thought = _thought(initialNow).copyWith(mediaKind: 'image');
    await posts.savePost(thought);
    await posts.savePostMediaAttachment(
      _attachment('image').copyWith(
        width: 3000,
        height: 1000,
        localPath: photo.path,
        downloadStatus: 'done',
      ),
    );

    await openCard(tester, thought);
    await pumpMediaFrames(tester);

    final full = find.byKey(const ValueKey('thought-photo-full'));
    expect(tester.widget<Image>(full).fit, BoxFit.contain);
    expect(
      tester.getRect(full),
      tester.getRect(find.byKey(const ValueKey('thought-card-screen'))),
    );
    expect(find.byType(ImageFiltered), findsNothing);
    await finish(tester);
  });

  testWidgets('an uploading multi-photo thought holds its place too', (
    tester,
  ) async {
    final thought = _thought(
      initialNow,
    ).copyWith(text: '', mediaKind: 'image_carousel');
    await posts.savePost(thought);

    await openCard(tester, thought);
    await pumpMediaFrames(tester);

    expect(
      find.byKey(const ValueKey('thought-media-placeholder')),
      findsOneWidget,
    );
    await finish(tester);
  });

  for (final c in bidiCases) {
    testWidgets('the card lays out mixed text: ${c.label}', (tester) async {
      final thought = _thought(initialNow).copyWith(text: c.text);
      await posts.savePost(thought);
      await openCard(tester, thought);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(c.text, findRichText: true),
      );
      expectBidiLayout(
        c,
        direction: paragraph.textDirection,
        boxes: paragraph.getBoxesForSelection,
      );
      await finish(tester);
    });
  }

  testWidgets('an Arabic thought reads right to left in an English app', (
    tester,
  ) async {
    final thought = _thought(initialNow).copyWith(text: 'فكرة هادئة');
    await posts.savePost(thought);

    await openCard(tester, thought);
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('فكرة هادئة', findRichText: true),
    );
    expect(paragraph.textDirection, TextDirection.rtl);
    await finish(tester);
  });

  testWidgets('expiry closes its owned media viewer and the card together', (
    tester,
  ) async {
    final photo = _tempFile('expires.png', pngBytes: true);
    final thought = _thought(initialNow).copyWith(
      mediaKind: 'image_carousel',
      expiresAt: initialNow.add(const Duration(seconds: 10)).toIso8601String(),
    );
    await posts.savePost(thought);
    final first = _attachment(
      'image',
    ).copyWith(localPath: photo.path, downloadStatus: 'done');
    await posts.savePostMediaAttachment(first);
    await posts.savePostMediaAttachment(
      first.copyWith(mediaId: 'media-image-2', blobId: 'blob-image-2'),
    );
    await openCard(tester, thought);
    tester.widget<MediaGrid>(find.byType(MediaGrid)).onTap!(0);
    tester.widget<MediaGrid>(find.byType(MediaGrid)).onTap!(0);
    await tester.pumpAndSettle();
    expect(
      find.byType(FullScreenTypedMediaViewer, skipOffstage: false),
      findsOneWidget,
    );

    now = initialNow.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(
      find.byType(FullScreenTypedMediaViewer, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(ThoughtCardScreen, skipOffstage: false), findsNothing);
    expect(find.text('orbit-home'), findsOneWidget);
    await finish(tester);
  });
}

const _alice = ContactModel(
  peerId: 'alice',
  publicKey: 'public-key',
  rendezvous: 'relay',
  username: 'Alice',
  signature: 'signature',
  scannedAt: '2026-10-20T12:00:00Z',
);

PostModel _thought(DateTime now) => PostModel(
  id: 'thought-1',
  eventId: 'event-thought-1',
  senderPeerId: 'alice',
  authorPeerId: 'alice',
  authorUsername: 'Alice',
  text: 'Quiet thought',
  audience: PostAudience.allFriends(),
  createdAt: now.subtract(const Duration(hours: 2)).toIso8601String(),
  visibleAt: now.subtract(const Duration(hours: 2)).toIso8601String(),
  expiresAt: now.add(const Duration(hours: 22)).toIso8601String(),
);

PostModel _withId(PostModel post, String id) => PostModel.fromMap({
  ...post.toMap(),
  'post_id': id,
  'event_id': 'event-$id',
});

PostMediaAttachmentModel _attachment(String kind) => PostMediaAttachmentModel(
  mediaId: 'media-$kind',
  postId: 'thought-1',
  blobId: 'blob-$kind',
  kind: kind,
  mime: kind == 'voice'
      ? 'audio/mp4'
      : kind == 'video'
      ? 'video/mp4'
      : 'image/png',
  sizeBytes: 100,
  createdAt: '2026-10-21T10:00:00Z',
  durationMs: kind == 'image' ? null : 2000,
  encryptionKeyBase64: 'private-key',
  encryptionNonce: 'nonce',
  isEncrypted: true,
);

File _tempFile(String name, {bool pngBytes = false}) {
  final directory = Directory.systemTemp.createTempSync('thought-card-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/$name')..writeAsBytesSync(
    pngBytes
        ? base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          )
        : [0, 1, 2, 3],
  );
}

class _CardPostRepository extends InMemoryPostRepository {
  final focusedIds = <String>[];
  Completer<void>? feedGate;

  @override
  Future<List<PostModel>> loadFeed() async {
    await feedGate?.future;
    return super.loadFeed();
  }

  Object? focusError;

  @override
  Future<void> markFocused(String postId) async {
    focusedIds.add(postId);
    if (focusError != null) throw focusError!;
    await super.markFocused(postId);
    final post = await getPost(postId);
    if (post != null) await savePost(post.copyWith(isRead: true));
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final poppedNames = <String?>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedNames.add(route.settings.name);
    super.didPop(route, previousRoute);
  }
}

Finder get _replyField => find.descendant(
  of: find.byKey(const ValueKey('thought-reply-composer')),
  matching: find.byType(TextField),
);

Finder get _replySend => find
    .ancestor(
      of: find.descendant(
        of: find.byKey(const ValueKey('thought-reply-composer')),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      matching: find.byType(GestureDetector),
    )
    .first;
