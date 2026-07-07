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
    expect(observed.greenFill15, const Color(0xFFDFF3E9));
    expect(observed.green500, const Color(0xFF0C7C46));
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
