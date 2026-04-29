import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/routing_smoke_group_criteria.dart';

void main() {
  group('routing smoke group criteria', () {
    test('G2 requires all five warm messages', () {
      expect(evaluateG2({'count': 5}).ok, isTrue);

      final partial = evaluateG2({'count': 3});

      expect(partial.ok, isFalse);
      expect(partial.detail, contains('requires 5/5'));
    });

    test('G4 requires Bob receiver-visible inbox recovery', () {
      expect(evaluateG4({'e2eMs': 1200}).ok, isTrue);

      final pending = evaluateG4({'e2eMs': -1});

      expect(pending.ok, isFalse);
      expect(pending.detail, contains('requires recovered receipt'));
    });

    test('G5 rejects pending or missing receiver timeline evidence', () {
      final passing = evaluateG5(
        {'timeline': _aliceTimeline()},
        {'timeline': _bobTimeline()},
      );

      expect(passing.ok, isTrue);

      final pendingBob = _bobTimeline();
      pendingBob[4] = {'n': 5, 'role': 'recv_inbox', 'pending': true};

      final pending = evaluateG5(
        {'timeline': _aliceTimeline()},
        {'timeline': pendingBob},
      );

      expect(pending.ok, isFalse);
      expect(pending.detail, contains('Bob msg5 pending'));

      final missingAliceReceipt = _aliceTimeline();
      missingAliceReceipt[6] = {'n': 7, 'label': 'recv', 'received': null};

      final missing = evaluateG5(
        {'timeline': missingAliceReceipt},
        {'timeline': _bobTimeline()},
      );

      expect(missing.ok, isFalse);
      expect(missing.detail, contains('Alice msg7 missing Bob receipt'));
    });

    test('G7 requires rotation plus pre and post rotation receipts', () {
      expect(
        evaluateG7(
          {'rotationMs': 1300},
          {
            'preRotation': {'e2eMs': 80},
            'postRotation': {'e2eMs': 90},
            'bothReceived': true,
          },
        ).ok,
        isTrue,
      );

      final senderOnly = evaluateG7(
        {'rotationMs': 1300},
        {'bothReceived': false},
      );

      expect(senderOnly.ok, isFalse);
      expect(senderOnly.detail, contains('requires both receipts'));
    });

    test('G8 requires Bob receipt in addition to Alice publish success', () {
      expect(
        evaluateG8({'sendMs': 900, 'outcome': 'success'}, {'e2eMs': 700}).ok,
        isTrue,
      );

      final senderOnly = evaluateG8(
        {'sendMs': 900, 'outcome': 'successNoPeers'},
        {'e2eMs': -1},
      );

      expect(senderOnly.ok, isFalse);
      expect(senderOnly.detail, contains('requires Bob receipt'));
    });
  });
}

List<Map<String, dynamic>> _aliceTimeline() {
  return <Map<String, dynamic>>[
    {'n': 1, 'label': 'cold', 'outcome': 'success'},
    {'n': 2, 'label': 'warm', 'outcome': 'success'},
    {'n': 3, 'label': 'warm', 'outcome': 'success'},
    {'n': 4, 'label': 'warm', 'outcome': 'success'},
    {'n': 5, 'label': 'offline', 'outcome': 'success'},
    {'n': 6, 'label': 'reconnect', 'outcome': 'success'},
    {
      'n': 7,
      'label': 'recv',
      'received': {'e2eMs': 250},
    },
    {'n': 8, 'label': 'warm', 'outcome': 'success'},
    {'n': 9, 'label': 'warm', 'outcome': 'success'},
  ];
}

List<Map<String, dynamic>> _bobTimeline() {
  return <Map<String, dynamic>>[
    {'n': 1, 'role': 'recv', 'e2eMs': 100},
    {'n': 2, 'role': 'recv', 'e2eMs': 110},
    {'n': 3, 'role': 'recv', 'e2eMs': 120},
    {'n': 4, 'role': 'recv', 'e2eMs': 130},
    {'n': 5, 'role': 'recv_inbox', 'e2eMs': 900},
    {'n': 6, 'role': 'recv', 'e2eMs': 140},
    {'n': 7, 'role': 'send', 'outcome': 'success'},
    {'n': 8, 'role': 'recv', 'e2eMs': 150},
    {'n': 9, 'role': 'recv', 'e2eMs': 160},
  ];
}
