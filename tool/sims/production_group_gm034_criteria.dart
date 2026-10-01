import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const productionGm034BeforeKey = 'aliceGm034MessageThenConfig';
const productionGm034AfterKey = 'aliceGm034ConfigThenMessage';

/// Texts of catalog `gm034`, identical to the original harness.
Map<String, String> productionGm034Texts(String run) => {
  productionGm034BeforeKey:
      'GM-034 Alice message before Charlie config update $run',
  productionGm034AfterKey:
      'GM-034 Alice message after Charlie config update $run',
};

const productionGm034Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-message-then-config',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-config-then-message',
];

const _keys = [productionGm034BeforeKey, productionGm034AfterKey];

List<String> validateProductionGroupGm034(Map<String, Object?> proof) {
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
      (proof['flows'] as List).join(',') == productionGm034Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm034' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    final removed = stage('aliceRemoved', 'alice');
    final removedAtText = removed['lastMembershipEventAt'] as String?;
    final removedAt = removedAtText == null
        ? null
        : DateTime.parse(removedAtText).toUtc();
    require(removedAt != null, 'Alice recorded the removal event time');
    require(
      !(removed['memberPeerIds'] as List).contains(charlie),
      'Alice removed Charlie',
    );
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final deliveries = (finals['alice']!['deliveries'] as List?) ?? const [];
    final sent = <String, Map<String, Object?>>{};
    final got = <String, Map<String, Object?>>{};
    for (final key in _keys) {
      final own = productionCatalogRows(finals['alice']!, key);
      require(
        own.length == 1 && own.single['isIncoming'] == false,
        'alice: own outgoing $key row',
      );
      if (own.isNotEmpty) {
        sent[key] = productionCatalogDurableSent(own.single, key, deliveries);
      }
      final rows = productionCatalogRows(stage('got:$key:bob', 'bob'), key);
      require(
        rows.length == 1 && rows.single['isIncoming'] == true,
        'bob: exactly one incoming $key row',
      );
      if (rows.isNotEmpty) {
        got[key] = productionCatalogReceived(
          rows.single,
          key,
          productionCatalogRows(finals['bob']!, key).length,
        );
      }
    }
    require(
      finals['charlie']!['selfMember'] == false,
      'Charlie applied his own removal',
    );
    if (failures.isNotEmpty) return failures;
    final bobFinal = finals['bob']!;
    DateTime at(String key) =>
        DateTime.parse(got[key]!['timestamp'] as String).toUtc();
    int count(String key) => got[key]!['persistedCount'] as int;
    final members = [for (final p in bobFinal['memberPeerIds'] as List) '$p']
      ..sort();
    final configMembers = [
      for (final p in (bobFinal['configMemberPeerIds'] as List?) ?? const [])
        '$p',
    ]..sort();
    final expected = {alice, bob};
    final removalIds = [
      for (final id in (bobFinal['memberRemovedTimelineIds'] as List?) ?? const [])
        '$id',
    ];
    final removalId =
        'sys-member_removed:${bobFinal['groupId']}:$charlie:$alice:'
        '${removedAt!.microsecondsSinceEpoch}';
    final timelineCount = removalIds.where((id) => id == removalId).length;
    final bobLast = bobFinal['lastMembershipEventAt'] as String?;
    final ids = [for (final k in _keys) got[k]!['messageId'] as String];
    final bobProof = {
      'orderCases': const ['message_then_config', 'config_then_message'],
      'receivedMessageIds': ids,
      'receivedTexts': [for (final k in _keys) got[k]!['text']],
      'removedPeerId': charlie,
      'removedAt': removedAt.toIso8601String(),
      'messageThenConfigReceivedAt': at(
        productionGm034BeforeKey,
      ).toIso8601String(),
      'configThenMessageReceivedAt': at(
        productionGm034AfterKey,
      ).toIso8601String(),
      'lastMembershipEventAt': bobLast,
      'messageThenConfigBeforeRemoval': at(
        productionGm034BeforeKey,
      ).isBefore(removedAt),
      'configThenMessageAfterRemoval': at(
        productionGm034AfterKey,
      ).isAfter(removedAt),
      'messageThenConfigPersistedCount': count(productionGm034BeforeKey),
      'configThenMessagePersistedCount': count(productionGm034AfterKey),
      'messageThenConfigExactOnce': count(productionGm034BeforeKey) == 1,
      'configThenMessageExactOnce': count(productionGm034AfterKey) == 1,
      'noDuplicateMessageIds': ids.toSet().length == ids.length,
      'membershipTimelineRemovedCount': timelineCount,
      'deterministicMembershipTimeline':
          timelineCount == 1 &&
          bobLast != null &&
          DateTime.parse(bobLast).toUtc().isAtSameMomentAs(removedAt),
      'finalMemberPeerIds': members,
      'finalConfigMemberPeerIds': configMembers,
      'deterministicConfigState':
          members.toSet().length == expected.length &&
          members.toSet().containsAll(expected) &&
          configMembers.toSet().length == expected.length &&
          configMembers.toSet().containsAll(expected),
      'validAliceMessagesSurvived':
          count(productionGm034BeforeKey) == 1 &&
          count(productionGm034AfterKey) == 1,
      'sentMessageIds': [for (final k in _keys) sent[k]!['messageId']],
    };
    final roleProof = <String, Map<String, Object?>>{
      'alice': {
        'removedPeerId': charlie,
        'removedAt': removedAt.toIso8601String(),
        'messageThenConfigSentBeforeRemoval': DateTime.parse(
          sent[productionGm034BeforeKey]!['timestamp'] as String,
        ).toUtc().isBefore(removedAt),
        'configThenMessageSentAfterRemoval': DateTime.parse(
          sent[productionGm034AfterKey]!['timestamp'] as String,
        ).toUtc().isAfter(removedAt),
      },
      'bob': bobProof,
      'charlie': {
        'selfRemovedByCharlieConfigUpdate':
            finals['charlie']!['selfMember'] == false,
      },
    };
    final verdicts = [
      for (final role in const ['alice', 'bob', 'charlie'])
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: 'gm034',
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': role == 'alice' ? [...sent.values] : const [],
          'receivedMessages': role == 'bob' ? [...got.values] : const [],
          'persistedMessageCounts': {
            if (role == 'bob')
              for (final g in got.values) '${g['key']}': g['persistedCount'],
          },
          'gm034ConfigUpdateReceiveOrderProof': roleProof[role],
        }),
    ];
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'gm034',
      relayAddresses: proof['relayAddresses'] as String,
      verdicts: verdicts,
    );
    if (!original.ok) failures.add(original.detail);
  } catch (error) {
    failures.add('malformed gm034 proof: ${error.runtimeType} $error');
  }
  return failures;
}
