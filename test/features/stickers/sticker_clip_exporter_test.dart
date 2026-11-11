import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/stickers/application/sticker_clip_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _channel = MethodChannel('mknoon/custom_sticker_clip_frames');
const _crop = Rect.fromLTRB(0, 0, 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory cache;
  late File source;
  late StickerClipExporter exporter;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('sticker_clip_export_test_');
    source = File('${cache.path}/capture.mp4')..writeAsBytesSync([1, 2, 3]);
    exporter = StickerClipExporter(temporaryDirectory: () async => cache);
  });

  tearDown(() async {
    await exporter.cancel();
    messenger.setMockMethodCallHandler(_channel, null);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  Matcher failure(StickerClipExportFailure value) =>
      isA<StickerClipExportException>().having(
        (error) => error.failure,
        'failure',
        value,
      );

  Iterable<Directory> jobs() => cache.listSync().whereType<Directory>();

  if (!kCustomStickersEnabled) {
    test(
      'disabled export never opens an owned job or invokes native',
      () async {
        var calls = 0;
        messenger.setMockMethodCallHandler(_channel, (call) async {
          calls++;
          return null;
        });
        await expectLater(
          exporter.export(clipPath: source.path, crop: _crop, circle: false),
          throwsA(failure(StickerClipExportFailure.disabled)),
        );
        expect(calls, 0);
        expect(jobs(), isEmpty);
      },
    );
    return;
  }

  test('returns actual bounded bytes and preserves the caller clip', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'extract');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['clipPath'], source.path);
      expect(args['crop'], [0.0, 0.0, 1.0, 1.0]);
      final output = File(args['framesPath']! as String);
      final rgba = Uint8List(512 * 512 * 4 * 2);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = i < rgba.length ~/ 2 ? 46 : 166;
        rgba[i + 1] = 70;
        rgba[i + 2] = 110;
        rgba[i + 3] = 255;
      }
      output.writeAsBytesSync(rgba);
      return {'durationMs': 160, 'frameCount': 2};
    });
    final asset = await exporter.export(
      clipPath: source.path,
      crop: _crop,
      circle: false,
    );
    expect(asset, isNotNull);
    final canonical = File(asset!.filePath).readAsBytesSync();
    final poster = File(asset.posterPath!).readAsBytesSync();
    expect(asset.sha256Hex, sha256.convert(canonical).toString());
    expect(asset.byteLength, canonical.length);
    expect(asset.mime, 'image/webp');
    expect(
      (asset.width, asset.height, asset.frameCount, asset.durationMs),
      (512, 512, 2, 160),
    );
    expect(img.WebPDecoder().startDecode(canonical)!.hasAnimation, isTrue);
    expect(img.decodeWebP(poster)!.hasAnimation, isFalse);
    expect(
      jobs().single.listSync().map((entry) => entry.uri.pathSegments.last),
      unorderedEquals(['sticker.webp', 'poster.webp']),
    );
    expect(source.readAsBytesSync(), [1, 2, 3]);
  });

  test('rejects inconsistent native output and removes only its job', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      File(args['framesPath']! as String).writeAsBytesSync([0, 0, 0, 0]);
      return {'durationMs': 160, 'frameCount': 2};
    });
    await expectLater(
      exporter.export(clipPath: source.path, crop: _crop, circle: true),
      throwsA(failure(StickerClipExportFailure.invalidClip)),
    );
    expect(jobs(), isEmpty);
    expect(source.existsSync(), isTrue);
  });

  test(
    'cancel joins native extraction and rejects a concurrent export',
    () async {
      final started = Completer<void>();
      final stopped = Completer<void>();
      final nativeExit = Completer<void>();
      String? jobId;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        if (call.method == 'cancel') {
          expect(args['jobId'], jobId);
          stopped.complete();
          return null;
        }
        jobId = args['jobId']! as String;
        File(args['framesPath']! as String).writeAsBytesSync([9, 8, 7]);
        started.complete();
        await stopped.future;
        await nativeExit.future;
        throw PlatformException(code: 'cancelled');
      });
      final pending = exporter.export(
        clipPath: source.path,
        crop: _crop,
        circle: true,
      );
      await started.future;
      final second = StickerClipExporter(temporaryDirectory: () async => cache);
      await expectLater(
        second.export(clipPath: source.path, crop: _crop, circle: false),
        throwsA(failure(StickerClipExportFailure.busy)),
      );
      var cancelReturned = false;
      final cancellation = exporter.cancel().then((_) => cancelReturned = true);
      try {
        await stopped.future;
        expect(cancelReturned, isFalse);
        expect(jobs(), hasLength(1));
      } finally {
        nativeExit.complete();
      }
      await cancellation;
      expect(await pending, isNull);
      expect(jobs(), isEmpty);
      expect(source.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test(
    'malformed coordinates and overlay fail before opening the channel',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls++;
        return null;
      });
      await expectLater(
        exporter.export(
          clipPath: source.path,
          crop: const Rect.fromLTRB(double.nan, 0, 1, 1),
          circle: false,
        ),
        throwsA(failure(StickerClipExportFailure.invalidClip)),
      );
      await expectLater(
        exporter.export(
          clipPath: source.path,
          crop: _crop,
          circle: false,
          textOverlay: Uint8List(4),
        ),
        throwsA(failure(StickerClipExportFailure.invalidClip)),
      );
      expect(calls, 0);
      expect(jobs(), isEmpty);
    },
  );
}
