import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateAccountTransferMediaOpenObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final cases = journeyGapRows(evidence.observations['media']);
  final kinds = <String>{};
  for (final row in cases) {
    final item = (
      kind: row['kind'] as String,
      messageId: row['messageId'] as String,
      attachmentId: row['attachmentId'] as String,
      importedAt: row['importedAtMs'] as int,
      openedAt: row['openedAtMs'] as int,
    );
    kinds.add(item.kind);
    final original = await fingerprintMediaFile(
      evidence.file(row['originalExportPath']),
    );
    final imported = await fingerprintMediaFile(
      evidence.file(row['importedExportPath']),
    );
    if (!original.sameBytes(imported) ||
        item.messageId.isEmpty ||
        item.attachmentId.isEmpty ||
        item.openedAt <= item.importedAt ||
        row['viewer'] != 'native_full_viewer' ||
        row['openedAttachmentId'] != item.attachmentId ||
        row['openedMessageId'] != item.messageId ||
        row['ownerAuthorityCurrent'] != true) {
      failures.add(
        '${item.kind}: exact complete migrated bytes/current owner must reach the actual full native viewer',
      );
    }
    final native = await evidence.json(row['nativeObservationPath']);
    if (native['plaintextSha256'] != imported.sha256Hex ||
        native['runId'] != evidence.receipt['runId'] ||
        native['messageId'] != item.messageId ||
        native['attachmentId'] != item.attachmentId ||
        (native['backend'] as String).isEmpty) {
      failures.add(
        '${item.kind}: native observation must bind this run, owner and actual full file',
      );
    }
    if (item.kind == 'video' || item.kind == 'voice') {
      final playback = (
        start: native['startPositionMs'] as int,
        end: native['endPositionMs'] as int,
        duration: native['durationMs'] as int,
      );
      if (playback.duration <= 0 ||
          playback.start < 0 ||
          playback.end - playback.start < 250 ||
          playback.end > playback.duration) {
        failures.add(
          '${item.kind}: native playback must actually advance within the media duration',
        );
      }
    }
    if ((item.kind == 'video' || item.kind == 'image') &&
        ((native['width'] as int) <= 0 || (native['height'] as int) <= 0)) {
      failures.add(
        '${item.kind}: actual full decoded frame dimensions required',
      );
    }
    if (item.kind == 'document' && (native['renderedPages'] as int) < 1) {
      failures.add(
        'document: a native rendered page is required, not an external-open intent',
      );
    }
    if (item.kind == 'voice') {
      final content = await evidence.json(row['audibleContentObservationPath']);
      if (content['runId'] != evidence.receipt['runId'] ||
          content['plaintextSha256'] != imported.sha256Hex ||
          (content['expectedPhrase'] as String).isEmpty ||
          content['heardPhrase'] != content['expectedPhrase']) {
        failures.add(
          'voice: independent intelligible-content observation must match this exact migrated clip',
        );
      }
    }
  }
  if (cases.length != 4 ||
      kinds.length != 4 ||
      !kinds.containsAll(['image', 'video', 'voice', 'document'])) {
    failures.add(
      'migrated image/video/voice/document full-open observations all required',
    );
  }
  final recovery = journeyGapMap(
    evidence.observations['missingOriginalRecovery'],
  );
  if (recovery['originalMissingAtOpen'] != true ||
      recovery['falsePlaybackSuccess'] != false ||
      recovery['recoverableUiShown'] != true ||
      recovery['retriedAttachmentId'] != recovery['originalAttachmentId'] ||
      (recovery['originalAttachmentId'] as String).isEmpty ||
      recovery['recoveredFullFileSha256'] !=
          recovery['expectedFullFileSha256'] ||
      !RegExp(
        r'^[a-f0-9]{64}$',
      ).hasMatch('${recovery['recoveredFullFileSha256']}')) {
    failures.add(
      'missing original must show honest recovery and reopen the exact recovered full attachment',
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
        journeyId: 'TRANSFER-011',
        requiredKinds: [
          'original-full-export',
          'imported-full-export',
          'native-full-open',
          'voice-content-observation',
          'missing-original-recovery',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateAccountTransferMediaOpenObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'TRANSFER-011 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'TRANSFER-011',
    ids: ['DC-019', 'TRANSFER-011'],
    captureGap:
        'verifyNativeMediaOpen has no existing device campaign consumer; '
        'native migrated-file opening, intelligible voice and missing-original recovery capture are absent.',
    prerequisites: [
      'Future fapp captures actual imported native viewer/decoder evidence bound to current owner and exact full file; no silent player or thumbnail substitution.',
      'Use an independent intelligible-content witness for the exact voice clip; playback position alone does not establish audibility or content.',
      'Retain exact source/imported full exports plus owned missing-original recovery evidence; hashes do not establish native decode completeness.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
