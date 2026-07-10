import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
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
      text: 'goto letter $i',
      timestamp: ts,
      status: 'delivered',
      isIncoming: true,
      createdAt: ts,
    );
  }

  const libraryButtonKey = ValueKey('test-library-goto-button');

  /// Pumps a ConversationWired whose shared-media route is a stand-in that
  /// pops a [DirectSharedMediaGoToMessage] for [targetMessageId].
  Future<void> pumpWired(
    WidgetTester tester, {
    required GatedPageMessageRepository messageRepo,
    required String targetMessageId,
    required List<String> revealed,
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
          sharedMediaLibraryRouteBuilder: (routeContext) => Scaffold(
            body: Center(
              child: TextButton(
                key: libraryButtonKey,
                onPressed: () => Navigator.of(routeContext).pop(
                  DirectSharedMediaGoToMessage(targetMessageId),
                ),
                child: const Text('go to target'),
              ),
            ),
          ),
          revealConversationMessageFn: (messageId) async {
            revealed.add(messageId);
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openLibraryAndRequestGoTo(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('conversation-shared-media-action')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(libraryButtonKey));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'loaded target reveals exact message and preserves conversation window',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messageRepo = GatedPageMessageRepository();
      for (var i = 0; i < 10; i++) {
        await messageRepo.saveMessage(makeMessage(i));
      }
      final revealed = <String>[];
      await pumpWired(
        tester,
        messageRepo: messageRepo,
        targetMessageId: 'msg-goto-3',
        revealed: revealed,
      );
      expect(messageRepo.pageRequests, hasLength(1));

      await openLibraryAndRequestGoTo(tester);

      // The exact stable message key was revealed exactly once with NO
      // additional page load (the target is already in the window) and the
      // transient highlight sits on exactly that row.
      expect(revealed, ['msg-goto-3']);
      expect(messageRepo.pageRequests, hasLength(1));
      expect(
        find.byKey(const ValueKey('conversation-highlight-msg-goto-3')),
        findsOneWidget,
      );

      // The highlight clears; the loaded window and composer state remain.
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const ValueKey('conversation-highlight-msg-goto-3')),
        findsNothing,
      );
      expect(find.textContaining('goto letter 9'), findsOneWidget);
      expect(
        tester.testTextInput.hasAnyClients,
        isFalse,
        reason: 'Go to Message must not steal composer focus',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unloaded target pages backward boundedly then reveals exact row',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 120 messages: the initial window is 70..119, older page 1 is
      // 20..69, older page 2 is 0..19. Target msg-goto-10 needs exactly two
      // serial older loads.
      final messageRepo = GatedPageMessageRepository();
      for (var i = 0; i < 120; i++) {
        await messageRepo.saveMessage(makeMessage(i));
      }
      final revealed = <String>[];
      await pumpWired(
        tester,
        messageRepo: messageRepo,
        targetMessageId: 'msg-goto-10',
        revealed: revealed,
      );
      expect(messageRepo.pageRequests, hasLength(1));

      messageRepo.gatePageRequests = true;
      await openLibraryAndRequestGoTo(tester);

      // SERIAL loading: exactly one older-page request is in flight while
      // gated — never a concurrent fan-out.
      expect(messageRepo.pageRequests, hasLength(2));
      expect(messageRepo.pageRequests.last, (50, tsOf(70)));
      expect(revealed, isEmpty);

      // Releasing page 1 (20..69, target still absent) triggers exactly ONE
      // more request.
      messageRepo.pageGates[0].complete();
      await tester.pump(const Duration(milliseconds: 200));
      expect(messageRepo.pageRequests, hasLength(3));
      expect(messageRepo.pageRequests.last, (50, tsOf(20)));
      expect(revealed, isEmpty);

      // Releasing page 2 (0..19) surfaces the target: the loop STOPS on the
      // match — no further page request — and reveals the exact row once.
      messageRepo.pageGates[1].complete();
      messageRepo.gatePageRequests = false;
      await tester.pump(const Duration(milliseconds: 300));
      expect(messageRepo.pageRequests, hasLength(3));
      expect(revealed, ['msg-goto-10']);

      // Pages appended in order without disturbing the live edge: the
      // newest message is still present after the reveal (no window reset),
      // and no duplicate-key exception surfaced from a double-appended row.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('goto letter 119'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing target exhausts history once and settles truthfully', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 80 messages: initial window 30..79, ONE older page (0..29, short of
    // the 50-row limit) exhausts history.
    final messageRepo = GatedPageMessageRepository();
    for (var i = 0; i < 80; i++) {
      await messageRepo.saveMessage(makeMessage(i));
    }
    final revealed = <String>[];
    await pumpWired(
      tester,
      messageRepo: messageRepo,
      targetMessageId: 'msg-goto-deleted',
      revealed: revealed,
    );
    expect(messageRepo.pageRequests, hasLength(1));

    await openLibraryAndRequestGoTo(tester);
    await tester.pump(const Duration(milliseconds: 300));

    // Finite: the call count equals the available pages (initial + the one
    // older page), then the search terminates — no retry-forever.
    expect(messageRepo.pageRequests, hasLength(2));
    expect(messageRepo.pageRequests.last, (50, tsOf(30)));

    // Truthful settle: no reveal, no highlight, no nearest-row substitute,
    // no stuck loading spinner — and the conversation stays usable.
    expect(revealed, isEmpty);
    expect(
      find.byKey(const ValueKey('conversation-highlight-msg-goto-deleted')),
      findsNothing,
    );
    expect(
      find.text('This message is no longer in the conversation'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('goto letter 79'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
