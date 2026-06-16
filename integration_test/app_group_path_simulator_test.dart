import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

// 04-P0 / SI-5 — Layer C (on-sim integration). Proves the real
// `mknoon/app_group_path` channel (AppDelegate handler) resolves the shared
// app-group container on iOS, and that a marker written at the channel-returned
// path round-trips through the Dart gate IN ONE PROCESS (path + sidecar format
// align). The genuine out-of-process NSE→app round-trip is device-only
// (`simctl push` does not invoke the NSE).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'app-group channel resolves the container and the gate round-trips a marker',
    (tester) async {
      final path = await AppGroupPathChannel().containerPath();
      expect(
        path,
        isNotNull,
        reason: 'the app-group channel should resolve on iOS',
      );
      expect(path!, isNotEmpty);
      // The app-group container path is UUID-based
      // (…/Containers/Shared/AppGroup/<uuid>), so it does NOT contain the group
      // id literally; just require a real, existing shared-container directory.
      expect(path, contains('AppGroup'));
      expect(Directory(path).existsSync(), isTrue);

      // Write an NSE-shaped marker at the channel-returned path…
      final sidecar = Directory('$path/RecentRemoteShown');
      await sidecar.create(recursive: true);
      const key = 'message:peer-itest|m-itest';
      final marker = File(
        '${sidecar.path}/${sha256.convert(utf8.encode(key))}',
      );
      await marker.writeAsString('');
      addTearDown(() {
        try {
          marker.deleteSync();
        } catch (_) {}
      });

      // …and consume it through the gate pointed at that same container.
      final gate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/itest-gate-${DateTime.now().microsecondsSinceEpoch}.json',
        appGroupSidecarDirProvider: () async => Directory(path),
      );
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-itest',
          messageId: 'm-itest',
        ),
        isTrue,
      );
    },
  );
}
