import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_quote_block.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../shared/bidi_layout_checks.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  late File photo;

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('thought-quote-');
    addTearDown(() => directory.deleteSync(recursive: true));
    photo = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
  });

  Future<void> pumpQuote(
    WidgetTester tester,
    ThoughtQuotePreview preview, {
    TextDirection appDirection = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: appDirection, child: child!),
      home: Scaffold(
        body: ThoughtQuoteBlock(
          label: "Bob's thought",
          preview: preview,
          now: now,
          unavailableText: 'No longer available',
          mediaLabel: (_) => 'Photo',
        ),
      ),
    ),
  );

  testWidgets('a quoted photo thought shows the photo itself', (tester) async {
    await pumpQuote(
      tester,
      ThoughtQuotePreview(
        text: 'Sunset at the lake?',
        mediaKind: 'image',
        expiresAt: now.add(const Duration(hours: 2)),
        imagePath: photo.path,
      ),
    );

    final thumbnail = tester.widget<Image>(
      find.byKey(const ValueKey('thought-quote-photo')),
    );
    expect((thumbnail.image as ResizeImage).imageProvider, FileImage(photo));
    expect(find.byIcon(Icons.photo_outlined), findsNothing);
    expect(find.text('Sunset at the lake?'), findsOneWidget);
  });

  testWidgets('a photo not on this phone yet shows the photo icon', (
    tester,
  ) async {
    await pumpQuote(
      tester,
      ThoughtQuotePreview(
        text: '',
        mediaKind: 'image',
        expiresAt: now.add(const Duration(hours: 2)),
      ),
    );

    expect(find.byKey(const ValueKey('thought-quote-photo')), findsNothing);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
  });

  testWidgets('an expired thought drops its photo with its text', (
    tester,
  ) async {
    await pumpQuote(
      tester,
      ThoughtQuotePreview(
        text: 'Sunset at the lake?',
        mediaKind: 'image',
        expiresAt: now.subtract(const Duration(minutes: 1)),
        imagePath: photo.path,
      ),
    );

    expect(find.byKey(const ValueKey('thought-quote-photo')), findsNothing);
    expect(find.text('Sunset at the lake?'), findsNothing);
    expect(find.text('No longer available'), findsOneWidget);
  });

  for (final c in bidiCases) {
    testWidgets('a chat quote of a thought lays out mixed text: ${c.label}', (
      tester,
    ) async {
      await pumpQuote(
        tester,
        ThoughtQuotePreview(
          text: c.text,
          mediaKind: 'none',
          expiresAt: now.add(const Duration(hours: 2)),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('thought-quote-text')),
      );
      expectBidiLayout(
        c,
        direction: paragraph.textDirection,
        boxes: paragraph.getBoxesForSelection,
        area: tester.getRect(
          find
              .ancestor(
                of: find.byKey(const ValueKey('thought-quote-text')),
                matching: find.byType(Column),
              )
              .first,
        ),
        toGlobal: paragraph.localToGlobal,
      );
    });
  }

  for (final appDirection in TextDirection.values) {
    for (final (text, direction) in [
      ('مرحبا 2026 🙂', TextDirection.rtl),
      ('Hello 2026 🙂', TextDirection.ltr),
    ]) {
      testWidgets('a short ${direction.name} quote sits on its own side in a '
          '${appDirection.name} app', (tester) async {
        await pumpQuote(
          tester,
          ThoughtQuotePreview(
            text: text,
            mediaKind: 'none',
            expiresAt: now.add(const Duration(hours: 2)),
          ),
          appDirection: appDirection,
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('thought-quote-text')),
        );
        expect(paragraph.textDirection, direction);
        final start = paragraph
            .localToGlobal(
              paragraph.getOffsetForCaret(
                const TextPosition(offset: 0),
                Rect.zero,
              ),
            )
            .dx;
        final area = tester.getRect(
          find
              .ancestor(
                of: find.byKey(const ValueKey('thought-quote-text')),
                matching: find.byType(Column),
              )
              .first,
        );
        expect(
          start,
          closeTo(direction == TextDirection.rtl ? area.right : area.left, 2),
        );
      });
    }
  }
}
