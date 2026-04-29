import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  group('GroupReactionDetailsSheet', () {
    testWidgets('uses readable light-background roles for labels and rows', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[colors]),
          home: Scaffold(
            body: ColoredBox(
              color: colors.surfaceBase,
              child: const GroupReactionDetailsSheet(
                emoji: '👍',
                participants: [
                  GroupReactionParticipantEntry(
                    peerId: 'peer-one',
                    displayName: 'Alice',
                    emoji: '👍',
                  ),
                  GroupReactionParticipantEntry(
                    peerId: 'peer-two',
                    displayName: 'You',
                    emoji: '👍',
                    isSelf: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final title = tester.widget<Text>(find.text('Reactions'));
      final count = tester.widget<Text>(find.text('👍 2'));
      final alice = tester.widget<Text>(find.text('Alice'));
      final you = tester.widget<Text>(find.text('You'));

      expectTextContrast(title.style!.color!, colors.surfaceBase);
      expectTextContrast(count.style!.color!, colors.surfaceBase);
      expectTextContrast(alice.style!.color!, colors.surfaceBase);
      expectTextContrast(you.style!.color!, colors.surfaceBase);
    });
  });
}
