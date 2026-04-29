import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/helpers/readability_test_helpers.dart';

void main() {
  test(
    'current dark background preferences resolve to dark readable colors',
    () {
      for (final preference in const [
        BackgroundPreference.defaultBackground,
        BackgroundPreference.cosmic,
        BackgroundPreference.cosmicMirrored,
      ]) {
        final colors = BackgroundReadableColors.resolve(preference);

        expect(colors.textPrimary, BackgroundReadableColors.dark.textPrimary);
        expect(colors.surfaceBase, BackgroundReadableColors.dark.surfaceBase);
        expect(colors.statusBarIconBrightness, Brightness.light);
        expect(colors.navigationBarIconBrightness, Brightness.light);
      }
    },
  );

  test('daylight lagoon resolves to light readable colors', () {
    final colors = BackgroundReadableColors.resolve(
      BackgroundPreference.daylightLagoon,
    );

    expect(
      colors.textPrimary,
      BackgroundReadableColors.representativeLight.textPrimary,
    );
    expect(
      colors.surfaceBase,
      BackgroundReadableColors.representativeLight.surfaceBase,
    );
    expect(colors.statusBarIconBrightness, Brightness.dark);
    expect(colors.navigationBarIconBrightness, Brightness.dark);
  });

  test(
    'unknown stored preferences fall back to default dark readable colors',
    () {
      final preference = BackgroundPreference.fromStorageString(
        'future-unknown-background',
      );

      expect(preference, BackgroundPreference.defaultBackground);
      expect(
        BackgroundReadableColors.resolve(preference).textPrimary,
        BackgroundReadableColors.dark.textPrimary,
      );
    },
  );

  test(
    'representative light fixture uses dark foreground and system chrome',
    () {
      final colors = BackgroundReadableColors.resolve(
        BackgroundPreference.defaultBackground,
        representativeToneOverride: BackgroundReadableTone.representativeLight,
      );

      expect(
        colors.textPrimary,
        BackgroundReadableColors.representativeLight.textPrimary,
      );
      expect(colors.statusBarIconBrightness, Brightness.dark);
      expect(colors.navigationBarIconBrightness, Brightness.dark);
    },
  );

  test('system chrome style follows resolved readable colors', () {
    final darkStyle = BackgroundReadableColors.dark.systemUiOverlayStyle;
    final lightStyle =
        BackgroundReadableColors.representativeLight.systemUiOverlayStyle;

    expect(darkStyle.statusBarIconBrightness, Brightness.light);
    expect(darkStyle.systemNavigationBarIconBrightness, Brightness.light);
    expect(lightStyle.statusBarIconBrightness, Brightness.dark);
    expect(lightStyle.systemNavigationBarIconBrightness, Brightness.dark);
    expect(lightStyle.statusBarColor, Colors.transparent);
  });

  test('minimum roles pass contrast against their effective surfaces', () {
    _expectTextContrast(BackgroundReadableColors.dark);
    _expectComponentContrast(BackgroundReadableColors.dark);
    _expectTextContrast(BackgroundReadableColors.representativeLight);
    _expectComponentContrast(BackgroundReadableColors.representativeLight);
  });
}

void _expectTextContrast(BackgroundReadableColors colors) {
  expectTextContrast(colors.textPrimary, colors.surfaceBase);
  expectTextContrast(colors.textSecondary, colors.surfaceBase);
  expectTextContrast(colors.textMuted, colors.surfaceBase);
  expectTextContrast(colors.placeholderText, colors.inputFill);
}

void _expectComponentContrast(BackgroundReadableColors colors) {
  expectComponentContrast(colors.iconPrimary, colors.surfaceBase);
  expectComponentContrast(colors.iconSecondary, colors.surfaceBase);
  expectComponentContrast(colors.iconMuted, colors.surfaceBase);
  expectComponentContrast(colors.border, colors.surfaceBase);
  expectComponentContrast(colors.inputBorder, colors.inputFill);
  expectComponentContrast(colors.disabledForeground, colors.disabledSurface);
}
