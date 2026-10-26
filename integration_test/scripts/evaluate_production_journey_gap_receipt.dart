import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:image/image.dart' as image;

import '../../tool/sims/production_journey_gap_criteria.dart';
import '../support/media_content_oracle.dart';

Future<Map<String, int>> _decodeFullExport(File file, String type) async {
  if (type == 'video') {
    final result = await Process.run('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-i',
      file.path,
      '-map',
      '0:v:0',
      '-f',
      'null',
      '-',
    ]).timeout(const Duration(minutes: 2));
    if (result.exitCode != 0) {
      throw const MediaOracleFailure('FULL_VIDEO_DECODE_FAILED');
    }
    return {};
  }
  var decoded = image.decodeImage(await file.readAsBytes());
  if (decoded == null && Platform.isMacOS) {
    // The native camera may produce HEIC. Use the existing macOS image decoder
    // for that export, then fully decode its pixels with the existing package.
    final directory = await Directory.systemTemp.createTemp(
      'journey-gap-decode-',
    );
    try {
      final converted = File('${directory.path}/full.png');
      final result = await Process.run('sips', [
        '-s',
        'format',
        'png',
        file.path,
        '--out',
        converted.path,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0 && await converted.exists()) {
        decoded = image.decodeImage(await converted.readAsBytes());
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw const MediaOracleFailure('FULL_IMAGE_DECODE_FAILED');
  }
  return {'width': decoded.width, 'height': decoded.height};
}

/// Read-only host evaluation of the MCP owner's saved observations. Never
/// installs an app, operates a target, opens media natively or changes a relay.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionJourneyGapIds.join('\n'));
    return;
  }
  String? option(String name) {
    final index = arguments.indexOf(name);
    return index >= 0 && index + 1 < arguments.length
        ? arguments[index + 1]
        : null;
  }

  final template = option('--template');
  if (template != null && productionJourneyGapIds.contains(template)) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 'mknoon.production-journey-gap.v1',
        'journeyId': template,
        'runId': '',
        'candidateSource': '',
        'executionStatus': 'not_run',
        'targets': <String, Object?>{},
        'evidence': <Object?>[],
        'observations': <String, Object?>{},
      }),
    );
    return;
  }
  final input = option('--receipt');
  final output = option('--output');
  final expectedSource = option('--source');
  if (input == null ||
      output == null ||
      expectedSource == null ||
      !RegExp(r'^[a-f0-9]{40}$').hasMatch(expectedSource)) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'evaluate_production_journey_gap_receipt.dart '
      '--source <full-candidate-revision> --receipt <case.json> --output <verdict.json>\n'
      'Or: --template <journey> | --list-scenarios',
    );
    exitCode = 64;
    return;
  }
  var status = 'FAIL';
  var code = 1;
  var journey = '';
  var run = '';
  final failures = <String>[];
  final mediaFiles = <Map<String, Object?>>[];
  try {
    final receiptFile = File(input).absolute;
    final receipt = journeyGapMap(jsonDecode(await receiptFile.readAsString()));
    journey = '${receipt['journeyId'] ?? ''}';
    run = '${receipt['runId'] ?? ''}';
    if (!productionJourneyGapIds.contains(journey)) {
      throw const FormatException('unsupported journey');
    }
    File localFile(Object? value) {
      if (value is! String || value.isEmpty || value.startsWith('/')) {
        throw const FormatException('evidence needs a relative local path');
      }
      final file = File.fromUri(receiptFile.parent.uri.resolve(value));
      if (!file.absolute.path.startsWith('${receiptFile.parent.path}/')) {
        throw const FormatException('evidence must stay in the run directory');
      }
      return file;
    }

    Future<void> checkEvidence(String kind) async {
      final evidence = journeyGapRows(receipt['evidence']);
      if (!evidence.any((e) => e['kind'] == kind)) {
        failures.add('actual $kind evidence is required');
      }
      for (final entry in evidence) {
        final fingerprint = await fingerprintMediaFile(
          localFile(entry['path']),
        );
        if (fingerprint.sha256Hex != entry['sha256']) {
          failures.add('raw evidence digest mismatch');
        }
      }
    }

    if (receipt['executionStatus'] == 'not_run') {
      status = 'NOT RUN';
      code = 3;
    } else if (receipt['executionStatus'] == 'blocked') {
      status = 'BLOCKED';
      code = 78;
      failures.add('${receipt['reason'] ?? 'missing execution prerequisite'}');
    } else if (receipt['executionStatus'] == 'target_unavailable') {
      await checkEvidence('device-discovery');
      if (receipt['reason'] != 'target_unavailable_by_project_policy' ||
          receipt['candidateSource'] != expectedSource ||
          run.trim().isEmpty ||
          receipt['schema'] != 'mknoon.production-journey-gap.v1') {
        failures.add('exact unavailable-target reason and candidate required');
      }
      if (failures.isEmpty) {
        status = 'N/A_TARGET_UNAVAILABLE';
        code = 0;
      }
    } else {
      if (receipt['candidateSource'] != expectedSource) {
        failures.add('candidate source mismatch');
      }
      failures.addAll(validateProductionJourneyGapReceipt(receipt));
      await checkEvidence('mcp-transcript');
      final observations = journeyGapMap(receipt['observations']);
      final media = journey == 'MEDIA-018'
          ? journeyGapRows(observations['cuts'])
          : journeyGapRows(observations['media']);
      for (final item in media) {
        SentMediaBinding? binding;
        // The ordinary production camera UI may not export the existing
        // encryption-input receipt. Keep that stronger byte comparison
        // explicitly NOT RUN; the required MCP full-viewer/content oracle and
        // actual full-file export still apply. Never label raw camera bytes as
        // the processed encryption input to manufacture this optional proof.
        if (item['senderReceiptFile'] != null) {
          final sender = journeyGapMap(
            jsonDecode(
              await localFile(item['senderReceiptFile']).readAsString(),
            ),
          );
          binding = SentMediaBinding.fromSenderReceipt(
            receipt: sender,
            expectedReceiptSha256: '${item['senderReceiptSha256']}',
            expectedIdentity: MediaWireIdentity(
              runId: run,
              owner: MediaOwnerLane.values.byName('${item['owner']}'),
              messageId: '${item['messageId']}',
              attachmentId: '${item['attachmentId']}',
            ),
          );
          if (!['android', 'ios'].contains(binding.source.runtimePlatform)) {
            failures.add('actual native processed-send source is required');
          }
        }
        for (final recipient in journeyGapRows(item['recipients'])) {
          final full = await fingerprintMediaFile(
            localFile(recipient['fullFile']),
          );
          final decoded = await _decodeFullExport(
            localFile(recipient['fullFile']),
            '${item['mediaType'] ?? 'image'}',
          );
          final native = journeyGapMap(recipient['nativeOpen']);
          if (decoded.isNotEmpty &&
              !((decoded['width'] == native['decodedWidth'] &&
                      decoded['height'] == native['decodedHeight']) ||
                  (decoded['width'] == native['decodedHeight'] &&
                      decoded['height'] == native['decodedWidth']))) {
            failures.add(
              'full export dimensions do not match the recorded native frame',
            );
          }
          final equal = binding?.source.plaintext.sameBytes(full);
          if (equal == false) {
            failures.add(
              'received full file differs from the processed send input',
            );
          }
          mediaFiles.add({
            'messageId': item['messageId'],
            'role': recipient['role'],
            'fullFile': full.toJson(),
            'hostFullDecode': 'PASS',
            'processedSendByteEquality': equal == null
                ? 'NOT RUN'
                : equal
                ? 'PASS'
                : 'FAIL',
          });
        }
      }
      if (failures.isEmpty) {
        status = 'PASS_RECORDED';
        code = 0;
      }
    }
  } on Object catch (error) {
    // Do not dump local payloads, QR data, file contents or native credentials.
    failures.add(
      error is MediaOracleFailure
          ? error.code
          : 'receipt/evidence unreadable or malformed',
    );
  }
  final verdict = <String, Object?>{
    'schema': 'mknoon.production-journey-gap.verdict.v1',
    'journeyId': journey,
    'runId': run,
    'status': status,
    'scope': 'host evaluation of supplied MCP/native observations and files',
    'nativeExecutedByThisCommand': false,
    'mediaFiles': mediaFiles,
    'failures': failures,
  };
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(verdict)}\n',
  );
  stdout.writeln(jsonEncode(verdict));
  exitCode = code;
}
