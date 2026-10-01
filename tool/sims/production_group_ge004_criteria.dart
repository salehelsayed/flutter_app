import 'production_catalog_case.dart';

const _keys = {
  'alice': 'aliceGe004PostReadd',
  'bob': 'bobGe004PostReadd',
  'charlie': 'charlieGe004PostReadd',
};

/// Texts of catalog `ge004`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe004Texts(String run) => {
  'aliceGe004PostReadd': (
    role: 'alice',
    text: 'GE-004 Alice after Charlie re-add $run',
  ),
  'bobGe004PostReadd': (role: 'bob', text: 'GE-004 Bob after Charlie re-add $run'),
  'charlieGe004PostReadd': (
    role: 'charlie',
    text: 'GE-004 Charlie after re-add $run',
  ),
};

const productionGe004Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-after-readd',
  'bob-after-readd',
  'charlie-after-readd',
];

List<String> validateProductionGroupGe004(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge004',
      flows: productionGe004Flows,
      verdicts: (c) {
        final charlie = '${c.peers['charlie']}';
        final removed = !c
            .members(c.stage('aliceRemoved', 'alice'))
            .contains(charlie);
        return [
          for (final role in const ['alice', 'bob', 'charlie'])
            () {
              final own = c.sent(role, _keys[role]!);
              final others = [
                for (final r in const ['alice', 'bob', 'charlie'])
                  if (r != role) _keys[r]!,
              ];
              final got = [for (final k in others) c.received(role, k)];
              final members = c.members(c.finalOf(role));
              return c.verdict(
                role,
                sent: [own],
                received: got,
                extra: {
                  'ge004ReaddExchangeProof': {
                    if (role == 'alice') ...{
                      'removedCharlie': removed,
                      'removedPeerId': charlie,
                      'readdedPeerId': charlie,
                    },
                    'readdedCharlie': members.contains(charlie),
                    'memberListIncludesAll': members.length == 3,
                    'actualDurablePayloadProof':
                        own?['actualDurablePayloadProof'] == true,
                    'actualLiveTopicPeerProof': false,
                    'postReaddSentCount': own == null ? 0 : 1,
                    'postReaddReceivedCount': got.whereType<Map>().length,
                    'postReaddSentKeys': [_keys[role]],
                    'postReaddReceivedKeys': others,
                    'finalMemberPeerIds': members.toList()..sort(),
                  },
                },
              );
            }(),
        ];
      },
    );
