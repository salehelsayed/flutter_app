import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// An in-flight operation's durable ownership, separate from its short BSD
/// file-lock sections. Native readers honor the same marker under flock.
/// No deadline can transfer ownership while the originating process is alive.
final class NotificationLockTransaction {
  NotificationLockTransaction({
    required this.owner,
    required this.release,
    required this.reacquire,
    required this.hasFileLock,
  });

  static const markerName = '.async-owner-v1.json';
  static const _channel = MethodChannel('com.mknoon/go_bridge');
  static final _zoneKey = Object();
  static final _hostOwners = <String>{};

  final Map<String, Object> owner;
  final Future<void> Function() release;
  final Future<void> Function() reacquire;
  final bool Function() hasFileLock;

  /// Lock-held helpers may not continue after a swallowed reacquisition error.
  static bool get hasAuthority {
    final transaction = Zone.current[_zoneKey] as NotificationLockTransaction?;
    return transaction == null || transaction.hasFileLock();
  }

  static Future<T> inside<T>(Future<T> Function() action) async {
    final transaction = Zone.current[_zoneKey] as NotificationLockTransaction?;
    if (transaction == null || transaction.hasFileLock()) return action();
    await transaction.reacquire();
    try {
      return await action();
    } finally {
      await transaction.release();
    }
  }

  // Synchronous iOS file work avoids yielding a protected disk transaction
  // to uncontrolled async I/O. Already-entered kernel I/O still has no hard
  // execution bound. Android retains its current asynchronous implementation.
  static Future<T> io<T>(T Function() sync, Future<T> Function() asyncIO) =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? Future<T>.sync(sync)
      : asyncIO();

  static File marker(File lock) => File('${lock.parent.path}/$markerName');

  static String? readMarker(File lock) {
    final file = marker(lock);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file || file.lengthSync() > 1024) {
      throw const FileSystemException('Invalid notification operation owner');
    }
    return file.readAsStringSync();
  }

  static Map<String, Object>? decodeOwner(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map ||
          value.length != 4 ||
          value['version'] != 1 ||
          value['pid'] is! int ||
          (value['pid'] as int) <= 0 ||
          value['processStart'] is! String ||
          !(RegExp(
                r'^[0-9]+:[0-9]{1,6}$',
              ).hasMatch(value['processStart'] as String) ||
              (!Platform.isIOS &&
                  value['processStart'] == 'host:${value['pid']}')) ||
          value['token'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['token'] as String)) {
        return null;
      }
      return Map<String, Object>.from(value);
    } on Object {
      return null;
    }
  }

  /// Runs before acquisition: a platform query must never extend flock scope.
  static Future<bool> ownerIsAlive(String encoded) async {
    final owner = decodeOwner(encoded);
    if (owner == null) return true; // Uncertain/future bytes grant no takeover.
    if (!Platform.isIOS) {
      if (owner['pid'] == pid) return _hostOwners.contains(owner['token']);
      return true; // Host tests explicitly control foreign-process evidence.
    }
    return await _channel.invokeMethod<bool>(
          'notificationLockOwnerIsAlive',
          owner,
        ) !=
        false;
  }

  static Future<Map<String, Object>> beginOwner() async {
    final random = Random.secure();
    final token = List.generate(
      32,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    if (!Platform.isIOS) {
      _hostOwners.add(token);
      return <String, Object>{
        'version': 1,
        'pid': pid,
        'processStart': 'host:$pid',
        'token': token,
      };
    }
    final identity = await _channel.invokeMapMethod<String, Object>(
      'notificationLockOwnerBegin',
      token,
    );
    if (identity?['pid'] is! int || identity?['processStart'] is! String) {
      throw const FileSystemException(
        'Notification process identity unavailable',
      );
    }
    return <String, Object>{'version': 1, ...identity!, 'token': token};
  }

  static Future<void> endOwner(Map<String, Object> owner) async {
    if (!Platform.isIOS) {
      _hostOwners.remove(owner['token']);
      return;
    }
    await _channel.invokeMethod<void>(
      'notificationLockOwnerEnd',
      owner['token'],
    );
  }

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  /// Only external callbacks use this boundary. Durable file operations stay
  /// inside flock. The Future is awaited to real completion; it is never
  /// detached. Reacquisition may refuse admission, leaving recoverable state.
  static Future<T> outside<T>(Future<T> Function() action) async {
    final transaction = Zone.current[_zoneKey] as NotificationLockTransaction?;
    if (transaction == null || !transaction.hasFileLock()) return action();
    await transaction.release();
    Object? failure;
    StackTrace? failureStack;
    T? value;
    try {
      value = await action();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      await transaction.reacquire();
    } catch (error, stack) {
      if (failure != null) {
        throw NotificationLockReacquisitionException(
          failure,
          failureStack!,
          error,
          stack,
        );
      }
      rethrow;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    return value as T;
  }
}

/// Both failures remain observable when a failed callback cannot reacquire.
final class NotificationLockReacquisitionException implements Exception {
  const NotificationLockReacquisitionException(
    this.originalError,
    this.originalStackTrace,
    this.reacquisitionError,
    this.reacquisitionStackTrace,
  );
  final Object originalError;
  final StackTrace originalStackTrace;
  final Object reacquisitionError;
  final StackTrace reacquisitionStackTrace;
}
