import 'dart:convert';

import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
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
