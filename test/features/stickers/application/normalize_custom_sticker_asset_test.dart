import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/stickers/application/normalize_custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// These fixtures require image >=4.12.0: older versions cannot encode WebP.
// They are real PNG/WebP bytes, not mocks of codec options or DTO assertions.
void main() {
  late Directory root;
  late Directory sources;
  late Directory temporary;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sticker-normalizer-');
    sources = await Directory(p.join(root.path, 'producer')).create();
    temporary = await Directory(p.join(root.path, 'normalizer')).create();
    await File(p.join(temporary.path, 'preexisting.txt'))
        .writeAsString('not owned by this normalization');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<NormalizedStickerAsset> source(
    Uint8List bytes, {
    String name = 'input',
    String mime = 'image/png',
    int width = 32,
    int height = 24,
    int frameCount = 1,
    int durationMs = 0,
    String? posterPath,
  }) async {
    final file = File(p.join(sources.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return NormalizedStickerAsset(
      filePath: file.path,
      sha256Hex: sha256.convert(bytes).toString(),
      mime: mime,
      byteLength: bytes.length,
      width: width,
      height: height,
      frameCount: frameCount,
      durationMs: durationMs,
      posterPath: posterPath,
    );
  }

  Future<void> invalid(NormalizedStickerAsset input) async {
    final before = await File(input.filePath).readAsBytes();
    final scratchBefore = await _tree(temporary);
    await expectLater(
      normalizeCustomStickerAsset(input, temporaryDirectory: temporary),
      throwsA(
        isA<CustomStickerException>().having(
          (error) => error.code,
          'code',
          CustomStickerErrorCode.invalidAsset,
        ),
      ),
    );
    expect(await File(input.filePath).readAsBytes(), orderedEquals(before));
    expect(await _tree(temporary), scratchBefore,
        reason: 'failure must leave no partial output or owned temp directory');
  }

  Future<(NormalizedStickerAsset, Uint8List, img.Image)> normalized(
    NormalizedStickerAsset input,
  ) async {
    final original = await File(input.filePath).readAsBytes();
    final output = await normalizeCustomStickerAsset(
      input,
      temporaryDirectory: temporary,
    );
    expect(output.filePath, isNot(input.filePath),
        reason: 'the successful result must have independent temp ownership');
    expect(p.isWithin(temporary.path, output.filePath), isTrue);
    expect(await File(input.filePath).readAsBytes(), orderedEquals(original));
    expect(
      await File(p.join(temporary.path, 'preexisting.txt')).readAsString(),
      'not owned by this normalization',
    );
    final bytes = await File(output.filePath).readAsBytes();
    expect(output.mime, 'image/webp');
    expect(output.sha256Hex, sha256.convert(bytes).toString());
    expect(output.byteLength, bytes.length);
    final chunks = _webpChunks(bytes);
    expect(chunks.map((chunk) => chunk.tag),
        everyElement(isIn(['VP8X', 'VP8 ', 'VP8L', 'ALPH', 'ANIM', 'ANMF'])));
    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull, reason: 'output must be a decodable WebP');
    final image = decoded!;
    expect(output.width, image.width);
    expect(output.height, image.height);
    expect(output.width, inInclusiveRange(1, 512));
    expect(output.height, inInclusiveRange(1, 512));
    expect(output.frameCount, image.numFrames);
    final duration = image.numFrames == 1
        ? 0
        : image.frames.fold<int>(0, (sum, frame) => sum + frame.frameDuration);
    expect(output.durationMs, duration);
    expect(output.frameCount, inInclusiveRange(1, 24));
    expect(output.durationMs, inInclusiveRange(0, 2000));
    expect(bytes.length,
        lessThanOrEqualTo(image.numFrames == 1 ? 262144 : 524288));
    expect(image.exif.isEmpty, isTrue);
    expect(image.iccProfile, isNull);
    expect(image.textData ?? <String, String>{}, isEmpty);
    return (output, bytes, image);
  }

  test('static PNG becomes independent canonical WebP with exact output claims',
      () async {
    final input = await source(img.encodePng(_pixels()));
    final (output, bytes, _) = await normalized(input);
    expect(output.frameCount, 1);
    expect(output.durationMs, 0);
    expect(output.posterPath, isNull);
    expect(output.sha256Hex, isNot(input.sha256Hex));
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    await File(output.filePath).delete();
    expect(await File(input.filePath).exists(), isTrue);
  });

  test('preserves already-baked pixel orientation and every alpha value', () async {
    final pixels = _pixels();
    final input = await source(img.encodePng(pixels));
    final (_, _, image) = await normalized(input);
    expect((image.width, image.height), (32, 24));
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        expect(image.getPixel(x, y).a, pixels.getPixel(x, y).a,
            reason: 'alpha at ($x,$y), including semi-transparent edges');
      }
    }
    // Sample well inside asymmetric regions: this tolerates a lossy encoder,
    // but catches rotation, mirroring, channel swaps and premultiplication.
    final red = image.getPixel(7, 7);
    final green = image.getPixel(24, 7);
    final blue = image.getPixel(7, 18);
    expect(red.r, greaterThan(red.g + 80));
    expect(green.g, greaterThan(green.b + 80));
    expect(blue.b, greaterThan(blue.r + 80));
    expect(red.r, greaterThan(180),
        reason: 'the alpha-128 red patch must retain straight RGB');
  });

  test('removes PNG comments, creator/source text and XMP before own encoding',
      () async {
    final pixels = _pixels()
      ..textData = {
        'Author': 'fixture-private-creator',
        'Comment': 'fixture-private-comment',
        'Source': 'fixture-private-source-contact',
      };
    var bytes = img.encodePng(pixels);
    bytes = _insertPngChunk(bytes, 'iTXt', [
      ...ascii.encode('XML:com.adobe.xmp'),
      0, 0, 0, 0, 0,
      ...ascii.encode('<xmp>fixture-private-xmp</xmp>'),
    ]);
    expect(latin1.decode(bytes), contains('fixture-private-creator'));
    final input = await source(bytes);
    final (_, canonical, _) = await normalized(input);
    expect(latin1.decode(canonical), isNot(contains('fixture-private')));
  });

  for (final orientation in [1, 6]) {
    test('rejects PNG eXIf, including orientation=$orientation, without baking',
        () async {
      final bytes = _insertPngChunk(
        img.encodePng(_pixels()),
        'eXIf',
        _privateExif(orientation: orientation),
      );
      await invalid(await source(bytes));
    });
  }

  test('rejects PNG ICC rather than silently dropping a source colour profile',
      () async {
    final bytes = _insertPngChunk(img.encodePng(_pixels()), 'iCCP', [
      ...ascii.encode('fixture-profile'),
      0, 0, // Profile name terminator, then deflate compression method.
      ...ZLibEncoder().convert(_profile()),
    ]);
    await invalid(await source(bytes));
  });

  test('output is independent of original RGB under fully transparent PNG pixels',
      () async {
    final first = _pixels(hiddenRgb: (243, 19, 71));
    final second = _pixels(hiddenRgb: (11, 211, 97));
    final aBytes = img.encodePng(first);
    final bBytes = img.encodePng(second);
    expect(img.decodePng(aBytes)!.getPixel(0, 0).r, 243);
    expect(img.decodePng(bBytes)!.getPixel(0, 0).r, 11);
    expect(first.getPixel(0, 0).a, 0);
    final a = await source(aBytes, name: 'hidden-a.png');
    final b = await source(bBytes, name: 'hidden-b.png');
    final (_, aOutput, _) = await normalized(a);
    final (_, bOutput, _) = await normalized(b);
    expect(aOutput, orderedEquals(bOutput),
        reason: 'raw hidden source RGB must be cleared before our own encode');
    // No assertion that lossy decoding yields RGB(0,0,0) under alpha=0:
    // chroma subsampling and block reconstruction can restore neighboring RGB.
  });

  test('accepts the maximum 512-by-512 static PNG dimensions', () async {
    final input = await source(
      img.encodePng(_solid(512, 512)),
      width: 512,
      height: 512,
    );
    final (output, _, _) = await normalized(input);
    expect((output.width, output.height), (512, 512));
  });

  test('accepts a valid static PNG at exactly the inclusive 2MiB input ceiling',
      () async {
    final png = img.encodePng(_pixels());
    final keyword = ascii.encode('Comment\u0000');
    final bytes = _insertPngChunk(png, 'tEXt', [
      ...keyword,
      ...List<int>.filled(2097152 - png.length - 12 - keyword.length, 120),
    ]);
    expect(bytes.length, 2097152);
    await normalized(await source(bytes));
  });

  for (final lossless in [true, false]) {
    test('preserves full bytes of sanitized static WebP (lossless=$lossless)',
        () async {
      final bytes = img.encodeWebP(_pixels(), lossless: lossless, quality: 80);
      final input = await source(bytes, mime: 'image/webp');
      final (output, copied, _) = await normalized(input);
      expect(copied, orderedEquals(bytes));
      expect(output.sha256Hex, input.sha256Hex);
    });
  }

  for (final tag in ['EXIF', 'XMP ', 'ICCP', 'JUNK']) {
    test('rejects WebP $tag payload rather than passing it through', () async {
      final bytes = _appendWebpChunk(
        img.encodeWebP(_pixels(), lossless: false, quality: 80),
        tag,
        tag == 'EXIF'
            ? _privateExif()
            : tag == 'ICCP' ? _profile() : ascii.encode('fixture-private-payload'),
      );
      expect(_webpChunks(bytes).map((chunk) => chunk.tag), contains(tag));
      await invalid(await source(bytes, mime: 'image/webp'));
    });
  }

  test('preserves all 24 frames and 2000ms of sanitized canonical animation',
      () async {
    final durations = List<int>.generate(24, (i) => i < 8 ? 84 : 83);
    final bytes = img.encodeWebP(_animation(durations));
    final input = await source(bytes,
        mime: 'image/webp', frameCount: 24, durationMs: 2000);
    final (output, copied, image) = await normalized(input);
    expect(copied, orderedEquals(bytes));
    expect(output.frameCount, 24);
    expect(output.durationMs, 2000);
    expect(image.frames.map((frame) => frame.frameDuration),
        orderedEquals(durations));
  });

  for (final field in [
    'sha256', 'length', 'mime', 'width', 'height', 'frameCount', 'durationMs',
  ]) {
    test('rejects false PNG descriptor $field and preserves caller ownership',
        () async {
      final input = await source(img.encodePng(_pixels()));
      await invalid(_with(input,
          sha256Hex: field == 'sha256' ? '0' * 64 : null,
          byteLength: field == 'length' ? input.byteLength - 1 : null,
          mime: field == 'mime' ? 'image/webp' : null,
          width: field == 'width' ? 31 : null,
          height: field == 'height' ? 23 : null,
          frameCount: field == 'frameCount' ? 2 : null,
          durationMs: field == 'durationMs' ? 1 : null));
    });
  }

  test('sniffs the bytes even when the path and MIME both claim PNG', () async {
    final input = await source(img.encodeJpg(_solid(32, 24)), name: 'camera.png');
    await invalid(input);
  });

  for (final dimensions in [(513, 24), (32, 513)]) {
    test('rejects actual PNG dimension ${dimensions.$1}x${dimensions.$2}',
        () async {
      final input = await source(
        img.encodePng(_solid(dimensions.$1, dimensions.$2)),
        width: dimensions.$1,
        height: dimensions.$2,
      );
      await invalid(input);
    });
  }

  test('rejects a valid PNG input exceeding 2MiB before metadata sanitization',
      () async {
    final pixels = _solid(32, 24)
      ..textData = {'Comment': 'x' * 2097152};
    final bytes = img.encodePng(pixels);
    expect(bytes.length, greaterThan(2097152));
    await invalid(await source(bytes));
  });

  test('rejects animated PNG even if its descriptor claims one static frame',
      () async {
    final bytes = img.encodePng(_animation([83, 83]));
    expect(img.decodePng(bytes)!.numFrames, 2);
    await invalid(await source(bytes));
  });

  test('rejects APNG supplied with truthful animation claims', () async {
    final bytes = img.encodePng(_animation([83, 83]));
    await invalid(await source(bytes, frameCount: 2, durationMs: 166));
  });

  test('rejects changed file bytes after the descriptor was created', () async {
    final input = await source(img.encodePng(_pixels()));
    await File(input.filePath).writeAsBytes(img.encodePng(_solid(32, 24)));
    await invalid(input);
  });

  test('rejects corrupt PNG IDAT with otherwise truthful claims', () async {
    final bytes = img.encodePng(_pixels());
    final offset = _pngChunkOffset(bytes, 'IDAT');
    bytes[offset + 8] ^= 0x80; // Damage actual compressed bytes; CRC no longer fits.
    await invalid(await source(bytes));
  });

  test('rejects truncated PNG data without leaking an output', () async {
    final bytes = img.encodePng(_pixels());
    final offset = _pngChunkOffset(bytes, 'IDAT');
    await invalid(await source(Uint8List.sublistView(bytes, 0, offset + 10)));
  });

  test('rejects empty source bytes', () async {
    await invalid(await source(Uint8List(0)));
  });

  test('rejects enormous PNG header dimensions despite small claimed dimensions',
      () async {
    final bytes = _pngDimensions(img.encodePng(_pixels()), 0x7fffffff, 0x7fffffff);
    // Keep the actual malicious fixture tiny; never allocate its claimed raster.
    expect(bytes.length, lessThan(4096));
    await invalid(await source(bytes));
  });

  test('rejects zero PNG header dimensions', () async {
    final bytes = _pngDimensions(img.encodePng(_pixels()), 0, 24);
    await invalid(await source(bytes));
  });

  for (final field in ['width', 'frameCount', 'durationMs']) {
    test('rejects false canonical WebP descriptor $field', () async {
      final bytes = img.encodeWebP(_animation([83, 83]));
      final input = await source(bytes,
          mime: 'image/webp', frameCount: 2, durationMs: 166);
      await invalid(_with(input,
          width: field == 'width' ? 31 : null,
          frameCount: field == 'frameCount' ? 1 : null,
          durationMs: field == 'durationMs' ? 165 : null));
    });
  }

  test('rejects static WebP falsely claiming nonzero duration', () async {
    final input = await source(img.encodeWebP(_pixels()),
        mime: 'image/webp', durationMs: 1);
    await invalid(input);
  });

  for (final dimensions in [(513, 24), (32, 513)]) {
    test('rejects actual WebP dimension ${dimensions.$1}x${dimensions.$2}',
        () async {
      final bytes = img.encodeWebP(_solid(dimensions.$1, dimensions.$2));
      await invalid(await source(bytes,
          mime: 'image/webp', width: dimensions.$1, height: dimensions.$2));
    });
  }

  test('rejects real 25-frame WebP even when the descriptor claims 24', () async {
    final bytes = img.encodeWebP(_animation(List<int>.filled(25, 80)));
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 24, durationMs: 2000));
  });

  test('rejects real duration 2001ms even when the descriptor claims 2000ms',
      () async {
    final bytes = img.encodeWebP(_animation([1000, 1001]));
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 2, durationMs: 2000));
  });

  test('rejects truthful out-of-contract WebP frame count and duration', () async {
    final bytes = img.encodeWebP(_animation(List<int>.filled(25, 81)));
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 25, durationMs: 2025));
  });

  test('rejects genuine static WebP above 256KiB despite fitting animated budget',
      () async {
    final bytes = img.encodeWebP(_noise(384, 384, seed: 71));
    expect(bytes.length, inInclusiveRange(262145, 524288),
        reason: 'fixture must specifically distinguish static vs animated limits');
    await invalid(await source(bytes,
        mime: 'image/webp', width: 384, height: 384));
  });

  test('rejects genuine animated WebP above 512KiB', () async {
    final frames = _noise(320, 320, seed: 5)..frameDuration = 83;
    frames.addFrame(_noise(320, 320, seed: 6)..frameDuration = 83);
    final bytes = img.encodeWebP(frames);
    expect(bytes.length, greaterThan(524288));
    await invalid(await source(bytes,
        mime: 'image/webp', width: 320, height: 320,
        frameCount: 2, durationMs: 166));
  });

  test('rejects truncated WebP instead of trusting its valid container prefix',
      () async {
    final bytes = img.encodeWebP(_pixels());
    final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 5);
    await invalid(await source(truncated, mime: 'image/webp'));
  });

  test('rejects undeclared trailing bytes after the WebP RIFF extent', () async {
    final bytes = Uint8List.fromList([
      ...img.encodeWebP(_pixels()),
      ...ascii.encode('fixture-private-trailing-data'),
    ]);
    await invalid(await source(bytes, mime: 'image/webp'));
  });

  test('rejects a WebP chunk length that overruns its real bounded file', () async {
    final bytes = img.encodeWebP(_pixels());
    ByteData.sublistView(bytes).setUint32(16, 0xfffffff0, Endian.little);
    await invalid(await source(bytes, mime: 'image/webp'));
  });

  test('rejects a corrupt later WebP frame instead of accepting a decoder skip',
      () async {
    final bytes = img.encodeWebP(_animation([83, 83]));
    final frames = _webpChunks(bytes).where((chunk) => chunk.tag == 'ANMF').toList();
    // ANMF has a 16-byte frame header then VP8L's 8-byte chunk header.
    final payload = frames.last.dataOffset + 16 + 8;
    expect(bytes[payload], 0x2f, reason: 'fixture must corrupt VP8L signature');
    bytes[payload] = 0;
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 2, durationMs: 166));
  });

  for (final fixture in [
    (tag: 'VP8L', lossless: true, width: 513),
    (tag: 'VP8 ', lossless: false, width: 600),
  ]) {
    test(
        'rejects ${fixture.tag.trim()} dimensions ${fixture.width}x24 hidden '
        'inside a 32x24 animation frame', () async {
      // Encode a genuinely valid, modest-size bitstream. Patching only its
      // dimensions would also corrupt the compressed raster and weaken causality.
      final donor = img.encodeWebP(
        _solid(fixture.width, 24),
        lossless: fixture.lossless,
        quality: 80,
      );
      expect(_webpChunks(donor).single.tag, fixture.tag);
      final donorImage = img.decodeWebP(donor)!;
      expect((donorImage.width, donorImage.height), (fixture.width, 24));
      final original = img.encodeWebP(_animation([83, 83]));
      final bytes = _replaceLastFramePayload(
        original,
        Uint8List.sublistView(donor, 12),
      );
      _webpChunks(bytes); // RIFF and outer chunk extents remain valid.
      final info = img.WebPDecoder().startDecode(bytes)!;
      expect((info.width, info.height), (32, 24));
      expect(info.frames.length, 2);
      expect(info.frames.map((frame) => (frame.width, frame.height)),
          everyElement((32, 24)));
      expect(bytes.length, lessThan(16384));
      await invalid(await source(bytes,
          mime: 'image/webp', frameCount: 2, durationMs: 166));
    });
  }

  test('rejects an inner WebP chunk extent crossing its enclosing ANMF boundary',
      () async {
    final bytes = img.encodeWebP(_animation([83, 83]));
    final frame = _webpChunks(bytes).firstWhere((chunk) => chunk.tag == 'ANMF');
    final inner = frame.dataOffset + 16;
    expect(ascii.decode(bytes.sublist(inner, inner + 4)), 'VP8L');
    // Overrun just this frame, not the entire file. A top-level RIFF extent
    // check cannot detect the nested chunk consuming bytes from the next ANMF.
    final declaredSize = frame.size;
    expect(inner + 8 + declaredSize,
        greaterThan(frame.dataOffset + frame.size));
    expect(inner + 8 + declaredSize, lessThan(bytes.length));
    ByteData.sublistView(bytes)
        .setUint32(inner + 4, declaredSize, Endian.little);
    _webpChunks(bytes);
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 2, durationMs: 166));
  });

  test('rejects enormous WebP canvas dimensions before decoding frame rasters',
      () async {
    final bytes = img.encodeWebP(_animation([83, 83]));
    final canvas = _webpChunks(bytes).singleWhere((chunk) => chunk.tag == 'VP8X');
    // VP8X's three-byte dimensions store size minus one.
    bytes.fillRange(canvas.dataOffset + 4, canvas.dataOffset + 10, 0xff);
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 2, durationMs: 166));
  });

  test('rejects a frame rectangle that exceeds its otherwise bounded canvas',
      () async {
    final bytes = img.encodeWebP(_animation([83, 83]));
    final frame = _webpChunks(bytes).lastWhere((chunk) => chunk.tag == 'ANMF');
    bytes[frame.dataOffset + 6] = 0; // ANMF width minus one = 512.
    bytes[frame.dataOffset + 7] = 2;
    bytes[frame.dataOffset + 8] = 0;
    await invalid(await source(bytes,
        mime: 'image/webp', frameCount: 2, durationMs: 166));
  });
}

NormalizedStickerAsset _with(
  NormalizedStickerAsset asset, {
  String? sha256Hex,
  String? mime,
  int? byteLength,
  int? width,
  int? height,
  int? frameCount,
  int? durationMs,
}) => NormalizedStickerAsset(
  filePath: asset.filePath,
  sha256Hex: sha256Hex ?? asset.sha256Hex,
  mime: mime ?? asset.mime,
  byteLength: byteLength ?? asset.byteLength,
  width: width ?? asset.width,
  height: height ?? asset.height,
  frameCount: frameCount ?? asset.frameCount,
  durationMs: durationMs ?? asset.durationMs,
  posterPath: asset.posterPath,
);

img.Image _pixels({(int, int, int) hiddenRgb = (0, 0, 0)}) {
  final image = img.Image(width: 32, height: 24, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (x < 2 || y < 2 || x >= 30 || y >= 22) {
        image.setPixelRgba(x, y, hiddenRgb.$1, hiddenRgb.$2, hiddenRgb.$3, 0);
      } else if (y < 12 && x < 16) {
        image.setPixelRgba(x, y, 240, 16, 16, 128);
      } else if (y < 12) {
        image.setPixelRgba(x, y, 16, 240, 16, 255);
      } else if (x < 16) {
        image.setPixelRgba(x, y, 16, 16, 240, 255);
      } else {
        image.setPixelRgba(x, y, 230, 210, 20, 64);
      }
    }
  }
  return image;
}

img.Image _solid(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (final pixel in image) {
    pixel.setRgba(90, 140, 210, 255);
  }
  return image;
}

img.Image _noise(int width, int height, {required int seed}) {
  final random = Random(seed);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  return image;
}

img.Image _animation(List<int> durations) {
  final image = _pixels()..frameDuration = durations.first;
  for (var i = 1; i < durations.length; i++) {
    final frame = _pixels()..frameDuration = durations[i];
    frame.setPixelRgba(18, 16, (i * 31) & 255, 100, 180, 255);
    image.addFrame(frame);
  }
  return image;
}

Future<Map<String, String>> _tree(Directory root) async {
  final result = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final key = p.relative(entity.path, from: root.path);
    result[key] = entity is File
        ? 'file:${sha256.convert(await entity.readAsBytes())}'
        : entity is Link ? 'link:${await entity.target()}' : 'directory';
  }
  return result;
}

// Fixture-only container inspection: checks full RIFF length, boundaries and
// padding independently of the image decoder, which can skip unknown chunks.
List<({String tag, int dataOffset, int size})> _webpChunks(Uint8List bytes) {
  expect(bytes.length, greaterThanOrEqualTo(12));
  expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
  expect(ascii.decode(bytes.sublist(8, 12)), 'WEBP');
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(4, Endian.little) + 8, bytes.length);
  final chunks = <({String tag, int dataOffset, int size})>[];
  var offset = 12;
  while (offset < bytes.length) {
    expect(offset + 8, lessThanOrEqualTo(bytes.length));
    final tag = ascii.decode(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    expect(offset + 8 + size + (size & 1), lessThanOrEqualTo(bytes.length));
    chunks.add((tag: tag, dataOffset: offset + 8, size: size));
    offset += 8 + size + (size & 1);
  }
  expect(offset, bytes.length);
  return chunks;
}

Uint8List _replaceLastFramePayload(Uint8List webp, Uint8List frameChunks) {
  final frame = _webpChunks(webp).lastWhere((chunk) => chunk.tag == 'ANMF');
  final size = 16 + frameChunks.length;
  final chunk = Uint8List(8 + size + (size & 1));
  chunk.setAll(0, ascii.encode('ANMF'));
  ByteData.sublistView(chunk).setUint32(4, size, Endian.little);
  // Keep the outer frame rectangle, duration, disposal and blend flags intact.
  chunk.setRange(8, 24, webp, frame.dataOffset);
  chunk.setAll(24, frameChunks);
  final bytes = Uint8List.fromList([
    ...webp.take(frame.dataOffset - 8),
    ...chunk,
    ...webp.skip(frame.dataOffset + frame.size + (frame.size & 1)),
  ]);
  ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
  return bytes;
}

int _pngChunkOffset(Uint8List bytes, String wanted) {
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final size = data.getUint32(offset, Endian.big);
    final tag = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (tag == wanted) return offset;
    offset += size + 12;
  }
  throw StateError('PNG fixture has no $wanted chunk');
}

Uint8List _pngChunk(String tag, List<int> payload) {
  final bytes = Uint8List(payload.length + 12);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, payload.length, Endian.big);
  bytes.setAll(4, ascii.encode(tag));
  bytes.setAll(8, payload);
  data.setUint32(bytes.length - 4,
      _crc32(Uint8List.sublistView(bytes, 4, bytes.length - 4)), Endian.big);
  return bytes;
}

Uint8List _insertPngChunk(Uint8List png, String tag, List<int> payload) =>
    Uint8List.fromList([
      ...png.take(33), // PNG signature plus complete IHDR.
      ..._pngChunk(tag, payload),
      ...png.skip(33),
    ]);

Uint8List _pngDimensions(Uint8List png, int width, int height) {
  final payload = Uint8List.fromList(png.sublist(16, 29));
  final data = ByteData.sublistView(payload);
  data.setUint32(0, width, Endian.big);
  data.setUint32(4, height, Endian.big);
  return Uint8List.fromList([
    ...png.take(8),
    ..._pngChunk('IHDR', payload),
    ...png.skip(33),
  ]);
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _privateExif({int orientation = 1}) {
  final exif = img.ExifData();
  exif.imageIfd
    ..orientation = orientation
    ..imageDescription = 'fixture-private-description';
  exif.exifIfd[0x927c] = img.IfdValueUndefined.list(
      ascii.encode('fixture-private-maker-note'));
  exif.gpsIfd
    ..gpsLatitudeRef = 'N'
    ..gpsLatitude = 1.25
    ..gpsLongitudeRef = 'E'
    ..gpsLongitude = 2.5;
  exif.thumbnailIfd.imageDescription = 'fixture-private-thumbnail';
  final output = img.OutputBuffer();
  exif.write(output);
  return output.getBytes();
}

// Metadata is forbidden by presence, so the ICC fixture only needs a bounded
// profile header; this test makes no claim to exercise colour conversion.
Uint8List _profile() {
  final profile = Uint8List(128);
  ByteData.sublistView(profile).setUint32(0, profile.length, Endian.big);
  profile.setAll(16, ascii.encode('RGB '));
  profile.setAll(20, ascii.encode('XYZ '));
  profile.setAll(36, ascii.encode('acsp'));
  return profile;
}

Uint8List _appendWebpChunk(Uint8List webp, String tag, List<int> payload) {
  final bytes = Uint8List(webp.length + 8 + payload.length + (payload.length & 1));
  final chunks = _webpChunks(webp);
  final extended = chunks.singleWhere((chunk) => chunk.tag == 'VP8X');
  // ICCP belongs before the image bitstream; EXIF/XMP belong after it.
  final insertion = tag == 'ICCP'
      ? extended.dataOffset + extended.size + (extended.size & 1)
      : webp.length;
  bytes.setRange(0, insertion, webp);
  bytes.setRange(insertion + bytes.length - webp.length, bytes.length,
      webp, insertion);
  final flag = switch (tag) {
    'EXIF' => 0x08,
    'XMP ' => 0x04,
    'ICCP' => 0x20,
    _ => 0,
  };
  bytes[extended.dataOffset] |= flag;
  bytes.setAll(insertion, ascii.encode(tag));
  final data = ByteData.sublistView(bytes);
  data.setUint32(insertion + 4, payload.length, Endian.little);
  bytes.setAll(insertion + 8, payload);
  data.setUint32(4, bytes.length - 8, Endian.little);
  return bytes;
}
