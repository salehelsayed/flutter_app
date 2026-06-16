import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const String _persistedAppGroupPathFileName = 'mknoon_app_group_path';

/// 04-P0 / SI-5 (iOS). FOREGROUND: resolve the shared app-group container path
/// via the platform channel and PERSIST it to app-support, so the FCM
/// background isolate — whose separate FlutterEngine may not carry this
/// hand-rolled channel — can read it later without re-hitting native. No-op
/// when the channel is unavailable (off-iOS / container missing).
Future<void> persistAppGroupContainerPathForGate({
  AppGroupPathChannel? channel,
  Future<Directory> Function()? supportDirectory,
}) async {
  try {
    final path = await (channel ?? AppGroupPathChannel()).containerPath();
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final dir = await (supportDirectory ?? getApplicationSupportDirectory)();
    final file = File('${dir.path}/$_persistedAppGroupPathFileName');
    await file.parent.create(recursive: true);
    await file.writeAsString(path.trim(), flush: true);
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RECENT_REMOTE_GATE_APP_GROUP_PERSIST_ERROR',
      details: {'error': error.runtimeType.toString()},
    );
  }
}

/// Reads the persisted app-group container path (callable from any isolate), or
/// null when it hasn't been persisted yet (e.g. first launch before any
/// foreground run).
Future<String?> readPersistedAppGroupContainerPath({
  Future<Directory> Function()? supportDirectory,
}) async {
  try {
    final dir = await (supportDirectory ?? getApplicationSupportDirectory)();
    final file = File('${dir.path}/$_persistedAppGroupPathFileName');
    if (!await file.exists()) {
      return null;
    }
    final path = (await file.readAsString()).trim();
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

/// Wires the module-global [recentRemoteNotificationGate] (call from BOTH the
/// foreground AND the FCM background isolate, guarded by `Platform.isIOS` at the
/// call site) to additionally consume the NSE's app-group sidecar dedupe markers
/// — preserving the SI-4 app-support JSON for the gate's own writes. If the path
/// isn't persisted yet, the provider yields nothing and the gate keeps its
/// app-support-only behavior (fail-open).
void configureRecentRemoteNotificationGateForIos({
  Future<Directory> Function()? supportDirectory,
}) {
  recentRemoteNotificationGate = RecentRemoteNotificationGate(
    appGroupSidecarDirProvider: () async {
      final path = await readPersistedAppGroupContainerPath(
        supportDirectory: supportDirectory,
      );
      if (path == null) {
        throw StateError('app-group container path not persisted yet');
      }
      return Directory(path);
    },
  );
}
