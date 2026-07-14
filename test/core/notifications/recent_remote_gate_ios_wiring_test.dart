import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';

void main() {
  late Directory support;
  late Directory appGroup;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('si5-support-');
    appGroup = await Directory.systemTemp.createTemp('si5-container-');
  });

  tearDown(() {
    debugResetRecentRemoteNotificationGate();
    try {
      support.deleteSync(recursive: true);
    } catch (_) {}
    try {
      appGroup.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('persist writes the channel-resolved path; read returns it', () async {
    await persistAppGroupContainerPathForGate(
      channel: AppGroupPathChannel(invoker: (m, a) async => appGroup.path),
      supportDirectory: () async => support,
    );
    expect(
      await readPersistedAppGroupContainerPath(
        supportDirectory: () async => support,
      ),
      appGroup.path,
    );
  });

  test('persist is a no-op when the channel returns null (off-iOS)', () async {
    await persistAppGroupContainerPathForGate(
      channel: AppGroupPathChannel(invoker: (m, a) async => null),
      supportDirectory: () async => support,
    );
    expect(
      await readPersistedAppGroupContainerPath(
        supportDirectory: () async => support,
      ),
      isNull,
    );
  });

  test(
    'configure wires the gate to consume an NSE sidecar via the persisted path',
    () async {
      await persistAppGroupContainerPathForGate(
        channel: AppGroupPathChannel(invoker: (m, a) async => appGroup.path),
        supportDirectory: () async => support,
      );
      final sidecar = Directory('${appGroup.path}/RecentRemoteShown');
      await sidecar.create(recursive: true);
      const key = 'message:peer-1|m-1';
      await File(
        '${sidecar.path}/${sha256.convert(utf8.encode(key))}',
      ).writeAsString('');

      configureRecentRemoteNotificationGateForIos(
        supportDirectory: () async => support,
      );

      expect(
        await recentRemoteNotificationGate.resolveFilePath(),
        '${appGroup.path}/mknoon_recent_remote_notifications.json',
      );

      expect(
        await recentRemoteNotificationGate.consumeIfRecentAnnouncement(
          payload: 'peer-1',
          messageId: 'm-1',
        ),
        isTrue,
      );
    },
  );

  test(
    'configured gate retries App Group resolution without pinning systemTemp',
    () async {
      var appGroupReady = false;
      final tempFallback = File(
        '${Directory.systemTemp.path}/mknoon_recent_remote_notifications.json',
      );
      if (tempFallback.existsSync()) tempFallback.deleteSync();

      configureRecentRemoteNotificationGateForIos(
        channel: AppGroupPathChannel(
          invoker: (_, _) async => appGroupReady ? appGroup.path : null,
        ),
        supportDirectory: () async => support,
      );

      await recentRemoteNotificationGate.markAnnouncement(
        payload: 'peer-race',
        messageId: 'event-race',
      );
      expect(tempFallback.existsSync(), isFalse);

      appGroupReady = true;
      await recentRemoteNotificationGate.markAnnouncement(
        payload: 'peer-race',
        messageId: 'event-race',
      );
      expect(
        await recentRemoteNotificationGate.resolveFilePath(),
        '${appGroup.path}/mknoon_recent_remote_notifications.json',
      );
      expect(
        File(
          '${appGroup.path}/mknoon_recent_remote_notifications.json',
        ).existsSync(),
        isTrue,
      );
    },
  );
}
