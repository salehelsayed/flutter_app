import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// Minimal fakes (same pattern as conversation_wired_test.dart)
// ---------------------------------------------------------------------------

class _FakeIdentityRepository implements IdentityRepository {
  final IdentityModel? identity;
  _FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;
  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeMessageRepository
    implements MessageRepository, MessageRepositoryChangeSource {
  final Map<String, ConversationMessage> store = {};
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  /// Simulate a background status change (e.g., pause handler transitioning
  /// sending -> failed). This updates the store AND emits on messageChanges,
  /// exactly like MessageRepositoryImpl.conditionalTransitionStatus does.
  void emitStatusChange(String id, String newStatus) {
    final msg = store[id];
    if (msg == null) return;
    final updated = msg.copyWith(status: newStatus);
    store[id] = updated;
    _messageChangeController.add(updated);
  }

  /// 184 TC-184-22: emit a FULL message-change (status + transport) on
  /// messageChanges, mirroring MessageRepositoryImpl.saveMessage's stream emit,
  /// so a test can drive the sending → inboxed(2-tick) → delivered(transport)
  /// progression where the terminal carries a real transport label.
  void emitMessageChange(ConversationMessage updated) {
    store[updated.id] = updated;
    _messageChangeController.add(updated);
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    store[message.id] = message;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final msg = store[id];
    if (msg == null) return;
    store[id] = msg.copyWith(status: status);
    _messageChangeController.add(store[id]!);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async =>
      store.values.where((m) => m.contactPeerId == contactPeerId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final msgs = await getMessagesForContact(contactPeerId);
    return msgs.isEmpty ? null : msgs.last;
  }

  @override
  Future<bool> messageExists(String id) async => store.containsKey(id);

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      store.values.where((m) => m.contactPeerId == contactPeerId).length;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteMessage(String id) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    var messages = store.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages.take(limit).toList().reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<ConversationMessage?> getMessage(String id) async => store[id];

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    final msg = store[id];
    if (msg != null && msg.status == fromStatus) {
      final updated = msg.copyWith(status: toStatus);
      store[id] = updated;
      _messageChangeController.add(updated);
      return 1;
    }
    return 0;
  }
}

class _FakeContactRepository implements ContactRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Return appropriate defaults for non-Future methods
    if (invocation.memberName == Symbol('getActiveContacts')) {
      return Future<List<ContactModel>>.value([]);
    }
    if (invocation.memberName == Symbol('getContact')) {
      return Future<ContactModel?>.value(null);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _contactPeerId = 'peer-bob';

final _identity = IdentityModel(
  peerId: 'me',
  publicKey: 'my-pk',
  privateKey: 'my-sk',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

final _contact = ContactModel(
  peerId: _contactPeerId,
  publicKey: 'bob-pk',
  rendezvous: '/ip4/127.0.0.1/tcp/4001',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: '2026-01-01T00:00:00.000Z',
);

ConversationMessage _makeSendingMessage() => ConversationMessage(
  id: 'msg-sending-001',
  contactPeerId: _contactPeerId,
  senderPeerId: 'me',
  text: 'Hello Bob',
  timestamp: '2026-01-01T00:00:00.000Z',
  status: 'sending',
  isIncoming: false,
  createdAt: '2026-01-01T00:00:00.000Z',
);

Widget _buildTestWidget({
  required _FakeMessageRepository messageRepo,
  List<ConversationMessage>? initialMessages,
  SendChatMessageFn? sendChatMessageFn,
}) {
  final chatListener = ChatMessageListener(
    chatMessageStream: const Stream<ChatMessage>.empty(),
    messageRepo: messageRepo,
    contactRepo: _FakeContactRepository(),
  );

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: ConversationWired(
      contact: _contact,
      identityRepo: _FakeIdentityRepository(_identity),
      messageRepo: messageRepo,
      chatMessageListener: chatListener,
      p2pService: FakeP2PService(),
      bridge: FakeBridge(),
      sendChatMessageFn: sendChatMessageFn ?? _noOpSendChatMessage,
      initialMessages: initialMessages,
      audioRecorderService: FakeAudioRecorderService(),
    ),
  );
}

/// F5: a send that resolves only after [delay], mirroring the helper-capped
/// degradation (a boundary-stalled send that the `callP2PMessageSend` timeout
/// turns into a ~2.5s durable-inbox fallback rather than an instant ack).
SendChatMessageFn _delayedSuccessSend(Duration delay) {
  return ({
    required P2PService p2pService,
    required MessageRepository messageRepo,
    required String targetPeerId,
    required String text,
    required String senderPeerId,
    required String senderUsername,
    String? messageId,
    String? timestamp,
    dynamic bridge,
    String? recipientMlKemPublicKey,
    String? quotedMessageId,
    List<MediaAttachment>? mediaAttachments,
    MediaAttachmentRepository? mediaAttachmentRepo,
    TransportMetrics? transportMetrics,
  }) async {
    await Future<void>.delayed(delay);
    return (SendChatMessageResult.success, null);
  };
}

Future<(SendChatMessageResult, ConversationMessage?)> _noOpSendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  dynamic bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  TransportMetrics? transportMetrics,
}) async {
  return (SendChatMessageResult.success, null);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConversationWired — sending->failed UI refresh', () {
    testWidgets(
      'message transitions from sending to failed via messageChanges stream '
      'and UI rebuilds with the failed indicator icon',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final sendingMessage = _makeSendingMessage();

        // Seed the message in the repo so getMessagesPage returns it
        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            initialMessages: [sendingMessage],
          ),
        );
        // Pump to trigger post-frame callback (initialLoadDone = true),
        // async identity load, and LetterCard fade-in animation
        await tester.pump(); // post-frame callback + start async
        await tester.pump(const Duration(seconds: 1)); // identity + animation
        await tester.pump(const Duration(seconds: 1)); // ensure fully visible

        // ASSERT — the message is currently displayed with status 'sending'.
        // In the 1:1 transport glyph contract, in-flight sends render a single
        // tick (the clock→tick change) until they reach a terminal
        // transport/status.
        expect(
          find.byIcon(Icons.done_rounded),
          findsOneWidget,
          reason:
              'Before the status change, the card must show the sending single tick',
        );
        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsNothing,
          reason: 'No failed indicator should be visible yet',
        );

        // ACT — simulate the pause handler emitting a status change on
        // messageChanges. This is exactly what conditionalTransitionStatus()
        // does in MessageRepositoryImpl when it transitions sending->failed.
        messageRepo.emitStatusChange('msg-sending-001', 'failed');

        // Let the stream event propagate and the widget rebuild. 159: the
        // messageChanges upsert applies its DATA synchronously but defers the
        // rebuild to the per-frame coalesced flush (post-frame), so pump an
        // extra frame for the flush's setState to render.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        // ASSERT — the UI must now show the failed indicator, not the
        // in-flight single tick.
        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsOneWidget,
          reason: 'The failed status must render error_outline_rounded',
        );
        expect(
          find.byIcon(Icons.done_rounded),
          findsNothing,
          reason:
              'The sending single tick must no longer be visible after transition to failed',
        );
      },
    );

    testWidgets(
      'F5: a slow send (durable inbox-custody fallback) never surfaces a '
      '"sending is taking longer" hint — it confuses users',
      (tester) async {
        final messageRepo = _FakeMessageRepository();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            // Resolves after 2s — mirrors the helper-capped durable fallback,
            // i.e. a send that "switches to inbox" custody and resolves slowly.
            sendChatMessageFn: _delayedSuccessSend(const Duration(seconds: 2)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        const hintText = 'Sending is taking longer…';

        // Drive a real send: type text, tap the send button.
        await tester.enterText(find.byType(TextField).first, 'hi there');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        // Below the old ~1.5s threshold: no hint.
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text(hintText), findsNothing);

        // Past the old threshold (~1.6s) but before the 2s resolution, while
        // still sending: the hint must STILL not appear (it was removed).
        await tester.pump(const Duration(milliseconds: 800));
        expect(
          find.text(hintText),
          findsNothing,
          reason: 'the "taking longer" hint must never be shown to the user',
        );

        // Through resolution at 2s: still nothing.
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(hintText), findsNothing);
      },
    );

    testWidgets(
      'message transitions from sending to sent still works after adding '
      'failed to the refresh filter',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final sendingMessage = _makeSendingMessage();

        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Before: sending status (single tick, clock→tick)
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);

        // ACT — normal send completion path
        messageRepo.emitStatusChange('msg-sending-001', 'sent');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(); // 159: per-frame coalesced flush rebuild

        // ASSERT — sent refreshes to the reached fallback icon when no
        // transport-specific glyph is available.
        expect(
          find.byIcon(Icons.done_rounded),
          findsOneWidget,
          reason: 'sent status transition must still refresh the UI',
        );
      },
    );

    testWidgets(
      'message transitions from sending to delivered still works after '
      'adding failed to the refresh filter',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final sendingMessage = _makeSendingMessage();

        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Before: sending status (single tick, clock→tick)
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);

        // ACT — ACK received, message delivered
        messageRepo.emitStatusChange('msg-sending-001', 'delivered');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(); // 159: per-frame coalesced flush rebuild

        // ASSERT — delivered refreshes to the reached fallback icon when no
        // transport-specific glyph is available.
        expect(
          find.byIcon(Icons.done_rounded),
          findsOneWidget,
          reason: 'delivered status transition must still refresh the UI',
        );
      },
    );

    // 184 TC-184-22 — the full honest progression on the 1:1 surface:
    // sending (1 tick) → inboxed custody (2 ticks, ~110 ms) → delivered live
    // (transport glyph). RED on HEAD: 'inboxed' renders the single-check
    // fallback, not done_all. Pins the mid-send re-render (TC-184-11) too.
    testWidgets(
      'sending → inboxed (two ticks) → delivered (transport glyph) progression',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final sendingMessage = _makeSendingMessage();

        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // 1 tick — the optimistic 'sending' state.
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // ~110 ms custody ACK → 'inboxed' → two ticks (done_all).
        messageRepo.emitStatusChange('msg-sending-001', 'inboxed');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(
          find.byIcon(Icons.done_all_rounded),
          findsOneWidget,
          reason: 'custody (inboxed) must render the two-tick on the 1:1 surface',
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);

        // Live delivery → the transport glyph (device_hub for 'direct'),
        // upgrading off the two-tick.
        messageRepo.emitMessageChange(
          sendingMessage.copyWith(status: 'delivered', transport: 'direct'),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byIcon(Icons.device_hub), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      },
    );
  });
}
