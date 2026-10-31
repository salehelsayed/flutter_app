import 'contact_transfer_native_evidence.dart';

List<String> validateCrossPlatformContactAddObservations(
  ContactTransferNativeEvidence evidence,
) {
  final failures = <String>[];
  final cases = journeyGapRows(evidence.observations['directions']);
  final directions = <String>{};
  for (final row in cases) {
    final direction = (
      scanner: row['scannerPlatform'] as String,
      display: row['displayPlatform'] as String,
      pending: row['pendingDialogSequence'] as int,
      consent: row['explicitAcceptSequence'] as int,
      mutual: row['mutualContactSequence'] as int,
    );
    final id = '${direction.scanner}->${direction.display}';
    if (!directions.add(id) ||
        direction.scanner == direction.display ||
        !['android', 'ios'].contains(direction.scanner) ||
        !['android', 'ios'].contains(direction.display)) {
      failures.add('exact distinct Android/iOS scan directions required');
    }
    final targets = journeyGapMap(evidence.receipt['targets']);
    final scanner = journeyGapMap(targets[row['scannerRole']]);
    final display = journeyGapMap(targets[row['displayRole']]);
    if (scanner['platform'] != direction.scanner ||
        display['platform'] != direction.display ||
        scanner['deviceId'] == display['deviceId']) {
      failures.add('$id: claimed direction must match distinct actual targets');
    }
    if (row['scannerInput'] != 'optical_camera' ||
        row['payloadKind'] != 'contact' ||
        row['displayedQrSha256'] != row['decodedQrSha256'] ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${row['decodedQrSha256']}') ||
        !(direction.pending < direction.consent &&
            direction.consent < direction.mutual)) {
      failures.add(
        '$id: exact optical payload and pending -> explicit consent -> mutual order required',
      );
    }
    for (final side in ['scanner', 'display']) {
      final before = journeyGapMap(row['${side}Before']);
      final after = journeyGapMap(row['${side}AfterReopen']);
      final accepted = after['acceptedRequestsFromOther'] as int;
      if (before['contactsWithOther'] != 0 ||
          before['requestsFromOther'] != 0 ||
          after['contactsWithOther'] != 1 ||
          accepted < 0 ||
          accepted > 1 ||
          side == 'display' && accepted != 1 ||
          after['publicKeySha256'] != row['${side}ExpectedOtherKeySha256'] ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch('${after['publicKeySha256']}') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch('${after['mlKemKeySha256']}')) {
        failures.add(
          '$id/$side: fresh one-to-one relationship and current keys must survive reopen',
        );
      }
    }
    final exchanges = journeyGapRows(row['firstMessages']);
    final roles = {row['scannerRole'], row['displayRole']};
    if (row['pendingCountAtRecipient'] != 1 ||
        exchanges.length != 2 ||
        exchanges.map((x) => x['messageId']).toSet().length != 2 ||
        exchanges.map((x) => x['senderRole']).toSet().length != 2 ||
        exchanges.any(
          (x) =>
              x['runId'] != evidence.receipt['runId'] ||
              x['sentText'] != x['receivedText'] ||
              x['senderRole'] == x['receiverRole'] ||
              !roles.contains(x['senderRole']) ||
              !roles.contains(x['receiverRole']) ||
              (x['messageId'] as String).isEmpty ||
              (x['sentText'] as String).isEmpty ||
              x['receivedCountAfterReopen'] != 1 ||
              x['authenticatedSenderKeySha256'] !=
                  x['currentContactKeySha256'] ||
              !RegExp(
                r'^[a-f0-9]{64}$',
              ).hasMatch('${x['authenticatedSenderKeySha256']}'),
        )) {
      failures.add(
        '$id: both first-message directions require exact content/current-key and dedupe witnesses',
      );
    }
  }
  if (cases.length != 2 ||
      !directions.containsAll(['android->ios', 'ios->android'])) {
    failures.add(
      'both actual platform scanning directions are required; Android A/B is insufficient',
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
        journeyId: 'CR-009',
        requiredKinds: [
          'optical-scan',
          'pending-dialog',
          'explicit-consent',
          'sql-after-reopen',
          'first-message-transcript',
        ],
      );
      evaluated = true;
      failures.addAll(validateCrossPlatformContactAddObservations(evidence));
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'CR-009 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'CR-009',
    ids: ['CR-001', 'CR-009'],
    captureGap:
        'ProductionJourney has Android/iOS-simulator implementations; '
        'no existing two-direction optical QR/consent/first-chat capture owner covers physical iOS.',
    prerequisites: [
      'Future fapp resolves live available targets and exact artifacts. Record actual target kind; simulator observations do not prove physical iOS.',
      'Actual app optical scanner and displayed QR in both available Android/iOS directions, fresh identities and explicit named consent.',
      'Retain hashed scanner/dialog/action, current-key SQL reopen and run-bound first-message evidence; absent platform legs are N/A by project policy.',
      'Saved observations may be checked with --receipt, --source and --run-id; no native PASS is emitted.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
