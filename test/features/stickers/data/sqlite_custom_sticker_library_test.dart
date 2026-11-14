import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/stickers/application/normalize_custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _byteQuota = 50 * 1024 * 1024;
const _animationByteLimit = 512 * 1024;

Matcher _error(CustomStickerErrorCode code) =>
    isA<CustomStickerException>().having((error) => error.code, 'code', code);

img.Image _pixels(int variant) {
  final image = img.Image(width: 16, height: 16, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final channels = [16 + x, 16 + y, 24];
      channels[variant % 3] = 235;
      image.setPixelRgba(x, y, channels[0], channels[1], channels[2], 255);
    }
  }
  return image;
}

Future<List<String>> _files(Directory directory) async {
  if (!await directory.exists()) return <String>[];
  final entries = await directory
      .list(recursive: true, followLinks: false)
      .where((entry) => entry is File || entry is Link)
      .map((entry) => p.relative(entry.path, from: directory.path))
      .toList();
  return entries..sort();
}

Future<Object> _outcome(Future<CustomSticker> operation) =>
    operation.then<Object>((value) => value, onError: (Object error) => error);

/// Pause only the first operation, after actual byte normalization. A serial
/// library must not need a second normalization to reach this test's release.
final class _NormalizerGate {
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;

  Future<NormalizedStickerAsset> call(
    NormalizedStickerAsset input, {
    required Directory temporaryDirectory,
  }) async {
    final callNumber = ++calls;
    final normalized = await normalizeCustomStickerAsset(
      input,
      temporaryDirectory: temporaryDirectory,
    );
    if (callNumber == 1) {
      entered.complete();
      await release.future;
    }
    return normalized;
  }

  Future<void> waitUntilEntered(Future<Object> admission) => Future.any<void>([
    entered.future,
    admission.then<void>((outcome) {
      fail('Admission finished before the real normalizer gate: $outcome');
    }),
  ]);

  void unblock() {
    if (!release.isCompleted) release.complete();
  }
}

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Directory documents;
  late Directory temporary;
  late Directory producer;
  late Database db;
  late List<SqliteCustomStickerLibrary> libraries;
  late List<StreamSubscription<void>> subscriptions;
  late bool accountAvailable;
  late int sourceNumber;

  SqliteCustomStickerLibrary library({_NormalizerGate? gate}) {
    final value = SqliteCustomStickerLibrary(
      db: db,
      documentsDirectory: documents,
      temporaryDirectory: temporary,
      mayUseAccount: () async => accountAvailable,
      enabled: true,
      normalizeAsset: gate?.call,
    );
    libraries.add(value);
    return value;
  }

  List<int> observe(SqliteCustomStickerLibrary value) {
    final events = <int>[];
    subscriptions.add(value.changes.listen((_) => events.add(events.length)));
    return events;
  }

  Future<void> settle(SqliteCustomStickerLibrary value) async {
    await value.drain();
    await Future<void>.delayed(Duration.zero);
  }

  Future<NormalizedStickerAsset> input(
    int variant, {
    bool webp = false,
    String? comment,
  }) async {
    final pixels = _pixels(variant);
    if (comment != null) pixels.textData = {'Comment': comment};
    final bytes = webp
        ? img.encodeWebP(pixels, lossless: true)
        : img.encodePng(pixels);
    final extension = webp ? 'webp' : 'png';
    final path = p.join(producer.path, 'source-${sourceNumber++}.$extension');
    await File(path).writeAsBytes(bytes, flush: true);
    return NormalizedStickerAsset(
      filePath: path,
      sha256Hex: sha256.convert(bytes).toString(),
      mime: webp ? 'image/webp' : 'image/png',
      byteLength: bytes.length,
      width: pixels.width,
      height: pixels.height,
      frameCount: 1,
      durationMs: 0,
    );
  }

  Future<List<Map<String, Object?>>> rows() =>
      db.query('custom_stickers', orderBy: 'position ASC, id ASC');

  // These are committed SQL accounting fixtures, not claims that their files
  // passed admission. Only the few explicitly admitted test items own files.
  Future<void> seedQuotaRows(
    List<int> byteLengths, {
    bool animated = false,
    int firstPosition = 1,
  }) async {
    final batch = db.batch();
    for (var index = 0; index < byteLengths.length; index++) {
      final hash = (1000 + index).toRadixString(16).padLeft(64, '0');
      batch.insert('custom_stickers', <String, Object?>{
        'id': 'quota-row-$index',
        'content_sha256': hash,
        'relative_path': 'stickers/$hash.webp',
        'mime': 'image/webp',
        'size_bytes': byteLengths[index],
        'width': 512,
        'height': 512,
        'frame_count': animated ? 2 : 1,
        'duration_ms': animated ? 166 : 0,
        'created_at_ms': 1700000000000 + index,
        'last_used_at_ms': 1700000000000 + index,
        'position': firstPosition + index,
      });
    }
    await batch.commit(noResult: true);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sqlite-sticker-library-');
    documents = await Directory(p.join(root.path, 'documents')).create();
    temporary = await Directory(p.join(root.path, 'temporary')).create();
    producer = await Directory(p.join(root.path, 'producer')).create();
    await File(p.join(temporary.path, 'unrelated.txt'))
        .writeAsString('not owned by the library');
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      p.join(root.path, 'identity.db'),
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    libraries = <SqliteCustomStickerLibrary>[];
    subscriptions = <StreamSubscription<void>>[];
    sourceNumber = 0;
    accountAvailable = true;
    expect(
      await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'custom_stickers'],
      ),
      hasLength(1),
      reason: 'Prerequisite: migration130 must be green before library RED.',
    );
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final value in libraries) {
      await value.retire();
    }
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'the default-disabled build refuses mutations and send preparation',
    () async {
      expect(
        kCustomStickersEnabled,
        isFalse,
        reason:
            'Run this suite without a flag or with the explicit false flag.',
      );
      final value = SqliteCustomStickerLibrary(
        db: db,
        documentsDirectory: documents,
        temporaryDirectory: temporary,
        mayUseAccount: () async => accountAvailable,
      );
      libraries.add(value);
      final events = observe(value);
      final source = await input(1);
      final original = await File(source.filePath).readAsBytes();
      final temporaryBefore = await _files(temporary);

      await expectLater(
        value.admit(source),
        throwsA(_error(CustomStickerErrorCode.disabled)),
      );
      await expectLater(
        value.remove('missing'),
        throwsA(_error(CustomStickerErrorCode.disabled)),
      );
      await expectLater(
        value.reorder(const <String>[]),
        throwsA(_error(CustomStickerErrorCode.disabled)),
      );
      await expectLater(
        value.prepareSend(
          'missing',
          representation: CustomStickerSendRepresentation.canonical,
        ),
        throwsA(_error(CustomStickerErrorCode.disabled)),
      );
      await settle(value);
      expect(await rows(), isEmpty);
      expect(await _files(documents), isEmpty);
      expect(await _files(temporary), temporaryBefore);
      expect(
        await File(source.filePath).readAsBytes(),
        orderedEquals(original),
      );
      expect(events, isEmpty);
    },
  );

  test(
    'PNG admission owns a distinct canonical copy and preserves the caller',
    () async {
      final value = library();
      final events = observe(value);
      final source = await input(1);
      final original = await File(source.filePath).readAsBytes();
      final temporaryBefore = await _files(temporary);
      final stored = await value.admit(source);
      final canonical = await File(stored.asset.filePath).readAsBytes();

      expect(
        p.isWithin(p.join(documents.path, 'stickers'), stored.asset.filePath),
        isTrue,
      );
      expect(stored.asset.filePath, isNot(source.filePath));
      expect(
        await File(source.filePath).readAsBytes(),
        orderedEquals(original),
      );
      expect(img.decodeWebP(canonical), isNotNull);
      expect(stored.asset.mime, 'image/webp');
      expect(stored.asset.sha256Hex, sha256.convert(canonical).toString());
      expect(stored.asset.byteLength, canonical.length);
      expect((stored.asset.width, stored.asset.height), (16, 16));
      expect((stored.asset.frameCount, stored.asset.durationMs), (1, 0));
      expect((await rows()).single['content_sha256'], stored.asset.sha256Hex);

      await File(source.filePath).writeAsBytes(img.encodePng(_pixels(2)));
      expect(
        await File(stored.asset.filePath).readAsBytes(),
        orderedEquals(canonical),
      );
      await File(source.filePath).delete();
      expect(
        await File(stored.asset.filePath).readAsBytes(),
        orderedEquals(canonical),
      );
      await settle(value);
      expect(await _files(temporary), temporaryBefore);
      expect(events, hasLength(1));
    },
  );

  test('real WebP admission and list restore the same durable item', () async {
    final value = library();
    final source = await input(2, webp: true);
    final stored = await value.admit(source);
    await value.retire();
    final restored = (await library().list()).single;

    expect(restored.id, stored.id);
    expect(restored.position, stored.position);
    expect(restored.createdAtMs, stored.createdAtMs);
    expect(restored.lastUsedAtMs, stored.lastUsedAtMs);
    expect(restored.asset.filePath, stored.asset.filePath);
    expect(restored.asset.sha256Hex, stored.asset.sha256Hex);
    expect(restored.asset.byteLength, stored.asset.byteLength);
    expect(
      (
        restored.asset.mime,
        restored.asset.width,
        restored.asset.height,
        restored.asset.frameCount,
        restored.asset.durationMs,
      ),
      (
        stored.asset.mime,
        stored.asset.width,
        stored.asset.height,
        stored.asset.frameCount,
        stored.asset.durationMs,
      ),
    );
    expect(
      img.decodeWebP(await File(restored.asset.filePath).readAsBytes()),
      isNotNull,
    );
    expect(await File(source.filePath).exists(), isTrue);
  });

  test('canonical-content dedup preserves the chosen user order', () async {
    final value = library();
    final firstSource = await input(1, comment: 'discard source comment A');
    final first = await value.admit(firstSource);
    final second = await value.admit(await input(2));
    final third = await value.admit(await input(3));
    final chosenOrder = [second.id, first.id, third.id];
    await value.reorder(chosenOrder);
    final filesBefore = await _files(documents);
    final duplicateSource = await input(1, comment: 'discard source comment B');
    expect(duplicateSource.sha256Hex, isNot(firstSource.sha256Hex));

    final duplicate = await value.admit(duplicateSource);
    expect(duplicate.id, first.id);
    expect(duplicate.asset.sha256Hex, first.asset.sha256Hex);
    expect(duplicate.asset.filePath, first.asset.filePath);
    expect(duplicate.position, 1);
    final listed = await value.list();
    expect(listed.map((item) => item.id), chosenOrder);
    expect(listed.map((item) => item.position), [0, 1, 2]);
    expect(await rows(), hasLength(3));
    expect(await _files(documents), filesBefore);
    expect(await File(duplicateSource.filePath).exists(), isTrue);
  });

  for (final byteLimit in [false, true]) {
    final label = byteLimit ? '50MiB' : '200-item';
    final code = byteLimit
        ? CustomStickerErrorCode.byteQuota
        : CustomStickerErrorCode.countQuota;
    test('$label quota uses committed rows but still permits dedup', () async {
      final value = library();
      final existingSource = await input(1);
      final existing = await value.admit(existingSource);
      if (byteLimit) {
        // 101 total rows, so countQuota cannot accidentally satisfy this test.
        await seedQuotaRows([
          ...List<int>.filled(99, _animationByteLimit),
          _animationByteLimit - existing.asset.byteLength,
        ], animated: true);
      } else {
        await seedQuotaRows(List<int>.filled(199, 128));
      }
      final before = await rows();
      final bytesBefore = before.fold<int>(
        0,
        (sum, row) => sum + (row['size_bytes'] as int),
      );
      expect(before.length, byteLimit ? 101 : 200);
      expect(
        bytesBefore,
        byteLimit ? equals(_byteQuota) : lessThan(_byteQuota),
      );
      final filesBefore = await _files(documents);
      final temporaryBefore = await _files(temporary);
      final rejectedSource = await input(2);

      await expectLater(value.admit(rejectedSource), throwsA(_error(code)));
      expect(await rows(), before);
      expect(await _files(documents), filesBefore);
      expect(await _files(temporary), temporaryBefore);
      expect(await File(rejectedSource.filePath).exists(), isTrue);

      final duplicate = await value.admit(existingSource);
      expect(duplicate.id, existing.id);
      expect(duplicate.position, existing.position);
      expect(await rows(), hasLength(before.length));
      expect(await _files(documents), filesBefore);
      expect(await _files(temporary), temporaryBefore);
    });
  }

  test(
    'overlapping admissions share the last slot and failure does not poison it',
    () async {
      await seedQuotaRows(List<int>.filled(199, 128), firstPosition: 0);
      final gate = _NormalizerGate();
      addTearDown(gate.unblock);
      final value = library(gate: gate);
      final events = observe(value);
      final firstSource = await input(1);
      final secondSource = await input(2);
      final temporaryBefore = await _files(temporary);
      final first = _outcome(value.admit(firstSource));
      await gate.waitUntilEntered(first);
      final second = _outcome(value.admit(secondSource));
      var drainFinished = false;
      final drained = value.drain().then<void>((_) {
        drainFinished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        drainFinished,
        isFalse,
        reason: 'drain must wait for the admitted work held at the gate.',
      );
      gate.unblock();
      final outcomes = await Future.wait([first, second]);
      await drained;
      final successes = outcomes.whereType<CustomSticker>().toList();
      final failures = outcomes.whereType<CustomStickerException>().toList();
      expect(successes, hasLength(1));
      expect(failures, hasLength(1));
      expect(failures.single.code, CustomStickerErrorCode.countQuota);
      expect(await rows(), hasLength(200));
      await settle(value);
      expect(events, hasLength(1));
      expect(await _files(documents), [
        p.relative(successes.single.asset.filePath, from: documents.path),
      ]);
      expect(await _files(temporary), temporaryBefore);

      await value.remove(successes.single.id);
      final retrySource = outcomes.first is CustomSticker
          ? secondSource
          : firstSource;
      final retried = await value.admit(retrySource);
      expect(await File(retried.asset.filePath).exists(), isTrue);
      expect(await rows(), hasLength(200));
      expect(await File(firstSource.filePath).exists(), isTrue);
      expect(await File(secondSource.filePath).exists(), isTrue);
    },
  );

  test(
    'invalid and stale permutations leave every row and order unchanged',
    () async {
      final value = library();
      final events = observe(value);
      final first = await value.admit(await input(1));
      final second = await value.admit(await input(2));
      final staleOrder = [first.id, second.id];
      final third = await value.admit(await input(3));
      await settle(value);
      final before = await rows();
      final eventsBefore = events.length;
      for (final invalid in <List<String>>[
        staleOrder,
        [first.id, second.id, second.id],
        [first.id, second.id, 'unknown'],
        [third.id, second.id, first.id, 'unknown'],
        const <String>[],
      ]) {
        await expectLater(
          value.reorder(invalid),
          throwsA(_error(CustomStickerErrorCode.invalidOrder)),
        );
        expect(await rows(), before);
      }
      await settle(value);
      expect(events, hasLength(eventsBefore));
    },
  );

  test(
    'remove deletes only owned content and compacts the surviving order',
    () async {
      final value = library();
      final first = await value.admit(await input(1));
      final middleSource = await input(2);
      final middle = await value.admit(middleSource);
      final last = await value.admit(await input(3));
      await value.reorder([first.id, middle.id, last.id]);

      await value.remove(middle.id);
      final survivors = await value.list();
      expect(survivors.map((item) => item.id), [first.id, last.id]);
      expect(survivors.map((item) => item.position), [0, 1]);
      expect(await File(middle.asset.filePath).exists(), isFalse);
      expect(await File(middleSource.filePath).exists(), isTrue);
      expect(await File(first.asset.filePath).exists(), isTrue);
      expect(await File(last.asset.filePath).exists(), isTrue);
    },
  );

  test(
    'canonical and default static sends retain exact bytes after library removal',
    () async {
      final value = library();
      final stored = await value.admit(await input(1));
      final canonical = await File(stored.asset.filePath).readAsBytes();
      final prepared = [
        await value.prepareSend(
          stored.id,
          representation: CustomStickerSendRepresentation.canonical,
        ),
        await value.prepareSend(
          stored.id,
          representation: defaultCustomStickerSendRepresentation,
        ),
      ];
      expect(prepared.first.file.path, isNot(prepared.last.file.path));
      for (final send in prepared) {
        expect(send.file.path, isNot(stored.asset.filePath));
        expect(p.isWithin(temporary.path, send.file.path), isTrue);
        expect(send.budgetBytes, canonical.length);
        expect((send.width, send.height), (16, 16));
        expect(send.durationMs, 0);
        expect(await send.file.readAsBytes(), orderedEquals(canonical));
      }

      await value.remove(stored.id);
      await settle(value);
      expect(await rows(), isEmpty);
      expect(await File(stored.asset.filePath).exists(), isFalse);
      for (final send in prepared) {
        expect(await send.file.readAsBytes(), orderedEquals(canonical));
        await send.file.delete(); // The composer now owns this lifetime.
      }
    },
  );

  test(
    'default send policy preserves the first frame and leaves canonical animation intact',
    () async {
      final value = library();
      final first = _pixels(0)..frameDuration = 83;
      first.addFrame(_pixels(1)..frameDuration = 84);
      final original = img.encodeWebP(first, lossless: true);
      final sourcePath = p.join(
        producer.path,
        'source-${sourceNumber++}.webp',
      );
      await File(sourcePath).writeAsBytes(original, flush: true);
      final source = NormalizedStickerAsset(
        filePath: sourcePath,
        sha256Hex: sha256.convert(original).toString(),
        mime: 'image/webp',
        byteLength: original.length,
        width: 16,
        height: 16,
        frameCount: 2,
        durationMs: 167,
      );
      final originalImage = img.decodeWebP(original)!;
      expect(originalImage.numFrames, 2);
      expect(
        originalImage.frames.first.getBytes(order: img.ChannelOrder.rgba),
        isNot(orderedEquals(
          originalImage.frames.last.getBytes(order: img.ChannelOrder.rgba),
        )),
        reason: 'The two visual frames must differ to detect a wrong poster.',
      );
      final temporaryBefore = await _files(temporary);
      final stored = await value.admit(source);
      final rowBefore = (await rows()).single;
      final canonical = await File(stored.asset.filePath).readAsBytes();
      expect(canonical, orderedEquals(original));
      expect((stored.asset.frameCount, stored.asset.durationMs), (2, 167));
      expect((rowBefore['frame_count'], rowBefore['duration_ms']), (2, 167));

      final prepared = await value.prepareSend(
        stored.id,
        representation: defaultCustomStickerSendRepresentation,
      );
      expect(prepared.file.path, isNot(stored.asset.filePath));
      expect(prepared.file.path, isNot(source.filePath));
      expect(p.isWithin(temporary.path, prepared.file.path), isTrue);
      final posterBytes = await prepared.file.readAsBytes();
      final decodedPoster = img.decodeWebP(posterBytes);
      expect(decodedPoster, isNotNull);
      final poster = decodedPoster!;
      expect(poster.numFrames, 1);
      expect(poster.frameDuration, 0);
      expect((poster.width, poster.height), (16, 16));
      expect(posterBytes.length, lessThanOrEqualTo(256 * 1024));
      expect(prepared.budgetBytes, posterBytes.length);
      expect((prepared.width, prepared.height), (16, 16));
      expect(prepared.durationMs ?? 0, 0);
      expect(
        poster.getBytes(order: img.ChannelOrder.rgba),
        orderedEquals(
          originalImage.frames.first.getBytes(order: img.ChannelOrder.rgba),
        ),
        reason: 'This tiny lossless fixture must preserve the first visual frame.',
      );

      await settle(value);
      final unchangedBytes = await File(stored.asset.filePath).readAsBytes();
      expect(unchangedBytes, orderedEquals(canonical));
      expect(await File(source.filePath).readAsBytes(), orderedEquals(original));
      final unchangedImage = img.decodeWebP(unchangedBytes)!;
      expect(unchangedImage.numFrames, 2);
      expect(
        unchangedImage.frames.map((frame) => frame.frameDuration),
        [83, 84],
      );
      final rowAfter = (await rows()).single;
      for (final field in [
        'id',
        'content_sha256',
        'relative_path',
        'mime',
        'size_bytes',
        'width',
        'height',
        'frame_count',
        'duration_ms',
      ]) {
        expect(rowAfter[field], rowBefore[field], reason: field);
      }
      await prepared.file.delete(); // Composer-owned poster lifetime.
      expect(await _files(temporary), temporaryBefore);
      expect(
        await File(stored.asset.filePath).readAsBytes(),
        orderedEquals(canonical),
      );
    },
  );

  test(
    'stored content replacement makes canonical send unavailable without publishing bytes',
    () async {
      final value = library();
      final source = await input(0, webp: true);
      final original = await File(source.filePath).readAsBytes();
      final stored = await value.admit(source);
      final unrelated = File(p.join(documents.path, 'unrelated.txt'));
      await unrelated.writeAsString('preserve unrelated document content');
      final temporaryBefore = await _files(temporary);
      final replacement = img.encodeWebP(_pixels(1), lossless: true);
      expect(img.decodeWebP(replacement), isNotNull);
      expect(
        sha256.convert(replacement).toString(),
        isNot(stored.asset.sha256Hex),
      );
      await File(stored.asset.filePath).writeAsBytes(replacement, flush: true);

      await expectLater(
        value.prepareSend(
          stored.id,
          representation: CustomStickerSendRepresentation.canonical,
        ),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      await settle(value);
      expect(await _files(temporary), temporaryBefore);
      expect(await temporary.list(followLinks: false).length, 1);
      expect(
        await File(p.join(temporary.path, 'unrelated.txt')).readAsString(),
        'not owned by the library',
      );
      expect(
        await unrelated.readAsString(),
        'preserve unrelated document content',
      );
      expect(await File(source.filePath).readAsBytes(), orderedEquals(original));
    },
  );

  test(
    'symlinked sticker ownership root rejects admission without touching outside files',
    () async {
      final outside = await Directory(p.join(root.path, 'outside')).create();
      final canary = File(p.join(outside.path, 'canary.txt'));
      await canary.writeAsString('outside the sticker ownership boundary');
      final stickerLink = Link(p.join(documents.path, 'stickers'));
      await stickerLink.create(outside.path);
      final value = library();
      final events = observe(value);
      final source = await input(1);
      final original = await File(source.filePath).readAsBytes();
      final temporaryBefore = await _files(temporary);
      final documentsBefore = await _files(documents);

      await expectLater(
        value.admit(source),
        throwsA(_error(CustomStickerErrorCode.storageFailure)),
      );
      await settle(value);
      expect(await rows(), isEmpty);
      expect(events, isEmpty);
      expect(await _files(temporary), temporaryBefore);
      expect(await temporary.list(followLinks: false).length, 1,
          reason: 'No normalization output or owned temporary directory may leak.');
      expect(
        await File(p.join(temporary.path, 'unrelated.txt')).readAsString(),
        'not owned by the library',
      );
      expect(await File(source.filePath).readAsBytes(), orderedEquals(original));
      expect(await _files(documents), documentsBefore);
      expect(
        await FileSystemEntity.type(stickerLink.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await stickerLink.target(), outside.path);
      expect(await _files(outside), ['canary.txt']);
      expect(await outside.list(followLinks: false).length, 1);
      expect(
        await canary.readAsString(),
        'outside the sticker ownership boundary',
      );
    },
  );

  for (final retiring in [true, false]) {
    final cause = retiring ? 'retirement' : 'account revocation';
    test(
      '$cause during normalization leaves no late row, file, or event',
      () async {
        final gate = _NormalizerGate();
        addTearDown(gate.unblock);
        final value = library(gate: gate);
        final events = observe(value);
        final source = await input(1);
        final original = await File(source.filePath).readAsBytes();
        final temporaryBefore = await _files(temporary);
        final operation = _outcome(value.admit(source));
        await gate.waitUntilEntered(operation);
        Future<void>? retired;
        if (retiring) {
          var retirementFinished = false;
          retired = value.retire().then<void>((_) {
            retirementFinished = true;
          });
          await Future<void>.delayed(Duration.zero);
          expect(
            retirementFinished,
            isFalse,
            reason: 'retire must drain the operation held at the real gate.',
          );
        } else {
          accountAvailable = false;
        }
        gate.unblock();
        expect(await operation, _error(CustomStickerErrorCode.unavailable));
        if (retired != null) await retired;
        await settle(value);

        expect(await rows(), isEmpty);
        expect(await _files(documents), isEmpty);
        expect(await _files(temporary), temporaryBefore);
        expect(
          await File(source.filePath).readAsBytes(),
          orderedEquals(original),
        );
        expect(events, isEmpty);
        if (retiring) {
          await expectLater(
            value.admit(await input(2)),
            throwsA(_error(CustomStickerErrorCode.unavailable)),
          );
          expect(
            gate.calls,
            1,
            reason: 'retired libraries must not start more normalization.',
          );
        } else {
          accountAvailable = true;
          final retried = await value.admit(source);
          expect(await File(retried.asset.filePath).exists(), isTrue);
          expect(await rows(), hasLength(1));
        }
      },
    );
  }
}
