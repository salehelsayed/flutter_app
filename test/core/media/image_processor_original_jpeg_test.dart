import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/jpeg_metadata.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('original-jpeg-');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'Original JPEG is metadata-only, keeping image bytes and ICC unchanged',
    () async {
      final base = _jpeg(orientation: 6);
      final icc = _segment(0xe2, [
        ...ascii.encode('ICC_PROFILE\u0000'),
        1,
        1,
        ...ascii.encode('fixture-colour-profile'),
      ]);
      final inputBytes = Uint8List.fromList([
        ...base.take(2),
        ..._segment(0xe0, ascii.encode('JFXX\u0000fixture-private-thumbnail')),
        ..._segment(
          0xe1,
          ascii.encode('http://ns.adobe.com/xap/1.0/\u0000fixture-private-xmp'),
        ),
        ..._segment(
          0xed,
          ascii.encode('Photoshop 3.0\u0000fixture-private-iptc'),
        ),
        ..._segment(0xfe, ascii.encode('fixture-private-comment')),
        ..._segment(0xe2, ascii.encode('MPF\u0000fixture-private-mpf')),
        ..._segment(0xeb, ascii.encode('fixture-private-opaque-app')),
        ...icc,
        ...base.skip(2),
        ...ascii.encode('fixture-private-trailing-data'),
      ]);
      final input = File('${root.path}/camera.jpg')
        ..writeAsBytesSync(inputBytes);
      var nativeCalls = 0;
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              nativeCalls++;
              final native = File('${root.path}/native.jpg')
                ..writeAsBytesSync(_jpeg());
              return XFile(native.path);
            },
      );

      final outputPath = await processor.processImage(
        inputPath: input.path,
        quality: ImageQualityPreference.original,
      );
      final output = await File(outputPath).readAsBytes();
      expect(nativeCalls, 0, reason: 'Original must not re-encode a safe JPEG');
      expect(outputPath, isNot(input.path));
      expect(await input.readAsBytes(), inputBytes);
      final originalSegments = _headers(base);
      final outputSegments = _headers(output);
      expect(
        outputSegments.where((s) => s.marker == 0xe2).map((s) => s.bytes),
        [icc],
      );
      for (final marker in [0xc0, 0xdb, 0xc4, 0xda]) {
        expect(
          outputSegments.where((s) => s.marker == marker).map((s) => s.bytes),
          originalSegments.where((s) => s.marker == marker).map((s) => s.bytes),
        );
      }
      final apps = outputSegments
          .where((s) => s.marker >= 0xe0 && s.marker <= 0xef)
          .toList();
      expect(apps.map((s) => s.marker), [0xe1, 0xe2]);
      final exif = apps.singleWhere((s) => s.marker == 0xe1).bytes;
      expect(
        exif.length,
        36,
        reason: 'only the freshly built Orientation IFD remains',
      );
      final parsed = img.ExifData.fromInputBuffer(
        img.InputBuffer(exif.sublist(10)),
      );
      expect(parsed.imageIfd.keys, [0x0112]);
      expect(parsed.imageIfd.orientation, 6);
      expect(parsed.exifIfd.isEmpty, isTrue);
      expect(parsed.gpsIfd.isEmpty, isTrue);
      expect(parsed.thumbnailIfd.isEmpty, isTrue);
      expect(latin1.decode(output), isNot(contains('fixture-private-')));
      // SOS through EOI is one unchanged suffix; nothing follows its primary EOI.
      final scan = originalSegments.singleWhere((s) => s.marker == 0xda).bytes;
      expect(output.sublist(output.length - scan.length), scan);
      expect(output.length, lessThan(inputBytes.length));
    },
  );

  for (var orientation = 1; orientation <= 8; orientation++) {
    test(
      'Original preserves decoded pixels for orientation $orientation',
      () async {
        final bytes = _jpeg(orientation: orientation);
        final input = File('${root.path}/portrait.jpg')
          ..writeAsBytesSync(bytes);
        final processor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => throw StateError('safe JPEG must bypass the encoder'),
        );
        final path = await processor.processImage(
          inputPath: input.path,
          quality: ImageQualityPreference.original,
        );
        final before = await _pixels(bytes);
        final after = await _pixels(await File(path).readAsBytes());
        expect(after.$1, before.$1);
        expect(after.$2, before.$2);
        expect(after.$3, before.$3);
        expect(after.$1, orientation >= 5 ? 24 : 32);
        expect(after.$2, orientation >= 5 ? 32 : 24);
      },
    );
  }

  test(
    'Original never returns raw input after native fallback fails',
    () async {
      final input = File('${root.path}/unsupported.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 2)));
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
      );
      await expectLater(
        processor.processImage(
          inputPath: input.path,
          quality: ImageQualityPreference.original,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Compressed retains settings while refusing failed image processing',
    () async {
      final input = File('${root.path}/camera.jpg')..writeAsBytesSync(_jpeg());
      final calls = <(int, bool, int, int)>[];
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              calls.add((quality, keepExif, minWidth, minHeight));
              return null;
            },
      );
      await expectLater(
        processor.processImage(
          inputPath: input.path,
          quality: ImageQualityPreference.compressed,
        ),
        throwsStateError,
      );
      expect(calls, [(85, false, 1920, 1080)]);
    },
  );

  for (final quality in ImageQualityPreference.values) {
    test(
      'HEIF ${quality.name} is processed without forwarding source metadata',
      () async {
        final input = File('${root.path}/camera.heif')
          ..writeAsBytesSync([
            0,
            0,
            0,
            24,
            ...ascii.encode('ftypmif1fixture-private-gps'),
          ]);
        final processed = File('${root.path}/native.jpg')
          ..writeAsBytesSync(_codedBase());
        final calls = <(int, bool, int, int)>[];
        final processor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                calls.add((quality, keepExif, minWidth, minHeight));
                // Native-port substitute: HEIF decode/metadata removal on real phones
                // belongs to device evidence; the flags and routing are causal here.
                return keepExif ? XFile(input.path) : XFile(processed.path);
              },
        );
        final result = await processor.processImage(
          inputPath: input.path,
          quality: quality,
        );
        expect(result, processed.path);
        expect(
          latin1.decode(await File(result).readAsBytes()),
          isNot(contains('fixture-private-gps')),
        );
        expect(calls, [
          quality == ImageQualityPreference.original
              ? (100, false, 0x7fffffff, 0x7fffffff)
              : (85, false, 1920, 1080),
        ]);
      },
    );
  }

  for (final name in ['camera-cache', 'camera.dat']) {
    test('extensionless or opaque JPEG $name still removes metadata', () async {
      final input = File('${root.path}/$name')
        ..writeAsBytesSync(_jpeg(orientation: 6));
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async =>
                throw StateError('safe JPEG must bypass native encoding'),
      );
      final prepared = await preparePendingComposerMedia(
        inputPath: input.path,
        imageProcessor: processor,
        imageQualityPreference: ImageQualityPreference.original,
        videoQualityPreference: ImageQualityPreference.original,
      );
      expect(prepared.file.path, isNot(input.path));
      expect(
        latin1.decode(await prepared.file.readAsBytes()),
        isNot(contains('fixture-private-')),
      );
      expect(prepared.budgetBytes, await prepared.file.length());
    });
  }

  test('unknown filenames recognize only existing image signatures', () {
    final processor = ImageProcessor();
    final known = <List<int>>[
      _jpeg(),
      img.encodePng(img.Image(width: 2, height: 2)),
      ascii.encode('RIFF0000WEBPfixture'),
      [0, 0, 0, 24, ...ascii.encode('ftypheicfixture')],
      [0, 0, 0, 24, ...ascii.encode('ftypmif1fixture')],
    ];
    for (var i = 0; i < known.length; i++) {
      final input = File('${root.path}/known-$i')..writeAsBytesSync(known[i]);
      expect(processor.isProcessableImage(input.path), isTrue);
    }
    final unchanged = <List<int>>[
      ascii.encode('%PDF-fixture'),
      ascii.encode('GIF89afixture'),
      [0, 0, 0, 24, ...ascii.encode('ftypmsf1fixture')],
      [0, 0, 0, 24, ...ascii.encode('ftypaviffixture')],
      [0x49, 0x49, 42, 0, 0, 0, 0, 0],
    ];
    for (var i = 0; i < unchanged.length; i++) {
      final input = File('${root.path}/unsupported-$i')
        ..writeAsBytesSync(unchanged[i]);
      expect(processor.isProcessableImage(input.path), isFalse);
    }
    expect(processor.isProcessableImage('${root.path}/photo.HEIC'), isTrue);
    expect(processor.isProcessableImage('${root.path}/photo.HEIF'), isTrue);
    expect(processor.isProcessableImage('${root.path}/photo.webp'), isTrue);
  });

  test('Original pending budget uses the stripped JPEG length', () async {
    final input = File('${root.path}/camera.jpg')
      ..writeAsBytesSync(_jpeg(orientation: 6));
    final prepared = await preparePendingComposerMedia(
      inputPath: input.path,
      imageProcessor: ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => throw StateError('safe JPEG must not be re-encoded'),
      ),
      imageQualityPreference: ImageQualityPreference.original,
      videoQualityPreference: ImageQualityPreference.original,
    );
    expect(prepared.file.path, isNot(input.path));
    expect(prepared.budgetBytes, await prepared.file.length());
    expect(prepared.budgetBytes, lessThan(await input.length()));
  });

  final fallbackInputs = <String, Uint8List>{
    'png': img.encodePng(img.Image(width: 2, height: 2)),
    'webp': Uint8List.fromList(ascii.encode('RIFF0000WEBPfixture')),
    'heic': Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...ascii.encode('ftypheicfixture'),
    ]),
    'adobe.jpg': Uint8List.fromList([
      0xff,
      0xd8,
      ..._segment(0xee, [...ascii.encode('Adobe'), 0, 100, 0, 0, 0, 0, 1]),
      ..._codedBase().skip(2),
    ]),
  };
  for (final entry in fallbackInputs.entries) {
    test(
      'Original native fallback retains privacy and full-size settings for ${entry.key}',
      () async {
        final input = File('${root.path}/source.${entry.key}')
          ..writeAsBytesSync(entry.value);
        final output = File('${root.path}/native.jpg')
          ..writeAsBytesSync(_codedBase());
        final calls = <(int, bool, int, int)>[];
        final processor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                expect(path, input.path);
                calls.add((quality, keepExif, minWidth, minHeight));
                return XFile(output.path);
              },
        );
        expect(
          await processor.processImage(
            inputPath: input.path,
            quality: ImageQualityPreference.original,
          ),
          output.path,
        );
        expect(calls, [(100, false, 0x7fffffff, 0x7fffffff)]);
      },
    );
  }

  test(
    'JPEG traversal preserves both progressive entropy spans and removes inter-scan metadata',
    () {
      // This is a structural traversal fixture, not raster-decode evidence. Real
      // JPEG/Flutter codec pixel preservation is covered by all orientations above.
      final headers = _headers(_codedBase());
      final prefix = <int>[
        for (final segment in headers.where((s) => s.marker != 0xda))
          ...segment.marker == 0xc0
              ? [0xff, 0xc2, ...segment.bytes.skip(2)]
              : segment.bytes,
        ..._segment(0xdd, [0, 1]),
      ];
      final baselineSos = headers.singleWhere((s) => s.marker == 0xda).bytes;
      final sosLength = 2 + (baselineSos[2] << 8) + baselineSos[3];
      final dcSos = Uint8List.fromList(baselineSos.take(sosLength).toList());
      dcSos[dcSos.length - 2] = 0;
      final acSos = _segment(0xda, [1, 1, 0, 1, 63, 0]);
      const firstScan = [0x31, 0xff, 0, 0x55, 0xff, 0xd0, 0x22];
      const secondScan = [0x99, 0xff, 0, 0x10];
      final input = Uint8List.fromList([
        0xff,
        0xd8,
        ...prefix,
        ...dcSos,
        ...firstScan,
        ..._segment(0xe1, [
          ...ascii.encode('Exif\u0000\u0000'),
          ..._littleTiff(6),
        ]),
        ..._segment(0xfe, ascii.encode('fixture-private-between-scans')),
        ...acSos,
        ...secondScan,
        0xff,
        0xd9,
        ...ascii.encode('fixture-private-trailer'),
      ]);
      expect(stripJpegMetadata(input), [
        0xff,
        0xd8,
        ...prefix,
        ...dcSos,
        ...firstScan,
        ...acSos,
        ...secondScan,
        0xff,
        0xd9,
      ]);
    },
  );

  test('little-endian orientations are rebuilt without copying their TIFF', () {
    for (var orientation = 1; orientation <= 8; orientation++) {
      final input = _withTiff(_littleTiff(orientation));
      final output = stripJpegMetadata(input);
      expect(output, isNotNull);
      // The raster decoder bakes orientation and removes its EXIF. Inspect the
      // output IFD directly; the Flutter pixel tests cover rendered orientation.
      final exif = _headers(output!).where((s) => s.marker == 0xe1).toList();
      if (orientation == 1) {
        expect(exif, isEmpty);
      } else {
        final parsed = img.ExifData.fromInputBuffer(
          img.InputBuffer(exif.single.bytes.sublist(10)),
        );
        expect(parsed.imageIfd.orientation, orientation);
        expect(parsed.imageIfd.keys, [0x0112]);
      }
    }
  });

  test(
    'all truncated prefixes and invalid marker lengths fall back safely',
    () {
      final source = _jpeg(orientation: 6);
      for (var length = 0; length < source.length; length++) {
        expect(
          stripJpegMetadata(Uint8List.sublistView(source, 0, length)),
          isNull,
          reason: 'truncated prefix $length',
        );
      }
      for (final length in [0, 1, 65535]) {
        expect(
          stripJpegMetadata(
            Uint8List.fromList([
              0xff,
              0xd8,
              0xff,
              0xe1,
              length >> 8,
              length & 255,
              ..._codedBase().skip(2),
            ]),
          ),
          isNull,
        );
      }
    },
  );

  test('unreadable or conflicting orientation metadata falls back', () {
    final corruptions = <Uint8List>[
      _littleTiff(99),
      _littleTiff(6)..[0] = 0,
      _littleTiff(6)..[2] = 43,
      _littleTiff(6)..setRange(4, 8, [255, 255, 255, 255]),
      _littleTiff(6)..setRange(8, 10, [255, 255]),
      _littleTiff(6)..[12] = 4,
      _littleTiff(6)..[14] = 2,
      Uint8List(8),
    ];
    for (final tiff in corruptions) {
      expect(stripJpegMetadata(_withTiff(tiff)), isNull);
    }
    expect(
      stripJpegMetadata(
        Uint8List.fromList([
          0xff,
          0xd8,
          ..._segment(0xe1, [
            ...ascii.encode('Exif\u0000\u0000'),
            ..._littleTiff(6),
          ]),
          ..._withTiff(_littleTiff(8)).skip(2),
        ]),
      ),
      isNull,
    );
  });

  test(
    'multi-part ICC segments remain byte-identical and incomplete profiles fall back',
    () {
      final chunks = [
        _segment(0xe2, [...ascii.encode('ICC_PROFILE\u0000'), 2, 2, 3, 4]),
        _segment(0xe2, [...ascii.encode('ICC_PROFILE\u0000'), 1, 2, 1, 2]),
      ];
      final input = Uint8List.fromList([
        0xff,
        0xd8,
        ...chunks.expand((x) => x),
        ..._codedBase().skip(2),
      ]);
      final output = stripJpegMetadata(input)!;
      expect(
        _headers(output).where((s) => s.marker == 0xe2).map((s) => s.bytes),
        chunks,
      );
      expect(
        stripJpegMetadata(
          Uint8List.fromList([
            0xff,
            0xd8,
            ...chunks.first,
            ..._codedBase().skip(2),
          ]),
        ),
        isNull,
      );
    },
  );
}

Uint8List _jpeg({int orientation = 1}) {
  final image = img.Image(width: 32, height: 24);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 13 + y * 7) & 255,
        (x * 3 + y * 11) & 255,
        (x * 17 + y) & 255,
      );
    }
  }
  image.exif.imageIfd
    ..orientation = orientation
    ..imageDescription = 'fixture-private-description';
  image.exif.exifIfd[0x927c] = img.IfdValueUndefined.list(
    ascii.encode('fixture-private-maker-note'),
  );
  image.exif.gpsIfd
    ..gpsLatitudeRef = 'N'
    ..gpsLatitude = 1.25
    ..gpsLongitudeRef = 'E'
    ..gpsLongitude = 2.5;
  image.exif.thumbnailIfd.imageDescription = 'fixture-private-thumbnail';
  return img.encodeJpg(image, quality: 77);
}

Uint8List _segment(int marker, List<int> payload) => Uint8List.fromList([
  0xff,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 255,
  ...payload,
]);

Uint8List _codedBase() => Uint8List.fromList([
  0xff,
  0xd8,
  for (final segment in _headers(_jpeg()))
    if (segment.marker < 0xe0 || segment.marker > 0xef) ...segment.bytes,
]);

Uint8List _withTiff(Uint8List tiff) => Uint8List.fromList([
  0xff,
  0xd8,
  ..._segment(0xe1, [...ascii.encode('Exif\u0000\u0000'), ...tiff]),
  ..._codedBase().skip(2),
]);

Uint8List _littleTiff(int orientation) {
  final data = ByteData(26)
    ..setUint16(0, 0x4949)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 0x0112, Endian.little)
    ..setUint16(12, 3, Endian.little)
    ..setUint32(14, 1, Endian.little)
    ..setUint16(18, orientation, Endian.little);
  return data.buffer.asUint8List();
}

// The fixture is baseline JPEG. Keep its entire scan/EOI suffix as one oracle,
// independent of the production parser's handling of entropy/restart markers.
List<({int marker, Uint8List bytes})> _headers(Uint8List bytes) {
  final result = <({int marker, Uint8List bytes})>[];
  var offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset] != 0xff) {
      throw const FormatException('Expected baseline JPEG fixture marker');
    }
    final marker = bytes[offset + 1];
    if (marker == 0xda) {
      final eoi = bytes.lastIndexOf(0xd9);
      result.add((
        marker: marker,
        bytes: Uint8List.sublistView(bytes, offset, eoi + 1),
      ));
      break;
    }
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    result.add((
      marker: marker,
      bytes: Uint8List.sublistView(bytes, offset, offset + 2 + length),
    ));
    offset += 2 + length;
  }
  return result;
}

Future<(int, int, Uint8List)> _pixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return (
        frame.image.width,
        frame.image.height,
        pixels!.buffer.asUint8List(),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
