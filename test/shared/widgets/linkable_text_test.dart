import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  /// Navigate past the DefaultTextStyle wrapper to our actual spans.
  List<TextSpan> findSpans(WidgetTester tester) {
    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    final outer = richText.text as TextSpan;
    final inner = outer.children![0] as TextSpan;
    return inner.children!.whereType<TextSpan>().toList();
  }

  RichText findLinkableRichText(WidgetTester tester) {
    return tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
  }

  group('LinkableText', () {
    testWidgets('plain text renders normally', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'Hello world'),
      ));
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('URL text renders within widget', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'Visit https://example.com today'),
      ));
      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.textContaining('https://example.com'), findsOneWidget);
    });

    testWidgets('prefix spans render before body text', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(
          text: 'Hello world',
          prefixSpans: [TextSpan(text: 'Alice: ')],
        ),
      ));
      expect(find.textContaining('Alice: '), findsOneWidget);
      expect(find.textContaining('Hello world'), findsOneWidget);
    });

    testWidgets('custom style applied to plain text spans', (tester) async {
      const style = TextStyle(fontSize: 20, color: Colors.red);
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'Plain text', style: style),
      ));
      final spans = findSpans(tester);
      final plainSpan = spans.first;
      expect(plainSpan.style?.fontSize, 20);
      expect(plainSpan.style?.color, Colors.red);
    });

    testWidgets('URL spans get underline decoration', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'https://example.com'),
      ));
      final spans = findSpans(tester);
      final urlSpan = spans.first;
      expect(urlSpan.style?.decoration, TextDecoration.underline);
    });

    testWidgets('URL spans use teal color', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'https://example.com'),
      ));
      final spans = findSpans(tester);
      final urlSpan = spans.first;
      expect(urlSpan.style?.color, const Color(0xFF81e6d9));
    });

    testWidgets('empty text renders without error', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: ''),
      ));
      expect(find.byType(LinkableText), findsOneWidget);
    });

    testWidgets('maxLines and overflow respected', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(
          text: 'Some text',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ));
      final richText = findLinkableRichText(tester);
      expect(richText.maxLines, 2);
      expect(richText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('onLinkTap fires with correct URL string', (tester) async {
      String? tappedUrl;
      await tester.pumpWidget(wrap(
        LinkableText(
          text: 'Visit https://example.com today',
          onLinkTap: (url) => tappedUrl = url,
        ),
      ));

      final spans = findSpans(tester);
      final urlSpan = spans.firstWhere((s) => s.recognizer != null);
      (urlSpan.recognizer! as TapGestureRecognizer).onTap!();

      expect(tappedUrl, 'https://example.com');
    });

    testWidgets('multiple URLs fire distinct callbacks', (tester) async {
      final tappedUrls = <String>[];
      await tester.pumpWidget(wrap(
        LinkableText(
          text: 'https://a.com and https://b.com',
          onLinkTap: (url) => tappedUrls.add(url),
        ),
      ));

      final urlSpans = findSpans(tester)
          .where((s) => s.recognizer != null)
          .toList();

      expect(urlSpans, hasLength(2));
      (urlSpans[0].recognizer! as TapGestureRecognizer).onTap!();
      (urlSpans[1].recognizer! as TapGestureRecognizer).onTap!();

      expect(tappedUrls, ['https://a.com', 'https://b.com']);
    });

    testWidgets('plain text spans have no gesture recognizer', (tester) async {
      await tester.pumpWidget(wrap(
        const LinkableText(text: 'Just plain text'),
      ));

      for (final span in findSpans(tester)) {
        expect(span.recognizer, isNull);
      }
    });

    testWidgets('re-parses when text prop changes', (tester) async {
      String? tappedUrl;
      await tester.pumpWidget(wrap(
        LinkableText(
          text: 'Visit https://a.com',
          onLinkTap: (url) => tappedUrl = url,
        ),
      ));

      await tester.pumpWidget(wrap(
        LinkableText(
          text: 'Visit https://b.com',
          onLinkTap: (url) => tappedUrl = url,
        ),
      ));

      final urlSpan = findSpans(tester)
          .firstWhere((s) => s.recognizer != null);
      (urlSpan.recognizer! as TapGestureRecognizer).onTap!();

      expect(tappedUrl, 'https://b.com');
    });
  });
}
