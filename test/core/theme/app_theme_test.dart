import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/core/widgets/undo_bar.dart';
import 'package:flutter_app/core/widgets/video_processing_notice.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
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

  group('AppTheme.darkTheme', () {
    testWidgets('dark snackbar action contrast for default retry', (
      tester,
    ) async {
      var retryCount = 0;
      await _pumpSnackBar(tester, (context) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Couldn't transcribe"),
            action: SnackBarAction(
              label: 'Try again',
              onPressed: () => retryCount += 1,
            ),
          ),
        );
      });

      _expectReadableSnackBarAction(tester);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(retryCount, 1);
    });

    testWidgets('dark snackbar action contrast for video retry notice', (
      tester,
    ) async {
      var retryCount = 0;
      await _pumpSnackBar(tester, (context) {
        showVideoProcessingNotice(
          context,
          message: 'Video stopped',
          retryLabel: 'Retry',
          onRetry: () => retryCount += 1,
        );
      });

      _expectReadableSnackBarAction(tester);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(retryCount, 1);
    });

    testWidgets('dark snackbar action contrast for undo', (tester) async {
      var undoCount = 0;
      var commitCount = 0;
      late UndoBarHandle handle;
      await _pumpSnackBar(tester, (context) {
        handle = showUndoBar(
          context,
          message: 'Invite declined',
          window: const Duration(seconds: 4),
          onUndo: () => undoCount += 1,
          onCommit: () {
            commitCount += 1;
          },
        );
      });
      addTearDown(handle.cancel);

      _expectReadableSnackBarAction(tester);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(undoCount, 1);
      expect(commitCount, 0);
    });
  });
}

Future<void> _pumpSnackBar(
  WidgetTester tester,
  void Function(BuildContext) show,
) async {
  late BuildContext snackBarContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            snackBarContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  show(snackBarContext);
  await tester.pumpAndSettle();
}

void _expectReadableSnackBarAction(WidgetTester tester) {
  final actionText = tester.widget<RichText>(
    find.descendant(
      of: find.byType(SnackBarAction),
      matching: find.byType(RichText),
    ),
  );
  final background = tester
      .widget<Material>(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      )
      .color!;
  final foreground = Color.alphaBlend(
    actionText.text.style!.color!,
    background,
  );
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final contrast = (lighter + 0.05) / (darker + 0.05);

  expect(
    contrast,
    greaterThanOrEqualTo(4.5),
    reason:
        'Rendered action $foreground on SnackBar $background must meet '
        'WCAG AA text contrast; got ${contrast.toStringAsFixed(2)}:1.',
  );
}
