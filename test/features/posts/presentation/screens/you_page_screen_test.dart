import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/group_thought_reactions.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../../shared/fakes/fake_just_audio.dart';

final _now = DateTime.utc(2026, 11, 1, 12);

PostModel _post({
  String id = 'post-1',
  String text = 'first coffee on the balcony',
  Duration age = const Duration(hours: 5),
  Duration left = const Duration(hours: 18, minutes: 10),
  PostAudience? audience,
}) => PostModel(
  id: id,
  eventId: 'event-$id',
  senderPeerId: 'me',
  authorPeerId: 'me',
  authorUsername: 'Saleh',
  text: text,
  audience: audience ?? PostAudience.allFriends(),
  createdAt: _now.subtract(age).toIso8601String(),
  visibleAt: _now.subtract(age).toIso8601String(),
  expiresAt: _now.add(left).toIso8601String(),
  isIncoming: false,
);

YouThought _past(
  String id,
  String text,
  Duration age, {
  List<ThoughtReactionGroup> reactions = const [],
  List<YouWroteBack> wroteBack = const [],
}) => YouThought(
  post: _post(
    id: id,
    text: text,
    age: age,
    left: const Duration(hours: 24) - age,
  ),
  reactions: reactions,
  wroteBack: wroteBack,
);

Finder _inCard(String postId, Finder finder) => find.descendant(
  of: find.byKey(ValueKey('you-thought-$postId')),
  matching: finder,
);

YouThought _thought({
  bool reactions = true,
  bool wroteBack = true,
  Duration left = const Duration(hours: 18, minutes: 10),
  PostAudience? audience,
}) => YouThought(
  post: _post(left: left, audience: audience),
  reactions: reactions
      ? [
          (
            reaction: ThoughtReaction.love,
            participants: [(peerId: 'omar', name: 'Omar')],
          ),
          (
            reaction: ThoughtReaction.applause,
            participants: [(peerId: 'layla', name: 'Layla')],
          ),
        ]
      : const [],
  wroteBack: wroteBack
      ? const [
          YouWroteBack(peerId: 'nour', name: 'Nour', hasUnread: true),
          YouWroteBack(peerId: 'sara', name: 'Sara', hasUnread: false),
          YouWroteBack(peerId: 'tarek', name: 'Tarek', hasUnread: false),
        ]
      : const [],
);

YouPageData _data({
  YouThought? thought,
  List<YouThought> past = const [],
  String? tag,
  int tagCount = 0,
}) => YouPageData(
  username: 'Saleh',
  avatarBytes: null,
  friendCount: 41,
  thought: thought,
  past: past,
  tag: tag,
  tagCount: tagCount,
);

Finder _keysStartingWith(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(prefix),
);

PostMediaAttachmentModel _media(String id, String kind, int position) =>
    PostMediaAttachmentModel(
      mediaId: id,
      postId: 'post-1',
      blobId: 'blob-$id',
      kind: kind,
      mime: kind == 'voice' ? 'audio/aac' : 'image/jpeg',
      sizeBytes: 10,
      position: position,
      durationMs: kind == 'voice' ? 4000 : null,
      localPath: 'missing/$id',
      downloadStatus: 'done',
      createdAt: _now.toIso8601String(),
    );

void main() {
  late List<String> openedChats;
  late int composeCalls;
  late List<String?> composeTags;
  late int backCalls;

  setUp(() {
    openedChats = [];
    composeCalls = 0;
    composeTags = [];
    backCalls = 0;
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Future<YouPageData> Function()? load, {
    Future<YouPageData> Function(int historyLimit)? paged,
    Future<YouPageData> Function(int historyLimit, String? tag)? tagged,
    DateTime Function()? now,
    Stream<String> replies = const Stream.empty(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: tagged ?? (limit, _) => paged != null ? paged(limit) : load!(),
          now: now ?? () => _now,
          onBack: () => backCalls++,
          onOpenChat: (peerId) async => openedChats.add(peerId),
          onCompose: (tag) async {
            composeCalls++;
            composeTags.add(tag);
          },
          thoughtReplies: replies,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('header shows the handle and the friend count', (tester) async {
    await pumpPage(tester, () async => _data());

    expect(find.text('you/ @Saleh'), findsOneWidget);
    expect(find.text('41 friends'), findsOneWidget);
  });

  testWidgets('back button calls onBack', (tester) async {
    await pumpPage(tester, () async => _data());

    await tester.tap(find.byTooltip('Back'));
    expect(backCalls, 1);
  });

  testWidgets('a live thought shows its text, reactions and replies', (
    tester,
  ) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.text('2 reacted'), findsOneWidget);
    expect(_keysStartingWith('you-reaction-'), findsNWidgets(2));
    expect(find.text('3 wrote back · 1 new'), findsOneWidget);
    expect(_keysStartingWith('you-wrote-'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('you-unread-nour')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-unread-sara')), findsNothing);
    expect(find.byKey(const ValueKey('you-unread-tarek')), findsNothing);
    expect(_keysStartingWith('you-unread-'), findsOneWidget);
  });

  testWidgets('the live line rounds the hours left up', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(find.text('still up for friends · gone in 19 h'), findsOneWidget);
  });

  testWidgets('a thought for picked people says how many see it', (
    tester,
  ) async {
    await pumpPage(
      tester,
      () async => _data(
        thought: _thought(
          audience: PostAudience.pickPeople(['omar', 'nour', 'layla']),
        ),
      ),
    );

    expect(find.text('3 people'), findsOneWidget);
    expect(find.text('still up for 3 people · gone in 19 h'), findsOneWidget);
    expect(find.text('All Friends'), findsNothing);
    expect(find.textContaining('for friends'), findsNothing);
  });

  testWidgets('tapping a wrote-back face opens that chat', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    await tester.tap(find.byKey(const ValueKey('you-wrote-sara')));
    await tester.pumpAndSettle();

    expect(openedChats, ['sara']);
  });

  testWidgets('nothing on the page says who saw the thought', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(
      find.textContaining(RegExp('seen', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('rows with a zero count are left out', (tester) async {
    await pumpPage(
      tester,
      () async => _data(thought: _thought(reactions: false, wroteBack: false)),
    );

    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.textContaining('reacted'), findsNothing);
    expect(find.textContaining('wrote back'), findsNothing);
    expect(_keysStartingWith('you-reaction-'), findsNothing);
    expect(_keysStartingWith('you-wrote-'), findsNothing);
  });

  testWidgets('replies with nothing unread show no new count', (tester) async {
    await pumpPage(
      tester,
      () async => _data(
        thought: YouThought(
          post: _post(),
          reactions: const [],
          wroteBack: const [
            YouWroteBack(peerId: 'sara', name: 'Sara', hasUnread: false),
          ],
        ),
      ),
    );

    expect(find.text('1 wrote back'), findsOneWidget);
    expect(find.textContaining('new'), findsNothing);
  });

  testWidgets('without a thought the page says nothing is shared', (
    tester,
  ) async {
    await pumpPage(tester, () async => _data());

    expect(find.text('Nothing shared right now'), findsOneWidget);
    expect(find.textContaining('still up for'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('you-composer')));
    await tester.pumpAndSettle();

    expect(composeCalls, 1);
  });

  testWidgets('the page reloads after a share', (tester) async {
    var loads = 0;
    await pumpPage(tester, () async {
      loads++;
      return _data(thought: loads > 1 ? _thought() : null);
    });
    expect(find.text('Nothing shared right now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('you-composer')));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.text('Nothing shared right now'), findsNothing);
  });

  testWidgets('only a reply to a shown thought reloads the page', (
    tester,
  ) async {
    final replies = StreamController<String>.broadcast();
    addTearDown(replies.close);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: (_, _) async {
            loads++;
            return _data(
              thought: _thought(),
              past: [_past('post-old', 'older walk', const Duration(days: 2))],
            );
          },
          now: () => _now,
          onBack: () {},
          onOpenChat: (_) async {},
          onCompose: (_) async {},
          thoughtReplies: replies.stream,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);

    replies.add('someone-elses-thought');
    await tester.pumpAndSettle();
    expect(loads, 1);

    replies.add('post-old');
    await tester.pumpAndSettle();
    expect(loads, 2);

    replies.add('post-1');
    await tester.pumpAndSettle();
    expect(loads, 3);
  });

  group('tags', () {
    final live = _past(
      'post-1',
      'first coffee #Mornings',
      const Duration(hours: 2),
    );
    final river = _past(
      'post-river',
      'walk by the river #walks',
      const Duration(days: 1),
    );
    final rain = _past('post-rain', 'rain again', const Duration(days: 2));
    final falls = _past(
      'post-falls',
      'sunset at the falls #Walks',
      const Duration(days: 3),
    );
    late List<String?> loadedTags;

    Future<void> pumpTagged(
      WidgetTester tester, {
      Stream<String> replies = const Stream.empty(),
    }) {
      loadedTags = [];
      return pumpPage(
        tester,
        null,
        replies: replies,
        tagged: (_, tag) async {
          loadedTags.add(tag);
          return tag == 'walks'
              ? _data(
                  thought: live,
                  past: [river, falls],
                  tag: 'walks',
                  tagCount: 2,
                )
              : _data(thought: live, past: [river, rain, falls]);
        },
      );
    }

    Text tagIn(WidgetTester tester, String postId, String key) => tester
        .widget<Text>(_inCard(postId, find.byKey(ValueKey('you-tag-$key'))));

    testWidgets('a tag in your own thought is set in the tag type', (
      tester,
    ) async {
      await pumpTagged(tester);

      expect(tagIn(tester, 'post-river', 'walks').style?.fontFamily, 'Menlo');
      expect(tagIn(tester, 'post-1', 'mornings').style?.fontFamily, 'Menlo');
      expect(tagIn(tester, 'post-falls', 'walks').data, '#Walks');
    });

    testWidgets('tapping a tag shows only your thoughts with it, with a bar', (
      tester,
    ) async {
      await pumpTagged(tester);
      expect(find.byKey(const ValueKey('you-tag-bar')), findsNothing);

      await tester.tap(
        _inCard('post-river', find.byKey(const ValueKey('you-tag-walks'))),
      );
      await tester.pumpAndSettle();

      expect(loadedTags, [null, 'walks']);
      final bar = find.byKey(const ValueKey('you-tag-bar'));
      expect(
        find.descendant(of: bar, matching: find.text('#walks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('2 thoughts')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('only you see this')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('you-thought-post-river')), findsOne);
      expect(find.byKey(const ValueKey('you-thought-post-falls')), findsOne);
      expect(find.byKey(const ValueKey('you-thought-post-rain')), findsNothing);
      expect(find.byKey(const ValueKey('you-thought-post-1')), findsNothing);
    });

    testWidgets('the clear X goes back to all your thoughts', (tester) async {
      await pumpTagged(tester);
      await tester.tap(
        _inCard('post-river', find.byKey(const ValueKey('you-tag-walks'))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('you-tag-clear')));
      await tester.pumpAndSettle();

      expect(loadedTags, [null, 'walks', null]);
      expect(find.byKey(const ValueKey('you-tag-bar')), findsNothing);
      expect(find.byKey(const ValueKey('you-thought-post-rain')), findsOne);
      expect(find.byKey(const ValueKey('you-thought-post-1')), findsOne);
    });

    testWidgets('in a tag view only a reply to a shown thought reloads', (
      tester,
    ) async {
      final replies = StreamController<String>.broadcast();
      addTearDown(replies.close);
      await pumpTagged(tester, replies: replies.stream);
      await tester.tap(
        _inCard('post-river', find.byKey(const ValueKey('you-tag-walks'))),
      );
      await tester.pumpAndSettle();
      expect(loadedTags, [null, 'walks']);

      replies.add('post-1');
      await tester.pumpAndSettle();
      expect(loadedTags, [null, 'walks']);

      replies.add('post-river');
      await tester.pumpAndSettle();
      expect(loadedTags, [null, 'walks', 'walks']);
    });

    testWidgets('a long tag keeps its X and count inside a phone screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = 'a' * 80;
      final long = _past('post-long', 'long #$key', const Duration(days: 1));
      await pumpPage(
        tester,
        null,
        tagged: (_, tag) async => tag == null
            ? _data(past: [long])
            : _data(past: [long], tag: key, tagCount: 1),
      );
      await tester.tap(
        _inCard('post-long', find.byKey(ValueKey('you-tag-$key'))),
      );
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byKey(const ValueKey('you-tag-bar')));
      final clear = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('you-tag-clear')),
          matching: find.byIcon(Icons.close),
        ),
      );
      final count = tester.getRect(find.text('1 thought'));
      expect(bar.width, 390);
      expect(clear.right, lessThanOrEqualTo(bar.right));
      expect(count.right, lessThanOrEqualTo(bar.right));
      expect(clear.right, lessThan(count.left));
    });

    testWidgets('one thought with the tag reads 1 thought', (tester) async {
      await pumpPage(
        tester,
        null,
        tagged: (_, tag) async => tag == null
            ? _data(past: [river, rain])
            : _data(past: [river], tag: 'walks', tagCount: 1),
      );
      await tester.tap(
        _inCard('post-river', find.byKey(const ValueKey('you-tag-walks'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 thought'), findsOneWidget);
    });

    testWidgets('the composer adds the next thought to the tag', (
      tester,
    ) async {
      await pumpTagged(tester);
      await tester.tap(
        _inCard('post-river', find.byKey(const ValueKey('you-tag-walks'))),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('you-composer')),
          matching: find.text('add to #walks'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('you-composer')));
      await tester.pumpAndSettle();

      expect(composeTags, ['#walks']);
      expect(find.byKey(const ValueKey('you-tag-bar')), findsOneWidget);
    });

    testWidgets('without a tag the composer opens empty', (tester) async {
      await pumpTagged(tester);
      await tester.tap(find.byKey(const ValueKey('you-composer')));
      await tester.pumpAndSettle();

      expect(composeTags, [null]);
    });
  });

  testWidgets('a thought with an hour or less left reads 1 h', (tester) async {
    await pumpPage(
      tester,
      () async => _data(thought: _thought(left: const Duration(minutes: 20))),
    );

    expect(find.text('still up for friends · gone in 1 h'), findsOneWidget);
  });

  testWidgets('a voice-only thought shows its voice player', (tester) async {
    final original = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    addTearDown(() => JustAudioPlatform.instance = original);
    final thought = _thought();
    await pumpPage(
      tester,
      () async => _data(
        thought: YouThought(
          post: thought.post.copyWith(
            text: '',
            media: [_media('voice-1', 'voice', 0)],
          ),
          reactions: thought.reactions,
          wroteBack: thought.wroteBack,
        ),
      ),
    );

    final player = tester.widget<AudioPlayerWidget>(
      find.byKey(const ValueKey('you-voice-voice-1')),
    );
    expect(player.attachment.mediaType, 'audio');
  });

  testWidgets('tapping the second photo opens the viewer on that photo', (
    tester,
  ) async {
    final thought = _thought();
    await pumpPage(
      tester,
      () async => _data(
        thought: YouThought(
          post: thought.post.copyWith(
            media: [_media('p1', 'image', 0), _media('p2', 'image', 1)],
          ),
          reactions: thought.reactions,
          wroteBack: thought.wroteBack,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('you-media-p2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final viewer = tester.widget<FullScreenTypedMediaViewer>(
      find.byKey(const ValueKey('you-media-viewer')),
    );
    expect(viewer.initialIndex, 1);
    expect(viewer.items.map((item) => item.attachmentId), [
      'blob-p1',
      'blob-p2',
    ]);
  });

  testWidgets('at expiry the thought and its viewer go even if reload fails', (
    tester,
  ) async {
    var clock = _now;
    var loads = 0;
    final thought = _thought(left: const Duration(minutes: 30));
    await pumpPage(tester, () async {
      if (loads++ > 0) throw StateError('store unavailable');
      return _data(
        thought: YouThought(
          post: thought.post.copyWith(media: [_media('p1', 'image', 0)]),
          reactions: thought.reactions,
          wroteBack: thought.wroteBack,
        ),
      );
    }, now: () => clock);
    await tester.tap(find.byKey(const ValueKey('you-media-p1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('you-media-viewer')), findsOneWidget);

    clock = _now.add(const Duration(minutes: 30, seconds: 1));
    await tester.pump(const Duration(minutes: 30, seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));

    expect(loads, greaterThan(1));
    expect(find.byKey(const ValueKey('you-media-viewer')), findsNothing);
    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.textContaining('still up for'), findsNothing);
    expect(find.text('Nothing shared right now'), findsOneWidget);
  });

  testWidgets(
    'past thoughts sit above the live one, oldest at the top, each with its '
    'own reacted and wrote-back rows',
    (tester) async {
      final older = _past(
        'past-old',
        'rain on the tram',
        const Duration(days: 3),
        reactions: [
          (
            reaction: ThoughtReaction.love,
            participants: [(peerId: 'omar', name: 'Omar')],
          ),
        ],
      );
      final newer = _past(
        'past-new',
        'new shoes',
        const Duration(hours: 30),
        wroteBack: const [
          YouWroteBack(peerId: 'sara', name: 'Sara', hasUnread: false),
        ],
      );
      await pumpPage(
        tester,
        () async => _data(
          thought: _thought(reactions: false, wroteBack: false),
          past: [newer, older],
        ),
      );

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('rain on the tram'), lessThan(top('new shoes')));
      expect(top('new shoes'), lessThan(top('first coffee on the balcony')));

      expect(_inCard('past-old', find.text('1 reacted')), findsOneWidget);
      expect(
        _inCard(
          'past-old',
          find.byKey(const ValueKey('you-reaction-omar-love')),
        ),
        findsOneWidget,
      );
      expect(_inCard('past-new', find.text('1 wrote back')), findsOneWidget);
      expect(_inCard('post-1', find.textContaining('reacted')), findsNothing);
      expect(
        _inCard('post-1', find.textContaining('wrote back')),
        findsNothing,
      );
      expect(
        _inCard('post-1', find.text('still up for friends · gone in 19 h')),
        findsOneWidget,
      );
      expect(_inCard('post-1', find.text('Today')), findsOneWidget);
      expect(_inCard('past-new', find.text('Yesterday')), findsOneWidget);

      await tester.tap(
        _inCard('past-new', find.byKey(const ValueKey('you-wrote-sara'))),
      );
      await tester.pumpAndSettle();
      expect(openedChats, ['sara']);
    },
  );

  testWidgets('an expired thought shows its day but no live line', (
    tester,
  ) async {
    await pumpPage(
      tester,
      () async => _data(
        past: [_past('past-new', 'new shoes', const Duration(hours: 30))],
      ),
    );

    expect(find.text('new shoes'), findsOneWidget);
    expect(_inCard('past-new', find.text('Yesterday')), findsOneWidget);
    expect(find.textContaining('still up for'), findsNothing);
    expect(find.text('Nothing shared right now'), findsOneWidget);
  });

  testWidgets('scrolling to the oldest past thought loads the next page', (
    tester,
  ) async {
    final limits = <int>[];
    await pumpPage(
      tester,
      null,
      paged: (limit) async {
        limits.add(limit);
        return _data(
          past: [
            for (var i = 0; i < limit; i++)
              _past('past-$i', 'past $i', Duration(days: i + 2)),
          ],
        );
      },
    );
    expect(limits, [20]);

    for (var i = 0; i < 20 && limits.length == 1; i++) {
      await tester.drag(
        find.byKey(const ValueKey('you-feed')),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
    }

    expect(limits, [20, 40]);
  });
}
