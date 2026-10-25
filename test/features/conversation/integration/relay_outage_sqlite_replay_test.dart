import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  testWidgets(
    'DC-017 queued text survives relay outage, SQLite restart and repeated replay in order',
    (tester) async {
      // Component transport seam: neither client goes offline. The complementary
      // Go test removes/restores the owned relay service on healthy peer links.
      final snapshots = await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp('astra_dc017_');
        var sender = await MediaRepositoryRealDbFixture.create(
          databasePath: '${temp.path}/sender.sqlite',
        );
        var receiver = await MediaRepositoryRealDbFixture.create(
          databasePath: '${temp.path}/receiver.sqlite',
        );
        final network = FakeP2PNetwork()
          ..inboxDisabled = true
          ..deliveryFails = true;
        final tx = FakeP2PService(peerId: 'dc017-sender', network: network);
        final rx = FakeP2PService(peerId: 'dc017-recipient', network: network);
        final bridge = PassthroughCryptoBridge();
        try {
          ContactModel contact(String id) => ContactModel(
            peerId: id,
            publicKey: '$id-public',
            rendezvous: 'owned-relay-fixture',
            username: 'Fixture',
            signature: 'fixture',
            scannedAt: '2026-10-24T00:00:00.000Z',
            mlKemPublicKey: '$id-mlkem',
          );
          final senderContacts = InMemoryContactRepository();
          final receiverContacts = InMemoryContactRepository();
          await senderContacts.addContact(contact(rx.peerId));
          await receiverContacts.addContact(contact(tx.peerId));
          await sender.db.insert('contacts', contact(rx.peerId).toMap());
          await receiver.db.insert('contacts', contact(tx.peerId).toMap());
          final identity = FakeIdentityRepository()
            ..seed(FakeIdentityRepository.makeIdentity(peerId: tx.peerId));
          const texts = [
            'First queued text',
            'Second queued text',
            'Third queued text',
          ];
          final ids = <String>[];
          for (final text in texts) {
            final (result, row) = await sendChatMessage(
              p2pService: tx,
              messageRepo: sender.messageRepo,
              targetPeerId: rx.peerId,
              text: text,
              senderPeerId: tx.peerId,
              senderUsername: 'Sender',
              bridge: bridge,
              recipientMlKemPublicKey: '${rx.peerId}-mlkem',
            );
            expect(result, isNot(SendChatMessageResult.success));
            expect(row, isNotNull);
            ids.add(row!.id);
          }
          final failed = await sender.messageRepo.getMessagesForContact(
            rx.peerId,
          );
          expect(failed.map((m) => m.id), ids);
          expect(
            failed.every((m) => m.status == 'failed' && m.wireEnvelope != null),
            isTrue,
          );
          expect(
            tx.currentState.isStarted && rx.currentState.isStarted,
            isTrue,
          );
          expect(network.inboxCount(rx.peerId), 0);
          expect(await receiver.db.query('messages'), isEmpty);
          final encryptions = bridge.commandLog
              .where((c) => c == 'message.encrypt')
              .length;
          sender = await sender.reopen();
          Future<int> retry() => retryFailedMessages(
            messageRepo: sender.messageRepo,
            identityRepo: identity,
            contactRepo: senderContacts,
            p2pService: tx,
            bridge: bridge,
          );
          expect(await retry(), 0);
          expect(await sender.db.query('messages'), hasLength(3));
          expect(network.inboxCount(rx.peerId), 0);

          // Only relay availability changes; client state remains started.
          network.inboxDisabled = false;
          expect(await retry(), greaterThan(0));
          expect(network.inboxCount(rx.peerId), 3);
          expect(await retry(), 0);
          expect(network.inboxCount(rx.peerId), 3);
          expect(
            bridge.commandLog.where((c) => c == 'message.encrypt'),
            hasLength(encryptions),
          );
          final queued = await rx.retrieveInbox();
          final deliveredIds = <String>[];
          for (final entry in queued) {
            final message = ChatMessage(
              from: tx.peerId,
              to: rx.peerId,
              content: entry['message'] as String,
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isIncoming: true,
              transport: 'inbox',
            );
            final admitted = await handleIncomingChatMessage(
              message: message,
              messageRepo: receiver.messageRepo,
              contactRepo: receiverContacts,
              bridge: bridge,
              ownMlKemSecretKey: 'fixture-receiver-secret',
              mediaAttachmentRepo: receiver.repo,
            );
            expect(admitted.$1, HandleChatMessageResult.chatMessage);
            deliveredIds.add(admitted.$2!.dedupKey!);
            receiver = await receiver.reopen();
            // Repeated replay after a real database reopen must not duplicate.
            await handleIncomingChatMessage(
              message: message,
              messageRepo: receiver.messageRepo,
              contactRepo: receiverContacts,
              bridge: bridge,
              ownMlKemSecretKey: 'fixture-receiver-secret',
              mediaAttachmentRepo: receiver.repo,
            );
          }
          expect(
            deliveredIds,
            ids,
            reason: 'relay retry preserves original send order',
          );
          final incoming = await receiver.messageRepo.getMessagesForContact(
            tx.peerId,
          );
          expect(incoming.map((m) => m.text), texts);
          expect(incoming.map((m) => m.dedupKey), ids);
          expect(await receiver.db.query('messages'), hasLength(3));

          network.deliveryFails = false;
          final receiptFuture = tx.messageStream
              .firstWhere(
                (message) =>
                    (jsonDecode(message.content) as Map)['type'] ==
                    'delivery_receipt',
              )
              .timeout(const Duration(seconds: 5));
          expect(
            await sendDeliveryReceipt(
              p2pService: rx,
              targetPeerId: tx.peerId,
              messageIds: deliveredIds,
            ),
            isTrue,
          );
          final receipt = await receiptFuture;
          for (var replay = 0; replay < 2; replay++) {
            await handleDeliveryReceipt(
              message: receipt,
              messageRepo: sender.messageRepo,
              mediaAttachmentRepo: sender.repo,
            );
          }
          sender = await sender.reopen();
          final delivered = await sender.messageRepo.getMessagesForContact(
            rx.peerId,
          );
          expect(delivered.map((m) => m.id), ids);
          expect(
            delivered.every(
              (m) => m.status == 'delivered' && m.wireEnvelope == null,
            ),
            isTrue,
          );
          expect(await retry(), 0);
          expect(network.inboxCount(rx.peerId), 0);
          expect(
            tx.currentState.isStarted && rx.currentState.isStarted,
            isTrue,
          );
          return (failed: failed, delivered: delivered);
        } finally {
          tx.dispose();
          rx.dispose();
          await sender.dispose();
          await receiver.dispose();
          await temp.delete(recursive: true);
        }
      });
      expect(snapshots, isNotNull);
      for (final row in [snapshots!.failed.first, snapshots.delivered.first]) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: LetterCard(
                senderPeerId: row.senderPeerId,
                senderName: 'Sender',
                text: row.text,
                time: '12:00',
                isIncoming: false,
                status: row.status,
                transport: row.transport,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(row.text), findsOneWidget);
        for (final internal in [
          'RELAY_SERVICE_UNAVAILABLE',
          'TEST_RELAY_DOWN',
          'outbox',
          'custody',
        ]) {
          expect(find.textContaining(internal), findsNothing);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
