import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Android-only finite BSD-flock acquisition failure.
///
/// The lock action is never time-capped after acquisition. Callers can
/// therefore fail closed before entering a notification side effect without
/// detaching an owner that is already mutating durable or native state.
final class BoundedPosixFlockUnavailableException implements Exception {
  const BoundedPosixFlockUnavailableException();

  @override
  String toString() => 'BoundedPosixFlockUnavailableException';
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

/// BSD `flock` shared by notification ownership stores.
///
/// Android retries `LOCK_EX | LOCK_NB` for one second. iOS/macOS retain the
/// historical blocking `LOCK_EX` protocol used by the Notification Service
/// Extension and app process.
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

  static Future<T> _withExclusive<T>(
    File file,
    Future<T> Function() action, {
    required bool ownerCompletion,
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
    try {
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
      return await action();
    } finally {
      if (acquired) {
        _api.flock(descriptor, lockUnlock);
      }
      _api.close(descriptor);
    }
  }
}

final class _BoundedPosixFlockApi {
  const _BoundedPosixFlockApi({
    required this.open,
    required this.flock,
    required this.close,
  });

  final _OpenDart open;
  final _FlockDart flock;
  final _CloseDart close;

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
    );
  }
}
