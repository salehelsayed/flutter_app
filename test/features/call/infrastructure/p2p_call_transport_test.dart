import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeP2PService implements P2PService {
  _FakeP2PService(this.result);

  SendMessageResult result;
  int directCalls = 0;
  int chatInboxCalls = 0;
  String? sentPeer;
  String? sentEnvelope;
  bool throwOnSend = false;
  Future<SendMessageResult>? pendingSend;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    directCalls += 1;
    sentPeer = peerId;
    sentEnvelope = message;
    if (throwOnSend) throw StateError('transport failed');
    final pending = pendingSend;
    if (pending != null) return pending;
    return result;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    chatInboxCalls += 1;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('shared direct-send diagnostics do not log recipient identity', () {
    final source = File(
      'lib/core/services/p2p_service_impl.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> sendMessage(');
    final end = source.indexOf('Future<DiscoveredPeer?> discoverPeer(', start);
    final directSendSource = source.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(directSendSource, isNot(contains("'peerId': peerId")));
  });

  test(
    'direct ACK reports byte acceptance and never application ringing',
    () async {
      final p2p = _FakeP2PService(
        const SendMessageResult(
          sent: true,
          acked: true,
          reply: 'ACK',
          transport: 'direct',
        ),
      );
      final transport = P2PCallTransport(p2pService: p2p);

      final result = await transport.send(
        recipientDevicePeerId: 'recipient-device',
        envelopeJson: '{"type":"call_signal","version":"1"}',
      );

      expect(result.outcome, CallDirectTransportOutcome.acceptedBytes);
      expect(result.transportAcknowledged, isTrue);
      expect(result.route, CallDirectRoute.direct);
      expect(p2p.directCalls, 1);
      expect(p2p.sentPeer, 'recipient-device');
      expect(p2p.chatInboxCalls, 0);
    },
  );

  test('missing transport ACK is a direct failure, not ringing', () async {
    final p2p = _FakeP2PService(
      const SendMessageResult(sent: true, acked: false, transport: 'relay'),
    );
    final transport = P2PCallTransport(p2pService: p2p);

    final result = await transport.send(
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: '{"type":"call_signal","version":"1"}',
    );

    expect(result.outcome, CallDirectTransportOutcome.failed);
    expect(result.transportAcknowledged, isFalse);
    expect(result.route, CallDirectRoute.circuitRelay);
    expect(p2p.chatInboxCalls, 0);
  });

  test(
    'transport rejects an oversized call frame without touching P2P',
    () async {
      final p2p = _FakeP2PService(
        const SendMessageResult(sent: true, acked: true),
      );
      final transport = P2PCallTransport(p2pService: p2p);

      final result = await transport.send(
        recipientDevicePeerId: 'recipient-device',
        envelopeJson: 'x' * (P2PCallTransport.maxSignalBytes + 1),
      );

      expect(result.outcome, CallDirectTransportOutcome.rejectedOversized);
      expect(p2p.directCalls, 0);
      expect(p2p.chatInboxCalls, 0);
    },
  );

  test('transport exceptions become a nonthrowing direct failure', () async {
    final p2p = _FakeP2PService(
      const SendMessageResult(sent: true, acked: true),
    )..throwOnSend = true;
    final transport = P2PCallTransport(p2pService: p2p);

    final result = await transport.send(
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: '{"type":"call_signal","version":"1"}',
    );

    expect(result.outcome, CallDirectTransportOutcome.failed);
    expect(result.transportAcknowledged, isFalse);
  });

  test('transport enforces its own bound when the P2P seam hangs', () async {
    final p2p = _FakeP2PService(
      const SendMessageResult(sent: true, acked: true),
    )..pendingSend = Completer<SendMessageResult>().future;
    final transport = P2PCallTransport(p2pService: p2p, timeoutMs: 1);

    final result = await transport.send(
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: '{"type":"call_signal","version":"1"}',
    );

    expect(result.outcome, CallDirectTransportOutcome.failed);
    expect(result.transportAcknowledged, isFalse);
  });
}
