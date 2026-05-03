import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

OrbitFriend _makeFriend(int i) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$i-abcdef1234',
      publicKey: 'pk-$i',
      rendezvous: '/ip4/127.0.0.1/tcp/400$i',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2024-01-01T00:00:00Z',
    ),
    messageCount: i,
  );
}

void main() {
  Widget wrap(Widget child, {BackgroundReadableColors? readableColors}) =>
      MaterialApp(
        theme: ThemeData(
          extensions: [readableColors ?? BackgroundReadableColors.dark],
        ),
        home: Scaffold(body: child),
      );

  // OrbitalAvatar uses Future.delayed for staggered animations,
  // and OverflowBadge uses Future.delayed(1000ms). We must pump
  // past all timers to avoid "pending timer" test failures.
  Future<void> pumpPastAnimations(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  group('OrbitalVisualization', () {
    testWidgets('renders "YOUR INNER CIRCLE" text', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: [])),
      );
      await pumpPastAnimations(tester);
      expect(find.text('YOUR INNER CIRCLE'), findsOneWidget);
    });

    testWidgets('renders center UserAvatar', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: [])),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('renders OrbitalAvatars for friends in ring 1', (tester) async {
      final friends = List.generate(3, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: friends),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OrbitalAvatar), findsNWidgets(3));
    });

    testWidgets('renders OrbitalAvatars for friends in ring 2', (tester) async {
      final friends = List.generate(8, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: friends),
        ),
      );
      await pumpPastAnimations(tester);
      // 5 in ring 1 + 3 in ring 2
      expect(find.byType(OrbitalAvatar), findsNWidgets(8));
    });

    testWidgets('shows OverflowBadge when more than 13 friends', (
      tester,
    ) async {
      final friends = List.generate(15, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: friends),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OverflowBadge), findsOneWidget);
    });

    testWidgets('hides OverflowBadge when 13 or fewer friends', (tester) async {
      final friends = List.generate(10, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: friends),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OverflowBadge), findsNothing);
    });

    testWidgets('renders CustomPaint for orbital rings', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: [])),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('uses readable heading and overflow text on daylight', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      final friends = List.generate(15, (i) => _makeFriend(i));

      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', friends: friends),
          readableColors: colors,
        ),
      );
      await pumpPastAnimations(tester);

      final heading = tester.widget<Text>(find.text('YOUR INNER CIRCLE'));
      final overflow = tester.widget<Text>(find.text('+2'));

      expect(heading.style!.color, colors.textMuted);
      expect(overflow.style!.color, colors.textMuted);
      expectTextContrast(heading.style!.color!, colors.surfaceBase);
      expectTextContrast(overflow.style!.color!, colors.surfaceSubtle);
    });
  });
}
