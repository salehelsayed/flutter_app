import '../../tool/sims/production_journey_gap_criteria.dart';
import 'contact_transfer_native_evidence.dart';

/// The existing CONTACT-001 oracle checks refusal-side zero mutation/egress,
/// real scanner entry, one logical request/contact and monotonic retry counts.
/// It evaluates observations; it does not capture or authenticate them.
List<String> validateQrCameraPermissionObservations(
  ContactTransferNativeEvidence evidence,
) => validateProductionJourneyGapReceipt(evidence.receipt);

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'CONTACT-001',
        requiredKinds: [
          'mcp-transcript',
          'native-permission',
          'app-counters',
          'device-discovery',
        ],
      );
      evaluated = true;
      failures.addAll(validateQrCameraPermissionObservations(evidence));
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'CONTACT-001 evidence is missing, malformed or not bound to this source/run',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'CONTACT-001',
    ids: ['CR-001', 'CONTACT-001'],
    captureGap:
        'No existing callable cross-platform optical-camera/OS-permission '
        'capture owner emits the required counters and raw MCP observations.',
    prerequisites: [
      'Future fapp owner pins available targets and exact candidate artifacts; unavailable platform legs are N/A by project policy.',
      'Actual Appium MCP cancellation, OS denial, Settings grant/retry and optical scan; no pasted QR or widget callback substitution.',
      'Record CONTACT_REQUEST_SEND_SENDING dispatch attempts, SQL logical counts, reopen and at least 10s duplicate observation; restore only owned state.',
      'Use --receipt <file> --source <full revision> --run-id <independent run>; this is saved-observation validation only.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
