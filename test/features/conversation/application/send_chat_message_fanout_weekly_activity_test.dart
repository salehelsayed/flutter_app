import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import 'send_chat_message_use_case_test.dart' show FakeP2PService;

const _budget = Duration(seconds: 3);
const _account = 'my-peer';
const _contact = 'target-peer';
const _message = 'b15-text-fanout-weekly';
const _targets = ['b15-text-device-a', 'b15-text-device-b'];
const _authoredAt = '2026-11-17T00:00:00.000Z';
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
  late _TextFanoutHarness h;

  setUp(() async {
    h = await _bounded(_TextFanoutHarness.create());
  });
  tearDown(() async {
    await _bounded(h.close());
  });

  test('B15TFW-001 fresh applied text fanout checkpoints one logical outgoing', () async {
    final result = await _bounded(h.send());
    expect(result.$1, SendChatMessageResult.success);
    await _bounded(h.expectApplied());
    await _bounded(h.reporter.flush());
    expect(h.bridge.operations('mark'), hasLength(1));
    expect(h.bridge.operations('markWeekly'), isEmpty,
        reason: 'One outgoing admission alone does not qualify weekly chat');
    final contacts = await _bounded(h.checkpointContacts());
    expect(contacts, [
      {
        'account': _contact,
        'incomingSeen': false,
        'deliveredOutgoingSeen': false,
        'outgoing': [
          {'message': _message, 'generation': _message},
        ],
      },
    ], reason: 'An applied logical initial must survive in the real private '
        'checkpoint once, independently of its two physical custody owners');
  });

  test('B15TFW-002 SQL authority refusal commits no parent or weekly witness', () async {
    h.beforeStage = () async {
      await _bounded(h.fixture.db.update('contacts', {'is_blocked': 1},
          where: 'peer_id = ?', whereArgs: [_contact]));
    };
    final result = await _bounded(h.send());
    expect(result.$1, SendChatMessageResult.sendFailed);
    expect(h.stages, [DirectEventFanoutStageOutcome.refused]);
    expect(await _bounded(h.fixture.messageRepo.getMessage(_message)), isNull);
    expect(await _bounded(h.siblings()), isEmpty);
    await _bounded(h.expectUnobserved());
  });

  test('B15TFW-003 authoritative present-null cannot recapture after ON', () async {
    await _bounded(h.reporter.observeConsent((enabled: false, consentEpoch: 8)));
    final original = h.capture();
    expect(original.capture, isNull);
    await _bounded(h.reporter.observeConsent((enabled: true, consentEpoch: 9)));
    expect(h.capture().capture, isNotNull);
    expect((await _bounded(h.send(capturedActivity: original))).$1,
        SendChatMessageResult.success);
    await _bounded(h.expectApplied());
    await _bounded(h.expectUnobserved());
  });

  for (final (id, turnover) in [
    ('B15TFW-004', 'profile'),
    ('B15TFW-005', 'epoch'),
  ]) {
    test('$id original $turnover capture cannot follow the applied SQL stage', () async {
      h.beforeStage = () async {
        if (turnover == 'profile') {
          h.reporter.observeIdentity(
            accountPeerId: _account,
            rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
            profileBinding: 'v1:${'b' * 64}',
          );
        }
        await _bounded(h.reporter.observeConsent((
          enabled: true,
          consentEpoch: turnover == 'profile' ? 7 : 8,
        )));
      };
      expect((await _bounded(h.send())).$1, SendChatMessageResult.success);
      await _bounded(h.expectApplied());
      await _bounded(h.expectUnobserved());
    });
  }

  test('B15TFW-006 OFF-created survivors cannot become a fresh ON admission', () async {
    await _bounded(h.reporter.observeConsent((enabled: false, consentEpoch: 8)));
    expect(h.capture().capture, isNull);
    expect((await _bounded(h.send())).$1, SendChatMessageResult.success);
    await _bounded(h.expectApplied());
    final before = await _bounded(h.siblings());
    final snapshotReads = h.snapshotReads;
    await _bounded(h.reporter.observeConsent((enabled: true, consentEpoch: 9)));
    expect(h.capture().capture, isNotNull);
    expect((await _bounded(h.send(fresh: false))).$1,
        SendChatMessageResult.sendFailed,
        reason: 'Both real custody owners survive the failed retry STORE');
    expect(h.stages, [DirectEventFanoutStageOutcome.applied],
        reason: 'A surviving generation is replayed without fresh staging');
    expect(h.snapshotReads, snapshotReads,
        reason: 'Persisted siblings, rather than a fresh roster, own retry');
    final after = await _bounded(h.siblings());
    expect(after, hasLength(2));
    for (var index = 0; index < before.length; index++) {
      for (final key in ['recipient_peer_id', 'contact_account_peer_id',
        'message_id', 'incarnation_id', 'wire_envelope']) {
        expect(after[index][key], before[index][key]);
      }
      expect(after[index]['retry_count'], (before[index]['retry_count'] as int) + 1);
    }
    await _bounded(h.expectUnobserved());
  });

  test('B15TFW-007 physical sender alias and authenticated linked receipt count one logical contact', () async {
    h.senderTransport = 'local-physical-sender';
    final original = h.capture();
    final sent = await _bounded(h.send(capturedActivity: original));
    expect(sent.$1, SendChatMessageResult.success);
    await _bounded(h.expectApplied());
    for (final row in await _bounded(h.siblings())) {
      expect((jsonDecode(row['wire_envelope'] as String) as Map)['senderPeerId'],
        h.senderTransport);
    }
    await _bounded(h.reporter.flush());
    expect((await _bounded(h.checkpointContacts())).single['deliveredOutgoingSeen'], isFalse);
    for (var duplicate = 0; duplicate < 2; duplicate++) {
      await _bounded(handleDeliveryReceipt(
        message: ChatMessage(from: _targets.first, to: _account, timestamp: _authoredAt,
          isIncoming: true, transport: 'direct', content: jsonEncode({
            'type': 'delivery_receipt', 'version': '1',
            'payload': {'messageIds': [_message], 'ts': _authoredAt},
          })),
        messageRepo: h.fixture.messageRepo,
        transportAuthority: DatabaseDirectTransportAuthority(database: h.fixture.db),
        capturedActivity: original,
      ));
    }
    await _bounded(h.reporter.flush());
    final parent = (await _bounded(h.fixture.messageRepo.getMessage(_message)))!;
    expect(parent.status, 'delivered');
    expect(parent.wireEnvelope, isNull);
    expect(parent.directEventFanoutGenerationId, _message);
    final contact = (await _bounded(h.checkpointContacts())).single as Map;
    expect(contact['account'], _contact);
    expect(contact['deliveredOutgoingSeen'], isTrue);
    expect(contact['outgoing'], isEmpty);
    expect(h.bridge.operations('mark'), hasLength(1));
    expect(h.bridge.operations('markWeekly'), isEmpty);
  });

  test('B15TFW-008 sibling insertion rollback cannot admit a fresh weekly tuple', () async {
    var insertions = 0;
    h.beforeSiblingInsert = () async {
      insertions++;
      if (insertions == 2) {
        throw StateError('controlled second sibling rollback');
      }
    };
    await expectLater(_bounded(h.send()), throwsA(isA<StateError>()));
    expect(insertions, 2, reason: 'The real owner inserted a first sibling before rollback');
    expect(h.stages, isEmpty, reason: 'No real final APPLIED result escaped the outer owner');
    expect(await _bounded(h.fixture.messageRepo.getMessage(_message)), isNull);
    expect(await _bounded(h.siblings()), isEmpty);
    await _bounded(h.expectUnobserved());
  });
}

// Only crypto, network and native-calendar boundaries are substituted. Contact
// authority, canonical parent, all sibling custody and checkpoint writes are real.
final class _TextFanoutHarness {
  _TextFanoutHarness(this.root, this.fixture, this.store, this.bridge, this.reporter);

  final Directory root;
  final MediaRepositoryRealDbFixture fixture;
  final EngagementChatCheckpointStore store;
  final _TextFanoutBridge bridge;
  final ActiveIdentityReporter reporter;
  final service = FakeP2PService(sendMessageResult: false);
  final stages = <DirectEventFanoutStageOutcome>[];
  Future<void> Function()? beforeStage;
  Future<void> Function()? beforeSiblingInsert;
  String senderTransport = _account;
  int snapshotReads = 0;

  static Future<_TextFanoutHarness> create() async {
    await _bounded(AppDiagnostics.installForTesting(useNative: false, enabled: true));
    final root = await _bounded(Directory.systemTemp.createTemp('b15-text-fanout-'));
    final fixture = await _bounded(MediaRepositoryRealDbFixture.create());
    final store = await _bounded(EngagementChatCheckpointStore.open('${root.path}/private'));
    final bridge = _TextFanoutBridge();
    final reporter = ActiveIdentityReporter(
      statePath: '${root.path}/native.json',
      chatWitnessStore: store,
      chatNowMilliseconds: () => _start + 10000,
    );
    final h = _TextFanoutHarness(root, fixture, store, bridge, reporter);
    // TC-361 persisted authorized-roster inputs: no legacy target, two ACTIVE
    // bindings whose verified account key matches the current contact.
    await _bounded(fixture.db.insert('contacts', {
      'peer_id': _contact, 'public_key': 'contact-signing-key',
      'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
      'username': 'Contact', 'signature': 'fixture-signature',
      'scanned_at': _authoredAt, 'ml_kem_public_key': 'legacy-mlkem',
    }));
    await _bounded(fixture.db.insert('direct_contact_device_roster_metadata', {
      'contact_account_peer_id': _contact, 'roster_initialized': 1,
      'legacy_target_state': 'revoked', 'initialized_at': _authoredAt,
      'legacy_revoked_at': _authoredAt, 'updated_at': _authoredAt,
    }));
    for (var index = 0; index < _targets.length; index++) {
      await _bounded(fixture.db.insert('direct_contact_device_bindings', {
        'contact_account_peer_id': _contact, 'device_id': 'device-$index',
        'verified_account_signing_public_key': 'contact-signing-key',
        'transport_peer_id': _targets[index], 'transport_public_key': 'signing-$index',
        'device_ml_kem_public_key': 'mlkem-$index',
        'binding_fingerprint': (index == 0 ? 'a' : 'b') * 64,
        'state': 'active', 'staged_at': _authoredAt, 'decided_at': _authoredAt,
      }));
    }
    final snapshot = await _bounded(dbReadDirectContactFanoutSnapshot(
      fixture.db, contactAccountPeerId: _contact));
    expect(snapshot!.targets.map((target) => target.peerId).toSet(), _targets.toSet());
    reporter.attachBridge(bridge);
    reporter.observeIdentity(accountPeerId: _account,
        rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
        profileBinding: _binding);
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 7)));
    final owner = h.capture().capture;
    expect(owner, isNotNull);
    final calendar = await _bounded(reporter.weeklyProjectionCaptured(owner!));
    expect(calendar, (week: _week, startMilliseconds: _start, endMilliseconds: _end));
    await _bounded(reporter.flush());
    expect(await _bounded(h.checkpointContacts()), isEmpty);
    expect(bridge.operations('mark'), isEmpty);
    expect(bridge.operations('markWeekly'), isEmpty);
    return h;
  }

  _Observation capture() => (reporter: reporter,
      capture: reporter.captureOwner(expectedAccountPeerId: _account));

  DirectEventFanoutAuthoring get authoring => DirectEventFanoutAuthoring(
    selector: const DirectLinkedEventFanoutSelector.enabled(),
    linkedOrigin: false, senderTransportPeerId: senderTransport,
    readSnapshot: (contact) {
      snapshotReads++;
      return _bounded(dbReadDirectContactFanoutSnapshot(
          fixture.db, contactAccountPeerId: contact));
    },
    encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
      final encrypted = await _bounded(callEncryptMessage(bridge: bridge,
          recipientMlKemPublicKey: recipientMlKemPublicKey, plaintext: plaintext,
          timeout: _budget));
      if (encrypted['ok'] != true) return null;
      return (kem: encrypted['kem'] as String,
          ciphertext: encrypted['ciphertext'] as String, nonce: encrypted['nonce'] as String);
    },
    loadTextSiblings: (id) => _bounded(dbLoadDirectInboxCustodyOutboxRowsForMessageId(
        fixture.db, messageId: id)),
    stageTextFanout: ({String? authoredTextIntentToken, required stagedRow,
      required messageId, required contactAccountPeerId, required senderTransportPeerId,
      required expectedSnapshot, required candidates}) async {
      final before = beforeStage;
      if (before != null) await _bounded(before());
      final staged = await _bounded(dbStageOutgoingDirectTextFanoutInboxCustody(
        fixture.db, authoredTextIntentToken: authoredTextIntentToken, stagedRow: stagedRow,
        messageId: messageId, contactAccountPeerId: contactAccountPeerId,
        senderTransportPeerId: senderTransportPeerId, expectedSnapshot: expectedSnapshot,
        candidates: candidates, beforeSiblingInsertForTest: beforeSiblingInsert,
      ));
      stages.add(staged.outcome);
      return staged;
    },
    loadEventSiblings: (_) async => throw StateError('Fresh text cannot load mutation siblings'),
    stageMutationFanout: ({required expectedRow, required stagedRow, required kind,
      required eventId, required parentMessageId, required contactAccountPeerId,
      required senderTransportPeerId, required expectedSnapshot, required candidates}) async =>
        throw StateError('Fresh text cannot stage a mutation'),
    stageReactionFanout: ({required reactionRow, required action, required parentMessageId,
      required contactAccountPeerId, required senderTransportPeerId,
      required expectedSnapshot, required candidates}) async =>
        throw StateError('Fresh text cannot stage a reaction'),
  );

  Future<(SendChatMessageResult, ConversationMessage?)> send({
    bool fresh = true, _Observation? capturedActivity,
  }) => sendChatMessage(
    p2pService: service, messageRepo: fixture.messageRepo,
    targetPeerId: _contact, text: 'fresh linked text',
    senderPeerId: _account, senderUsername: 'Me', messageId: _message,
    preassignedMessageIdIsFresh: fresh, timestamp: _authoredAt, createdAt: _authoredAt,
    bridge: bridge, recipientMlKemPublicKey: 'legacy-mlkem',
    activityReporter: reporter, capturedActivity: capturedActivity,
    directEventFanout: authoring,
    storeInAckCustodyInboxDetailed: (peer, envelope, {required custodyKind, timeoutMs}) async =>
        const InboxStoreOutcome(status: InboxStoreStatus.failed, errorCode: 'TEST_OFFLINE'),
  );

  Future<List<Map<String, Object?>>> siblings() => _bounded(
      dbLoadDirectInboxCustodyOutboxRowsForMessageId(fixture.db, messageId: _message));

  Future<void> expectApplied() async {
    expect(stages, [DirectEventFanoutStageOutcome.applied]);
    final parent = await _bounded(fixture.messageRepo.getMessage(_message));
    expect(parent, isNotNull);
    expect(parent!.isIncoming, isFalse);
    expect(parent.contactPeerId, _contact);
    expect(parent.text, 'fresh linked text');
    expect(parent.directEventFanoutGenerationId, _message);
    final rows = await _bounded(siblings());
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['recipient_peer_id']).toSet(), _targets.toSet());
    for (final row in rows) {
      expect(row['contact_account_peer_id'], _contact);
      expect(row['message_id'], _message);
      expect(row['incarnation_id'], computeDirectEventFanoutIncarnation(
          messageId: _message, recipientPeerId: row['recipient_peer_id'] as String));
    }
    expect(parent.wireEnvelope, rows.first['wire_envelope']);
  }

  Future<List<dynamic>> checkpointContacts() async {
    final bytes = await _bounded(store.read(isCurrent: () => true));
    if (bytes == null) return const [];
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect(decoded['phase'], 'collecting');
    return decoded['contacts'] as List<dynamic>;
  }

  Future<void> expectUnobserved() async {
    await _bounded(reporter.flush());
    expect(bridge.operations('mark'), isEmpty);
    expect(bridge.operations('markWeekly'), isEmpty);
    expect(await _bounded(checkpointContacts()), isEmpty);
  }

  Future<void> close() async {
    await _bounded(reporter.dispose());
    await _bounded(store.close());
    await _bounded(fixture.dispose());
    await _bounded(AppDiagnostics.instance.dispose());
    await _bounded(root.delete(recursive: true));
  }
}

final class _TextFanoutBridge extends FakeBridge {
  _TextFanoutBridge() : super(initialResponses: {
    'message.encrypt': {'ok': true, 'kem': 'fixture-kem',
        'ciphertext': 'fixture-ciphertext', 'nonce': 'fixture-nonce'},
  });
  final requests = <Map<String, dynamic>>[];
  int revision = 0;

  @override
  bool get isInitialized => true;

  List<Map<String, dynamic>> operations(String op) =>
      requests.where((request) => request['op'] == op).toList();

  @override
  Future<String> send(String raw) async {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    if (envelope['cmd'] != 'active_identity_reporter_v1') return super.send(raw);
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
}
