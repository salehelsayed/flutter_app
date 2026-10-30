import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';

import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateAccountTransferContinuityObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  Future<AccountMigrationAuthorityRecord> authority(String field) async =>
      AccountMigrationAuthorityRecord.fromPersistedJson(
        await evidence.file(observed[field]).readAsString(),
      );
  final old = await authority('oldAuthorityPath');
  final target = await authority('newAuthorityPath');
  final restartedOld = await authority('oldAfterRestartAuthorityPath');
  final imported = journeyGapMap(observed['importedIdentity']);
  final native = journeyGapMap(observed['newNativeIdentity']);
  if ([old, target, restartedOld].any((record) => record.isFailClosed) ||
      old.state != AccountMigrationAuthorityState.migratedOut ||
      restartedOld.state != AccountMigrationAuthorityState.migratedOut ||
      target.state != AccountMigrationAuthorityState.active ||
      old.accountPeerId != target.accountPeerId ||
      restartedOld.accountPeerId != target.accountPeerId ||
      imported['peerId'] != target.accountPeerId ||
      native['peerId'] != target.accountPeerId ||
      imported['publicKeySha256'] != native['publicKeySha256'] ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${native['publicKeySha256']}')) {
    failures.add(
      'reopened imported owner/native key must be active only on target; old source stays retired',
    );
  }
  final order = (
    imported: observed['importVerifiedSequence'] as int,
    blocked: observed['oldNetworkBlockedSequence'] as int,
    committed: observed['newActiveSequence'] as int,
    retired: observed['oldRetiredSequence'] as int,
    reopened: observed['newColdReopenSequence'] as int,
  );
  if (!(order.imported < order.blocked &&
      order.blocked < order.committed &&
      order.committed <= order.retired &&
      order.retired < order.reopened)) {
    failures.add(
      'verified import -> source block -> target active -> source retirement -> cold reopen ordering required',
    );
  }
  for (final lane in ['direct', 'group']) {
    final before = journeyGapMap(observed['${lane}Before']);
    final after = journeyGapMap(observed['${lane}AfterReopen']);
    if (before['historySha256'] != after['historySha256'] ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${before['historySha256']}') ||
        before['currentKeySha256'] != after['currentKeySha256'] ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${after['currentKeySha256']}') ||
        (after['historyCount'] as int) <= 0 ||
        before['historyCount'] != after['historyCount']) {
      failures.add(
        '$lane: imported history and current key authority must survive actual target reopen',
      );
    }
  }
  final exchanges = journeyGapRows(observed['freshExchanges']);
  final legs = exchanges
      .map((row) => '${row['lane']}/${row['direction']}')
      .toSet();
  if (exchanges.length != 4 ||
      !legs.containsAll([
        'direct/outbound',
        'direct/inbound',
        'group/outbound',
        'group/inbound',
      ]) ||
      exchanges.map((row) => row['messageId']).toSet().length != 4 ||
      exchanges.any(
        (row) =>
            row['runId'] != evidence.receipt['runId'] ||
            (row['dispatchSequence'] as int) <= order.reopened ||
            row['sentText'] != row['receivedText'] ||
            (row['sentText'] as String).isEmpty ||
            row['receivedCountAfterReopen'] != 1 ||
            row['authenticatedSenderKeySha256'] !=
                row['currentSenderKeySha256'] ||
            !RegExp(
              r'^[a-f0-9]{64}$',
            ).hasMatch('${row['authenticatedSenderKeySha256']}'),
      )) {
    failures.add(
      'fresh direct/group exchanges in both directions must follow cold reopen and use current authenticated keys',
    );
  }
  if (observed['oldReplayAttemptsAfterRestart'] != 0 ||
      observed['oldProviderLeaseCountAfterRetirement'] != 0 ||
      observed['newProviderLeaseCount'] != 1) {
    failures.add(
      'old runtime/provider cannot replay or retain active authority after source retirement',
    );
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'TRANSFER-010',
        requiredKinds: [
          'native-runtime-identity',
          'durable-authority',
          'cold-reopen-history',
          'authenticated-peer-exchange',
          'provider-lease',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateAccountTransferContinuityObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'TRANSFER-010 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'TRANSFER-010',
    ids: ['DC-019', 'TRANSFER-010'],
    captureGap:
        'No existing native transfer campaign joins imported account/native runtime '
        'identity, cold-reopened history, authenticated fresh exchanges and old provider retirement.',
    prerequisites: [
      'Future fapp owns actual Move Account UI, exact installed artifacts and available pinned peers; use Hetzner only for external relay/provider execution.',
      'Capture real current runtime keys, production persisted authority, source restart and independent provider lease observations without exposing secrets.',
      'Host bundle/import/cutover tests remain separate; record actual fresh direct/group app exchanges after native target cold reopen.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
