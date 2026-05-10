import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

void main() {
  group('group multi-party device criteria', () {
    test('scenario requirements map GM roles to device counts', () {
      expect(scenarioRequirement('gm001').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm001').requiredDeviceCount, 3);
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
      expect(scenarioRequirement('gm005').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm005').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm006').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm006').requiredDeviceCount, 3);
      expect(scenarioRequirement('gm007').roles, ['alice', 'bob', 'charlie']);
      expect(scenarioRequirement('gm007').requiredDeviceCount, 3);

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

    test('accepts valid GM-001 A/B/C receiver persistence verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm001Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm001 verdicts valid'));
    });

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

    test('accepts valid GM-007 history-boundary verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm007',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm007Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm007 verdicts valid'));
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

List<Map<String, dynamic>> _validGm001Verdicts() {
  const members = <String>['alice-peer', 'bob-peer', 'charlie-peer'];
  return <Map<String, dynamic>>[
    _baseVerdict(
      scenario: 'gm001',
      role: 'alice',
      peerId: 'alice-peer',
      groupId: 'gm001-group',
      memberPeerIds: members,
      sentMessages: const <Map<String, Object?>>[
        {
          'key': 'aliceInitial',
          'messageId': 'gm001-a1',
          'text': 'hello gm001',
          'outcome': 'success',
          'senderPeerId': 'alice-peer',
        },
      ],
    ),
    _baseVerdict(
      scenario: 'gm001',
      role: 'bob',
      peerId: 'bob-peer',
      groupId: 'gm001-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received('aliceInitial', 'gm001-a1', 'hello gm001', 'alice-peer'),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
    ),
    _baseVerdict(
      scenario: 'gm001',
      role: 'charlie',
      peerId: 'charlie-peer',
      groupId: 'gm001-group',
      memberPeerIds: members,
      receivedMessages: <Map<String, Object?>>[
        _received('aliceInitial', 'gm001-a1', 'hello gm001', 'alice-peer'),
      ],
      persistedMessageCounts: const <String, int>{'aliceInitial': 1},
    ),
  ];
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
  int? keyEpoch,
}) {
  return <String, Object?>{
    'key': key,
    'messageId': messageId,
    'text': text,
    'senderPeerId': senderPeerId,
    if (keyEpoch != null) 'keyEpoch': keyEpoch,
    'isIncoming': true,
  };
}
