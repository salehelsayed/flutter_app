import 'dart:io';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/erase_account_notification_state.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

import '../secure_storage/fake_secure_key_store.dart';

void main() {
  test(
    'erase removes real notification state in support and App Group containers',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'erase-notification-state-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final support = await Directory('${temporary.path}/support').create();
      final shared = await Directory('${temporary.path}/app-group').create();
      final produced = <Directory, List<FileSystemEntity>>{};
      final sentinels = <File>[];
      for (final root in [support, shared]) {
        final sharedContainer = root == shared;
        final channel = AppGroupPathChannel(
          invoker: (_, _) async => shared.path,
        );
        final lease = await DurableNotificationToneLease.openDefault(
          supportDirectory: () async => support,
          useIosAppGroup: sharedContainer,
          appGroupPathChannel: channel,
          installedProfileId: '',
        );
        expect(await lease.claimEvent('fixture-message-id'), isTrue);
        expect(await lease.acquireTone('fixture-conversation'), isTrue);
        final registry =
            await DurableConversationNotificationIdRegistry.openDefault(
              supportDirectory: () async => support,
              useIosAppGroup: sharedContainer,
              appGroupPathChannel: channel,
              installedProfileId: '',
            );
        await registry.resolve(
          'fixture-conversation',
          activeNotificationIds: () async => const <Object?>[],
        );
        final overlay = PendingConversationNotificationOverlayStore(
          directory: Directory(
            '${root.path}/$pendingConversationNotificationOverlayDirectoryName',
          ),
          resolveBinding: () async => 'fixture-account',
          secureStore: FakeSecureKeyStore(),
        );
        expect(
          await overlay.project(
            conversationKey: 'fixture-conversation',
            canonicalSnapshot: null,
            currentMessage: PendingConversationNotificationMessage(
              eventId: 'fixture-event',
              line: 'Fixture message',
              occurredAtMicros: DateTime.now().microsecondsSinceEpoch,
            ),
          ),
          isNotNull,
        );
        final gate = RecentRemoteNotificationGate(
          supportDirectoryProvider: () async => root,
          appGroupSidecarDirProvider: sharedContainer ? () async => root : null,
          fallbackToSystemTempOnDirectoryError: false,
        );
        await gate.rebindAccount('fixture-account');
        await gate.markAnnouncement(
          payload: 'fixture-peer',
          messageId: 'provider-id',
        );
        expect(
          await gate.promoteExactAnnouncementAlias(
            sourcePayload: 'fixture-peer',
            sourceMessageId: 'provider-id',
            targetPayload: 'fixture-peer',
            targetMessageId: 'canonical-id',
          ),
          isTrue,
        );
        produced[root] = await root.list().toList();
        expect(produced[root], isNotEmpty);
        final kept = File('${root.path}/unrelated-setting');
        await kept.writeAsString('keep');
        sentinels.add(kept);
      }

      final events = <Map<String, dynamic>>[];
      final capture = installScopedE2EFlowEventSink(events.add);
      try {
        await eraseAccountNotificationState(directory: null);
      } finally {
        capture.release();
      }
      expect(events.single['event'], 'ACCOUNT_NOTIFICATION_ERASE_SKIPPED');
      expect(events.single['details'], {
        'reason': 'shared_container_unavailable',
      });

      for (final root in produced.keys) {
        await eraseAccountNotificationState(directory: root);
        for (final entry in produced[root]!) {
          expect(
            await FileSystemEntity.type(entry.path, followLinks: false),
            FileSystemEntityType.notFound,
            reason: entry.path,
          );
        }
        await eraseAccountNotificationState(directory: root);
        expect(await root.exists(), isTrue);
      }
      for (final sentinel in sentinels) {
        expect(await sentinel.readAsString(), 'keep');
      }
      expect(
        await readPersistedAppGroupContainerPath(
          supportDirectory: () async => support,
        ),
        shared.path,
      );
    },
  );
}
