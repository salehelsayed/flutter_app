import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/device_criteria.dart';

void main() {
  group('Plan 258 Android 1:1 device criteria', () {
    test(
      'connectivity requires three-message drain, network markers, no resume, and rewarm',
      () {
        final artifact = <String, Object?>{
          'scenario': 'android.connectivity_restore_inbox_drain',
          'status': 'passed',
          'deviceIds': <String>['physical-android', 'android-emulator'],
          'messagesQueued': 3,
          'messagesRendered': 3,
          'events': <String>[
            'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
            'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
            'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
          ],
          'resumeEventsDuringWindow': 0,
        };

        expect(validateConnectivityRestoreArtifact(artifact).ok, isTrue);

        artifact['deviceIds'] = <String>[
          'physical-android',
          'physical-android',
        ];
        expect(validateConnectivityRestoreArtifact(artifact).ok, isFalse);
        artifact['deviceIds'] = <String>[
          'physical-android',
          'android-emulator',
        ];

        artifact['resumeEventsDuringWindow'] = 1;
        expect(validateConnectivityRestoreArtifact(artifact).ok, isFalse);

        artifact['resumeEventsDuringWindow'] = 0;
        (artifact['events']! as List<String>).add('APP_LIFECYCLE_RESUME_BEGIN');
        expect(validateConnectivityRestoreArtifact(artifact).ok, isFalse);

        artifact['events'] = <String>[
          'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
          'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
          'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
        ];
        expect(validateConnectivityRestoreArtifact(artifact).ok, isFalse);
      },
    );

    test(
      'keepalive requires drop/skip, no direct attempt, bounded custody, recovery, and re-arm',
      () {
        final artifact = <String, Object?>{
          'scenario': 'android.keepalive_drop_skip_direct',
          'status': 'passed',
          'events': <String>[
            // A healthy precondition ping must not be mistaken for the later
            // re-arm. The validator has to select a success after the dropped
            // send, rather than the first success in the campaign trace.
            'P2P_SERVICE_PEER_PING_SUCCESS',
            'KEEPALIVE_PEER_DROP',
            'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
            'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
            'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
            'DELIVERY_RECEIPT_APPLIED',
            'P2P_SERVICE_PEER_PING_SUCCESS',
          ],
          'sendWindowEvents': <String>[
            'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
            'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
            'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
          ],
          'messageIdPrefix': 'a1b2c3d4',
          'messageEvents': <Map<String, Object?>>[
            <String, Object?>{
              'event': 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
              'eventIndex': 2,
              'messageIdPrefix': 'a1b2c3d4',
            },
            <String, Object?>{
              'event': 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
              'eventIndex': 3,
              'messageIdPrefix': 'a1b2c3d4',
            },
            <String, Object?>{
              'event': 'DELIVERY_RECEIPT_APPLIED',
              'eventIndex': 5,
              'messageIdPrefix': 'a1b2c3d4',
            },
          ],
          'deviceIds': <String>['physical-android', 'android-emulator'],
          'custodyLatencyMs': 850,
        };

        expect(validateKeepaliveDropArtifact(artifact).ok, isTrue);

        artifact['deviceIds'] = <String>[
          'android-emulator',
          'android-emulator',
        ];
        expect(validateKeepaliveDropArtifact(artifact).ok, isFalse);
        artifact['deviceIds'] = <String>[
          'physical-android',
          'android-emulator',
        ];

        (artifact['sendWindowEvents']! as List<String>).add(
          'P2P_SERVICE_DIAL_PEER_BEGIN',
        );
        expect(validateKeepaliveDropArtifact(artifact).ok, isFalse);

        artifact['sendWindowEvents'] = <String>[
          'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
          'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
          'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
        ];
        final messageEvents =
            artifact['messageEvents']! as List<Map<String, Object?>>;
        messageEvents.last['messageIdPrefix'] = 'deadbeef';
        expect(
          validateKeepaliveDropArtifact(artifact).ok,
          isFalse,
          reason: 'a receipt from another message cannot close recovery',
        );

        messageEvents.last['messageIdPrefix'] = 'a1b2c3d4';
        artifact['events'] = <String>[
          'P2P_SERVICE_PEER_PING_SUCCESS',
          'KEEPALIVE_PEER_DROP',
          'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
          'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
          'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
          'DELIVERY_RECEIPT_APPLIED',
        ];
        expect(
          validateKeepaliveDropArtifact(artifact).ok,
          isFalse,
          reason: 'a pre-drop health ping is not post-send re-arm evidence',
        );
      },
    );

    test(
      'wake artifact requires equal SHA-256 values and rejects raw tokens',
      () {
        const hash =
            'c6d6d8f1db3f5f96b1a2cde64d7f996202bf72afde5275c7fd9d96f74ea68f31';
        final artifact = <String, Object?>{
          'scenario': 'android.wake_token_directionality',
          'status': 'passed',
          'registeredTokenSha256': hash,
          'storedTokenSha256': hash,
          'attachedTokenSha256': hash,
          'deviceIds': <String>['physical-android', 'android-emulator'],
        };

        expect(validateWakeTokenArtifact(artifact).ok, isTrue);

        artifact['rawWakeToken'] = 'secret-token';
        expect(validateWakeTokenArtifact(artifact).ok, isFalse);

        artifact.remove('rawWakeToken');
        artifact['deviceIds'] = <String>[
          'physical-android',
          'physical-android',
        ];
        expect(validateWakeTokenArtifact(artifact).ok, isFalse);

        artifact['deviceIds'] = <String>['physical-android', '   '];
        expect(validateWakeTokenArtifact(artifact).ok, isFalse);
      },
    );

    test(
      'recorder requires pregrant, real plugin, decodable M4A, duration, and cleanup',
      () {
        final artifact = <String, Object?>{
          'scenario': 'android.voice_recorder_native_smoke',
          'status': 'passed',
          'permissionPregranted': true,
          'realRecordPlugin': true,
          'mime': 'audio/mp4',
          'sizeBytes': 4096,
          'durationMs': 2050,
          'decodable': true,
          'temporaryFileDeleted': true,
        };

        expect(validateVoiceRecorderArtifact(artifact).ok, isTrue);

        artifact['realRecordPlugin'] = false;
        expect(validateVoiceRecorderArtifact(artifact).ok, isFalse);
      },
    );

    test(
      'selected, attempted, and terminal 1:1 scenario IDs must match exactly',
      () {
        const selected = <String>['connectivity', 'keepalive', 'wake'];
        const attempted = <String>['connectivity', 'keepalive', 'wake'];
        const terminal = <String>['connectivity', 'keepalive', 'wake'];

        expect(
          validateScenarioReconciliation(
            selected: selected,
            attempted: attempted,
            terminal: terminal,
          ).ok,
          isTrue,
        );
        expect(
          validateScenarioReconciliation(
            selected: selected,
            attempted: attempted.take(2),
            terminal: terminal,
          ).ok,
          isFalse,
        );
      },
    );

    test('LAN/topology N/A is visible and never claims the proof boundary', () {
      final artifact = <String, Object?>{
        'scenario': 'android.same_lan_mdns',
        'status': 'notApplicable',
        'reasonCode': 'target_topology_unavailable',
        'attempted': false,
        'boundaryProven': false,
      };

      expect(validateTopologyNotApplicable(artifact).ok, isTrue);

      artifact['boundaryProven'] = true;
      expect(validateTopologyNotApplicable(artifact).ok, isFalse);
    });
  });
}
