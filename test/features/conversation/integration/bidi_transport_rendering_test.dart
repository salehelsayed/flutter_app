import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  final examples = <String, (String, TextDirection)>{
    'Arabic': ('مرحبا بالعالم، كيف الحال؟', TextDirection.rtl),
    'mixed first-strong Arabic': ('مرحبا Hello 👩🏽‍💻', TextDirection.rtl),
    'emoji and mixed first-strong Latin': (
      '👨‍👩‍👧‍👦 Hello مرحبا 👍🏽 ❤️',
      TextDirection.ltr,
    ),
    'supported long text': (
      List.filled(80, 'مرحبا Hello 👩🏽‍💻 0123456789').join(' '),
      TextDirection.rtl,
    ),
  };
  for (final entry in examples.entries) {
    testWidgets(
      'DC-014 two-peer ${entry.key} retains content and bubble direction',
      (tester) async {
        final (input, direction) = entry.value;
        final rows = await tester.runAsync(() async {
          final network = FakeP2PNetwork();
          final alice = TestUser.create(
            peerId: '12D3KooWBidiAliceFixture00001',
            username: 'Alice',
            network: network,
          );
          final bob = TestUser.create(
            peerId: '12D3KooWBidiBobFixture0000002',
            username: 'Bob',
            network: network,
          );
          alice.addContact(bob);
          bob.addContact(alice);
          alice.start();
          bob.start();
          try {
            final received = bob.chatListener.incomingMessageStream.first;
            final (result, sent) = await alice.sendMessage(bob.peerId, input);
            expect(result, SendChatMessageResult.success);
            final incoming = await received.timeout(const Duration(seconds: 3));
            final senderRows = await alice.loadConversationWith(bob.peerId);
            final receiverRows = await bob.loadConversationWith(alice.peerId);
            expect(senderRows.single.id, sent!.id);
            expect(receiverRows.single.id, sent.id);
            expect(incoming.id, sent.id);
            expect(senderRows.single.text, input);
            expect(receiverRows.single.text, input);
            return <ConversationMessage>[
              senderRows.single,
              receiverRows.single,
            ];
          } finally {
            alice.dispose();
            bob.dispose();
          }
        });
        // Render the persisted values from BOTH peers, rather than comparing a
        // separately seeded widget string to a transport-only assertion.
        for (var peer = 0; peer < rows!.length; peer++) {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: LetterCard(
                    senderPeerId: 'fixture-author',
                    senderName: 'Alice',
                    text: rows[peer].text,
                    time: '12:00',
                    isIncoming: peer == 1,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final rich = tester.widget<RichText>(
            find.descendant(
              of: find.byType(LinkableText),
              matching: find.byType(RichText),
            ),
          );
          expect(rich.text.toPlainText(), contains(input));
          expect(rich.textDirection, direction);
          expect(rich.maxLines, isNull);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
