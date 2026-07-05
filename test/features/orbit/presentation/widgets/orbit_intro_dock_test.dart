import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_intro_dock.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildDock({
    bool dismissed = false,
    int unseenCount = 3,
    int pendingGroupInviteCount = 1,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: OrbitIntroDock(
            foldedReviewItems: [
              _foldedItem(targetPeerId: 'peer-a', targetDisplayName: 'Dora'),
              _foldedItem(targetPeerId: 'peer-b', targetDisplayName: 'Mina'),
              _foldedItem(targetPeerId: 'peer-c', targetDisplayName: 'Rami'),
            ],
            pendingGroupInviteCount: pendingGroupInviteCount,
            unseenCount: unseenCount,
            dismissed: dismissed,
            onTap: () {},
            onDismissed: () {},
          ),
        ),
      ),
    );
  }

  group('OrbitIntroDock', () {
    testWidgets('TC-207-04 facepile and plural unseen label render', (
      tester,
    ) async {
      await tester.pumpWidget(buildDock());

      expect(find.byKey(const ValueKey('orbit-intro-dock')), findsOneWidget);
      expect(find.byType(UserAvatar), findsNWidgets(2));
      expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
      expect(find.text('3 new'), findsOneWidget);
    });

    testWidgets('TC-207-09 dock and remnant expose localized button semantics', (
      tester,
    ) async {
      await tester.pumpWidget(buildDock());
      expect(
        tester.getSemantics(find.byKey(const ValueKey('orbit-intro-dock'))),
        matchesSemantics(
          label: 'Open introductions review, 3 new',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.pumpWidget(buildDock(dismissed: true, unseenCount: 0));
      expect(
        tester.getSemantics(find.byKey(const ValueKey('orbit-intro-remnant'))),
        matchesSemantics(
          label: 'Open introductions review',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });
  });
}

FoldedIntroductionReviewItem _foldedItem({
  required String targetPeerId,
  required String targetDisplayName,
}) {
  final intro = IntroductionModel(
    id: 'intro-$targetPeerId',
    introducerId: 'introducer-$targetPeerId',
    recipientId: 'own-peer',
    introducedId: targetPeerId,
    createdAt: '2026-07-06T00:00:00.000Z',
    introducerUsername: 'Noor',
    recipientUsername: 'Alice',
    introducedUsername: targetDisplayName,
  );

  return FoldedIntroductionReviewItem(
    targetPeerId: targetPeerId,
    targetPeerName: targetDisplayName,
    targetDisplayName: targetDisplayName,
    displaySourceIntroductionId: intro.id,
    newestIntroduction: intro,
    introductions: [intro],
    introductionIds: [intro.id],
    introducerAttributions: const [
      FoldedIntroductionIntroducerAttribution(
        introducerId: 'introducer',
        displayName: 'Noor',
      ),
    ],
    pendingCurrentViewerDecisionIntroIds: [intro.id],
    acceptedCurrentViewerDecisionIntroIds: const [],
    passedCurrentViewerDecisionIntroIds: const [],
  );
}
