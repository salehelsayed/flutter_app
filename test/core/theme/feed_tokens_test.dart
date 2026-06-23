import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';

void main() {
  // TC-10 (§9): FeedTokens ThemeExtension resolves the spec tokens + lerp.
  testWidgets(
    'FeedTokens is registered on AppTheme.darkTheme and resolves all spec tokens',
    (tester) async {
      late FeedTokens viaExtension;
      late FeedTokens viaGetter;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              viaExtension = Theme.of(context).extension<FeedTokens>()!;
              viaGetter = context.feedTokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Same instance both ways (the `?? FeedTokens.dark` getter fallback path
      // must not mask a missing registration).
      expect(viaGetter, same(viaExtension));

      // Colors / fills.
      expect(viaExtension.teal400, isA<Color>());
      expect(viaExtension.tealFill08, isA<Color>());
      expect(viaExtension.green500, isA<Color>());
      expect(viaExtension.greenFill15, isA<Color>());
      // Surfaces.
      expect(viaExtension.surfaceSubtle, isA<Color>());
      expect(viaExtension.surfaceRaised, isA<Color>());
      expect(viaExtension.borderSoft, isA<Color>());
      expect(viaExtension.canvas, isA<Color>());
      // Blur sigmas.
      expect(viaExtension.blurLetter, greaterThan(0));
      expect(viaExtension.blurNav, greaterThan(0));
      // Geometry.
      expect(viaExtension.radiusFull, 16.0);
      expect(viaExtension.space3, greaterThan(0));
      // Typography (AppText folded in).
      expect(viaExtension.textMessage, isA<TextStyle>());
      expect(viaExtension.leadingMessage, greaterThan(1.0));
      expect(viaExtension.textMeta, isA<TextStyle>());
    },
  );

  test('FeedTokens.lerp interpolates a representative token', () {
    const a = FeedTokens.dark;
    final b = a.copyWith(
      teal400: const Color(0xFF000000),
      blurLetter: a.blurLetter + 10,
    );

    final mid = a.lerp(b, 0.5);

    expect(mid.teal400, Color.lerp(a.teal400, b.teal400, 0.5));
    expect(mid.blurLetter, closeTo(a.blurLetter + 5, 0.001));
  });

  test('FeedTokens.lerp returns this when other is not FeedTokens', () {
    const a = FeedTokens.dark;
    expect(a.lerp(null, 0.5), same(a));
  });
}
