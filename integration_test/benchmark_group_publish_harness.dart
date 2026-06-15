/// Simulator Benchmark: Group Publish Timing
///
/// GP-Sim-1 requires `run_group_publish_benchmark.dart`, which coordinates a
/// real Go CLI test peer joining the group before this harness publishes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '_support/cli_peer_fixture.dart';
import 'benchmark_helpers.dart';
import 'group_multi_device_real_harness.dart' as group_harness;

const _configuredSharedDir = String.fromEnvironment(
  'BENCHMARK_SHARED_DIR',
  defaultValue: '/tmp',
);
const _configuredRunId = String.fromEnvironment(
  'BENCHMARK_RUN_ID',
  defaultValue: 'adhoc',
);

String _sharedPath(String name) =>
    '$_configuredSharedDir/gp_${_configuredRunId}_$name';

void _writeSharedJson(String name, Map<String, dynamic> value) {
  Directory(_configuredSharedDir).createSync(recursive: true);
  File(_sharedPath(name)).writeAsStringSync(jsonEncode(value));
}

Future<void> _waitForSharedSignal(
  String name, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sharedPath(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('Timed out waiting for shared signal: $name');
}

Map<String, dynamic> _buildCliJoinFixture({
  required GroupModel group,
  required String groupKey,
  required int keyEpoch,
  required List<GroupMember> members,
}) {
  return {
    'groupId': group.id,
    'groupKey': groupKey,
    'keyEpoch': keyEpoch,
    'groupConfig': buildGroupConfigPayload(group, members),
  };
}

Future<group_harness.GroupMultiDeviceTestStack> _createCliGroupNode(
  Map<String, dynamic> cliPeerFixture,
) {
  final suffix = DateTime.now().millisecondsSinceEpoch;
  return group_harness.setupGroupMultiDeviceStack(
    dbName: 'benchmark_group_cli_$suffix.db',
    username: 'Bench Group Sender',
    cliPeerFixture: cliPeerFixture,
  );
}

Future<void> runGroupPublishBenchmark(WidgetTester tester) async {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  {
    print('\n${'═' * 60}');
    print('  BENCHMARK: GROUP PUBLISH — PEERS READY (GP-Sim-1)');
    print('${'═' * 60}\n');

    final cliPeerFixture = loadCliPeerFixture();
    if (cliPeerFixture == null || _configuredRunId == 'adhoc') {
      print(
        '[SKIP] GP-Sim-1 requires '
        '`integration_test/scripts/run_group_publish_benchmark.dart`',
      );
      return;
    }

    final stack = await _createCliGroupNode(cliPeerFixture);
    final sendTimings = <int>[];
    final topicPeersSeen = <int>[];

    try {
      final cliContact = stack.cliContact;
      expect(cliContact, isNotNull, reason: 'CLI contact must be available');

      final groupResult = await createGroupWithMembers(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        p2pService: stack.p2pService,
        identity: stack.identity,
        selectedContacts: [cliContact!],
        type: GroupType.chat,
        name: 'Benchmark Group',
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      );

      final group = await stack.groupRepo.getGroup(groupResult.group.id);
      final keyInfo = await stack.groupRepo.getLatestKey(groupResult.group.id);
      final members = await stack.groupRepo.getMembers(groupResult.group.id);
      expect(group, isNotNull);
      expect(keyInfo, isNotNull);

      _writeSharedJson(
        'join_fixture.json',
        _buildCliJoinFixture(
          group: group!,
          groupKey: keyInfo!.encryptedKey,
          keyEpoch: keyInfo.keyGeneration,
          members: members,
        ),
      );
      await _waitForSharedSignal('cli_joined');
      await stack.groupInviteDeliveryAttemptRepo.markJoined(
        groupId: group.id,
        peerId: cliContact.peerId,
        username: cliContact.username,
      );

      // Allow the mesh to settle after the subscriber joins.
      await Future<void>.delayed(const Duration(seconds: 5));

      for (var i = 0; i < 5; i++) {
        final events = await captureFlowEventsUntil(
          () async {
            final result = await sendGroupMessage(
              bridge: stack.bridge,
              groupRepo: stack.groupRepo,
              msgRepo: stack.groupMsgRepo,
              groupId: group.id,
              text: 'Group benchmark message ${i + 1}',
              senderPeerId: stack.identity.peerId,
              senderPublicKey: stack.identity.publicKey,
              senderPrivateKey: stack.identity.privateKey,
              senderUsername: stack.identity.username,
              inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
            );
            expect(
              result.$1,
              anyOf(
                SendGroupMessageResult.success,
                SendGroupMessageResult.successNoPeers,
              ),
            );
          },
          postActionTimeout: const Duration(seconds: 2),
          until: (captured) {
            return filterEvents(captured, 'GROUP_SEND_MSG_TIMING').isNotEmpty;
          },
        );

        final groupTimings = filterEvents(events, 'GROUP_SEND_MSG_TIMING');
        expect(groupTimings, isNotEmpty, reason: 'Missing group send timing');
        final sendDetails =
            groupTimings.first['details'] as Map<String, dynamic>;
        final elapsedMs = (sendDetails['elapsedMs'] as num).toInt();
        sendTimings.add(elapsedMs);

        final publishDebug = filterEvents(events, 'group:publish_debug');
        if (publishDebug.isNotEmpty) {
          final details = publishDebug.last['details'] as Map<String, dynamic>;
          final topicPeers = (details['topicPeers'] as num?)?.toInt() ?? 0;
          topicPeersSeen.add(topicPeers);
          print(
            '[PUBLISH ${i + 1}] elapsedMs=$elapsedMs '
            'outcome=${sendDetails['outcome']} '
            'prepareMs=${sendDetails['prepareMs'] ?? 'n/a'} '
            'publishMs=${sendDetails['publishMs'] ?? 'n/a'} '
            'inboxMs=${sendDetails['inboxMs'] ?? 'n/a'} '
            'topicPeers=$topicPeers '
            'encryptMs=${details['encryptMs'] ?? 'n/a'} '
            'signMs=${details['signMs'] ?? 'n/a'}',
          );
        }
      }

      sendTimings.sort();
      printBenchmark(
        'sim_group_publish_peers_ready_ms',
        p50: percentile(sendTimings, 50),
        p95: percentile(sendTimings, 95),
        n: sendTimings.length,
      );

      if (topicPeersSeen.isNotEmpty) {
        topicPeersSeen.sort();
        print(
          '[BENCHMARK] sim_group_publish_peers_ready_topic_peers = '
          '${topicPeersSeen.last}',
        );
      }
    } finally {
      await stack.teardown();
    }
  }
}
