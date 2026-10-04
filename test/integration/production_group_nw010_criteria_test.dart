import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_nw010_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _before = 'aliceDuringBackgroundBeforeEdit';
const _after = 'aliceDuringBackgroundAfterEdit';
const _live = 'alicePostForegroundLive';
const _back = 'bobPostForegroundPublishBack';
final _f = CatalogFixture(
  'private_background_resume_group_delivery',
  productionNw010Texts('run'),
  productionNw010Flows,
);
const _pair = ['peer-a', 'peer-b'];

Map<String, Object?> _applied(String key) => {
  'event': 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
  'details': {'rawMessageId': 'm-$key'},
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceFinal'] = _f.snap(
    'alice',
    members: _pair,
    watched: {
      _before: [_f.row(_before, incoming: false)],
      _after: [_f.row(_after, incoming: false)],
      _live: [_f.row(_live, incoming: false)],
      _back: [_f.row(_back, incoming: true)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_before, ['bob', 'charlie']),
        _f.delivery(_after, ['bob']),
        _f.delivery(_live, ['bob']),
      ],
      'liveMessageIds': ['m-$_back'],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    members: _pair,
    watched: {
      _before: [_f.row(_before, incoming: true)],
      _after: [_f.row(_after, incoming: true)],
      _live: [_f.row(_live, incoming: true)],
      _back: [_f.row(_back, incoming: false)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_back, ['alice']),
      ],
      'liveMessageIds': ['m-$_live'],
      'flowEvents': [
        _applied(_before),
        {
          'event': 'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED',
          'details': {'groupId': 'g'},
        },
        _applied(_after),
      ],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: {
      _before: [_f.row(_before, incoming: true)],
    },
    extra: {
      'liveMessageIds': ['m-$_before'],
    },
  );
  for (final (key, role) in const [
    (_before, 'charlie'),
    (_before, 'bob'),
    (_after, 'bob'),
    (_live, 'bob'),
    (_back, 'alice'),
  ]) {
    p['got:$key:$role'] = _f.got(role, key);
  }
  p['aliceRemoved'] = _f.snap('alice', members: _pair);
  p['bobRecovered'] = {'groupRecoveryActive': false};
  p['bob-offline'] = true;
  p['order'] = [
    'bob-offline',
    'remove-charlie',
    'alice-after-edit',
    'bob-online',
  ];
  return p;
}

void main() {
  test('observed NW-010 and OB-011 pass the original oracles', () {
    expect(validateProductionGroupNw010(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob applied the removal after the second post': (p) =>
        p['bobFinal']['flowEvents'] = [
          _applied(_before),
          _applied(_after),
          {'event': 'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED', 'details': {}},
        ],
    'Bob got a missed post live': (p) =>
        p['bobFinal']['liveMessageIds'] = ['m-$_before', 'm-$_live'],
    'Charlie holds the second post': (p) =>
        p['charlieFinal']['watched'][_after] = [_f.row(_after, incoming: true)],
    'the second post was addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][1]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'Bob relaunched before the removal': (p) => p['order'] = [
      'bob-offline',
      'bob-online',
      'remove-charlie',
      'alice-after-edit',
    ],
    'Bob\'s group recovery never finished': (p) =>
        p['bobRecovered'] = {'groupRecoveryActive': true},
    'Bob was never away': (p) => p['bob-offline'] = false,
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupNw010(proof), isNotEmpty);
    });
  }
}
