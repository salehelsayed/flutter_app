import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_ring_painter.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

OrbitFriend _friend(int index, {int unreadCount = 0}) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$index',
      publicKey: 'pk-$index',
      rendezvous: '/ip4/127.0.0.1/tcp/40$index',
      username: 'Friend $index',
      signature: 'sig-$index',
      scannedAt: '2026-07-07T00:00:00Z',
    ),
    messageCount: index,
    unreadCount: unreadCount,
  );
}

Widget _wrap(BackgroundReadableColors colors, {bool expanded = false}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [colors]),
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        body: OrbitalVisualization(
          userPeerId: 'self',
          overflowExpanded: expanded,
          items: [
            OrbitFriendItem(_friend(0, unreadCount: 2)),
            for (var i = 1; i < 15; i++) OrbitFriendItem(_friend(i)),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('node halo is mounted on light and absent on dark', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(_wrap(colors));
    await tester.pump();

    expect(find.byKey(const ValueKey('orbit-node-halo-self')), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-node-halo-0')), findsOneWidget);
    // Paper White: the halo is a CRISP ring (opaque accent, zero blur, 2px
    // spread) — not the old translucent bloom — plus a neutral lift shadow.
    final selfRing = _haloRingShadow(
      tester,
      const ValueKey('orbit-node-halo-self'),
    );
    expect(selfRing.color, colors.nodeSelfGlow);
    expect(selfRing.blurRadius, 0.0);
    expect(selfRing.spreadRadius, 2.0);
    final contactRing = _haloRingShadow(
      tester,
      const ValueKey('orbit-node-halo-0'),
    );
    expect(contactRing.color, colors.nodeContactGlow);
    expect(contactRing.blurRadius, 0.0);
    expect(contactRing.spreadRadius, 2.0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_wrap(BackgroundReadableColors.dark));
    await tester.pump();

    expect(find.byKey(const ValueKey('orbit-node-halo-self')), findsNothing);
    expect(find.byKey(const ValueKey('orbit-node-halo-0')), findsNothing);
  });

  testWidgets('rings and overflow arcs use Signal ink-violet on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(_wrap(colors, expanded: true));
    await tester.pump();

    final ringPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((paint) => paint.painter is OrbitalRingPainter);
    final painter = ringPaint.painter! as OrbitalRingPainter;

    expect(painter.ring1Color, colors.ring1);
    expect(painter.ring2Color, colors.ring2);
    expect(painter.glowColor, colors.ringGlow);
    expect(painter.arcs, isNotEmpty);

    final unreadPaint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(UnreadOrbitIndicator),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere((paint) => paint.painter is UnreadOrbitRingPainter);
    final unreadPainter = unreadPaint.painter! as UnreadOrbitRingPainter;
    expect(unreadPainter.accent, UnreadOrbitIndicator.kUnreadAccent);
  });
}

BoxShadow _haloRingShadow(WidgetTester tester, Key haloKey) {
  final decoratedBox = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(haloKey),
      matching: find.byType(DecoratedBox),
    ),
  );
  final decoration = decoratedBox.decoration as BoxDecoration;
  // The crisp accent ring is the first shadow; the neutral lift is the second.
  return decoration.boxShadow!.first;
}
