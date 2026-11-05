import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/chat_search.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import 'helpers/direct_library_test_stubs.dart';

const String kContactPeerId = '12D3KooWGotoContactPeer';
const String kOwnPeerId = '12D3KooWGotoOwnPeer';

void main() {
  ContactModel makeContact() => ContactModel(
    peerId: kContactPeerId,
    publicKey: 'pub',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-02-11T10:00:00.000Z',
  );

  IdentityModel makeIdentity() => IdentityModel(
    peerId: kOwnPeerId,
    publicKey: 'pub',
    privateKey: 'priv',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: 'Me',
    createdAt: '2026-02-11T09:00:00.000Z',
    updatedAt: '2026-02-11T09:00:00.000Z',
  );

  String tsOf(int i) =>
      DateTime.utc(2026, 2, 11, 10, 0, 0, i).toIso8601String();

  ConversationMessage makeMessage(int i) {
    final ts = tsOf(i);
    return ConversationMessage(
      id: 'msg-goto-$i',
      contactPeerId: kContactPeerId,
      senderPeerId: kContactPeerId,
      text: const {5, 100, 118, 200}.contains(i)
          ? 'letter $i: back to Dahab?'
          : 'goto letter $i',
      timestamp: ts,
      status: 'delivered',
      isIncoming: true,
      createdAt: ts,
    );
  }

  Future<void> pumpWired(
    WidgetTester tester, {
    required GatedPageMessageRepository messageRepo,
    required List<String> revealed,
    bool realReveal = false,
  }) async {
    final contactRepo = InMemoryContactRepository();
    contactRepo.addTestContact(makeContact());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: makeContact(),
          identityRepo: StubIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          ),
          p2pService: StubP2PService(),
          contactRepo: contactRepo,
          micPermissionGateway: FakeMicPermissionGateway(),
          revealConversationMessageFn: realReveal
              ? null
              : (messageId) async {
                  revealed.add(messageId);
                },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'the magnifier searches this chat newest first, loads older pages for an '
    'old match, and closing brings the header back',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messageRepo = GatedPageMessageRepository();
      for (var i = 0; i < 120; i++) {
        await messageRepo.saveMessage(makeMessage(i));
      }
      final revealed = <String>[];
      await pumpWired(tester, messageRepo: messageRepo, revealed: revealed);

      await tester.tap(find.byTooltip('Search'));
      await settle(tester);
      expect(find.byType(ChatSearchBar), findsOneWidget);
      expect(find.text('Alice'), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byType(ChatSearchBar),
          matching: find.byType(TextField),
        ),
        'dahab',
      );
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(revealed, ['msg-goto-118']);
      expect(
        find.byKey(const ValueKey('conversation-highlight-msg-goto-118')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Previous match'));
      await settle(tester);
      await tester.tap(find.byTooltip('Previous match'));
      await settle(tester);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(revealed, ['msg-goto-118', 'msg-goto-100', 'msg-goto-5']);

      await tester.tap(find.byTooltip('Close search'));
      await settle(tester);
      expect(find.byType(ChatSearchBar), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> search(WidgetTester tester, String words) async {
    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(ChatSearchBar),
        matching: find.byType(TextField),
      ),
      words,
    );
    await settle(tester);
  }

  testWidgets(
    'a message arriving or edited while searching updates the count and keeps '
    'the shown match',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messageRepo = GatedPageMessageRepository();
      for (var i = 0; i < 120; i++) {
        await messageRepo.saveMessage(makeMessage(i));
      }
      final revealed = <String>[];
      await pumpWired(tester, messageRepo: messageRepo, revealed: revealed);
      await search(tester, 'dahab');
      expect(find.text('1 of 3'), findsOneWidget);

      await messageRepo.saveMessage(makeMessage(200));
      await settle(tester);
      expect(find.text('2 of 4'), findsOneWidget);
      expect(revealed, ['msg-goto-118']);

      // The shown match loses its words.
      await messageRepo.saveMessage(
        makeMessage(118).copyWith(text: 'goto letter 118'),
      );
      await settle(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      // The match now shown in its place is brought into view.
      expect(revealed, ['msg-goto-118', 'msg-goto-100']);
    },
  );

  testWidgets('stepping back to a newer match scrolls the list to it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messageRepo = GatedPageMessageRepository();
    for (var i = 0; i < 120; i++) {
      await messageRepo.saveMessage(makeMessage(i));
    }
    await pumpWired(
      tester,
      messageRepo: messageRepo,
      revealed: [],
      realReveal: true,
    );
    await search(tester, 'dahab');
    await tester.tap(find.byTooltip('Previous match'));
    await settle(tester);
    await tester.tap(find.byTooltip('Previous match'));
    await settle(tester);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('msg-msg-goto-5')), findsOneWidget);

    await tester.tap(find.byTooltip('Next match'));
    await settle(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    final row = find.byKey(const ValueKey('msg-msg-goto-100'));
    expect(row, findsOneWidget);
    final list = tester.getRect(find.byKey(const ValueKey('messages')));
    expect(list.contains(tester.getCenter(row)), isTrue);
  });

  testWidgets(
    'closing search while a far match is still loading leaves the chat where '
    'it was',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messageRepo = GatedPageMessageRepository();
      for (var i = 0; i < 120; i++) {
        await messageRepo.saveMessage(makeMessage(i));
      }
      await pumpWired(
        tester,
        messageRepo: messageRepo,
        revealed: [],
        realReveal: true,
      );
      await search(tester, 'dahab');
      expect(find.text('1 of 3'), findsOneWidget);

      messageRepo.gatePageRequests = true;
      await tester.tap(find.byTooltip('Previous match'));
      await settle(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(messageRepo.pageGates, hasLength(1));

      await tester.tap(find.byTooltip('Close search'));
      await settle(tester);
      expect(find.byType(ChatSearchBar), findsNothing);
      for (var i = 0; i < messageRepo.pageGates.length; i++) {
        messageRepo.pageGates[i].complete();
        await settle(tester);
      }

      // The abandoned jump asks for no further page, moves nothing and
      // highlights nothing; the chat is back at its live edge.
      expect(messageRepo.pageGates, hasLength(1));
      expect(find.byKey(const ValueKey('msg-msg-goto-119')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversation-highlight-msg-goto-5')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
