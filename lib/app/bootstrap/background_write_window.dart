import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// BL-30: runs writes that must not be caught by iOS suspension.
///
/// Build 131 was killed with RUNNINGBOARD 0xdead10cc about 2.5 s after a
/// background launch while the bootstrap was committing to the database. A
/// window holds one iOS background assertion for the whole body, so the
/// process is not suspended mid-write.
abstract interface class BackgroundWriteWindow {
  Future<T> run<T>(String reason, Future<T> Function() body);
}

/// Non-iOS platforms (and callers that need no assertion) run the body as is.
final class PassthroughBackgroundWriteWindow implements BackgroundWriteWindow {
  const PassthroughBackgroundWriteWindow();

  @override
  Future<T> run<T>(String reason, Future<T> Function() body) => body();
}

/// iOS: one `bgBegin` assertion around the body, ended after it.
///
/// A refused or failed begin still runs the body (never worse than no
/// assertion), and startup is never blocked on the channel.
final class IosBackgroundWriteWindow implements BackgroundWriteWindow {
  const IosBackgroundWriteWindow({
    this.channel = const MethodChannel('com.mknoon/go_bridge'),
  });

  final MethodChannel channel;

  @override
  Future<T> run<T>(String reason, Future<T> Function() body) async {
    final taskId = await _begin();
    try {
      return await body();
    } finally {
      if (taskId != null) await _end(taskId);
    }
  }

  // GoBridge.swift bgBegin: a task id string, or "" when iOS refuses.
  Future<String?> _begin() async {
    try {
      final id = await channel.invokeMethod<String>('bgBegin');
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  // GoBridge.swift bgEnd: {"taskId": id}. An already-expired task is a no-op.
  Future<void> _end(String taskId) async {
    try {
      await channel.invokeMethod<void>(
        'bgEnd',
        jsonEncode(<String, String>{'taskId': taskId}),
      );
    } catch (_) {
      // The native expiration handler ends the task on its own.
    }
  }
}

BackgroundWriteWindow defaultBackgroundWriteWindow({bool? isIOS}) =>
    (isIOS ?? Platform.isIOS)
    ? const IosBackgroundWriteWindow()
    : const PassthroughBackgroundWriteWindow();

/// The bootstrap's every-launch identity database open plus the writes that
/// follow it, inside one [BackgroundWriteWindow].
Future<D> openIdentityDatabaseWithPostOpenWrites<D>({
  required BackgroundWriteWindow window,
  required Future<D> Function() open,
  required Future<void> Function(D db) postOpenWrites,
}) => window.run('bootstrap_identity_writes', () async {
  final db = await open();
  await postOpenWrites(db);
  return db;
});
