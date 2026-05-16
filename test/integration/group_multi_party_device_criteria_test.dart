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

    test('accepts valid GM-001 A/B/C receiver persistence verdicts', () {
      final verdict = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm001',
        relayAddresses: expectedMultiPartyRelayAddresses,
        verdicts: _validGm001Verdicts(),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.detail, contains('gm001 verdicts valid'));
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
    ...?keyEpoch == null ? null : <String, Object?>{'keyEpoch': keyEpoch},
    'isIncoming': true,
  };
}
