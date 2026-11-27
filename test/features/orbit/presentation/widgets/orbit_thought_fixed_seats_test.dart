import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_thought_note_bubble.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/thought_card_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/in_memory_post_repository.dart';

const _deadline = Duration(seconds: 3);
final _now = DateTime.utc(2026, 11, 27, 12);

Finder _avatar(int index) => find.byKey(ValueKey('orbit-node-$index'));

Finder get _notes => find.byType(OrbitThoughtNoteBubble);

Finder get _badges => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('orbit-thought-badge-'),
    _ => false,
  },
);

void main() {
  const scenarios = [
    (friends: 3, thoughts: 2, notes: 2, badges: 0, locale: 'en'),
    (friends: 8, thoughts: 5, notes: 4, badges: 1, locale: 'en'),
    (friends: 15, thoughts: 6, notes: 4, badges: 2, locale: 'en'),
    (friends: 8, thoughts: 5, notes: 4, badges: 1, locale: 'ar'),
  ];

  for (final scenario in scenarios) {
    testWidgets(
      'BL-108 notes open on fixed seats for ${scenario.friends} friends (${scenario.locale})',
      (tester) async {
        await _mount(
          tester,
          count: scenario.friends,
          thoughts: scenario.thoughts,
          locale: scenario.locale,
        );
        try {
          expect(
            _notes.evaluate().length + _badges.evaluate().length,
            scenario.thoughts,
          );
          final viz = find.byType(OrbitalVisualization);
          final layout = computeOrbitLayout(
            memberCount: scenario.friends,
            geometry: tester.widget<OrbitalVisualization>(viz).geometry,
            mirrored: scenario.locale == 'ar',
          );
          expect(layout.ring1Radius, 62);
          expect(layout.ring2Radius, 108);

          var previous = Duration.zero;
          for (final elapsed in [
            const Duration(milliseconds: 500),
            const Duration(seconds: 2),
            const Duration(seconds: 10),
          ]) {
            await _advance(tester, elapsed - previous);
            previous = elapsed;
            expect(
              tester.widget<OrbitalVisualization>(viz).thoughtVisibility,
              1,
            );
            final center = tester.getCenter(
              find.byKey(const ValueKey('orbit-self-node')),
            );
            final paintedAvatars = [
              Rect.fromCenter(center: center, width: 48, height: 48),
            ];
            for (final seat in layout.seats.where(
              (seat) => seat.kind != OrbitSeatKind.arc,
            )) {
              final actual = tester.getCenter(_avatar(seat.index));
              final relative = actual - center;
              expect(
                (relative - Offset(seat.dx, seat.dy)).distance,
                lessThan(0.01),
                reason: 'Avatar ${seat.index} at ${elapsed.inMilliseconds} ms',
              );
              expect(relative.distance, closeTo(seat.radius, 0.01));
              paintedAvatars.add(
                Rect.fromCenter(
                  center: actual,
                  width: seat.avatarSize,
                  height: seat.avatarSize,
                ),
              );
            }
            expect(_notes, findsNWidgets(scenario.notes));
            expect(_badges, findsNWidgets(scenario.badges));
            final canvas = tester.getRect(
              find.byKey(const ValueKey('orbit-viz-canvas')),
            );
            for (final element in _notes.evaluate()) {
              final bounds = tester.getRect(find.byWidget(element.widget));
              expect(bounds.top, greaterThanOrEqualTo(canvas.top - 0.01));
              expect(bounds.bottom, lessThanOrEqualTo(canvas.bottom + 0.01));
              expect(
                paintedAvatars.any((avatar) => bounds.overlaps(avatar)),
                isFalse,
              );
            }
          }
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  for (final useBadge in [false, true]) {
    testWidgets(
      'BL-108 opens a full Thought from the ${useBadge ? 'badge' : 'avatar'}',
      (tester) async {
        final chats = <String>[];
        await _mount(tester, count: 8, thoughts: 5, onChat: chats.add);
        try {
          await _advance(tester, const Duration(seconds: 2));
          final target = useBadge ? _badges : _avatar(0);
          expect(target, findsOneWidget);
          final index = useBadge
              ? int.parse(
                  (tester.widget(target).key! as ValueKey<String>).value
                      .split('-')
                      .last,
                )
              : 0;
          if (useBadge) {
            expect(tester.getSize(target), const Size.square(18));
          }
          await tester.tap(target).timeout(_deadline);
          await _advance(tester, const Duration(milliseconds: 400));
          final card = find.byType(ThoughtCardScreen);
          expect(card, findsOneWidget);
          expect(
            tester.widget<ThoughtCardScreen>(card).initialPost.id,
            'thought-$index',
          );
          expect(chats, isEmpty);
        } finally {
          await _unmount(tester);
        }
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required int count,
  required int thoughts,
  String locale = 'en',
  ValueChanged<String>? onChat,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final repo = InMemoryPostRepository();
  addTearDown(repo.dispose);
  final items = [
    for (var i = 0; i < count; i++)
      OrbitFriendItem(
        OrbitFriend(
          contact: ContactModel(
            peerId: 'friend-$i',
            username: locale == 'ar' ? 'صديق $i' : 'Friend $i',
            publicKey: 'pk-$i',
            rendezvous: '',
            signature: '',
            scannedAt: _now.toIso8601String(),
          ),
          messageCount: 0,
          unreadCount: 0,
        ),
      ),
  ];
  final posts = {
    for (var i = 0; i < thoughts; i++)
      'thought-$i': PostModel(
        id: 'thought-$i',
        eventId: 'event-$i',
        senderPeerId: 'friend-$i',
        authorPeerId: 'friend-$i',
        authorUsername: locale == 'ar' ? 'صديق $i' : 'Friend $i',
        text: locale == 'ar'
            ? 'فكرة قصيرة عن هذا الصباح والطريق إلى البيت $i'
            : 'A short thought about this morning and the walk home $i',
        audience: PostAudience.allFriends(),
        createdAt: _now.toIso8601String(),
        visibleAt: _now.toIso8601String(),
        expiresAt: _now.add(const Duration(hours: 1)).toIso8601String(),
        mediaKind: 'none',
      ),
  };
  await tester
      .pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
          home: Scaffold(
            body: Builder(
              builder: (context) => InnerCircleInteractiveSurface(
                userPeerId: 'self',
                items: items,
                onFriendTap: (friend) => onChat?.call(friend.peerId),
                onGroupTap: (_) {},
                nowProvider: () => _now,
                thoughtsByPeerId: {
                  for (final post in posts.values)
                    post.senderPeerId: OrbitThoughtNote(
                      postId: post.id,
                      text: post.text,
                      isRead: false,
                      expiresAt: DateTime.parse(post.expiresAt),
                    ),
                },
                onThoughtTap: (id) {
                  final post = posts[id]!;
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ThoughtCardScreen(
                        initialPost: post,
                        authorName: post.authorUsername,
                        postRepo: repo,
                        loadCurrentThought: () async => post,
                        downloadMedia: (attachment, _) async => attachment,
                        nowProvider: () => _now,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      )
      .timeout(_deadline);
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 500);
  var remaining = duration;
  while (remaining > Duration.zero) {
    final frame = remaining < step ? remaining : step;
    await tester.pump(frame).timeout(_deadline);
    remaining -= frame;
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink()).timeout(_deadline);
  await _advance(tester, const Duration(seconds: 2));
}
