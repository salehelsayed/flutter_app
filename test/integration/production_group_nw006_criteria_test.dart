import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_nw006_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _missed = 'aliceMissedDuringDisconnect';
const _live = 'alicePostReconnectLive';
const _back = 'bobPublishBackAfterReconnect';
final _f = CatalogFixture(
  'private_peer_disconnect_not_removal',
  productionNw006Texts('run'),
  productionNw006Flows,
);

Map<String, dynamic> fixture() {
  final p = _f.base();
  Map<String, Object?> rows(Map<String, bool> keys) => {
    for (final e in keys.entries) e.key: [_f.row(e.key, incoming: e.value)],
  };
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: rows({_missed: false, _live: false, _back: true}),
    extra: {
      'deliveries': [
        _f.delivery(_missed, ['bob', 'charlie']),
        _f.delivery(_live, ['bob', 'charlie']),
      ],
      'liveMessageIds': ['m-$_back'],
      'memberRemovedTimelineIds': <String>[],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: rows({_missed: true, _live: true, _back: false}),
    extra: {
      'deliveries': [
        _f.delivery(_back, ['alice', 'charlie']),
      ],
      'liveMessageIds': ['m-$_live'],
      'memberRemovedTimelineIds': <String>[],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: rows({_missed: true, _live: true, _back: true}),
    extra: {
      'liveMessageIds': ['m-$_missed', 'm-$_live', 'm-$_back'],
      'memberRemovedTimelineIds': <String>[],
    },
  );
  for (final (key, role) in const [
    (_missed, 'bob'),
    (_missed, 'charlie'),
    (_live, 'bob'),
    (_live, 'charlie'),
    (_back, 'alice'),
    (_back, 'charlie'),
  ]) {
    p['got:$key:$role'] = _f.got(role, key);
  }
  p['aliceBeforeDisconnect'] = _f.snap('alice');
  p['aliceDuringDisconnect'] = _f.snap('alice');
  p['bobRelaunched'] = _f.snap('bob');
  p['bob-offline'] = true;
  return p;
}

void main() {
  test('observed NW-006 passes the original oracle', () {
    expect(validateProductionGroupNw006(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob got the missed message live': (p) =>
        p['bobFinal']['liveMessageIds'] = ['m-$_missed', 'm-$_live'],
    'Charlie got the missed message from the inbox': (p) =>
        p['charlieFinal']['liveMessageIds'] = ['m-$_live', 'm-$_back'],
    'the post-reconnect message reached Bob from the inbox': (p) =>
        p['bobFinal']['liveMessageIds'] = <String>[],
    'Alice dropped Bob from the durable recipients': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-c'],
    'Bob saw a removal': (p) =>
        p['bobFinal']['memberRemovedTimelineIds'] = ['sys-member_removed:x'],
    'the key epoch changed': (p) => p['charlieFinal']['keyEpoch'] = 3,
    'Bob was not disconnected': (p) => p['bob-offline'] = false,
    'Bob was not a member after relaunch': (p) =>
        p['bobRelaunched']['selfMember'] = false,
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupNw006(proof), isNotEmpty);
    });
  }
}
