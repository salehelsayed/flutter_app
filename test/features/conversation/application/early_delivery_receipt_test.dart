import 'dart:convert';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_message_repository.dart';
import 'send_chat_message_use_case_test.dart' as send_fixtures;

const _messageId = 'early-receipt-original-message';

ChatMessage _receipt({String from = 'target-peer'}) => ChatMessage(
  from: from,
  to: 'my-peer',
  timestamp: '2026-09-09T19:30:00.000Z',
  isIncoming: true,
  transport: 'direct',
  content: jsonEncode({
    'type': 'delivery_receipt',
    'payload': {
      'messageIds': [_messageId],
    },
  }),
);

class _ReceiptDuringSend extends send_fixtures.FakeP2PService {
  _ReceiptDuringSend(
    this.repository, {
    required this.nativeAck,
    this.receiptDuringSend = true,
    this.receiptFrom = 'target-peer',
  });

  final FakeMessageRepository repository;
  final bool nativeAck;
  final bool receiptDuringSend;
  final String receiptFrom;
  int earlyReceipts = 0;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (receiptDuringSend && earlyReceipts == 0) {
      earlyReceipts++;
      expect((await repository.getMessage(_messageId))!.status, 'sending');
      await handleDeliveryReceipt(
        message: _receipt(from: receiptFrom),
        messageRepo: repository,
      );
    }
    return SendMessageResult(sent: true, acked: nativeAck, transport: 'direct');
  }
}

class _ReceiptSettlementRepository extends FakeMessageRepository {
  bool refuseReceipt = false;

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) async {
    if (refuseReceipt && mode == OutgoingOrdinarySettlementMode.receipt) {
      return OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: await getMessage(messageId),
      );
    }
    return super.settleOutgoingOrdinaryTransport(
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
    );
  }
}

Future<void> _send(
  FakeMessageRepository repository,
  _ReceiptDuringSend service,
) async {
  await send_fixtures.sendChatMessage(
    p2pService: service,
    messageRepo: repository,
    messageId: _messageId,
    targetPeerId: 'target-peer',
    text: "that's cool",
    senderPeerId: 'my-peer',
    senderUsername: 'Me',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RECEIPT-CONVERGENCE late applied receipt observes the original '
      'trace without rewriting its pending final', () async {
    final diagnostics = await AppDiagnostics.installForTesting();
    addTearDown(diagnostics.dispose);
    final repository = _ReceiptSettlementRepository();
    await _send(
      repository,
      _ReceiptDuringSend(
        repository,
        nativeAck: false,
        receiptDuringSend: false,
      ),
    );
    final trace = diagnostics.traceForOperation('message:$_messageId');
    final before = await diagnostics.eventsForTesting();
    final originalFinal = before.singleWhere(
      (event) => event['traceId'] == trace && event['stage'] == 'finish',
    );
    final originalFinalBytes = jsonEncode(originalFinal);
    expect(originalFinal['outcome'], 'pending');
    expect((await repository.getMessage(_messageId))!.status, 'sent');
    bool appliedObservation(Map<String, Object?> event) =>
        event['stage'] == 'receipt' &&
        (event['values'] as Map)['direction'] == 'outgoing';

    await handleDeliveryReceipt(
      message: _receipt(from: 'another-peer'),
      messageRepo: repository,
    );
    repository.refuseReceipt = true;
    await handleDeliveryReceipt(message: _receipt(), messageRepo: repository);
    expect((await repository.getMessage(_messageId))!.status, 'sent');
    expect(
      (await diagnostics.eventsForTesting()).where(appliedObservation),
      isEmpty,
    );

    repository.refuseReceipt = false;
    String? unrelatedTrace;
    await diagnostics.runWithAttempt(
      feature: 'message',
      body: (current) async {
        unrelatedTrace = current;
        await handleDeliveryReceipt(
          message: _receipt(),
          messageRepo: repository,
        );
      },
    );
    final row = (await repository.getMessage(_messageId))!;
    expect(row.status, 'delivered');
    expect(row.wireEnvelope, isNull);
    final after = await diagnostics.eventsForTesting();
    final observations = after.where(appliedObservation).toList();
    expect(observations, hasLength(1));
    expect(observations.single['traceId'], trace);
    expect(observations.single['traceId'], isNot(unrelatedTrace));
    expect(observations.single['outcome'], 'ok');
    expect(observations.single['values'], containsPair('committed', true));
    expect(observations.single['values'], containsPair('acknowledged', true));
    expect(
      jsonEncode(
        after.singleWhere(
          (event) => event['eventId'] == originalFinal['eventId'],
        ),
      ),
      originalFinalBytes,
    );
    expect(
      after.where(
        (event) => event['traceId'] == trace && event['stage'] == 'finish',
      ),
      hasLength(1),
    );
    await handleDeliveryReceipt(message: _receipt(), messageRepo: repository);
    expect(
      (await diagnostics.eventsForTesting()).where(appliedObservation),
      hasLength(1),
    );
    final export = await diagnostics.exportPreview();
    for (final privateValue in [
      _messageId,
      'target-peer',
      'my-peer',
      "that's cool",
    ]) {
      expect(export, isNot(contains(privateValue)));
    }
  });

  test(
    'RECEIPT-CONVERGENCE unbound receipt cannot borrow an unrelated trace',
    () async {
      final diagnostics = await AppDiagnostics.installForTesting(
        enabled: false,
      );
      addTearDown(diagnostics.dispose);
      final repository = FakeMessageRepository();
      await _send(
        repository,
        _ReceiptDuringSend(
          repository,
          nativeAck: false,
          receiptDuringSend: false,
        ),
      );
      await diagnostics.setEnabled(true);
      await diagnostics.runWithAttempt(
        feature: 'message',
        body: (_) =>
            handleDeliveryReceipt(message: _receipt(), messageRepo: repository),
      );
      expect((await repository.getMessage(_messageId))!.status, 'delivered');
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) =>
              event['stage'] == 'receipt' &&
              (event['values'] as Map)['direction'] == 'outgoing',
        ),
        isEmpty,
      );
    },
  );

  test(
    'early valid receipt survives a lost native ACK and stops ordinary retry',
    () async {
      final repository = FakeMessageRepository();
      final service = _ReceiptDuringSend(repository, nativeAck: false);

      await _send(repository, service);

      expect(service.earlyReceipts, 1);
      final row = (await repository.getMessage(_messageId))!;
      expect(row.status, 'delivered');
      expect(row.wireEnvelope, isNull);
      expect(
        repository.directCustodyRows,
        hasLength(1),
        reason: 'delivery proof must preserve the separate relay transfer',
      );

      final storesBeforeRetry = service.storeInInboxCallCount;
      expect(
        await retryUnackedMessages(
          messageRepo: repository,
          p2pService: service,
          olderThan: Duration.zero,
        ),
        0,
      );
      expect(service.storeInInboxCallCount, storesBeforeRetry);
      expect(repository.directCustodyRows, hasLength(1));
    },
  );

  test(
    'native committed ACK preserves delivery after an early receipt',
    () async {
      final repository = FakeMessageRepository();
      final service = _ReceiptDuringSend(repository, nativeAck: true);

      await _send(repository, service);

      expect(service.earlyReceipts, 1);
      expect((await repository.getMessage(_messageId))!.status, 'delivered');
    },
  );

  test('receipt after send settlement still completes delivery', () async {
    final repository = FakeMessageRepository();
    final service = _ReceiptDuringSend(
      repository,
      nativeAck: false,
      receiptDuringSend: false,
    );

    await _send(repository, service);

    expect((await repository.getMessage(_messageId))!.status, 'sent');
    await handleDeliveryReceipt(message: _receipt(), messageRepo: repository);
    final row = (await repository.getMessage(_messageId))!;
    expect(row.status, 'delivered');
    expect(row.wireEnvelope, isNull);
  });

  test('early receipt from another peer cannot complete delivery', () async {
    final repository = FakeMessageRepository();
    final service = _ReceiptDuringSend(
      repository,
      nativeAck: false,
      receiptFrom: 'another-peer',
    );

    await _send(repository, service);

    expect(service.earlyReceipts, 1);
    final row = (await repository.getMessage(_messageId))!;
    expect(row.status, 'sent');
    expect(row.wireEnvelope, isNotNull);
    expect(repository.directCustodyRows, hasLength(1));
  });
}
