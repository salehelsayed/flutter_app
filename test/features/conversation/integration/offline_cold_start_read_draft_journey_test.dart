import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/composer_draft_store.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

final _owner = TestEd25519Identity.fromSeedByte(96);
final _peer = TestEd25519Identity.fromSeedByte(97);
const _history = 'Already here offline — أمس';
const _newText = 'One offline intent 🌱';
const _savedDraft = 'Unsent composer draft — مسودة';

void main() {
  testWidgets(
    'TRANSPORT-005/DC-022 offline cold SQL reopen renders local history and retains one automatically recoverable new-send intent across another reopen',
    (tester) async {
      installFakeJustAudioPlatform();
      await tester.runAsync(() async {
        final journey = await _OfflineJourney.open();
        try {
          // A fresh handle/repository/listener must read the existing rows.
          await journey.reopen(tester);
          await journey.mount(tester);
          expect(find.text(_history), findsOneWidget);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          await _sendAndReopen(tester, journey, _newText);
        } finally {
          await journey.close(tester);
        }
      });
    },
  );

  testWidgets(
    'TRANSPORT-005/DC-022 typed unsent draft survives offline cold SQL and '
    'file-store reopen and sends once',
    (tester) async {
      installFakeJustAudioPlatform();
      await tester.runAsync(() async {
        final journey = await _OfflineJourney.open();
        try {
          await journey.mount(tester);
          await tester.enterText(find.byType(TextField), _savedDraft);
          await _frames(tester);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            _savedDraft,
          );
          expect(
            await journey.db.messageRepo.getMessagesForContact(_peer.peerId),
            hasLength(1),
          );
          expect(
            (await journey.drafts.load(
              ComposerDraftKey.direct(_peer.peerId),
            ))?.text,
            _savedDraft,
          );
          await journey.reopen(tester);
          await journey.mount(tester);
          expect(find.text(_history), findsOneWidget);
          // A new production file store and screen must read the saved draft;
          // no initialText or cached draft is supplied to the reopened screen.
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            _savedDraft,
          );
          await _sendAndReopen(
            tester,
            journey,
            _savedDraft,
            alreadyTyped: true,
          );
        } finally {
          await journey.close(tester);
        }
      });
    },
  );
}

Future<void> _sendAndReopen(
  WidgetTester tester,
  _OfflineJourney journey,
  String text, {
  bool alreadyTyped = false,
}) async {
  if (!alreadyTyped) await tester.enterText(find.byType(TextField), text);
  // Text entry schedules the build that enables the composer's send handler.
  await _frames(tester);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await _until(tester, () => journey.sendAttempt != null);
  final (result, sent) = await journey.sendAttempt!.timeout(
    const Duration(seconds: 15),
  );
  expect(result, SendChatMessageResult.nodeNotRunning);
  expect(sent, isNotNull);
  await _frames(tester);
  final id = sent!.id;
  final rows = await journey.db.messageRepo.getMessagesForContact(_peer.peerId);
  expect(rows.map((message) => message.text), [_history, text]);
  expect(rows.map((message) => message.id).toSet(), hasLength(2));
  final pending = rows.singleWhere((message) => message.id == id);
  expect(pending.text, text);
  expect(pending.status, 'failed');
  expect(pending.transport, isNull);
  expect(pending.wireEnvelope, isNotEmpty);
  final custody =
      (await journey.db.messageRepo.loadDirectInboxCustody()).single;
  expect(custody.messageId, id);
  expect(custody.recipientPeerId, _peer.peerId);
  expect(custody.wireEnvelope, pending.wireEnvelope);
  expect(await journey.db.messageRepo.loadAuthoredDirectTextIntents(), isEmpty);
  expect(journey.p2p.currentState.isStarted, isFalse);
  expect(journey.p2p.sendMessageCallCount, 0);
  expect(journey.p2p.sendMessageWithReplyCallCount, 0);
  expect(journey.p2p.discoverPeerCallCount, 0);
  expect(journey.p2p.dialPeerCallCount, 0);
  expect(journey.p2p.storeInInboxCallCount, 0);
  expect(journey.storedEnvelopes, isEmpty);
  _expectAutomaticPending(tester, id);
  expect(
    tester.widget<TextField>(find.byType(TextField)).controller!.text,
    isEmpty,
  );

  await journey.reopen(tester);
  await journey.mount(tester);
  expect(find.text(_history), findsOneWidget);
  expect(find.text(text), findsOneWidget);
  _expectAutomaticPending(tester, id);
  final reopened = (await journey.db.messageRepo.getMessagesForContact(
    _peer.peerId,
  )).singleWhere((message) => !message.isIncoming);
  expect(reopened.id, id);
  expect(reopened.text, text);
  expect(reopened.status, 'failed');
  expect(reopened.transport, isNull);
  expect(reopened.wireEnvelope, custody.wireEnvelope);

  // The existing automatic recovery entry point keeps the same opaque owner
  // when the host's offline relay substitute refuses custody. No manual Retry
  // is introduced, and this test never creates a socket or a second message.
  final recoveryWires = <String>[];
  expect(
    await drainDirectInboxCustodyOutbox(
      custodyRepository: journey.db.messageRepo,
      storeInAckCustodyInboxDetailed:
          (peer, envelope, {required custodyKind, timeoutMs}) async {
            expect(peer, _peer.peerId);
            recoveryWires.add(envelope);
            return const InboxStoreOutcome(
              status: InboxStoreStatus.failed,
              errorCode: 'HOST_OFFLINE',
            );
          },
    ),
    0,
  );
  expect(recoveryWires, [custody.wireEnvelope]);
  final retained =
      (await journey.db.messageRepo.loadDirectInboxCustody()).single;
  expect(retained.messageId, id);
  expect(retained.incarnationId, custody.incarnationId);
  expect(retained.wireEnvelope, custody.wireEnvelope);
  expect(
    (await journey.db.messageRepo.getMessagesForContact(
      _peer.peerId,
    )).map((message) => message.id),
    rows.map((message) => message.id),
  );
  await journey.reopen(tester);
  await journey.mount(tester);
  expect(find.text(text), findsOneWidget);
  expect(find.text(_history), findsOneWidget);
  _expectAutomaticPending(tester, id);
  expect(
    (await journey.db.messageRepo.loadDirectInboxCustody()).single.messageId,
    id,
  );
}

void _expectAutomaticPending(WidgetTester tester, String id) {
  final row = find.byKey(ValueKey('msg-$id'));
  expect(row, findsOneWidget);
  final card = tester.widget<LetterCard>(
    find.descendant(of: row, matching: find.byType(LetterCard)),
  );
  // Persisted failed+envelope is presented as automatic pending, including
  // cold reopen. A terminal Retry or delivered glyph would be false here.
  expect(card.status, 'sending');
  expect(card.transport, isNull);
  expect(find.descendant(of: row, matching: find.text('Retry')), findsNothing);
  final labels = tester
      .widgetList<Semantics>(
        find.descendant(of: row, matching: find.byType(Semantics)),
      )
      .map((widget) => widget.properties.label)
      .whereType<String>();
  expect(labels, contains('Message status: sending'));
  expect(
    labels.where(
      (label) => label.contains('delivered') || label.contains('sent via'),
    ),
    isEmpty,
  );
}

class _OfflineJourney {
  _OfflineJourney(this.root, this.db)
    : drafts = FileComposerDraftStore(documentsDirectory: () async => root);
  final Directory root;
  MediaRepositoryRealDbFixture db;
  FileComposerDraftStore drafts;
  final bridge = PassthroughCryptoBridge();
  final p2p = FakeP2PService();
  final storedEnvelopes = <String>[];
  ChatMessageListener? listener;
  Future<(SendChatMessageResult, ConversationMessage?)>? sendAttempt;

  static Future<_OfflineJourney> open() async {
    final root = await Directory.systemTemp.createTemp('offline-cold-');
    final db = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/identity.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    final journey = _OfflineJourney(root, db);
    await buildWidgetContactRepository(db.db).addContact(journey.contact);
    await db.messageRepo.saveMessage(
      ConversationMessage(
        id: 'offline-local-history',
        contactPeerId: _peer.peerId,
        senderPeerId: _peer.peerId,
        text: _history,
        timestamp: '2026-10-20T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-10-20T10:00:00.000Z',
      ),
    );
    return journey;
  }

  ContactModel get contact => ContactModel(
    peerId: _peer.peerId,
    publicKey: _peer.publicKey,
    username: 'Offline peer',
    rendezvous: 'test-only-offline',
    signature: 'test-only-signature',
    scannedAt: '2026-10-20T10:00:00.000Z',
    mlKemPublicKey: 'test-only-peer-mlkem',
  );

  Future<void> mount(WidgetTester tester) async {
    final contacts = buildWidgetContactRepository(db.db);
    listener = ChatMessageListener(
      chatMessageStream: const Stream.empty(),
      messageRepo: db.messageRepo,
      contactRepo: contacts,
    );
    final identity = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: _owner.peerId,
          publicKey: _owner.publicKey,
          privateKey: _owner.privateKey,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: contact,
          identityRepo: identity,
          messageRepo: db.messageRepo,
          chatMessageListener: listener!,
          p2pService: p2p,
          bridge: bridge,
          contactRepo: contacts,
          composerDraftStore: drafts,
          micPermissionGateway: FakeMicPermissionGateway(),
          sendChatMessageFn:
              ({
                required p2pService,
                required messageRepo,
                required targetPeerId,
                required text,
                required senderPeerId,
                required senderUsername,
                messageId,
                required preassignedMessageIdIsFresh,
                authoredTextIntentToken,
                timestamp,
                bridge,
                recipientMlKemPublicKey,
                quotedMessageId,
                mediaAttachments,
                privateMediaPolicy,
                mediaAttachmentRepo,
                transportMetrics,
                directEventFanout,
              }) {
                return sendAttempt = sendChatMessage(
                  p2pService: p2pService,
                  messageRepo: messageRepo,
                  targetPeerId: targetPeerId,
                  text: text,
                  senderPeerId: senderPeerId,
                  senderUsername: senderUsername,
                  messageId: messageId,
                  preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
                  authoredTextIntentToken: authoredTextIntentToken,
                  timestamp: timestamp,
                  bridge: bridge,
                  recipientMlKemPublicKey: recipientMlKemPublicKey,
                  quotedMessageId: quotedMessageId,
                  mediaAttachments: mediaAttachments,
                  privateMediaPolicy: privateMediaPolicy,
                  mediaAttachmentRepo: mediaAttachmentRepo,
                  transportMetrics: transportMetrics,
                  directEventFanout: directEventFanout,
                  storeInAckCustodyInboxDetailed:
                      (
                        peer,
                        envelope, {
                        required custodyKind,
                        timeoutMs,
                      }) async {
                        storedEnvelopes.add(envelope);
                        return const InboxStoreOutcome(
                          status: InboxStoreStatus.failed,
                          errorCode: 'HOST_OFFLINE',
                        );
                      },
                );
              },
        ),
      ),
    );
    // Queue behind the screen's initial load before typing or asserting restore.
    await drafts.load(ComposerDraftKey.direct(_peer.peerId));
    await _until(
      tester,
      () =>
          find.byType(ConversationScreen).evaluate().isNotEmpty &&
          find.text(_history).evaluate().isNotEmpty,
    );
  }

  Future<void> reopen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Disposal queues the final autosave; drain it before discarding this store.
    await drafts.load(ComposerDraftKey.direct(_peer.peerId));
    listener?.dispose();
    listener = null;
    db = await db.reopen();
    drafts = FileComposerDraftStore(documentsDirectory: () async => root);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await drafts.load(ComposerDraftKey.direct(_peer.peerId));
    listener?.dispose();
    p2p.dispose();
    bridge.dispose();
    await db.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'the offline SQL-backed conversation must load',
  );
  await _frames(tester);
}
