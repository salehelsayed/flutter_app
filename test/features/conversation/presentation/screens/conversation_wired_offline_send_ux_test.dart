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
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// 170 — 1:1 send button frozen + failure SnackBar hides Send, under degraded
// network. These tests pin the two reported defects:
//   S2 (TC-01): the composer accepts a SECOND message while the first send is
//       still in flight (the Send button must not be dead for the whole
//       direct->relay->inbox round-trip).
//   S1 (TC-04): a send-failure SnackBar carries a bottom margin so it never
//       renders over the bottom composer / Send button.
// plus two preservation locks:
//   TC-03: the optimistic sending->failed bubble status survives the
//       (now background-resolving) send completion.
//   TC-02: one Send tap == exactly one outgoing message (no duplicate-send
//       once the global re-entrancy lock is relaxed).
//
// Harness mirrors conversation_wired_sending_to_failed_test.dart with a
// call-counting, per-call `Completer`-gated `SendChatMessageFn` so the test
// controls when/whether a send resolves.
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
  }) async =>
      // Mirror messages_db_helpers.dart:645-666 — the retryUnacked lane picks up
      // outgoing 'sent' rows that still carry a wire envelope. 185 asserts an
      // offline send is left in exactly this state (not terminal 'failed').
      store.values
          .where(
            (m) =>
                m.status == 'sent' &&
                !m.isIncoming &&
                (m.wireEnvelope != null && m.wireEnvelope!.isNotEmpty),
          )
          .toList();

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
    if (invocation.memberName == Symbol('getActiveContacts')) {
      return Future<List<ContactModel>>.value([]);
    }
    if (invocation.memberName == Symbol('getContact')) {
      return Future<ContactModel?>.value(null);
    }
    return null;
  }
}

/// A call-counting, per-call `Completer`-gated send. Each invocation records the
/// text, increments [callCount], and returns a future that resolves ONLY when
/// the test completes the matching `Completer` — so the test fully controls the
/// in-flight window (and can leave a send pending indefinitely).
class _GatedSendRecorder {
  int callCount = 0;
  final List<String> sentTexts = [];
  final List<String?> messageIds = [];
  final List<Completer<(SendChatMessageResult, ConversationMessage?)>>
  _completers = [];

  int get pending => _completers.length;

  /// Resolve the last in-flight send as [result] with a NULL message — the
  /// early-return failure shape (invalidMessage / nodeNotRunning /
  /// encryptionRequired) the UI handles in its `message == null` branch.
  void completeLast(SendChatMessageResult result) {
    _completers.last.complete((result, null));
  }

  /// Resolve the last in-flight send as [result] carrying a NON-NULL message —
  /// the REAL production shape of a terminal peerNotFound/dialFailed/sendFailed
  /// (send_chat_message_use_case.dart returns `failedMessage` with the wire
  /// envelope preserved). The UI handles this in its `message != null` branch.
  void completeLastWithMessage(
    SendChatMessageResult result,
    ConversationMessage message,
  ) {
    _completers.last.complete((result, message));
  }

  SendChatMessageFn get fn => ({
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
  }) {
    callCount++;
    sentTexts.add(text);
    messageIds.add(messageId);
    final completer =
        Completer<(SendChatMessageResult, ConversationMessage?)>();
    _completers.add(completer);
    return completer.future;
  };
}

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

/// A relay-unreachable node state (isStarted, but no relay/circuit) →
/// `relayReady == false` → the 185 sender-offline predicate is true.
final _offlineState = const NodeState(isStarted: true, peerId: 'me');

/// A relay-online node state → `relayReady == true` → sender is online.
final _onlineState = const NodeState(
  isStarted: true,
  peerId: 'me',
  relayState: 'online',
);

Widget _buildTestWidget({
  required _FakeMessageRepository messageRepo,
  required SendChatMessageFn sendChatMessageFn,
  P2PService? p2pService,
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
      p2pService: p2pService ?? FakeP2PService(initialState: _offlineState),
      bridge: FakeBridge(),
      sendChatMessageFn: sendChatMessageFn,
      audioRecorderService: FakeAudioRecorderService(),
    ),
  );
}

/// Settle the screen's async prologue (identity load + initial frame).
Future<void> _settleStartup(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Type [text] then tap the Send button, flushing the synchronous optimistic
/// insert + local save + the early composer release.
Future<void> _typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('ConversationWired — offline send UX (170)', () {
    testWidgets(
      'S2 a second message can be sent while the first send is still in flight',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
          ),
        );
        await _settleStartup(tester);

        // First send — gated, never resolves (simulates the multi-second
        // degraded-network round-trip).
        await _typeAndSend(tester, 'first');
        expect(
          recorder.callCount,
          1,
          reason: 'the first send must be dispatched',
        );

        // Second send while the first is STILL in flight. On HEAD the global
        // `_isSending` lock (set before the network call, reset only in the
        // outer finally after the still-pending await) nulls the Send button's
        // onTap and the early-return guard swallows this tap -> callCount stays
        // 1. After the fix the composer is released right after the optimistic
        // save, so this second send proceeds.
        await _typeAndSend(tester, 'second');

        expect(
          recorder.callCount,
          2,
          reason:
              'the composer must accept a second send while the first is in '
              'flight (Send button stays usable during the network round-trip)',
        );

        // INV re-verify: both optimistic rows coexist; the second send did NOT
        // clobber the first row.
        expect(find.text('first'), findsOneWidget);
        expect(find.text('second'), findsOneWidget);
        expect(
          find.byIcon(Icons.done_rounded),
          findsNWidgets(2),
          reason: 'both messages remain optimistically "sending"',
        );
      },
    );

    testWidgets(
      'S1 send-failure SnackBar does not overlap the composer (has a bottom '
      'margin)',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
          ),
        );
        await _settleStartup(tester);

        // 185: nodeNotRunning is inherently a sender-offline condition, so it
        // now shows the honest "no internet" copy (renamed from the old
        // "Network not connected. Message saved.").
        const offlineSnackText =
            "No internet connection. Message will send when you're back online.";

        await _typeAndSend(tester, 'offline message');
        expect(recorder.callCount, 1);

        // Resolve the in-flight send as the offline failure
        // (nodeNotRunning -> the honest sender-offline copy).
        recorder.completeLast(SendChatMessageResult.nodeNotRunning);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800)); // slide-in

        final snackBarFinder = find.byType(SnackBar);
        expect(snackBarFinder, findsOneWidget);
        final snackBar = tester.widget<SnackBar>(snackBarFinder);

        // Distinct discriminator: pinned to the offline-notice bar. 185:
        // nodeNotRunning is a sender-offline (queued, self-healing) state, so it
        // uses the informational slate tone, NOT the error-red.
        expect(snackBar.backgroundColor, Colors.blueGrey[700]);

        // S1 core: the failure bar carries a bottom margin that lifts it off
        // the composer. (RED on HEAD: margin == null.)
        expect(
          snackBar.margin,
          isNotNull,
          reason: 'the failure SnackBar must have a margin clearing the Send '
              'button',
        );
        final margin = snackBar.margin! as EdgeInsets;
        expect(margin.bottom, greaterThan(0));

        // Stronger geometric lock. NOTE: tester.getRect(find.byType(SnackBar))
        // returns the margin-INCLUSIVE outer box (it always spans down to the
        // screen bottom), so it cannot be used directly. The visible bar is
        // lifted by `margin.bottom`; assert that lifted bottom edge sits above
        // the composer, and that the rendered failure text does not overlap it.
        final composeRect = tester.getRect(find.byType(ComposeArea));
        final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
        final visibleBarBottom = screenHeight - margin.bottom;
        expect(
          visibleBarBottom,
          lessThanOrEqualTo(composeRect.top),
          reason: 'the failure SnackBar, lifted by its bottom margin, must sit '
              'entirely above the composer / Send button',
        );
        final contentRect = tester.getRect(find.text(offlineSnackText));
        expect(
          contentRect.overlaps(composeRect),
          isFalse,
          reason: 'the rendered failure text must not render over the composer',
        );
      },
    );

    testWidgets(
      'PRESERVE optimistic sending->failed bubble status survives the '
      'background send completion',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
          ),
        );
        await _settleStartup(tester);

        await _typeAndSend(tester, 'preserve me');

        // Optimistic sending row visible immediately, before resolution.
        expect(recorder.callCount, 1);
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        // Resolve as a failure -> the bubble must transition sending->failed.
        recorder.completeLast(SendChatMessageResult.nodeNotRunning);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsOneWidget,
          reason:
              'the failed status write on the background completion must still '
              'drive the bubble (this is the retry affordance source)',
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);

        // The durable "failed" status the retry path re-dispatches from is
        // persisted (retry re-dispatch itself is covered by
        // retry_failed_messages_use_case_test.dart).
        final stored = messageRepo.store.values.firstWhere(
          (m) => m.text == 'preserve me',
        );
        expect(stored.status, 'failed');
      },
    );

    testWidgets(
      'PRESERVE one Send tap dispatches exactly one message (no duplicate)',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
          ),
        );
        await _settleStartup(tester);

        await tester.enterText(find.byType(TextField).first, 'hi');
        await tester.pump();

        // Two taps in immediate succession, NO pump between -> the composer
        // clear + still-held in-flight lock must coalesce to a single send.
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.tap(
          find.byIcon(Icons.arrow_upward_rounded),
          warnIfMissed: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          recorder.callCount,
          1,
          reason: 'two immediate taps must dispatch exactly one message',
        );
        expect(find.text('hi'), findsOneWidget);
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 185 — offline-send failure truthfulness. When the SENDER is offline
  // (relayReady == false) a connectivity-class failure must stay in the
  // retriable self-healing lane ('sent', wire envelope preserved) and the
  // snackbar must name the sender's connection, not blame the contact.
  // ---------------------------------------------------------------------------
  group('ConversationWired — offline-send truthfulness (185)', () {
    // NOTE (synthetic shape): TC-185-01 drives a NULL-message peerNotFound to
    // exercise the UI's *defensive* `message == null` else-branch reclassify.
    // In PRODUCTION peerNotFound/dialFailed are always NON-NULL (the terminal
    // failure path returns a failedMessage — send_chat_message_use_case.dart
    // :1305-1345), so the real offline path is the `message != null` branch,
    // locked by TC-185-01b below. This case guards the else-branch belt-and-
    // suspenders handling only; it is not the production shape.
    testWidgets(
      "TC-185-01 offline send (defensive else-branch) lands retriable 'sent', not 'failed'",
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
            // default = offline (relayReady == false)
          ),
        );
        await _settleStartup(tester);

        await _typeAndSend(tester, 'offline retriable');
        expect(recorder.callCount, 1);

        // Synthetic null-message resolution -> the UI's else branch.
        recorder.completeLast(SendChatMessageResult.peerNotFound);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        final stored = messageRepo.store.values.firstWhere(
          (m) => m.text == 'offline retriable',
        );
        expect(
          stored.status,
          'sent',
          reason:
              'an offline send must stay retriable (getUnacked-eligible), not '
              'drop to terminal failed (RED on HEAD: peerNotFound -> failed)',
        );
        // No Retry affordance for a purely-offline send.
        expect(
          find.byKey(ValueKey('failed-message-retry-${stored.id}')),
          findsNothing,
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      },
    );

    // TC-185-01b — the REAL production shape: peerNotFound, dialFailed AND
    // sendFailed all return a NON-NULL failedMessage
    // (send_chat_message_use_case.dart :1305-1345, the terminal rung persists
    // the wire envelope for every reason string), handled by the UI's
    // `message != null` branch. Looping over every connectivity-class result
    // guards ALL `||` arms of the keepRetriableOffline predicate (a revert
    // dropping any arm re-reds). sendFailed is the 185×187 gap: with the 183
    // keepalive latched, 187 skips the direct dial and the race fails with
    // reason 'direct_skipped_keepalive_drop' → _resultForFailureReason →
    // sendFailed — which used to drop the offline sender to terminal
    // 'failed' + Retry (field-hit 2026-07-02).
    for (final result in const [
      SendChatMessageResult.peerNotFound,
      SendChatMessageResult.dialFailed,
      SendChatMessageResult.sendFailed,
    ]) {
      testWidgets(
        'TC-185-01b offline send returning a NON-NULL failedMessage '
        '(${result.name}, '
        'production shape) is reclassified to retriable and stays in the unacked lane',
        (tester) async {
          final messageRepo = _FakeMessageRepository();
          final recorder = _GatedSendRecorder();

          await tester.pumpWidget(
            _buildTestWidget(
              messageRepo: messageRepo,
              sendChatMessageFn: recorder.fn,
            ),
          );
          await _settleStartup(tester);

          await _typeAndSend(tester, 'offline nonnull');
          expect(recorder.callCount, 1);

          // Mirror send_chat_message_use_case.dart:1305-1345 — the terminal
          // failure path SAVES a failedMessage carrying the wire envelope, then
          // returns it non-null (handled by the UI's message!=null branch).
          final sentId = recorder.messageIds.last!;
          final failedMessage = ConversationMessage(
            id: sentId,
            contactPeerId: _contactPeerId,
            senderPeerId: _identity.peerId,
            text: 'offline nonnull',
            timestamp: '2026-07-01T10:00:00.000Z',
            status: 'failed',
            isIncoming: false,
            createdAt: '2026-07-01T10:00:00.000Z',
            wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{}}',
          );
          await messageRepo.saveMessage(failedMessage);
          recorder.completeLastWithMessage(result, failedMessage);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump();

          final stored = messageRepo.store[sentId]!;
          expect(
            stored.status,
            'sent',
            reason: 'the UI must override the use case terminal failed',
          );
          expect(
            stored.wireEnvelope,
            isNotNull,
            reason: 'the status-only write must preserve the wire envelope',
          );
          // Proof it re-enters the EXISTING retryUnacked convergence lane.
          final lane = await messageRepo.getUnackedOutgoingMessages(
            olderThan: Duration.zero,
          );
          expect(
            lane.any((m) => m.id == sentId),
            isTrue,
            reason: 'getUnackedOutgoingMessages must pick up the kept-sent row',
          );
          expect(
            find.byKey(ValueKey('failed-message-retry-$sentId')),
            findsNothing,
          );
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        },
      );
    }

    testWidgets(
      'TC-185-02 online peerNotFound still fails (no over-correction)',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final recorder = _GatedSendRecorder();

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            sendChatMessageFn: recorder.fn,
            p2pService: FakeP2PService(initialState: _onlineState),
          ),
        );
        await _settleStartup(tester);

        await _typeAndSend(tester, 'online fail');
        expect(recorder.callCount, 1);

        // Sender is ONLINE; peerNotFound is a genuine per-contact failure.
        recorder.completeLast(SendChatMessageResult.peerNotFound);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        final stored = messageRepo.store.values.firstWhere(
          (m) => m.text == 'online fail',
        );
        expect(
          stored.status,
          'failed',
          reason:
              'a genuine failure while WE are online must stay failed — the fix '
              'must not blanket-reclassify (mutation: ignore relayReady -> red)',
        );
        expect(
          find.byKey(ValueKey('failed-message-retry-${stored.id}')),
          findsOneWidget,
        );
      },
    );

    // TC-185-20 — offline: EVERY connectivity-class result must show the honest
    // sender-offline copy, never the contact-blaming/generic copy. Looping
    // guards every snackbar arm (sendFailed = the 185×187 keepalive-skip gap:
    // reason 'direct_skipped_keepalive_drop' maps to sendFailed).
    const senderOfflineCopy =
        "No internet connection. Message will send when you're back online.";
    for (final c in const [
      (SendChatMessageResult.peerNotFound, 'Contact appears offline. Message saved.'),
      (SendChatMessageResult.dialFailed, 'Could not connect to contact. Message saved.'),
      (SendChatMessageResult.sendFailed, 'Failed to send message. Message saved.'),
    ]) {
      testWidgets(
        'TC-185-20 offline failure snackbar names the sender connection '
        '(${c.$1.name})',
        (tester) async {
          final messageRepo = _FakeMessageRepository();
          final recorder = _GatedSendRecorder();

          await tester.pumpWidget(
            _buildTestWidget(
              messageRepo: messageRepo,
              sendChatMessageFn: recorder.fn,
            ),
          );
          await _settleStartup(tester);

          await _typeAndSend(tester, 'offline snack');
          if (c.$1 == SendChatMessageResult.sendFailed) {
            // sendFailed's lane/copy eligibility requires the terminal-rung
            // production shape (non-null failedMessage with the persisted wire
            // envelope) — the NULL-shaped sendFailed (encrypt_failed) is NOT
            // self-healing and keeps the generic red copy by design.
            final sentId = recorder.messageIds.last!;
            final failedMessage = ConversationMessage(
              id: sentId,
              contactPeerId: _contactPeerId,
              senderPeerId: _identity.peerId,
              text: 'offline snack',
              timestamp: '2026-07-01T10:00:00.000Z',
              status: 'failed',
              isIncoming: false,
              createdAt: '2026-07-01T10:00:00.000Z',
              wireEnvelope:
                  '{"type":"chat_message","version":"2","encrypted":{}}',
            );
            await messageRepo.saveMessage(failedMessage);
            recorder.completeLastWithMessage(c.$1, failedMessage);
          } else {
            recorder.completeLast(c.$1);
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));

          expect(find.text(senderOfflineCopy), findsOneWidget);
          expect(find.text(c.$2), findsNothing);
          // 185: offline-queued uses the informational slate tone, not error-red.
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            Colors.blueGrey[700],
          );
        },
      );

      testWidgets(
        'TC-185-21 online ${c.$1.name} '
        'snackbar keeps its non-offline copy (no over-correction)',
        (tester) async {
          final messageRepo = _FakeMessageRepository();
          final recorder = _GatedSendRecorder();

          await tester.pumpWidget(
            _buildTestWidget(
              messageRepo: messageRepo,
              sendChatMessageFn: recorder.fn,
              p2pService: FakeP2PService(initialState: _onlineState),
            ),
          );
          await _settleStartup(tester);

          await _typeAndSend(tester, 'online snack');
          recorder.completeLast(c.$1);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));

          expect(find.text(c.$2), findsOneWidget);
          expect(find.text(senderOfflineCopy), findsNothing);
          // 185: a genuine online failure keeps the error-red.
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            Colors.red[700],
          );
        },
      );
    }
  });
}
