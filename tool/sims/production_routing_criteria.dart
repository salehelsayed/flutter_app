import '../../integration_test/scripts/routing_smoke_group_criteria.dart';

const productionRoutingCases = [
  'S1',
  'S1-CONV',
  'S2',
  'S3',
  'S4',
  'S5',
  'S6',
  'S7',
  'S8',
  'S9',
  'S10',
  'S13',
  'S11',
  'S12',
  'S14',
  'S15',
  'X1',
  'X2',
  'X3',
  'G1',
  'G2',
  'G3',
  'G4',
  'G5',
  'G6',
  'G7',
  'G8',
];

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
bool _elapsed(Object? value) => value is int && value >= 0;

/// Reuses the preserved pure legacy predicates, and independently binds each
/// synthesized predicate input to observed production rows and flow receipts.
/// S12, S14 and G6 retain their informational scope; no throughput/LAN claim is
/// inferred from an unconditional legacy criterion.
List<String> validateProductionRouting(Map<String, Object?> proof) {
  final failures = <String>[];
  final cases = _maps(proof['cases']);
  if (cases.map((c) => c['id']).join(',') != productionRoutingCases.join(',')) {
    return ['all 27 ordered routing receipts are required exactly once'];
  }
  final peers = _map(proof['peers']);
  final run = proof['runId'];
  final group = proof['groupId'];
  if (run is! String ||
      run.isEmpty ||
      group is! String ||
      group.isEmpty ||
      peers['alice'] is! String ||
      peers['bob'] is! String ||
      peers['alice'] == peers['bob']) {
    return ['exact run, peer and group identities required'];
  }
  final usedMessages = <String>{};
  void require(bool ok, String reason) {
    if (!ok) failures.add(reason);
  }

  for (final c in cases) {
    final id = c['id'] as String;
    final exchanges = _maps(c['exchanges']);
    final groupCase = id.startsWith('G');
    for (final x in exchanges) {
      final sender = _map(x['sender']);
      final receiver = _map(x['receiver']);
      final role = x['senderRole'];
      final opposite = role == 'alice' ? 'bob' : 'alice';
      final message = sender['id'];
      final text = sender['text'];
      final expectedTarget = groupCase
          ? group
          : (id == 'S7' ? c['unreachablePeerId'] : peers[opposite]);
      require(
        peers.containsKey(role) &&
            message is String &&
            message.isNotEmpty &&
            usedMessages.add(message) &&
            text is String &&
            (text.startsWith('$id:') || id == 'S11' && text.isEmpty) &&
            (text.contains(run) || message.startsWith('routing-$run-$id')) &&
            sender['incoming'] == false &&
            sender['conversationId'] == expectedTarget &&
            sender['lane'] == (groupCase ? 'group' : 'direct'),
        '$id has unbound/duplicate outgoing row',
      );
      if (receiver.isNotEmpty) {
        require(
          receiver['id'] == message &&
              receiver['text'] == text &&
              receiver['incoming'] == true &&
              receiver['lane'] == sender['lane'] &&
              receiver['conversationId'] == (groupCase ? group : peers[role]) &&
              _elapsed(x['receiptMs']),
          '$id has unbound incoming row',
        );
      }
      final timing = _map(x['timing']);
      require(
        timing['outcome'] is String && _elapsed(timing['elapsedMs']),
        '$id lacks actual send timing',
      );
    }
    Map<String, dynamic> send(Map x) {
      final timing = _map(x['timing']);
      // The production group sender reports its durable offline custody as
      // success_no_peers. The retained predicate calls that same outcome
      // successNoPeers. Keep the raw timing in the case receipt and translate
      // only a send that actually stored the inbox copy.
      if (timing['outcome'] == 'success_no_peers' &&
          timing['inboxStored'] == true) {
        return {...timing, 'outcome': 'successNoPeers'};
      }
      return timing;
    }

    Map<String, dynamic> receive(Map x) =>
        _map(x['receiver']).isEmpty ? {} : {'e2eMs': x['receiptMs']};
    bool delivered(Map x) =>
        _map(x['receiver']).isNotEmpty && _elapsed(x['receiptMs']);
    final first = exchanges.firstOrNull ?? <String, dynamic>{};
    final alice = send(first);
    final bob = receive(first);
    GroupSmokeCriterion? original;
    switch (id) {
      case 'S1':
      case 'S4':
      case 'S6':
      case 'G1':
        require(
          exchanges.length == 1 &&
              alice['outcome'] == 'success' &&
              delivered(first),
          '$id send and receive required',
        );
      case 'S1-CONV':
        final s1 = _maps(cases.first['exchanges']).singleOrNull;
        require(
          s1 != null &&
              c['messageId'] == _map(s1['sender'])['id'] &&
              c['status'] == 'delivered' &&
              _elapsed(c['convergenceMs']) &&
              (c['convergenceMs'] as int) <= 120000,
          'S1-CONV exact delivered convergence required',
        );
      case 'S2':
      case 'G2':
        require(
          exchanges.length == 5 && exchanges.every(delivered),
          '$id requires five exact receipts',
        );
        if (id == 'G2') {
          original = evaluateG2({'count': exchanges.where(delivered).length});
        }
      case 'S3':
        require(exchanges.length == 1, '$id requires one exchange');
        original = evaluateS3(alice, bob);
      case 'S5':
      case 'G3':
        final outgoing = exchanges
            .where((x) => x['senderRole'] == 'alice')
            .toList();
        final replies = exchanges
            .where((x) => x['senderRole'] == 'bob')
            .toList();
        require(
          outgoing.length == (id == 'S5' ? 3 : 2) &&
              replies.length == (id == 'S5' ? 2 : 1) &&
              exchanges.every(delivered),
          '$id bidirectional receipts incomplete',
        );
      case 'S7':
        require(
          exchanges.length == 1 &&
              ['failed', 'success'].contains(alice['outcome']) &&
              c['unreachablePeerId'] is String &&
              !peers.values.contains(c['unreachablePeerId']) &&
              _map(first['receiver']).isEmpty,
          'S7 requires the unreachable fixture attempt',
        );
      case 'S8':
      case 'G5':
        final expected = id == 'S8' ? 10 : 9;
        require(
          exchanges.length == expected &&
              exchanges.map((x) => x['n']).join(',') ==
                  List.generate(expected, (i) => i + 1).join(','),
          '$id exact lifecycle sequence required',
        );
        final a = <Map<String, dynamic>>[], b = <Map<String, dynamic>>[];
        for (final x in exchanges) {
          final n = x['n'];
          if (n == 7) {
            require(x['senderRole'] == 'bob', '$id msg7 must be Bob reply');
            a.add({
              'n': n,
              'label': 'recv',
              'received': id == 'S8' ? delivered(x) : receive(x),
            });
            b.add({'n': n, 'role': 'send', ...send(x)});
          } else {
            require(x['senderRole'] == 'alice', '$id forward role changed');
            a.add({
              'n': n,
              'label': n == 5
                  ? 'offline'
                  : n == 6
                  ? 'reconnect'
                  : 'warm',
              ...send(x),
            });
            b.add({'n': n, 'role': 'recv', ...receive(x)});
          }
        }
        original = id == 'S8'
            ? evaluateS8({'timeline': a}, {'timeline': b})
            : evaluateG5({'timeline': a}, {'timeline': b});
      case 'S9':
        original = evaluateS9(
          {'timings': exchanges.map(send).toList()},
          {
            'count': exchanges.where(delivered).length,
            'timings': exchanges.map(receive).toList(),
          },
        );
      case 'S10':
        final deletion = _map(c['deletion']);
        final tombstone = _map(c['receiverTombstone']);
        require(
          exchanges.length == 1 &&
              tombstone['id'] == _map(first['sender'])['id'] &&
              tombstone['contactPeerId'] == peers['alice'] &&
              tombstone['deletedAt'] is String,
          'S10 committed deletion identity missing',
        );
        original = evaluateS10(deletion, {
          'received': delivered(first),
          'deleted': tombstone['deletedAt'] is String,
        });
      case 'S13':
        require(
          exchanges.length == 10 && exchanges.where(delivered).length >= 5,
          'S13 needs ten rapid sends and at least five receipts',
        );
      case 'S11':
        original = evaluateS11({'voiceTiming': alice});
        require(
          exchanges.length == 1 &&
              _maps(_map(first['sender'])['attachments']).any(
                (a) =>
                    a['mediaType'] == 'audio' &&
                    a['size'] is int &&
                    (a['size'] as int) > 0,
              ),
          'S11 actual voice attachment missing',
        );
      case 'S12':
        final uploads = _maps(c['uploads']);
        require(
          c['scope'] == 'informational' &&
              uploads.length == 2 &&
              uploads.map((u) => u['sizeBytes']).join(',') ==
                  '1048576,5242880' &&
              uploads.every(
                (u) =>
                    _elapsed(u['uploadMs']) &&
                    (u.containsKey('result') || u['error'] is String),
              ),
          'S12 both informational upload attempts required',
        );
      case 'S14':
        require(
          c['scope'] == 'informational' &&
              c['isLocal'] is bool &&
              exchanges.length == 1,
          'S14 actual path observation required without claiming LAN',
        );
      case 'S15':
      case 'X1':
      case 'X2':
      case 'X3':
        require(
          exchanges.length == 1 && alice['outcome'] == 'success',
          '$id actual successful send required',
        );
      case 'G4':
        require(exchanges.length == 1, 'G4 one recovered exchange required');
        original = evaluateG4(bob);
      case 'G6':
        require(
          c['scope'] == 'informational' &&
              _elapsed(c['peerDiscoveryMs']) &&
              (c['peerDiscoveryMs'] as int) >= 5000,
          'G6 observed join/settle interval required',
        );
      case 'G7':
        final rotation = _map(c['rotation']);
        final before = rotation['beforeGeneration'],
            after = rotation['afterGeneration'];
        require(
          exchanges.length == 2 &&
              rotation['rotated'] == true &&
              before is int &&
              after is int &&
              after > before &&
              _map(exchanges.firstOrNull?['receiver'])['keyGeneration'] ==
                  before &&
              _map(exchanges.lastOrNull?['receiver'])['keyGeneration'] == after,
          'G7 real key generation change and both decrypted rows required',
        );
        original = evaluateG7(
          {'rotationMs': rotation['rotationMs']},
          {
            'preRotation': receive(exchanges.firstOrNull ?? {}),
            'postRotation': receive(exchanges.lastOrNull ?? {}),
            'bothReceived': exchanges.length == 2 && exchanges.every(delivered),
          },
        );
      case 'G8':
        require(exchanges.length == 1, 'G8 one exact exchange required');
        original = evaluateG8(alice, bob);
    }
    if (original != null) {
      require(original.ok, '$id preserved predicate: ${original.detail}');
    }
    if ({'S2', 'S9', 'G2'}.contains(id)) {
      require(
        _elapsed(c['sendPhaseMs']) && (c['sendPhaseMs'] as int) <= 180000,
        '$id preserves the original three-minute batch stage',
      );
    }
    if ({'S3', 'S8', 'S9', 'G4', 'G5'}.contains(id)) {
      final stop = _map(c['stop']), restart = _map(c['restart']);
      require(
        stop['operation'] == 'stop' &&
            stop['result'] == true &&
            _map(stop['after'])['isStarted'] == false &&
            restart['operation'] == 'start' &&
            restart['result'] == true &&
            _map(restart['after'])['isStarted'] == true,
        '$id actual offline and restarted node required',
      );
    }
    if (id == 'S6') {
      require(
        c['processDeathVerified'] == true &&
            c['beforeNonce'] != null &&
            c['afterNonce'] != null &&
            c['beforeNonce'] != c['afterNonce'],
        'S6 fresh process restart required',
      );
    }
    if (id == 'S15') {
      final start = _map(c['coreStart']);
      require(
        start['operation'] == 'start_core' &&
            start['result'] == true &&
            _map(start['after'])['isStarted'] == true &&
            _map(start['after'])['registeredNamespaces'] is List &&
            (_map(start['after'])['registeredNamespaces'] as List).isEmpty,
        'S15 pre-registration core start observation required',
      );
    }
    if (id == 'X1') {
      final restarts = _maps(c['restarts']);
      require(
        restarts.length == 2 &&
            restarts.map((r) => r['role']).toSet().containsAll([
              'alice',
              'bob',
            ]) &&
            restarts.every(
              (r) =>
                  _map(r['stop'])['result'] == true &&
                  _map(_map(r['stop'])['after'])['isStarted'] == false &&
                  _map(r['start'])['result'] == true &&
                  _map(_map(r['start'])['after'])['isStarted'] == true,
            ),
        'X1 both actual node restarts required',
      );
    }
    if (id == 'X2') {
      final lifecycle = _maps(c['lifecycle']);
      require(
        lifecycle.length == 2 &&
            lifecycle.map((r) => r['role']).toSet().containsAll([
              'alice',
              'bob',
            ]) &&
            lifecycle.every(
              (r) => r['paused'] == 'paused' && r['resumed'] == 'resumed',
            ),
        'X2 both actual OS lifecycle receipts required',
      );
    }
    if (id == 'X3') {
      final checks = _maps(c['healthChecks']);
      require(
        checks.length == 2 &&
            checks.every(
              (r) => r['operation'] == 'health_check' && r['result'] == true,
            ),
        'X3 both actual health-check completions required',
      );
    }
  }
  return failures;
}
