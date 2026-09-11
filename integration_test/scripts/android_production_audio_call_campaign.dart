import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_production_audio_call_evidence.dart';
import '_android_app_package.dart';

const String _fixtureIdentityEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256';
const String _turnAuthorityDigestEnvironment =
    'PLAN399_LOCAL_TURN_AUTHORITY_SHA256';
const String _coturnInstanceDigestEnvironment =
    'PLAN399_LOCAL_COTURN_INSTANCE_SHA256';
const String androidProductionAudioCallPionOracleEnvironment =
    'PLAN399_PION_ORACLE_ATTESTATION_B64';
const String _profileEnvironment = 'SIMS_ARTIFACT_PROFILE_ID';
// The local relay/coturn campaign must never replace a tester's personal app.
const String androidProductionAudioCallAppPackage =
    'com.mknoon.sims.productionaudio';
const String androidProductionAudioCallReadinessOperation = 'readiness';
const int _maximumUiDumpBytes = 4 * 1024 * 1024;
const int _maximumSavedTextBytes = 1024 * 1024;
const int _maximumScreenshotBytes = 20 * 1024 * 1024;
const int _maximumTelecomDumpBytes = 4 * 1024 * 1024;
const int _maximumTelecomCallBlockLines = 4096;
const Duration _coldAppLaunchTimeout = Duration(minutes: 6);

final class _UiHierarchyUnavailable implements Exception {
  const _UiHierarchyUnavailable();

  @override
  String toString() => 'UIAutomator did not return a complete hierarchy.';
}

const Set<String> _nativeSemanticPlatformPackageCandidates = <String>{
  'com.android.systemui',
  'com.android.dialer',
  'com.google.android.dialer',
};

final class AndroidProductionAudioCallCampaignResult {
  const AndroidProductionAudioCallCampaignResult._({
    required this.processExitCode,
    required this.json,
  });

  factory AndroidProductionAudioCallCampaignResult.pass(
    SimsArtifactEvidence evidence,
  ) => AndroidProductionAudioCallCampaignResult._(
    processExitCode: 0,
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': androidProductionAudioCallAssertionCount,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'The cached production APK completed one emulator-to-physical '
          'Android audio call through the disposable local relay.',
      'artifactEvidence': evidence.toJson(),
    },
  );

  factory AndroidProductionAudioCallCampaignResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidProductionAudioCallCampaignResult._(
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

  factory AndroidProductionAudioCallCampaignResult.fail({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidProductionAudioCallCampaignResult._(
    processExitCode: 1,
    json: <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': androidProductionAudioCallAssertionCount,
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

/// Preserves the causal campaign failure when exact app-state restoration also
/// fails.
///
/// Dart exceptions thrown from `finally` otherwise replace the active error.
/// Keeping both failures typed lets the campaign result retain the primary
/// classification while still reporting the restoration failure as secondary.
final class AndroidProductionAudioCallPrimaryFailure implements Exception {
  const AndroidProductionAudioCallPrimaryFailure({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.restorationError,
    required this.restorationStackTrace,
  });

  final Object primaryError;
  final StackTrace primaryStackTrace;
  final Object restorationError;
  final StackTrace restorationStackTrace;

  @override
  String toString() =>
      '$primaryError\nSecondary app-state restoration failure: '
      '$restorationError';
}

enum AndroidProductionAudioCallTargetKind { physical, emulator }

final class AndroidProductionAudioCallTarget {
  const AndroidProductionAudioCallTarget({
    required this.deviceId,
    required this.kind,
  });

  final String deviceId;
  final AndroidProductionAudioCallTargetKind kind;
}

void validateAndroidProductionAudioCallTopology(
  List<AndroidProductionAudioCallTarget> targets,
) {
  if (targets.length != 2 ||
      targets.first.deviceId.isEmpty ||
      targets.last.deviceId.isEmpty ||
      targets.first.deviceId == targets.last.deviceId ||
      targets.first.kind != AndroidProductionAudioCallTargetKind.physical ||
      targets.last.kind != AndroidProductionAudioCallTargetKind.emulator) {
    throw const FormatException(
      'Production audio call requires one explicit physical Android followed '
      'by one distinct Android emulator.',
    );
  }
}

void validateAndroidProductionAudioCallAppPackage(String packageName) {
  if (packageName != androidProductionAudioCallAppPackage) {
    throw const FormatException(
      'Production audio-call controls require the fixed disposable app owner.',
    );
  }
}

void validateAndroidProductionAudioCallNativeAnswerPackage(String packageName) {
  if (packageName == androidProductionAudioCallAppPackage ||
      !_nativeSemanticPlatformPackageCandidates.contains(packageName)) {
    throw const FormatException(
      'Production audio-call Answer must be owned by a proven Android '
      'native/system package.',
    );
  }
}

final class AndroidProductionAudioCallSemanticNode {
  const AndroidProductionAudioCallSemanticNode({
    required this.label,
    required this.packageName,
    required this.centerX,
    required this.centerY,
  });

  final String label;
  final String packageName;
  final int centerX;
  final int centerY;
}

/// Privacy-safe observation of the fixed strings that may identify the
/// production CallStyle surface. Arbitrary notification or contact text is
/// deliberately never retained.
final class AndroidProductionAudioCallNativeSemanticDiagnostic {
  AndroidProductionAudioCallNativeSemanticDiagnostic({
    required Set<String> markers,
    required Set<String> answerOwnerClasses,
  }) : markers = Set<String>.unmodifiable(markers),
       answerOwnerClasses = Set<String>.unmodifiable(answerOwnerClasses);

  final Set<String> markers;
  final Set<String> answerOwnerClasses;

  @override
  String toString() {
    final safeMarkers = markers.toList(growable: false)..sort();
    final safeOwners = answerOwnerClasses.toList(growable: false)..sort();
    return 'markers=${safeMarkers.join(',')};'
        'answerOwnerClasses=${safeOwners.join(',')}';
  }
}

AndroidProductionAudioCallNativeSemanticDiagnostic
inspectAndroidProductionAudioCallNativeSemanticSurface(String xml) {
  const safeLabels = <String, String>{
    'MKnoon call': 'title',
    'MKnoon caller': 'person',
    'Incoming call': 'incoming',
    'Answer': 'answer',
    'Decline': 'decline',
    'Call in progress': 'ongoing',
    'End': 'end',
  };
  final markers = <String>{};
  final answerOwnerClasses = <String>{};
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = match.group(0)!;
    final values = <String>{
      _xmlDecode(_attribute(raw, 'text')),
      _xmlDecode(_attribute(raw, 'content-desc')),
    }..remove('');
    for (final value in values) {
      final marker = safeLabels[value];
      if (marker != null) markers.add(marker);
    }
    if (!values.contains('Answer')) continue;
    final packageName = _xmlDecode(_attribute(raw, 'package'));
    answerOwnerClasses.add(
      packageName == androidProductionAudioCallAppPackage
          ? 'app'
          : _nativeSemanticPlatformPackageCandidates.contains(packageName)
          ? 'native-candidate'
          : 'other',
    );
  }
  return AndroidProductionAudioCallNativeSemanticDiagnostic(
    markers: markers,
    answerOwnerClasses: answerOwnerClasses,
  );
}

final class AndroidProductionAudioCallSelectorException implements Exception {
  const AndroidProductionAudioCallSelectorException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum AndroidProductionAudioCallStartDispatchStatus {
  acknowledged,
  semanticActionNotDispatched,
  downstreamTimedOut,
  downstreamRejected,
}

enum AndroidProductionAudioCallStartDispatchSurface {
  starting,
  cancel,
  failure,
}

/// Typed post-tap acknowledgement from the production caller UI.
///
/// A successful shell tap is deliberately insufficient: only the stable
/// `Cancel call` surface acknowledges dispatch. The transient starting marker
/// and exact failure surface are retained as bounded, non-private diagnostics.
final class AndroidProductionAudioCallStartDispatchAcknowledgement {
  AndroidProductionAudioCallStartDispatchAcknowledgement({
    required this.status,
    required Iterable<AndroidProductionAudioCallStartDispatchSurface>
    observedSurfaces,
  }) : observedSurfaces = List.unmodifiable(observedSurfaces) {
    final hasCancel = this.observedSurfaces.contains(
      AndroidProductionAudioCallStartDispatchSurface.cancel,
    );
    final hasFailure = this.observedSurfaces.contains(
      AndroidProductionAudioCallStartDispatchSurface.failure,
    );
    final hasStarting = this.observedSurfaces.contains(
      AndroidProductionAudioCallStartDispatchSurface.starting,
    );
    final valid = switch (status) {
      AndroidProductionAudioCallStartDispatchStatus.acknowledged =>
        hasCancel && !hasFailure,
      AndroidProductionAudioCallStartDispatchStatus
          .semanticActionNotDispatched =>
        !hasStarting && !hasCancel && !hasFailure,
      AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut =>
        hasStarting && !hasCancel && !hasFailure,
      AndroidProductionAudioCallStartDispatchStatus.downstreamRejected =>
        hasFailure && !hasCancel,
    };
    if (!valid) {
      throw ArgumentError(
        'Start-dispatch acknowledgement contradicts its observed surfaces.',
      );
    }
  }

  final AndroidProductionAudioCallStartDispatchStatus status;
  final List<AndroidProductionAudioCallStartDispatchSurface> observedSurfaces;

  bool get downstreamObserved => observedSurfaces.isNotEmpty;
}

final class AndroidProductionAudioCallStartDispatchException
    implements Exception {
  const AndroidProductionAudioCallStartDispatchException(this.status);

  final AndroidProductionAudioCallStartDispatchStatus status;

  @override
  String toString() => switch (status) {
    AndroidProductionAudioCallStartDispatchStatus.semanticActionNotDispatched =>
      'Start voice call semanticActionNotDispatched; '
          'downstream-not-observed.',
    AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut =>
      'Start voice call downstreamTimedOut after its starting surface.',
    AndroidProductionAudioCallStartDispatchStatus.downstreamRejected =>
      'Start voice call downstreamRejected.',
    AndroidProductionAudioCallStartDispatchStatus.acknowledged =>
      'Start voice call was already acknowledged.',
  };
}

/// Selects one action only from its exact accessibility description. Text,
/// approximate labels, resource IDs, and hard-coded coordinates are never
/// fallback selectors.
AndroidProductionAudioCallSemanticNode
selectExactAndroidProductionAudioSemanticNode(
  String xml, {
  required String label,
  required Set<String> allowedPackages,
}) {
  if (allowedPackages.isEmpty ||
      allowedPackages.any(
        (package) => !RegExp(r'^[A-Za-z][A-Za-z0-9_.]+$').hasMatch(package),
      )) {
    throw const AndroidProductionAudioCallSelectorException(
      'Semantic package ownership must be explicit and canonical.',
    );
  }
  final matches = _exactSemanticNodes(
    xml,
    label: label,
    requireClickable: true,
    allowedPackages: allowedPackages,
  );
  if (matches.length != 1) {
    throw AndroidProductionAudioCallSelectorException(
      'Expected exactly one enabled, clickable semantic node "$label"; '
      'found ${matches.length}.',
    );
  }
  return matches.single;
}

/// Selects the real Android system Answer action.
///
/// CallStyle notification actions are exposed by different Android releases
/// through either `content-desc` or visible accessibility `text`. This
/// dedicated selector accepts both exact representations, but only for the
/// small native package allowlist that the driver separately proves is loaded
/// from a read-only platform partition. App-owned Flutter controls continue to
/// use [selectExactAndroidProductionAudioSemanticNode] and never gain a text
/// fallback.
AndroidProductionAudioCallSemanticNode
selectExactAndroidProductionAudioNativeAnswerNode(
  String xml, {
  required Set<String> allowedPackages,
}) {
  if (allowedPackages.isEmpty ||
      allowedPackages.any(
        (package) =>
            package == androidProductionAudioCallAppPackage ||
            !_nativeSemanticPlatformPackageCandidates.contains(package),
      )) {
    throw const AndroidProductionAudioCallSelectorException(
      'Native Answer package ownership must be explicit and system-only.',
    );
  }
  final matches = _exactSemanticNodes(
    xml,
    label: 'Answer',
    requireClickable: true,
    allowedPackages: allowedPackages,
    allowExactText: true,
  );
  if (matches.length != 1) {
    throw AndroidProductionAudioCallSelectorException(
      'Expected exactly one enabled, clickable native Answer node; found '
      '${matches.length}.',
    );
  }
  return matches.single;
}

final class AndroidProductionAudioCallIdentity {
  const AndroidProductionAudioCallIdentity({
    required this.username,
    required this.peerId,
    required this.qrPayload,
    required this.mlKemPublicKey,
  });

  final String username;
  final String peerId;
  final String qrPayload;
  final String mlKemPublicKey;
}

abstract interface class AndroidProductionAudioCallCampaignDriver {
  Future<AndroidProductionAudioCallTargetKind> classifyTarget(String deviceId);

  Future<void> verifyRelayReachable(String deviceId);

  Future<void> captureState();

  Future<void> prepareTarget({
    required String deviceId,
    required String expectedApkSha256,
  });

  Future<AndroidProductionAudioCallIdentity> bootstrapIdentity({
    required String deviceId,
    required String role,
  });

  Future<void> establishContact({
    required String ownerDeviceId,
    required String ownerRole,
    required AndroidProductionAudioCallIdentity contact,
  });

  Future<void> openConversation({
    required String deviceId,
    required String contactUsername,
  });

  Future<Map<String, Object?>> observe({
    required String deviceId,
    required String role,
    required String operation,
    required String runId,
    required String nonce,
    required String profileSha256,
    required String apkSha256,
    String? contactAccountPeerId,
  });

  Future<AndroidProductionAudioCallStartDispatchAcknowledgement>
  dispatchStartVoiceCall(String deviceId);

  Future<void> tapSemantic(String deviceId, String label);

  /// Taps the native Android incoming-call Answer surface and returns the
  /// exact driver-proven native/system package that owned the selected node.
  Future<String> tapNativeAnswer(String deviceId);

  Future<void> waitForSemantic(String deviceId, String label);

  Future<void> waitForSemanticAbsent(String deviceId, String label);

  Future<List<AndroidProductionAudioCallArtifactDigest>> captureArtifacts(
    String stage,
  );

  /// Captures failure-only diagnostics. These artifacts are deliberately not
  /// returned to, or registered in, the success evidence payload.
  Future<void> captureFailureArtifacts(String stage);

  Future<bool> nativeCallReleased(String deviceId);

  Future<void> restoreState();
}

/// Dependency-injectable orchestration core. Independent device work is
/// deliberately paired through [Future.wait] so the fast lane does not pay
/// serial ADB/poller latency.
Future<Map<String, Object?>> executeAndroidProductionAudioCallCampaign({
  required List<String> devices,
  required String apkSha256,
  required String profileSha256,
  required String relayFixtureIdentitySha256,
  required String turnAuthoritySha256,
  required String coturnInstanceIdentitySha256,
  required AndroidProductionAudioCallPionOracleEvidence pionOracle,
  required AndroidProductionAudioCallCampaignDriver driver,
  required String runId,
  required String callerNonce,
  required String calleeNonce,
  Duration rtpObservationTimeout = const Duration(seconds: 20),
  Duration rtpObservationPollInterval = const Duration(milliseconds: 250),
}) async {
  if (devices.length != 2 || devices.first == devices.last) {
    throw const FormatException(
      'Production audio call requires two distinct explicit Android serials.',
    );
  }
  if (!_isSha256(coturnInstanceIdentitySha256) ||
      pionOracle.fixtureInstanceSha256 != coturnInstanceIdentitySha256) {
    throw const FormatException(
      'The Pion oracle is not bound to this coturn fixture instance.',
    );
  }
  final kinds = await Future.wait<AndroidProductionAudioCallTargetKind>(
    devices.map(driver.classifyTarget),
  );
  final targets = List<AndroidProductionAudioCallTarget>.generate(
    devices.length,
    (index) => AndroidProductionAudioCallTarget(
      deviceId: devices[index],
      kind: kinds[index],
    ),
    growable: false,
  );
  validateAndroidProductionAudioCallTopology(targets);
  await Future.wait<void>(devices.map(driver.verifyRelayReachable));

  final physicalDeviceId = devices.first;
  final emulatorDeviceId = devices.last;
  var stateCaptured = false;
  var stateRestored = false;
  late AndroidProductionAudioCallIdentity callerIdentity;
  late AndroidProductionAudioCallIdentity calleeIdentity;
  late Map<String, Object?> callerFinalReceipt;
  late Map<String, Object?> calleeFinalReceipt;
  var nativeCallsReleasedBothEndpoints = false;
  var nativeAnswered = false;
  final artifacts = <AndroidProductionAudioCallArtifactDigest>[];
  Object? primaryError;
  StackTrace? primaryStackTrace;

  try {
    await driver.captureState();
    stateCaptured = true;
    await Future.wait<void>(
      devices.map(
        (deviceId) => driver.prepareTarget(
          deviceId: deviceId,
          expectedApkSha256: apkSha256,
        ),
      ),
    );

    final identities = await Future.wait<AndroidProductionAudioCallIdentity>(
      <Future<AndroidProductionAudioCallIdentity>>[
        driver.bootstrapIdentity(
          deviceId: emulatorDeviceId,
          role: androidProductionAudioCallCallerRole,
        ),
        driver.bootstrapIdentity(
          deviceId: physicalDeviceId,
          role: androidProductionAudioCallCalleeRole,
        ),
      ],
    );
    callerIdentity = identities.first;
    calleeIdentity = identities.last;
    _validateIdentity(callerIdentity);
    _validateIdentity(calleeIdentity);

    // The emulator has the slower cold-start path. Let its reciprocal setup
    // finish before the physical peer starts an exact-receipt send; otherwise
    // the emulator can process and confirm queued requests only after the
    // sender's bounded direct-ACK window has expired. Both directions retain
    // the exact call-wake receipt contract, while independent peer phases
    // above and below remain concurrent.
    await driver.establishContact(
      ownerDeviceId: emulatorDeviceId,
      ownerRole: androidProductionAudioCallCallerRole,
      contact: calleeIdentity,
    );
    await driver.establishContact(
      ownerDeviceId: physicalDeviceId,
      ownerRole: androidProductionAudioCallCalleeRole,
      contact: callerIdentity,
    );
    await Future.wait<void>(<Future<void>>[
      driver.openConversation(
        deviceId: emulatorDeviceId,
        contactUsername: calleeIdentity.username,
      ),
      driver.openConversation(
        deviceId: physicalDeviceId,
        contactUsername: callerIdentity.username,
      ),
    ]);

    final armed =
        await Future.wait<Map<String, Object?>>(<Future<Map<String, Object?>>>[
          driver.observe(
            deviceId: emulatorDeviceId,
            role: androidProductionAudioCallCallerRole,
            operation: androidProductionAudioCallArmOperation,
            runId: runId,
            nonce: callerNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
          ),
          driver.observe(
            deviceId: physicalDeviceId,
            role: androidProductionAudioCallCalleeRole,
            operation: androidProductionAudioCallArmOperation,
            runId: runId,
            nonce: calleeNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
          ),
        ]);
    _validateObserverOperationReceipt(
      armed.first,
      role: androidProductionAudioCallCallerRole,
      operation: androidProductionAudioCallArmOperation,
      runId: runId,
      nonce: callerNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );
    _validateObserverOperationReceipt(
      armed.last,
      role: androidProductionAudioCallCalleeRole,
      operation: androidProductionAudioCallArmOperation,
      runId: runId,
      nonce: calleeNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );

    final startDispatch = await driver.dispatchStartVoiceCall(emulatorDeviceId);
    if (startDispatch.status !=
            AndroidProductionAudioCallStartDispatchStatus.acknowledged ||
        !startDispatch.downstreamObserved) {
      throw AndroidProductionAudioCallStartDispatchException(
        startDispatch.status,
      );
    }
    final callerReadiness = await driver.observe(
      deviceId: emulatorDeviceId,
      role: androidProductionAudioCallCallerRole,
      operation: androidProductionAudioCallReadinessOperation,
      runId: runId,
      nonce: callerNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
      contactAccountPeerId: calleeIdentity.peerId,
    );
    _validateObserverOperationReceipt(
      callerReadiness,
      role: androidProductionAudioCallCallerRole,
      operation: androidProductionAudioCallReadinessOperation,
      runId: runId,
      nonce: callerNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );
    final nativeAnswerPackage = await driver.tapNativeAnswer(physicalDeviceId);
    validateAndroidProductionAudioCallNativeAnswerPackage(nativeAnswerPackage);
    nativeAnswered = true;
    await Future.wait<void>(<Future<void>>[
      driver.waitForSemantic(emulatorDeviceId, 'Connected'),
      driver.waitForSemantic(emulatorDeviceId, 'Call controls'),
      driver.waitForSemantic(physicalDeviceId, 'Connected'),
      driver.waitForSemantic(physicalDeviceId, 'Call controls'),
    ]);

    final sampled =
        await Future.wait<Map<String, Object?>>(<Future<Map<String, Object?>>>[
          _waitForBidirectionalAudioRtp(
            driver: driver,
            deviceId: emulatorDeviceId,
            role: androidProductionAudioCallCallerRole,
            runId: runId,
            nonce: callerNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
            timeout: rtpObservationTimeout,
            pollInterval: rtpObservationPollInterval,
          ),
          _waitForBidirectionalAudioRtp(
            driver: driver,
            deviceId: physicalDeviceId,
            role: androidProductionAudioCallCalleeRole,
            runId: runId,
            nonce: calleeNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
            timeout: rtpObservationTimeout,
            pollInterval: rtpObservationPollInterval,
          ),
        ]);
    _validateObserverOperationReceipt(
      sampled.first,
      role: androidProductionAudioCallCallerRole,
      operation: androidProductionAudioCallSampleOperation,
      runId: runId,
      nonce: callerNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );
    _validateObserverOperationReceipt(
      sampled.last,
      role: androidProductionAudioCallCalleeRole,
      operation: androidProductionAudioCallSampleOperation,
      runId: runId,
      nonce: calleeNonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );
    artifacts.addAll(await driver.captureArtifacts('active'));

    await driver.tapSemantic(emulatorDeviceId, 'Mute');
    await driver.waitForSemantic(emulatorDeviceId, 'Unmute');
    await driver.tapSemantic(emulatorDeviceId, 'Unmute');
    await driver.waitForSemantic(emulatorDeviceId, 'Mute');
    await driver.tapSemantic(emulatorDeviceId, 'Speaker');
    await driver.waitForSemantic(emulatorDeviceId, 'Audio output: Speaker');
    await driver.tapSemantic(emulatorDeviceId, 'End');
    await Future.wait<void>(<Future<void>>[
      driver.waitForSemanticAbsent(emulatorDeviceId, 'Call controls'),
      driver.waitForSemanticAbsent(physicalDeviceId, 'Call controls'),
    ]);

    final stopped =
        await Future.wait<Map<String, Object?>>(<Future<Map<String, Object?>>>[
          driver.observe(
            deviceId: emulatorDeviceId,
            role: androidProductionAudioCallCallerRole,
            operation: androidProductionAudioCallStopOperation,
            runId: runId,
            nonce: callerNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
          ),
          driver.observe(
            deviceId: physicalDeviceId,
            role: androidProductionAudioCallCalleeRole,
            operation: androidProductionAudioCallStopOperation,
            runId: runId,
            nonce: calleeNonce,
            profileSha256: profileSha256,
            apkSha256: apkSha256,
          ),
        ]);
    callerFinalReceipt = stopped.first;
    calleeFinalReceipt = stopped.last;
    if (callerFinalReceipt['callBindingSha256'] !=
            sampled.first['callBindingSha256'] ||
        calleeFinalReceipt['callBindingSha256'] !=
            sampled.last['callBindingSha256']) {
      throw const FormatException(
        'Production observer call binding changed between sample and stop.',
      );
    }
    artifacts.addAll(await driver.captureArtifacts('terminal'));
    final nativeCleanup = await Future.wait<bool>(
      devices.map(driver.nativeCallReleased),
    );
    if (nativeCleanup.length != 2 ||
        nativeCleanup.any((released) => !released)) {
      throw StateError(
        'Android Telecom retained an active production call on an endpoint.',
      );
    }
    nativeCallsReleasedBothEndpoints = true;
  } on Object catch (error, stackTrace) {
    try {
      await driver.captureFailureArtifacts('failure');
    } on Object {
      // Best-effort diagnostics must never replace the causal campaign error.
    }
    primaryError = error;
    primaryStackTrace = stackTrace;
  } finally {
    if (stateCaptured) {
      try {
        await driver.restoreState();
        stateRestored = true;
      } on Object catch (restorationError, restorationStackTrace) {
        final causalError = primaryError;
        if (causalError != null) {
          Error.throwWithStackTrace(
            AndroidProductionAudioCallPrimaryFailure(
              primaryError: causalError,
              primaryStackTrace: primaryStackTrace!,
              restorationError: restorationError,
              restorationStackTrace: restorationStackTrace,
            ),
            primaryStackTrace,
          );
        }
        Error.throwWithStackTrace(restorationError, restorationStackTrace);
      }
    }
  }

  final causalError = primaryError;
  if (causalError != null) {
    Error.throwWithStackTrace(causalError, primaryStackTrace!);
  }

  return aggregateAndroidProductionAudioCallEvidence(
    callerReceipt: callerFinalReceipt,
    calleeReceipt: calleeFinalReceipt,
    runId: runId,
    callerNonce: callerNonce,
    calleeNonce: calleeNonce,
    profileSha256: profileSha256,
    apkSha256: apkSha256,
    relayFixtureIdentitySha256: relayFixtureIdentitySha256,
    turnAuthoritySha256: turnAuthoritySha256,
    coturnInstanceIdentitySha256: coturnInstanceIdentitySha256,
    pionOracle: pionOracle,
    callerIdentitySha256: _sha256Text(callerIdentity.peerId),
    calleeIdentitySha256: _sha256Text(calleeIdentity.peerId),
    physicalDeviceId: physicalDeviceId,
    emulatorDeviceId: emulatorDeviceId,
    semanticControls: AndroidProductionAudioCallSemanticControls(
      callStarted: true,
      nativeAnswered: nativeAnswered,
      muteExercised: true,
      speakerExercised: true,
      hangupExercised: true,
    ),
    terminalSurfacesDismissed: true,
    nativeCallsReleasedBothEndpoints: nativeCallsReleasedBothEndpoints,
    appStateRestored: stateRestored,
    artifacts: artifacts,
  );
}

Future<AndroidProductionAudioCallCampaignResult>
runAndroidProductionAudioCallCampaign({
  required List<String> devices,
  required String? artifactPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final artifact = artifactPath == null ? null : File(artifactPath).absolute;
  if (artifact == null || !_isRegularFile(artifact)) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable centrally cached $androidProductionAudioCallProfileId '
          'APK is required; this campaign never builds an app.',
      artifactPresent: false,
    );
  }
  if (env[_profileEnvironment]?.trim() case final configured?
      when configured.isNotEmpty &&
          configured != androidProductionAudioCallProfileId) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'Production audio-call E2E requires '
          '$androidProductionAudioCallProfileId; received $configured.',
      artifactPresent: true,
    );
  }

  late final _LocalRelayBinding relay;
  late final AndroidProductionAudioCallPionOracleEvidence pionOracle;
  try {
    relay = _LocalRelayBinding.fromEnvironment(env);
    pionOracle = decodeAndroidProductionAudioCallPionOracleAttestation(
      env[androidProductionAudioCallPionOracleEnvironment] ?? '',
    );
  } on FormatException catch (error) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: error.message,
      artifactPresent: true,
    );
  }
  late final String apkSha256;
  try {
    apkSha256 = sha256.convert(await artifact.readAsBytes()).toString();
  } on FileSystemException catch (error) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The centrally cached APK could not be read: ${error.message}',
      artifactPresent: false,
    );
  }
  final profileSha256 = _sha256Text(androidProductionAudioCallProfileId);
  late final String packageName;
  try {
    packageName = resolveAndroidAppPackage();
    validateAndroidProductionAudioCallAppPackage(packageName);
  } on FormatException catch (error) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: error.message,
      artifactPresent: true,
    );
  }
  final driver = SystemAndroidProductionAudioCallCampaignDriver(
    physicalDeviceId: devices.isEmpty ? '' : devices.first,
    emulatorDeviceId: devices.length < 2 ? '' : devices.last,
    artifact: artifact,
    artifactSha256: apkSha256,
    packageName: packageName,
    relayHost: relay.host,
    relayPort: relay.port,
    proofDirectory: _proofDirectory(env),
  );
  final tokens = _SecureTokens();

  late final Map<String, Object?> runtimeProof;
  try {
    runtimeProof = await executeAndroidProductionAudioCallCampaign(
      devices: devices,
      apkSha256: apkSha256,
      profileSha256: profileSha256,
      relayFixtureIdentitySha256: relay.fixtureIdentitySha256,
      turnAuthoritySha256: relay.turnAuthoritySha256,
      coturnInstanceIdentitySha256: relay.coturnInstanceIdentitySha256,
      pionOracle: pionOracle,
      driver: driver,
      runId: tokens.next('production-audio'),
      callerNonce: tokens.next('caller'),
      calleeNonce: tokens.next('callee'),
    );
  } on AndroidProductionAudioCallPrimaryFailure catch (error) {
    return _compoundCampaignFailureResult(error);
  } on FormatException catch (error) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail: error.message,
      artifactPresent: true,
    );
  } on AndroidAppStateBlocked catch (error) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: error.detail,
      artifactPresent: true,
    );
  } on AndroidAppStateFailure catch (error) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      artifactPresent: false,
    );
  } on Object catch (error, stackTrace) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'test',
      detail: 'Production audio-call campaign failed: $error\n$stackTrace',
      artifactPresent: false,
    );
  }

  final durable = writeSimsArtifactEvidenceSync(
    directory: _proofDirectory(env),
    capabilityId: androidProductionAudioCallScenarioId,
    validatorIds: const <String>[androidProductionAudioCallArtifactValidatorId],
    payload: androidProductionAudioCallDurablePayload(runtimeProof),
  );
  final audit = auditSimsArtifactEvidence(
    evidence: durable,
    expectedValidatorIds: const <String>[
      androidProductionAudioCallArtifactValidatorId,
    ],
  );
  if (!audit.isValid) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'harness',
      detail: audit.detail,
      artifactPresent: false,
    );
  }
  final decoded = jsonDecode(File(durable.path).readAsStringSync());
  if (decoded is! Map ||
      !validateAndroidProductionAudioCallDurableArtifact(
        decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
      ).ok) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'harness',
      detail: 'Durable production audio-call evidence failed validation.',
      artifactPresent: false,
    );
  }
  return AndroidProductionAudioCallCampaignResult.pass(durable);
}

AndroidProductionAudioCallCampaignResult _compoundCampaignFailureResult(
  AndroidProductionAudioCallPrimaryFailure failure,
) {
  final primary = failure.primaryError;
  final secondary =
      '\nSecondary app-state restoration failure: ${failure.restorationError}';
  if (primary is FormatException) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail: '${primary.message}$secondary',
      artifactPresent: true,
    );
  }
  if (primary is AndroidAppStateBlocked) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: '${primary.detail}$secondary',
      artifactPresent: true,
    );
  }
  if (primary is AndroidAppStateFailure) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'restoration',
      detail: '${primary.detail}$secondary',
      artifactPresent: false,
    );
  }
  return AndroidProductionAudioCallCampaignResult.fail(
    blocker: 'test',
    detail:
        'Production audio-call campaign failed: $primary\n'
        '${failure.primaryStackTrace}$secondary',
    artifactPresent: false,
  );
}

AndroidProductionAudioCallPionOracleEvidence
decodeAndroidProductionAudioCallPionOracleAttestation(String encoded) {
  if (encoded.isEmpty ||
      encoded.length > 64 * 1024 ||
      encoded.contains(RegExp(r'\s'))) {
    throw const FormatException(
      'A bounded Pion oracle attestation is required before device launch.',
    );
  }
  late final Object? decoded;
  try {
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty || bytes.length > 48 * 1024) {
      throw const FormatException('Pion oracle attestation size is invalid.');
    }
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } on Object {
    throw const FormatException('Pion oracle attestation is malformed.');
  }
  if (decoded is! Map) {
    throw const FormatException('Pion oracle attestation is not an object.');
  }
  return AndroidProductionAudioCallPionOracleEvidence.fromResult(
    decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
  );
}

final class SystemAndroidProductionAudioCallCampaignDriver
    implements AndroidProductionAudioCallCampaignDriver {
  SystemAndroidProductionAudioCallCampaignDriver({
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
    required this.artifact,
    required this.artifactSha256,
    required this.packageName,
    required this.relayHost,
    required this.relayPort,
    required this.proofDirectory,
    AndroidHostProcessRunner runner = const SystemAndroidHostProcessRunner(),
    int startDispatchMaximumPolls = 180,
    Duration startDispatchPollInterval = const Duration(milliseconds: 250),
  }) : _runner = runner,
       _startDispatchMaximumPolls = startDispatchMaximumPolls,
       _startDispatchPollInterval = startDispatchPollInterval {
    validateAndroidProductionAudioCallAppPackage(packageName);
    if (startDispatchMaximumPolls < 1 || startDispatchPollInterval.isNegative) {
      throw ArgumentError(
        'Start-dispatch polling must have a positive bound and non-negative '
        'interval.',
      );
    }
  }

  final String physicalDeviceId;
  final String emulatorDeviceId;
  final File artifact;
  final String artifactSha256;
  final String packageName;
  final String relayHost;
  final int relayPort;
  final Directory proofDirectory;
  final AndroidHostProcessRunner _runner;
  final int _startDispatchMaximumPolls;
  final Duration _startDispatchPollInterval;
  final Random _random = Random.secure();
  AndroidAppStateGuard? _stateGuard;
  final Map<String, Future<Set<String>>> _nativeSemanticPackages =
      <String, Future<Set<String>>>{};
  final Map<String, Future<String>> _pendingUiDumps = {};

  @override
  Future<AndroidProductionAudioCallTargetKind> classifyTarget(
    String deviceId,
  ) async {
    _requireExpectedDevice(deviceId);
    late final ProcessResult state;
    try {
      state = await _run('adb', <String>[
        '-s',
        deviceId,
        'get-state',
      ], allowFailure: true);
    } on ProcessException catch (error) {
      throw FormatException('adb is unavailable: ${error.message}');
    }
    if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
      throw FormatException('Android target "$deviceId" is not ready.');
    }
    final qemu = await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'getprop',
      'ro.kernel.qemu',
    ], allowFailure: true);
    if (qemu.exitCode != 0) {
      throw FormatException('Android target "$deviceId" is not classifiable.');
    }
    return '${qemu.stdout}'.trim() == '1'
        ? AndroidProductionAudioCallTargetKind.emulator
        : AndroidProductionAudioCallTargetKind.physical;
  }

  @override
  Future<void> verifyRelayReachable(String deviceId) async {
    final probe = await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'toybox',
      'nc',
      '-z',
      '-w',
      '5',
      relayHost,
      '$relayPort',
    ], allowFailure: true);
    if (probe.exitCode != 0) {
      throw FormatException(
        'The disposable local relay is unreachable from "$deviceId".',
      );
    }
  }

  @override
  Future<void> captureState() async {
    if (_stateGuard != null) {
      throw StateError('Android app state was already captured.');
    }
    _stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[physicalDeviceId, emulatorDeviceId],
      packageName: packageName,
      backupLabel: 'production-audio-call',
      preparedArtifact: artifact,
      expectedArtifactSha256: artifactSha256,
      runner: _runner,
    );
  }

  @override
  Future<void> prepareTarget({
    required String deviceId,
    required String expectedApkSha256,
  }) async {
    final guard = _stateGuard;
    if (guard == null) throw StateError('Android app state was not captured.');
    if (expectedApkSha256 != artifactSha256) {
      throw const FormatException('Prepared APK custody binding changed.');
    }
    await guard.prepareFreshInstall(
      device: deviceId,
      artifact: artifact,
      expectedArtifactSha256: artifactSha256,
    );
    await _adbShell(deviceId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_WAKEUP',
    ]);
    await _adbShell(deviceId, const <String>[
      'wm',
      'dismiss-keyguard',
    ], allowFailure: true);
    await _adbShell(deviceId, const <String>[
      'cmd',
      'statusbar',
      'collapse',
    ], allowFailure: true);
    await _grant(deviceId, 'android.permission.RECORD_AUDIO');
    await _grant(deviceId, 'android.permission.POST_NOTIFICATIONS');
    final username = deviceId == emulatorDeviceId
        ? 'Plan399Caller'
        : 'Plan399Callee';
    await _writeAppFile(
      deviceId,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': username}),
    );
  }

  @override
  Future<AndroidProductionAudioCallIdentity> bootstrapIdentity({
    required String deviceId,
    required String role,
  }) async {
    await _deleteAppFile(deviceId, 'intro_e2e_identity.json');
    await _launch(deviceId);
    final raw = await _waitForAppFile(
      deviceId,
      'intro_e2e_identity.json',
      timeout: const Duration(minutes: 3),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Identity export is not an object.');
    }
    final identity = decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final qrPayload = identity['qrPayload'];
    final mlKemPublicKey = identity['mlKemPublicKey'];
    if (qrPayload is! String ||
        qrPayload.isEmpty ||
        mlKemPublicKey is! String ||
        mlKemPublicKey.isEmpty) {
      throw FormatException('Identity export for $role is incomplete.');
    }
    final qr = jsonDecode(qrPayload);
    if (qr is! Map || qr['ns'] is! String || qr['un'] is! String) {
      throw FormatException('Identity QR payload for $role is invalid.');
    }
    return AndroidProductionAudioCallIdentity(
      username: qr['un']! as String,
      peerId: qr['ns']! as String,
      qrPayload: qrPayload,
      mlKemPublicKey: mlKemPublicKey,
    );
  }

  @override
  Future<void> establishContact({
    required String ownerDeviceId,
    required String ownerRole,
    required AndroidProductionAudioCallIdentity contact,
  }) async {
    final stepId = 'production-contact-$ownerRole-${_token('step')}';
    await _deleteAppFile(ownerDeviceId, 'intro_e2e_result.json');
    await _writeAppFile(
      ownerDeviceId,
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{
        'stepId': stepId,
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': contact.qrPayload,
            'mlKemPublicKey': contact.mlKemPublicKey,
          },
        ],
        'open_conversation_with_peer_id': contact.peerId,
        'send_contact_requests_for_added_contacts': true,
        'require_exact_call_wake_receipt': true,
      }),
    );
    await _foreground(ownerDeviceId);
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(ownerDeviceId, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['stepId'] == stepId) {
            if (decoded['status'] == 'failed' || decoded['success'] == false) {
              throw StateError('Contact setup failed for $ownerRole.');
            }
            final snapshot = decoded['snapshot'];
            final contacts = snapshot is Map ? snapshot['contacts'] : null;
            final present =
                contacts is List &&
                contacts.whereType<Map>().any(
                  (row) => row['peerId'] == contact.peerId,
                );
            final uiNavigation = decoded['uiNavigation'];
            final conversationOpened =
                uiNavigation is Map &&
                uiNavigation['requestedPeerId'] == contact.peerId &&
                uiNavigation['opened'] == true;
            if (decoded['status'] == 'complete' &&
                decoded['success'] == true &&
                !conversationOpened) {
              throw StateError(
                'Contact setup receipt for $ownerRole did not open the '
                'requested conversation for ${contact.peerId}.',
              );
            }
            if (decoded['status'] == 'complete' &&
                decoded['success'] == true &&
                present &&
                conversationOpened) {
              await _deleteAppFile(ownerDeviceId, 'intro_e2e_config.json');
              await _deleteAppFile(ownerDeviceId, 'intro_e2e_result.json');
              return;
            }
          }
        } on FormatException {
          // The app replaces receipts atomically; retry a partial read.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('Contact setup timed out for $ownerRole.');
  }

  @override
  Future<void> openConversation({
    required String deviceId,
    required String contactUsername,
  }) async {
    await _foreground(deviceId);
    await waitForSemantic(deviceId, 'Start voice call');
  }

  @override
  Future<Map<String, Object?>> observe({
    required String deviceId,
    required String role,
    required String operation,
    required String runId,
    required String nonce,
    required String profileSha256,
    required String apkSha256,
    String? contactAccountPeerId,
  }) async {
    final readiness = operation == androidProductionAudioCallReadinessOperation;
    if (readiness != (contactAccountPeerId != null)) {
      throw const FormatException(
        'Only readiness observations accept an exact contact peer.',
      );
    }
    final request = jsonEncode(<String, Object?>{
      'schema': androidProductionAudioCallObservationRequestSchema,
      'transport_action': androidProductionAudioCallObserverAction,
      'scenario': androidProductionAudioCallScenarioId,
      'buildProfile': androidProductionAudioCallProfileId,
      'role': role,
      'operation': operation,
      'stepId': 'production-call-$role-$operation-$runId',
      'runId': runId,
      'nonce': nonce,
      'profileSha256': profileSha256,
      'apkSha256': apkSha256,
      if (readiness) 'contactAccountPeerId': contactAccountPeerId,
    });

    Future<void> issueRequest() async {
      await _deleteAppFile(deviceId, 'intro_e2e_result.json');
      await _writeAppFile(deviceId, 'intro_e2e_config.json', request);
    }

    await issueRequest();
    final expectedStatus = switch (operation) {
      androidProductionAudioCallArmOperation => 'armed',
      androidProductionAudioCallSampleOperation => 'observing',
      androidProductionAudioCallStopOperation => 'complete',
      androidProductionAudioCallReadinessOperation => 'ready',
      _ => throw FormatException('Unsupported observer operation $operation.'),
    };
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(deviceId, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final receipt = decoded.map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            );
            if (receipt['stepId'] ==
                    'production-call-$role-$operation-$runId' &&
                receipt['nonce'] == nonce) {
              if (receipt['status'] == 'failed' ||
                  receipt['success'] == false) {
                throw StateError(
                  'Production call observer failed for $role/$operation.',
                );
              }
              if (receipt['status'] == expectedStatus &&
                  receipt['success'] == true) {
                return receipt;
              }
              if (readiness &&
                  receipt['status'] == 'not_ready' &&
                  receipt['success'] == true) {
                await Future<void>.delayed(const Duration(milliseconds: 300));
                await issueRequest();
                continue;
              }
            }
          }
        } on FormatException {
          // Retry an incomplete atomic receipt within the bounded window.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException(
      'Production call observer timed out for $role/$operation.',
    );
  }

  @override
  Future<void> tapSemantic(String deviceId, String label) async {
    if (label == 'Answer') {
      throw const AndroidProductionAudioCallSelectorException(
        'Native Answer requires explicit native/system package proof.',
      );
    }
    final allowedPackages = await _allowedSemanticPackages(deviceId, label);
    await _tapSemanticNode(
      deviceId,
      label: label,
      allowedPackages: allowedPackages,
    );
  }

  @override
  Future<AndroidProductionAudioCallStartDispatchAcknowledgement>
  dispatchStartVoiceCall(String deviceId) async {
    if (deviceId != emulatorDeviceId) {
      throw const FormatException(
        'Start voice call dispatch belongs to the explicit emulator caller.',
      );
    }
    final allowedPackages = await _allowedSemanticPackages(
      deviceId,
      'Start voice call',
    );
    await _tapSemanticNode(
      deviceId,
      label: 'Start voice call',
      allowedPackages: allowedPackages,
    );

    final observed = <AndroidProductionAudioCallStartDispatchSurface>[];
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    for (
      var poll = 0;
      poll < _startDispatchMaximumPolls && DateTime.now().isBefore(deadline);
      poll += 1
    ) {
      final surface = _classifyStartDispatchSurface(
        await _uiDump(deviceId),
        allowedPackages: allowedPackages,
      );
      if (surface != null && (observed.isEmpty || observed.last != surface)) {
        observed.add(surface);
      }
      if (surface == AndroidProductionAudioCallStartDispatchSurface.failure) {
        return AndroidProductionAudioCallStartDispatchAcknowledgement(
          status:
              AndroidProductionAudioCallStartDispatchStatus.downstreamRejected,
          observedSurfaces: observed,
        );
      }
      if (surface == AndroidProductionAudioCallStartDispatchSurface.cancel) {
        return AndroidProductionAudioCallStartDispatchAcknowledgement(
          status: AndroidProductionAudioCallStartDispatchStatus.acknowledged,
          observedSurfaces: observed,
        );
      }
      if (poll + 1 < _startDispatchMaximumPolls &&
          _startDispatchPollInterval > Duration.zero) {
        await Future<void>.delayed(_startDispatchPollInterval);
      }
    }
    final status =
        observed.contains(
          AndroidProductionAudioCallStartDispatchSurface.starting,
        )
        ? AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut
        : AndroidProductionAudioCallStartDispatchStatus
              .semanticActionNotDispatched;
    return AndroidProductionAudioCallStartDispatchAcknowledgement(
      status: status,
      observedSurfaces: observed,
    );
  }

  @override
  Future<String> tapNativeAnswer(String deviceId) async {
    if (deviceId != physicalDeviceId) {
      throw const FormatException(
        'Native Answer must run on the explicit physical Android callee.',
      );
    }
    final allowedPackages = await _allowedSemanticPackages(deviceId, 'Answer');
    var answered = false;
    try {
      final node = await _tapSemanticNode(
        deviceId,
        label: 'Answer',
        allowedPackages: allowedPackages,
        allowExactText: true,
      );
      validateAndroidProductionAudioCallNativeAnswerPackage(node.packageName);
      if (!allowedPackages.contains(node.packageName)) {
        throw const AndroidProductionAudioCallSelectorException(
          'Selected Answer owner was not proven by the Android driver.',
        );
      }
      answered = true;
      return node.packageName;
    } finally {
      // On failure, keep the shade visible until the outer campaign captures
      // its bounded diagnostics. A successful action returns immediately to
      // the app so connected-surface assertions observe the real app UI.
      if (answered) await _collapseNativeAnswerSurface(deviceId);
    }
  }

  Future<AndroidProductionAudioCallSemanticNode> _tapSemanticNode(
    String deviceId, {
    required String label,
    required Set<String> allowedPackages,
    bool allowExactText = false,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    final observedNativeMarkers = <String>{};
    final observedAnswerOwnerClasses = <String>{};
    var unavailableUiReads = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (label == 'Answer' && allowExactText) {
        // Incoming native windows can replace the shade after it was opened.
        // Each bounded attempt must observe the current system-owned surface.
        await _revealNativeAnswerSurface(deviceId);
      }
      final String xml;
      try {
        xml = await _uiDump(deviceId);
      } on _UiHierarchyUnavailable {
        unavailableUiReads++;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      if (label == 'Answer' && allowExactText) {
        final diagnostic =
            inspectAndroidProductionAudioCallNativeSemanticSurface(xml);
        observedNativeMarkers.addAll(diagnostic.markers);
        observedAnswerOwnerClasses.addAll(diagnostic.answerOwnerClasses);
      }
      final matches = _exactSemanticNodes(
        xml,
        label: label,
        requireClickable: true,
        allowedPackages: allowedPackages,
        allowExactText: allowExactText,
      );
      if (matches.length > 1) {
        throw AndroidProductionAudioCallSelectorException(
          'Expected exactly one enabled, clickable semantic node "$label"; '
          'found ${matches.length}.',
        );
      }
      if (matches.length == 1) {
        final node = matches.single;
        await _adbShell(deviceId, <String>[
          'input',
          'tap',
          '${node.centerX}',
          '${node.centerY}',
        ]);
        return node;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final diagnostic = AndroidProductionAudioCallNativeSemanticDiagnostic(
      markers: observedNativeMarkers,
      answerOwnerClasses: observedAnswerOwnerClasses,
    );
    throw AndroidProductionAudioCallSelectorException(
      'Expected exactly one enabled, clickable semantic node "$label"; '
      'found 0 before timeout; $diagnostic; '
      'unavailableUiReads=$unavailableUiReads.',
    );
  }

  @override
  Future<void> waitForSemantic(String deviceId, String label) async {
    final allowedPackages = await _allowedSemanticPackages(deviceId, label);
    final nativeAnswer = label == 'Answer';
    if (nativeAnswer) await _revealNativeAnswerSurface(deviceId);
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final String xml;
      try {
        xml = await _uiDump(deviceId);
      } on _UiHierarchyUnavailable {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      final matches = _exactSemanticNodes(
        xml,
        label: label,
        requireClickable: false,
        allowedPackages: allowedPackages,
        allowExactText: nativeAnswer,
      );
      if (matches.length > 1) {
        throw AndroidProductionAudioCallSelectorException(
          'Expected exactly one enabled semantic node "$label"; found '
          '${matches.length}.',
        );
      }
      if (matches.length == 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Semantic node "$label" did not appear.');
  }

  Future<void> _revealNativeAnswerSurface(String deviceId) async {
    if (deviceId != physicalDeviceId) {
      throw const FormatException(
        'Native Answer presentation belongs to the physical Android callee.',
      );
    }
    // Android 14+ may deny full-screen-intent use while still posting the
    // production CallStyle notification. Revealing the shade makes that real
    // SystemUI-owned action observable. Failure is tolerated so an already
    // visible full-screen system surface remains usable by the same selector.
    await _adbShell(deviceId, const <String>[
      'cmd',
      'statusbar',
      'expand-notifications',
    ], allowFailure: true);
  }

  Future<void> _collapseNativeAnswerSurface(String deviceId) async {
    await _adbShell(deviceId, const <String>[
      'cmd',
      'statusbar',
      'collapse',
    ], allowFailure: true);
  }

  @override
  Future<void> waitForSemanticAbsent(String deviceId, String label) async {
    final allowedPackages = await _allowedSemanticPackages(deviceId, label);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final String xml;
      try {
        xml = await _uiDump(deviceId);
      } on _UiHierarchyUnavailable {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      final matches = _exactSemanticNodes(
        xml,
        label: label,
        requireClickable: false,
        allowedPackages: allowedPackages,
      );
      if (matches.isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Semantic node "$label" remained visible.');
  }

  @override
  Future<List<AndroidProductionAudioCallArtifactDigest>> captureArtifacts(
    String stage,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(stage)) {
      throw const FormatException('Artifact stage is unsafe.');
    }
    proofDirectory.createSync(recursive: true);
    final rows =
        await Future.wait<List<AndroidProductionAudioCallArtifactDigest>>(
          <Future<List<AndroidProductionAudioCallArtifactDigest>>>[
            _captureDeviceArtifacts(
              deviceId: emulatorDeviceId,
              role: androidProductionAudioCallCallerRole,
              stage: stage,
            ),
            _captureDeviceArtifacts(
              deviceId: physicalDeviceId,
              role: androidProductionAudioCallCalleeRole,
              stage: stage,
            ),
          ],
        );
    return List<AndroidProductionAudioCallArtifactDigest>.unmodifiable(
      rows.expand((row) => row),
    );
  }

  @override
  Future<void> captureFailureArtifacts(String stage) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(stage)) {
      throw const FormatException('Failure artifact stage is unsafe.');
    }
    proofDirectory.createSync(recursive: true);
    try {
      await Future.wait<void>(<Future<void>>[
        _captureFailureArtifactsForEndpoint(
          deviceId: emulatorDeviceId,
          role: androidProductionAudioCallCallerRole,
          stage: stage,
        ),
        _captureFailureArtifactsForEndpoint(
          deviceId: physicalDeviceId,
          role: androidProductionAudioCallCalleeRole,
          stage: stage,
        ),
      ]);
    } finally {
      await _collapseNativeAnswerSurface(physicalDeviceId);
    }
  }

  Future<void> _captureFailureArtifactsForEndpoint({
    required String deviceId,
    required String role,
    required String stage,
  }) async {
    await Future.wait<void>(<Future<void>>[
      _ignoreDiagnosticFailure(
        () async => _captureDeviceArtifacts(
          deviceId: deviceId,
          role: role,
          stage: stage,
        ),
      ),
      _ignoreDiagnosticFailure(
        () => _writeFailureAppProcessLogcat(
          deviceId: deviceId,
          role: role,
          stage: stage,
        ),
      ),
    ]);
  }

  Future<void> _ignoreDiagnosticFailure(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // One unavailable diagnostic must not obscure the causal campaign error
      // or prevent another endpoint/diagnostic from being captured.
    }
  }

  Future<void> _writeFailureAppProcessLogcat({
    required String deviceId,
    required String role,
    required String stage,
  }) async {
    final log = await readSanitizedAppProcessLogcat(deviceId);
    final file = File(
      '${proofDirectory.path}/$stage-$role-${_token('capture')}-app-logcat.txt',
    );
    await file.writeAsString(log, flush: true);
  }

  /// Returns a bounded, sanitized log from only the currently running app PID.
  ///
  /// Failure capture uses this alongside the bounded global tail so noisy
  /// UIAutomator/SystemUI traffic cannot evict the causal production app lines.
  Future<String> readSanitizedAppProcessLogcat(String deviceId) async {
    _requireExpectedDevice(deviceId);
    final pidResult = await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'pidof',
      '-s',
      packageName,
    ]);
    final pid = '${pidResult.stdout}'.trim();
    if (pidResult.exitCode != 0 ||
        !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(pid)) {
      throw StateError('Production app PID is unavailable for diagnostics.');
    }
    final logResult = await _run('adb', <String>[
      '-s',
      deviceId,
      'logcat',
      '-d',
      '--pid=$pid',
      '-t',
      '2000',
      '-v',
      'threadtime',
    ]);
    final raw = '${logResult.stdout}';
    if (logResult.exitCode != 0 ||
        utf8.encode(raw).length > _maximumSavedTextBytes) {
      throw StateError('Bounded app-process logcat capture failed.');
    }
    final sanitized = sanitizeAndroidProductionAudioCallDiagnosticText(raw);
    if (utf8.encode(sanitized).length > _maximumSavedTextBytes) {
      throw StateError('Sanitized app-process logcat exceeds its byte bound.');
    }
    return sanitized;
  }

  @override
  Future<bool> nativeCallReleased(String deviceId) async {
    _requireExpectedDevice(deviceId);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final result = await _run('adb', <String>[
        '-s',
        deviceId,
        'shell',
        'dumpsys',
        'telecom',
      ]);
      if (result.exitCode == 0 &&
          androidProductionAudioCallNativeStateReleased(
            '${result.stdout}',
            packageName: packageName,
          )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<Set<String>> _allowedSemanticPackages(String deviceId, String label) {
    _requireExpectedDevice(deviceId);
    if (label != 'Answer') {
      return Future<Set<String>>.value(<String>{packageName});
    }
    return _nativeSemanticPackages.putIfAbsent(
      deviceId,
      () => _proveNativeSemanticPackages(deviceId),
    );
  }

  Future<Set<String>> _proveNativeSemanticPackages(String deviceId) async {
    final candidates = _nativeSemanticPlatformPackageCandidates.toList(
      growable: false,
    );
    final results = await Future.wait<(String, ProcessResult)>(
      candidates.map(
        (candidate) async => (
          candidate,
          await _run('adb', <String>[
            '-s',
            deviceId,
            'shell',
            'pm',
            'path',
            candidate,
          ], allowFailure: true),
        ),
      ),
    );
    final proven = <String>{};
    for (final (candidate, result) in results) {
      if (candidate != packageName &&
          result.exitCode == 0 &&
          '${result.stdout}'
              .split('\n')
              .map((line) => line.trim())
              .any(_isReadOnlyPlatformPackagePath)) {
        proven.add(candidate);
      }
    }
    if (proven.isEmpty) {
      throw const AndroidProductionAudioCallSelectorException(
        'No Android native/system package could be proven for Answer.',
      );
    }
    return Set<String>.unmodifiable(proven);
  }

  @override
  Future<void> restoreState() async {
    final guard = _stateGuard;
    if (guard == null) throw StateError('Android app state was not captured.');
    await guard.restoreAll();
  }

  Future<List<AndroidProductionAudioCallArtifactDigest>>
  _captureDeviceArtifacts({
    required String deviceId,
    required String role,
    required String stage,
  }) async {
    final stem = '$stage-$role-${_token('capture')}';
    final ui = sanitizeAndroidProductionAudioCallDiagnosticText(
      await _uiDump(deviceId),
    );
    final logResult = await _run('adb', <String>[
      '-s',
      deviceId,
      'logcat',
      '-d',
      '-t',
      '800',
      '-v',
      'threadtime',
    ]);
    if (logResult.exitCode != 0) {
      throw StateError('Bounded logcat capture failed for $role.');
    }
    final log = sanitizeAndroidProductionAudioCallDiagnosticText(
      '${logResult.stdout}',
    );
    final screenshot = await _screenshot(deviceId);
    if (screenshot.isEmpty || screenshot.length > _maximumScreenshotBytes) {
      throw StateError('Bounded screenshot capture failed for $role.');
    }
    final uiFile = File('${proofDirectory.path}/$stem-ui.xml');
    final logFile = File('${proofDirectory.path}/$stem-logcat.txt');
    final screenshotFile = File('${proofDirectory.path}/$stem.png');
    await Future.wait<void>(<Future<void>>[
      uiFile.writeAsString(ui, flush: true),
      logFile.writeAsString(log, flush: true),
      screenshotFile.writeAsBytes(screenshot, flush: true),
    ]);
    return <AndroidProductionAudioCallArtifactDigest>[
      AndroidProductionAudioCallArtifactDigest(
        role: role,
        kind: '${stage}UiDump',
        sha256Digest: sha256.convert(await uiFile.readAsBytes()).toString(),
        bounded: true,
        redacted: true,
      ),
      AndroidProductionAudioCallArtifactDigest(
        role: role,
        kind: '${stage}Logcat',
        sha256Digest: sha256.convert(await logFile.readAsBytes()).toString(),
        bounded: true,
        redacted: true,
      ),
      AndroidProductionAudioCallArtifactDigest(
        role: role,
        kind: '${stage}Screenshot',
        sha256Digest: sha256
            .convert(await screenshotFile.readAsBytes())
            .toString(),
        bounded: true,
        redacted: false,
      ),
    ];
  }

  Future<List<int>> _screenshot(String deviceId) async {
    final process = await Process.start('adb', <String>[
      '-s',
      deviceId,
      'exec-out',
      'screencap',
      '-p',
    ], runInShell: false);
    final outputFuture = process.stdout.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) {
        if (builder.length + chunk.length > _maximumScreenshotBytes) {
          throw StateError('Android screenshot exceeds its byte bound.');
        }
        builder.add(chunk);
        return builder;
      },
    );
    final stderrDone = process.stderr.drain<void>();
    try {
      final output = await Future.wait<Object?>(<Future<Object?>>[
        process.exitCode,
        outputFuture,
        stderrDone,
      ]).timeout(const Duration(seconds: 20));
      final code = output[0]! as int;
      if (code != 0) {
        throw StateError('screencap failed with exit code $code');
      }
      return (output[1]! as BytesBuilder).takeBytes();
    } on Object {
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on Object {
        // The bounded capture failure remains authoritative.
      }
      rethrow;
    }
  }

  Future<String> _uiDump(String deviceId) {
    final pending = _pendingUiDumps[deviceId];
    if (pending != null) return pending;
    // Android permits one UiAutomation connection. Concurrent assertions on
    // the same phone share a capture instead of disconnecting one another.
    late final Future<String> capture;
    capture = _readUiDump(deviceId).whenComplete(() {
      if (identical(_pendingUiDumps[deviceId], capture)) {
        _pendingUiDumps.remove(deviceId);
      }
    });
    _pendingUiDumps[deviceId] = capture;
    return capture;
  }

  Future<String> _readUiDump(String deviceId) async {
    final remote = '/data/local/tmp/plan399-${_token('ui')}.xml';
    try {
      final dump = await _adbShell(deviceId, <String>[
        'uiautomator',
        'dump',
        remote,
      ], allowFailure: true);
      if (!dump.contains('dumped to') && !dump.contains('UI hierchary')) {
        // Some Android releases write the success marker to stderr; the cat
        // below remains the authoritative check.
      }
      final result = await _run('adb', <String>[
        '-s',
        deviceId,
        'exec-out',
        'cat',
        remote,
      ], allowFailure: true);
      final xml = '${result.stdout}';
      final hierarchy = xml.trim().replaceFirst(
        RegExp(r'^<\?xml[^>]*\?>\s*'),
        '',
      );
      final completeHierarchy =
          RegExp(r'^<hierarchy(?:\s[^>]*)?/>$').hasMatch(hierarchy) ||
          ((hierarchy.startsWith('<hierarchy>') ||
                  hierarchy.startsWith('<hierarchy ')) &&
              hierarchy.endsWith('</hierarchy>'));
      if (result.exitCode != 0 ||
          !completeHierarchy ||
          utf8.encode(xml).length > _maximumUiDumpBytes) {
        // exec-out may report a missing file as stdout with exitCode == 0.
        // Shell error text is neither an empty UI nor proof that a node is absent.
        throw const _UiHierarchyUnavailable();
      }
      return xml;
    } finally {
      await _adbShell(deviceId, <String>[
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
    }
  }

  Future<void> _launch(String deviceId) async {
    await _adbShell(deviceId, <String>['am', 'force-stop', packageName]);
    await _adbShellWithTimeout(deviceId, <String>[
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/com.mknoon.app.MainActivity',
    ], timeout: _coldAppLaunchTimeout);
  }

  Future<void> _foreground(String deviceId) async {
    _requireExpectedDevice(deviceId);
    await _adbShell(deviceId, <String>[
      'am',
      'start',
      '-W',
      '--activity-reorder-to-front',
      '-n',
      '$packageName/com.mknoon.app.MainActivity',
    ]);
  }

  Future<void> _grant(String deviceId, String permission) async {
    await _adbShell(deviceId, <String>[
      'pm',
      'grant',
      packageName,
      permission,
    ], allowFailure: true);
  }

  Future<String> _waitForAppFile(
    String deviceId,
    String name, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await _readAppFile(deviceId, name);
      if (value != null && value.trim().isNotEmpty) return value;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('$name timed out on Android target.');
  }

  Future<String?> _readAppFile(String deviceId, String name) async {
    final result = await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'run-as',
      packageName,
      'cat',
      'app_flutter/$name',
    ], allowFailure: true);
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}';
  }

  Future<void> _deleteAppFile(String deviceId, String name) async {
    await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'run-as',
      packageName,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFailure: true);
  }

  Future<void> _writeAppFile(
    String deviceId,
    String name,
    String content,
  ) async {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final local = File(
      '${Directory.systemTemp.path}/plan399-$safeName-${_token('cfg')}',
    );
    final remote = '/data/local/tmp/plan399-$safeName-${_token('cfg')}';
    try {
      await local.writeAsString(content, flush: true);
      final push = await _run('adb', <String>[
        '-s',
        deviceId,
        'push',
        local.path,
        remote,
      ]);
      if (push.exitCode != 0) throw StateError('Config staging failed.');
      await _adbShell(deviceId, <String>[
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adbShell(deviceId, <String>[
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$safeName',
      ]);
    } finally {
      await _adbShell(deviceId, <String>[
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
      if (await local.exists()) await local.delete();
    }
  }

  Future<String> _adbShell(
    String deviceId,
    List<String> command, {
    bool allowFailure = false,
  }) async {
    final result = await _run('adb', <String>[
      '-s',
      deviceId,
      'shell',
      ...command,
    ], allowFailure: allowFailure);
    if (!allowFailure && result.exitCode != 0) {
      throw StateError('Android command failed on explicit target.');
    }
    return '${result.stdout}';
  }

  Future<String> _adbShellWithTimeout(
    String deviceId,
    List<String> command, {
    required Duration timeout,
    bool allowFailure = false,
  }) async {
    final result = await _runWithTimeout(
      'adb',
      <String>['-s', deviceId, 'shell', ...command],
      timeout: timeout,
      allowFailure: allowFailure,
    );
    if (!allowFailure && result.exitCode != 0) {
      throw StateError('Android command failed on explicit target.');
    }
    return '${result.stdout}';
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final result = await _runner.run(executable, arguments);
    if (!allowFailure && result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments.take(4).toList(growable: false),
        'Production audio-call host command failed.',
        result.exitCode,
      );
    }
    return result;
  }

  Future<ProcessResult> _runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    bool allowFailure = false,
  }) async {
    final runner = _runner;
    final result = runner is AndroidHostProcessRunnerWithTimeout
        ? await runner.runWithTimeout(executable, arguments, timeout: timeout)
        : await runner.run(executable, arguments);
    if (!allowFailure && result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments.take(4).toList(growable: false),
        'Production audio-call host command failed.',
        result.exitCode,
      );
    }
    return result;
  }

  void _requireExpectedDevice(String deviceId) {
    if (deviceId != physicalDeviceId && deviceId != emulatorDeviceId) {
      throw FormatException('Unexpected Android target "$deviceId".');
    }
  }

  String _token(String prefix) {
    final suffix = List<int>.generate(
      8,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}

bool androidProductionAudioCallNativeStateReleased(
  String telecomDump, {
  required String packageName,
}) {
  if (utf8.encode(telecomDump).length > _maximumTelecomDumpBytes ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_.]+$').hasMatch(packageName)) {
    return false;
  }
  final lines = telecomDump.split('\n');
  final callHeader = RegExp(
    r'^\s*Call\s+[A-Za-z0-9@#._-]+\s*:\s*$',
    caseSensitive: false,
  );
  final stateLine = RegExp(
    r'^\s*(?:mState|state|callState)\s*[:=]\s*(?:STATE_)?([A-Z][A-Z0-9_]*)\b',
    caseSensitive: false,
  );
  const liveStates = <String>{
    'NEW',
    'DIALING',
    'CONNECTING',
    'RINGING',
    'ACTIVE',
    'HOLDING',
    'ON_HOLD',
    'SELECT_PHONE_ACCOUNT',
    'ANSWERED',
    'PULLING',
    'PULLING_CALL',
    'AUDIO_PROCESSING',
    'SIMULATED_RINGING',
    'DISCONNECTING',
  };
  const terminalStates = <String>{'DISCONNECTED', 'ABORTED'};

  bool ownedCallIsReleased(List<String> block) {
    if (!block.any((line) => line.contains(packageName))) return true;
    final states = <String>[
      for (final line in block)
        if (stateLine.firstMatch(line) case final match?)
          match.group(1)!.toUpperCase(),
    ];
    if (states.isEmpty) return false;
    if (states.any(liveStates.contains)) return false;
    return states.every(terminalStates.contains);
  }

  final starts = <int>[
    for (var index = 0; index < lines.length; index += 1)
      if (callHeader.hasMatch(lines[index])) index,
  ];
  if (starts.isEmpty) {
    if (!lines.any((line) => line.contains(packageName))) return true;
    final hasCallState = lines.any(stateLine.hasMatch);
    return !hasCallState || ownedCallIsReleased(lines);
  }
  for (var blockIndex = 0; blockIndex < starts.length; blockIndex += 1) {
    final start = starts[blockIndex];
    final end = blockIndex + 1 < starts.length
        ? starts[blockIndex + 1]
        : lines.length;
    if (end - start > _maximumTelecomCallBlockLines) return false;
    final block = lines.sublist(start, end);
    if (!ownedCallIsReleased(block)) return false;
  }
  return true;
}

bool _isReadOnlyPlatformPackagePath(String value) {
  if (!value.startsWith('package:/')) return false;
  final path = value.substring('package:'.length);
  return const <String>[
    '/system/',
    '/system_ext/',
    '/product/',
    '/vendor/',
    '/apex/',
  ].any(path.startsWith);
}

void _validateIdentity(AndroidProductionAudioCallIdentity identity) {
  if (identity.username.trim().isEmpty ||
      identity.peerId.trim().isEmpty ||
      identity.qrPayload.trim().isEmpty ||
      identity.mlKemPublicKey.trim().isEmpty) {
    throw const FormatException('Production audio-call identity is invalid.');
  }
}

void _validateObserverOperationReceipt(
  Map<String, Object?> receipt, {
  required String role,
  required String operation,
  required String runId,
  required String nonce,
  required String profileSha256,
  required String apkSha256,
  bool requireBidirectionalAudioRtp = true,
}) {
  const keys = <String>{
    'schema',
    'scenario',
    'buildProfile',
    'role',
    'operation',
    'stepId',
    'runId',
    'nonce',
    'profileSha256',
    'apkSha256',
    'callBindingSha256',
    'status',
    'success',
    'stateSequence',
    'outgoingObserved',
    'ringingObserved',
    'acceptedObserved',
    'connectedObserved',
    'terminalObserved',
    'activeCallSurfaceObserved',
    'structuralMediaReadyObserved',
    'relayOnlyObserved',
    'selectedRelayTransport',
    'localAudioEnabledObserved',
    'inboundAudioRtpObserved',
    'outboundAudioRtpObserved',
    'wakeAuthorityReady',
    'containsPrivateMaterial',
  };
  final expectedStatus = switch (operation) {
    androidProductionAudioCallArmOperation => 'armed',
    androidProductionAudioCallSampleOperation => 'observing',
    androidProductionAudioCallStopOperation => 'complete',
    androidProductionAudioCallReadinessOperation => 'ready',
    _ => null,
  };
  if (receipt.keys.toSet().length != keys.length ||
      !receipt.keys.toSet().containsAll(keys) ||
      receipt['schema'] != androidProductionAudioCallObservationResultSchema ||
      receipt['scenario'] != androidProductionAudioCallScenarioId ||
      receipt['buildProfile'] != androidProductionAudioCallProfileId ||
      receipt['role'] != role ||
      receipt['operation'] != operation ||
      receipt['stepId'] != 'production-call-$role-$operation-$runId' ||
      receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['profileSha256'] != profileSha256 ||
      receipt['apkSha256'] != apkSha256 ||
      receipt['status'] != expectedStatus ||
      receipt['success'] != true ||
      receipt['containsPrivateMaterial'] != false) {
    throw FormatException('Observer $role/$operation receipt is invalid.');
  }
  if (operation == androidProductionAudioCallArmOperation) {
    if (receipt['callBindingSha256'] != null ||
        !_sameSequence(receipt['stateSequence'], const <String>[]) ||
        receipt['outgoingObserved'] != false ||
        receipt['ringingObserved'] != false ||
        receipt['acceptedObserved'] != false ||
        receipt['connectedObserved'] != false ||
        receipt['terminalObserved'] != false ||
        receipt['activeCallSurfaceObserved'] != false ||
        receipt['structuralMediaReadyObserved'] != false ||
        receipt['relayOnlyObserved'] != false ||
        receipt['selectedRelayTransport'] != 'unknown' ||
        receipt['localAudioEnabledObserved'] != false ||
        receipt['inboundAudioRtpObserved'] != false ||
        receipt['outboundAudioRtpObserved'] != false) {
      throw FormatException('Observer $role did not arm from an empty state.');
    }
    if (receipt['wakeAuthorityReady'] != false) {
      throw FormatException('Observer $role arm receipt leaked readiness.');
    }
    return;
  }
  if (operation == androidProductionAudioCallReadinessOperation) {
    if (receipt['callBindingSha256'] != null ||
        !_sameSequence(receipt['stateSequence'], const <String>[]) ||
        receipt['outgoingObserved'] != false ||
        receipt['ringingObserved'] != false ||
        receipt['acceptedObserved'] != false ||
        receipt['connectedObserved'] != false ||
        receipt['terminalObserved'] != false ||
        receipt['activeCallSurfaceObserved'] != false ||
        receipt['structuralMediaReadyObserved'] != false ||
        receipt['relayOnlyObserved'] != false ||
        receipt['selectedRelayTransport'] != 'unknown' ||
        receipt['localAudioEnabledObserved'] != false ||
        receipt['inboundAudioRtpObserved'] != false ||
        receipt['outboundAudioRtpObserved'] != false ||
        receipt['wakeAuthorityReady'] != true) {
      throw FormatException('Observer $role readiness proof is incomplete.');
    }
    return;
  }
  final expectedSequence = role == androidProductionAudioCallCallerRole
      ? <String>['outgoing', 'ringing', 'accepted', 'connected']
      : <String>['ringing', 'accepted', 'connected'];
  if (operation == androidProductionAudioCallStopOperation) {
    expectedSequence.add('terminal');
  }
  if (!_isSha256(receipt['callBindingSha256']) ||
      !_sameSequence(receipt['stateSequence'], expectedSequence) ||
      receipt['outgoingObserved'] !=
          (role == androidProductionAudioCallCallerRole) ||
      receipt['ringingObserved'] != true ||
      receipt['acceptedObserved'] != true ||
      receipt['connectedObserved'] != true ||
      receipt['terminalObserved'] !=
          (operation == androidProductionAudioCallStopOperation) ||
      receipt['activeCallSurfaceObserved'] != true ||
      receipt['structuralMediaReadyObserved'] != true ||
      receipt['relayOnlyObserved'] != true ||
      receipt['selectedRelayTransport'] != 'turn_udp' ||
      receipt['localAudioEnabledObserved'] != true ||
      receipt['inboundAudioRtpObserved'] is! bool ||
      receipt['outboundAudioRtpObserved'] is! bool ||
      (requireBidirectionalAudioRtp &&
          (receipt['inboundAudioRtpObserved'] != true ||
              receipt['outboundAudioRtpObserved'] != true)) ||
      receipt['wakeAuthorityReady'] != false) {
    throw FormatException('Observer $role/$operation proof is incomplete.');
  }
}

Future<Map<String, Object?>> _waitForBidirectionalAudioRtp({
  required AndroidProductionAudioCallCampaignDriver driver,
  required String deviceId,
  required String role,
  required String runId,
  required String nonce,
  required String profileSha256,
  required String apkSha256,
  required Duration timeout,
  required Duration pollInterval,
}) async {
  if (timeout.isNegative || pollInterval.isNegative) {
    throw ArgumentError('RTP observation bounds cannot be negative.');
  }
  final elapsed = Stopwatch()..start();
  while (true) {
    final receipt = await driver.observe(
      deviceId: deviceId,
      role: role,
      operation: androidProductionAudioCallSampleOperation,
      runId: runId,
      nonce: nonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
    );
    _validateObserverOperationReceipt(
      receipt,
      role: role,
      operation: androidProductionAudioCallSampleOperation,
      runId: runId,
      nonce: nonce,
      profileSha256: profileSha256,
      apkSha256: apkSha256,
      requireBidirectionalAudioRtp: false,
    );
    if (receipt['inboundAudioRtpObserved'] == true &&
        receipt['outboundAudioRtpObserved'] == true) {
      return receipt;
    }
    if (elapsed.elapsed >= timeout) {
      throw TimeoutException(
        'Production $role did not observe bidirectional audio RTP within '
        'the bounded campaign window.',
        timeout,
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

List<AndroidProductionAudioCallSemanticNode> _exactSemanticNodes(
  String xml, {
  required String label,
  required bool requireClickable,
  required Set<String> allowedPackages,
  bool allowExactText = false,
}) {
  final matches = <AndroidProductionAudioCallSemanticNode>[];
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = match.group(0)!;
    final packageName = _xmlDecode(_attribute(raw, 'package'));
    final contentDescription = _xmlDecode(_attribute(raw, 'content-desc'));
    final text = _xmlDecode(_attribute(raw, 'text'));
    if ((contentDescription != label && (!allowExactText || text != label)) ||
        !allowedPackages.contains(packageName) ||
        _attribute(raw, 'enabled') != 'true' ||
        _attribute(raw, 'visible-to-user') == 'false' ||
        (requireClickable && _attribute(raw, 'clickable') != 'true')) {
      continue;
    }
    final bounds = RegExp(
      r'bounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"',
    ).firstMatch(raw);
    if (bounds == null) continue;
    final left = int.parse(bounds.group(1)!);
    final top = int.parse(bounds.group(2)!);
    final right = int.parse(bounds.group(3)!);
    final bottom = int.parse(bounds.group(4)!);
    if (left < 0 || top < 0 || right <= left || bottom <= top) continue;
    matches.add(
      AndroidProductionAudioCallSemanticNode(
        label: label,
        packageName: packageName,
        centerX: (left + right) ~/ 2,
        centerY: (top + bottom) ~/ 2,
      ),
    );
  }
  return List<AndroidProductionAudioCallSemanticNode>.unmodifiable(matches);
}

AndroidProductionAudioCallStartDispatchSurface? _classifyStartDispatchSurface(
  String xml, {
  required Set<String> allowedPackages,
}) {
  const failureLabel = "Couldn't start voice call. Please try again.";
  final failures = _exactSemanticMarkerCount(
    xml,
    label: failureLabel,
    allowedPackages: allowedPackages,
  );
  final cancels = _exactSemanticMarkerCount(
    xml,
    label: 'Cancel call',
    allowedPackages: allowedPackages,
  );
  final starting = _exactSemanticMarkerCount(
    xml,
    label: 'Starting voice call',
    allowedPackages: allowedPackages,
  );
  if (failures > 1 || cancels > 1 || starting > 1) {
    throw const AndroidProductionAudioCallSelectorException(
      'Start-dispatch acknowledgement surface is ambiguous.',
    );
  }
  if (failures == 1) {
    return AndroidProductionAudioCallStartDispatchSurface.failure;
  }
  if (cancels == 1) {
    return AndroidProductionAudioCallStartDispatchSurface.cancel;
  }
  if (starting == 1) {
    return AndroidProductionAudioCallStartDispatchSurface.starting;
  }
  return null;
}

int _exactSemanticMarkerCount(
  String xml, {
  required String label,
  required Set<String> allowedPackages,
}) {
  var count = 0;
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = match.group(0)!;
    final packageName = _xmlDecode(_attribute(raw, 'package'));
    final contentDescription = _xmlDecode(_attribute(raw, 'content-desc'));
    final text = _xmlDecode(_attribute(raw, 'text'));
    if ((contentDescription == label || text == label) &&
        allowedPackages.contains(packageName) &&
        _attribute(raw, 'visible-to-user') != 'false') {
      count += 1;
    }
  }
  return count;
}

String _attribute(String node, String name) =>
    RegExp('${RegExp.escape(name)}="([^"]*)"').firstMatch(node)?.group(1) ?? '';

String _xmlDecode(String value) => value
    .replaceAll('&#10;', '\n')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

bool _sameSequence(Object? value, List<String> expected) {
  if (value is! List || value.length != expected.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (value[index] != expected[index]) return false;
  }
  return true;
}

/// Returns a bounded diagnostic with private call/network material removed.
///
/// Whole SDP, ICE-candidate, and media-counter lines are discarded before
/// token-level redaction. A post-sanitization residue scan fails closed so a
/// diagnostic is never written or hashed while a known private form remains.
String sanitizeAndroidProductionAudioCallDiagnosticText(String value) {
  var redacted = value
      .replaceAll(RegExp(r'>\s*<'), '>\n<')
      .split('\n')
      .map(
        (line) => _privateDiagnosticLine.hasMatch(line)
            ? '<redacted-private-line>'
            : line,
      )
      .join('\n')
      .replaceAll(
        RegExp(r'(?:turn|turns):[^\s,\]\"]+', caseSensitive: false),
        '<turn-url>',
      )
      .replaceAll(
        RegExp(r'/ip4/[^/\s]+/(?:tcp|udp)/\d+(?:/p2p/[^/\s]+)?'),
        '<multiaddr>',
      )
      .replaceAll(RegExp(r'12D3KooW[A-Za-z0-9]+'), '<peer>')
      .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '<ip>')
      .replaceAll(
        RegExp(r'(?:[0-9a-f]{0,4}:){2,}[0-9a-f:]{0,39}', caseSensitive: false),
        '<ip>',
      )
      .replaceAll(
        RegExp(
          r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
          caseSensitive: false,
        ),
        '<uuid>',
      )
      .replaceAll(
        RegExp(
          r'"?(?:call[_-]?id|nonce|credential|password|secret|bearer|port)"?\s*[:=]\s*"?[^"\s,}]+"?',
          caseSensitive: false,
        ),
        '<redacted>',
      )
      .replaceAll(RegExp(r':\d{2,5}\b'), ':<port>');
  final bytes = utf8.encode(redacted);
  if (bytes.length > _maximumSavedTextBytes) {
    redacted =
        '${utf8.decode(bytes.take(_maximumSavedTextBytes).toList(growable: false), allowMalformed: true)}\n<truncated>\n';
  }
  if (_containsForbiddenDiagnosticResidue(redacted)) {
    throw const FormatException(
      'Diagnostic sanitization retained forbidden private material.',
    );
  }
  return redacted;
}

final RegExp _privateDiagnosticLine = RegExp(
  r'(?:^\s*(?:v=0|o=|s=-|t=|m=(?:audio|video|application)\b|c=IN\s+IP[46]\b)|\ba=[A-Za-z][A-Za-z0-9-]*\b|\bcandidate\b(?:\s+|\s*[:=])|\b(?:ice[_-]?(?:ufrag|pwd)|sdp|sessionDescription)\b\s*[:=]|\b(?:call[_-]?id|nonce|credential|password|secret|bearer)\b|\b(?:ssrc|track[_-]?(?:identifier|id)|report[_-]?id|remote[_-]?id|codec[_-]?id|mid|rid)\b\s*[:=]|\b(?:packets|bytes|frames|samples|concealedSamples|jitter|roundTripTime|bitrate|audioLevel|totalAudioEnergy)[A-Za-z0-9_]*\b)',
  caseSensitive: false,
);

bool _containsForbiddenDiagnosticResidue(String value) => <RegExp>[
  _privateDiagnosticLine,
  RegExp(r'(?:turn|turns):', caseSensitive: false),
  RegExp(r'/ip[46]/', caseSensitive: false),
  RegExp(r'12D3KooW[A-Za-z0-9]+'),
  RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
  RegExp(r'(?:[0-9a-f]{0,4}:){2,}[0-9a-f:]{0,39}', caseSensitive: false),
  RegExp(
    r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
    caseSensitive: false,
  ),
  RegExp(
    r'"?(?:call[_-]?id|nonce|credential|password|secret|bearer|port)"?\s*[:=]',
    caseSensitive: false,
  ),
  RegExp(r':\d{2,5}\b'),
].any((pattern) => pattern.hasMatch(value));

bool androidProductionAudioCallIsPrivateIpv4(String value) {
  final octets = value.split('.').map(int.tryParse).toList(growable: false);
  if (octets.length != 4 || octets.any((part) => part == null)) return false;
  final values = octets.cast<int>();
  if (values.any((part) => part < 0 || part > 255)) return false;
  return values[0] == 10 ||
      (values[0] == 172 && values[1] >= 16 && values[1] <= 31) ||
      (values[0] == 192 && values[1] == 168);
}

final class _LocalRelayBinding {
  const _LocalRelayBinding({
    required this.host,
    required this.port,
    required this.fixtureIdentitySha256,
    required this.turnAuthoritySha256,
    required this.coturnInstanceIdentitySha256,
  });

  factory _LocalRelayBinding.fromEnvironment(Map<String, String> environment) {
    final relay = environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
    final fixtureIdentity =
        environment[_fixtureIdentityEnvironment]?.trim() ?? '';
    final turnAuthority =
        environment[_turnAuthorityDigestEnvironment]?.trim() ?? '';
    final coturnInstance =
        environment[_coturnInstanceDigestEnvironment]?.trim() ?? '';
    final match = RegExp(
      r'^/ip4/([^/]+)/tcp/([1-9][0-9]*)/p2p/[A-Za-z0-9]+$',
    ).firstMatch(relay);
    final port = match == null ? null : int.tryParse(match.group(2)!);
    final host = match?.group(1) ?? '';
    if (match == null ||
        port == null ||
        port > 65535 ||
        !androidProductionAudioCallIsPrivateIpv4(host) ||
        !_isSha256(fixtureIdentity) ||
        !_isSha256(turnAuthority) ||
        !_isSha256(coturnInstance)) {
      throw const FormatException(
        'Production audio-call fast path requires one attested disposable '
        'RFC1918 libp2p relay; remote/EC2 relays are rejected.',
      );
    }
    return _LocalRelayBinding(
      host: host,
      port: port,
      fixtureIdentitySha256: fixtureIdentity,
      turnAuthoritySha256: turnAuthority,
      coturnInstanceIdentitySha256: coturnInstance,
    );
  }

  final String host;
  final int port;
  final String fixtureIdentitySha256;
  final String turnAuthoritySha256;
  final String coturnInstanceIdentitySha256;
}

final class _SecureTokens {
  final Random _random = Random.secure();

  String next(String prefix) {
    final suffix = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  return configured == null || configured.isEmpty
      ? Directory(
          'build/sims/proofs/$androidProductionAudioCallScenarioId',
        ).absolute
      : Directory(configured).absolute;
}

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
    FileSystemEntityType.file;

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();
