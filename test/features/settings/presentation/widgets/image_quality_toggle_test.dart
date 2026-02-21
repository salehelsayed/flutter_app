import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/image_quality_toggle.dart';

void main() {
  Widget wrap({
    required ImageQualityPreference value,
    required ValueChanged<ImageQualityPreference> onChanged,
    String? label,
    IconData? icon,
  }) {
    return MaterialApp(
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

  testWidgets('renders default label "Photo Quality" when no label provided', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.compressed,
      onChanged: (_) {},
    ));

    expect(find.text('Photo Quality'), findsOneWidget);
  });

  testWidgets('renders custom label when label provided', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.compressed,
      onChanged: (_) {},
      label: 'Video Quality',
    ));

    expect(find.text('Video Quality'), findsOneWidget);
    expect(find.text('Photo Quality'), findsNothing);
  });

  testWidgets('renders custom icon when icon provided', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.compressed,
      onChanged: (_) {},
      icon: Icons.videocam,
    ));

    expect(find.byIcon(Icons.videocam), findsOneWidget);
  });

  testWidgets('renders "Compressed" as selected when value is compressed', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.compressed,
      onChanged: (_) {},
    ));

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
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.original,
      onChanged: (_) {},
    ));

    final compressedText = tester.widget<Text>(find.text('Compressed'));
    expect(compressedText.style?.fontWeight, FontWeight.w400);

    final originalText = tester.widget<Text>(find.text('Original'));
    expect(originalText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('calls onChanged(original) when tapping Original option', (
    tester,
  ) async {
    ImageQualityPreference? changed;
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.compressed,
      onChanged: (v) => changed = v,
    ));

    await tester.tap(find.text('Original'));
    expect(changed, ImageQualityPreference.original);
  });

  testWidgets('calls onChanged(compressed) when tapping Compressed option', (
    tester,
  ) async {
    ImageQualityPreference? changed;
    await tester.pumpWidget(wrap(
      value: ImageQualityPreference.original,
      onChanged: (v) => changed = v,
    ));

    await tester.tap(find.text('Compressed'));
    expect(changed, ImageQualityPreference.compressed);
  });
}
