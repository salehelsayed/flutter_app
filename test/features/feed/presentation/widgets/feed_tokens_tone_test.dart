import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FeedTokens.dark preserves the existing literals', () {
    const tokens = FeedTokens.dark;

    expect(tokens.teal400, const Color(0xFF2DD4BF));
    expect(tokens.tealFill08, const Color(0x142DD4BF));
    expect(tokens.green500, const Color(0xFF22C55E));
    expect(tokens.greenFill15, const Color(0x2622C55E));
    expect(tokens.surfaceSubtle, const Color(0xBF101218));
    expect(tokens.surfaceRaised, const Color(0xDB181A20));
    expect(tokens.borderSoft, const Color(0x1FFFFFFF));
    expect(tokens.canvas, const Color(0xE60A0A0F));
  });

  testWidgets('AmbientBackground appends FeedTokens.light by tone', (
    tester,
  ) async {
    late FeedTokens observed;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AmbientBackground(
          preference: BackgroundPreference.daylightLagoon,
          child: Builder(
            builder: (context) {
              observed = context.feedTokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(observed, FeedTokens.light);
    expect(observed.greenFill15, const Color(0xFFDCE9E1));
    expect(observed.green500, const Color(0xFF236143));
  });

  test('Signal Feed tokens match the locked warm hierarchy', () {
    const tokens = FeedTokens.light;

    expect(tokens.canvas, const Color(0xFFECE8E1));
    expect(tokens.surfaceRaised, const Color(0xFFFAF8F3));
    expect(tokens.surfaceSubtle, const Color(0xFFE1DCE5));
    expect(tokens.borderSoft, const Color(0xFFB3ACBD));
    expect(tokens.teal400, const Color(0xFF6045B6));
    expect(tokens.tealFill08, const Color(0x146045B6));
    // Small success text/border is full-opacity #236143, never pale/bright.
    expect(tokens.green500, const Color(0xFF236143));
    expect(tokens.greenFill15, const Color(0xFFDCE9E1));
    // Readable warm message + meta text.
    expect(tokens.textMessage.color, const Color(0xFF25222B));
    expect(tokens.textMeta.color, const Color(0xFF56515E));
    // Numeric geometry stays identical to dark.
    expect(tokens.blurLetter, FeedTokens.dark.blurLetter);
    expect(tokens.blurNav, FeedTokens.dark.blurNav);
    expect(tokens.radiusFull, FeedTokens.dark.radiusFull);
    expect(tokens.space3, FeedTokens.dark.space3);
    expect(tokens.leadingMessage, FeedTokens.dark.leadingMessage);

    // Small success text is AA on the warm canvas and its own success fill.
    for (final bg in <Color>[tokens.canvas, tokens.greenFill15]) {
      final blended = Color.alphaBlend(tokens.green500, bg);
      final lf = blended.computeLuminance();
      final lb = bg.computeLuminance();
      final ratio = (max(lf, lb) + 0.05) / (min(lf, lb) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'green500 on $bg');
    }

    // FeedTokens.dark literals are untouched.
    expect(FeedTokens.dark.green500, const Color(0xFF22C55E));
    expect(FeedTokens.dark.canvas, const Color(0xE60A0A0F));
  });

  testWidgets('AmbientBackground keeps FeedTokens.dark on dark tones', (
    tester,
  ) async {
    late FeedTokens observed;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AmbientBackground(
          preference: BackgroundPreference.defaultBackground,
          child: Builder(
            builder: (context) {
              observed = context.feedTokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(observed, FeedTokens.dark);
  });
}
