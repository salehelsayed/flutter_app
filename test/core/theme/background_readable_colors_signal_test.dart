import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/helpers/readability_test_helpers.dart';

void main() {
  const light = BackgroundReadableColors.representativeLight;
  const dark = BackgroundReadableColors.dark;
  // The Signal ground and the Feed success-bubble fill are not token fields;
  // they are the surfaces small roles are actually rendered on.
  const canvas = Color(0xFFECE8E1);
  const successFill = Color(0xFFDCE9E1);

  test(
    'representativeLight pins warm mineral roles and passes every '
    'effective-surface contrast pair',
    () {
      // Exact locked warm roles (paper-white ground/surfaces are forbidden).
      expect(light.textPrimary, const Color(0xFF25222B));
      expect(light.textSecondary, const Color(0xFF56515E));
      expect(light.textMuted, const Color(0xFF65606C));
      expect(light.surfaceBase, const Color(0xFFF4F0EA));
      expect(light.surfaceRaised, const Color(0xFFFAF8F3));
      expect(light.surfaceSubtle, const Color(0xFFE1DCE5));
      expect(light.inputFill, const Color(0xFFE1DCE5));
      expect(light.inputBorder, const Color(0xFF7C7297));
      expect(light.placeholderText, const Color(0xFF645F6A));
      expect(light.accent, const Color(0xFF6045B6));
      expect(light.connectedHeading, const Color(0xFF236143));
      expect(light.navActive, const Color(0xFF6045B6));
      expect(light.composerHint, const Color(0xFF645F6A));
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.surfaceRaised, isNot(const Color(0xFFFFFFFF)));
      expect(light.surfaceBase, isNot(const Color(0xFFF4F6FA)));

      // Normal + small muted text ≥4.5:1 on every effective surface.
      for (final bg in <Color>[
        canvas,
        light.surfaceBase,
        light.surfaceRaised,
        light.surfaceSubtle,
      ]) {
        expectTextContrast(light.textPrimary, bg);
        expectTextContrast(light.textSecondary, bg);
        expectTextContrast(light.textMuted, bg);
      }
      // Placeholder / composer hint on their lavender fill.
      expectTextContrast(light.placeholderText, light.inputFill);
      expectTextContrast(light.composerHint, light.composerInputFill);

      // Small success text is AA on canvas, subtle, and the rendered success
      // fill — never alpha-faded.
      expectTextContrast(light.connectedHeading, canvas);
      expectTextContrast(light.connectedHeading, light.surfaceSubtle);
      expectTextContrast(light.connectedHeading, successFill);

      // Filled-success white content (#2F7755 is the Material secondary).
      expectComponentContrast(
        const Color(0xFFFFFFFF),
        const Color(0xFF2F7755),
      );

      // Interactive + control borders ≥3:1 on their real control surfaces.
      expectComponentContrast(light.inputBorder, light.inputFill);
      expectComponentContrast(light.border, light.surfaceBase);
      expectComponentContrast(light.border, light.surfaceRaised);
      expectComponentContrast(light.accentIcon, light.accent);
      expectComponentContrast(light.navActive, canvas);
    },
  );

  test(
    'surface borders are soft only at decorative consumers while controls '
    'retain three-to-one borders',
    () {
      // Light: decorative surfaceBorder is softer than, and distinct from,
      // the control border / input border.
      expect(light.surfaceBorder, const Color(0xFFB3ACBD));
      expect(light.border, const Color(0xFF8D83A8));
      expect(light.inputBorder, const Color(0xFF7C7297));
      expect(light.surfaceBorder, isNot(light.border));
      expect(light.surfaceBorder, isNot(light.inputBorder));

      // Control borders keep ≥3:1; decorative surfaceBorder is intentionally
      // NOT held to a control-contrast floor.
      expectComponentContrast(light.border, light.surfaceRaised);
      expectComponentContrast(light.inputBorder, light.inputFill);

      // Dark: surfaceBorder == prior dark border, so decorative-outline
      // consumers render byte-identically on dark.
      expect(dark.surfaceBorder, const Color(0x80FFFFFF));
      expect(dark.border, const Color(0x80FFFFFF));
    },
  );

  test('dark tokens equal the transcribed HEAD literals', () {
    expect(dark.ring1, const Color(0x4081E6D9));
    expect(dark.ring2, const Color(0x33A78BFA));
    expect(dark.ringGlow, const Color(0x1481E6D9));
    expect(dark.connectedHeading, const Color(0xFF1DB954));
    expect(dark.nodeSelfGlow, Colors.transparent);
    expect(dark.nodeContactGlow, Colors.transparent);
    expect(dark.avatarFrameBorder, const Color(0x59FFFFFF));
    expect(dark.avatarFrameFill, const Color(0xB316181E));
  });
}
