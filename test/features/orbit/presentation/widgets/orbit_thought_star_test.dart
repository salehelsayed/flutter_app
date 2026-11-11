import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner request 2026-11-10: a friend with an unopened thought gets an orbiting
// star while the thought titles are hidden (the pinched-in state).
void main() {
  final start = DateTime.utc(2026, 11, 10, 12);
  const starKey = ValueKey('orbit-thought-star');

  OrbitFriend friend(int index, {int unread = 0}) => OrbitFriend(
    contact: ContactModel(
      peerId: 'friend-$index',
      username: 'Friend $index',
      publicKey: 'pk-$index',
      rendezvous: '',
      signature: '',
      scannedAt: '2026-11-10T00:00:00Z',
    ),
    messageCount: unread,
    unreadCount: unread,
  );

  OrbitThoughtNote note({bool read = false}) => OrbitThoughtNote(
    postId: 'post-0',
    text: 'A thought',
    isRead: read,
    expiresAt: start.add(const Duration(hours: 1)),
  );

  Widget pump({
    required double thoughtVisibility,
    OrbitThoughtNote? thought,
    int unread = 0,
    ValueChanged<OrbitFriend>? onFriendTap,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(
          body: Center(
            child: OrbitalVisualization(
              userPeerId: 'self',
              items: [
                OrbitFriendItem(friend(0, unread: unread)),
                OrbitFriendItem(friend(1)),
              ],
              nowProvider: () => start,
              thoughtsByPeerId: thought == null
                  ? const {}
                  : {'friend-0': thought},
              thoughtVisibility: thoughtVisibility,
              onFriendTap: onFriendTap ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  int satellites(WidgetTester tester) => find
      .byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> &&
            key.value.startsWith('unread-satellite-');
      })
      .evaluate()
      .length;

  testWidgets('an unopened thought with hidden titles shows the star', (
    tester,
  ) async {
    await tester.pumpWidget(pump(thoughtVisibility: 0, thought: note()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsOneWidget);
  });

  testWidgets('shown titles hide the star', (tester) async {
    await tester.pumpWidget(pump(thoughtVisibility: 1, thought: note()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsNothing);
  });

  testWidgets('a read thought shows no star', (tester) async {
    await tester.pumpWidget(
      pump(thoughtVisibility: 0, thought: note(read: true)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsNothing);
  });

  testWidgets('no thought shows no star', (tester) async {
    await tester.pumpWidget(pump(thoughtVisibility: 0));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsNothing);
  });

  testWidgets('the star and the unread orbit show together', (tester) async {
    await tester.pumpWidget(
      pump(thoughtVisibility: 0, thought: note(), unread: 2),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsOneWidget);
    expect(satellites(tester), 2);
  });

  testWidgets('the star never takes a tap meant for the avatar', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      pump(
        thoughtVisibility: 0,
        thought: note(),
        onFriendTap: (f) => opened.add(f.peerId),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('orbit-node-0')));
    expect(opened, ['friend-0']);
    final star = tester.renderObject(find.byKey(starKey));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      tester.getCenter(find.byKey(starKey)),
      tester.view.viewId,
    );
    expect(result.path.where((entry) => entry.target == star), isEmpty);
  });

  // Owner follow-up 2026-11-11: the star marks the pinched-in view only. Notes
  // put away for the "+N" arcs or for a sculpt session show no star.
  Widget surface(Map<String, OrbitThoughtNote> thoughts) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(
          body: InnerCircleInteractiveSurface(
            userPeerId: 'self',
            onSelfAvatarTap: () {},
            items: [for (var i = 0; i < 14; i++) OrbitFriendItem(friend(i))],
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            thoughtsByPeerId: thoughts,
            nowProvider: () => start,
          ),
        ),
      ),
    ),
  );

  testWidgets('notes put away for the +N arcs show no star', (tester) async {
    await tester.pumpWidget(surface({'friend-0': note()}));
    await tester.tap(find.byType(OverflowBadge));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(starKey),
      findsNothing,
      reason: 'the badge put the notes away, not a pinch',
    );
    await tester.tap(find.byType(OverflowBadge));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<OrbitalVisualization>(find.byType(OrbitalVisualization))
          .overflowExpanded,
      isTrue,
    );
    expect(find.byKey(starKey), findsNothing, reason: 'arcs are open');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a thought arriving in a sculpt session shows no star', (
    tester,
  ) async {
    await tester.pumpWidget(surface(const {}));
    await tester.pump(const Duration(seconds: 1));
    await tester.longPress(
      find.byKey(const ValueKey('orbit-center-self-avatar')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
    await tester.pumpWidget(surface({'friend-0': note()}));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pinch that hides the titles shows the star', (tester) async {
    await tester.pumpWidget(surface({'friend-0': note()}));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsNothing, reason: 'titles are shown');
    final center = tester.getCenter(
      find.byKey(const ValueKey('orbit-thought-pinch-surface')),
    );
    final a = await tester.startGesture(
      center - const Offset(50, 0),
      pointer: 1,
    );
    final b = await tester.startGesture(
      center + const Offset(50, 0),
      pointer: 2,
    );
    await a.moveBy(const Offset(25, 0));
    await b.moveBy(const Offset(-25, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(starKey), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
