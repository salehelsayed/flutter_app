import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/image_quality_toggle.dart';

void main() {
  Widget wrap({
    required ImageQualityPreference value,
    required ValueChanged<ImageQualityPreference> onChanged,
    String? label,
    IconData? icon,
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ImageQualityToggle(
          value: value,
          onChanged: onChanged,
          label: label ?? 'Photo Quality',
          icon: icon ?? Icons.photo_size_select_large,
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

  BoxDecoration segmentedControlDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate((widget) {
        if (widget is! Container || widget.decoration is! BoxDecoration) {
          return false;
        }

        final decoration = widget.decoration! as BoxDecoration;
        final borderRadius = decoration.borderRadius;
        return widget.child is Row &&
            borderRadius is BorderRadius &&
            borderRadius.topLeft.x == 10;
      }),
    );
    return container.decoration! as BoxDecoration;
  }

  BoxDecoration optionDecoration(WidgetTester tester, String text) {
    final option = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return option.decoration! as BoxDecoration;
  }

  testWidgets('renders default label "Photo Quality" when no label provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(value: ImageQualityPreference.compressed, onChanged: (_) {}),
    );

    expect(find.text('Photo Quality'), findsOneWidget);
  });

  testWidgets('renders custom label when label provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.compressed,
        onChanged: (_) {},
        label: 'Video Quality',
      ),
    );

    expect(find.text('Video Quality'), findsOneWidget);
    expect(find.text('Photo Quality'), findsNothing);
  });

  testWidgets('renders custom icon when icon provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.compressed,
        onChanged: (_) {},
        icon: Icons.videocam,
      ),
    );

    expect(find.byIcon(Icons.videocam), findsOneWidget);
  });

  testWidgets('uses representative light readable roles', (tester) async {
    const colors = BackgroundReadableColors.representativeLight;
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.compressed,
        onChanged: (_) {},
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final icon = tester.widget<Icon>(
      find.byIcon(Icons.photo_size_select_large),
    );
    expect(icon.color, colors.iconMuted);

    final label = tester.widget<Text>(find.text('Photo Quality'));
    expect(label.style?.color, colors.textMuted);

    final segmentedControl = segmentedControlDecoration(tester);
    expect(segmentedControl.color, colors.surfaceSubtle);

    final compressedOption = optionDecoration(tester, 'Compressed');
    expect(compressedOption.color, colors.surfaceRaised);

    final compressedText = tester.widget<Text>(find.text('Compressed'));
    expect(compressedText.style?.color, colors.textPrimary);

    final originalText = tester.widget<Text>(find.text('Original'));
    expect(originalText.style?.color, colors.textSecondary);

    final description = tester.widget<Text>(
      find.text(
        'Smaller file size, faster sending. Metadata is always removed.',
      ),
    );
    expect(description.style?.color, colors.textMuted);
  });

  testWidgets('keeps dark readable roles for custom video quality toggle', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.dark;
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.original,
        onChanged: (_) {},
        label: 'Video Quality',
        icon: Icons.videocam,
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final icon = tester.widget<Icon>(find.byIcon(Icons.videocam));
    expect(icon.color, colors.iconMuted);

    final label = tester.widget<Text>(find.text('Video Quality'));
    expect(label.style?.color, colors.textMuted);

    final segmentedControl = segmentedControlDecoration(tester);
    expect(segmentedControl.color, colors.surfaceSubtle);

    final originalOption = optionDecoration(tester, 'Original');
    expect(originalOption.color, colors.surfaceRaised);

    final originalText = tester.widget<Text>(find.text('Original'));
    expect(originalText.style?.color, colors.textPrimary);

    final compressedText = tester.widget<Text>(find.text('Compressed'));
    expect(compressedText.style?.color, colors.textSecondary);

    final description = tester.widget<Text>(
      find.text('Full quality, larger file size. Metadata is always removed.'),
    );
    expect(description.style?.color, colors.textMuted);
  });

  testWidgets('renders "Compressed" as selected when value is compressed', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(value: ImageQualityPreference.compressed, onChanged: (_) {}),
    );

    // Find the Compressed text — it should have bold weight (w600)
    final compressedText = tester.widget<Text>(find.text('Compressed'));
    expect(compressedText.style?.fontWeight, FontWeight.w600);

    // Original text should have normal weight (w400)
    final originalText = tester.widget<Text>(find.text('Original'));
    expect(originalText.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('renders "Original" as selected when value is original', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(value: ImageQualityPreference.original, onChanged: (_) {}),
    );

    final compressedText = tester.widget<Text>(find.text('Compressed'));
    expect(compressedText.style?.fontWeight, FontWeight.w400);

    final originalText = tester.widget<Text>(find.text('Original'));
    expect(originalText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('calls onChanged(original) when tapping Original option', (
    tester,
  ) async {
    ImageQualityPreference? changed;
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.compressed,
        onChanged: (v) => changed = v,
      ),
    );

    await tester.tap(find.text('Original'));
    expect(changed, ImageQualityPreference.original);
  });

  testWidgets('calls onChanged(compressed) when tapping Compressed option', (
    tester,
  ) async {
    ImageQualityPreference? changed;
    await tester.pumpWidget(
      wrap(
        value: ImageQualityPreference.original,
        onChanged: (v) => changed = v,
      ),
    );

    await tester.tap(find.text('Compressed'));
    expect(changed, ImageQualityPreference.compressed);
  });
}
