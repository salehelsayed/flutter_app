import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _budget = Duration(seconds: 3);
const _account = 'receipt-local-account';
const _contact = 'receipt-remote-account';
const _message = 'weekly-receipt-initial';
const _time = '2026-11-17T00:00:00.000Z';
const _week = '2026-W47';
const _start = 1794783600000;
const _end = 1795388400000;
const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

typedef _Observation = ({
  ActiveIdentityReporter? reporter,
  ActiveIdentityReporterCapture? capture,
});

Future<T> _bounded<T>(Future<T> work) => work.timeout(_budget);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ReceiptHarness h;
  setUp(() async => h = await _bounded(_ReceiptHarness.create()));
  tearDown(() async => _bounded(h.close()));

  test('B15RW-001 live ACK settlement grants no weekly delivery until the application receipt', () async {
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.settleLive(parent));
    await _bounded(h.expectPending());
    final original = h.capture();
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.reporter.flush());
    expect(h.bridge.operations('markWeekly'), isEmpty,
        reason: 'One logical delivery alone does not qualify weekly chat');
    expect(await _bounded(h.contacts()), [
      {
        'account': _contact,
        'incomingSeen': false,
        'deliveredOutgoingSeen': true,
        'outgoing': <Object>[],
      },
    ], reason: 'An authenticated application receipt must confirm the admitted '
        'logical initial once even when live ACK settlement already delivered it');
  });

  test('B15RW-002 an application receipt for an unknown tuple cannot credit an admitted message', () async {
    await _bounded(h.admitInitial());
    final unknown = await _bounded(h.stageParent('weekly-receipt-unknown'));
    await _bounded(h.settleLive(unknown));
    await _bounded(h.receipt(id: unknown.id, capturedActivity: h.capture()));
    await _bounded(h.expectPending());
  });

  test('B15RW-003 a foreign receipt cannot credit the admitted logical contact', () async {
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.settleLive(parent));
    await _bounded(h.receipt(from: 'unrelated-account', capturedActivity: h.capture()));
    await _bounded(h.expectPending());
  });

  test('B15RW-004 an initial receipt cannot credit the current edit generation', () async {
    final parent = await _bounded(h.admitInitial());
    final edit = parent.copyWith(
      text: 'a later edit',
      editedAt: '2026-11-17T00:00:01.000Z',
      wireEnvelope: _envelope(_message, eventId: 'weekly-receipt-edit-event'),
    );
    final applied = await _bounded(h.fixture.messageRepo.stageOutgoingOrdinaryAttempt(
      expected: parent, staged: edit, kind: OutgoingOrdinaryAttemptKind.edit,
    ));
    expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
    expect(applied.message!.wireEnvelope, edit.wireEnvelope);
    await _bounded(h.receipt(capturedActivity: h.capture()));
    final kept = await _bounded(h.fixture.messageRepo.getMessage(_message));
    expect(kept!.wireEnvelope, edit.wireEnvelope);
    expect(kept.editedAt, edit.editedAt);
    await _bounded(h.expectPending());
  });

  test('B15RW-005 a present-null observation cannot recapture an ON tuple', () async {
    await _bounded(h.reporter.observeConsent((enabled: false, consentEpoch: 8)));
    final original = h.capture();
    expect(original.capture, isNull);
    await _bounded(h.reporter.observeConsent((enabled: true, consentEpoch: 9)));
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.settleLive(parent));
    expect(h.capture().capture, isNotNull);
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.expectPending());
  });

  test('B15RW-006 an original epoch cannot credit a successor admitted tuple', () async {
    final original = h.capture();
    expect(original.capture, isNotNull);
    await _bounded(h.reporter.observeConsent((enabled: true, consentEpoch: 8)));
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.settleLive(parent));
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.expectPending());
  });

}

String _envelope(String id, {String? eventId}) => MessagePayload.buildEncryptedEnvelope(
  id: id, senderPeerId: _account, senderUsername: 'Local',
  kem: 'public-fixture-kem', ciphertext: 'public-fixture-ciphertext',
  nonce: 'public-fixture-nonce', eventId: eventId,
);

ChatMessage _receipt({String id = _message, String from = _contact}) => ChatMessage(
  from: from, to: _account, timestamp: _time, isIncoming: true, transport: 'direct',
  content: jsonEncode({
    'type': 'delivery_receipt', 'version': '1',
    'payload': {'messageIds': [id], 'ts': _time},
  }),
);

final class _ReceiptHarness {
  _ReceiptHarness(this.root, this.fixture, this.store, this.bridge, this.reporter);

  final Directory root;
  final MediaRepositoryRealDbFixture fixture;
  final EngagementChatCheckpointStore store;
  final _ReceiptBridge bridge;
  final ActiveIdentityReporter reporter;

  static Future<_ReceiptHarness> create() async {
    await _bounded(AppDiagnostics.installForTesting(useNative: false, enabled: true));
    final root = await _bounded(Directory.systemTemp.createTemp('b15-weekly-receipt-'));
    final fixture = await _bounded(MediaRepositoryRealDbFixture.create());
    final store = await _bounded(EngagementChatCheckpointStore.open('${root.path}/private'));
    final bridge = _ReceiptBridge();
    final reporter = ActiveIdentityReporter(
      statePath: '${root.path}/native.json', chatWitnessStore: store,
      chatNowMilliseconds: () => _start + 10000,
    );
    await _bounded(fixture.db.insert('contacts', {
      'peer_id': _contact, 'public_key': 'public-contact-fixture',
      'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
      'username': 'Contact', 'signature': 'public-fixture-signature',
      'scanned_at': _time,
    }));
    reporter.attachBridge(bridge);
    reporter.observeIdentity(accountPeerId: _account,
        rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
        profileBinding: _binding);
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 7)));
    final h = _ReceiptHarness(root, fixture, store, bridge, reporter);
    final owner = h.capture().capture;
    expect(owner, isNotNull);
    expect(await _bounded(reporter.weeklyProjectionCaptured(owner!)),
        (week: _week, startMilliseconds: _start, endMilliseconds: _end));
    await _bounded(reporter.flush());
    return h;
  }

  _Observation capture() => (reporter: reporter,
      capture: reporter.captureOwner(expectedAccountPeerId: _account));

  Future<ConversationMessage> stageParent(String id) async {
    final parent = ConversationMessage(
      id: id, contactPeerId: _contact, senderPeerId: _account,
      text: 'ordinary receipt initial', timestamp: _time, createdAt: _time,
      status: 'sending', isIncoming: false, wireEnvelope: _envelope(id),
    );
    final staged = await _bounded(fixture.messageRepo.stageOutgoingOrdinaryAttempt(
      expected: null, staged: parent, kind: OutgoingOrdinaryAttemptKind.fresh,
    ));
    expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
    expect(staged.message!.wireEnvelope, parent.wireEnvelope);
    return staged.message!;
  }

  // Explicit witness setup tied to real SQL APPLIED, not an outgoing-producer
  // integration claim. Only the real receipt handler may report delivery.
  Future<ConversationMessage> admitInitial() async {
    final owner = capture().capture!;
    final intent = reporter.reserveChatCaptured(owner,
        contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(intent, isNotNull);
    final staged = await _bounded(reporter.observeChatSqlCaptured(
      owner, () => stageParent(_message),
    ));
    reporter.admitChatCaptured(owner, intent!);
    await _bounded(expectPending());
    return staged;
  }

  Future<void> settleLive(ConversationMessage parent) async {
    final settled = await _bounded(fixture.messageRepo.settleOutgoingOrdinaryTransport(
      messageId: parent.id, expectedContactPeerId: _contact,
      expectedEnvelope: parent.wireEnvelope, status: 'delivered', transport: 'direct',
      relayExpiresAt: null, mode: OutgoingOrdinarySettlementMode.live,
    ));
    expect(settled.outcome, OutgoingOrdinaryMutationOutcome.applied);
    final durable = await _bounded(fixture.messageRepo.getMessage(parent.id));
    expect(durable!.status, 'delivered');
    expect(durable.wireEnvelope, isNull);
  }

  Future<void> receipt({String id = _message, String from = _contact,
    required _Observation capturedActivity,
  }) => handleDeliveryReceipt(message: _receipt(id: id, from: from),
      messageRepo: fixture.messageRepo, capturedActivity: capturedActivity);

  Future<List<dynamic>> contacts() async {
    final bytes = await _bounded(store.read(isCurrent: () => true));
    expect(bytes, isNotNull, reason: 'The real admitted tuple must already be checkpointed');
    final snapshot = jsonDecode(utf8.decode(bytes!)) as Map<String, dynamic>;
    expect(snapshot['version'], 1);
    expect(snapshot['phase'], 'collecting');
    return snapshot['contacts'] as List<dynamic>;
  }

  Future<void> expectPending() async {
    await _bounded(reporter.flush());
    expect(await _bounded(contacts()), [
      {
        'account': _contact, 'incomingSeen': false, 'deliveredOutgoingSeen': false,
        'outgoing': [{'message': _message, 'generation': _message}],
      },
    ]);
    expect(bridge.operations('markWeekly'), isEmpty);
  }

  Future<void> close() async {
    await _bounded(reporter.dispose());
    await _bounded(store.close());
    await _bounded(fixture.dispose());
    await _bounded(AppDiagnostics.instance.dispose());
    await _bounded(root.delete(recursive: true));
  }
}

final class _ReceiptBridge implements Bridge {
  final requests = <Map<String, dynamic>>[];
  int revision = 0;

  @override
  bool get isInitialized => true;

  List<Map<String, dynamic>> operations(String op) =>
      requests.where((request) => request['op'] == op).toList();

  @override
  Future<String> send(String raw) async {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    expect(envelope['cmd'], 'active_identity_reporter_v1');
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(payload);
    final op = payload['op'];
    return jsonEncode({'ok': true, 'data': {
      'revision': op == 'configure' ? ++revision : payload['revision'],
      'consentEpoch': payload['consentEpoch'],
      if (op == 'configure') 'configured': payload['enabled'] == true,
      if (op == 'mark' || op == 'markWeekly') 'accepted': true,
      if (op == 'flush') 'queued': true,
      if (op == 'weeklyProjection') 'weekly': {
        'week': _week, 'startUnixMillis': _start, 'endUnixMillis': _end,
        'kinds': <String>[], 'acknowledged': <Object>[],
      },
    }});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
