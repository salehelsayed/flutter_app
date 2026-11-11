import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/stickers/application/method_channel_sticker_cutout_service.dart';
import 'package:flutter_app/features/stickers/application/sticker_cutout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _channel = MethodChannel('mknoon/custom_sticker_cutout');
const _injectedChannel = MethodChannel('test/custom_sticker_cutout');
const _gateTimeout = Duration(seconds: 2);
const _bounds = Rect.fromLTRB(0, 0, 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory sandbox;
  late Directory cache;
  late File source;
  late File foreign;
  late Uint8List sourceBytes;
  late MethodChannelStickerCutoutService service;
  late List<MethodCall> calls;
  late List<_Request> requests;
  late List<Completer<Object?>> heldReplies;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('sticker_cutout_service_');
    cache = Directory(p.join(sandbox.path, 'cache'))..createSync();
    final caller = Directory(p.join(sandbox.path, 'caller'))..createSync();
    sourceBytes = img.encodePng(_pixels());
    source = File(p.join(caller.path, 'private-source.png'))
      ..writeAsBytesSync(sourceBytes);
    final otherOwner = Directory(p.join(cache.path, 'other-owner'))
      ..createSync();
    foreign = File(p.join(otherOwner.path, 'keep.txt'))
      ..writeAsStringSync('keep');
    service = MethodChannelStickerCutoutService(
      temporaryDirectory: cache,
      enabled: true,
    );
    calls = [];
    requests = [];
    heldReplies = [];
  });

  tearDown(() async {
    // Release only test-owned gates, including when the scaffold fails early.
    for (final reply in heldReplies) {
      if (!reply.isCompleted) reply.complete(null);
    }
    try {
      await service.cancel().timeout(_gateTimeout);
    } catch (_) {
      // Cleanup is not a passing cancellation assertion; tests check it below.
    }
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_injectedChannel, null);
    try {
      expect(
        source.existsSync(),
        isTrue,
        reason: 'source remains caller-owned',
      );
      expect(source.readAsBytesSync(), sourceBytes);
      expect(foreign.existsSync(), isTrue, reason: 'never sweep another owner');
      expect(foreign.readAsStringSync(), 'keep');
    } finally {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    }
  });

  void install(
    FutureOr<Object?> Function(_Request request) extract, {
    FutureOr<Object?> Function(MethodCall call)? cancel,
  }) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'availability') return 'ready';
      if (call.method == 'cancel') {
        return cancel == null ? null : await cancel(call);
      }
      expect(call.method, 'extract');
      final args = Map<String, Object?>.from(call.arguments as Map);
      final request = _Request(
        args['jobId']! as String,
        args['sourceImagePath']! as String,
        File(args['outputPath']! as String),
      );
      requests.add(request);
      expect(request.id, isNotEmpty);
      expect(
        File(request.sourcePath).resolveSymbolicLinksSync(),
        source.resolveSymbolicLinksSync(),
      );
      expect(p.isAbsolute(request.output.path), isTrue);
      expect(p.basename(request.output.path), 'result.png');
      expect(request.output.parent.existsSync(), isTrue);
      expect(
        p.isWithin(
          cache.resolveSymbolicLinksSync(),
          request.output.parent.resolveSymbolicLinksSync(),
        ),
        isTrue,
        reason: 'native receives a path inside this service-owned job',
      );
      return await extract(request);
    });
  }

  Object writeValid(_Request request) {
    request.output.writeAsBytesSync(img.encodePng(_pixels()));
    return _descriptor();
  }

  void expectRemoved(_Request request) {
    expect(
      request.output.parent.existsSync(),
      isFalse,
      reason: 'remove the failed/cancelled job, not only its output file',
    );
  }

  Future<void> rejectsOutput(
    Uint8List Function() bytes, {
    Map<String, Object?> Function()? descriptor,
  }) async {
    install((request) {
      request.output.writeAsBytesSync(bytes());
      return descriptor == null ? _descriptor() : descriptor();
    });
    await expectLater(
      service.extract(source.path),
      throwsA(_failure(StickerCutoutErrorCode.failed)),
    );
    expect(
      requests,
      hasLength(1),
      reason: 'rejection must actually inspect the native-produced fixture',
    );
    expectRemoved(requests.single);
  }

  test('explicit flag-off does no channel or directory work', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return 'ready';
    });
    await _withoutFileSystem(() async {
      final disabled = MethodChannelStickerCutoutService(
        temporaryDirectory: _ForbiddenDirectory(),
        enabled: false,
      );
      expect(
        await disabled.availability(),
        StickerCutoutAvailability.unsupported,
      );
      await expectLater(
        disabled.extract('missing-relative-source'),
        throwsA(_failure(StickerCutoutErrorCode.disabled)),
      );
      await disabled.cancel();
    });
    expect(calls, isEmpty);
  });

  if (!kCustomStickersEnabled) {
    test('constructor defaults to the shipping flag-off boundary', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return 'ready';
      });
      await _withoutFileSystem(() async {
        final disabled = MethodChannelStickerCutoutService(
          temporaryDirectory: _ForbiddenDirectory(),
        );
        expect(
          await disabled.availability(),
          StickerCutoutAvailability.unsupported,
        );
        await expectLater(
          disabled.extract(source.path),
          throwsA(_failure(StickerCutoutErrorCode.disabled)),
        );
      });
      expect(calls, isEmpty);
    });
  }

  for (final availability in StickerCutoutAvailability.values) {
    test(
      'availability maps ${availability.name} without touching files',
      () async {
        messenger.setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          expect(call.method, 'availability');
          return availability.name;
        });
        final capabilities = MethodChannelStickerCutoutService(
          temporaryDirectory: _ForbiddenDirectory(),
          enabled: true,
        );
        expect(await capabilities.availability(), availability);
        expect(calls, hasLength(1));
      },
    );
  }

  test('uses an explicitly supplied channel', () async {
    var injectedCalls = 0;
    messenger.setMockMethodCallHandler(_injectedChannel, (call) async {
      injectedCalls++;
      expect(call.method, 'availability');
      return 'ready';
    });
    final injected = MethodChannelStickerCutoutService(
      temporaryDirectory: _ForbiddenDirectory(),
      channel: _injectedChannel,
      enabled: true,
    );
    expect(await injected.availability(), StickerCutoutAvailability.ready);
    expect(injectedCalls, 1);
  });

  test(
    'missing plugin routes availability and extraction to unsupported',
    () async {
      expect(
        await service.availability(),
        StickerCutoutAvailability.unsupported,
      );
      await expectLater(
        service.extract(source.path),
        throwsA(_failure(StickerCutoutErrorCode.unsupported)),
      );
      expect(cache.listSync().map((e) => p.basename(e.path)), ['other-owner']);
    },
  );

  test('availability errors expose only a safe typed error', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      throw PlatformException(
        code: 'unsafe-native-code',
        message: source.path,
        details: {'image': 'PRIVATE_IMAGE_PAYLOAD'},
      );
    });
    final result = await _observe(service.availability());
    expect(calls, hasLength(1));
    _expectSafeFailure(
      result.error,
      StickerCutoutErrorCode.failed,
      source.path,
    );
  });

  test(
    'success returns the owned validated PNG and transfers ownership',
    () async {
      install(writeValid);
      final result = await service.extract(source.path);
      expect(result, isNotNull);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(result!.imagePath, request.output.path);
      expect(
        (result.width, result.height, result.subjectBounds),
        (4, 3, _bounds),
      );
      final actual = img.decodePng(File(result.imagePath).readAsBytesSync())!;
      expect((actual.width, actual.height, actual.numFrames), (4, 3, 1));
      expect(actual.numChannels, 4);
      expect(actual.exif.isEmpty, isTrue);
      expect(actual.iccProfile, isNull);
      expect(actual.textData ?? <String, String>{}, isEmpty);
      expect(
        (
          actual.getPixel(0, 0).r,
          actual.getPixel(0, 0).g,
          actual.getPixel(0, 0).b,
          actual.getPixel(0, 0).a,
        ),
        (0, 0, 0, 0),
      );

      final before = request.output.readAsBytesSync();
      await service.cancel();
      await service.cancel();
      expect(calls.where((c) => c.method == 'cancel'), isEmpty);
      expect(request.output.readAsBytesSync(), before);
    },
  );

  test(
    'subsequent jobs use fresh tokens and retain prior caller-owned PNGs',
    () async {
      install(writeValid);
      final first = (await service.extract(source.path))!;
      final firstBytes = File(first.imagePath).readAsBytesSync();
      final second = (await service.extract(source.path))!;
      expect(requests, hasLength(2));
      expect(requests[0].id, isNot(requests[1].id));
      expect(
        requests[0].output.parent.path,
        isNot(requests[1].output.parent.path),
      );
      await service.cancel();
      expect(File(first.imagePath).readAsBytesSync(), firstBytes);
      expect(File(second.imagePath).existsSync(), isTrue);
    },
  );

  test(
    'no subject removes only its pending job, including partial output',
    () async {
      install((request) {
        request.output.writeAsBytesSync([7, 8, 9]);
        File(
          p.join(request.output.parent.path, 'partial.tmp'),
        ).writeAsStringSync('partial');
        return null;
      });
      expect(await service.extract(source.path), isNull);
      expect(requests, hasLength(1));
      expectRemoved(requests.single);
    },
  );

  for (final invalid in ['missing', 'directory']) {
    test(
      'invalid caller source ($invalid) fails before native admission',
      () async {
        install(writeValid);
        final path = invalid == 'missing'
            ? p.join(sandbox.path, 'absent.png')
            : source.parent.path;
        await expectLater(
          service.extract(path),
          throwsA(_failure(StickerCutoutErrorCode.invalidSource)),
        );
        expect(requests, isEmpty);
        expect(cache.listSync().map((e) => p.basename(e.path)), [
          'other-owner',
        ]);
      },
    );
  }

  test(
    'native failure is private, cleans only its job, and permits a retry',
    () async {
      install((request) {
        if (requests.length > 1) return writeValid(request);
        request.output.writeAsBytesSync([1, 2, 3]);
        throw PlatformException(
          code: 'unsafe-native-code',
          message: source.path,
          details: {
            'image': 'PRIVATE_IMAGE_PAYLOAD',
            'outputPath': request.output.path,
          },
        );
      });
      final failed = await _observe(service.extract(source.path));
      expect(requests, hasLength(1));
      _expectSafeFailure(
        failed.error,
        StickerCutoutErrorCode.failed,
        source.path,
      );
      expectRemoved(requests.single);
      final result = await service.extract(source.path);
      expect(result, isNotNull);
      expect(requests, hasLength(2));
      expect(requests[0].id, isNot(requests[1].id));
    },
  );

  test('never reads or deletes an arbitrary returned output path', () async {
    install(
      (request) => {
        ..._descriptor(),
        'imagePath': source.path,
        'outputPath': source.path,
        'path': source.path,
      },
    );
    await expectLater(
      service.extract(source.path),
      throwsA(_failure(StickerCutoutErrorCode.failed)),
    );
    expect(requests, hasLength(1));
    expectRemoved(requests.single);
  });

  final badBytes = <String, Uint8List Function()>{
    'malformed bytes': () => Uint8List.fromList([1, 2, 3, 4]),
    'JPEG renamed result.png': () => img.encodeJpg(_pixels()),
    'truncated PNG': () {
      final bytes = img.encodePng(_pixels());
      return Uint8List.fromList(bytes.take(bytes.length - 7).toList());
    },
    'corrupt PNG checksum': () {
      final bytes = img.encodePng(_pixels());
      bytes[29] ^= 1; // IHDR CRC, without changing its valid dimensions.
      return bytes;
    },
    'trailing private payload': () => Uint8List.fromList([
      ...img.encodePng(_pixels()),
      ...utf8.encode('PRIVATE_IMAGE_PAYLOAD'),
    ]),
    'APNG with two frames': () {
      final image = _pixels()..frameDuration = 50;
      image.addFrame(_pixels()..frameDuration = 50);
      final bytes = img.encodePng(image);
      expect(img.decodePng(bytes)!.numFrames, 2);
      return bytes;
    },
    'nonzero RGB beneath alpha zero': () {
      final image = _pixels()..setPixelRgba(0, 0, 81, 99, 137, 0);
      final bytes = img.encodePng(image);
      expect(img.decodePng(bytes)!.getPixel(0, 0).r, 81);
      return bytes;
    },
    'text metadata': () {
      final image = _pixels()..textData = {'Comment': 'PRIVATE_IMAGE_PAYLOAD'};
      final bytes = img.encodePng(image);
      expect(img.decodePng(bytes)!.textData, isNotEmpty);
      return bytes;
    },
    'ICC metadata': () {
      final profile = Uint8List(128);
      ByteData.sublistView(profile).setUint32(0, profile.length, Endian.big);
      profile.setAll(36, ascii.encode('acsp'));
      final image = _pixels()
        ..iccProfile = img.IccProfile(
          'private',
          img.IccProfileCompression.none,
          profile,
        );
      final bytes = img.encodePng(image);
      expect(img.decodePng(bytes)!.iccProfile, isNotNull);
      return bytes;
    },
    'EXIF orientation and private metadata': () {
      final exif = img.ExifData();
      exif.imageIfd
        ..orientation = 6
        ..imageDescription = 'PRIVATE_IMAGE_PAYLOAD';
      final output = img.OutputBuffer();
      exif.write(output);
      return _insertPngChunk(
        img.encodePng(_pixels()),
        'eXIf',
        output.getBytes(),
      );
    },
  };
  for (final fixture in badBytes.entries) {
    test(
      'rejects actual native output: ${fixture.key}',
      () => rejectsOutput(fixture.value),
    );
  }

  for (final size in [(2049, 3), (4, 2049)]) {
    test(
      'rejects actual ${size.$1}x${size.$2} PNG with truthful native dimensions',
      () async {
        await rejectsOutput(
          () => img.encodePng(_pixels(width: size.$1, height: size.$2)),
          descriptor: () => _descriptor(width: size.$1, height: size.$2),
        );
      },
    );
  }

  test('accepts the inclusive 2048 limit independently on each axis', () async {
    for (final size in [(2048, 3), (4, 2048)]) {
      install((request) {
        request.output.writeAsBytesSync(
          img.encodePng(_pixels(width: size.$1, height: size.$2)),
        );
        return _descriptor(width: size.$1, height: size.$2);
      });
      final result = await service.extract(source.path);
      expect(result, isNotNull);
      expect((result!.width, result.height), size);
      expect(File(result.imagePath).existsSync(), isTrue);
    }
  });

  test('rejects a real single-frame PNG above the 24MiB byte cap', () async {
    await rejectsOutput(() {
      // uint16 + uncompressed PNG exceeds the byte cap while both dimensions
      // remain legal. No text/profile metadata or malformed padding causes it.
      final image = img.Image(
        width: 2048,
        height: 2048,
        numChannels: 4,
        format: img.Format.uint16,
      );
      image.setPixelRgba(0, 0, 65535, 0, 0, 65535);
      image.setPixelRgba(2047, 2047, 0, 65535, 0, 65535);
      final bytes = img.encodePng(image, level: 0, filter: img.PngFilter.none);
      expect(bytes.length, greaterThan(24 * 1024 * 1024));
      final header = ByteData.sublistView(bytes);
      expect(
        (header.getUint32(16, Endian.big), header.getUint32(20, Endian.big)),
        (2048, 2048),
      );
      expect(image.numFrames, 1);
      return bytes;
    }, descriptor: () => _descriptor(width: 2048, height: 2048));
  });

  final badDescriptors = <String, Map<String, Object?> Function()>{
    'wrong raster width': () => _descriptor(width: 5),
    'missing height': () => _descriptor()..remove('height'),
    'nonfinite subject bound': () =>
        _descriptor(bounds: const Rect.fromLTRB(double.nan, 0, 1, 1)),
    'subject outside normalized image': () =>
        _descriptor(bounds: const Rect.fromLTRB(-0.1, 0, 1, 1)),
    'empty subject rectangle': () =>
        _descriptor(bounds: const Rect.fromLTRB(0.5, 0, 0.5, 1)),
  };
  for (final descriptor in badDescriptors.entries) {
    test(
      'rejects native descriptor: ${descriptor.key}',
      () => rejectsOutput(
        () => img.encodePng(_pixels()),
        descriptor: descriptor.value,
      ),
    );
  }

  test('output symlink cannot transfer ownership of a caller file', () async {
    install((request) {
      Link(request.output.path).createSync(source.path);
      return _descriptor();
    });
    await expectLater(
      service.extract(source.path),
      throwsA(_failure(StickerCutoutErrorCode.failed)),
    );
    expect(requests, hasLength(1));
    expectRemoved(requests.single);
  });

  test(
    'cancel ack frees admission and stale reply only cleans the retired job',
    () async {
      final entered = Completer<_Request>();
      final cancelEntered = Completer<void>();
      final oldReply = Completer<Object?>();
      heldReplies.add(oldReply);
      install(
        (request) {
          if (requests.length > 1) return writeValid(request);
          request.output.writeAsBytesSync([1, 2, 3]);
          entered.complete(request);
          return oldReply.future;
        },
        cancel: (call) {
          final args = Map<String, Object?>.from(call.arguments as Map);
          expect(args['jobId'], requests.first.id);
          if (!cancelEntered.isCompleted) cancelEntered.complete();
          return null;
        },
      );

      final first = _observe(service.extract(source.path));
      final old = await _mustReach(entered, first, 'native extract');
      await expectLater(
        service.extract(source.path),
        throwsA(_failure(StickerCutoutErrorCode.unavailable)),
      );
      expect(
        requests,
        hasLength(1),
        reason: 'busy refuses a second native job',
      );

      final cancellation = _observe(service.cancel());
      final repeatedCancellation = _observe(service.cancel());
      await _mustReach(cancelEntered, cancellation, 'native cancel');
      expect((await cancellation.timeout(_gateTimeout)).error, isNull);
      expect((await repeatedCancellation.timeout(_gateTimeout)).error, isNull);
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
      final cancelled = await first.timeout(_gateTimeout);
      expect(cancelled.error, isNull);
      expect(cancelled.value, isNull);
      expect(
        oldReply.isCompleted,
        isFalse,
        reason: 'cancel acknowledgement must not join the old extract reply',
      );
      expectRemoved(old);

      final successor = (await service.extract(source.path))!;
      expect(requests, hasLength(2));
      final next = requests.last;
      expect(next.id, isNot(old.id));
      expect(next.output.parent.path, isNot(old.output.parent.path));
      final successorBytes = File(successor.imagePath).readAsBytesSync();

      // Model a late old producer completion. It writes only its original path.
      old.output.parent.createSync(recursive: true);
      writeValid(old);
      oldReply.complete(_descriptor());
      await _eventually(
        () => !old.output.parent.existsSync(),
        'late old job cleanup',
      );
      expect(File(successor.imagePath).readAsBytesSync(), successorBytes);
      await service.cancel();
      expect(File(successor.imagePath).readAsBytesSync(), successorBytes);
    },
  );

  for (final failure in ['platform', 'missingPlugin']) {
    test(
      '$failure cancel failure is best-effort and cannot block the successor',
      () async {
        final entered = Completer<_Request>();
        final nextEntered = Completer<_Request>();
        final cancelEntered = Completer<void>();
        final oldReply = Completer<Object?>();
        final nextReply = Completer<Object?>();
        heldReplies.addAll([oldReply, nextReply]);
        install(
          (request) {
            if (requests.length == 1) {
              entered.complete(request);
              return oldReply.future;
            }
            if (requests.length == 2) {
              nextEntered.complete(request);
              return nextReply.future;
            }
            return writeValid(
              request,
            ); // An unintended third admission fails promptly.
          },
          cancel: (call) {
            if (!cancelEntered.isCompleted) cancelEntered.complete();
            if (failure == 'missingPlugin') {
              throw MissingPluginException(
                'PRIVATE_IMAGE_PAYLOAD ${source.path}',
              );
            }
            throw PlatformException(
              code: 'unsafe-cancel',
              message: source.path,
              details: 'PRIVATE_IMAGE_PAYLOAD',
            );
          },
        );
        final first = _observe(service.extract(source.path));
        final old = await _mustReach(entered, first, 'native extract');
        final cancellation = _observe(service.cancel());
        final repeatedCancellation = _observe(service.cancel());
        await _mustReach(cancelEntered, cancellation, 'native cancel');

        expect((await cancellation.timeout(_gateTimeout)).error, isNull);
        expect(
          (await repeatedCancellation.timeout(_gateTimeout)).error,
          isNull,
        );
        expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
        final cancelled = await first.timeout(_gateTimeout);
        expect(cancelled.error, isNull);
        expect(cancelled.value, isNull);
        expect(
          oldReply.isCompleted,
          isFalse,
          reason: 'a failed cancel attempt must also release Dart admission',
        );
        expectRemoved(old);

        final successorResult = _observe(service.extract(source.path));
        final next = await _mustReach(
          nextEntered,
          successorResult,
          'successor extract',
        );
        writeValid(next);
        final successorBytes = next.output.readAsBytesSync();
        expect(requests, hasLength(2));
        expect(next.id, isNot(old.id));
        expect(next.output.parent.path, isNot(old.output.parent.path));

        old.output.parent.createSync(recursive: true);
        writeValid(old);
        oldReply.complete(_descriptor());
        await _eventually(
          () => !old.output.parent.existsSync(),
          'failed-cancel cleanup',
        );
        expect(next.output.readAsBytesSync(), successorBytes);
        await expectLater(
          service.extract(source.path),
          throwsA(_failure(StickerCutoutErrorCode.unavailable)),
        );
        expect(
          requests,
          hasLength(2),
          reason: 'late old completion must not clear the active successor',
        );

        nextReply.complete(_descriptor());
        final successor = await successorResult.timeout(_gateTimeout);
        expect(successor.error, isNull);
        expect(successor.value, isNotNull);
        expect(
          File(successor.value!.imagePath).readAsBytesSync(),
          successorBytes,
        );
      },
    );
  }
}

Matcher _failure(StickerCutoutErrorCode code) =>
    isA<StickerCutoutException>().having((e) => e.code, 'code', code);

void _expectSafeFailure(
  Object? error,
  StickerCutoutErrorCode code,
  String privatePath,
) {
  expect(error, _failure(code));
  expect(error.toString(), isNot(contains(privatePath)));
  expect(error.toString(), isNot(contains('PRIVATE_IMAGE_PAYLOAD')));
  expect(error.toString(), isNot(contains('unsafe-')));
}

Map<String, Object?> _descriptor({
  int width = 4,
  int height = 3,
  Rect bounds = _bounds,
}) => {
  'width': width,
  'height': height,
  'subjectBounds': {
    'left': bounds.left,
    'top': bounds.top,
    'right': bounds.right,
    'bottom': bounds.bottom,
  },
};

img.Image _pixels({int width = 4, int height = 3}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(42, 89, 137, 255));
  image.setPixelRgba(0, 0, 0, 0, 0, 0);
  return image;
}

final class _Request {
  const _Request(this.id, this.sourcePath, this.output);
  final String id;
  final String sourcePath;
  final File output;
}

final class _Observed<T> {
  const _Observed(this.value, this.error);
  final T? value;
  final Object? error;
}

Future<_Observed<T>> _observe<T>(Future<T> future) => future.then(
  (value) => _Observed<T>(value, null),
  onError: (Object error, StackTrace _) => _Observed<T>(null, error),
);

/// Causal RED exits immediately if the scaffold returns before the mock gate.
/// The short bound also protects against an implementation that never settles.
Future<T> _mustReach<T>(
  Completer<T> gate,
  Future<Object?> operation,
  String label,
) =>
    Future.any<T>([
      gate.future,
      operation.then<T>((_) {
        if (gate.isCompleted) return gate.future;
        throw TestFailure('Operation completed before reaching $label');
      }),
    ]).timeout(
      _gateTimeout,
      onTimeout: () => throw TestFailure('Operation never reached $label'),
    );

Future<void> _eventually(bool Function() condition, String label) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < _gateTimeout) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: label);
}

Future<T> _withoutFileSystem<T>(Future<T> Function() body) async {
  var attempts = 0;
  Never forbidden() {
    attempts++;
    throw TestFailure('Disabled cutout attempted filesystem work');
  }

  final result = await IOOverrides.runZoned(
    body,
    createFile: (_) => forbidden(),
    createDirectory: (_) => forbidden(),
    createLink: (_) => forbidden(),
    getCurrentDirectory: forbidden,
    getSystemTempDirectory: forbidden,
    stat: (_) => forbidden(),
    statSync: (_) => forbidden(),
    fseGetType: (_, _) => forbidden(),
    fseGetTypeSync: (_, _) => forbidden(),
    fseIdentical: (_, _) => forbidden(),
    fseIdenticalSync: (_, _) => forbidden(),
  );
  expect(
    attempts,
    0,
    reason: 'even a caught filesystem attempt violates flag-off',
  );
  return result;
}

/// This tripwire covers directory/path access, not just observable mutations.
final class _ForbiddenDirectory implements Directory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw TestFailure(
    'Unexpected temporary-directory access: ${invocation.memberName}',
  );
}

Uint8List _insertPngChunk(Uint8List png, String tag, Uint8List payload) {
  final chunk = Uint8List(payload.length + 12);
  final data = ByteData.sublistView(chunk);
  data.setUint32(0, payload.length, Endian.big);
  chunk.setAll(4, ascii.encode(tag));
  chunk.setAll(8, payload);
  var crc = 0xffffffff;
  for (final byte in Uint8List.sublistView(chunk, 4, chunk.length - 4)) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
  }
  data.setUint32(chunk.length - 4, (crc ^ 0xffffffff) & 0xffffffff, Endian.big);
  return Uint8List.fromList([...png.take(33), ...chunk, ...png.skip(33)]);
}
