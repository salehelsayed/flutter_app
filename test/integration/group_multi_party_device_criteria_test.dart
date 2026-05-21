import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

void main() {
  group('group multi-party device criteria', () {
    test('all scenario list includes device-backed GE and GM coverage', () {
      expect(
        allGroupMultiPartyDeviceScenarioIds,
        containsAll(<String>[
          'ge001',
          'ge002',
          'ge003',
          'ge004',
          'ge005',
          'ge006',
          'ge007',
          'ge008',
          'ge009',
          'ge010',
          'ge011',
          'ge012',
          'ge013',
          'ge014',
          'ge015',
          'ge016',
          'ge020',
          'ge021',
          'ge023',
          'ge024',
          'gm001',
          'de002',
          'de003',
          'de007',
          'de017',
          'ir001',
          'ir015',
          'pl002',
          'pl012',
          'private_abc_create',
          'private_online_add',
          'private_offline_readd',
          'private_readd_current',
          'private_readd_active_members',
          'private_readd_alternating_churn',
          'private_network_chaos_invariants',
          'private_rotated_device_readd',
          'private_same_user_multi_device_readd',
          'private_readd_cycles',
          'private_rapid_readd',
          'private_concurrent_admin_membership_edits',
          'private_timeline_truth',
          'private_history_retention',
          'private_invite_terminal_states',
          'private_stale_invite_readd',
          'private_admin_role_transfer_delivery',
          'gm002',
          'gm035',
        ]),
      );
      expect(allGroupMultiPartyDeviceScenarioIds, isNot(contains('all')));
      for (final scenario in allGroupMultiPartyDeviceScenarioIds) {
        expect(scenarioRequirement(scenario).scenario, scenario);
      }
    });

    test('scenario requirements map GM roles to device counts', () {
      expect(scenarioRequirement('ge001').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge001').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge002').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge002').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge003').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge003').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge004').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge004').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge005').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge005').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge006').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge006').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge007').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge007').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge008').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge008').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge009').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge009').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge010').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge010').requiredDeviceCount, 3);
      expect(scenarioRequirement('go001').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('go001').requiredDeviceCount, 3);
      expect(scenarioRequirement('go002').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('go002').requiredDeviceCount, 3);
      expect(scenarioRequirement('go003').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('go003').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge011').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge011').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge012').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge012').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge013').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge013').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge014').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge014').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge015').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge015').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge016').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge016').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge020').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge020').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge021').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge021').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge023').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge023').requiredDeviceCount, 3);
      expect(scenarioRequirement('ge024').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ge024').requiredDeviceCount, 3);
      expect(scenarioRequirement('private_abc_create').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(scenarioRequirement('private_abc_create').requiredDeviceCount, 3);
      expect(scenarioRequirement('private_full_mesh_online').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_full_mesh_online').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_relay_only_delivery').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_relay_only_delivery').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_partition_readd_heal').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_partition_readd_heal').requiredDeviceCount,
        3,
      );
      expect(
        scenarioRequirement('private_relay_reconnect_group_recovery').roles,
        ['alice', 'bob', 'charlie'],
      );
      expect(
        scenarioRequirement(
          'private_relay_reconnect_group_recovery',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_peer_disconnect_not_removal').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_peer_disconnect_not_removal',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_long_offline_epoch_churn').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_long_offline_epoch_churn',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_online_add').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(scenarioRequirement('private_online_add').requiredDeviceCount, 4);
      expect(scenarioRequirement('gm001').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm001').requiredDeviceCount, 3);
      expect(scenarioRequirement('de002').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('de002').requiredDeviceCount, 3);
      expect(scenarioRequirement('de003').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('de003').requiredDeviceCount, 3);
      expect(scenarioRequirement('de007').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('de007').requiredDeviceCount, 3);
      expect(scenarioRequirement('ir001').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ir001').requiredDeviceCount, 3);
      expect(scenarioRequirement('ir015').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ir015').requiredDeviceCount, 3);
      expect(scenarioRequirement('ir016').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('ir016').requiredDeviceCount, 3);
      expect(scenarioRequirement('pl002').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('pl002').requiredDeviceCount, 3);
      expect(scenarioRequirement('pl012').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('pl012').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm002').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(scenarioRequirement('gm002').requiredDeviceCount, 4);
      expect(scenarioRequirement('gm003').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(scenarioRequirement('gm003').requiredDeviceCount, 4);
      expect(scenarioRequirement('gm004').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm004').requiredDeviceCount, 3);
      expect(scenarioRequirement('private_online_remove').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_online_remove').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_offline_remove').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_offline_remove').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_offline_readd').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_offline_readd').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_readd_current').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_readd_current').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_readd_active_members').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(
        scenarioRequirement('private_readd_active_members').requiredDeviceCount,
        4,
      );
      expect(scenarioRequirement('private_readd_alternating_churn').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(
        scenarioRequirement(
          'private_readd_alternating_churn',
        ).requiredDeviceCount,
        4,
      );
      expect(scenarioRequirement('private_network_chaos_invariants').roles, [
        'alice',
        'bob',
        'charlie',
        'dana',
      ]);
      expect(
        scenarioRequirement(
          'private_network_chaos_invariants',
        ).requiredDeviceCount,
        4,
      );
      expect(scenarioRequirement('private_late_leave_readd').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_late_leave_readd').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_rotated_device_readd').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_rotated_device_readd').requiredDeviceCount,
        3,
      );
      expect(
        scenarioRequirement('private_same_user_multi_device_readd').roles,
        ['alice', 'bob', 'charlie', 'dana'],
      );
      expect(
        scenarioRequirement(
          'private_same_user_multi_device_readd',
        ).requiredDeviceCount,
        4,
      );
      expect(scenarioRequirement('private_readd_cycles').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_readd_cycles').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_rapid_readd').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(scenarioRequirement('private_rapid_readd').requiredDeviceCount, 3);
      expect(
        scenarioRequirement('private_concurrent_admin_membership_edits').roles,
        ['alice', 'bob', 'charlie', 'dana'],
      );
      expect(
        scenarioRequirement(
          'private_concurrent_admin_membership_edits',
        ).requiredDeviceCount,
        4,
      );
      expect(scenarioRequirement('private_timeline_truth').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_timeline_truth').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_history_retention').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_history_retention').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_invite_terminal_states').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_invite_terminal_states',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_stale_invite_readd').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_stale_invite_readd').requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_stale_lower_key_update').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_stale_lower_key_update',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_same_epoch_key_conflict').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_same_epoch_key_conflict',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('private_partial_key_distribution').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_partial_key_distribution',
        ).requiredDeviceCount,
        3,
      );
      expect(
        scenarioRequirement('private_admin_role_transfer_delivery').roles,
        ['alice', 'bob', 'charlie'],
      );
      expect(
        scenarioRequirement(
          'private_admin_role_transfer_delivery',
        ).requiredDeviceCount,
        3,
      );
      expect(scenarioRequirement('gm005').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm005').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm006').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm006').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm007').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm007').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm008').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm008').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm009').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm009').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm010').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm010').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm011').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm011').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm012').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm012').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm013').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm013').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm014').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm014').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm015').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm015').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm016').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm016').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm017').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm017').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm018').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm018').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm019').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm019').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm020').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm020').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm021').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm021').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm022').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm022').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm023').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm023').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm024').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm024').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm025').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm025').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm033').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm033').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm034').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm034').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm035').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm035').requiredDeviceCount, 3);

      final invalid = evaluateDeviceSelection(
        scenario: 'gm001',
        deviceIds: const <String>['alice-device', 'bob-device'],
      );

      expect(invalid.ok, isFalse);
      expect(invalid.detail, contains('requires 3 device IDs'));
    });

    test('device selection requires distinct app targets for each role', () {
      final valid = evaluateDeviceSelection(
        scenario: 'gm002',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
          'dana-device',
        ],
      );

      expect(valid.ok, isTrue);
      expect(
        roleDeviceMapForScenario(
          scenario: 'gm002',
          deviceIds: const <String>[
            'alice-device',
            'bob-device',
            'charlie-device',
            'dana-device',
          ],
        ),
        {
          'alice': 'alice-device',
          'bob': 'bob-device',
          'charlie': 'charlie-device',
          'dana': 'dana-device',
        },
      );

      final duplicate = evaluateDeviceSelection(
        scenario: 'gm002',
        deviceIds: const <String>[
          'same-device',
          'bob-device',
          'charlie-device',
          'same-device',
        ],
      );

      expect(duplicate.ok, isFalse);
      expect(duplicate.detail, contains('distinct Flutter app targets'));
    });

    test('relay configuration must use the exact app relay profile', () {
      expect(
        evaluateRelayConfiguration(expectedMultiPartyRelayAddresses).ok,
        isTrue,
      );

      final missing = evaluateRelayConfiguration(null);
      expect(missing.ok, isFalse);
      expect(missing.detail, contains('MKNOON_RELAY_ADDRESSES is required'));

      final wrong = evaluateRelayConfiguration('/dns/example/tcp/4001');
      expect(wrong.ok, isFalse);
      expect(wrong.detail, contains('does not match'));
    });

    test(
      'ML-016 private_non_friend_member_delivery accepts no-contact Dana delivery proof',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_non_friend_member_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validMl016NonFriendVerdicts(),
        );

        expect(verdict.ok, isTrue, reason: verdict.detail);
        expect(
          verdict.detail,
          contains('private_non_friend_member_delivery verdicts valid'),
        );
      },
    );

    test(
      'ML-016 private_non_friend_member_delivery rejects contact-seeded Dana proof',
      () {
        final verdicts = _validMl016NonFriendVerdicts();
        verdicts[2] = _withMl016ProofOverrides(
          verdicts[2],
          const <String, Object?>{'danaHasSavedAliceContact': true},
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_non_friend_member_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'dana: ml016NonFriendDeliveryProof.danaHasSavedAliceContact must be false',
          ),
        );
      },
    );

    test(
      'ML-016 private_non_friend_member_delivery rejects blank stable labels',
      () {
        final verdicts = _validMl016NonFriendVerdicts();
        verdicts[2] = _withMl016ProofOverrides(
          verdicts[2],
          const <String, Object?>{
            'aliceStableSenderLabel': '',
            'bobStableSenderLabel': 'Unknown',
          },
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_non_friend_member_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('aliceStableSenderLabel'));
        expect(rejected.detail, contains('bobStableSenderLabel'));
      },
    );

    test('ML-020 accepts private_admin_role_transfer_delivery proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_admin_role_transfer_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validMl020AdminRoleTransferVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_admin_role_transfer_delivery verdicts valid'),
      );
    });

    test(
      'ML-020 private_admin_role_transfer_delivery rejects creator-bound proof',
      () {
        final verdicts = _validMl020AdminRoleTransferVerdicts();
        verdicts[0] = _withMl020ProofOverrides(
          verdicts[0],
          const <String, Object?>{'creatorRequiredForDelivery': true},
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_admin_role_transfer_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'alice: ml020AdminRoleDeliveryProof.creatorRequiredForDelivery must be false',
          ),
        );
      },
    );

    test(
      'ML-020 private_admin_role_transfer_delivery rejects removed-window delivery to Charlie',
      () {
        final verdicts = _validMl020AdminRoleTransferVerdicts();
        final charlie = verdicts[2];
        charlie['receivedMessages'] = <Map<String, Object?>>[
          ...List<Map<String, Object?>>.from(
            charlie['receivedMessages'] as List,
          ),
          _received(
            'aliceRemovedWindowAfterDemotion',
            'msg-ml020-alice-removed',
            'ML-020 Alice removed-window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ];
        verdicts[2] = _withMl020ProofOverrides(charlie, const <String, Object?>{
          'charlieReceivedRemovedWindow': true,
          'removedWindowPlaintextCount': 1,
        });

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_admin_role_transfer_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('charlieReceivedRemovedWindow'));
        expect(rejected.detail, contains('removedWindowPlaintextCount'));
      },
    );

    test('PL-009 accepts private reaction roundtrip verdicts', () {
      expect(scenarioRequirement('private_reaction_roundtrip').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement('private_reaction_roundtrip').requiredDeviceCount,
        3,
      );

      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_reaction_roundtrip',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReactionRoundtripVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_reaction_roundtrip verdicts valid'),
      );
    });

    test('PL-009 rejects reaction proofs without receiver stream evidence', () {
      final verdicts = _validPrivateReactionRoundtripVerdicts();
      verdicts[2] = _withPl009ProofOverrides(
        verdicts[2],
        const <String, Object?>{'receivedViaGroupReactionStream': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_reaction_roundtrip',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: PL-009 reaction must arrive through group reaction stream',
        ),
      );
    });

    test('PL-010 accepts removed reaction rejection verdicts', () {
      expect(scenarioRequirement('private_removed_reaction_rejected').roles, [
        'alice',
        'bob',
        'charlie',
      ]);
      expect(
        scenarioRequirement(
          'private_removed_reaction_rejected',
        ).requiredDeviceCount,
        3,
      );

      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_removed_reaction_rejected',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateRemovedReactionRejectedVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_removed_reaction_rejected verdicts valid'),
      );
    });

    test('PL-010 rejects visible reaction mutation on remaining member', () {
      final verdicts = _validPrivateRemovedReactionRejectedVerdicts();
      verdicts[1] = _withPl010ProofOverrides(
        verdicts[1],
        const <String, Object?>{
          'visibleStateUnchanged': false,
          'visibleReactionCountForTarget': 1,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_removed_reaction_rejected',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: PL-010 removed reaction must not mutate visible reactions',
        ),
      );
    });

    test('PL-010 rejects accepted app-peer reaction after removal', () {
      final verdicts = _validPrivateRemovedReactionRejectedVerdicts();
      verdicts[2] =
          _withPl010ProofOverrides(verdicts[2], const <String, Object?>{
            'reactionOutcome': 'success',
            'reactionAccepted': true,
            'reactionRejectedOrIgnored': true,
          });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_removed_reaction_rejected',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: PL-010 Charlie app-peer reaction must be rejected after removal',
        ),
      );
    });

    test('accepts valid GM-001 A/B/C receiver persistence verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm001Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm001 verdicts valid'));
    });

    test('rejects GM-001 without DE-001 live delivery proof', () {
      final missingProof = _validGm001Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('de001LiveDeliveryProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing DE-001 live delivery proof fields'),
      );
    });

    test('rejects GM-001 DE-001 timestamp mismatch', () {
      final wrongTimestamp = _validGm001Verdicts();
      wrongTimestamp[1] = {
        ...wrongTimestamp[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceInitial',
            'gm001-a1',
            'hello gm001',
            'alice-peer',
            groupId: 'gm001-group',
            keyEpoch: 1,
            timestamp: '2026-05-12T14:36:17.000000Z',
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongTimestamp,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received aliceInitial timestamp mismatch'),
      );
    });

    test('accepts valid DE-002 rapid ordered delivery verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'de002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validDe002Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('de002 verdicts valid'));
    });

    test('rejects DE-002 without ordered delivery proof', () {
      final missingProof = _validDe002Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('de002OrderedDeliveryProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing DE-002 ordered delivery proof fields'),
      );
    });

    test('rejects DE-002 out-of-order receiver proof', () {
      final outOfOrder = _validDe002Verdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        outOfOrder[1]['receivedMessages'] as List,
      );
      final first = bobReceived[0];
      bobReceived[0] = bobReceived[1];
      bobReceived[1] = first;
      outOfOrder[1] = {...outOfOrder[1], 'receivedMessages': bobReceived};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: outOfOrder,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received DE-002 keys are not in sequence order'),
      );
    });

    test('accepts valid DE-003 caller message id verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'de003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validDe003Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('de003 verdicts valid'));
    });

    test('rejects DE-003 without message id proof', () {
      final missingProof = _validDe003Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('de003MessageIdProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing DE-003 message id proof fields'),
      );
    });

    test('rejects DE-003 receiver message id mismatch', () {
      final wrongId = _validDe003Verdicts();
      wrongId[1] = {
        ...wrongId[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceExplicit',
            'wrong-de003-id',
            'DE-003 explicit id',
            'alice-peer',
            groupId: 'de003-group',
            keyEpoch: 1,
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongId,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('messageId mismatch'));
    });

    test('accepts valid DE-007 zero-peer replay verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'de007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validDe007Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('de007 verdicts valid'));
    });

    test('rejects DE-007 without zero-peer proof', () {
      final missingProof = _validDe007Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('de007ZeroPeerProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing DE-007 zero-peer proof fields'),
      );
    });

    test('rejects DE-007 receiver message id mismatch', () {
      final wrongId = _validDe007Verdicts();
      wrongId[1] = {
        ...wrongId[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceZeroPeer',
            'wrong-de007-id',
            'DE-007 zero-peer durable fallback',
            'alice-peer',
            groupId: 'de007-group',
            keyEpoch: 1,
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongId,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('message id mismatch'));
    });

    test('accepts valid DE-017 membership-ordering verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'de017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validDe017Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('de017 verdicts valid'));
    });

    test('rejects DE-017 without membership-ordering proof', () {
      final missingProof = _validDe017Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('de017MembershipOrderingProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing DE-017 membership-ordering proof fields'),
      );
    });

    test('rejects DE-017 repaired post-removal leak', () {
      final leaked = _validDe017Verdicts();
      leaked[1] = {
        ...leaked[1],
        'de017MembershipOrderingProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[1]['de017MembershipOrderingProof'] as Map,
          ),
          'postRemovalPersistedCountAfterRepair': 1,
          'repairedPostRemovalContent': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'de017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: de017MembershipOrderingProof.repairedPostRemovalContent must be true',
        ),
      );
    });

    test('accepts valid IR-001 offline active reconnect verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validIr001Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('ir001 verdicts valid'));
    });

    test('rejects IR-001 without offline reconnect proof', () {
      final missingProof = _validIr001Verdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ir001OfflineReconnectProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing IR-001 offline reconnect proof fields'),
      );
    });

    test('rejects IR-001 missed backlog count mismatch', () {
      final wrongCount = _validIr001Verdicts();
      wrongCount[1] = {
        ...wrongCount[1],
        'ir001OfflineReconnectProof': <String, Object?>{
          ...Map<String, Object?>.from(
            wrongCount[1]['ir001OfflineReconnectProof'] as Map,
          ),
          'drainedMissedCount': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongCount,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ir001OfflineReconnectProof.drainedMissedCount must be 3',
        ),
      );
    });

    test('rejects IR-001 post-drain live delivery without live proof', () {
      final notLive = _validIr001Verdicts();
      notLive[1] = {
        ...notLive[1],
        'ir001OfflineReconnectProof': <String, Object?>{
          ...Map<String, Object?>.from(
            notLive[1]['ir001OfflineReconnectProof'] as Map,
          ),
          'liveAfterDrainWasLive': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: notLive,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ir001OfflineReconnectProof.liveAfterDrainWasLive must be true',
        ),
      );
    });

    test('accepts valid IR-015 variant replay verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validIr015Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('ir015 verdicts valid'));
    });

    test('rejects IR-015 without media rehydration proof', () {
      final missingMedia = _validIr015Verdicts();
      missingMedia[1] = {
        ...missingMedia[1],
        'ir015VariantReplayProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingMedia[1]['ir015VariantReplayProof'] as Map,
          ),
          'mediaVariantsRehydrated': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingMedia,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ir015VariantReplayProof.mediaVariantsRehydrated must be true',
        ),
      );
    });

    test('rejects IR-015 quote target mismatch', () {
      final wrongQuote = _validIr015Verdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        wrongQuote[1]['receivedMessages'] as List,
      );
      final quoteIndex = bobReceived.indexWhere(
        (entry) => entry['key'] == 'aliceIr015Quote',
      );
      bobReceived[quoteIndex] = {
        ...bobReceived[quoteIndex],
        'quotedMessageId': 'wrong-parent',
      };
      wrongQuote[1] = {...wrongQuote[1], 'receivedMessages': bobReceived};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongQuote,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: ir015VariantReplayProof quote did not reference text'),
      );
    });

    test('IR-016 accepts long-offline retention cutoff proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validIr016Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('ir016 verdicts valid'));
    });

    test('IR-016 rejects silent-complete Bob retention proof', () {
      final silentComplete = _validIr016Verdicts();
      silentComplete[1] = {
        ...silentComplete[1],
        'ir016RetentionCutoffProof': <String, Object?>{
          ...Map<String, Object?>.from(
            silentComplete[1]['ir016RetentionCutoffProof'] as Map,
          ),
          'lastBacklogExpiredAtRecorded': false,
          'explicitRetentionStateRecorded': false,
          'noSilentCompleteState': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: silentComplete,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ir016RetentionCutoffProof.noSilentCompleteState must be true',
        ),
      );
    });

    test('IR-016 rejects Bob expired-message resurrection', () {
      final resurrected = _validIr016Verdicts();
      resurrected[1] = {
        ...resurrected[1],
        'ir016RetentionCutoffProof': <String, Object?>{
          ...Map<String, Object?>.from(
            resurrected[1]['ir016RetentionCutoffProof'] as Map,
          ),
          'expiredBacklogSkipped': false,
          'expiredVisibleCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ir016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: resurrected,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ir016RetentionCutoffProof.expiredVisibleCount must be 0',
        ),
      );
    });

    test('PL-002 accepts valid media-only empty-text verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPl002Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('pl002 verdicts valid'));
    });

    test('PL-002 rejects missing recipient media descriptor proof', () {
      final missingMedia = _validPl002Verdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        missingMedia[1]['receivedMessages'] as List,
      );
      bobReceived[0] = {...bobReceived[0], 'media': <Map<String, Object?>>[]};
      missingMedia[1] = {...missingMedia[1], 'receivedMessages': bobReceived};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingMedia,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: pl002MediaOnlyProof received media-only descriptor mismatch',
        ),
      );
    });

    test('PL-002 rejects non-empty text in media-only proof', () {
      final wrongText = _validPl002Verdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        wrongText[0]['sentMessages'] as List,
      );
      aliceSent[0] = {...aliceSent[0], 'text': 'not media only'};
      wrongText[0] = {...wrongText[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongText,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: pl002MediaOnlyProof sent media-only descriptor mismatch',
        ),
      );
    });

    test('PL-012 accepts valid media schema variant verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPl012Verdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('pl012 verdicts valid'));
    });

    test('PL-012 rejects missing recipient variant descriptor', () {
      final missingMedia = _validPl012Verdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        missingMedia[1]['receivedMessages'] as List,
      );
      final media = List<Map<String, Object?>>.from(
        bobReceived[0]['media'] as List,
      );
      bobReceived[0] = {
        ...bobReceived[0],
        'media': media
            .where((attachment) => attachment['mime'] != 'image/gif')
            .toList(growable: false),
        'mediaCount': 4,
      };
      missingMedia[1] = {...missingMedia[1], 'receivedMessages': bobReceived};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingMedia,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: pl012MediaSchemaProof received variant descriptor mismatch',
        ),
      );
    });

    test('PL-012 rejects missing voice waveform', () {
      final missingWaveform = _validPl012Verdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        missingWaveform[0]['sentMessages'] as List,
      );
      final media = List<Map<String, Object?>>.from(
        aliceSent[0]['media'] as List,
      );
      aliceSent[0] = {
        ...aliceSent[0],
        'media': media
            .map((attachment) {
              if (attachment['mediaType'] != 'audio') return attachment;
              return <String, Object?>{
                for (final entry in attachment.entries)
                  if (entry.key != 'waveform') entry.key: entry.value,
              };
            })
            .toList(growable: false),
      };
      missingWaveform[0] = {...missingWaveform[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'pl012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingWaveform,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: pl012MediaSchemaProof sent variant descriptor mismatch',
        ),
      );
    });

    test('NW-001 accepts valid private full-mesh online verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateFullMeshOnlineVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_full_mesh_online verdicts valid'),
      );
    });

    test('NW-001 rejects Alice-only full-mesh proof', () {
      final aliceOnly = _validPrivateFullMeshOnlineVerdicts();
      aliceOnly[1] = {
        ...aliceOnly[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };
      aliceOnly[2] = {
        ...aliceOnly[2],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: aliceOnly,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bob: missing received proof keys'));
      expect(rejected.detail, contains('charlie: missing received proof keys'));
    });

    test('NW-001 rejects missing Bob or Charlie publish proof', () {
      final missingBobPublish = _validPrivateFullMeshOnlineVerdicts();
      missingBobPublish[1] = {
        ...missingBobPublish[1],
        'sentMessages': const <Map<String, Object?>>[],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingBobPublish,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bob: sent bobFullMesh count=0'));
    });

    test('NW-001 rejects missing topic peer counts', () {
      final missingTopicCounts = _validPrivateFullMeshOnlineVerdicts();
      missingTopicCounts[0] = _withNw001ProofOverrides(
        missingTopicCounts[0],
        const <String, Object?>{'topicPeerCountsBySender': <String, int>{}},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingTopicCounts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: nw001FullMeshProof.topicPeerCountsBySender.alice'),
      );
    });

    test('NW-001 rejects zero or partial peer publish proof', () {
      final partialPeer = _validPrivateFullMeshOnlineVerdicts();
      final bobSent = List<Map<String, Object?>>.from(
        partialPeer[1]['sentMessages'] as List,
      );
      bobSent[0] = {
        ...bobSent[0],
        'outcome': 'successNoPeers',
        'topicPeers': 0,
        'liveFanoutState': 'zero_peers',
      };
      partialPeer[1] = _withNw001ProofOverrides(
        {...partialPeer[1], 'sentMessages': bobSent},
        const <String, Object?>{
          'successNoPeersCount': 1,
          'partialPeerPublishCount': 1,
          'topicPeerCountsBySender': <String, int>{
            'alice': 2,
            'bob': 0,
            'charlie': 2,
          },
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: partialPeer,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bob: NW-001 bobFullMesh must publish'));
      expect(rejected.detail, contains('successNoPeersCount must be 0'));
      expect(rejected.detail, contains('partialPeerPublishCount must be 0'));
    });

    test(
      'NW-001 rejects missing receiver tuple and duplicate visible message',
      () {
        final missingReceiver = _validPrivateFullMeshOnlineVerdicts();
        final bobReceived = List<Map<String, Object?>>.from(
          missingReceiver[1]['receivedMessages'] as List,
        )..removeWhere((entry) => entry['key'] == 'charlieFullMesh');
        missingReceiver[1] = _withNw001ProofOverrides(
          {
            ...missingReceiver[1],
            'receivedMessages': bobReceived,
            'persistedMessageCounts': const <String, int>{
              'aliceFullMesh': 1,
              'charlieFullMesh': 2,
            },
          },
          const <String, Object?>{'duplicateVisibleMessageCount': 1},
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_full_mesh_online',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingReceiver,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('bob: received charlieFullMesh count=0'),
        );
        expect(
          rejected.detail,
          contains('duplicateVisibleMessageCount must be 0'),
        );
      },
    );

    test('NW-001 rejects non-NW-001 proof row id', () {
      final wrongRow = _validPrivateFullMeshOnlineVerdicts();
      wrongRow[2] = _withNw001ProofOverrides(
        wrongRow[2],
        const <String, Object?>{'rowId': 'GM-001'},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_full_mesh_online',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongRow,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: nw001FullMeshProof.rowId must be NW-001'),
      );
    });

    test('NW-002 accepts valid relay-only delivery verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateRelayOnlyDeliveryVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_relay_only_delivery verdicts valid'),
      );
    });

    test('NW-002 rejects direct-only route proof', () {
      final directOnly = _validPrivateRelayOnlyDeliveryVerdicts();
      for (var i = 0; i < directOnly.length; i++) {
        directOnly[i] = _withNw002ProofOverrides(
          directOnly[i],
          const <String, Object?>{
            'circuitOrRelayRouteProven': false,
            'directPathSuppressed': false,
          },
        );
      }

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: directOnly,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('circuitOrRelayRouteProven'));
      expect(rejected.detail, contains('directPathSuppressed'));
    });

    test('NW-002 rejects fabricated route booleans without diagnostics', () {
      final fabricated = _validPrivateRelayOnlyDeliveryVerdicts();
      for (var i = 0; i < fabricated.length; i++) {
        fabricated[i] =
            _withNw002ProofOverrides(fabricated[i], const <String, Object?>{
              'circuitOrRelayRouteProven': true,
              'directPathSuppressed': true,
              'routeDiagnostics': <Map<String, Object?>>[],
            });
      }

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: fabricated,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('must be backed by a Bob route diagnostic'),
      );
    });

    test('NW-002 rejects scenario-only route diagnostics', () {
      final fabricated = _validPrivateRelayOnlyDeliveryVerdicts();
      for (var i = 0; i < fabricated.length; i++) {
        fabricated[i] = _withNw002ProofOverrides(
          fabricated[i],
          const <String, Object?>{
            'circuitOrRelayRouteProven': true,
            'directPathSuppressed': true,
            'routeDiagnostics': <Map<String, Object?>>[
              <String, Object?>{
                'scenario': 'private_relay_only_delivery',
                'relayEnvPresent': true,
              },
            ],
          },
        );
      }

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: fabricated,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('must be backed by a Bob route diagnostic'),
      );
    });

    test('NW-002 rejects missing relay-only role', () {
      final missingRelayRole = _validPrivateRelayOnlyDeliveryVerdicts();
      missingRelayRole[0] = _withNw002ProofOverrides(
        missingRelayRole[0],
        const <String, Object?>{'relayOnlyRoles': <String>[]},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingRelayRole,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('relayOnlyRoles must include bob'));
    });

    test('NW-002 rejects missing routed receiver and publish-back proof', () {
      final missingTuples = _validPrivateRelayOnlyDeliveryVerdicts();
      final charlieReceived = List<Map<String, Object?>>.from(
        missingTuples[2]['receivedMessages'] as List,
      )..removeWhere((entry) => entry['key'] == 'bobRelayOnlyPublishBack');
      missingTuples[2] = _withNw002ProofOverrides(
        {
          ...missingTuples[2],
          'receivedMessages': charlieReceived,
          'persistedMessageCounts': const <String, int>{
            'aliceToRelayOnlyBob': 1,
          },
        },
        const <String, Object?>{
          'routedSenderPublishBackCovered': false,
          'deliveryModeByMessage': <String, Object?>{
            'aliceToRelayOnlyBob': <String, Object?>{
              'senderRole': 'alice',
              'routedReceiverRoles': <String>[],
              'deliveryMode': 'live_pubsub',
            },
          },
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingTuples,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('missing routed receiver bob'));
      expect(rejected.detail, contains('routedSenderPublishBackCovered'));
      expect(
        rejected.detail,
        contains('received bobRelayOnlyPublishBack count=0'),
      );
    });

    test('NW-002 rejects successNoPeers without replay proof', () {
      final noReplay = _validPrivateRelayOnlyDeliveryVerdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        noReplay[0]['sentMessages'] as List,
      );
      aliceSent[0] = {...aliceSent[0], 'outcome': 'successNoPeers'};
      noReplay[0] = _withNw002ProofOverrides(
        {...noReplay[0], 'sentMessages': aliceSent},
        const <String, Object?>{'successNoPeersCount': 1},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: noReplay,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('successNoPeers'));
      expect(rejected.detail, contains('replay'));
    });

    test(
      'NW-002 rejects duplicate visible delivery or membership mutation',
      () {
        final duplicateAndMutation = _validPrivateRelayOnlyDeliveryVerdicts();
        duplicateAndMutation[1] = _withNw002ProofOverrides(
          duplicateAndMutation[1],
          const <String, Object?>{
            'duplicateVisibleMessageCount': 1,
            'membershipMutationCount': 1,
          },
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_relay_only_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: duplicateAndMutation,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('duplicateVisibleMessageCount'));
        expect(rejected.detail, contains('membershipMutationCount'));
      },
    );

    test('NW-003 accepts complete partition re-add heal proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivatePartitionReaddHealVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_partition_readd_heal verdicts valid'),
      );
    });

    test('NW-003 rejects missing row id', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[0] = _withNw003ProofOverrides(
        verdicts[0],
        const <String, Object?>{'rowId': 'RA-007'},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: nw003PartitionReaddHealProof.rowId must be NW-003'),
      );
    });

    test('NW-003 rejects missing Alice-to-Bob partition', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[1] = _withNw003ProofOverrides(
        verdicts[1],
        const <String, Object?>{'alicePartitionedFromBob': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('alicePartitionedFromBob must be true'));
    });

    test('NW-003 rejects missing Alice-to-Charlie partition', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[2] = _withNw003ProofOverrides(
        verdicts[2],
        const <String, Object?>{'alicePartitionedFromCharlie': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alicePartitionedFromCharlie must be true'),
      );
    });

    test('NW-003 rejects fake-only partition coverage', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[0] = _withNw003ProofOverrides(
        verdicts[0],
        const <String, Object?>{
          'partitionProofSource': 'fake_network',
          'fakeNetworkOnly': true,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('partitionProofSource'));
      expect(rejected.detail, contains('fakeNetworkOnly must be false'));
    });

    test('NW-003 rejects Bob missing removed-window history', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[1] = _withNw003ProofOverrides(
        {
          ...verdicts[1],
          'receivedMessages': const <Map<String, Object?>>[],
          'persistedMessageCounts': const <String, int>{},
        },
        const <String, Object?>{'bobReceivedRemovedWindowAfterHeal': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bobReceivedRemovedWindowAfterHeal'));
      expect(rejected.detail, contains('bob: missing received proof keys'));
    });

    test('NW-003 rejects Charlie receiving removed-window history', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      final charlieReceived =
          List<Map<String, Object?>>.from(
            verdicts[2]['receivedMessages'] as List,
          )..add(
            _received(
              'aliceRemovedWindow',
              'nw003-removed-window',
              'NW-003 removed-window',
              'alice-peer',
              groupId: 'private-partition-readd-heal-group',
              keyEpoch: 2,
              timestamp: '2026-05-13T11:02:00.000Z',
              usedOfflineDrain: true,
            ),
          );
      verdicts[2] = _withNw003ProofOverrides(
        {
          ...verdicts[2],
          'receivedMessages': charlieReceived,
          'persistedMessageCounts': const <String, int>{
            'aliceRemovedWindow': 1,
            'alicePostHeal': 1,
            'bobPostHeal': 1,
          },
        },
        const <String, Object?>{'charlieDidNotReceiveRemovedWindow': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('charlieDidNotReceiveRemovedWindow'));
      expect(rejected.detail, contains('must not receive aliceRemovedWindow'));
    });

    test('NW-003 rejects missing final membership and key convergence', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[0] = _withNw003ProofOverrides(
        {
          ...verdicts[0],
          'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'keyEpoch': 1,
        },
        const <String, Object?>{
          'finalMembershipConvergedForAliceBobCharlie': false,
          'finalKeyEpochConvergedForAliceBobCharlie': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('finalMembershipConverged'));
      expect(rejected.detail, contains('finalKeyEpochConverged'));
      expect(rejected.detail, contains('incomplete membership convergence'));
    });

    test('NW-003 rejects missing post-heal live delivery from one role', () {
      final verdicts = _validPrivatePartitionReaddHealVerdicts();
      verdicts[2] = _withNw003ProofOverrides(
        {...verdicts[2], 'sentMessages': const <Map<String, Object?>>[]},
        const <String, Object?>{'postHealCharlieToAliceBobDelivery': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partition_readd_heal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('postHealCharlieToAliceBobDelivery'));
      expect(
        rejected.detail,
        contains('charlie: sent charliePostHeal count=0'),
      );
    });

    test('NW-004 accepts relay reconnect group recovery proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateRelayReconnectGroupRecoveryVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_relay_reconnect_group_recovery verdicts valid'),
      );
    });

    test('NW-004 rejects missing relay drop and reconnect proof', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      verdicts[0] = _withNw004ProofOverrides(
        verdicts[0],
        const <String, Object?>{
          'relayDropForced': false,
          'relayReconnectCalled': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('relayDropForced must be true'));
      expect(rejected.detail, contains('relayReconnectCalled must be true'));
    });

    test('NW-004 rejects recovery without rejoin or preserved topics', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      verdicts[1] = _withNw004ProofOverrides(
        verdicts[1],
        const <String, Object?>{
          'groupTopicsRejoinedAfterReconnect': false,
          'topicsPreservedInPlace': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('requires group topic rejoin'));
    });

    test('NW-004 rejects missing replay drain for dropped publish', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        verdicts[1]['receivedMessages'] as List,
      );
      bobReceived[0] = {...bobReceived[0], 'usedOfflineDrain': false};
      verdicts[1] = _withNw004ProofOverrides(
        {...verdicts[1], 'receivedMessages': bobReceived},
        const <String, Object?>{
          'groupReplayDrainCompleted': false,
          'missedDuringDropRecoveredByReplay': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('groupReplayDrainCompleted'));
      expect(rejected.detail, contains('recovered by offline drain'));
    });

    test('NW-004 rejects non-iOS-26.2 app peer proof', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      verdicts[2] = _withNw004ProofOverrides(
        verdicts[2],
        const <String, Object?>{'appPeerPlatform': 'ios_26_4_core_simulator'},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('appPeerPlatform'));
    });

    test('NW-004 rejects ack missing when needsGroupRecovery was observed', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      verdicts[1] =
          _withNw004ProofOverrides(verdicts[1], const <String, Object?>{
            'needsGroupRecoveryObserved': true,
            'recoveryAckSentAfterRejoinAndDrain': false,
          });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('recoveryAckSentAfterRejoinAndDrain'));
    });

    test('NW-004 rejects duplicate delivery and convergence drift', () {
      final verdicts = _validPrivateRelayReconnectGroupRecoveryVerdicts();
      verdicts[0] = _withNw004ProofOverrides(
        {
          ...verdicts[0],
          'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'keyEpoch': 1,
        },
        const <String, Object?>{
          'duplicateVisibleMessageCount': 1,
          'finalMembershipConvergedForAliceBobCharlie': false,
          'finalKeyEpochConvergedForAliceBobCharlie': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_reconnect_group_recovery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('duplicateVisibleMessageCount'));
      expect(rejected.detail, contains('finalMembershipConverged'));
      expect(rejected.detail, contains('finalKeyEpochConverged'));
    });

    test('NW-006 accepts peer disconnect not removal proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivatePeerDisconnectNotRemovalVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_peer_disconnect_not_removal verdicts valid'),
      );
    });

    test('NW-006 rejects missing row id and wrong app-peer source', () {
      final verdicts = _validPrivatePeerDisconnectNotRemovalVerdicts();
      verdicts[0] =
          _withNw006ProofOverrides(verdicts[0], const <String, Object?>{
            'rowId': 'NW-004',
            'appPeerPlatform': 'ios_26_4_core_simulator',
            'disconnectProofSource': 'fake_network',
          });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('rowId must be NW-006'));
      expect(rejected.detail, contains('appPeerPlatform'));
      expect(rejected.detail, contains('disconnectProofSource'));
    });

    test('NW-006 rejects missing disconnect and durable recipient proof', () {
      final verdicts = _validPrivatePeerDisconnectNotRemovalVerdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        verdicts[0]['sentMessages'] as List,
      );
      aliceSent[0] = {
        ...aliceSent[0],
        'recipientPeerIds': const <String>['charlie-peer'],
      };
      verdicts[0] = _withNw006ProofOverrides(
        {...verdicts[0], 'sentMessages': aliceSent},
        const <String, Object?>{
          'bobDisconnected': false,
          'durableRecipientIncludedDisconnectedBob': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bobDisconnected'));
      expect(
        rejected.detail,
        contains('durableRecipientIncludedDisconnectedBob'),
      );
      expect(rejected.detail, contains('disconnected Bob must remain'));
    });

    test('NW-006 rejects removal side effects', () {
      final verdicts = _validPrivatePeerDisconnectNotRemovalVerdicts();
      verdicts[1] = _withNw006ProofOverrides(
        verdicts[1],
        const <String, Object?>{
          'bobRemovedSignalCount': 1,
          'membershipMutationCount': 1,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bobRemovedSignalCount'));
      expect(rejected.detail, contains('membershipMutationCount'));
    });

    test('NW-006 rejects missing replay and post-reconnect live proof', () {
      final verdicts = _validPrivatePeerDisconnectNotRemovalVerdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        verdicts[1]['receivedMessages'] as List,
      );
      bobReceived[0] = {...bobReceived[0], 'usedOfflineDrain': false};
      bobReceived[1] = {...bobReceived[1], 'usedOfflineDrain': true};
      verdicts[1] = _withNw006ProofOverrides(
        {...verdicts[1], 'receivedMessages': bobReceived},
        const <String, Object?>{
          'missedDuringDisconnectRecoveredByReplay': false,
          'postReconnectLiveDeliveryToBob': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missedDuringDisconnectRecoveredByReplay'),
      );
      expect(rejected.detail, contains('postReconnectLiveDeliveryToBob'));
      expect(rejected.detail, contains('must be recovered by offline drain'));
      expect(rejected.detail, contains('must be live after reconnect'));
    });

    test('NW-006 rejects duplicate delivery and convergence drift', () {
      final verdicts = _validPrivatePeerDisconnectNotRemovalVerdicts();
      verdicts[2] = _withNw006ProofOverrides(
        {
          ...verdicts[2],
          'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'keyEpoch': 1,
        },
        const <String, Object?>{
          'duplicateVisibleMessageCount': 1,
          'finalMembershipConvergedForAliceBobCharlie': false,
          'finalKeyEpochConvergedForAliceBobCharlie': false,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_peer_disconnect_not_removal',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('duplicateVisibleMessageCount'));
      expect(rejected.detail, contains('finalMembershipConverged'));
      expect(rejected.detail, contains('finalKeyEpochConverged'));
    });

    test('NW-010 accepts background resume group delivery proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_background_resume_group_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateBackgroundResumeGroupDeliveryVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_background_resume_group_delivery verdicts valid'),
      );
    });

    test(
      'NW-010 rejects missing row id and non-app-peer background source',
      () {
        final verdicts = _validPrivateBackgroundResumeGroupDeliveryVerdicts();
        verdicts[1] =
            _withNw010ProofOverrides(verdicts[1], const <String, Object?>{
              'rowId': 'NW-006',
              'appPeerPlatform': 'ios_26_4_core_simulator',
              'backgroundProofSource': 'process_restart',
            });

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_background_resume_group_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('rowId must be NW-010'));
        expect(rejected.detail, contains('appPeerPlatform'));
        expect(rejected.detail, contains('backgroundProofSource'));
      },
    );

    test(
      'NW-010 rejects missing background and foreground lifecycle proof',
      () {
        final verdicts = _validPrivateBackgroundResumeGroupDeliveryVerdicts();
        verdicts[1] =
            _withNw010ProofOverrides(verdicts[1], const <String, Object?>{
              'bobBackgroundedDuringAliceActivity': false,
              'bobForegroundedAfterMembershipEdit': false,
              'groupTopicsRejoinedAfterForeground': false,
              'groupReplayDrainCompleted': false,
              'recoveryAckSentAfterRejoinAndDrain': false,
            });

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_background_resume_group_delivery',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: verdicts,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('bobBackgroundedDuringAliceActivity'));
        expect(rejected.detail, contains('bobForegroundedAfterMembershipEdit'));
        expect(rejected.detail, contains('groupTopicsRejoinedAfterForeground'));
        expect(rejected.detail, contains('groupReplayDrainCompleted'));
        expect(rejected.detail, contains('recoveryAckSentAfterRejoinAndDrain'));
      },
    );

    test('NW-010 rejects unordered drain and duplicate replay', () {
      final verdicts = _validPrivateBackgroundResumeGroupDeliveryVerdicts();
      final bobReceived = List<Map<String, Object?>>.from(
        verdicts[1]['receivedMessages'] as List,
      );
      bobReceived[0] = {...bobReceived[0], 'usedOfflineDrain': false};
      verdicts[1] = _withNw010ProofOverrides(
        {...verdicts[1], 'receivedMessages': bobReceived},
        const <String, Object?>{
          'orderedDrainIncludesContentAndMembership': false,
          'orderedDrainKeys': <String>[
            'aliceDuringBackgroundAfterEdit',
            'memberRemovedCharlie',
            'aliceDuringBackgroundBeforeEdit',
          ],
          'duplicateVisibleMessageCount': 1,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_background_resume_group_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('orderedDrainIncludesContentAndMembership'),
      );
      expect(rejected.detail, contains('orderedDrainKeys'));
      expect(rejected.detail, contains('duplicateVisibleMessageCount'));
      expect(rejected.detail, contains('drain/live classification mismatch'));
    });

    test('NW-010 rejects missing entitlement filtering and convergence', () {
      final verdicts = _validPrivateBackgroundResumeGroupDeliveryVerdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        verdicts[0]['sentMessages'] as List,
      );
      aliceSent[1] = {
        ...aliceSent[1],
        'recipientPeerIds': const <String>['charlie-peer'],
      };
      final charlieReceived =
          List<Map<String, Object?>>.from(
            verdicts[2]['receivedMessages'] as List,
          )..add(
            _received(
              'aliceDuringBackgroundAfterEdit',
              'nw010-after-edit',
              'NW-010 missed after membership edit',
              'alice-peer',
              groupId: 'private-background-resume-group',
              keyEpoch: 2,
              usedOfflineDrain: false,
            ),
          );
      verdicts[0] = _withNw010ProofOverrides(
        {...verdicts[0], 'sentMessages': aliceSent},
        const <String, Object?>{
          'entitlementFilteringPreserved': false,
          'finalMembershipConvergedForAliceBob': false,
          'finalKeyEpochConvergedForAliceBob': false,
          'charlieRemovedBeforeSecondBackgroundMessage': false,
        },
      );
      verdicts[2] = {...verdicts[2], 'receivedMessages': charlieReceived};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_background_resume_group_delivery',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('entitlementFilteringPreserved'));
      expect(
        rejected.detail,
        contains('second background send must include Bob'),
      );
      expect(rejected.detail, contains('exclude removed Charlie'));
      expect(rejected.detail, contains('removed member must not receive'));
      expect(rejected.detail, contains('finalMembershipConvergedForAliceBob'));
      expect(rejected.detail, contains('finalKeyEpochConvergedForAliceBob'));
    });

    test('NW-012 accepts long offline epoch churn proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_long_offline_epoch_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateLongOfflineEpochChurnVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_long_offline_epoch_churn verdicts valid'),
      );
    });

    test('NW-012 rejects non-iOS proof source and wrong row id', () {
      final verdicts = _validPrivateLongOfflineEpochChurnVerdicts();
      verdicts[2] =
          _withNw012ProofOverrides(verdicts[2], const <String, Object?>{
            'rowId': 'NW-010',
            'appPeerPlatform': 'ios_26_4_core_simulator',
            'offlineProofSource': 'host_fake_network',
          });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_long_offline_epoch_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('rowId must be NW-012'));
      expect(rejected.detail, contains('appPeerPlatform'));
      expect(rejected.detail, contains('offlineProofSource'));
    });

    test('NW-012 rejects removed-window leakage and duplicate replay', () {
      final verdicts = _validPrivateLongOfflineEpochChurnVerdicts();
      final charlieReceived =
          List<Map<String, Object?>>.from(
            verdicts[2]['receivedMessages'] as List,
          )..add(
            _received(
              'aliceRemovedWindow',
              'nw012-removed-window',
              'NW-012 removed-window',
              'alice-peer',
              groupId: 'private-long-offline-epoch-churn-group',
              keyEpoch: 2,
              usedOfflineDrain: true,
            ),
          );
      verdicts[2] = _withNw012ProofOverrides(
        {...verdicts[2], 'receivedMessages': charlieReceived},
        const <String, Object?>{
          'charlieReceivedOnlyFinalActiveInterval': false,
          'duplicateVisibleMessageCount': 1,
          'removedWindowPlaintextCount': 1,
          'staleEpochPlaintextCount': 1,
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_long_offline_epoch_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('unexpected received proof keys'));
      expect(
        rejected.detail,
        contains('charlieReceivedOnlyFinalActiveInterval'),
      );
      expect(rejected.detail, contains('duplicateVisibleMessageCount'));
      expect(rejected.detail, contains('removedWindowPlaintextCount'));
      expect(rejected.detail, contains('staleEpochPlaintextCount'));
    });

    test('NW-012 rejects weak final convergence and unordered drain', () {
      final verdicts = _validPrivateLongOfflineEpochChurnVerdicts();
      final aliceSent = List<Map<String, Object?>>.from(
        verdicts[0]['sentMessages'] as List,
      );
      aliceSent[0] = {
        ...aliceSent[0],
        'recipientPeerIds': const <String>['charlie-peer'],
      };
      verdicts[0] = _withNw012ProofOverrides(
        {...verdicts[0], 'sentMessages': aliceSent},
        const <String, Object?>{
          'entitlementFilteringPreserved': false,
          'finalMembershipConverged': false,
          'finalKeyEpochConverged': false,
          'finalEpoch': 2,
          'orderedDrainKeys': <String>[
            'aliceFinalActiveOne',
            'memberRemovedCharlie',
            'bobFinalActiveTwo',
          ],
        },
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_long_offline_epoch_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: verdicts,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('entitlementFilteringPreserved'));
      expect(rejected.detail, contains('removed-window send must include Bob'));
      expect(
        rejected.detail,
        contains('removed-window send must exclude Charlie'),
      );
      expect(rejected.detail, contains('finalMembershipConverged'));
      expect(rejected.detail, contains('finalKeyEpochConverged'));
      expect(rejected.detail, contains('finalEpoch must be at least 4'));
      expect(rejected.detail, contains('orderedDrainKeys'));
    });

    test('accepts private A/B/C create reusable proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateAbcCreateVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_abc_create verdicts valid'));
    });

    test('rejects private A/B/C create without ML-001 invite path proof', () {
      final missingProof = _validPrivateAbcCreateVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ml001CreateInviteProof');

      final rejectedMissing = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );
      expect(rejectedMissing.ok, isFalse);
      expect(
        rejectedMissing.detail,
        contains('bob: missing ML-001 create/invite proof fields'),
      );

      final wrongPath = _validPrivateAbcCreateVerdicts();
      wrongPath[2] = {
        ...wrongPath[2],
        'ml001CreateInviteProof': {
          ...wrongPath[2]['ml001CreateInviteProof'] as Map<String, Object?>,
          'invitePath': 'fixture_import',
        },
      };

      final rejectedPath = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongPath,
      );
      expect(rejectedPath.ok, isFalse);
      expect(rejectedPath.detail, contains('supported_pending_invite'));
    });

    test('rejects private proof topic and key epoch divergence', () {
      final topicMismatch = _validPrivateAbcCreateVerdicts();
      topicMismatch[1] = {
        ...topicMismatch[1],
        'topicName': '/mknoon/group/other-topic',
      };

      final rejectedTopic = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: topicMismatch,
      );
      expect(rejectedTopic.ok, isFalse);
      expect(rejectedTopic.detail, contains('disagree on topicName'));

      final epochMismatch = _validPrivateAbcCreateVerdicts();
      epochMismatch[2] = {...epochMismatch[2], 'keyEpoch': 2};

      final rejectedEpoch = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: epochMismatch,
      );
      expect(rejectedEpoch.ok, isFalse);
      expect(
        rejectedEpoch.detail,
        contains('keyEpoch must be exactly 1 for KE-001'),
      );

      final wrongInitialEpoch = _validPrivateAbcCreateVerdicts();
      for (var i = 0; i < wrongInitialEpoch.length; i++) {
        wrongInitialEpoch[i] = {
          ...wrongInitialEpoch[i],
          'keyEpoch': 2,
          'sentMessages': [
            for (final sent
                in wrongInitialEpoch[i]['sentMessages']
                    as List<Map<String, Object?>>)
              {...sent, 'keyEpoch': 2},
          ],
          'receivedMessages': [
            for (final received
                in wrongInitialEpoch[i]['receivedMessages']
                    as List<Map<String, Object?>>)
              {...received, 'keyEpoch': 2},
          ],
        };
      }

      final rejectedWrongInitialEpoch = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_abc_create',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongInitialEpoch,
      );
      expect(rejectedWrongInitialEpoch.ok, isFalse);
      expect(
        rejectedWrongInitialEpoch.detail,
        contains('keyEpoch must be exactly 1 for KE-001'),
      );
    });

    test('accepts private online-add ML-002 live proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateOnlineAddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_online_add verdicts valid'));
    });

    test('rejects private online-add without ML-002 proof fields', () {
      final missingProof = _validPrivateOnlineAddVerdicts();
      missingProof[3] = Map<String, dynamic>.from(missingProof[3])
        ..remove('ml002OnlineAddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: missing ML-002 online-add proof fields'),
      );
    });

    test(
      'rejects ML-002 private online-add without Bob post-join proof to D',
      () {
        final missingBob = _validPrivateOnlineAddVerdicts();
        missingBob[1] = {
          ...missingBob[1],
          'sentMessages': const <Map<String, Object?>>[],
        };
        missingBob[3] = {
          ...missingBob[3],
          'receivedMessages': <Map<String, Object?>>[
            _received(
              'aliceAfterDanaAdd',
              'poa-a1',
              'private alice after dana',
              'alice-peer',
              keyEpoch: 2,
              liveOnly: true,
              usedOfflineDrain: false,
            ),
          ],
          'persistedMessageCounts': const <String, int>{'aliceAfterDanaAdd': 1},
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_online_add',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingBob,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('bob: sent bobAfterDanaAdd count=0'));
        expect(
          rejected.detail,
          contains('dana: missing received proof keys bobAfterDanaAdd'),
        );
      },
    );

    test(
      'rejects ML-002 private online-add D receipt that used offline drain',
      () {
        final drained = _validPrivateOnlineAddVerdicts();
        drained[3] = {
          ...drained[3],
          'receivedMessages': <Map<String, Object?>>[
            _received(
              'aliceAfterDanaAdd',
              'poa-a1',
              'private alice after dana',
              'alice-peer',
              keyEpoch: 2,
              liveOnly: true,
              usedOfflineDrain: false,
            ),
            _received(
              'bobAfterDanaAdd',
              'poa-b1',
              'private bob after dana',
              'bob-peer',
              keyEpoch: 2,
              liveOnly: true,
              usedOfflineDrain: true,
            ),
          ],
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_online_add',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: drained,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'dana: received bobAfterDanaAdd usedOfflineDrain must be false',
          ),
        );
      },
    );

    test('accepts private offline-add ML-003 replay proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateOfflineAddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_offline_add verdicts valid'));
    });

    test(
      'rejects private offline-add hash divergence as non-converged config',
      () {
        final divergent = _validPrivateOfflineAddVerdicts();
        divergent[3] = <String, dynamic>{
          ...divergent[3],
          'groupConfigStateHash': 'private-offline-add-dana-diverged-state',
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_offline_add',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: divergent,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('role verdicts disagree on groupConfigStateHash'),
        );
      },
    );

    test('rejects private offline-add without ML-003 proof fields', () {
      final missingProof = _validPrivateOfflineAddVerdicts();
      missingProof[3] = Map<String, dynamic>.from(missingProof[3])
        ..remove('ml003OfflineAddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: missing ML-003 offline-add proof fields'),
      );
    });

    test('rejects private offline-add fixture-only invite path', () {
      final fixtureOnly = _validPrivateOfflineAddVerdicts();
      fixtureOnly[3] = {
        ...fixtureOnly[3],
        'ml003OfflineAddProof': {
          ...fixtureOnly[3]['ml003OfflineAddProof'] as Map<String, Object?>,
          'invitePath': 'fixture_import',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: fixtureOnly,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('supported_pending_invite'));
    });

    test('rejects ML-003 private offline-add without Bob replay to D', () {
      final missingBob = _validPrivateOfflineAddVerdicts();
      missingBob[1] = {
        ...missingBob[1],
        'sentMessages': const <Map<String, Object?>>[],
      };
      missingBob[3] = {
        ...missingBob[3],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterDanaOfflineAdd',
            'poff-a1',
            'private alice offline replay',
            'alice-peer',
            keyEpoch: 2,
            liveOnly: false,
            usedOfflineDrain: true,
          ),
          _received(
            'aliceLiveAfterDanaDrain',
            'poff-live1',
            'private alice live after drain',
            'alice-peer',
            keyEpoch: 2,
            liveOnly: true,
            usedOfflineDrain: false,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterDanaOfflineAdd': 1,
          'aliceLiveAfterDanaDrain': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_add',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingBob,
      );

      expect(
        rejected.detail,
        contains('bob: sent bobAfterDanaOfflineAdd count=0'),
      );
      expect(
        rejected.detail,
        contains('dana: missing received proof keys bobAfterDanaOfflineAdd'),
      );
    });

    test('accepts valid GE-001 A/B/C all-send smoke verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe001Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge001 verdicts valid'));
    });

    test('rejects GE-001 duplicate receiver persistence', () {
      final duplicate = _validGe001Verdicts();
      duplicate[1] = {
        ...duplicate[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe001Initial',
            'ge001-a1',
            'hello ge001 from alice',
            'alice-peer',
          ),
          _received(
            'aliceGe001Initial',
            'ge001-a1-dup',
            'hello ge001 from alice',
            'alice-peer',
          ),
          _received(
            'charlieGe001Initial',
            'ge001-c1',
            'hello ge001 from charlie',
            'charlie-peer',
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicate,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: received aliceGe001Initial count=2; requires exactly one receiver persistence',
        ),
      );
    });

    test('accepts valid GE-002 removal continuity verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe002Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge002 verdicts valid'));
    });

    test('rejects GE-002 Charlie post-removal leakage', () {
      final leaked = _validGe002Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe002PostRemoval01',
            'ge002-a-01',
            'ge002 alice post removal 01',
            'alice-peer',
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe002PostRemoval01': 1,
        },
        'ge002RemovalContinuityProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ge002RemovalContinuityProof'] as Map,
          ),
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge002RemovalContinuityProof.postRemovalPlaintextCount must be 0',
        ),
      );
    });

    test('accepts valid GE-003 remaining pair verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe003Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge003 verdicts valid'));
    });

    test('rejects GE-003 Charlie post-removal leakage', () {
      final leaked = _validGe003Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'bobGe003PostRemoval01',
            'ge003-b-01',
            'ge003 bob post removal 01',
            'bob-peer',
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'bobGe003PostRemoval01': 1,
        },
        'ge003RemainingPairProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ge003RemainingPairProof'] as Map,
          ),
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge003RemainingPairProof.postRemovalPlaintextCount must be 0',
        ),
      );
    });

    test('accepts valid GE-004 re-add exchange verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe004Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge004 verdicts valid'));
    });

    test('rejects GE-004 missing Charlie post-readd receipt', () {
      final missing = _validGe004Verdicts();
      final aliceProof = Map<String, Object?>.from(
        missing[0]['ge004ReaddExchangeProof'] as Map,
      );
      missing[0] = {
        ...missing[0],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'bobGe004PostReadd',
            'ge004-b1',
            'ge004 bob after readd',
            'bob-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'bobGe004PostReadd': 1},
        'ge004ReaddExchangeProof': <String, Object?>{
          ...aliceProof,
          'postReaddReceivedCount': 1,
          'postReaddReceivedKeys': const <String>['bobGe004PostReadd'],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing received proof keys charlieGe004PostReadd'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: ge004ReaddExchangeProof.postReaddReceivedCount must be 2',
        ),
      );
    });

    test('accepts valid GE-005 remove/re-add loop verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe005Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge005 verdicts valid'));
    });

    test('rejects GE-005 removed-window Charlie leakage', () {
      final leaked = _validGe005Verdicts();
      final charlieProof = Map<String, Object?>.from(
        leaked[2]['ge005RemoveReaddLoopProof'] as Map,
      );
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          ...((leaked[2]['receivedMessages'] as List)
              .cast<Map<String, Object?>>()),
          _received(
            'aliceGe005Removed01',
            'ge005-removed-01',
            'ge005 removed window 01',
            'alice-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': <String, int>{
          ...((leaked[2]['persistedMessageCounts'] as Map).cast<String, int>()),
          'aliceGe005Removed01': 1,
        },
        'ge005RemoveReaddLoopProof': <String, Object?>{
          ...charlieProof,
          'removedWindowPlaintextCount': 1,
          'removedWindowReceivedKeys': const <String>['aliceGe005Removed01'],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge005RemoveReaddLoopProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test('accepts valid GE-006 offline re-add catch-up verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe006Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge006 verdicts valid'));
    });

    test('rejects GE-006 removed-window Charlie leakage', () {
      final leaked = _validGe006Verdicts();
      final charlieProof = Map<String, Object?>.from(
        leaked[2]['ge006OfflineReaddProof'] as Map,
      );
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          ...((leaked[2]['receivedMessages'] as List)
              .cast<Map<String, Object?>>()),
          _received(
            'aliceGe006RemovedWindow',
            'ge006-removed-window',
            'ge006 removed window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': <String, int>{
          ...((leaked[2]['persistedMessageCounts'] as Map).cast<String, int>()),
          'aliceGe006RemovedWindow': 1,
        },
        'ge006OfflineReaddProof': <String, Object?>{
          ...charlieProof,
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge006OfflineReaddProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test('rejects GE-006 missing post-readd Charlie catch-up', () {
      final missing = _validGe006Verdicts();
      final charlieProof = Map<String, Object?>.from(
        missing[2]['ge006OfflineReaddProof'] as Map,
      );
      missing[2] = {
        ...missing[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe006PostReadd',
            'ge006-alice-post-readd',
            'ge006 alice post readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'aliceGe006PostReadd': 1},
        'ge006OfflineReaddProof': <String, Object?>{
          ...charlieProof,
          'postReaddReceivedCount': 1,
          'postReaddReceivedKeys': const <String>['aliceGe006PostReadd'],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing received proof keys bobGe006PostReadd'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge006OfflineReaddProof.postReaddReceivedCount must be 2',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge006OfflineReaddProof.postReaddReceivedKeys mismatch, missing bobGe006PostReadd',
        ),
      );
    });

    test('accepts valid GE-007 offline observer catch-up verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe007Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge007 verdicts valid'));
    });

    test('rejects GE-007 missing Bob removed-window catch-up', () {
      final missing = _validGe007Verdicts();
      final bobProof = Map<String, Object?>.from(
        missing[1]['ge007OfflineObserverProof'] as Map,
      );
      missing[1] = {
        ...missing[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe007PostReadd',
            'ge007-alice-post-readd',
            'ge007 alice post readd',
            'alice-peer',
          ),
          _received(
            'charlieGe007PostReadd',
            'ge007-charlie-post-readd',
            'ge007 charlie post readd',
            'charlie-peer',
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe007PostReadd': 1,
          'charlieGe007PostReadd': 1,
        },
        'ge007OfflineObserverProof': <String, Object?>{
          ...bobProof,
          'receivedRemovedWindowMessage': false,
          'entitledReceivedCount': 2,
          'entitledReceivedKeys': const <String>[
            'aliceGe007PostReadd',
            'charlieGe007PostReadd',
          ],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceGe007RemovedWindow'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge007OfflineObserverProof.receivedRemovedWindowMessage must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge007OfflineObserverProof.entitledReceivedCount must be 3',
        ),
      );
    });

    test('rejects GE-007 missing Bob post-readd catch-up', () {
      final missing = _validGe007Verdicts();
      final bobProof = Map<String, Object?>.from(
        missing[1]['ge007OfflineObserverProof'] as Map,
      );
      missing[1] = {
        ...missing[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe007RemovedWindow',
            'ge007-removed-window',
            'ge007 removed window',
            'alice-peer',
          ),
          _received(
            'aliceGe007PostReadd',
            'ge007-alice-post-readd',
            'ge007 alice post readd',
            'alice-peer',
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe007RemovedWindow': 1,
          'aliceGe007PostReadd': 1,
        },
        'ge007OfflineObserverProof': <String, Object?>{
          ...bobProof,
          'receivedCharliePostReaddMessage': false,
          'entitledReceivedCount': 2,
          'entitledReceivedKeys': const <String>[
            'aliceGe007RemovedWindow',
            'aliceGe007PostReadd',
          ],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys charlieGe007PostReadd'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge007OfflineObserverProof.receivedCharliePostReaddMessage must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge007OfflineObserverProof.entitledReceivedKeys mismatch, missing charlieGe007PostReadd',
        ),
      );
    });

    test('accepts valid GE-008 send storm remove/re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe008Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge008 verdicts valid'));
    });

    test('rejects GE-008 Charlie removed-window leak', () {
      final leaked = _validGe008Verdicts();
      final charlieProof = Map<String, Object?>.from(
        leaked[2]['ge008SendStormProof'] as Map,
      );
      final receivedMessages = <Map<String, Object?>>[
        ...((leaked[2]['receivedMessages'] as List)
            .cast<Map<String, Object?>>()),
        _received(
          'aliceGe008Removed0',
          'ge008-aliceGe008Removed0',
          'ge008 aliceGe008Removed0',
          'alice-peer',
        ),
      ];
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': receivedMessages,
        'persistedMessageCounts': <String, int>{
          for (final entry in receivedMessages) entry['key'] as String: 1,
        },
        'ge008SendStormProof': <String, Object?>{
          ...charlieProof,
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys aliceGe008Removed0'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge008SendStormProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test('rejects GE-008 missing post-readd storm message', () {
      final missing = _validGe008Verdicts();
      final aliceProof = Map<String, Object?>.from(
        missing[0]['ge008SendStormProof'] as Map,
      );
      final receivedMessages =
          ((missing[0]['receivedMessages'] as List)
                  .cast<Map<String, Object?>>())
              .where((entry) => entry['key'] != 'charlieGe008Post1')
              .toList(growable: false);
      missing[0] = {
        ...missing[0],
        'receivedMessages': receivedMessages,
        'persistedMessageCounts': <String, int>{
          for (final entry in receivedMessages) entry['key'] as String: 1,
        },
        'ge008SendStormProof': <String, Object?>{
          ...aliceProof,
          'receivedCharliePostReaddMessages': false,
          'postReaddReceivedCount': 3,
          'receivedPostReaddKeys': const <String>[
            'bobGe008Post0',
            'bobGe008Post1',
            'charlieGe008Post0',
          ],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing received proof keys charlieGe008Post1'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: ge008SendStormProof.receivedCharliePostReaddMessages must be true',
        ),
      );
      expect(
        rejected.detail,
        contains('alice: ge008SendStormProof.postReaddReceivedCount must be 4'),
      );
    });

    test('accepts valid GE-009 partition-heal verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe009Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge009 verdicts valid'));
    });

    test('rejects GE-009 missing Charlie replay drain', () {
      final missing = _validGe009Verdicts();
      final charlieProof = Map<String, Object?>.from(
        missing[2]['ge009PartitionHealProof'] as Map,
      );
      final receivedMessages =
          ((missing[2]['receivedMessages'] as List)
                  .cast<Map<String, Object?>>())
              .where((entry) => entry['key'] != 'bobGe009PostReadd')
              .toList(growable: false);
      missing[2] = {
        ...missing[2],
        'receivedMessages': receivedMessages,
        'persistedMessageCounts': <String, int>{
          for (final entry in receivedMessages) entry['key'] as String: 1,
        },
        'ge009PartitionHealProof': <String, Object?>{
          ...charlieProof,
          'drainedReplayAfterHeal': false,
          'receivedAliceBobReplayAfterHeal': false,
          'postReaddReplayKeys': const <String>['aliceGe009PostReadd'],
          'finalTimelineConverged': false,
          'finalMessageCount': 5,
          'finalTimelineKeys': const <String>[
            'aliceGe009BeforePartition',
            'bobGe009BeforePartition',
            'charlieGe009BeforePartition',
            'aliceGe009PostReadd',
            'charlieGe009AfterHeal',
          ],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missing,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing received proof keys bobGe009PostReadd'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge009PartitionHealProof.drainedReplayAfterHeal must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge009PartitionHealProof.finalMessageCount must be 6',
        ),
      );
    });

    test('rejects GE-009 divergent final timeline and removed leak', () {
      final invalid = _validGe009Verdicts();
      final charlieProof = Map<String, Object?>.from(
        invalid[2]['ge009PartitionHealProof'] as Map,
      );
      final receivedMessages = <Map<String, Object?>>[
        ...((invalid[2]['receivedMessages'] as List)
            .cast<Map<String, Object?>>()),
        _received(
          'aliceGe009RemovedLeak',
          'ge009-removed-leak',
          'ge009 removed leak',
          'alice-peer',
        ),
      ];
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': receivedMessages,
        'persistedMessageCounts': <String, int>{
          for (final entry in receivedMessages) entry['key'] as String: 1,
        },
        'ge009PartitionHealProof': <String, Object?>{
          ...charlieProof,
          'removedWindowPlaintextCount': 1,
          'finalTimelineConverged': false,
          'finalTimelineKeys': const <String>[
            'aliceGe009BeforePartition',
            'bobGe009BeforePartition',
            'charlieGe009BeforePartition',
            'aliceGe009PostReadd',
            'bobGe009PostReadd',
            'aliceGe009RemovedLeak',
            'charlieGe009AfterHeal',
          ],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceGe009RemovedLeak',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge009PartitionHealProof.removedWindowPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge009PartitionHealProof.finalTimelineConverged must be true',
        ),
      );
    });

    test('accepts valid GE-010 zero-live-peer fallback verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe010Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge010 verdicts valid'));
    });

    test('accepts valid GO-001 zero-peer sender-status verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'go001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGo001Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('go001 verdicts valid'));
    });

    test('rejects GO-001 sender without durable zero-peer status proof', () {
      final invalid = _validGo001Verdicts();
      final proof = Map<String, Object?>.from(
        invalid[0]['ge010ZeroLivePeersInboxFallbackProof'] as Map,
      );
      invalid[0] = {
        ...invalid[0],
        'ge010ZeroLivePeersInboxFallbackProof': <String, Object?>{
          ...proof,
          'senderStatusSent': false,
          'inboxStored': false,
          'honestSenderFallbackStatus': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'go001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: ge010ZeroLivePeersInboxFallbackProof.honestSenderFallbackStatus must be true',
        ),
      );
    });

    test('accepts valid GO-002 inbox-store failure status verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'go002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGo002Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('go002 verdicts valid'));
    });

    test('rejects GO-002 sender marked reliable before retry', () {
      final invalid = _validGo002Verdicts();
      final proof = Map<String, Object?>.from(
        invalid[0]['go002InboxStoreFailureSenderStatusProof'] as Map,
      );
      invalid[0] = {
        ...invalid[0],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceGo002InboxStoreFailure',
            'messageId': 'go002-inbox-fail',
            'text': 'go002 inbox failure',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'senderDeviceId': 'alice-device',
            'transportPeerId': 'alice-device',
            'keyEpoch': 1,
            'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
            'failedInboxRecipientPeerIds': <String>['bob-peer', 'charlie-peer'],
            'forcedInboxStoreFailure': true,
            'senderStatusBeforeRetry': 'sent',
            'inboxStoredBeforeRetry': true,
            'retryPayloadBeforeRetry': false,
            'retryCount': 1,
            'senderStatusAfterRetry': 'sent',
            'inboxStoredAfterRetry': true,
            'retryPayloadAfterRetry': false,
            'actualDurablePayloadProof': true,
            'topicPeers': 2,
            'actualTopicPeerProof': true,
          },
        ],
        'go002InboxStoreFailureSenderStatusProof': <String, Object?>{
          ...proof,
          'senderStatusPendingBeforeRetry': false,
          'inboxStoredFalseBeforeRetry': false,
          'retryPayloadPresentBeforeRetry': false,
          'notSilentlyReliableBeforeRetry': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'go002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: go002InboxStoreFailureSenderStatusProof.notSilentlyReliableBeforeRetry must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGo002InboxStoreFailure senderStatusBeforeRetry must be pending',
        ),
      );
    });

    test('rejects GE-010 sender without honest zero-peer fallback', () {
      final invalid = _validGe010Verdicts();
      final sent = Map<String, Object?>.from(
        (invalid[0]['sentMessages'] as List).single as Map,
      );
      final proof = Map<String, Object?>.from(
        invalid[0]['ge010ZeroLivePeersInboxFallbackProof'] as Map,
      );
      invalid[0] = {
        ...invalid[0],
        'sentMessages': <Map<String, Object?>>[
          <String, Object?>{...sent, 'outcome': 'success', 'topicPeers': 1},
        ],
        'ge010ZeroLivePeersInboxFallbackProof': <String, Object?>{
          ...proof,
          'zeroLiveTopicPeersAtSend': false,
          'successNoPeers': false,
          'honestSenderFallbackStatus': false,
          'topicPeersAtSend': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGe010ZeroPeerFallback outcome must be successNoPeers',
        ),
      );
      expect(
        rejected.detail,
        contains('alice: sent aliceGe010ZeroPeerFallback topicPeers must be 0'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: ge010ZeroLivePeersInboxFallbackProof.honestSenderFallbackStatus must be true',
        ),
      );
    });

    test('rejects GE-010 receiver without inbox recovery proof', () {
      final invalid = _validGe010Verdicts();
      final bobProof = Map<String, Object?>.from(
        invalid[1]['ge010ZeroLivePeersInboxFallbackProof'] as Map,
      );
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ge010ZeroLivePeersInboxFallbackProof': <String, Object?>{
          ...bobProof,
          'drainedInboxAfterReturn': false,
          'receivedZeroPeerMessage': false,
          'noDuplicatePersistence': false,
          'postDrainPersistedCount': 0,
          'receivedKeys': const <String>[],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceGe010ZeroPeerFallback'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge010ZeroLivePeersInboxFallbackProof.drainedInboxAfterReturn must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge010ZeroLivePeersInboxFallbackProof.postDrainPersistedCount must be 1',
        ),
      );
    });

    test('accepts valid GE-011 partial-live fallback verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe011Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge011 verdicts valid'));
    });

    test('rejects GE-011 sender without partial-live proof', () {
      final invalid = _validGe011Verdicts();
      final sent = Map<String, Object?>.from(
        (invalid[0]['sentMessages'] as List).single as Map,
      );
      final proof = Map<String, Object?>.from(
        invalid[0]['ge011PartialLivePeersInboxFallbackProof'] as Map,
      );
      invalid[0] = {
        ...invalid[0],
        'sentMessages': <Map<String, Object?>>[
          <String, Object?>{
            ...sent,
            'outcome': 'successNoPeers',
            'topicPeers': 0,
          },
        ],
        'ge011PartialLivePeersInboxFallbackProof': <String, Object?>{
          ...proof,
          'partialLiveTopicPeersAtSend': false,
          'honestPartialFallbackStatus': false,
          'topicPeersAtSend': 0,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGe011PartialLiveFallback outcome must be success',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGe011PartialLiveFallback topicPeers must be 1',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: ge011PartialLivePeersInboxFallbackProof.honestPartialFallbackStatus must be true',
        ),
      );
    });

    test('rejects GE-011 live receiver without duplicate dedupe proof', () {
      final invalid = _validGe011Verdicts();
      final bobProof = Map<String, Object?>.from(
        invalid[1]['ge011PartialLivePeersInboxFallbackProof'] as Map,
      );
      invalid[1] = {
        ...invalid[1],
        'persistedMessageCounts': const <String, int>{
          'aliceGe011PartialLiveFallback': 2,
        },
        'ge011PartialLivePeersInboxFallbackProof': <String, Object?>{
          ...bobProof,
          'drainedDuplicateInboxAfterLive': false,
          'noDuplicatePersistence': false,
          'postDrainPersistedCount': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: persisted aliceGe011PartialLiveFallback count=2; requires exactly one',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge011PartialLivePeersInboxFallbackProof.drainedDuplicateInboxAfterLive must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: ge011PartialLivePeersInboxFallbackProof.postDrainPersistedCount must be 1',
        ),
      );
    });

    test('accepts valid GE-012 same-user multi-device verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe012Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge012 verdicts valid'));
    });

    test('rejects GE-012 sibling that does not restore Bob identity', () {
      final invalid = _validGe012Verdicts();
      invalid[2] = {...invalid[2], 'peerId': 'charlie-peer'};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('ge012: bob and charlie roles must share one logical peer id'),
      );
    });

    test('rejects GE-012 sibling mirror as incoming duplicate', () {
      final invalid = _validGe012Verdicts();
      final received = (invalid[2]['receivedMessages'] as List)
          .cast<Map<String, Object?>>();
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          received[0],
          <String, Object?>{
            ...received[1],
            'isIncoming': true,
            'persistedCount': 2,
          },
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: received bobGe012PrimarySend isIncoming=true'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: received bobGe012PrimarySend persistedCount must be exactly one',
        ),
      );
    });

    test('accepts valid GE-013 device revocation verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe013Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge013 verdicts valid'));
    });

    test('rejects GE-013 post-revoke B2 plaintext', () {
      final invalid = _validGe013Verdicts();
      final received = (invalid[0]['receivedMessages'] as List)
          .cast<Map<String, Object?>>();
      invalid[0] = {
        ...invalid[0],
        'receivedMessages': <Map<String, Object?>>[
          ...received,
          _ge013Received(
            _ge013BobSiblingAfterKey,
            'ge013-b2-after',
            'ge013 b2 after revoke',
            'bob-peer',
            isIncoming: true,
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: received post-revoke B2 plaintext'),
      );
    });

    test('rejects GE-013 accepted post-revoke B2 send', () {
      final invalid = _validGe013Verdicts();
      final sent = (invalid[2]['sentMessages'] as List)
          .cast<Map<String, Object?>>();
      invalid[2] = {
        ...invalid[2],
        'sentMessages': <Map<String, Object?>>[
          sent[0],
          <String, Object?>{...sent[1], 'outcome': 'success', 'accepted': true},
        ],
        'ge013DeviceRevocationProof': <String, Object?>{
          ...(invalid[2]['ge013DeviceRevocationProof'] as Map),
          'b2PostRevokeOutcome': 'success',
          'b2PostRevokeAccepted': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: sent bobGe013SiblingAfterRevoke outcome=success'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ge013DeviceRevocationProof.b2PostRevokeAccepted must be false',
        ),
      );
    });

    test('accepts valid GE-014 restart-before-topic-join verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe014Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge014 verdicts valid'));
    });

    test('rejects GE-014 missing persisted invite and key proof', () {
      final invalid = _validGe014Verdicts();
      invalid[2] = {
        ...invalid[2],
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'charliePersistedInviteBeforeRestart': false,
          'charliePersistedKeyBeforeRestart': false,
          'charlieRecoveredInviteAfterRestart': false,
          'charlieRecoveredKeyAfterRestart': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charliePersistedInviteBeforeRestart must be true'),
      );
      expect(
        rejected.detail,
        contains('charliePersistedKeyBeforeRestart must be true'),
      );
      expect(
        rejected.detail,
        contains('charlieRecoveredInviteAfterRestart must be true'),
      );
      expect(
        rejected.detail,
        contains('charlieRecoveredKeyAfterRestart must be true'),
      );
    });

    test('rejects GE-014 Charlie topic join before restart', () {
      final invalid = _validGe014Verdicts();
      invalid[2] = {
        ...invalid[2],
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'charlieNotJoinedTopicBeforeRestart': false,
          'charlieJoinedTopicBeforeRestart': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlieNotJoinedTopicBeforeRestart must be true'),
      );
      expect(
        rejected.detail,
        contains('charlieJoinedTopicBeforeRestart must be false'),
      );
    });

    test('rejects GE-014 missing post-readd retrieval', () {
      final invalid = _validGe014Verdicts();
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'retrievedPostReaddMessages': false,
          'postReaddReceivedKeys': const <String>[],
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('charlie: missing received proof keys'));
      expect(
        rejected.detail,
        contains('retrievedPostReaddMessages must be true'),
      );
      expect(rejected.detail, contains('postReaddReceivedKeys mismatch'));
    });

    test('rejects GE-014 removed-window plaintext on Charlie', () {
      final invalid = _validGe014Verdicts();
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe014RemovedWindow',
            'ge014-a-removed',
            'alice removed-window',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceGe014PostReadd',
            'ge014-a-post',
            'alice post-readd',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'bobGe014PostReadd',
            'ge014-b-post',
            'bob post-readd',
            'bob-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe014RemovedWindow': 1,
          'aliceGe014PostReadd': 1,
          'bobGe014PostReadd': 1,
        },
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceGe014RemovedWindow'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects GE-014 stale epoch or mismatched final membership', () {
      final invalid = _validGe014Verdicts();
      invalid[1] = {
        ...invalid[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[1]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'memberListIncludesCharlie': false,
          'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'finalEpoch': 4,
        },
      };
      invalid[2] = {
        ...invalid[2],
        'keyEpoch': 1,
        'ge014RestartBeforeTopicJoinProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge014RestartBeforeTopicJoinProof'] as Map,
          ),
          'hasStaleEpochAfterRestart': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: incomplete membership convergence, missing charlie-peer',
        ),
      );
      expect(
        rejected.detail,
        contains('memberListIncludesCharlie must be true'),
      );
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterRestart must be false'),
      );
      expect(rejected.detail, contains('finalEpoch must be >= 2'));
      expect(rejected.detail, contains('GE-014 finalEpoch mismatch'));
    });

    test('accepts valid GE-015 admin restart mutation verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe015Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge015 verdicts valid'));
    });

    test('rejects GE-015 missing restart and pending fanout proof', () {
      final invalid = _validGe015Verdicts();
      invalid[0] = {
        ...invalid[0],
        'ge015AdminRestartMutationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[0]['ge015AdminRestartMutationProof'] as Map,
          ),
          'adminRestartedBeforeFanoutComplete': false,
          'pendingFanoutStatusBeforeRestart': 'sent',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('adminRestartedBeforeFanoutComplete must be true'),
      );
      expect(
        rejected.detail,
        contains('pendingFanoutStatusBeforeRestart must be'),
      );
    });

    test('rejects GE-015 dishonest sent before repair', () {
      final invalid = _validGe015Verdicts();
      invalid[0] = {
        ...invalid[0],
        'ge015AdminRestartMutationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[0]['ge015AdminRestartMutationProof'] as Map,
          ),
          'addInviteRepairCompletedAfterRestart': false,
          'finalFanoutStatus': 'sent',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('addInviteRepairCompletedAfterRestart must be true'),
      );
      expect(
        rejected.detail,
        contains('finalFanoutStatus cannot be sent before repair'),
      );
    });

    test('rejects GE-015 stranded peer, leakage, and divergent epoch', () {
      final invalid = _validGe015Verdicts();
      invalid[1] = {
        ...invalid[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'ge015AdminRestartMutationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[1]['ge015AdminRestartMutationProof'] as Map,
          ),
          'allActivePeersConverged': false,
          'strandedPeerCount': 1,
          'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'finalEpoch': 4,
        },
      };
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe015RemovedWindow',
            'ge015-a-removed',
            'alice removed-window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe015RemovedWindow': 1,
        },
        'ge015AdminRestartMutationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge015AdminRestartMutationProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
          'hasStaleEpochAfterRepair': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('allActivePeersConverged must be true'));
      expect(rejected.detail, contains('strandedPeerCount must be 0'));
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceGe015RemovedWindow'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterRepair must be false'),
      );
      expect(rejected.detail, contains('GE-015 finalEpoch mismatch'));
    });

    test('accepts valid GE-016 concurrent admin mutation verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe016Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge016 verdicts valid'));
    });

    test('rejects GE-016 missing Dana convergence and version winner', () {
      final invalid = _validGe016Verdicts();
      invalid[1] = {
        ...invalid[1],
        'ge016ConcurrentAdminMutationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[1]['ge016ConcurrentAdminMutationProof'] as Map,
          ),
          'danaPresentAfterConflict': false,
          'addWinsByVersion': false,
          'finalMemberPeerIds': const <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          ],
          'finalRolesByPeerId': const <String, String>{
            'alice-peer': 'admin',
            'bob-peer': 'admin',
            'charlie-peer': 'writer',
          },
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('danaPresentAfterConflict must be true'),
      );
      expect(rejected.detail, contains('addWinsByVersion must be true'));
      expect(
        rejected.detail,
        contains('GE-016 final membership must include exactly one Dana'),
      );
    });

    test('accepts valid GE-020 long soak churn verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe020Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge020 verdicts valid'));
    });

    test('rejects GE-020 deaf member, stranded queue, and divergence', () {
      final invalid = _validGe020Verdicts();
      invalid[0] = {
        ...invalid[0],
        'ge020LongSoakChurnProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[0]['ge020LongSoakChurnProof'] as Map,
          ),
          'noPermanentDeafMember': false,
          'strandedQueueCount': 1,
          'heldDeliveryQueuesDrained': false,
          'finalEpoch': 3,
        },
      };
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGe020RemovedWindow',
            'ge020-a-removed',
            'alice removed-window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe020RemovedWindow': 1,
        },
        'ge020LongSoakChurnProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge020LongSoakChurnProof'] as Map,
          ),
          'noRemovedWindowPlaintext': false,
          'removedWindowPlaintextCount': 1,
          'postRemovalSendAccepted': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('noPermanentDeafMember must be true'));
      expect(
        rejected.detail,
        contains('heldDeliveryQueuesDrained must be true'),
      );
      expect(rejected.detail, contains('strandedQueueCount must be 0'));
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceGe020RemovedWindow'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
      expect(
        rejected.detail,
        contains('postRemovalSendAccepted must be false'),
      );
      expect(rejected.detail, contains('GE-020 finalEpoch mismatch'));
    });

    test('accepts valid GE-021 large group flaky member verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe021Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge021 verdicts valid'));
    });

    test('rejects GE-021 small roster, missed stable delivery, and leak', () {
      final invalid = _validGe021Verdicts();
      invalid[0] = {
        ...invalid[0],
        'ge021LargeGroupFlakyMemberProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[0]['ge021LargeGroupFlakyMemberProof'] as Map,
          ),
          'largeGroupRosterSize': 3,
          'syntheticStableMemberCount': 0,
          'finalRosterConverged': false,
          'stableMessageMissCount': 1,
          'noStableMemberMisses': false,
          'flakyRemovedAndReadded': false,
          'finalMemberPeerIds': const <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          ],
        },
      };
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          ...((invalid[2]['receivedMessages'] as List)
              .cast<Map<String, Object?>>()),
          _received(
            'aliceGe021RemovedWindow',
            'ge021-a-removed',
            'alice removed-window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe021Initial': 1,
          'bobGe021WhileFlaky': 1,
          'aliceGe021AfterOnline': 1,
          'aliceGe021RemovedWindow': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('largeGroupRosterSize must be >= 10'));
      expect(rejected.detail, contains('finalRosterConverged must be true'));
      expect(rejected.detail, contains('noStableMemberMisses must be true'));
      expect(rejected.detail, contains('stableMessageMissCount must be 0'));
      expect(rejected.detail, contains('flakyRemovedAndReadded must be true'));
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceGe021RemovedWindow'),
      );
    });

    test('accepts valid GE-023 media remove/re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge023',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe023Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge023 verdicts valid'));
    });

    test('rejects GE-023 missing media proof and removed-window leak', () {
      final invalid = _validGe023Verdicts();
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .map((entry) => Map<String, Object?>.from(entry))
          .toList();
      aliceSent[0].remove('mediaAttachments');
      aliceSent[1]['durableMediaCount'] = 0;
      invalid[0] = {...invalid[0], 'sentMessages': aliceSent};

      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          ...((invalid[2]['receivedMessages'] as List)
              .cast<Map<String, Object?>>()),
          _received(
            'aliceGe023RemovedWindow',
            'ge023-a-removed',
            'alice removed media',
            'alice-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGe023BeforeRemoval': 1,
          'aliceGe023RemovedWindow': 1,
        },
        'ge023MediaReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            invalid[2]['ge023MediaReaddProof'] as Map,
          ),
          'removedWindowMediaInaccessible': false,
          'noRemovedWindowPlaintext': false,
          'removedWindowPlaintextCount': 1,
          'removedWindowAttachmentCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge023',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('sent aliceGe023BeforeRemoval must carry exactly one media'),
      );
      expect(
        rejected.detail,
        contains('sent aliceGe023RemovedWindow must include media in durable'),
      );
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceGe023RemovedWindow'),
      );
      expect(
        rejected.detail,
        contains('removedWindowMediaInaccessible must be true'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
      expect(
        rejected.detail,
        contains('removedWindowAttachmentCount must be 0'),
      );
    });

    test('accepts valid GE-024 quoted reply boundary verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'ge024',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGe024Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('ge024 verdicts valid'));
    });

    test(
      'rejects GE-024 missing quote proof and removed-window parent leak',
      () {
        final invalid = _validGe024Verdicts();
        final bobSent = (invalid[1]['sentMessages'] as List)
            .cast<Map<String, Object?>>()
            .map((entry) => Map<String, Object?>.from(entry))
            .toList();
        bobSent[0]['quotedMessageId'] = 'wrong-parent';
        invalid[1] = {...invalid[1], 'sentMessages': bobSent};

        invalid[2] = {
          ...invalid[2],
          'receivedMessages': <Map<String, Object?>>[
            ...((invalid[2]['receivedMessages'] as List)
                .cast<Map<String, Object?>>()),
            _received(
              'aliceGe024RemovedWindowParent',
              'ge024-removed-parent',
              'alice removed parent',
              'alice-peer',
              keyEpoch: 1,
            ),
          ],
          'persistedMessageCounts': const <String, int>{
            'aliceGe024BeforeRemovalParent': 1,
            'aliceGe024RemovedWindowParent': 1,
            'bobGe024ReplyAvailable': 1,
            'bobGe024ReplyUnavailable': 1,
          },
          'ge024QuotedReplyProof': <String, Object?>{
            ...Map<String, Object?>.from(
              invalid[2]['ge024QuotedReplyProof'] as Map,
            ),
            'unavailableParentMissing': false,
            'noUnavailableParentPlaintext': false,
            'removedWindowPlaintextCount': 1,
            'noCrashRenderingUnavailableQuote': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'ge024',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: invalid,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('sent bobGe024ReplyAvailable quotedMessageId must be'),
        );
        expect(
          rejected.detail,
          contains('removed-window quote parent must not be received'),
        );
        expect(
          rejected.detail,
          contains('unavailableParentMissing must be true'),
        );
        expect(
          rejected.detail,
          contains('noUnavailableParentPlaintext must be true'),
        );
        expect(
          rejected.detail,
          contains('removedWindowPlaintextCount must be 0'),
        );
        expect(
          rejected.detail,
          contains('noCrashRenderingUnavailableQuote must be true'),
        );
      },
    );

    test('accepts valid GM-002 A/B/C/D convergence verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm002Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm002 verdicts valid'));
    });

    test('accepts valid GM-003 offline-add catch-up verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm003Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm003 verdicts valid'));
    });

    test('accepts valid GM-004 online removal verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm004Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm004 verdicts valid'));
    });

    test('accepts private_online_remove ML-005 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateOnlineRemoveVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_online_remove verdicts valid'));
    });

    test(
      'PL-006 rejects private_online_remove without removed media proof',
      () {
        final missingProof = _validPrivateOnlineRemoveVerdicts();
        missingProof[0] = Map<String, dynamic>.from(missingProof[0])
          ..remove('pl006RemovedMediaProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_online_remove',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('alice: missing PL-006 removed-media proof fields'),
        );
      },
    );

    test('PL-006 rejects Charlie direct media download after removal', () {
      final allowedDownload = _validPrivateOnlineRemoveVerdicts();
      allowedDownload[2] = {
        ...allowedDownload[2],
        'pl006RemovedMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            allowedDownload[2]['pl006RemovedMediaProof'] as Map,
          ),
          'directDownloadDenied': false,
          'directDownloadOk': true,
          'directDownloadOutputBytes': 8,
          'noDirectDownloadPlaintext': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: allowedDownload,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl006RemovedMediaProof.directDownloadDenied must be true',
        ),
      );
    });

    test('PL-006 rejects Charlie direct download output bytes', () {
      final leakedOutput = _validPrivateOnlineRemoveVerdicts();
      leakedOutput[2] = {
        ...leakedOutput[2],
        'pl006RemovedMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leakedOutput[2]['pl006RemovedMediaProof'] as Map,
          ),
          'directDownloadOutputBytes': 8,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leakedOutput,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl006RemovedMediaProof.directDownloadOutputBytes must be 0',
        ),
      );
    });

    test('PL-006 rejects Charlie media rows or pending downloads', () {
      final leakedRows = _validPrivateOnlineRemoveVerdicts();
      leakedRows[2] = {
        ...leakedRows[2],
        'pl006RemovedMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leakedRows[2]['pl006RemovedMediaProof'] as Map,
          ),
          'mediaRowsAfterRemoval': 1,
          'replayMediaRowsAbsent': false,
          'pendingDownloadsAfterRemoval': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leakedRows,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl006RemovedMediaProof.replayMediaRowsAbsent must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl006RemovedMediaProof.mediaRowsAfterRemoval must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl006RemovedMediaProof.pendingDownloadsAfterRemoval must be 0',
        ),
      );
    });

    test('PL-006 rejects mismatched removed media blob ids', () {
      final mismatchedBlob = _validPrivateOnlineRemoveVerdicts();
      mismatchedBlob[1] = {
        ...mismatchedBlob[1],
        'pl006RemovedMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            mismatchedBlob[1]['pl006RemovedMediaProof'] as Map,
          ),
          'mediaBlobId': 'different-post-removal-media',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: mismatchedBlob,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: pl006RemovedMediaProof.mediaBlobId must match Alice upload',
        ),
      );
    });

    test('accepts private_offline_remove ML-006 and IR-004 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateOfflineRemoveVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_offline_remove verdicts valid'));
    });

    test('accepts private_offline_readd RA-003 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateOfflineReaddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_offline_readd verdicts valid'));
    });

    test('accepts private_readd_current ML-007 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test(
      'accepts private_readd_current PL-004 quote re-add proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateReaddCurrentVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_readd_current verdicts valid'),
        );
      },
    );

    test('rejects private_readd_current PL-004 quote id mismatch', () {
      final mismatched = _validPrivateReaddCurrentVerdicts();
      final charlie = Map<String, dynamic>.from(mismatched[2]);
      final received = (charlie['receivedMessages'] as List)
          .map((entry) => Map<String, Object?>.from(entry as Map))
          .toList(growable: true);
      final quoteIndex = received.indexWhere(
        (entry) => entry['key'] == 'bobAfterReaddCurrent',
      );
      received[quoteIndex] = {
        ...received[quoteIndex],
        'quotedMessageId': 'wrong-parent',
      };
      mismatched[2] = {...charlie, 'receivedMessages': received};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: mismatched,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl004QuoteReaddLiveProof received quote did not reference Alice post-readd target',
        ),
      );
    });

    test(
      'PL-007 accepts private_readd_current re-added media proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateReaddCurrentVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_readd_current verdicts valid'),
        );
      },
    );

    test('PL-007 rejects missing re-added media proof fields', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('pl007ReaddMediaProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing PL-007 re-add media proof fields'),
      );
    });

    test('PL-007 rejects Charlie removed-window media leakage or residue', () {
      final leaked = _validPrivateReaddCurrentVerdicts();
      leaked[2] = {
        ...leaked[2],
        'pl007ReaddMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['pl007ReaddMediaProof'] as Map,
          ),
          'removedWindowMediaMessageCount': 1,
          'removedWindowMediaRowsAfterReadd': 1,
          'removedWindowPendingDownloadsBeforeReadd': 1,
          'pendingDownloadsAfterPostReadd': 1,
          'removedWindowDirectDownloadDenied': false,
          'removedWindowDirectDownloadOk': true,
          'removedWindowDirectDownloadOutputBytes': 4,
          'noRemovedWindowMediaPlaintext': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.removedWindowMediaMessageCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.removedWindowDirectDownloadOk must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.noRemovedWindowMediaPlaintext must be true',
        ),
      );
    });

    test('PL-007 rejects missing Charlie post-readd media download', () {
      final missingDownload = _validPrivateReaddCurrentVerdicts();
      missingDownload[2] = {
        ...missingDownload[2],
        'pl007ReaddMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDownload[2]['pl007ReaddMediaProof'] as Map,
          ),
          'postReaddMediaRows': 0,
          'postReaddMediaDownloaded': false,
          'postReaddMediaPersisted': false,
          'postReaddMediaDecrypted': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDownload,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.postReaddMediaDownloaded must be true',
        ),
      );
      expect(
        rejected.detail,
        contains('charlie: pl007ReaddMediaProof.postReaddMediaRows must be 1'),
      );
    });

    test('PL-007 rejects mismatched media blob id or window proof', () {
      final mismatched = _validPrivateReaddCurrentVerdicts();
      mismatched[1] = {
        ...mismatched[1],
        'pl007ReaddMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            mismatched[1]['pl007ReaddMediaProof'] as Map,
          ),
          'removedWindowMediaBlobId': 'wrong-removed-window-media',
        },
      };
      mismatched[2] = {
        ...mismatched[2],
        'pl007ReaddMediaProof': <String, Object?>{
          ...Map<String, Object?>.from(
            mismatched[2]['pl007ReaddMediaProof'] as Map,
          ),
          'postReaddMessageKey': 'aliceDuringCharlieRemoval',
          'postReaddMediaBlobId': 'wrong-post-readd-media',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: mismatched,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: pl007ReaddMediaProof.removedWindowMediaBlobId must match Alice removed-window media',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.postReaddMessageKey must be aliceAfterImmediateReadd',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl007ReaddMediaProof.postReaddMediaBlobId must match Alice post-readd media',
        ),
      );
    });

    test(
      'PL-011 accepts private_readd_current re-added reaction proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateReaddCurrentVerdicts(),
        );

        expect(verdict.ok, isTrue, reason: verdict.detail);
        expect(
          verdict.detail,
          contains('private_readd_current verdicts valid'),
        );
      },
    );

    test('PL-011 rejects missing re-added reaction proof fields', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('pl011ReaddReactionProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing PL-011 re-add reaction proof fields'),
      );
    });

    test('PL-011 rejects missing receiver stream evidence', () {
      final missingStream = _validPrivateReaddCurrentVerdicts();
      missingStream[1] = _withPl011ProofOverrides(
        missingStream[1],
        const <String, Object?>{'receivedViaGroupReactionStream': false},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingStream,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: PL-011 reaction must arrive through group reaction stream',
        ),
      );
    });

    test('PL-011 rejects reaction before current re-add target is visible', () {
      final staleTarget = _validPrivateReaddCurrentVerdicts();
      final alice = Map<String, dynamic>.from(staleTarget[0]);
      final sent = (alice['sentMessages'] as List)
          .map((entry) => Map<String, Object?>.from(entry as Map))
          .toList(growable: true);
      final targetIndex = sent.indexWhere(
        (entry) => entry['key'] == 'aliceAfterImmediateReadd',
      );
      sent[targetIndex] = {...sent[targetIndex], 'keyEpoch': 1};
      staleTarget[0] = {...alice, 'sentMessages': sent};
      staleTarget[2] =
          _withPl011ProofOverrides(staleTarget[2], const <String, Object?>{
            'targetVisibleBeforeReaction': false,
            'postReaddReactionAtCurrentEpoch': false,
          });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleTarget,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: PL-011 target must be sent at current re-add epoch'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: pl011ReaddReactionProof.targetVisibleBeforeReaction must be true',
        ),
      );
    });

    test(
      'accepts private_readd_current RA-006 delayed old key proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateReaddCurrentVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_readd_current verdicts valid'),
        );
      },
    );

    test('accepts private_readd_current RA-007 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test('accepts private_readd_current RA-008 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test('accepts private_readd_current RA-009 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test('accepts private_readd_current RA-010 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test('accepts private_readd_current RA-014 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test(
      'UP-001 rejects private_readd_current without membership/config sync proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[0] = Map<String, dynamic>.from(missingProof[0])
          ..remove('up001MembershipConfigSyncProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('alice: missing UP-001 membership/config sync proof fields'),
        );
      },
    );

    test('UP-003 rejects private_readd_current without compose gate proof', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('up003ComposeGateProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing UP-003 compose gate proof fields'),
      );
    });

    test('accepts private_readd_current RA-015 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCurrentVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_current verdicts valid'));
    });

    test('accepts valid RA-011 late leave re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_late_leave_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validRa011LateLeaveReaddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_late_leave_readd verdicts valid'),
      );
    });

    test('accepts valid RA-012 rotated device re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rotated_device_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validRa012RotatedDeviceReaddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_rotated_device_readd verdicts valid'),
      );
    });

    test('RA-013 accepts same-user multi-device re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_same_user_multi_device_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validRa013SameUserMultiDeviceReaddVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_same_user_multi_device_readd verdicts valid'),
      );
    });

    test('RA-013 rejects weak same-user device proof', () {
      final weak = _validRa013SameUserMultiDeviceReaddVerdicts();
      weak[3] = <String, dynamic>{
        ...weak[3],
        'ra013SameUserMultiDeviceReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            weak[3]['ra013SameUserMultiDeviceReaddProof'] as Map,
          ),
          'preAcceptPlaintextCount': 1,
          'memberListIncludesDanaAccount': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_same_user_multi_device_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: weak,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: ra013SameUserMultiDeviceReaddProof'),
      );
      expect(rejected.detail, contains('preAcceptPlaintextCount must be 0'));
    });

    test('RA-017 accepts private_readd_active_members proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddActiveMembersVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_readd_active_members verdicts valid'),
      );
    });

    test('RA-017 rejects A/B/C-only proof missing Dana role', () {
      final missingDana = _validPrivateReaddActiveMembersVerdicts()
        ..removeWhere((verdict) => verdict['role'] == 'dana');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDana,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('dana: missing role verdict'));
      expect(
        rejected.detail,
        contains('dana: RA-017 requires explicit D/Dana peer id coverage'),
      );
    });

    test('RA-017 rejects missing Dana active send counter', () {
      final missingDanaSend = _validPrivateReaddActiveMembersVerdicts();
      final dana = Map<String, dynamic>.from(missingDanaSend[3]);
      dana['sentMessages'] = _mapListForTest(dana['sentMessages'])
          .where((entry) => entry['key'] != 'ra017Cycle1_removed_dana')
          .toList(growable: false);
      missingDanaSend[3] = dana;

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDanaSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: sent ra017Cycle1_removed_dana count=0'),
      );
    });

    test('RA-017 rejects missing active receive counter', () {
      final missingReceive = _validPrivateReaddActiveMembersVerdicts();
      final bob = Map<String, dynamic>.from(missingReceive[1]);
      bob['receivedMessages'] = _mapListForTest(bob['receivedMessages'])
          .where((entry) => entry['key'] != 'ra017Cycle1_removed_dana')
          .toList(growable: false);
      bob['persistedMessageCounts'] = <String, int>{
        ...Map<String, int>.from(bob['persistedMessageCounts'] as Map),
      }..remove('ra017Cycle1_removed_dana');
      missingReceive[1] = bob;

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingReceive,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received ra017Cycle1_removed_dana count=0'),
      );
    });

    test('RA-017 rejects fewer than 3 Charlie churn cycles', () {
      final shortRun = _validPrivateReaddActiveMembersVerdicts();
      shortRun[0] = {
        ...shortRun[0],
        'ra017ActiveMemberChurnProof': <String, Object?>{
          ...Map<String, Object?>.from(
            shortRun[0]['ra017ActiveMemberChurnProof'] as Map,
          ),
          'churnCycles': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: shortRun,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: ra017ActiveMemberChurnProof.churnCycles must be >= 3'),
      );
    });

    test('RA-017 rejects removed-window plaintext leakage to Charlie', () {
      final leaked = _validPrivateReaddActiveMembersVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          ..._mapListForTest(leaked[2]['receivedMessages']),
          _received(
            'ra017Cycle1_removed_alice',
            'ra017-c1-removed-alice',
            'RA-017 cycle 1 removed from Alice',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': <String, int>{
          ...Map<String, int>.from(leaked[2]['persistedMessageCounts'] as Map),
          'ra017Cycle1_removed_alice': 1,
        },
        'ra017ActiveMemberChurnProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ra017ActiveMemberChurnProof'] as Map,
          ),
          'charlieRemovedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('removed-window RA-017 plaintext leaked'),
      );
      expect(
        rejected.detail,
        contains('charlieRemovedWindowPlaintextCount must be 0'),
      );
    });

    test('RA-017 rejects final member or key divergence', () {
      final divergent = _validPrivateReaddActiveMembersVerdicts();
      divergent[3] = {
        ...divergent[3],
        'keyEpoch': 6,
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
        'activeMemberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
        'ra017ActiveMemberChurnProof': <String, Object?>{
          ...Map<String, Object?>.from(
            divergent[3]['ra017ActiveMemberChurnProof'] as Map,
          ),
          'finalRoles': const <String>['alice', 'bob', 'charlie'],
          'finalEpoch': 6,
          'finalEpochConverged': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_active_members',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('missing dana-peer'));
      expect(rejected.detail, contains('finalEpochConverged must be true'));
      expect(
        rejected.detail,
        contains('dana: ra017ActiveMemberChurnProof.finalEpoch must be >= 7'),
      );
    });

    test('RA-018 accepts private_readd_alternating_churn proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddAlternatingChurnVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_readd_alternating_churn verdicts valid'),
      );
    });

    test('RA-018 rejects weak RA-017-only proof', () {
      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddActiveMembersVerdicts(),
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missing RA-018 alternating churn proof fields'),
      );
      expect(
        rejected.detail,
        contains('sent ra018Cycle1_charlieRemoved_alice count=0'),
      );
    });

    test('RA-018 rejects weak ML-008-only proof', () {
      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCyclesVerdicts(),
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('dana: missing role verdict'));
      expect(
        rejected.detail,
        contains('missing RA-018 alternating churn proof fields'),
      );
    });

    test('RA-018 rejects missing Charlie or Dana churn target', () {
      final missingCharlie = _validPrivateReaddAlternatingChurnVerdicts();
      missingCharlie[0] = _withRa018ProofOverrides(
        missingCharlie[0],
        const <String, Object?>{
          'churnTargets': <String>['dana'],
        },
      );
      final charlieRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingCharlie,
      );
      expect(charlieRejected.ok, isFalse);
      expect(
        charlieRejected.detail,
        contains('churnTargets must include charlie, dana'),
      );

      final missingDana = _validPrivateReaddAlternatingChurnVerdicts();
      missingDana[1] = _withRa018ProofOverrides(
        missingDana[1],
        const <String, Object?>{
          'churnTargets': <String>['charlie'],
        },
      );
      final danaRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDana,
      );
      expect(danaRejected.ok, isFalse);
      expect(
        danaRejected.detail,
        contains('churnTargets must include charlie, dana'),
      );
    });

    test('RA-018 rejects missing active sender or inactive sender use', () {
      final missingSender = _validPrivateReaddAlternatingChurnVerdicts();
      missingSender[2] = _withRa018ProofOverrides(
        missingSender[2],
        const <String, Object?>{
          'activeSenders': <String>['alice', 'bob', 'dana'],
        },
      );
      final missingSenderRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingSender,
      );
      expect(missingSenderRejected.ok, isFalse);
      expect(
        missingSenderRejected.detail,
        contains('activeSenders must include alice, bob, charlie, dana'),
      );

      final inactiveSender = _validPrivateReaddAlternatingChurnVerdicts();
      inactiveSender[3] = _withRa018ProofOverrides(
        inactiveSender[3],
        const <String, Object?>{'inactiveSenderAttemptCount': 1},
      );
      final inactiveSenderRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: inactiveSender,
      );
      expect(inactiveSenderRejected.ok, isFalse);
      expect(
        inactiveSenderRejected.detail,
        contains('inactiveSenderAttemptCount must be 0'),
      );
    });

    test('RA-018 rejects inactive-window plaintext leakage', () {
      final leaked = _validPrivateReaddAlternatingChurnVerdicts();
      leaked[2] = _withRa018ProofOverrides(
        {
          ...leaked[2],
          'receivedMessages': <Map<String, Object?>>[
            ..._mapListForTest(leaked[2]['receivedMessages']),
            _received(
              'ra018Cycle1_charlieRemoved_alice',
              'ra018-c1-charlieRemoved-alice',
              'RA-018 cycle 1 charlieRemoved from Alice',
              'alice-peer',
              keyEpoch: 2,
            ),
          ],
          'persistedMessageCounts': <String, int>{
            ...Map<String, int>.from(
              leaked[2]['persistedMessageCounts'] as Map,
            ),
            'ra018Cycle1_charlieRemoved_alice': 1,
          },
        },
        const <String, Object?>{'charlieRemovedWindowPlaintextCount': 1},
      );
      leaked[3] = _withRa018ProofOverrides(
        {
          ...leaked[3],
          'receivedMessages': <Map<String, Object?>>[
            ..._mapListForTest(leaked[3]['receivedMessages']),
            _received(
              'ra018Cycle1_danaRemoved_charlie',
              'ra018-c1-danaRemoved-charlie',
              'RA-018 cycle 1 danaRemoved from Charlie',
              'charlie-peer',
              keyEpoch: 4,
            ),
          ],
          'persistedMessageCounts': <String, int>{
            ...Map<String, int>.from(
              leaked[3]['persistedMessageCounts'] as Map,
            ),
            'ra018Cycle1_danaRemoved_charlie': 1,
          },
        },
        const <String, Object?>{'danaRemovedWindowPlaintextCount': 1},
      );

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: removed-window RA-018 plaintext leaked'),
      );
      expect(
        rejected.detail,
        contains('dana: removed-window RA-018 plaintext leaked'),
      );
      expect(
        rejected.detail,
        contains('charlieRemovedWindowPlaintextCount must be 0'),
      );
      expect(
        rejected.detail,
        contains('danaRemovedWindowPlaintextCount must be 0'),
      );
    });

    test('RA-018 rejects duplicate visible messages', () {
      final duplicated = _validPrivateReaddAlternatingChurnVerdicts();
      final bob = Map<String, dynamic>.from(duplicated[1]);
      bob['receivedMessages'] = <Map<String, Object?>>[
        ..._mapListForTest(bob['receivedMessages']),
        _received(
          'ra018Cycle1_charlieRemoved_alice',
          'ra018-c1-charlieRemoved-alice',
          'RA-018 cycle 1 charlieRemoved from Alice',
          'alice-peer',
          keyEpoch: 2,
        ),
      ];
      bob['persistedMessageCounts'] = <String, int>{
        ...Map<String, int>.from(bob['persistedMessageCounts'] as Map),
        'ra018Cycle1_charlieRemoved_alice': 2,
      };
      duplicated[1] = _withRa018ProofOverrides(bob, const <String, Object?>{
        'duplicateVisibleMessageCount': 1,
      });

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicated,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received ra018Cycle1_charlieRemoved_alice count=2'),
      );
      expect(
        rejected.detail,
        contains('duplicateVisibleMessageCount must be 0'),
      );
    });

    test('RA-018 rejects insufficient cycles or final divergence', () {
      final shortRun = _validPrivateReaddAlternatingChurnVerdicts();
      shortRun[0] = _withRa018ProofOverrides(
        shortRun[0],
        const <String, Object?>{'churnCycles': 2},
      );
      final shortRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: shortRun,
      );
      expect(shortRejected.ok, isFalse);
      expect(
        shortRejected.detail,
        contains('ra018AlternatingChurnProof.churnCycles must be >= 3'),
      );

      final divergent = _validPrivateReaddAlternatingChurnVerdicts();
      divergent[3] = _withRa018ProofOverrides(
        {
          ...divergent[3],
          'keyEpoch': 12,
          'memberPeerIds': const <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          ],
          'activeMemberPeerIds': const <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          ],
        },
        const <String, Object?>{
          'finalRoles': <String>['alice', 'bob', 'charlie'],
          'finalEpoch': 12,
          'finalEpochConverged': false,
        },
      );
      final divergentRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_alternating_churn',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );
      expect(divergentRejected.ok, isFalse);
      expect(divergentRejected.detail, contains('missing dana-peer'));
      expect(
        divergentRejected.detail,
        contains('finalEpochConverged must be true'),
      );
      expect(divergentRejected.detail, contains('finalEpoch must be >= 13'));
    });

    test('NW-014 accepts private_network_chaos_invariants proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_network_chaos_invariants',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateNetworkChaosInvariantVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_network_chaos_invariants verdicts valid'),
      );
    });

    test('NW-014 rejects weak churn proof without chaos invariant fields', () {
      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_network_chaos_invariants',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddAlternatingChurnVerdicts(),
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missing NW-014 chaos invariant proof fields'),
      );
    });

    test(
      'NW-014 rejects wrong seed or missing fake-network proof requirement',
      () {
        final wrongSeed = _validPrivateNetworkChaosInvariantVerdicts();
        wrongSeed[0] = _withNw014ProofOverrides(
          wrongSeed[0],
          const <String, Object?>{
            'fixedSeed': 7,
            'fakeNetworkChaosProofRequired': false,
          },
        );

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_network_chaos_invariants',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: wrongSeed,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('fixedSeed must be 14014'));
        expect(
          rejected.detail,
          contains('fakeNetworkChaosProofRequired must be true'),
        );
      },
    );

    test('accepts private_readd_cycles ML-008 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateReaddCyclesVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_readd_cycles verdicts valid'));
    });

    test('accepts valid GM-005 offline removal verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm005Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm005 verdicts valid'));
    });

    test('accepts valid GM-006 immediate re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm006Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm006 verdicts valid'));
    });

    test(
      'accepts valid GM-007, KE-018, and IR-005 history-boundary verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm007',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validGm007Verdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(verdict.detail, contains('gm007 verdicts valid'));
      },
    );

    test('accepts valid GM-008 restart re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm008Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm008 verdicts valid'));
    });

    test('accepts valid GM-009 duplicate removal verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm009Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm009 verdicts valid'));
    });

    test('accepts valid GM-010 duplicate re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm010Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm010 verdicts valid'));
    });

    test('accepts valid GM-011 stale add removal verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm011Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm011 verdicts valid'));
    });

    test('accepts valid GM-012 stale remove re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm012Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm012 verdicts valid'));
    });

    test('accepts valid GM-013 simultaneous remove/send verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm013Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm013 verdicts valid'));
    });

    test('accepts valid GM-014 simultaneous re-add/send verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm014Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm014 verdicts valid'));
    });

    test('accepts valid GM-015 admin self-removal policy verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm015Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm015 verdicts valid'));
    });

    test('accepts valid GM-016 removed member unsubscribe verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm016Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm016 verdicts valid'));
    });

    test('accepts valid GM-017 stale subscription rejection verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm017Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm017 verdicts valid'));
    });

    test('accepts valid GO-003 sender validation feedback verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'go003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGo003Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('go003 verdicts valid'));
    });

    test('accepts valid GM-018 remaining-member continuity verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm018',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm018Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm018 verdicts valid'));
    });

    test('rejects GM-018 missing repeated live or inbox proof', () {
      final invalid = _validGm018Verdicts();
      final bobProof =
          Map<String, Object?>.from(
              invalid[1]['gm018RemainingDeliveryContinuityProof'] as Map,
            )
            ..['liveBobReceiptCount'] = 2
            ..['inboxReplayReceiptCount'] = 1
            ..['exactOnceDelivery'] = false;
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGm018Live1',
            'gm018-live-1',
            'gm018 live 1',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'aliceGm018Live1': 1},
        'gm018RemainingDeliveryContinuityProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm018',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.liveBobReceiptCount must be >= 3',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.inboxReplayReceiptCount must be >= 3',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.exactOnceDelivery must be true',
        ),
      );
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceGm018Live2'),
      );
    });

    test('rejects GM-018 labeled replay without Bob offline durable proof', () {
      final invalid = _validGm018Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm018RemainingDeliveryContinuityProof'] as Map,
            )
            ..['bobOfflineProofObserved'] = false
            ..['inboxSentAfterBobOffline'] = false;
      final bobProof =
          Map<String, Object?>.from(
              invalid[1]['gm018RemainingDeliveryContinuityProof'] as Map,
            )
            ..['bobOfflineBeforeInboxSend'] = false
            ..['bobRestartedBeforeInboxDrain'] = false
            ..['inboxReplayDrainedFromDurableInbox'] = false
            ..['inboxLiveLeakCountBeforeReplay'] = 1
            ..['inboxReplayDrainMessageCount'] = 0
            ..remove('inboxReplayMessageIds')
            ..remove('inboxReplayReceiptKeys');
      invalid[0] = {
        ...invalid[0],
        'gm018RemainingDeliveryContinuityProof': aliceProof,
      };
      invalid[1] = {
        ...invalid[1],
        'gm018RemainingDeliveryContinuityProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm018',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm018RemainingDeliveryContinuityProof.bobOfflineProofObserved must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm018RemainingDeliveryContinuityProof.inboxSentAfterBobOffline must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.bobOfflineBeforeInboxSend must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.inboxLiveLeakCountBeforeReplay must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.inboxReplayDrainMessageCount must be >= 3',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm018RemainingDeliveryContinuityProof.inboxReplayMessageIds must include exact actual message IDs',
        ),
      );
    });

    test('rejects GM-018 Charlie plaintext leak or stale recipients', () {
      final invalid = _validGm018Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm018RemainingDeliveryContinuityProof'] as Map,
            )
            ..['receivedPostRemovalPlaintext'] = true
            ..['postRemovalPlaintextCount'] = 1;
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGm018Live1',
            'gm018-live-1',
            'gm018 live 1',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'aliceGm018Live1': 1},
        'gm018RemainingDeliveryContinuityProof': charlieProof,
      };
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[0] = {
        ...aliceSent[0],
        'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
      };
      invalid[0] = {...invalid[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm018',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm018RemainingDeliveryContinuityProof.receivedPostRemovalPlaintext must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm018RemainingDeliveryContinuityProof.postRemovalPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys aliceGm018Live1'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm018Live1 recipientPeerIds mismatch, unexpected charlie-peer',
        ),
      );
    });

    test('accepts valid GM-019 durable recipient window verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm019Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm019 verdicts valid'));
    });

    test('rejects GM-019 wrong durable recipient windows', () {
      final invalid = _validGm019Verdicts();
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[0] = {
        ...aliceSent[0],
        'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
      };
      aliceSent[1] = {
        ...aliceSent[1],
        'recipientPeerIds': <String>['bob-peer'],
      };
      invalid[0] = {...invalid[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm019RemovedWindow recipientPeerIds mismatch, unexpected charlie-peer',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm019AfterReadd recipientPeerIds mismatch, missing charlie-peer',
        ),
      );
    });

    test('rejects GM-019 duplicate recipients and sender recipients', () {
      final invalid = _validGm019Verdicts();
      final bobSent = (invalid[1]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      bobSent[0] = {
        ...bobSent[0],
        'recipientPeerIds': <String>[
          'alice-peer',
          'charlie-peer',
          'charlie-peer',
          'bob-peer',
        ],
      };
      invalid[1] = {...invalid[1], 'sentMessages': bobSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: sent bobGm019AfterReadd recipientPeerIds contain duplicates',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: sent bobGm019AfterReadd recipientPeerIds mismatch, unexpected bob-peer',
        ),
      );
    });

    test('rejects GM-019 missing actual durable proof and timestamp order', () {
      final invalid = _validGm019Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm019DurableRecipientWindowProof'] as Map,
            )
            ..['actualDurablePayloadProof'] = false
            ..['removedWindowSentAt'] = '2026-05-11T08:20:00.000Z'
            ..['readdAt'] = '2026-05-11T08:10:00.000Z';
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[0] = {...aliceSent[0], 'actualDurablePayloadProof': false};
      invalid[0] = {
        ...invalid[0],
        'sentMessages': aliceSent,
        'gm019DurableRecipientWindowProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm019DurableRecipientWindowProof.actualDurablePayloadProof must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm019DurableRecipientWindowProof timestamps must satisfy',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm019RemovedWindow must report actual durable payload proof',
        ),
      );
    });

    test('rejects GM-019 wrong scenario, missing role, and Charlie leak', () {
      final wrongScenario = _validGm019Verdicts();
      wrongScenario[1] = {...wrongScenario[1], 'scenario': 'gm018'};

      final rejectedScenario = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongScenario,
      );
      expect(rejectedScenario.ok, isFalse);
      expect(rejectedScenario.detail, contains('bob: scenario mismatch gm018'));

      final missingCharlie = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm019Verdicts().take(2).toList(growable: false),
      );
      expect(missingCharlie.ok, isFalse);
      expect(missingCharlie.detail, contains('charlie: missing role verdict'));

      final charlieLeak = _validGm019Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              charlieLeak[2]['gm019DurableRecipientWindowProof'] as Map,
            )
            ..['receivedRemovedWindowMessage'] = true
            ..['removedWindowPlaintextCount'] = 1;
      charlieLeak[2] = {
        ...charlieLeak[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGm019RemovedWindow',
            'gm019-removed-window',
            'gm019 removed window',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGm019RemovedWindow': 1,
        },
        'gm019DurableRecipientWindowProof': charlieProof,
      };

      final rejectedLeak = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm019',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: charlieLeak,
      );
      expect(rejectedLeak.ok, isFalse);
      expect(
        rejectedLeak.detail,
        contains(
          'charlie: gm019DurableRecipientWindowProof.receivedRemovedWindowMessage must be false',
        ),
      );
      expect(
        rejectedLeak.detail,
        contains(
          'charlie: unexpected received proof keys aliceGm019RemovedWindow',
        ),
      );
    });

    test('accepts valid GM-020 immediate recipient exclusion verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm020Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm020 verdicts valid'));
    });

    test('rejects GM-020 Charlie recipient and missing Bob recipient', () {
      final invalid = _validGm020Verdicts();
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[0] = {
        ...aliceSent[0],
        'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
      };
      aliceSent[1] = {
        ...aliceSent[1],
        'recipientPeerIds': <String>['charlie-peer'],
      };
      invalid[0] = {...invalid[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm020ImmediatePostRemoval recipientPeerIds mismatch, unexpected charlie-peer',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm020OfflinePostRemoval recipientPeerIds mismatch, missing bob-peer, unexpected charlie-peer',
        ),
      );
    });

    test('rejects GM-020 duplicate recipients and sender recipients', () {
      final invalid = _validGm020Verdicts();
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[1] = {
        ...aliceSent[1],
        'recipientPeerIds': <String>['bob-peer', 'bob-peer', 'alice-peer'],
      };
      invalid[0] = {...invalid[0], 'sentMessages': aliceSent};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm020OfflinePostRemoval recipientPeerIds contain duplicates',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm020OfflinePostRemoval recipientPeerIds mismatch, unexpected alice-peer',
        ),
      );
    });

    test('rejects GM-020 missing actual durable proof and timestamp order', () {
      final invalid = _validGm020Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm020ImmediateRecipientExclusionProof'] as Map,
            )
            ..['actualDurablePayloadProof'] = false
            ..['firstPostRemovalSentAt'] = '2026-05-11T08:10:00.000Z'
            ..['offlinePostRemovalSentAt'] = '2026-05-11T08:05:00.000Z';
      final aliceSent = (invalid[0]['sentMessages'] as List)
          .cast<Map<String, Object?>>()
          .toList();
      aliceSent[0] = {...aliceSent[0], 'actualDurablePayloadProof': false};
      invalid[0] = {
        ...invalid[0],
        'sentMessages': aliceSent,
        'gm020ImmediateRecipientExclusionProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm020ImmediateRecipientExclusionProof.actualDurablePayloadProof must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm020ImmediateRecipientExclusionProof timestamps must satisfy',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm020ImmediatePostRemoval must report actual durable payload proof',
        ),
      );
    });

    test('rejects GM-020 missing proof and Charlie plaintext leak', () {
      final missingProof = _validGm020Verdicts();
      final aliceWithoutProof = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm020ImmediateRecipientExclusionProof');
      missingProof[0] = aliceWithoutProof;

      final rejectedMissing = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );
      expect(rejectedMissing.ok, isFalse);
      expect(
        rejectedMissing.detail,
        contains(
          'alice: missing GM-020 immediate recipient exclusion proof fields',
        ),
      );

      final charlieLeak = _validGm020Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              charlieLeak[2]['gm020ImmediateRecipientExclusionProof'] as Map,
            )
            ..['receivedPostRemovalPlaintext'] = true
            ..['postRemovalPlaintextCount'] = 1;
      charlieLeak[2] = {
        ...charlieLeak[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGm020ImmediatePostRemoval',
            'gm020-immediate',
            'gm020 immediate',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGm020ImmediatePostRemoval': 1,
        },
        'gm020ImmediateRecipientExclusionProof': charlieProof,
      };

      final rejectedLeak = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: charlieLeak,
      );
      expect(rejectedLeak.ok, isFalse);
      expect(
        rejectedLeak.detail,
        contains(
          'charlie: gm020ImmediateRecipientExclusionProof.receivedPostRemovalPlaintext must be false',
        ),
      );
      expect(
        rejectedLeak.detail,
        contains(
          'charlie: unexpected received proof keys aliceGm020ImmediatePostRemoval',
        ),
      );
    });

    test('accepts valid GM-021 fresh re-add package verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm021Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm021 verdicts valid'));
    });

    test('rejects GM-021 missing fresh-vs-old package proof', () {
      final missingProof = _validGm021Verdicts();
      final aliceWithoutProof = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm021FreshReaddPackageProof');
      missingProof[0] = aliceWithoutProof;

      final rejectedMissing = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );
      expect(rejectedMissing.ok, isFalse);
      expect(
        rejectedMissing.detail,
        contains('alice: missing GM-021 fresh re-add package proof fields'),
      );

      final identicalPackages = _validGm021Verdicts();
      final charlieProof = Map<String, Object?>.from(
        identicalPackages[2]['gm021FreshReaddPackageProof'] as Map,
      )..['freshKeyPackageId'] = 'kp-charlie-old';
      identicalPackages[2] = {
        ...identicalPackages[2],
        'gm021FreshReaddPackageProof': charlieProof,
      };

      final rejectedIdentical = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: identicalPackages,
      );
      expect(rejectedIdentical.ok, isFalse);
      expect(
        rejectedIdentical.detail,
        contains(
          'charlie: gm021FreshReaddPackageProof.oldKeyPackageId and freshKeyPackageId must differ',
        ),
      );
    });

    test('rejects GM-021 missing same-active-device stale package rejection', () {
      final invalid = _validGm021Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm021FreshReaddPackageProof'] as Map,
            )
            ..['sameActiveDeviceStaleKeyPackageRejected'] = false
            ..['sameActiveDeviceStaleKeyPackageAccepted'] = true
            ..['sameActiveDeviceStaleKeyPackageRejectionReason'] = 'accepted';
      invalid[2] = {...invalid[2], 'gm021FreshReaddPackageProof': charlieProof};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm021FreshReaddPackageProof.sameActiveDeviceStaleKeyPackageRejected must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm021FreshReaddPackageProof.sameActiveDeviceStaleKeyPackageAccepted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm021FreshReaddPackageProof.sameActiveDeviceStaleKeyPackageRejectionReason must be unbound_device',
        ),
      );
    });

    test('rejects GM-021 accepted stale plaintext on Alice or Bob', () {
      final invalid = _validGm021Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm021FreshReaddPackageProof'] as Map,
            )
            ..['receivedStaleSameActiveDevicePlaintext'] = true
            ..['staleSameActiveDevicePlaintextCount'] = 1;
      invalid[0] = {
        ...invalid[0],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'charlieGm021FreshAfterReadd',
            'gm021-fresh',
            'gm021 fresh after readd',
            'charlie-peer',
            keyEpoch: 2,
          ),
          _received(
            'charlieGm021StaleSameActive',
            'gm021-stale-same-active',
            'gm021 stale same active',
            'charlie-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'charlieGm021FreshAfterReadd': 1,
          'charlieGm021StaleSameActive': 1,
        },
        'gm021FreshReaddPackageProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm021',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm021FreshReaddPackageProof.receivedStaleSameActiveDevicePlaintext must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm021FreshReaddPackageProof.staleSameActiveDevicePlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: unexpected received proof keys charlieGm021StaleSameActive',
        ),
      );
    });

    test('GM-022 accepts repeated remove re-add dedupe verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm022',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm022Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm022 verdicts valid'));
    });

    test('GM-022 rejects duplicate Charlie and non-unique recipients', () {
      final invalid = _validGm022Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm022RepeatedReaddDedupProof'] as Map,
            )
            ..['duplicateMemberPeerIds'] = const <String>['charlie-peer']
            ..['charlieMemberEntryCount'] = 2
            ..['activeCharlieEntryCount'] = 2
            ..['durableRecipientsUnique'] = false;
      invalid[0] = {
        ...invalid[0],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
          'charlie-peer',
        ],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceGm022AfterReadd',
            'messageId': 'gm022-alice-after',
            'text': 'gm022 alice after readd',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>[
              'bob-peer',
              'charlie-peer',
              'charlie-peer',
            ],
            'actualDurablePayloadProof': true,
          },
        ],
        'gm022RepeatedReaddDedupProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm022',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm022RepeatedReaddDedupProof.duplicateMemberPeerIds must be empty',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm022RepeatedReaddDedupProof.charlieMemberEntryCount must be 1',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm022AfterReadd recipientPeerIds contain duplicates',
        ),
      );
    });

    test('GM-023 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm023',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm023 role devices'));
      expect(
        roleDeviceMapForScenario(
          scenario: 'gm023',
          deviceIds: const <String>[
            'alice-device',
            'bob-device',
            'charlie-device',
          ],
        ),
        const <String, String>{
          'alice': 'alice-device',
          'bob': 'bob-device',
          'charlie': 'charlie-device',
        },
      );
    });

    test('GM-023 accepts inactive shadow proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm023',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm023Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm023 verdicts valid'));
    });

    test('GM-023 rejects stale shadow delivery and inactive discovery use', () {
      final invalid = _validGm023Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm023InactiveShadowProof'] as Map,
            )
            ..['inactiveShadowBeforeActive'] = false
            ..['freshCharlieSendAccepted'] = false
            ..['staleInactiveShadowSendAccepted'] = true
            ..['discoveryUsedActiveEntry'] = false
            ..['inactiveShadowDialedOrCounted'] = true
            ..['durableRecipientsUnique'] = false
            ..['charlieMemberEntryCount'] = 2;
      invalid[0] = {
        ...invalid[0],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceGm023AfterInactiveShadow',
            'messageId': 'gm023-alice-after',
            'text': 'gm023 alice after inactive shadow',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>[
              'bob-peer',
              'charlie-peer',
              'charlie-peer',
            ],
            'actualDurablePayloadProof': true,
          },
        ],
        'gm023InactiveShadowProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm023',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm023InactiveShadowProof.inactiveShadowBeforeActive must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm023InactiveShadowProof.staleInactiveShadowSendAccepted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm023InactiveShadowProof.inactiveShadowDialedOrCounted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm023AfterInactiveShadow recipientPeerIds contain duplicates',
        ),
      );
    });

    test('GM-024 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm024',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm024 role devices'));
      expect(
        roleDeviceMapForScenario(
          scenario: 'gm024',
          deviceIds: const <String>[
            'alice-device',
            'bob-device',
            'charlie-device',
          ],
        ),
        const <String, String>{
          'alice': 'alice-device',
          'bob': 'bob-device',
          'charlie': 'charlie-device',
        },
      );
    });

    test('GM-024 accepts member display state convergence verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm024',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm024Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm024 verdicts valid'));
    });

    test('GM-024 rejects stale display state and recipient drift', () {
      final invalid = _validGm024Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm024MemberDisplayStateProof'] as Map,
            )
            ..['charlieCurrentStatus'] = 'stale'
            ..['topicJoined'] = false
            ..['composeSendPermission'] = false
            ..['livePublishAccepted'] = false
            ..['liveTopicPeerState'] = 'not_joined_or_no_peers'
            ..['liveTopicPeerCount'] = 0
            ..['durableRecipientsUnique'] = false
            ..['actualSendKeys'] = const <String>['aliceGm024AfterReadd'];
      invalid[0] = {
        ...invalid[0],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceGm024AfterReadd',
            'messageId': 'gm024-alice-after',
            'text': 'gm024 alice after readd',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>[
              'bob-peer',
              'charlie-peer',
              'charlie-peer',
            ],
            'actualDurablePayloadProof': true,
            'actualTopicPeerProof': true,
            'topicPeers': 2,
          },
        ],
        'gm024MemberDisplayStateProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm024',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.charlieCurrentStatus must be current',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.topicJoined must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.composeSendPermission must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.livePublishAccepted must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.liveTopicPeerCount must be >= 2',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm024AfterReadd recipientPeerIds contain duplicates',
        ),
      );
    });

    test('GM-024 rejects missing actual topic peer evidence', () {
      final invalid = _validGm024Verdicts();
      final aliceSent =
          Map<String, Object?>.from(
              ((invalid[0]['sentMessages'] as List).single as Map),
            )
            ..remove('actualTopicPeerProof')
            ..remove('topicPeers');
      invalid[0] = {
        ...invalid[0],
        'sentMessages': <Map<String, Object?>>[aliceSent],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm024',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: sent aliceGm024AfterReadd must report actual topic peer proof',
        ),
      );
      expect(
        rejected.detail,
        contains('alice: sent aliceGm024AfterReadd missing topicPeers'),
      );
    });

    test('GM-024 rejects proof topic count drift from sent evidence', () {
      final invalid = _validGm024Verdicts();
      final aliceSent = Map<String, Object?>.from(
        ((invalid[0]['sentMessages'] as List).single as Map),
      )..['topicPeers'] = 1;
      invalid[0] = {
        ...invalid[0],
        'sentMessages': <Map<String, Object?>>[aliceSent],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm024',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: sent aliceGm024AfterReadd topicPeers must be >= 2'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm024MemberDisplayStateProof.liveTopicPeerCount must match sent aliceGm024AfterReadd topicPeers',
        ),
      );
    });

    test('GM-025 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm025',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm025 role devices'));
    });

    test('GM-025 accepts role permission re-add verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm025',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm025Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm025 verdicts valid'));
    });

    test(
      'GM-025 rejects stale permissions duplicate Charlie and missing action proof',
      () {
        final invalid = _validGm025Verdicts();
        final aliceProof =
            Map<String, Object?>.from(
                invalid[0]['gm025RolePermissionReaddProof'] as Map,
              )
              ..['rawMemberPeerIds'] = const <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
                'charlie-peer',
              ]
              ..['readdedRemoveMembersAllowed'] = true
              ..['staleRemoveMembersAllowedAfterReadd'] = true
              ..remove('actualActionOutcome')
              ..['staleActionAttempted'] = false;
        invalid[0] = {
          ...invalid[0],
          'memberPeerIds': const <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
            'charlie-peer',
          ],
          'gm025RolePermissionReaddProof': aliceProof,
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm025',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: invalid,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'alice: GM-025 final memberPeerIds must not contain duplicates',
          ),
        );
        expect(
          rejected.detail,
          contains(
            'alice: gm025RolePermissionReaddProof.rawMemberPeerIds must not contain duplicates',
          ),
        );
        expect(
          rejected.detail,
          contains(
            'alice: gm025RolePermissionReaddProof.readdedRemoveMembersAllowed must be false',
          ),
        );
        expect(
          rejected.detail,
          contains(
            'alice: gm025RolePermissionReaddProof.staleRemoveMembersAllowedAfterReadd must be false',
          ),
        );
        expect(
          rejected.detail,
          contains(
            'alice: gm025RolePermissionReaddProof.staleActionAttempted must be true',
          ),
        );
        expect(
          rejected.detail,
          contains(
            'alice: gm025RolePermissionReaddProof.actualActionOutcome must be denied',
          ),
        );
      },
    );

    test('GM-033 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm033',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm033 role devices'));
    });

    test('GM-033 accepts replay-during-readd verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm033',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm033Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm033 verdicts valid'));
    });

    test('GM-033 rejects removed-window leak or missing replay proof', () {
      final invalid = _validGm033Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm033ReplayDuringMembershipUpdateProof'] as Map,
            )
            ..['staleRemovedWindowStoredForCharlie'] = false
            ..['replayStartedBeforeRemoval'] = false;
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm033ReplayDuringMembershipUpdateProof'] as Map,
            )
            ..['receivedRemovedWindowMessage'] = true
            ..['removedWindowPlaintextCount'] = 1
            ..['removedWindowMessageIdPersisted'] = true
            ..['replayResumed'] = false;
      invalid[0] = {
        ...invalid[0],
        'gm033ReplayDuringMembershipUpdateProof': aliceProof,
      };
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceGm033BeforeRemoval',
            'gm033-before',
            'gm033 before',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'aliceGm033RemovedWindow',
            'gm033-removed',
            'gm033 removed',
            'alice-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceGm033BeforeRemoval': 1,
          'aliceGm033RemovedWindow': 1,
        },
        'gm033ReplayDuringMembershipUpdateProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm033',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm033ReplayDuringMembershipUpdateProof.replayStartedBeforeRemoval must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm033ReplayDuringMembershipUpdateProof.staleRemovedWindowStoredForCharlie must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm033ReplayDuringMembershipUpdateProof.replayResumed must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm033ReplayDuringMembershipUpdateProof.receivedRemovedWindowMessage must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm033ReplayDuringMembershipUpdateProof.removedWindowPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm033ReplayDuringMembershipUpdateProof.removedWindowMessageIdPersisted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceGm033RemovedWindow',
        ),
      );
    });

    test('GM-034 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm034',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm034 role devices'));
    });

    test('GM-034 accepts config-update receive-order verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm034',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm034Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm034 verdicts valid'));
    });

    test('GM-034 rejects missing order proof or duplicate delivery', () {
      final invalid = _validGm034Verdicts();
      final bobProof =
          Map<String, Object?>.from(
              invalid[1]['gm034ConfigUpdateReceiveOrderProof'] as Map,
            )
            ..['messageThenConfigExactOnce'] = false
            ..['messageThenConfigPersistedCount'] = 2
            ..['deterministicConfigState'] = false
            ..['orderCases'] = const <String>['message_then_config'];
      invalid[1] = {
        ...invalid[1],
        'persistedMessageCounts': const <String, int>{
          'aliceGm034MessageThenConfig': 2,
          'aliceGm034ConfigThenMessage': 1,
        },
        'gm034ConfigUpdateReceiveOrderProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm034',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: persisted aliceGm034MessageThenConfig count=2; requires exactly one',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm034ConfigUpdateReceiveOrderProof.messageThenConfigExactOnce must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm034ConfigUpdateReceiveOrderProof.deterministicConfigState must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm034ConfigUpdateReceiveOrderProof.orderCases must match GM-034 delivery order cases',
        ),
      );
    });

    test('GM-035 maps Alice Bob Charlie role devices', () {
      final verdict = evaluateDeviceSelection(
        scenario: 'gm035',
        deviceIds: const <String>[
          'alice-device',
          'bob-device',
          'charlie-device',
        ],
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm035 role devices'));
    });

    test('GM-035 accepts zero-peer re-add first-send verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm035',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm035Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm035 verdicts valid'));
    });

    test('GM-035 rejects missing zero-topic or durable recipient proof', () {
      final invalid = _validGm035Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm035ZeroPeerReaddFirstSendProof'] as Map,
            )
            ..['initialTopicPeers'] = 1
            ..['actualDurablePayloadProof'] = false
            ..['recipientPeerIds'] = const <String>['alice-peer']
            ..['durableRecipientsUnique'] = false;
      final sentMessages =
          (invalid[2]['sentMessages'] as List<Map<String, Object?>>)
              .map((entry) => Map<String, Object?>.from(entry))
              .toList(growable: false);
      sentMessages[0]
        ..['topicPeers'] = 1
        ..['actualDurablePayloadProof'] = false;
      invalid[2] = {
        ...invalid[2],
        'sentMessages': sentMessages,
        'gm035ZeroPeerReaddFirstSendProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm035',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: sent charlieGm035FirstAfterReadd topicPeers must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: sent charlieGm035FirstAfterReadd must report actual durable payload proof',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm035ZeroPeerReaddFirstSendProof.initialTopicPeers must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm035ZeroPeerReaddFirstSendProof.actualDurablePayloadProof must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm035ZeroPeerReaddFirstSendProof.recipientPeerIds mismatch',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm035ZeroPeerReaddFirstSendProof.durableRecipientsUnique must be true',
        ),
      );
    });

    test('GM-035 rejects missing receiver drain or duplicate persistence', () {
      final invalid = _validGm035Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm035ZeroPeerReaddFirstSendProof'] as Map,
            )
            ..['durableDrainCompleted'] = false
            ..['postLiveDuplicatePersistedCount'] = 2
            ..['noDuplicatePersistence'] = false;
      invalid[0] = {
        ...invalid[0],
        'persistedMessageCounts': const <String, int>{
          'charlieGm035FirstAfterReadd': 2,
        },
        'gm035ZeroPeerReaddFirstSendProof': aliceProof,
      };
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm035',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: persisted charlieGm035FirstAfterReadd count=2; requires exactly one',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm035ZeroPeerReaddFirstSendProof.durableDrainCompleted must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm035ZeroPeerReaddFirstSendProof.postLiveDuplicatePersistedCount must be 1',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm035ZeroPeerReaddFirstSendProof.noDuplicatePersistence must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: received charlieGm035FirstAfterReadd count=0; requires exactly one receiver persistence',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: missing received proof keys charlieGm035FirstAfterReadd',
        ),
      );
    });

    test('rejects GM-017 missing A/B validation rejection proof', () {
      final invalid = _validGm017Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm017StaleSubscriptionValidationProof'] as Map,
            )
            ..['validationRejected'] = false
            ..['validationRejectCount'] = 0
            ..['validationRejectReason'] = 'missing';
      invalid[0] = {
        ...invalid[0],
        'gm017StaleSubscriptionValidationProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm017StaleSubscriptionValidationProof.validationRejected must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm017StaleSubscriptionValidationProof.validationRejectCount must be >= 1',
        ),
      );
    });

    test('rejects GM-017 Charlie not stale or leave path used', () {
      final invalid = _validGm017Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm017StaleSubscriptionValidationProof'] as Map,
            )
            ..['groupPresentAfterRemoval'] = false
            ..['keyPresentAfterRemoval'] = false
            ..['memberListStillIncludesCharlie'] = false
            ..['staleSubscriptionPresent'] = false
            ..['leaveRequested'] = true
            ..['leaveResponseOk'] = true;
      invalid[2] = {
        ...invalid[2],
        'memberPeerIds': const <String>[],
        'keyEpoch': 0,
        'gm017StaleSubscriptionValidationProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm017StaleSubscriptionValidationProof.groupPresentAfterRemoval must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm017StaleSubscriptionValidationProof.leaveRequested must be false',
        ),
      );
      expect(
        rejected.detail,
        contains('charlie: GM-017 stale memberPeerIds must include Charlie'),
      );
    });

    test('rejects GM-017 accepted stale Charlie plaintext', () {
      final invalid = _validGm017Verdicts();
      final bobProof =
          Map<String, Object?>.from(
              invalid[1]['gm017StaleSubscriptionValidationProof'] as Map,
            )
            ..['receivedStaleCharliePlaintext'] = true
            ..['stalePlaintextCount'] = 1;
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterStaleCharlieReject',
            'gm017-a-after',
            'alice after stale reject',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'charlieStaleAfterRemoval',
            'gm017-c-stale',
            'stale charlie after removal',
            'charlie-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterStaleCharlieReject': 1,
          'charlieStaleAfterRemoval': 1,
        },
        'gm017StaleSubscriptionValidationProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm017',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: gm017StaleSubscriptionValidationProof.receivedStaleCharliePlaintext must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm017StaleSubscriptionValidationProof.stalePlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: unexpected received proof keys charlieStaleAfterRemoval',
        ),
      );
    });

    test(
      'rejects GM-017 wrong scenario, role, or missing healthy delivery',
      () {
        final invalid = _validGm017Verdicts();
        invalid[2] = {...invalid[2], 'scenario': 'gm016'};
        invalid[1] = {
          ...invalid[1],
          'receivedMessages': const <Map<String, Object?>>[],
          'persistedMessageCounts': const <String, int>{},
        };
        invalid.add({...invalid[1], 'role': 'dana'});

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm017',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: invalid,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('dana: unexpected role for gm017'));
        expect(rejected.detail, contains('charlie: scenario mismatch gm016'));
        expect(
          rejected.detail,
          contains('bob: received aliceAfterStaleCharlieReject count=0'),
        );
      },
    );

    test('rejects GM-016 missing leave proof', () {
      final invalid = _validGm016Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm016RemovedUnsubscribeProof'] as Map,
            )
            ..['leaveRequested'] = false
            ..['leaveResponseOk'] = false;
      invalid[2] = {
        ...invalid[2],
        'gm016RemovedUnsubscribeProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.leaveRequested must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.leaveResponseOk must be true',
        ),
      );
    });

    test('rejects GM-016 post-leave events or plaintext leaks', () {
      final invalid = _validGm016Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm016RemovedUnsubscribeProof'] as Map,
            )
            ..['postLeaveInboundEventCount'] = 1
            ..['postLeaveDiscoveryEventCount'] = 1
            ..['postLeavePayloadParseFailedCount'] = 1
            ..['postLeaveDecryptionFailedCount'] = 1
            ..['postRemovalPlaintextCount'] = 1
            ..['receivedAlicePostRemoval'] = true;
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieUnsubscribe',
            'gm016-a-after',
            'alice after unsubscribe',
            'alice-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieUnsubscribe': 1,
        },
        'gm016RemovedUnsubscribeProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.postLeaveInboundEventCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.postLeaveDiscoveryEventCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.postRemovalPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof.receivedAlicePostRemoval must be false',
        ),
      );
    });

    test('rejects GM-016 missing quiet-window or A/B delivery proof', () {
      final invalid = _validGm016Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm016RemovedUnsubscribeProof'] as Map,
            )
            ..['postLeaveQuietWindowMs'] = 0
            ..['staleDiscoveryRegisterStimulus'] = false;
      final bobProof = Map<String, Object?>.from(
        invalid[1]['gm016RemovedUnsubscribeProof'] as Map,
      )..['receivedAlicePostRemoval'] = false;
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'gm016RemovedUnsubscribeProof': bobProof,
      };
      invalid[2] = {
        ...invalid[2],
        'gm016RemovedUnsubscribeProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm016',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received aliceAfterCharlieUnsubscribe count=0'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm016RemovedUnsubscribeProof.receivedAlicePostRemoval must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm016RemovedUnsubscribeProof requires staleDiscoveryRegisterStimulus or postLeaveQuietWindowMs >= 3000',
        ),
      );
    });

    test('rejects GM-015 writerless zombie state', () {
      final invalid = _validGm015Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm015AdminSelfRemovalPolicyProof'] as Map,
            )
            ..['adminPeerIds'] = const <String>[]
            ..['memberListHasActiveAdmin'] = false;
      invalid[0] = {
        ...invalid[0],
        'gm015AdminSelfRemovalPolicyProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: GM-015 writerless zombie group has no active admin'),
      );
    });

    test('rejects GM-015 ambiguous success and missing clear reasons', () {
      final invalid = _validGm015Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm015AdminSelfRemovalPolicyProof'] as Map,
            )
            ..['selfRemovalOutcome'] = 'success'
            ..['selfRemovalReason'] = ''
            ..['voluntaryLeaveBroadcastOutcome'] = 'success'
            ..['voluntaryLeaveBroadcastSkipReason'] = ''
            ..['leaveOutcome'] = 'success'
            ..['leaveReason'] = '';
      invalid[0] = {
        ...invalid[0],
        'gm015AdminSelfRemovalPolicyProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm015AdminSelfRemovalPolicyProof.selfRemovalOutcome must be blocked',
        ),
      );
      expect(
        rejected.detail,
        contains('alice: missing GM-015 clear self-removal block reason'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm015AdminSelfRemovalPolicyProof.leaveOutcome must be blocked',
        ),
      );
      expect(
        rejected.detail,
        contains('alice: missing GM-015 clear leave block reason'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm015AdminSelfRemovalPolicyProof.voluntaryLeaveBroadcastSkipReason must be lastAdmin',
        ),
      );
    });

    test(
      'rejects GM-015 stale admin, disappearance, dissolve, or mutation',
      () {
        final invalid = _validGm015Verdicts();
        final bobProof =
            Map<String, Object?>.from(
                invalid[1]['gm015AdminSelfRemovalPolicyProof'] as Map,
              )
              ..['groupPresent'] = false
              ..['groupDissolved'] = true
              ..['creatorPeerId'] = 'bob-peer'
              ..['adminPeerIds'] = const <String>['bob-peer']
              ..['mutationAfterBlockedAttempt'] = true
              ..['keyEpochUnchanged'] = false;
        invalid[1] = {
          ...invalid[1],
          'memberPeerIds': const <String>['bob-peer', 'charlie-peer'],
          'gm015AdminSelfRemovalPolicyProof': bobProof,
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm015',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: invalid,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('bob: GM-015 silent group disappearance after block'),
        );
        expect(
          rejected.detail,
          contains('bob: GM-015 unexpected dissolution after block'),
        );
        expect(
          rejected.detail,
          contains(
            'bob: GM-015 stale admin role; Alice must remain sole admin',
          ),
        );
        expect(
          rejected.detail,
          contains('bob: GM-015 membership mutated after blocked operation'),
        );
        expect(
          rejected.detail,
          contains('bob: GM-015 key epoch changed after blocked operation'),
        );
      },
    );

    test('rejects GM-015 missing post-attempt delivery', () {
      final invalid = _validGm015Verdicts();
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm015',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: received charlieAfterBlockedAdminLeave count=0'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: missing received proof keys charlieAfterBlockedAdminLeave',
        ),
      );
    });

    test('rejects GM-014 silent loss, stale state, leaks, and duplicates', () {
      final invalid = _validGm014Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              invalid[0]['gm014SimultaneousReaddSendProof'] as Map,
            )
            ..['receivedBobPostReadd'] = false
            ..['hasStaleEpochAfterCatchUp'] = true
            ..['finalEpoch'] = 1;
      invalid[0] = {
        ...invalid[0],
        'gm014SimultaneousReaddSendProof': aliceProof,
      };
      invalid[1] = {
        ...invalid[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };
      final charlieProof =
          Map<String, Object?>.from(
              invalid[2]['gm014SimultaneousReaddSendProof'] as Map,
            )
            ..['repairSignalRecorded'] = false
            ..['directPostReaddDecrypt'] = false
            ..['caughtUpPostReaddMessage'] = false
            ..['postReaddPersistedCount'] = 2
            ..['removedWindowPlaintextCount'] = 1
            ..['charlieMemberRowCount'] = 2
            ..['charlieActiveDeviceBindingCount'] = 2
            ..['duplicateTopicJoins'] = true
            ..['duplicateDurableRecipients'] = true;
      invalid[2] = {
        ...invalid[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterReadd',
            'gm014-a-after',
            'alice after readd',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterReadd',
            'gm014-a-after-duplicate',
            'alice after readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'aliceAfterReadd': 2},
        'gm014SimultaneousReaddSendProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: invalid,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm014SimultaneousReaddSendProof.receivedBobPostReadd must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm014SimultaneousReaddSendProof.hasStaleEpochAfterCatchUp must be false',
        ),
      );
      expect(
        rejected.detail,
        contains('bob: received aliceAfterReadd count=0'),
      );
      expect(
        rejected.detail,
        contains('charlie: received aliceAfterReadd count=2'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm014SimultaneousReaddSendProof requires repairSignalRecorded or directPostReaddDecrypt',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm014SimultaneousReaddSendProof.caughtUpPostReaddMessage must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm014SimultaneousReaddSendProof.removedWindowPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm014SimultaneousReaddSendProof.charlieMemberRowCount must be 1',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm014SimultaneousReaddSendProof.duplicateTopicJoins must be false',
        ),
      );
    });

    test('rejects GM-014 cross-role re-add timestamp drift', () {
      final drifted = _validGm014Verdicts();
      final bobProof = Map<String, Object?>.from(
        drifted[1]['gm014SimultaneousReaddSendProof'] as Map,
      );
      bobProof
        ..['readdAt'] = '2026-04-05T12:00:10.012Z'
        ..['charlieJoinedAt'] = '2026-04-05T12:00:10.012Z';
      drifted[1] = {...drifted[1], 'gm014SimultaneousReaddSendProof': bobProof};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm014',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: drifted,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'gm014SimultaneousReaddSendProof.readdAt must match one shared re-add timestamp across alice, bob, charlie',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'gm014SimultaneousReaddSendProof.charlieJoinedAt must match one shared re-add timestamp across alice, bob, charlie',
        ),
      );
    });

    test('rejects GM-013 missing or unordered boundary timestamps', () {
      final nondeterministic = _validGm013Verdicts();
      final aliceProof = Map<String, Object?>.from(
        nondeterministic[0]['gm013SimultaneousRemoveSendProof'] as Map,
      );
      aliceProof
        ..remove('removalCutoffAt')
        ..['beforeSentAt'] = '2026-04-05T12:00:00.000Z'
        ..['afterSentAt'] = '2026-04-05T11:59:59.999Z';
      nondeterministic[0] = {
        ...nondeterministic[0],
        'gm013SimultaneousRemoveSendProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: nondeterministic,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm013SimultaneousRemoveSendProof.removalCutoffAt must be a parseable timestamp',
        ),
      );
    });

    test('rejects GM-013 accept-after-cutoff proof', () {
      final acceptedAfter = _validGm013Verdicts();
      final bobProof =
          Map<String, Object?>.from(
              acceptedAfter[1]['gm013SimultaneousRemoveSendProof'] as Map,
            )
            ..['rejectedAfterCutoff'] = false
            ..['afterCutoffAccepted'] = true
            ..['afterCutoffPersistedCount'] = 1;
      acceptedAfter[1] = {
        ...acceptedAfter[1],
        'gm013SimultaneousRemoveSendProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedAfter,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: gm013SimultaneousRemoveSendProof.rejectedAfterCutoff must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm013SimultaneousRemoveSendProof.afterCutoffAccepted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm013SimultaneousRemoveSendProof.afterCutoffPersistedCount must be 0',
        ),
      );
    });

    test('rejects GM-013 reject-before-cutoff proof', () {
      final rejectedBefore = _validGm013Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              rejectedBefore[0]['gm013SimultaneousRemoveSendProof'] as Map,
            )
            ..['acceptedBeforeCutoff'] = false
            ..['beforeCutoffPersistedCount'] = 0;
      rejectedBefore[0] = {
        ...rejectedBefore[0],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'bobAfterCharlieRemove',
            'gm013-b-after',
            'bob after charlie remove',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'bobAfterCharlieRemove': 1,
        },
        'gm013SimultaneousRemoveSendProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: rejectedBefore,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: received charlieBeforeCutoff count=0'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm013SimultaneousRemoveSendProof.acceptedBeforeCutoff must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm013SimultaneousRemoveSendProof.beforeCutoffPersistedCount must be 1',
        ),
      );
    });

    test('rejects GM-013 missing clear after-cutoff event', () {
      final missingEvent = _validGm013Verdicts();
      final aliceProof =
          Map<String, Object?>.from(
              missingEvent[0]['gm013SimultaneousRemoveSendProof'] as Map,
            )
            ..['clearAfterCutoffRejectionEvent'] = false
            ..['afterCutoffRejectionReason'] = 'dropped';
      missingEvent[0] = {
        ...missingEvent[0],
        'gm013SimultaneousRemoveSendProof': aliceProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingEvent,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: gm013SimultaneousRemoveSendProof.clearAfterCutoffRejectionEvent must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm013SimultaneousRemoveSendProof.afterCutoffRejectionReason must be a clear removal rejection reason',
        ),
      );
    });

    test('rejects GM-013 missing or duplicate delivery', () {
      final missingDelivery = _validGm013Verdicts();
      missingDelivery[1] = {
        ...missingDelivery[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'charlieBeforeCutoff',
            'gm013-c-before',
            'charlie before cutoff',
            'charlie-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'charlieBeforeCutoff': 1},
      };

      final missingRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(missingRejected.ok, isFalse);
      expect(
        missingRejected.detail,
        contains('bob: received aliceAfterCharlieRemove count=0'),
      );

      final duplicateDelivery = _validGm013Verdicts();
      duplicateDelivery[1] = {
        ...duplicateDelivery[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'charlieBeforeCutoff',
            'gm013-c-before',
            'charlie before cutoff',
            'charlie-peer',
            keyEpoch: 1,
          ),
          _received(
            'charlieBeforeCutoff',
            'gm013-c-before-dup',
            'charlie before cutoff',
            'charlie-peer',
            keyEpoch: 1,
          ),
          _received(
            'aliceAfterCharlieRemove',
            'gm013-a-after',
            'alice after charlie remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'charlieBeforeCutoff': 2,
          'aliceAfterCharlieRemove': 1,
        },
      };

      final duplicateRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicateDelivery,
      );

      expect(duplicateRejected.ok, isFalse);
      expect(
        duplicateRejected.detail,
        contains('bob: received charlieBeforeCutoff count=2'),
      );
    });

    test('rejects GM-013 Alice/Bob membership or config rollback', () {
      final rollback = _validGm013Verdicts();
      final bobProof =
          Map<String, Object?>.from(
              rollback[1]['gm013SimultaneousRemoveSendProof'] as Map,
            )
            ..['memberListExcludesCharlie'] = false
            ..['validatorConfigExcludesCharlie'] = false;
      rollback[1] = {
        ...rollback[1],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
        'gm013SimultaneousRemoveSendProof': bobProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: rollback,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: post-removal membership still includes charlie'),
      );
      expect(
        rejected.detail,
        contains('bob: GM-013 final memberPeerIds must exclude Charlie'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: gm013SimultaneousRemoveSendProof.validatorConfigExcludesCharlie must be true',
        ),
      );
    });

    test('rejects GM-013 Charlie post-removal plaintext or accepted send', () {
      final charlieLeak = _validGm013Verdicts();
      final charlieProof =
          Map<String, Object?>.from(
              charlieLeak[2]['gm013SimultaneousRemoveSendProof'] as Map,
            )
            ..['postRemovalSendOutcome'] = 'success'
            ..['postRemovalPublishAccepted'] = true
            ..['receivedAlicePostRemoval'] = true
            ..['postRemovalPlaintextCount'] = 1;
      charlieLeak[2] = {
        ...charlieLeak[2],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'charlieBeforeCutoff',
            'messageId': 'gm013-c-before',
            'text': 'charlie before cutoff',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 1,
            'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
          },
          {
            'key': 'charlieAfterCharlieRemove',
            'messageId': 'gm013-c-after-remove',
            'text': 'charlie after charlie remove',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 1,
            'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
          },
        ],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieRemove',
            'gm013-a-after',
            'alice after charlie remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieRemove': 1,
        },
        'gm013SimultaneousRemoveSendProof': charlieProof,
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm013',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: charlieLeak,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceAfterCharlieRemove',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm013SimultaneousRemoveSendProof.postRemovalPublishAccepted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm013SimultaneousRemoveSendProof.postRemovalSendOutcome must be rejected',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm013SimultaneousRemoveSendProof.postRemovalPlaintextCount must be 0',
        ),
      );
    });

    test('rejects GM-012 missing stale remove re-add proof', () {
      final missingProof = _validGm012Verdicts();
      missingProof[0] = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm012StaleRemoveReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing GM-012 stale remove re-add proof fields'),
      );
    });

    test('rejects GM-012 stale remove stranding or config rollback', () {
      final stranded = _validGm012Verdicts();
      stranded[0] = {
        ...stranded[0],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'gm012StaleRemoveReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stranded[0]['gm012StaleRemoveReaddProof'] as Map,
          ),
          'staleRemoveIgnored': false,
          'memberListIncludesCharlie': false,
          'validatorConfigIncludesCharlie': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stranded,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: incomplete membership convergence'),
      );
      expect(
        rejected.detail,
        contains(
          'alice: GM-012 final memberPeerIds must contain Charlie exactly once',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm012StaleRemoveReaddProof.staleRemoveIgnored must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'alice: gm012StaleRemoveReaddProof.validatorConfigIncludesCharlie must be true',
        ),
      );
    });

    test('rejects GM-012 duplicate Charlie member or device binding', () {
      final duplicateState = _validGm012Verdicts();
      duplicateState[1] = {
        ...duplicateState[1],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
          'charlie-peer',
        ],
        'gm012StaleRemoveReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            duplicateState[1]['gm012StaleRemoveReaddProof'] as Map,
          ),
          'charlieMemberRowCount': 2,
          'charlieActiveDeviceBindingCount': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicateState,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'GM-012 final memberPeerIds must contain Charlie exactly once',
        ),
      );
      expect(rejected.detail, contains('charlieMemberRowCount must be 1'));
      expect(
        rejected.detail,
        contains('charlieActiveDeviceBindingCount must be 1'),
      );
    });

    test('rejects GM-012 stale durable recipients or missing delivery', () {
      final missingDelivery = _validGm012Verdicts();
      missingDelivery[0] = {
        ...missingDelivery[0],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceAfterStaleRemove',
            'messageId': 'gm012-a-after',
            'text': 'alice after stale remove',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>['bob-peer'],
          },
        ],
      };
      missingDelivery[2] = {
        ...missingDelivery[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'bobAfterStaleRemove',
            'gm012-b-after',
            'bob after stale remove',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'bobAfterStaleRemove': 1},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: sent aliceAfterStaleRemove recipientPeerIds mismatch'),
      );
      expect(
        rejected.detail,
        contains('charlie: received aliceAfterStaleRemove count=0'),
      );
    });

    test('rejects GM-012 false proof fields and stale key rollback', () {
      final staleKey = _validGm012Verdicts();
      staleKey[2] = {
        ...staleKey[2],
        'gm012StaleRemoveReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleKey[2]['gm012StaleRemoveReaddProof'] as Map,
          ),
          'postReaddPublishAccepted': false,
          'hasStaleEpochAfterStaleRemove': true,
          'removedWindowPlaintextCount': 1,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleKey,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: gm012StaleRemoveReaddProof.postReaddPublishAccepted must be true',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm012StaleRemoveReaddProof.hasStaleEpochAfterStaleRemove must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm012StaleRemoveReaddProof.removedWindowPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains('charlie: gm012StaleRemoveReaddProof.finalEpoch must be >= 2'),
      );
    });

    test('rejects GM-012 role mismatch and non-GM-012 scenario names', () {
      final duplicate = _validGm012Verdicts();
      duplicate[2] = {...duplicate[2], 'role': 'bob'};

      final duplicateRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicate,
      );

      expect(duplicateRejected.ok, isFalse);
      expect(duplicateRejected.detail, contains('bob: duplicate role verdict'));

      final mismatched = _validGm012Verdicts();
      mismatched[2] = {...mismatched[2], 'scenario': 'gm011'};

      final mismatchRejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm012',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: mismatched,
      );

      expect(mismatchRejected.ok, isFalse);
      expect(
        mismatchRejected.detail,
        contains('charlie: scenario mismatch gm011'),
      );
    });

    test('rejects GM-011 missing stale add removal proof', () {
      final missingProof = _validGm011Verdicts();
      missingProof[0] = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm011StaleAddRemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing GM-011 stale add removal proof fields'),
      );
    });

    test('rejects GM-011 stale add resurrection or old key acceptance', () {
      final resurrected = _validGm011Verdicts();
      resurrected[0] = {
        ...resurrected[0],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
        'gm011StaleAddRemovalProof': <String, Object?>{
          ...resurrected[0]['gm011StaleAddRemovalProof'] as Map,
          'staleAddIgnored': false,
          'memberListExcludesCharlie': false,
        },
      };
      resurrected[2] = {
        ...resurrected[2],
        'gm011StaleAddRemovalProof': <String, Object?>{
          ...resurrected[2]['gm011StaleAddRemovalProof'] as Map,
          'hasOldKeyAfterStaleAdd': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: resurrected,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: post-removal membership still includes charlie'),
      );
      expect(
        rejected.detail,
        contains('alice: GM-011 final memberPeerIds must exclude Charlie'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm011StaleAddRemovalProof.hasOldKeyAfterStaleAdd must be false',
        ),
      );
    });

    test('rejects GM-011 Charlie post-removal leak or publish', () {
      final leaked = _validGm011Verdicts();
      leaked[2] = {
        ...leaked[2],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'charlieAfterStaleAdd',
            'messageId': 'gm011-c-after',
            'text': 'charlie after stale add',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 1,
          },
        ],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterStaleAdd',
            'gm011-a-after',
            'alice after stale add',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'aliceAfterStaleAdd': 1},
        'gm011StaleAddRemovalProof': <String, Object?>{
          ...leaked[2]['gm011StaleAddRemovalProof'] as Map,
          'postRemovalSendOutcome': 'success',
          'postRemovalPublishAccepted': true,
          'receivedAlicePostStaleAdd': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: unexpected received proof keys aliceAfterStaleAdd'),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm011StaleAddRemovalProof.postRemovalPublishAccepted must be false',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: gm011StaleAddRemovalProof.postRemovalPlaintextCount must be 0',
        ),
      );
    });

    test('rejects GM-011 stale durable recipients or missing A/B delivery', () {
      final staleRecipients = _validGm011Verdicts();
      staleRecipients[0] = {
        ...staleRecipients[0],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceAfterStaleAdd',
            'messageId': 'gm011-a-after',
            'text': 'alice after stale add',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
          },
        ],
      };
      staleRecipients[1] = {
        ...staleRecipients[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleRecipients,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: sent aliceAfterStaleAdd recipientPeerIds mismatch'),
      );
      expect(
        rejected.detail,
        contains('bob: received aliceAfterStaleAdd count=0'),
      );
    });

    test('rejects GM-011 duplicate role verdict', () {
      final duplicate = _validGm011Verdicts();
      duplicate[2] = {...duplicate[2], 'role': 'bob'};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicate,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bob: duplicate role verdict'));
    });

    test('rejects GM-011 non-GM-011 role scenario names', () {
      final mismatched = _validGm011Verdicts();
      mismatched[2] = {...mismatched[2], 'scenario': 'gm010'};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm011',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: mismatched,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('charlie: scenario mismatch gm010'));
    });

    test('rejects GM-010 missing duplicate re-add proof', () {
      final missingProof = _validGm010Verdicts();
      missingProof[0] = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm010DuplicateReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing GM-010 duplicate re-add proof fields'),
      );
    });

    test('rejects GM-010 duplicate Charlie row, device, or config join', () {
      final duplicateState = _validGm010Verdicts();
      duplicateState[0] = {
        ...duplicateState[0],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
          'charlie-peer',
        ],
        'gm010DuplicateReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            duplicateState[0]['gm010DuplicateReaddProof'] as Map,
          ),
          'charlieMemberRowCount': 2,
          'charlieActiveDeviceBindingCount': 2,
          'charlieGroupConfigJoinCountAfterReadd': 2,
          'duplicateReaddTriggeredCharlieGroupConfigJoin': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicateState,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('final memberPeerIds must contain Charlie exactly once'),
      );
      expect(rejected.detail, contains('charlieMemberRowCount must be 1'));
      expect(
        rejected.detail,
        contains('charlieActiveDeviceBindingCount must be 1'),
      );
      expect(
        rejected.detail,
        contains('charlieGroupConfigJoinCountAfterReadd must be 1'),
      );
      expect(
        rejected.detail,
        contains('duplicateReaddTriggeredCharlieGroupConfigJoin must be false'),
      );
    });

    test('rejects GM-010 duplicate durable inbox recipients', () {
      final duplicateRecipients = _validGm010Verdicts();
      duplicateRecipients[2] = {
        ...duplicateRecipients[2],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'charlieAfterDuplicateReadd',
            'messageId': 'gm010-c-after',
            'text': 'charlie after duplicate readd',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 2,
            'recipientPeerIds': <String>['alice-peer', 'bob-peer', 'bob-peer'],
          },
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicateRecipients,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: sent charlieAfterDuplicateReadd recipientPeerIds contain duplicates',
        ),
      );
    });

    test('rejects GM-010 missing post-readd delivery and convergence', () {
      final missingDelivery = _validGm010Verdicts();
      missingDelivery[1] = {
        ...missingDelivery[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterDuplicateReadd',
            'gm010-a-after',
            'alice after duplicate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterDuplicateReadd': 1,
        },
        'gm010DuplicateReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[1]['gm010DuplicateReaddProof'] as Map,
          ),
          'memberListIncludesCharlie': false,
          'receivedCharliePostReaddMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm010',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys charlieAfterDuplicateReadd'),
      );
      expect(
        rejected.detail,
        contains('receivedCharliePostReaddMessage must be true'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: incomplete membership convergence, missing charlie-peer',
        ),
      );
    });

    test('rejects missing role verdicts and sender-only evidence', () {
      final missingCharlie = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm001Verdicts().take(2).toList(growable: false),
      );

      expect(missingCharlie.ok, isFalse);
      expect(missingCharlie.detail, contains('charlie: missing role verdict'));

      final senderOnly = _validGm001Verdicts();
      senderOnly[1] = {
        ...senderOnly[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: senderOnly,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('bob: received aliceInitial count=0'));
    });

    test('rejects duplicate receiver messages', () {
      final duplicate = _validGm001Verdicts();
      duplicate[1] = {
        ...duplicate[1],
        'receivedMessages': [
          _received('aliceInitial', 'gm001-a1', 'hello', 'alice-peer'),
          _received('aliceInitial', 'gm001-a1-dup', 'hello', 'alice-peer'),
        ],
        'persistedMessageCounts': {'aliceInitial': 2},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicate,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('requires exactly one receiver persistence'),
      );
    });

    test('rejects receiver message id that differs from sender tuple', () {
      final wrongMessageId = _validGm001Verdicts();
      wrongMessageId[1] = {
        ...wrongMessageId[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceInitial',
            'wrong-message-id',
            'hello gm001',
            'alice-peer',
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongMessageId,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('messageId mismatch'));
    });

    test('rejects receiver text that differs from sender tuple', () {
      final wrongText = _validGm001Verdicts();
      wrongText[1] = {
        ...wrongText[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceInitial',
            'gm001-a1',
            'wrong plaintext',
            'alice-peer',
          ),
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongText,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('text mismatch'));
    });

    test('rejects receiver key epoch that differs from sender verdict', () {
      final wrongEpoch = _validGm001Verdicts();
      wrongEpoch[1] = {...wrongEpoch[1], 'keyEpoch': 2};

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: wrongEpoch,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('keyEpoch mismatch'));
    });

    test('rejects incomplete GM-002 membership convergence', () {
      final incomplete = _validGm002Verdicts();
      incomplete[2] = {
        ...incomplete[2],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm002',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: incomplete,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('incomplete membership convergence'));
    });

    test('rejects GM-003 pre-add leakage to Dana', () {
      final leaked = _validGm003Verdicts();
      leaked[3] = {
        ...leaked[3],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeDanaAdd',
            'gm003-a-before',
            'alice before dana',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'aliceAfterDanaOfflineAdd',
            'gm003-a-after',
            'alice after offline dana add',
            'alice-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeDanaAdd': 1,
          'aliceAfterDanaOfflineAdd': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: unexpected received proof keys aliceBeforeDanaAdd'),
      );
    });

    test('rejects GM-003 missing Dana post-add catch-up', () {
      final missingCatchUp = _validGm003Verdicts();
      missingCatchUp[3] = {
        ...missingCatchUp[3],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingCatchUp,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: missing received proof keys aliceAfterDanaOfflineAdd'),
      );
    });

    test('rejects GM-003 missing Dana send-after-join', () {
      final missingDanaSend = _validGm003Verdicts();
      missingDanaSend[3] = {
        ...missingDanaSend[3],
        'sentMessages': const <Map<String, Object?>>[],
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDanaSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('dana: sent danaAfterOfflineJoin count=0'),
      );
    });

    test('rejects GM-003 duplicate receiver persistence', () {
      final duplicate = _validGm003Verdicts();
      duplicate[1] = {
        ...duplicate[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeDanaAdd',
            'gm003-a-before',
            'alice before dana',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'aliceAfterDanaOfflineAdd',
            'gm003-a-after',
            'alice after offline dana add',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'aliceAfterDanaOfflineAdd',
            'gm003-a-after-dup',
            'alice after offline dana add',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'danaAfterOfflineJoin',
            'gm003-d-after',
            'dana after offline join',
            'dana-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeDanaAdd': 1,
          'aliceAfterDanaOfflineAdd': 2,
          'danaAfterOfflineJoin': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicate,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('requires exactly one receiver persistence'),
      );
    });

    test('rejects GM-003 missing offline/catch-up proof fields', () {
      final missingProof = _validGm003Verdicts();
      missingProof[0] = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm003OfflineAddProof');
      missingProof[3] = Map<String, dynamic>.from(missingProof[3])
        ..remove('gm003OfflineCatchUpProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm003',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing GM-003 offline add proof fields'),
      );
      expect(
        rejected.detail,
        contains('dana: missing GM-003 offline catch-up proof fields'),
      );
    });

    test('rejects GM-004 missing Charlie removal proof', () {
      final missingProof = _validGm004Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('gm004RemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing GM-004 removal proof fields'),
      );
    });

    test('rejects GM-004 Charlie post-removal plaintext', () {
      final leaked = _validGm004Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieRemove',
            'gm004-a-after',
            'alice after charlie remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieRemove': 1,
        },
        'gm004RemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(leaked[2]['gm004RemovalProof'] as Map),
          'receivedAliceAfterRemoval': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceAfterCharlieRemove',
        ),
      );
    });

    test('rejects GM-004 missing A/B post-removal delivery', () {
      final missingBobDelivery = _validGm004Verdicts();
      missingBobDelivery[1] = {
        ...missingBobDelivery[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingBobDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceAfterCharlieRemove'),
      );
    });

    test('rejects GM-004 successful Charlie post-removal send', () {
      final acceptedSend = _validGm004Verdicts();
      acceptedSend[2] = {
        ...acceptedSend[2],
        'gm004RemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            acceptedSend[2]['gm004RemovalProof'] as Map,
          ),
          'postRemovalSendOutcome': 'success',
          'postRemovalPublishAccepted': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('postRemovalPublishAccepted must be false'),
      );
      expect(
        rejected.detail,
        contains('postRemovalSendOutcome must reject send'),
      );
    });

    test('rejects GM-004 rotated epoch evidence on Charlie', () {
      final leakedKey = _validGm004Verdicts();
      leakedKey[2] = {
        ...leakedKey[2],
        'keyEpoch': 2,
        'gm004RemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leakedKey[2]['gm004RemovalProof'] as Map,
          ),
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leakedKey,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('hasRotatedEpoch must be false'));
      expect(rejected.detail, contains('must not hold rotated epoch'));
    });

    test('rejects private_online_remove without ML-005 proof fields', () {
      final missingProof = _validPrivateOnlineRemoveVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml005OnlineRemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-005 online-removal proof fields'),
      );
    });

    test('rejects private_online_remove Charlie post-removal plaintext', () {
      final leaked = _validPrivateOnlineRemoveVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieRemove',
            'ml005-a-after',
            'alice after charlie remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieRemove': 1,
        },
        'ml005OnlineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml005OnlineRemovalProof'] as Map,
          ),
          'receivedAliceAfterRemoval': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceAfterCharlieRemove',
        ),
      );
      expect(rejected.detail, contains('postRemovalPlaintextCount must be 0'));
    });

    test('rejects private_online_remove missing A/B post-removal delivery', () {
      final missingBobDelivery = _validPrivateOnlineRemoveVerdicts();
      missingBobDelivery[1] = {
        ...missingBobDelivery[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ml005OnlineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingBobDelivery[1]['ml005OnlineRemovalProof'] as Map,
          ),
          'receivedAliceAfterRemoval': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingBobDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceAfterCharlieRemove'),
      );
      expect(
        rejected.detail,
        contains('bob: ml005OnlineRemovalProof.receivedAliceAfterRemoval'),
      );
    });

    test(
      'rejects private_online_remove successful Charlie post-removal send',
      () {
        final acceptedSend = _validPrivateOnlineRemoveVerdicts();
        acceptedSend[2] = {
          ...acceptedSend[2],
          'ml005OnlineRemovalProof': <String, Object?>{
            ...Map<String, Object?>.from(
              acceptedSend[2]['ml005OnlineRemovalProof'] as Map,
            ),
            'postRemovalSendOutcome': 'success',
            'postRemovalPublishAccepted': true,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_online_remove',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: acceptedSend,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('postRemovalPublishAccepted must be false'),
        );
        expect(
          rejected.detail,
          contains('postRemovalSendOutcome must reject send'),
        );
      },
    );

    test('rejects private_online_remove without KE-006 key proof fields', () {
      final missingProof = _validPrivateOnlineRemoveVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ke006RemovalKeyRotationProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing KE-006 removal-key proof fields'),
      );
    });

    test('rejects private_online_remove Charlie retaining KE-006 key', () {
      final retainedKey = _validPrivateOnlineRemoveVerdicts();
      retainedKey[2] = {
        ...retainedKey[2],
        'keyEpoch': 2,
        'ke006RemovalKeyRotationProof': <String, Object?>{
          ...Map<String, Object?>.from(
            retainedKey[2]['ke006RemovalKeyRotationProof'] as Map,
          ),
          'hasRotatedEpoch': true,
          'retainedEpochAfterRemoval': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: retainedKey,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('hasRotatedEpoch must be false'));
      expect(
        rejected.detail,
        contains('retainedEpochAfterRemoval must stay below rotated epoch'),
      );
    });

    test('rejects private_offline_remove without ML-006 proof fields', () {
      final missingProof = _validPrivateOfflineRemoveVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml006OfflineRemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-006 offline removal proof fields'),
      );
    });

    test('rejects private_offline_remove without IR-004 proof fields', () {
      final missingProof = _validPrivateOfflineRemoveVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ir004PostRemovalReplayProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing IR-004 post-removal replay proof fields'),
      );
    });

    test('rejects IR-004 proof when Charlie receives post-removal plaintext', () {
      final leaked = _validPrivateOfflineRemoveVerdicts();
      leaked[2] = {
        ...leaked[2],
        'ir004PostRemovalReplayProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ir004PostRemovalReplayProof'] as Map,
          ),
          'postRemovalPlaintextCount': 1,
          'receivedAlicePostRemoval': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: ir004PostRemovalReplayProof.postRemovalPlaintextCount must be 0',
        ),
      );
      expect(
        rejected.detail,
        contains('receivedAlicePostRemoval must be false'),
      );
    });

    test('rejects private_offline_remove Charlie post-removal plaintext', () {
      final leaked = _validPrivateOfflineRemoveVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieOfflineRemove',
            'ml006-a-after',
            'alice after offline charlie remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieOfflineRemove': 1,
        },
        'ml006OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml006OfflineRemovalProof'] as Map,
          ),
          'receivedAliceAfterRemoval': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceAfterCharlieOfflineRemove',
        ),
      );
      expect(rejected.detail, contains('postRemovalPlaintextCount must be 0'));
    });

    test('rejects private_offline_remove accepted Charlie send', () {
      final acceptedSend = _validPrivateOfflineRemoveVerdicts();
      acceptedSend[2] = {
        ...acceptedSend[2],
        'ml006OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            acceptedSend[2]['ml006OfflineRemovalProof'] as Map,
          ),
          'postRemovalSendOutcome': 'success',
          'postRemovalPublishAccepted': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('postRemovalPublishAccepted must be false'),
      );
      expect(
        rejected.detail,
        contains('postRemovalSendOutcome must reject send'),
      );
    });

    test('rejects private_offline_remove missing A/B delivery', () {
      final missingDelivery = _validPrivateOfflineRemoveVerdicts();
      missingDelivery[0] = {
        ...missingDelivery[0],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ml006OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[0]['ml006OfflineRemovalProof'] as Map,
          ),
          'receivedBobAfterRemoval': false,
        },
      };
      missingDelivery[1] = {
        ...missingDelivery[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ml006OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[1]['ml006OfflineRemovalProof'] as Map,
          ),
          'receivedAliceAfterRemoval': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: missing received proof keys bobAfterCharlieOfflineRemove',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'bob: missing received proof keys aliceAfterCharlieOfflineRemove',
        ),
      );
      expect(rejected.detail, contains('receivedBobAfterRemoval'));
      expect(rejected.detail, contains('receivedAliceAfterRemoval'));
    });

    test(
      'rejects private_offline_remove missing stale reconnect and drain proof',
      () {
        final missingCatchUp = _validPrivateOfflineRemoveVerdicts();
        missingCatchUp[2] = {
          ...missingCatchUp[2],
          'ml006OfflineRemovalProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingCatchUp[2]['ml006OfflineRemovalProof'] as Map,
            ),
            'reconnectedWithStaleState': false,
            'retrievedInboxAfterReconnect': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_offline_remove',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingCatchUp,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('reconnectedWithStaleState must be true'),
        );
        expect(
          rejected.detail,
          contains('retrievedInboxAfterReconnect must be true'),
        );
      },
    );

    test('rejects private_offline_remove Charlie retaining rotated epoch', () {
      final leakedKey = _validPrivateOfflineRemoveVerdicts();
      leakedKey[2] = {
        ...leakedKey[2],
        'keyEpoch': 2,
        'ml006OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leakedKey[2]['ml006OfflineRemovalProof'] as Map,
          ),
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leakedKey,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('hasRotatedEpoch must be false'));
      expect(rejected.detail, contains('must not hold rotated epoch'));
    });

    test('rejects GM-005 missing Charlie stale-offline proof', () {
      final missingProof = _validGm005Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('gm005OfflineRemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing GM-005 offline removal proof fields'),
      );
    });

    test('rejects GM-005 Charlie post-removal plaintext', () {
      final leaked = _validGm005Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieOfflineRemove1',
            'gm005-a-after-1',
            'alice after offline charlie remove 1',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieOfflineRemove1': 1,
        },
        'gm005OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['gm005OfflineRemovalProof'] as Map,
          ),
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceAfterCharlieOfflineRemove1',
        ),
      );
      expect(rejected.detail, contains('postRemovalPlaintextCount must be 0'));
    });

    test('rejects GM-005 Charlie accepted post-removal send', () {
      final acceptedSend = _validGm005Verdicts();
      acceptedSend[2] = {
        ...acceptedSend[2],
        'gm005OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            acceptedSend[2]['gm005OfflineRemovalProof'] as Map,
          ),
          'postRemovalSendOutcome': 'success',
          'postRemovalPublishAccepted': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('postRemovalPublishAccepted must be false'),
      );
      expect(
        rejected.detail,
        contains('postRemovalSendOutcome must reject send'),
      );
    });

    test('rejects GM-005 Charlie retaining rotated epoch', () {
      final leakedKey = _validGm005Verdicts();
      leakedKey[2] = {
        ...leakedKey[2],
        'keyEpoch': 2,
        'gm005OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leakedKey[2]['gm005OfflineRemovalProof'] as Map,
          ),
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leakedKey,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('hasRotatedEpoch must be false'));
      expect(rejected.detail, contains('must not hold rotated epoch'));
    });

    test('rejects GM-005 Bob missing an Alice post-removal message', () {
      final missingDelivery = _validGm005Verdicts();
      missingDelivery[1] = {
        ...missingDelivery[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieOfflineRemove1',
            'gm005-a-after-1',
            'alice after offline charlie remove 1',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterCharlieOfflineRemove2',
            'gm005-a-after-2',
            'alice after offline charlie remove 2',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieOfflineRemove1': 1,
          'aliceAfterCharlieOfflineRemove2': 1,
        },
        'gm005OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[1]['gm005OfflineRemovalProof'] as Map,
          ),
          'receivedAllAlicePostRemovalMessages': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: missing received proof keys aliceAfterCharlieOfflineRemove3',
        ),
      );
      expect(
        rejected.detail,
        contains('receivedAllAlicePostRemovalMessages must be true'),
      );
    });

    test('rejects GM-005 missing reconnect and inbox retrieval proof', () {
      final missingCatchUp = _validGm005Verdicts();
      missingCatchUp[2] = {
        ...missingCatchUp[2],
        'gm005OfflineRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingCatchUp[2]['gm005OfflineRemovalProof'] as Map,
          ),
          'reconnectedWithStaleState': false,
          'retrievedInboxAfterReconnect': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingCatchUp,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('reconnectedWithStaleState must be true'),
      );
      expect(
        rejected.detail,
        contains('retrievedInboxAfterReconnect must be true'),
      );
    });

    test('rejects GM-006 missing immediate re-add proof', () {
      final missingProof = _validGm006Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('gm006ImmediateReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing GM-006 immediate re-add proof fields'),
      );
    });

    test('rejects private_readd_current without ML-007 proof fields', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml007ReaddCurrentProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-007 re-add current proof fields'),
      );
    });

    test('rejects private_readd_current without RA-002 proof fields', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ra002OnlineSubscribedReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing RA-002 online re-add proof fields'),
      );
    });

    test('rejects private_readd_current RA-002 removed-window leakage', () {
      final leaked = _validPrivateReaddCurrentVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'ml007-a-during',
            'alice during charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'ml007-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'bobAfterReaddCurrent',
            'ml007-b-after',
            'bob after readd current',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
          'bobAfterReaddCurrent': 1,
        },
        'ra002OnlineSubscribedReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ra002OnlineSubscribedReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ra002OnlineSubscribedReaddProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test('rejects private_offline_readd without RA-003 proof fields', () {
      final missingProof = _validPrivateOfflineReaddVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ra003OfflineReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing RA-003 offline re-add proof fields'),
      );
    });

    test('rejects private_offline_readd RA-003 removed-window leakage', () {
      final leaked = _validPrivateOfflineReaddVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'ra003-a-during',
            'alice during offline charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'ra003-a-after',
            'alice after offline readd',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'bobAfterOfflineReadd',
            'ra003-b-after',
            'bob after offline readd',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
          'bobAfterOfflineReadd': 1,
        },
        'ra003OfflineReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ra003OfflineReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ra003OfflineReaddProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test('rejects private_readd_current without KE-008 activation proof', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ke008ReaddActivationProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing KE-008 re-add activation proof fields'),
      );
    });

    test(
      'rejects private_readd_current Charlie rejoin without current key',
      () {
        final staleActivation = _validPrivateReaddCurrentVerdicts();
        staleActivation[2] = {
          ...staleActivation[2],
          'keyEpoch': 1,
          'ke008ReaddActivationProof': <String, Object?>{
            ...Map<String, Object?>.from(
              staleActivation[2]['ke008ReaddActivationProof'] as Map,
            ),
            'importedCurrentEpochBeforeRejoinAck': false,
            'epochBeforeRejoinAck': 1,
            'hasCurrentEpochBeforePostReaddPublish': false,
            'postReaddPublishEpoch': 1,
            'hasStaleEpochAfterReadd': true,
            'finalEpoch': 1,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: staleActivation,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('importedCurrentEpochBeforeRejoinAck must be true'),
        );
        expect(
          rejected.detail,
          contains('hasCurrentEpochBeforePostReaddPublish must be true'),
        );
        expect(
          rejected.detail,
          contains('hasStaleEpochAfterReadd must be false'),
        );
        expect(
          rejected.detail,
          contains(
            'charlie: ke008ReaddActivationProof.finalEpoch must be >= 2',
          ),
        );
      },
    );

    test(
      'rejects private_readd_current without KE-010 key-before-config proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ke010KeyBeforeConfigProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing KE-010 key-before-config proof fields'),
        );
      },
    );

    test('rejects private_readd_current KE-010 pre-config plaintext leak', () {
      final leaked = _validPrivateReaddCurrentVerdicts();
      leaked[2] = {
        ...leaked[2],
        'ke010KeyBeforeConfigProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ke010KeyBeforeConfigProof'] as Map,
          ),
          'noPreConfigPlaintextDespiteKey': false,
          'receivedBobPostConfigAtCurrentEpoch': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('noPreConfigPlaintextDespiteKey must be true'),
      );
      expect(
        rejected.detail,
        contains('receivedBobPostConfigAtCurrentEpoch must be true'),
      );
    });

    test(
      'rejects private_readd_current without KE-011 delayed old key proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ke011DelayedOldKeyAfterReaddProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing KE-011 delayed old key proof fields'),
        );
      },
    );

    test('rejects private_readd_current KE-011 Charlie downgrade', () {
      final downgraded = _validPrivateReaddCurrentVerdicts();
      downgraded[2] = {
        ...downgraded[2],
        'keyEpoch': 1,
        'ke011DelayedOldKeyAfterReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            downgraded[2]['ke011DelayedOldKeyAfterReaddProof'] as Map,
          ),
          'keptCurrentEpochAfterDelayedOldKey': false,
          'storedDelayedOldKeyAsHistorical': false,
          'epochAfterDelayedOldKey': 1,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: downgraded,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('keptCurrentEpochAfterDelayedOldKey must be true'),
      );
      expect(rejected.detail, contains('epochAfterDelayedOldKey must be >= 2'));
    });

    test(
      'rejects private_readd_current without RA-006 delayed old key proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra006DelayedOldKeyAfterReaddProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing RA-006 delayed old key proof fields'),
        );
      },
    );

    test('rejects private_readd_current RA-006 Charlie downgrade', () {
      final downgraded = _validPrivateReaddCurrentVerdicts();
      downgraded[2] = {
        ...downgraded[2],
        'keyEpoch': 1,
        'ra006DelayedOldKeyAfterReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            downgraded[2]['ra006DelayedOldKeyAfterReaddProof'] as Map,
          ),
          'keptCurrentEpochAfterDelayedOldKey': false,
          'storedDelayedOldKeyAsHistorical': false,
          'epochAfterDelayedOldKey': 1,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: downgraded,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('keptCurrentEpochAfterDelayedOldKey must be true'),
      );
      expect(rejected.detail, contains('epochAfterDelayedOldKey must be >= 2'));
    });

    test('rejects private_readd_current without RA-007 observer proof', () {
      final missingProof = _validPrivateReaddCurrentVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ra007PartitionedObserverReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing RA-007 partitioned observer proof fields'),
      );
    });

    test('rejects private_readd_current RA-007 Bob non-convergence', () {
      final nonConverged = _validPrivateReaddCurrentVerdicts();
      nonConverged[1] = {
        ...nonConverged[1],
        'memberPeerIds': <String>['alice-peer', 'bob-peer'],
        'ra007PartitionedObserverReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            nonConverged[1]['ra007PartitionedObserverReaddProof'] as Map,
          ),
          'observedCharlieReadded': false,
          'receivedCharliePostHealAtCurrentEpoch': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: nonConverged,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('observedCharlieReadded must be true'));
      expect(
        rejected.detail,
        contains('receivedCharliePostHealAtCurrentEpoch must be true'),
      );
    });

    test(
      'rejects private_readd_current without RA-008 removed peer partition proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra008PartitionedRemovedReaddProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'charlie: missing RA-008 removed peer partition proof fields',
          ),
        );
      },
    );

    test('rejects private_readd_current RA-008 removed-window leakage', () {
      final leaked = _validPrivateReaddCurrentVerdicts();
      leaked[2] = {
        ...leaked[2],
        'ra008PartitionedRemovedReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ra008PartitionedRemovedReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: ra008PartitionedRemovedReaddProof.removedWindowPlaintextCount must be 0',
        ),
      );
    });

    test(
      'rejects private_readd_current without RA-009 first publish proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[1] = Map<String, dynamic>.from(missingProof[1])
          ..remove('ra009FirstReaddPublishProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('bob: missing RA-009 first re-add publish proof fields'),
        );
      },
    );

    test('rejects private_readd_current RA-009 missing Bob visibility', () {
      final missingVisibility = _validPrivateReaddCurrentVerdicts();
      missingVisibility[1] = {
        ...missingVisibility[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'ml007-a-during',
            'alice during charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'ml007-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
        },
        'ra009FirstReaddPublishProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingVisibility[1]['ra009FirstReaddPublishProof'] as Map,
          ),
          'receivedCharlieFirstPostReaddAtCurrentEpoch': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingVisibility,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys charlieAfterImmediateReadd'),
      );
      expect(
        rejected.detail,
        contains('receivedCharlieFirstPostReaddAtCurrentEpoch must be true'),
      );
    });

    test(
      'rejects private_readd_current without RA-010 incoming restart proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra010ReaddIncomingRestartProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing RA-010 incoming restart proof fields'),
        );
      },
    );

    test('rejects private_readd_current RA-010 lost post-restart delivery', () {
      final lostRestartDelivery = _validPrivateReaddCurrentVerdicts();
      lostRestartDelivery[2] = {
        ...lostRestartDelivery[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterImmediateReadd',
            'ml007-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'bobAfterReaddCurrent',
            'ml007-b-after',
            'bob after readd current',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterImmediateReadd': 1,
          'bobAfterReaddCurrent': 1,
        },
        'ra010ReaddIncomingRestartProof': <String, Object?>{
          ...Map<String, Object?>.from(
            lostRestartDelivery[2]['ra010ReaddIncomingRestartProof'] as Map,
          ),
          'receivedSecondIncomingAfterRestartAtCurrentEpoch': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: lostRestartDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: missing received proof keys aliceAfterCharlieRestart',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'receivedSecondIncomingAfterRestartAtCurrentEpoch must be true',
        ),
      );
    });

    test(
      'rejects private_readd_current without RA-014 old-key publish proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra014OldKeyPublishAfterReaddProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing RA-014 old-key publish proof fields'),
        );
      },
    );

    test('rejects private_readd_current RA-014 stale publish acceptance', () {
      final staleAccepted = _validPrivateReaddCurrentVerdicts();
      staleAccepted[2] = {
        ...staleAccepted[2],
        'ra014OldKeyPublishAfterReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleAccepted[2]['ra014OldKeyPublishAfterReaddProof'] as Map,
          ),
          'oldKeyPublishRejected': false,
          'staleEpoch': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleAccepted,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('oldKeyPublishRejected must be true'));
      expect(rejected.detail, contains('staleEpoch must be lower than 2'));
    });

    test(
      'rejects private_readd_current without RA-015 already-joined refresh proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra015AlreadyJoinedReaddRefreshProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'charlie: missing RA-015 already-joined re-add proof fields',
          ),
        );
      },
    );

    test('rejects private_readd_current RA-015 missing current delivery', () {
      final noDelivery = _validPrivateReaddCurrentVerdicts();
      noDelivery[2] = {
        ...noDelivery[2],
        'ra015AlreadyJoinedReaddRefreshProof': <String, Object?>{
          ...Map<String, Object?>.from(
            noDelivery[2]['ra015AlreadyJoinedReaddRefreshProof'] as Map,
          ),
          'receivedAlicePostRefreshAtCurrentEpoch': false,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: noDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('receivedAlicePostRefreshAtCurrentEpoch must be true'),
      );
      expect(rejected.detail, contains('finalEpoch must be >= 2'));
    });

    test(
      'RA-016 accepts private_readd_current removed-interval replay proof',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateReaddCurrentVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_readd_current verdicts valid'),
        );
      },
    );

    test(
      'RA-016 rejects private_readd_current without removed-interval replay proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ra016RemovedIntervalReplayProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'charlie: missing RA-016 removed-interval replay proof fields',
          ),
        );
      },
    );

    test(
      'RA-016 rejects private_readd_current Charlie removed-window leakage',
      () {
        final leaked = _validPrivateReaddCurrentVerdicts();
        leaked[2] = {
          ...leaked[2],
          'ra016RemovedIntervalReplayProof': <String, Object?>{
            ...Map<String, Object?>.from(
              leaked[2]['ra016RemovedIntervalReplayProof'] as Map,
            ),
            'removedWindowPlaintextCount': 1,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: leaked,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('removedWindowPlaintextCount must be 0'),
        );
      },
    );

    test(
      'RA-016 rejects private_readd_current missing host direct fake-network coverage',
      () {
        final missingHostCoverage = _validPrivateReaddCurrentVerdicts();
        missingHostCoverage[0] = {
          ...missingHostCoverage[0],
          'ra016RemovedIntervalReplayProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingHostCoverage[0]['ra016RemovedIntervalReplayProof'] as Map,
            ),
            'hostDirectRemovedIntervalReplayCovered': false,
          },
        };
        missingHostCoverage[1] = {
          ...missingHostCoverage[1],
          'ra016RemovedIntervalReplayProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingHostCoverage[1]['ra016RemovedIntervalReplayProof'] as Map,
            ),
            'hostFakeNetworkRemovedIntervalReplayCovered': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingHostCoverage,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('hostDirectRemovedIntervalReplayCovered must be true'),
        );
        expect(
          rejected.detail,
          contains('hostFakeNetworkRemovedIntervalReplayCovered must be true'),
        );
      },
    );

    test(
      'RA-016 rejects private_readd_current missing live current delivery',
      () {
        final missingDelivery = _validPrivateReaddCurrentVerdicts();
        missingDelivery[2] = {
          ...missingDelivery[2],
          'ra016RemovedIntervalReplayProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingDelivery[2]['ra016RemovedIntervalReplayProof'] as Map,
            ),
            'receivedBobPostReaddCurrent': false,
            'livePostReaddCurrentDeliveryCovered': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingDelivery,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('livePostReaddCurrentDeliveryCovered must be true'),
        );
        expect(
          rejected.detail,
          contains('receivedBobPostReaddCurrent must be true'),
        );
      },
    );

    test('RA-016 rejects private_readd_current final epoch mismatch', () {
      final epochMismatch = _validPrivateReaddCurrentVerdicts();
      epochMismatch[1] = {
        ...epochMismatch[1],
        'ra016RemovedIntervalReplayProof': <String, Object?>{
          ...Map<String, Object?>.from(
            epochMismatch[1]['ra016RemovedIntervalReplayProof'] as Map,
          ),
          'finalEpoch': 3,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: epochMismatch,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('RA-016 finalEpoch mismatch'));
    });

    test('rejects RA-011 missing late leave repair proof', () {
      final missingProof = _validRa011LateLeaveReaddVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ra011LateLeaveReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_late_leave_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing RA-011 late leave re-add proof fields'),
      );
    });

    test('rejects RA-011 late leave without repair join', () {
      final stranded = _validRa011LateLeaveReaddVerdicts();
      stranded[2] = {
        ...stranded[2],
        'ra011LateLeaveReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stranded[2]['ra011LateLeaveReaddProof'] as Map,
          ),
          'lateLeaveRepairJoinCompleted': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_late_leave_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stranded,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: ra011LateLeaveReaddProof.lateLeaveRepairJoinCompleted must be true',
        ),
      );
    });

    test('rejects RA-012 missing rotated material proof', () {
      final missingProof = _validRa012RotatedDeviceReaddVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ra012RotatedDeviceReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rotated_device_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing RA-012 rotated device re-add proof fields'),
      );
    });

    test('rejects RA-012 retained old device material', () {
      final retainedOldMaterial = _validRa012RotatedDeviceReaddVerdicts();
      retainedOldMaterial[2] = {
        ...retainedOldMaterial[2],
        'ra012RotatedDeviceReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            retainedOldMaterial[2]['ra012RotatedDeviceReaddProof'] as Map,
          ),
          'oldDeviceMaterialRetained': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rotated_device_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: retainedOldMaterial,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: ra012RotatedDeviceReaddProof.oldDeviceMaterialRetained must be false',
        ),
      );
    });

    test(
      'rejects private_readd_current without KE-012 delayed old config proof',
      () {
        final missingProof = _validPrivateReaddCurrentVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ke012DelayedOldConfigAfterReaddProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_readd_current',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing KE-012 delayed old config proof fields'),
        );
      },
    );

    test('rejects private_readd_current KE-012 active member loss', () {
      final activeLoss = _validPrivateReaddCurrentVerdicts();
      activeLoss[1] = {
        ...activeLoss[1],
        'ke012DelayedOldConfigAfterReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            activeLoss[1]['ke012DelayedOldConfigAfterReaddProof'] as Map,
          ),
          'keptActiveAfterDelayedOldConfig': false,
        },
      };
      activeLoss[2] = {
        ...activeLoss[2],
        'keyEpoch': 1,
        'ke012DelayedOldConfigAfterReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            activeLoss[2]['ke012DelayedOldConfigAfterReaddProof'] as Map,
          ),
          'keptFinalMembersAfterDelayedOldConfig': false,
          'keptCurrentEpochAfterDelayedOldConfig': false,
          'epochAfterDelayedOldConfig': 1,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: activeLoss,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('keptActiveAfterDelayedOldConfig must be true'),
      );
      expect(
        rejected.detail,
        contains('keptFinalMembersAfterDelayedOldConfig must be true'),
      );
      expect(
        rejected.detail,
        contains('epochAfterDelayedOldConfig must be >= 2'),
      );
    });

    test('rejects private_readd_current Charlie removed-window plaintext', () {
      final leaked = _validPrivateReaddCurrentVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'ml007-a-during',
            'alice during charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'ml007-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'bobAfterReaddCurrent',
            'ml007-b-after',
            'bob after readd current',
            'bob-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
          'bobAfterReaddCurrent': 1,
        },
        'ml007ReaddCurrentProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml007ReaddCurrentProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects private_readd_current Charlie stale epoch after re-add', () {
      final stale = _validPrivateReaddCurrentVerdicts();
      stale[2] = {
        ...stale[2],
        'keyEpoch': 1,
        'ml007ReaddCurrentProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stale[2]['ml007ReaddCurrentProof'] as Map,
          ),
          'hasStaleEpochAfterReadd': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stale,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterReadd must be false'),
      );
      expect(rejected.detail, contains('finalEpoch must be >= 2'));
    });

    test('rejects private_readd_current missing Bob delivery to Charlie', () {
      final missingDelivery = _validPrivateReaddCurrentVerdicts();
      missingDelivery[2] = {
        ...missingDelivery[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterImmediateReadd',
            'ml007-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterImmediateReadd': 1,
        },
        'ml007ReaddCurrentProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[2]['ml007ReaddCurrentProof'] as Map,
          ),
          'receivedBobPostReaddMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_current',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('charlie: missing received proof keys'));
      expect(rejected.detail, contains('bobAfterReaddCurrent'));
      expect(
        rejected.detail,
        contains('receivedBobPostReaddMessage must be true'),
      );
    });

    test('rejects private_readd_cycles without ML-008 proof fields', () {
      final missingProof = _validPrivateReaddCyclesVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml008CycleProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-008 cycle proof fields'),
      );
    });

    test('rejects private_readd_cycles with fewer than 20 cycles', () {
      final shortRun = _validPrivateReaddCyclesVerdicts();
      shortRun[0] = {
        ...shortRun[0],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(shortRun[0]['ml008CycleProof'] as Map),
          'cycleCount': 19,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: shortRun,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: ml008CycleProof.cycleCount must be 20'),
      );
    });

    test('rejects private_readd_cycles without Bob exact member-row proof', () {
      final missingExactRows = _validPrivateReaddCyclesVerdicts();
      missingExactRows[1] = {
        ...missingExactRows[1],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingExactRows[1]['ml008CycleProof'] as Map,
          ),
          'bobCharlieExactMemberRowCountProofs': 19,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingExactRows,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'bob: ml008CycleProof.bobCharlieExactMemberRowCountProofs must be >= 20',
        ),
      );
    });

    test('rejects private_readd_cycles without enough restart markers', () {
      final weakRestart = _validPrivateReaddCyclesVerdicts();
      weakRestart[0] = {
        ...weakRestart[0],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            weakRestart[0]['ml008CycleProof'] as Map,
          ),
          'restartMarkersObserved': 3,
        },
      };
      weakRestart[1] = {
        ...weakRestart[1],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            weakRestart[1]['ml008CycleProof'] as Map,
          ),
          'restartMarkersPerformed': 1,
        },
      };
      weakRestart[2] = {
        ...weakRestart[2],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            weakRestart[2]['ml008CycleProof'] as Map,
          ),
          'restartMarkersPerformed': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: weakRestart,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('restartMarkersObserved'));
      expect(
        rejected.detail,
        contains('restartMarkersPerformed total must be >= 4'),
      );
    });

    test('rejects private_readd_cycles Charlie removed-window plaintext', () {
      final leaked = _validPrivateReaddCyclesVerdicts();
      leaked[2] = {
        ...leaked[2],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(leaked[2]['ml008CycleProof'] as Map),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects private_readd_cycles missing post-readd delivery', () {
      final missingDelivery = _validPrivateReaddCyclesVerdicts();
      missingDelivery[0] = {
        ...missingDelivery[0],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[0]['ml008CycleProof'] as Map,
          ),
          'receivedCharliePostReaddCount': 19,
        },
      };
      missingDelivery[2] = {
        ...missingDelivery[2],
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[2]['ml008CycleProof'] as Map,
          ),
          'receivedAlicePostReaddCount': 19,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'alice: ml008CycleProof.receivedCharliePostReaddCount must be >= 20',
        ),
      );
      expect(
        rejected.detail,
        contains(
          'charlie: ml008CycleProof.receivedAlicePostReaddCount must be >= 20',
        ),
      );
    });

    test('rejects private_readd_cycles final epoch divergence', () {
      final divergent = _validPrivateReaddCyclesVerdicts();
      divergent[2] = {
        ...divergent[2],
        'keyEpoch': 19,
        'ml008CycleProof': <String, Object?>{
          ...Map<String, Object?>.from(divergent[2]['ml008CycleProof'] as Map),
          'finalEpoch': 19,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_readd_cycles',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: ml008CycleProof.finalEpoch must be >= 20'),
      );
      expect(rejected.detail, contains('ML-008 finalEpoch mismatch'));
    });

    test('accepts private_rapid_readd ML-009 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateRapidReaddVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('private_rapid_readd verdicts valid'));
    });

    test('rejects private_rapid_readd without ML-009 proof fields', () {
      final missingProof = _validPrivateRapidReaddVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml009RapidReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-009 rapid re-add proof fields'),
      );
    });

    test('rejects private_rapid_readd without rapid ordering proof', () {
      final weakOrdering = _validPrivateRapidReaddVerdicts();
      weakOrdering[0] = {
        ...weakOrdering[0],
        'ml009RapidReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            weakOrdering[0]['ml009RapidReaddProof'] as Map,
          ),
          'readdIssuedBeforeRemovalAcks': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: weakOrdering,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('readdIssuedBeforeRemovalAcks'));
    });

    test('rejects private_rapid_readd stale remove application', () {
      final staleRemove = _validPrivateRapidReaddVerdicts();
      staleRemove[1] = {
        ...staleRemove[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'ml009RapidReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleRemove[1]['ml009RapidReaddProof'] as Map,
          ),
          'memberListIncludesCharlie': false,
          'staleRemoveIgnored': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleRemove,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('memberListIncludesCharlie'));
      expect(rejected.detail, contains('staleRemoveIgnored'));
    });

    test('rejects private_rapid_readd Charlie removed-window plaintext', () {
      final leaked = _validPrivateRapidReaddVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringRapidRemove',
            'ml009-a-during',
            'alice during rapid remove',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'alicePostRapidReadd',
            'ml009-a-after',
            'alice after rapid readd',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'bobPostRapidReadd',
            'ml009-b-after',
            'bob after rapid readd',
            'bob-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringRapidRemove': 1,
          'alicePostRapidReadd': 1,
          'bobPostRapidReadd': 1,
        },
        'ml009RapidReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml009RapidReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceDuringRapidRemove'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects private_rapid_readd missing Bob delivery to Charlie', () {
      final missingDelivery = _validPrivateRapidReaddVerdicts();
      missingDelivery[2] = {
        ...missingDelivery[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'alicePostRapidReadd',
            'ml009-a-after',
            'alice after rapid readd',
            'alice-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{'alicePostRapidReadd': 1},
        'ml009RapidReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[2]['ml009RapidReaddProof'] as Map,
          ),
          'receivedBobPostReaddMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing received proof keys bobPostRapidReadd'),
      );
      expect(rejected.detail, contains('receivedBobPostReaddMessage'));
    });

    test('rejects private_rapid_readd final epoch divergence', () {
      final divergent = _validPrivateRapidReaddVerdicts();
      divergent[2] = {
        ...divergent[2],
        'keyEpoch': 1,
        'ml009RapidReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            divergent[2]['ml009RapidReaddProof'] as Map,
          ),
          'hasStaleEpochAfterReadd': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_rapid_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterReadd must be false'),
      );
      expect(
        rejected.detail,
        contains('charlie: ml009RapidReaddProof.finalEpoch must be >= 2'),
      );
      expect(rejected.detail, contains('ML-009 finalEpoch mismatch'));
    });

    test('accepts private_concurrent_admin_membership_edits ML-012 proof', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_concurrent_admin_membership_edits',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateConcurrentAdminMembershipVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_concurrent_admin_membership_edits verdicts valid'),
      );
    });

    test('rejects private_concurrent_admin_membership_edits missing proof', () {
      final missingProof = _validPrivateConcurrentAdminMembershipVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ml012ConcurrentAdminEditsProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_concurrent_admin_membership_edits',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing ML-012 concurrent-admin proof fields'),
      );
    });

    test(
      'rejects private_concurrent_admin_membership_edits wrong row or app peer metadata',
      () {
        final wrongMetadata = _validPrivateConcurrentAdminMembershipVerdicts();
        wrongMetadata[0] = {
          ...wrongMetadata[0],
          'ml012ConcurrentAdminEditsProof': <String, Object?>{
            ...Map<String, Object?>.from(
              wrongMetadata[0]['ml012ConcurrentAdminEditsProof'] as Map,
            ),
            'rowId': 'ML-013',
            'appPeerPlatform': 'ios_26_4_core_simulator',
            'concurrentAdminProofSource': 'fake_network',
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_concurrent_admin_membership_edits',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: wrongMetadata,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('rowId must be ML-012'));
        expect(rejected.detail, contains('appPeerPlatform'));
        expect(rejected.detail, contains('concurrentAdminProofSource'));
      },
    );

    test(
      'rejects private_concurrent_admin_membership_edits missing delivery order',
      () {
        final weak = _validPrivateConcurrentAdminMembershipVerdicts();
        weak[0] = {
          ...weak[0],
          'ml012ConcurrentAdminEditsProof': <String, Object?>{
            ...Map<String, Object?>.from(
              weak[0]['ml012ConcurrentAdminEditsProof'] as Map,
            ),
            'deliveryOrdersTested': const <String>['add_then_remove'],
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_concurrent_admin_membership_edits',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: weak,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('deliveryOrdersTested'));
      },
    );

    test(
      'rejects private_concurrent_admin_membership_edits member divergence',
      () {
        final divergent = _validPrivateConcurrentAdminMembershipVerdicts();
        divergent[3] = {
          ...divergent[3],
          'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
          'ml012ConcurrentAdminEditsProof': <String, Object?>{
            ...Map<String, Object?>.from(
              divergent[3]['ml012ConcurrentAdminEditsProof'] as Map,
            ),
            'finalMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
            'independentAddPreserved': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_concurrent_admin_membership_edits',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: divergent,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('finalMemberPeerIds'));
        expect(rejected.detail, contains('independentAddPreserved'));
      },
    );

    test(
      'rejects private_concurrent_admin_membership_edits config hash mismatch',
      () {
        final divergent = _validPrivateConcurrentAdminMembershipVerdicts();
        divergent[1] = {
          ...divergent[1],
          'ml012ConcurrentAdminEditsProof': <String, Object?>{
            ...Map<String, Object?>.from(
              divergent[1]['ml012ConcurrentAdminEditsProof'] as Map,
            ),
            'finalConfigStateHash': 'different-hash',
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_concurrent_admin_membership_edits',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: divergent,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('finalConfigStateHash mismatch'));
      },
    );

    test('accepts private_timeline_truth ML-015 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateTimelineTruthVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(verdict.detail, contains('private_timeline_truth verdicts valid'));
    });

    test(
      'UP-002 accepts private_timeline_truth durable timeline proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateTimelineTruthVerdicts(),
        );

        expect(verdict.ok, isTrue, reason: verdict.detail);
        expect(
          verdict.detail,
          contains('private_timeline_truth verdicts valid'),
        );
      },
    );

    test(
      'UP-002 rejects private_timeline_truth without durable timeline proof',
      () {
        final missingProof = _validPrivateTimelineTruthVerdicts();
        missingProof[0] = Map<String, dynamic>.from(missingProof[0])
          ..remove('up002DurableTimelineProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('alice: missing UP-002 durable timeline proof fields'),
        );
      },
    );

    test(
      'UP-002 rejects private_timeline_truth timeline/final-state mismatch',
      () {
        final divergent = _validPrivateTimelineTruthVerdicts();
        divergent[1] = {
          ...divergent[1],
          'up002DurableTimelineProof': <String, Object?>{
            ...Map<String, Object?>.from(
              divergent[1]['up002DurableTimelineProof'] as Map,
            ),
            'addTimelineEventCount': 1,
            'timelineOrderShowsAddRemoveReadd': false,
            'finalStateMatchesTimeline': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: divergent,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('addTimelineEventCount must be >= 2'));
        expect(
          rejected.detail,
          contains('timelineOrderShowsAddRemoveReadd must be true'),
        );
        expect(
          rejected.detail,
          contains('finalStateMatchesTimeline must be true'),
        );
      },
    );

    test(
      'UP-004 accepts private_timeline_truth unread churn proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateTimelineTruthVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_timeline_truth verdicts valid'),
        );
      },
    );

    test(
      'UP-004 rejects private_timeline_truth without unread churn proof',
      () {
        final missingProof = _validPrivateTimelineTruthVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('up004UnreadChurnProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing UP-004 unread churn proof fields'),
        );
      },
    );

    test(
      'UP-004 rejects private_timeline_truth removed-window unread leakage',
      () {
        final leaked = _validPrivateTimelineTruthVerdicts();
        leaked[2] = {
          ...leaked[2],
          'up004UnreadChurnProof': <String, Object?>{
            ...Map<String, Object?>.from(
              leaked[2]['up004UnreadChurnProof'] as Map,
            ),
            'removedWindowUnreadExcluded': false,
            'removedWindowUnreadCount': 1,
            'finalUnreadCountAfterOpen': 1,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: leaked,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('removedWindowUnreadExcluded must be true'),
        );
        expect(
          rejected.detail,
          contains(
            'charlie: up004UnreadChurnProof.removedWindowUnreadCount must be 0',
          ),
        );
        expect(
          rejected.detail,
          contains('finalUnreadCountAfterOpen must be 0'),
        );
      },
    );

    test(
      'UP-006 accepts private_timeline_truth re-add UI state proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateTimelineTruthVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_timeline_truth verdicts valid'),
        );
      },
    );

    test(
      'UP-006 rejects private_timeline_truth without re-add UI state proof',
      () {
        final missingProof = _validPrivateTimelineTruthVerdicts();
        missingProof[0] = Map<String, dynamic>.from(missingProof[0])
          ..remove('up006ReaddUiStateProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('alice: missing UP-006 re-add UI state proof fields'),
        );
      },
    );

    test('UP-006 rejects private_timeline_truth stale removed state reuse', () {
      final stale = _validPrivateTimelineTruthVerdicts();
      stale[2] = {
        ...stale[2],
        'up006ReaddUiStateProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stale[2]['up006ReaddUiStateProof'] as Map,
          ),
          'latestCharlieTimelineText': 'Alice removed Charlie',
          'latestCharlieTimelineIsReadd': false,
          'staleRemovedStateReused': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stale,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('latestCharlieTimelineIsReadd must be true'),
      );
      expect(
        rejected.detail,
        contains('staleRemovedStateReused must be false'),
      );
      expect(
        rejected.detail,
        contains('latestCharlieTimelineText must not contain removed'),
      );
    });

    test(
      'UP-009 accepts private_timeline_truth re-add sender identity proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateTimelineTruthVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_timeline_truth verdicts valid'),
        );
      },
    );

    test(
      'UP-009 rejects private_timeline_truth without re-add sender identity proof',
      () {
        final missingProof = _validPrivateTimelineTruthVerdicts();
        missingProof[1] = Map<String, dynamic>.from(missingProof[1])
          ..remove('up009ReaddSenderIdentityProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('bob: missing UP-009 sender identity proof fields'),
        );
      },
    );

    test(
      'UP-009 rejects private_timeline_truth stale rendered sender label',
      () {
        final stale = _validPrivateTimelineTruthVerdicts();
        stale[0] = {
          ...stale[0],
          'up009ReaddSenderIdentityProof': <String, Object?>{
            ...Map<String, Object?>.from(
              stale[0]['up009ReaddSenderIdentityProof'] as Map,
            ),
            'currentMemberUsername': 'Readded Charlie',
            'renderedSenderDisplayName': 'Old Charlie',
            'renderedLabelMatchesCurrentMember': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: stale,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('renderedLabelMatchesCurrentMember must be true'),
        );
        expect(
          rejected.detail,
          contains(
            'renderedSenderDisplayName must match currentMemberUsername',
          ),
        );
      },
    );

    test(
      'UP-010 accepts private_timeline_truth notification route proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateTimelineTruthVerdicts(),
        );

        expect(verdict.ok, isTrue);
        expect(
          verdict.detail,
          contains('private_timeline_truth verdicts valid'),
        );
      },
    );

    test(
      'UP-010 rejects private_timeline_truth without notification route proof',
      () {
        final missingProof = _validPrivateTimelineTruthVerdicts();
        missingProof[0] = Map<String, dynamic>.from(missingProof[0])
          ..remove('up010NotificationRouteProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_timeline_truth',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('alice: missing UP-010 notification route proof fields'),
        );
      },
    );

    test('UP-010 rejects private_timeline_truth stale removed route open', () {
      final stale = _validPrivateTimelineTruthVerdicts();
      stale[2] = {
        ...stale[2],
        'up010NotificationRouteProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stale[2]['up010NotificationRouteProof'] as Map,
          ),
          'staleRemovedGroupRejected': false,
          'staleRemovedResolutionMissing': false,
          'staleRemovedGroupOpened': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stale,
      );

      expect(
        rejected.detail,
        contains('staleRemovedGroupRejected must be true'),
      );
      expect(
        rejected.detail,
        contains('staleRemovedGroupOpened must be false'),
      );
    });

    test('rejects private_timeline_truth without ML-015 proof fields', () {
      final missingProof = _validPrivateTimelineTruthVerdicts();
      missingProof[1] = Map<String, dynamic>.from(missingProof[1])
        ..remove('ml015TimelineTruthProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing ML-015 timeline-truth proof fields'),
      );
    });

    test('rejects private_timeline_truth timeline/member divergence', () {
      final divergent = _validPrivateTimelineTruthVerdicts();
      divergent[1] = {
        ...divergent[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'activeMemberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'ml015TimelineTruthProof': <String, Object?>{
          ...Map<String, Object?>.from(
            divergent[1]['ml015TimelineTruthProof'] as Map,
          ),
          'timelineOrderMatchesMembershipIntervals': false,
          'memberListIncludesCharlie': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('timelineOrderMatchesMembershipIntervals must be true'),
      );
      expect(rejected.detail, contains('memberListIncludesCharlie'));
    });

    test('rejects private_timeline_truth removed-window leak to Charlie', () {
      final leaked = _validPrivateTimelineTruthVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeTimelineRemoval',
            'ml015-a-before',
            'alice before removal',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'aliceDuringTimelineRemoval',
            'ml015-a-window',
            'alice removed window',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'alicePostTimelineReadd',
            'ml015-a-after',
            'alice after readd',
            'alice-peer',
            keyEpoch: 3,
          ),
          _received(
            'bobPostTimelineReadd',
            'ml015-b-after',
            'bob after readd',
            'bob-peer',
            keyEpoch: 3,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeTimelineRemoval': 1,
          'aliceDuringTimelineRemoval': 1,
          'alicePostTimelineReadd': 1,
          'bobPostTimelineReadd': 1,
        },
        'ml015TimelineTruthProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml015TimelineTruthProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('unexpected received proof keys aliceDuringTimelineRemoval'),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects private_timeline_truth final epoch divergence', () {
      final divergent = _validPrivateTimelineTruthVerdicts();
      divergent[2] = {
        ...divergent[2],
        'keyEpoch': 1,
        'ml015TimelineTruthProof': <String, Object?>{
          ...Map<String, Object?>.from(
            divergent[2]['ml015TimelineTruthProof'] as Map,
          ),
          'hasStaleEpochAfterReadd': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_timeline_truth',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: divergent,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterReadd must be false'),
      );
      expect(
        rejected.detail,
        contains('charlie: ml015TimelineTruthProof.finalEpoch must be >= 2'),
      );
      expect(rejected.detail, contains('ML-015 finalEpoch mismatch'));
    });

    test('accepts private_history_retention ML-017 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_history_retention',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateHistoryRetentionVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_history_retention verdicts valid'),
      );
    });

    test('rejects private_history_retention without ML-017 proof fields', () {
      final missingProof = _validPrivateHistoryRetentionVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ml017HistoryRetentionProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_history_retention',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing ML-017 history-retention proof fields'),
      );
    });

    test('rejects private_history_retention missing old history', () {
      final missingHistory = _validPrivateHistoryRetentionVerdicts();
      missingHistory[2] = {
        ...missingHistory[2],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ml017HistoryRetentionProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingHistory[2]['ml017HistoryRetentionProof'] as Map,
          ),
          'retainedPreRemovalHistory': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_history_retention',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingHistory,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missing received proof keys aliceBeforeHistoryRemoval'),
      );
      expect(rejected.detail, contains('retainedPreRemovalHistory'));
    });

    test('rejects private_history_retention post-removal leak', () {
      final leaked = _validPrivateHistoryRetentionVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeHistoryRemoval',
            'ml017-a-before',
            'alice before removal',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'alicePostHistoryRemoval',
            'ml017-a-after',
            'alice after removal',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeHistoryRemoval': 1,
          'alicePostHistoryRemoval': 1,
        },
        'ml017HistoryRetentionProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml017HistoryRetentionProof'] as Map,
          ),
          'receivedAlicePostRemovalMessage': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_history_retention',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('unexpected received proof keys alicePostHistoryRemoval'),
      );
      expect(rejected.detail, contains('postRemovalPlaintextCount must be 0'));
    });

    test('rejects private_history_retention accepted Charlie send', () {
      final acceptedSend = _validPrivateHistoryRetentionVerdicts();
      acceptedSend[2] = {
        ...acceptedSend[2],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'charliePostHistoryRemoval',
            'messageId': 'ml017-c-after',
            'text': 'charlie after removal',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 1,
          },
        ],
        'ml017HistoryRetentionProof': <String, Object?>{
          ...Map<String, Object?>.from(
            acceptedSend[2]['ml017HistoryRetentionProof'] as Map,
          ),
          'postRemovalPublishAccepted': true,
          'postRemovalSendRejected': false,
          'postRemovalSendOutcome': 'success',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_history_retention',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('postRemovalPublishAccepted must be false'),
      );
      expect(rejected.detail, contains('postRemovalSendOutcome'));
    });

    test('accepts private_invite_terminal_states ML-018 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_invite_terminal_states',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateInviteTerminalStatesVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_invite_terminal_states verdicts valid'),
      );
    });

    test(
      'rejects private_invite_terminal_states without ML-018 proof fields',
      () {
        final missingProof = _validPrivateInviteTerminalStatesVerdicts();
        missingProof[2] = Map<String, dynamic>.from(missingProof[2])
          ..remove('ml018InviteTerminalProof');

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_invite_terminal_states',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingProof,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('charlie: missing ML-018 invite-terminal proof fields'),
        );
      },
    );

    test('rejects private_invite_terminal_states post-terminal leak', () {
      final leaked = _validPrivateInviteTerminalStatesVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterInviteTerminalStates',
            'ml018-a-after',
            'alice after invite terminal states',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterInviteTerminalStates': 1,
        },
        'ml018InviteTerminalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml018InviteTerminalProof'] as Map,
          ),
          'receivedAlicePostTerminalMessage': true,
          'postTerminalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_invite_terminal_states',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'unexpected received proof keys aliceAfterInviteTerminalStates',
        ),
      );
      expect(rejected.detail, contains('postTerminalPlaintextCount must be 0'));
    });

    test('rejects private_invite_terminal_states accepted Charlie send', () {
      final acceptedSend = _validPrivateInviteTerminalStatesVerdicts();
      acceptedSend[2] = {
        ...acceptedSend[2],
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'charlieAfterInviteTerminalStates',
            'messageId': 'ml018-c-after',
            'text': 'charlie after invite terminal states',
            'outcome': 'success',
            'senderPeerId': 'charlie-peer',
            'keyEpoch': 1,
          },
        ],
        'ml018InviteTerminalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            acceptedSend[2]['ml018InviteTerminalProof'] as Map,
          ),
          'postTerminalPublishAccepted': true,
          'postTerminalSendRejected': false,
          'postTerminalSendOutcome': 'success',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_invite_terminal_states',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: acceptedSend,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('postTerminalPublishAccepted must be false'),
      );
      expect(
        rejected.detail,
        contains(
          'postTerminalSendOutcome must be groupNotFound or unauthorized',
        ),
      );
    });

    test(
      'accepts private_stale_invite_readd ML-019 and KE-016 proof verdicts',
      () {
        final verdict = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_stale_invite_readd',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: _validPrivateStaleInviteReaddVerdicts(),
        );

        expect(verdict.ok, isTrue, reason: verdict.detail);
        expect(
          verdict.detail,
          contains('private_stale_invite_readd verdicts valid'),
        );
      },
    );

    test('accepts private_stale_invite_readd RA-004 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateStaleInviteReaddVerdicts(),
      );

      expect(verdict.ok, isTrue, reason: verdict.detail);
      expect(
        verdict.detail,
        contains('private_stale_invite_readd verdicts valid'),
      );
    });

    test('rejects private_stale_invite_readd without RA-004 proof', () {
      final missingRa004 = _validPrivateStaleInviteReaddVerdicts();
      missingRa004[2] = {...missingRa004[2]}
        ..remove('ra004StaleInviteBeforeReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingRa004,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missing RA-004 stale invite proof fields'),
      );
    });

    test('rejects private_stale_invite_readd RA-004 old accept success', () {
      final staleAccepted = _validPrivateStaleInviteReaddVerdicts();
      staleAccepted[2] = {
        ...staleAccepted[2],
        'ra004StaleInviteBeforeReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleAccepted[2]['ra004StaleInviteBeforeReaddProof'] as Map,
          ),
          'oldAcceptBeforeCurrentRejected': false,
          'oldAcceptResultBeforeCurrent': 'success',
          'noGroupAfterOldAccept': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleAccepted,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('oldAcceptBeforeCurrentRejected'));
      expect(
        rejected.detail,
        contains('oldAcceptResultBeforeCurrent must be revoked or notFound'),
      );
    });

    test('rejects private_stale_invite_readd without KE-016 proof', () {
      final missingKe016 = _validPrivateStaleInviteReaddVerdicts();
      missingKe016[2] = {...missingKe016[2]}..remove('ke016StaleReinviteProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingKe016,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('missing KE-016 stale re-invite proof fields'),
      );
    });

    test('rejects private_stale_invite_readd without stale reject proof', () {
      final staleAccepted = _validPrivateStaleInviteReaddVerdicts();
      staleAccepted[2] = {
        ...staleAccepted[2],
        'ml019StaleInviteProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleAccepted[2]['ml019StaleInviteProof'] as Map,
          ),
          'staleAcceptRejected': false,
          'staleAcceptResult': 'success',
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleAccepted,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('staleAcceptRejected'));
      expect(
        rejected.detail,
        contains('staleAcceptResult must be invalidPayload'),
      );
    });

    test('rejects private_stale_invite_readd removed-window leak', () {
      final leaked = _validPrivateStaleInviteReaddVerdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringStaleInviteRemoval',
            'ml019-a-during',
            'alice during stale invite removal',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringStaleInviteRemoval': 1,
        },
        'ml019StaleInviteProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ml019StaleInviteProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_invite_readd',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'unexpected received proof keys aliceDuringStaleInviteRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('accepts private_stale_lower_key_update KE-003 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_stale_lower_key_update',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateStaleLowerKeyUpdateVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_stale_lower_key_update verdicts valid'),
      );
    });

    test(
      'rejects private_stale_lower_key_update downgrade after stale update',
      () {
        final downgraded = _validPrivateStaleLowerKeyUpdateVerdicts();
        downgraded[1] = {
          ...downgraded[1],
          'keyEpoch': 4,
          'ke003StaleLowerKeyUpdateProof': <String, Object?>{
            ...Map<String, Object?>.from(
              downgraded[1]['ke003StaleLowerKeyUpdateProof'] as Map,
            ),
            'keptEpochFiveAfterStale': false,
            'epochAfterStale': 4,
            'finalEpoch': 4,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_stale_lower_key_update',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: downgraded,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('keptEpochFiveAfterStale'));
        expect(rejected.detail, contains('epochAfterStale must be 5'));
        expect(rejected.detail, contains('finalEpoch must be 5'));
      },
    );

    test('accepts private_same_epoch_key_conflict KE-005 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_same_epoch_key_conflict',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivateSameEpochKeyConflictVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_same_epoch_key_conflict verdicts valid'),
      );
    });

    test(
      'rejects private_same_epoch_key_conflict replacement after conflict',
      () {
        final replaced = _validPrivateSameEpochKeyConflictVerdicts();
        replaced[1] = {
          ...replaced[1],
          'ke005SameEpochKeyConflictProof': <String, Object?>{
            ...Map<String, Object?>.from(
              replaced[1]['ke005SameEpochKeyConflictProof'] as Map,
            ),
            'rejectedConflictingMaterial': false,
            'keptOriginalEpochFiveAfterConflict': false,
            'epochAfterConflict': 6,
            'finalEpoch': 6,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'private_same_epoch_key_conflict',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: replaced,
        );

        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('rejectedConflictingMaterial'));
        expect(rejected.detail, contains('keptOriginalEpochFiveAfterConflict'));
        expect(rejected.detail, contains('epochAfterConflict must be 5'));
        expect(rejected.detail, contains('finalEpoch must be 5'));
      },
    );

    test('accepts private_partial_key_distribution KE-015 proof verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partial_key_distribution',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validPrivatePartialKeyDistributionVerdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(
        verdict.detail,
        contains('private_partial_key_distribution verdicts valid'),
      );
    });

    test('rejects partial key distribution without KE-015 proof fields', () {
      final missingProof = _validPrivatePartialKeyDistributionVerdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ke015PartialKeyDistributionProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partial_key_distribution',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: missing KE-015 partial-key-distribution proof fields',
        ),
      );
    });

    test('rejects partial key distribution when sender promotes epoch', () {
      final unblocked = _validPrivatePartialKeyDistributionVerdicts();
      unblocked[0] = {
        ...unblocked[0],
        'keyEpoch': 2,
        'sentMessages': const <Map<String, Object?>>[
          {
            'key': 'aliceAfterPartialKeyDistributionFailure',
            'messageId': 'ke015-a-after',
            'text': 'alice after partial distribution failure',
            'outcome': 'success',
            'senderPeerId': 'alice-peer',
            'keyEpoch': 2,
          },
        ],
        'ke015PartialKeyDistributionProof': <String, Object?>{
          ...Map<String, Object?>.from(
            unblocked[0]['ke015PartialKeyDistributionProof'] as Map,
          ),
          'rotationBlocked': false,
          'keptSenderEpochAfterFailure': false,
          'blockedKeyRotatedPublish': false,
          'finalEpoch': 2,
          'postFailureMessageEpoch': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partial_key_distribution',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: unblocked,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('rotationBlocked must be true'));
      expect(rejected.detail, contains('finalEpoch must remain 1'));
      expect(rejected.detail, contains('postFailureMessageEpoch must be 1'));
    });

    test('rejects partial key distribution when failed recipient is deaf', () {
      final deaf = _validPrivatePartialKeyDistributionVerdicts();
      deaf[2] = {
        ...deaf[2],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'ke015PartialKeyDistributionProof': <String, Object?>{
          ...Map<String, Object?>.from(
            deaf[2]['ke015PartialKeyDistributionProof'] as Map,
          ),
          'receivedPostFailureAtPreviousEpoch': false,
          'notDeafAfterFailedKeyUpdate': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_partial_key_distribution',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: deaf,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: missing received proof keys aliceAfterPartialKeyDistributionFailure',
        ),
      );
    });

    test('rejects GM-006 Charlie removal-window plaintext', () {
      final leaked = _validGm006Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'gm006-a-during',
            'alice during charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'gm006-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
        },
        'gm006ImmediateReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['gm006ImmediateReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects GM-006 Charlie stale epoch after re-add', () {
      final stale = _validGm006Verdicts();
      stale[2] = {
        ...stale[2],
        'keyEpoch': 1,
        'gm006ImmediateReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stale[2]['gm006ImmediateReaddProof'] as Map,
          ),
          'hasStaleEpochAfterReadd': true,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stale,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterReadd must be false'),
      );
      expect(rejected.detail, contains('finalEpoch must be >= 2'));
    });

    test('rejects GM-006 missing Bob post-readd delivery', () {
      final missingDelivery = _validGm006Verdicts();
      missingDelivery[1] = {
        ...missingDelivery[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRemoval',
            'gm006-a-during',
            'alice during charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterImmediateReadd',
            'gm006-a-after',
            'alice after immediate readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRemoval': 1,
          'aliceAfterImmediateReadd': 1,
        },
        'gm006ImmediateReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[1]['gm006ImmediateReaddProof'] as Map,
          ),
          'receivedCharliePostReaddMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys charlieAfterImmediateReadd'),
      );
      expect(
        rejected.detail,
        contains('receivedCharliePostReaddMessage must be true'),
      );
    });

    test('rejects GM-008 missing restart proof', () {
      final missingProof = _validGm008Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('gm008RestartReaddProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing GM-008 restart re-add proof fields'),
      );
    });

    test('rejects GM-008 Charlie removed-window plaintext', () {
      final leaked = _validGm008Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceDuringCharlieRestartedRemoval',
            'gm008-a-during',
            'alice during restarted charlie removal',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterRestartReadd',
            'gm008-a-after',
            'alice after restart readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceDuringCharlieRestartedRemoval': 1,
          'aliceAfterRestartReadd': 1,
        },
        'gm008RestartReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['gm008RestartReaddProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRestartedRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects GM-008 Charlie stale epoch after restart re-add', () {
      final stale = _validGm008Verdicts();
      stale[2] = {
        ...stale[2],
        'keyEpoch': 1,
        'gm008RestartReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            stale[2]['gm008RestartReaddProof'] as Map,
          ),
          'hasStaleEpochAfterRestartReadd': true,
          'rejoinedFromCurrentPersistedEpoch': false,
          'finalEpoch': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: stale,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('hasStaleEpochAfterRestartReadd must be false'),
      );
      expect(
        rejected.detail,
        contains('rejoinedFromCurrentPersistedEpoch must be true'),
      );
      expect(rejected.detail, contains('finalEpoch must be >= 2'));
    });

    test(
      'rejects GM-008 missing Charlie post-readd delivery to Alice and Bob',
      () {
        final missingDelivery = _validGm008Verdicts();
        missingDelivery[0] = {
          ...missingDelivery[0],
          'receivedMessages': const <Map<String, Object?>>[],
          'persistedMessageCounts': const <String, int>{},
          'gm008RestartReaddProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingDelivery[0]['gm008RestartReaddProof'] as Map,
            ),
            'receivedCharliePostReaddMessage': false,
          },
        };
        missingDelivery[1] = {
          ...missingDelivery[1],
          'receivedMessages': <Map<String, Object?>>[
            _received(
              'aliceDuringCharlieRestartedRemoval',
              'gm008-a-during',
              'alice during restarted charlie removal',
              'alice-peer',
              keyEpoch: 2,
            ),
            _received(
              'aliceAfterRestartReadd',
              'gm008-a-after',
              'alice after restart readd',
              'alice-peer',
              keyEpoch: 2,
            ),
          ],
          'persistedMessageCounts': const <String, int>{
            'aliceDuringCharlieRestartedRemoval': 1,
            'aliceAfterRestartReadd': 1,
          },
          'gm008RestartReaddProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingDelivery[1]['gm008RestartReaddProof'] as Map,
            ),
            'receivedCharliePostReaddMessage': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm008',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingDelivery,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains(
            'alice: missing received proof keys charlieAfterRestartReadd',
          ),
        );
        expect(
          rejected.detail,
          contains('bob: missing received proof keys charlieAfterRestartReadd'),
        );
        expect(
          rejected.detail,
          contains('receivedCharliePostReaddMessage must be true'),
        );
      },
    );

    test(
      'rejects GM-008 missing Alice post-readd delivery to Bob and Charlie',
      () {
        final missingDelivery = _validGm008Verdicts();
        missingDelivery[1] = {
          ...missingDelivery[1],
          'receivedMessages': <Map<String, Object?>>[
            _received(
              'aliceDuringCharlieRestartedRemoval',
              'gm008-a-during',
              'alice during restarted charlie removal',
              'alice-peer',
              keyEpoch: 2,
            ),
            _received(
              'charlieAfterRestartReadd',
              'gm008-c-after',
              'charlie after restart readd',
              'charlie-peer',
              keyEpoch: 2,
            ),
          ],
          'persistedMessageCounts': const <String, int>{
            'aliceDuringCharlieRestartedRemoval': 1,
            'charlieAfterRestartReadd': 1,
          },
          'gm008RestartReaddProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingDelivery[1]['gm008RestartReaddProof'] as Map,
            ),
            'receivedAlicePostReaddMessage': false,
          },
        };
        missingDelivery[2] = {
          ...missingDelivery[2],
          'receivedMessages': const <Map<String, Object?>>[],
          'persistedMessageCounts': const <String, int>{},
          'gm008RestartReaddProof': <String, Object?>{
            ...Map<String, Object?>.from(
              missingDelivery[2]['gm008RestartReaddProof'] as Map,
            ),
            'receivedAlicePostReaddMessage': false,
          },
        };

        final rejected = evaluateGroupMultiPartyVerdicts(
          scenario: 'gm008',
          relayAddresses: expectedMultiPartyRelayAddresses,
          verdicts: missingDelivery,
        );

        expect(rejected.ok, isFalse);
        expect(
          rejected.detail,
          contains('bob: missing received proof keys aliceAfterRestartReadd'),
        );
        expect(
          rejected.detail,
          contains(
            'charlie: missing received proof keys aliceAfterRestartReadd',
          ),
        );
        expect(
          rejected.detail,
          contains('receivedAlicePostReaddMessage must be true'),
        );
      },
    );

    test('rejects GM-008 missing final member and key convergence', () {
      final incomplete = _validGm008Verdicts();
      incomplete[1] = {
        ...incomplete[1],
        'memberPeerIds': const <String>['alice-peer', 'bob-peer'],
        'gm008RestartReaddProof': <String, Object?>{
          ...Map<String, Object?>.from(
            incomplete[1]['gm008RestartReaddProof'] as Map,
          ),
          'memberListIncludesCharlie': false,
          'finalEpoch': 3,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm008',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: incomplete,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('memberListIncludesCharlie must be true'),
      );
      expect(
        rejected.detail,
        contains(
          'bob: incomplete membership convergence, missing charlie-peer',
        ),
      );
      expect(rejected.detail, contains('GM-008 finalEpoch mismatch'));
    });

    test('rejects GM-009 missing duplicate removal proof', () {
      final missingProof = _validGm009Verdicts();
      missingProof[0] = Map<String, dynamic>.from(missingProof[0])
        ..remove('gm009DuplicateRemovalProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing GM-009 duplicate removal proof fields'),
      );
    });

    test('rejects GM-009 duplicate rotation or Charlie key distribution', () {
      final duplicateRotation = _validGm009Verdicts();
      duplicateRotation[0] = {
        ...duplicateRotation[0],
        'gm009DuplicateRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            duplicateRotation[0]['gm009DuplicateRemovalProof'] as Map,
          ),
          'rotationCount': 2,
          'keyDistributionCount': 2,
          'distributedKeyToCharlie': true,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: duplicateRotation,
      );

      expect(rejected.ok, isFalse);
      expect(rejected.detail, contains('rotationCount must be 1'));
      expect(rejected.detail, contains('keyDistributionCount must be 1'));
      expect(
        rejected.detail,
        contains('distributedKeyToCharlie must be false'),
      );
    });

    test('rejects GM-009 Charlie member state or post-removal access', () {
      final staleCharlie = _validGm009Verdicts();
      staleCharlie[1] = {
        ...staleCharlie[1],
        'memberPeerIds': const <String>[
          'alice-peer',
          'bob-peer',
          'charlie-peer',
        ],
      };
      staleCharlie[2] = {
        ...staleCharlie[2],
        'memberPeerIds': const <String>['charlie-peer'],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterDuplicateRemove',
            'gm009-a-after',
            'alice after duplicate remove',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterDuplicateRemove': 1,
        },
        'gm009DuplicateRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            staleCharlie[2]['gm009DuplicateRemovalProof'] as Map,
          ),
          'groupPresentAfterDuplicateRemoval': true,
          'postRemovalPublishAccepted': true,
          'receivedAlicePostDuplicateRemove': true,
          'postRemovalPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: staleCharlie,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: post-removal membership still includes charlie'),
      );
      expect(
        rejected.detail,
        contains('groupPresentAfterDuplicateRemoval must be false'),
      );
      expect(
        rejected.detail,
        contains('postRemovalPublishAccepted must be false'),
      );
      expect(rejected.detail, contains('postRemovalPlaintextCount must be 0'));
    });

    test('rejects GM-009 missing A/B post-removal delivery', () {
      final missingDelivery = _validGm009Verdicts();
      missingDelivery[0] = {
        ...missingDelivery[0],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
      };
      missingDelivery[1] = {
        ...missingDelivery[1],
        'receivedMessages': const <Map<String, Object?>>[],
        'persistedMessageCounts': const <String, int>{},
        'gm009DuplicateRemovalProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingDelivery[1]['gm009DuplicateRemovalProof'] as Map,
          ),
          'receivedAlicePostDuplicateRemove': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm009',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingDelivery,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('alice: missing received proof keys bobAfterDuplicateRemove'),
      );
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceAfterDuplicateRemove'),
      );
      expect(
        rejected.detail,
        contains('receivedAlicePostDuplicateRemove must be true'),
      );
    });

    test('rejects GM-007 missing history-boundary proof', () {
      final missingProof = _validGm007Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('gm007HistoryBoundaryProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing GM-007 history-boundary proof fields'),
      );
    });

    test('rejects GM-007 without KE-018 replay-window proof', () {
      final missingProof = _validGm007Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ke018HistoryReplayEpochWindowProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing KE-018 history replay epoch-window proof'),
      );
    });

    test('rejects GM-007 without IR-005 re-add replay proof', () {
      final missingProof = _validGm007Verdicts();
      missingProof[2] = Map<String, dynamic>.from(missingProof[2])
        ..remove('ir005ReaddReplayProof');

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingProof,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing IR-005 re-add replay proof'),
      );
    });

    test('rejects IR-005 proof with Charlie removed-window replay', () {
      final leaked = _validGm007Verdicts();
      leaked[2] = {
        ...leaked[2],
        'ir005ReaddReplayProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['ir005ReaddReplayProof'] as Map,
          ),
          'noRemovedWindowReplayAfterDrain': false,
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('noRemovedWindowReplayAfterDrain must be true'),
      );
      expect(
        rejected.detail,
        contains('ir005ReaddReplayProof.removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects GM-007 Charlie missing pre-removal delivery', () {
      final missingPreRemoval = _validGm007Verdicts();
      missingPreRemoval[2] = {
        ...missingPreRemoval[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceAfterCharlieReadd',
            'gm007-a-after',
            'alice after charlie readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceAfterCharlieReadd': 1,
        },
        'gm007HistoryBoundaryProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingPreRemoval[2]['gm007HistoryBoundaryProof'] as Map,
          ),
          'receivedPreRemovalMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingPreRemoval,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: missing received proof keys aliceBeforeCharlieRemoval',
        ),
      );
      expect(
        rejected.detail,
        contains('receivedPreRemovalMessage must be true'),
      );
    });

    test('rejects GM-007 Charlie removed-window plaintext', () {
      final leaked = _validGm007Verdicts();
      leaked[2] = {
        ...leaked[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeCharlieRemoval',
            'gm007-a-before',
            'alice before charlie removal',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'aliceDuringCharlieRemoval2',
            'gm007-a-during-2',
            'alice during charlie removal 2',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterCharlieReadd',
            'gm007-a-after',
            'alice after charlie readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeCharlieRemoval': 1,
          'aliceDuringCharlieRemoval2': 1,
          'aliceAfterCharlieReadd': 1,
        },
        'gm007HistoryBoundaryProof': <String, Object?>{
          ...Map<String, Object?>.from(
            leaked[2]['gm007HistoryBoundaryProof'] as Map,
          ),
          'removedWindowPlaintextCount': 1,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: leaked,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains(
          'charlie: unexpected received proof keys aliceDuringCharlieRemoval2',
        ),
      );
      expect(
        rejected.detail,
        contains('removedWindowPlaintextCount must be 0'),
      );
    });

    test('rejects GM-007 Bob missing removed-window delivery', () {
      final missingWindow = _validGm007Verdicts();
      missingWindow[1] = {
        ...missingWindow[1],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeCharlieRemoval',
            'gm007-a-before',
            'alice before charlie removal',
            'alice-peer',
            keyEpoch: 1,
          ),
          _received(
            'aliceDuringCharlieRemoval1',
            'gm007-a-during-1',
            'alice during charlie removal 1',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceDuringCharlieRemoval2',
            'gm007-a-during-2',
            'alice during charlie removal 2',
            'alice-peer',
            keyEpoch: 2,
          ),
          _received(
            'aliceAfterCharlieReadd',
            'gm007-a-after',
            'alice after charlie readd',
            'alice-peer',
            keyEpoch: 2,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeCharlieRemoval': 1,
          'aliceDuringCharlieRemoval1': 1,
          'aliceDuringCharlieRemoval2': 1,
          'aliceAfterCharlieReadd': 1,
        },
        'gm007HistoryBoundaryProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingWindow[1]['gm007HistoryBoundaryProof'] as Map,
          ),
          'receivedRemovedWindowMessageCount': 2,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingWindow,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('bob: missing received proof keys aliceDuringCharlieRemoval3'),
      );
      expect(
        rejected.detail,
        contains('receivedRemovedWindowMessageCount must be 3'),
      );
    });

    test('rejects GM-007 Charlie missing post-readd delivery', () {
      final missingPostReadd = _validGm007Verdicts();
      missingPostReadd[2] = {
        ...missingPostReadd[2],
        'receivedMessages': <Map<String, Object?>>[
          _received(
            'aliceBeforeCharlieRemoval',
            'gm007-a-before',
            'alice before charlie removal',
            'alice-peer',
            keyEpoch: 1,
          ),
        ],
        'persistedMessageCounts': const <String, int>{
          'aliceBeforeCharlieRemoval': 1,
        },
        'gm007HistoryBoundaryProof': <String, Object?>{
          ...Map<String, Object?>.from(
            missingPostReadd[2]['gm007HistoryBoundaryProof'] as Map,
          ),
          'receivedPostReaddMessage': false,
        },
      };

      final rejected = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: missingPostReadd,
      );

      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('charlie: missing received proof keys aliceAfterCharlieReadd'),
      );
      expect(
        rejected.detail,
        contains('receivedPostReaddMessage must be true'),
      );
    });
  });
}

List<Map<String, dynamic>> _validGe001Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const aliceSent = <String, Object?>{
    'key': 'aliceGe001Initial',
    'messageId': 'ge001-a1',
    'text': 'hello ge001 from alice',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
  };
  const bobSent = <String, Object?>{
    'key': 'bobGe001Initial',
    'messageId': 'ge001-b1',
    'text': 'hello ge001 from bob',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
  };
  const charlieSent = <String, Object?>{
    'key': 'charlieGe001Initial',
    'messageId': 'ge001-c1',
    'text': 'hello ge001 from charlie',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
  };
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge001',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge001-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe001Initial',
          'ge001-b1',
          'hello ge001 from bob',
          'bob-peer',
        ),
        _received(
          'charlieGe001Initial',
          'ge001-c1',
          'hello ge001 from charlie',
          'charlie-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe001Initial': 1,
        'charlieGe001Initial': 1,
      },
    ),
    _baseVerdict(
      scenario: 'ge001',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge001-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe001Initial',
          'ge001-a1',
          'hello ge001 from alice',
          'alice-peer',
        ),
        _received(
          'charlieGe001Initial',
          'ge001-c1',
          'hello ge001 from charlie',
          'charlie-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe001Initial': 1,
        'charlieGe001Initial': 1,
      },
    ),
    _baseVerdict(
      scenario: 'ge001',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge001-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[charlieSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe001Initial',
          'ge001-a1',
          'hello ge001 from alice',
          'alice-peer',
        ),
        _received(
          'bobGe001Initial',
          'ge001-b1',
          'hello ge001 from bob',
          'bob-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe001Initial': 1,
        'bobGe001Initial': 1,
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe002Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  final sentMessages = <Map<String, Object?>>[];
  final receivedMessages = <Map<String, Object?>>[];
  final persistedCounts = <String, int>{};
  final keys = <String>[];

  for (var index = 0; index < 10; index++) {
    final ordinal = (index + 1).toString().padLeft(2, '0');
    final key = 'aliceGe002PostRemoval$ordinal';
    final messageId = 'ge002-a-$ordinal';
    final text = 'ge002 alice post removal $ordinal';
    keys.add(key);
    sentMessages.add(<String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 1,
      'recipientPeerIds': const <String>['bob-peer'],
      'actualDurablePayloadProof': true,
    });
    receivedMessages.add(
      _received(key, messageId, text, 'alice-peer', keyEpoch: 1),
    );
    persistedCounts[key] = 1;
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge002',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge002-group',
      memberPeerIds: remainingMembers,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'ge002RemovalContinuityProof': <String, Object?>{
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'actualDurablePayloadProof': true,
          'postRemovalMessageCount': 10,
          'postRemovalMessageKeys': keys,
          'everyPostRemovalExcludedCharlie': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge002',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge002-group',
      memberPeerIds: remainingMembers,
      receivedMessages: receivedMessages,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ge002RemovalContinuityProof': <String, Object?>{
          'receivedEveryPostRemovalMessage': true,
          'postRemovalReceiptCount': 10,
          'postRemovalMessageKeys': keys,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge002',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge002-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: <String, Object?>{
        'ge002RemovalContinuityProof': <String, Object?>{
          'selfRemoved': true,
          'groupPresentAfterRemoval': false,
          'postRemovalPlaintextCount': 0,
          'checkedPostRemovalMessageCount': 10,
          'postRemovalMessageKeys': keys,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe003Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  final sentMessages = <Map<String, Object?>>[];
  final receivedMessages = <Map<String, Object?>>[];
  final persistedCounts = <String, int>{};
  final keys = <String>[];

  for (var index = 0; index < 10; index++) {
    final ordinal = (index + 1).toString().padLeft(2, '0');
    final key = 'bobGe003PostRemoval$ordinal';
    final messageId = 'ge003-b-$ordinal';
    final text = 'ge003 bob post removal $ordinal';
    keys.add(key);
    sentMessages.add(<String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': 'bob-peer',
      'keyEpoch': 1,
      'recipientPeerIds': const <String>['alice-peer'],
      'actualDurablePayloadProof': true,
    });
    receivedMessages.add(
      _received(key, messageId, text, 'bob-peer', keyEpoch: 1),
    );
    persistedCounts[key] = 1;
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge003',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge003-group',
      memberPeerIds: remainingMembers,
      receivedMessages: receivedMessages,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ge003RemainingPairProof': <String, Object?>{
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'receivedEveryPostRemovalMessage': true,
          'postRemovalReceiptCount': 10,
          'postRemovalMessageKeys': keys,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge003',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge003-group',
      memberPeerIds: remainingMembers,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'ge003RemainingPairProof': <String, Object?>{
          'actualDurablePayloadProof': true,
          'postRemovalMessageCount': 10,
          'postRemovalMessageKeys': keys,
          'everyPostRemovalExcludedCharlie': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge003',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge003-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: <String, Object?>{
        'ge003RemainingPairProof': <String, Object?>{
          'selfRemoved': true,
          'groupPresentAfterRemoval': false,
          'postRemovalPlaintextCount': 0,
          'checkedPostRemovalMessageCount': 10,
          'postRemovalMessageKeys': keys,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe004Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge004ReaddExchangeProof';
  const aliceSent = <String, Object?>{
    'key': 'aliceGe004PostReadd',
    'messageId': 'ge004-a1',
    'text': 'ge004 alice after readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobSent = <String, Object?>{
    'key': 'bobGe004PostReadd',
    'messageId': 'ge004-b1',
    'text': 'ge004 bob after readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const charlieSent = <String, Object?>{
    'key': 'charlieGe004PostReadd',
    'messageId': 'ge004-c1',
    'text': 'ge004 charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };

  Map<String, Object?> proof({
    required String sentKey,
    required List<String> receivedKeys,
    bool includeAliceRemovalFields = false,
  }) {
    return <String, Object?>{
      if (includeAliceRemovalFields) ...<String, Object?>{
        'removedCharlie': true,
        'removedPeerId': 'charlie-peer',
        'readdedPeerId': 'charlie-peer',
      },
      'readdedCharlie': true,
      'memberListIncludesAll': true,
      'actualDurablePayloadProof': true,
      'postReaddSentCount': 1,
      'postReaddReceivedCount': 2,
      'postReaddSentKeys': <String>[sentKey],
      'postReaddReceivedKeys': receivedKeys,
      'finalMemberPeerIds': members,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge004',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge004-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe004PostReadd',
          'ge004-b1',
          'ge004 bob after readd',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'charlieGe004PostReadd',
          'ge004-c1',
          'ge004 charlie after readd',
          'charlie-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe004PostReadd': 1,
        'charlieGe004PostReadd': 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          sentKey: 'aliceGe004PostReadd',
          receivedKeys: const <String>[
            'bobGe004PostReadd',
            'charlieGe004PostReadd',
          ],
          includeAliceRemovalFields: true,
        ),
      },
    ),
    _baseVerdict(
      scenario: 'ge004',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge004-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe004PostReadd',
          'ge004-a1',
          'ge004 alice after readd',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'charlieGe004PostReadd',
          'ge004-c1',
          'ge004 charlie after readd',
          'charlie-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe004PostReadd': 1,
        'charlieGe004PostReadd': 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          sentKey: 'bobGe004PostReadd',
          receivedKeys: const <String>[
            'aliceGe004PostReadd',
            'charlieGe004PostReadd',
          ],
        ),
      },
    ),
    _baseVerdict(
      scenario: 'ge004',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge004-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[charlieSent],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe004PostReadd',
          'ge004-a1',
          'ge004 alice after readd',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'bobGe004PostReadd',
          'ge004-b1',
          'ge004 bob after readd',
          'bob-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe004PostReadd': 1,
        'bobGe004PostReadd': 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          sentKey: 'charlieGe004PostReadd',
          receivedKeys: const <String>[
            'aliceGe004PostReadd',
            'bobGe004PostReadd',
          ],
        ),
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe005Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge005RemoveReaddLoopProof';
  const cycleCount = 20;
  final removedKeys = <String>[
    for (var cycle = 1; cycle <= cycleCount; cycle++)
      'aliceGe005Removed${cycle.toString().padLeft(2, '0')}',
  ];
  final readdKeys = <String>[
    for (var cycle = 1; cycle <= cycleCount; cycle++)
      'bobGe005Readd${cycle.toString().padLeft(2, '0')}',
  ];
  final aliceSent = <Map<String, Object?>>[
    for (var cycle = 1; cycle <= cycleCount; cycle++)
      {
        'key': removedKeys[cycle - 1],
        'messageId': 'ge005-removed-${cycle.toString().padLeft(2, '0')}',
        'text': 'ge005 removed window ${cycle.toString().padLeft(2, '0')}',
        'outcome': 'success',
        'senderPeerId': 'alice-peer',
        'keyEpoch': 1,
        'recipientPeerIds': <String>['bob-peer'],
        'actualDurablePayloadProof': true,
      },
  ];
  final bobSent = <Map<String, Object?>>[
    for (var cycle = 1; cycle <= cycleCount; cycle++)
      {
        'key': readdKeys[cycle - 1],
        'messageId': 'ge005-readd-${cycle.toString().padLeft(2, '0')}',
        'text': 'ge005 readd window ${cycle.toString().padLeft(2, '0')}',
        'outcome': 'success',
        'senderPeerId': 'bob-peer',
        'keyEpoch': 1,
        'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
        'actualDurablePayloadProof': true,
      },
  ];

  Map<String, Object?> proof({
    required int removedWindowSentCount,
    required int removedWindowReceivedCount,
    required int readdWindowSentCount,
    required int readdWindowReceivedCount,
    required int removedWindowPlaintextCount,
    required List<String> removedWindowSentKeys,
    required List<String> removedWindowReceivedKeys,
    required List<String> readdWindowSentKeys,
    required List<String> readdWindowReceivedKeys,
    bool actualDurablePayloadProof = false,
    bool removedWindowExcludedCharlie = false,
    bool readdWindowIncludedCharlie = false,
  }) {
    return <String, Object?>{
      'cycleCount': cycleCount,
      'completedCycleCount': cycleCount,
      'finalMemberListIncludesAll': true,
      'finalMemberPeerIds': members,
      'actualDurablePayloadProof': actualDurablePayloadProof,
      'removedWindowExcludedCharlie': removedWindowExcludedCharlie,
      'readdWindowIncludedCharlie': readdWindowIncludedCharlie,
      'removedWindowSentCount': removedWindowSentCount,
      'removedWindowReceivedCount': removedWindowReceivedCount,
      'readdWindowSentCount': readdWindowSentCount,
      'readdWindowReceivedCount': readdWindowReceivedCount,
      'removedWindowPlaintextCount': removedWindowPlaintextCount,
      'removedWindowSentKeys': removedWindowSentKeys,
      'removedWindowReceivedKeys': removedWindowReceivedKeys,
      'readdWindowSentKeys': readdWindowSentKeys,
      'readdWindowReceivedKeys': readdWindowReceivedKeys,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge005',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge005-group',
      memberPeerIds: members,
      sentMessages: aliceSent,
      receivedMessages: <Map<String, Object?>>[
        for (var cycle = 1; cycle <= cycleCount; cycle++)
          _received(
            readdKeys[cycle - 1],
            'ge005-readd-${cycle.toString().padLeft(2, '0')}',
            'ge005 readd window ${cycle.toString().padLeft(2, '0')}',
            'bob-peer',
            keyEpoch: 1,
          ),
      ],
      persistedMessageCounts: <String, int>{
        for (final key in readdKeys) key: 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          removedWindowSentCount: cycleCount,
          removedWindowReceivedCount: 0,
          readdWindowSentCount: 0,
          readdWindowReceivedCount: cycleCount,
          removedWindowPlaintextCount: 0,
          removedWindowSentKeys: removedKeys,
          removedWindowReceivedKeys: const <String>[],
          readdWindowSentKeys: const <String>[],
          readdWindowReceivedKeys: readdKeys,
          actualDurablePayloadProof: true,
          removedWindowExcludedCharlie: true,
        ),
      },
    ),
    _baseVerdict(
      scenario: 'ge005',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge005-group',
      memberPeerIds: members,
      sentMessages: bobSent,
      receivedMessages: <Map<String, Object?>>[
        for (var cycle = 1; cycle <= cycleCount; cycle++)
          _received(
            removedKeys[cycle - 1],
            'ge005-removed-${cycle.toString().padLeft(2, '0')}',
            'ge005 removed window ${cycle.toString().padLeft(2, '0')}',
            'alice-peer',
            keyEpoch: 1,
          ),
      ],
      persistedMessageCounts: <String, int>{
        for (final key in removedKeys) key: 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          removedWindowSentCount: 0,
          removedWindowReceivedCount: cycleCount,
          readdWindowSentCount: cycleCount,
          readdWindowReceivedCount: 0,
          removedWindowPlaintextCount: 0,
          removedWindowSentKeys: const <String>[],
          removedWindowReceivedKeys: removedKeys,
          readdWindowSentKeys: readdKeys,
          readdWindowReceivedKeys: const <String>[],
          actualDurablePayloadProof: true,
          readdWindowIncludedCharlie: true,
        ),
      },
    ),
    _baseVerdict(
      scenario: 'ge005',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge005-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        for (var cycle = 1; cycle <= cycleCount; cycle++)
          _received(
            readdKeys[cycle - 1],
            'ge005-readd-${cycle.toString().padLeft(2, '0')}',
            'ge005 readd window ${cycle.toString().padLeft(2, '0')}',
            'bob-peer',
            keyEpoch: 1,
          ),
      ],
      persistedMessageCounts: <String, int>{
        for (final key in readdKeys) key: 1,
      },
      extra: <String, Object?>{
        proofName: proof(
          removedWindowSentCount: 0,
          removedWindowReceivedCount: 0,
          readdWindowSentCount: 0,
          readdWindowReceivedCount: cycleCount,
          removedWindowPlaintextCount: 0,
          removedWindowSentKeys: const <String>[],
          removedWindowReceivedKeys: const <String>[],
          readdWindowSentKeys: const <String>[],
          readdWindowReceivedKeys: readdKeys,
        ),
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe006Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge006OfflineReaddProof';
  const aliceRemoved = <String, Object?>{
    'key': 'aliceGe006RemovedWindow',
    'messageId': 'ge006-removed-window',
    'text': 'ge006 removed window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const alicePost = <String, Object?>{
    'key': 'aliceGe006PostReadd',
    'messageId': 'ge006-alice-post-readd',
    'text': 'ge006 alice post readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobPost = <String, Object?>{
    'key': 'bobGe006PostReadd',
    'messageId': 'ge006-bob-post-readd',
    'text': 'ge006 bob post readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const charliePost = <String, Object?>{
    'key': 'charlieGe006PostCatchUp',
    'messageId': 'ge006-charlie-post-catchup',
    'text': 'ge006 charlie post catchup',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge006',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge006-group',
      keyEpoch: 2,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceRemoved, alicePost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe006PostReadd',
          'ge006-bob-post-readd',
          'ge006 bob post readd',
          'bob-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe006PostCatchUp',
          'ge006-charlie-post-catchup',
          'ge006 charlie post catchup',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe006PostReadd': 1,
        'charlieGe006PostCatchUp': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'charlieOfflineDuringMutation': true,
          'removedWindowExcludedCharlie': true,
          'postReaddDurableIncludesCharlie': true,
          'receivedBobPostReaddMessage': true,
          'receivedCharliePostCatchUpMessage': true,
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge006',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge006-group',
      keyEpoch: 2,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobPost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe006RemovedWindow',
          'ge006-removed-window',
          'ge006 removed window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGe006PostReadd',
          'ge006-alice-post-readd',
          'ge006 alice post readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe006PostCatchUp',
          'ge006-charlie-post-catchup',
          'ge006 charlie post catchup',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe006RemovedWindow': 1,
        'aliceGe006PostReadd': 1,
        'charlieGe006PostCatchUp': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'memberListIncludesCharlie': true,
          'receivedRemovedWindowMessage': true,
          'receivedAlicePostReaddMessage': true,
          'receivedCharliePostCatchUpMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge006',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge006-group',
      keyEpoch: 2,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[charliePost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe006PostReadd',
          'ge006-alice-post-readd',
          'ge006 alice post readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGe006PostReadd',
          'ge006-bob-post-readd',
          'ge006 bob post readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe006PostReadd': 1,
        'bobGe006PostReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'offlineDuringRemovalAndReadd': true,
          'retrievedInboxAfterReconnect': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'postCatchUpPublishAccepted': true,
          'removedWindowPlaintextCount': 0,
          'postReaddReceivedCount': 2,
          'postReaddReceivedKeys': <String>[
            'aliceGe006PostReadd',
            'bobGe006PostReadd',
          ],
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe007Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge007OfflineObserverProof';
  const aliceRemoved = <String, Object?>{
    'key': 'aliceGe007RemovedWindow',
    'messageId': 'ge007-removed-window',
    'text': 'ge007 removed window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const alicePost = <String, Object?>{
    'key': 'aliceGe007PostReadd',
    'messageId': 'ge007-alice-post-readd',
    'text': 'ge007 alice post readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const charliePost = <String, Object?>{
    'key': 'charlieGe007PostReadd',
    'messageId': 'ge007-charlie-post-readd',
    'text': 'ge007 charlie post readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobPost = <String, Object?>{
    'key': 'bobGe007PostCatchUp',
    'messageId': 'ge007-bob-post-catchup',
    'text': 'ge007 bob post catchup',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge007',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge007-group',
      keyEpoch: 1,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceRemoved, alicePost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGe007PostReadd',
          'ge007-charlie-post-readd',
          'ge007 charlie post readd',
          'charlie-peer',
        ),
        _received(
          'bobGe007PostCatchUp',
          'ge007-bob-post-catchup',
          'ge007 bob post catchup',
          'bob-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGe007PostReadd': 1,
        'bobGe007PostCatchUp': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'bobOfflineDuringMutation': true,
          'removedWindowDurableIncludesBob': true,
          'postReaddDurableIncludesBob': true,
          'receivedCharliePostReaddMessage': true,
          'receivedBobPostCatchUpMessage': true,
          'offlinePeerId': 'bob-peer',
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge007',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge007-group',
      keyEpoch: 1,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobPost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe007RemovedWindow',
          'ge007-removed-window',
          'ge007 removed window',
          'alice-peer',
        ),
        _received(
          'aliceGe007PostReadd',
          'ge007-alice-post-readd',
          'ge007 alice post readd',
          'alice-peer',
        ),
        _received(
          'charlieGe007PostReadd',
          'ge007-charlie-post-readd',
          'ge007 charlie post readd',
          'charlie-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe007RemovedWindow': 1,
        'aliceGe007PostReadd': 1,
        'charlieGe007PostReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'offlineDuringMutation': true,
          'retrievedInboxAfterReconnect': true,
          'memberListIncludesAliceCharlie': true,
          'memberListIncludesBob': true,
          'receivedRemovedWindowMessage': true,
          'receivedAlicePostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'postCatchUpPublishAccepted': true,
          'entitledReceivedCount': 3,
          'entitledReceivedKeys': <String>[
            'aliceGe007RemovedWindow',
            'aliceGe007PostReadd',
            'charlieGe007PostReadd',
          ],
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge007',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge007-group',
      keyEpoch: 1,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[charliePost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe007PostReadd',
          'ge007-alice-post-readd',
          'ge007 alice post readd',
          'alice-peer',
        ),
        _received(
          'bobGe007PostCatchUp',
          'ge007-bob-post-catchup',
          'ge007 bob post catchup',
          'bob-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe007PostReadd': 1,
        'bobGe007PostCatchUp': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'selfRemovedDuringMutation': true,
          'readdedCharlie': true,
          'memberListIncludesBob': true,
          'receivedAlicePostReaddMessage': true,
          'receivedBobPostCatchUpMessage': true,
          'finalEpoch': 1,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe008Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge008SendStormProof';
  const alicePre = <String>['aliceGe008Pre0', 'aliceGe008Pre1'];
  const bobPre = <String>['bobGe008Pre0', 'bobGe008Pre1'];
  const charliePre = <String>['charlieGe008Pre0', 'charlieGe008Pre1'];
  const aliceRemoved = <String>['aliceGe008Removed0', 'aliceGe008Removed1'];
  const bobRemoved = <String>['bobGe008Removed0', 'bobGe008Removed1'];
  const alicePost = <String>['aliceGe008Post0', 'aliceGe008Post1'];
  const bobPost = <String>['bobGe008Post0', 'bobGe008Post1'];
  const charliePost = <String>['charlieGe008Post0', 'charlieGe008Post1'];

  Map<String, Object?> sent(
    String key,
    String role,
    List<String> recipientPeerIds,
  ) {
    return <String, Object?>{
      'key': key,
      'messageId': 'ge008-$key',
      'text': 'ge008 $key',
      'outcome': 'success',
      'senderPeerId': '$role-peer',
      'keyEpoch': 1,
      'recipientPeerIds': recipientPeerIds,
      'actualDurablePayloadProof': true,
    };
  }

  List<Map<String, Object?>> received(List<MapEntry<String, String>> entries) {
    return <Map<String, Object?>>[
      for (final entry in entries)
        _received(
          entry.key,
          'ge008-${entry.key}',
          'ge008 ${entry.key}',
          '${entry.value}-peer',
        ),
    ];
  }

  Map<String, int> counts(List<Map<String, Object?>> entries) {
    return <String, int>{
      for (final entry in entries) entry['key'] as String: 1,
    };
  }

  final aliceSent = <Map<String, Object?>>[
    for (final key in alicePre)
      sent(key, 'alice', const <String>['bob-peer', 'charlie-peer']),
    for (final key in aliceRemoved)
      sent(key, 'alice', const <String>['bob-peer']),
    for (final key in alicePost)
      sent(key, 'alice', const <String>['bob-peer', 'charlie-peer']),
  ];
  final bobSent = <Map<String, Object?>>[
    for (final key in bobPre)
      sent(key, 'bob', const <String>['alice-peer', 'charlie-peer']),
    for (final key in bobRemoved)
      sent(key, 'bob', const <String>['alice-peer']),
    for (final key in bobPost)
      sent(key, 'bob', const <String>['alice-peer', 'charlie-peer']),
  ];
  final charlieSent = <Map<String, Object?>>[
    for (final key in charliePre)
      sent(key, 'charlie', const <String>['alice-peer', 'bob-peer']),
    for (final key in charliePost)
      sent(key, 'charlie', const <String>['alice-peer', 'bob-peer']),
  ];
  final aliceReceived = received(<MapEntry<String, String>>[
    for (final key in bobPre) MapEntry<String, String>(key, 'bob'),
    for (final key in charliePre) MapEntry<String, String>(key, 'charlie'),
    for (final key in bobRemoved) MapEntry<String, String>(key, 'bob'),
    for (final key in bobPost) MapEntry<String, String>(key, 'bob'),
    for (final key in charliePost) MapEntry<String, String>(key, 'charlie'),
  ]);
  final bobReceived = received(<MapEntry<String, String>>[
    for (final key in alicePre) MapEntry<String, String>(key, 'alice'),
    for (final key in charliePre) MapEntry<String, String>(key, 'charlie'),
    for (final key in aliceRemoved) MapEntry<String, String>(key, 'alice'),
    for (final key in alicePost) MapEntry<String, String>(key, 'alice'),
    for (final key in charliePost) MapEntry<String, String>(key, 'charlie'),
  ]);
  final charlieReceived = received(<MapEntry<String, String>>[
    for (final key in alicePre) MapEntry<String, String>(key, 'alice'),
    for (final key in bobPre) MapEntry<String, String>(key, 'bob'),
    for (final key in alicePost) MapEntry<String, String>(key, 'alice'),
    for (final key in bobPost) MapEntry<String, String>(key, 'bob'),
  ]);

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge008',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge008-group',
      memberPeerIds: members,
      sentMessages: aliceSent,
      receivedMessages: aliceReceived,
      persistedMessageCounts: counts(aliceReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'preStormComplete': true,
          'removedWindowComplete': true,
          'postReaddStormComplete': true,
          'charlieExcludedDuringRemovedWindow': true,
          'duplicateDeliveryDeduped': true,
          'receivedBobRemovedWindowMessages': true,
          'receivedCharliePostReaddMessages': true,
          'preStormSentCount': 2,
          'removedWindowSentCount': 2,
          'postReaddSentCount': 2,
          'preStormReceivedCount': 4,
          'removedWindowReceivedCount': 2,
          'postReaddReceivedCount': 4,
          'receivedPreStormKeys': <String>[
            'bobGe008Pre0',
            'bobGe008Pre1',
            'charlieGe008Pre0',
            'charlieGe008Pre1',
          ],
          'receivedRemovedWindowKeys': <String>[
            'bobGe008Removed0',
            'bobGe008Removed1',
          ],
          'receivedPostReaddKeys': <String>[
            'bobGe008Post0',
            'bobGe008Post1',
            'charlieGe008Post0',
            'charlieGe008Post1',
          ],
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge008',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge008-group',
      memberPeerIds: members,
      sentMessages: bobSent,
      receivedMessages: bobReceived,
      persistedMessageCounts: counts(bobReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'preStormComplete': true,
          'removedWindowComplete': true,
          'postReaddStormComplete': true,
          'memberListExcludesCharlieDuringRemovedWindow': true,
          'memberListIncludesAliceCharlie': true,
          'duplicateDeliveryDeduped': true,
          'receivedAliceRemovedWindowMessages': true,
          'receivedCharliePostReaddMessages': true,
          'preStormSentCount': 2,
          'removedWindowSentCount': 2,
          'postReaddSentCount': 2,
          'preStormReceivedCount': 4,
          'removedWindowReceivedCount': 2,
          'postReaddReceivedCount': 4,
          'receivedPreStormKeys': <String>[
            'aliceGe008Pre0',
            'aliceGe008Pre1',
            'charlieGe008Pre0',
            'charlieGe008Pre1',
          ],
          'receivedRemovedWindowKeys': <String>[
            'aliceGe008Removed0',
            'aliceGe008Removed1',
          ],
          'receivedPostReaddKeys': <String>[
            'aliceGe008Post0',
            'aliceGe008Post1',
            'charlieGe008Post0',
            'charlieGe008Post1',
          ],
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge008',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge008-group',
      memberPeerIds: members,
      sentMessages: charlieSent,
      receivedMessages: charlieReceived,
      persistedMessageCounts: counts(charlieReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'selfRemovedDuringStorm': true,
          'staleRemovedWindowSendsRejected': true,
          'readdedCharlie': true,
          'preStormComplete': true,
          'postReaddStormComplete': true,
          'duplicateDeliveryDeduped': true,
          'receivedPostReaddStormMessages': true,
          'preStormSentCount': 2,
          'postReaddSentCount': 2,
          'preStormReceivedCount': 4,
          'postReaddReceivedCount': 4,
          'staleRemovedWindowAttemptCount': 2,
          'staleRemovedWindowAcceptedCount': 0,
          'staleRemovedWindowPublishCount': 0,
          'removedWindowPlaintextCount': 0,
          'receivedPreStormKeys': <String>[
            'aliceGe008Pre0',
            'aliceGe008Pre1',
            'bobGe008Pre0',
            'bobGe008Pre1',
          ],
          'receivedPostReaddKeys': <String>[
            'aliceGe008Post0',
            'aliceGe008Post1',
            'bobGe008Post0',
            'bobGe008Post1',
          ],
          'rejectedRemovedWindowKeys': <String>[
            'charlieGe008RemovedStale0',
            'charlieGe008RemovedStale1',
          ],
          'finalEpoch': 1,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe009Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge009PartitionHealProof';
  const allKeys = <String>[
    'aliceGe009BeforePartition',
    'bobGe009BeforePartition',
    'charlieGe009BeforePartition',
    'aliceGe009PostReadd',
    'bobGe009PostReadd',
    'charlieGe009AfterHeal',
  ];

  Map<String, Object?> sent(
    String key,
    String role,
    List<String> recipientPeerIds,
  ) {
    return <String, Object?>{
      'key': key,
      'messageId': 'ge009-$key',
      'text': 'ge009 $key',
      'outcome': 'success',
      'senderPeerId': '$role-peer',
      'keyEpoch': 1,
      'recipientPeerIds': recipientPeerIds,
      'actualDurablePayloadProof': true,
    };
  }

  List<Map<String, Object?>> received(List<MapEntry<String, String>> entries) {
    return <Map<String, Object?>>[
      for (final entry in entries)
        _received(
          entry.key,
          'ge009-${entry.key}',
          'ge009 ${entry.key}',
          '${entry.value}-peer',
        ),
    ];
  }

  Map<String, int> counts(List<Map<String, Object?>> entries) {
    return <String, int>{
      for (final entry in entries) entry['key'] as String: 1,
    };
  }

  final aliceSent = <Map<String, Object?>>[
    sent('aliceGe009BeforePartition', 'alice', const <String>[
      'bob-peer',
      'charlie-peer',
    ]),
    sent('aliceGe009PostReadd', 'alice', const <String>[
      'bob-peer',
      'charlie-peer',
    ]),
  ];
  final bobSent = <Map<String, Object?>>[
    sent('bobGe009BeforePartition', 'bob', const <String>[
      'alice-peer',
      'charlie-peer',
    ]),
    sent('bobGe009PostReadd', 'bob', const <String>[
      'alice-peer',
      'charlie-peer',
    ]),
  ];
  final charlieSent = <Map<String, Object?>>[
    sent('charlieGe009BeforePartition', 'charlie', const <String>[
      'alice-peer',
      'bob-peer',
    ]),
    sent('charlieGe009AfterHeal', 'charlie', const <String>[
      'alice-peer',
      'bob-peer',
    ]),
  ];
  final aliceReceived = received(const <MapEntry<String, String>>[
    MapEntry<String, String>('bobGe009BeforePartition', 'bob'),
    MapEntry<String, String>('charlieGe009BeforePartition', 'charlie'),
    MapEntry<String, String>('bobGe009PostReadd', 'bob'),
    MapEntry<String, String>('charlieGe009AfterHeal', 'charlie'),
  ]);
  final bobReceived = received(const <MapEntry<String, String>>[
    MapEntry<String, String>('aliceGe009BeforePartition', 'alice'),
    MapEntry<String, String>('charlieGe009BeforePartition', 'charlie'),
    MapEntry<String, String>('aliceGe009PostReadd', 'alice'),
    MapEntry<String, String>('charlieGe009AfterHeal', 'charlie'),
  ]);
  final charlieReceived = received(const <MapEntry<String, String>>[
    MapEntry<String, String>('aliceGe009BeforePartition', 'alice'),
    MapEntry<String, String>('bobGe009BeforePartition', 'bob'),
    MapEntry<String, String>('aliceGe009PostReadd', 'alice'),
    MapEntry<String, String>('bobGe009PostReadd', 'bob'),
  ]);

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge009',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge009-group',
      memberPeerIds: members,
      sentMessages: aliceSent,
      receivedMessages: aliceReceived,
      persistedMessageCounts: counts(aliceReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'partitionedDuringMembershipMutation': true,
          'removedAndReaddedCharlie': true,
          'partitionHealed': true,
          'finalMembershipConverged': true,
          'finalTimelineConverged': true,
          'duplicateDeliveryDeduped': true,
          'charlieExcludedDuringPartition': true,
          'postReaddDurableIncludedCharlie': true,
          'receivedBobPostReaddReplay': true,
          'receivedCharlieAfterHeal': true,
          'receivedPrePartitionKeys': <String>[
            'bobGe009BeforePartition',
            'charlieGe009BeforePartition',
          ],
          'receivedPostHealKeys': <String>[
            'bobGe009PostReadd',
            'charlieGe009AfterHeal',
          ],
          'finalTimelineKeys': allKeys,
          'finalMessageCount': 6,
          'finalMemberPeerIds': members,
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge009',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge009-group',
      memberPeerIds: members,
      sentMessages: bobSent,
      receivedMessages: bobReceived,
      persistedMessageCounts: counts(bobReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'partitionedDuringMembershipMutation': true,
          'removedAndReaddedCharlie': true,
          'partitionHealed': true,
          'finalMembershipConverged': true,
          'finalTimelineConverged': true,
          'duplicateDeliveryDeduped': true,
          'charlieExcludedDuringPartition': true,
          'postReaddDurableIncludedCharlie': true,
          'receivedAlicePostReaddReplay': true,
          'receivedCharlieAfterHeal': true,
          'receivedPrePartitionKeys': <String>[
            'aliceGe009BeforePartition',
            'charlieGe009BeforePartition',
          ],
          'receivedPostHealKeys': <String>[
            'aliceGe009PostReadd',
            'charlieGe009AfterHeal',
          ],
          'finalTimelineKeys': allKeys,
          'finalMessageCount': 6,
          'finalMemberPeerIds': members,
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ge009',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge009-group',
      memberPeerIds: members,
      sentMessages: charlieSent,
      receivedMessages: charlieReceived,
      persistedMessageCounts: counts(charlieReceived),
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'partitionedDuringMembershipMutation': true,
          'removedAndReaddedCharlie': true,
          'partitionHealed': true,
          'finalMembershipConverged': true,
          'finalTimelineConverged': true,
          'duplicateDeliveryDeduped': true,
          'isolatedFromLiveTopicDuringMutation': true,
          'drainedReplayAfterHeal': true,
          'receivedAliceBobReplayAfterHeal': true,
          'postHealPublishAccepted': true,
          'removedWindowPlaintextCount': 0,
          'receivedPrePartitionKeys': <String>[
            'aliceGe009BeforePartition',
            'bobGe009BeforePartition',
          ],
          'postReaddReplayKeys': <String>[
            'aliceGe009PostReadd',
            'bobGe009PostReadd',
          ],
          'finalTimelineKeys': allKeys,
          'finalMessageCount': 6,
          'finalMemberPeerIds': members,
          'finalEpoch': 1,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe010Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge010ZeroLivePeersInboxFallbackProof';
  const key = 'aliceGe010ZeroPeerFallback';
  const sent = <String, Object?>{
    'key': key,
    'messageId': 'ge010-zero-peer',
    'text': 'ge010 zero peer',
    'outcome': 'successNoPeers',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'topicPeers': 0,
    'actualTopicPeerProof': true,
  };
  final received = _received(
    key,
    'ge010-zero-peer',
    'ge010 zero peer',
    'alice-peer',
    keyEpoch: 1,
  );
  const aliceProof = <String, Object?>{
    'bobLeftLiveTopicBeforeSend': true,
    'charlieLeftLiveTopicBeforeSend': true,
    'zeroLiveTopicPeersAtSend': true,
    'successNoPeers': true,
    'senderStatusSent': true,
    'inboxStored': true,
    'actualDurablePayloadProof': true,
    'honestSenderFallbackStatus': true,
    'noLiveDeliveryDuringSendWindow': true,
    'topicPeersAtSend': 0,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'sentKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };
  const receiverProof = <String, Object?>{
    'leftLiveTopicBeforeSend': true,
    'rejoinedLiveTopicAfterSend': true,
    'drainedInboxAfterReturn': true,
    'receivedZeroPeerMessage': true,
    'noDuplicatePersistence': true,
    'noLiveDeliveryDuringSendWindow': true,
    'senderEligibleAtSend': true,
    'postDrainPersistedCount': 1,
    'preRejoinPlaintextCount': 0,
    'receivedKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge010',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge010-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[sent],
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'ge010',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge010-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: receiverProof},
    ),
    _baseVerdict(
      scenario: 'ge010',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge010-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: receiverProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGo001Verdicts() {
  return _validGe010Verdicts()
      .map(
        (verdict) => <String, dynamic>{
          ...verdict,
          'scenario': 'go001',
          'groupId': 'go001-group',
        },
      )
      .toList();
}

List<Map<String, dynamic>> _validGo002Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'go002InboxStoreFailureSenderStatusProof';
  const key = 'aliceGo002InboxStoreFailure';
  const sent = <String, Object?>{
    'key': key,
    'messageId': 'go002-inbox-fail',
    'text': 'go002 inbox failure',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'failedInboxRecipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'forcedInboxStoreFailure': true,
    'senderStatusBeforeRetry': 'pending',
    'inboxStoredBeforeRetry': false,
    'retryPayloadBeforeRetry': true,
    'retryCount': 1,
    'senderStatusAfterRetry': 'sent',
    'inboxStoredAfterRetry': true,
    'retryPayloadAfterRetry': false,
    'actualDurablePayloadProof': true,
    'topicPeers': 2,
    'actualTopicPeerProof': true,
  };
  final received = _received(
    key,
    'go002-inbox-fail',
    'go002 inbox failure',
    'alice-peer',
    keyEpoch: 1,
  );
  const aliceProof = <String, Object?>{
    'publishSucceeded': true,
    'actualTopicPeerProof': true,
    'topicPeersPositive': true,
    'forcedInboxStoreFailure': true,
    'senderStatusPendingBeforeRetry': true,
    'inboxStoredFalseBeforeRetry': true,
    'retryPayloadPresentBeforeRetry': true,
    'notSilentlyReliableBeforeRetry': true,
    'retryCount': 1,
    'retryRanOnce': true,
    'retryPromotedToSent': true,
    'inboxStoredTrueAfterRetry': true,
    'retryPayloadClearedAfterRetry': true,
    'actualDurablePayloadProof': true,
    'topicPeersAtSend': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'failedInboxRecipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'sentKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };
  const receiverProof = <String, Object?>{
    'receivedLivePublish': true,
    'noDuplicatePersistence': true,
    'senderEligibleAtSend': true,
    'postRetryPersistedCount': 1,
    'receivedKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'go002',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'go002-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[sent],
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'go002',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'go002-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: receiverProof},
    ),
    _baseVerdict(
      scenario: 'go002',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'go002-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: receiverProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe011Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge011PartialLivePeersInboxFallbackProof';
  const key = 'aliceGe011PartialLiveFallback';
  const sent = <String, Object?>{
    'key': key,
    'messageId': 'ge011-partial-live',
    'text': 'ge011 partial live',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'topicPeers': 1,
    'actualTopicPeerProof': true,
  };
  final received = _received(
    key,
    'ge011-partial-live',
    'ge011 partial live',
    'alice-peer',
    keyEpoch: 1,
  );
  const aliceProof = <String, Object?>{
    'bobLiveTopicPeerAtSend': true,
    'charlieLeftLiveTopicBeforeSend': true,
    'partialLiveTopicPeersAtSend': true,
    'liveDeliveryToBobDuringSendWindow': true,
    'noLiveDeliveryToCharlieDuringSendWindow': true,
    'senderStatusSent': true,
    'inboxStored': true,
    'actualDurablePayloadProof': true,
    'honestPartialFallbackStatus': true,
    'topicPeersAtSend': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'sentKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };
  const bobProof = <String, Object?>{
    'liveTopicPeerAtSend': true,
    'receivedLiveDuringSendWindow': true,
    'drainedDuplicateInboxAfterLive': true,
    'noDuplicatePersistence': true,
    'senderEligibleAtSend': true,
    'preDrainPersistedCount': 1,
    'postDrainPersistedCount': 1,
    'receivedKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };
  const charlieProof = <String, Object?>{
    'leftLiveTopicBeforeSend': true,
    'rejoinedLiveTopicAfterSend': true,
    'drainedInboxAfterReturn': true,
    'receivedInboxMessage': true,
    'noLiveDeliveryDuringSendWindow': true,
    'noDuplicatePersistence': true,
    'senderEligibleAtSend': true,
    'postDrainPersistedCount': 1,
    'preRejoinPlaintextCount': 0,
    'receivedKeys': <String>[key],
    'finalMemberPeerIds': members,
    'finalKeyEpoch': 1,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge011',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge011-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[sent],
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'ge011',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge011-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'ge011',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge011-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{proofName: charlieProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe012Verdicts() {
  const members = <String>['alice-peer', 'bob-peer'];
  const proofName = 'ge012SameUserDeviceProof';
  const aliceKey = 'aliceGe012ToBobDevices';
  const bobPrimaryKey = 'bobGe012PrimarySend';
  const bobSiblingKey = 'bobGe012SiblingSend';
  const bobDevices = <String>['bob-device-1', 'bob-device-2'];
  const aliceSent = <String, Object?>{
    'key': aliceKey,
    'messageId': 'ge012-alice',
    'text': 'ge012 alice to bob devices',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
  };
  const bobPrimarySent = <String, Object?>{
    'key': bobPrimaryKey,
    'messageId': 'ge012-bob-primary',
    'text': 'ge012 bob primary',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device-1',
    'transportPeerId': 'bob-device-1',
    'keyEpoch': 1,
  };
  const bobSiblingSent = <String, Object?>{
    'key': bobSiblingKey,
    'messageId': 'ge012-bob-sibling',
    'text': 'ge012 bob sibling',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device-2',
    'transportPeerId': 'bob-device-2',
    'keyEpoch': 1,
  };

  Map<String, Object?> proof(String transportPeerId) => <String, Object?>{
    'logicalBobPeerId': 'bob-peer',
    'logicalBobMembershipCount': 1,
    'logicalBobDeviceIds': bobDevices,
    'memberPeerIds': members,
    'roleTransportPeerId': transportPeerId,
  };

  Map<String, Object?> received(
    String key,
    String messageId,
    String text,
    String senderPeerId, {
    required bool isIncoming,
  }) {
    return <String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'senderPeerId': senderPeerId,
      'keyEpoch': 1,
      'isIncoming': isIncoming,
      'persistedCount': 1,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge012',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge012-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceSent],
      receivedMessages: <Map<String, Object?>>[
        received(
          bobPrimaryKey,
          'ge012-bob-primary',
          'ge012 bob primary',
          'bob-peer',
          isIncoming: true,
        ),
        received(
          bobSiblingKey,
          'ge012-bob-sibling',
          'ge012 bob sibling',
          'bob-peer',
          isIncoming: true,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        bobPrimaryKey: 1,
        bobSiblingKey: 1,
      },
      extra: <String, Object?>{
        'transportPeerId': 'alice-device',
        proofName: proof('alice-device'),
      },
    ),
    _baseVerdict(
      scenario: 'ge012',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge012-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobPrimarySent],
      receivedMessages: <Map<String, Object?>>[
        received(
          aliceKey,
          'ge012-alice',
          'ge012 alice to bob devices',
          'alice-peer',
          isIncoming: true,
        ),
        received(
          bobSiblingKey,
          'ge012-bob-sibling',
          'ge012 bob sibling',
          'bob-peer',
          isIncoming: false,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        aliceKey: 1,
        bobSiblingKey: 1,
      },
      extra: <String, Object?>{
        'transportPeerId': 'bob-device-1',
        proofName: proof('bob-device-1'),
      },
    ),
    _baseVerdict(
      scenario: 'ge012',
      role: 'charlie',
      peerId: 'bob-peer',
      groupId: 'ge012-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobSiblingSent],
      receivedMessages: <Map<String, Object?>>[
        received(
          aliceKey,
          'ge012-alice',
          'ge012 alice to bob devices',
          'alice-peer',
          isIncoming: true,
        ),
        received(
          bobPrimaryKey,
          'ge012-bob-primary',
          'ge012 bob primary',
          'bob-peer',
          isIncoming: false,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        aliceKey: 1,
        bobPrimaryKey: 1,
      },
      extra: <String, Object?>{
        'transportPeerId': 'bob-device-2',
        proofName: proof('bob-device-2'),
      },
    ),
  ];
}

const _ge013BobSiblingBeforeKey = 'bobGe013SiblingBeforeRevoke';
const _ge013BobSiblingAfterKey = 'bobGe013SiblingAfterRevoke';
const _ge013BobPrimaryAfterKey = 'bobGe013PrimaryAfterRevoke';
const _ge013AliceAfterKey = 'aliceGe013AfterRevoke';

Map<String, Object?> _ge013Received(
  String key,
  String messageId,
  String text,
  String senderPeerId, {
  required bool isIncoming,
}) {
  return <String, Object?>{
    'key': key,
    'messageId': messageId,
    'text': text,
    'senderPeerId': senderPeerId,
    'keyEpoch': 1,
    'isIncoming': isIncoming,
    'persistedCount': 1,
  };
}

List<Map<String, dynamic>> _validGe013Verdicts() {
  const members = <String>['alice-peer', 'bob-peer'];
  const proofName = 'ge013DeviceRevocationProof';
  const activeBobDevices = <String>['bob-device-1'];
  const revokedBobDevices = <String>['bob-device-2'];
  const aliceSent = <String, Object?>{
    'key': _ge013AliceAfterKey,
    'messageId': 'ge013-alice-after',
    'text': 'ge013 alice after revoke',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
  };
  const bobPrimarySent = <String, Object?>{
    'key': _ge013BobPrimaryAfterKey,
    'messageId': 'ge013-bob-primary-after',
    'text': 'ge013 bob primary after revoke',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device-1',
    'transportPeerId': 'bob-device-1',
    'keyEpoch': 1,
  };
  const bobSiblingBeforeSent = <String, Object?>{
    'key': _ge013BobSiblingBeforeKey,
    'messageId': 'ge013-b2-before',
    'text': 'ge013 b2 before revoke',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device-2',
    'transportPeerId': 'bob-device-2',
    'keyEpoch': 1,
  };
  const bobSiblingAfterSent = <String, Object?>{
    'key': _ge013BobSiblingAfterKey,
    'messageId': 'ge013-b2-after',
    'text': 'ge013 b2 after revoke',
    'outcome': 'unauthorized',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device-2',
    'transportPeerId': 'bob-device-2',
    'accepted': false,
    'keyEpoch': 1,
  };

  Map<String, Object?> proof(
    String transportPeerId, {
    Object? b2PostRevokeOutcome,
    Object? b2PostRevokeAccepted,
  }) {
    return <String, Object?>{
      'logicalBobPeerId': 'bob-peer',
      'logicalBobMembershipCount': 1,
      'activeLogicalBobDeviceIds': activeBobDevices,
      'revokedLogicalBobDeviceIds': revokedBobDevices,
      'revokedSiblingDeviceId': 'bob-device-2',
      'primaryDeviceId': 'bob-device-1',
      'memberPeerIds': members,
      'roleTransportPeerId': transportPeerId,
      'revocationApplied': true,
      'b1RemainedActive': true,
      'b1FunctionalAfterRevoke': true,
      'aliceFunctionalAfterRevoke': true,
      'b2PostRevokeOutcome': b2PostRevokeOutcome,
      'b2PostRevokeAccepted': b2PostRevokeAccepted,
      'postRevokeB2PlaintextCount': 0,
      'noPostRevokeB2Plaintext': true,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge013',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge013-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[aliceSent],
      receivedMessages: <Map<String, Object?>>[
        _ge013Received(
          _ge013BobSiblingBeforeKey,
          'ge013-b2-before',
          'ge013 b2 before revoke',
          'bob-peer',
          isIncoming: true,
        ),
        _ge013Received(
          _ge013BobPrimaryAfterKey,
          'ge013-bob-primary-after',
          'ge013 bob primary after revoke',
          'bob-peer',
          isIncoming: true,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        _ge013BobSiblingBeforeKey: 1,
        _ge013BobPrimaryAfterKey: 1,
      },
      extra: <String, Object?>{
        'transportPeerId': 'alice-device',
        proofName: proof('alice-device'),
      },
    ),
    _baseVerdict(
      scenario: 'ge013',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge013-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[bobPrimarySent],
      receivedMessages: <Map<String, Object?>>[
        _ge013Received(
          _ge013BobSiblingBeforeKey,
          'ge013-b2-before',
          'ge013 b2 before revoke',
          'bob-peer',
          isIncoming: false,
        ),
        _ge013Received(
          _ge013AliceAfterKey,
          'ge013-alice-after',
          'ge013 alice after revoke',
          'alice-peer',
          isIncoming: true,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        _ge013BobSiblingBeforeKey: 1,
        _ge013AliceAfterKey: 1,
      },
      extra: <String, Object?>{
        'transportPeerId': 'bob-device-1',
        proofName: proof('bob-device-1'),
      },
    ),
    _baseVerdict(
      scenario: 'ge013',
      role: 'charlie',
      peerId: 'bob-peer',
      groupId: 'ge013-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        bobSiblingBeforeSent,
        bobSiblingAfterSent,
      ],
      receivedMessages: const <Map<String, Object?>>[],
      persistedMessageCounts: const <String, int>{},
      extra: <String, Object?>{
        'transportPeerId': 'bob-device-2',
        proofName: proof(
          'bob-device-2',
          b2PostRevokeOutcome: 'unauthorized',
          b2PostRevokeAccepted: false,
        ),
      },
    ),
  ];
}

String _de002Key(int index) =>
    'aliceSeq${(index + 1).toString().padLeft(3, '0')}';

String _de002Text(int index) =>
    'DE-002 rapid message ${(index + 1).toString().padLeft(3, '0')}';

String _de002MessageId(int index) =>
    'de002-a-${(index + 1).toString().padLeft(3, '0')}';

String _de002Timestamp(int index) => DateTime.utc(
  2026,
  5,
  12,
  1,
).add(Duration(microseconds: index)).toIso8601String();

List<String> _de002Keys() =>
    List<String>.generate(100, (index) => _de002Key(index));

Map<String, Object?> _de002Proof({
  required bool sender,
  required List<String> orderedKeys,
}) {
  return <String, Object?>{
    'rowId': 'DE-002',
    if (sender) ...<String, Object?>{
      'sentAllMessages': true,
      'preservedSendOrder': true,
      'timestampsStrictlyIncreasing': true,
      'sentCount': orderedKeys.length,
    } else ...<String, Object?>{
      'receivedAllMessagesOnce': true,
      'preservedPerSenderOrder': true,
      'matchedSenderPeerId': true,
      'timestampsStrictlyIncreasing': true,
      'receivedCount': orderedKeys.length,
      'expectedCount': 100,
    },
    'firstKey': orderedKeys.first,
    'lastKey': orderedKeys.last,
    'orderedKeys': orderedKeys,
  };
}

List<Map<String, dynamic>> _validDe002Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final keys = _de002Keys();
  final sentMessages = List<Map<String, Object?>>.generate(
    keys.length,
    (index) => <String, Object?>{
      'key': keys[index],
      'messageId': _de002MessageId(index),
      'groupId': 'de002-group',
      'text': _de002Text(index),
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 1,
      'timestamp': _de002Timestamp(index),
    },
  );
  List<Map<String, Object?>> receivedMessages() =>
      List<Map<String, Object?>>.generate(
        keys.length,
        (index) => _received(
          keys[index],
          _de002MessageId(index),
          _de002Text(index),
          'alice-peer',
          groupId: 'de002-group',
          keyEpoch: 1,
          timestamp: _de002Timestamp(index),
        ),
      );
  final counts = <String, int>{for (final key in keys) key: 1};

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'de002',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'de002-group',
      memberPeerIds: members,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'de002OrderedDeliveryProof': _de002Proof(
          sender: true,
          orderedKeys: keys,
        ),
      },
    ),
    _baseVerdict(
      scenario: 'de002',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'de002-group',
      memberPeerIds: members,
      receivedMessages: receivedMessages(),
      persistedMessageCounts: counts,
      extra: <String, Object?>{
        'de002OrderedDeliveryProof': _de002Proof(
          sender: false,
          orderedKeys: keys,
        ),
      },
    ),
    _baseVerdict(
      scenario: 'de002',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'de002-group',
      memberPeerIds: members,
      receivedMessages: receivedMessages(),
      persistedMessageCounts: counts,
      extra: <String, Object?>{
        'de002OrderedDeliveryProof': _de002Proof(
          sender: false,
          orderedKeys: keys,
        ),
      },
    ),
  ];
}

List<Map<String, dynamic>> _validDe003Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const messageId = 'de003-explicit-id';
  const text = 'DE-003 explicit id';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'de003',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'de003-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceExplicit',
          'messageId': messageId,
          'groupId': 'de003-group',
          'text': text,
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
          'timestamp': '2026-05-12T03:00:00.000Z',
        },
      ],
      extra: <String, Object?>{
        'de003MessageIdProof': {
          'rowId': 'DE-003',
          'requestedMessageId': messageId,
          'returnedMessageId': messageId,
          'publishPathMessageIdPreserved': true,
          'replayEnvelopeCoveredByHostGate': true,
          'retryPathCoveredByHostGate': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de003',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'de003-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceExplicit',
          messageId,
          text,
          'alice-peer',
          groupId: 'de003-group',
          keyEpoch: 1,
          timestamp: '2026-05-12T03:00:00.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceExplicit': 1},
      extra: <String, Object?>{
        'de003MessageIdProof': {
          'rowId': 'DE-003',
          'requestedMessageId': messageId,
          'receivedMessageId': messageId,
          'receivedExplicitMessageOnce': true,
          'matchedRequestedMessageId': true,
          'duplicateReplayDeduped': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de003',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'de003-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceExplicit',
          messageId,
          text,
          'alice-peer',
          groupId: 'de003-group',
          keyEpoch: 1,
          timestamp: '2026-05-12T03:00:00.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceExplicit': 1},
      extra: <String, Object?>{
        'de003MessageIdProof': {
          'rowId': 'DE-003',
          'requestedMessageId': messageId,
          'receivedMessageId': messageId,
          'receivedExplicitMessageOnce': true,
          'matchedRequestedMessageId': true,
          'duplicateReplayDeduped': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validDe007Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const messageId = 'de007-zero-peer-id';
  const text = 'DE-007 zero-peer durable fallback';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'de007',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'de007-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceZeroPeer',
          'messageId': messageId,
          'groupId': 'de007-group',
          'text': text,
          'outcome': 'successNoPeers',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
          'timestamp': '2026-05-12T04:00:00.000Z',
        },
      ],
      extra: const <String, Object?>{
        'de007ZeroPeerProof': <String, Object?>{
          'rowId': 'DE-007',
          'messageId': messageId,
          'sendResultSuccessNoPeers': true,
          'inboxStored': true,
          'publishedBeforeReceiversJoined': true,
          'activeRecipientsCovered': true,
          'activeRecipientCount': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de007',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'de007-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        {
          ..._received(
            'aliceZeroPeer',
            messageId,
            text,
            'alice-peer',
            groupId: 'de007-group',
            keyEpoch: 1,
            timestamp: '2026-05-12T04:00:00.000Z',
          ),
          'persistedCount': 1,
        },
      ],
      persistedMessageCounts: const <String, int>{'aliceZeroPeer': 1},
      extra: const <String, Object?>{
        'de007ZeroPeerProof': <String, Object?>{
          'rowId': 'DE-007',
          'messageId': messageId,
          'joinedAfterAliceSend': true,
          'receivedViaOfflineReplay': true,
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'matchedSenderPeerId': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de007',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'de007-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        {
          ..._received(
            'aliceZeroPeer',
            messageId,
            text,
            'alice-peer',
            groupId: 'de007-group',
            keyEpoch: 1,
            timestamp: '2026-05-12T04:00:00.000Z',
          ),
          'persistedCount': 1,
        },
      ],
      persistedMessageCounts: const <String, int>{'aliceZeroPeer': 1},
      extra: const <String, Object?>{
        'de007ZeroPeerProof': <String, Object?>{
          'rowId': 'DE-007',
          'messageId': messageId,
          'joinedAfterAliceSend': true,
          'receivedViaOfflineReplay': true,
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'matchedSenderPeerId': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validDe017Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const groupId = 'de017-group';
  const memberAddedAt = '2026-05-12T05:00:03.000Z';
  const removalAt = '2026-05-12T05:00:11.000Z';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'de017',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: remainingMembers,
      extra: const <String, Object?>{
        'de017MembershipOrderingProof': <String, Object?>{
          'rowId': 'DE-017',
          'removedPeerId': 'charlie-peer',
          'addedCharlieBeforePublishingMemberEvent': true,
          'publishedMemberEventAfterCharlieContent': true,
          'removedCharlieAfterPostRemovalContent': true,
          'bobConfirmedAddRepair': true,
          'bobConfirmedRemovalRepair': true,
          'memberListExcludesCharlie': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de017',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: remainingMembers,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charliePostAddOutOfOrder',
          'de017-post-add',
          'DE-017 Charlie post-add before member event',
          'charlie-peer',
          groupId: groupId,
          keyEpoch: 1,
          timestamp: '2026-05-12T05:00:04.000Z',
        ),
        _received(
          'charliePreRemovalBeforeEvent',
          'de017-pre-removal',
          'DE-017 Charlie pre-removal before event',
          'charlie-peer',
          groupId: groupId,
          keyEpoch: 1,
          timestamp: '2026-05-12T05:00:10.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charliePostAddOutOfOrder': 1,
        'charliePreRemovalBeforeEvent': 1,
      },
      extra: const <String, Object?>{
        'de017MembershipOrderingProof': <String, Object?>{
          'rowId': 'DE-017',
          'removedPeerId': 'charlie-peer',
          'memberAddedAt': memberAddedAt,
          'removalAt': removalAt,
          'bufferedContentBeforeMemberAdd': true,
          'deliveredPostAddAfterMembership': true,
          'retainedPreRemovalContent': true,
          'repairedPostRemovalContent': true,
          'memberListExcludesCharlie': true,
          'postRemovalPersistedCountAfterRepair': 0,
        },
      },
    ),
    _baseVerdict(
      scenario: 'de017',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: remainingMembers,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charliePostAddOutOfOrder',
          'messageId': 'de017-post-add',
          'groupId': groupId,
          'text': 'DE-017 Charlie post-add before member event',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'timestamp': '2026-05-12T05:00:04.000Z',
        },
        {
          'key': 'charliePreRemovalBeforeEvent',
          'messageId': 'de017-pre-removal',
          'groupId': groupId,
          'text': 'DE-017 Charlie pre-removal before event',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'timestamp': '2026-05-12T05:00:10.000Z',
        },
        {
          'key': 'charliePostRemovalBeforeEvent',
          'messageId': 'de017-post-removal',
          'groupId': groupId,
          'text': 'DE-017 Charlie post-removal before event',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'timestamp': '2026-05-12T05:00:12.000Z',
        },
      ],
      extra: const <String, Object?>{
        'de017MembershipOrderingProof': <String, Object?>{
          'rowId': 'DE-017',
          'removedPeerId': 'charlie-peer',
          'memberAddedAt': memberAddedAt,
          'removalAt': removalAt,
          'sentPostAddBeforeMemberEvent': true,
          'sentPreRemovalBeforeRemovalEvent': true,
          'sentPostRemovalBeforeRemovalEvent': true,
          'postRemovalAcceptedByLocalSend': true,
          'selfRemovedAfterRemoval': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validIr001Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'ir001-group';
  const missedKeys = <String>[
    'aliceMissedWhileBobOffline1',
    'aliceMissedWhileBobOffline2',
    'aliceMissedWhileBobOffline3',
  ];
  const liveKey = 'aliceLiveAfterBobDrain';
  const allKeys = <String>[...missedKeys, liveKey];
  final missedSent = List<Map<String, Object?>>.generate(3, (index) {
    final messageNumber = index + 1;
    return <String, Object?>{
      'key': missedKeys[index],
      'messageId': 'ir001-missed-$messageNumber',
      'groupId': groupId,
      'text': 'IR-001 missed while Bob offline $messageNumber',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 1,
      'timestamp': '2026-05-12T06:00:0$messageNumber.000Z',
    };
  });
  final liveSent = <String, Object?>{
    'key': liveKey,
    'messageId': 'ir001-live-after-drain',
    'groupId': groupId,
    'text': 'IR-001 live after Bob drain',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'timestamp': '2026-05-12T06:00:10.000Z',
  };
  final sentMessages = <Map<String, Object?>>[...missedSent, liveSent];
  final persistedCounts = <String, int>{for (final key in allKeys) key: 1};
  final bobReceived = <Map<String, Object?>>[
    for (var index = 0; index < missedKeys.length; index++)
      <String, Object?>{
        ..._received(
          missedKeys[index],
          'ir001-missed-${index + 1}',
          'IR-001 missed while Bob offline ${index + 1}',
          'alice-peer',
          groupId: groupId,
          keyEpoch: 1,
          timestamp: '2026-05-12T06:00:0${index + 1}.000Z',
          liveOnly: false,
          usedOfflineDrain: true,
        ),
        'persistedCount': 1,
      },
    <String, Object?>{
      ..._received(
        liveKey,
        'ir001-live-after-drain',
        'IR-001 live after Bob drain',
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-12T06:00:10.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
      'persistedCount': 1,
    },
  ];
  final charlieReceived = <Map<String, Object?>>[
    for (var index = 0; index < missedKeys.length; index++)
      <String, Object?>{
        ..._received(
          missedKeys[index],
          'ir001-missed-${index + 1}',
          'IR-001 missed while Bob offline ${index + 1}',
          'alice-peer',
          groupId: groupId,
          keyEpoch: 1,
          timestamp: '2026-05-12T06:00:0${index + 1}.000Z',
          liveOnly: true,
          usedOfflineDrain: false,
        ),
        'persistedCount': 1,
      },
    <String, Object?>{
      ..._received(
        liveKey,
        'ir001-live-after-drain',
        'IR-001 live after Bob drain',
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-12T06:00:10.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
      'persistedCount': 1,
    },
  ];

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ir001',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'ir001OfflineReconnectProof': <String, Object?>{
          'rowId': 'IR-001',
          'activeOfflineRecipientRole': 'bob',
          'bobWasJoinedBeforeOffline': true,
          'bobOfflineBeforeMissedSendObserved': true,
          'bobDrainCompletedBeforeLiveSend': true,
          'missedMessageCount': missedKeys.length,
          'missedKeys': missedKeys,
          'missedMessageIds': const <String>[
            'ir001-missed-1',
            'ir001-missed-2',
            'ir001-missed-3',
          ],
          'liveKey': liveKey,
          'liveMessageId': 'ir001-live-after-drain',
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir001',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: bobReceived,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ir001OfflineReconnectProof': <String, Object?>{
          'rowId': 'IR-001',
          'restoredActiveMembershipBeforeDrain': true,
          'receivedAllMissedExactlyOnce': true,
          'usedOfflineDrainForMissed': true,
          'liveAfterDrainReceived': true,
          'liveAfterDrainWasLive': true,
          'drainedMissedCount': missedKeys.length,
          'missedKeys': missedKeys,
          'liveKey': liveKey,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir001',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: charlieReceived,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ir001OfflineReconnectProof': <String, Object?>{
          'rowId': 'IR-001',
          'onlineControlReceivedMissedLive': true,
          'onlineControlReceivedLiveAfterReconnect': true,
          'onlineControlMissedCount': missedKeys.length,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validIr015Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'ir015-group';
  const keys = <String>[
    'aliceIr015Text',
    'aliceIr015Quote',
    'aliceIr015Image',
    'aliceIr015Video',
    'aliceIr015File',
    'aliceIr015Gif',
    'aliceIr015Voice',
  ];
  const mediaKeys = <String>[
    'aliceIr015Image',
    'aliceIr015Video',
    'aliceIr015File',
    'aliceIr015Gif',
    'aliceIr015Voice',
  ];

  String messageIdFor(String key) => 'ir015-${key.substring(10).toLowerCase()}';
  String textFor(String key) => 'IR-015 $key replay variant';
  Map<String, Object?> mediaFor(String key) {
    switch (key) {
      case 'aliceIr015Image':
        return const <String, Object?>{
          'id': 'ir015-image',
          'mime': 'image/jpeg',
          'mediaType': 'image',
          'size': 12345,
        };
      case 'aliceIr015Video':
        return const <String, Object?>{
          'id': 'ir015-video',
          'mime': 'video/mp4',
          'mediaType': 'video',
          'durationMs': 4200,
          'size': 23456,
        };
      case 'aliceIr015File':
        return const <String, Object?>{
          'id': 'ir015-file',
          'mime': 'application/octet-stream',
          'mediaType': 'file',
          'size': 34567,
        };
      case 'aliceIr015Gif':
        return const <String, Object?>{
          'id': 'ir015-gif',
          'mime': 'image/gif',
          'mediaType': 'image',
          'size': 45678,
        };
      case 'aliceIr015Voice':
        return const <String, Object?>{
          'id': 'ir015-voice',
          'mime': 'audio/mp4',
          'mediaType': 'audio',
          'durationMs': 3100,
          'size': 56789,
        };
      default:
        return const <String, Object?>{};
    }
  }

  Map<String, Object?> sent(String key, int index) {
    final entry = <String, Object?>{
      'key': key,
      'messageId': messageIdFor(key),
      'groupId': groupId,
      'text': textFor(key),
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 1,
      'timestamp': '2026-05-12T07:00:0$index.000Z',
    };
    if (key == 'aliceIr015Quote') {
      entry['quotedMessageId'] = messageIdFor('aliceIr015Text');
    }
    if (mediaKeys.contains(key)) {
      entry['mediaAttachmentCount'] = 1;
      entry['mediaAttachments'] = <Map<String, Object?>>[mediaFor(key)];
    }
    return entry;
  }

  Map<String, Object?> received(String key, int index, {required bool live}) {
    final entry = <String, Object?>{
      ..._received(
        key,
        messageIdFor(key),
        textFor(key),
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-12T07:00:0$index.000Z',
        liveOnly: live,
        usedOfflineDrain: !live,
      ),
      'persistedCount': 1,
    };
    if (key == 'aliceIr015Quote') {
      entry['quotedMessageId'] = messageIdFor('aliceIr015Text');
    }
    if (mediaKeys.contains(key)) {
      entry['mediaAttachmentCount'] = 1;
      entry['mediaAttachments'] = <Map<String, Object?>>[mediaFor(key)];
    }
    return entry;
  }

  final sentMessages = <Map<String, Object?>>[
    for (var i = 0; i < keys.length; i++) sent(keys[i], i + 1),
  ];
  final bobReceived = <Map<String, Object?>>[
    for (var i = 0; i < keys.length; i++) received(keys[i], i + 1, live: false),
  ];
  final charlieReceived = <Map<String, Object?>>[
    for (var i = 0; i < keys.length; i++) received(keys[i], i + 1, live: true),
  ];
  final persistedCounts = <String, int>{for (final key in keys) key: 1};

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ir015',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'ir015VariantReplayProof': <String, Object?>{
          'rowId': 'IR-015',
          'activeOfflineRecipientRole': 'bob',
          'bobWasJoinedBeforeOffline': true,
          'bobOfflineBeforeVariantSendObserved': true,
          'charlieOnlineReceivedAllVariants': true,
          'bobDrainCompletedAfterAllVariants': true,
          'variantKeys': keys,
          'mediaVariantKeys': mediaKeys,
          'quoteKey': 'aliceIr015Quote',
          'quoteTargetMessageId': 'ir015-text',
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir015',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: bobReceived,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ir015VariantReplayProof': <String, Object?>{
          'rowId': 'IR-015',
          'restoredActiveMembershipBeforeDrain': true,
          'receivedAllVariantsExactlyOnce': true,
          'usedOfflineDrainForAllVariants': true,
          'quoteRehydrated': true,
          'mediaVariantsRehydrated': true,
          'matchedKeyEpochs': true,
          'drainedVariantCount': keys.length,
          'variantKeys': keys,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir015',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: charlieReceived,
      persistedMessageCounts: persistedCounts,
      extra: <String, Object?>{
        'ir015VariantReplayProof': <String, Object?>{
          'rowId': 'IR-015',
          'onlineControlReceivedAllVariantsLive': true,
          'onlineControlVariantCount': keys.length,
          'quoteRehydrated': true,
          'mediaVariantsRehydrated': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validIr016Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'ir016-group';
  const expiredKeys = <String>[
    'aliceIr016Expired1',
    'aliceIr016Expired2',
    'aliceIr016Expired3',
    'aliceIr016Expired4',
  ];
  const retainedKeys = <String>[
    'aliceIr016Retained1',
    'aliceIr016Retained2',
    'aliceIr016Retained3',
  ];
  const allKeys = <String>[...expiredKeys, ...retainedKeys];

  String messageIdFor(String key) => 'ir016-${key.substring(9).toLowerCase()}';
  String textFor(String key) => 'IR-016 $key retention cutoff';

  Map<String, Object?> sent(String key, int index) {
    return <String, Object?>{
      'key': key,
      'messageId': messageIdFor(key),
      'groupId': groupId,
      'text': textFor(key),
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 1,
      'timestamp': key.contains('Expired')
          ? '2026-05-01T07:00:0$index.000Z'
          : '2026-05-14T07:00:0$index.000Z',
    };
  }

  Map<String, Object?> received(String key, int index, {required bool live}) {
    return <String, Object?>{
      ..._received(
        key,
        messageIdFor(key),
        textFor(key),
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: key.contains('Expired')
            ? '2026-05-01T07:00:0$index.000Z'
            : '2026-05-14T07:00:0$index.000Z',
        liveOnly: live,
        usedOfflineDrain: !live,
      ),
      'persistedCount': 1,
    };
  }

  final sentMessages = <Map<String, Object?>>[
    for (var i = 0; i < allKeys.length; i++) sent(allKeys[i], i + 1),
  ];
  final bobReceived = <Map<String, Object?>>[
    for (var i = 0; i < retainedKeys.length; i++)
      received(retainedKeys[i], i + 1, live: false),
  ];
  final charlieReceived = <Map<String, Object?>>[
    for (var i = 0; i < allKeys.length; i++)
      received(allKeys[i], i + 1, live: true),
  ];

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ir016',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: sentMessages,
      extra: <String, Object?>{
        'ir016RetentionCutoffProof': <String, Object?>{
          'rowId': 'IR-016',
          'activeOfflineRecipientRole': 'bob',
          'bobWasJoinedBeforeOffline': true,
          'bobOfflineBeforeExpiredSendObserved': true,
          'sentExpiredBeyondRetention': true,
          'sentRetainedWithinRetention': true,
          'bobDrainCompletedAfterRetained': true,
          'expiredKeys': expiredKeys,
          'retainedKeys': retainedKeys,
          'manyMessagesSentCount': allKeys.length,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir016',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: bobReceived,
      persistedMessageCounts: const <String, int>{
        'aliceIr016Retained1': 1,
        'aliceIr016Retained2': 1,
        'aliceIr016Retained3': 1,
      },
      extra: <String, Object?>{
        'ir016RetentionCutoffProof': <String, Object?>{
          'rowId': 'IR-016',
          'restoredActiveMembershipBeforeDrain': true,
          'receivedRetainedExactlyOnce': true,
          'usedOfflineDrainForRetained': true,
          'expiredBacklogSkipped': true,
          'expiredVisibleCount': 0,
          'lastBacklogExpiredAtRecorded': true,
          'lastBacklogRetainedAtRecorded': true,
          'explicitRetentionStateRecorded': true,
          'noSilentCompleteState': true,
          'retentionWindowDays': 7,
          'drainedRetainedCount': retainedKeys.length,
          'expiredKeys': expiredKeys,
          'retainedKeys': retainedKeys,
        },
      },
    ),
    _baseVerdict(
      scenario: 'ir016',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: charlieReceived,
      persistedMessageCounts: const <String, int>{
        'aliceIr016Expired1': 1,
        'aliceIr016Expired2': 1,
        'aliceIr016Expired3': 1,
        'aliceIr016Expired4': 1,
        'aliceIr016Retained1': 1,
        'aliceIr016Retained2': 1,
        'aliceIr016Retained3': 1,
      },
      extra: <String, Object?>{
        'ir016RetentionCutoffProof': <String, Object?>{
          'rowId': 'IR-016',
          'onlineControlReceivedAllMessagesLive': true,
          'onlineControlMessageCount': allKeys.length,
          'onlineControlExpiredCount': expiredKeys.length,
          'onlineControlRetainedCount': retainedKeys.length,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm001Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'gm001-group';
  const messageId = 'gm001-a1';
  const text = 'hello gm001';
  const timestamp = '2026-05-12T14:36:16.419641Z';
  const keyEpoch = 1;
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm001',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceInitial',
          'groupId': groupId,
          'messageId': messageId,
          'text': text,
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'timestamp': timestamp,
          'keyEpoch': keyEpoch,
        },
      ],
      extra: const <String, Object?>{
        'de001LiveDeliveryProof': <String, Object?>{
          'rowId': 'DE-001',
          'sentLiveText': true,
          'sentGroupId': groupId,
          'sentMessageId': messageId,
          'sentTimestamp': timestamp,
          'sentKeyEpoch': keyEpoch,
          'bobReceiptSignalObserved': true,
          'charlieReceiptSignalObserved': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm001',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceInitial',
          messageId,
          text,
          'alice-peer',
          groupId: groupId,
          keyEpoch: keyEpoch,
          timestamp: timestamp,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
      extra: const <String, Object?>{
        'de001LiveDeliveryProof': <String, Object?>{
          'rowId': 'DE-001',
          'receivedVisibleMessageOnce': true,
          'matchedGroupId': true,
          'matchedMessageId': true,
          'matchedSenderPeerId': true,
          'matchedTimestamp': true,
          'matchedEpoch': true,
          'incomingVisible': true,
          'receivedTimestamp': timestamp,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm001',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceInitial',
          messageId,
          text,
          'alice-peer',
          groupId: groupId,
          keyEpoch: keyEpoch,
          timestamp: timestamp,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
      extra: const <String, Object?>{
        'de001LiveDeliveryProof': <String, Object?>{
          'rowId': 'DE-001',
          'receivedVisibleMessageOnce': true,
          'matchedGroupId': true,
          'matchedMessageId': true,
          'matchedSenderPeerId': true,
          'matchedTimestamp': true,
          'matchedEpoch': true,
          'incomingVisible': true,
          'receivedTimestamp': timestamp,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateFullMeshOnlineVerdicts() {
  const scenario = 'private_full_mesh_online';
  const groupId = 'private-full-mesh-online-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const keysByRole = <String, String>{
    'alice': 'aliceFullMesh',
    'bob': 'bobFullMesh',
    'charlie': 'charlieFullMesh',
  };
  const textsByRole = <String, String>{
    'alice': 'NW-001 Alice full mesh',
    'bob': 'NW-001 Bob full mesh',
    'charlie': 'NW-001 Charlie full mesh',
  };
  const timestampsByRole = <String, String>{
    'alice': '2026-05-13T09:01:00.000Z',
    'bob': '2026-05-13T09:02:00.000Z',
    'charlie': '2026-05-13T09:03:00.000Z',
  };
  final sentByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };

  for (final senderRole in peerIdsByRole.keys) {
    final key = keysByRole[senderRole]!;
    final messageId = 'nw001-$senderRole-message';
    final text = textsByRole[senderRole]!;
    sentByRole[senderRole]!.add(<String, Object?>{
      'key': key,
      'messageId': messageId,
      'groupId': groupId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': peerIdsByRole[senderRole],
      'keyEpoch': 1,
      'timestamp': timestampsByRole[senderRole],
      'topicPeers': 2,
      'liveFanoutState': 'full_peers',
    });
    for (final receiverRole in peerIdsByRole.keys) {
      if (receiverRole == senderRole) continue;
      receivedByRole[receiverRole]!.add(
        _received(
          key,
          messageId,
          text,
          peerIdsByRole[senderRole]!,
          groupId: groupId,
          keyEpoch: 1,
          timestamp: timestampsByRole[senderRole],
          liveOnly: true,
          usedOfflineDrain: false,
        ),
      );
    }
  }

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => const <String, Object?>{
    'rowId': 'NW-001',
    'activeRoles': <String>['alice', 'bob', 'charlie'],
    'senderRoles': <String>['alice', 'bob', 'charlie'],
    'expectedReceiversPerMessage': 2,
    'allRolePublishesCovered': true,
    'allActiveReceiversCovered': true,
    'duplicateVisibleMessageCount': 0,
    'successNoPeersCount': 0,
    'partialPeerPublishCount': 0,
    'topicPeerCountsBySender': <String, int>{
      'alice': 2,
      'bob': 2,
      'charlie': 2,
    },
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 1,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw001FullMeshProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw001ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw001FullMeshProof': <String, Object?>{
      ...Map<String, Object?>.from(verdict['nw001FullMeshProof'] as Map),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateRelayOnlyDeliveryVerdicts() {
  const scenario = 'private_relay_only_delivery';
  const groupId = 'private-relay-only-delivery-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final aliceSent = <String, Object?>{
    'key': 'aliceToRelayOnlyBob',
    'messageId': 'nw002-alice-message',
    'groupId': groupId,
    'text': 'NW-002 Alice to relay-only Bob',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'keyEpoch': 1,
    'timestamp': '2026-05-13T10:01:00.000Z',
    'topicPeers': 2,
    'liveFanoutState': 'full_peers',
  };
  final bobSent = <String, Object?>{
    'key': 'bobRelayOnlyPublishBack',
    'messageId': 'nw002-bob-message',
    'groupId': groupId,
    'text': 'NW-002 Bob relay-only publish back',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['bob'],
    'keyEpoch': 1,
    'timestamp': '2026-05-13T10:02:00.000Z',
    'topicPeers': 2,
    'liveFanoutState': 'full_peers',
  };
  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[aliceSent],
    'bob': <Map<String, Object?>>[bobSent],
    'charlie': <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobRelayOnlyPublishBack',
        'nw002-bob-message',
        'NW-002 Bob relay-only publish back',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-13T10:02:00.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceToRelayOnlyBob',
        'nw002-alice-message',
        'NW-002 Alice to relay-only Bob',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-13T10:01:00.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'aliceToRelayOnlyBob',
        'nw002-alice-message',
        'NW-002 Alice to relay-only Bob',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-13T10:01:00.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
      _received(
        'bobRelayOnlyPublishBack',
        'nw002-bob-message',
        'NW-002 Bob relay-only publish back',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-13T10:02:00.000Z',
        liveOnly: true,
        usedOfflineDrain: false,
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-002',
    'relayOnlyRoles': const <String>['bob'],
    'circuitOrRelayRouteProven': true,
    'directPathSuppressed': true,
    'relayLifecycleProof': true,
    'activeMembershipPreserved': true,
    'deliveryModeByMessage': const <String, Object?>{
      'aliceToRelayOnlyBob': <String, Object?>{
        'senderRole': 'alice',
        'routedReceiverRoles': <String>['bob'],
        'deliveryMode': 'live_pubsub',
      },
      'bobRelayOnlyPublishBack': <String, Object?>{
        'senderRole': 'bob',
        'routedReceiverRoles': <String>['alice', 'charlie'],
        'deliveryMode': 'live_pubsub',
      },
    },
    'allRoutedReceiversCovered': true,
    'routedSenderPublishBackCovered': true,
    'replayDeliveryCovered': false,
    'successNoPeersCount': 0,
    'duplicateVisibleMessageCount': 0,
    'membershipMutationCount': 0,
    'routeDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'GROUP_DISCOVERY',
        'step': 'known_member_dial_success',
        'peerIdPrefix': 'bob-peer',
        'path': 'relay',
        'attemptedDirect': false,
        'directAddrCount': 0,
        'usedRelayFallback': false,
      },
    ],
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 1,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw002RelayOnlyDeliveryProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw002ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw002RelayOnlyDeliveryProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw002RelayOnlyDeliveryProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivatePartitionReaddHealVerdicts() {
  const scenario = 'private_partition_readd_heal';
  const groupId = 'private-partition-readd-heal-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final removedWindow = <String, Object?>{
    'key': 'aliceRemovedWindow',
    'messageId': 'nw003-removed-window',
    'groupId': groupId,
    'text': 'NW-003 removed-window',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[peerIdsByRole['bob']!],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T11:02:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final alicePostHeal = <String, Object?>{
    'key': 'alicePostHeal',
    'messageId': 'nw003-alice-post-heal',
    'groupId': groupId,
    'text': 'NW-003 Alice post-heal',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T11:03:00.000Z',
  };
  final bobPostHeal = <String, Object?>{
    'key': 'bobPostHeal',
    'messageId': 'nw003-bob-post-heal',
    'groupId': groupId,
    'text': 'NW-003 Bob post-heal',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['bob'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T11:04:00.000Z',
  };
  final charliePostHeal = <String, Object?>{
    'key': 'charliePostHeal',
    'messageId': 'nw003-charlie-post-heal',
    'groupId': groupId,
    'text': 'NW-003 Charlie post-heal',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['charlie'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T11:05:00.000Z',
  };

  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[removedWindow, alicePostHeal],
    'bob': <Map<String, Object?>>[bobPostHeal],
    'charlie': <Map<String, Object?>>[charliePostHeal],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobPostHeal',
        'nw003-bob-post-heal',
        'NW-003 Bob post-heal',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:04:00.000Z',
      ),
      _received(
        'charliePostHeal',
        'nw003-charlie-post-heal',
        'NW-003 Charlie post-heal',
        peerIdsByRole['charlie']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:05:00.000Z',
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceRemovedWindow',
        'nw003-removed-window',
        'NW-003 removed-window',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:02:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'alicePostHeal',
        'nw003-alice-post-heal',
        'NW-003 Alice post-heal',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:03:00.000Z',
      ),
      _received(
        'charliePostHeal',
        'nw003-charlie-post-heal',
        'NW-003 Charlie post-heal',
        peerIdsByRole['charlie']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:05:00.000Z',
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'alicePostHeal',
        'nw003-alice-post-heal',
        'NW-003 Alice post-heal',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:03:00.000Z',
      ),
      _received(
        'bobPostHeal',
        'nw003-bob-post-heal',
        'NW-003 Bob post-heal',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T11:04:00.000Z',
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-003',
    'scenario': scenario,
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'partitionProofSource': 'app_peer_core_simulator',
    'fakeNetworkOnly': false,
    'alicePartitionedFromBob': true,
    'alicePartitionedFromCharlie': true,
    'bobAndCharliePartitionedFromAlice': true,
    'removedWindowSentWhileCharlieRemoved': true,
    'removedWindowLiveDeliveryBlockedDuringPartition': true,
    'bobReceivedRemovedWindowAfterHeal': true,
    'charlieDidNotReceiveRemovedWindow': true,
    'finalMembershipConvergedForAliceBobCharlie': true,
    'finalKeyEpochConvergedForAliceBobCharlie': true,
    'postHealAliceToBobCharlieDelivery': true,
    'postHealBobToAliceCharlieDelivery': true,
    'postHealCharlieToAliceBobDelivery': true,
    'routeDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'P2P_PEER_DISCONNECT_RESPONSE',
        'targetRole': 'bob',
        'ok': true,
      },
      <String, Object?>{
        'sourceEvent': 'P2P_PEER_DISCONNECT_RESPONSE',
        'targetRole': 'charlie',
        'ok': true,
      },
      <String, Object?>{
        'sourceEvent': 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
        'senderRole': 'alice',
        'topicPeers': 0,
      },
    ],
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 2,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw003PartitionReaddHealProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw003ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw003PartitionReaddHealProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw003PartitionReaddHealProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateRelayReconnectGroupRecoveryVerdicts() {
  const scenario = 'private_relay_reconnect_group_recovery';
  const groupId = 'private-relay-reconnect-group-recovery';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final missedDuringDrop = <String, Object?>{
    'key': 'aliceMissedDuringRelayDrop',
    'messageId': 'nw004-missed-during-drop',
    'groupId': groupId,
    'text': 'NW-004 missed during relay drop',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[peerIdsByRole['bob']!],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:01:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final alicePostReconnectLive = <String, Object?>{
    'key': 'alicePostReconnectLive',
    'messageId': 'nw004-alice-post-reconnect-live',
    'groupId': groupId,
    'text': 'NW-004 Alice live after reconnect',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:02:00.000Z',
  };
  final bobRecoveredPublishBack = <String, Object?>{
    'key': 'bobRecoveredPublishBack',
    'messageId': 'nw004-bob-recovered-publish-back',
    'groupId': groupId,
    'text': 'NW-004 Bob recovered publish back',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['bob'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:03:00.000Z',
  };

  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[missedDuringDrop, alicePostReconnectLive],
    'bob': <Map<String, Object?>>[bobRecoveredPublishBack],
    'charlie': const <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobRecoveredPublishBack',
        'nw004-bob-recovered-publish-back',
        'NW-004 Bob recovered publish back',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:03:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceMissedDuringRelayDrop',
        'nw004-missed-during-drop',
        'NW-004 missed during relay drop',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:01:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'alicePostReconnectLive',
        'nw004-alice-post-reconnect-live',
        'NW-004 Alice live after reconnect',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:02:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'alicePostReconnectLive',
        'nw004-alice-post-reconnect-live',
        'NW-004 Alice live after reconnect',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:02:00.000Z',
        usedOfflineDrain: false,
      ),
      _received(
        'bobRecoveredPublishBack',
        'nw004-bob-recovered-publish-back',
        'NW-004 Bob recovered publish back',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:03:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-004',
    'scenario': scenario,
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'relayDropForced': true,
    'relayReconnectCalled': true,
    'recoveryMode': 'watchdog_restart',
    'needsGroupRecoveryObserved': true,
    'groupTopicsRejoinedAfterReconnect': true,
    'topicsPreservedInPlace': false,
    'groupReplayDrainCompleted': true,
    'missedDuringDropRecoveredByReplay': true,
    'postReconnectLiveDeliveryToRecoveredPeer': true,
    'recoveredPeerPublishBackLive': true,
    'recoveryAckSentAfterRejoinAndDrain': true,
    'membershipUnchangedByReconnect': true,
    'finalMembershipConvergedForAliceBobCharlie': true,
    'finalKeyEpochConvergedForAliceBobCharlie': true,
    'duplicateVisibleMessageCount': 0,
    'routeDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'APP_PEER_RELAY_DROP',
        'targetRole': 'bob',
        'relayState': 'degraded',
      },
      <String, Object?>{
        'sourceEvent': 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
        'senderRole': 'alice',
        'topicPeers': 0,
      },
    ],
    'reconnectDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'P2P_RELAY_RECONNECT_RESPONSE',
        'targetRole': 'bob',
        'recoveryMode': 'watchdog_restart',
        'needsGroupRecovery': true,
      },
      <String, Object?>{
        'sourceEvent': 'GROUP_REJOIN_AND_DRAIN',
        'targetRole': 'bob',
        'ackAfterDrain': true,
      },
    ],
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 2,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw004RelayReconnectRecoveryProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw004ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw004RelayReconnectRecoveryProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw004RelayReconnectRecoveryProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivatePeerDisconnectNotRemovalVerdicts() {
  const scenario = 'private_peer_disconnect_not_removal';
  const groupId = 'private-peer-disconnect-not-removal-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final missedDuringDisconnect = <String, Object?>{
    'key': 'aliceMissedDuringDisconnect',
    'messageId': 'nw006-missed-during-disconnect',
    'groupId': groupId,
    'text': 'NW-006 missed while Bob disconnected',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[
      peerIdsByRole['bob']!,
      peerIdsByRole['charlie']!,
    ],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:10:00.000Z',
    'topicPeers': 1,
    'liveFanoutState': 'partial_peers',
    'inboxStored': true,
  };
  final alicePostReconnectLive = <String, Object?>{
    'key': 'alicePostReconnectLive',
    'messageId': 'nw006-alice-post-reconnect-live',
    'groupId': groupId,
    'text': 'NW-006 Alice live after reconnect',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:11:00.000Z',
  };
  final bobPublishBack = <String, Object?>{
    'key': 'bobPublishBackAfterReconnect',
    'messageId': 'nw006-bob-publish-back-after-reconnect',
    'groupId': groupId,
    'text': 'NW-006 Bob publish back after reconnect',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['bob'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:12:00.000Z',
  };

  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      missedDuringDisconnect,
      alicePostReconnectLive,
    ],
    'bob': <Map<String, Object?>>[bobPublishBack],
    'charlie': const <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobPublishBackAfterReconnect',
        'nw006-bob-publish-back-after-reconnect',
        'NW-006 Bob publish back after reconnect',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:12:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceMissedDuringDisconnect',
        'nw006-missed-during-disconnect',
        'NW-006 missed while Bob disconnected',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:10:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'alicePostReconnectLive',
        'nw006-alice-post-reconnect-live',
        'NW-006 Alice live after reconnect',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:11:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'aliceMissedDuringDisconnect',
        'nw006-missed-during-disconnect',
        'NW-006 missed while Bob disconnected',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:10:00.000Z',
        usedOfflineDrain: false,
      ),
      _received(
        'alicePostReconnectLive',
        'nw006-alice-post-reconnect-live',
        'NW-006 Alice live after reconnect',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:11:00.000Z',
        usedOfflineDrain: false,
      ),
      _received(
        'bobPublishBackAfterReconnect',
        'nw006-bob-publish-back-after-reconnect',
        'NW-006 Bob publish back after reconnect',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:12:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-006',
    'scenario': scenario,
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'disconnectProofSource': 'app_peer_core_simulator',
    'bobDisconnected': true,
    'bobGroupPresentDuringDisconnect': true,
    'bobSelfMemberActiveDuringDisconnect': true,
    'bobRemovedSignalCount': 0,
    'membershipMutationCount': 0,
    'durableRecipientIncludedDisconnectedBob': true,
    'missedDuringDisconnectRecoveredByReplay': true,
    'postReconnectLiveDeliveryToBob': true,
    'bobPublishBackAfterReconnect': true,
    'duplicateVisibleMessageCount': 0,
    'finalMembershipConvergedForAliceBobCharlie': true,
    'finalKeyEpochConvergedForAliceBobCharlie': true,
    'stableKeyEpoch': true,
    'disconnectDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'APP_PEER_DISCONNECT',
        'targetRole': 'bob',
        'topicPeersDuringAliceSend': 1,
      },
      <String, Object?>{
        'sourceEvent': 'GROUP_REJOIN_AND_DRAIN',
        'targetRole': 'bob',
        'replayDrain': true,
      },
    ],
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 2,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw006DisconnectNotRemovalProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw006ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw006DisconnectNotRemovalProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw006DisconnectNotRemovalProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>>
_validPrivateBackgroundResumeGroupDeliveryVerdicts() {
  const scenario = 'private_background_resume_group_delivery';
  const groupId = 'private-background-resume-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  final beforeEdit = <String, Object?>{
    'key': 'aliceDuringBackgroundBeforeEdit',
    'messageId': 'nw010-before-edit',
    'groupId': groupId,
    'text': 'NW-010 missed before membership edit',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[
      peerIdsByRole['bob']!,
      peerIdsByRole['charlie']!,
    ],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:20:00.000Z',
    'topicPeers': 1,
    'liveFanoutState': 'partial_peers',
    'inboxStored': true,
  };
  final afterEdit = <String, Object?>{
    'key': 'aliceDuringBackgroundAfterEdit',
    'messageId': 'nw010-after-edit',
    'groupId': groupId,
    'text': 'NW-010 missed after membership edit',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[peerIdsByRole['bob']!],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:21:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final postForegroundLive = <String, Object?>{
    'key': 'alicePostForegroundLive',
    'messageId': 'nw010-post-foreground-live',
    'groupId': groupId,
    'text': 'NW-010 Alice live after foreground',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['alice'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:22:00.000Z',
  };
  final bobPublishBack = <String, Object?>{
    'key': 'bobPostForegroundPublishBack',
    'messageId': 'nw010-bob-publish-back',
    'groupId': groupId,
    'text': 'NW-010 Bob publish after foreground',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['bob'],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T12:23:00.000Z',
  };

  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[beforeEdit, afterEdit, postForegroundLive],
    'bob': <Map<String, Object?>>[bobPublishBack],
    'charlie': const <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobPostForegroundPublishBack',
        'nw010-bob-publish-back',
        'NW-010 Bob publish after foreground',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:23:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceDuringBackgroundBeforeEdit',
        'nw010-before-edit',
        'NW-010 missed before membership edit',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:20:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'aliceDuringBackgroundAfterEdit',
        'nw010-after-edit',
        'NW-010 missed after membership edit',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:21:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'alicePostForegroundLive',
        'nw010-post-foreground-live',
        'NW-010 Alice live after foreground',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:22:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'aliceDuringBackgroundBeforeEdit',
        'nw010-before-edit',
        'NW-010 missed before membership edit',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 2,
        timestamp: '2026-05-13T12:20:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-010',
    'scenario': scenario,
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'backgroundProofSource': 'app_peer_core_simulator_lifecycle_pause_resume',
    'bobBackgroundedDuringAliceActivity': true,
    'bobForegroundedAfterMembershipEdit': true,
    'bobReceivedNoLiveCopyWhileBackgrounded': true,
    'groupTopicsRejoinedAfterForeground': true,
    'groupReplayDrainCompleted': true,
    'recoveryAckSentAfterRejoinAndDrain': true,
    'orderedDrainIncludesContentAndMembership': true,
    'orderedDrainKeys': const <String>[
      'aliceDuringBackgroundBeforeEdit',
      'memberRemovedCharlie',
      'aliceDuringBackgroundAfterEdit',
    ],
    'entitlementFilteringPreserved': true,
    'postForegroundLiveDeliveryToBob': true,
    'bobPublishBackAfterForeground': true,
    'duplicateVisibleMessageCount': 0,
    'finalMembershipConvergedForAliceBob': true,
    'finalKeyEpochConvergedForAliceBob': true,
    'charlieRemovedBeforeSecondBackgroundMessage': true,
    'lifecycleDiagnostics': const <Map<String, Object?>>[
      <String, Object?>{
        'sourceEvent': 'APP_PEER_BACKGROUND_PAUSE',
        'targetRole': 'bob',
        'transportStopped': true,
      },
      <String, Object?>{
        'sourceEvent': 'APP_PEER_FOREGROUND_RESUME',
        'targetRole': 'bob',
        'rejoinDrainAck': true,
      },
    ],
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: remainingMembers,
        keyEpoch: role == 'charlie' ? 0 : 2,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': remainingMembers,
          'nw010BackgroundResumeDeliveryProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw010ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw010BackgroundResumeDeliveryProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw010BackgroundResumeDeliveryProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateLongOfflineEpochChurnVerdicts() {
  const scenario = 'private_long_offline_epoch_churn';
  const groupId = 'private-long-offline-epoch-churn-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
  };
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  final removedWindow = <String, Object?>{
    'key': 'aliceRemovedWindow',
    'messageId': 'nw012-removed-window',
    'groupId': groupId,
    'text': 'NW-012 removed-window',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[peerIdsByRole['bob']!],
    'keyEpoch': 2,
    'timestamp': '2026-05-13T13:20:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final aliceFinal = <String, Object?>{
    'key': 'aliceFinalActiveOne',
    'messageId': 'nw012-alice-final-active-one',
    'groupId': groupId,
    'text': 'NW-012 Alice final active one',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['alice'],
    'recipientPeerIds': <String>[
      peerIdsByRole['bob']!,
      peerIdsByRole['charlie']!,
    ],
    'keyEpoch': 4,
    'timestamp': '2026-05-13T13:42:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final bobFinal = <String, Object?>{
    'key': 'bobFinalActiveTwo',
    'messageId': 'nw012-bob-final-active-two',
    'groupId': groupId,
    'text': 'NW-012 Bob final active two',
    'outcome': 'successNoPeers',
    'senderPeerId': peerIdsByRole['bob'],
    'recipientPeerIds': <String>[
      peerIdsByRole['alice']!,
      peerIdsByRole['charlie']!,
    ],
    'keyEpoch': 4,
    'timestamp': '2026-05-13T13:43:00.000Z',
    'topicPeers': 0,
    'liveFanoutState': 'zero_peers',
    'inboxStored': true,
  };
  final charliePostLive = <String, Object?>{
    'key': 'charliePostReconnectLive',
    'messageId': 'nw012-charlie-post-reconnect-live',
    'groupId': groupId,
    'text': 'NW-012 Charlie post reconnect live',
    'outcome': 'success',
    'senderPeerId': peerIdsByRole['charlie'],
    'keyEpoch': 4,
    'timestamp': '2026-05-13T13:45:00.000Z',
  };

  final sentByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[removedWindow, aliceFinal],
    'bob': <Map<String, Object?>>[bobFinal],
    'charlie': <Map<String, Object?>>[charliePostLive],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    'alice': <Map<String, Object?>>[
      _received(
        'bobFinalActiveTwo',
        'nw012-bob-final-active-two',
        'NW-012 Bob final active two',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:43:00.000Z',
        usedOfflineDrain: false,
      ),
      _received(
        'charliePostReconnectLive',
        'nw012-charlie-post-reconnect-live',
        'NW-012 Charlie post reconnect live',
        peerIdsByRole['charlie']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:45:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'bob': <Map<String, Object?>>[
      _received(
        'aliceFinalActiveOne',
        'nw012-alice-final-active-one',
        'NW-012 Alice final active one',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:42:00.000Z',
        usedOfflineDrain: false,
      ),
      _received(
        'charliePostReconnectLive',
        'nw012-charlie-post-reconnect-live',
        'NW-012 Charlie post reconnect live',
        peerIdsByRole['charlie']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:45:00.000Z',
        usedOfflineDrain: false,
      ),
    ],
    'charlie': <Map<String, Object?>>[
      _received(
        'aliceFinalActiveOne',
        'nw012-alice-final-active-one',
        'NW-012 Alice final active one',
        peerIdsByRole['alice']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:42:00.000Z',
        usedOfflineDrain: true,
      ),
      _received(
        'bobFinalActiveTwo',
        'nw012-bob-final-active-two',
        'NW-012 Bob final active two',
        peerIdsByRole['bob']!,
        groupId: groupId,
        keyEpoch: 4,
        timestamp: '2026-05-13T13:43:00.000Z',
        usedOfflineDrain: true,
      ),
    ],
  };

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'NW-012',
    'scenario': scenario,
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'offlineProofSource': 'app_peer_core_simulator_long_offline_reconnect',
    'charlieOfflineThroughEpochChurn': true,
    'groupTopicsRejoinedAfterReconnect': true,
    'groupReplayDrainCompleted': true,
    'entitlementFilteringPreserved': true,
    'finalActiveMessagesDelivered': true,
    'charlieReceivedOnlyFinalActiveInterval': true,
    'postReconnectLiveDelivery': true,
    'finalMembershipConverged': true,
    'finalKeyEpochConverged': true,
    'finalMemberRoles': const <String>['alice', 'bob', 'charlie'],
    'finalEpoch': 4,
    'orderedDrainKeys': const <String>[
      'memberRemovedCharlie',
      'memberReaddedCharlie',
      'aliceFinalActiveOne',
      'bobFinalActiveTwo',
    ],
    'finalActiveMessageKeys': const <String>[
      'aliceFinalActiveOne',
      'bobFinalActiveTwo',
    ],
    'duplicateVisibleMessageCount': 0,
    'removedWindowPlaintextCount': 0,
    'staleFirstIntervalPlaintextCount': 0,
    'staleEpochPlaintextCount': 0,
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 4,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'nw012LongOfflineEpochConvergenceProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withNw012ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw012LongOfflineEpochConvergenceProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['nw012LongOfflineEpochConvergenceProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateAbcCreateVerdicts() {
  const scenario = 'private_abc_create';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-abc-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceInitial',
          'messageId': 'pabc-a1',
          'text': 'private abc hello',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
        },
      ],
      extra: _privateAbcVerdictExtra(
        deviceId: 'sim-alice',
        members: members,
        topicName: '/mknoon/group/private-abc',
        groupConfigStateHash: 'private-abc-state',
        ml001Proof: _ml001AliceProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-abc-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceInitial',
          'pabc-a1',
          'private abc hello',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
      extra: _privateAbcVerdictExtra(
        deviceId: 'sim-bob',
        members: members,
        topicName: '/mknoon/group/private-abc',
        groupConfigStateHash: 'private-abc-state',
        ml001Proof: _ml001InviteeProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-abc-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceInitial',
          'pabc-a1',
          'private abc hello',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
      extra: _privateAbcVerdictExtra(
        deviceId: 'sim-charlie',
        members: members,
        topicName: '/mknoon/group/private-abc',
        groupConfigStateHash: 'private-abc-state',
        ml001Proof: _ml001InviteeProof(),
      ),
    ),
  ];
}

Map<String, Object?> _privateAbcVerdictExtra({
  required String deviceId,
  required List<String> members,
  required String topicName,
  required String groupConfigStateHash,
  required Map<String, Object?> ml001Proof,
}) {
  return <String, Object?>{
    'deviceId': deviceId,
    'topicName': topicName,
    'activeMemberPeerIds': members,
    'groupConfigStateHash': groupConfigStateHash,
    'ml001CreateInviteProof': ml001Proof,
  };
}

Map<String, Object?> _ml001AliceProof() {
  return const <String, Object?>{
    'rowId': 'ML-001',
    'invitePath': 'supported_pending_invite',
    'createdViaCreateGroupWithMembers': true,
    'bobInviteSent': true,
    'charlieInviteSent': true,
    'bobAcceptedSignal': true,
    'charlieAcceptedSignal': true,
    'readableJoinTimelineObserved': true,
  };
}

Map<String, Object?> _ml001InviteeProof() {
  return const <String, Object?>{
    'rowId': 'ML-001',
    'invitePath': 'supported_pending_invite',
    'storedPendingInvite': true,
    'acceptedPendingInvite': true,
    'joinedViaGroupJoin': true,
    'readableSelfJoinTimeline': true,
    'receivedAliceInitialAfterInviteAccept': true,
  };
}

List<Map<String, dynamic>> _validPrivateReactionRoundtripVerdicts() {
  const scenario = 'private_reaction_roundtrip';
  const groupId = 'group-pl009';
  const alicePeerId = 'alice-peer';
  const bobPeerId = 'bob-peer';
  const charliePeerId = 'charlie-peer';
  const members = <String>[alicePeerId, bobPeerId, charliePeerId];
  const targetMessage = <String, Object?>{
    'key': 'aliceReactionTarget',
    'messageId': 'msg-pl009-target',
    'groupId': groupId,
    'text': 'PL-009 Alice reaction target',
    'outcome': 'success',
    'senderPeerId': alicePeerId,
    'keyEpoch': 1,
    'timestamp': '2026-05-13T00:00:00.000Z',
    'accepted': true,
  };

  Map<String, Object?> proofFor(String role, {required bool streamReceived}) {
    return <String, Object?>{
      'rowId': 'PL-009',
      'activeRoles': const <String>['alice', 'bob', 'charlie'],
      'targetMessageId': 'msg-pl009-target',
      'reactorRole': 'bob',
      'reactionEmoji': '🔥',
      'reactionOutcome': 'success',
      'reactionAccepted': true,
      'observedByRole': role,
      'receivedViaGroupReactionStream': streamReceived,
      'appliedOnceToTarget': true,
      'persistedReactionCount': 1,
      'aliceObservedSignal': true,
      'charlieObservedSignal': true,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: alicePeerId,
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[targetMessage],
      extra: <String, Object?>{
        'pl009ReactionRoundtripProof': proofFor('alice', streamReceived: true),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: bobPeerId,
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceReactionTarget',
          'msg-pl009-target',
          'PL-009 Alice reaction target',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceReactionTarget': 1},
      extra: <String, Object?>{
        'pl009ReactionRoundtripProof': proofFor('bob', streamReceived: false),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: charliePeerId,
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceReactionTarget',
          'msg-pl009-target',
          'PL-009 Alice reaction target',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceReactionTarget': 1},
      extra: <String, Object?>{
        'pl009ReactionRoundtripProof': proofFor(
          'charlie',
          streamReceived: true,
        ),
      },
    ),
  ];
}

Map<String, dynamic> _withPl009ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'pl009ReactionRoundtripProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['pl009ReactionRoundtripProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateRemovedReactionRejectedVerdicts() {
  const scenario = 'private_removed_reaction_rejected';
  const groupId = 'group-pl010';
  const alicePeerId = 'alice-peer';
  const bobPeerId = 'bob-peer';
  const charliePeerId = 'charlie-peer';
  const activeMembers = <String>[alicePeerId, bobPeerId];
  const targetMessage = <String, Object?>{
    'key': 'aliceReactionTargetBeforeRemoval',
    'messageId': 'msg-pl010-target',
    'groupId': groupId,
    'text': 'PL-010 Alice pre-removal target',
    'outcome': 'success',
    'senderPeerId': alicePeerId,
    'keyEpoch': 1,
    'timestamp': '2026-05-13T00:00:00.000Z',
    'accepted': true,
  };

  Map<String, Object?> proofFor(
    String role, {
    bool removedMemberExcluded = false,
    bool selfRemovedOrExcluded = false,
  }) {
    return <String, Object?>{
      'rowId': 'PL-010',
      'activeRoles': const <String>['alice', 'bob'],
      'removedRole': 'charlie',
      'reactorRole': 'charlie',
      'targetMessageId': 'msg-pl010-target',
      'reactionEmoji': '🔥',
      'reactionOutcome': 'notMember',
      'reactionAccepted': false,
      'reactionRejectedOrIgnored': true,
      'observedByRole': role,
      'oldLocalMessageRetained': true,
      'removedMemberExcluded': removedMemberExcluded,
      'selfRemovedOrExcluded': selfRemovedOrExcluded,
      'visibleReactionCountForRemovedMember': 0,
      'visibleReactionCountForTarget': 0,
      'visibleStateUnchanged': true,
      'localReactionCountAfterAttempt': 0,
      'aliceObservedNoMutationSignal': true,
      'bobObservedNoMutationSignal': true,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: alicePeerId,
      groupId: groupId,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[targetMessage],
      extra: <String, Object?>{
        'pl010RemovedReactionProof': proofFor(
          'alice',
          removedMemberExcluded: true,
        ),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: bobPeerId,
      groupId: groupId,
      memberPeerIds: activeMembers,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceReactionTargetBeforeRemoval',
          'msg-pl010-target',
          'PL-010 Alice pre-removal target',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceReactionTargetBeforeRemoval': 1,
      },
      extra: <String, Object?>{
        'pl010RemovedReactionProof': proofFor(
          'bob',
          removedMemberExcluded: true,
        ),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: charliePeerId,
      groupId: groupId,
      keyEpoch: 0,
      memberPeerIds: activeMembers,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceReactionTargetBeforeRemoval',
          'msg-pl010-target',
          'PL-010 Alice pre-removal target',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceReactionTargetBeforeRemoval': 1,
      },
      extra: <String, Object?>{
        'pl010RemovedReactionProof': proofFor(
          'charlie',
          selfRemovedOrExcluded: true,
        ),
      },
    ),
  ];
}

Map<String, dynamic> _withPl010ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'pl010RemovedReactionProof': <String, Object?>{
      ...Map<String, Object?>.from(verdict['pl010RemovedReactionProof'] as Map),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateOnlineAddVerdicts() {
  const scenario = 'private_online_add';
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-online-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterDanaAdd',
          'messageId': 'poa-a1',
          'text': 'private alice after dana',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterDanaAdd',
          'poa-b1',
          'private bob after dana',
          'bob-peer',
          keyEpoch: 2,
        ),
        _received(
          'danaAfterJoin',
          'poa-d1',
          'private dana joined',
          'dana-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterDanaAdd': 1,
        'danaAfterJoin': 1,
      },
      extra: _privateOnlineAddVerdictExtra(
        deviceId: 'sim-alice',
        members: members,
        ml002Proof: _ml002AliceProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-online-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterDanaAdd',
          'messageId': 'poa-b1',
          'text': 'private bob after dana',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'poa-a1',
          'private alice after dana',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'danaAfterJoin',
          'poa-d1',
          'private dana joined',
          'dana-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaAdd': 1,
        'danaAfterJoin': 1,
      },
      extra: _privateOnlineAddVerdictExtra(
        deviceId: 'sim-bob',
        members: members,
        ml002Proof: _ml002BobProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-online-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'poa-a1',
          'private alice after dana',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterDanaAdd',
          'poa-b1',
          'private bob after dana',
          'bob-peer',
          keyEpoch: 2,
        ),
        _received(
          'danaAfterJoin',
          'poa-d1',
          'private dana joined',
          'dana-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaAdd': 1,
        'bobAfterDanaAdd': 1,
        'danaAfterJoin': 1,
      },
      extra: _privateOnlineAddVerdictExtra(
        deviceId: 'sim-charlie',
        members: members,
        ml002Proof: _ml002CharlieProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'dana',
      peerId: 'dana-peer',
      groupId: 'private-online-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'danaAfterJoin',
          'messageId': 'poa-d1',
          'text': 'private dana joined',
          'outcome': 'successNoPeers',
          'senderPeerId': 'dana-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'poa-a1',
          'private alice after dana',
          'alice-peer',
          keyEpoch: 2,
          liveOnly: true,
          usedOfflineDrain: false,
        ),
        _received(
          'bobAfterDanaAdd',
          'poa-b1',
          'private bob after dana',
          'bob-peer',
          keyEpoch: 2,
          liveOnly: true,
          usedOfflineDrain: false,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaAdd': 1,
        'bobAfterDanaAdd': 1,
      },
      extra: _privateOnlineAddVerdictExtra(
        deviceId: 'sim-dana',
        members: members,
        ml002Proof: _ml002DanaProof(),
      ),
    ),
  ];
}

Map<String, Object?> _privateOnlineAddVerdictExtra({
  required String deviceId,
  required List<String> members,
  required Map<String, Object?> ml002Proof,
}) {
  return <String, Object?>{
    'deviceId': deviceId,
    'topicName': '/mknoon/group/private-online-add',
    'activeMemberPeerIds': members,
    'groupConfigStateHash': 'private-online-add-state',
    'ml002OnlineAddProof': ml002Proof,
  };
}

Map<String, Object?> _ml002AliceProof() {
  return const <String, Object?>{
    'rowId': 'ML-002',
    'danaOnlineBeforeAdd': true,
    'danaNotActiveBeforeAdd': true,
    'aliceAddedDana': true,
    'danaJoinedAfterAdd': true,
    'allRolesSeeDanaActiveAfterJoin': true,
    'aliceSentPostJoin': true,
    'bobSentPostJoin': true,
  };
}

Map<String, Object?> _ml002BobProof() {
  return const <String, Object?>{
    'rowId': 'ML-002',
    'danaActiveAfterJoin': true,
    'bobSentPostJoin': true,
  };
}

Map<String, Object?> _ml002CharlieProof() {
  return const <String, Object?>{
    'rowId': 'ML-002',
    'danaActiveAfterJoin': true,
  };
}

Map<String, Object?> _ml002DanaProof() {
  return const <String, Object?>{
    'rowId': 'ML-002',
    'danaOnlineBeforeAdd': true,
    'danaNotActiveBeforeAdd': true,
    'joinedViaGroupJoinWithConfig': true,
    'currentKeyEpochInstalledBeforeLiveReceive': true,
    'receivedAlicePostJoinLiveNoDrain': true,
    'receivedBobPostJoinLiveNoDrain': true,
    'noOfflineDrainBeforeLiveReceipts': true,
  };
}

List<Map<String, dynamic>> _validPrivateOfflineAddVerdicts() {
  const scenario = 'private_offline_add';
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-offline-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterDanaOfflineAdd',
          'messageId': 'poff-a1',
          'text': 'private alice offline replay',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceLiveAfterDanaDrain',
          'messageId': 'poff-live1',
          'text': 'private alice live after drain',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterDanaOfflineAdd',
          'poff-b1',
          'private bob offline replay',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobAfterDanaOfflineAdd': 1},
      extra: _privateOfflineAddVerdictExtra(
        deviceId: 'sim-alice',
        members: members,
        ml003Proof: _ml003AliceProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-offline-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterDanaOfflineAdd',
          'messageId': 'poff-b1',
          'text': 'private bob offline replay',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaOfflineAdd',
          'poff-a1',
          'private alice offline replay',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaOfflineAdd': 1,
      },
      extra: _privateOfflineAddVerdictExtra(
        deviceId: 'sim-bob',
        members: members,
        ml003Proof: _ml003BobProof(),
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-offline-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaOfflineAdd',
          'poff-a1',
          'private alice offline replay',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterDanaOfflineAdd',
          'poff-b1',
          'private bob offline replay',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaOfflineAdd': 1,
        'bobAfterDanaOfflineAdd': 1,
      },
      extra: _privateOfflineAddVerdictExtra(
        deviceId: 'sim-charlie',
        members: members,
      ),
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'dana',
      peerId: 'dana-peer',
      groupId: 'private-offline-add-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaOfflineAdd',
          'poff-a1',
          'private alice offline replay',
          'alice-peer',
          keyEpoch: 2,
          liveOnly: false,
          usedOfflineDrain: true,
        ),
        _received(
          'bobAfterDanaOfflineAdd',
          'poff-b1',
          'private bob offline replay',
          'bob-peer',
          keyEpoch: 2,
          liveOnly: false,
          usedOfflineDrain: true,
        ),
        _received(
          'aliceLiveAfterDanaDrain',
          'poff-live1',
          'private alice live after drain',
          'alice-peer',
          keyEpoch: 2,
          liveOnly: true,
          usedOfflineDrain: false,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaOfflineAdd': 1,
        'bobAfterDanaOfflineAdd': 1,
        'aliceLiveAfterDanaDrain': 1,
      },
      extra: _privateOfflineAddVerdictExtra(
        deviceId: 'sim-dana',
        members: members,
        ml003Proof: _ml003DanaProof(),
      ),
    ),
  ];
}

Map<String, Object?> _privateOfflineAddVerdictExtra({
  required String deviceId,
  required List<String> members,
  Map<String, Object?>? ml003Proof,
}) {
  return <String, Object?>{
    'deviceId': deviceId,
    'topicName': '/mknoon/group/private-offline-add',
    'activeMemberPeerIds': members,
    'groupConfigStateHash': 'private-offline-add-state',
    'ml003OfflineAddProof': ?ml003Proof,
  };
}

Map<String, Object?> _ml003AliceProof() {
  return const <String, Object?>{
    'rowId': 'ML-003',
    'invitePath': 'supported_pending_invite',
    'danaOfflineDuringAdd': true,
    'danaNotSubscribedDuringAdd': true,
    'danaNotActiveBeforeAccept': true,
    'aliceAddedDana': true,
    'aliceSentPostAddBeforeDanaAccept': true,
    'bobSentPostAddBeforeDanaAccept': true,
    'liveSentAfterDanaDrain': true,
  };
}

Map<String, Object?> _ml003BobProof() {
  return const <String, Object?>{
    'rowId': 'ML-003',
    'danaActiveInConfigBeforeBobSend': true,
    'bobSentPostAddBeforeDanaAccept': true,
  };
}

Map<String, Object?> _ml003DanaProof() {
  return const <String, Object?>{
    'rowId': 'ML-003',
    'invitePath': 'supported_pending_invite',
    'startedAfterPostAddSends': true,
    'storedPendingInvite': true,
    'acceptedPendingInvite': true,
    'joinedViaGroupJoinWithConfig': true,
    'drainedOfflineInbox': true,
    'preAddMessageAbsent': true,
    'receivedAlicePostAddReplay': true,
    'receivedBobPostAddReplay': true,
    'replayPersistedExactlyOnce': true,
    'liveAfterDrainWithoutRestart': true,
  };
}

List<Map<String, dynamic>> _validGm002Verdicts() {
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm002',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm002-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterDanaAdd',
          'messageId': 'gm002-a1',
          'text': 'alice after dana',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received('danaAfterJoin', 'gm002-d1', 'dana joined', 'dana-peer'),
      ],
      persistedMessageCounts: const <String, int>{'danaAfterJoin': 1},
    ),
    _baseVerdict(
      scenario: 'gm002',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm002-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'gm002-a1',
          'alice after dana',
          'alice-peer',
        ),
        _received('danaAfterJoin', 'gm002-d1', 'dana joined', 'dana-peer'),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaAdd': 1,
        'danaAfterJoin': 1,
      },
    ),
    _baseVerdict(
      scenario: 'gm002',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm002-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'gm002-a1',
          'alice after dana',
          'alice-peer',
        ),
        _received('danaAfterJoin', 'gm002-d1', 'dana joined', 'dana-peer'),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaAdd': 1,
        'danaAfterJoin': 1,
      },
    ),
    _baseVerdict(
      scenario: 'gm002',
      role: 'dana',
      peerId: 'dana-peer',
      groupId: 'gm002-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'danaAfterJoin',
          'messageId': 'gm002-d1',
          'text': 'dana joined',
          'outcome': 'successNoPeers',
          'senderPeerId': 'dana-peer',
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaAdd',
          'gm002-a1',
          'alice after dana',
          'alice-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterDanaAdd': 1},
    ),
  ];
}

List<Map<String, dynamic>> _validGm003Verdicts() {
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm003',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm003-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceBeforeDanaAdd',
          'messageId': 'gm003-a-before',
          'text': 'alice before dana',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 3,
        },
        {
          'key': 'aliceAfterDanaOfflineAdd',
          'messageId': 'gm003-a-after',
          'text': 'alice after offline dana add',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'danaAfterOfflineJoin',
          'gm003-d-after',
          'dana after offline join',
          'dana-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{'danaAfterOfflineJoin': 1},
      extra: const <String, Object?>{
        'gm003OfflineAddProof': <String, Object?>{
          'danaOfflineDuringAdd': true,
          'postAddSentBeforeDanaLaunch': true,
          'danaLaunchedAfterPostAddSend': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm003',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm003-group',
      memberPeerIds: members,
      keyEpoch: 3,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeDanaAdd',
          'gm003-a-before',
          'alice before dana',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'aliceAfterDanaOfflineAdd',
          'gm003-a-after',
          'alice after offline dana add',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'danaAfterOfflineJoin',
          'gm003-d-after',
          'dana after offline join',
          'dana-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeDanaAdd': 1,
        'aliceAfterDanaOfflineAdd': 1,
        'danaAfterOfflineJoin': 1,
      },
    ),
    _baseVerdict(
      scenario: 'gm003',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm003-group',
      memberPeerIds: members,
      keyEpoch: 3,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeDanaAdd',
          'gm003-a-before',
          'alice before dana',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'aliceAfterDanaOfflineAdd',
          'gm003-a-after',
          'alice after offline dana add',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'danaAfterOfflineJoin',
          'gm003-d-after',
          'dana after offline join',
          'dana-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeDanaAdd': 1,
        'aliceAfterDanaOfflineAdd': 1,
        'danaAfterOfflineJoin': 1,
      },
    ),
    _baseVerdict(
      scenario: 'gm003',
      role: 'dana',
      peerId: 'dana-peer',
      groupId: 'gm003-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'danaAfterOfflineJoin',
          'messageId': 'gm003-d-after',
          'text': 'dana after offline join',
          'outcome': 'successNoPeers',
          'senderPeerId': 'dana-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDanaOfflineAdd',
          'gm003-a-after',
          'alice after offline dana add',
          'alice-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDanaOfflineAdd': 1,
      },
      extra: const <String, Object?>{
        'gm003OfflineCatchUpProof': <String, Object?>{
          'startedAfterPostAddSend': true,
          'installedGroupConfigBeforeCatchUp': true,
          'drainedOfflineInbox': true,
          'preAddMessageAbsent': true,
          'postAddMessageCaughtUp': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm004Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm004',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm004-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterCharlieRemove',
          'messageId': 'gm004-a-after',
          'text': 'alice after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterCharlieRemove',
          'gm004-b-after',
          'bob after charlie remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobAfterCharlieRemove': 1},
      extra: const <String, Object?>{
        'gm004RemovalProof': <String, Object?>{
          'charlieOnlineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'rotatedEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm004',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm004-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterCharlieRemove',
          'messageId': 'gm004-b-after',
          'text': 'bob after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterCharlieRemove',
          'gm004-a-after',
          'alice after charlie remove',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterCharlieRemove': 1},
      extra: const <String, Object?>{
        'gm004RemovalProof': <String, Object?>{
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm004',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm004-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        'gm004RemovalProof': <String, Object?>{
          'onlineBeforeRemoval': true,
          'currentMemberBeforeRemoval': true,
          'groupPresentAfterRemoval': false,
          'hasRotatedEpoch': false,
          'rotatedEpoch': 0,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAliceAfterRemoval': false,
          'receivedBobAfterRemoval': false,
          'postRemovalPlaintextCount': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateOnlineRemoveVerdicts() {
  const scenario = 'private_online_remove';
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-online-remove-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterCharlieRemove',
          'messageId': 'ml005-a-after',
          'text': 'alice after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterCharlieRemove',
          'ml005-b-after',
          'bob after charlie remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobAfterCharlieRemove': 1},
      extra: const <String, Object?>{
        'ml005OnlineRemovalProof': <String, Object?>{
          'rowId': 'ML-005',
          'charlieOnlineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'receivedBobAfterRemoval': true,
          'rotatedEpoch': 2,
        },
        'ke006RemovalKeyRotationProof': <String, Object?>{
          'rowId': 'KE-006',
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'rotatedKeyGenerated': true,
          'rotatedEpoch': 2,
          'distributedRotatedKeyToBob': true,
          'sentPostRemovalAtRotatedEpoch': true,
          'receivedBobAfterRemoval': true,
        },
        'pl006RemovedMediaProof': <String, Object?>{
          'rowId': 'PL-006',
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'mediaUploadedAfterRemoval': true,
          'mediaBlobId': 'pl006-post-removal-media',
          'uploadAllowedPeers': <String>['alice-peer', 'bob-peer'],
          'uploadAllowedPeersExcludeRemoved': true,
          'uploadAllowedPeersIncludeActive': true,
          'uploadAllowedPeersCount': 2,
          'sentPostRemovalMediaAtRotatedEpoch': true,
          'bobReceiptSignalObserved': true,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-online-remove-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterCharlieRemove',
          'messageId': 'ml005-b-after',
          'text': 'bob after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterCharlieRemove',
          'ml005-a-after',
          'alice after charlie remove',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterCharlieRemove': 1},
      extra: const <String, Object?>{
        'ml005OnlineRemovalProof': <String, Object?>{
          'rowId': 'ML-005',
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
          'receivedAliceAfterRemoval': true,
          'sentPostRemovalAccepted': true,
        },
        'ke006RemovalKeyRotationProof': <String, Object?>{
          'rowId': 'KE-006',
          'memberListExcludesCharlie': true,
          'receivedRotatedKey': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
          'receivedAliceAfterRemoval': true,
          'sentPostRemovalAtRotatedEpoch': true,
        },
        'pl006RemovedMediaProof': <String, Object?>{
          'rowId': 'PL-006',
          'memberListExcludesCharlie': true,
          'removedPeerId': 'charlie-peer',
          'receivedAliceAfterRemoval': true,
          'receivedAliceAfterRemovalAtRotatedEpoch': true,
          'bobReceivedMediaDescriptor': true,
          'bobMediaDownloaded': true,
          'mediaCount': 1,
          'mediaBlobId': 'pl006-post-removal-media',
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-online-remove-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        'ml005OnlineRemovalProof': <String, Object?>{
          'rowId': 'ML-005',
          'onlineBeforeRemoval': true,
          'currentMemberBeforeRemoval': true,
          'groupPresentAfterRemoval': false,
          'hasRotatedEpoch': false,
          'rotatedEpoch': 0,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAliceAfterRemoval': false,
          'receivedBobAfterRemoval': false,
          'postRemovalPlaintextCount': 0,
        },
        'ke006RemovalKeyRotationProof': <String, Object?>{
          'rowId': 'KE-006',
          'onlineBeforeRemoval': true,
          'currentMemberBeforeRemoval': true,
          'excludedFromRotatedKeyDistribution': true,
          'hasRotatedEpoch': false,
          'excludedRotatedEpoch': 2,
          'retainedEpochAfterRemoval': 0,
          'postRemovalPublishAccepted': false,
          'receivedAliceAfterRemoval': false,
          'receivedBobAfterRemoval': false,
          'postRemovalPlaintextCount': 0,
        },
        'pl006RemovedMediaProof': <String, Object?>{
          'rowId': 'PL-006',
          'onlineBeforeRemoval': true,
          'currentMemberBeforeRemoval': true,
          'groupPresentAfterRemoval': false,
          'mediaBlobId': 'pl006-post-removal-media',
          'directDownloadAttempted': true,
          'directDownloadDenied': true,
          'directDownloadOk': false,
          'directDownloadError': 'not authorized',
          'directDownloadOutputBytes': 0,
          'noDirectDownloadPlaintext': true,
          'noPostRemovalMessage': true,
          'postRemovalPlaintextCount': 0,
          'mediaRowsAfterRemoval': 0,
          'replayMediaRowsAbsent': true,
          'pendingDownloadsAfterRemoval': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateOfflineRemoveVerdicts() {
  const scenario = 'private_offline_remove';
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-offline-remove-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterCharlieOfflineRemove',
          'messageId': 'ml006-a-after',
          'text': 'alice after offline charlie remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterCharlieOfflineRemove',
          'ml006-b-after',
          'bob after offline charlie remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterCharlieOfflineRemove': 1,
      },
      extra: const <String, Object?>{
        'ml006OfflineRemovalProof': <String, Object?>{
          'rowId': 'ML-006',
          'charlieOfflineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'sentPostRemovalAccepted': true,
          'receivedBobAfterRemoval': true,
          'rotatedEpoch': 2,
        },
        'ir004PostRemovalReplayProof': <String, Object?>{
          'rowId': 'IR-004',
          'charlieOfflineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'sentAlicePostRemoval': true,
          'receivedBobPostRemoval': true,
          'rotatedEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-offline-remove-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterCharlieOfflineRemove',
          'messageId': 'ml006-b-after',
          'text': 'bob after offline charlie remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterCharlieOfflineRemove',
          'ml006-a-after',
          'alice after offline charlie remove',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterCharlieOfflineRemove': 1,
      },
      extra: const <String, Object?>{
        'ml006OfflineRemovalProof': <String, Object?>{
          'rowId': 'ML-006',
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
          'receivedAliceAfterRemoval': true,
          'sentPostRemovalAccepted': true,
        },
        'ir004PostRemovalReplayProof': <String, Object?>{
          'rowId': 'IR-004',
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
          'receivedAlicePostRemoval': true,
          'sentBobPostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-offline-remove-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        'ml006OfflineRemovalProof': <String, Object?>{
          'rowId': 'ML-006',
          'hadOldConfigBeforeOffline': true,
          'hadOldKeyBeforeOffline': true,
          'offlineDuringRemoval': true,
          'reconnectedWithStaleState': true,
          'retrievedInboxAfterReconnect': true,
          'convergedRemoved': true,
          'groupPresentAfterCatchUp': false,
          'hasRotatedEpoch': false,
          'rotatedEpoch': 0,
          'postRemovalPlaintextCount': 0,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAliceAfterRemoval': false,
          'receivedBobAfterRemoval': false,
        },
        'ir004PostRemovalReplayProof': <String, Object?>{
          'rowId': 'IR-004',
          'hadOldConfigBeforeOffline': true,
          'hadOldKeyBeforeOffline': true,
          'offlineDuringRemoval': true,
          'reconnectedWithStaleState': true,
          'retrievedInboxAfterReconnect': true,
          'convergedRemoved': true,
          'groupPresentAfterCatchUp': false,
          'retainedRotatedEpoch': false,
          'staleKeyEpochBeforeDrain': 1,
          'rotatedEpochAfterDrain': 0,
          'postRemovalPlaintextCount': 0,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAlicePostRemoval': false,
          'receivedBobPostRemoval': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm005Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  final aliceSentMessages = <Map<String, Object?>>[
    const {
      'key': 'aliceAfterCharlieOfflineRemove1',
      'messageId': 'gm005-a-after-1',
      'text': 'alice after offline charlie remove 1',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
    },
    const {
      'key': 'aliceAfterCharlieOfflineRemove2',
      'messageId': 'gm005-a-after-2',
      'text': 'alice after offline charlie remove 2',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
    },
    const {
      'key': 'aliceAfterCharlieOfflineRemove3',
      'messageId': 'gm005-a-after-3',
      'text': 'alice after offline charlie remove 3',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
    },
  ];
  final bobReceivedMessages = <Map<String, Object?>>[
    _received(
      'aliceAfterCharlieOfflineRemove1',
      'gm005-a-after-1',
      'alice after offline charlie remove 1',
      'alice-peer',
      keyEpoch: 2,
    ),
    _received(
      'aliceAfterCharlieOfflineRemove2',
      'gm005-a-after-2',
      'alice after offline charlie remove 2',
      'alice-peer',
      keyEpoch: 2,
    ),
    _received(
      'aliceAfterCharlieOfflineRemove3',
      'gm005-a-after-3',
      'alice after offline charlie remove 3',
      'alice-peer',
      keyEpoch: 2,
    ),
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm005',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm005-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: aliceSentMessages,
      extra: const <String, Object?>{
        'gm005OfflineRemovalProof': <String, Object?>{
          'charlieOfflineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'rotatedEpoch': 2,
          'postRemovalMessageCount': 3,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm005',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm005-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      receivedMessages: bobReceivedMessages,
      persistedMessageCounts: const <String, int>{
        'aliceAfterCharlieOfflineRemove1': 1,
        'aliceAfterCharlieOfflineRemove2': 1,
        'aliceAfterCharlieOfflineRemove3': 1,
      },
      extra: const <String, Object?>{
        'gm005OfflineRemovalProof': <String, Object?>{
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
          'receivedAllAlicePostRemovalMessages': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm005',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm005-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        'gm005OfflineRemovalProof': <String, Object?>{
          'hadOldConfigBeforeOffline': true,
          'hadOldKeyBeforeOffline': true,
          'offlineDuringRemoval': true,
          'reconnectedWithStaleState': true,
          'retrievedInboxAfterReconnect': true,
          'convergedRemoved': true,
          'groupPresentAfterCatchUp': false,
          'hasRotatedEpoch': false,
          'rotatedEpoch': 0,
          'postRemovalPlaintextCount': 0,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm006Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm006',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm006-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRemoval',
          'messageId': 'gm006-a-during',
          'text': 'alice during charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterImmediateReadd',
          'messageId': 'gm006-a-after',
          'text': 'alice after immediate readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterImmediateReadd',
          'gm006-c-after',
          'charlie after immediate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm006ImmediateReaddProof': <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'sentRemovedWindowBeforeReadd': true,
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm006',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm006-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRemoval',
          'gm006-a-during',
          'alice during charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterImmediateReadd',
          'gm006-c-after',
          'charlie after immediate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterImmediateReadd',
          'gm006-a-after',
          'alice after immediate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRemoval': 1,
        'charlieAfterImmediateReadd': 1,
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm006ImmediateReaddProof': <String, Object?>{
          'memberListIncludesCharlie': true,
          'receivedRemovedWindowMessage': true,
          'receivedCharliePostReaddMessage': true,
          'receivedAlicePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm006',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm006-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterImmediateReadd',
          'messageId': 'gm006-c-after',
          'text': 'charlie after immediate readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterImmediateReadd',
          'gm006-a-after',
          'alice after immediate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm006ImmediateReaddProof': <String, Object?>{
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterReadd': false,
          'postReaddPublishAccepted': true,
          'receivedAlicePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateOfflineReaddVerdicts() {
  const scenario = 'private_offline_readd';
  const groupId = 'private-offline-readd-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRemoval',
          'messageId': 'ra003-a-during',
          'text': 'alice during offline charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterImmediateReadd',
          'messageId': 'ra003-a-after',
          'text': 'alice after offline readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterImmediateReadd',
          'ra003-c-after',
          'charlie after offline readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterOfflineReadd',
          'ra003-b-after',
          'bob after offline readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterImmediateReadd': 1,
        'bobAfterOfflineReadd': 1,
      },
      extra: const <String, Object?>{
        'ra003OfflineReaddProof': <String, Object?>{
          'rowId': 'RA-003',
          'removedCharlieWhileOffline': true,
          'sentRemovedWindowWhileCharlieOffline': true,
          'waitedForCharlieRemovalResolutionBeforeReadd': true,
          'readdedCharlieAfterReconnect': true,
          'sentPostReaddAfterOfflineReconnect': true,
          'receivedCharliePostReaddAfterOfflineReconnect': true,
          'receivedBobPostReaddAfterOfflineReconnect': true,
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterOfflineReadd',
          'messageId': 'ra003-b-after',
          'text': 'bob after offline readd',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRemoval',
          'ra003-a-during',
          'alice during offline charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterImmediateReadd',
          'ra003-c-after',
          'charlie after offline readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterImmediateReadd',
          'ra003-a-after',
          'alice after offline readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRemoval': 1,
        'charlieAfterImmediateReadd': 1,
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra003OfflineReaddProof': <String, Object?>{
          'rowId': 'RA-003',
          'observedCharlieRemovedWhileOffline': true,
          'receivedRemovedWindowWhileCharlieOffline': true,
          'observedCharlieReaddedAfterReconnect': true,
          'receivedAlicePostReaddAfterOfflineReconnect': true,
          'sentBobPostReaddAfterOfflineReconnect': true,
          'receivedCharliePostReaddAfterOfflineReconnect': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterImmediateReadd',
          'messageId': 'ra003-c-after',
          'text': 'charlie after offline readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterImmediateReadd',
          'ra003-a-after',
          'alice after offline readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterOfflineReadd',
          'ra003-b-after',
          'bob after offline readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterImmediateReadd': 1,
        'bobAfterOfflineReadd': 1,
      },
      extra: const <String, Object?>{
        'ra003OfflineReaddProof': <String, Object?>{
          'rowId': 'RA-003',
          'offlineDuringRemoval': true,
          'reconnectedBeforeReadd': true,
          'resolvedRemovalBeforeReadd': true,
          'removedWindowPlaintextCount': 0,
          'rejoinedAfterOfflineRemoval': true,
          'receivedAlicePostReaddAfterOfflineReconnect': true,
          'receivedBobPostReaddAfterOfflineReconnect': true,
          'postReaddPublishAccepted': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateReaddCurrentVerdicts() {
  const scenario = 'private_readd_current';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'private-readd-current-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRemoval',
          'messageId': 'ml007-a-during',
          'text': 'alice during charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterImmediateReadd',
          'messageId': 'ml007-a-after',
          'text': 'alice after immediate readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterCharlieRestart',
          'messageId': 'ra010-a-after-restart',
          'text': 'alice after charlie restart',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterImmediateReadd',
          'ml007-c-after',
          'charlie after immediate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterReaddCurrent',
          'ml007-b-after',
          'bob after readd current',
          'bob-peer',
          keyEpoch: 2,
          quotedMessageId: 'ml007-a-after',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterImmediateReadd': 1,
        'bobAfterReaddCurrent': 1,
      },
      extra: const <String, Object?>{
        'ml007ReaddCurrentProof': <String, Object?>{
          'rowId': 'ML-007',
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'sentRemovedWindowBeforeReadd': true,
          'sentAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
        'up001MembershipConfigSyncProof': <String, Object?>{
          'rowId': 'UP-001',
          'role': 'alice',
          'nativeValidatorCoveredByHost': true,
          'liveThreePartyProof': true,
          'groupConfigStateHashObserved': true,
          'finalDbConfigUiConverged': true,
          'createSnapshotMatched': true,
          'addSnapshotMatched': true,
          'removeSnapshotMatched': true,
          'readdSnapshotMatched': true,
          'finalEpoch': 2,
          'operationSnapshots': <Map<String, Object?>>[
            <String, Object?>{
              'operation': 'create',
              'dbMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'configMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'uiMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
            },
            <String, Object?>{
              'operation': 'add',
              'dbMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'configMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'uiMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
            },
            <String, Object?>{
              'operation': 'remove',
              'dbMemberPeerIds': <String>['alice-peer', 'bob-peer'],
              'configMemberPeerIds': <String>['alice-peer', 'bob-peer'],
              'uiMemberPeerIds': <String>['alice-peer', 'bob-peer'],
            },
            <String, Object?>{
              'operation': 'readd',
              'dbMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'configMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
              'uiMemberPeerIds': <String>[
                'alice-peer',
                'bob-peer',
                'charlie-peer',
              ],
            },
          ],
        },
        'pl004QuoteReaddLiveProof': <String, Object?>{
          'rowId': 'PL-004',
          'quoteBoundary': 'post_readd_live',
          'quoteSenderRole': 'bob',
          'readdedCharlieBeforeQuote': true,
          'quoteTargetMessageId': 'ml007-a-after',
          'receivedQuotedMessageId': 'ml007-a-after',
          'receivedQuotedPostReaddLive': true,
          'quoteTargetVisibleBeforeQuotedDelivery': true,
          'finalEpoch': 2,
        },
        'pl007ReaddMediaProof': <String, Object?>{
          'rowId': 'PL-007',
          'removedPeerId': 'charlie-peer',
          'removedCharlie': true,
          'readdedCharlie': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowMessageKey': 'aliceDuringCharlieRemoval',
          'postReaddMessageKey': 'aliceAfterImmediateReadd',
          'removedWindowMediaBlobId': 'pl007-removed-window-media',
          'postReaddMediaBlobId': 'pl007-post-readd-media',
          'removedWindowSentWhileCharlieRemoved': true,
          'postReaddMediaSentAfterReadd': true,
          'removedWindowMediaSentAtCurrentEpoch': true,
          'postReaddMediaSentAtCurrentEpoch': true,
          'removedWindowAllowedPeers': <String>['alice-peer', 'bob-peer'],
          'removedWindowAllowedPeersExcludeCharlie': true,
          'removedWindowAllowedPeersIncludeActive': true,
          'removedWindowAllowedPeersCount': 2,
          'postReaddAllowedPeers': <String>[
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          ],
          'postReaddAllowedPeersIncludeAll': true,
          'postReaddAllowedPeersCount': 3,
          'finalEpoch': 2,
        },
        'pl011ReaddReactionProof': <String, Object?>{
          'rowId': 'PL-011',
          'activeRoles': <String>['alice', 'bob', 'charlie'],
          'readdedRole': 'charlie',
          'reactorRole': 'charlie',
          'targetMessageId': 'ml007-a-after',
          'reactionEmoji': '✅',
          'reactionOutcome': 'success',
          'reactionAccepted': true,
          'observedByRole': 'alice',
          'receivedViaGroupReactionStream': true,
          'appliedOnceToTarget': true,
          'persistedReactionCount': 1,
          'readdedBeforeReaction': true,
          'targetVisibleBeforeReaction': true,
          'postReaddReactionAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'aliceObservedSignal': true,
          'bobObservedSignal': true,
          'finalEpoch': 2,
        },
        'ra002OnlineSubscribedReaddProof': <String, Object?>{
          'rowId': 'RA-002',
          'removedCharlieWhileOnline': true,
          'sentRemovedWindowWhileCharlieOnline': true,
          'readdedCharlieWithoutRestart': true,
          'sentPostReaddWithoutCharlieRestart': true,
          'receivedCharliePostReaddWithoutRestart': true,
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
        'ke008ReaddActivationProof': <String, Object?>{
          'rowId': 'KE-008',
          'readdCurrentKeyAvailableBeforeFixture': true,
          'wroteReaddFixtureWithCurrentKey': true,
          'readdEpoch': 2,
          'waitedForCharlieCurrentKeyRejoinBeforePostReaddSends': true,
          'charlieAcknowledgedRejoinAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ke010KeyBeforeConfigProof': <String, Object?>{
          'rowId': 'KE-010',
          'keyBeforeConfigOrderingCoveredByFakeNetwork': true,
          'liveAuthorizedDeliveryCovered': true,
          'sentPostConfigAuthorizedAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ke011DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'KE-011',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'deliveredDelayedOldKeyAfterReadd': true,
          'sentAlicePostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra006DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'RA-006',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'deliveredDelayedOldKeyAfterReadd': true,
          'sentAlicePostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra007PartitionedObserverReaddProof': <String, Object?>{
          'rowId': 'RA-007',
          'partitionedObserverOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'removedCharlie': true,
          'readdedCharlie': true,
          'sentRemovedWindowWhileBobPartitionedCoveredByFakeNetwork': true,
          'sentAlicePostHealAtCurrentEpoch': true,
          'receivedBobPostHealAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ra008PartitionedRemovedReaddProof': <String, Object?>{
          'rowId': 'RA-008',
          'removedPeerPartitionOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'removedCharlie': true,
          'readdedCharlie': true,
          'sentRemovedWindowWhileCharliePartitionedCoveredByFakeNetwork': true,
          'sentAlicePostHealAtCurrentEpoch': true,
          'receivedBobPostHealAtCurrentEpoch': true,
          'receivedCharliePostHealAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ra009FirstReaddPublishProof': <String, Object?>{
          'rowId': 'RA-009',
          'firstReaddPublishOrderingCoveredByFakeNetwork': true,
          'liveFirstReaddPublishCovered': true,
          'readdedCharlie': true,
          'receivedCharlieFirstPostReaddAtCurrentEpoch': true,
          'firstCharliePostReaddMessageKey': 'charlieAfterImmediateReadd',
          'finalEpoch': 2,
        },
        'ra010ReaddIncomingRestartProof': <String, Object?>{
          'rowId': 'RA-010',
          'liveIncomingBeforeAndAfterRestartCovered': true,
          'readdedCharlie': true,
          'sentFirstIncomingBeforeCharlieRestartAtCurrentEpoch': true,
          'sentSecondIncomingAfterCharlieRestartAtCurrentEpoch': true,
          'firstIncomingMessageKey': 'aliceAfterImmediateReadd',
          'postRestartIncomingMessageKey': 'aliceAfterCharlieRestart',
          'finalEpoch': 2,
        },
        'ra014OldKeyPublishAfterReaddProof': <String, Object?>{
          'rowId': 'RA-014',
          'staleOldPublishRejectionCoveredByFakeNetwork': true,
          'nativeOldKeyPublishRejectionCovered': true,
          'livePostRejectDeliveryCovered': true,
          'rejectedCharlieOldKeyPublish': true,
          'sentAliceCurrentAfterReject': true,
          'receivedCharlieCurrentAfterReject': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra015AlreadyJoinedReaddRefreshProof': <String, Object?>{
          'rowId': 'RA-015',
          'flutterAlreadyJoinedPayloadCoveredByHost': true,
          'nativeAlreadyJoinedRefreshCovered': true,
          'fakeNetworkAlreadyJoinedReaddCovered': true,
          'livePostRefreshDeliveryCovered': true,
          'readdedCharlie': true,
          'sentAliceCurrentAfterRefresh': true,
          'receivedCharlieCurrentAfterRefresh': true,
          'finalEpoch': 2,
        },
        'ra016RemovedIntervalReplayProof': <String, Object?>{
          'rowId': 'RA-016',
          'hostDirectRemovedIntervalReplayCovered': true,
          'hostFakeNetworkRemovedIntervalReplayCovered': true,
          'removedIntervalReplayRejectedByRecipientInterval': true,
          'livePostReaddCurrentDeliveryCovered': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'sentAlicePostReaddCurrent': true,
          'receivedBobPostReaddCurrent': true,
          'receivedCharliePostReaddCurrent': true,
          'finalEpoch': 2,
        },
        'ke012DelayedOldConfigAfterReaddProof': <String, Object?>{
          'rowId': 'KE-012',
          'delayedOldConfigOrderingCoveredByFakeNetwork': true,
          'livePostStaleConfigDeliveryCovered': true,
          'deliveredDelayedOldConfigAfterReadd': true,
          'sentAlicePostStaleConfigAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'private-readd-current-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterReaddCurrent',
          'messageId': 'ml007-b-after',
          'text': 'bob after readd current',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
          'quotedMessageId': 'ml007-a-after',
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRemoval',
          'ml007-a-during',
          'alice during charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterImmediateReadd',
          'ml007-c-after',
          'charlie after immediate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterImmediateReadd',
          'ml007-a-after',
          'alice after immediate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterCharlieRestart',
          'ra010-a-after-restart',
          'alice after charlie restart',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRemoval': 1,
        'charlieAfterImmediateReadd': 1,
        'aliceAfterImmediateReadd': 1,
        'aliceAfterCharlieRestart': 1,
      },
      extra: const <String, Object?>{
        'ml007ReaddCurrentProof': <String, Object?>{
          'rowId': 'ML-007',
          'memberListIncludesCharlie': true,
          'receivedRemovedWindowMessage': true,
          'sentBobPostReaddMessage': true,
          'receivedAlicePostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
        'up001MembershipConfigSyncProof': <String, Object?>{
          'rowId': 'UP-001',
          'role': 'bob',
          'nativeValidatorCoveredByHost': true,
          'liveThreePartyProof': true,
          'groupConfigStateHashObserved': true,
          'finalDbConfigUiConverged': true,
          'observedRemovalSnapshot': true,
          'observedReaddSnapshot': true,
          'finalEpoch': 2,
        },
        'pl004QuoteReaddLiveProof': <String, Object?>{
          'rowId': 'PL-004',
          'quoteBoundary': 'post_readd_live',
          'quoteSenderRole': 'bob',
          'observedCharlieReaddedBeforeQuote': true,
          'quoteTargetMessageId': 'ml007-a-after',
          'sentQuotedMessageId': 'ml007-a-after',
          'sentQuotedPostReaddLive': true,
          'quoteTargetVisibleBeforeSend': true,
          'finalEpoch': 2,
        },
        'pl007ReaddMediaProof': <String, Object?>{
          'rowId': 'PL-007',
          'removedPeerId': 'charlie-peer',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowMessageKey': 'aliceDuringCharlieRemoval',
          'postReaddMessageKey': 'aliceAfterImmediateReadd',
          'removedWindowMediaBlobId': 'pl007-removed-window-media',
          'postReaddMediaBlobId': 'pl007-post-readd-media',
          'retainedActiveMembershipDuringRemovedWindow': true,
          'removedWindowMediaMessageReceived': true,
          'removedWindowMediaDownloaded': true,
          'removedWindowMediaPersisted': true,
          'postReaddMediaMessageReceived': true,
          'postReaddMediaDownloaded': true,
          'postReaddMediaPersisted': true,
          'postReaddMediaDecrypted': true,
          'finalEpoch': 2,
        },
        'pl011ReaddReactionProof': <String, Object?>{
          'rowId': 'PL-011',
          'activeRoles': <String>['alice', 'bob', 'charlie'],
          'readdedRole': 'charlie',
          'reactorRole': 'charlie',
          'targetMessageId': 'ml007-a-after',
          'reactionEmoji': '✅',
          'reactionOutcome': 'success',
          'reactionAccepted': true,
          'observedByRole': 'bob',
          'receivedViaGroupReactionStream': true,
          'appliedOnceToTarget': true,
          'persistedReactionCount': 1,
          'readdedBeforeReaction': true,
          'targetVisibleBeforeReaction': true,
          'postReaddReactionAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'aliceObservedSignal': true,
          'bobObservedSignal': true,
          'finalEpoch': 2,
        },
        'ra002OnlineSubscribedReaddProof': <String, Object?>{
          'rowId': 'RA-002',
          'observedCharlieRemovedWhileOnline': true,
          'receivedRemovedWindowWhileCharlieOnline': true,
          'observedCharlieReaddedWithoutRestart': true,
          'receivedAlicePostReaddWithoutCharlieRestart': true,
          'sentBobPostReaddWithoutCharlieRestart': true,
          'receivedCharliePostReaddWithoutRestart': true,
          'finalEpoch': 2,
        },
        'ke008ReaddActivationProof': <String, Object?>{
          'rowId': 'KE-008',
          'observedCharlieReadded': true,
          'receivedCharliePostReaddAtCurrentEpoch': true,
          'sentBobPostReaddAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ke010KeyBeforeConfigProof': <String, Object?>{
          'rowId': 'KE-010',
          'keyBeforeConfigOrderingCoveredByFakeNetwork': true,
          'liveAuthorizedDeliveryCovered': true,
          'observedCharlieAuthorized': true,
          'receivedCharliePostConfigAtCurrentEpoch': true,
          'sentBobPostConfigAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ke011DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'KE-011',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'observedCharlieReadded': true,
          'receivedCharliePostStaleAtCurrentEpoch': true,
          'sentBobPostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra006DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'RA-006',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'observedCharlieReadded': true,
          'receivedCharliePostStaleAtCurrentEpoch': true,
          'sentBobPostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra007PartitionedObserverReaddProof': <String, Object?>{
          'rowId': 'RA-007',
          'partitionedObserverOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'activeObserverPartitionCoveredByFakeNetwork': true,
          'retainedEntitledRemovedWindowCoveredByFakeNetwork': true,
          'observedCharlieReadded': true,
          'receivedAlicePostHealAtCurrentEpoch': true,
          'receivedCharliePostHealAtCurrentEpoch': true,
          'sentBobPostHealAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ra008PartitionedRemovedReaddProof': <String, Object?>{
          'rowId': 'RA-008',
          'removedPeerPartitionOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'observedCharlieRemoved': true,
          'receivedRemovedWindowWhileCharliePartitionedCoveredByFakeNetwork':
              true,
          'observedCharlieReadded': true,
          'receivedAlicePostHealAtCurrentEpoch': true,
          'receivedCharliePostHealAtCurrentEpoch': true,
          'sentBobPostHealAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ra009FirstReaddPublishProof': <String, Object?>{
          'rowId': 'RA-009',
          'firstReaddPublishOrderingCoveredByFakeNetwork': true,
          'liveFirstReaddPublishCovered': true,
          'observedCharlieReadded': true,
          'receivedCharlieFirstPostReaddAtCurrentEpoch': true,
          'firstCharliePostReaddMessageKey': 'charlieAfterImmediateReadd',
          'finalEpoch': 2,
        },
        'ra010ReaddIncomingRestartProof': <String, Object?>{
          'rowId': 'RA-010',
          'liveIncomingBeforeAndAfterRestartCovered': true,
          'observedCharlieReadded': true,
          'receivedAlicePostRestartAtCurrentEpoch': true,
          'postRestartIncomingMessageKey': 'aliceAfterCharlieRestart',
          'finalEpoch': 2,
        },
        'ra014OldKeyPublishAfterReaddProof': <String, Object?>{
          'rowId': 'RA-014',
          'staleOldPublishRejectionCoveredByFakeNetwork': true,
          'nativeOldKeyPublishRejectionCovered': true,
          'livePostRejectDeliveryCovered': true,
          'rejectedCharlieOldKeyPublish': true,
          'receivedAliceCurrentAfterReject': true,
          'receivedCharlieCurrentAfterReject': true,
          'sentBobCurrentAfterReject': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra015AlreadyJoinedReaddRefreshProof': <String, Object?>{
          'rowId': 'RA-015',
          'flutterAlreadyJoinedPayloadCoveredByHost': true,
          'nativeAlreadyJoinedRefreshCovered': true,
          'fakeNetworkAlreadyJoinedReaddCovered': true,
          'livePostRefreshDeliveryCovered': true,
          'observedCharlieReadded': true,
          'receivedAliceCurrentAfterRefresh': true,
          'receivedCharlieCurrentAfterRefresh': true,
          'sentBobCurrentAfterRefresh': true,
          'finalEpoch': 2,
        },
        'ra016RemovedIntervalReplayProof': <String, Object?>{
          'rowId': 'RA-016',
          'hostDirectRemovedIntervalReplayCovered': true,
          'hostFakeNetworkRemovedIntervalReplayCovered': true,
          'removedIntervalReplayRejectedByRecipientInterval': true,
          'livePostReaddCurrentDeliveryCovered': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'receivedAlicePostReaddCurrent': true,
          'sentBobPostReaddCurrent': true,
          'receivedCharliePostReaddCurrent': true,
          'finalEpoch': 2,
        },
        'ke012DelayedOldConfigAfterReaddProof': <String, Object?>{
          'rowId': 'KE-012',
          'delayedOldConfigOrderingCoveredByFakeNetwork': true,
          'livePostStaleConfigDeliveryCovered': true,
          'keptActiveAfterDelayedOldConfig': true,
          'observedCharlieReadded': true,
          'receivedCharliePostStaleConfigAtCurrentEpoch': true,
          'sentBobPostStaleConfigAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'private-readd-current-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterImmediateReadd',
          'messageId': 'ml007-c-after',
          'text': 'charlie after immediate readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterImmediateReadd',
          'ml007-a-after',
          'alice after immediate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterCharlieRestart',
          'ra010-a-after-restart',
          'alice after charlie restart',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterReaddCurrent',
          'ml007-b-after',
          'bob after readd current',
          'bob-peer',
          keyEpoch: 2,
          quotedMessageId: 'ml007-a-after',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterImmediateReadd': 1,
        'aliceAfterCharlieRestart': 1,
        'bobAfterReaddCurrent': 1,
      },
      extra: const <String, Object?>{
        'ml007ReaddCurrentProof': <String, Object?>{
          'rowId': 'ML-007',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterReadd': false,
          'postReaddPublishAccepted': true,
          'receivedAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'finalEpoch': 2,
        },
        'up001MembershipConfigSyncProof': <String, Object?>{
          'rowId': 'UP-001',
          'role': 'charlie',
          'nativeValidatorCoveredByHost': true,
          'liveThreePartyProof': true,
          'groupConfigStateHashObserved': true,
          'finalDbConfigUiConverged': true,
          'observedSelfRemovalDuringRemoval': true,
          'observedReaddSnapshot': true,
          'finalEpoch': 2,
        },
        'up003ComposeGateProof': <String, Object?>{
          'rowId': 'UP-003',
          'liveThreePartyProof': true,
          'hostUiComposerGateCovered': true,
          'activeBeforeRemovalObserved': true,
          'removedStateSendRejected': true,
          'removedStateOutcome': 'groupNotFound',
          'pendingReaddImportedWithoutCurrentKey': true,
          'pendingReaddMemberListIncludesCharlie': true,
          'pendingReaddSendRejected': true,
          'pendingReaddSendOutcome': 'error',
          'rejoinAcknowledgedAfterCurrentKey': true,
          'activeAfterCurrentKeyCanSend': true,
          'finalEpoch': 2,
        },
        'pl004QuoteReaddLiveProof': <String, Object?>{
          'rowId': 'PL-004',
          'quoteBoundary': 'post_readd_live',
          'quoteSenderRole': 'bob',
          'readdedBeforeQuotedDelivery': true,
          'quoteTargetMessageId': 'ml007-a-after',
          'receivedQuotedMessageId': 'ml007-a-after',
          'receivedQuotedPostReaddLive': true,
          'quoteTargetVisibleBeforeQuotedDelivery': true,
          'removedWindowPlaintextCount': 0,
          'finalEpoch': 2,
        },
        'pl007ReaddMediaProof': <String, Object?>{
          'rowId': 'PL-007',
          'removedPeerId': 'charlie-peer',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowMediaBlobId': 'pl007-removed-window-media',
          'postReaddMediaBlobId': 'pl007-post-readd-media',
          'removedWindowMessageKey': 'aliceDuringCharlieRemoval',
          'postReaddMessageKey': 'aliceAfterImmediateReadd',
          'removedWindowMediaMessageCount': 0,
          'removedWindowMediaRowsBeforeReadd': 0,
          'removedWindowMediaRowsAfterReadd': 0,
          'removedWindowPendingDownloadsBeforeReadd': 0,
          'pendingDownloadsAfterPostReadd': 0,
          'removedWindowDirectDownloadAttempted': true,
          'removedWindowDirectDownloadDenied': true,
          'removedWindowDirectDownloadOk': false,
          'removedWindowDirectDownloadOutputBytes': 0,
          'noRemovedWindowMediaPlaintext': true,
          'postReaddMediaMessageReceived': true,
          'postReaddMediaRows': 1,
          'postReaddMediaDownloaded': true,
          'postReaddMediaPersisted': true,
          'postReaddMediaDecrypted': true,
          'postReaddMediaEpoch': 2,
          'finalEpoch': 2,
        },
        'pl011ReaddReactionProof': <String, Object?>{
          'rowId': 'PL-011',
          'activeRoles': <String>['alice', 'bob', 'charlie'],
          'readdedRole': 'charlie',
          'reactorRole': 'charlie',
          'targetMessageId': 'ml007-a-after',
          'reactionEmoji': '✅',
          'reactionOutcome': 'success',
          'reactionAccepted': true,
          'observedByRole': 'charlie',
          'receivedViaGroupReactionStream': false,
          'appliedOnceToTarget': true,
          'persistedReactionCount': 1,
          'readdedBeforeReaction': true,
          'targetVisibleBeforeReaction': true,
          'postReaddReactionAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'aliceObservedSignal': true,
          'bobObservedSignal': true,
          'finalEpoch': 2,
        },
        'ra002OnlineSubscribedReaddProof': <String, Object?>{
          'rowId': 'RA-002',
          'onlineBeforeRemoval': true,
          'remainedProcessAliveDuringRemoval': true,
          'staleSubscriptionWindowCovered': true,
          'removedWindowPlaintextCount': 0,
          'rejoinedWithoutRestart': true,
          'receivedAlicePostReaddWithoutRestart': true,
          'receivedBobPostReaddWithoutRestart': true,
          'postReaddPublishAccepted': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ke008ReaddActivationProof': <String, Object?>{
          'rowId': 'KE-008',
          'importedCurrentEpochBeforeRejoinAck': true,
          'epochBeforeRejoinAck': 2,
          'rejoinAcknowledgedAfterCurrentKey': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'hasCurrentEpochBeforePostReaddPublish': true,
          'postReaddPublishAccepted': true,
          'postReaddPublishEpoch': 2,
          'receivedAlicePostReaddAtCurrentEpoch': true,
          'receivedBobPostReaddAtCurrentEpoch': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterReadd': false,
          'finalEpoch': 2,
        },
        'ke010KeyBeforeConfigProof': <String, Object?>{
          'rowId': 'KE-010',
          'keyBeforeConfigOrderingCoveredByFakeNetwork': true,
          'liveAuthorizedDeliveryCovered': true,
          'noPreConfigPlaintextDespiteKey': true,
          'receivedAlicePostConfigAtCurrentEpoch': true,
          'receivedBobPostConfigAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ke011DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'KE-011',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'keptCurrentEpochAfterDelayedOldKey': true,
          'storedDelayedOldKeyAsHistorical': true,
          'postStalePublishAccepted': true,
          'receivedAlicePostStaleAtCurrentEpoch': true,
          'receivedBobPostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'epochBeforeDelayedOldKey': 2,
          'epochAfterDelayedOldKey': 2,
          'finalEpoch': 2,
        },
        'ra006DelayedOldKeyAfterReaddProof': <String, Object?>{
          'rowId': 'RA-006',
          'delayedOldKeyOrderingCoveredByFakeNetwork': true,
          'livePostStaleDeliveryCovered': true,
          'keptCurrentEpochAfterDelayedOldKey': true,
          'storedDelayedOldKeyAsHistorical': true,
          'postStalePublishAccepted': true,
          'receivedAlicePostStaleAtCurrentEpoch': true,
          'receivedBobPostStaleAtCurrentEpoch': true,
          'staleEpoch': 1,
          'epochBeforeDelayedOldKey': 2,
          'epochAfterDelayedOldKey': 2,
          'finalEpoch': 2,
        },
        'ra007PartitionedObserverReaddProof': <String, Object?>{
          'rowId': 'RA-007',
          'partitionedObserverOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'bobPartitionDoesNotLeakRemovedWindowCoveredByFakeNetwork': true,
          'removedWindowPlaintextCount': 0,
          'postHealPublishAccepted': true,
          'receivedAlicePostHealAtCurrentEpoch': true,
          'receivedBobPostHealAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ra008PartitionedRemovedReaddProof': <String, Object?>{
          'rowId': 'RA-008',
          'removedPeerPartitionOrderingCoveredByFakeNetwork': true,
          'livePostHealDeliveryCovered': true,
          'missedRemovalBeforeReaddCoveredByFakeNetwork': true,
          'removedWindowPlaintextCount': 0,
          'postHealPublishAccepted': true,
          'receivedAlicePostHealAtCurrentEpoch': true,
          'receivedBobPostHealAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ra009FirstReaddPublishProof': <String, Object?>{
          'rowId': 'RA-009',
          'firstReaddPublishOrderingCoveredByFakeNetwork': true,
          'liveFirstReaddPublishCovered': true,
          'sentFirstPostReaddAtCurrentEpoch': true,
          'firstPostReaddPublishAccepted': true,
          'firstPostReaddMessageKey': 'charlieAfterImmediateReadd',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ra010ReaddIncomingRestartProof': <String, Object?>{
          'rowId': 'RA-010',
          'liveIncomingBeforeAndAfterRestartCovered': true,
          'receivedFirstIncomingBeforeRestartAtCurrentEpoch': true,
          'restartPreservedCurrentGroupKeyConfig': true,
          'receivedSecondIncomingAfterRestartAtCurrentEpoch': true,
          'firstIncomingMessageKey': 'aliceAfterImmediateReadd',
          'postRestartIncomingMessageKey': 'aliceAfterCharlieRestart',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ra014OldKeyPublishAfterReaddProof': <String, Object?>{
          'rowId': 'RA-014',
          'staleOldPublishRejectionCoveredByFakeNetwork': true,
          'nativeOldKeyPublishRejectionCovered': true,
          'livePostRejectDeliveryCovered': true,
          'oldKeyPublishRejected': true,
          'postRejectPublishAccepted': true,
          'receivedAlicePostRejectAtCurrentEpoch': true,
          'receivedBobPostRejectAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'staleEpoch': 1,
          'finalEpoch': 2,
        },
        'ra015AlreadyJoinedReaddRefreshProof': <String, Object?>{
          'rowId': 'RA-015',
          'flutterAlreadyJoinedPayloadCoveredByHost': true,
          'nativeAlreadyJoinedRefreshCovered': true,
          'fakeNetworkAlreadyJoinedReaddCovered': true,
          'livePostRefreshDeliveryCovered': true,
          'alreadyJoinedReaddRefreshAccepted': true,
          'importedCurrentConfigBeforeRejoinAck': true,
          'postRefreshPublishAccepted': true,
          'receivedAlicePostRefreshAtCurrentEpoch': true,
          'receivedBobPostRefreshAtCurrentEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ra016RemovedIntervalReplayProof': <String, Object?>{
          'rowId': 'RA-016',
          'hostDirectRemovedIntervalReplayCovered': true,
          'hostFakeNetworkRemovedIntervalReplayCovered': true,
          'removedIntervalReplayRejectedByRecipientInterval': true,
          'livePostReaddCurrentDeliveryCovered': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'postReaddPublishAccepted': true,
          'receivedAlicePostReaddCurrent': true,
          'receivedBobPostReaddCurrent': true,
          'finalEpoch': 2,
        },
        'ke012DelayedOldConfigAfterReaddProof': <String, Object?>{
          'rowId': 'KE-012',
          'delayedOldConfigOrderingCoveredByFakeNetwork': true,
          'livePostStaleConfigDeliveryCovered': true,
          'keptFinalMembersAfterDelayedOldConfig': true,
          'keptCurrentEpochAfterDelayedOldConfig': true,
          'postStaleConfigPublishAccepted': true,
          'receivedAlicePostStaleConfigAtCurrentEpoch': true,
          'receivedBobPostStaleConfigAtCurrentEpoch': true,
          'epochBeforeDelayedOldConfig': 2,
          'epochAfterDelayedOldConfig': 2,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

Map<String, dynamic> _withPl011ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'pl011ReaddReactionProof': <String, Object?>{
      ...Map<String, Object?>.from(verdict['pl011ReaddReactionProof'] as Map),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateReaddActiveMembersVerdicts() {
  const scenario = 'private_readd_active_members';
  const groupId = 'private-readd-active-members-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
    'dana': 'dana-peer',
  };
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  final sentByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };

  void addMessage({
    required int cycle,
    required String phase,
    required String senderRole,
    required List<String> receiverRoles,
    required int keyEpoch,
  }) {
    final key = _ra017KeyForTest(cycle, phase, senderRole);
    final messageId = 'ra017-c$cycle-$phase-$senderRole';
    final text =
        'RA-017 cycle $cycle $phase from ${_titleRoleForTest(senderRole)}';
    sentByRole[senderRole]!.add(<String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': peerIdsByRole[senderRole],
      'keyEpoch': keyEpoch,
    });
    for (final receiverRole in receiverRoles) {
      receivedByRole[receiverRole]!.add(
        _received(
          key,
          messageId,
          text,
          peerIdsByRole[senderRole]!,
          keyEpoch: keyEpoch,
        ),
      );
    }
  }

  for (var cycle = 1; cycle <= 3; cycle++) {
    addMessage(
      cycle: cycle,
      phase: 'removed',
      senderRole: 'alice',
      receiverRoles: const <String>['bob', 'dana'],
      keyEpoch: cycle * 2,
    );
    addMessage(
      cycle: cycle,
      phase: 'removed',
      senderRole: 'bob',
      receiverRoles: const <String>['alice', 'dana'],
      keyEpoch: cycle * 2,
    );
    addMessage(
      cycle: cycle,
      phase: 'removed',
      senderRole: 'dana',
      receiverRoles: const <String>['alice', 'bob'],
      keyEpoch: cycle * 2,
    );
    addMessage(
      cycle: cycle,
      phase: 'readd',
      senderRole: 'alice',
      receiverRoles: const <String>['bob', 'charlie', 'dana'],
      keyEpoch: cycle * 2 + 1,
    );
    addMessage(
      cycle: cycle,
      phase: 'readd',
      senderRole: 'bob',
      receiverRoles: const <String>['alice', 'charlie', 'dana'],
      keyEpoch: cycle * 2 + 1,
    );
    addMessage(
      cycle: cycle,
      phase: 'readd',
      senderRole: 'dana',
      receiverRoles: const <String>['alice', 'bob', 'charlie'],
      keyEpoch: cycle * 2 + 1,
    );
  }

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'RA-017',
    'churnCycles': 3,
    'activeSenders': const <String>['alice', 'bob', 'dana'],
    'activeReceivers': const <String>['alice', 'bob', 'dana'],
    'danaActiveMemberCovered': true,
    'charlieRemovedWindowPlaintextCount': 0,
    'finalRoles': const <String>['alice', 'bob', 'charlie', 'dana'],
    'finalMemberListConverged': true,
    'finalEpoch': 7,
    'finalEpochConverged': true,
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie', 'dana'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 7,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'ra017ActiveMemberChurnProof': proofForRole(role),
        },
      ),
  ];
}

List<Map<String, dynamic>> _validPrivateReaddCyclesVerdicts() {
  const scenario = 'private_readd_cycles';
  const groupId = 'private-readd-cycles-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 21,
      extra: const <String, Object?>{
        'ml008CycleProof': <String, Object?>{
          'rowId': 'ML-008',
          'cycleCount': 20,
          'removedWindowSendCount': 20,
          'sentPostReaddCount': 20,
          'receivedCharliePostReaddCount': 20,
          'restartMarkersObserved': 4,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 21,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 21,
      extra: const <String, Object?>{
        'ml008CycleProof': <String, Object?>{
          'rowId': 'ML-008',
          'cycleCount': 20,
          'receivedRemovedWindowCount': 20,
          'receivedAlicePostReaddCount': 20,
          'receivedCharliePostReaddCount': 20,
          'bobCharlieExactMemberRowCountProofs': 20,
          'restartMarkersPerformed': 2,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 21,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 21,
      extra: const <String, Object?>{
        'ml008CycleProof': <String, Object?>{
          'rowId': 'ML-008',
          'cycleCount': 20,
          'selfRemovalCount': 20,
          'receivedAlicePostReaddCount': 20,
          'postReaddSendCount': 20,
          'removedWindowPlaintextCount': 0,
          'restartMarkersPerformed': 2,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 21,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateRapidReaddVerdicts() {
  const scenario = 'private_rapid_readd';
  const groupId = 'private-rapid-readd-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringRapidRemove',
          'messageId': 'ml009-a-during',
          'text': 'alice during rapid remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'alicePostRapidReadd',
          'messageId': 'ml009-a-after',
          'text': 'alice after rapid readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobPostRapidReadd',
          'ml009-b-after',
          'bob after rapid readd',
          'bob-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobPostRapidReadd': 1},
      extra: const <String, Object?>{
        'ml009RapidReaddProof': <String, Object?>{
          'rowId': 'ML-009',
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'readdIssuedBeforeRemovalAcks': true,
          'sentRemovedWindowBeforeReadd': true,
          'sentAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 3,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobPostRapidReadd',
          'messageId': 'ml009-b-after',
          'text': 'bob after rapid readd',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringRapidRemove',
          'ml009-a-during',
          'alice during rapid remove',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'alicePostRapidReadd',
          'ml009-a-after',
          'alice after rapid readd',
          'alice-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringRapidRemove': 1,
        'alicePostRapidReadd': 1,
      },
      extra: const <String, Object?>{
        'ml009RapidReaddProof': <String, Object?>{
          'rowId': 'ML-009',
          'memberListIncludesCharlie': true,
          'receivedRemovedWindowMessage': true,
          'receivedAlicePostReaddMessage': true,
          'sentBobPostReaddMessage': true,
          'staleRemoveIgnored': true,
          'finalEpoch': 3,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'alicePostRapidReadd',
          'ml009-a-after',
          'alice after rapid readd',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'bobPostRapidReadd',
          'ml009-b-after',
          'bob after rapid readd',
          'bob-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'alicePostRapidReadd': 1,
        'bobPostRapidReadd': 1,
      },
      extra: const <String, Object?>{
        'ml009RapidReaddProof': <String, Object?>{
          'rowId': 'ML-009',
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'receivedAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'removedWindowPlaintextCount': 0,
          'staleRemoveIgnored': true,
          'hasStaleEpochAfterReadd': false,
          'finalEpoch': 3,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateConcurrentAdminMembershipVerdicts() {
  const scenario = 'private_concurrent_admin_membership_edits';
  const groupId = 'private-concurrent-admin-membership-group';
  const activeMembers = <String>['alice-peer', 'bob-peer', 'dana-peer'];
  const deliveryOrders = <String>['add_then_remove', 'remove_then_add'];
  const finalHash = 'ml012-final-config-hash';

  Map<String, Object?> activeProof(String role) => <String, Object?>{
    'rowId': 'ML-012',
    'appPeerPlatform': 'ios_26_2_core_simulator',
    'concurrentAdminProofSource': 'app_peer_core_simulator',
    'deliveryOrdersTested': deliveryOrders,
    'finalMemberPeerIds': activeMembers,
    'finalConfigStateHash': finalHash,
    'memberSetsConverged': true,
    'configHashesConverged': true,
    'independentAddPreserved': true,
    'removedCharlieExcluded': true,
    'sameTargetNewerReaddWins': true,
    'sameTargetTieRemoveWins': true,
    'role': role,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      extra: <String, Object?>{
        'activeMemberPeerIds': activeMembers,
        'ml012ConcurrentAdminEditsProof': activeProof('alice'),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      extra: <String, Object?>{
        'activeMemberPeerIds': activeMembers,
        'ml012ConcurrentAdminEditsProof': activeProof('bob'),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: const <String>[],
      keyEpoch: 1,
      extra: const <String, Object?>{
        'activeMemberPeerIds': <String>[],
        'ml012ConcurrentAdminEditsProof': <String, Object?>{
          'rowId': 'ML-012',
          'appPeerPlatform': 'ios_26_2_core_simulator',
          'concurrentAdminProofSource': 'app_peer_core_simulator',
          'deliveryOrdersTested': deliveryOrders,
          'charlieRemoved': true,
          'postRemovalGroupAbsent': true,
          'removedCharlieExcluded': true,
          'sameTargetTieRemoveWins': true,
          'removedWindowPlaintextCount': 0,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'dana',
      peerId: 'dana-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      extra: <String, Object?>{
        'activeMemberPeerIds': activeMembers,
        'ml012ConcurrentAdminEditsProof': activeProof('dana'),
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateTimelineTruthVerdicts() {
  const scenario = 'private_timeline_truth';
  const groupId = 'private-timeline-truth-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceBeforeTimelineRemoval',
          'messageId': 'ml015-a-before',
          'text': 'alice before removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
        },
        {
          'key': 'aliceDuringTimelineRemoval',
          'messageId': 'ml015-a-window',
          'text': 'alice removed window',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'alicePostTimelineReadd',
          'messageId': 'ml015-a-after',
          'text': 'alice after readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobPostTimelineReadd',
          'ml015-b-after',
          'bob after readd',
          'bob-peer',
          keyEpoch: 3,
        ),
        _received(
          'charliePostTimelineReadd',
          'ml015-c-after',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobPostTimelineReadd': 1,
        'charliePostTimelineReadd': 1,
      },
      extra: const <String, Object?>{
        'ml015TimelineTruthProof': <String, Object?>{
          'rowId': 'ML-015',
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'sentBeforeRemovalMessage': true,
          'sentRemovedWindowBeforeReadd': true,
          'sentAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'timelineOrderMatchesMembershipIntervals': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 3,
        },
        'up002DurableTimelineProof': <String, Object?>{
          'rowId': 'UP-002',
          'role': 'alice',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'addTimelineEventCount': 2,
          'removeTimelineEventCount': 1,
          'timelineContainsInitialAdd': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsAddRemoveReadd': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalStateMatchesTimeline': true,
          'finalEpoch': 3,
        },
        'up004UnreadChurnProof': <String, Object?>{
          'rowId': 'UP-004',
          'role': 'alice',
          'liveThreePartyProof': true,
          'preRemovalUnreadCount': 0,
          'removedWindowUnreadCount': 0,
          'postReaddUnreadCount': 2,
          'postReaddUnreadIncluded': true,
          'readClearOnOpen': true,
          'finalUnreadCountAfterOpen': 0,
        },
        'up006ReaddUiStateProof': <String, Object?>{
          'rowId': 'UP-006',
          'role': 'alice',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsRemoveBeforeReadd': true,
          'readdLabelIsActive': true,
          'latestCharlieTimelineText': 'Alice added Charlie',
          'latestCharlieTimelineIsReadd': true,
          'staleRemovedStateReused': false,
          'stalePendingInviteStateReused': false,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up009ReaddSenderIdentityProof': <String, Object?>{
          'rowId': 'UP-009',
          'role': 'alice',
          'liveThreePartyProof': true,
          'readdMemberPresent': true,
          'charliePostReaddMessageVisible': true,
          'charliePostReaddMessageIncoming': true,
          'charlieOwnMessageStoredAsSent': false,
          'senderPeerIdMatchesCharlie': true,
          'messageId': 'ml015-c-after',
          'storedSenderUsername': 'Charlie',
          'currentMemberUsername': 'Charlie',
          'renderedSenderDisplayName': 'Charlie',
          'renderedLabelNonBlank': true,
          'renderedLabelMatchesCurrentMember': true,
          'renderedLabelNotPeerFallback': true,
          'renderedLabelNotUnknown': true,
          'contactIndependentResolution': true,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up010NotificationRouteProof': <String, Object?>{
          'rowId': 'UP-010',
          'role': 'alice',
          'liveThreePartyProof': true,
          'notificationRouteProofSource': 'app_peer_core_simulator',
          'currentLocalMemberPresent': true,
          'currentGroupRouteOpened': true,
          'currentRouteGroupIdMatches': true,
          'currentRoutePendingInviteAbsent': true,
          'currentResolutionRecoveryDrainCalls': 0,
          'staleRemovedRecoveryDrainAttempted': true,
          'staleRemovedGroupRejected': true,
          'staleRemovedResolutionMissing': true,
          'staleRemovedGroupOpened': false,
          'restoredLocalMemberAfterProbe': true,
          'postReaddMessageVisible': true,
          'messageVisibilityMatchesMembership': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobPostTimelineReadd',
          'messageId': 'ml015-b-after',
          'text': 'bob after readd',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeTimelineRemoval',
          'ml015-a-before',
          'alice before removal',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceDuringTimelineRemoval',
          'ml015-a-window',
          'alice removed window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'alicePostTimelineReadd',
          'ml015-a-after',
          'alice after readd',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'charliePostTimelineReadd',
          'ml015-c-after',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeTimelineRemoval': 1,
        'aliceDuringTimelineRemoval': 1,
        'alicePostTimelineReadd': 1,
        'charliePostTimelineReadd': 1,
      },
      extra: const <String, Object?>{
        'ml015TimelineTruthProof': <String, Object?>{
          'rowId': 'ML-015',
          'receivedBeforeRemovalMessage': true,
          'receivedRemovedWindowMessage': true,
          'receivedAlicePostReaddMessage': true,
          'sentBobPostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'timelineOrderMatchesMembershipIntervals': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 3,
        },
        'up002DurableTimelineProof': <String, Object?>{
          'rowId': 'UP-002',
          'role': 'bob',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'addTimelineEventCount': 2,
          'removeTimelineEventCount': 1,
          'timelineContainsInitialAdd': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsAddRemoveReadd': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalStateMatchesTimeline': true,
          'finalEpoch': 3,
        },
        'up004UnreadChurnProof': <String, Object?>{
          'rowId': 'UP-004',
          'role': 'bob',
          'liveThreePartyProof': true,
          'preRemovalUnreadCovered': true,
          'preRemovalUnreadCount': 1,
          'removedWindowActiveRecipientUnreadCovered': true,
          'removedWindowUnreadCount': 1,
          'postReaddUnreadCount': 2,
          'postReaddUnreadIncluded': true,
          'readClearOnOpen': true,
          'finalUnreadCountAfterOpen': 0,
        },
        'up006ReaddUiStateProof': <String, Object?>{
          'rowId': 'UP-006',
          'role': 'bob',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsRemoveBeforeReadd': true,
          'readdLabelIsActive': true,
          'latestCharlieTimelineText': 'Alice added Charlie',
          'latestCharlieTimelineIsReadd': true,
          'staleRemovedStateReused': false,
          'stalePendingInviteStateReused': false,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up009ReaddSenderIdentityProof': <String, Object?>{
          'rowId': 'UP-009',
          'role': 'bob',
          'liveThreePartyProof': true,
          'readdMemberPresent': true,
          'charliePostReaddMessageVisible': true,
          'charliePostReaddMessageIncoming': true,
          'charlieOwnMessageStoredAsSent': false,
          'senderPeerIdMatchesCharlie': true,
          'messageId': 'ml015-c-after',
          'storedSenderUsername': 'Charlie',
          'currentMemberUsername': 'Charlie',
          'renderedSenderDisplayName': 'Charlie',
          'renderedLabelNonBlank': true,
          'renderedLabelMatchesCurrentMember': true,
          'renderedLabelNotPeerFallback': true,
          'renderedLabelNotUnknown': true,
          'contactIndependentResolution': true,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up010NotificationRouteProof': <String, Object?>{
          'rowId': 'UP-010',
          'role': 'bob',
          'liveThreePartyProof': true,
          'notificationRouteProofSource': 'app_peer_core_simulator',
          'currentLocalMemberPresent': true,
          'currentGroupRouteOpened': true,
          'currentRouteGroupIdMatches': true,
          'currentRoutePendingInviteAbsent': true,
          'currentResolutionRecoveryDrainCalls': 0,
          'staleRemovedRecoveryDrainAttempted': true,
          'staleRemovedGroupRejected': true,
          'staleRemovedResolutionMissing': true,
          'staleRemovedGroupOpened': false,
          'restoredLocalMemberAfterProbe': true,
          'postReaddMessageVisible': true,
          'messageVisibilityMatchesMembership': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charliePostTimelineReadd',
          'messageId': 'ml015-c-after',
          'text': 'charlie after readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 3,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeTimelineRemoval',
          'ml015-a-before',
          'alice before removal',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'alicePostTimelineReadd',
          'ml015-a-after',
          'alice after readd',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'bobPostTimelineReadd',
          'ml015-b-after',
          'bob after readd',
          'bob-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeTimelineRemoval': 1,
        'alicePostTimelineReadd': 1,
        'bobPostTimelineReadd': 1,
      },
      extra: const <String, Object?>{
        'ml015TimelineTruthProof': <String, Object?>{
          'rowId': 'ML-015',
          'receivedBeforeRemovalMessage': true,
          'receivedAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'sentCharliePostReaddMessage': true,
          'selfRemovalCleanupObserved': true,
          'memberListIncludesAliceBob': true,
          'timelineOrderMatchesMembershipIntervals': true,
          'timelineContainsReadd': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterReadd': false,
          'finalEpoch': 3,
        },
        'up002DurableTimelineProof': <String, Object?>{
          'rowId': 'UP-002',
          'role': 'charlie',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'addTimelineEventCount': 2,
          'removeTimelineEventCount': 1,
          'timelineContainsInitialAdd': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsAddRemoveReadd': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalStateMatchesTimeline': true,
          'finalEpoch': 3,
        },
        'up004UnreadChurnProof': <String, Object?>{
          'rowId': 'UP-004',
          'role': 'charlie',
          'liveThreePartyProof': true,
          'preRemovalUnreadCovered': true,
          'preRemovalUnreadCount': 1,
          'removedWindowUnreadExcluded': true,
          'removedWindowUnreadCount': 0,
          'removedWindowPlaintextCount': 0,
          'postReaddUnreadCount': 2,
          'postReaddUnreadIncluded': true,
          'readClearOnOpen': true,
          'finalUnreadCountAfterOpen': 0,
        },
        'up006ReaddUiStateProof': <String, Object?>{
          'rowId': 'UP-006',
          'role': 'charlie',
          'liveThreePartyProof': true,
          'reopenedTimelineRead': true,
          'timelineContainsRemoval': true,
          'timelineContainsReadd': true,
          'timelineOrderShowsRemoveBeforeReadd': true,
          'readdLabelIsActive': true,
          'latestCharlieTimelineText': 'Alice added Charlie',
          'latestCharlieTimelineIsReadd': true,
          'staleRemovedStateReused': false,
          'stalePendingInviteStateReused': false,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up009ReaddSenderIdentityProof': <String, Object?>{
          'rowId': 'UP-009',
          'role': 'charlie',
          'liveThreePartyProof': true,
          'readdMemberPresent': true,
          'charliePostReaddMessageVisible': true,
          'charliePostReaddMessageIncoming': false,
          'charlieOwnMessageStoredAsSent': true,
          'senderPeerIdMatchesCharlie': true,
          'messageId': 'ml015-c-after',
          'storedSenderUsername': 'Charlie',
          'currentMemberUsername': 'Charlie',
          'renderedSenderDisplayName': 'Charlie',
          'renderedLabelNonBlank': true,
          'renderedLabelMatchesCurrentMember': true,
          'renderedLabelNotPeerFallback': true,
          'renderedLabelNotUnknown': true,
          'contactIndependentResolution': true,
          'memberListIncludesCharlie': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
        'up010NotificationRouteProof': <String, Object?>{
          'rowId': 'UP-010',
          'role': 'charlie',
          'liveThreePartyProof': true,
          'notificationRouteProofSource': 'app_peer_core_simulator',
          'currentLocalMemberPresent': true,
          'currentGroupRouteOpened': true,
          'currentRouteGroupIdMatches': true,
          'currentRoutePendingInviteAbsent': true,
          'currentResolutionRecoveryDrainCalls': 0,
          'staleRemovedRecoveryDrainAttempted': true,
          'staleRemovedGroupRejected': true,
          'staleRemovedResolutionMissing': true,
          'staleRemovedGroupOpened': false,
          'restoredLocalMemberAfterProbe': true,
          'postReaddMessageVisible': true,
          'messageVisibilityMatchesMembership': true,
          'finalMemberListIncludesAliceBobCharlie': true,
          'finalEpoch': 3,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateHistoryRetentionVerdicts() {
  const scenario = 'private_history_retention';
  const groupId = 'private-history-retention-group';
  const activeMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceBeforeHistoryRemoval',
          'messageId': 'ml017-a-before',
          'text': 'alice before removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
        },
        {
          'key': 'alicePostHistoryRemoval',
          'messageId': 'ml017-a-after',
          'text': 'alice after removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobPostHistoryRemoval',
          'ml017-b-after',
          'bob after removal',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobPostHistoryRemoval': 1},
      extra: const <String, Object?>{
        'ml017HistoryRetentionProof': <String, Object?>{
          'rowId': 'ML-017',
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'sentPreRemovalHistory': true,
          'sentPostRemovalMessage': true,
          'receivedBobPostRemovalMessage': true,
          'memberListExcludesCharlie': true,
          'rotatedEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobPostHistoryRemoval',
          'messageId': 'ml017-b-after',
          'text': 'bob after removal',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeHistoryRemoval',
          'ml017-a-before',
          'alice before removal',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'alicePostHistoryRemoval',
          'ml017-a-after',
          'alice after removal',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeHistoryRemoval': 1,
        'alicePostHistoryRemoval': 1,
      },
      extra: const <String, Object?>{
        'ml017HistoryRetentionProof': <String, Object?>{
          'rowId': 'ML-017',
          'receivedPreRemovalHistory': true,
          'receivedAlicePostRemovalMessage': true,
          'sentBobPostRemovalMessage': true,
          'memberListExcludesCharlie': true,
          'hasRotatedEpoch': true,
          'rotatedEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 0,
      sentMessages: const <Map<String, Object?>>[],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeHistoryRemoval',
          'ml017-a-before',
          'alice before removal',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeHistoryRemoval': 1,
      },
      extra: const <String, Object?>{
        'ml017HistoryRetentionProof': <String, Object?>{
          'rowId': 'ML-017',
          'retainedLocalGroup': true,
          'retainedPreRemovalHistory': true,
          'composeDisabled': true,
          'postRemovalSendRejected': true,
          'selfMemberRemoved': true,
          'noCurrentKey': true,
          'selfRemovalCleanupObserved': true,
          'receivedAlicePostRemovalMessage': false,
          'receivedBobPostRemovalMessage': false,
          'postRemovalPublishAccepted': false,
          'postRemovalPlaintextCount': 0,
          'postRemovalSendOutcome': 'unauthorized',
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateInviteTerminalStatesVerdicts() {
  const scenario = 'private_invite_terminal_states';
  const groupId = 'private-invite-terminal-states-group';
  const activeMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterInviteTerminalStates',
          'messageId': 'ml018-a-after',
          'text': 'alice after invite terminal states',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterInviteTerminalStates',
          'ml018-b-after',
          'bob after invite terminal states',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterInviteTerminalStates': 1,
      },
      extra: const <String, Object?>{
        'ml018InviteTerminalProof': <String, Object?>{
          'rowId': 'ML-018',
          'sentDeclineInvite': true,
          'sentExpiryInvite': true,
          'sentCancellationInvite': true,
          'sentCancellationRevocation': true,
          'sentPostTerminalMessage': true,
          'receivedBobPostTerminalMessage': true,
          'memberListExcludesCharlie': true,
          'terminalInviteePeerId': 'charlie-peer',
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterInviteTerminalStates',
          'messageId': 'ml018-b-after',
          'text': 'bob after invite terminal states',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterInviteTerminalStates',
          'ml018-a-after',
          'alice after invite terminal states',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterInviteTerminalStates': 1,
      },
      extra: const <String, Object?>{
        'ml018InviteTerminalProof': <String, Object?>{
          'rowId': 'ML-018',
          'receivedAlicePostTerminalMessage': true,
          'sentBobPostTerminalMessage': true,
          'memberListExcludesCharlie': true,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: activeMembers,
      keyEpoch: 0,
      extra: const <String, Object?>{
        'ml018InviteTerminalProof': <String, Object?>{
          'rowId': 'ML-018',
          'receivedDeclineInvite': true,
          'declinedInvite': true,
          'declinePendingCleared': true,
          'declineTombstoneRecorded': true,
          'declinedDelayedCopyRejected': true,
          'receivedExpiryInvite': true,
          'expiredInviteRejected': true,
          'receivedCancellationInvite': true,
          'cancelledInviteRejected': true,
          'noLocalGroup': true,
          'noUsableKey': true,
          'postTerminalSendRejected': true,
          'receivedAlicePostTerminalMessage': false,
          'receivedBobPostTerminalMessage': false,
          'postTerminalPublishAccepted': false,
          'postTerminalPlaintextCount': 0,
          'postTerminalSendOutcome': 'groupNotFound',
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateStaleInviteReaddVerdicts() {
  const scenario = 'private_stale_invite_readd';
  const groupId = 'private-stale-invite-readd-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringStaleInviteRemoval',
          'messageId': 'ml019-a-during',
          'text': 'alice during stale invite removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterStaleInviteReadd',
          'messageId': 'ml019-a-after',
          'text': 'alice after stale invite readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterStaleInviteReadd',
          'ml019-b-after',
          'bob after stale invite readd',
          'bob-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterStaleInviteReadd',
          'ml019-c-after',
          'charlie after stale invite readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterStaleInviteReadd': 1,
        'charlieAfterStaleInviteReadd': 1,
      },
      extra: const <String, Object?>{
        'ml019StaleInviteProof': <String, Object?>{
          'rowId': 'ML-019',
          'sentOldInvite': true,
          'removedCharlieAfterOldInvite': true,
          'rotatedAfterRemoval': true,
          'sentRemovedWindowMessage': true,
          'sentLatestInvite': true,
          'sentPostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'memberListIncludesCharlie': true,
          'staleInviteePeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
        'ke016StaleReinviteProof': <String, Object?>{
          'rowId': 'KE-016',
          'sentEpochNInvite': true,
          'rotatedToNextEpochBeforeAccept': true,
          'sentCurrentEpochInvite': true,
          'sentPostAcceptAtCurrentEpoch': true,
          'receivedBobPostAcceptAtCurrentEpoch': true,
          'receivedCharliePostAcceptAtCurrentEpoch': true,
          'memberListIncludesCharlie': true,
          'staleInviteePeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
        'ra004StaleInviteBeforeReaddProof': <String, Object?>{
          'rowId': 'RA-004',
          'sentOldInvite': true,
          'removedCharlieBeforeOldAccept': true,
          'rotatedAfterRemoval': true,
          'revokedOldInviteBeforeCurrentInvite': true,
          'sentCurrentInviteAfterOldAcceptBlocked': true,
          'sentPostCurrentInviteMessage': true,
          'receivedBobPostCurrentInviteMessage': true,
          'receivedCharliePostCurrentInviteMessage': true,
          'memberListIncludesCharlie': true,
          'staleInviteePeerId': 'charlie-peer',
          'oldInviteId': 'invite-old',
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterStaleInviteReadd',
          'messageId': 'ml019-b-after',
          'text': 'bob after stale invite readd',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringStaleInviteRemoval',
          'ml019-a-during',
          'alice during stale invite removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterStaleInviteReadd',
          'ml019-a-after',
          'alice after stale invite readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterStaleInviteReadd',
          'ml019-c-after',
          'charlie after stale invite readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringStaleInviteRemoval': 1,
        'aliceAfterStaleInviteReadd': 1,
        'charlieAfterStaleInviteReadd': 1,
      },
      extra: const <String, Object?>{
        'ml019StaleInviteProof': <String, Object?>{
          'rowId': 'ML-019',
          'observedOldAdd': true,
          'observedRemovalBeforeReadd': true,
          'receivedRemovedWindowMessage': true,
          'memberListIncludesCharlie': true,
          'hasCurrentEpoch': true,
          'receivedAlicePostReaddMessage': true,
          'sentBobPostReaddMessage': true,
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
        'ke016StaleReinviteProof': <String, Object?>{
          'rowId': 'KE-016',
          'observedEpochNInviteMemberState': true,
          'observedRemovalBeforeCurrentInvite': true,
          'receivedRemovedWindowMessage': true,
          'memberListIncludesCharlie': true,
          'hasCurrentEpoch': true,
          'receivedAlicePostAcceptAtCurrentEpoch': true,
          'sentBobPostAcceptAtCurrentEpoch': true,
          'receivedCharliePostAcceptAtCurrentEpoch': true,
          'finalEpoch': 2,
        },
        'ra004StaleInviteBeforeReaddProof': <String, Object?>{
          'rowId': 'RA-004',
          'observedOldInviteMemberState': true,
          'observedRemovalBeforeCurrentInvite': true,
          'receivedRemovedWindowMessage': true,
          'memberListIncludesCharlie': true,
          'hasCurrentEpoch': true,
          'receivedAlicePostCurrentInviteMessage': true,
          'sentBobPostCurrentInviteMessage': true,
          'receivedCharliePostCurrentInviteMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterStaleInviteReadd',
          'messageId': 'ml019-c-after',
          'text': 'charlie after stale invite readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleInviteReadd',
          'ml019-a-after',
          'alice after stale invite readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterStaleInviteReadd',
          'ml019-b-after',
          'bob after stale invite readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleInviteReadd': 1,
        'bobAfterStaleInviteReadd': 1,
      },
      extra: const <String, Object?>{
        'ml019StaleInviteProof': <String, Object?>{
          'rowId': 'ML-019',
          'receivedOldInvite': true,
          'receivedLatestInvite': true,
          'delayedOldInviteRejected': true,
          'pendingRemainedLatestBeforeAccept': true,
          'acceptedLatestInvite': true,
          'staleAcceptRejected': true,
          'noKeyDowngradeAfterStaleAccept': true,
          'memberListIncludesAliceBobCharlie': true,
          'receivedAlicePostReaddMessage': true,
          'receivedBobPostReaddMessage': true,
          'sentCharliePostReaddMessage': true,
          'oldInviteEpoch': 1,
          'latestInviteEpoch': 2,
          'acceptedEpoch': 2,
          'delayedStoreResult': 'invalidPayload',
          'staleAcceptResult': 'invalidPayload',
          'removedWindowPlaintextCount': 0,
          'finalEpoch': 2,
        },
        'ke016StaleReinviteProof': <String, Object?>{
          'rowId': 'KE-016',
          'receivedEpochNInvite': true,
          'receivedCurrentEpochInvite': true,
          'delayedEpochNInviteRejected': true,
          'pendingRemainedCurrentBeforeAccept': true,
          'acceptedCurrentEpochInvite': true,
          'staleEpochNAcceptRejected': true,
          'noKeyDowngradeAfterStaleAccept': true,
          'memberListIncludesAliceBobCharlie': true,
          'receivedAlicePostAcceptAtCurrentEpoch': true,
          'receivedBobPostAcceptAtCurrentEpoch': true,
          'sentCharliePostAcceptAtCurrentEpoch': true,
          'epochNInviteEpoch': 1,
          'currentInviteEpoch': 2,
          'acceptedEpoch': 2,
          'delayedStoreResult': 'invalidPayload',
          'staleAcceptResult': 'invalidPayload',
          'removedWindowPlaintextCount': 0,
          'finalEpoch': 2,
        },
        'ra004StaleInviteBeforeReaddProof': <String, Object?>{
          'rowId': 'RA-004',
          'receivedOldInvite': true,
          'oldInviteEpoch': 1,
          'oldAcceptAttemptedBeforeCurrentInvite': true,
          'oldInviteWasPendingBeforeBlockedAccept': false,
          'oldAcceptBeforeCurrentRejected': true,
          'oldAcceptResultBeforeCurrent': 'notFound',
          'noGroupAfterOldAccept': true,
          'noKeyAfterOldAccept': true,
          'receivedCurrentInvite': true,
          'acceptedCurrentInvite': true,
          'currentInviteEpoch': 2,
          'acceptedEpoch': 2,
          'staleAcceptRejected': true,
          'staleAcceptResult': 'revoked',
          'noKeyDowngradeAfterStaleAccept': true,
          'removedWindowPlaintextCount': 0,
          'memberListIncludesAliceBobCharlie': true,
          'receivedAlicePostCurrentInviteMessage': true,
          'receivedBobPostCurrentInviteMessage': true,
          'sentCharliePostCurrentInviteMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateStaleLowerKeyUpdateVerdicts() {
  const scenario = 'private_stale_lower_key_update';
  const groupId = 'private-stale-lower-key-update-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterStaleLowerUpdate',
          'messageId': 'ke003-a-after',
          'text': 'alice after stale lower update',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 5,
        },
      ],
      extra: const <String, Object?>{
        'ke003StaleLowerKeyUpdateProof': <String, Object?>{
          'rowId': 'KE-003',
          'heldLowerEpochForBob': true,
          'deliveredEpochFiveBeforeStale': true,
          'deliveredStaleEpochAfterEpochFive': true,
          'sentEpochFiveAfterStale': true,
          'staleEpoch': 4,
          'currentEpoch': 5,
          'finalEpoch': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleLowerUpdate',
          'ke003-a-after',
          'alice after stale lower update',
          'alice-peer',
          keyEpoch: 5,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleLowerUpdate': 1,
      },
      extra: const <String, Object?>{
        'ke003StaleLowerKeyUpdateProof': <String, Object?>{
          'rowId': 'KE-003',
          'acceptedEpochFiveBeforeStale': true,
          'storedStaleEpochAsHistorical': true,
          'keptEpochFiveAfterStale': true,
          'receivedEpochFiveAfterStale': true,
          'staleEpoch': 4,
          'currentEpoch': 5,
          'epochBeforeStale': 5,
          'epochAfterStale': 5,
          'finalEpoch': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleLowerUpdate',
          'ke003-a-after',
          'alice after stale lower update',
          'alice-peer',
          keyEpoch: 5,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleLowerUpdate': 1,
      },
      extra: const <String, Object?>{
        'ke003StaleLowerKeyUpdateProof': <String, Object?>{
          'rowId': 'KE-003',
          'notTargetedByStaleUpdate': true,
          'receivedEpochFiveAfterStale': true,
          'staleEpoch': 4,
          'currentEpoch': 5,
          'finalEpoch': 5,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateSameEpochKeyConflictVerdicts() {
  const scenario = 'private_same_epoch_key_conflict';
  const groupId = 'private-same-epoch-key-conflict-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterSameEpochConflict',
          'messageId': 'ke005-a-after',
          'text': 'alice after same epoch conflict',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 5,
        },
      ],
      extra: const <String, Object?>{
        'ke005SameEpochKeyConflictProof': <String, Object?>{
          'rowId': 'KE-005',
          'generatedOriginalEpochFive': true,
          'deliveredOriginalEpochFiveToBob': true,
          'deliveredSameEpochConflictToBob': true,
          'sentEpochFiveAfterConflict': true,
          'conflictEpoch': 5,
          'currentEpoch': 5,
          'finalEpoch': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterSameEpochConflict',
          'ke005-a-after',
          'alice after same epoch conflict',
          'alice-peer',
          keyEpoch: 5,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterSameEpochConflict': 1,
      },
      extra: const <String, Object?>{
        'ke005SameEpochKeyConflictProof': <String, Object?>{
          'rowId': 'KE-005',
          'acceptedOriginalEpochFive': true,
          'observedSameEpochConflict': true,
          'rejectedConflictingMaterial': true,
          'keptOriginalEpochFiveAfterConflict': true,
          'receivedEpochFiveAfterConflict': true,
          'conflictEpoch': 5,
          'currentEpoch': 5,
          'epochBeforeConflict': 5,
          'epochAfterConflict': 5,
          'finalEpoch': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 5,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterSameEpochConflict',
          'ke005-a-after',
          'alice after same epoch conflict',
          'alice-peer',
          keyEpoch: 5,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterSameEpochConflict': 1,
      },
      extra: const <String, Object?>{
        'ke005SameEpochKeyConflictProof': <String, Object?>{
          'rowId': 'KE-005',
          'notTargetedByConflict': true,
          'receivedEpochFiveAfterConflict': true,
          'conflictEpoch': 5,
          'currentEpoch': 5,
          'finalEpoch': 5,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivatePartialKeyDistributionVerdicts() {
  const scenario = 'private_partial_key_distribution';
  const groupId = 'private-partial-key-distribution-group';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterPartialKeyDistributionFailure',
          'messageId': 'ke015-a-after',
          'text': 'alice after partial distribution failure',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
        },
      ],
      extra: const <String, Object?>{
        'ke015PartialKeyDistributionProof': <String, Object?>{
          'rowId': 'KE-015',
          'attemptedMixedDistribution': true,
          'bobKeyUpdateSucceeded': true,
          'charlieKeyUpdateFailed': true,
          'rotationBlocked': true,
          'keptSenderEpochAfterFailure': true,
          'blockedKeyRotatedPublish': true,
          'sentPostFailureAtPreviousEpoch': true,
          'attemptedEpoch': 2,
          'postFailureMessageEpoch': 1,
          'finalEpoch': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterPartialKeyDistributionFailure',
          'ke015-a-after',
          'alice after partial distribution failure',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterPartialKeyDistributionFailure': 1,
      },
      extra: const <String, Object?>{
        'ke015PartialKeyDistributionProof': <String, Object?>{
          'rowId': 'KE-015',
          'receivedSuccessfulKeyUpdate': true,
          'successfulRecipientStillReceivesPostFailure': true,
          'receivedPostFailureAtPreviousEpoch': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterPartialKeyDistributionFailure',
          'ke015-a-after',
          'alice after partial distribution failure',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterPartialKeyDistributionFailure': 1,
      },
      extra: const <String, Object?>{
        'ke015PartialKeyDistributionProof': <String, Object?>{
          'rowId': 'KE-015',
          'failedRecipientDidNotAdvance': true,
          'receivedPostFailureAtPreviousEpoch': true,
          'notDeafAfterFailedKeyUpdate': true,
          'finalEpoch': 1,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validMl016NonFriendVerdicts() {
  const scenario = 'private_non_friend_member_delivery';
  const groupId = 'group-ml016';
  const alicePeerId = 'alice-peer';
  const bobPeerId = 'bob-peer';
  const danaPeerId = 'dana-peer';
  const activeMembers = <String>[alicePeerId, bobPeerId, danaPeerId];
  const aliceMessage = <String, Object?>{
    'key': 'aliceNonFriendToDana',
    'messageId': 'msg-ml016-alice',
    'groupId': groupId,
    'text': 'ML-016 Alice to non-friend Dana',
    'outcome': 'success',
    'senderPeerId': alicePeerId,
    'keyEpoch': 2,
    'accepted': true,
  };
  const bobMessage = <String, Object?>{
    'key': 'bobNonFriendToDana',
    'messageId': 'msg-ml016-bob',
    'groupId': groupId,
    'text': 'ML-016 Bob to non-friend Dana',
    'outcome': 'success',
    'senderPeerId': bobPeerId,
    'keyEpoch': 2,
    'accepted': true,
  };

  Map<String, Object?> proofFor(String role) {
    return <String, Object?>{
      'rowId': 'ML-016',
      'scenario': scenario,
      'proofRole': role,
      'appPeerPlatform': 'ios_26_2_core_simulator',
      'nonFriendProofSource': 'app_peer_core_simulator',
      'danaExplicitlyInvitedOrAdmitted': true,
      'danaHasSavedAliceContact': false,
      'danaHasSavedBobContact': false,
      'aliceMessageReceived': true,
      'bobMessageReceived': true,
      'alicePersistedExactlyOnce': true,
      'bobPersistedExactlyOnce': true,
      'aliceStableSenderLabel': 'Alice',
      'bobStableSenderLabel': 'Bob',
      'senderLabelsNonBlank': true,
      'messagesHiddenByContactGate': false,
      'finalMemberConvergence': true,
      'finalKeyConvergence': true,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: alicePeerId,
      groupId: groupId,
      keyEpoch: 2,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[aliceMessage],
      extra: <String, Object?>{
        'ml016NonFriendDeliveryProof': proofFor('alice'),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: bobPeerId,
      groupId: groupId,
      keyEpoch: 2,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[bobMessage],
      extra: <String, Object?>{'ml016NonFriendDeliveryProof': proofFor('bob')},
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'dana',
      peerId: danaPeerId,
      groupId: groupId,
      keyEpoch: 2,
      memberPeerIds: activeMembers,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceNonFriendToDana',
          'msg-ml016-alice',
          'ML-016 Alice to non-friend Dana',
          alicePeerId,
          keyEpoch: 2,
        ),
        _received(
          'bobNonFriendToDana',
          'msg-ml016-bob',
          'ML-016 Bob to non-friend Dana',
          bobPeerId,
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceNonFriendToDana': 1,
        'bobNonFriendToDana': 1,
      },
      extra: <String, Object?>{'ml016NonFriendDeliveryProof': proofFor('dana')},
    ),
  ];
}

Map<String, dynamic> _withMl016ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'ml016NonFriendDeliveryProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['ml016NonFriendDeliveryProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validMl020AdminRoleTransferVerdicts() {
  const scenario = 'private_admin_role_transfer_delivery';
  const groupId = 'group-ml020';
  const alicePeerId = 'alice-peer';
  const bobPeerId = 'bob-peer';
  const charliePeerId = 'charlie-peer';
  const activeMembers = <String>[alicePeerId, bobPeerId, charliePeerId];
  const aliceRemoved = <String, Object?>{
    'key': 'aliceRemovedWindowAfterDemotion',
    'messageId': 'msg-ml020-alice-removed',
    'groupId': groupId,
    'text': 'ML-020 Alice removed-window',
    'outcome': 'success',
    'senderPeerId': alicePeerId,
    'keyEpoch': 2,
    'timestamp': '2026-05-15T18:02:00.000Z',
    'accepted': true,
  };
  const bobRemoved = <String, Object?>{
    'key': 'bobRemovedWindowAfterAliceDemotion',
    'messageId': 'msg-ml020-bob-removed',
    'groupId': groupId,
    'text': 'ML-020 Bob removed-window',
    'outcome': 'success',
    'senderPeerId': bobPeerId,
    'keyEpoch': 2,
    'timestamp': '2026-05-15T18:03:00.000Z',
    'accepted': true,
  };
  const aliceAfter = <String, Object?>{
    'key': 'aliceAfterCharlieReadd',
    'messageId': 'msg-ml020-alice-after',
    'groupId': groupId,
    'text': 'ML-020 Alice after readd',
    'outcome': 'success',
    'senderPeerId': alicePeerId,
    'keyEpoch': 3,
    'timestamp': '2026-05-15T18:04:00.000Z',
    'accepted': true,
  };
  const bobAfter = <String, Object?>{
    'key': 'bobAfterCharlieReadd',
    'messageId': 'msg-ml020-bob-after',
    'groupId': groupId,
    'text': 'ML-020 Bob after readd',
    'outcome': 'success',
    'senderPeerId': bobPeerId,
    'keyEpoch': 3,
    'timestamp': '2026-05-15T18:05:00.000Z',
    'accepted': true,
  };
  const charlieAfter = <String, Object?>{
    'key': 'charlieAfterRoleReadd',
    'messageId': 'msg-ml020-charlie-after',
    'groupId': groupId,
    'text': 'ML-020 Charlie after readd',
    'outcome': 'success',
    'senderPeerId': charliePeerId,
    'keyEpoch': 3,
    'timestamp': '2026-05-15T18:06:00.000Z',
    'accepted': true,
  };

  Map<String, Object?> proofFor(String role) {
    return <String, Object?>{
      'rowId': 'ML-020',
      'scenario': scenario,
      'proofRole': role,
      'appPeerPlatform': 'ios_26_2_core_simulator',
      'roleChangeProofSource': 'app_peer_core_simulator',
      'bobPromotedToAdmin': true,
      'aliceDemotedButActive': true,
      'charlieRemovedBeforeReadd': true,
      'charlieReaddedAfterRemoval': true,
      'removedWindowDeliveryExcludedCharlie': true,
      'postReaddDeliveryToAllActiveMembers': true,
      'roleStateConverged': true,
      'memberStateConverged': true,
      'finalKeyConverged': true,
      'creatorRequiredForDelivery': false,
      'adminOnlyDelivery': false,
      'charlieReceivedRemovedWindow': false,
      'removedWindowPlaintextCount': 0,
      'finalEpoch': 3,
      'finalMemberRoles': const <String, String>{
        'alice': 'writer',
        'bob': 'admin',
        'charlie': 'writer',
      },
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: alicePeerId,
      groupId: groupId,
      keyEpoch: 3,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[aliceRemoved, aliceAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobRemovedWindowAfterAliceDemotion',
          'msg-ml020-bob-removed',
          'ML-020 Bob removed-window',
          bobPeerId,
          keyEpoch: 2,
          timestamp: '2026-05-15T18:03:00.000Z',
        ),
        _received(
          'bobAfterCharlieReadd',
          'msg-ml020-bob-after',
          'ML-020 Bob after readd',
          bobPeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:05:00.000Z',
        ),
        _received(
          'charlieAfterRoleReadd',
          'msg-ml020-charlie-after',
          'ML-020 Charlie after readd',
          charliePeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:06:00.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobRemovedWindowAfterAliceDemotion': 1,
        'bobAfterCharlieReadd': 1,
        'charlieAfterRoleReadd': 1,
      },
      extra: <String, Object?>{
        'ml020AdminRoleDeliveryProof': proofFor('alice'),
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: bobPeerId,
      groupId: groupId,
      keyEpoch: 3,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[bobRemoved, bobAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceRemovedWindowAfterDemotion',
          'msg-ml020-alice-removed',
          'ML-020 Alice removed-window',
          alicePeerId,
          keyEpoch: 2,
          timestamp: '2026-05-15T18:02:00.000Z',
        ),
        _received(
          'aliceAfterCharlieReadd',
          'msg-ml020-alice-after',
          'ML-020 Alice after readd',
          alicePeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:04:00.000Z',
        ),
        _received(
          'charlieAfterRoleReadd',
          'msg-ml020-charlie-after',
          'ML-020 Charlie after readd',
          charliePeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:06:00.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceRemovedWindowAfterDemotion': 1,
        'aliceAfterCharlieReadd': 1,
        'charlieAfterRoleReadd': 1,
      },
      extra: <String, Object?>{'ml020AdminRoleDeliveryProof': proofFor('bob')},
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: charliePeerId,
      groupId: groupId,
      keyEpoch: 3,
      memberPeerIds: activeMembers,
      sentMessages: const <Map<String, Object?>>[charlieAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterCharlieReadd',
          'msg-ml020-alice-after',
          'ML-020 Alice after readd',
          alicePeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:04:00.000Z',
        ),
        _received(
          'bobAfterCharlieReadd',
          'msg-ml020-bob-after',
          'ML-020 Bob after readd',
          bobPeerId,
          keyEpoch: 3,
          timestamp: '2026-05-15T18:05:00.000Z',
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterCharlieReadd': 1,
        'bobAfterCharlieReadd': 1,
      },
      extra: <String, Object?>{
        'ml020AdminRoleDeliveryProof': proofFor('charlie'),
      },
    ),
  ];
}

Map<String, dynamic> _withMl020ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'ml020AdminRoleDeliveryProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['ml020AdminRoleDeliveryProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validGm007Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm007',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm007-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceBeforeCharlieRemoval',
          'messageId': 'gm007-a-before',
          'text': 'alice before charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
        },
        {
          'key': 'aliceDuringCharlieRemoval1',
          'messageId': 'gm007-a-during-1',
          'text': 'alice during charlie removal 1',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceDuringCharlieRemoval2',
          'messageId': 'gm007-a-during-2',
          'text': 'alice during charlie removal 2',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceDuringCharlieRemoval3',
          'messageId': 'gm007-a-during-3',
          'text': 'alice during charlie removal 3',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterCharlieReadd',
          'messageId': 'gm007-a-after',
          'text': 'alice after charlie readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      extra: const <String, Object?>{
        'gm007HistoryBoundaryProof': <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'sentPreRemovalBeforeRemove': true,
          'sentRemovedWindowWhileRemoved': true,
          'sentPostReaddAfterReadd': true,
          'finalEpoch': 2,
        },
        'ke018HistoryReplayEpochWindowProof': <String, Object?>{
          'rowId': 'KE-018',
          'sentPreRemovalReplayWindow': true,
          'sentRemovedWindowWhileCharlieRemoved': true,
          'sentRemovedWindowCount': 3,
          'sentPostReaddReplayWindow': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ir005ReaddReplayProof': <String, Object?>{
          'rowId': 'IR-005',
          'sentPreRemovalReplayWindow': true,
          'sentRemovedWindowWhileCharlieRemoved': true,
          'sentRemovedWindowCount': 3,
          'sentPostReaddReplayWindow': true,
          'readdedCharlie': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm007',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm007-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeCharlieRemoval',
          'gm007-a-before',
          'alice before charlie removal',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceDuringCharlieRemoval1',
          'gm007-a-during-1',
          'alice during charlie removal 1',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceDuringCharlieRemoval2',
          'gm007-a-during-2',
          'alice during charlie removal 2',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceDuringCharlieRemoval3',
          'gm007-a-during-3',
          'alice during charlie removal 3',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterCharlieReadd',
          'gm007-a-after',
          'alice after charlie readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeCharlieRemoval': 1,
        'aliceDuringCharlieRemoval1': 1,
        'aliceDuringCharlieRemoval2': 1,
        'aliceDuringCharlieRemoval3': 1,
        'aliceAfterCharlieReadd': 1,
      },
      extra: const <String, Object?>{
        'gm007HistoryBoundaryProof': <String, Object?>{
          'memberListIncludesCharlie': true,
          'receivedPreRemovalMessage': true,
          'receivedRemovedWindowMessageCount': 3,
          'receivedPostReaddMessage': true,
          'finalEpoch': 2,
        },
        'ke018HistoryReplayEpochWindowProof': <String, Object?>{
          'rowId': 'KE-018',
          'receivedPreRemovalReplayWindow': true,
          'receivedRemovedWindowWhileCharlieRemoved': true,
          'receivedRemovedWindowCount': 3,
          'receivedPostReaddReplayWindow': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
        'ir005ReaddReplayProof': <String, Object?>{
          'rowId': 'IR-005',
          'receivedPreRemovalReplayWindow': true,
          'receivedRemovedWindowWhileCharlieRemoved': true,
          'receivedRemovedWindowCount': 3,
          'receivedPostReaddReplayWindow': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm007',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm007-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceBeforeCharlieRemoval',
          'gm007-a-before',
          'alice before charlie removal',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceAfterCharlieReadd',
          'gm007-a-after',
          'alice after charlie readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceBeforeCharlieRemoval': 1,
        'aliceAfterCharlieReadd': 1,
      },
      extra: const <String, Object?>{
        'gm007HistoryBoundaryProof': <String, Object?>{
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'receivedPreRemovalMessage': true,
          'receivedPostReaddMessage': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterReadd': false,
          'finalEpoch': 2,
        },
        'ke018HistoryReplayEpochWindowProof': <String, Object?>{
          'rowId': 'KE-018',
          'receivedPreRemovalReplayWindow': true,
          'postReaddMissingBeforeDrain': true,
          'drainedPostReaddReplayAtCurrentEpoch': true,
          'noRemovedWindowReplayAfterDrain': true,
          'memberListIncludesAliceBobCharlie': true,
          'removedWindowPlaintextCount': 0,
          'preRemovalReplayEpoch': 1,
          'postReaddReplayEpoch': 2,
          'finalEpoch': 2,
        },
        'ir005ReaddReplayProof': <String, Object?>{
          'rowId': 'IR-005',
          'receivedAllowedPreRemovalHistory': true,
          'postReaddMissingBeforeDrain': true,
          'receivedPostReaddReplayAfterDrain': true,
          'noRemovedWindowReplayAfterDrain': true,
          'memberListIncludesAliceBobCharlie': true,
          'removedWindowPlaintextCount': 0,
          'preRemovalReplayEpoch': 1,
          'postReaddReplayEpoch': 2,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGe014Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge014RestartBeforeTopicJoinProof';
  const aliceRemoved = <String, Object?>{
    'key': 'aliceGe014RemovedWindow',
    'messageId': 'ge014-a-removed',
    'text': 'alice removed-window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
  };
  const alicePost = <String, Object?>{
    'key': 'aliceGe014PostReadd',
    'messageId': 'ge014-a-post',
    'text': 'alice post-readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 3,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
  };
  const bobPost = <String, Object?>{
    'key': 'bobGe014PostReadd',
    'messageId': 'ge014-b-post',
    'text': 'bob post-readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 3,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
  };
  const charlieAfterRestart = <String, Object?>{
    'key': 'charlieGe014AfterRestart',
    'messageId': 'ge014-c-after',
    'text': 'charlie after restart',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 3,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
  };
  const aliceProof = <String, Object?>{
    'removedCharlie': true,
    'readdedCharlie': true,
    'charlieReceivedInviteBeforeRestart': true,
    'charliePersistedInviteBeforeRestart': true,
    'charliePersistedKeyBeforeRestart': true,
    'charlieNotJoinedTopicBeforeRestart': true,
    'charlieJoinedTopicBeforeRestart': false,
    'charlieRestartedBeforeTopicJoin': true,
    'sentPostReaddMessages': true,
    'receivedCharliePostRestartMessage': true,
    'removedPeerId': 'charlie-peer',
    'memberListIncludesCharlie': true,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };
  const bobProof = <String, Object?>{
    'observedCharlieRestartBoundary': true,
    'receivedRemovedWindowMessage': true,
    'receivedAlicePostReaddMessage': true,
    'receivedCharliePostRestartMessage': true,
    'memberListIncludesCharlie': true,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };
  const charlieProof = <String, Object?>{
    'removedCharlie': true,
    'readdedCharlie': true,
    'charlieReceivedInviteBeforeRestart': true,
    'charliePersistedInviteBeforeRestart': true,
    'charliePersistedKeyBeforeRestart': true,
    'charlieNotJoinedTopicBeforeRestart': true,
    'charlieJoinedTopicBeforeRestart': false,
    'charlieRestartedBeforeTopicJoin': true,
    'charlieRecoveredInviteAfterRestart': true,
    'charlieRecoveredKeyAfterRestart': true,
    'charlieJoinedTopicAfterRestart': true,
    'retrievedPostReaddMessages': true,
    'postReaddReceivedKeys': <String>[
      'aliceGe014PostReadd',
      'bobGe014PostReadd',
    ],
    'postReaddPublishAccepted': true,
    'removedWindowPlaintextCount': 0,
    'hasStaleEpochAfterRestart': false,
    'memberListIncludesAliceBob': true,
    'memberListIncludesCharlie': true,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge014',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge014-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[aliceRemoved, alicePost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe014PostReadd',
          'ge014-b-post',
          'bob post-readd',
          'bob-peer',
          keyEpoch: 3,
        ),
        _received(
          'charlieGe014AfterRestart',
          'ge014-c-after',
          'charlie after restart',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe014PostReadd': 1,
        'charlieGe014AfterRestart': 1,
      },
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'ge014',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge014-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[bobPost],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe014RemovedWindow',
          'ge014-a-removed',
          'alice removed-window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGe014PostReadd',
          'ge014-a-post',
          'alice post-readd',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'charlieGe014AfterRestart',
          'ge014-c-after',
          'charlie after restart',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe014RemovedWindow': 1,
        'aliceGe014PostReadd': 1,
        'charlieGe014AfterRestart': 1,
      },
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'ge014',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge014-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[charlieAfterRestart],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe014PostReadd',
          'ge014-a-post',
          'alice post-readd',
          'alice-peer',
          keyEpoch: 3,
        ),
        _received(
          'bobGe014PostReadd',
          'ge014-b-post',
          'bob post-readd',
          'bob-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe014PostReadd': 1,
        'bobGe014PostReadd': 1,
      },
      extra: const <String, Object?>{proofName: charlieProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe015Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge015AdminRestartMutationProof';
  const aliceRemoved = <String, Object?>{
    'key': 'aliceGe015RemovedWindow',
    'messageId': 'ge015-a-removed',
    'text': 'alice removed-window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
  };
  const bobAfterRepair = <String, Object?>{
    'key': 'bobGe015AfterRemoveRepair',
    'messageId': 'ge015-b-after-remove-repair',
    'text': 'bob after remove repair',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer'],
  };
  const charlieAfterInviteRepair = <String, Object?>{
    'key': 'charlieGe015AfterInviteRepair',
    'messageId': 'ge015-c-after-invite-repair',
    'text': 'charlie after invite repair',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 3,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
  };
  const aliceProof = <String, Object?>{
    'adminPersistedLocalMutationBeforeRestart': true,
    'adminRestartedBeforeFanoutComplete': true,
    'removeFanoutInterruptedBeforeRestart': true,
    'removeFanoutRepairCompletedAfterRestart': true,
    'addInviteStatusDurableBeforeRestart': true,
    'addInviteRepairCompletedAfterRestart': true,
    'pendingFanoutStatusBeforeRestart': 'needs_resend',
    'finalFanoutStatus': 'sent',
    'allActivePeersConverged': true,
    'strandedPeerCount': 0,
    'removedWindowPlaintextLeakCount': 0,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };
  const bobProof = <String, Object?>{
    'observedAdminRestartBoundary': true,
    'receivedRemoveRepairKey': true,
    'receivedRemovedWindowMessage': true,
    'receivedCharlieAfterInviteRepair': true,
    'allActivePeersConverged': true,
    'strandedPeerCount': 0,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };
  const charlieProof = <String, Object?>{
    'removedBeforeAdminRestart': true,
    'notEntitledDuringRemovedWindow': true,
    'joinedAfterInviteRepair': true,
    'sentAfterInviteRepair': true,
    'allActivePeersConverged': true,
    'removedWindowPlaintextCount': 0,
    'hasStaleEpochAfterRepair': false,
    'memberPeerIds': members,
    'finalEpoch': 3,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge015',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge015-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[aliceRemoved],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe015AfterRemoveRepair',
          'ge015-b-after-remove-repair',
          'bob after remove repair',
          'bob-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe015AfterInviteRepair',
          'ge015-c-after-invite-repair',
          'charlie after invite repair',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe015AfterRemoveRepair': 1,
        'charlieGe015AfterInviteRepair': 1,
      },
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'ge015',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge015-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[bobAfterRepair],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe015RemovedWindow',
          'ge015-a-removed',
          'alice removed-window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe015AfterInviteRepair',
          'ge015-c-after-invite-repair',
          'charlie after invite repair',
          'charlie-peer',
          keyEpoch: 3,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe015RemovedWindow': 1,
        'charlieGe015AfterInviteRepair': 1,
      },
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'ge015',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge015-group',
      memberPeerIds: members,
      keyEpoch: 3,
      sentMessages: const <Map<String, Object?>>[charlieAfterInviteRepair],
      extra: const <String, Object?>{proofName: charlieProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe016Verdicts() {
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  const proofName = 'ge016ConcurrentAdminMutationProof';
  const proof = <String, Object?>{
    'bobPromotedToAdmin': true,
    'aliceRemoveCharliePrepared': true,
    'bobAddDanaApplied': true,
    'staleRemovePublishedAfterAdd': true,
    'allActivePeersConverged': true,
    'deterministicConflictWinner': 'bob_add_dana',
    'finalMembershipConverged': true,
    'charliePresentAfterConflict': true,
    'danaPresentAfterConflict': true,
    'finalMemberPeerIds': members,
    'finalRolesByPeerId': <String, String>{
      'alice-peer': 'admin',
      'bob-peer': 'admin',
      'charlie-peer': 'writer',
      'dana-peer': 'writer',
    },
    'bobPromotedAt': '2026-05-14T04:36:04.000Z',
    'removeCharlieAt': '2026-05-14T04:36:05.000Z',
    'addDanaAt': '2026-05-14T04:36:06.000Z',
    'lastMembershipEventAt': '2026-05-14T04:36:06.000Z',
    'addWinsByVersion': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge016',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge016-group',
      memberPeerIds: members,
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge016',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge016-group',
      memberPeerIds: members,
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge016',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge016-group',
      memberPeerIds: members,
      extra: const <String, Object?>{proofName: proof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe020Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge020LongSoakChurnProof';
  const aliceInitial = <String, Object?>{
    'key': 'aliceGe020Initial',
    'messageId': 'ge020-a-initial',
    'text': 'alice initial',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
  };
  const bobHeld = <String, Object?>{
    'key': 'bobGe020OfflineHeld',
    'messageId': 'ge020-b-held',
    'text': 'bob held',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
  };
  const aliceAfterRejoin = <String, Object?>{
    'key': 'aliceGe020AfterRejoin',
    'messageId': 'ge020-a-after-rejoin',
    'text': 'alice after rejoin',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
  };
  const aliceRemovedWindow = <String, Object?>{
    'key': 'aliceGe020RemovedWindow',
    'messageId': 'ge020-a-removed',
    'text': 'alice removed-window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
  };
  const charlieAfterReadd = <String, Object?>{
    'key': 'charlieGe020AfterReadd',
    'messageId': 'ge020-c-after-readd',
    'text': 'charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
  };
  const proof = <String, Object?>{
    'noPermanentDeafMember': true,
    'allActivePeersConverged': true,
    'heldDeliveryQueuesDrained': true,
    'noStrandedRetryQueues': true,
    'strandedQueueCount': 0,
    'noRemovedWindowPlaintext': true,
    'removedWindowPlaintextCount': 0,
    'duplicateDeliveryDeduped': true,
    'keyEpochConverged': true,
    'finalEpoch': 2,
    'memberPeerIds': members,
    'postRemovalSendAccepted': false,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge020',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge020-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        aliceInitial,
        aliceAfterRejoin,
        aliceRemovedWindow,
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe020OfflineHeld',
          'ge020-b-held',
          'bob held',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'charlieGe020AfterReadd',
          'ge020-c-after-readd',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe020OfflineHeld': 1,
        'charlieGe020AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge020',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge020-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobHeld],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe020Initial',
          'ge020-a-initial',
          'alice initial',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe020AfterRejoin',
          'ge020-a-after-rejoin',
          'alice after rejoin',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe020RemovedWindow',
          'ge020-a-removed',
          'alice removed-window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe020AfterReadd',
          'ge020-c-after-readd',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe020Initial': 1,
        'aliceGe020AfterRejoin': 1,
        'aliceGe020RemovedWindow': 1,
        'charlieGe020AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge020',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge020-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieAfterReadd],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe020Initial',
          'ge020-a-initial',
          'alice initial',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'bobGe020OfflineHeld',
          'ge020-b-held',
          'bob held',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe020AfterRejoin',
          'ge020-a-after-rejoin',
          'alice after rejoin',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe020Initial': 1,
        'bobGe020OfflineHeld': 1,
        'aliceGe020AfterRejoin': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe021Verdicts() {
  const syntheticMembers = <String>[
    'ge021-stable-01-peer',
    'ge021-stable-02-peer',
    'ge021-stable-03-peer',
    'ge021-stable-04-peer',
    'ge021-stable-05-peer',
    'ge021-stable-06-peer',
    'ge021-stable-07-peer',
    'ge021-stable-08-peer',
  ];
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    ...syntheticMembers,
  ];
  const proofName = 'ge021LargeGroupFlakyMemberProof';
  const aliceInitial = <String, Object?>{
    'key': 'aliceGe021Initial',
    'messageId': 'ge021-a-initial',
    'text': 'alice initial',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>[
      'bob-peer',
      'charlie-peer',
      ...syntheticMembers,
    ],
    'actualDurablePayloadProof': true,
  };
  const bobWhileFlaky = <String, Object?>{
    'key': 'bobGe021WhileFlaky',
    'messageId': 'ge021-b-flaky',
    'text': 'bob while flaky',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>[
      'alice-peer',
      'charlie-peer',
      ...syntheticMembers,
    ],
    'actualDurablePayloadProof': true,
  };
  const aliceAfterOnline = <String, Object?>{
    'key': 'aliceGe021AfterOnline',
    'messageId': 'ge021-a-online',
    'text': 'alice after online',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'recipientPeerIds': <String>[
      'bob-peer',
      'charlie-peer',
      ...syntheticMembers,
    ],
    'actualDurablePayloadProof': true,
  };
  const aliceRemovedWindow = <String, Object?>{
    'key': 'aliceGe021RemovedWindow',
    'messageId': 'ge021-a-removed',
    'text': 'alice removed-window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', ...syntheticMembers],
    'actualDurablePayloadProof': true,
  };
  const charlieAfterReadd = <String, Object?>{
    'key': 'charlieGe021AfterReadd',
    'messageId': 'ge021-c-readd',
    'text': 'charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer', ...syntheticMembers],
    'actualDurablePayloadProof': true,
  };
  const proof = <String, Object?>{
    'largeGroupRosterSize': 11,
    'stableDevicePeerIds': <String>['alice-peer', 'bob-peer'],
    'syntheticStableMemberPeerIds': syntheticMembers,
    'syntheticStableMemberCount': 8,
    'flakyPeerId': 'charlie-peer',
    'flakyChurnCycles': 2,
    'flakyLiveLeaveRejoinCompleted': true,
    'flakyRemovedAndReadded': true,
    'allStableDevicesConverged': true,
    'stableMemberDeliveryConverged': true,
    'noStableMemberMisses': true,
    'stableMessageMissCount': 0,
    'strandedQueueCount': 0,
    'finalRosterConverged': true,
    'finalIncludesFlaky': true,
    'finalMemberPeerIds': members,
    'noRemovedWindowPlaintext': true,
    'removedWindowPlaintextCount': 0,
    'postRemovalSendAccepted': false,
    'keyEpochConverged': true,
    'finalEpoch': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge021',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        aliceInitial,
        aliceAfterOnline,
        aliceRemovedWindow,
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGe021WhileFlaky',
          'ge021-b-flaky',
          'bob while flaky',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'charlieGe021AfterReadd',
          'ge021-c-readd',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobGe021WhileFlaky': 1,
        'charlieGe021AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge021',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobWhileFlaky],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe021Initial',
          'ge021-a-initial',
          'alice initial',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe021AfterOnline',
          'ge021-a-online',
          'alice after online',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe021RemovedWindow',
          'ge021-a-removed',
          'alice removed-window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieGe021AfterReadd',
          'ge021-c-readd',
          'charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe021Initial': 1,
        'aliceGe021AfterOnline': 1,
        'aliceGe021RemovedWindow': 1,
        'charlieGe021AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge021',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieAfterReadd],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGe021Initial',
          'ge021-a-initial',
          'alice initial',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'bobGe021WhileFlaky',
          'ge021-b-flaky',
          'bob while flaky',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGe021AfterOnline',
          'ge021-a-online',
          'alice after online',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGe021Initial': 1,
        'bobGe021WhileFlaky': 1,
        'aliceGe021AfterOnline': 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe023Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'ge023MediaReaddProof';
  const contentHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Map<String, Object?> media(
    String id,
    String messageId, {
    bool local = false,
  }) {
    return <String, Object?>{
      'id': id,
      'messageId': messageId,
      'mime': 'image/jpeg',
      'size': 2048,
      'mediaType': 'image',
      'width': 1200,
      'height': 800,
      'downloadStatus': local ? 'done' : 'pending',
      'localPathPresent': local,
      'contentHash': contentHash,
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    };
  }

  Map<String, Object?> sentMedia({
    required String key,
    required String messageId,
    required String text,
    required String senderPeerId,
    required List<String> recipientPeerIds,
    required String attachmentId,
  }) {
    final attachment = media(attachmentId, messageId, local: true);
    return <String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': senderPeerId,
      'keyEpoch': 1,
      'recipientPeerIds': recipientPeerIds,
      'actualDurablePayloadProof': true,
      'mediaAttachments': <Map<String, Object?>>[attachment],
      'mediaAttachmentIds': <String>[attachmentId],
      'mediaContentHashes': <String>[contentHash],
      'mediaAttachmentCount': 1,
      'wireMediaCount': 1,
      'durableMediaCount': 1,
    };
  }

  Map<String, Object?> receivedMedia({
    required String key,
    required String messageId,
    required String text,
    required String senderPeerId,
    required String attachmentId,
  }) {
    final base = _received(key, messageId, text, senderPeerId, keyEpoch: 1);
    return <String, Object?>{
      ...base,
      'mediaAttachments': <Map<String, Object?>>[
        media(attachmentId, messageId),
      ],
      'mediaAttachmentIds': <String>[attachmentId],
      'mediaContentHashes': <String>[contentHash],
      'mediaAttachmentCount': 1,
    };
  }

  const beforeKey = 'aliceGe023BeforeRemoval';
  const removedKey = 'aliceGe023RemovedWindow';
  const afterKey = 'charlieGe023AfterReadd';
  const beforeId = 'ge023-a-before';
  const removedId = 'ge023-a-removed';
  const afterId = 'ge023-c-after';
  const beforeAttachmentId = 'ge023-before-blob';
  const removedAttachmentId = 'ge023-removed-blob';
  const afterAttachmentId = 'ge023-after-blob';
  final beforeSent = sentMedia(
    key: beforeKey,
    messageId: beforeId,
    text: 'alice before media',
    senderPeerId: 'alice-peer',
    recipientPeerIds: const <String>['bob-peer', 'charlie-peer'],
    attachmentId: beforeAttachmentId,
  );
  final removedSent = sentMedia(
    key: removedKey,
    messageId: removedId,
    text: 'alice removed media',
    senderPeerId: 'alice-peer',
    recipientPeerIds: const <String>['bob-peer'],
    attachmentId: removedAttachmentId,
  );
  final afterSent = sentMedia(
    key: afterKey,
    messageId: afterId,
    text: 'charlie after media',
    senderPeerId: 'charlie-peer',
    recipientPeerIds: const <String>['alice-peer', 'bob-peer'],
    attachmentId: afterAttachmentId,
  );
  const proof = <String, Object?>{
    'actualMediaPayloadProof': true,
    'renderReadyMetadataProof': true,
    'contentHash': contentHash,
    'removedPeerId': 'charlie-peer',
    'finalIncludesRemovedPeer': true,
    'removedWindowMediaInaccessible': true,
    'noRemovedWindowPlaintext': true,
    'removedWindowPlaintextCount': 0,
    'removedWindowAttachmentCount': 0,
    'finalMemberPeerIds': members,
    'finalEpoch': 1,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge023',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge023-group',
      memberPeerIds: members,
      sentMessages: <Map<String, Object?>>[beforeSent, removedSent],
      receivedMessages: <Map<String, Object?>>[
        receivedMedia(
          key: afterKey,
          messageId: afterId,
          text: 'charlie after media',
          senderPeerId: 'charlie-peer',
          attachmentId: afterAttachmentId,
        ),
      ],
      persistedMessageCounts: const <String, int>{afterKey: 1},
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge023',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge023-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        receivedMedia(
          key: beforeKey,
          messageId: beforeId,
          text: 'alice before media',
          senderPeerId: 'alice-peer',
          attachmentId: beforeAttachmentId,
        ),
        receivedMedia(
          key: removedKey,
          messageId: removedId,
          text: 'alice removed media',
          senderPeerId: 'alice-peer',
          attachmentId: removedAttachmentId,
        ),
        receivedMedia(
          key: afterKey,
          messageId: afterId,
          text: 'charlie after media',
          senderPeerId: 'charlie-peer',
          attachmentId: afterAttachmentId,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        beforeKey: 1,
        removedKey: 1,
        afterKey: 1,
      },
      extra: const <String, Object?>{proofName: proof},
    ),
    _baseVerdict(
      scenario: 'ge023',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge023-group',
      memberPeerIds: members,
      sentMessages: <Map<String, Object?>>[afterSent],
      receivedMessages: <Map<String, Object?>>[
        receivedMedia(
          key: beforeKey,
          messageId: beforeId,
          text: 'alice before media',
          senderPeerId: 'alice-peer',
          attachmentId: beforeAttachmentId,
        ),
      ],
      persistedMessageCounts: const <String, int>{beforeKey: 1},
      extra: const <String, Object?>{proofName: proof},
    ),
  ];
}

List<Map<String, dynamic>> _validGe024Verdicts() {
  const proofName = 'ge024QuotedReplyProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const beforeKey = 'aliceGe024BeforeRemovalParent';
  const removedKey = 'aliceGe024RemovedWindowParent';
  const availableKey = 'bobGe024ReplyAvailable';
  const unavailableKey = 'bobGe024ReplyUnavailable';
  const beforeId = 'ge024-before-parent';
  const removedId = 'ge024-removed-parent';
  const availableId = 'ge024-available-reply';
  const unavailableId = 'ge024-unavailable-reply';

  Map<String, Object?> sent({
    required String key,
    required String messageId,
    required String text,
    required String senderPeerId,
    required List<String> recipientPeerIds,
    String? quotedMessageId,
  }) {
    final entry = <String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'senderPeerId': senderPeerId,
      'recipientPeerIds': recipientPeerIds,
      'outcome': 'success',
      'keyEpoch': 1,
    };
    if (quotedMessageId != null) {
      entry['quotedMessageId'] = quotedMessageId;
    }
    return entry;
  }

  Map<String, Object?> received({
    required String key,
    required String messageId,
    required String text,
    required String senderPeerId,
    String? quotedMessageId,
  }) {
    final entry = <String, Object?>{
      ..._received(key, messageId, text, senderPeerId, keyEpoch: 1),
    };
    if (quotedMessageId != null) {
      entry['quotedMessageId'] = quotedMessageId;
    }
    return entry;
  }

  Map<String, Object?> proof({required bool missingRemovedParent}) {
    return <String, Object?>{
      'quotePropagationProof': true,
      'availableParentMessageId': beforeId,
      'removedWindowParentMessageId': removedId,
      'availableReplyMessageId': availableId,
      'unavailableReplyMessageId': unavailableId,
      'availableReplyQuotedMessageId': beforeId,
      'unavailableReplyQuotedMessageId': removedId,
      'availableReplyHasExpectedQuote': true,
      'unavailableReplyHasExpectedQuote': true,
      'availableParentPresent': true,
      'unavailableParentMissing': missingRemovedParent,
      'removedWindowPlaintextCount': 0,
      'noUnavailableParentPlaintext': true,
      'noCrashRenderingUnavailableQuote': true,
      'removedPeerId': 'charlie-peer',
      'finalIncludesRemovedPeer': true,
      'finalMemberPeerIds': members,
      'finalEpoch': 1,
    };
  }

  final beforeSent = sent(
    key: beforeKey,
    messageId: beforeId,
    text: 'alice before parent',
    senderPeerId: 'alice-peer',
    recipientPeerIds: const <String>['bob-peer', 'charlie-peer'],
  );
  final removedSent = sent(
    key: removedKey,
    messageId: removedId,
    text: 'alice removed parent',
    senderPeerId: 'alice-peer',
    recipientPeerIds: const <String>['bob-peer'],
  );
  final availableSent = sent(
    key: availableKey,
    messageId: availableId,
    text: 'bob available quote reply',
    senderPeerId: 'bob-peer',
    recipientPeerIds: const <String>['alice-peer', 'charlie-peer'],
    quotedMessageId: beforeId,
  );
  final unavailableSent = sent(
    key: unavailableKey,
    messageId: unavailableId,
    text: 'bob unavailable quote reply',
    senderPeerId: 'bob-peer',
    recipientPeerIds: const <String>['alice-peer', 'charlie-peer'],
    quotedMessageId: removedId,
  );

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'ge024',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ge024-group',
      memberPeerIds: members,
      sentMessages: <Map<String, Object?>>[beforeSent, removedSent],
      receivedMessages: <Map<String, Object?>>[
        received(
          key: availableKey,
          messageId: availableId,
          text: 'bob available quote reply',
          senderPeerId: 'bob-peer',
          quotedMessageId: beforeId,
        ),
        received(
          key: unavailableKey,
          messageId: unavailableId,
          text: 'bob unavailable quote reply',
          senderPeerId: 'bob-peer',
          quotedMessageId: removedId,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        availableKey: 1,
        unavailableKey: 1,
      },
      extra: <String, Object?>{proofName: proof(missingRemovedParent: false)},
    ),
    _baseVerdict(
      scenario: 'ge024',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ge024-group',
      memberPeerIds: members,
      sentMessages: <Map<String, Object?>>[availableSent, unavailableSent],
      receivedMessages: <Map<String, Object?>>[
        received(
          key: beforeKey,
          messageId: beforeId,
          text: 'alice before parent',
          senderPeerId: 'alice-peer',
        ),
        received(
          key: removedKey,
          messageId: removedId,
          text: 'alice removed parent',
          senderPeerId: 'alice-peer',
        ),
      ],
      persistedMessageCounts: const <String, int>{beforeKey: 1, removedKey: 1},
      extra: <String, Object?>{proofName: proof(missingRemovedParent: false)},
    ),
    _baseVerdict(
      scenario: 'ge024',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ge024-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        received(
          key: beforeKey,
          messageId: beforeId,
          text: 'alice before parent',
          senderPeerId: 'alice-peer',
        ),
        received(
          key: availableKey,
          messageId: availableId,
          text: 'bob available quote reply',
          senderPeerId: 'bob-peer',
          quotedMessageId: beforeId,
        ),
        received(
          key: unavailableKey,
          messageId: unavailableId,
          text: 'bob unavailable quote reply',
          senderPeerId: 'bob-peer',
          quotedMessageId: removedId,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        beforeKey: 1,
        availableKey: 1,
        unavailableKey: 1,
      },
      extra: <String, Object?>{proofName: proof(missingRemovedParent: true)},
    ),
  ];
}

List<Map<String, dynamic>> _validGm008Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm008',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm008-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRestartedRemoval',
          'messageId': 'gm008-a-during',
          'text': 'alice during restarted charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterRestartReadd',
          'messageId': 'gm008-a-after',
          'text': 'alice after restart readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterRestartReadd',
          'gm008-c-after',
          'charlie after restart readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterRestartReadd': 1,
      },
      extra: const <String, Object?>{
        'gm008RestartReaddProof': <String, Object?>{
          'removedCharlie': true,
          'charlieRestartedBeforeReadd': true,
          'distributedCurrentEpochToRemainingOnly': true,
          'sentRemovedWindowAfterRestartBeforeReadd': true,
          'readdedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm008',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm008-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRestartedRemoval',
          'gm008-a-during',
          'alice during restarted charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterRestartReadd',
          'gm008-c-after',
          'charlie after restart readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterRestartReadd',
          'gm008-a-after',
          'alice after restart readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRestartedRemoval': 1,
        'charlieAfterRestartReadd': 1,
        'aliceAfterRestartReadd': 1,
      },
      extra: const <String, Object?>{
        'gm008RestartReaddProof': <String, Object?>{
          'observedCharlieRestartBoundary': true,
          'memberListIncludesCharlie': true,
          'receivedRemovedWindowMessage': true,
          'receivedCharliePostReaddMessage': true,
          'receivedAlicePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm008',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm008-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterRestartReadd',
          'messageId': 'gm008-c-after',
          'text': 'charlie after restart readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterRestartReadd',
          'gm008-a-after',
          'alice after restart readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterRestartReadd': 1},
      extra: const <String, Object?>{
        'gm008RestartReaddProof': <String, Object?>{
          'runtimeRestartedAfterRemoval': true,
          'preReaddSendRejected': true,
          'rejoinedFromCurrentPersistedEpoch': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
          'hasStaleEpochAfterRestartReadd': false,
          'postReaddPublishAccepted': true,
          'receivedAlicePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm009Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm009',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm009-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterDuplicateRemove',
          'messageId': 'gm009-a-after',
          'text': 'alice after duplicate remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterDuplicateRemove',
          'gm009-b-after',
          'bob after duplicate remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobAfterDuplicateRemove': 1},
      extra: const <String, Object?>{
        'gm009DuplicateRemovalProof': <String, Object?>{
          'removedCharlieOnce': true,
          'duplicateRemoveIgnored': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'removalTimelineCount': 1,
          'rotationCount': 1,
          'keyDistributionCount': 1,
          'distributedKeyToCharlie': false,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm009',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm009-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterDuplicateRemove',
          'messageId': 'gm009-b-after',
          'text': 'bob after duplicate remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDuplicateRemove',
          'gm009-a-after',
          'alice after duplicate remove',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDuplicateRemove': 1,
      },
      extra: const <String, Object?>{
        'gm009DuplicateRemovalProof': <String, Object?>{
          'memberListExcludesCharlie': true,
          'removalTimelineCount': 1,
          'receivedAlicePostDuplicateRemove': true,
          'sentBobPostDuplicateRemove': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm009',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm009-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterDuplicateRemove',
          'messageId': 'gm009-c-after',
          'text': 'charlie after duplicate remove',
          'outcome': 'groupNotFound',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 0,
        },
      ],
      receivedMessages: const <Map<String, Object?>>[],
      persistedMessageCounts: const <String, int>{},
      extra: const <String, Object?>{
        'gm009DuplicateRemovalProof': <String, Object?>{
          'currentMemberBeforeRemoval': true,
          'groupPresentAfterDuplicateRemoval': false,
          'hasRotatedEpoch': false,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAlicePostDuplicateRemove': false,
          'receivedBobPostDuplicateRemove': false,
          'postRemovalPlaintextCount': 0,
          'finalEpoch': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm010Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm010',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm010-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterDuplicateReadd',
          'messageId': 'gm010-a-after',
          'text': 'alice after duplicate readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterDuplicateReadd',
          'gm010-c-after',
          'charlie after duplicate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterDuplicateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm010DuplicateReaddProof': <String, Object?>{
          'removedCharlie': true,
          'readdedCharlie': true,
          'duplicateReaddApplied': true,
          'duplicateReaddIgnored': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'charlieGroupConfigJoinCountAfterReadd': 1,
          'duplicateReaddTriggeredCharlieGroupConfigJoin': false,
          'charlieJoinMeasurementSource':
              'successful group fixture import after re-add',
          'receivedCharliePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm010',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm010-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterDuplicateReadd',
          'gm010-c-after',
          'charlie after duplicate readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterDuplicateReadd',
          'gm010-a-after',
          'alice after duplicate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterDuplicateReadd': 1,
        'aliceAfterDuplicateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm010DuplicateReaddProof': <String, Object?>{
          'memberListIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'charlieGroupConfigJoinCountAfterReadd': 1,
          'duplicateReaddTriggeredCharlieGroupConfigJoin': false,
          'charlieJoinMeasurementSource':
              'successful group fixture import after re-add',
          'receivedCharliePostReaddMessage': true,
          'receivedAlicePostReaddMessage': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm010',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm010-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterDuplicateReadd',
          'messageId': 'gm010-c-after',
          'text': 'charlie after duplicate readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterDuplicateReadd',
          'gm010-a-after',
          'alice after duplicate readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterDuplicateReadd': 1,
      },
      extra: const <String, Object?>{
        'gm010DuplicateReaddProof': <String, Object?>{
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'charlieGroupConfigJoinCountAfterReadd': 1,
          'duplicateReaddTriggeredCharlieGroupConfigJoin': false,
          'charlieJoinMeasurementSource':
              'successful group fixture import after re-add',
          'postReaddPublishAccepted': true,
          'receivedAlicePostReaddMessage': true,
          'removedWindowPlaintextCount': 0,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm011Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm011',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm011-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterStaleAdd',
          'messageId': 'gm011-a-after',
          'text': 'alice after stale add',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterStaleAdd',
          'gm011-b-after',
          'bob after stale add',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobAfterStaleAdd': 1},
      extra: const <String, Object?>{
        'gm011StaleAddRemovalProof': <String, Object?>{
          'appliedRemoveVersion3': true,
          'deliveredStaleAddVersion2': true,
          'staleAddIgnored': true,
          'staleConfigIncludedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'validatorConfigExcludesCharlie': true,
          'sentAlicePostStaleAdd': true,
          'receivedBobPostStaleAdd': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm011',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm011-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterStaleAdd',
          'messageId': 'gm011-b-after',
          'text': 'bob after stale add',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleAdd',
          'gm011-a-after',
          'alice after stale add',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterStaleAdd': 1},
      extra: const <String, Object?>{
        'gm011StaleAddRemovalProof': <String, Object?>{
          'appliedRemoveVersion3': true,
          'deliveredStaleAddVersion2': true,
          'staleAddIgnored': true,
          'staleConfigIncludedCharlie': true,
          'memberListExcludesCharlie': true,
          'validatorConfigExcludesCharlie': true,
          'sentBobPostStaleAdd': true,
          'receivedAlicePostStaleAdd': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm011',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm011-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterStaleAdd',
          'messageId': 'gm011-c-after',
          'text': 'charlie after stale add',
          'outcome': 'groupNotFound',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 0,
        },
      ],
      receivedMessages: const <Map<String, Object?>>[],
      persistedMessageCounts: const <String, int>{},
      extra: const <String, Object?>{
        'gm011StaleAddRemovalProof': <String, Object?>{
          'deliveredStaleAddVersion2': true,
          'groupPresentAfterStaleAdd': false,
          'currentMemberAfterStaleAdd': false,
          'hasOldKeyAfterStaleAdd': false,
          'hasRotatedEpoch': false,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAlicePostStaleAdd': false,
          'receivedBobPostStaleAdd': false,
          'postRemovalPlaintextCount': 0,
          'finalEpoch': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm012Verdicts() {
  const currentMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm012',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm012-group',
      memberPeerIds: currentMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterStaleRemove',
          'messageId': 'gm012-a-after',
          'text': 'alice after stale remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterStaleRemove',
          'gm012-c-after',
          'charlie after stale remove',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterStaleRemove',
          'gm012-b-after',
          'bob after stale remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterStaleRemove': 1,
        'bobAfterStaleRemove': 1,
      },
      extra: const <String, Object?>{
        'gm012StaleRemoveReaddProof': <String, Object?>{
          'appliedRemoveVersion2': true,
          'appliedReaddVersion3': true,
          'deliveredStaleRemoveVersion2': true,
          'staleRemoveIgnored': true,
          'removedPeerId': 'charlie-peer',
          'memberListIncludesCharlie': true,
          'validatorConfigIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'sentAlicePostStaleRemove': true,
          'receivedCharliePostStaleRemove': true,
          'receivedBobPostStaleRemove': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm012',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm012-group',
      memberPeerIds: currentMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterStaleRemove',
          'messageId': 'gm012-b-after',
          'text': 'bob after stale remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleRemove',
          'gm012-a-after',
          'alice after stale remove',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterStaleRemove',
          'gm012-c-after',
          'charlie after stale remove',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleRemove': 1,
        'charlieAfterStaleRemove': 1,
      },
      extra: const <String, Object?>{
        'gm012StaleRemoveReaddProof': <String, Object?>{
          'deliveredStaleRemoveVersion2': true,
          'staleRemoveIgnored': true,
          'memberListIncludesCharlie': true,
          'validatorConfigIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'sentBobPostStaleRemove': true,
          'receivedAlicePostStaleRemove': true,
          'receivedCharliePostStaleRemove': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm012',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm012-group',
      memberPeerIds: currentMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterStaleRemove',
          'messageId': 'gm012-c-after',
          'text': 'charlie after stale remove',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleRemove',
          'gm012-a-after',
          'alice after stale remove',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobAfterStaleRemove',
          'gm012-b-after',
          'bob after stale remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleRemove': 1,
        'bobAfterStaleRemove': 1,
      },
      extra: const <String, Object?>{
        'gm012StaleRemoveReaddProof': <String, Object?>{
          'deliveredStaleRemoveVersion2': true,
          'staleRemoveIgnored': true,
          'memberListIncludesCharlie': true,
          'validatorConfigIncludesCharlie': true,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'groupPresentAfterStaleRemove': true,
          'currentMemberAfterStaleRemove': true,
          'postReaddPublishAccepted': true,
          'sentCharliePostStaleRemove': true,
          'receivedAlicePostStaleRemove': true,
          'receivedBobPostStaleRemove': true,
          'hasStaleEpochAfterStaleRemove': false,
          'removedWindowPlaintextCount': 0,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm013Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const cutoffAt = '2026-04-05T12:00:00.000Z';
  const beforeAt = '2026-04-05T11:59:59.999Z';
  const afterAt = '2026-04-05T12:00:00.000Z';
  const remainingProof = <String, Object?>{
    'removalCutoffAt': cutoffAt,
    'beforeSentAt': beforeAt,
    'afterSentAt': afterAt,
    'acceptedBeforeCutoff': true,
    'beforeCutoffPersistedCount': 1,
    'rejectedAfterCutoff': true,
    'afterCutoffAccepted': false,
    'afterCutoffPersistedCount': 0,
    'clearAfterCutoffRejectionEvent': true,
    'afterCutoffRejectionReason':
        'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
    'memberListExcludesCharlie': true,
    'validatorConfigExcludesCharlie': true,
    'finalEpoch': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm013',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm013-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterCharlieRemove',
          'messageId': 'gm013-a-after',
          'text': 'alice after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieBeforeCutoff',
          'gm013-c-before',
          'charlie before cutoff',
          'charlie-peer',
          keyEpoch: 1,
        ),
        _received(
          'bobAfterCharlieRemove',
          'gm013-b-after',
          'bob after charlie remove',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieBeforeCutoff': 1,
        'bobAfterCharlieRemove': 1,
      },
      extra: const <String, Object?>{
        'gm013SimultaneousRemoveSendProof': <String, Object?>{
          ...remainingProof,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'sentAlicePostRemoval': true,
          'receivedBobPostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm013',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm013-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterCharlieRemove',
          'messageId': 'gm013-b-after',
          'text': 'bob after charlie remove',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['alice-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieBeforeCutoff',
          'gm013-c-before',
          'charlie before cutoff',
          'charlie-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceAfterCharlieRemove',
          'gm013-a-after',
          'alice after charlie remove',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieBeforeCutoff': 1,
        'aliceAfterCharlieRemove': 1,
      },
      extra: const <String, Object?>{
        'gm013SimultaneousRemoveSendProof': <String, Object?>{
          ...remainingProof,
          'receivedAlicePostRemoval': true,
          'sentBobPostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm013',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm013-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieBeforeCutoff',
          'messageId': 'gm013-c-before',
          'text': 'charlie before cutoff',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
        {
          'key': 'charlieAfterCharlieRemove',
          'messageId': 'gm013-c-after-remove',
          'text': 'charlie after charlie remove',
          'outcome': 'groupNotFound',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 0,
        },
      ],
      receivedMessages: const <Map<String, Object?>>[],
      persistedMessageCounts: const <String, int>{},
      extra: const <String, Object?>{
        'gm013SimultaneousRemoveSendProof': <String, Object?>{
          'currentMemberBeforeRemoval': true,
          'startedOldEpochPublishBeforeRemoval': true,
          'groupPresentAfterRemoval': false,
          'currentMemberAfterRemoval': false,
          'hasRotatedEpoch': false,
          'postRemovalSendOutcome': 'groupNotFound',
          'postRemovalPublishAccepted': false,
          'receivedAlicePostRemoval': false,
          'receivedBobPostRemoval': false,
          'postRemovalPlaintextCount': 0,
          'finalEpoch': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm014Verdicts() {
  const allMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const readdAt = '2026-04-05T12:00:10.000Z';
  const sendAt = '2026-04-05T12:00:11.000Z';
  const sharedProof = <String, Object?>{
    'readdAt': readdAt,
    'charlieJoinedAt': readdAt,
    'alicePostReaddSentAt': sendAt,
    'memberListIncludesCharlie': true,
    'validatorConfigIncludesCharlie': true,
    'hasStaleEpochAfterCatchUp': false,
    'finalEpoch': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm014',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm014-group',
      memberPeerIds: allMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterReadd',
          'messageId': 'gm014-a-after',
          'text': 'alice after readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
          'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
        },
      ],
      persistedMessageCounts: const <String, int>{},
      extra: const <String, Object?>{
        'gm014SimultaneousReaddSendProof': <String, Object?>{
          ...sharedProof,
          'readdedCharlie': true,
          'readdedPeerId': 'charlie-peer',
          'sentAlicePostReadd': true,
          'receivedBobPostReadd': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm014',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm014-group',
      memberPeerIds: allMembers,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterReadd',
          'gm014-a-after',
          'alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterReadd': 1},
      extra: const <String, Object?>{
        'gm014SimultaneousReaddSendProof': <String, Object?>{
          ...sharedProof,
          'receivedAlicePostReadd': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm014',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm014-group',
      memberPeerIds: allMembers,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterReadd',
          'gm014-a-after',
          'alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'aliceAfterReadd': 1},
      extra: const <String, Object?>{
        'gm014SimultaneousReaddSendProof': <String, Object?>{
          ...sharedProof,
          'delayedKeyOrConfig': true,
          'repairSignalRecorded': true,
          'directPostReaddDecrypt': false,
          'caughtUpPostReaddMessage': true,
          'postReaddPersistedCount': 1,
          'removedWindowPlaintextCount': 0,
          'charlieMemberRowCount': 1,
          'charlieActiveDeviceBindingCount': 1,
          'duplicateTopicJoins': false,
          'duplicateDurableRecipients': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm015Verdicts() {
  const allMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const sharedProof = <String, Object?>{
    'groupPresent': true,
    'groupDissolved': false,
    'creatorPeerId': 'alice-peer',
    'finalMemberPeerIds': allMembers,
    'adminPeerIds': <String>['alice-peer'],
    'memberListHasActiveAdmin': true,
    'mutationAfterBlockedAttempt': false,
    'keyEpochUnchanged': true,
    'initialKeyEpoch': 1,
    'finalKeyEpoch': 1,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm015',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm015-group',
      memberPeerIds: allMembers,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterBlockedAdminSelfRemoval',
          'gm015-b-after',
          'bob after blocked admin self-removal',
          'bob-peer',
          keyEpoch: 1,
        ),
        _received(
          'charlieAfterBlockedAdminLeave',
          'gm015-c-after',
          'charlie after blocked admin leave',
          'charlie-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterBlockedAdminSelfRemoval': 1,
        'charlieAfterBlockedAdminLeave': 1,
      },
      extra: const <String, Object?>{
        'gm015AdminSelfRemovalPolicyProof': <String, Object?>{
          ...sharedProof,
          'selfRemovalOutcome': 'blocked',
          'selfRemovalReason':
              "You can't remove the last admin from this group.",
          'voluntaryLeaveBroadcastOutcome': 'skipped',
          'voluntaryLeaveBroadcastSkipReason': 'lastAdmin',
          'leaveOutcome': 'blocked',
          'leaveReason':
              "You can't leave this group because you're the only admin.",
          'receivedBobPostAttemptSend': true,
          'receivedCharliePostAttemptSend': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm015',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm015-group',
      memberPeerIds: allMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'bobAfterBlockedAdminSelfRemoval',
          'messageId': 'gm015-b-after',
          'text': 'bob after blocked admin self-removal',
          'outcome': 'success',
          'senderPeerId': 'bob-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterBlockedAdminLeave',
          'gm015-c-after',
          'charlie after blocked admin leave',
          'charlie-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterBlockedAdminLeave': 1,
      },
      extra: const <String, Object?>{
        'gm015AdminSelfRemovalPolicyProof': <String, Object?>{
          ...sharedProof,
          'sentBobPostAttemptSend': true,
          'receivedCharliePostAttemptSend': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm015',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm015-group',
      memberPeerIds: allMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterBlockedAdminLeave',
          'messageId': 'gm015-c-after',
          'text': 'charlie after blocked admin leave',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobAfterBlockedAdminSelfRemoval',
          'gm015-b-after',
          'bob after blocked admin self-removal',
          'bob-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'bobAfterBlockedAdminSelfRemoval': 1,
      },
      extra: const <String, Object?>{
        'gm015AdminSelfRemovalPolicyProof': <String, Object?>{
          ...sharedProof,
          'receivedBobPostAttemptSend': true,
          'sentCharliePostAttemptSend': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm016Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const proofName = 'gm016RemovedUnsubscribeProof';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm016',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm016-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterCharlieUnsubscribe',
          'messageId': 'gm016-a-after',
          'text': 'alice after unsubscribe',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'charlieOnlineBeforeRemoval': true,
          'removedCharlie': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'sentAlicePostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm016',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm016-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterCharlieUnsubscribe',
          'gm016-a-after',
          'alice after unsubscribe',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterCharlieUnsubscribe': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'memberListExcludesCharlie': true,
          'receivedAlicePostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm016',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm016-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'activeMemberBeforeRemoval': true,
          'leaveRequested': true,
          'leaveResponseOk': true,
          'groupPresentAfterRemoval': false,
          'groupRecreatedAfterQuietWindow': false,
          'receivedAlicePostRemoval': false,
          'memberRowsAfterRemoval': 0,
          'keyEpochAfterRemoval': 0,
          'postLeaveGroupJoinCount': 0,
          'postLeaveInboundEventCount': 0,
          'postLeaveReactionEventCount': 0,
          'postLeaveDiscoveryEventCount': 0,
          'postLeavePayloadParseFailedCount': 0,
          'postLeaveDecryptionFailedCount': 0,
          'postRemovalPlaintextCount': 0,
          'postLeaveQuietWindowMs': 5000,
          'staleDiscoveryRegisterStimulus': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm017Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const staleMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'gm017StaleSubscriptionValidationProof';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm017',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm017-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterStaleCharlieReject',
          'messageId': 'gm017-a-after',
          'text': 'alice after stale reject',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlieFromLocalConfig': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'validationRejected': true,
          'validationRejectCount': 1,
          'validationRejectReason': 'non_member',
          'receivedStaleCharliePlaintext': false,
          'stalePlaintextCount': 0,
          'sentAliceHealthyAfterReject': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm017',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm017-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleCharlieReject',
          'gm017-a-after',
          'alice after stale reject',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleCharlieReject': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'installedConfigWithoutCharlie': true,
          'memberListExcludesCharlie': true,
          'validationRejected': true,
          'validationRejectCount': 1,
          'validationRejectReason': 'bad_signature_or_epoch',
          'receivedStaleCharliePlaintext': false,
          'stalePlaintextCount': 0,
          'receivedAliceHealthyAfterReject': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm017',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm017-group',
      memberPeerIds: staleMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieStaleAfterRemoval',
          'messageId': 'gm017-c-stale',
          'text': 'stale charlie after removal',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'groupPresentAfterRemoval': true,
          'keyPresentAfterRemoval': true,
          'memberListStillIncludesCharlie': true,
          'staleSubscriptionPresent': true,
          'sentStaleMarker': true,
          'stalePublishAccepted': true,
          'leaveRequested': false,
          'leaveResponseOk': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGo003Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const staleMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'go003SenderValidationFeedbackProof';
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'go003',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'go003-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceAfterStaleCharlieReject',
          'messageId': 'go003-a-after',
          'text': 'alice after stale reject',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlieFromLocalConfig': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'validationRejected': true,
          'validationRejectCount': 1,
          'validationRejectReason': 'non_member',
          'receivedStaleCharliePlaintext': false,
          'stalePlaintextCount': 0,
          'sentAliceHealthyAfterReject': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'go003',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'go003-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterStaleCharlieReject',
          'go003-a-after',
          'alice after stale reject',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterStaleCharlieReject': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'installedConfigWithoutCharlie': true,
          'memberListExcludesCharlie': true,
          'validationRejected': true,
          'validationRejectCount': 1,
          'validationRejectReason': 'bad_signature_or_epoch',
          'receivedStaleCharliePlaintext': false,
          'stalePlaintextCount': 0,
          'receivedAliceHealthyAfterReject': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'go003',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'go003-group',
      memberPeerIds: staleMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieStaleAfterRemoval',
          'messageId': 'go003-c-stale',
          'text': 'stale charlie after removal',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'groupPresentAfterRemoval': true,
          'keyPresentAfterRemoval': true,
          'memberListStillIncludesCharlie': true,
          'staleSubscriptionPresent': true,
          'sentStaleMarker': true,
          'stalePublishAccepted': true,
          'senderValidationFeedbackReceived': true,
          'senderValidationFeedbackMessageId': 'go003-c-stale',
          'senderValidationFeedbackReason': 'non_member',
          'senderValidationFeedbackKeyEpoch': 1,
          'senderStatusAfterFeedback': 'failed',
          'senderWireEnvelopeRetryableAfterFeedback': true,
          'senderInboxStoredAfterFeedback': true,
          'leaveRequested': false,
          'leaveResponseOk': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm018Verdicts() {
  const remainingMembers = <String>['alice-peer', 'bob-peer'];
  const staleMembers = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const proofName = 'gm018RemainingDeliveryContinuityProof';
  const sentMessages = <Map<String, Object?>>[
    {
      'key': 'aliceGm018Live1',
      'messageId': 'gm018-live-1',
      'text': 'gm018 live 1',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018Live2',
      'messageId': 'gm018-live-2',
      'text': 'gm018 live 2',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018Live3',
      'messageId': 'gm018-live-3',
      'text': 'gm018 live 3',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018Inbox1',
      'messageId': 'gm018-inbox-1',
      'text': 'gm018 inbox 1',
      'outcome': 'successNoPeers',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018Inbox2',
      'messageId': 'gm018-inbox-2',
      'text': 'gm018 inbox 2',
      'outcome': 'successNoPeers',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018Inbox3',
      'messageId': 'gm018-inbox-3',
      'text': 'gm018 inbox 3',
      'outcome': 'successNoPeers',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
    {
      'key': 'aliceGm018AfterCharlieOffline',
      'messageId': 'gm018-after-offline',
      'text': 'gm018 after charlie offline',
      'outcome': 'success',
      'senderPeerId': 'alice-peer',
      'keyEpoch': 2,
      'recipientPeerIds': <String>['bob-peer'],
    },
  ];
  final bobReceivedMessages = <Map<String, Object?>>[
    for (final sent in sentMessages)
      _received(
        sent['key']! as String,
        sent['messageId']! as String,
        sent['text']! as String,
        'alice-peer',
        keyEpoch: 2,
      ),
  ];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm018',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm018-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      sentMessages: sentMessages,
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'removedCharlieFromLocalConfig': true,
          'removedPeerId': 'charlie-peer',
          'memberListExcludesCharlie': true,
          'staleOnlinePressureObserved': true,
          'charlieOfflinePressureObserved': true,
          'bobOfflineProofObserved': true,
          'inboxSentAfterBobOffline': true,
          'allDurableRecipientsBobOnly': true,
          'liveSequenceSentCount': 3,
          'inboxSequenceSentCount': 3,
          'liveSequenceMessageIds': <String>[
            'gm018-live-1',
            'gm018-live-2',
            'gm018-live-3',
          ],
          'inboxSequenceMessageIds': <String>[
            'gm018-inbox-1',
            'gm018-inbox-2',
            'gm018-inbox-3',
          ],
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm018',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm018-group',
      memberPeerIds: remainingMembers,
      keyEpoch: 2,
      receivedMessages: bobReceivedMessages,
      persistedMessageCounts: const <String, int>{
        'aliceGm018Live1': 1,
        'aliceGm018Live2': 1,
        'aliceGm018Live3': 1,
        'aliceGm018Inbox1': 1,
        'aliceGm018Inbox2': 1,
        'aliceGm018Inbox3': 1,
        'aliceGm018AfterCharlieOffline': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'memberListExcludesCharlie': true,
          'staleOnlinePressureRejected': true,
          'staleOfflinePressureSurvived': true,
          'exactOnceDelivery': true,
          'bobOfflineBeforeInboxSend': true,
          'bobRestartedBeforeInboxDrain': true,
          'inboxReplayDrainedFromDurableInbox': true,
          'inboxLiveLeakCountBeforeReplay': 0,
          'inboxReplayDrainMessageCount': 3,
          'liveBobReceiptCount': 3,
          'liveBobReceiptMessageIds': <String>[
            'gm018-live-1',
            'gm018-live-2',
            'gm018-live-3',
          ],
          'inboxReplayReceiptCount': 3,
          'inboxReplayMessageIds': <String>[
            'gm018-inbox-1',
            'gm018-inbox-2',
            'gm018-inbox-3',
          ],
          'inboxReplayReceiptKeys': <String>[
            'aliceGm018Inbox1',
            'aliceGm018Inbox2',
            'aliceGm018Inbox3',
          ],
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm018',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm018-group',
      memberPeerIds: staleMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieGm018StaleOnline',
          'messageId': 'gm018-charlie-stale',
          'text': 'gm018 stale charlie',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 1,
          'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
        },
      ],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'groupPresentAfterRemoval': true,
          'keyPresentAfterRemoval': true,
          'memberListStillIncludesCharlie': true,
          'staleOnlinePressureSent': true,
          'staleOfflineOrRestartPressure': true,
          'receivedPostRemovalPlaintext': false,
          'postRemovalPlaintextCount': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm019Verdicts() {
  const proofName = 'gm019DurableRecipientWindowProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const aliceRemoved = <String, Object?>{
    'key': 'aliceGm019RemovedWindow',
    'messageId': 'gm019-removed-window',
    'text': 'gm019 removed window',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceAfter = <String, Object?>{
    'key': 'aliceGm019AfterReadd',
    'messageId': 'gm019-alice-after',
    'text': 'gm019 alice after readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobAfter = <String, Object?>{
    'key': 'bobGm019AfterReadd',
    'messageId': 'gm019-bob-after',
    'text': 'gm019 bob after readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm019',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm019-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceRemoved, aliceAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGm019AfterReadd',
          'gm019-bob-after',
          'gm019 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobGm019AfterReadd': 1},
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'actualDurablePayloadProof': true,
          'removedPeerId': 'charlie-peer',
          'removedAt': '2026-05-11T08:00:00.000Z',
          'removedWindowSentAt': '2026-05-11T08:01:00.000Z',
          'readdAt': '2026-05-11T08:05:00.000Z',
          'postReaddSentAt': '2026-05-11T08:06:00.000Z',
          'removedWindowExcludedCharlie': true,
          'postReaddIncludedCharlie': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm019',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm019-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm019RemovedWindow',
          'gm019-removed-window',
          'gm019 removed window',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm019AfterReadd',
          'gm019-alice-after',
          'gm019 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm019RemovedWindow': 1,
        'aliceGm019AfterReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'actualDurablePayloadProof': true,
          'bobPostReaddSent': true,
          'receivedAliceRemovedWindow': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm019',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm019-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm019AfterReadd',
          'gm019-alice-after',
          'gm019 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm019AfterReadd',
          'gm019-bob-after',
          'gm019 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm019AfterReadd': 1,
        'bobGm019AfterReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'receivedRemovedWindowMessage': false,
          'removedWindowPlaintextCount': 0,
          'receivedAlicePostReadd': true,
          'receivedBobPostReadd': true,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm020Verdicts() {
  const proofName = 'gm020ImmediateRecipientExclusionProof';
  const activeMembers = <String>['alice-peer', 'bob-peer'];
  const postRemovalKeys = <String>[
    'aliceGm020ImmediatePostRemoval',
    'aliceGm020OfflinePostRemoval',
  ];
  const aliceImmediate = <String, Object?>{
    'key': 'aliceGm020ImmediatePostRemoval',
    'messageId': 'gm020-immediate',
    'text': 'gm020 immediate',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceOffline = <String, Object?>{
    'key': 'aliceGm020OfflinePostRemoval',
    'messageId': 'gm020-offline',
    'text': 'gm020 offline',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm020',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm020-group',
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceImmediate, aliceOffline],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'actualDurablePayloadProof': true,
          'removedPeerId': 'charlie-peer',
          'removedAt': '2026-05-11T08:00:00.000Z',
          'firstPostRemovalSentAt': '2026-05-11T08:00:01.000Z',
          'offlinePostRemovalSentAt': '2026-05-11T08:00:05.000Z',
          'postRemovalMessageCount': 2,
          'postRemovalMessageKeys': postRemovalKeys,
          'everyPostRemovalExcludedCharlie': true,
          'charlieUnavailableBeforeOfflinePostRemoval': true,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm020',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm020-group',
      memberPeerIds: activeMembers,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm020ImmediatePostRemoval',
          'gm020-immediate',
          'gm020 immediate',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm020OfflinePostRemoval',
          'gm020-offline',
          'gm020 offline',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm020ImmediatePostRemoval': 1,
        'aliceGm020OfflinePostRemoval': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'receivedEveryPostRemovalMessage': true,
          'postRemovalReceiptCount': 2,
          'postRemovalMessageKeys': postRemovalKeys,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm020',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm020-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          'receivedPostRemovalPlaintext': false,
          'postRemovalPlaintextCount': 0,
          'unavailableBeforeOfflinePostRemoval': true,
          'checkedPostRemovalMessageKeys': postRemovalKeys,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm021Verdicts() {
  const proofName = 'gm021FreshReaddPackageProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const activeKeyPackageIds = <String>[
    'kp-alice',
    'kp-bob',
    'kp-charlie-fresh',
  ];
  const sharedProof = <String, Object?>{
    'oldDeviceId': 'charlie-device',
    'freshDeviceId': 'charlie-device',
    'oldKeyPackageId': 'kp-charlie-old',
    'freshKeyPackageId': 'kp-charlie-fresh',
    'activeConfigContainsFreshPackage': true,
    'oldRemovedPackageAbsentFromActiveConfig': true,
    'activeConfigKeyPackageIds': activeKeyPackageIds,
  };
  const charlieFresh = <String, Object?>{
    'key': 'charlieGm021FreshAfterReadd',
    'messageId': 'gm021-fresh',
    'text': 'gm021 fresh after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'senderDeviceId': 'charlie-device',
    'senderKeyPackageId': 'kp-charlie-fresh',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm021',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm021FreshAfterReadd',
          'gm021-fresh',
          'gm021 fresh after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm021FreshAfterReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          ...sharedProof,
          'removedCharlie': true,
          'readdedCharlie': true,
          'removedAt': '2026-05-11T08:00:00.000Z',
          'readdAt': '2026-05-11T08:05:00.000Z',
          'receivedFreshCharlieMessage': true,
          'receivedStaleSameActiveDevicePlaintext': false,
          'staleSameActiveDevicePlaintextCount': 0,
          'receivedStaleFullOldDevicePlaintext': false,
          'staleFullOldDevicePlaintextCount': 0,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm021',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm021FreshAfterReadd',
          'gm021-fresh',
          'gm021 fresh after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm021FreshAfterReadd': 1,
      },
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          ...sharedProof,
          'receivedFreshCharlieMessage': true,
          'receivedStaleSameActiveDevicePlaintext': false,
          'staleSameActiveDevicePlaintextCount': 0,
          'receivedStaleFullOldDevicePlaintext': false,
          'staleFullOldDevicePlaintextCount': 0,
        },
      },
    ),
    _baseVerdict(
      scenario: 'gm021',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm021-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieFresh],
      extra: const <String, Object?>{
        proofName: <String, Object?>{
          ...sharedProof,
          'freshPostReaddPublishAccepted': true,
          'freshSendUsedFreshKeyPackage': true,
          'sameActiveDeviceStaleKeyPackageRejected': true,
          'sameActiveDeviceStaleKeyPackageAccepted': false,
          'sameActiveDeviceStaleKeyPackageRejectionReason': 'unbound_device',
          'fullOldDevicePackageRejected': false,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validGm022Verdicts() {
  const proofName = 'gm022RepeatedReaddDedupProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const sharedProof = <String, Object?>{
    'removeReaddCycleCount': 20,
    'rawMemberPeerIds': members,
    'configMemberPeerIds': members,
    'duplicateMemberPeerIds': <String>[],
    'charlieMemberEntryCount': 1,
    'activeCharlieEntryCount': 1,
    'activeCharlieDeviceCount': 1,
    'validatorUsedActiveEntry': true,
    'freshCharlieSendAccepted': true,
    'staleShadowSendAccepted': false,
    'postCycleDeliveryStable': true,
    'durableRecipientsUnique': true,
  };
  const charlieSend = <String, Object?>{
    'key': 'charlieGm022AfterReadd',
    'messageId': 'gm022-charlie-after',
    'text': 'gm022 charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceSend = <String, Object?>{
    'key': 'aliceGm022AfterReadd',
    'messageId': 'gm022-alice-after',
    'text': 'gm022 alice after readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobSend = <String, Object?>{
    'key': 'bobGm022AfterReadd',
    'messageId': 'gm022-bob-after',
    'text': 'gm022 bob after readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm022',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm022-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm022AfterReadd',
          'gm022-charlie-after',
          'gm022 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm022AfterReadd',
          'gm022-bob-after',
          'gm022 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm022AfterReadd': 1,
        'bobGm022AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm022',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm022-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm022AfterReadd',
          'gm022-charlie-after',
          'gm022 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm022AfterReadd',
          'gm022-alice-after',
          'gm022 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm022AfterReadd': 1,
        'aliceGm022AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm022',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm022-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm022AfterReadd',
          'gm022-alice-after',
          'gm022 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm022AfterReadd',
          'gm022-bob-after',
          'gm022 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm022AfterReadd': 1,
        'bobGm022AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGm023Verdicts() {
  const proofName = 'gm023InactiveShadowProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const sharedProof = <String, Object?>{
    'inactiveShadowBeforeActive': true,
    'duplicateConfigRejected': false,
    'activeEntrySelected': true,
    'freshCharlieSendAccepted': true,
    'staleInactiveShadowSendAccepted': false,
    'discoveryUsedActiveEntry': true,
    'inactiveShadowDialedOrCounted': false,
    'postShadowDeliveryStable': true,
    'durableRecipientsUnique': true,
    'charlieMemberEntryCount': 1,
    'activeCharlieEntryCount': 1,
    'activeCharlieDeviceCount': 1,
    'rawMemberPeerIds': members,
    'configMemberPeerIds': members,
  };
  const charlieSend = <String, Object?>{
    'key': 'charlieGm023AfterInactiveShadow',
    'messageId': 'gm023-charlie-after',
    'text': 'gm023 charlie after inactive shadow',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceSend = <String, Object?>{
    'key': 'aliceGm023AfterInactiveShadow',
    'messageId': 'gm023-alice-after',
    'text': 'gm023 alice after inactive shadow',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobSend = <String, Object?>{
    'key': 'bobGm023AfterInactiveShadow',
    'messageId': 'gm023-bob-after',
    'text': 'gm023 bob after inactive shadow',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm023',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm023-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm023AfterInactiveShadow',
          'gm023-charlie-after',
          'gm023 charlie after inactive shadow',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm023AfterInactiveShadow',
          'gm023-bob-after',
          'gm023 bob after inactive shadow',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm023AfterInactiveShadow': 1,
        'bobGm023AfterInactiveShadow': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm023',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm023-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm023AfterInactiveShadow',
          'gm023-charlie-after',
          'gm023 charlie after inactive shadow',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm023AfterInactiveShadow',
          'gm023-alice-after',
          'gm023 alice after inactive shadow',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm023AfterInactiveShadow': 1,
        'aliceGm023AfterInactiveShadow': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm023',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm023-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm023AfterInactiveShadow',
          'gm023-alice-after',
          'gm023 alice after inactive shadow',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm023AfterInactiveShadow',
          'gm023-bob-after',
          'gm023 bob after inactive shadow',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm023AfterInactiveShadow': 1,
        'bobGm023AfterInactiveShadow': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGm024Verdicts() {
  const proofName = 'gm024MemberDisplayStateProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const sharedProof = <String, Object?>{
    'rawMemberPeerIds': members,
    'configMemberPeerIds': members,
    'charlieMemberEntryCount': 1,
    'activeCharlieEntryCount': 1,
    'activeCharlieDeviceCount': 1,
    'charlieRole': 'writer',
    'charlieJoinedStatus': 'joined',
    'charlieCurrentStatus': 'current',
    'activeTransportIdentity': 'charlie-device',
    'activeTransportPeerIds': <String>['charlie-device'],
    'keyEpoch': 2,
    'composeSendPermission': true,
    'topicJoined': true,
    'livePublishAccepted': true,
    'liveTopicPeerState': 'joined_with_peers',
    'liveTopicPeerCount': 2,
    'actualSendKeys': <String>[
      'aliceGm024AfterReadd',
      'bobGm024AfterReadd',
      'charlieGm024AfterReadd',
    ],
    'exactOnceDelivery': true,
    'durableRecipientsUnique': true,
  };
  const charlieSend = <String, Object?>{
    'key': 'charlieGm024AfterReadd',
    'messageId': 'gm024-charlie-after',
    'text': 'gm024 charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'senderDeviceId': 'charlie-device',
    'transportPeerId': 'charlie-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };
  const aliceSend = <String, Object?>{
    'key': 'aliceGm024AfterReadd',
    'messageId': 'gm024-alice-after',
    'text': 'gm024 alice after readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };
  const bobSend = <String, Object?>{
    'key': 'bobGm024AfterReadd',
    'messageId': 'gm024-bob-after',
    'text': 'gm024 bob after readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device',
    'transportPeerId': 'bob-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm024',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm024-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm024AfterReadd',
          'gm024-charlie-after',
          'gm024 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm024AfterReadd',
          'gm024-bob-after',
          'gm024 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm024AfterReadd': 1,
        'bobGm024AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm024',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm024-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm024AfterReadd',
          'gm024-charlie-after',
          'gm024 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm024AfterReadd',
          'gm024-alice-after',
          'gm024 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm024AfterReadd': 1,
        'aliceGm024AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm024',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm024-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm024AfterReadd',
          'gm024-alice-after',
          'gm024 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm024AfterReadd',
          'gm024-bob-after',
          'gm024 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm024AfterReadd': 1,
        'bobGm024AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGm025Verdicts() {
  const proofName = 'gm025RolePermissionReaddProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const sharedProof = <String, Object?>{
    'rawMemberPeerIds': members,
    'configMemberPeerIds': members,
    'charlieMemberEntryCount': 1,
    'configCharlieMemberEntryCount': 1,
    'oldCharlieRole': 'writer',
    'oldRemoveMembersAllowed': true,
    'readdedCharlieRole': 'writer',
    'readdedRemoveMembersAllowed': false,
    'staleRemoveMembersAllowedAfterReadd': false,
    'bridgeConfigCurrentRoleProof': true,
    'bridgeConfigCurrentPermissionProof': true,
    'staleActionAttempted': true,
    'staleActionAccepted': false,
    'actualActionOutcome': 'denied',
    'bobStillMemberAfterAction': true,
    'aliceStillSeesBobAfterAction': true,
    'actionTombstonePersisted': false,
    'liveTopicPeerCount': 2,
    'actualSendKeys': <String>[
      'aliceGm025AfterReadd',
      'bobGm025AfterReadd',
      'charlieGm025AfterReadd',
      'charlieDeniedRemoveMembersAction',
    ],
  };
  const charlieSend = <String, Object?>{
    'key': 'charlieGm025AfterReadd',
    'messageId': 'gm025-charlie-after',
    'text': 'gm025 charlie after readd',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'senderDeviceId': 'charlie-device',
    'transportPeerId': 'charlie-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };
  const charlieDeniedAction = <String, Object?>{
    'key': 'charlieDeniedRemoveMembersAction',
    'messageId': 'gm025-charlie-denied-action',
    'text': '{"__sys":"member_banned"}',
    'outcome': 'success',
    'senderPeerId': 'charlie-peer',
    'senderDeviceId': 'charlie-device',
    'transportPeerId': 'charlie-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };
  const aliceSend = <String, Object?>{
    'key': 'aliceGm025AfterReadd',
    'messageId': 'gm025-alice-after',
    'text': 'gm025 alice after readd',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };
  const bobSend = <String, Object?>{
    'key': 'bobGm025AfterReadd',
    'messageId': 'gm025-bob-after',
    'text': 'gm025 bob after readd',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device',
    'transportPeerId': 'bob-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
    'actualTopicPeerProof': true,
    'topicPeers': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm025',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm025-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[aliceSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm025AfterReadd',
          'gm025-charlie-after',
          'gm025 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm025AfterReadd',
          'gm025-bob-after',
          'gm025 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm025AfterReadd': 1,
        'bobGm025AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm025',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm025-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobSend],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm025AfterReadd',
          'gm025-charlie-after',
          'gm025 charlie after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceGm025AfterReadd',
          'gm025-alice-after',
          'gm025 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm025AfterReadd': 1,
        'aliceGm025AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
    _baseVerdict(
      scenario: 'gm025',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm025-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        charlieSend,
        charlieDeniedAction,
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm025AfterReadd',
          'gm025-alice-after',
          'gm025 alice after readd',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm025AfterReadd',
          'gm025-bob-after',
          'gm025 bob after readd',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm025AfterReadd': 1,
        'bobGm025AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: sharedProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGm033Verdicts() {
  const proofName = 'gm033ReplayDuringMembershipUpdateProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const aliceBefore = <String, Object?>{
    'key': 'aliceGm033BeforeRemoval',
    'messageId': 'gm033-before',
    'text': 'gm033 before',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceRemovedWindow = <String, Object?>{
    'key': 'aliceGm033RemovedWindow',
    'messageId': 'gm033-removed',
    'text': 'gm033 removed',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceAfter = <String, Object?>{
    'key': 'aliceGm033AfterReadd',
    'messageId': 'gm033-after',
    'text': 'gm033 after',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobAfter = <String, Object?>{
    'key': 'bobGm033AfterReadd',
    'messageId': 'gm033-bob-after',
    'text': 'gm033 bob after',
    'outcome': 'success',
    'senderPeerId': 'bob-peer',
    'senderDeviceId': 'bob-device',
    'transportPeerId': 'bob-device',
    'keyEpoch': 2,
    'recipientPeerIds': <String>['alice-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceProof = <String, Object?>{
    'actualDurablePayloadProof': true,
    'replayStartedBeforeRemoval': true,
    'staleRemovedWindowStoredForCharlie': true,
    'removedWindowNormalRecipientsExcludedCharlie': true,
    'postReaddIncludedCharlie': true,
    'removedPeerId': 'charlie-peer',
    'replayStartedAt': '2026-05-11T12:00:00.000Z',
    'removedAt': '2026-05-11T12:01:00.000Z',
    'removedWindowSentAt': '2026-05-11T12:02:00.000Z',
    'staleStoredAt': '2026-05-11T12:02:30.000Z',
    'readdAt': '2026-05-11T12:03:00.000Z',
    'postReaddSentAt': '2026-05-11T12:04:00.000Z',
  };
  const bobProof = <String, Object?>{
    'receivedBeforeRemoval': true,
    'receivedRemovedWindow': true,
    'receivedAlicePostReadd': true,
    'bobPostReaddSent': true,
  };
  const charlieProof = <String, Object?>{
    'replayStarted': true,
    'replayResumed': true,
    'receivedBeforeRemoval': true,
    'receivedAlicePostReadd': true,
    'receivedBobPostReadd': true,
    'postReaddExactOnce': true,
    'receivedRemovedWindowMessage': false,
    'removedWindowMessageIdPersisted': false,
    'removedWindowPlaintextCount': 0,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm033',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm033-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        aliceBefore,
        aliceRemovedWindow,
        aliceAfter,
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'bobGm033AfterReadd',
          'gm033-bob-after',
          'gm033 bob after',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{'bobGm033AfterReadd': 1},
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'gm033',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm033-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[bobAfter],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm033BeforeRemoval',
          'gm033-before',
          'gm033 before',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGm033RemovedWindow',
          'gm033-removed',
          'gm033 removed',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGm033AfterReadd',
          'gm033-after',
          'gm033 after',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm033BeforeRemoval': 1,
        'aliceGm033RemovedWindow': 1,
        'aliceGm033AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'gm033',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm033-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm033BeforeRemoval',
          'gm033-before',
          'gm033 before',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGm033AfterReadd',
          'gm033-after',
          'gm033 after',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'bobGm033AfterReadd',
          'gm033-bob-after',
          'gm033 bob after',
          'bob-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm033BeforeRemoval': 1,
        'aliceGm033AfterReadd': 1,
        'bobGm033AfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: charlieProof},
    ),
  ];
}

List<Map<String, dynamic>> _validGm034Verdicts() {
  const proofName = 'gm034ConfigUpdateReceiveOrderProof';
  const finalMembers = <String>['alice-peer', 'bob-peer'];
  const aliceMessageThenConfig = <String, Object?>{
    'key': 'aliceGm034MessageThenConfig',
    'messageId': 'gm034-message-then-config',
    'text': 'gm034 message then config',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'timestamp': '2026-05-11T12:00:00.000Z',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer', 'charlie-peer'],
    'actualDurablePayloadProof': true,
  };
  const aliceConfigThenMessage = <String, Object?>{
    'key': 'aliceGm034ConfigThenMessage',
    'messageId': 'gm034-config-then-message',
    'text': 'gm034 config then message',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'senderDeviceId': 'alice-device',
    'transportPeerId': 'alice-device',
    'timestamp': '2026-05-11T12:02:00.000Z',
    'keyEpoch': 1,
    'recipientPeerIds': <String>['bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const bobProof = <String, Object?>{
    'orderCases': <String>['message_then_config', 'config_then_message'],
    'receivedMessageIds': <String>[
      'gm034-message-then-config',
      'gm034-config-then-message',
    ],
    'receivedTexts': <String>[
      'gm034 message then config',
      'gm034 config then message',
    ],
    'removedPeerId': 'charlie-peer',
    'removedAt': '2026-05-11T12:01:00.000Z',
    'messageThenConfigReceivedAt': '2026-05-11T12:00:00.000Z',
    'configThenMessageReceivedAt': '2026-05-11T12:02:00.000Z',
    'lastMembershipEventAt': '2026-05-11T12:01:00.000Z',
    'messageThenConfigBeforeRemoval': true,
    'configThenMessageAfterRemoval': true,
    'messageThenConfigPersistedCount': 1,
    'configThenMessagePersistedCount': 1,
    'messageThenConfigExactOnce': true,
    'configThenMessageExactOnce': true,
    'noDuplicateMessageIds': true,
    'membershipTimelineRemovedCount': 1,
    'deterministicMembershipTimeline': true,
    'finalMemberPeerIds': finalMembers,
    'finalConfigMemberPeerIds': finalMembers,
    'deterministicConfigState': true,
    'validAliceMessagesSurvived': true,
    'sentMessageIds': <String>[
      'gm034-message-then-config',
      'gm034-config-then-message',
    ],
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm034',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm034-group',
      memberPeerIds: finalMembers,
      keyEpoch: 1,
      sentMessages: const <Map<String, Object?>>[
        aliceMessageThenConfig,
        aliceConfigThenMessage,
      ],
    ),
    _baseVerdict(
      scenario: 'gm034',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm034-group',
      memberPeerIds: finalMembers,
      keyEpoch: 1,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceGm034MessageThenConfig',
          'gm034-message-then-config',
          'gm034 message then config',
          'alice-peer',
          keyEpoch: 1,
        ),
        _received(
          'aliceGm034ConfigThenMessage',
          'gm034-config-then-message',
          'gm034 config then message',
          'alice-peer',
          keyEpoch: 1,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceGm034MessageThenConfig': 1,
        'aliceGm034ConfigThenMessage': 1,
      },
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'gm034',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm034-group',
      memberPeerIds: const <String>[],
      keyEpoch: 0,
    ),
  ];
}

List<Map<String, dynamic>> _validRa011LateLeaveReaddVerdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'private_late_leave_readd',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ra011-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRemoval',
          'messageId': 'ra011-a-during',
          'text': 'alice during charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterImmediateReadd',
          'messageId': 'ra011-a-after',
          'text': 'alice after late leave readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterImmediateReadd',
          'ra011-c-after',
          'charlie after late leave repair',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra011LateLeaveReaddProof': <String, Object?>{
          'rowId': 'RA-011',
          'removedCharlie': true,
          'observedCharlieLeaveStartedBeforeReadd': true,
          'readdedCharlieBeforeLateLeaveCompleted': true,
          'receivedCharliePostLateLeaveRepair': true,
          'memberListIncludesCharlie': true,
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'private_late_leave_readd',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ra011-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRemoval',
          'ra011-a-during',
          'alice during charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterImmediateReadd',
          'ra011-c-after',
          'charlie after late leave repair',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterImmediateReadd',
          'ra011-a-after',
          'alice after late leave readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRemoval': 1,
        'charlieAfterImmediateReadd': 1,
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra011LateLeaveReaddProof': <String, Object?>{
          'rowId': 'RA-011',
          'observedCharlieRemoved': true,
          'observedCharlieReadded': true,
          'receivedAlicePostLateLeaveRepair': true,
          'receivedCharliePostLateLeaveRepair': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
      },
    ),
    _baseVerdict(
      scenario: 'private_late_leave_readd',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ra011-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterImmediateReadd',
          'messageId': 'ra011-c-after',
          'text': 'charlie after late leave repair',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterImmediateReadd',
          'ra011-a-after',
          'alice after late leave readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra011LateLeaveReaddProof': <String, Object?>{
          'rowId': 'RA-011',
          'leaveStartedBeforeReadd': true,
          'importedReaddBeforeLateLeaveCompleted': true,
          'lateLeaveRepairJoinCompleted': true,
          'postReaddPublishAccepted': true,
          'receivedAlicePostLateLeaveRepair': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validRa012RotatedDeviceReaddVerdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const oldMlKem = 'old-charlie-mlkem';
  const rotatedMlKem = 'rotated-charlie-mlkem';
  const oldKeyPackage = 'old-charlie-key-package';
  const rotatedKeyPackage = 'rotated-charlie-key-package';
  const commonMaterial = <String, Object?>{
    'samePeerIdReadded': true,
    'oldMlKemPublicKey': oldMlKem,
    'rotatedMlKemPublicKey': rotatedMlKem,
    'oldKeyPackageId': oldKeyPackage,
    'rotatedKeyPackageId': rotatedKeyPackage,
    'memberConfigUsesRotatedDeviceMaterial': true,
    'oldDeviceMaterialRetained': false,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'private_rotated_device_readd',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'ra012-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringCharlieRemoval',
          'messageId': 'ra012-a-during',
          'text': 'alice during charlie removal',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
        {
          'key': 'aliceAfterImmediateReadd',
          'messageId': 'ra012-a-after',
          'text': 'alice after rotated device readd',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieAfterImmediateReadd',
          'ra012-c-after',
          'charlie after rotated device readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra012RotatedDeviceReaddProof': <String, Object?>{
          'rowId': 'RA-012',
          'removedCharlie': true,
          'readdedCharlieWithRotatedMaterial': true,
          'receivedCharliePostRotatedReadd': true,
          'memberListIncludesCharlie': true,
          'removedPeerId': 'charlie-peer',
          'finalEpoch': 2,
          ...commonMaterial,
        },
      },
    ),
    _baseVerdict(
      scenario: 'private_rotated_device_readd',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'ra012-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringCharlieRemoval',
          'ra012-a-during',
          'alice during charlie removal',
          'alice-peer',
          keyEpoch: 2,
        ),
        _received(
          'charlieAfterImmediateReadd',
          'ra012-c-after',
          'charlie after rotated device readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterImmediateReadd',
          'ra012-a-after',
          'alice after rotated device readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringCharlieRemoval': 1,
        'charlieAfterImmediateReadd': 1,
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra012RotatedDeviceReaddProof': <String, Object?>{
          'rowId': 'RA-012',
          'observedCharlieRemoved': true,
          'observedCharlieReaddedWithRotatedMaterial': true,
          'receivedAlicePostRotatedReadd': true,
          'receivedCharliePostRotatedReadd': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
          ...commonMaterial,
        },
      },
    ),
    _baseVerdict(
      scenario: 'private_rotated_device_readd',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'ra012-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieAfterImmediateReadd',
          'messageId': 'ra012-c-after',
          'text': 'charlie after rotated device readd',
          'outcome': 'success',
          'senderPeerId': 'charlie-peer',
          'keyEpoch': 2,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterImmediateReadd',
          'ra012-a-after',
          'alice after rotated device readd',
          'alice-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterImmediateReadd': 1,
      },
      extra: const <String, Object?>{
        'ra012RotatedDeviceReaddProof': <String, Object?>{
          'rowId': 'RA-012',
          'importedRotatedMaterial': true,
          'postRotatedReaddPublishAccepted': true,
          'receivedAlicePostRotatedReadd': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'finalEpoch': 2,
          ...commonMaterial,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validRa013SameUserMultiDeviceReaddVerdicts() {
  const scenario = 'private_same_user_multi_device_readd';
  const groupId = 'ra013-group';
  const alicePeerId = 'alice-peer';
  const bobPeerId = 'bob-peer';
  const charliePeerId = 'charlie-peer';
  const danaPeerId = 'dana-peer';
  const phoneDeviceId = 'charlie-phone-device';
  const tabletDeviceId = 'charlie-tablet-device';
  const members = <String>[alicePeerId, bobPeerId, charliePeerId];
  const common = <String, Object?>{
    'rowId': 'RA-013',
    'sameAccountPeerId': charliePeerId,
    'phoneDeviceId': phoneDeviceId,
    'tabletDeviceId': tabletDeviceId,
    'distinctDeviceIds': true,
    'finalEpoch': 2,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: scenario,
      role: 'alice',
      peerId: alicePeerId,
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceDuringRa013Removal',
          'messageId': 'ra013-a-removed',
          'groupId': groupId,
          'text': 'RA-013 Alice during Charlie removal',
          'outcome': 'success',
          'senderPeerId': alicePeerId,
          'keyEpoch': 2,
          'accepted': true,
        },
        {
          'key': 'aliceAfterRa013PhoneAccept',
          'messageId': 'ra013-a-phone',
          'groupId': groupId,
          'text': 'RA-013 Alice after phone accept',
          'outcome': 'success',
          'senderPeerId': alicePeerId,
          'keyEpoch': 2,
          'accepted': true,
        },
        {
          'key': 'aliceAfterRa013TabletAccept',
          'messageId': 'ra013-a-tablet',
          'groupId': groupId,
          'text': 'RA-013 Alice after tablet accept',
          'outcome': 'success',
          'senderPeerId': alicePeerId,
          'keyEpoch': 2,
          'accepted': true,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieTabletAfterRa013Accept',
          'ra013-c2-post',
          'RA-013 Charlie tablet after own accept',
          charliePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieTabletAfterRa013Accept': 1,
      },
      extra: const <String, Object?>{
        'ra013SameUserMultiDeviceReaddProof': <String, Object?>{
          ...common,
          'removedCharlie': true,
          'readdedCharlieWithTwoDevices': true,
          'phoneAcceptedBeforeTablet': true,
          'tabletPendingWhilePhoneJoined': true,
          'sentRemovedWindowMessage': true,
          'sentPostPhoneAcceptMessage': true,
          'sentPostTabletAcceptMessage': true,
          'receivedTabletPostAcceptMessage': true,
          'removedWindowRecipientExcludedTablet': true,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'bob',
      peerId: bobPeerId,
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceDuringRa013Removal',
          'ra013-a-removed',
          'RA-013 Alice during Charlie removal',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterRa013PhoneAccept',
          'ra013-a-phone',
          'RA-013 Alice after phone accept',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterRa013TabletAccept',
          'ra013-a-tablet',
          'RA-013 Alice after tablet accept',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
        _received(
          'charlieTabletAfterRa013Accept',
          'ra013-c2-post',
          'RA-013 Charlie tablet after own accept',
          charliePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceDuringRa013Removal': 1,
        'aliceAfterRa013PhoneAccept': 1,
        'aliceAfterRa013TabletAccept': 1,
        'charlieTabletAfterRa013Accept': 1,
      },
      extra: const <String, Object?>{
        'ra013SameUserMultiDeviceReaddProof': <String, Object?>{
          ...common,
          'observedCharlieRemoved': true,
          'observedCharlieReaddedWithTwoDevices': true,
          'receivedRemovedWindowAsActiveMember': true,
          'receivedPostPhoneAccept': true,
          'receivedPostTabletAccept': true,
          'receivedTabletDevicePostAccept': true,
          'memberListIncludesCharlie': true,
          'memberListIncludesDanaAccount': false,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'charlie',
      peerId: charliePeerId,
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterRa013PhoneAccept',
          'ra013-a-phone',
          'RA-013 Alice after phone accept',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
        _received(
          'aliceAfterRa013TabletAccept',
          'ra013-a-tablet',
          'RA-013 Alice after tablet accept',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterRa013PhoneAccept': 1,
        'aliceAfterRa013TabletAccept': 1,
      },
      extra: const <String, Object?>{
        'ra013SameUserMultiDeviceReaddProof': <String, Object?>{
          ...common,
          'phoneAcceptedOwnInvite': true,
          'tabletDeviceInMemberConfig': true,
          'receivedPostPhoneAccept': true,
          'receivedPostTabletAccept': true,
          'memberListIncludesAliceBob': true,
          'memberListIncludesCharlie': true,
          'removedWindowPlaintextCount': 0,
        },
      },
    ),
    _baseVerdict(
      scenario: scenario,
      role: 'dana',
      peerId: danaPeerId,
      groupId: groupId,
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'charlieTabletAfterRa013Accept',
          'messageId': 'ra013-c2-post',
          'groupId': groupId,
          'text': 'RA-013 Charlie tablet after own accept',
          'outcome': 'success',
          'senderPeerId': charliePeerId,
          'senderDeviceId': tabletDeviceId,
          'transportRolePeerId': danaPeerId,
          'keyEpoch': 2,
          'accepted': true,
        },
      ],
      receivedMessages: <Map<String, Object?>>[
        _received(
          'aliceAfterRa013TabletAccept',
          'ra013-a-tablet',
          'RA-013 Alice after tablet accept',
          alicePeerId,
          groupId: groupId,
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'aliceAfterRa013TabletAccept': 1,
      },
      extra: const <String, Object?>{
        'ra013SameUserMultiDeviceReaddProof': <String, Object?>{
          ...common,
          'actualRolePeerId': danaPeerId,
          'tabletPendingBeforeOwnAccept': true,
          'groupAbsentBeforeOwnAccept': true,
          'tabletAcceptedAfterPhone': true,
          'receivedPostTabletAccept': true,
          'sentTabletDevicePostAccept': true,
          'memberListIncludesDanaAccount': false,
          'tabletDeviceInMemberConfig': true,
          'preAcceptPlaintextCount': 0,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPrivateReaddAlternatingChurnVerdicts() {
  const scenario = 'private_readd_alternating_churn';
  const groupId = 'private-readd-alternating-churn-group';
  const peerIdsByRole = <String, String>{
    'alice': 'alice-peer',
    'bob': 'bob-peer',
    'charlie': 'charlie-peer',
    'dana': 'dana-peer',
  };
  const members = <String>[
    'alice-peer',
    'bob-peer',
    'charlie-peer',
    'dana-peer',
  ];
  final sentByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };
  final receivedByRole = <String, List<Map<String, Object?>>>{
    for (final role in peerIdsByRole.keys) role: <Map<String, Object?>>[],
  };
  final intervals = <Map<String, Object?>>[];

  void addMessage({
    required int cycle,
    required String operation,
    required String churnTarget,
    required String senderRole,
    required List<String> activeRoles,
    required List<String> receiverRoles,
    required int keyEpoch,
  }) {
    final key = _ra018KeyForTest(cycle, operation, senderRole);
    final messageId = 'ra018-c$cycle-$operation-$senderRole';
    final text =
        'RA-018 cycle $cycle $operation from ${_titleRoleForTest(senderRole)}';
    intervals.add(<String, Object?>{
      'cycle': cycle,
      'operation': operation,
      'churnTarget': churnTarget,
      'sender': senderRole,
      'activeRoles': activeRoles,
      'receiverRoles': receiverRoles,
      'key': key,
    });
    sentByRole[senderRole]!.add(<String, Object?>{
      'key': key,
      'messageId': messageId,
      'text': text,
      'outcome': 'success',
      'senderPeerId': peerIdsByRole[senderRole],
      'keyEpoch': keyEpoch,
    });
    for (final receiverRole in receiverRoles) {
      receivedByRole[receiverRole]!.add(
        _received(
          key,
          messageId,
          text,
          peerIdsByRole[senderRole]!,
          keyEpoch: keyEpoch,
        ),
      );
    }
  }

  for (var cycle = 1; cycle <= 3; cycle++) {
    final epochBase = (cycle - 1) * 4 + 1;
    addMessage(
      cycle: cycle,
      operation: 'charlieRemoved',
      churnTarget: 'charlie',
      senderRole: 'alice',
      activeRoles: const <String>['alice', 'bob', 'dana'],
      receiverRoles: const <String>['bob', 'dana'],
      keyEpoch: epochBase + 1,
    );
    addMessage(
      cycle: cycle,
      operation: 'charlieReadded',
      churnTarget: 'charlie',
      senderRole: 'bob',
      activeRoles: const <String>['alice', 'bob', 'charlie', 'dana'],
      receiverRoles: const <String>['alice', 'charlie', 'dana'],
      keyEpoch: epochBase + 2,
    );
    addMessage(
      cycle: cycle,
      operation: 'danaRemoved',
      churnTarget: 'dana',
      senderRole: 'charlie',
      activeRoles: const <String>['alice', 'bob', 'charlie'],
      receiverRoles: const <String>['alice', 'bob'],
      keyEpoch: epochBase + 3,
    );
    addMessage(
      cycle: cycle,
      operation: 'danaReadded',
      churnTarget: 'dana',
      senderRole: 'dana',
      activeRoles: const <String>['alice', 'bob', 'charlie', 'dana'],
      receiverRoles: const <String>['alice', 'bob', 'charlie'],
      keyEpoch: epochBase + 4,
    );
  }

  Map<String, int> countsFor(String role) => <String, int>{
    for (final message in receivedByRole[role]!) message['key'] as String: 1,
  };

  Map<String, Object?> proofForRole(String role) => <String, Object?>{
    'rowId': 'RA-018',
    'churnCycles': 3,
    'churnTargets': const <String>['charlie', 'dana'],
    'activeSenders': const <String>['alice', 'bob', 'charlie', 'dana'],
    'activeReceivers': const <String>['alice', 'bob', 'charlie', 'dana'],
    'activeIntervals': intervals,
    'charlieRemovedWindowPlaintextCount': 0,
    'danaRemovedWindowPlaintextCount': 0,
    'duplicateVisibleMessageCount': 0,
    'inactiveSenderAttemptCount': 0,
    'finalRoles': const <String>['alice', 'bob', 'charlie', 'dana'],
    'finalMemberListConverged': true,
    'finalEpoch': 13,
    'finalEpochConverged': true,
    'proofRole': role,
  };

  return <Map<String, dynamic>>[
    for (final role in const <String>['alice', 'bob', 'charlie', 'dana'])
      _baseVerdict(
        scenario: scenario,
        role: role,
        peerId: peerIdsByRole[role]!,
        groupId: groupId,
        memberPeerIds: members,
        keyEpoch: 13,
        sentMessages: sentByRole[role]!,
        receivedMessages: receivedByRole[role]!,
        persistedMessageCounts: countsFor(role),
        extra: <String, Object?>{
          'activeMemberPeerIds': members,
          'ra018AlternatingChurnProof': proofForRole(role),
        },
      ),
  ];
}

Map<String, dynamic> _withRa018ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'ra018AlternatingChurnProof': <String, Object?>{
      ...Map<String, Object?>.from(
        verdict['ra018AlternatingChurnProof'] as Map,
      ),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validPrivateNetworkChaosInvariantVerdicts() {
  return _validPrivateReaddAlternatingChurnVerdicts()
      .map((verdict) {
        final raProof = Map<String, Object?>.from(
          verdict['ra018AlternatingChurnProof'] as Map,
        );
        final nw014Proof = <String, Object?>{
          ...raProof,
          'rowId': 'NW-014',
          'scenario': 'private_network_chaos_invariants',
          'appPeerPlatform': 'ios_26_2_core_simulator',
          'chaosProofSource': 'app_peer_core_simulator_churn_invariant_subset',
          'fixedSeed': 14014,
          'modelInvariant': 'active_entitled_exactly_once',
          'messageOperationCount': 12,
          'membershipOperationCount': 12,
          'fakeNetworkChaosProofRequired': true,
        };
        return <String, dynamic>{
          ...verdict,
          'scenario': 'private_network_chaos_invariants',
          'nw014ChaosInvariantProof': nw014Proof,
        };
      })
      .toList(growable: false);
}

Map<String, dynamic> _withNw014ProofOverrides(
  Map<String, dynamic> verdict,
  Map<String, Object?> overrides,
) {
  return <String, dynamic>{
    ...verdict,
    'nw014ChaosInvariantProof': <String, Object?>{
      ...Map<String, Object?>.from(verdict['nw014ChaosInvariantProof'] as Map),
      ...overrides,
    },
  };
}

List<Map<String, dynamic>> _validGm035Verdicts() {
  const proofName = 'gm035ZeroPeerReaddFirstSendProof';
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const charlieFirst = <String, Object?>{
    'key': 'charlieGm035FirstAfterReadd',
    'messageId': 'gm035-charlie-first',
    'text': 'gm035 charlie first after readd',
    'outcome': 'successNoPeers',
    'senderPeerId': 'charlie-peer',
    'senderDeviceId': 'charlie-device',
    'transportPeerId': 'charlie-device',
    'timestamp': '2026-05-12T00:00:00.000Z',
    'keyEpoch': 2,
    'topicPeers': 0,
    'initialTopicPeers': 0,
    'actualTopicPeerProof': true,
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'actualDurablePayloadProof': true,
  };
  const charlieProof = <String, Object?>{
    'readdedCharlie': true,
    'aliceBobEligibleAtSend': true,
    'sentBeforeLiveDiscoveryCompleted': true,
    'successNoPeers': true,
    'actualDurablePayloadProof': true,
    'durableRecipientsUnique': true,
    'replayEnvelopeMessageIdMatches': true,
    'initialTopicPeers': 0,
    'keyEpoch': 2,
    'messageId': 'gm035-charlie-first',
    'recipientPeerIds': <String>['alice-peer', 'bob-peer'],
    'currentMemberPeerIds': members,
  };
  const aliceProof = <String, Object?>{
    'durableDrainCompleted': true,
    'receivedCharlieFirstSend': true,
    'liveDuplicateDelivered': true,
    'noDuplicatePersistence': true,
    'senderEligibleAtSend': true,
    'postDrainPersistedCount': 1,
    'postLiveDuplicatePersistedCount': 1,
    'receivedMessageId': 'gm035-charlie-first',
    'currentMemberPeerIds': members,
  };
  const bobProof = <String, Object?>{
    'durableDrainCompleted': true,
    'receivedCharlieFirstSend': true,
    'liveDuplicateDelivered': true,
    'noDuplicatePersistence': true,
    'senderEligibleAtSend': true,
    'postDrainPersistedCount': 1,
    'postLiveDuplicatePersistedCount': 1,
    'receivedMessageId': 'gm035-charlie-first',
    'currentMemberPeerIds': members,
  };

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm035',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm035-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm035FirstAfterReadd',
          'gm035-charlie-first',
          'gm035 charlie first after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm035FirstAfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: aliceProof},
    ),
    _baseVerdict(
      scenario: 'gm035',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm035-group',
      memberPeerIds: members,
      keyEpoch: 2,
      receivedMessages: <Map<String, Object?>>[
        _received(
          'charlieGm035FirstAfterReadd',
          'gm035-charlie-first',
          'gm035 charlie first after readd',
          'charlie-peer',
          keyEpoch: 2,
        ),
      ],
      persistedMessageCounts: const <String, int>{
        'charlieGm035FirstAfterReadd': 1,
      },
      extra: const <String, Object?>{proofName: bobProof},
    ),
    _baseVerdict(
      scenario: 'gm035',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm035-group',
      memberPeerIds: members,
      keyEpoch: 2,
      sentMessages: const <Map<String, Object?>>[charlieFirst],
      extra: const <String, Object?>{proofName: charlieProof},
    ),
  ];
}

String _ra017KeyForTest(int cycle, String phase, String senderRole) =>
    'ra017Cycle${cycle}_${phase}_$senderRole';

String _ra018KeyForTest(int cycle, String operation, String senderRole) =>
    'ra018Cycle${cycle}_${operation}_$senderRole';

String _titleRoleForTest(String role) {
  switch (role) {
    case 'alice':
      return 'Alice';
    case 'bob':
      return 'Bob';
    case 'charlie':
      return 'Charlie';
    case 'dana':
      return 'Dana';
    default:
      return role;
  }
}

List<Map<String, Object?>> _mapListForTest(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, Object?>.from(entry))
      .toList(growable: false);
}

List<Map<String, dynamic>> _validPl002Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'pl002-group';
  const key = 'alicePl002MediaOnly';
  const messageId = 'pl002-media-only-message';
  const media = <String, Object?>{
    'id': 'pl002-voice',
    'mime': 'audio/mp4',
    'mediaType': 'audio',
    'durationMs': 2200,
    'size': 4096,
  };
  const sent = <String, Object?>{
    'key': key,
    'messageId': messageId,
    'groupId': groupId,
    'text': '',
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'timestamp': '2026-05-14T18:04:00.000Z',
    'mediaCount': 1,
    'media': <Map<String, Object?>>[media],
  };

  Map<String, Object?> received({required bool live}) {
    return <String, Object?>{
      ..._received(
        key,
        messageId,
        '',
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-14T18:04:00.000Z',
        liveOnly: live,
        usedOfflineDrain: false,
      ),
      'persistedCount': 1,
      'mediaCount': 1,
      'media': <Map<String, Object?>>[media],
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'pl002',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[sent],
      extra: const <String, Object?>{
        'pl002MediaOnlyProof': <String, Object?>{
          'rowId': 'PL-002',
          'acceptedMediaOnly': true,
          'emptyTextPreserved': true,
          'mediaDescriptorPublished': true,
          'bobReceiptSignalObserved': true,
          'charlieReceiptSignalObserved': true,
          'mediaCount': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'pl002',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received(live: true)],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{
        'pl002MediaOnlyProof': <String, Object?>{
          'rowId': 'PL-002',
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'emptyTextPreserved': true,
          'mediaDescriptorPersisted': true,
          'mediaCount': 1,
        },
      },
    ),
    _baseVerdict(
      scenario: 'pl002',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received(live: true)],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{
        'pl002MediaOnlyProof': <String, Object?>{
          'rowId': 'PL-002',
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'emptyTextPreserved': true,
          'mediaDescriptorPersisted': true,
          'mediaCount': 1,
        },
      },
    ),
  ];
}

List<Map<String, dynamic>> _validPl012Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  const groupId = 'pl012-group';
  const key = 'alicePl012MediaVariants';
  const messageId = 'pl012-media-schema-message';
  const text = 'PL-012 schema variants test';
  const media = <Map<String, Object?>>[
    <String, Object?>{
      'id': 'pl012-image',
      'mime': 'image/jpeg',
      'mediaType': 'image',
      'width': 800,
      'height': 600,
      'size': 8192,
      'contentHash':
          '1111111111111111111111111111111111111111111111111111111111111111',
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    },
    <String, Object?>{
      'id': 'pl012-gif',
      'mime': 'image/gif',
      'mediaType': 'image',
      'width': 320,
      'height': 240,
      'size': 4096,
      'contentHash':
          '2222222222222222222222222222222222222222222222222222222222222222',
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    },
    <String, Object?>{
      'id': 'pl012-file',
      'mime': 'application/octet-stream',
      'mediaType': 'file',
      'size': 2048,
      'contentHash':
          '3333333333333333333333333333333333333333333333333333333333333333',
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    },
    <String, Object?>{
      'id': 'pl012-video',
      'mime': 'video/mp4',
      'mediaType': 'video',
      'width': 1280,
      'height': 720,
      'durationMs': 12000,
      'size': 32768,
      'contentHash':
          '4444444444444444444444444444444444444444444444444444444444444444',
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    },
    <String, Object?>{
      'id': 'pl012-voice',
      'mime': 'audio/mp4',
      'mediaType': 'audio',
      'durationMs': 3300,
      'waveform': <double>[0.1, 0.4, 0.2],
      'size': 6144,
      'contentHash':
          '5555555555555555555555555555555555555555555555555555555555555555',
      'hasEncryptionMetadata': true,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
    },
  ];
  const sent = <String, Object?>{
    'key': key,
    'messageId': messageId,
    'groupId': groupId,
    'text': text,
    'outcome': 'success',
    'senderPeerId': 'alice-peer',
    'keyEpoch': 1,
    'timestamp': '2026-05-16T03:04:00.000Z',
    'mediaCount': 5,
    'media': media,
  };

  Map<String, Object?> received({required bool live}) {
    return <String, Object?>{
      ..._received(
        key,
        messageId,
        text,
        'alice-peer',
        groupId: groupId,
        keyEpoch: 1,
        timestamp: '2026-05-16T03:04:00.000Z',
        liveOnly: live,
        usedOfflineDrain: false,
      ),
      'persistedCount': 1,
      'mediaCount': 5,
      'media': media,
    };
  }

  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'pl012',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: groupId,
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[sent],
      extra: const <String, Object?>{
        'pl012MediaSchemaProof': <String, Object?>{
          'rowId': 'PL-012',
          'acceptedVariantMessage': true,
          'mediaDescriptorPublished': true,
          'bobReceiptSignalObserved': true,
          'charlieReceiptSignalObserved': true,
          'mediaCount': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: 'pl012',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received(live: true)],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{
        'pl012MediaSchemaProof': <String, Object?>{
          'rowId': 'PL-012',
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'mediaDescriptorPersisted': true,
          'mediaCount': 5,
        },
      },
    ),
    _baseVerdict(
      scenario: 'pl012',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: groupId,
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[received(live: true)],
      persistedMessageCounts: const <String, int>{key: 1},
      extra: const <String, Object?>{
        'pl012MediaSchemaProof': <String, Object?>{
          'rowId': 'PL-012',
          'receivedVisibleMessageOnce': true,
          'matchedMessageId': true,
          'mediaDescriptorPersisted': true,
          'mediaCount': 5,
        },
      },
    ),
  ];
}

Map<String, dynamic> _baseVerdict({
  required String scenario,
  required String role,
  required String peerId,
  required String groupId,
  required List<String> memberPeerIds,
  int keyEpoch = 1,
  List<Map<String, Object?>> sentMessages = const <Map<String, Object?>>[],
  List<Map<String, Object?>> receivedMessages = const <Map<String, Object?>>[],
  Map<String, int> persistedMessageCounts = const <String, int>{},
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, dynamic>{
    'scenario': scenario,
    'role': role,
    'peerId': peerId,
    'groupId': groupId,
    'keyEpoch': keyEpoch,
    'relayLifecycleProof': true,
    'memberPeerIds': memberPeerIds,
    'sentMessages': sentMessages,
    'receivedMessages': receivedMessages,
    'persistedMessageCounts': persistedMessageCounts,
    ...extra,
  };
}

Map<String, Object?> _received(
  String key,
  String messageId,
  String text,
  String senderPeerId, {
  String? groupId,
  int? keyEpoch,
  String? timestamp,
  String? quotedMessageId,
  bool? liveOnly,
  bool? usedOfflineDrain,
}) {
  return <String, Object?>{
    'key': key,
    ...?groupId == null ? null : <String, Object?>{'groupId': groupId},
    'messageId': messageId,
    'text': text,
    'senderPeerId': senderPeerId,
    ...?keyEpoch == null ? null : <String, Object?>{'keyEpoch': keyEpoch},
    ...?timestamp == null ? null : <String, Object?>{'timestamp': timestamp},
    ...?quotedMessageId == null
        ? null
        : <String, Object?>{'quotedMessageId': quotedMessageId},
    'isIncoming': true,
    ...?liveOnly == null ? null : <String, Object?>{'liveOnly': liveOnly},
    ...?usedOfflineDrain == null
        ? null
        : <String, Object?>{'usedOfflineDrain': usedOfflineDrain},
  };
}
