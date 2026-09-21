import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

final Uint8List _tinyPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x00,
  0x02,
  0x00,
  0x01,
  0xE2,
  0x21,
  0xBC,
  0x33,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

MediaAttachment _makeMedia(int i) {
  return MediaAttachment(
    id: 'media-$i',
    messageId: 'msg-1',
    mime: 'image/jpeg',
    size: 1024,
    mediaType: 'image',
    downloadStatus: 'done',
    createdAt: '2024-01-01T00:00:00Z',
  );
}

MediaAttachment _makeVideoMedia(String videoPath) {
  return MediaAttachment(
    id: 'video-1',
    messageId: 'msg-1',
    mime: 'video/mp4',
    size: 2048,
    mediaType: 'video',
    localPath: videoPath,
    downloadStatus: 'done',
    createdAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late Directory tempDir;
  late String videoPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_grid_test_');
    videoPath = '${tempDir.path}/clip.mp4';
    await File(videoPath).writeAsBytes(const [0x00, 0x00, 0x00, 0x18]);
    await File(derivedVideoThumbnailPath(videoPath)).writeAsBytes(_tinyPng);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('MediaGrid', () {
    for (final locale in ['en', 'de', 'ar']) {
      for (final width in [320.0, 360.0]) {
        for (final brightness in Brightness.values) {
          testWidgets(
            'R1 full grid retry $locale ${width.toInt()} $brightness at 2x',
            (tester) async {
              final semantics = tester.ensureSemantics();
              try {
                final retried = <String>[];
                final opened = <int>[];
                await tester.pumpWidget(
                  MaterialApp(
                    locale: Locale(locale),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: ThemeData(
                      brightness: brightness,
                      extensions: [
                        brightness == Brightness.light
                            ? BackgroundReadableColors.representativeLight
                            : BackgroundReadableColors.dark,
                      ],
                    ),
                    home: Scaffold(
                      body: MediaQuery(
                        data: const MediaQueryData(
                          textScaler: TextScaler.linear(2),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: width,
                            child: MediaGrid(
                              media: List.generate(
                                2,
                                (i) => _makeMedia(
                                  i,
                                ).copyWith(downloadStatus: 'failed'),
                              ),
                              onTap: opened.add,
                              onRetryUnavailableMedia: (item) =>
                                  retried.add(item.id),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                expect(tester.takeException(), isNull);
                final l10n = AppLocalizations.of(
                  tester.element(find.byType(MediaGrid)),
                )!;
                expect(find.text(l10n.btn_retry), findsNWidgets(2));
                expect(
                  find.semantics.byLabel(l10n.media_retry_unavailable),
                  findsNWidgets(2),
                );
                expect(
                  retried,
                  isEmpty,
                  reason: 'build never dispatches retry',
                );
                for (var i = 0; i < 2; i++) {
                  final tile = find.byKey(
                    ValueKey('media-grid-cell-msg-1-media-$i'),
                  );
                  final button = find.byKey(
                    ValueKey('unavailable-media-retry-msg-1-media-$i'),
                  );
                  final label = find.descendant(
                    of: button,
                    matching: find.text(l10n.btn_retry),
                  );
                  final tileRect = tester.getRect(tile);
                  final buttonRect = tester.getRect(button);
                  expect(tileRect.width, closeTo((width - 3) / 2, 0.01));
                  expect(tileRect.height, tileRect.width);
                  expect(buttonRect.width, greaterThanOrEqualTo(48));
                  expect(buttonRect.height, greaterThanOrEqualTo(48));
                  expect(tileRect.intersect(buttonRect), buttonRect);
                  final paragraph = tester.renderObject<RenderParagraph>(label);
                  expect(paragraph.text.toPlainText(), l10n.btn_retry);
                  expect(paragraph.didExceedMaxLines, isFalse);
                  expect(paragraph.maxLines, isNull);
                  expect(paragraph.textScaler.scale(14), 28);
                  expect(paragraph.text.style!.fontSize, 14);
                  // Every glyph must be laid out and painted inside the action
                  // and tile. A passing RenderFlex assertion alone misses clips.
                  final paragraphRect = tester.getRect(label);
                  expect(buttonRect.intersect(paragraphRect), paragraphRect);
                  for (var char = 0; char < l10n.btn_retry.length; char++) {
                    if (l10n.btn_retry[char] == ' ') continue;
                    final boxes = paragraph.getBoxesForSelection(
                      TextSelection(baseOffset: char, extentOffset: char + 1),
                    );
                    expect(boxes, isNotEmpty);
                    for (final box in boxes) {
                      final rect = box.toRect().shift(
                        paragraph.localToGlobal(Offset.zero),
                      );
                      expect(
                        paragraphRect.inflate(0.01).contains(rect.topLeft),
                        isTrue,
                      );
                      expect(
                        paragraphRect.inflate(0.01).contains(rect.bottomRight),
                        isTrue,
                      );
                      expect(
                        buttonRect.inflate(0.01).contains(rect.topLeft),
                        isTrue,
                      );
                      expect(
                        buttonRect.inflate(0.01).contains(rect.bottomRight),
                        isTrue,
                      );
                    }
                  }
                  final node = tester.getSemantics(button);
                  expect(node.label, l10n.media_retry_unavailable);
                  expect(
                    node.getSemanticsData().hasAction(SemanticsAction.tap),
                    isTrue,
                  );
                  expect(
                    node.getSemanticsData().flagsCollection.isButton,
                    isTrue,
                  );
                  await tester.tap(label);
                  expect(
                    retried,
                    List.generate(i * 3 + 1, (n) => 'media-${n ~/ 3}'),
                  );
                  // The target's edge must also hit this action, not its neighbor.
                  await tester.tapAt(
                    buttonRect.centerLeft + const Offset(4, 0),
                  );
                  tester.semantics.tap(
                    find.semantics.byLabel(l10n.media_retry_unavailable).at(i),
                  );
                  expect(
                    retried,
                    List.generate((i + 1) * 3, (n) => 'media-${n ~/ 3}'),
                  );
                  expect(opened, isEmpty);
                  await tester.pump();
                  expect(tester.takeException(), isNull);
                }
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }

    testWidgets('renders single item with 4:3 AspectRatio', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(AspectRatio), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, closeTo(4 / 3, 0.01));
    });

    testWidgets('renders 2 items side by side', (tester) async {
      await tester.pumpWidget(
        wrap(MediaGrid(media: [_makeMedia(0), _makeMedia(1)])),
      );
      // 2 items each with 1:1 aspect ratio
      final aspects = tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(aspects.length, 2);
    });

    testWidgets('renders ClipRRect container', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('renders empty SizedBox when media is empty', (tester) async {
      await tester.pumpWidget(wrap(const MediaGrid(media: [])));
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets(
      'renders generated thumbnail for downloaded video attachments',
      (tester) async {
        await tester.pumpWidget(
          wrap(MediaGrid(media: [_makeVideoMedia(videoPath)])),
        );
        await tester.pump();

        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      },
    );
  });
}
