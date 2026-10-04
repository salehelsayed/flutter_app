import 'production_catalog_case.dart';

const _proof = 'i01DissolveConvergenceProof';
const _scenario = 'private_online_dissolve_convergence';

/// Catalog `private_online_dissolve_convergence` sends no proof messages.
Map<String, ProductionCatalogText> productionDissolveTexts(String run) =>
    const {};

const productionDissolveFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-dissolve',
];

bool _dissolveRow(Map snapshot) =>
    ((snapshot['dissolveTimelineTexts'] as List?) ?? const []).any(
      (t) => '$t'.contains('dissolved the group') || '$t'.contains('group_dissolved'),
    );

/// I-01. With all three online, Alice dissolves the group from Group Info
/// (Dissolve Group, Dissolve). Her dissolve succeeds with a signed sender
/// binding, and every device ends with the group dissolved (read-only); Bob
/// and Charlie record the group-dissolved timeline row.
List<String> validateProductionGroupDissolve(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: _scenario,
      flows: productionDissolveFlows,
      verdicts: (c) {
        final binding = proof['aliceBinding'] as Map;
        Map<String, Object?> common(String role) {
          final end = c.finalOf(role);
          return {
            'rowId': 'I-01',
            'scenario': _scenario,
            'proofRole': role,
            'groupDissolvedLocally': end['isDissolved'] == true,
            // The composer is blocked on a dissolved group.
            'readOnlyAfterDissolve': end['isDissolved'] == true,
            'dissolveTimelineRowPresent': _dissolveRow(end),
          };
        }

        final events = (c.finalOf('alice')['flowEvents'] as List?) ?? const [];
        return [
          c.verdict(
            'alice',
            extra: {
              _proof: {
                ...common('alice'),
                'dissolveResultSuccess': events.any(
                  (e) => (e as Map)['event'] == 'GROUP_DISSOLVE_USE_CASE_SUCCESS',
                ),
                'actorBindingSigned':
                    binding['deviceIdPresent'] == true &&
                    binding['transportPeerIdPresent'] == true,
              },
            },
          ),
          for (final r in ['bob', 'charlie'])
            c.verdict(r, extra: {_proof: common(r)}),
        ];
      },
    );
