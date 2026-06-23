import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

void main() {
  // Mount helper — dark theme registers FeedTokens.dark, so context.feedTokens
  // resolves the real token set (TC-11..TC-15b read tokens, never hardcodes).
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );

  FeedTokens tokensOf(WidgetTester tester) {
    final context = tester.element(find.byType(LetterBubble));
    return context.feedTokens;
  }

  // The single decorated bubble container that carries the BoxDecoration
  // (fill + border [+ glow]). There is exactly one in a LetterBubble.
  Container decoratedBubble(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
      description: 'Container with BoxDecoration',
    );
    expect(finder, findsOneWidget);
    return tester.widget<Container>(finder);
  }

  BoxDecoration decorationOf(WidgetTester tester) =>
      decoratedBubble(tester).decoration! as BoxDecoration;

  // The body Text rendering the letter content.
  Text bodyText(WidgetTester tester, String text) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == text,
      description: 'Text("$text")',
    );
    expect(finder, findsOneWidget);
    return tester.widget<Text>(finder);
  }

  group('LetterBubble — fill / border / glow per role', () {
    testWidgets('TC-11 incoming resting: surfaceSubtle fill + borderSoft, '
        'and a BackdropFilter is present', (tester) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(text: 'hi', role: LetterBubbleRole.incoming)),
      );
      await tester.pump();

      final tokens = tokensOf(tester);
      final decoration = decorationOf(tester);

      // Mutation: swap the fill (e.g. to surfaceRaised / greenFill15) -> red.
      expect(decoration.color, tokens.surfaceSubtle);

      // 1px borderSoft hairline.
      final border = decoration.border! as Border;
      expect(border.top.color, tokens.borderSoft);
      expect(border.top.width, 1.0);

      // No teal glow on a resting incoming bubble.
      expect(decoration.boxShadow, anyOf(isNull, isEmpty));

      // A BackdropFilter must wrap the bubble (blur).
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('TC-12 incoming focused: surfaceRaised + teal400 border + '
        'a teal-derived glow BoxShadow', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LetterBubble(
            text: 'hi',
            role: LetterBubbleRole.incoming,
            focused: true,
          ),
        ),
      );
      await tester.pump();

      final tokens = tokensOf(tester);
      final decoration = decorationOf(tester);

      expect(decoration.color, tokens.surfaceRaised);

      final border = decoration.border! as Border;
      expect(border.top.color, tokens.teal400);
      // ~1.5px focused border (thicker than the 1px resting hairline).
      expect(border.top.width, greaterThan(1.0));

      // Mutation: drop the glow -> boxShadow null/empty -> red.
      final shadows = decoration.boxShadow;
      expect(shadows, isNotNull);
      expect(shadows, isNotEmpty);
      final glow = shadows!.first;
      // Glow colour derives from teal400 (same RGB channels, reduced alpha).
      expect(glow.color.r, tokens.teal400.r);
      expect(glow.color.g, tokens.teal400.g);
      expect(glow.color.b, tokens.teal400.b);
      expect(glow.color.a, lessThan(tokens.teal400.a));
      expect(glow.blurRadius, greaterThan(8.0));
    });

    testWidgets('TC-13 outgoing: greenFill15 fill + green500 border, '
        'right-aligned', (tester) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(text: 'ok', role: LetterBubbleRole.outgoing)),
      );
      await tester.pump();

      final tokens = tokensOf(tester);
      final decoration = decorationOf(tester);

      // Mutation: use teal (tealFill08 / teal400) -> red.
      expect(decoration.color, tokens.greenFill15);
      final border = decoration.border! as Border;
      expect(border.top.color, tokens.green500);
      expect(border.top.width, 1.0);

      // Right alignment: the bubble sits inside a right-aligned container.
      final align = tester.widget<Align>(
        find
            .ancestor(
              of: find.byType(BackdropFilter),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('TC-14 system: greenFill15 fill + green500 border, '
        'left-aligned', (tester) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(
          text: 'system note',
          role: LetterBubbleRole.system,
        )),
      );
      await tester.pump();

      final tokens = tokensOf(tester);
      final decoration = decorationOf(tester);

      // Mutation: drop green (use borderSoft / surfaceSubtle) -> red.
      expect(decoration.color, tokens.greenFill15);
      final border = decoration.border! as Border;
      expect(border.top.color, tokens.green500);

      final align = tester.widget<Align>(
        find
            .ancestor(
              of: find.byType(BackdropFilter),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(align.alignment, Alignment.centerLeft);
    });
  });

  group('LetterBubble — chrome / geometry', () {
    testWidgets('TC-15 no chrome: no time text, no status-tick icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(
          // body deliberately contains a colon to prove the time-pattern
          // matcher only fires on real HH:MM, not arbitrary text.
          text: 'meeting notes: bring slides',
          role: LetterBubbleRole.outgoing,
        )),
      );
      await tester.pump();

      // Mutation: re-add Text(time) like '3:00' -> this matcher catches it.
      final timeText = find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final data = widget.data;
        if (data == null) return false;
        return RegExp(r'\d{1,2}:\d{2}').hasMatch(data);
      }, description: 'Text matching a HH:MM time pattern');
      expect(timeText, findsNothing);

      // Mutation: re-add a status tick -> caught.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('TC-15b max width: content ConstrainedBox is '
        'MediaQuery width * 0.76', (tester) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(text: 'hi', role: LetterBubbleRole.incoming)),
      );
      await tester.pump();

      final context = tester.element(find.byType(LetterBubble));
      final expected = MediaQuery.of(context).size.width * 0.76;

      // Mutation: remove ConstrainedBox / set maxWidth to a different fraction
      // (e.g. * 1.0) -> closeTo fails -> red.
      final constrained = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final match = constrained.where(
        (box) => (box.constraints.maxWidth - expected).abs() < 0.5,
      );
      expect(
        match,
        isNotEmpty,
        reason: 'a ConstrainedBox should cap content at width * 0.76 '
            '(expected ~$expected)',
      );
      expect(match.first.constraints.maxWidth, closeTo(expected, 0.5));
    });

    testWidgets('corner radius is radiusFull (16) via ClipRRect', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const LetterBubble(text: 'hi', role: LetterBubbleRole.incoming)),
      );
      await tester.pump();

      final tokens = tokensOf(tester);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(
        clip.borderRadius,
        BorderRadius.circular(tokens.radiusFull),
      );
    });
  });

  group('LetterBubble — BiDi (ported from message_bubble_test.dart)', () {
    testWidgets('TC-07 Arabic text drives RTL on body Text', (tester) async {
      const arabic = 'مرحبا بالعالم';
      await tester.pumpWidget(
        wrap(const LetterBubble(text: arabic, role: LetterBubbleRole.incoming)),
      );
      await tester.pump();

      // Mutation: force TextDirection.ltr on the body Text -> red.
      expect(bodyText(tester, arabic).textDirection, ui.TextDirection.rtl);
    });

    testWidgets('TC-07 Arabic-first mixed text drives RTL on body Text', (
      tester,
    ) async {
      const mixed = 'مرحبا Hello كيف الحال';
      await tester.pumpWidget(
        wrap(const LetterBubble(text: mixed, role: LetterBubbleRole.incoming)),
      );
      await tester.pump();

      expect(bodyText(tester, mixed).textDirection, ui.TextDirection.rtl);
    });

    testWidgets('TC-07 LTR control stays LTR', (tester) async {
      const english = 'Hello world';
      await tester.pumpWidget(
        wrap(const LetterBubble(
          text: english,
          role: LetterBubbleRole.outgoing,
        )),
      );
      await tester.pump();

      expect(bodyText(tester, english).textDirection, ui.TextDirection.ltr);
    });

    testWidgets('TC-07 English-first mixed text stays LTR', (tester) async {
      const mixed = 'Hello مرحبا 123';
      await tester.pumpWidget(
        wrap(const LetterBubble(text: mixed, role: LetterBubbleRole.outgoing)),
      );
      await tester.pump();

      expect(bodyText(tester, mixed).textDirection, ui.TextDirection.ltr);
    });
  });

  group('LetterBubble — media (parity with the 1:1 / group chat)', () {
    // MediaGrid + AudioPlayerWidget read l10n, so the media wrap registers the
    // localization delegates (the plain `wrap` above does not).
    Widget wrapMedia(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

    MediaAttachment imageAtt({String? localPath}) => MediaAttachment(
      id: 'img-1',
      messageId: 'm1',
      mime: 'image/jpeg',
      size: 1024,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-01-01T00:00:00Z',
    );

    const audioAtt = MediaAttachment(
      id: 'aud-1',
      messageId: 'm1',
      mime: 'audio/mp4',
      size: 2048,
      mediaType: 'audio',
      durationMs: 3000,
      downloadStatus: 'done',
      createdAt: '2026-01-01T00:00:00Z',
      // localPath null → the player stays unloaded (no real-file IO in tests).
    );

    testWidgets('renders a MediaGrid for an image, with the text pill as '
        'caption and onTap wired', (tester) async {
      await tester.pumpWidget(
        wrapMedia(
          LetterBubble(
            text: 'look at this',
            role: LetterBubbleRole.incoming,
            media: [imageAtt()],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MediaGrid), findsOneWidget);
      final grid = tester.widget<MediaGrid>(find.byType(MediaGrid));
      expect(grid.media, hasLength(1));
      expect(grid.onTap, isNotNull);
      // The caption pill still renders (text present → BackdropFilter blur).
      expect(find.text('look at this'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('a caption-less image renders the grid and NO empty text pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapMedia(
          LetterBubble(
            text: '',
            role: LetterBubbleRole.incoming,
            media: [imageAtt()],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MediaGrid), findsOneWidget);
      // No caption → the text pill (its BackdropFilter blur) is absent. On HEAD
      // a caption-less media message rendered an empty blurred bubble.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('renders an inline AudioPlayerWidget for a voice attachment', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapMedia(
          const LetterBubble(
            text: '',
            role: LetterBubbleRole.incoming,
            media: [audioAtt],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AudioPlayerWidget), findsOneWidget);
      expect(find.byType(MediaGrid), findsNothing);
    });

    testWidgets('group bubble forwards requireVerifiedContentHash + '
        'ownedMediaPeerId to MediaGrid', (tester) async {
      await tester.pumpWidget(
        wrapMedia(
          LetterBubble(
            text: '',
            role: LetterBubbleRole.incoming,
            media: [imageAtt()],
            requireVerifiedContentHash: true,
            ownedMediaPeerId: 'g-1',
          ),
        ),
      );
      await tester.pump();

      final grid = tester.widget<MediaGrid>(find.byType(MediaGrid));
      expect(grid.requireVerifiedContentHash, isTrue);
      expect(grid.ownedMediaPeerId, 'g-1');
    });

    // NOTE: the media TAP → FullScreenImageViewer navigation is intentionally
    // not exercised here. `LetterBubble._openMediaViewer` is a verbatim mirror
    // of the conversation/group screens' media-tap handler (already covered by
    // their tests), and driving the real push + Image.file decode inside a
    // LetterBubble widget test leaves an async image/route stream pending that
    // hangs the test harness at teardown. The onTap WIRING is locked above
    // (`expect(grid.onTap, isNotNull)`).
  });
}
