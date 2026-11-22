import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_app/features/stickers/application/sticker_cutout.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_flow.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_overlay_editor_result.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_layers.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fake_custom_sticker_library.dart';

class _FakeCutout implements StickerCutoutService {
  StickerCutoutAvailability available = StickerCutoutAvailability.ready;
  Object? extractError;
  StickerCutout? result;
  Completer<StickerCutout?>? gate;
  final extracted = <String>[];
  int cancels = 0;

  @override
  Future<StickerCutoutAvailability> availability() async => available;

  @override
  Future<StickerCutout?> extract(String sourceImagePath) async {
    extracted.add(sourceImagePath);
    if (extractError case final error?) throw error;
    if (gate case final gate?) return gate.future;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    gate?.complete(null);
  }
}

final _cutoutPng = Uint8List.fromList([1, 2, 3]);
final _croppedPng = Uint8List.fromList([4, 5, 6]);
const _cutoutPath = '/tmp/cutout.png';
const _clipText = StickerTextLayer(id: 1, text: 'H');

void main() {
  late FakeCustomStickerLibrary library;
  late _FakeCutout cutout;
  late List<String> log;
  late StickerEditorResult editorResult;
  late StickerClipCrop? clipCrop;
  late List<List<StickerTextLayer>> exportedLayers;

  StickerCreateFlow flow({
    Future<StickerOverlayEditorResult> Function(
      String clipPath,
      StickerClipCrop crop,
    )?
    editClipText,
  }) => StickerCreateFlow(
    library: library,
    cutout: cutout,
    pickPhoto: (source) async {
      log.add('pick ${source.name}');
      return '/tmp/photo.jpg';
    },
    captureClip: () async {
      log.add('capture clip');
      return '/tmp/clip.mp4';
    },
    readBytes: (path) async {
      log.add('read $path');
      return _cutoutPng;
    },
    deleteFile: (path) async => log.add('delete $path'),
    cropStill: (path) async {
      log.add('crop still $path');
      return (bytes: _croppedPng, shape: StickerShape.circle);
    },
    cropClip: (path) async {
      log.add('crop clip $path');
      return clipCrop;
    },
    editStill: (bytes, shape) async {
      log.add('edit ${bytes.first} ${shape.name}');
      return editorResult;
    },
    exportClip: (path, crop, layers) async {
      log.add('export $path ${crop.crop} ${crop.circle}');
      exportedLayers.add(layers);
      return fakeStickerAsset('clip');
    },
    showNoSubject: () => log.add('no subject'),
    editClipText:
        editClipText ?? (_, _) async => StickerOverlayEditorReady(const []),
  );

  setUp(() {
    library = FakeCustomStickerLibrary();
    cutout = _FakeCutout();
    log = [];
    editorResult = StickerEditorResult.ready(fakeStickerAsset('made'));
    clipCrop = (crop: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.5), circle: true);
    exportedLayers = [];
  });

  test(
    'a found subject goes to the editor, is saved, and every temp is deleted',
    () async {
      cutout.result = const StickerCutout(
        imagePath: _cutoutPath,
        width: 400,
        height: 300,
        subjectBounds: Rect.fromLTWH(0, 0, 1, 1),
      );

      final outcome = await flow().run(StickerCreateSource.cameraPhoto);

      expect(log, [
        'pick cameraPhoto',
        'read $_cutoutPath',
        'edit 1 square',
        'delete $_cutoutPath',
        'delete /nonexistent/made.webp',
        'delete /tmp/photo.jpg',
      ]);
      expect(
        (outcome as StickerCreateSaved).sticker.asset.sha256Hex,
        'sha-made',
      );
      expect(library.ids, [outcome.sticker.id]);
    },
  );

  test('no clear subject tells the user, then goes to crop', () async {
    cutout.result = null;

    final outcome = await flow().run(StickerCreateSource.galleryPhoto);

    expect(log, [
      'pick galleryPhoto',
      'no subject',
      'crop still /tmp/photo.jpg',
      'edit 4 circle',
      'delete /nonexistent/made.webp',
      'delete /tmp/photo.jpg',
    ]);
    expect(outcome, isA<StickerCreateSaved>());
  });

  for (final available in [
    StickerCutoutAvailability.needsModel,
    StickerCutoutAvailability.unsupported,
  ]) {
    test('${available.name} goes straight to crop without a message', () async {
      cutout.available = available;

      await flow().run(StickerCreateSource.cameraPhoto);

      expect(cutout.extracted, isEmpty);
      expect(log, [
        'pick cameraPhoto',
        'crop still /tmp/photo.jpg',
        'edit 4 circle',
        'delete /nonexistent/made.webp',
        'delete /tmp/photo.jpg',
      ]);
    });
  }

  test('a cut-out error goes straight to crop without a message', () async {
    cutout.extractError = const StickerCutoutException(
      StickerCutoutErrorCode.unavailable,
    );

    await flow().run(StickerCreateSource.cameraPhoto);

    expect(log, [
      'pick cameraPhoto',
      'crop still /tmp/photo.jpg',
      'edit 4 circle',
      'delete /nonexistent/made.webp',
      'delete /tmp/photo.jpg',
    ]);
  });

  test(
    'cancelling during the cut-out shows nothing and saves nothing',
    () async {
      cutout.gate = Completer<StickerCutout?>();
      final create = flow();

      final pending = create.run(StickerCreateSource.cameraPhoto);
      await Future<void>.delayed(Duration.zero);
      await create.cancel();
      final outcome = await pending;

      expect(outcome, isA<StickerCreateCancelled>());
      expect(cutout.cancels, 1);
      expect(log, ['pick cameraPhoto', 'delete /tmp/photo.jpg']);
      expect(library.ids, isEmpty);
    },
  );

  test('backing out of the editor cancels and deletes the cut-out', () async {
    cutout.result = const StickerCutout(
      imagePath: _cutoutPath,
      width: 1,
      height: 1,
      subjectBounds: Rect.fromLTWH(0, 0, 1, 1),
    );
    editorResult = const StickerEditorResult.cancelled();

    final outcome = await flow().run(StickerCreateSource.cameraPhoto);

    expect(outcome, isA<StickerCreateCancelled>());
    expect(log.sublist(log.length - 2), [
      'delete $_cutoutPath',
      'delete /tmp/photo.jpg',
    ]);
    expect(library.ids, isEmpty);
  });

  test('a clip is cropped, exported with that crop and saved', () async {
    final outcome = await flow().run(StickerCreateSource.cameraClip);

    expect(log, [
      'capture clip',
      'crop clip /tmp/clip.mp4',
      'export /tmp/clip.mp4 Rect.fromLTRB(0.1, 0.2, 0.6, 0.7) true',
      'delete /nonexistent/clip.webp',
      'delete /tmp/clip.mp4',
    ]);
    expect((outcome as StickerCreateSaved).sticker.asset.sha256Hex, 'sha-clip');
  });

  test('clip text is approved after crop and before export', () async {
    final create = flow(
      editClipText: (path, crop) async {
        expect(path, '/tmp/clip.mp4');
        expect(crop, clipCrop);
        expect(library.ids, isEmpty);
        log.add('edit clip text');
        return StickerOverlayEditorReady(const [_clipText]);
      },
    );

    final outcome = await create
        .run(StickerCreateSource.cameraClip)
        .timeout(const Duration(seconds: 2));

    expect(log, [
      'capture clip',
      'crop clip /tmp/clip.mp4',
      'edit clip text',
      'export /tmp/clip.mp4 Rect.fromLTRB(0.1, 0.2, 0.6, 0.7) true',
      'delete /nonexistent/clip.webp',
      'delete /tmp/clip.mp4',
    ]);
    expect(outcome, isA<StickerCreateSaved>());
    expect(library.ids, hasLength(1));
  });

  test('cancelling clip text exports and admits nothing', () async {
    final create = flow(
      editClipText: (_, _) async => const StickerOverlayEditorCancelled(),
    );

    final outcome = await create
        .run(StickerCreateSource.cameraClip)
        .timeout(const Duration(seconds: 2));

    expect(outcome, isA<StickerCreateCancelled>());
    expect(library.ids, isEmpty);
    expect(log, [
      'capture clip',
      'crop clip /tmp/clip.mp4',
      'delete /tmp/clip.mp4',
    ]);
  });

  test('a cancelled clip ignores a late text approval', () async {
    final approval = Completer<StickerOverlayEditorResult>();
    var editing = false;
    final create = flow(
      editClipText: (_, _) {
        editing = true;
        return approval.future.timeout(const Duration(seconds: 2));
      },
    );
    final pending = create
        .run(StickerCreateSource.cameraClip)
        .timeout(const Duration(seconds: 2));
    await Future<void>.delayed(
      Duration.zero,
    ).timeout(const Duration(seconds: 2));
    await create.cancel().timeout(const Duration(seconds: 2));
    approval.complete(StickerOverlayEditorReady(const []));
    final outcome = await pending;

    expect(editing, isTrue);
    expect(outcome, isA<StickerCreateCancelled>());
    expect(library.ids, isEmpty);
    expect(log, [
      'capture clip',
      'crop clip /tmp/clip.mp4',
      'delete /tmp/clip.mp4',
    ]);
  });

  test('clip export receives an immutable approved layer snapshot', () async {
    final layers = [_clipText];
    final approved = StickerOverlayEditorReady(layers);
    layers.clear();
    final create = flow(editClipText: (_, _) async => approved);

    await create
        .run(StickerCreateSource.cameraClip)
        .timeout(const Duration(seconds: 2));

    expect(exportedLayers, [
      const [_clipText],
    ]);
    expect(exportedLayers.single.clear, throwsUnsupportedError);
    expect(library.ids, hasLength(1));
  });

  test('saving clip text with no layers still exports once', () async {
    final create = flow(
      editClipText: (_, _) async => StickerOverlayEditorReady(const []),
    );

    final outcome = await create
        .run(StickerCreateSource.cameraClip)
        .timeout(const Duration(seconds: 2));

    expect(outcome, isA<StickerCreateSaved>());
    expect(exportedLayers, [isEmpty]);
    expect(library.ids, hasLength(1));
  });

  test('backing out of the clip crop cancels without exporting', () async {
    clipCrop = null;

    final outcome = await flow().run(StickerCreateSource.cameraClip);

    expect(outcome, isA<StickerCreateCancelled>());
    expect(log, [
      'capture clip',
      'crop clip /tmp/clip.mp4',
      'delete /tmp/clip.mp4',
    ]);
  });

  test('a full library reports its error code and keeps nothing', () async {
    cutout.available = StickerCutoutAvailability.unsupported;
    library.admitError = const CustomStickerException(
      CustomStickerErrorCode.countQuota,
    );

    final outcome = await flow().run(StickerCreateSource.cameraPhoto);

    expect(
      (outcome as StickerCreateFailed).code,
      CustomStickerErrorCode.countQuota,
    );
    expect(library.ids, isEmpty);
    expect(log.sublist(log.length - 2), [
      'delete /nonexistent/made.webp',
      'delete /tmp/photo.jpg',
    ]);
  });
}
