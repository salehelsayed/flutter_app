import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/run_transport_e2e.dart';

const sender = 'flutter-peer';

TransportIncomingProof proof(
  String text, {
  String source = 'collector:post-verify',
  String from = sender,
  String? wire,
}) => TransportIncomingProof(
  from: from,
  to: 'cli-peer',
  content: wire ?? '{"version":"2","senderPeerId":"$from","encrypted":{}}',
  source: source,
  timestamp: '2026-09-23T00:00:00Z',
  payloadText: text,
);

Map<String, bool> verdicts(List<TransportIncomingProof> evidence) => {
  for (final result in verifyCliReceivedMessages(evidence, sender))
    result.name: result.passed,
};

void main() {
  test('receiver checks consume decrypted live and inbox evidence', () {
    expect(
      verdicts([
        proof('A4: Encrypted hello'),
        proof('A6: Fast path message', source: 'inbox:g3'),
      ]),
      {'RECV-A1': true, 'RECV-A4': true, 'RECV-A6': true},
    );
  });

  test('plaintext fallback has an explicit negative receiver assertion', () {
    expect(
      verdicts([
        proof(
          'A1: Hello from Flutter v1',
          wire: '{"payload":{"text":"A1: Hello from Flutter v1"}}',
        ),
        proof('A4: Encrypted hello'),
        proof('A6: Fast path message'),
      ])['RECV-A1'],
      isFalse,
    );
  });

  test('missing or foreign A6 proof fails instead of omitting the check', () {
    for (final evidence in [
      [proof('A4: Encrypted hello')],
      [
        proof('A4: Encrypted hello'),
        proof('A6: Fast path message', from: 'another-peer'),
      ],
    ]) {
      expect(verdicts(evidence)['RECV-A6'], isFalse);
    }
  });

  test('another encrypted scenario cannot substitute for live A4', () {
    expect(verdicts([proof('A6: Fast path message')])['RECV-A4'], isFalse);
  });

  test('inbox-only A4 does not prove the live route', () {
    expect(
      verdicts([
        proof('A4: Encrypted hello', source: 'inbox:g3'),
        proof('A6: Fast path message'),
      ])['RECV-A4'],
      isFalse,
    );
  });

  test('foreign A1 traffic cannot fail the tested sender negative control', () {
    expect(
      verdicts([
        proof('A1: unrelated traffic', from: 'another-peer'),
        proof('A4: Encrypted hello'),
        proof('A6: Fast path message'),
      ]),
      {'RECV-A1': true, 'RECV-A4': true, 'RECV-A6': true},
    );
  });
}
