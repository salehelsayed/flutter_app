import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../test/features/conversation/application/send_chat_message_use_case_test.dart' as fixtures;

const _messageId = 'early-receipt-original-message';

ChatMessage _receipt() => ChatMessage(
  from: 'target-peer',
  to: 'my-peer',
  timestamp: '2026-09-09T19:30:00.000Z',
  isIncoming: true,
  transport: 'direct',
  content: jsonEncode({
    'type': 'delivery_receipt',
    'payload': {'messageIds': [_messageId]},
  }),
);

class _ReceiptDuringSend extends fixtures.FakeP2PService {
  _ReceiptDuringSend(this.repository, {required this.nativeAck});

  final fixtures.FakeMessageRepository repository;
  final bool nativeAck;
  int earlyReceipts = 0;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (earlyReceipts == 0) {
      earlyReceipts++;
      expect((await repository.getMessage(_messageId))!.status, 'sending');
      await handleDeliveryReceipt(message: _receipt(), messageRepo: repository);
    }
    return SendMessageResult(sent: true, acked: nativeAck, transport: 'direct');
  }
}

Future<void> _send(
  fixtures.FakeMessageRepository repository,
  _ReceiptDuringSend service,
) async {
  await fixtures.sendChatMessage(
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
  test('early valid receipt survives a lost native ACK', () async {
    final repository = fixtures.FakeMessageRepository();
    final service = _ReceiptDuringSend(repository, nativeAck: false);
    await _send(repository, service);
    expect(service.earlyReceipts, 1);
    final row = (await repository.getMessage(_messageId))!;
    expect(row.status, 'delivered', reason: 'the valid receiver receipt is independent delivery proof');
    expect(row.wireEnvelope, isNull);
  });

  test('native committed ACK repairs the ignored early receipt', () async {
    final repository = fixtures.FakeMessageRepository();
    final service = _ReceiptDuringSend(repository, nativeAck: true);
    await _send(repository, service);
    expect(service.earlyReceipts, 1);
    expect((await repository.getMessage(_messageId))!.status, 'delivered');
  });

  test('replayed receipt after send settlement repairs delivery status', () async {
    final repository = fixtures.FakeMessageRepository();
    final service = _ReceiptDuringSend(repository, nativeAck: false);
    await _send(repository, service);
    expect((await repository.getMessage(_messageId))!.status, 'sent');
    await handleDeliveryReceipt(message: _receipt(), messageRepo: repository);
    final row = (await repository.getMessage(_messageId))!;
    expect(row.status, 'delivered');
    expect(row.wireEnvelope, isNull);
  });
}
