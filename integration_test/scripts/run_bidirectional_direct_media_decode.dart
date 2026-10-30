import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:image/image.dart' as image;

import '../support/media_content_oracle.dart';
import 'media_recorded_control_process.dart';

const _scenario = 'production.media.bidirectional-direct-media';
const _journeys = <String>["DC-008", "MEDIA-004"];
const _knownGap =
    "KNOWN GAP [DC-008, MEDIA-004]: Actual gallery JPEG/PNG selection, paired photo/video/document transport, native full opening, caption and reopen with private policy have no joined producer. Ordinary exported controls do not grant private read authority.";
const _cases = <String, String>{
  'alice-to-bob-jpeg': 'jpeg',
  'bob-to-alice-jpeg': 'jpeg',
  'alice-to-bob-png': 'png',
  'bob-to-alice-png': 'png',
  'alice-to-bob-video': 'video',
  'bob-to-alice-video': 'video',
  'alice-to-bob-pdf': 'pdf',
  'bob-to-alice-pdf': 'pdf',
};

// Saved ordinary-file controls only. No picker, network, current SQL authority,
// native viewer, permission or lifecycle action is executed here. No supplied
// declaration is promoted to native proof. In particular, never export a
// protected/view-once file to feed this ordinary-media assertion entrypoint.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  List<String>? failures;
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 ||
        arguments.first != '--assert-existing-control') {
      stderr.writeln(
        'Usage: --list-scenarios | --assert-existing-control <saved-control.json>',
      );
      exitCode = 64;
      return;
    }
    try {
      final input = File(arguments.last).absolute;
      final decoded = jsonDecode(await input.readAsString());
      failures = decoded is Map
          ? await validateRecordedControls(
              Map<String, Object?>.from(decoded),
              input.parent,
            )
          : ['saved control must be an object'];
    } on Object {
      failures = ['saved control unreadable or malformed'];
    }
  }
  final failed = failures != null && failures.isNotEmpty;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(<String, Object?>{
      'status': failed ? 'FAIL' : 'BLOCKED',
      'blocker': failed ? 'test' : 'missingDriver',
      'assertionsAttempted': failed ? 1 : 0,
      'artifactPresent': false,
      'printOnly': false,
      'exitCode': failed ? 1 : 78,
      'scenario': _scenario,
      'journeyIds': _journeys,
      'detail': _knownGap,
      'nativeExecutedByThisCommand': false,
      'recordedControlEvaluated': failures != null,
      'recordedControlFailures': failures ?? const <String>[],
      'qualifyingNativeJourneyWritten': false,
      'scope': 'host assertion of supplied processed-input receipts, full ordinary exports and caption observations; native journey remains blocked',
      'prerequisites': <String>['Exact candidate/build and only live available pinned targets, resolved by the future execution owner.', 'Owned run directory with genuine processed blob:encrypt sender receipts, their independently retained digests and full receiver exports.', 'Existing public route composition may inject MediaOracleGoBridgeClient; unchanged installed bootstrap has no such consumer.', 'Actual Appium MCP/native owner must produce the missing UI/OS/viewer observations and restore only owned state.', 'No AWS binding; future external test services use authorized Hetzner only.'],
      'missingAssertions': <String>[_knownGap, 'No native decoder callback producer exists for verifyNativeMediaOpen; host decode and recorded caption fields do not fill that gap.'],
    })}',
  );
  exitCode = failed ? 1 : 78;
}

/// Pins actual processed encryption-input receipt hashes to full receiver bytes.
/// The cases are supplied controls, not a new capture/evidence producer. Caption
/// equality checks declarations only; it does not prove UI, DB or cold restart.
Future<List<String>> validateRecordedControls(
  Map<String, Object?> input,
  Directory runDirectory,
) async {
  final failures = <String>[];
  final rawCases = input['cases'];
  if (rawCases is! Map ||
      rawCases.length != _cases.length ||
      !rawCases.keys.toSet().containsAll(_cases.keys)) {
    return ['exact per-format control cases required'];
  }
  final identities = <String>{};
  final attachmentIds = <String>{};
  for (final entry in _cases.entries) {
    try {
      final raw = rawCases[entry.key];
      if (raw is! Map) throw const MediaOracleFailure('CONTROL_NOT_OBJECT');
      final item = Map<String, Object?>.from(raw);
      if (item['owner'] != 'direct') {
        throw const MediaOracleFailure('ORDINARY_DIRECT_EXPORT_ONLY');
      }
      final identity = MediaWireIdentity(
        runId: input['runId'] as String,
        owner: MediaOwnerLane.direct,
        messageId: item['messageId'] as String,
        attachmentId: item['attachmentId'] as String,
      );
      if (!identities.add(identity.digest) ||
          !attachmentIds.add(identity.attachmentId)) {
        throw const MediaOracleFailure('DISTINCT_CASE_IDENTITIES_REQUIRED');
      }
      // Same media/recipient field names as the existing production gap
      // evaluator; the case map selects supplied records, not app observations.
      final ownedRoot = await runDirectory.resolveSymbolicLinks();
      Future<File> evidenceFile(Object? relative) async {
        if (relative is! String ||
            relative.isEmpty ||
            relative.startsWith('/')) {
          throw const MediaOracleFailure('OWNED_RELATIVE_EVIDENCE_REQUIRED');
        }
        final file = File.fromUri(runDirectory.uri.resolve(relative));
        final resolved = await file.resolveSymbolicLinks();
        if (!resolved.startsWith('$ownedRoot${Platform.pathSeparator}')) {
          throw const MediaOracleFailure('EVIDENCE_OUTSIDE_OWNED_RUN');
        }
        return File(resolved);
      }

      final senderFile = await evidenceFile(item['senderReceiptFile']);
      final sender = jsonDecode(await senderFile.readAsString());
      if (sender is! Map) {
        throw const MediaOracleFailure('SENDER_RECEIPT_REQUIRED');
      }
      final binding = SentMediaBinding.fromSenderReceipt(
        receipt: Map<String, Object?>.from(sender),
        expectedReceiptSha256: item['senderReceiptSha256'] as String,
        expectedIdentity: identity,
      );
      if (!{'android', 'ios'}.contains(binding.source.runtimePlatform)) {
        throw const MediaOracleFailure('NATIVE_PROCESSED_SOURCE_REQUIRED');
      }
      final recipients = item['recipients'];
      if (recipients is! List ||
          recipients.length != 1 ||
          recipients.single is! Map) {
        throw const MediaOracleFailure('ONE_BOUND_DIRECT_RECIPIENT_REQUIRED');
      }
      final recipient = Map<String, Object?>.from(recipients.single as Map);
      if (recipient['messageId'] != identity.messageId ||
          recipient['attachmentId'] != identity.attachmentId ||
          recipient['messageCount'] != 1 ||
          recipient['attachmentCount'] != 1 ||
          recipient['messageCountAfterReopen'] != 1 ||
          recipient['attachmentCountAfterReopen'] != 1 ||
          recipient['downloadStatus'] != 'done') {
        throw const MediaOracleFailure(
          'RECORDED_RECIPIENT_IDENTITY_OR_REOPEN_MISMATCH',
        );
      }
      final full = await evidenceFile(recipient['fullFile']);
      final resolved = full.path;
      final received = await fingerprintMediaFile(full);
      if (!binding.source.plaintext.sameBytes(received)) {
        throw const MediaOracleFailure('RECEIVER_PLAINTEXT_MISMATCH');
      }
      final caption = item['caption'];
      if (caption is! String || recipient['caption'] != caption) {
        throw const MediaOracleFailure('RECORDED_CAPTION_MISMATCH');
      }
      final type = entry.value;
      if (type == 'image' || type == 'jpeg' || type == 'png') {
        if (!binding.mime.startsWith('image/') ||
            type == 'jpeg' && binding.mime != 'image/jpeg' ||
            type == 'png' && binding.mime != 'image/png') {
          throw const MediaOracleFailure('IMAGE_FORMAT_MISMATCH');
        }
        final imageBytes = await File(resolved).readAsBytes();
        var decoded = type == 'jpeg'
            ? image.decodeJpg(imageBytes)
            : type == 'png'
            ? image.decodePng(imageBytes)
            : image.decodeImage(imageBytes);
        if (decoded == null && type == 'image' && Platform.isMacOS) {
          // Existing evaluator fallback for a complete HEIC/HEIF export. This
          // observes a host decoder, never a recipient native viewer.
          final scratch = await Directory.systemTemp.createTemp(
            'media-control-decode-',
          );
          try {
            final converted = File('${scratch.path}/full.png');
            final conversion = await runRecordedMediaDecoder('sips', <String>[
              '-s',
              'format',
              'png',
              resolved,
              '--out',
              converted.path,
            ], timeout: const Duration(seconds: 30));
            if (conversion == 0 && await converted.exists()) {
              decoded = image.decodeImage(await converted.readAsBytes());
            }
          } finally {
            await scratch.delete(recursive: true);
          }
        }
        if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
          throw const MediaOracleFailure('HOST_FULL_IMAGE_DECODE_FAILED');
        }
      }
      if (type == 'video') {
        if (!binding.mime.startsWith('video/')) {
          throw const MediaOracleFailure('VIDEO_MIME_REQUIRED');
        }
        // Reject the known PNG/JPEG-in-an-mp4-path fixture shape before the
        // decoder can treat a still image as a one-frame video input.
        final header = await File(resolved)
            .openRead(0, 8)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        if (header.length >= 3 &&
                header[0] == 0xff &&
                header[1] == 0xd8 &&
                header[2] == 0xff ||
            header.length == 8 &&
                header[0] == 0x89 &&
                ascii.decode(header.sublist(1, 4)) == 'PNG') {
          throw const MediaOracleFailure('STILL_IMAGE_IS_NOT_VIDEO');
        }
        // Same bounded complete visual-stream host decode as the existing
        // gap evaluator. This is never device playback, audio or orientation.
        final decoded = await runRecordedMediaDecoder('ffmpeg', <String>[
          '-nostdin',
          '-v',
          'error',
          '-i',
          resolved,
          '-map',
          '0:v:0',
          '-f',
          'null',
          '-',
        ], timeout: const Duration(minutes: 2));
        if (decoded != 0) {
          throw const MediaOracleFailure('HOST_FULL_VIDEO_DECODE_FAILED');
        }
      }
      if (type == 'pdf') {
        if (binding.mime != 'application/pdf') {
          throw const MediaOracleFailure('PDF_MIME_REQUIRED');
        }
        final signature = await File(resolved)
            .openRead(0, 5)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        if (ascii.decode(signature, allowInvalid: true) != '%PDF-') {
          throw const MediaOracleFailure('PDF_SIGNATURE_REQUIRED');
        }
        // A signature plus complete byte equality is not a rendered PDF page.
      }
      if (!received.sameBytes(await fingerprintMediaFile(File(resolved)))) {
        throw const MediaOracleFailure('EXPORT_CHANGED_DURING_ASSERTION');
      }
    } on Object catch (error) {
      failures.add(
        '${entry.key}: ${error is MediaOracleFailure ? error.code : 'control unreadable or malformed'}',
      );
    }
  }
  return failures;
}
