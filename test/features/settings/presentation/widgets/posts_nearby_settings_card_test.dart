import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/presentation/widgets/posts_nearby_settings_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({
    required bool sharingEnabled,
    required ValueChanged<bool> onChanged,
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PostsNearbySettingsCard(
          sharingEnabled: sharingEnabled,
          onChanged: onChanged,
        ),
      ),
    );
  }

  BoxDecoration cardDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding == const EdgeInsets.all(20) &&
            widget.decoration is BoxDecoration,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('uses representative light readable roles when sharing is off', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;
    bool? changed;

    await tester.pumpWidget(
      wrap(
        sharingEnabled: false,
        onChanged: (value) => changed = value,
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final title = tester.widget<Text>(find.text('Share People Nearby'));
    expect(title.style?.color, colors.textPrimary);

    final status = tester.widget<Text>(find.text('Off'));
    expect(status.style?.color, colors.textSecondary);

    final helper = tester.widget<Text>(
      find.text(
        'Shares only an approximate location with direct friends. No live maps, and never strangers.',
      ),
    );
    expect(helper.style?.color, colors.textMuted);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changed, isTrue);
  });

  testWidgets('uses representative light readable roles when sharing is on', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;
    bool? changed;

    await tester.pumpWidget(
      wrap(
        sharingEnabled: true,
        onChanged: (value) => changed = value,
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final status = tester.widget<Text>(find.text('On'));
    expect(status.style?.color, colors.textSecondary);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changed, isFalse);
  });

  testWidgets('keeps dark readable roles for visible text and card chrome', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.dark;

    await tester.pumpWidget(
      wrap(sharingEnabled: true, onChanged: (_) {}, readableColors: colors),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final title = tester.widget<Text>(find.text('Share People Nearby'));
    expect(title.style?.color, colors.textPrimary);

    final status = tester.widget<Text>(find.text('On'));
    expect(status.style?.color, colors.textSecondary);

    final helper = tester.widget<Text>(
      find.text(
        'Shares only an approximate location with direct friends. No live maps, and never strangers.',
      ),
    );
    expect(helper.style?.color, colors.textMuted);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue);
  });
}
