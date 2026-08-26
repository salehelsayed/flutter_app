import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/ios_notification_payload_campaign.dart';

final class IosNotificationPayloadCampaignOptions {
  const IosNotificationPayloadCampaignOptions({
    required this.receiverDeviceId,
    required this.prebuiltApplicationPath,
    required this.stagingManifestPath,
    required this.xctestrunPath,
    required this.providerDriverPath,
    required this.providerRequestPath,
    required this.relayTarget,
    required this.relayKeyPath,
    required this.proofDirectory,
    required this.verbose,
    this.automationDriverPath =
        'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
  });

  final String? receiverDeviceId;
  final String? prebuiltApplicationPath;
  final String? stagingManifestPath;
  final String? xctestrunPath;
  final String? providerDriverPath;
  final String? providerRequestPath;
  final String? relayTarget;
  final String? relayKeyPath;
  final String proofDirectory;
  final bool verbose;
  final String automationDriverPath;
}

final class IosNotificationPayloadCampaignResult {
  const IosNotificationPayloadCampaignResult(this.processExitCode, this.json);

  final int processExitCode;
  final Map<String, Object?> json;
}

Future<IosNotificationPayloadCampaignResult> runIosNotificationPayloadCampaign(
  IosNotificationPayloadCampaignOptions options,
) async {
  try {
    return await _IosNotificationPayloadCampaign(options).run();
  } on _Blocked catch (error) {
    return _blocked(error.blocker, error.detail);
  } on _CampaignFailure catch (error) {
    return _failed(error.detail, assertionsAttempted: error.attempts);
  } on ProcessException catch (error) {
    return _blocked(
      'missingDriver',
      'The iOS payload automation command could not start: ${error.message}',
    );
  } on Object catch (error, stackTrace) {
    if (options.verbose) stderr.writeln(stackTrace);
    return _failed(
      'The iOS payload campaign stopped without a typed verdict: '
      '${error.runtimeType}.',
      assertionsAttempted: 0,
    );
  }
}

final class _IosNotificationPayloadCampaign {
  _IosNotificationPayloadCampaign(this.options);

  final IosNotificationPayloadCampaignOptions options;
  final Random _random = Random.secure();

  late final String receiverDeviceId;
  late final String peerDeviceId;
  late final Directory application;
  late final File stagingManifest;
  late final File xctestrun;
  late final File providerDriver;
  late final File providerRequest;
  late final File relayKey;
  late final File automationDriver;
  late final Directory proofDirectory;
  late final String relayTarget;
  late final String applicationSha256;
  late final String providerRequestSha256;

  Future<IosNotificationPayloadCampaignResult> run() async {
    final staging = await _preflight();
    proofDirectory.createSync(recursive: true);
    final fastRunId = _safeRunToken('ios-payload-fast');
    final fastNonce = _safeRunToken('nonce-fast');
    final recoveryRunId = _safeRunToken('ios-payload-recovery');
    final recoveryNonce = _safeRunToken('nonce-recovery');
    final retryRunId = _safeRunToken('ios-payload-retry');
    final retryNonce = _safeRunToken('nonce-retry');
    final captureDirectory = Directory(
      '${proofDirectory.path}${Platform.pathSeparator}'
      'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
    )..createSync(recursive: true);
    final captureMode = Process.runSync('chmod', <String>[
      '700',
      captureDirectory.path,
    ]);
    if (captureMode.exitCode != 0) {
      throw const _CampaignFailure(
        'The private iOS capture directory could not be made owner-only.',
        attempts: 0,
      );
    }
    final fastPhase = await _runAutomationPhase(
      phase: 'fast-path',
      runId: fastRunId,
      nonce: fastNonce,
      directory: Directory(
        '${captureDirectory.path}${Platform.pathSeparator}fast-path',
      ),
    );
    final automationReceipt = fastPhase.receipt;
    final validation = validateIosNotificationAutomationReceipt(
      automationReceipt,
      runId: fastRunId,
      nonce: fastNonce,
      receiverDeviceId: receiverDeviceId,
      peerDeviceId: peerDeviceId,
      preparedApplicationSha256: applicationSha256,
      providerRequestSha256: providerRequestSha256,
      payloadProducerSha256: staging['payloadProducerSha256']! as String,
      apnsPayloadSha256: automationReceipt['apnsPayloadSha256']! as String,
    );
    if (!validation.ok) {
      throw _CampaignFailure(
        'The physical iOS receipt was rejected: ${validation.detail}',
        attempts: 7,
      );
    }
    // The fast-path driver performs full provider/app/notification cleanup.
    // The second leg therefore starts from a fresh dedicated install while
    // reusing the same signed products and exact provider/producer stack.
    final recoveryPhase = await _runAutomationPhase(
      phase: 'recovery',
      runId: recoveryRunId,
      nonce: recoveryNonce,
      directory: Directory(
        '${captureDirectory.path}${Platform.pathSeparator}recovery',
      ),
    );
    final recoveryAutomationReceipt = recoveryPhase.receipt;
    final recoveryValidation = validateIosNotificationRecoveryAutomationReceipt(
      recoveryAutomationReceipt,
      runId: recoveryRunId,
      nonce: recoveryNonce,
      receiverDeviceId: receiverDeviceId,
      peerDeviceId: peerDeviceId,
      preparedApplicationSha256: applicationSha256,
      providerRequestSha256: providerRequestSha256,
      payloadProducerSha256: staging['payloadProducerSha256']! as String,
      apnsPayloadSha256:
          recoveryAutomationReceipt['apnsPayloadSha256']! as String,
    );
    if (!recoveryValidation.ok) {
      throw _CampaignFailure(
        'The physical iOS recovery receipt was rejected: '
        '${recoveryValidation.detail}',
        attempts:
            fastPhase.assertionsAttempted + recoveryPhase.assertionsAttempted,
      );
    }
    // Recovery cleanup removes the candidate and every private provider
    // intermediate. The retry leg therefore starts from a third fresh install
    // and cannot inherit the single-send inventory it is intended to fence.
    final retryPhase = await _runAutomationPhase(
      phase: 'retry',
      runId: retryRunId,
      nonce: retryNonce,
      directory: Directory(
        '${captureDirectory.path}${Platform.pathSeparator}retry',
      ),
    );
    final retryAutomationReceipt = retryPhase.receipt;
    final retryValidation = validateIosNotificationRetryAutomationReceipt(
      retryAutomationReceipt,
      runId: retryRunId,
      nonce: retryNonce,
      receiverDeviceId: receiverDeviceId,
      peerDeviceId: peerDeviceId,
      preparedApplicationSha256: applicationSha256,
      providerRequestSha256: providerRequestSha256,
      payloadProducerSha256: staging['payloadProducerSha256']! as String,
      apnsPayloadSha256: retryAutomationReceipt['apnsPayloadSha256']! as String,
    );
    final totalAssertions =
        fastPhase.assertionsAttempted +
        recoveryPhase.assertionsAttempted +
        retryPhase.assertionsAttempted;
    if (!retryValidation.ok) {
      throw _CampaignFailure(
        'The physical iOS retry receipt was rejected: '
        '${retryValidation.detail}',
        attempts: totalAssertions,
      );
    }
    final capturedAt = DateTime.now().toUtc().toIso8601String();
    final exactArtifact = buildIosNotificationArtifact(
      automationReceipt: automationReceipt,
      recoveryAutomationReceipt: recoveryAutomationReceipt,
      retryAutomationReceipt: retryAutomationReceipt,
      capturedAt: capturedAt,
    );
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: iosNotificationPayloadCapabilityId,
      validatorIds: const <String>[iosNotificationPayloadValidator],
      payload: <String, Object?>{
        ...exactArtifact,
        'buildProfile': iosNotificationPayloadBuildProfile,
        'stagingEnvironment': staging['environment'],
        'candidateAppRevision': staging['candidateAppRevision'],
        'candidateRelayRevision': staging['candidateRelayRevision'],
        'candidateRelaySha256': staging['candidateRelaySha256'],
        'automationReceiptSha256': sha256
            .convert(fastPhase.receiptFile.readAsBytesSync())
            .toString(),
        'recoveryAutomationReceiptSha256': sha256
            .convert(recoveryPhase.receiptFile.readAsBytesSync())
            .toString(),
        'retryAutomationReceiptSha256': sha256
            .convert(retryPhase.receiptFile.readAsBytesSync())
            .toString(),
      },
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[iosNotificationPayloadValidator],
    );
    if (!audit.isValid) {
      throw _CampaignFailure(
        'The durable iOS evidence audit failed: ${audit.detail}',
        attempts: totalAssertions,
      );
    }
    final durableArtifact = _readCapturedJson(
      File(evidence.path),
      'durable proof artifact',
    );
    final durableValidation = validateNotificationArtifact(durableArtifact);
    if (!durableValidation.ok) {
      throw _CampaignFailure(
        'The durable iOS proof failed semantic validation: '
        '${durableValidation.detail}',
        attempts: totalAssertions,
      );
    }
    return IosNotificationPayloadCampaignResult(0, <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': totalAssertions,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Physical iPhone APNs/NSE staging and an automated airplane-mode '
          'tap rendered the message with zero relay drain before visibility. '
          'A fresh second APNs leg then proved delivered badge=nil, absolute '
          'badge convergence, exact owned-card retirement, and unrelated-card '
          'survival. A third fresh leg fenced the first delivery before a '
          'private identical-payload retry, then proved one useful card and '
          'active-to-trusted-passive NSE handoffs across the complete window; '
          'all legs reused the central ios.device.production signed '
          'app/XCUITest bundle with zero child builds.',
      'artifactEvidence': evidence.toJson(),
    });
  }

  Future<_AutomationPhaseResult> _runAutomationPhase({
    required String phase,
    required String runId,
    required String nonce,
    required Directory directory,
  }) async {
    directory.createSync(recursive: true);
    final receiptFile = File(
      '${directory.path}${Platform.pathSeparator}automation_receipt.json',
    );
    final child = await Process.start(Platform.resolvedExecutable, <String>[
      'run',
      automationDriver.path,
      '--receiver',
      receiverDeviceId,
      '--peer-device',
      peerDeviceId,
      '--application-binary',
      application.path,
      '--xctestrun',
      xctestrun.path,
      '--provider-driver',
      providerDriver.path,
      '--provider-request',
      providerRequest.path,
      '--staging-manifest',
      stagingManifest.path,
      '--relay-target',
      relayTarget,
      '--relay-key',
      relayKey.path,
      '--run-id',
      runId,
      '--nonce',
      nonce,
      '--phase',
      phase,
      '--output',
      receiptFile.path,
      '--capture-directory',
      directory.path,
      if (options.verbose) '--verbose',
    ], includeParentEnvironment: true);
    final stdoutText = await child.stdout.transform(utf8.decoder).join();
    final stderrText = await child.stderr.transform(utf8.decoder).join();
    final childExit = await child.exitCode;
    if (options.verbose) {
      stdout.write(stdoutText);
      stderr.write(stderrText);
    }
    final result = _driverResult(stdoutText);
    if (childExit == 78) {
      throw _Blocked(
        result?['blocker'] as String? ?? 'environment',
        result?['detail'] as String? ??
            'The iOS $phase automation rig reported an unavailable prerequisite.',
      );
    }
    if (childExit != 0) {
      throw _CampaignFailure(
        result?['detail'] as String? ??
            _bounded(stderrText.isNotEmpty ? stderrText : stdoutText),
        attempts: result?['assertionsAttempted'] as int? ?? 1,
      );
    }
    if (!_regularFile(receiptFile)) {
      throw _CampaignFailure(
        'The iOS $phase automation driver exited zero without a receipt.',
        attempts: result?['assertionsAttempted'] as int? ?? 0,
      );
    }
    return _AutomationPhaseResult(
      receiptFile: receiptFile,
      receipt: _readCapturedJson(receiptFile, '$phase automation receipt'),
      assertionsAttempted: result?['assertionsAttempted'] as int? ?? 0,
    );
  }

  Future<Map<String, Object?>> _preflight() async {
    final preparedPath = options.prebuiltApplicationPath?.trim() ?? '';
    File? bundledXctestrun;
    final preparedType = FileSystemEntity.typeSync(
      preparedPath,
      followLinks: true,
    );
    if (preparedType == FileSystemEntityType.directory) {
      final bundle = Directory(preparedPath).absolute;
      final bundleManifest = File(
        '${bundle.path}${Platform.pathSeparator}bundle_manifest.json',
      );
      if (!_regularFile(bundleManifest)) {
        throw const _Blocked(
          'missingArtifact',
          'The central ios.device.production bundle has no attested member '
              'manifest.',
        );
      }
      final decoded = _readJson(bundleManifest, 'iOS build bundle manifest');
      if (decoded['schema'] != 'mknoon.sims.ios-device-production-bundle.v1' ||
          decoded['profileId'] != iosNotificationPayloadBuildProfile ||
          decoded['centralCompileCommands'] != 1 ||
          decoded['logicalBuildCount'] != 1 ||
          decoded['childBuildCount'] != 0) {
        throw const _Blocked(
          'missingArtifact',
          'The central ios.device.production companion bundle contract is '
              'invalid.',
        );
      }
      application = _bundleApplication(bundle, decoded['applicationApp']);
      bundledXctestrun = _bundleMember(
        bundle,
        decoded['xctestrun'],
        '.xctestrun',
      );
      final products = _bundleDirectory(bundle, decoded['testProducts']);
      if (!products.existsSync()) {
        throw const _Blocked(
          'missingArtifact',
          'The central ios.device.production bundle has no prebuilt UI test '
              'products.',
        );
      }
    } else {
      application = Directory(preparedPath).absolute;
    }
    if (preparedPath.isEmpty ||
        !_directory(application) ||
        !application.path.endsWith('.app')) {
      throw const _Blocked(
        'missingArtifact',
        'SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION must name the centrally attested '
            'signed-app/UI-rig bundle; child app builds are forbidden.',
      );
    }
    final selectedProfile = Platform.environment['SIMS_ARTIFACT_PROFILE_ID']
        ?.trim();
    if (selectedProfile != null &&
        selectedProfile.isNotEmpty &&
        selectedProfile != iosNotificationPayloadBuildProfile) {
      throw _Blocked(
        'missingArtifact',
        'Prepared profile $selectedProfile is not '
            '$iosNotificationPayloadBuildProfile.',
      );
    }
    applicationSha256 = sha256FileSystemEntity(application);

    final stagingPath = options.stagingManifestPath?.trim() ?? '';
    stagingManifest = File(stagingPath).absolute;
    if (stagingPath.isEmpty || !_regularFile(stagingManifest)) {
      throw const _Blocked(
        'credentials',
        'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST is required and must attest '
            'the staging relay, APNs credentials, and successful provider '
            'probe without embedding secrets.',
      );
    }
    final staging = _readJson(stagingManifest, 'staging manifest');
    if (staging['providerConfigured'] != true ||
        staging['providerCredentialsAvailable'] != true ||
        staging['providerProbeSucceeded'] != true) {
      throw const _Blocked(
        'credentials',
        'The staging manifest does not prove usable APNs provider '
            'credentials and a successful provider probe.',
      );
    }
    final stagingValidation = validateIosNotificationStagingManifest(staging);
    if (!stagingValidation.ok) {
      throw _Blocked('credentials', stagingValidation.detail);
    }
    peerDeviceId = staging['peerDeviceId']! as String;

    final requestPath = options.providerRequestPath?.trim() ?? '';
    providerRequest = File(requestPath).absolute;
    if (requestPath.isEmpty || !_regularFile(providerRequest)) {
      throw const _Blocked(
        'credentials',
        'SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST must name the private '
            'run-scoped relay/APNs request; no token or ciphertext is accepted '
            'on the command line.',
      );
    }
    final request = _readJson(providerRequest, 'provider request');
    final requestValidation = validateIosNotificationProviderRequest(request);
    if (!requestValidation.ok) {
      throw _Blocked('credentials', requestValidation.detail);
    }
    if (request['peerDeviceId'] != peerDeviceId) {
      throw const _Blocked(
        'credentials',
        'The private provider request is not bound to the staging peer device.',
      );
    }
    providerRequestSha256 = sha256
        .convert(providerRequest.readAsBytesSync())
        .toString();

    final providerPath = options.providerDriverPath?.trim() ?? '';
    providerDriver = File(providerPath).absolute;
    if (providerPath.isEmpty || !_executableFile(providerDriver)) {
      throw const _Blocked(
        'missingDriver',
        'SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER must be an executable '
            'staging adapter that seeds relay custody and submits the APNs '
            'message without exposing credentials.',
      );
    }
    final xctestrunPath = options.xctestrunPath?.trim() ?? '';
    xctestrun = bundledXctestrun ?? File(xctestrunPath).absolute;
    if ((bundledXctestrun == null && xctestrunPath.isEmpty) ||
        !_regularFile(xctestrun) ||
        !xctestrun.path.endsWith('.xctestrun')) {
      throw const _Blocked(
        'missingArtifact',
        'SIMS_IOS_NOTIFICATION_XCTESTRUN must name a prebuilt physical-device '
            'UI rig. The campaign uses test-without-building and never builds '
            'the app or rig as a child process.',
      );
    }
    automationDriver = File(options.automationDriverPath).absolute;
    if (!_regularFile(automationDriver)) {
      throw const _Blocked(
        'missingDriver',
        'The repo-owned iOS notification XCUITest driver is missing.',
      );
    }

    relayTarget = options.relayTarget?.trim() ?? '';
    relayKey = File(options.relayKeyPath?.trim() ?? '').absolute;
    if (relayTarget.isEmpty ||
        relayTarget.contains(RegExp(r'[\r\n]')) ||
        !_regularFile(relayKey)) {
      throw const _Blocked(
        'environment',
        'SIMS_NOTIFICATION_RELAY_TARGET and a readable '
            'SIMS_NOTIFICATION_RELAY_KEY are required for the staging custody '
            'and no-drain assertions.',
      );
    }

    receiverDeviceId = options.receiverDeviceId?.trim() ?? '';
    if (!_safeDeviceId(receiverDeviceId) || receiverDeviceId == peerDeviceId) {
      throw const _Blocked(
        'targetUnavailable',
        'One explicit physical iPhone ID and one distinct peer device ID are '
            'required.',
      );
    }
    if (staging['receiverDeviceId'] != receiverDeviceId ||
        request['receiverDeviceId'] != receiverDeviceId) {
      throw const _Blocked(
        'credentials',
        'The staging manifest and private provider request are not bound to '
            'the explicitly selected dedicated iPhone.',
      );
    }
    await _verifyPhysicalTarget();
    proofDirectory = Directory(options.proofDirectory).absolute;
    return staging;
  }

  Future<void> _verifyPhysicalTarget() async {
    final flutter = await Process.run('flutter', const <String>[
      'devices',
      '--machine',
    ]);
    if (flutter.exitCode != 0) {
      throw const _Blocked(
        'environment',
        'flutter devices --machine could not resolve the live target matrix.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode('${flutter.stdout}');
    } on FormatException {
      throw const _Blocked(
        'environment',
        'flutter devices --machine returned invalid JSON.',
      );
    }
    final live = decoded is List
        ? decoded.whereType<Map>().where(
            (device) =>
                device['id'] == receiverDeviceId &&
                '${device['targetPlatform']}'.contains('ios'),
          )
        : const Iterable<Map>.empty();
    if (live.isEmpty) {
      throw const _Blocked(
        'deviceLost',
        'The explicitly selected iPhone disappeared after Sims live-target '
            'resolution.',
      );
    }
    final trace = await Process.run('xcrun', const <String>[
      'xctrace',
      'list',
      'devices',
    ]);
    if (trace.exitCode != 0) {
      throw const _Blocked(
        'environment',
        'xctrace could not verify the physical iOS target.',
      );
    }
    final lines = '${trace.stdout}'
        .split('\n')
        .where((line) => line.contains(receiverDeviceId))
        .where((line) => !line.toLowerCase().contains('simulator'));
    if (lines.isEmpty) {
      throw const _Blocked(
        'deviceLost',
        'The selected iOS target is not a connected physical iPhone.',
      );
    }
  }

  String _safeRunToken(String prefix) {
    final random = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${base64Url.encode(random).replaceAll('=', '')}';
  }
}

final class _AutomationPhaseResult {
  const _AutomationPhaseResult({
    required this.receiptFile,
    required this.receipt,
    required this.assertionsAttempted,
  });

  final File receiptFile;
  final Map<String, Object?> receipt;
  final int assertionsAttempted;
}

Map<String, Object?> _readJson(File file, String label) {
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) throw const FormatException('root is not an object');
    return value.map<String, Object?>((key, item) => MapEntry('$key', item));
  } on Object catch (error) {
    throw _Blocked('environment', '$label is invalid JSON: $error');
  }
}

Map<String, Object?> _readCapturedJson(File file, String label) {
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) throw const FormatException('root is not an object');
    return value.map<String, Object?>((key, item) => MapEntry('$key', item));
  } on Object catch (error) {
    throw _CampaignFailure(
      'The physical iOS $label is invalid JSON: $error',
      attempts: 1,
    );
  }
}

Map<String, Object?>? _driverResult(String output) {
  const prefix = 'IOS_PAYLOAD_DRIVER_RESULT_JSON=';
  final lines = const LineSplitter()
      .convert(output)
      .where((line) => line.startsWith(prefix))
      .toList(growable: false);
  if (lines.length != 1) return null;
  try {
    final decoded = jsonDecode(lines.single.substring(prefix.length));
    if (decoded is! Map) return null;
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on FormatException {
    return null;
  }
}

IosNotificationPayloadCampaignResult _blocked(String blocker, String detail) =>
    IosNotificationPayloadCampaignResult(78, <String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 78,
      'detail': detail,
    });

IosNotificationPayloadCampaignResult _failed(
  String detail, {
  required int assertionsAttempted,
}) => IosNotificationPayloadCampaignResult(1, <String, Object?>{
  'status': 'FAIL',
  'assertionsAttempted': assertionsAttempted,
  'artifactPresent': false,
  'printOnly': false,
  'blocker': 'test',
  'exitCode': 1,
  'detail': detail,
});

final class _Blocked implements Exception {
  const _Blocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

final class _CampaignFailure implements Exception {
  const _CampaignFailure(this.detail, {required this.attempts});

  final String detail;
  final int attempts;
}

bool _regularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
        FileSystemEntityType.file &&
    file.lengthSync() > 0;

bool _directory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: true) ==
    FileSystemEntityType.directory;

bool _executableFile(File file) {
  if (!_regularFile(file)) return false;
  final result = Process.runSync('test', <String>['-x', file.path]);
  return result.exitCode == 0;
}

bool _safeDeviceId(String value) =>
    RegExp(r'^[A-Za-z0-9._:-]{4,160}$').hasMatch(value);

File _bundleMember(Directory bundle, Object? relative, String suffix) {
  if (relative is! String ||
      relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('..') ||
      !relative.endsWith(suffix)) {
    throw const _Blocked(
      'missingArtifact',
      'The central iOS bundle contains an unsafe member path.',
    );
  }
  final member = File(
    '${bundle.path}${Platform.pathSeparator}$relative',
  ).absolute;
  if (!_regularFile(member)) {
    throw _Blocked(
      'missingArtifact',
      'The central iOS bundle member is missing: $relative.',
    );
  }
  return member;
}

Directory _bundleDirectory(Directory bundle, Object? relative) {
  if (relative is! String ||
      relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('..')) {
    throw const _Blocked(
      'missingArtifact',
      'The central iOS bundle contains an unsafe directory path.',
    );
  }
  return Directory('${bundle.path}${Platform.pathSeparator}$relative').absolute;
}

Directory _bundleApplication(Directory bundle, Object? relative) {
  if (relative is! String || !relative.endsWith('.app')) {
    throw const _Blocked(
      'missingArtifact',
      'The central iOS bundle has no signed application member.',
    );
  }
  final application = _bundleDirectory(bundle, relative);
  if (!_directory(application)) {
    throw _Blocked(
      'missingArtifact',
      'The central iOS application member is missing: $relative.',
    );
  }
  return application;
}

String _bounded(String value) {
  final trimmed = value.trim();
  return trimmed.length <= 1000 ? trimmed : '${trimmed.substring(0, 1000)}…';
}
