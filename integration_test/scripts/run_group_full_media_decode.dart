import '../../tool/sims/production_group_media_criteria.dart';
import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateGroupFullMediaDecodeObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  // Retain the existing real new-member voice-playing and video-open oracle.
  // Its narrower native player credit is not replaced by file metadata.
  final playerProof = await evidence.json(observed['newMemberPlayerProofPath']);
  failures.addAll(validateProductionGroupMedia(playerProof));
  if (playerProof['runId'] != evidence.receipt['runId']) {
    failures.add('new-member player proof must bind this run');
  }
  final members = (observed['entitledRoles'] as List).cast<String>().toSet();
  final sender = observed['senderRole'] as String;
  final media = journeyGapRows(observed['media']);
  if (members.length < 3 ||
      !members.contains(sender) ||
      !media.map((item) => item['kind']).toSet().containsAll([
        'image',
        'video',
        'voice',
        'document',
      ])) {
    failures.add(
      'current sender and every entitled image/video/voice/document receiver required',
    );
  }
  for (final item in media) {
    final source = await fingerprintMediaFile(
      evidence.file(item['processedSentFilePath']),
    );
    final recipients = journeyGapRows(item['recipients']);
    final expected = members.difference({sender});
    if (recipients.length != expected.length ||
        recipients
            .map((row) => row['role'])
            .toSet()
            .difference(expected)
            .isNotEmpty ||
        recipients.map((row) => row['role']).toSet().length !=
            expected.length) {
      failures.add(
        'every entitled recipient must have an independent media outcome',
      );
    }
    for (final row in recipients) {
      final received = await fingerprintMediaFile(
        evidence.file(row['fullReceivedFilePath']),
      );
      final native = await evidence.json(row['nativeOpenPath']);
      if (!received.sameBytes(source) ||
          row['messageId'] != item['messageId'] ||
          row['attachmentId'] != item['attachmentId'] ||
          row['caption'] != item['caption'] ||
          row['persistedCountAfterReopen'] != 1 ||
          row['downloadStatus'] != 'done' ||
          native['attachmentId'] != item['attachmentId'] ||
          native['plaintextSha256'] != received.sha256Hex ||
          native['viewer'] != 'native_full_viewer') {
        failures.add(
          '${row['role']}: exact sent rendition/caption and current complete native open required',
        );
      }
      if (['image', 'video'].contains(item['kind']) &&
          ((native['width'] as int) <= 0 || (native['height'] as int) <= 0)) {
        failures.add('${row['role']}: full decoded frame required');
      }
      if (['video', 'voice'].contains(item['kind']) &&
          ((native['startPositionMs'] as int) < 0 ||
              (native['durationMs'] as int) <= 0 ||
              (native['endPositionMs'] as int) -
                      (native['startPositionMs'] as int) <
                  250 ||
              (native['endPositionMs'] as int) >
                  (native['durationMs'] as int))) {
        failures.add(
          '${row['role']}: actual native playback advancement required',
        );
      }
      if (item['kind'] == 'document' && (native['renderedPages'] as int) < 1) {
        failures.add('${row['role']}: full native document page required');
      }
    }
  }
  final interrupted = journeyGapMap(observed['receiverInterruption']);
  if (interrupted['verifiedOwnedDeath'] != true ||
      interrupted['freshInvocation'] != true ||
      interrupted['finalMessageCount'] != 1 ||
      interrupted['finalAttachmentCount'] != 1 ||
      !evidence.files.containsKey(interrupted['processDeathPath'])) {
    failures.add(
      'one receiver must actually die/reopen and converge without duplicates',
    );
  }
  final partial = journeyGapMap(observed['partialFailure']);
  if ((partial['unaffectedCompletedAtMs'] as int) >=
          (partial['failedRecipientRetriedAtMs'] as int) ||
      partial['unaffectedFailedCount'] != 0 ||
      partial['retriedRecipientFinalCount'] != 1) {
    failures.add(
      'one recipient failure must not stall or duplicate an unaffected recipient',
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
        journeyId: 'MEDIA-036',
        requiredKinds: [
          'new-member-player-proof',
          'processed-sent-full-file',
          'every-recipient-full-file',
          'native-full-open',
          'receiver-interruption',
          'independent-partial-failure',
        ],
      );
      evaluated = true;
      failures.addAll(await validateGroupFullMediaDecodeObservations(evidence));
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'MEDIA-036 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'MEDIA-036',
    ids: ['GC-006', 'MEDIA-036'],
    captureGap:
        'Existing new-member campaign already proves actual voice-playing and video opening; no current producer joins exact processed bytes, all entitled recipients, complete native media, receiver restart and independent failures.',
    prerequisites: [
      'Retain run_production_group_new_member_media.dart and validateProductionGroupMedia actual native player credit unchanged.',
      'Future fapp supplies current membership, actual source/receiver full exports and native full viewer/decoder observations per recipient, plus owned interruption and partial failure.',
      'Do not infer intelligible voice/full decode completeness from player start, descriptors or thumbnails; external execution remains Hetzner-only.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
