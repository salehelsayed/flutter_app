import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateFreshOnboardingFirstMessagesObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final initial = await evidence.json(observed['initialStatePath']);
  final ready = await evidence.json(observed['afterOnboardingStatePath']);
  final actions = await evidence.json(observed['fixtureCommandAuditPath']);
  if (initial['identityPeerId'] != null ||
      initial['contacts'] != 0 ||
      initial['groups'] != 0 ||
      initial['messages'] != 0 ||
      (actions['seedOrBootstrapCommands'] as List).isNotEmpty ||
      ready['identityPeerId'] is! String ||
      (ready['identityPeerId'] as String).isEmpty ||
      ready['secureIdentityPersistedAfterReopen'] != true ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${ready['identityKeySha256']}')) {
    failures.add(
      'real unseeded onboarding must create and durably reopen the identity without prepared contacts/groups',
    );
  }
  final order = (
    onboarded: observed['onboardingCompleteSequence'] as int,
    scanned: observed['opticalContactScanSequence'] as int,
    consent: observed['contactConsentSequence'] as int,
    direct: observed['firstDirectSequence'] as int,
    invite: observed['groupInviteConsentSequence'] as int,
    group: observed['firstGroupSequence'] as int,
  );
  if (!(order.onboarded < order.scanned &&
      order.scanned < order.consent &&
      order.consent < order.direct &&
      order.direct < order.invite &&
      order.invite < order.group)) {
    failures.add(
      'actual onboarding -> optical scan/consent -> first direct -> group invite consent -> first group order required',
    );
  }
  final first = journeyGapRows(observed['firstMessages']);
  if (first.length != 2 ||
      !first.map((row) => row['lane']).toSet().containsAll([
        'direct',
        'group',
      ])) {
    failures.add('both first ordinary direct and group message legs required');
  }
  for (final row in first) {
    final recipients = journeyGapRows(row['receivers']);
    if (row['runId'] != evidence.receipt['runId'] ||
        row['senderPeerId'] != ready['identityPeerId'] ||
        (row['text'] as String).isEmpty ||
        (row['messageId'] as String).isEmpty ||
        recipients.isEmpty ||
        recipients.length != (row['entitledReceiverCount'] as int) ||
        recipients.any(
          (recipient) =>
              recipient['receivedText'] != row['text'] ||
              recipient['messageId'] != row['messageId'] ||
              recipient['persistedCountAfterReopen'] != 1 ||
              recipient['authenticatedSenderKeySha256'] !=
                  ready['identityKeySha256'],
        )) {
      failures.add(
        '${row['lane']}: actual newly onboarded identity must deliver exact first content to every entitled peer once',
      );
    }
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
        journeyId: 'RG-002',
        requiredKinds: [
          'unseeded-initial-state',
          'native-onboarding',
          'fixture-command-audit',
          'optical-contact-consent',
          'group-invite-consent',
          'first-direct-group-exchange',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateFreshOnboardingFirstMessagesObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'RG-002 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'RG-002',
    ids: ['RG-002'],
    captureGap:
        'Existing host golden path substitutes native identity/storage/network, and existing production journeys prepare contacts; no exact unseeded native onboarding/consent/first-direct/first-group capture owner exists.',
    prerequisites: [
      'Future fapp starts an owned disposable installation with no identity/contacts/groups/messages and retains a command audit proving no fixture bootstrap or seeding.',
      'Use normal native onboarding, actual optical contact scan and explicit contact/invite consent, then ordinary first direct and group sends from the newly persisted identity.',
      'Verify every entitled receiver exact content/current sender key and one persisted copy after reopen; prepared contacts or host fakes do not satisfy the initial state.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
