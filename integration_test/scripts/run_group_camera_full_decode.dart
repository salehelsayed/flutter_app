import 'dart:convert';
import 'dart:io';

import '../../tool/sims/production_journey_gap_criteria.dart';
import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';
import 'evaluate_production_journey_gap_receipt.dart' as existing_decoder;

Future<List<String>> validateGroupCameraFullDecodeObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = validateProductionJourneyGapReceipt(evidence.receipt);
  for (final item in journeyGapRows(evidence.observations['media'])) {
    final sent = await fingerprintMediaFile(
      evidence.file(item['processedSentFilePath']),
    );
    for (final recipient in journeyGapRows(item['recipients'])) {
      final file = evidence.file(recipient['fullFile']);
      final received = await fingerprintMediaFile(file);
      if (!sent.sameBytes(received)) {
        failures.add(
          '${recipient['role']}: full camera rendition differs from actual processed sent bytes',
        );
      }
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
        journeyId: 'MEDIA-035',
        requiredKinds: [
          'native-camera',
          'processed-sent-full-file',
          'every-recipient-full-export',
          'native-full-open',
          'current-membership',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateGroupCameraFullDecodeObservations(evidence),
      );
      // Reuse the existing full-export decoder (including its HEIC fallback),
      // rather than implementing a second image/video decoder here. Its
      // PASS_RECORDED remains read-only saved evidence, never native PASS.
      final temporary = await Directory.systemTemp.createTemp(
        'group-camera-evaluator-',
      );
      try {
        String option(String name) => arguments[arguments.indexOf(name) + 1];
        final output = File('${temporary.path}/verdict.json');
        await existing_decoder.main([
          '--receipt',
          option('--receipt'),
          '--source',
          option('--source'),
          '--output',
          output.path,
        ]);
        final verdict = journeyGapMap(jsonDecode(await output.readAsString()));
        if (verdict['status'] != 'PASS_RECORDED') {
          failures.add(
            'existing full-export/recorded-native criteria rejected this camera evidence',
          );
        }
      } finally {
        await temporary.delete(recursive: true);
      }
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'MEDIA-035 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'MEDIA-035',
    ids: ['GC-006', 'MEDIA-035'],
    captureGap:
        'Existing camera receipt criteria/host full-export decoder can check saved observations, but no installed ordinary-app group camera producer captures exact processed input and every recipient native full-open evidence.',
    prerequisites: [
      'Future fapp uses actual group camera Original and Compressed capture, exact caption and every current entitled recipient.',
      'Existing validateProductionJourneyGapReceipt MEDIA-035 criteria are reused with actual full-file hashing/host image decode; raw native viewer/capture provenance remains separately required.',
      'A native camera callback, gallery fixture or HEIF mock is insufficient; host codec success does not prove native decoder completeness.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
