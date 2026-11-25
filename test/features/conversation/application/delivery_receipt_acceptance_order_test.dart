import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _budget = Duration(seconds: 10);
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

  test('B15RA-001 benign public save and refused edit preserve receipt eligibility', () async {
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.sql(() => h.fixture.messageRepo.saveMessage(parent)));
    final refused = await _bounded(h.sql(() => h.fixture.messageRepo.stageOutgoingOrdinaryAttempt(
      expected: parent.copyWith(text: 'wrong predecessor'),
      staged: parent.copyWith(text: 'edit', editedAt: '2026-11-17T00:00:01.000Z',
          wireEnvelope: _envelope(_message, eventId: 'refused-edit')),
      kind: OutgoingOrdinaryAttemptKind.edit,
    )));
    expect(refused.outcome, OutgoingOrdinaryMutationOutcome.preserved);
    expect(await _bounded(h.sql(() => h.fixture.messageRepo.deleteMessage('absent'))), 0);
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  for (final removal in ['message', 'bulk', 'contact']) {
    test('B15RA-002 $removal accepted before receipt rejects erased and reinserted lineage', () async {
      final parent = await _bounded(h.admitInitial());
      final original = await _bounded(h.fixture.messageRepo.getMessage(parent.id));
      final before = (await _bounded(h.fixture.db.query('messages',
        where: 'id = ?', whereArgs: [parent.id]))).single;
      await _bounded(h.remove(removal));
      expect(await _bounded(h.fixture.messageRepo.getMessage(parent.id)), isNull);
      await _bounded(h.sql(() => h.fixture.messageRepo.saveMessage(original!)));
      final restored = await _bounded(h.fixture.messageRepo.getMessage(parent.id));
      expect(restored!.toMap(), original!.toMap());
      expect((await _bounded(h.fixture.db.query('messages',
        where: 'id = ?', whereArgs: [parent.id]))).single, before);
      await _bounded(h.receipt(capturedActivity: h.capture()));
      await _bounded(h.expectDelivered(false));
    });
  }

  for (final removal in ['message', 'bulk', 'contact', 'edit']) {
    test('B15RA-003 receipt accepted before later $removal survives queued checkpoint', () async {
      h.holdCheckpoint();
      final parent = await _bounded(h.admitInitial(flush: false));
      await _bounded(h.checkpointHold['entered']!.future);
      try {
        await _bounded(h.receipt(capturedActivity: h.capture()));
        await _bounded(h.remove(removal));
        final current = await _bounded(h.fixture.messageRepo.getMessage(parent.id));
        if (removal == 'edit') {
          expect(current!.editedAt, '2026-11-17T00:00:01.000Z');
        } else {
          expect(current, isNull);
        }
      } finally {
        h.releaseCheckpoint();
      }
      await _bounded(h.expectDelivered(true));
    });
  }

  test('B15RA-004 outer v109 rollback after applied parent CAS does not revoke receipt', () async {
    final parent = await _bounded(h.admitInitial());
    final edit = parent.copyWith(text: 'rolled back edit',
        editedAt: '2026-11-17T00:00:01.000Z',
        wireEnvelope: _envelope(_message, eventId: 'rollback-edit'));
    await expectLater(_bounded(h.sql(() => dbStageOutgoingDirectTextMutationInboxCustody(
      h.fixture.db, expectedRow: parent.toMap(), stagedRow: edit.toMap(),
      kind: OutgoingOrdinaryAttemptKind.edit, recipientPeerId: _contact,
      eventId: 'rollback-edit', wireEnvelope: edit.wireEnvelope!,
      beforeCustodyInsertForTest: () async => throw StateError('controlled rollback'),
    ))), throwsA(isA<StateError>()));
    final durable = await _bounded(h.fixture.messageRepo.getMessage(parent.id));
    expect(durable!.toMap(), parent.toMap());
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-005 a reserved intent is admitted by actual SQL after contact purge', () async {
    final owner = h.capture().capture!;
    final intent = h.reporter.reserveChatCaptured(owner,
        contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(intent, isNotNull);
    await _bounded(h.remove('contact'));
    final parent = await _bounded(h.sql(() => h.stageParent(_message)));
    h.reporter.admitChatCaptured(owner, intent!);
    expect(parent.id, _message);
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-006 SQL admission before purge stays revoked despite reversed completion callbacks', () async {
    final owner = h.capture().capture!;
    final intent = h.reporter.reserveChatCaptured(owner,
        contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(intent, isNotNull);
    final committed = Completer<void>();
    final release = Completer<void>();
    final parent = h.parent(_message);
    final pending = h.sql(() => dbWriteTransaction(
      h.fixture.db,
      (txn) => dbStageOutgoingOrdinaryAttemptWithinTransaction(txn,
        expectedRow: null, stagedRow: parent.toMap(),
        kind: OutgoingOrdinaryAttemptKind.fresh),
      beforeAuthorityResolutionForTest: () async {
        committed.complete();
        await _bounded(release.future);
      },
    ));
    try {
      await _bounded(committed.future);
      await _bounded(h.remove('contact'));
      await _bounded(h.sql(() => h.fixture.messageRepo.saveMessage(parent)));
      await _bounded(h.receipt(capturedActivity: h.capture()));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
    expect(await _bounded(pending), OutgoingOrdinaryMutationOutcome.applied);
    h.reporter.admitChatCaptured(owner, intent!);
    await _bounded(h.expectDelivered(false));
  });

  for (final fence in ['off', 'profile', 'epoch']) {
    test('B15RA-007 $fence fences an accepted receipt waiting on checkpoint', () async {
      h.holdCheckpoint();
      await _bounded(h.admitInitial(flush: false));
      await _bounded(h.checkpointHold['entered']!.future);
      try {
        await _bounded(h.receipt(capturedActivity: h.capture()));
        if (fence == 'profile') {
          h.reporter.observeIdentity(accountPeerId: _account,
            rootPrivateKeyBase64: 'public-replacement-fixture',
            profileBinding: 'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
        } else {
          await _bounded(h.reporter.observeConsent((enabled: fence != 'off', consentEpoch: 8)));
        }
      } finally {
        h.releaseCheckpoint();
      }
      await _bounded(h.reporter.flush());
      expect(h.bridge.operations('markWeekly'), isEmpty);
      final bytes = await _bounded(h.store.read(isCurrent: () => true));
      if (bytes != null) {
        final contacts = (jsonDecode(utf8.decode(bytes)) as Map)['contacts'] as List;
        expect(contacts.where((c) => (c as Map)['deliveredOutgoingSeen'] == true), isEmpty);
      }
    });
  }
  test('B15RA-008 failed contact deletion rolls back its real message removal', () async {
    final parent = await _bounded(h.admitInitial());
    await expectLater(_bounded(h.sql(() => dbPurgeDirectContactConversationAndContact(
      h.fixture.db, _contact,
      beforeContactDeleteForTest: () async => throw StateError('controlled purge rollback'),
    ))), throwsA(isA<StateError>()));
    final durable = await _bounded(h.fixture.messageRepo.getMessage(parent.id));
    expect(durable!.toMap(), parent.toMap());
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-009 restored checkpoint references alone cannot authorize a new receipt', () async {
    await _bounded(h.admitInitial());
    await _bounded(h.reporter.dispose());
    final replacementBridge = _ReceiptBridge();
    final replacement = ActiveIdentityReporter(
      statePath: '${h.root.path}/replacement-native.json', chatWitnessStore: h.store,
      chatNowMilliseconds: () => _start + 10000,
      chatStoreDeadline: _budget,
    );
    try {
      replacement.attachBridge(replacementBridge);
      replacement.observeIdentity(accountPeerId: _account,
        rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
        profileBinding: _binding);
      await _bounded(replacement.observeConsent((enabled: true, consentEpoch: 7)));
      await _bounded(replacement.flush());
      await _bounded(h.receipt(capturedActivity: (
        reporter: replacement,
        capture: replacement.captureOwner(expectedAccountPeerId: _account),
      )));
      await _bounded(replacement.flush());
      final contact = (await _bounded(h.contacts())).single as Map;
      expect(contact['deliveredOutgoingSeen'], isFalse);
      expect(replacementBridge.operations('markWeekly'), isEmpty);
    } finally {
      await _bounded(replacement.dispose());
    }
  });

  test('B15RA-010 deleting another real message leaves the admitted initial eligible', () async {
    await _bounded(h.admitInitial());
    final other = await _bounded(h.sql(() => h.stageParent('unrelated-message')));
    expect(await _bounded(h.sql(() => h.fixture.messageRepo.deleteMessage(other.id))), 1);
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-011 accepted receipt survives later deletion while caller publication is held', () async {
    final committed = Completer<void>();
    final release = Completer<void>();
    final held = await _bounded(_ReceiptHarness.create(afterReceipt: () async {
      committed.complete();
      await _bounded(release.future);
    }));
    try {
    await _bounded(held.admitInitial());
    final receipt = held.receipt(capturedActivity: held.capture());
    try {
      await _bounded(committed.future);
      await _bounded(held.remove('message'));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
    await _bounded(receipt);
    await _bounded(held.expectDelivered(true));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      await _bounded(held.close());
    }
  });

  test('B15RA-012 mutation entry before a valid receipt cannot poison it when mutation fails', () async {
    await _bounded(h.admitInitial());
    final entered = Completer<void>();
    final release = Completer<void>();
    // Hold before the real operation, not inside the SQL lock; the receipt can
    // genuinely be accepted before this attempted mutation later rolls back.
    final mutation = h.sql(() async {
      entered.complete();
      await _bounded(release.future);
      return dbPurgeDirectContactConversationAndContact(h.fixture.db, _contact,
        beforeContactDeleteForTest: () async => throw StateError('controlled failed deletion'));
    });
    final observedFailure = expectLater(_bounded(mutation), throwsA(isA<StateError>()));
    try {
      await _bounded(entered.future);
      await _bounded(h.receipt(capturedActivity: h.capture()));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
    await _bounded(observedFailure);
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-013 applied delivery remains after purge and duplicate receipt', () async {
    final parent = await _bounded(h.admitInitial());
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
    await _bounded(h.remove('contact'));
    await _bounded(h.sql(() => h.fixture.messageRepo.saveMessage(parent)));
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-014 committed receipt qualification leaves the SQL Zone before native retention', () async {
    await _bounded(h.admitInitial());
    final original = h.capture();
    final incoming = ConversationMessage(
      id: 'real-incoming-initial', contactPeerId: _contact, senderPeerId: _contact,
      text: 'incoming setup', timestamp: _time, createdAt: _time,
      status: 'delivered', isIncoming: true,
    );
    final applied = await _bounded(h.fixture.messageRepo.applyIncomingOrdinaryTextMutation(
      incoming: incoming, kind: IncomingOrdinaryTextMutationKind.initial,
    ));
    expect(applied.outcome, IncomingOrdinaryTextMutationOutcome.inserted);
    // Known incoming setup uses the real typed insertion, not a synthetic
    // receipt or SQL outcome. Incoming-listener adoption is a separate unit.
    h.reporter.chatIncomingCaptured(original.capture!, contactAccountPeerId: _contact);
    await _bounded(h.reporter.flush());
    expect(h.bridge.operations('markWeekly'), isEmpty);
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.reporter.flush());
    expect(h.bridge.operations('markWeekly'), hasLength(1));
    final bytes = await _bounded(h.store.read(isCurrent: () => true));
    expect((jsonDecode(utf8.decode(bytes!)) as Map)['phase'], 'qualified_retained');
  });

  test(
    'B15RA-015 profile ABA cannot apply an old accepted receipt or borrow restored lineage',
    () async {
      final committed = Completer<void>();
      final releaseReceipt = Completer<void>();
      final held = await _bounded(
        _ReceiptHarness.create(
          afterReceipt: () async {
            if (committed.isCompleted) return;
            committed.complete();
            await _bounded(releaseReceipt.future);
          },
        ),
      );
      try {
        // Keep initial lineage unpublished even if optional checkpoint
        // preparation expires before reaching the store's hold.
        held.holdCheckpoint();
        await _bounded(held.admitInitial(flush: false));
        final receipt = held.receipt(capturedActivity: held.capture());
        try {
          await _bounded(Future.any([committed.future, receipt]));
          expect(
            committed.isCompleted,
            isTrue,
            reason: 'The receipt must reach the committed SQL checkpoint',
          );
          final delivered = await _bounded(
            held.fixture.messageRepo.getMessage(_message),
          );
          expect(delivered?.status, 'delivered');
          held.reporter.observeIdentity(
            accountPeerId: _account,
            rootPrivateKeyBase64: 'public-other-profile',
            profileBinding:
                'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          );
          held.reporter.observeIdentity(
            accountPeerId: _account,
            rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
            profileBinding: _binding,
          );
        } finally {
          held.releaseCheckpoint();
          releaseReceipt.complete();
          await _bounded(receipt);
        }
        await _bounded(held.reporter.flush());
        await _bounded(held.receipt(capturedActivity: held.capture()));
        await _bounded(held.reporter.flush());
        expect(held.bridge.operations('markWeekly'), isEmpty);
        final bytes = await _bounded(held.store.read(isCurrent: () => true));
        if (bytes != null) {
          final contacts =
              (jsonDecode(utf8.decode(bytes)) as Map)['contacts'] as List;
          expect(
            contacts.where((c) => (c as Map)['deliveredOutgoingSeen'] == true),
            isEmpty,
          );
        }
      } finally {
        if (!releaseReceipt.isCompleted) {
          releaseReceipt.complete();
        }
        await _bounded(held.close());
      }
    },
  );

  test('B15RA-016 OFF-started real delete invalidates a new-epoch same-id admission after ON', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final held = await _bounded(_ReceiptHarness.create(beforeDelete: () async {
      entered.complete();
      await _bounded(release.future);
    }));
    Future<int>? deletion;
    try {
      await _bounded(held.reporter.observeConsent((enabled: false, consentEpoch: 8)));
      expect(held.capture().capture, isNull);
      deletion = held.sql(() => held.fixture.messageRepo.deleteMessage(_message));
      await _bounded(entered.future);
      await _bounded(held.reporter.observeConsent((enabled: true, consentEpoch: 9)));
      final parent = await _bounded(held.admitInitial());
      final before = (await _bounded(held.fixture.db.query('messages',
        where: 'id = ?', whereArgs: [_message]))).single;
      release.complete();
      expect(await _bounded(deletion), 1);
      expect(await _bounded(held.fixture.messageRepo.getMessage(_message)), isNull);
      await _bounded(held.sql(() => held.fixture.messageRepo.saveMessage(parent)));
      final restored = await _bounded(held.fixture.messageRepo.getMessage(_message));
      expect(restored!.toMap(), parent.toMap());
      expect((await _bounded(held.fixture.db.query('messages',
        where: 'id = ?', whereArgs: [_message]))).single, before);
      await _bounded(held.receipt(capturedActivity: held.capture()));
      await _bounded(held.expectDelivered(false));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (deletion != null) {
        await _bounded(deletion);
      }
      await _bounded(held.close());
    }
  });

  for (final change in ['profile', 'ABA']) {
    test('B15RA-017 stale $change SQL realm cannot invalidate successor lineage', () async {
      final oldNegative = h.reporter.captureChatSqlMutationObserver(
        sqlRealm: h.fixture.db, isSqlRealmOpen: () => h.fixture.db.isOpen,
        expectedAccountPeerId: _account);
      expect(oldNegative, isNotNull);
      h.reporter.observeIdentity(accountPeerId: _account,
        rootPrivateKeyBase64: 'public-other-profile',
        profileBinding: 'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      if (change == 'ABA') {
        h.reporter.observeIdentity(accountPeerId: _account,
          rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
          profileBinding: _binding);
      }
      await _bounded(h.reporter.flush());
      final successor = await _bounded(MediaRepositoryRealDbFixture.create(singleInstance: false));
      try {
        expect(identical(successor.db, h.fixture.db), isFalse);
        expect(await _bounded(successor.db.query('messages')), isEmpty);
        await _bounded(successor.db.insert('contacts', {
          'peer_id': _contact, 'public_key': 'public-contact-fixture',
          'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
          'username': 'Contact', 'signature': 'public-fixture-signature',
          'scanned_at': _time,
        }));
        final owner = h.capture().capture!;
        final intent = h.reporter.reserveChatCaptured(owner,
            contactAccountPeerId: _contact, messageId: _message, generationId: _message);
        expect(intent, isNotNull);
        final parent = h.parent(_message);
        final staged = await _bounded(h.reporter.observeChatSqlCaptured(owner,
          () => successor.messageRepo.stageOutgoingOrdinaryAttempt(
            expected: null, staged: parent, kind: OutgoingOrdinaryAttemptKind.fresh)));
        expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
        h.reporter.admitChatCaptured(owner, intent!);
        await _bounded(h.reporter.flush());
        // This genuinely deletes the matching old storage row. It must not
        // poison a successor loaded profile and distinct physical SQL realm.
        await _bounded(h.fixture.messageRepo.saveMessage(parent));
        expect(await _bounded(runWithOutgoingInitialAuthorityObserver(null,
          () => h.fixture.messageRepo.deleteMessage(_message),
          mutationObservation: (observer: oldNegative))), 1);
        await _bounded(handleDeliveryReceipt(message: _receipt(),
          messageRepo: successor.messageRepo, capturedActivity: h.capture()));
        await _bounded(h.expectDelivered(true));
      } finally {
        await _bounded(successor.dispose());
      }
    });
  }

  test('B15RA-018 a foreign physical SQL realm cannot revoke the current profile lineage', () async {
    await _bounded(h.admitInitial());
    final foreign = await _bounded(MediaRepositoryRealDbFixture.create(singleInstance: false));
    try {
      expect(identical(foreign.db, h.fixture.db), isFalse);
      expect(await _bounded(foreign.db.query('messages')), isEmpty);
      await _bounded(foreign.db.insert('contacts', {
        'peer_id': _contact, 'public_key': 'public-contact-fixture',
        'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
        'username': 'Contact', 'signature': 'public-fixture-signature',
        'scanned_at': _time,
      }));
      await _bounded(foreign.messageRepo.saveMessage(h.parent(_message)));
      final negative = h.reporter.captureChatSqlMutationObserver(
        sqlRealm: h.fixture.db, isSqlRealmOpen: () => h.fixture.db.isOpen,
        expectedAccountPeerId: _account);
      expect(await _bounded(runWithOutgoingInitialAuthorityObserver(null,
        () => foreign.messageRepo.deleteMessage(_message),
        mutationObservation: (observer: negative))), 1);
      await _bounded(h.receipt(capturedActivity: h.capture()));
      await _bounded(h.expectDelivered(true));
    } finally {
      await _bounded(foreign.dispose());
    }
  });

  test('B15RA-019 a real purge of another contact leaves current lineage eligible', () async {
    await _bounded(h.admitInitial());
    const otherContact = 'unrelated-logical-contact';
    final other = h.parent('unrelated-contact-message').copyWith(contactPeerId: otherContact);
    await _bounded(h.fixture.db.insert('contacts', {
      'peer_id': otherContact, 'public_key': 'public-other-contact-fixture',
      'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
      'username': 'Other', 'signature': 'public-other-signature', 'scanned_at': _time,
    }));
    final staged = await _bounded(h.sql(() => h.fixture.messageRepo.stageOutgoingOrdinaryAttempt(
      expected: null, staged: other, kind: OutgoingOrdinaryAttemptKind.fresh)));
    expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
    final purge = await _bounded(h.sql(() => dbPurgeDirectContactConversationAndContact(
      h.fixture.db, otherContact)));
    expect(purge.deletedMessages, 1);
    expect(purge.deletedContact, isTrue);
    await _bounded(h.receipt(capturedActivity: h.capture()));
    await _bounded(h.expectDelivered(true));
  });

  test('B15RA-020 committed SQL admission survives delayed producer callback and finally cancel', () async {
    final committed = Completer<void>();
    final release = Completer<void>();
    final held = await _bounded(_ReceiptHarness.create(afterTextStage: () async {
      committed.complete();
      await _bounded(release.future);
    }));
    Future<OutgoingOrdinaryMutationResult>? pending;
    try {
      final original = held.capture();
      final intent = held.reporter.reserveChatCaptured(original.capture!,
        contactAccountPeerId: _contact, messageId: _message, generationId: _message);
      expect(intent, isNotNull);
      final parent = held.parent(_message);
      pending = held.sql(() => held.fixture.messageRepo.stageOutgoingDirectTextInboxCustody(
        expected: null, staged: parent, kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _contact, incarnationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        wireEnvelope: parent.wireEnvelope!,
      ));
      await _bounded(committed.future);
      // A sender's late finally is observation cleanup, not SQL rollback.
      held.reporter.cancelChatCaptured(original.capture!, intent!);
      await _bounded(held.receipt(capturedActivity: original));
      await _bounded(held.expectDelivered(true));
      release.complete();
      final applied = await _bounded(pending);
      expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
      held.reporter.admitChatCaptured(original.capture!, intent);
      await _bounded(held.receipt(capturedActivity: original));
      await _bounded(held.expectDelivered(true));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (pending != null) {
        await _bounded(pending);
      }
      await _bounded(held.close());
    }
  });

  test('B15RA-021 unresolved fresh admission rolls back and remains cancelable', () async {
    final original = h.capture();
    final intent = h.reporter.reserveChatCaptured(original.capture!,
      contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(intent, isNotNull);
    final entered = Completer<void>();
    final release = Completer<void>();
    final pending = h.sql(() => dbWriteTransaction(h.fixture.db, (txn) async {
      final applied = await dbStageOutgoingOrdinaryAttemptWithinTransaction(txn,
        expectedRow: null, stagedRow: h.parent(_message).toMap(),
        kind: OutgoingOrdinaryAttemptKind.fresh);
      expect(applied, OutgoingOrdinaryMutationOutcome.applied);
      entered.complete();
      await _bounded(release.future);
      throw StateError('controlled fresh rollback');
    }));
    final failed = expectLater(_bounded(pending), throwsA(isA<StateError>()));
    try {
      await _bounded(entered.future);
      h.reporter.cancelChatCaptured(original.capture!, intent!);
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
    await _bounded(failed);
    await _bounded(h.reporter.flush());
    expect(await _bounded(h.fixture.messageRepo.getMessage(_message)), isNull);
    final replacement = h.reporter.reserveChatCaptured(original.capture!,
      contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(replacement, isNotNull, reason: 'Aborted SQL did not admit or retain the cancelled intent');
    final applied = await _bounded(h.sql(() => h.stageParent(_message)));
    expect(applied.id, _message);
    h.reporter.admitChatCaptured(original.capture!, replacement!);
    await _bounded(h.receipt(capturedActivity: original));
    await _bounded(h.expectDelivered(true));
  });

  for (final sameSender in [true, false]) {
    test('B15RA-022 ${sameSender ? 'same-sender re-encryption preserves' : 'foreign header revokes'} lineage before ACK clearing', () async {
      await _bounded(h.admitInitial());
      final replacement = MessagePayload.buildEncryptedEnvelope(
        id: _message, senderPeerId: sameSender ? _account : 'unproven-transport-sender',
        senderUsername: 'Local', kem: 'public-retry-kem',
        ciphertext: 'public-retry-ciphertext', nonce: 'public-retry-nonce',
      );
      await _bounded(h.sql(() => h.fixture.messageRepo.updateWireEnvelope(_message, replacement)));
      final current = (await _bounded(h.fixture.messageRepo.getMessage(_message)))!;
      expect(current.wireEnvelope, replacement);
      await _bounded(h.settleLive(current));
      await _bounded(h.receipt(capturedActivity: h.capture()));
      await _bounded(h.expectDelivered(sameSender));
    });
  }
  test('B15RA-023 finalized same-sender SQL controls stay bounded while checkpoint is held', () async {
    h.holdCheckpoint();
    await _bounded(h.admitInitial(flush: false));
    await _bounded(h.checkpointHold['entered']!.future);
    final baseline = h.reporter.pendingChatFactCountForTesting;
    expect(baseline, greaterThan(0), reason: 'The real admission is still queued behind held optional I/O');
    var lastEnvelope = '';
    try {
      await _bounded(() async {
        for (var index = 0; index < 16; index++) {
          lastEnvelope = MessagePayload.buildEncryptedEnvelope(
            id: _message, senderPeerId: _account, senderUsername: 'Local',
            kem: 'public-retry-kem', ciphertext: 'public-retry-ciphertext-$index',
            nonce: 'public-retry-nonce',
          );
          await _bounded(h.sql(() =>
              h.fixture.messageRepo.updateWireEnvelope(_message, lastEnvelope)));
          expect(h.reporter.pendingChatFactCountForTesting, baseline,
            reason: 'Each committed same-sender control retires without waiting for the checkpoint');
        }
      }());
      final durable = (await _bounded(h.fixture.db.query('messages',
        where: 'id = ?', whereArgs: [_message]))).single;
      expect(durable['wire_envelope'], lastEnvelope);
      await _bounded(h.receipt(capturedActivity: h.capture()));
      final accepted = h.reporter.pendingChatFactCountForTesting;
      expect(accepted, baseline + 1,
        reason: 'The sealed receipt still has its real worker effect queued');
      await _bounded(h.remove('message'));
      expect(await _bounded(h.fixture.messageRepo.getMessage(_message)), isNull);
      expect(h.reporter.pendingChatFactCountForTesting, accepted,
        reason: 'Committed removal retires its control without discarding accepted credit');
    } finally {
      h.releaseCheckpoint();
    }
    await _bounded(h.expectDelivered(true));
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
  _ReceiptHarness(this.root, this.fixture, this.store, this.bridge, this.reporter, this.checkpointHold);

  final Map<String, Completer<void>> checkpointHold;
  final Directory root;
  final MediaRepositoryRealDbFixture fixture;
  final EngagementChatCheckpointStore store;
  final _ReceiptBridge bridge;
  final ActiveIdentityReporter reporter;

  static Future<_ReceiptHarness> create({
    Future<void> Function()? afterReceipt,
    Future<void> Function()? beforeDelete,
    Future<void> Function()? afterTextStage,
  }) async {
    await _bounded(AppDiagnostics.installForTesting(useNative: false, enabled: true));
    final root = await _bounded(Directory.systemTemp.createTemp('b15-weekly-receipt-'));
    final fixture = await _bounded(MediaRepositoryRealDbFixture.create(
      singleInstance: false,
      afterOrdinaryReceiptSettlement: afterReceipt,
      beforeMessageDelete: beforeDelete,
      afterDirectTextCustodyStage: afterTextStage,
    ));
    final checkpointHold = <String, Completer<void>>{};
    final store = await _bounded(EngagementChatCheckpointStore.open('${root.path}/private',
      beforeCommit: (_) async {
        final gate = checkpointHold['release'];
        if (gate != null) {
          final entered = checkpointHold['entered']!;
          if (!entered.isCompleted) {
            entered.complete();
          }
          await _bounded(gate.future);
        }
      },
    ));
    final bridge = _ReceiptBridge();
    final reporter = ActiveIdentityReporter(
      statePath: '${root.path}/native.json', chatWitnessStore: store,
      chatNowMilliseconds: () => _start + 10000,
      chatStoreDeadline: _budget,
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
    final h = _ReceiptHarness(root, fixture, store, bridge, reporter, checkpointHold);
    final owner = h.capture().capture;
    expect(owner, isNotNull);
    expect(await _bounded(reporter.weeklyProjectionCaptured(owner!)),
        (week: _week, startMilliseconds: _start, endMilliseconds: _end));
    await _bounded(reporter.flush());
    return h;
  }

  _Observation capture() => (reporter: reporter,
      capture: reporter.captureOwner(expectedAccountPeerId: _account));

  ConversationMessage parent(String id) => ConversationMessage(
      id: id, contactPeerId: _contact, senderPeerId: _account,
      text: 'ordinary receipt initial', timestamp: _time, createdAt: _time,
      status: 'sending', isIncoming: false, wireEnvelope: _envelope(id),
    );

  Future<ConversationMessage> stageParent(String id) async {
    final parent = this.parent(id);
    final staged = await _bounded(fixture.messageRepo.stageOutgoingOrdinaryAttempt(
      expected: null, staged: parent, kind: OutgoingOrdinaryAttemptKind.fresh,
    ));
    expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
    expect(staged.message!.wireEnvelope, parent.wireEnvelope);
    return staged.message!;
  }

  // Explicit witness setup tied to real SQL APPLIED, not an outgoing-producer
  // integration claim. Only the real receipt handler may report delivery.
  Future<ConversationMessage> admitInitial({bool flush = true}) async {
    final owner = capture().capture!;
    final intent = reporter.reserveChatCaptured(owner,
        contactAccountPeerId: _contact, messageId: _message, generationId: _message);
    expect(intent, isNotNull);
    final staged = await _bounded(reporter.observeChatSqlCaptured(
      owner, () => stageParent(_message),
    ));
    reporter.admitChatCaptured(owner, intent!);
    if (flush) {
      await _bounded(expectPending());
    }
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

  Future<T> sql<T>(Future<T> Function() work) =>
      reporter.observeChatSqlCaptured(capture().capture, work,
        mutationObservation: (observer: reporter.captureChatSqlMutationObserver(
          sqlRealm: fixture.db, isSqlRealmOpen: () => fixture.db.isOpen,
          expectedAccountPeerId: _account,
        )),
      );

  Future<void> remove(String kind) async {
    if (kind == 'edit') {
      final current = (await _bounded(fixture.messageRepo.getMessage(_message)))!;
      final staged = current.copyWith(text: 'accepted edit after receipt',
        editedAt: '2026-11-17T00:00:01.000Z', status: 'sending',
        transport: null, relayExpiresAt: null, custodyCheckedAt: null,
        wireEnvelope: _envelope(_message, eventId: 'later-accepted-edit'));
      final result = await _bounded(sql(() => fixture.messageRepo.stageOutgoingOrdinaryAttempt(
        expected: current, staged: staged, kind: OutgoingOrdinaryAttemptKind.edit,
      )));
      expect(result.outcome, OutgoingOrdinaryMutationOutcome.applied);
    } else if (kind == 'message') {
      expect(await _bounded(sql(() => fixture.messageRepo.deleteMessage(_message))), 1);
    } else if (kind == 'bulk') {
      expect(await _bounded(sql(() => fixture.messageRepo.deleteMessagesForContact(_contact))), 1);
    } else {
      final result = await _bounded(sql(() => dbPurgeDirectContactConversationAndContact(fixture.db, _contact)));
      expect(result.deletedContact, isTrue);
    }
  }

  void holdCheckpoint() {
    checkpointHold['entered'] = Completer<void>();
    checkpointHold['release'] = Completer<void>();
  }

  void releaseCheckpoint() {
    final gate = checkpointHold.remove('release');
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  Future<void> expectDelivered(bool expected) async {
    await _bounded(reporter.flush());
    final contact = (await _bounded(contacts())).single as Map;
    expect(contact['deliveredOutgoingSeen'], expected,
      reason: 'Only authenticated receipt acceptance in the original SQL-admitted lineage may credit delivery');
    expect(bridge.operations('markWeekly'), isEmpty,
      reason: 'Outgoing delivery without incoming communication never qualifies weekly chat');
  }

  Future<void> close() async {
    releaseCheckpoint();
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
    assertNotInsideDbWriteTransaction();
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
