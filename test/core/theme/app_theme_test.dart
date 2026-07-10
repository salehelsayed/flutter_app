import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme.lightTheme', () {
    test(
      'light theme exposes the locked warm ColorScheme and light extensions',
      () {
        final theme = AppTheme.lightTheme;

        // Brightness is genuinely light (inert scaffold delegates to darkTheme
        // and is dark → RED here until the real light theme lands).
        expect(theme.brightness, Brightness.light);

        // Warm mineral scaffold ground; pure white is forbidden.
        expect(theme.scaffoldBackgroundColor, const Color(0xFFECE8E1));

        // Locked Material ColorScheme.
        final scheme = theme.colorScheme;
        expect(scheme.brightness, Brightness.light);
        expect(scheme.primary, const Color(0xFF6045B6));
        expect(scheme.onPrimary, const Color(0xFFFFFFFF));
        expect(scheme.secondary, const Color(0xFF2F7755));
        expect(scheme.onSecondary, const Color(0xFFFFFFFF));
        expect(scheme.surface, const Color(0xFFFAF8F3));
        expect(scheme.onSurface, const Color(0xFF25222B));
        expect(scheme.error, const Color(0xFFB4232F));
        expect(scheme.onError, const Color(0xFFFFFFFF));
        expect(scheme.outline, const Color(0xFF8D83A8));
        expect(scheme.outlineVariant, const Color(0xFFB3ACBD));
        expect(scheme.surfaceContainerHighest, const Color(0xFFE1DCE5));

        // Component defaults for pushed input / dialog / sheet / popup chrome.
        expect(theme.inputDecorationTheme.fillColor, const Color(0xFFE1DCE5));
        expect(theme.dialogTheme.backgroundColor, const Color(0xFFFAF8F3));
        expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFFFAF8F3));
        expect(theme.popupMenuTheme.color, const Color(0xFFFAF8F3));

        // Light extensions are provided at the root.
        final readable = theme.extension<BackgroundReadableColors>();
        expect(readable, isNotNull);
        expect(readable!.statusBarIconBrightness, Brightness.dark);
        expect(readable.isLightSurface, isTrue);

        final feed = theme.extension<FeedTokens>();
        expect(feed, same(FeedTokens.light));
      },
    );

    test('dark theme remains dark and literal-preserved', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, isNot(const Color(0xFFECE8E1)));
      expect(
        theme.extension<BackgroundReadableColors>()!.statusBarIconBrightness,
        Brightness.light,
      );
      expect(theme.extension<FeedTokens>(), same(FeedTokens.dark));
    });
  });
}
