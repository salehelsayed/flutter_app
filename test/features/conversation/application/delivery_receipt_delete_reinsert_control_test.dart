import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/direct_reaction_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_observer.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _account = 'receipt-guard-local';
const _contact = 'receipt-guard-remote';
const _id = 'receipt-guard-message';
const _time = '2026-11-17T00:00:00.000Z';
const _edited = '2026-11-17T00:00:01.000Z';

Future<T> _bounded<T>(Future<T> work) =>
    work.timeout(const Duration(seconds: 3));

String _envelope({String? eventId}) => MessagePayload.buildEncryptedEnvelope(
  id: _id, senderPeerId: _account, senderUsername: 'Local',
  kem: 'public-fixture-kem', ciphertext: 'public-fixture-ciphertext',
  nonce: 'public-fixture-nonce', eventId: eventId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B15RW-ERASURE-001 public delete and late insert erase row history while fresh admission survives', () async {
    await _bounded(AppDiagnostics.installForTesting(useNative: false, enabled: true));
    final fixture = await _bounded(MediaRepositoryRealDbFixture.create(
      wireOutgoingDirectTextMutationInboxCustody: true,
    ));
    final root = await _bounded(Directory.systemTemp.createTemp('b15-receipt-guard-'));
    final store = await _bounded(EngagementChatCheckpointStore.open('${root.path}/private'));
    // The production observer and real store establish a genuinely fresh
    // admitted witness. This is not reporter/bootstrap/producer integration.
    final observer = EngagementChatObserver(
      store: store,
      lookupWeek: (_) async => (
        week: '2026-W47', startMilliseconds: 0, endMilliseconds: 2000000,
      ),
      retainChat: (_, __) async => true,
      nowMilliseconds: () => 10000,
    );
    try {
      expect(fixture.messageRepo.supportsDirectTextMutationInboxCustody, isTrue);
      observer.replaceOwner((
        accountPeerId: _account,
        profileBinding: 'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        consentEpoch: 7,
      ));
      final capture = observer.captureOwner(expectedAccountPeerId: _account)!;
      final intent = observer.reserve(capture,
          contactAccount: _contact, messageId: _id, generationId: _id);
      expect(intent, isNotNull);
      final repo = fixture.messageRepo;
      final initial = ConversationMessage(
        id: _id, contactPeerId: _contact, senderPeerId: _account,
        text: 'original', timestamp: _time, createdAt: _time,
        status: 'sending', isIncoming: false, wireEnvelope: _envelope(),
      );
      final staged = await _bounded(repo.stageOutgoingDirectTextInboxCustody(
        expected: null, staged: initial, kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _contact, incarnationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        wireEnvelope: initial.wireEnvelope!,
      ));
      expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
      observer.admitted(intent!);
      await _bounded(observer.flush());
      final checkpoint = await _bounded(store.read(isCurrent: () => true));
      expect(checkpoint, isNotNull);
      expect((jsonDecode(utf8.decode(checkpoint!)) as Map)['contacts'], [
        {'account': _contact, 'incomingSeen': false, 'deliveredOutgoingSeen': false,
          'outgoing': [{'message': _id, 'generation': _id}]},
      ]);
      final custody = await _bounded(repo.loadDirectInboxCustodyForMessage(
          recipientPeerId: _contact, messageId: _id));
      expect(custody, isNotNull);
      Future<void> live(ConversationMessage current) async {
        final settled = await _bounded(repo.settleOutgoingOrdinaryTransport(
          messageId: _id, expectedContactPeerId: _contact,
          expectedEnvelope: current.wireEnvelope, status: 'delivered',
          transport: 'direct', relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ));
        expect(settled.outcome, OutgoingOrdinaryMutationOutcome.applied);
      }
      await _bounded(live(staged.message!));
      // A real repository projection retained before the edit, not a
      // hand-written delivered row or fabricated settlement result.
      final delayedOriginal = (await _bounded(repo.getMessage(_id)))!;
      expect(delayedOriginal.status, 'delivered');
      expect(delayedOriginal.wireEnvelope, isNull);
      final originalSql = (await _bounded(fixture.db.query('messages',
          where: 'id = ?', whereArgs: [_id], limit: 1))).single;
      final edit = delayedOriginal.copyWith(
        status: 'sending', transport: null, text: 'later edit', editedAt: _edited,
        wireEnvelope: _envelope(eventId: 'receipt-guard-edit'),
      );
      final editStage = await _bounded(repo.stageOutgoingDirectTextMutationInboxCustody(
        expected: delayedOriginal, staged: edit, kind: OutgoingOrdinaryAttemptKind.edit,
        recipientPeerId: _contact, eventId: 'receipt-guard-edit',
        wireEnvelope: edit.wireEnvelope!,
      ));
      expect(editStage.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(editStage.custody, isNotNull);
      await _bounded(live(editStage.message!));
      final deliveredEdit = (await _bounded(repo.getMessage(_id)))!;
      expect(deliveredEdit.editedAt, _edited);
      expect(deliveredEdit.wireEnvelope, isNull);
      final completion = await _bounded(repo.completeAcceptedDirectInboxCustodyIfExact(
        expected: custody!, relayExpiresAt: 1795000000000,
      ));
      expect(completion.completed, isTrue);
      expect(await _bounded(repo.loadDirectInboxCustodyForMessage(
          recipientPeerId: _contact, messageId: _id)), isNull);
      final mutationCompletion = await _bounded(repo.completeAcceptedDirectTextMutationInboxCustodyIfExact(
        expected: editStage.custody!, relayExpiresAt: 1795000000000,
      ));
      expect(mutationCompletion, DirectMutationInboxCustodyCompletionOutcome.completed);
      expect(await _bounded(repo.loadDirectTextMutationInboxCustodyForEvent(
          recipientPeerId: _contact, eventId: 'receipt-guard-edit')), isNull);
      expect((await _bounded(repo.getMessage(_id)))!.editedAt, _edited);
      // This diagnostic asserts current reachability, not a new deletion
      // policy. It never claims that reinsertion should be refused.
      final removal = repo.messageRemovals.first.timeout(const Duration(seconds: 3));
      expect(await _bounded(repo.deleteMessage(_id)), 1);
      final removed = await _bounded(removal);
      expect(removed.messageId, _id);
      expect(removed.contactPeerId, _contact);
      expect(await _bounded(repo.getMessage(_id)), isNull);
      expect(await _bounded(fixture.db.query('messages',
          where: 'id = ?', whereArgs: [_id])), isEmpty);
      await _bounded(observer.flush());
      expect(identical(observer.captureOwner(expectedAccountPeerId: _account), capture), isTrue);
      expect(await _bounded(store.read(isCurrent: () => true)), checkpoint);

      await _bounded(repo.saveMessage(delayedOriginal));
      final reinsertedSql = (await _bounded(fixture.db.query('messages',
          where: 'id = ?', whereArgs: [_id], limit: 1))).single;
      // Compare the WHOLE physical row, including any schema defaults or
      // high-water columns omitted from the ConversationMessage projection.
      expect(reinsertedSql, originalSql,
          reason: 'Public delete followed by late public save can recreate '
              'the exact earlier delivered initial row after both custody owners retire');
      final reinserted = (await _bounded(repo.getMessage(_id)))!;
      expect(reinserted.status, 'delivered');
      expect(reinserted.wireEnvelope, isNull);
      expect(reinserted.editedAt, isNull);
      expect(reinserted.text, 'original');
      await _bounded(observer.flush());
      expect(identical(observer.captureOwner(expectedAccountPeerId: _account), capture), isTrue);
      expect(await _bounded(store.read(isCurrent: () => true)), checkpoint,
          reason: 'The same freshly admitted witness survives physical history erasure');
    } finally {
      await _bounded(observer.dispose());
      await _bounded(store.close());
      await _bounded(fixture.dispose());
      await _bounded(root.delete(recursive: true));
      await _bounded(AppDiagnostics.instance.dispose());
    }
  });
}
