import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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
/// A writer never holds the lock across a network call; it holds it for one
/// read, one merge and one rename (milliseconds). So a lock older than
/// [staleAfter] belongs to a writer that was killed while holding it (the
/// Android minimal engine destroyed at its budget, an iOS task expiry), and is
/// taken over. Its age counts both ways, so a lock stamped in the future (the
/// clock went back) also goes stale.
///
/// [acquireTimeout] is longer than [staleAfter] on purpose (T4a F5): a
/// foreground dismissSoft that meets a dead writer's lock waits it out and is
/// saved, instead of failing quietly and bringing the banner back.
///
/// Each lock file holds its owner's token; a writer deletes only its own lock,
/// never one a waiter has taken over meanwhile.
class UpdateCheckStateLock {
  UpdateCheckStateLock(
    this.lockFile, {
    this.staleAfter = defaultStaleAfter,
    this.acquireTimeout = defaultAcquireTimeout,
    this.retryDelay = const Duration(milliseconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final File lockFile;
  final Duration staleAfter;
  final Duration acquireTimeout;
  final Duration retryDelay;
  final DateTime Function() _clock;

  static const Duration defaultStaleAfter = Duration(seconds: 10);
  static const Duration defaultAcquireTimeout = Duration(seconds: 15);

  static final Map<String, Future<void>> _isolateTails = {};
  static int _tokenCounter = 0;

  /// errno EEXIST on Linux, Android, iOS and macOS.
  static const int _eexist = 17;

  String? _token;

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
    final token =
        '$pid.${Isolate.current.hashCode}.${_clock().microsecondsSinceEpoch}.'
        '${_tokenCounter++}';
    while (true) {
      try {
        await lockFile.create(exclusive: true);
        _token = token;
        await lockFile.writeAsString(token, flush: true);
        return;
      } on FileSystemException catch (error) {
        // Only "it exists" means busy. Anything else (for example iOS before
        // the first unlock) fails fast.
        final busy =
            error.osError?.errorCode == _eexist || await lockFile.exists();
        if (!busy) rethrow;
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
      return _clock().difference(modified).abs() > staleAfter;
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
    final token = _token;
    _token = null;
    if (token == null) return;
    try {
      // Taken over meanwhile: the lock now belongs to someone else.
      if (await lockFile.readAsString() != token) return;
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
