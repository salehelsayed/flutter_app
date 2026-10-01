import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const productionGm016Key = 'aliceAfterCharlieUnsubscribe';

/// Text of catalog `gm016`, identical to the original harness.
String productionGm016Text(String run) =>
    'GM-016 Alice after Charlie unsubscribe $run';

const productionGm016Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-unsubscribe',
];

int _countSince(Map snapshot, int baseline, Set<String> names) =>
    ((snapshot['flowEvents'] as List?) ?? const [])
        .skip(baseline)
        .where((e) => e is Map && names.contains(e['event']))
        .length;

int _inbound(Map snapshot, String kind) =>
    ((snapshot['inbound'] as Map?)?[kind] as int?) ?? 0;

List<String> validateProductionGroupGm016(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    final alice = peers['alice'], bob = peers['bob'], charlie = peers['charlie'];
    require({alice, bob, charlie}.length == 3, 'three distinct peers');
    require(
      (proof['flows'] as List).join(',') == productionGm016Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm016' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();
    final before = stage('charlieBefore', 'charlie');
    final atRemoval = stage('charlieAtRemoval', 'charlie');
    final afterQuiet = stage('charlieAfterQuiet', 'charlie');
    final removed = stage('aliceRemoved', 'alice');
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final ownRows = productionCatalogRows(
      finals['alice']!,
      productionGm016Key,
    );
    require(
      ownRows.length == 1 && ownRows.single['isIncoming'] == false,
      'alice: own outgoing $productionGm016Key row',
    );
    final gotRows = productionCatalogRows(
      stage('got:$productionGm016Key:bob', 'bob'),
      productionGm016Key,
    );
    require(
      gotRows.length == 1 && gotRows.single['isIncoming'] == true,
      'bob: exactly one incoming $productionGm016Key row',
    );
    if (failures.isNotEmpty) return failures;
    final sent = productionCatalogDurableSent(
      ownRows.single,
      productionGm016Key,
      (finals['alice']!['deliveries'] as List?) ?? const [],
    );
    final received = productionCatalogReceived(
      gotRows.single,
      productionGm016Key,
      productionCatalogRows(finals['bob']!, productionGm016Key).length,
    );
    final charlieFinal = finals['charlie']!;
    final baseline = ((atRemoval['flowEvents'] as List?) ?? const []).length;
    final allEvents = ((charlieFinal['flowEvents'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final joins = _countSince(charlieFinal, baseline, {
      'GROUP_FL_BRIDGE_JOIN_REQUEST',
      'GROUP_FL_BRIDGE_JOIN_CONFIG_REQUEST',
    });
    final leak = productionCatalogRows(charlieFinal, productionGm016Key).length;
    final inboundMessages =
        _inbound(charlieFinal, 'message') - _inbound(atRemoval, 'message');
    final roleProof = <String, Map<String, Object?>>{
      'alice': {
        'charlieOnlineBeforeRemoval': before['relayReady'] == true,
        'removedCharlie': !members(removed).contains(charlie),
        'removedPeerId': charlie,
        'memberListExcludesCharlie': !members(
          finals['alice']!,
        ).contains(charlie),
        'sentAlicePostRemoval': sent['accepted'] == true,
      },
      'bob': {
        'memberListExcludesCharlie': !members(finals['bob']!).contains(charlie),
        'receivedAlicePostRemoval': true,
      },
      'charlie': {
        'activeMemberBeforeRemoval': before['selfMember'] == true,
        'leaveRequested': allEvents.any(
          (e) => e['event'] == 'GROUP_FL_BRIDGE_LEAVE_REQUEST',
        ),
        'leaveResponseOk': allEvents.any(
          (e) =>
              e['event'] == 'GROUP_FL_BRIDGE_LEAVE_RESPONSE' &&
              (e['details'] as Map?)?['severity'] == 'info',
        ),
        'groupPresentAfterRemoval': charlieFinal['groupPresent'] == true,
        'groupRecreatedAfterQuietWindow':
            afterQuiet['groupPresent'] == true && joins > 0,
        'receivedAlicePostRemoval': inboundMessages > 0 || leak > 0,
        'memberRowsAfterRemoval': members(charlieFinal).length,
        'keyEpochAfterRemoval': charlieFinal['keyEpoch'],
        'postLeaveGroupJoinCount': joins,
        'postLeaveInboundEventCount': inboundMessages,
        'postLeaveReactionEventCount':
            _inbound(charlieFinal, 'reaction') - _inbound(atRemoval, 'reaction'),
        'postLeaveDiscoveryEventCount': _countSince(charlieFinal, baseline, {
          'GROUP_DISCOVERY',
        }),
        'postLeavePayloadParseFailedCount': _countSince(
          charlieFinal,
          baseline,
          {'GROUP_PAYLOAD_PARSE_FAILED'},
        ),
        // The original counts GROUP_DECRYPTION_FAILED, which production no
        // longer emits; the count is kept for parity and is always zero.
        'postLeaveDecryptionFailedCount': _countSince(charlieFinal, baseline, {
          'GROUP_DECRYPTION_FAILED',
        }),
        'postRemovalPlaintextCount': leak,
        'postLeaveQuietWindowMs': proof['quietWindowMs'],
      },
    };
    final verdicts = [
      for (final role in const ['alice', 'bob', 'charlie'])
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: 'gm016',
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': role == 'alice' ? [sent] : const [],
          'receivedMessages': role == 'bob' ? [received] : const [],
          'persistedMessageCounts': {
            if (role == 'bob') productionGm016Key: received['persistedCount'],
          },
          'gm016RemovedUnsubscribeProof': roleProof[role],
        }),
    ];
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'gm016',
      relayAddresses: proof['relayAddresses'] as String,
      verdicts: verdicts,
    );
    if (!original.ok) failures.add(original.detail);
  } catch (error) {
    failures.add('malformed gm016 proof: ${error.runtimeType} $error');
  }
  return failures;
}
