import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_media_reaction_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _k = 'aliceMediaReactionTarget';
final _f = CatalogFixture(
  'private_media_reaction_roundtrip',
  productionMediaReactionTexts('run'),
  productionMediaReactionFlows,
);

Map<String, Object?> _row({required bool incoming}) => {
  ..._f.row(_k, incoming: incoming),
  'mediaAttachmentCount': 1,
};

Map<String, Object?> _identity(String role) => {
  'runId': 'run',
  'role': role,
  'groupId': 'g',
  'messageId': 'm-$_k',
  'reactorPeerId': 'peer-b',
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _k: [_row(incoming: false)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_k, ['bob', 'charlie']),
      ],
    },
  );
  for (final r in ['bob', 'charlie']) {
    p['got:$_k:$r'] = _f.snap(
      r,
      watched: {
        _k: [_row(incoming: true)],
      },
    );
    p['${r}Final'] = _f.snap(
      r,
      watched: {
        _k: [_row(incoming: true)],
      },
    );
  }
  p['reactionArmed'] = {
    for (final r in ['alice', 'bob', 'charlie'])
      r: {..._identity(r), 'armed': true, 'initialReactionCount': 0},
  };
  p['reactionFinal'] = {
    for (final r in ['alice', 'bob', 'charlie'])
      r: {
        ..._identity(r),
        'reactions': [
          {
            'id': 'r1',
            'message_id': 'm-$_k',
            'sender_peer_id': 'peer-b',
            'emoji': '🔥',
            'removed_at': null,
            'timestamp': 't',
          },
        ],
        'outcomes': r == 'bob'
            ? [
                {'outcome': 'success', 'reactionId': 'r1'},
              ]
            : [],
        'changes': r == 'bob'
            ? []
            : [
                {
                  'type': 'upserted',
                  'reactionId': 'r1',
                  'messageId': 'm-$_k',
                  'senderPeerId': 'peer-b',
                  'emoji': '🔥',
                  'timestamp': 't',
                },
              ],
      },
  };
  return p;
}

void main() {
  test('observed L-01 media reaction passes the original oracle', () {
    expect(validateProductionGroupMediaReaction(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'the sent message carries no image': (p) =>
        (p['aliceFinal']['watched'][_k] as List).single.remove(
          'mediaAttachmentCount',
        ),
    "Bob's reaction did not publish": (p) =>
        p['reactionFinal']['bob']['outcomes'] = [
          {'outcome': 'failed', 'reactionId': 'r1'},
        ],
    'Charlie saw no reaction stream change': (p) =>
        p['reactionFinal']['charlie']['changes'] = [],
    'Alice persisted the reaction twice': (p) =>
        (p['reactionFinal']['alice']['reactions'] as List).add(
          (p['reactionFinal']['alice']['reactions'] as List).single,
        ),
    'the reaction targets another message': (p) =>
        p['reactionFinal']['charlie']['messageId'] = 'other',
    'an armed observation was not fresh': (p) =>
        p['reactionArmed']['bob']['initialReactionCount'] = 1,
    'Charlie never got the image message': (p) =>
        p['got:$_k:charlie']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupMediaReaction(proof), isNotEmpty);
    });
  }
}
