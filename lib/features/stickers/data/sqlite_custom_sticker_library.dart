import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/normalize_custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

const _table = 'custom_stickers';
const _maximumItems = 200;
const _maximumBytes = 52428800;
const _maximumAssetBytes = 524288;

/// One account's library. Account replacement/erase must retire and drain this
/// instance before closing its database or changing the owned directories.
final class SqliteCustomStickerLibrary implements CustomStickerLibrary {
  SqliteCustomStickerLibrary({
    required Database db,
    required Directory documentsDirectory,
    required Directory temporaryDirectory,
    required Future<bool> Function() mayUseAccount,
    bool enabled = kCustomStickersEnabled,
    Future<NormalizedStickerAsset> Function(
      NormalizedStickerAsset input, {
      required Directory temporaryDirectory,
    })?
    normalizeAsset,
  }) : _db = db,
       _documents = Directory(p.normalize(documentsDirectory.absolute.path)),
       _temporary = Directory(p.normalize(temporaryDirectory.absolute.path)),
       _trustedDocuments = documentsDirectory.resolveSymbolicLinksSync(),
       _trustedTemporary = temporaryDirectory.resolveSymbolicLinksSync(),
       _mayUseAccount = mayUseAccount,
       _enabled = enabled,
       _normalizeAsset = normalizeAsset ?? normalizeCustomStickerAsset;

  final Database _db;
  final Directory _documents;
  final Directory _temporary;
  final String _trustedDocuments;
  final String _trustedTemporary;
  final Future<bool> Function() _mayUseAccount;
  final bool _enabled;
  final Future<NormalizedStickerAsset> Function(
    NormalizedStickerAsset input, {
    required Directory temporaryDirectory,
  })
  _normalizeAsset;
  final Lock _lock = Lock();
  final _changes = StreamController<void>.broadcast(sync: true);
  bool _retired = false;
  Future<void>? _retirement;

  @override
  Stream<void> get changes => _changes.stream;

  /// Closes admission before yielding; queued operations observe this flag too.
  Future<void> retire() {
    _retired = true;
    return _retirement ??= drain().then<void>((_) {
      // A paused presentation subscriber must not hold an account erase barrier.
      if (!_changes.isClosed) unawaited(_changes.close());
    });
  }

  Future<void> drain() => _lock.synchronized<void>(() {});

  /// Passive account authority for core received-media preparation. This does
  /// not acquire the mutation lock or keep retirement waiting for an editor.
  Future<void> checkAccountAccess() => _checkAccess();

  @override
  Future<List<CustomSticker>> list() => _run(() async {
    _stickerRoot(create: false);
    final rows = await _db.query(_table, orderBy: 'position ASC, id ASC');
    await _checkAccess(requireEnabled: false);
    _stickerRoot(create: false);
    // Listing never prunes accounting rows or treats a missing file as deletion.
    return rows.map(_hydrate).toList(growable: false);
  }, requireEnabled: false);

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) => _run(() async {
    _stickerRoot(create: false);
    Directory? scratch;
    File? ownedFile;
    var keepFile = false;
    var committed = false;
    List<Map<String, Object?>> positionsBefore = const [];
    String? insertedId;
    try {
      scratch = _scratch();
      final normalized = await _normalizeAsset(
        asset,
        temporaryDirectory: scratch,
      );
      await _checkAccess();
      final bytes = _normalizedBytes(normalized, scratch);
      final hash = sha256.convert(bytes).toString();

      final matches = await _db.query(
        _table,
        where: 'content_sha256 = ?',
        whereArgs: [hash],
      );
      await _checkAccess();
      if (matches.isNotEmpty) {
        final existing = _hydrate(matches.single);
        _deleteScratch(scratch);
        scratch = null;
        await _checkAccess();
        _storedBytes(existing.asset);
        return existing;
      }
      await _checkQuota(_db, bytes.length);
      await _checkAccess();

      final id = const Uuid().v4();
      final relativePath = 'stickers/$id.webp';
      final directory = _stickerRoot(create: true)!;
      ownedFile = _writeNewFile(directory, '$id.webp', bytes);
      await _checkAccess();
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = <String, Object?>{
        'id': id,
        'content_sha256': hash,
        'relative_path': relativePath,
        'mime': 'image/webp',
        'size_bytes': bytes.length,
        'width': normalized.width,
        'height': normalized.height,
        'frame_count': normalized.frameCount,
        'duration_ms': normalized.durationMs,
        'created_at_ms': now,
        'last_used_at_ms': now,
        'position': 0,
      };
      Map<String, Object?>? duplicate;
      await dbWriteTransaction(_db, (transaction) async {
        _checkLocal();
        final existing = await transaction.query(
          _table,
          where: 'content_sha256 = ?',
          whereArgs: [hash],
        );
        if (existing.isNotEmpty) {
          duplicate = existing.single;
          _checkLocal();
          return;
        }
        await _checkQuota(transaction, bytes.length);
        positionsBefore = await _positions(transaction);
        await transaction.rawUpdate(
          'UPDATE $_table SET position = position + 1',
        );
        _checkLocal();
        await transaction.insert(_table, row);
        _checkLocal();
      });
      if (duplicate != null) {
        final existing = _hydrate(duplicate!);
        _deleteOwnedFile(ownedFile, inDocuments: true);
        ownedFile = null;
        _deleteScratch(scratch);
        scratch = null;
        await _checkAccess();
        _storedBytes(existing.asset);
        return existing;
      }
      committed = true;
      insertedId = id;
      _deleteScratch(scratch);
      scratch = null;
      await _checkAccess();
      final result = _hydrate(row);
      _storedBytes(result.asset);
      keepFile = true;
      _changes.add(null);
      return result;
    } catch (_) {
      if (committed) {
        try {
          await dbWriteTransaction(_db, (transaction) async {
            await transaction.delete(
              _table,
              where: 'id = ?',
              whereArgs: [insertedId],
            );
            await _restorePositions(transaction, positionsBefore);
          });
        } catch (_) {
          // If compensation itself fails, preserve the file backing that row.
          keepFile = true;
          rethrow;
        }
      }
      rethrow;
    } finally {
      try {
        if (ownedFile != null && !keepFile) {
          _deleteOwnedFile(ownedFile, inDocuments: true);
        }
      } finally {
        if (scratch != null) _deleteScratch(scratch);
      }
    }
  });

  @override
  Future<void> remove(String id) => _run(() async {
    final matches = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
    await _checkAccess();
    if (matches.isEmpty) return;
    final removedRow = matches.single;
    final file = _ownedFile(
      removedRow['relative_path'] as String,
      allowMissing: true,
    );
    List<Map<String, Object?>> positionsBefore = const [];
    var committed = false;
    try {
      await dbWriteTransaction(_db, (transaction) async {
        _checkLocal();
        positionsBefore = await _positions(transaction);
        await transaction.delete(_table, where: 'id = ?', whereArgs: [id]);
        final remaining = positionsBefore
            .where((row) => row['id'] != id)
            .toList(growable: false);
        for (var index = 0; index < remaining.length; index++) {
          await transaction.update(
            _table,
            {'position': index},
            where: 'id = ?',
            whereArgs: [remaining[index]['id']],
          );
        }
        _checkLocal();
      });
      committed = true;
      await _checkAccess();
      _deleteOwnedFile(file, inDocuments: true);
      // No asynchronous gap between this owned-file deletion and publication.
      _changes.add(null);
    } catch (_) {
      if (committed) {
        await dbWriteTransaction(_db, (transaction) async {
          await transaction.insert(_table, removedRow);
          await _restorePositions(transaction, positionsBefore);
        });
      }
      rethrow;
    }
  });

  @override
  Future<void> reorder(List<String> orderedIds) {
    final requested = List<String>.of(orderedIds);
    return _run(() async {
      List<Map<String, Object?>> positionsBefore = const [];
      var changed = false;
      var committed = false;
      try {
        await dbWriteTransaction(_db, (transaction) async {
          _checkLocal();
          positionsBefore = await _positions(transaction);
          final actualIds = positionsBefore.map((row) => row['id']).toSet();
          if (requested.length != actualIds.length ||
              requested.toSet().length != requested.length ||
              !actualIds.containsAll(requested)) {
            _fail(CustomStickerErrorCode.invalidOrder);
          }
          final oldPositions = {
            for (final row in positionsBefore) row['id']: row['position'],
          };
          for (var index = 0; index < requested.length; index++) {
            if (oldPositions[requested[index]] == index) continue;
            changed = true;
            await transaction.update(
              _table,
              {'position': index},
              where: 'id = ?',
              whereArgs: [requested[index]],
            );
          }
          _checkLocal();
        });
        committed = changed;
        await _checkAccess();
        if (changed) _changes.add(null);
      } catch (_) {
        if (committed) {
          await dbWriteTransaction(
            _db,
            (transaction) => _restorePositions(transaction, positionsBefore),
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  }) => _run(() async {
    final matches = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
    await _checkAccess();
    if (matches.isEmpty) _fail(CustomStickerErrorCode.unavailable);
    final stored = _hydrate(matches.single);
    _storedBytes(stored.asset);
    Directory? scratch;
    File? output;
    var published = false;
    var usageCommitted = false;
    var previousUsage = stored.lastUsedAtMs;
    try {
      scratch = _scratch();
      NormalizedStickerAsset canonical;
      try {
        // This real validator checks the stored byte length, hash, structure,
        // metadata and decoded claims; a row alone is not a send capability.
        canonical = await normalizeCustomStickerAsset(
          stored.asset,
          temporaryDirectory: scratch,
        );
      } on CustomStickerException catch (error) {
        if (error.code == CustomStickerErrorCode.invalidAsset) {
          _fail(CustomStickerErrorCode.unavailable);
        }
        rethrow;
      }
      await _checkAccess();
      _ownedFile(p.relative(stored.asset.filePath, from: _documents.path));
      var bytes = _normalizedBytes(canonical, scratch);
      var duration = stored.asset.durationMs;
      if (representation == CustomStickerSendRepresentation.staticPoster &&
          stored.asset.isAnimated) {
        final pngBytes = await _posterPng(bytes);
        await _checkAccess();
        _checkScratch(scratch);
        final png = _writeNewFile(scratch, 'first-frame.png', pngBytes);
        canonical = await normalizeCustomStickerAsset(
          NormalizedStickerAsset(
            filePath: png.path,
            sha256Hex: sha256.convert(pngBytes).toString(),
            mime: 'image/png',
            byteLength: pngBytes.length,
            width: stored.asset.width,
            height: stored.asset.height,
            frameCount: 1,
            durationMs: 0,
          ),
          temporaryDirectory: scratch,
        );
        await _checkAccess();
        bytes = _normalizedBytes(canonical, scratch);
        duration = 0;
      }
      await _checkAccess();
      final now = DateTime.now().millisecondsSinceEpoch;
      await dbWriteTransaction(_db, (transaction) async {
        _checkLocal();
        final current = await transaction.query(
          _table,
          columns: ['last_used_at_ms'],
          where: 'id = ? AND content_sha256 = ?',
          whereArgs: [id, stored.asset.sha256Hex],
        );
        if (current.isEmpty) _fail(CustomStickerErrorCode.unavailable);
        previousUsage = current.single['last_used_at_ms'] as int;
        await transaction.update(
          _table,
          {'last_used_at_ms': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        _checkLocal();
      });
      usageCommitted = true;
      _deleteScratch(scratch);
      scratch = null;
      await _checkAccess();
      _checkTemporaryRoot();
      // Publish only after the final asynchronous gate; this bounded copy and
      // ownership transfer have no suspension point in which retirement can win.
      output = _writeNewFile(
        _temporary,
        'sticker-send-${const Uuid().v4()}.webp',
        bytes,
      );
      final result = PendingComposerMedia(
        file: output,
        budgetBytes: bytes.length,
        width: stored.asset.width,
        height: stored.asset.height,
        durationMs: duration,
      );
      published = true;
      if (previousUsage != now) _changes.add(null);
      return result;
    } catch (_) {
      if (usageCommitted) {
        await dbWriteTransaction(_db, (transaction) async {
          await transaction.update(
            _table,
            {'last_used_at_ms': previousUsage},
            where: 'id = ?',
            whereArgs: [id],
          );
        });
      }
      rethrow;
    } finally {
      try {
        if (output != null && !published) {
          _deleteOwnedFile(output, inDocuments: false);
        }
      } finally {
        if (scratch != null) _deleteScratch(scratch);
      }
    }
  });

  Future<T> _run<T>(Future<T> Function() body, {bool requireEnabled = true}) {
    try {
      _checkLocal(requireEnabled: requireEnabled);
    } catch (error, stack) {
      return Future<T>.error(error, stack);
    }
    return _lock.synchronized<T>(() async {
      try {
        await _checkAccess(requireEnabled: requireEnabled);
        return await body();
      } on CustomStickerException {
        rethrow;
      } catch (_) {
        _fail(CustomStickerErrorCode.storageFailure);
      }
    });
  }

  void _checkLocal({bool requireEnabled = true}) {
    if (_retired) _fail(CustomStickerErrorCode.unavailable);
    if (requireEnabled && !_enabled) _fail(CustomStickerErrorCode.disabled);
  }

  Future<void> _checkAccess({bool requireEnabled = true}) async {
    _checkLocal(requireEnabled: requireEnabled);
    final bool allowed;
    try {
      allowed = await _mayUseAccount();
    } catch (_) {
      _fail(CustomStickerErrorCode.unavailable);
    }
    _checkLocal(requireEnabled: requireEnabled);
    if (!allowed) _fail(CustomStickerErrorCode.unavailable);
  }

  Future<void> _checkQuota(DatabaseExecutor executor, int addition) async {
    final totals = (await executor.rawQuery(
      'SELECT COUNT(*) AS count, COALESCE(SUM(size_bytes), 0) AS bytes FROM $_table',
    )).single;
    if ((totals['count'] as int) >= _maximumItems) {
      _fail(CustomStickerErrorCode.countQuota);
    }
    if ((totals['bytes'] as int) + addition > _maximumBytes) {
      _fail(CustomStickerErrorCode.byteQuota);
    }
  }

  Future<List<Map<String, Object?>>> _positions(DatabaseExecutor executor) =>
      executor.query(
        _table,
        columns: ['id', 'position'],
        orderBy: 'position ASC, id ASC',
      );

  Future<void> _restorePositions(
    Transaction transaction,
    List<Map<String, Object?>> before,
  ) async {
    for (final row in before) {
      await transaction.update(
        _table,
        {'position': row['position']},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  CustomSticker _hydrate(Map<String, Object?> row) => CustomSticker(
    id: row['id'] as String,
    asset: NormalizedStickerAsset(
      filePath: _absoluteOwnedPath(row['relative_path'] as String),
      sha256Hex: row['content_sha256'] as String,
      mime: row['mime'] as String,
      byteLength: row['size_bytes'] as int,
      width: row['width'] as int,
      height: row['height'] as int,
      frameCount: row['frame_count'] as int,
      durationMs: row['duration_ms'] as int,
    ),
    createdAtMs: row['created_at_ms'] as int,
    lastUsedAtMs: row['last_used_at_ms'] as int,
    position: row['position'] as int,
  );

  void _checkDirectory(Directory directory, String trusted) {
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        directory.resolveSymbolicLinksSync() != trusted) {
      _fail(CustomStickerErrorCode.storageFailure);
    }
  }

  void _checkTemporaryRoot() => _checkDirectory(_temporary, _trustedTemporary);

  Directory? _stickerRoot({required bool create}) {
    _checkDirectory(_documents, _trustedDocuments);
    final directory = Directory(p.join(_documents.path, 'stickers'));
    var type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (!create) return null;
      directory.createSync();
      type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory ||
        directory.resolveSymbolicLinksSync() !=
            p.join(_trustedDocuments, 'stickers')) {
      _fail(CustomStickerErrorCode.storageFailure);
    }
    return directory;
  }

  String _absoluteOwnedPath(String relative) {
    if (!relative.startsWith('stickers/') ||
        relative.length <= 9 ||
        relative.endsWith('/') ||
        relative.contains('\\') ||
        relative.contains('\u0000') ||
        p.posix.normalize(relative) != relative) {
      _fail(CustomStickerErrorCode.storageFailure);
    }
    final path = p.joinAll([_documents.path, ...p.posix.split(relative)]);
    if (!p.isWithin(p.join(_documents.path, 'stickers'), path)) {
      _fail(CustomStickerErrorCode.storageFailure);
    }
    return path;
  }

  File _ownedFile(String relative, {bool allowMissing = false}) {
    final path = _absoluteOwnedPath(relative);
    final root = _stickerRoot(create: false);
    if (root == null) {
      if (allowMissing) return File(path);
      _fail(CustomStickerErrorCode.unavailable);
    }
    var directory = _documents.path;
    final parts = p.posix.split(relative);
    for (var index = 0; index < parts.length; index++) {
      directory = p.join(directory, parts[index]);
      final type = FileSystemEntity.typeSync(directory, followLinks: false);
      if (type == FileSystemEntityType.notFound && allowMissing) {
        return File(path);
      }
      final expected = index == parts.length - 1
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (type != expected) _fail(CustomStickerErrorCode.unavailable);
    }
    final file = File(path);
    if (file.resolveSymbolicLinksSync() !=
        p.joinAll([_trustedDocuments, ...parts])) {
      _fail(CustomStickerErrorCode.unavailable);
    }
    return file;
  }

  Uint8List _storedBytes(NormalizedStickerAsset asset) {
    final relative = p.relative(asset.filePath, from: _documents.path);
    final file = _ownedFile(relative);
    try {
      return _readBytes(file, asset.byteLength, asset.sha256Hex);
    } on CustomStickerException {
      _fail(CustomStickerErrorCode.unavailable);
    } on FileSystemException {
      _fail(CustomStickerErrorCode.unavailable);
    }
  }

  Uint8List _normalizedBytes(NormalizedStickerAsset asset, Directory scratch) {
    _checkScratch(scratch);
    if (asset.mime != 'image/webp' ||
        !p.isWithin(scratch.path, p.normalize(p.absolute(asset.filePath))) ||
        FileSystemEntity.typeSync(asset.filePath, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(
          scratch.resolveSymbolicLinksSync(),
          File(asset.filePath).resolveSymbolicLinksSync(),
        )) {
      _fail(CustomStickerErrorCode.invalidAsset);
    }
    return _readBytes(File(asset.filePath), asset.byteLength, asset.sha256Hex);
  }

  Uint8List _readBytes(File file, int size, String expectedHash) {
    if (size < 1 || size > _maximumAssetBytes) {
      _fail(CustomStickerErrorCode.invalidAsset);
    }
    final handle = file.openSync(mode: FileMode.read);
    try {
      if (handle.lengthSync() != size) {
        _fail(CustomStickerErrorCode.invalidAsset);
      }
      final bytes = Uint8List(size);
      var offset = 0;
      while (offset < size) {
        final count = handle.readIntoSync(bytes, offset, size);
        if (count == 0) _fail(CustomStickerErrorCode.invalidAsset);
        offset += count;
      }
      if (handle.readByteSync() != -1 ||
          handle.lengthSync() != size ||
          sha256.convert(bytes).toString() != expectedHash) {
        _fail(CustomStickerErrorCode.invalidAsset);
      }
      return bytes;
    } finally {
      handle.closeSync();
    }
  }

  Directory _scratch() {
    _checkTemporaryRoot();
    return _temporary.createTempSync('custom-sticker-');
  }

  void _checkScratch(Directory scratch) {
    _checkTemporaryRoot();
    if (!p.isWithin(_temporary.path, scratch.path) ||
        FileSystemEntity.typeSync(scratch.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        scratch.resolveSymbolicLinksSync() !=
            p.join(_trustedTemporary, p.basename(scratch.path))) {
      _fail(CustomStickerErrorCode.storageFailure);
    }
  }

  void _deleteScratch(Directory scratch) {
    _checkScratch(scratch);
    // Only this operation's exclusively created directory is swept; no caller
    // input, library root, or previously returned composer file lives here.
    scratch.deleteSync(recursive: true);
  }

  File _writeNewFile(Directory directory, String name, Uint8List bytes) {
    final file = File(p.join(directory.path, name));
    file.createSync(exclusive: true);
    try {
      file.writeAsBytesSync(bytes, flush: true);
      return file;
    } catch (_) {
      file.deleteSync();
      rethrow;
    }
  }

  void _deleteOwnedFile(File file, {required bool inDocuments}) {
    if (inDocuments) {
      final relative = p.relative(file.path, from: _documents.path);
      _ownedFile(relative, allowMissing: true);
    } else {
      _checkTemporaryRoot();
      if (p.dirname(file.path) != _temporary.path) {
        _fail(CustomStickerErrorCode.storageFailure);
      }
      final type = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        _fail(CustomStickerErrorCode.storageFailure);
      }
    }
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      file.deleteSync();
    }
  }
}

// Isolate capture is deliberately limited to bytes, outside the instance's
// asynchronous method context (which also contains a live SQLite connection).
Future<Uint8List> _posterPng(Uint8List bytes) =>
    Isolate.run(() => _firstFramePng(bytes));

Uint8List _firstFramePng(Uint8List bytes) {
  // Full decoding composites partial ANMF frames onto their canvas. The input
  // already passed the normalizer's 512-square, 24-frame bounds.
  final decoder = img.WebPDecoder()..maxPixels = 512 * 512 * 24;
  final animation = decoder.decode(bytes);
  if (animation == null) _fail(CustomStickerErrorCode.unavailable);
  final first = animation.frames.first;
  final clean = img.Image(
    width: first.width,
    height: first.height,
    numChannels: 4,
  );
  for (final pixel in first) {
    final alpha = (pixel.aNormalized * 255).round();
    clean.setPixelRgba(
      pixel.x,
      pixel.y,
      alpha == 0 ? 0 : (pixel.rNormalized * 255).round(),
      alpha == 0 ? 0 : (pixel.gNormalized * 255).round(),
      alpha == 0 ? 0 : (pixel.bNormalized * 255).round(),
      alpha,
    );
  }
  return img.encodePng(clean);
}

Never _fail(CustomStickerErrorCode code) => throw CustomStickerException(code);
