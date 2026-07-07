import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/helpers/readability_test_helpers.dart';

void main() {
  test(
    'representativeLight pins the exact Signal ink and porcelain values',
    () {
      const colors = BackgroundReadableColors.representativeLight;

      expect(colors.textPrimary, const Color(0xFF16181F));
      expect(colors.textSecondary, const Color(0xFF4A4E5C));
      expect(colors.textMuted, const Color(0xFF656A79));
      expect(colors.placeholderText, const Color(0xFF6A6F7E));
      expect(colors.surfaceBase, const Color(0xFFF4F6FA));
      expect(colors.inputFill, const Color(0xFFF7F8FB));
    },
  );

  test('new Signal light tokens are exact', () {
    const colors = BackgroundReadableColors.representativeLight;

    expect(colors.accent, const Color(0xFF5A24E0));
    // Paper White: bolder neutral-ink orbit rings + OPAQUE crisp node-ring
    // colors (the old ink-violet rings + translucent node blooms washed out).
    expect(colors.ring1, const Color(0x52262A3A));
    expect(colors.ring2, const Color(0x70262A3A));
    expect(colors.nodeSelfGlow, const Color(0xFF5A24E0));
    expect(colors.nodeContactGlow, const Color(0xFFE5484D));
    expect(colors.composerHint, const Color(0xFF656A79));
    expect(colors.sendIcon, const Color(0xFF5A24E0));
    expect(colors.micIcon, const Color(0xFF5A24E0));
    expect(colors.navActive, const Color(0xFF5A24E0));
  });

  test('new dark tokens equal the transcribed HEAD literals', () {
    const colors = BackgroundReadableColors.dark;

    expect(colors.ring1, const Color(0x4081E6D9));
    expect(colors.ring2, const Color(0x33A78BFA));
    expect(colors.ringGlow, const Color(0x1481E6D9));
    expect(colors.ctaBg, const Color(0xFF1A1A2E));
    expect(colors.ctaIcon, const Color(0xFF64B5F6));
    expect(colors.ctaMenuFill, const Color(0x1AFFFFFF));
    expect(colors.ctaMenuBorder, const Color(0x26FFFFFF));
    expect(colors.composerBarColor, const Color.fromRGBO(10, 10, 15, 0.95));
    expect(colors.sendBg, const Color(0x261DB954));
    expect(colors.sendIcon, const Color(0xFF1DB954));
    expect(colors.micBg, const Color(0x261DB954));
    expect(colors.micBorder, const Color(0x4D1DB954));
    expect(colors.micShadow, const Color(0x3D1DB954));
    expect(colors.micIcon, const Color(0xFF1DB954));
    expect(colors.connectedHeading, const Color(0xFF1DB954));
    expect(colors.emptyHint, const Color(0x80FFFFFF));
    expect(colors.emptyDate, const Color(0x59FFFFFF));
    expect(colors.emptyDivider, const Color(0x1FFFFFFF));
    expect(colors.emptyAvatarGlow, const Color(0x4D4ECDC4));
    expect(colors.avatarFrameBorder, const Color(0x59FFFFFF));
    expect(colors.avatarFrameFill, const Color(0xB316181E));
    expect(colors.nodeSelfGlow, Colors.transparent);
    expect(colors.nodeContactGlow, Colors.transparent);
  });

  test('ground legibility uses the real Paper White ground', () {
    const colors = BackgroundReadableColors.representativeLight;
    const ground = Color(0xFFFFFFFF);

    expectTextContrast(colors.textSecondary, ground);
    expectTextContrast(colors.textMuted, ground);
    expectTextContrast(colors.composerHint, ground);
    expectTextContrast(colors.placeholderText, colors.inputFill);
    expectComponentContrast(colors.accentIcon, colors.accent);
    expectComponentContrast(colors.navActive, ground);
  });
}
