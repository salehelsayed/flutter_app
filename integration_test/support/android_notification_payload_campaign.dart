import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';

const String androidNotificationCapabilityId =
    'notifications.android_payload_campaign';
const String androidNotificationBuildProfileId = 'android.production_fcm';

/// Content-safe fingerprint of the package's durable notification-channel
/// configuration. Per-channel last-post timestamps are intentionally removed:
/// posting and dismissing a campaign card advances that counter without
/// changing user-visible channel policy.
String androidNotificationChannelStateSha256(
  String dumpsys, {
  required String packageName,
}) {
  final lines = dumpsys.split('\n');
  final packageHeader = RegExp(
    r'^\s+AppSettings:\s+' + RegExp.escape(packageName) + r'\s+\(',
  );
  final nextPackageHeader = RegExp(r'^\s+AppSettings:\s+');
  String? header;
  final stableChildren = <String>[];
  var inPackage = false;
  for (final raw in lines) {
    if (!inPackage) {
      if (!packageHeader.hasMatch(raw)) continue;
      inPackage = true;
      header = raw.trim().replaceFirst(RegExp(r'\s+\(\d+\)'), ' (<uid>)');
      continue;
    }
    if (nextPackageHeader.hasMatch(raw)) break;
    final line = raw.trim();
    if (line.startsWith('Delegate:') ||
        line.startsWith('NotificationChannel{') ||
        line.startsWith('NotificationChannelGroup{')) {
      stableChildren.add(
        line.replaceAll(
          RegExp(r'mLastNotificationUpdateTimeMs=-?\d+'),
          'mLastNotificationUpdateTimeMs=<volatile>',
        ),
      );
    }
  }
  stableChildren.sort();
  final stable = <String>[?header, ...stableChildren];
  return sha256.convert(utf8.encode(jsonEncode(stable))).toString();
}

final class AndroidStagedEnvelopeObservation {
  const AndroidStagedEnvelopeObservation({
    required this.messageId,
    required this.ciphertextSha256,
    required this.nonceSha256,
    required this.receivedAtMs,
  });

  final String messageId;
  final String ciphertextSha256;
  final String nonceSha256;
  final int receivedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'messageIdPrefix': safeNotificationIdPrefix(messageId),
    'ciphertextSha256': ciphertextSha256,
    'nonceSha256': nonceSha256,
    'receivedAtMs': receivedAtMs,
  };
}

/// Validates the exact app-private file written by the production Android FCM
/// background handler. Raw encrypted fields are reduced to hashes immediately.
AndroidStagedEnvelopeObservation parseAndroidStagedEnvelopeObservation(
  String encoded, {
  required String expectedMessageId,
  required String expectedSenderPeerId,
  required DateTime notBefore,
}) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('staged envelope root must be an object');
  }
  final value = decoded.map<String, Object?>(
    (key, item) => MapEntry('$key', item),
  );
  final kind = value['kind'];
  final kem = value['kem'];
  final ciphertext = value['ciphertext'];
  final nonce = value['nonce'];
  final senderPeerId = value['senderPeerId'];
  final messageId = value['messageId'];
  final receivedAtMs = value['receivedAtMs'];
  if (kind != 'chat' ||
      kem is! String ||
      kem.isEmpty ||
      ciphertext is! String ||
      ciphertext.isEmpty ||
      nonce is! String ||
      nonce.isEmpty ||
      senderPeerId != expectedSenderPeerId ||
      messageId != expectedMessageId ||
      receivedAtMs is! num ||
      receivedAtMs.toInt() < notBefore.millisecondsSinceEpoch) {
    throw const FormatException(
      'staged envelope does not match the real run-bound ciphertext tuple',
    );
  }
  return AndroidStagedEnvelopeObservation(
    messageId: messageId as String,
    ciphertextSha256: sha256.convert(utf8.encode(ciphertext)).toString(),
    nonceSha256: sha256.convert(utf8.encode(nonce)).toString(),
    receivedAtMs: receivedAtMs.toInt(),
  );
}

bool relayJournalContainsAndroidProviderSend(
  String journal, {
  required String recipientPeerId,
}) {
  final prefix = recipientPeerId.length <= 20
      ? recipientPeerId
      : recipientPeerId.substring(0, 20);
  return RegExp(
    r'\[PUSH\] Notification sent to\s+' + RegExp.escape(prefix) + r'\b',
  ).hasMatch(journal);
}

bool notificationWindowContainsRelayDrain(String logcat) =>
    logcat.contains('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS');

String safeNotificationIdPrefix(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

enum AndroidNotificationActionResultDisposition {
  accepted,
  bindingMismatch,
  boundFailure,
  invalidCompletion,
}

/// Classifies an installed-app action receipt without trusting any values from
/// that receipt for diagnostics.
///
/// Binding is checked before failure state so a stale or forged receipt cannot
/// be reported as a failure from the staged request.
AndroidNotificationActionResultDisposition
classifyAndroidNotificationActionResult({
  required Map<String, Object?> result,
  required Map<String, Object?> config,
  required String expectedStatus,
}) {
  final bindingMatches =
      result['schema'] == androidNotificationPayloadE2EResultSchema &&
      result['transport_action'] == config['transport_action'] &&
      result['scenario'] == androidNotificationPayloadE2EScenario &&
      result['stepId'] == config['stepId'] &&
      result['runId'] == config['runId'] &&
      result['nonce'] == config['nonce'];
  if (!bindingMatches) {
    return AndroidNotificationActionResultDisposition.bindingMismatch;
  }
  if (result['status'] == 'failed' && result['success'] == false) {
    return AndroidNotificationActionResultDisposition.boundFailure;
  }
  if (result['status'] != expectedStatus || result['success'] != true) {
    return AndroidNotificationActionResultDisposition.invalidCompletion;
  }
  return AndroidNotificationActionResultDisposition.accepted;
}

const Set<String> _safeAndroidNotificationActionErrorTypes = <String>{
  'FileSystemException',
  'FirebaseException',
  'FormatException',
  'PlatformException',
  'SocketException',
  'StateError',
  'TimeoutException',
};

/// Returns only an explicitly allowlisted error class from a failure receipt.
/// Raw exception messages and arbitrary receipt content are never returned.
String safeAndroidNotificationActionErrorType(Object? value) =>
    value is String && _safeAndroidNotificationActionErrorTypes.contains(value)
    ? value
    : 'unavailable';

Map<String, Object?> androidNotificationScenarioArtifact({
  required String testCase,
  required String scenario,
  required List<String> devices,
  required Iterable<String> passedChecks,
  required Map<String, Object?> evidence,
  required DateTime capturedAt,
}) => <String, Object?>{
  'testCase': testCase,
  'scenario': scenario,
  'status': 'passed',
  'platform': 'android',
  'capturedAt': capturedAt.toUtc().toIso8601String(),
  'devices': List<String>.unmodifiable(devices),
  'checks': <String, bool>{for (final check in passedChecks) check: true},
  'evidence': evidence,
};
