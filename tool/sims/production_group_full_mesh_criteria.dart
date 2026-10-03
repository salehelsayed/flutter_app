import 'production_catalog_case.dart';

const _roles = ['alice', 'bob', 'charlie'];
const _keys = {
  'alice': 'aliceFullMesh',
  'bob': 'bobFullMesh',
  'charlie': 'charlieFullMesh',
};
const _proof = 'nw001FullMeshProof';

/// Texts of catalog `private_full_mesh_online` (NW-001), identical to the
/// original harness.
Map<String, ProductionCatalogText> productionFullMeshTexts(String run) => {
  'aliceFullMesh': (role: 'alice', text: 'NW-001 Alice full mesh $run'),
  'bobFullMesh': (role: 'bob', text: 'NW-001 Bob full mesh $run'),
  'charlieFullMesh': (role: 'charlie', text: 'NW-001 Charlie full mesh $run'),
};

const productionFullMeshFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-full-mesh',
  'bob-full-mesh',
  'charlie-full-mesh',
];

/// NW-001. All three members online: each sends once through the composer
/// with both others on the live topic (production `success`, `full_peers`,
/// at least two topic peers) and each other member stores the message once,
/// received live and never from the offline inbox.
List<String> validateProductionGroupFullMesh(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'private_full_mesh_online',
      flows: productionFullMeshFlows,
      verdicts: (c) {
        final sent = {for (final r in _roles) r: c.sentFanout(r, _keys[r]!)};
        Map<String, Object?>? received(String role, String key) {
          final got = c.received(role, key);
          if (got == null) return null;
          final live = c.live(role, key);
          return {...got, 'liveOnly': live, 'usedOfflineDrain': !live};
        }

        final receivedBy = {
          for (final r in _roles)
            r: [
              for (final s in _roles)
                if (s != r) received(r, _keys[s]!),
            ],
        };
        final topicPeers = {
          for (final r in _roles)
            if (sent[r]?['topicPeers'] case final int n) r: n,
        };
        // As the original's `_nw001FullMeshProof`, counted per sender.
        var successNoPeers = 0;
        var partial = 0;
        for (final r in _roles) {
          final n = topicPeers[r];
          if (n == null || n < 2) partial++;
          if (sent[r]?['outcome'] == 'successNoPeers') successNoPeers++;
          if (sent[r]?['liveFanoutState'] != 'full_peers') partial++;
        }
        return [
          for (final r in _roles)
            c.verdict(
              r,
              sent: [sent[r]],
              received: receivedBy[r]!,
              extra: {
                _proof: {
                  'rowId': 'NW-001',
                  'activeRoles': _roles,
                  'senderRoles': _roles,
                  'expectedReceiversPerMessage': 2,
                  'allRolePublishesCovered': sent.values.every(
                    (s) => s != null,
                  ),
                  'allActiveReceiversCovered':
                      receivedBy[r]!.length == 2 &&
                      receivedBy[r]!.every(
                        (m) =>
                            m != null &&
                            m['persistedCount'] == 1 &&
                            m['liveOnly'] == true &&
                            m['usedOfflineDrain'] == false,
                      ),
                  'duplicateVisibleMessageCount': receivedBy[r]!
                      .where((m) => ((m?['persistedCount'] as int?) ?? 0) > 1)
                      .length,
                  'successNoPeersCount': successNoPeers,
                  'partialPeerPublishCount': partial,
                  'topicPeerCountsBySender': topicPeers,
                },
              },
            ),
        ];
      },
    );
