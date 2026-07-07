import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget wrap(BackgroundReadableColors colors) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [colors]),
      home: const Scaffold(
        body: EmptyConversationState(
          contactPeerId: 'peer-empty',
          connectionDate: 'July 7, 2026',
        ),
      ),
    );
  }

  testWidgets(
    'heading, hint, date, divider, and avatar glow use Signal tones',
    (tester) async {
      const colors = BackgroundReadableColors.representativeLight;

      await tester.pumpWidget(wrap(colors));
      await tester.pump();

      final heading = tester.widget<Text>(find.text('Connected!'));
      expect(heading.style!.color, colors.connectedHeading);
      expectComponentContrast(heading.style!.color!, const Color(0xFFEDEEF3));

      final date = tester.widget<Text>(find.text('July 7, 2026'));
      expect(date.style!.color, colors.emptyDate);
      expectTextContrast(date.style!.color!, const Color(0xFFEDEEF3));

      final hint = tester.widget<Text>(
        find.text('Write the first letter\nto start your conversation'),
      );
      expect(hint.style!.color, colors.emptyHint);
      expectTextContrast(hint.style!.color!, const Color(0xFFEDEEF3));

      final divider = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) => container.color == colors.emptyDivider)
          .toList();
      expect(divider, isNotEmpty);

      final glowContainer = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) {
            final decoration = container.decoration;
            return decoration is BoxDecoration &&
                decoration.boxShadow?.any(
                      (shadow) =>
                          shadow.color ==
                          colors.emptyAvatarGlow.withValues(alpha: 0.3),
                    ) ==
                    true;
          })
          .toList();
      expect(glowContainer, isNotEmpty);
    },
  );

  testWidgets('dark date, divider, and avatar glow literals stay unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
    await tester.pump();

    final date = tester.widget<Text>(find.text('July 7, 2026'));
    expect(date.style!.color, const Color(0x59FFFFFF));

    final divider = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.color == const Color(0x1FFFFFFF))
        .toList();
    expect(divider, isNotEmpty);
  });
}
