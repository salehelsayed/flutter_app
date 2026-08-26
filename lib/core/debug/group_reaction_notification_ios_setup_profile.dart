import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Exact signed profile used only by the physical-iPhone Plan 397 fixture
/// setup build. Ordinary profile/release builds never receive this define.
const String groupReactionNotificationIosSetupBuildProfile =
    'ios.device.group_reaction_notification_397';

/// Runtime-only XCTest handoff used by the exact signed Plan 397 setup app.
const String groupReactionNotificationIosAutoSetupUsernameEnvironmentKey =
    'MKNOON_397_AUTO_SETUP_USERNAME';

/// Fresh per-launch value forwarded only by the exact Plan-398 setup readiness
/// boundary. The app receipt persists its SHA-256, never this raw value.
const String groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey =
    'MKNOON_398_SETUP_READINESS_ATTEMPT';
const String groupReactionNotificationIosSetupEntryProfileEnvironmentKey =
    'MKNOON_398_SETUP_ENTRY_PROFILE_ID';

const String groupReactionNotificationIosSetupReadinessFileName =
    'intro_e2e_setup_readiness.json';
const String groupReactionNotificationIosSetupReadinessSchema =
    'mknoon.plan398.ios-setup-readiness.v3';

enum GroupReactionNotificationIosSetupEntryStage { nativeAppDelegate, dartMain }

enum GroupReactionNotificationIosSetupBootstrapStage {
  shareLaunch,
  database,
  identityStore,
  autoSetup,
}

enum GroupReactionNotificationIosSetupReadinessDisposition {
  ready,
  nativeEntryFailure,
  dartEntryFailure,
  bootstrapDocumentsFailure,
  bootstrapShareLaunchFailure,
  bootstrapDatabaseFailure,
  bootstrapIdentityStoreFailure,
  bootstrapAutoSetupFailure,
  profileLaunchFailure,
  identityGenerationFailure,
  identityReloadFailure,
  qrGenerationFailure,
  identityExportFailure,
  invalid,
}

/// Keeps the generic intro fixture actions closed unless the one signed
/// Plan 397 setup product also explicitly enables E2E mode.
bool allowsGroupReactionNotificationIosSetupActions({
  required bool e2eTestMode,
  required String installedProfileId,
}) =>
    e2eTestMode &&
    installedProfileId == groupReactionNotificationIosSetupBuildProfile;

/// Resolves the XCTest-provided setup username without opening this seam to
/// ordinary builds, other E2E products, or non-iOS platforms.
String? resolveGroupReactionNotificationIosAutoSetupUsername({
  required bool isIos,
  required bool e2eTestMode,
  required String installedProfileId,
  required Map<String, String> launchEnvironment,
}) {
  if (!isIos ||
      !allowsGroupReactionNotificationIosSetupActions(
        e2eTestMode: e2eTestMode,
        installedProfileId: installedProfileId,
      )) {
    return null;
  }
  final username =
      launchEnvironment[groupReactionNotificationIosAutoSetupUsernameEnvironmentKey]
          ?.trim();
  return username == null || username.isEmpty ? null : username;
}

/// Resolves the fresh host/XCTest launch binding for the exact setup product.
/// Legacy Plan-397 setup launches omit this value and keep their established
/// uninstrumented behavior.
String? resolveGroupReactionNotificationIosSetupReadinessAttempt({
  required bool isIos,
  required bool e2eTestMode,
  required String installedProfileId,
  required Map<String, String> launchEnvironment,
}) {
  if (!isIos ||
      !allowsGroupReactionNotificationIosSetupActions(
        e2eTestMode: e2eTestMode,
        installedProfileId: installedProfileId,
      )) {
    return null;
  }
  final attempt =
      launchEnvironment[groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey]
          ?.trim();
  if (attempt == null ||
      !RegExp(r'^[A-Za-z0-9._:-]{16,160}$').hasMatch(attempt)) {
    return null;
  }
  return attempt;
}

Future<bool> acknowledgeGroupReactionNotificationIosDartMainEntry({
  required bool isIos,
  required bool e2eTestMode,
  required String installedProfileId,
  required Map<String, String> launchEnvironment,
  required Future<Object?> Function(Map<String, Object?> arguments)
  acknowledgeNative,
}) async {
  if (!isIos ||
      !allowsGroupReactionNotificationIosSetupActions(
        e2eTestMode: e2eTestMode,
        installedProfileId: installedProfileId,
      )) {
    return false;
  }
  final attempt =
      launchEnvironment[groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey];
  final runtimeProfile =
      launchEnvironment[groupReactionNotificationIosSetupEntryProfileEnvironmentKey];
  if (attempt == null ||
      attempt != attempt.trim() ||
      !RegExp(r'^[A-Za-z0-9._:-]{16,160}$').hasMatch(attempt) ||
      runtimeProfile != groupReactionNotificationIosSetupBuildProfile) {
    throw StateError('Plan 398 setup entry launch binding rejected');
  }
  final attemptSha256 = sha256.convert(utf8.encode(attempt)).toString();
  Object? response;
  try {
    response = await acknowledgeNative(<String, Object?>{
      'schema': groupReactionNotificationIosSetupReadinessSchema,
      'profileId': groupReactionNotificationIosSetupBuildProfile,
      'launchAttemptSha256': attemptSha256,
    });
  } on Object {
    throw StateError('Plan 398 native Dart-entry acknowledgement failed');
  }
  if (classifyGroupReactionNotificationIosSetupReadinessReceipt(
        response,
        expectedLaunchAttemptSha256: attemptSha256,
      ) !=
      GroupReactionNotificationIosSetupReadinessDisposition
          .bootstrapDocumentsFailure) {
    throw StateError('Plan 398 native Dart-entry acknowledgement rejected');
  }
  return true;
}

Map<String, Object?>
buildGroupReactionNotificationIosSetupEntryReadinessReceipt({
  required String launchAttemptSha256,
  required GroupReactionNotificationIosSetupEntryStage stage,
}) {
  if (!_isLowercaseSha256(launchAttemptSha256)) {
    throw ArgumentError.value(
      launchAttemptSha256,
      'launchAttemptSha256',
      'must be a lowercase SHA-256',
    );
  }
  final (receiptStage, reason, dartEntryAcknowledged) = switch (stage) {
    GroupReactionNotificationIosSetupEntryStage.nativeAppDelegate => (
      'native_app_delegate',
      'dart_main_not_reached',
      false,
    ),
    GroupReactionNotificationIosSetupEntryStage.dartMain => (
      'dart_main',
      'application_documents_not_ready',
      true,
    ),
  };
  return _setupReadinessReceipt(
    status: 'FAIL',
    stage: receiptStage,
    reason: reason,
    launchAttemptSha256: launchAttemptSha256,
    nativeEntryAcknowledged: true,
    dartEntryAcknowledged: dartEntryAcknowledged,
    launchInputPresent: false,
    identityInitiallyPresent: null,
    generationAttempted: false,
    generationSucceeded: false,
    reloadSucceeded: false,
    qrPayloadBuilt: false,
    identityExported: false,
    identityExportSha256: null,
  );
}

Map<String, Object?>
buildGroupReactionNotificationIosSetupBootstrapReadinessReceipt({
  required String launchAttemptSha256,
  required GroupReactionNotificationIosSetupBootstrapStage stage,
}) {
  if (!_isLowercaseSha256(launchAttemptSha256)) {
    throw ArgumentError.value(
      launchAttemptSha256,
      'launchAttemptSha256',
      'must be a lowercase SHA-256',
    );
  }
  final (receiptStage, reason) = switch (stage) {
    GroupReactionNotificationIosSetupBootstrapStage.shareLaunch => (
      'bootstrap_share_launch',
      'bootstrap_share_launch_incomplete',
    ),
    GroupReactionNotificationIosSetupBootstrapStage.database => (
      'bootstrap_database',
      'bootstrap_database_incomplete',
    ),
    GroupReactionNotificationIosSetupBootstrapStage.identityStore => (
      'bootstrap_identity_store',
      'bootstrap_identity_store_incomplete',
    ),
    GroupReactionNotificationIosSetupBootstrapStage.autoSetup => (
      'bootstrap_auto_setup',
      'bootstrap_auto_setup_not_reached',
    ),
  };
  return _setupReadinessReceipt(
    status: 'FAIL',
    stage: receiptStage,
    reason: reason,
    launchAttemptSha256: launchAttemptSha256,
    launchInputPresent: false,
    identityInitiallyPresent: null,
    generationAttempted: false,
    generationSucceeded: false,
    reloadSucceeded: false,
    qrPayloadBuilt: false,
    identityExported: false,
    identityExportSha256: null,
  );
}

Future<Map<String, Object?>> runGroupReactionNotificationIosSetupReadiness<T>({
  required String launchAttemptSha256,
  required Future<String?> Function() resolveUsername,
  required Future<T?> Function() loadIdentity,
  required Future<bool> Function() generateIdentity,
  required Future<bool> Function(T identity, String username) persistUsername,
  required Future<String?> Function(T identity) buildSignedQrPayload,
  required Future<String?> Function(T identity, String signedQrPayload)
  exportIdentity,
  required Future<void> Function(Map<String, Object?> receipt) writeReceipt,
}) async {
  if (!_isLowercaseSha256(launchAttemptSha256)) {
    throw ArgumentError.value(
      launchAttemptSha256,
      'launchAttemptSha256',
      'must be a lowercase SHA-256',
    );
  }

  Map<String, Object?> current = _setupReadinessReceipt(
    status: 'FAIL',
    stage: 'profile_launch',
    reason: 'profile_launch_failed',
    launchAttemptSha256: launchAttemptSha256,
    launchInputPresent: false,
    identityInitiallyPresent: null,
    generationAttempted: false,
    generationSucceeded: false,
    reloadSucceeded: false,
    qrPayloadBuilt: false,
    identityExported: false,
    identityExportSha256: null,
  );

  Future<void> publish(Map<String, Object?> receipt) async {
    current = receipt;
    await writeReceipt(receipt);
  }

  await publish(current);
  String? username;
  try {
    username = (await resolveUsername())?.trim();
  } on Object {
    return current;
  }
  if (username == null || username.isEmpty) return current;

  T? identity;
  try {
    identity = await loadIdentity();
  } on Object {
    return current;
  }
  final identityInitiallyPresent = identity != null;
  var generationAttempted = false;
  var generationSucceeded = false;

  if (identity == null) {
    generationAttempted = true;
    await publish(
      _setupReadinessReceipt(
        status: 'FAIL',
        stage: 'identity_generation',
        reason: 'identity_generation_failed',
        launchAttemptSha256: launchAttemptSha256,
        launchInputPresent: true,
        identityInitiallyPresent: false,
        generationAttempted: true,
        generationSucceeded: false,
        reloadSucceeded: false,
        qrPayloadBuilt: false,
        identityExported: false,
        identityExportSha256: null,
      ),
    );
    try {
      generationSucceeded = await generateIdentity();
    } on Object {
      return current;
    }
    if (!generationSucceeded) return current;

    await publish(
      _setupReadinessReceipt(
        status: 'FAIL',
        stage: 'identity_reload',
        reason: 'identity_reload_failed',
        launchAttemptSha256: launchAttemptSha256,
        launchInputPresent: true,
        identityInitiallyPresent: false,
        generationAttempted: true,
        generationSucceeded: true,
        reloadSucceeded: false,
        qrPayloadBuilt: false,
        identityExported: false,
        identityExportSha256: null,
      ),
    );
    try {
      identity = await loadIdentity();
      if (identity == null || !await persistUsername(identity, username)) {
        return current;
      }
    } on Object {
      return current;
    }
  }

  final resolvedIdentity = identity;
  await publish(
    _setupReadinessReceipt(
      status: 'FAIL',
      stage: 'qr_generation',
      reason: 'qr_generation_failed',
      launchAttemptSha256: launchAttemptSha256,
      launchInputPresent: true,
      identityInitiallyPresent: identityInitiallyPresent,
      generationAttempted: generationAttempted,
      generationSucceeded: generationSucceeded,
      reloadSucceeded: true,
      qrPayloadBuilt: false,
      identityExported: false,
      identityExportSha256: null,
    ),
  );
  String? qrPayload;
  try {
    qrPayload = await buildSignedQrPayload(resolvedIdentity);
  } on Object {
    return current;
  }
  if (qrPayload == null || qrPayload.isEmpty) return current;

  await publish(
    _setupReadinessReceipt(
      status: 'FAIL',
      stage: 'identity_export',
      reason: 'identity_export_failed',
      launchAttemptSha256: launchAttemptSha256,
      launchInputPresent: true,
      identityInitiallyPresent: identityInitiallyPresent,
      generationAttempted: generationAttempted,
      generationSucceeded: generationSucceeded,
      reloadSucceeded: true,
      qrPayloadBuilt: true,
      identityExported: false,
      identityExportSha256: null,
    ),
  );
  String? exportSha256;
  try {
    exportSha256 = await exportIdentity(resolvedIdentity, qrPayload);
  } on Object {
    return current;
  }
  if (!_isLowercaseSha256(exportSha256)) return current;

  await publish(
    _setupReadinessReceipt(
      status: 'PASS',
      stage: 'ready',
      reason: 'ready',
      launchAttemptSha256: launchAttemptSha256,
      launchInputPresent: true,
      identityInitiallyPresent: identityInitiallyPresent,
      generationAttempted: generationAttempted,
      generationSucceeded: generationSucceeded,
      reloadSucceeded: true,
      qrPayloadBuilt: true,
      identityExported: true,
      identityExportSha256: exportSha256,
    ),
  );
  return current;
}

GroupReactionNotificationIosSetupReadinessDisposition
classifyGroupReactionNotificationIosSetupReadinessReceipt(
  Object? raw, {
  required String expectedLaunchAttemptSha256,
  String? expectedIdentityExportSha256,
}) {
  if (raw == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .nativeEntryFailure;
  }
  if (!_isLowercaseSha256(expectedLaunchAttemptSha256) || raw is! Map) {
    return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
  }
  Map<String, Object?> receipt;
  try {
    receipt = Map<String, Object?>.from(raw);
  } on Object {
    return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
  }
  const expectedKeys = <String>{
    'schema',
    'status',
    'stage',
    'reason',
    'profileId',
    'launchAttemptSha256',
    'nativeEntryAcknowledged',
    'dartEntryAcknowledged',
    'launchInputPresent',
    'identityInitiallyPresent',
    'generationAttempted',
    'generationSucceeded',
    'reloadSucceeded',
    'qrPayloadBuilt',
    'identityExported',
    'identityExportSha256',
    'containsSecrets',
  };
  if (receipt.length != expectedKeys.length ||
      !expectedKeys.every(receipt.containsKey) ||
      receipt['schema'] != groupReactionNotificationIosSetupReadinessSchema ||
      receipt['profileId'] != groupReactionNotificationIosSetupBuildProfile ||
      receipt['launchAttemptSha256'] != expectedLaunchAttemptSha256 ||
      receipt['containsSecrets'] != false ||
      receipt['nativeEntryAcknowledged'] is! bool ||
      receipt['dartEntryAcknowledged'] is! bool ||
      receipt['launchInputPresent'] is! bool ||
      receipt['generationAttempted'] is! bool ||
      receipt['generationSucceeded'] is! bool ||
      receipt['reloadSucceeded'] is! bool ||
      receipt['qrPayloadBuilt'] is! bool ||
      receipt['identityExported'] is! bool ||
      (receipt['identityInitiallyPresent'] != null &&
          receipt['identityInitiallyPresent'] is! bool) ||
      (receipt['identityExportSha256'] != null &&
          !_isLowercaseSha256(receipt['identityExportSha256']))) {
    return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
  }

  final nativeEntryAcknowledged = receipt['nativeEntryAcknowledged']! as bool;
  final dartEntryAcknowledged = receipt['dartEntryAcknowledged']! as bool;
  final launchInputPresent = receipt['launchInputPresent']! as bool;
  final identityInitiallyPresent = receipt['identityInitiallyPresent'] as bool?;
  final generationAttempted = receipt['generationAttempted']! as bool;
  final generationSucceeded = receipt['generationSucceeded']! as bool;
  final reloadSucceeded = receipt['reloadSucceeded']! as bool;
  final qrPayloadBuilt = receipt['qrPayloadBuilt']! as bool;
  final identityExported = receipt['identityExported']! as bool;
  final exportSha256 = receipt['identityExportSha256'] as String?;
  final generationConsistent = identityInitiallyPresent == true
      ? !generationAttempted && !generationSucceeded
      : identityInitiallyPresent == false &&
            generationAttempted &&
            generationSucceeded;

  bool matches(String status, String stage, String reason) =>
      receipt['status'] == status &&
      receipt['stage'] == stage &&
      receipt['reason'] == reason;

  final isClosedPreEntryArm =
      !launchInputPresent &&
      identityInitiallyPresent == null &&
      !generationAttempted &&
      !generationSucceeded &&
      !reloadSucceeded &&
      !qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null;
  if (!nativeEntryAcknowledged) {
    return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
  }
  if (isClosedPreEntryArm &&
      !dartEntryAcknowledged &&
      matches('FAIL', 'native_app_delegate', 'dart_main_not_reached')) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .dartEntryFailure;
  }
  if (!dartEntryAcknowledged) {
    return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
  }
  if (isClosedPreEntryArm &&
      matches('FAIL', 'dart_main', 'application_documents_not_ready')) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .bootstrapDocumentsFailure;
  }
  if (isClosedPreEntryArm &&
      matches(
        'FAIL',
        'bootstrap_share_launch',
        'bootstrap_share_launch_incomplete',
      )) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .bootstrapShareLaunchFailure;
  }
  if (isClosedPreEntryArm &&
      matches('FAIL', 'bootstrap_database', 'bootstrap_database_incomplete')) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .bootstrapDatabaseFailure;
  }
  if (isClosedPreEntryArm &&
      matches(
        'FAIL',
        'bootstrap_identity_store',
        'bootstrap_identity_store_incomplete',
      )) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .bootstrapIdentityStoreFailure;
  }
  if (isClosedPreEntryArm &&
      matches(
        'FAIL',
        'bootstrap_auto_setup',
        'bootstrap_auto_setup_not_reached',
      )) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .bootstrapAutoSetupFailure;
  }

  if (matches('FAIL', 'profile_launch', 'profile_launch_failed') &&
      !launchInputPresent &&
      identityInitiallyPresent == null &&
      !generationAttempted &&
      !generationSucceeded &&
      !reloadSucceeded &&
      !qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .profileLaunchFailure;
  }
  if (matches('FAIL', 'identity_generation', 'identity_generation_failed') &&
      launchInputPresent &&
      identityInitiallyPresent == false &&
      generationAttempted &&
      !generationSucceeded &&
      !reloadSucceeded &&
      !qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .identityGenerationFailure;
  }
  if (matches('FAIL', 'identity_reload', 'identity_reload_failed') &&
      launchInputPresent &&
      identityInitiallyPresent == false &&
      generationAttempted &&
      generationSucceeded &&
      !reloadSucceeded &&
      !qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .identityReloadFailure;
  }
  if (matches('FAIL', 'qr_generation', 'qr_generation_failed') &&
      launchInputPresent &&
      generationConsistent &&
      reloadSucceeded &&
      !qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .qrGenerationFailure;
  }
  if (matches('FAIL', 'identity_export', 'identity_export_failed') &&
      launchInputPresent &&
      generationConsistent &&
      reloadSucceeded &&
      qrPayloadBuilt &&
      !identityExported &&
      exportSha256 == null) {
    return GroupReactionNotificationIosSetupReadinessDisposition
        .identityExportFailure;
  }
  if (matches('PASS', 'ready', 'ready') &&
      launchInputPresent &&
      generationConsistent &&
      reloadSucceeded &&
      qrPayloadBuilt &&
      identityExported &&
      _isLowercaseSha256(exportSha256) &&
      (expectedIdentityExportSha256 == null ||
          exportSha256 == expectedIdentityExportSha256)) {
    return GroupReactionNotificationIosSetupReadinessDisposition.ready;
  }
  return GroupReactionNotificationIosSetupReadinessDisposition.invalid;
}

bool isAllowedGroupReactionNotificationIosSetupReadinessTransition({
  required Object? previous,
  required Object? next,
}) {
  if (previous is! Map || next is! Map) return false;
  Map<String, Object?> previousReceipt;
  Map<String, Object?> nextReceipt;
  try {
    previousReceipt = Map<String, Object?>.from(previous);
    nextReceipt = Map<String, Object?>.from(next);
  } on Object {
    return false;
  }
  final attemptSha256 = previousReceipt['launchAttemptSha256'];
  if (attemptSha256 is! String ||
      !_isLowercaseSha256(attemptSha256) ||
      nextReceipt['launchAttemptSha256'] != attemptSha256 ||
      classifyGroupReactionNotificationIosSetupReadinessReceipt(
            previousReceipt,
            expectedLaunchAttemptSha256: attemptSha256,
          ) ==
          GroupReactionNotificationIosSetupReadinessDisposition.invalid ||
      classifyGroupReactionNotificationIosSetupReadinessReceipt(
            nextReceipt,
            expectedLaunchAttemptSha256: attemptSha256,
          ) ==
          GroupReactionNotificationIosSetupReadinessDisposition.invalid) {
    return false;
  }
  final previousStage = previousReceipt['stage'];
  final nextStage = nextReceipt['stage'];
  const allowedNextStages = <String, Set<String>>{
    'native_app_delegate': {'dart_main'},
    'dart_main': {'bootstrap_share_launch'},
    'bootstrap_share_launch': {'bootstrap_database'},
    'bootstrap_database': {'bootstrap_identity_store'},
    'bootstrap_identity_store': {'bootstrap_auto_setup'},
    'bootstrap_auto_setup': {'profile_launch'},
    'profile_launch': {'identity_generation', 'qr_generation'},
    'identity_generation': {'identity_reload'},
    'identity_reload': {'qr_generation'},
    'qr_generation': {'identity_export'},
    'identity_export': {'ready'},
  };
  return previousStage is String &&
      nextStage is String &&
      (allowedNextStages[previousStage]?.contains(nextStage) ?? false);
}

Map<String, Object?> _setupReadinessReceipt({
  required String status,
  required String stage,
  required String reason,
  required String launchAttemptSha256,
  bool nativeEntryAcknowledged = true,
  bool dartEntryAcknowledged = true,
  required bool launchInputPresent,
  required bool? identityInitiallyPresent,
  required bool generationAttempted,
  required bool generationSucceeded,
  required bool reloadSucceeded,
  required bool qrPayloadBuilt,
  required bool identityExported,
  required String? identityExportSha256,
}) => <String, Object?>{
  'schema': groupReactionNotificationIosSetupReadinessSchema,
  'status': status,
  'stage': stage,
  'reason': reason,
  'profileId': groupReactionNotificationIosSetupBuildProfile,
  'launchAttemptSha256': launchAttemptSha256,
  'nativeEntryAcknowledged': nativeEntryAcknowledged,
  'dartEntryAcknowledged': dartEntryAcknowledged,
  'launchInputPresent': launchInputPresent,
  'identityInitiallyPresent': identityInitiallyPresent,
  'generationAttempted': generationAttempted,
  'generationSucceeded': generationSucceeded,
  'reloadSucceeded': reloadSucceeded,
  'qrPayloadBuilt': qrPayloadBuilt,
  'identityExported': identityExported,
  'identityExportSha256': identityExportSha256,
  'containsSecrets': false,
};

bool _isLowercaseSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
