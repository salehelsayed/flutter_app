import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';

import '../../tool/sims/artifact_evidence.dart';
import 'group_media_ios_background_recovery_evidence.dart';
import 'group_media_prepared_artifact_custody.dart';
import 'group_media_reliability_criteria.dart';

const String groupMediaReliabilityAndroidArtifactEnvironment =
    groupMediaAndroidDisposableArtifactEnvironment;
const String groupMediaReliabilityIosArtifactEnvironment =
    'SIMS_ARTIFACT_IOS_DEVICE_GROUP_MEDIA_269';

final RegExp _safeTargetPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$',
);
final RegExp _androidEmulatorPattern = RegExp(r'^emulator-[1-9][0-9]*$');
final RegExp _iosPhysicalPattern = RegExp(r'^[A-Fa-f0-9-]{24,64}$');
final RegExp _safeRunIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
final RegExp _safeFailureCodePattern = RegExp(r'^[a-z0-9_]{1,96}$');

final class GroupMediaReliabilityRunnerArguments {
  const GroupMediaReliabilityRunnerArguments({
    required this.listScenarios,
    required this.scenario,
    required this.deviceIds,
    required this.runId,
  });

  final bool listScenarios;
  final String? scenario;
  final List<String> deviceIds;
  final String? runId;

  static GroupMediaReliabilityRunnerArguments parse(List<String> arguments) {
    if (arguments.length == 1 && arguments.single == '--list-scenarios') {
      return const GroupMediaReliabilityRunnerArguments(
        listScenarios: true,
        scenario: null,
        deviceIds: <String>[],
        runId: null,
      );
    }
    String? scenario;
    String? devices;
    String? runId;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String takeValue(String option) {
        if (index + 1 >= arguments.length) {
          throw FormatException('$option requires one value');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--scenario':
          if (scenario != null) {
            throw const FormatException('--scenario may appear only once');
          }
          scenario = takeValue(argument).trim();
        case '-d':
        case '--devices':
          if (devices != null) {
            throw const FormatException('-d/--devices may appear only once');
          }
          devices = takeValue(argument).trim();
        case '--run-id':
          if (runId != null) {
            throw const FormatException('--run-id may appear only once');
          }
          runId = takeValue(argument).trim();
        default:
          throw FormatException(
            'Unknown group-media runner argument: $argument',
          );
      }
    }

    if (!groupMediaReliabilityScenarioIds.contains(scenario)) {
      throw FormatException(
        'Unknown or missing group-media scenario: $scenario',
      );
    }
    if (runId != null && !_safeRunIdPattern.hasMatch(runId)) {
      throw const FormatException('--run-id must be a safe identifier');
    }
    final deviceIds = devices == null
        ? const <String>[]
        : devices.split(',').map((value) => value.trim()).toList();
    if (deviceIds.isNotEmpty) {
      _validateDevices(scenario!, deviceIds);
    }
    return GroupMediaReliabilityRunnerArguments(
      listScenarios: false,
      scenario: scenario,
      deviceIds: List<String>.unmodifiable(deviceIds),
      runId: runId,
    );
  }
}

final class GroupMediaReliabilityRoleBinding {
  const GroupMediaReliabilityRoleBinding({
    required this.role,
    required this.deviceId,
    required this.identityNamespace,
  });

  final String role;
  final String deviceId;
  final String identityNamespace;
}

final class GroupMediaReliabilityPreparedArtifact {
  const GroupMediaReliabilityPreparedArtifact({
    required this.path,
    required this.profile,
    required this.sha256Digest,
  });

  final String path;
  final String profile;
  final String sha256Digest;
}

final class GroupMediaReliabilityRunContext {
  const GroupMediaReliabilityRunContext({
    required this.scenario,
    required this.runId,
    required this.preparedArtifact,
    required this.roles,
    required this.proofDirectory,
    required this.buildGuardLog,
    this.androidCompanionArtifact,
    this.authorityMode = groupMediaDistinctAuthorityMode,
  });

  final String scenario;
  final String runId;
  final GroupMediaReliabilityPreparedArtifact preparedArtifact;
  final Map<String, GroupMediaReliabilityRoleBinding> roles;
  final Directory proofDirectory;
  final File? buildGuardLog;
  final GroupMediaReliabilityPreparedArtifact? androidCompanionArtifact;
  final String authorityMode;

  bool get childBuildsAllowed => false;
}

typedef GroupMediaReliabilityScenarioExecutor =
    Future<Map<String, Object?>> Function(
      GroupMediaReliabilityRunContext context,
    );

final class GroupMediaReliabilityRunnerResult {
  const GroupMediaReliabilityRunnerResult({
    required this.json,
    required this.exitCode,
  });

  final Map<String, Object?> json;
  final int exitCode;

  String get sentinel => 'SIMS_RESULT_JSON=${jsonEncode(json)}';

  factory GroupMediaReliabilityRunnerResult.blocked(
    String blocker,
    String detail,
  ) => GroupMediaReliabilityRunnerResult(
    json: <String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 78,
      'detail': detail,
    },
    exitCode: 78,
  );

  factory GroupMediaReliabilityRunnerResult.failed(String detail) =>
      GroupMediaReliabilityRunnerResult(
        json: <String, Object?>{
          'status': 'FAIL',
          'assertionsAttempted': 1,
          'artifactPresent': false,
          'printOnly': false,
          'blocker': 'test',
          'exitCode': 1,
          'detail': detail,
        },
        exitCode: 1,
      );

  factory GroupMediaReliabilityRunnerResult.passed(
    SimsArtifactEvidence evidence,
  ) => GroupMediaReliabilityRunnerResult(
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': 1,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail': 'Group media reliability artifact passed strict v1 validation.',
      'artifactEvidence': evidence.toJson(),
    },
    exitCode: 0,
  );
}

final class GroupMediaReliabilityBlocked implements Exception {
  const GroupMediaReliabilityBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;

  @override
  String toString() => detail;
}

/// A stable, redacted scenario failure that is safe to preserve in Sims output.
final class GroupMediaReliabilityScenarioFailure implements Exception {
  factory GroupMediaReliabilityScenarioFailure(String code) {
    if (!_safeFailureCodePattern.hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'must be a safe failure code');
    }
    return GroupMediaReliabilityScenarioFailure._(code);
  }

  const GroupMediaReliabilityScenarioFailure._(this.code);

  final String code;

  @override
  String toString() => code;
}

Future<GroupMediaReliabilityRunnerResult> runGroupMediaReliabilityRunner({
  required List<String> arguments,
  required Map<String, String> environment,
  required GroupMediaReliabilityScenarioExecutor executeScenario,
}) async {
  var scenarioExecutionStarted = false;
  try {
    final parsed = GroupMediaReliabilityRunnerArguments.parse(arguments);
    if (parsed.listScenarios) {
      throw const FormatException(
        '--list-scenarios is metadata mode and must not execute a proof',
      );
    }
    final context = _buildContext(parsed, environment);
    _requireEmptyBuildGuard(context.buildGuardLog);
    scenarioExecutionStarted = true;
    final artifact = await executeScenario(context);
    final custodyFailure = _validatePreparedArtifactCustody(context);
    if (custodyFailure != null) {
      return GroupMediaReliabilityRunnerResult.failed(custodyFailure);
    }
    _requireEmptyBuildGuard(context.buildGuardLog);

    final validatorId =
        context.scenario == groupMediaForegroundRetryAclRoundtripScenario
        ? groupMediaReliabilityArtifactValidatorId
        : groupMediaIosBackgroundRecoveryArtifactValidatorId;
    final validationDetail = _validateScenarioArtifact(context, artifact);
    if (validationDetail != null) {
      return GroupMediaReliabilityRunnerResult.failed(validationDetail);
    }
    final evidence = _persistArtifact(
      context,
      artifact,
      validatorId: validatorId,
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: <String>[validatorId],
    );
    if (!audit.isValid) {
      return GroupMediaReliabilityRunnerResult.failed(audit.detail);
    }
    final durableArtifact = jsonDecode(
      File(audit.canonicalPath!).readAsStringSync(),
    );
    final durableValidationDetail = _validateScenarioArtifact(
      context,
      durableArtifact,
    );
    if (durableValidationDetail != null) {
      return GroupMediaReliabilityRunnerResult.failed(durableValidationDetail);
    }
    return GroupMediaReliabilityRunnerResult.passed(evidence);
  } on GroupMediaReliabilityBlocked catch (error) {
    return GroupMediaReliabilityRunnerResult.blocked(
      error.blocker,
      error.detail,
    );
  } on GroupMediaReliabilityScenarioFailure catch (error) {
    return GroupMediaReliabilityRunnerResult.failed(
      'Group media scenario failed at ${error.code}.',
    );
  } on FormatException catch (error) {
    if (scenarioExecutionStarted) {
      return GroupMediaReliabilityRunnerResult.failed(
        'Group media proof validation failed after scenario execution began: '
        '${error.message}',
      );
    }
    return GroupMediaReliabilityRunnerResult.blocked('harness', error.message);
  } on FileSystemException catch (error) {
    return GroupMediaReliabilityRunnerResult.blocked(
      'harness',
      'Group media artifact custody failed: ${error.message}',
    );
  } on Object {
    return GroupMediaReliabilityRunnerResult.failed(
      'The group media scenario failed before a validated artifact existed.',
    );
  }
}

String? _validatePreparedArtifactCustody(
  GroupMediaReliabilityRunContext context,
) {
  if (context.scenario == groupMediaForegroundRetryAclRoundtripScenario) {
    if (_androidPreparedArtifactSha256(context.preparedArtifact.path) !=
        context.preparedArtifact.sha256Digest) {
      return 'The prepared Android APK changed during scenario execution.';
    }
    return null;
  }

  final bundleDigest = groupMediaPreparedDirectorySha256(
    Directory(context.preparedArtifact.path),
  );
  if (bundleDigest != context.preparedArtifact.sha256Digest) {
    return 'The prepared iOS bundle changed during scenario execution.';
  }

  final companion = context.androidCompanionArtifact;
  if (companion == null ||
      _androidPreparedArtifactSha256(companion.path) !=
          companion.sha256Digest) {
    return 'The prepared Android companion APK changed during scenario '
        'execution.';
  }
  return null;
}

String _androidPreparedArtifactSha256(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: true) !=
      FileSystemEntityType.file) {
    throw FileSystemException(
      'Prepared Android artifact is no longer a regular file.',
      path,
    );
  }
  return sha256.convert(File(path).readAsBytesSync()).toString();
}

String? _validateScenarioArtifact(
  GroupMediaReliabilityRunContext context,
  Object? artifact,
) {
  if (artifact is Map && artifact['run_id'] != context.runId) {
    return 'Artifact run_id does not match runner custody.';
  }
  if (context.scenario == groupMediaForegroundRetryAclRoundtripScenario) {
    if (artifact is! Map ||
        (artifact.containsKey('authority_mode')
                ? artifact['authority_mode']
                : groupMediaDistinctAuthorityMode) !=
            context.authorityMode) {
      return 'Artifact authority mode does not match runner custody.';
    }
    final validation = validateGroupMediaReliabilityArtifact(artifact);
    if (!validation.ok) return validation.detail;
  } else {
    final validation = validateGroupMediaIosBackgroundRecoveryArtifact(
      artifact,
    );
    if (!validation.ok) return validation.detail;
  }

  final root = artifact as Map;
  final prepared = root['prepared_artifact'];
  final digestField =
      context.scenario == groupMediaForegroundRetryAclRoundtripScenario
      ? 'sha256'
      : 'bundle_sha256';
  if (prepared is! Map ||
      prepared['profile'] != context.preparedArtifact.profile ||
      prepared[digestField] != context.preparedArtifact.sha256Digest) {
    return 'Prepared artifact evidence does not match runner custody.';
  }
  if (context.scenario == groupMediaIosReceiverBackgroundRecoveryScenario) {
    final companion = context.androidCompanionArtifact;
    if (companion == null ||
        prepared['android_profile'] != companion.profile ||
        prepared['android_sha256'] != companion.sha256Digest ||
        prepared['android_package'] !=
            groupMediaReliabilityAndroidPackageName) {
      return 'Android companion artifact evidence does not match custody.';
    }
  }
  return null;
}

GroupMediaReliabilityRunContext _buildContext(
  GroupMediaReliabilityRunnerArguments parsed,
  Map<String, String> environment,
) {
  final scenario = parsed.scenario!;
  final isAndroid = scenario == groupMediaForegroundRetryAclRoundtripScenario;
  final authorityMode =
      environment['SIMS_GROUP_MEDIA_AUTHORITY_MODE'] ??
      groupMediaDistinctAuthorityMode;
  if (!groupMediaAuthorityModeIsValid(authorityMode) ||
      (!isAndroid && authorityMode != groupMediaDistinctAuthorityMode)) {
    throw const FormatException(
      'Group media authority mode is invalid for this scenario.',
    );
  }
  final expectedProfile = isAndroid
      ? groupMediaReliabilityAndroidBuildProfile
      : groupMediaReliabilityIosBuildProfile;
  final artifactEnvironment = isAndroid
      ? groupMediaReliabilityAndroidArtifactEnvironment
      : groupMediaReliabilityIosArtifactEnvironment;
  final artifactValue = environment[artifactEnvironment]?.trim();
  if (artifactValue == null || artifactValue.isEmpty) {
    throw GroupMediaReliabilityBlocked(
      'missingArtifact',
      '$artifactEnvironment must name the centrally prepared $expectedProfile '
          'artifact.',
    );
  }
  final suppliedProfile = environment['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (suppliedProfile != null &&
      suppliedProfile.isNotEmpty &&
      suppliedProfile != expectedProfile) {
    throw GroupMediaReliabilityBlocked(
      'missingArtifact',
      'Prepared profile $suppliedProfile cannot satisfy $expectedProfile.',
    );
  }

  late final GroupMediaReliabilityPreparedArtifact preparedArtifact;
  GroupMediaReliabilityPreparedArtifact? androidCompanionArtifact;
  if (isAndroid) {
    preparedArtifact = _resolveAndroidPreparedArtifact(artifactValue);
  } else {
    final artifact = Directory(artifactValue).absolute;
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
        FileSystemEntityType.directory) {
      throw const GroupMediaReliabilityBlocked(
        'missingArtifact',
        'The centrally prepared physical-iOS app/XCTest bundle is missing.',
      );
    }
    preparedArtifact = GroupMediaReliabilityPreparedArtifact(
      path: artifact.path,
      profile: expectedProfile,
      sha256Digest: groupMediaPreparedDirectorySha256(artifact),
    );
    final companionValue =
        environment[groupMediaReliabilityAndroidArtifactEnvironment]?.trim();
    if (companionValue == null || companionValue.isEmpty) {
      throw const GroupMediaReliabilityBlocked(
        'missingArtifact',
        'The dedicated Android companion APK is required for the iOS row.',
      );
    }
    androidCompanionArtifact = _resolveAndroidPreparedArtifact(companionValue);
  }

  final deviceIds = parsed.deviceIds.isNotEmpty
      ? parsed.deviceIds
      : _environmentDevices(scenario, environment);
  _validateDevices(scenario, deviceIds);
  final relay = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  if (relay == null || relay.isEmpty || relay.contains(RegExp(r'[\r\n]'))) {
    throw const GroupMediaReliabilityBlocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES is required for the real relay boundary.',
    );
  }

  final runId =
      parsed.runId ??
      'p269-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  final roles = <String, GroupMediaReliabilityRoleBinding>{
    'sender': GroupMediaReliabilityRoleBinding(
      role: 'sender',
      deviceId: deviceIds[0],
      identityNamespace: '$runId-sender',
    ),
    'receiver': GroupMediaReliabilityRoleBinding(
      role: 'receiver',
      deviceId: deviceIds[1],
      identityNamespace: '$runId-receiver',
    ),
  };
  final proofPath = environment['SIMS_PROOF_DIRECTORY']?.trim();
  final buildGuardPath = environment['SIMS_BUILD_GUARD_LOG']?.trim();
  return GroupMediaReliabilityRunContext(
    scenario: scenario,
    runId: runId,
    preparedArtifact: preparedArtifact,
    roles: Map<String, GroupMediaReliabilityRoleBinding>.unmodifiable(roles),
    proofDirectory: Directory(
      proofPath == null || proofPath.isEmpty
          ? 'build/sims/proofs/groups.media_send_reliability'
          : proofPath,
    ).absolute,
    buildGuardLog: buildGuardPath == null || buildGuardPath.isEmpty
        ? null
        : File(buildGuardPath).absolute,
    androidCompanionArtifact: androidCompanionArtifact,
    authorityMode: authorityMode,
  );
}

GroupMediaReliabilityPreparedArtifact _resolveAndroidPreparedArtifact(
  String value,
) {
  final artifact = File(value).absolute;
  if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
      FileSystemEntityType.file) {
    throw const GroupMediaReliabilityBlocked(
      'missingArtifact',
      'The centrally prepared dedicated group-media APK is not a regular file.',
    );
  }
  return GroupMediaReliabilityPreparedArtifact(
    path: artifact.path,
    profile: groupMediaReliabilityAndroidBuildProfile,
    sha256Digest: _androidPreparedArtifactSha256(artifact.path),
  );
}

List<String> _environmentDevices(
  String scenario,
  Map<String, String> environment,
) {
  final sender = environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']?.trim() ?? '';
  final receiver = scenario == groupMediaForegroundRetryAclRoundtripScenario
      ? environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']?.trim() ?? ''
      : environment['SIMS_IOS_PHYSICAL_DEVICE_ID']?.trim() ?? '';
  return <String>[sender, receiver];
}

void _validateDevices(String scenario, List<String> deviceIds) {
  if (deviceIds.length != 2 ||
      deviceIds.any((value) => !_safeTargetPattern.hasMatch(value)) ||
      deviceIds[0] == deviceIds[1] ||
      _androidEmulatorPattern.hasMatch(deviceIds[0])) {
    throw const FormatException(
      'Exactly two distinct safe targets are required in sender,receiver order',
    );
  }
  if (scenario == groupMediaForegroundRetryAclRoundtripScenario) {
    if (!_androidEmulatorPattern.hasMatch(deviceIds[1])) {
      throw const FormatException(
        'Android reliability requires physical sender then emulator receiver',
      );
    }
  } else if (!_iosPhysicalPattern.hasMatch(deviceIds[1]) ||
      _androidEmulatorPattern.hasMatch(deviceIds[1])) {
    throw const FormatException(
      'iOS reliability requires physical Android sender then physical iPhone',
    );
  }
}

void _requireEmptyBuildGuard(File? buildGuardLog) {
  if (buildGuardLog == null || !buildGuardLog.existsSync()) return;
  if (buildGuardLog.readAsStringSync().trim().isNotEmpty) {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'A forbidden child build command reached the Sims build guard.',
    );
  }
}

SimsArtifactEvidence _persistArtifact(
  GroupMediaReliabilityRunContext context,
  Map<String, Object?> artifact, {
  required String validatorId,
}) {
  context.proofDirectory.createSync(recursive: true);
  final target = File(
    '${context.proofDirectory.path}${Platform.pathSeparator}'
    'group-media-${context.runId}.json',
  );
  if (target.existsSync()) {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'The run-scoped group media artifact already exists.',
    );
  }
  final temporary = File('${target.path}.pending');
  if (temporary.existsSync()) temporary.deleteSync();
  try {
    temporary.writeAsStringSync('${jsonEncode(artifact)}\n', flush: true);
    temporary.renameSync(target.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
  final canonicalPath = target.resolveSymbolicLinksSync();
  return SimsArtifactEvidence(
    path: canonicalPath,
    sha256Digest: sha256
        .convert(File(canonicalPath).readAsBytesSync())
        .toString(),
    validatorIds: <String>[validatorId],
  );
}
