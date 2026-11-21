import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/features/stickers/application/sticker_clip_exporter.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_flow.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_overlay_editor_result.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_editor_screen.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
// The pinned video_player dependency supplies this controlled platform boundary.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../fake_custom_sticker_library.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

class _OnePhotoPicker implements MediaPicker {
  _OnePhotoPicker(this.path);

  final String path;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => XFile(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClipVideoPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  int _nextId = 0;
  final volumes = <double>[];
  final looping = <bool>[];
  final disposed = <int>[];
  var plays = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++_nextId;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final initialized = VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: const Size(1080, 1920),
    );
    // Native player events stay open until the player is released.
    final events = StreamController<VideoEvent>(
      onListen: () => _events[playerId]!.add(initialized),
      onCancel: () async {},
    );
    _events[playerId] = events;
    return events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool value) async => looping.add(value);

  @override
  Future<void> setVolume(int playerId, double value) async =>
      volumes.add(value);

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    final events = _events.remove(playerId);
    if (events != null) {
      await events.close().timeout(const Duration(seconds: 2));
    }
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blue);
}

final class _GatedClipLibrary extends FakeCustomStickerLibrary {
  _GatedClipLibrary(this.bound);

  final Duration bound;
  final release = Completer<void>();
  bool started = false;

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) async {
    started = true;
    await release.future.timeout(bound);
    return super.admit(asset);
  }
}

Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  for (final crop in [
    const Rect.fromLTRB(0, 0.21875, 1, 0.78125),
    const Rect.fromLTRB(0.25, 0, 0.75, 1),
    const Rect.fromLTRB(0.1, 0.2, 0.6, 0.7),
  ]) {
    testWidgets('clip text preview maps the exact selected crop $crop', (
      tester,
    ) async {
      const viewportKey = Key('clip-viewport');
      const sourceKey = Key('clip-source');
      await tester
          .pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox.square(
                  key: viewportKey,
                  dimension: 200,
                  child: StickerClipPreview(
                    crop: crop,
                    child: const ColoredBox(key: sourceKey, color: Colors.blue),
                  ),
                ),
              ),
            ),
          )
          .timeout(const Duration(seconds: 2));

      final viewport = tester.getRect(find.byKey(viewportKey));
      final source = tester.getRect(find.byKey(sourceKey));
      final selected = Rect.fromLTRB(
        source.left + source.width * crop.left,
        source.top + source.height * crop.top,
        source.left + source.width * crop.right,
        source.top + source.height * crop.bottom,
      );
      expect(selected.left, moreOrLessEquals(viewport.left));
      expect(selected.top, moreOrLessEquals(viewport.top));
      expect(selected.right, moreOrLessEquals(viewport.right));
      expect(selected.bottom, moreOrLessEquals(viewport.bottom));
    });
  }

  testWidgets(
    'clip text route reuses the editor and owns a muted looping player',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final video = _ClipVideoPlatform();
      VideoPlayerPlatform.instance = video;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      StickerOverlayEditorResult? result;
      await tester
          .pumpWidget(
            _app(
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => unawaited(
                      Navigator.of(context)
                          .push<StickerOverlayEditorResult>(
                            MaterialPageRoute(
                              builder: (_) => const StickerClipTextScreen(
                                clipPath: '/tmp/owned-sticker-clip.mp4',
                                crop: (
                                  crop: Rect.fromLTRB(0, 0.21875, 1, 0.78125),
                                  circle: true,
                                ),
                              ),
                            ),
                          )
                          .then((value) {
                            result = value;
                          }),
                    ),
                    child: const Text('open clip text'),
                  ),
                ),
              ),
            ),
          )
          .timeout(const Duration(seconds: 2));
      await tester
          .tap(find.text('open clip text'))
          .timeout(const Duration(seconds: 2));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );

      expect(find.byType(StickerTextEditorScreen), findsOneWidget);
      expect(find.byIcon(Icons.text_fields), findsOneWidget);
      expect(video.volumes.last, 0);
      expect(video.looping.last, isTrue);
      expect(video.plays, 1);
      expect(video.disposed, isEmpty);
      await tester
          .tap(find.byTooltip('Cancel'))
          .timeout(const Duration(seconds: 2));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      expect(result, isA<StickerOverlayEditorCancelled>());
      // Observe player release at the platform boundary after the route pops.
      for (var i = 0; i < 40 && video.disposed.isEmpty; i++) {
        await tester
            .pump(const Duration(milliseconds: 20))
            .timeout(const Duration(seconds: 2));
      }
      expect(
        find.byType(StickerClipTextScreen, skipOffstage: false),
        findsNothing,
      );
      expect(video.disposed, [1]);
    },
  );

  if (kCustomStickersEnabled) {
    for (final result in ['ready', 'failed', 'scope replaced']) {
      testWidgets('video save opens a pending tray item, then $result', (
        tester,
      ) async {
        const bound = Duration(seconds: 3);
        final root = Directory.systemTemp.createTempSync('stk-clip-pending-');
        addTearDown(() => root.deleteSync(recursive: true));
        final input = File('${root.path}/clip.mp4')..writeAsBytesSync([1]);
        final original = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = _ClipVideoPlatform();
        addTearDown(() => VideoPlayerPlatform.instance = original);
        const channel = MethodChannel('mknoon/custom_sticker_clip_frames');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final release = Completer<void>();
        final library = _GatedClipLibrary(bound);
        if (result == 'failed') {
          library.admitError = const CustomStickerException(
            CustomStickerErrorCode.storageFailure,
          );
        }
        final opened = ValueNotifier(true);
        final scopeGeneration = ValueNotifier(0);
        addTearDown(opened.dispose);
        addTearDown(scopeGeneration.dispose);
        final sent = <String>[];
        var extracts = 0;
        var cancelled = 0;
        var finished = false;
        var chats = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') {
            cancelled++;
            return null;
          }
          expect(call.method, 'extract');
          extracts++;
          await release.future.timeout(bound);
          if (result == 'scope replaced') {
            throw PlatformException(code: 'cancelled');
          }
          final args = call.arguments as Map;
          final bytes = Uint8List(512 * 512 * 4 * 2);
          for (var offset = 0; offset < bytes.length; offset += 4) {
            bytes[offset] = offset < bytes.length ~/ 2 ? 45 : 145;
            bytes[offset + 3] = 255;
          }
          File(args['framesPath'] as String).writeAsBytesSync(bytes);
          return {'durationMs': 160, 'frameCount': 2};
        });
        addTearDown(() {
          if (!release.isCompleted) release.complete();
          if (!library.release.isCompleted) library.release.complete();
          messenger.setMockMethodCallHandler(channel, null);
        });
        final catalog = StickerCatalog.parse(
          '{"packs":[]}',
          includeTestOnly: false,
        );
        await tester
            .pumpWidget(
              _app(
                ValueListenableBuilder<int>(
                  valueListenable: scopeGeneration,
                  builder: (_, generation, _) => CustomStickerScope(
                    key: ValueKey(generation),
                    library: library,
                    child: Scaffold(
                      body: Column(
                        children: [
                          TextButton(
                            onPressed: () => chats++,
                            child: const Text('Chat action'),
                          ),
                          TextButton(
                            onPressed: () => opened.value = !opened.value,
                            child: const Text('Toggle tray'),
                          ),
                        ],
                      ),
                      bottomNavigationBar: ValueListenableBuilder<bool>(
                        valueListenable: opened,
                        builder: (context, show, _) {
                          if (!show) return const SizedBox.shrink();
                          final source = myStickersFromScope(
                            context,
                            onSend: sent.add,
                          )!;
                          return StickerPanel(
                            catalog: catalog,
                            recentIds: const [],
                            onSend: (_) {},
                            myStickers: MyStickersSource(
                              library: source.library,
                              clipSaves: source.clipSaves,
                              onSend: source.onSend,
                              onCreate: () => unawaited(
                                openStickerCreate(
                                  context,
                                  library: source.library,
                                  clipSaves: source.clipSaves,
                                  captureClipPath: (_) async => input.path,
                                  exporter: StickerClipExporter(
                                    temporaryDirectory: () async => root,
                                  ),
                                  temporaryDirectory: () async => root,
                                ).whenComplete(() => finished = true),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            )
            .timeout(bound);

        Future<void> settle() => tester
            .pumpAndSettle(
              const Duration(milliseconds: 50),
              EnginePhase.sendSemanticsUpdate,
              bound,
            )
            .then((_) {});
        Future<void> until(bool Function() condition) async {
          final elapsed = Stopwatch()..start();
          while (!condition() && elapsed.elapsed < bound) {
            await tester
                .runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 10)),
                )
                .timeout(bound);
            await tester.pump(const Duration(milliseconds: 10)).timeout(bound);
          }
          expect(condition(), isTrue);
        }

        const pending = ValueKey('my-sticker-pending');
        const ready = ValueKey('my-sticker-custom-1');
        final mine = find.byKey(const ValueKey('sticker-tab-mine'));
        await tester.tap(mine).timeout(bound);
        await settle();
        await tester
            .tap(find.byKey(const ValueKey('my-sticker-create')))
            .timeout(bound);
        await settle();
        await tester.tap(find.text('Record clip')).timeout(bound);
        await settle();
        await tester.tap(find.text('Crop')).timeout(bound);
        await settle();
        await tester.tap(find.text('Save sticker')).timeout(bound);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 350)).timeout(bound);
        expect(find.text('Save sticker').hitTestable(), findsNothing);
        expect(find.byKey(pending), findsOneWidget);
        final pendingSemantics = tester.widget<Semantics>(find.byKey(pending));
        expect(pendingSemantics.properties.label, 'Creating sticker…');
        expect(pendingSemantics.properties.onTap, isNull);
        expect(library.ids, isEmpty);
        await tester
            .tap(find.byKey(pending), warnIfMissed: false)
            .timeout(bound);
        expect(sent, isEmpty);
        await tester.tap(find.text('Chat action')).timeout(bound);
        expect(chats, 1);
        await until(() => extracts == 1);

        if (result == 'scope replaced') {
          scopeGeneration.value++;
          await tester.pump().timeout(bound);
          await tester.tap(mine).timeout(bound);
          await tester.pump().timeout(bound);
          expect(find.byKey(pending), findsNothing);
          await until(() => cancelled == 1);
        } else {
          await tester.tap(find.text('Toggle tray')).timeout(bound);
          await tester.pump().timeout(bound);
          expect(find.byKey(pending), findsNothing);
          await tester.tap(find.text('Toggle tray')).timeout(bound);
          await tester.pump().timeout(bound);
          expect(find.byKey(pending), findsOneWidget);
        }

        release.complete();
        if (result != 'scope replaced') {
          await until(() => library.started);
          expect(find.byKey(pending), findsOneWidget);
          expect(find.byKey(ready), findsNothing);
          library.release.complete();
        }
        await until(() => finished);
        await tester.pump(const Duration(milliseconds: 350)).timeout(bound);
        expect(input.existsSync(), isFalse);
        expect(find.byKey(pending), findsNothing);
        if (result == 'ready') {
          expect(find.byKey(ready), findsOneWidget);
          expect(library.ids, ['custom-1']);
          await tester.tap(find.byKey(ready)).timeout(bound);
          expect(sent, ['custom-1']);
        } else {
          expect(library.ids, isEmpty);
          expect(find.byKey(ready), findsNothing);
          expect(
            find.text("Couldn't save this sticker. Try again."),
            result == 'failed' ? findsOneWidget : findsNothing,
          );
        }
      });
    }
  }

  group('centeredSquareCrop', () {
    test('a portrait frame keeps the full width, centred vertically', () {
      expect(
        centeredSquareCrop(const Size(1080, 1920)),
        const Rect.fromLTRB(0, 0.21875, 1, 0.78125),
      );
    });

    test('a landscape frame keeps the full height, centred horizontally', () {
      expect(
        centeredSquareCrop(const Size(2000, 1000)),
        const Rect.fromLTRB(0.25, 0, 0.75, 1),
      );
    });
  });

  group('deleteStickerTemp', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('stk-del-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('deletes a plain file and keeps its folder', () async {
      final file = File('${root.path}/photo.jpg')..writeAsBytesSync([1]);

      await deleteStickerTemp(file.path);

      expect(file.existsSync(), isFalse);
      expect(root.existsSync(), isTrue);
    });

    test('deletes a clip export job folder with its poster', () async {
      final job = Directory('${root.path}/mknoon-sticker-animation-abc')
        ..createSync();
      final webp = File('${job.path}/sticker.webp')..writeAsBytesSync([1]);
      File('${job.path}/poster.png').writeAsBytesSync([2]);

      await deleteStickerTemp(webp.path);

      expect(job.existsSync(), isFalse);
    });

    test('a missing file is not an error', () async {
      await deleteStickerTemp('${root.path}/gone.png');
    });
  });

  testWidgets('the source sheet offers photo, gallery and clip', (
    tester,
  ) async {
    StickerCreateSource? picked;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await showStickerCreateSourceSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New sticker'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    await tester.tap(find.text('Record clip'));
    await tester.pumpAndSettle();

    expect(picked, StickerCreateSource.cameraClip);
  });

  testWidgets('the source sheet reads right to left in Arabic', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showStickerCreateSourceSheet(context),
            child: const Text('open'),
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ملصق جديد'), findsOneWidget);
    final clip = find.text('تسجيل مقطع');
    expect(Directionality.of(tester.element(clip)), TextDirection.rtl);
    final photo = find.text('التقاط صورة');
    expect(
      tester.getCenter(find.byIcon(Icons.photo_camera_outlined)).dx,
      greaterThan(tester.getCenter(photo).dx),
    );
  });

  testWidgets('the crop screen returns the cropped square and chosen shape', (
    tester,
  ) async {
    final png = img.encodePng(img.Image(width: 40, height: 30));
    StickerStillCrop? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.of(context).push<StickerStillCrop>(
                  MaterialPageRoute(
                    builder: (_) => StickerCropScreen(imageBytes: png),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final crop = find.widgetWithText(TextButton, 'Crop');
    expect(tester.widget<TextButton>(crop).onPressed, isNull);
    for (var i = 0; i < 50; i++) {
      if (tester.widget<TextButton>(crop).onPressed != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    await tester.tap(find.text('Circle'));
    await tester.pump();
    await tester.tap(find.text('Crop'));
    for (var i = 0; i < 20 && result == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(result?.shape, StickerShape.circle);
    final cropped = img.decodePng(result!.bytes)!;
    expect(cropped.width, cropped.height);
  });

  testWidgets('a gallery photo is copied first, so backing out of crop keeps '
      'the original and cleans the copy', (tester) async {
    final root = Directory.systemTemp.createTempSync('stk-pick-');
    addTearDown(() => root.deleteSync(recursive: true));
    final original = File('${root.path}/IMG_0001.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 30)));
    final temp = Directory('${root.path}/tmp')..createSync();
    Future<void>? running;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => running = openStickerCreate(
                context,
                library: FakeCustomStickerLibrary(),
                picker: _OnePhotoPicker(original.path),
                temporaryDirectory: () async => temp,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    final crop = find.widgetWithText(TextButton, 'Crop');
    await _settleUntil(
      tester,
      () =>
          crop.evaluate().isNotEmpty &&
          tester.widget<TextButton>(crop).onPressed != null,
    );
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    var finished = false;
    unawaited(running!.whenComplete(() => finished = true));
    await _settleUntil(tester, () => finished);
    expect(finished, isTrue);

    expect(original.existsSync(), isTrue);
    expect(temp.listSync(), isEmpty);
  });

  for (final availability in ['ready', 'unsupported']) {
    testWidgets('Create uses the shipping cutout gate and preserves crop '
        'fallback when native availability is $availability', (tester) async {
      final root = Directory.systemTemp.createTempSync('stk-cutout-route-');
      addTearDown(() => root.deleteSync(recursive: true));
      final originalBytes = img.encodePng(
        img.fill(
          img.Image(width: 40, height: 30),
          color: img.ColorRgb8(180, 30, 20),
        ),
      );
      final cutoutBytes = img.encodePng(
        img.fill(
          img.Image(width: 40, height: 30, numChannels: 4),
          color: img.ColorRgba8(20, 180, 30, 255),
        ),
      );
      expect(img.decodePng(cutoutBytes)!.hasAlpha, isTrue);
      final original = File('${root.path}/original.png')
        ..writeAsBytesSync(originalBytes);
      final temp = Directory('${root.path}/tmp')..createSync();
      final library = FakeCustomStickerLibrary();
      final calls = <String>[];
      const channel = MethodChannel('mknoon/custom_sticker_cutout');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'availability') return availability;
        expect(call.method, 'extract');
        final arguments = call.arguments as Map;
        await File(arguments['outputPath'] as String).writeAsBytes(cutoutBytes);
        return {
          'width': 40,
          'height': 30,
          'subjectBounds': {
            'left': 0.0,
            'top': 0.0,
            'right': 1.0,
            'bottom': 1.0,
          },
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var temporaryReads = 0;
      Future<void>? running;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => running = openStickerCreate(
                  context,
                  library: library,
                  picker: _OnePhotoPicker(original.path),
                  temporaryDirectory: () async {
                    temporaryReads++;
                    return temp;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(temporaryReads, 0);
      await tester.tap(find.text('Gallery'));

      final usesCutout = kCustomStickersEnabled && availability == 'ready';
      final destination = usesCutout
          ? find.byType(StickerTextEditorScreen)
          : find.byType(StickerCropScreen);
      await _settleUntil(tester, () => destination.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(destination, findsOneWidget);
      if (usesCutout) {
        expect(find.byType(StickerCropScreen), findsNothing);
        expect(
          tester.widget<StickerTextEditorScreen>(destination).sourceBytes,
          orderedEquals(cutoutBytes),
        );
      }
      expect(
        calls,
        !kCustomStickersEnabled
            ? isEmpty
            : orderedEquals(
                usesCutout ? ['availability', 'extract'] : ['availability'],
              ),
      );

      if (usesCutout) {
        await tester.tap(find.byTooltip('Cancel'));
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      var finished = false;
      unawaited(running!.whenComplete(() => finished = true));
      await _settleUntil(tester, () => finished);
      expect(finished, isTrue);
      expect(original.readAsBytesSync(), orderedEquals(originalBytes));
      expect(temp.listSync(recursive: true).whereType<File>(), isEmpty);
      expect(library.ids, isEmpty);
    });
  }

  group('stickerCreateMessage', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final saved = StickerCreateSaved(
      CustomSticker(
        id: 'a',
        asset: fakeStickerAsset('a'),
        createdAtMs: 0,
        lastUsedAtMs: 0,
        position: 0,
      ),
    );

    test('saved, full, failed and cancelled read as approved', () {
      expect(stickerCreateMessage(l10n, saved), 'Saved to My stickers');
      for (final code in [
        CustomStickerErrorCode.countQuota,
        CustomStickerErrorCode.byteQuota,
      ]) {
        expect(
          stickerCreateMessage(l10n, StickerCreateFailed(code)),
          'My stickers is full. Delete one to add another.',
        );
      }
      expect(
        stickerCreateMessage(
          l10n,
          const StickerCreateFailed(CustomStickerErrorCode.storageFailure),
        ),
        "Couldn't save this sticker. Try again.",
      );
      expect(
        stickerCreateMessage(l10n, const StickerCreateCancelled()),
        isNull,
      );
    });

    test('Arabic messages are the approved copy', () {
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(stickerCreateMessage(ar, saved), 'تم الحفظ في ملصقاتي');
      expect(
        stickerCreateMessage(
          ar,
          const StickerCreateFailed(CustomStickerErrorCode.byteQuota),
        ),
        'ملصقاتي ممتلئة. احذف ملصقًا لإضافة آخر.',
      );
    });

    test('German quotes the library name', () {
      expect(
        stickerCreateMessage(
          lookupAppLocalizations(const Locale('de')),
          const StickerCreateFailed(CustomStickerErrorCode.countQuota),
        ),
        '„Meine Sticker“ ist voll. Lösche einen, um einen neuen hinzuzufügen.',
      );
    });
  });
}
