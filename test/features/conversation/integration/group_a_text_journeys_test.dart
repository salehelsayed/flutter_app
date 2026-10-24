import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import 'two_user_message_exchange_test.dart' as exchange;

class _TranscriptNetwork extends FakeP2PNetwork {
  final frames = <({String from, String to, String wire})>[];
  @override
  Future<bool> deliver(
    String fromPeerId,
    String toPeerId,
    String content, {
    String transport = 'direct',
  }) {
    frames.add((from: fromPeerId, to: toPeerId, wire: content));
    return super.deliver(fromPeerId, toPeerId, content, transport: transport);
  }

  @override
  bool storeInInbox(String fromPeerId, String toPeerId, String content) {
    frames.add((from: fromPeerId, to: toPeerId, wire: content));
    return super.storeInInbox(fromPeerId, toPeerId, content);
  }

  @override
  InboxStoreOutcome storeInInboxDetailed(
    String fromPeerId,
    String toPeerId,
    String content,
  ) {
    frames.add((from: fromPeerId, to: toPeerId, wire: content));
    return super.storeInInboxDetailed(fromPeerId, toPeerId, content);
  }
}

void main() {
  test(
    'DC-002 DC-014 one hundred numbered messages survive both SQL/runtime restarts and inbox replay',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'astra-numbered-chat-',
      );
      var leftDb = await MediaRepositoryRealDbFixture.create(
        databasePath: '${directory.path}/left.db',
      );
      var rightDb = await MediaRepositoryRealDbFixture.create(
        databasePath: '${directory.path}/right.db',
      );
      final network = _TranscriptNetwork();
      final bridge = PassthroughCryptoBridge();
      final leftContacts = InMemoryContactRepository();
      final rightContacts = InMemoryContactRepository();
      ContactModel contact(String id) => ContactModel(
        peerId: id,
        publicKey: 'synthetic-signing-$id',
        rendezvous: 'synthetic-relay',
        username: id,
        signature: 'synthetic-signature',
        scannedAt: '2026-10-01T00:00:00.000Z',
        mlKemPublicKey: 'synthetic-kem-$id',
      );
      leftContacts.addTestContact(contact('right'));
      rightContacts.addTestContact(contact('left'));
      late FakeP2PService left;
      late FakeP2PService right;
      late ChatMessageListener leftListener;
      late ChatMessageListener rightListener;
      void start() {
        left = FakeP2PService(peerId: 'left', network: network);
        right = FakeP2PService(peerId: 'right', network: network);
        leftListener = ChatMessageListener(
          chatMessageStream: left.messageStream,
          messageRepo: leftDb.messageRepo,
          contactRepo: leftContacts,
          mediaAttachmentRepo: leftDb.repo,
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'synthetic-own-kem',
        );
        rightListener = ChatMessageListener(
          chatMessageStream: right.messageStream,
          messageRepo: rightDb.messageRepo,
          contactRepo: rightContacts,
          mediaAttachmentRepo: rightDb.repo,
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'synthetic-own-kem',
        );
        leftListener.start();
        rightListener.start();
      }

      void stop() {
        leftListener.dispose();
        rightListener.dispose();
        left.dispose();
        right.dispose();
      }

      start();
      addTearDown(() async {
        stop();
        await leftDb.dispose();
        await rightDb.dispose();
        directory.deleteSync(recursive: true);
      });
      final expected =
          <({String id, String text, bool fromLeft, String wire})>[];
      Future<void> send(int number, {bool offline = false}) async {
        final fromLeft = number.isOdd;
        final sender = fromLeft ? left : right;
        final receiver = fromLeft ? right : left;
        final recipientListener = fromLeft ? rightListener : leftListener;
        final text = 'Message ${number.toString().padLeft(3, '0')}';
        if (offline) receiver.setOnline(false);
        final received = recipientListener.incomingMessageStream
            .firstWhere((m) => m.text == text)
            .timeout(const Duration(seconds: 5));
        final (result, sent) = await sendChatMessage(
          p2pService: sender,
          messageRepo: fromLeft ? leftDb.messageRepo : rightDb.messageRepo,
          targetPeerId: receiver.peerId,
          text: text,
          senderPeerId: sender.peerId,
          senderUsername: sender.peerId,
          bridge: bridge,
          recipientMlKemPublicKey: 'synthetic-kem-${receiver.peerId}',
        );
        expect(result, SendChatMessageResult.success);
        expect(sent, isNotNull);
        final sentMessage = sent!;
        if (offline) {
          expect(sentMessage.status, 'inboxed');
          receiver.setOnline(true);
          // Earlier accepted custody copies may also replay; the exact
          // transcript below must still contain each numbered message once.
          await receiver.drainOfflineInbox();
        }
        final incoming = await received;
        expect(incoming.id, sentMessage.id);
        expect(incoming.text, text);
        expected.add((
          id: sentMessage.id,
          text: text,
          fromLeft: fromLeft,
          wire: network.frames
              .lastWhere(
                (f) => f.from == sender.peerId && f.to == receiver.peerId,
              )
              .wire,
        ));
      }

      Future<void> verify() async {
        for (final isLeft in [true, false]) {
          final messages = await loadConversation(
            messageRepo: isLeft ? leftDb.messageRepo : rightDb.messageRepo,
            contactPeerId: isLeft ? 'right' : 'left',
          );
          expect(
            messages.map((m) => m.id).toList(),
            expected.map((m) => m.id).toList(),
          );
          expect(
            messages.map((m) => m.text).toList(),
            expected.map((m) => m.text).toList(),
          );
          expect(
            messages.map((m) => m.isIncoming).toList(),
            expected.map((m) => isLeft ? !m.fromLeft : m.fromLeft).toList(),
          );
          expect(messages.map((m) => m.id).toSet(), hasLength(expected.length));
        }
      }

      for (var number = 1; number <= 100; number++) {
        await send(number, offline: number == 49 || number == 74);
        if (number % 25 == 0) {
          await verify();
          // Retain duplicate transport custody independently of either runtime.
          for (final row in expected.where(
            (m) => m.text.endsWith('0') || m.text.endsWith('1'),
          )) {
            expect(
              network.storeInInbox(
                row.fromLeft ? 'left' : 'right',
                row.fromLeft ? 'right' : 'left',
                row.wire,
              ),
              isTrue,
            );
          }
          stop();
          leftDb = await leftDb.reopen();
          rightDb = await rightDb.reopen();
          start();
          await verify();
          await left.drainOfflineInbox();
          await right.drainOfflineInbox();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await verify();
        }
      }
      expect(expected, hasLength(100));
      await send(101);
      await send(102);
      await verify();
    },
  );

  testWidgets(
    'ACCESS-001 mixed Arabic English long text and emoji retain recipient content and direction',
    (tester) async {
      late exchange.TestUser alice;
      late exchange.TestUser bob;
      await tester.runAsync(() async {
        final network = exchange.FakeP2PNetwork();
        alice = exchange.TestUser.create(
          peerId: 'left',
          username: 'Alice',
          network: network,
        );
        bob = exchange.TestUser.create(
          peerId: 'right',
          username: 'ليلى',
          network: network,
        );
        alice.addContact(bob);
        bob.addContact(alice);
        alice.start();
        bob.start();
      });
      addTearDown(() {
        alice.dispose();
        bob.dispose();
      });
      final samples = [
        ('مرحبا Alice 👩🏽‍💻 123', TextDirection.rtl),
        ('Hello ليلى 👨‍👩‍👧‍👦 123', TextDirection.ltr),
        ('👩🏽‍💻 مرحبا Alpha 👨‍👩‍👧‍👦', TextDirection.rtl),
        (
          'Hello ${List.filled(120, 'ليلى 👩🏽‍💻 Alpha').join(' ')}',
          TextDirection.ltr,
        ),
      ];
      final received = <ConversationMessage>[];
      await tester.runAsync(() async {
        for (final sample in samples) {
          final incoming = bob.chatListener.incomingMessageStream.first.timeout(
            const Duration(seconds: 3),
          );
          final (result, sent) = await alice.sendMessage(bob.peerId, sample.$1);
          expect(result, SendChatMessageResult.success);
          final message = await incoming;
          expect(message.id, sent!.id);
          expect(message.text, sample.$1);
          received.add(message);
        }
        expect(
          (await bob.loadConversation(
            alice.peerId,
          )).map((m) => m.text).toList(),
          samples.map((s) => s.$1).toList(),
        );
      });
      for (var index = 0; index < samples.length; index++) {
        final message = received[index];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: message.senderPeerId,
                  senderName: 'Alice',
                  text: message.text,
                  time: '12:00',
                  isIncoming: true,
                  bubbleLayout: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final body = find.byWidgetPredicate(
          (w) => w is LinkableText && w.text == samples[index].$1,
        );
        expect(body, findsOneWidget);
        expect(
          tester.widget<LinkableText>(body).textDirection,
          samples[index].$2,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
