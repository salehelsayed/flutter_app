import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_routing_criteria.dart';

Map<String, dynamic> fixture() {
  const run = 'routing-test-run';
  final cases = <Map<String, dynamic>>[];
  final counts = {
    'S1-CONV': 0,
    'S2': 5,
    'S5': 5,
    'S8': 10,
    'S9': 5,
    'S13': 10,
    'S12': 0,
    'G2': 5,
    'G3': 3,
    'G5': 9,
    'G6': 0,
    'G7': 2,
  };
  for (final id in productionRoutingCases) {
    final group = id.startsWith('G');
    final exchanges = <Map<String, dynamic>>[];
    for (var n = 1; n <= (counts[id] ?? 1); n++) {
      final role =
          ((id == 'S5' || id == 'G3') && n.isEven ||
              (id == 'S8' || id == 'G5') && n == 7)
          ? 'bob'
          : 'alice';
      final opposite = role == 'alice' ? 'bob' : 'alice';
      final message = 'routing-$run-$id-$n';
      final text = id == 'S11' ? '' : '$id: message $n $run';
      final sender = <String, dynamic>{
        'id': message,
        'text': text,
        'incoming': false,
        'lane': group ? 'group' : 'direct',
        'conversationId': group
            ? 'group'
            : id == 'S7'
            ? 'unreachable'
            : opposite,
        'status': 'delivered',
        if (id == 'S11')
          'attachments': [
            {'mediaType': 'audio', 'size': 10240},
          ],
      };
      exchanges.add({
        'senderRole': role,
        'sender': sender,
        'n': n,
        'timing': {
          'outcome': 'success',
          'elapsedMs': 10,
          'sendPath': id == 'S3' ? 'inbox' : 'direct',
        },
        if (!{'S7', 'S11'}.contains(id)) ...{
          'receiver': {
            'id': message,
            'text': text,
            'incoming': true,
            'lane': sender['lane'],
            'conversationId': group ? 'group' : role,
            if (id == 'G7') 'keyGeneration': n + 1,
          },
          'receiptMs': 20,
        },
      });
    }
    final c = <String, dynamic>{'id': id, 'exchanges': exchanges};
    if ({'S2', 'S9', 'G2'}.contains(id)) c['sendPhaseMs'] = 1000;
    if (id == 'S1-CONV') {
      c.addAll({
        'messageId': 'routing-$run-S1-1',
        'status': 'delivered',
        'convergenceMs': 100,
      });
    }
    if (id == 'S7') c['unreachablePeerId'] = 'unreachable';
    if ({'S3', 'S8', 'S9', 'G4', 'G5'}.contains(id)) {
      c.addAll({'stop': stop(), 'restart': start()});
    }
    if (id == 'S6') {
      c.addAll({
        'processDeathVerified': true,
        'beforeNonce': 'old',
        'afterNonce': 'new',
      });
    }
    if (id == 'S10') {
      c.addAll({
        'deletion': {'outcome': 'success'},
        'receiverTombstone': {
          'id': 'routing-$run-S10-1',
          'contactPeerId': 'alice',
          'deletedAt': '2026-09-27T00:00:00Z',
        },
      });
    }
    if (id == 'S12') {
      c.addAll({
        'scope': 'informational',
        'uploads': [
          for (final size in [1048576, 5242880])
            {
              'sizeBytes': size,
              'uploadMs': 40,
              'result': {'ok': true},
            },
        ],
      });
    }
    if (id == 'S14') c.addAll({'scope': 'informational', 'isLocal': false});
    if (id == 'S15') {
      c['coreStart'] = {
        'operation': 'start_core',
        'result': true,
        'after': {'isStarted': true, 'registeredNamespaces': []},
      };
    }
    if (id == 'X1') {
      c['restarts'] = [
        for (final role in ['alice', 'bob'])
          {'role': role, 'stop': stop(), 'start': start()},
      ];
    }
    if (id == 'X2') {
      c['lifecycle'] = [
        for (final role in ['alice', 'bob'])
          {'role': role, 'paused': 'paused', 'resumed': 'resumed'},
      ];
    }
    if (id == 'X3') {
      c['healthChecks'] = [
        for (var i = 0; i < 2; i++)
          {'operation': 'health_check', 'result': true},
      ];
    }
    if (id == 'G6') {
      c.addAll({'scope': 'informational', 'peerDiscoveryMs': 5002});
    }
    if (id == 'G7') {
      c['rotation'] = {
        'rotationMs': 20,
        'rotated': true,
        'beforeGeneration': 2,
        'afterGeneration': 3,
      };
    }
    cases.add(c);
  }
  return jsonDecode(
        jsonEncode({
          'runId': run,
          'peers': {'alice': 'alice', 'bob': 'bob'},
          'groupId': 'group',
          'cases': cases,
        }),
      )
      as Map<String, dynamic>;
}

Map<String, dynamic> stop() => {
  'operation': 'stop',
  'result': true,
  'after': {'isStarted': false},
};
Map<String, dynamic> start() => {
  'operation': 'start',
  'result': true,
  'after': {'isStarted': true},
};
Map row(Map p, String id) =>
    (p['cases'] as List).cast<Map>().singleWhere((c) => c['id'] == id);
Map exchange(Map p, String id, [int index = 0]) =>
    row(p, id)['exchanges'][index] as Map;

void main() {
  test('all 27 original boundaries accept bound production observations', () {
    expect(productionRoutingCases, hasLength(27));
    expect(validateProductionRouting(fixture()), isEmpty);
  });
  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'late batch stage': (p) => row(p, 'S9')['sendPhaseMs'] = 180001,
    'missing case': (p) => (p['cases'] as List).removeLast(),
    'duplicate case': (p) => (p['cases'] as List)[1] = (p['cases'] as List)[0],
    'wrong run': (p) => p['runId'] = 'other-run',
    'wrong receiver identity': (p) =>
        exchange(p, 'S1')['receiver']['conversationId'] = 'foreign',
    'wrong incoming text': (p) =>
        exchange(p, 'S4')['receiver']['text'] = 'other message',
    'missing receiver row': (p) => exchange(p, 'S1').remove('receiver'),
    'fake timing': (p) => exchange(p, 'S1').remove('timing'),
    'duplicate message identity': (p) => exchange(p, 'S2', 1)['sender']['id'] =
        exchange(p, 'S2')['sender']['id'],
    'read instead of delivered convergence': (p) =>
        row(p, 'S1-CONV')['status'] = 'read',
    'wrong convergence row': (p) => row(p, 'S1-CONV')['messageId'] = 'other',
    'late convergence': (p) => row(p, 'S1-CONV')['convergenceMs'] = 120001,
    'four warm messages': (p) =>
        (row(p, 'S2')['exchanges'] as List).removeLast(),
    'offline direct path': (p) =>
        exchange(p, 'S3')['timing']['sendPath'] = 'direct',
    'node never stopped': (p) =>
        row(p, 'S3')['stop']['after']['isStarted'] = true,
    'node restart failed': (p) => row(p, 'G4')['restart']['result'] = false,
    'wrong reverse role': (p) => exchange(p, 'S5', 1)['senderRole'] = 'alice',
    'stale process nonce': (p) => row(p, 'S6')['afterNonce'] = 'old',
    'unreachable fixture is real peer': (p) =>
        row(p, 'S7')['unreachablePeerId'] = 'bob',
    'nine direct lifecycle messages': (p) =>
        (row(p, 'S8')['exchanges'] as List).removeLast(),
    'wrong lifecycle ordinal': (p) => exchange(p, 'S8', 4)['n'] = 4,
    'missing reverse lifecycle receipt': (p) =>
        exchange(p, 'S8', 6).remove('receiver'),
    'failed batch send': (p) =>
        exchange(p, 'S9', 2)['timing']['outcome'] = 'failed',
    'missing batch receipt': (p) => exchange(p, 'S9', 3).remove('receiver'),
    'uncommitted deletion': (p) =>
        row(p, 'S10')['receiverTombstone']['deletedAt'] = null,
    'wrong deleted row': (p) =>
        row(p, 'S10')['receiverTombstone']['id'] = 'other',
    'failed deletion publication': (p) =>
        row(p, 'S10')['deletion']['outcome'] = 'failed',
    'nine rapid sends': (p) =>
        (row(p, 'S13')['exchanges'] as List).removeLast(),
    'four rapid receipts': (p) {
      for (var i = 4; i < 10; i++) {
        exchange(p, 'S13', i).remove('receiver');
      }
    },
    'voice missing native outcome': (p) =>
        exchange(p, 'S11')['timing']['outcome'] = 'failed',
    'voice attachment missing': (p) =>
        exchange(p, 'S11')['sender']['attachments'] = [],
    'missing 5MB upload': (p) =>
        (row(p, 'S12')['uploads'] as List).removeLast(),
    'invented LAN claim': (p) => row(p, 'S14')['scope'] = 'LAN proven',
    'already registered before gap': (p) =>
        row(p, 'S15')['coreStart']['after']['registeredNamespaces'] = [
          'registered',
        ],
    'one restart only': (p) => (row(p, 'X1')['restarts'] as List).removeLast(),
    'logical foreground only': (p) =>
        row(p, 'X2')['lifecycle'][0]['paused'] = 'resumed',
    'missing health check': (p) =>
        (row(p, 'X3')['healthChecks'] as List).removeLast(),
    'four group warm receipts': (p) => exchange(p, 'G2', 4).remove('receiver'),
    'no group reverse receipt': (p) => exchange(p, 'G3', 1).remove('receiver'),
    'unresolved group lifecycle': (p) =>
        exchange(p, 'G5', 4).remove('receiver'),
    'missing discovery interval': (p) => row(p, 'G6').remove('peerDiscoveryMs'),
    'rotation no-op': (p) => row(p, 'G7')['rotation']['rotated'] = false,
    'wrong post-rotation epoch': (p) =>
        exchange(p, 'G7', 1)['receiver']['keyGeneration'] = 2,
    'missing pre-rotation receipt': (p) => exchange(p, 'G7').remove('receiver'),
    'group publication without receiver': (p) =>
        exchange(p, 'G8').remove('receiver'),
  };
  for (final entry in corruptions.entries) {
    test('rejects ${entry.key}', () {
      final p = fixture();
      entry.value(p);
      expect(validateProductionRouting(p), isNotEmpty);
    });
  }
  test(
    'retains the original rapid-receipt minimum without inventing remaining receipts',
    () {
      final p = fixture();
      for (var i = 5; i < 10; i++) {
        exchange(p, 'S13', i).remove('receiver');
      }
      expect(validateProductionRouting(p), isEmpty);
    },
  );
  test(
    'informational media errors are recorded without claiming throughput success',
    () {
      final p = fixture();
      row(p, 'S12')['uploads'][1] = {
        'sizeBytes': 5242880,
        'uploadMs': 42,
        'error': 'actual upload attempt failed',
      };
      expect(validateProductionRouting(p), isEmpty);
    },
  );
  test('offline group custody accepts the production no-peers outcome', () {
    final p = fixture();
    final offline = exchange(p, 'G5', 4)['timing'] as Map<String, dynamic>;
    offline['outcome'] = 'success_no_peers';
    offline['inboxStored'] = true;
    expect(validateProductionRouting(p), isEmpty);

    offline['inboxStored'] = false;
    expect(validateProductionRouting(p), isNotEmpty);
  });
}
