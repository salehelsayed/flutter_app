import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_send.dart';
import 'package:flutter_app/features/stickers/application/sticker_media.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('a cached chat sticker stops when it leaves the viewport', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    final directory = Directory.systemTemp.createTempSync('chat-sticker-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final animation = img.Image(width: 8, height: 8, frameDuration: 80)
      ..clear(img.ColorRgb8(255, 0, 0))
      ..addFrame(
        img.Image(width: 8, height: 8, frameDuration: 80)
          ..clear(img.ColorRgb8(0, 0, 255)),
      );
    final bytes = img.WebPEncoder().encode(animation);
    final file = File('${directory.path}/sticker.webp')
      ..writeAsBytesSync(bytes);
    final media = MediaAttachment(
      id: 'animated-sticker',
      messageId: 'message',
      mime: 'image/webp',
      size: bytes.length,
      mediaType: 'image',
      width: 8,
      height: 8,
      localPath: file.path,
      downloadStatus: 'done',
      createdAt: '2026-01-01T10:00:00Z',
      stickerId: kCustomStickerMarkerId,
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const stickerKey = ValueKey('animated-chat-sticker');
    const viewportKey = ValueKey('chat-sticker-viewport');

    await tester.runAsync(loadBundledStickerCatalog).timeout(bound);
    await tester
        .pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 180,
                  child: ListView.builder(
                    key: viewportKey,
                    controller: scroll,
                    itemCount: 3,
                    itemBuilder: (_, index) => switch (index) {
                      0 => const SizedBox(height: 220),
                      1 => LetterCard(
                        key: stickerKey,
                        senderPeerId: 'peer-a',
                        senderName: 'Alice',
                        text: '',
                        time: '10:00',
                        isIncoming: true,
                        media: [media],
                        bubbleLayout: true,
                      ),
                      _ => const SizedBox(height: 300),
                    },
                  ),
                ),
              ),
            ),
          ),
        )
        .timeout(bound);
    final sticker = find.byKey(stickerKey, skipOffstage: false);
    final viewport = find.byKey(viewportKey);
    final mediaCell = find.byKey(
      const ValueKey('media-grid-cell-message-animated-sticker'),
      skipOffstage: false,
    );
    final pixels = find.descendant(
      of: mediaCell,
      matching: find.byType(RawImage, skipOffstage: false),
      skipOffstage: false,
    );

    Future<int> observeFrameChanges() async {
      var changes = 0;
      var previous = tester.widgetList<RawImage>(pixels).firstOrNull?.image;
      for (var sample = 0; sample < 24; sample++) {
        await tester
            .runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 8)),
            )
            .timeout(bound);
        await tester.pump(const Duration(milliseconds: 12)).timeout(bound);
        final current = tester.widgetList<RawImage>(pixels).firstOrNull?.image;
        if (current != null &&
            previous != null &&
            !identical(current, previous)) {
          changes++;
        }
        previous = current;
      }
      return changes;
    }

    scroll.jumpTo(220);
    await tester.pump().timeout(bound);
    expect(
      tester.getRect(viewport).overlaps(tester.getRect(mediaCell)),
      isTrue,
    );
    expect(await observeFrameChanges().timeout(bound), greaterThan(0));

    scroll.jumpTo(0);
    await tester.pump().timeout(bound);
    expect(sticker, findsOneWidget, reason: 'the scroll cache retains the row');
    expect(
      tester.getRect(viewport).overlaps(tester.getRect(mediaCell)),
      isFalse,
    );
    expect(
      await observeFrameChanges().timeout(bound),
      lessThanOrEqualTo(1),
      reason: 'An offscreen chat sticker must not keep advancing frames.',
    );
    await tester.pumpWidget(const SizedBox.shrink()).timeout(bound);
  });
}
