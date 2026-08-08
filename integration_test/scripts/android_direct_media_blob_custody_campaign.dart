import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_direct_media_blob_custody_campaign_contract.dart';
import '../support/android_direct_media_blob_custody_evidence.dart';
import 'android_direct_media_blob_custody_device_action.dart';

export '../support/android_direct_media_blob_custody_campaign_contract.dart';

const int androidDirectMediaBlobCustodyAssertionCount = 4;
const String _fixtureIdentityEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256';
const String _fixtureProbeEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL';

final class AndroidDirectMediaBlobCustodyCampaignResult {
  const AndroidDirectMediaBlobCustodyCampaignResult._({
    required this.processExitCode,
    required this.json,
  });

  factory AndroidDirectMediaBlobCustodyCampaignResult.pass(
    SimsArtifactEvidence evidence,
  ) => AndroidDirectMediaBlobCustodyCampaignResult._(
    processExitCode: 0,
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': androidDirectMediaBlobCustodyAssertionCount,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'The physical-Android sender and Android-emulator receiver proved '
          'restart-safe direct-media custody against the disposable relay.',
      'artifactEvidence': evidence.toJson(),
    },
  );

  factory AndroidDirectMediaBlobCustodyCampaignResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidDirectMediaBlobCustodyCampaignResult._(
    processExitCode: 78,
    json: <String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': 0,
      'artifactPresent': artifactPresent,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 78,
      'detail': detail,
    },
  );

  factory AndroidDirectMediaBlobCustodyCampaignResult.fail({
    required String blocker,
    required String detail,
    required bool artifactPresent,
    int assertionsAttempted = 0,
  }) => AndroidDirectMediaBlobCustodyCampaignResult._(
    processExitCode: 1,
    json: <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': assertionsAttempted,
      'artifactPresent': artifactPresent,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 1,
      'detail': detail,
    },
  );

  final int processExitCode;
  final Map<String, Object?> json;
}

/// Validates the centrally prepared APK and fixture binding, then delegates
/// only the mobile choreography to [deviceDriver].
///
/// The default driver is the concrete ADB/app-action campaign. Tests may inject
/// a driver, but every driver must return the exact hash-only evidence schema;
/// the campaign persists it only after independent validation.
Future<AndroidDirectMediaBlobCustodyCampaignResult>
runAndroidDirectMediaBlobCustodyCampaign({
  required List<String> devices,
  required String? artifactPath,
  AndroidDirectMediaBlobCustodyDeviceDriver? deviceDriver,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  if (artifactPath == null ||
      artifactPath.trim().isEmpty ||
      !FileSystemEntity.isFileSync(artifactPath)) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable centrally prepared '
          '$androidDirectMediaBlobCustodyBuildProfileId APK is required.',
      artifactPresent: false,
    );
  }
  final configuredProfile = env['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (configuredProfile != androidDirectMediaBlobCustodyBuildProfileId) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'Direct-media custody requires '
          '$androidDirectMediaBlobCustodyBuildProfileId; the executor supplied '
          '${configuredProfile == null || configuredProfile.isEmpty ? '(none)' : configuredProfile}.',
      artifactPresent: true,
    );
  }
  if (devices.length != 2 ||
      devices.first.trim().isEmpty ||
      devices.last.trim().isEmpty ||
      devices.first == devices.last) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail:
          'Direct-media custody requires exactly two distinct targets ordered '
          'as one USB physical Android and one Android emulator.',
      artifactPresent: true,
    );
  }

  final fixtureIdentitySha256 = env[_fixtureIdentityEnvironment]?.trim();
  final relayMultiaddr = env['MKNOON_RELAY_ADDRESSES']?.trim();
  final fixtureProbeUrl = env[_fixtureProbeEnvironment]?.trim();
  if (!_isLowercaseSha256(fixtureIdentitySha256) ||
      !_isSingleFixtureMultiaddr(relayMultiaddr) ||
      !_isFixtureProbeUrl(fixtureProbeUrl, relayMultiaddr)) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: 'environment',
      detail:
          'The disposable relay must provide one attested reachable multiaddr '
          'and a hash-only fixture identity before device mutation.',
      artifactPresent: true,
    );
  }
  final artifact = File(artifactPath).absolute;
  late final String artifactSha256;
  try {
    artifactSha256 = sha256.convert(await artifact.readAsBytes()).toString();
  } on FileSystemException catch (error) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The prepared APK could not be read: ${error.message}',
      artifactPresent: false,
    );
  }

  try {
    final runtimeEvidence =
        await (deviceDriver ?? runAndroidDirectMediaBlobCustodyAdbDeviceAction)(
          AndroidDirectMediaBlobCustodyCampaignContext(
            physicalDeviceId: devices.first,
            emulatorDeviceId: devices.last,
            artifact: artifact,
            artifactSha256: artifactSha256,
            relayMultiaddr: relayMultiaddr!,
            fixtureProbeUrl: fixtureProbeUrl!,
            fixtureIdentitySha256: fixtureIdentitySha256!,
          ),
        );
    if (runtimeEvidence['fixtureIdentitySha256'] != fixtureIdentitySha256) {
      throw const FormatException(
        'device evidence is not bound to the running disposable fixture',
      );
    }
    final validation = validateAndroidDirectMediaBlobCustodyEvidence(
      runtimeEvidence,
    );
    if (!validation.ok) throw FormatException(validation.detail);

    final durable = writeSimsArtifactEvidenceSync(
      directory: _proofDirectory(env),
      capabilityId: androidDirectMediaBlobCustodyScenarioId,
      validatorIds: const <String>[
        androidDirectMediaBlobCustodyArtifactValidatorId,
      ],
      payload: androidDirectMediaBlobCustodyDurablePayload(runtimeEvidence),
    );
    final audit = auditSimsArtifactEvidence(
      evidence: durable,
      expectedValidatorIds: const <String>[
        androidDirectMediaBlobCustodyArtifactValidatorId,
      ],
    );
    if (!audit.isValid) throw FormatException(audit.detail);
    final decoded = jsonDecode(File(durable.path).readAsStringSync());
    if (decoded is! Map ||
        !validateAndroidDirectMediaBlobCustodyDurableArtifact(
          decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
        ).ok) {
      throw const FormatException(
        'durable direct-media custody evidence failed validation',
      );
    }
    return AndroidDirectMediaBlobCustodyCampaignResult.pass(durable);
  } on AndroidDirectMediaBlobCustodyCampaignBlocked catch (blocked) {
    return AndroidDirectMediaBlobCustodyCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on FormatException catch (error) {
    return AndroidDirectMediaBlobCustodyCampaignResult.fail(
      blocker: 'harness',
      detail: error.message,
      artifactPresent: false,
      assertionsAttempted: androidDirectMediaBlobCustodyAssertionCount,
    );
  } on Object catch (error) {
    return AndroidDirectMediaBlobCustodyCampaignResult.fail(
      blocker: 'test',
      detail: 'Direct-media custody device action failed: $error',
      artifactPresent: false,
      assertionsAttempted: androidDirectMediaBlobCustodyAssertionCount,
    );
  }
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  return Directory(
    configured == null || configured.isEmpty
        ? 'build/sims/proofs/$androidDirectMediaBlobCustodyScenarioId'
        : configured,
  ).absolute;
}

bool _isLowercaseSha256(String? value) =>
    value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSingleFixtureMultiaddr(String? value) {
  if (value == null || value.isEmpty || value.contains(',')) return false;
  return RegExp(
    r'^/ip4/[^/]+/tcp/[1-9][0-9]*/p2p/[A-Za-z0-9]+$',
  ).hasMatch(value);
}

bool _isFixtureProbeUrl(String? value, String? relayMultiaddr) {
  if (value == null || relayMultiaddr == null) return false;
  final relayHost = RegExp(
    r'^/ip4/([^/]+)/',
  ).firstMatch(relayMultiaddr)?.group(1);
  final uri = Uri.tryParse(value);
  return relayHost != null &&
      uri != null &&
      uri.scheme == 'http' &&
      uri.host == relayHost &&
      uri.port > 0 &&
      RegExp(r'^/[0-9a-f]{64}$').hasMatch(uri.path) &&
      !uri.hasQuery &&
      !uri.hasFragment;
}
