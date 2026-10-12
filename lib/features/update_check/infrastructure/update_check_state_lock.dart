import 'dart:async';
import 'dart:io';

/// Serializes read-merge-rename of the update check state file (T4a).
///
/// Two layers, because neither one is enough alone:
/// - An in-isolate async mutex per file path. Writers in one isolate queue up
///   without touching the disk.
/// - An exclusive lock file (`File.create(exclusive: true)`, an `O_EXCL`
///   create). It separates isolates and processes: the foreground engine, the
///   Android minimal engine and the main engine's background run can all write
///   the file. POSIX `fcntl` locks would not do this, because they belong to
///   the process, and two isolates share one process.
///
/// A lock file older than [staleAfter] belongs to a writer that died, so it is
/// taken over. A writer never holds the lock across a network call; it holds
/// it for one read, one merge and one rename.
class UpdateCheckStateLock {
  UpdateCheckStateLock(
    this.lockFile, {
    this.staleAfter = const Duration(seconds: 30),
    this.acquireTimeout = const Duration(seconds: 10),
    this.retryDelay = const Duration(milliseconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final File lockFile;
  final Duration staleAfter;
  final Duration acquireTimeout;
  final Duration retryDelay;
  final DateTime Function() _clock;

  static final Map<String, Future<void>> _isolateTails = {};

  /// Runs [action] while holding both locks. Throws
  /// [UpdateCheckStateLockTimeout] when the file lock stays busy.
  Future<T> synchronized<T>(Future<T> Function() action) async {
    final key = lockFile.path;
    final previous = _isolateTails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _isolateTails[key] = tail;
    try {
      await previous;
      await _acquireFile();
      try {
        return await action();
      } finally {
        await _releaseFile();
      }
    } finally {
      done.complete();
      if (identical(_isolateTails[key], tail)) _isolateTails.remove(key);
    }
  }

  Future<void> _acquireFile() async {
    final stopwatch = Stopwatch()..start();
    await lockFile.parent.create(recursive: true);
    while (true) {
      try {
        await lockFile.create(exclusive: true);
        return;
      } on FileSystemException {
        if (await _isStale()) {
          await _takeOverStale();
          continue;
        }
      }
      if (stopwatch.elapsed >= acquireTimeout) {
        throw UpdateCheckStateLockTimeout(lockFile.path);
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<bool> _isStale() async {
    try {
      final modified = await lockFile.lastModified();
      return _clock().difference(modified) > staleAfter;
    } on FileSystemException {
      // Gone already: the next create decides.
      return false;
    }
  }

  /// Renames the stale lock away first. Only one waiter's rename can succeed,
  /// so two waiters do not both delete and recreate it.
  Future<void> _takeOverStale() async {
    final aside = File(
      '${lockFile.path}.stale.$pid.${_clock().microsecondsSinceEpoch}',
    );
    try {
      await lockFile.rename(aside.path);
      await aside.delete();
    } on FileSystemException {
      // Another waiter took it over or the owner released it.
    }
  }

  Future<void> _releaseFile() async {
    try {
      await lockFile.delete();
    } on FileSystemException {
      // Already gone: a waiter judged it stale. Nothing else to undo.
    }
  }
}

class UpdateCheckStateLockTimeout implements Exception {
  const UpdateCheckStateLockTimeout(this.path);

  final String path;

  @override
  String toString() => 'UpdateCheckStateLockTimeout($path)';
}
