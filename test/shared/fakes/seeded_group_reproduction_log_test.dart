import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'seeded_group_reproduction_log.dart';

void main() {
  group('SeededGroupReproductionLog', () {
    test(
      'ST-015 canonicalizes seed operation bridge diagnostic and failure',
      () {
        final first =
            SeededGroupReproductionLog(
                rowId: 'ST-015',
                seed: 15015,
                scenario: 'fake-network-repro',
              )
              ..recordOperation(
                step: 1,
                actor: 'alice',
                action: 'send',
                details: <String, Object?>{
                  'messageId': 'st015-msg-1',
                  'recipient': 'bob',
                  'groupId': 'group-st015',
                },
              )
              ..recordBridgeResponse(
                step: 1,
                actor: 'alice',
                command: 'group:publish',
                ok: true,
                response: <String, Object?>{
                  'keyEpoch': 1,
                  'transport': 'fake-network',
                },
              )
              ..recordDiagnostic(
                step: 1,
                layer: 'transport',
                event: 'fake_network_publish',
                details: <String, Object?>{
                  'recipientCount': 1,
                  'route': 'direct',
                },
              )
              ..recordFailure(
                step: 1,
                layer: 'transport',
                reason: 'injected_drop',
                details: <String, Object?>{
                  'messageId': 'st015-msg-1',
                  'expectedRecipient': 'bob',
                },
              );

        final reordered =
            SeededGroupReproductionLog(
                rowId: 'ST-015',
                seed: 15015,
                scenario: 'fake-network-repro',
              )
              ..recordOperation(
                step: 1,
                actor: 'alice',
                action: 'send',
                details: <String, Object?>{
                  'groupId': 'group-st015',
                  'recipient': 'bob',
                  'messageId': 'st015-msg-1',
                },
              )
              ..recordBridgeResponse(
                step: 1,
                actor: 'alice',
                command: 'group:publish',
                ok: true,
                response: <String, Object?>{
                  'transport': 'fake-network',
                  'keyEpoch': 1,
                },
              )
              ..recordDiagnostic(
                step: 1,
                layer: 'transport',
                event: 'fake_network_publish',
                details: <String, Object?>{
                  'route': 'direct',
                  'recipientCount': 1,
                },
              )
              ..recordFailure(
                step: 1,
                layer: 'transport',
                reason: 'injected_drop',
                details: <String, Object?>{
                  'expectedRecipient': 'bob',
                  'messageId': 'st015-msg-1',
                },
              );

        expect(reordered.canonicalJson(), first.canonicalJson());

        final decoded =
            jsonDecode(first.canonicalJson()) as Map<String, Object?>;
        expect(decoded['rowId'], 'ST-015');
        expect(decoded['seed'], 15015);
        expect(decoded['operations'], isA<List>());
        expect(decoded['bridgeResponses'], isA<List>());
        expect(decoded['diagnostics'], isA<List>());
        expect(decoded['failure'], isA<Map>());
        expect(first.canonicalJson(), contains('"reason":"injected_drop"'));
        expect(first.canonicalJson(), contains('"command":"group:publish"'));
      },
    );
  });
}
