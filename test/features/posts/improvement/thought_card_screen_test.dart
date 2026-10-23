// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/load_orbit_thoughts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/thought_card_screen.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
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
    VoidCallback? onMessage,
    Future<void> Function(String postId)? onDelete,
    Future<PostModel?> Function()? loadCurrent,
    Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)?
    download,
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
            onMessage: messageable ? (onMessage ?? () {}) : null,
            onDelete: onDelete,
            downloadMedia:
                download ??
                (_) async => throw StateError('Unexpected media download'),
            eligibilityChanges: eligibility.stream,
            nowProvider: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

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
      expect(find.text('2h ago'), findsOneWidget);
      expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
      expect(posts.focusedIds, ['thought-1']);
      expect((await posts.getPost('thought-1'))!.isRead, isTrue);
      expect(find.byType(PostCard), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.comment_outlined), findsNothing);
      expect(find.byKey(const ValueKey('thought-message')), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('an own thought card has no Message button and stays unread', (
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
    expect(find.text('2h ago'), findsOneWidget);
    expect(find.text('Quiet thought', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('thought-message')), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(posts.focusedIds, isEmpty);
    expect((await posts.getPost('thought-1'))!.isRead, isFalse);
    expect(find.byKey(const ValueKey('thought-delete')), findsNothing);
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

  testWidgets(
    'Message removes the card before opening ordinary chat with no thought payload',
    (tester) async {
      final thought = _thought(initialNow);
      await posts.savePost(thought);
      var messageCalls = 0;
      var closedBeforeMessage = false;
      await openCard(
        tester,
        thought,
        onMessage: () {
          messageCalls++;
          closedBeforeMessage = navigationObserver.poppedNames.contains(
            'thought-card',
          );
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('ordinary-chat-empty-composer')),
              ),
            ),
          );
        },
      );

      await tester.tap(find.byKey(const ValueKey('thought-message')));
      await tester.tap(find.byKey(const ValueKey('thought-message')));
      await tester.pumpAndSettle();

      expect(messageCalls, 1);
      expect(closedBeforeMessage, isTrue);
      expect(find.byType(ThoughtCardScreen, skipOffstage: false), findsNothing);
      expect(find.text('ordinary-chat-empty-composer'), findsOneWidget);
      expect(
        find.text('Quiet thought', findRichText: true, skipOffstage: false),
        findsNothing,
      );
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
    'downloads encrypted photo metadata through the supplied existing downloader and opens the shared viewer',
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
          await posts.updatePostMediaLocalPath(requested.mediaId, photo.path);
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
      final grid = tester.widget<MediaGrid>(find.byType(MediaGrid));
      expect(grid.media.single.localPath, photo.path);
      expect(grid.media.single.downloadStatus, 'done');
      grid.onTap!(0);
      await pumpMediaFrames(tester);
      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items.single.attachmentId, 'blob-image');
      expect(viewer.items.single.capabilities.allowed, isEmpty);
      expect(viewer.items.single.owner, isNull);
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
          await posts.updatePostMediaLocalPath(requested.mediaId, photo.path);
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
      expect(
        tester
            .widget<MediaGrid>(find.byType(MediaGrid))
            .media
            .single
            .downloadStatus,
        'done',
      );
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
            await posts.updatePostMediaLocalPath(requested.mediaId, file.path);
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

  testWidgets('expiry closes its owned media viewer and the card together', (
    tester,
  ) async {
    final photo = _tempFile('expires.png', pngBytes: true);
    final thought = _thought(initialNow).copyWith(
      mediaKind: 'image',
      expiresAt: initialNow.add(const Duration(seconds: 10)).toIso8601String(),
    );
    await posts.savePost(thought);
    await posts.savePostMediaAttachment(
      _attachment(
        'image',
      ).copyWith(localPath: photo.path, downloadStatus: 'done'),
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

  @override
  Future<void> markFocused(String postId) async {
    focusedIds.add(postId);
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
