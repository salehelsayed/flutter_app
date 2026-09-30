import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'production_android_journey.dart';
import 'production_journey_peer.dart';

bool productionProviderSendAccepted(
  Map<String, Object?> diagnostic,
  int exitCode,
) =>
    exitCode == 0 &&
    diagnostic['ok'] == true &&
    diagnostic['stage'] == 'fcm' &&
    diagnostic['operation'] == 'deliver' &&
    diagnostic['validateOnly'] == false;

bool productionProviderIngressObserved(String log, String probeDigest) => log
    .split('\n')
    .any(
      (line) =>
          line.contains('providerIngress=true') &&
          line.contains('probeSha256=$probeDigest') &&
          line.contains('package=com.mknoon.app'),
    );

Map<String, Object?>? productionProviderDiagnosticFromStreams(
  String stdout,
  String stderr,
) {
  for (final stream in [stdout, stderr]) {
    for (final line in stream.split('\n').reversed) {
      try {
        final decoded = jsonDecode(line.trim());
        if (decoded is Map &&
            decoded['schema'] == 'mknoon.fcm-provider-result.v1') {
          return Map<String, Object?>.from(decoded);
        }
      } on FormatException {
        // Build hooks may print before the provider's one-line receipt.
      } on TypeError {
        // Ignore unrelated JSON that cannot be a provider receipt.
      }
    }
  }
  return null;
}

String productionProviderFailureSummary(Map<String, Object?> diagnostic) {
  final stage =
      {'oauth', 'fcm', 'request_prepare'}.contains(diagnostic['stage'])
      ? diagnostic['stage']
      : 'unknown';
  final status = diagnostic['httpStatus'];
  final httpStatus = status is int && status >= 100 && status <= 599
      ? status.toString()
      : 'unknown';
  final reason = diagnostic['reason'];
  final safeReason =
      reason is String && RegExp(r'^[A-Z_]{2,32}$').hasMatch(reason)
      ? reason
      : 'UNKNOWN';
  return 'stage=$stage httpStatus=$httpStatus reason=$safeReason';
}

/// Requires both an accepted Firebase send and the matching callback in the
/// actual production Android receiver. Token and service credentials stay out
/// of the proof directory and all shareable receipts.
Future<Map<String, Object?>> proveProductionProviderDelivery({
  required ProductionAndroidJourney journey,
  required ProductionJourneyPeer receiver,
  Future<void> Function()? backgroundReceiver,
  String? token,
  String? caseId,
  Map<String, Object?>? data,
}) async {
  if (!journey.usesProviderReceiver ||
      receiver.invocation.role != 'bob' ||
      receiver.invocation.profileId != productionNotificationAndroidProfile ||
      receiver.packageName != productionNotificationAndroidPackage ||
      receiver.device != journey.emulator) {
    throw StateError(
      'provider probe requires the production emulator receiver',
    );
  }
  final credential =
      Platform.environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH'] ??
      Platform.environment['FIREBASE_SERVICE_ACCOUNT'];
  if (credential == null || !File(credential).existsSync()) {
    throw StateError('verified provider credential is unavailable');
  }
  final liveToken = token ?? await receiver.claimProviderToken();
  if (backgroundReceiver != null) await backgroundReceiver();
  final probeId =
      'wave2-${journey.runId}-${caseId ?? receiver.invocation.nonce}';
  final probeDigest = sha256.convert(utf8.encode(probeId)).toString();
  final temporary = await Directory.systemTemp.createTemp('wave2-provider-');
  final request = File('${temporary.path}/request.json');
  final started = Stopwatch()..start();
  try {
    await request.writeAsString(
      jsonEncode({
        'token': liveToken,
        'transportContract': {'caseId': probeId, 'expectedOutcome': 'display'},
        if (data != null) 'data': {...data, 'probe_id': probeId},
      }),
      flush: true,
    );
    final permission = await journey.runner.run('chmod', ['600', request.path]);
    if (permission.exitCode != 0) {
      throw StateError('private request setup failed');
    }
    final send = await journey.runner.run('node', [
      'scripts/send_fcm_provider_probe.js',
      '--request-file',
      request.path,
      '--service-account',
      credential,
      '--mode',
      'data-only',
      '--kind',
      'chat',
      '--probe-id',
      probeId,
    ]);
    final diagnostic = productionProviderDiagnosticFromStreams(
      '${send.stdout}',
      '${send.stderr}',
    );
    if (diagnostic == null) {
      throw StateError('provider send has no redacted diagnostic');
    }
    if (!productionProviderSendAccepted(diagnostic, send.exitCode)) {
      throw StateError(
        'provider send was not accepted: '
        '${productionProviderFailureSummary(diagnostic)}',
      );
    }
    var observed = false;
    while (started.elapsed < const Duration(seconds: 45)) {
      final log = await receiver.adb([
        'logcat',
        '-d',
        '-v',
        'raw',
        '-s',
        'MknoonJourneyFCM:I',
      ]);
      observed = productionProviderIngressObserved(
        '${log.stdout}',
        probeDigest,
      );
      if (observed) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!observed) throw StateError('provider callback was not observed');
    final receipt = <String, Object?>{
      'receiverProfile': receiver.invocation.profileId,
      'receiverPackage': receiver.packageName,
      'receiverRole': receiver.invocation.role,
      'probeSha256': probeDigest,
      'send': diagnostic,
      'nativeIngressObserved': true,
      'elapsedMs': started.elapsedMilliseconds,
    };
    await File(
      '${journey.output.path}/provider-delivery-${caseId ?? "probe"}.json',
    ).writeAsString(jsonEncode(receipt));
    return receipt;
  } finally {
    await temporary.delete(recursive: true);
  }
}
