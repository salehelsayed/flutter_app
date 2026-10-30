import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';

import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateAccountTransferPairingObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final displayedText = await evidence
      .file(observed['displayedPayloadPath'])
      .readAsString();
  final scannedText = await evidence
      .file(observed['scannedPayloadPath'])
      .readAsString();
  final scanAt = DateTime.parse(observed['scanAt'] as String).toUtc();
  final displayed = parseMigrationQrPayload(
    qrData: displayedText,
    now: () => scanAt,
  );
  final scanned = parseMigrationQrPayload(
    qrData: scannedText,
    now: () => scanAt,
  );
  if (displayed.$1 != MigrationQrParseResult.success ||
      scanned.$1 != MigrationQrParseResult.success ||
      displayed.$2 != scanned.$2) {
    failures.add(
      'actual displayed and optically decoded migration payload must parse and match at scan time',
    );
    return failures;
  }
  final payload = scanned.$2!;
  final route = (
    entry: observed['scannerInput'] as String,
    scan: observed['scanSequence'] as int,
    confirmation: observed['confirmationSequence'] as int,
    consent: observed['confirmedSequence'] as int,
  );
  if (route.entry != 'optical_camera' ||
      route.scan >= route.confirmation ||
      route.confirmation >= route.consent ||
      observed['route'] != 'account_migration' ||
      observed['contactDialogCount'] != 0 ||
      observed['contactRequestsSent'] != 0 ||
      observed['contactsAdded'] != 0 ||
      observed['sessionId'] != payload.sessionId) {
    failures.add(
      'optical scan must retain the migration route and require confirmation with zero contact side effects',
    );
  }
  final expectedCode = deriveMigrationPairingConfirmationCode(payload);
  if (observed['oldPhoneConfirmationCode'] != expectedCode ||
      observed['newPhoneConfirmationCode'] != expectedCode ||
      observed['channelNonce'] != payload.channelNonce) {
    failures.add(
      'both confirmation surfaces and channel nonce must bind the exact scanned pairing payload',
    );
  }
  final mismatch = journeyGapMap(observed['mismatchedCode']);
  if (mismatch['transferStarted'] != false ||
      mismatch['contactsAdded'] != 0 ||
      mismatch['returnedToConfirmation'] != true) {
    failures.add(
      'mismatched confirmation must stop transfer and retain a usable confirmation route',
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
        journeyId: 'TRANSFER-001',
        requiredKinds: [
          'displayed-qr',
          'optical-scan',
          'confirmation-ui',
          'contact-egress-counters',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateAccountTransferPairingObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'TRANSFER-001 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'TRANSFER-001',
    ids: ['DC-019', 'TRANSFER-001'],
    captureGap:
        'Existing scanner/migration tests inject callbacks or paste QR data; '
        'no current campaign captures native migration QR display plus optical decode and confirmation.',
    prerequisites: [
      'Future fapp owner pins available prepared devices and exact candidate, and uses actual Appium MCP scanner/confirmation actions.',
      'Capture displayed/decoded payloads as hashed run-local artifacts, route/action ordering and zero contact egress counters; never log private keys.',
      'Use current production QR parse/confirmation-code oracle at the actual recorded scan time; no host callback is optical evidence.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
