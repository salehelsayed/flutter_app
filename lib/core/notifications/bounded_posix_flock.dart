import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostic_events.dart';

/// Finite Android acquisition or refused/expired iOS background admission.
///
/// The lock action is never time-capped after acquisition. Callers can
/// therefore fail closed before entering a notification side effect without
/// detaching an owner that is already mutating durable or native state.
final class BoundedPosixFlockUnavailableException implements Exception {
  const BoundedPosixFlockUnavailableException();

  @override
  String toString() => 'BoundedPosixFlockUnavailableException';
}

/// Same-isolate recursive acquisition of one lock path.
///
/// On Darwin a blocking second descriptor would freeze the isolate that must
/// resume the first asynchronous owner. Treat recursion as a fail-closed
/// programming error before entering `flock(2)`.
final class BoundedPosixFlockReentrantException implements Exception {
  const BoundedPosixFlockReentrantException(this.path);

  final String path;

  @override
  String toString() => 'BoundedPosixFlockReentrantException($path)';
}

/// Retains both failures when ending a background assertion also fails while
/// propagating an action/acquisition failure. The native lock is already free.
final class BoundedPosixFlockBackgroundCleanupException implements Exception {
  const BoundedPosixFlockBackgroundCleanupException({
    required this.originalError,
    required this.originalStackTrace,
    required this.cleanupError,
    required this.cleanupStackTrace,
  });

  final Object originalError;
  final StackTrace originalStackTrace;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;

  @override
  String toString() => 'BoundedPosixFlockBackgroundCleanupException';
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);
typedef _FsyncNative = Int32 Function(Int32);
typedef _FsyncDart = int Function(int);

/// BSD `flock` shared by notification ownership stores.
///
/// Android retries `LOCK_EX | LOCK_NB` for one second. iOS/macOS retain the
/// historical blocking `LOCK_EX` protocol used by the Notification Service
/// Extension and app process. iOS requests a scoped background assertion before
/// acquisition, verifies admission after acquisition, and ends it after unlock.
/// This protects ordinary suspension while the grant is live. An owner that
/// outlives native expiration remains unsafe; it is never detached or unlocked
/// early because a pending callback may still mutate durable/native state.
final class BoundedPosixFlock {
  BoundedPosixFlock._();

  /// Production acquisition bound: `const Duration(seconds: 1)`.
  static const Duration acquisitionTimeout = Duration(seconds: 1);
  static const Duration _retryInterval = Duration(milliseconds: 10);
  static const int openReadWrite = 2;
  static const int lockExclusive = 2;
  static const int lockNonBlocking = 4;
  static const int lockUnlock = 8;
  static final _BoundedPosixFlockApi _api = _BoundedPosixFlockApi.load();
  static const _backgroundTasks = MethodChannel('com.mknoon/go_bridge');
  @visibleForTesting
  static bool? debugUseIosBackgroundTasks;

  static bool get _usesIosBackgroundTasks =>
      debugUseIosBackgroundTasks ?? Platform.isIOS;
  static final Object _isolateOwnerZoneKey = Object();
  static final Map<String, Future<void>> _isolateTails =
      <String, Future<void>>{};

  static Future<T> withExclusive<T>(File file, Future<T> Function() action) =>
      _withExclusive(file, action, ownerCompletion: false);

  /// Completes an already-created durable owner without abandoning it at the
  /// contender deadline.
  ///
  /// Android still uses nonblocking flock attempts so the isolate event loop
  /// remains schedulable, but retries until the real lock owner releases. This
  /// is reserved for post-show commit; initial acquisition and release use the
  /// finite contender API above.
  static Future<T> withExclusiveOwnerCompletion<T>(
    File file,
    Future<T> Function() action,
  ) => _withExclusive(file, action, ownerCompletion: true);

  /// Flushes the directory entry after an atomic rename. Flushing only the
  /// file contents does not make rename metadata power-loss safe on POSIX.
  static void syncDirectory(Directory directory) {
    final nativePath = directory.path.toNativeUtf8();
    late final int descriptor;
    try {
      descriptor = _api.open(nativePath, 0);
    } finally {
      malloc.free(nativePath);
    }
    if (descriptor < 0) {
      throw FileSystemException(
        'Unable to open notification directory for sync',
        directory.path,
      );
    }
    try {
      if (_api.fsync(descriptor) != 0) {
        throw FileSystemException(
          'Unable to sync notification directory',
          directory.path,
        );
      }
    } finally {
      _api.close(descriptor);
    }
  }

  static Future<T> _withExclusive<T>(
    File file,
    Future<T> Function() action, {
    required bool ownerCompletion,
  }) async {
    final diagnosticOwner = Object();
    var diagnosticReleased = false;
    void reportReleased() {
      if (diagnosticReleased) return;
      diagnosticReleased = true;
      AppDiagnosticEvents.notificationFileLock(
        diagnosticOwner,
        NotificationFileLockPhase.released,
      );
    }

    AppDiagnosticEvents.notificationFileLock(
      diagnosticOwner,
      NotificationFileLockPhase.waiting,
    );
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _withExclusiveNative(
          file,
          action,
          ownerCompletion: ownerCompletion,
          diagnosticOwner: diagnosticOwner,
          onNativeReleased: reportReleased,
        );
      }
      return await _serializeBlockingPlatformAcquisition(
        file,
        () => _withExclusiveNative(
          file,
          action,
          ownerCompletion: ownerCompletion,
          diagnosticOwner: diagnosticOwner,
          onNativeReleased: reportReleased,
        ),
      );
    } finally {
      // Native unlock/close have completed before reporting release. This is
      // observation only; suspension never causes an early unlock of an owner.
      reportReleased();
    }
  }

  static Future<T> _serializeBlockingPlatformAcquisition<T>(
    File file,
    Future<T> Function() action,
  ) async {
    final key = file.absolute.path;
    if (Zone.current[_isolateOwnerZoneKey] == key) {
      throw BoundedPosixFlockReentrantException(key);
    }
    final previous = _isolateTails[key] ?? Future<void>.value();
    final release = Completer<void>();
    _isolateTails[key] = release.future;
    await previous;
    try {
      return await runZoned(
        action,
        zoneValues: <Object, Object>{_isolateOwnerZoneKey: key},
      );
    } finally {
      release.complete();
      if (identical(_isolateTails[key], release.future)) {
        _isolateTails.remove(key);
      }
    }
  }

  static Future<T> _withExclusiveNative<T>(
    File file,
    Future<T> Function() action, {
    required bool ownerCompletion,
    required Object diagnosticOwner,
    required VoidCallback onNativeReleased,
  }) async {
    await file.create(recursive: true);
    final nativePath = file.path.toNativeUtf8();
    late final int descriptor;
    try {
      descriptor = _api.open(nativePath, openReadWrite);
    } finally {
      malloc.free(nativePath);
    }
    if (descriptor < 0) {
      throw FileSystemException('Unable to open notification lock', file.path);
    }

    var acquired = false;
    int? backgroundTask;
    Object? originalError;
    StackTrace? originalStackTrace;
    try {
      if (_usesIosBackgroundTasks) {
        backgroundTask = await _backgroundTasks.invokeMethod<int>(
          'notificationLockBegin',
        );
        if (backgroundTask == null) {
          throw const BoundedPosixFlockUnavailableException();
        }
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final stopwatch = Stopwatch()..start();
        var firstAttempt = true;
        while (true) {
          // The first nonblocking attempt is immediate. Every retry is fenced
          // by the absolute acquisition deadline before touching flock again,
          // so a delayed timer wake cannot enter the action after one second.
          if (!ownerCompletion &&
              !firstAttempt &&
              stopwatch.elapsed >= acquisitionTimeout) {
            throw const BoundedPosixFlockUnavailableException();
          }
          if (_api.flock(descriptor, lockExclusive | lockNonBlocking) == 0) {
            acquired = true;
            break;
          }
          firstAttempt = false;
          if (!ownerCompletion && stopwatch.elapsed >= acquisitionTimeout) {
            throw const BoundedPosixFlockUnavailableException();
          }
          if (ownerCompletion) {
            await Future<void>.delayed(_retryInterval);
          } else {
            final remaining = acquisitionTimeout - stopwatch.elapsed;
            await Future<void>.delayed(
              remaining < _retryInterval ? remaining : _retryInterval,
            );
          }
        }
      } else {
        if (_api.flock(descriptor, lockExclusive) != 0) {
          throw FileSystemException(
            'Unable to acquire notification lock',
            file.path,
          );
        }
        acquired = true;
      }
      AppDiagnosticEvents.notificationFileLock(
        diagnosticOwner,
        NotificationFileLockPhase.held,
      );
      if (backgroundTask != null &&
          await _backgroundTasks.invokeMethod<bool>(
                'notificationLockIsActive',
                backgroundTask,
              ) !=
              true) {
        // Blocking acquisition may consume the grant. Do not start the action
        // on an already-expired lease. Expiration after this check remains an
        // owner-lifetime limitation, not permission to unlock pending work.
        throw const BoundedPosixFlockUnavailableException();
      }
      return await action();
    } catch (error, stackTrace) {
      originalError = error;
      originalStackTrace = stackTrace;
      rethrow;
    } finally {
      if (acquired) {
        _api.flock(descriptor, lockUnlock);
      }
      _api.close(descriptor);
      onNativeReleased();
      if (backgroundTask != null) {
        try {
          await _backgroundTasks.invokeMethod<void>(
            'notificationLockEnd',
            backgroundTask,
          );
        } catch (error, stackTrace) {
          if (originalError != null) {
            throw BoundedPosixFlockBackgroundCleanupException(
              originalError: originalError,
              originalStackTrace: originalStackTrace!,
              cleanupError: error,
              cleanupStackTrace: stackTrace,
            );
          }
          rethrow;
        }
      }
    }
  }
}

final class _BoundedPosixFlockApi {
  const _BoundedPosixFlockApi({
    required this.open,
    required this.flock,
    required this.close,
    required this.fsync,
  });

  final _OpenDart open;
  final _FlockDart flock;
  final _CloseDart close;
  final _FsyncDart fsync;

  factory _BoundedPosixFlockApi.load() {
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux)) {
      throw UnsupportedError('BSD flock is unavailable on this platform');
    }
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : DynamicLibrary.process();
    return _BoundedPosixFlockApi(
      open: library.lookupFunction<_OpenNative, _OpenDart>('open'),
      flock: library.lookupFunction<_FlockNative, _FlockDart>('flock'),
      close: library.lookupFunction<_CloseNative, _CloseDart>('close'),
      fsync: library.lookupFunction<_FsyncNative, _FsyncDart>('fsync'),
    );
  }
}
