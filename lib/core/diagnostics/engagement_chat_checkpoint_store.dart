import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef EngagementChatBeforeCommit =
    Future<void> Function(String temporaryPath);
typedef EngagementChatRename =
    Future<void> Function(String temporaryPath, String checkpointPath);

/// A single private checkpoint, with a shared physical writer per canonical path.
///
/// The two filesystem seams permit controlled prepare/issued-rename races.
/// They do not replace the store's ownership, bounds or serialization policy.
final class EngagementChatCheckpointStore {
  EngagementChatCheckpointStore._(
    this.privateDirectory,
    this._writer, {
    this.beforeCommit,
    this.rename,
  });

  static const _maximumBytes = 256 * 1024;
  static final Map<String, _CheckpointWriter> _writers = {};
  final String privateDirectory;
  final _CheckpointWriter _writer;
  final EngagementChatBeforeCommit? beforeCommit;
  final EngagementChatRename? rename;
  bool _closed = false;

  String get checkpointPath => _writer.path;

  static Future<EngagementChatCheckpointStore> open(
    String privateDirectory, {
    EngagementChatBeforeCommit? beforeCommit,
    EngagementChatRename? rename,
  }) async {
    final directory = await Directory(privateDirectory).create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    final path = '$canonical/engagement-chat-witness-v1.json';
    final writer = _writers.putIfAbsent(path, () => _CheckpointWriter(path));
    writer.clients++;
    return EngagementChatCheckpointStore._(
      canonical,
      writer,
      beforeCommit: beforeCommit,
      rename: rename,
    );
  }

  bool _allows(bool Function() isCurrent) {
    try {
      return !_closed && isCurrent();
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> read({required bool Function() isCurrent}) {
    if (!_allows(isCurrent)) {
      return Future<Uint8List?>.value();
    }
    return _writer.run<Uint8List?>(() async {
      if (!_allows(isCurrent) ||
          await FileSystemEntity.type(checkpointPath, followLinks: false) !=
              FileSystemEntityType.file) {
        return null;
      }
      final file = File(checkpointPath);
      if (await file.length() > _maximumBytes || !_allows(isCurrent)) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return _allows(isCurrent) && bytes.length <= _maximumBytes ? bytes : null;
    }, null);
  }

  Future<bool> replace(
    Uint8List bytes, {
    required bool Function() isCurrent,
  }) {
    if (bytes.length > _maximumBytes || !_allows(isCurrent)) {
      return Future.value(false);
    }
    // Copy at the public boundary, before waiting for another physical writer.
    final ownedBytes = Uint8List.fromList(bytes);
    return _writer.run<bool>(() async {
      if (!_allows(isCurrent)) {
        return false;
      }
      final type = await FileSystemEntity.type(checkpointPath, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        return false;
      }
      if (!await _writer.removeOwnedTemporary()) {
        return false;
      }
      final temporary = File(_writer.nextTemporaryPath());
      var ownsTemporary = false;
      try {
        await temporary.create(exclusive: true);
        ownsTemporary = true;
        _writer.ownedTemporary = temporary.path;
        await temporary.writeAsBytes(ownedBytes, flush: true);
        if (!_allows(isCurrent)) {
          return false;
        }
        final prepare = beforeCommit;
        if (prepare != null) {
          await prepare(temporary.path);
        }
        if (!_allows(isCurrent)) {
          return false;
        }
        final commit = rename;
        if (commit == null) {
          await temporary.rename(checkpointPath);
        } else {
          await commit(temporary.path, checkpointPath);
        }
        // An issued rename cannot be cancelled. Keep the path fence until it
        // settles, and reject its acknowledgement if its owner has changed.
        return _allows(isCurrent);
      } finally {
        if (ownsTemporary) {
          await _writer.removeOwnedTemporary();
        }
      }
    }, false);
  }

  Future<bool> clear({required bool Function() isCurrent}) {
    if (!_allows(isCurrent)) {
      return Future.value(false);
    }
    return _writer.run<bool>(() async {
      if (!_allows(isCurrent)) {
        return false;
      }
      final type = await FileSystemEntity.type(checkpointPath, followLinks: false);
      if (!_allows(isCurrent)) {
        return false;
      }
      if (!await _writer.removeOwnedTemporary() || !_allows(isCurrent)) {
        return false;
      }
      if (type == FileSystemEntityType.file) {
        await File(checkpointPath).delete();
      } else if (type != FileSystemEntityType.notFound) {
        return false;
      }
      return _allows(isCurrent);
    }, false);
  }

  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _writer.clients--;
      _writer.releaseIfIdle();
    }
    // Joining does not abandon an issued rename or release its physical fence.
    return _writer.tail;
  }
}

final class _CheckpointWriter {
  _CheckpointWriter(this.path)
    : _nonce = '${pid}-${Random.secure().nextInt(1 << 32)}';

  final String path;
  final String _nonce;
  int clients = 0;
  int _unfinished = 0;
  int _sequence = 0;
  String? ownedTemporary;
  Future<void> tail = Future<void>.value();

  String nextTemporaryPath() => '$path.$_nonce-${_sequence++}.tmp';

  Future<bool> removeOwnedTemporary() async {
    final owned = ownedTemporary;
    if (owned == null) {
      return true;
    }
    try {
      final type = await FileSystemEntity.type(owned, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await File(owned).delete();
      } else if (type != FileSystemEntityType.notFound) {
        return false;
      }
      ownedTemporary = null;
      return true;
    } catch (_) {
      // Keep ownership and refuse another temporary until cleanup succeeds.
      return false;
    }
  }

  Future<T> run<T>(Future<T> Function() operation, T failure) {
    if (_unfinished >= 64) {
      return Future.value(failure);
    }
    _unfinished++;
    final result = tail.then<T>((_) async {
      try {
        return await operation();
      } catch (_) {
        return failure;
      } finally {
        _unfinished--;
        releaseIfIdle();
      }
    });
    // No timeout here: successor instances must wait for the physical operation.
    tail = result.then<void>((_) {});
    return result;
  }

  void releaseIfIdle() {
    if (clients == 0 && _unfinished == 0 && ownedTemporary == null &&
        identical(EngagementChatCheckpointStore._writers[path], this)) {
      EngagementChatCheckpointStore._writers.remove(path);
    }
  }
}
