import 'dart:convert';
import 'dart:io';

import '../../tool/sims/production_journey_gap_criteria.dart';
import '../support/media_content_oracle.dart';

export '../../tool/sims/production_journey_gap_criteria.dart'
    show journeyGapMap, journeyGapRows;

final class ContactTransferCaptureUnavailable implements Exception {}

/// Read-only binding of the existing saved-observation envelope. Hash equality
/// establishes file identity, not who captured it or whether a native action ran.
final class ContactTransferNativeEvidence {
  ContactTransferNativeEvidence._(this.receipt, this.files);
  final Map<String, Object?> receipt;
  final Map<String, File> files;
  Map<String, Object?> get observations =>
      journeyGapMap(receipt['observations']);

  static Future<ContactTransferNativeEvidence> load(
    List<String> arguments, {
    required String journeyId,
    required List<String> requiredKinds,
  }) async {
    String option(String name) {
      final index = arguments.indexOf(name);
      if (index < 0 || index + 1 >= arguments.length) {
        throw FormatException('missing $name');
      }
      return arguments[index + 1];
    }

    final expectedSource = option('--source');
    final expectedRun = option('--run-id');
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(expectedSource) ||
        expectedRun.isEmpty) {
      throw const FormatException(
        'independent full source and run ID required',
      );
    }
    final input = File(option('--receipt')).absolute;
    final root = await input.parent.resolveSymbolicLinks();
    final receipt = journeyGapMap(jsonDecode(await input.readAsString()));
    if (receipt['schema'] != 'mknoon.production-journey-gap.v1' ||
        receipt['journeyId'] != journeyId ||
        receipt['runId'] != expectedRun ||
        receipt['candidateSource'] != expectedSource) {
      throw const FormatException(
        'saved observations do not match the independent invocation',
      );
    }
    if ([
      'not_run',
      'blocked',
      'target_unavailable',
    ].contains(receipt['executionStatus'])) {
      throw ContactTransferCaptureUnavailable();
    }
    if (receipt['executionStatus'] != 'complete') {
      throw const FormatException(
        'saved-observation execution status is unsupported',
      );
    }
    final targets = journeyGapMap(receipt['targets']);
    final ids = <String>{};
    if (targets.isEmpty) {
      throw const FormatException('pinned target observations required');
    }
    for (final value in targets.values) {
      final target = journeyGapMap(value);
      final id = target['deviceId'];
      if (id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          !['android', 'ios'].contains(target['platform']) ||
          ![
            'usb_physical',
            'android_emulator',
            'ios_simulator',
          ].contains(target['kind']) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch('${target['artifactSha256']}')) {
        throw const FormatException(
          'distinct targets, actual target kind and exact artifacts required',
        );
      }
    }
    final entries = journeyGapRows(receipt['evidence']);
    final files = <String, File>{};
    for (final entry in entries) {
      final path = entry['path'];
      if (path is! String ||
          path.isEmpty ||
          path.startsWith('/') ||
          Uri.parse(path).hasScheme ||
          path.split('/').contains('..')) {
        throw const FormatException(
          'raw evidence must be a relative run-local file',
        );
      }
      final file = File.fromUri(input.parent.uri.resolve(path));
      final canonical = await file.resolveSymbolicLinks();
      if (!canonical.startsWith('$root/')) {
        throw const FormatException(
          'raw evidence resolves outside the run directory',
        );
      }
      final fingerprint = await fingerprintMediaFile(File(canonical));
      if (fingerprint.sha256Hex != entry['sha256']) {
        throw const FormatException('raw evidence digest mismatch');
      }
      files[path] = File(canonical);
    }
    for (final kind in requiredKinds) {
      if (!entries.any((entry) => entry['kind'] == kind)) {
        throw FormatException('missing actual $kind evidence');
      }
    }
    return ContactTransferNativeEvidence._(receipt, files);
  }

  File file(Object? path) {
    final file = files[path];
    if (file == null) {
      throw const FormatException('assertion references unhashed raw evidence');
    }
    return file;
  }

  Future<Map<String, Object?>> json(Object? path) async =>
      journeyGapMap(jsonDecode(await file(path).readAsString()));
}

/// No caller can convert recorded observations into native PASS. The future
/// fapp owner must provide the missing reviewed capture producer separately.
void writeContactTransferNativeResult({
  required String journeyId,
  required List<String> ids,
  required String captureGap,
  required List<String> prerequisites,
  required List<String> failures,
  required bool evaluated,
}) {
  stdout.writeln(
    jsonEncode({
      'journeyId': journeyId,
      'ids': ids,
      'status': failures.isEmpty ? 'NOT RUN' : 'FAIL',
      'reason': 'KNOWN GAP [${ids.join('/')}]: $captureGap',
      'recordedCriteria': !evaluated
          ? 'NOT RUN'
          : failures.isEmpty
          ? 'SATISFIED_CAPTURE_UNVERIFIED'
          : 'REJECTED',
      'recordedAssertionFailures': failures,
      'nativeExecutedByThisCommand': false,
      'captureProducerAvailable': false,
      'prerequisites': prerequisites,
    }),
  );
  exitCode = failures.isEmpty ? 78 : 1;
}
