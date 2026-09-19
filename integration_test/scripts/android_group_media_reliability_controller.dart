import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/debug/group_media_reliability_authority_target.dart';

import 'group_media_reliability_criteria.dart';
import 'group_media_reliability_runner_contract.dart';
import '../support/android_app_state_guard.dart';
import '../support/group_media_android_disposable_app.dart';

String _closedGroupMediaWaitPhase(Object? phase) =>
    const {
      'identity_sender',
      'identity_receiver',
      'contacts_sender',
      'contacts_receiver',
      'identity_probe',
      'sender_setup',
      'receiver_accept_arm',
      'sender_authority_refresh',
      'receiver_authority_ready',
      'sender_send',
      'receiver_barrier',
      'receiver_recover',
      'receiver_render_probe',
      'sender_probe',
    }.contains(phase)
    ? phase! as String
    : 'unknown';

String groupMediaWaitTimeoutCode(Object? phase) =>
    'group_wait_${_closedGroupMediaWaitPhase(phase)}_timeout';

/// Retains only closed observations already read for this exact wait. No new
/// endpoint reads or IDs, SQL rows, paths, or exception text enter the receipt.
Future<void> retainAndroidGroupMediaWaitTimeout({
  required Directory directory,
  required String phase,
  required bool senderSendCompleted,
  Map<String, Object?> observation = const {},
}) async {
  final receipt = <String, Object?>{
    'schema': 'mknoon.group-media-wait-timeout.v1',
    'waitStage': _closedGroupMediaWaitPhase(phase),
    'cause': 'timeout',
    'errorCode': groupMediaWaitTimeoutCode(phase),
    'senderSendCompleted': senderSendCompleted,
    for (final key in const [
      'matchingEndpointObserved',
      'matchedBarrierState',
      'barrierReached',
      'recoveryReleased',
      'barrierProcessObserved',
    ])
      if (observation[key] is bool) key: observation[key],
    if (const {
      'complete',
      'armed',
      'pending',
      'running',
      'failed',
    }.contains(observation['endpointStatus']))
      'endpointStatus': observation['endpointStatus'],
    if (const {
      'receiver_jpeg_post_claim_pre_commit',
      'receiver_jpeg_strict_verified_ciphertext_pre_commit',
    }.contains(observation['barrierName']))
      'barrierName': observation['barrierName'],
    if (const {
      'pending',
      'downloading',
      'done',
      'failed',
      'upload_pending',
    }.contains(observation['barrierPriorStatus']))
      'barrierPriorStatus': observation['barrierPriorStatus'],
    for (final key in const [
      'barrierAttempt',
      'jpegAttempts',
      'mp4Attempts',
      'voiceAttempts',
    ])
      if (observation[key] is int &&
          (observation[key]! as int) >= 0 &&
          (observation[key]! as int) <= 100000)
        key: observation[key],
  };
  final bytes = utf8.encode(jsonEncode(receipt));
  final digest = sha256.convert(bytes).toString();
  final file = File('${directory.path}/wait-timeout-$digest.json');
  await file.parent.create(recursive: true);
  if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
}

/// The host wait loop is injectable for bounded diagnostics tests only.
Future<T> waitForAndroidGroupMediaValue<T>(
  String phase,
  Duration timeout,
  Future<T?> Function() read, {
  DateTime Function()? now,
  Future<void> Function(Duration)? pause,
  Future<void> Function()? onTimeout,
}) async {
  final clock = now ?? DateTime.now;
  final delay = pause ?? Future<void>.delayed;
  final deadline = clock().add(timeout);
  while (clock().isBefore(deadline)) {
    final value = await read();
    if (value != null) return value;
    await delay(const Duration(milliseconds: 200));
  }
  try {
    await onTimeout?.call();
  } on Object {
    // Evidence failure cannot replace the original bounded wait failure.
  }
  throw GroupMediaReliabilityScenarioFailure(groupMediaWaitTimeoutCode(phase));
}

final class AndroidGroupMediaProcessTransitionEvidence {
  const AndroidGroupMediaProcessTransitionEvidence({
    required this.oldPid,
    required this.freshPid,
    required this.oldPidGone,
    required this.launcherComponent,
    required this.relaunchedWithoutGroupRoute,
  });

  final String oldPid;
  final String freshPid;
  final bool oldPidGone;
  final String launcherComponent;
  final bool relaunchedWithoutGroupRoute;
}

/// Exact ADB owner for TC-269-19's receiver process-death boundary.
///
/// The launcher component is resolved before mutation. Relaunch uses only
/// `am start -W -n <launcher>`: no deep link, route, notification, or group ID
/// can accidentally open the conversation and trigger route-owned recovery.
final class AndroidGroupMediaProcessDeathController {
  const AndroidGroupMediaProcessDeathController({
    this.runner = const SystemAndroidHostProcessRunner(),
    this.pollInterval = const Duration(milliseconds: 100),
    this.maximumPolls = 50,
  });

  final AndroidHostProcessRunner runner;
  final Duration pollInterval;
  final int maximumPolls;

  Future<AndroidGroupMediaProcessTransitionEvidence> forceStopAndRelaunch({
    required String deviceId,
    required String packageName,
    Future<void> Function()? afterStoppedBeforeLaunch,
  }) async {
    _validateTarget(deviceId, packageName);
    if (maximumPolls <= 0 || pollInterval.isNegative) {
      throw ArgumentError('process polling bounds are invalid');
    }

    final launcher = await _resolveLauncher(deviceId, packageName);
    final oldPid = await _requireSinglePid(
      deviceId,
      packageName,
      context: 'before force-stop',
    );

    final stopped = await _adb(deviceId, <String>[
      'shell',
      'am',
      'force-stop',
      packageName,
    ]);
    if (stopped.exitCode != 0) {
      throw StateError('Android receiver force-stop failed');
    }
    final oldPidGone = await _pollPid(
      deviceId,
      packageName,
      predicate: (value) => value.isEmpty,
    );
    if (oldPidGone == null) {
      throw StateError('Android receiver PID survived force-stop');
    }

    if (afterStoppedBeforeLaunch != null) {
      await afterStoppedBeforeLaunch();
      final pidAfterStaging = await _readPid(deviceId, packageName);
      if (pidAfterStaging.isNotEmpty) {
        throw StateError(
          'Android process restarted while the stopped-window command was staged',
        );
      }
    }

    await _launchResolvedComponent(deviceId, launcher);
    final freshPid = await _pollPid(
      deviceId,
      packageName,
      predicate: (value) => value.isNotEmpty && value != oldPid,
    );
    if (freshPid == null) {
      throw StateError('Android receiver did not expose a fresh PID');
    }

    return AndroidGroupMediaProcessTransitionEvidence(
      oldPid: oldPid,
      freshPid: freshPid,
      oldPidGone: true,
      launcherComponent: launcher,
      relaunchedWithoutGroupRoute: true,
    );
  }

  /// Starts the package's validated launcher component without a deep link or
  /// group route and requires one unambiguous process to become observable.
  Future<String> launchValidatedLauncher({
    required String deviceId,
    required String packageName,
  }) async {
    _validateTarget(deviceId, packageName);
    final launcher = await _resolveLauncher(deviceId, packageName);
    await _launchResolvedComponent(deviceId, launcher);
    final launchedPid = await _pollPid(
      deviceId,
      packageName,
      predicate: (value) => value.isNotEmpty,
    );
    if (launchedPid == null) {
      throw StateError('Android launcher did not expose a process');
    }
    return launcher;
  }

  Future<void> _launchResolvedComponent(
    String deviceId,
    String launcher,
  ) async {
    final launched = await _adb(deviceId, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      launcher,
    ]);
    final output = '${launched.stdout}\n${launched.stderr}';
    final acceptedStatus =
        output.contains('Status: ok') || output.contains('Status: timeout');
    if (launched.exitCode != 0 ||
        output.contains('Error:') ||
        !acceptedStatus ||
        !output.contains(launcher)) {
      throw StateError('Android receiver launcher relaunch failed');
    }
  }

  Future<String> _resolveLauncher(String deviceId, String packageName) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '--user',
      '0',
      packageName,
    ]);
    final component = '${result.stdout}'.trim().split(RegExp(r'\s+')).last;
    final expected = RegExp(
      '^${RegExp.escape(packageName)}'
      r'/[A-Za-z0-9_.$]+$',
    );
    if (result.exitCode != 0 || !expected.hasMatch(component)) {
      throw StateError('Android launcher component could not be validated');
    }
    return component;
  }

  Future<String> _requireSinglePid(
    String deviceId,
    String packageName, {
    required String context,
  }) async {
    final value = await _readPid(deviceId, packageName);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw StateError('Android receiver has no single PID $context');
    }
    return value;
  }

  Future<String?> _pollPid(
    String deviceId,
    String packageName, {
    required bool Function(String value) predicate,
  }) async {
    for (var attempt = 0; attempt < maximumPolls; attempt++) {
      final value = await _readPid(deviceId, packageName);
      if (predicate(value)) return value;
      if (attempt + 1 < maximumPolls && pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
    }
    return null;
  }

  Future<String> _readPid(String deviceId, String packageName) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'pidof',
      packageName,
    ]);
    final value = '${result.stdout}'.trim();
    if (result.exitCode == 1 && value.isEmpty) return '';
    if (result.exitCode != 0 ||
        (value.isNotEmpty && !RegExp(r'^[1-9][0-9]*$').hasMatch(value))) {
      throw StateError('Android receiver PID probe was ambiguous');
    }
    return value;
  }

  Future<ProcessResult> _adb(String deviceId, List<String> arguments) =>
      runner.run('adb', <String>['-s', deviceId, ...arguments]);

  void _validateTarget(String deviceId, String packageName) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(deviceId) ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName)) {
      throw const FormatException('unsafe Android process target');
    }
  }
}

const String _commandSchema = 'mknoon.group-media-reliability-command.v1';
const String _endpointSchema = 'mknoon.group-media-reliability-endpoint.v1';
const String _stateSchema = 'mknoon.group-media-reliability-state.v1';
const String _transportAction = 'group_media_reliability_android';
const String _barrierName = 'receiver_jpeg_post_claim_pre_commit';
const Map<String, String> _renderLabelsByKind = <String, String>{
  'jpeg': 'P269 receiver JPEG decoded',
  'mp4': 'P269 receiver MP4 thumbnail decoded',
  'voice': 'P269 receiver voice player ready',
};
const Set<String> _renderFailureLabels = <String>{
  'Media unavailable',
  "Couldn't verify this media",
  'Retry unavailable media',
};

bool androidGroupMediaTargetIsInteractive({
  required String powerDump,
  required String windowPolicyDump,
}) {
  final awake =
      RegExp(r'\bmWakefulness=Awake\b').hasMatch(powerDump) ||
      RegExp(r'\bmInteractive=true\b').hasMatch(powerDump) ||
      RegExp(r'\bWakefulness:\s*Awake\b').hasMatch(powerDump);
  final locked = RegExp(
    r'\b(?:mShowingLockscreen|isStatusBarKeyguard|mInputRestricted|showing)\s*=\s*true\b',
  ).hasMatch(windowPolicyDump);
  final explicitUnlocked = RegExp(
    r'\b(?:mShowingLockscreen|isStatusBarKeyguard|mInputRestricted|showing)\s*=\s*false\b',
  ).hasMatch(windowPolicyDump);
  return awake && explicitUnlocked && !locked;
}

final class AndroidGroupMediaCommandSafetyEvidence {
  const AndroidGroupMediaCommandSafetyEvidence({
    required this.productionPackageCommands,
    required this.uninstallCommands,
    required this.pmClearCommands,
    required this.broadDeleteCommands,
  });

  final int productionPackageCommands;
  final int uninstallCommands;
  final int pmClearCommands;
  final int broadDeleteCommands;
}

/// Observes every host command in the TC19 boundary and rejects destructive or
/// production-package mutations before delegating them to ADB.
final class _AndroidGroupMediaSafetyAuditingRunner
    implements AndroidHostProcessRunner {
  _AndroidGroupMediaSafetyAuditingRunner(this.delegate);

  final AndroidHostProcessRunner delegate;
  var _productionPackageCommands = 0;
  var _uninstallCommands = 0;
  var _pmClearCommands = 0;
  var _broadDeleteCommands = 0;

  AndroidGroupMediaCommandSafetyEvidence get evidence =>
      AndroidGroupMediaCommandSafetyEvidence(
        productionPackageCommands: _productionPackageCommands,
        uninstallCommands: _uninstallCommands,
        pmClearCommands: _pmClearCommands,
        broadDeleteCommands: _broadDeleteCommands,
      );

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    if (executable == 'adb') {
      _observeAdb(arguments);
    }
    return delegate.run(executable, arguments);
  }

  void _observeAdb(List<String> arguments) {
    final command = arguments.length >= 2 && arguments.first == '-s'
        ? arguments.sublist(2)
        : arguments;
    if (groupMediaAndroidCommandTargetsProductionPackage(command)) {
      _productionPackageCommands += 1;
    }
    if (command.contains('uninstall')) {
      _uninstallCommands += 1;
    }
    if (_containsSequence(command, const <String>['shell', 'pm', 'clear'])) {
      _pmClearCommands += 1;
    }
    if (_isBroadDelete(command)) {
      _broadDeleteCommands += 1;
    }
    if (_productionPackageCommands != 0 ||
        _uninstallCommands != 0 ||
        _pmClearCommands != 0 ||
        _broadDeleteCommands != 0) {
      throw StateError(
        'TC19 rejected a production-package or destructive Android command.',
      );
    }
  }

  bool _containsSequence(List<String> values, List<String> sequence) {
    if (values.length < sequence.length) return false;
    for (var start = 0; start <= values.length - sequence.length; start += 1) {
      var matches = true;
      for (var offset = 0; offset < sequence.length; offset += 1) {
        if (values[start + offset] != sequence[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  bool _isBroadDelete(List<String> command) {
    final rmIndex = command.indexOf('rm');
    if (rmIndex < 0) return false;
    final operands = command.sublist(rmIndex + 1);
    if (operands.any(
      (value) =>
          value.startsWith('--recursive') ||
          (value.startsWith('-') &&
              !value.startsWith('--') &&
              (value.contains('r') || value.contains('R'))),
    )) {
      return true;
    }
    return operands.any(
      (value) =>
          value == '/' ||
          value == '.' ||
          value == 'app_flutter' ||
          value.endsWith('/app_flutter'),
    );
  }
}

const String _configFile = 'intro_e2e_config.json';
const String _resultFile = 'intro_e2e_result.json';
const String _identityFile = 'intro_e2e_identity.json';
const String _stateFile = 'group_media_reliability_state.json';

/// Executes TC-269-19 against the centrally prepared dedicated P269 APK.
///
/// The returned value is still in memory. The shared runner persists it only
/// after this function has restored both devices' exact pre-campaign state.
Future<Map<String, Object?>> executeAndroidGroupMediaReliabilityScenario(
  GroupMediaReliabilityRunContext context, {
  AndroidHostProcessRunner runner = const SystemAndroidHostProcessRunner(),
}) async {
  if (context.scenario != groupMediaForegroundRetryAclRoundtripScenario ||
      context.preparedArtifact.profile !=
          groupMediaReliabilityAndroidBuildProfile) {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'Android group-media controller received the wrong scenario/profile.',
    );
  }
  final sender = context.roles['sender'];
  final receiver = context.roles['receiver'];
  if (sender == null || receiver == null) {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'Android group-media controller requires sender and receiver roles.',
    );
  }
  final artifact = File(context.preparedArtifact.path).absolute;
  final expectedArtifactSha256 = context.preparedArtifact.sha256Digest;
  final currentDigest = artifact.existsSync()
      ? (await sha256.bind(artifact.openRead()).first).toString()
      : null;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedArtifactSha256) ||
      currentDigest != expectedArtifactSha256) {
    throw const GroupMediaReliabilityBlocked(
      'missingArtifact',
      'The prepared Android APK changed after runner custody validation.',
    );
  }

  const packageName = groupMediaReliabilityAndroidPackageName;
  if (packageName == 'com.mknoon.app') {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'The P269 Android proof cannot target the production package.',
    );
  }
  final auditedRunner = _AndroidGroupMediaSafetyAuditingRunner(runner);
  final host = _AndroidGroupMediaHost(
    context: context,
    artifact: artifact,
    packageName: packageName,
    senderDeviceId: sender.deviceId,
    receiverDeviceId: receiver.deviceId,
    runner: auditedRunner,
  );
  await host.verifyPrerequisites();
  return host.run();
}

final class _AndroidGroupMediaHost {
  _AndroidGroupMediaHost({
    required this.context,
    required this.artifact,
    required this.packageName,
    required this.senderDeviceId,
    required this.receiverDeviceId,
    required this.runner,
  }) : processController = AndroidGroupMediaProcessDeathController(
         runner: runner,
       );

  final GroupMediaReliabilityRunContext context;
  final File artifact;
  final String packageName;
  final String senderDeviceId;
  final String receiverDeviceId;
  final _AndroidGroupMediaSafetyAuditingRunner runner;
  final AndroidGroupMediaProcessDeathController processController;
  bool _senderSendCompleted = false;

  Future<void> verifyPrerequisites() async {
    late final ProcessResult version;
    late final ProcessResult attached;
    try {
      version = await runner.run('adb', const <String>['version']);
      attached = await runner.run('adb', const <String>['devices', '-l']);
    } on ProcessException catch (error) {
      throw GroupMediaReliabilityBlocked(
        'missingDriver',
        'ADB is unavailable: ${error.message}',
      );
    }
    if (version.exitCode != 0 || attached.exitCode != 0) {
      throw const GroupMediaReliabilityBlocked(
        'missingDriver',
        'ADB prerequisite probing failed.',
      );
    }

    final rows = <List<String>>[];
    for (final line in '${attached.stdout}'.split('\n').skip(1)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length >= 2) rows.add(fields);
    }
    final senderRows = rows
        .where((fields) => fields.first == senderDeviceId)
        .toList(growable: false);
    final receiverRows = rows
        .where((fields) => fields.first == receiverDeviceId)
        .toList(growable: false);
    if (senderDeviceId == receiverDeviceId ||
        senderRows.length != 1 ||
        receiverRows.length != 1) {
      throw const GroupMediaReliabilityBlocked(
        'targetUnavailable',
        'Each explicit Android role must have exactly one inventory row.',
      );
    }
    final senderFields = senderRows.single;
    final receiverFields = receiverRows.single;
    if (senderFields[1] != 'device' || receiverFields[1] != 'device') {
      throw const GroupMediaReliabilityBlocked(
        'targetUnavailable',
        'Both explicit Android targets must be attached in device state.',
      );
    }
    if (!senderFields
        .skip(2)
        .any((field) => field.startsWith('usb:') && field.length > 4)) {
      throw const GroupMediaReliabilityBlocked(
        'targetUnavailable',
        'The Android sender must be an attached USB physical device.',
      );
    }
    final senderQemu = await _shellText(senderDeviceId, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ], preMutation: true);
    final receiverQemu = await _shellText(receiverDeviceId, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ], preMutation: true);
    const physicalQemuValues = <String>{'', '0'};
    if (!physicalQemuValues.contains(senderQemu.trim()) ||
        receiverQemu.trim() != '1') {
      throw const GroupMediaReliabilityBlocked(
        'targetUnavailable',
        'Android roles must be USB physical sender then emulator receiver.',
      );
    }
    for (final deviceId in <String>[senderDeviceId, receiverDeviceId]) {
      final state = await Future.wait(<Future<String>>[
        _shellText(deviceId, const <String>[
          'dumpsys',
          'power',
        ], preMutation: true),
        _shellText(deviceId, const <String>[
          'dumpsys',
          'window',
          'policy',
        ], preMutation: true),
      ]);
      if (!androidGroupMediaTargetIsInteractive(
        powerDump: state[0],
        windowPolicyDump: state[1],
      )) {
        throw const GroupMediaReliabilityBlocked(
          'targetUnavailable',
          'Both Android targets must be awake and unlocked before mutation.',
        );
      }
    }
  }

  Future<Map<String, Object?>> run() async {
    final resetRoot = Directory(
      '${context.proofDirectory.absolute.path}${Platform.pathSeparator}'
      '.android-disposable-${_shortDigest(context.runId)}',
    );
    final roleByDeviceId = <String, String>{
      senderDeviceId: 'sender',
      receiverDeviceId: 'receiver',
    };
    final apps = <GroupMediaAndroidDisposableApp>[];
    final touched = <GroupMediaAndroidDisposableApp>{};
    for (final deviceId in <String>[senderDeviceId, receiverDeviceId]) {
      late final GroupMediaAndroidDisposableApp app;
      app = GroupMediaAndroidDisposableApp(
        deviceId: deviceId,
        artifact: artifact,
        expectedArtifactSha256: context.preparedArtifact.sha256Digest,
        runId: context.runId,
        workDirectory: resetRoot,
        runner: runner,
        onMutationStarted: () => touched.add(app),
      );
      apps.add(app);
    }
    final preResetReceipts =
        <String, GroupMediaAndroidDisposableResetReceipt>{};
    final postResetReceipts =
        <String, GroupMediaAndroidDisposableResetReceipt>{};
    Map<String, Object?> Function(
      Map<String, GroupMediaAndroidDisposableResetReceipt> preResetReceipts,
      Map<String, GroupMediaAndroidDisposableResetReceipt> postResetReceipts,
    )?
    aggregateAfterCleanup;
    Object? primaryError;
    StackTrace? primaryStackTrace;
    try {
      for (final app in apps) {
        await app.installPreparedArtifact();
        final receipt = await app.reset('pre');
        preResetReceipts[roleByDeviceId[app.deviceId]!] = receipt;
      }
      await _prepareRole(
        senderDeviceId,
        'P269Sender${_shortDigest('${context.runId}:sender')}',
      );
      await _prepareRole(
        receiverDeviceId,
        'P269Receiver${_shortDigest('${context.runId}:receiver')}',
      );
      await _requirePreparedArtifactCustody('before launcher start');
      await Future.wait(<Future<String>>[
        processController.launchValidatedLauncher(
          deviceId: senderDeviceId,
          packageName: packageName,
        ),
        processController.launchValidatedLauncher(
          deviceId: receiverDeviceId,
          packageName: packageName,
        ),
      ]);

      final messageIds = <String, String>{
        for (final kind in const <String>['jpeg', 'mp4', 'voice'])
          kind: 'message-$kind-${_shortDigest('${context.runId}:m:$kind')}',
      };
      final attachmentIds = <String, String>{
        for (final kind in const <String>['jpeg', 'mp4', 'voice'])
          kind: 'blob-$kind-${_shortDigest('${context.runId}:b:$kind')}',
      };
      final identities = await Future.wait(<Future<_AndroidIdentity>>[
        _waitForIdentity(
          senderDeviceId,
          role: 'sender',
          messageIds: messageIds,
          attachmentIds: attachmentIds,
        ),
        _waitForIdentity(
          receiverDeviceId,
          role: 'receiver',
          messageIds: messageIds,
          attachmentIds: attachmentIds,
        ),
      ]);
      final senderIdentity = identities[0];
      final receiverIdentity = identities[1];
      await _establishContacts(senderIdentity, receiverIdentity);

      final senderSetup = await _runGroupPhase(
        deviceId: senderDeviceId,
        phase: 'sender_setup',
        role: 'sender',
        groupId: '',
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverIdentity.transportPeerId,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
        expectedStatus: 'complete',
      );
      final groupId = _requiredToken(senderSetup, 'groupId', maxLength: 160);
      final receiverArm = await _runGroupPhase(
        deviceId: receiverDeviceId,
        phase: 'receiver_accept_arm',
        role: 'receiver',
        groupId: groupId,
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverIdentity.transportPeerId,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
        expectedStatus: 'armed',
      );
      final receiverTransport = _requiredToken(
        receiverArm,
        'transportPeerId',
        maxLength: 180,
      );

      Map<String, Object?>? authoritySetup;
      if (context.authorityMode == groupMediaDistinctAuthorityMode) {
        final refreshed = await _runGroupPhase(
          deviceId: senderDeviceId,
          phase: 'sender_authority_refresh',
          role: 'sender',
          groupId: groupId,
          receiverAccountPeerId: receiverIdentity.accountPeerId,
          receiverTransportPeerId: receiverTransport,
          messageIds: messageIds,
          attachmentIds: attachmentIds,
          expectedStatus: 'complete',
        );
        final receiverReady = await _runGroupPhase(
          deviceId: receiverDeviceId,
          phase: 'receiver_authority_ready',
          role: 'receiver',
          groupId: groupId,
          receiverAccountPeerId: receiverIdentity.accountPeerId,
          receiverTransportPeerId: receiverTransport,
          messageIds: messageIds,
          attachmentIds: attachmentIds,
          expectedStatus: 'complete',
          expectedAuthority:
              GroupMediaReliabilityAuthorityTarget.fromObservation(
                _object(
                  _object(
                    refreshed['authorityRefresh'],
                    'authority refresh',
                  )['after'],
                  'sender authority after',
                ),
              ),
        );
        authoritySetup = await buildAndRetainAndroidGroupMediaAuthoritySetup(
          directory: context.proofDirectory,
          runId: context.runId,
          senderSetup: senderSetup,
          receiverArm: receiverArm,
          senderRefresh: refreshed,
          receiverReady: receiverReady,
        );
        // Preserve the actual setup observations before any media or cleanup.
        final bytes = utf8.encode(jsonEncode(authoritySetup));
        final digest = sha256.convert(bytes).toString();
        final file = File(
          '${context.proofDirectory.path}/authority-setup-$digest.json',
        );
        await file.parent.create(recursive: true);
        if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      }

      final senderSendConfig = _groupPhaseConfig(
        phase: 'sender_send',
        role: 'sender',
        groupId: groupId,
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverTransport,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
      );
      await _stageConfig(senderDeviceId, senderSendConfig);
      final senderSendFuture = _waitForGroupEndpoint(
        senderDeviceId,
        config: senderSendConfig,
        expectedStatus: 'complete',
        timeout: const Duration(minutes: 4),
      );
      // JPEG is the final fixture. Require the sender endpoint's complete
      // upload/publication receipt before observing or acting on its receiver
      // barrier, so the emitted flow order is the real causal order.
      final senderSend = await senderSendFuture;
      _senderSendCompleted = true;
      final barrier = await _waitForBarrierState(
        groupId: groupId,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
      );

      final recoveryConfig = _groupPhaseConfig(
        phase: 'receiver_recover',
        role: 'receiver',
        groupId: groupId,
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverTransport,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
      );
      final receiverTransition = await processController.forceStopAndRelaunch(
        deviceId: receiverDeviceId,
        packageName: packageName,
        afterStoppedBeforeLaunch: () =>
            _stageConfig(receiverDeviceId, recoveryConfig),
      );
      final receiverRecovery = await _waitForGroupEndpoint(
        receiverDeviceId,
        config: recoveryConfig,
        expectedStatus: 'complete',
        timeout: const Duration(minutes: 4),
      );

      // Recovery remains launcher-only through its durable prior-status read,
      // both explicit passes, and the complete endpoint receipt above. Only
      // now may the proof open the exact real group route to test rendering.
      final receiverRender = await _runGroupPhase(
        deviceId: receiverDeviceId,
        phase: 'receiver_render_probe',
        role: 'receiver',
        groupId: groupId,
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverTransport,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
        expectedStatus: 'complete',
      );
      final receiverRenderedKinds = await _waitForReceiverRenderedKinds();

      final senderProbeConfig = _groupPhaseConfig(
        phase: 'sender_probe',
        role: 'sender',
        groupId: groupId,
        receiverAccountPeerId: receiverIdentity.accountPeerId,
        receiverTransportPeerId: receiverTransport,
        messageIds: messageIds,
        attachmentIds: attachmentIds,
      );
      final senderTransition = await processController.forceStopAndRelaunch(
        deviceId: senderDeviceId,
        packageName: packageName,
        afterStoppedBeforeLaunch: () =>
            _stageConfig(senderDeviceId, senderProbeConfig),
      );
      final senderProbe = await _waitForGroupEndpoint(
        senderDeviceId,
        config: senderProbeConfig,
        expectedStatus: 'complete',
        timeout: const Duration(minutes: 3),
      );

      await _requirePreparedArtifactCustody('after scenario execution');
      aggregateAfterCleanup = (preResetReceipts, postResetReceipts) =>
          aggregateAndroidGroupMediaReliabilityEvidence(
            authoritySetup: authoritySetup,
            context: context,
            senderExportedAccountPeerId: senderIdentity.accountPeerId,
            receiverExportedAccountPeerId: receiverIdentity.accountPeerId,
            senderSetup: senderSetup,
            receiverArm: receiverArm,
            senderSend: senderSend,
            barrierState: barrier,
            receiverTransition: receiverTransition,
            receiverRecovery: receiverRecovery,
            receiverRender: receiverRender,
            receiverRenderedKinds: receiverRenderedKinds,
            senderTransition: senderTransition,
            senderProbe: senderProbe,
            messageIds: messageIds,
            attachmentIds: attachmentIds,
            preResetReceipts: preResetReceipts,
            postResetReceipts: postResetReceipts,
            commandSafety: runner.evidence,
            appsLeftInstalled: true,
          );
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    } finally {
      final cleanupFailures = <Object>[];
      for (final app in touched.toList(growable: false).reversed) {
        try {
          final receipt = await app.reset('post');
          postResetReceipts[roleByDeviceId[app.deviceId]!] = receipt;
        } on Object catch (error) {
          cleanupFailures.add(error);
        }
      }
      if (resetRoot.existsSync()) resetRoot.deleteSync(recursive: true);
      // A cleanup error must not replace the causal scenario failure. The
      // runner still withholds evidence, while a cleanup-only failure remains
      // fatal when the scenario itself had otherwise completed.
      if (cleanupFailures.isNotEmpty && primaryError == null) {
        throw StateError(
          'Dedicated P269 Android post-reset failed on '
          '${cleanupFailures.length} target(s).',
        );
      }
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }
    if (aggregateAfterCleanup == null ||
        preResetReceipts.length != apps.length ||
        postResetReceipts.length != apps.length ||
        roleByDeviceId.values.any(
          (role) =>
              preResetReceipts[role]?.sha256Digest ==
              postResetReceipts[role]?.sha256Digest,
        )) {
      throw StateError('Dedicated P269 Android reset custody was incomplete.');
    }
    return aggregateAfterCleanup(preResetReceipts, postResetReceipts);
  }

  Future<void> _prepareRole(String deviceId, String username) async {
    await _requireAdb(deviceId, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      'android.permission.RECORD_AUDIO',
    ]);
    await _adb(deviceId, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      'android.permission.POST_NOTIFICATIONS',
    ], allowFailure: true);
    await _writeAppJsonAtomic(deviceId, 'auto_setup.json', <String, Object?>{
      'username': username,
    });
  }

  Future<void> _requirePreparedArtifactCustody(String phase) async {
    final expected = context.preparedArtifact.sha256Digest;
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
            FileSystemEntityType.file ||
        (await sha256.bind(artifact.openRead()).first).toString() != expected) {
      throw StateError('Prepared Android APK custody failed $phase.');
    }
  }

  Future<_AndroidIdentity> _waitForIdentity(
    String deviceId, {
    required String role,
    required Map<String, String> messageIds,
    required Map<String, String> attachmentIds,
  }) async {
    final value = await _waitForValue<Map<String, Object?>>(
      role == 'sender' ? 'identity_sender' : 'identity_receiver',
      const Duration(minutes: 3),
      () => _readAppJson(deviceId, _identityFile),
    );
    final qrPayload = value['qrPayload'];
    final mlKemPublicKey = value['mlKemPublicKey'];
    if (qrPayload is! String ||
        qrPayload.isEmpty ||
        mlKemPublicKey is! String ||
        mlKemPublicKey.isEmpty) {
      throw const FormatException('Android identity export is incomplete');
    }
    final qr = _object(jsonDecode(qrPayload), 'identity QR');
    final accountPeerId = _requiredToken(qr, 'ns', maxLength: 180);
    final probe = await _runGroupPhase(
      deviceId: deviceId,
      phase: 'identity_probe',
      role: role,
      groupId: '',
      receiverAccountPeerId: '',
      receiverTransportPeerId: '',
      messageIds: messageIds,
      attachmentIds: attachmentIds,
      expectedStatus: 'complete',
    );
    final probedAccount = _requiredToken(
      probe,
      'accountPeerId',
      maxLength: 180,
    );
    final transportPeerId = _requiredToken(
      probe,
      'transportPeerId',
      maxLength: 180,
    );
    if (probedAccount != accountPeerId ||
        !groupMediaRoleIdentityMatches(
          context.authorityMode,
          accountPeerId,
          transportPeerId,
        )) {
      throw const FormatException(
        'Android account and transport identity authority did not bind',
      );
    }
    return _AndroidIdentity(
      deviceId: deviceId,
      accountPeerId: accountPeerId,
      transportPeerId: transportPeerId,
      qrPayload: qrPayload,
      mlKemPublicKey: mlKemPublicKey,
    );
  }

  Future<void> _establishContacts(
    _AndroidIdentity sender,
    _AndroidIdentity receiver,
  ) async {
    await Future.wait(<Future<Map<String, Object?>>>[
      _runGenericConfig(sender.deviceId, <String, Object?>{
        'stepId': 'p269-contact-sender-${_shortDigest(context.runId)}',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': receiver.qrPayload,
            'mlKemPublicKey': receiver.mlKemPublicKey,
          },
        ],
        'contact_settle_delay_ms': 500,
      }),
      _runGenericConfig(receiver.deviceId, <String, Object?>{
        'stepId': 'p269-contact-receiver-${_shortDigest(context.runId)}',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': sender.qrPayload,
            'mlKemPublicKey': sender.mlKemPublicKey,
          },
        ],
        'contact_settle_delay_ms': 500,
      }),
    ]);
  }

  Future<Map<String, Object?>> _runGenericConfig(
    String deviceId,
    Map<String, Object?> config,
  ) async {
    await _stageConfig(deviceId, config);
    final stepId = config['stepId']! as String;
    return _waitForValue<Map<String, Object?>>(
      deviceId == senderDeviceId ? 'contacts_sender' : 'contacts_receiver',
      const Duration(minutes: 3),
      () async {
        final result = await _readAppJson(deviceId, _resultFile);
        if (result == null || result['stepId'] != stepId) return null;
        if (result['status'] == 'failed' || result['success'] == false) {
          throw StateError('Generic Android app step failed');
        }
        return result['status'] == 'complete' && result['success'] == true
            ? result
            : null;
      },
    );
  }

  Future<Map<String, Object?>> _runGroupPhase({
    required String deviceId,
    required String phase,
    required String role,
    required String groupId,
    required String receiverAccountPeerId,
    required String receiverTransportPeerId,
    required Map<String, String> messageIds,
    required Map<String, String> attachmentIds,
    required String expectedStatus,
    GroupMediaReliabilityAuthorityTarget? expectedAuthority,
  }) async {
    final config = _groupPhaseConfig(
      phase: phase,
      role: role,
      groupId: groupId,
      receiverAccountPeerId: receiverAccountPeerId,
      receiverTransportPeerId: receiverTransportPeerId,
      messageIds: messageIds,
      attachmentIds: attachmentIds,
      expectedAuthority: expectedAuthority,
    );
    await _stageConfig(deviceId, config);
    return _waitForGroupEndpoint(
      deviceId,
      config: config,
      expectedStatus: expectedStatus,
      timeout: const Duration(minutes: 3),
    );
  }

  Map<String, Object?> _groupPhaseConfig({
    required String phase,
    required String role,
    required String groupId,
    required String receiverAccountPeerId,
    required String receiverTransportPeerId,
    required Map<String, String> messageIds,
    required Map<String, String> attachmentIds,
    GroupMediaReliabilityAuthorityTarget? expectedAuthority,
  }) {
    if ((phase == 'receiver_authority_ready') != (expectedAuthority != null) ||
        (expectedAuthority != null && !expectedAuthority.isForGroup(groupId))) {
      throw const FormatException('group-media authority target rejected');
    }
    final nonce = 'nonce-${_shortDigest('${context.runId}:$phase:$role')}';
    return <String, Object?>{
      'schema': _commandSchema,
      'transport_action': _transportAction,
      'scenario': groupMediaForegroundRetryAclRoundtripScenario,
      'stepId': 'group-media-$phase-${context.runId}',
      'phase': phase,
      'role': role,
      'runId': context.runId,
      'nonce': nonce,
      'groupId': groupId,
      'receiverAccountPeerId': receiverAccountPeerId,
      'receiverTransportPeerId': receiverTransportPeerId,
      'messageIds': messageIds,
      'attachmentIds': attachmentIds,
      if (expectedAuthority != null)
        'expectedAuthority': expectedAuthority.toJson(),
    };
  }

  Future<Map<String, Object?>> _waitForGroupEndpoint(
    String deviceId, {
    required Map<String, Object?> config,
    required String expectedStatus,
    required Duration timeout,
  }) {
    Map<String, Object?> observation = const {
      'matchingEndpointObserved': false,
    };
    return _waitForValue<Map<String, Object?>>(
      config['phase']! as String,
      timeout,
      () async {
        final result = await _readAppJson(deviceId, _resultFile);
        if (result == null ||
            result['schema'] != _endpointSchema ||
            result['scenario'] !=
                groupMediaForegroundRetryAclRoundtripScenario ||
            result['buildProfile'] !=
                groupMediaReliabilityAndroidBuildProfile ||
            result['stepId'] != config['stepId'] ||
            result['phase'] != config['phase'] ||
            result['role'] != config['role'] ||
            result['runId'] != context.runId ||
            result['nonce'] != config['nonce']) {
          return null;
        }
        observation = {
          'matchingEndpointObserved': true,
          'endpointStatus': result['status'],
        };
        if (result['status'] == 'failed' || result['success'] == false) {
          final errorCode = result['errorCode'];
          final safeErrorCode =
              errorCode is String &&
                  RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(errorCode)
              ? errorCode
              : 'unexpected_error';
          await retainGroupMediaEndpointFailure(
            directory: context.proofDirectory,
            config: config,
            result: result,
            safeErrorCode: safeErrorCode,
          );
          throw GroupMediaReliabilityScenarioFailure(
            'group_endpoint_${config['phase']}_$safeErrorCode',
          );
        }
        if ((result.containsKey('authorityMode')
                ? result['authorityMode']
                : groupMediaDistinctAuthorityMode) !=
            context.authorityMode) {
          throw GroupMediaReliabilityScenarioFailure(
            'group_endpoint_authority_mode_mismatch',
          );
        }
        return result['status'] == expectedStatus && result['success'] == true
            ? result
            : null;
      },
      observation: () => observation,
    );
  }

  Future<Map<String, Object?>> _waitForBarrierState({
    required String groupId,
    required Map<String, String> messageIds,
    required Map<String, String> attachmentIds,
  }) {
    Map<String, Object?> observation = const {'matchedBarrierState': false};
    return _waitForValue<Map<String, Object?>>(
      'receiver_barrier',
      const Duration(minutes: 4),
      () async {
        final state = await _readAppJson(receiverDeviceId, _stateFile);
        if (state == null ||
            state['schema'] != _stateSchema ||
            state['runId'] != context.runId ||
            state['groupId'] != groupId ||
            state['jpegMessageId'] != messageIds['jpeg'] ||
            state['jpegAttachmentId'] != attachmentIds['jpeg'] ||
            !_sameStringMap(state['mediaAttachmentIds'], attachmentIds)) {
          return null;
        }
        final barrier = _optionalObject(state['barrier']);
        final attempts = _optionalObject(state['attempts']);
        observation = {
          'matchedBarrierState': true,
          'barrierName': barrier?['name'],
          'barrierReached': barrier?['reached'],
          'barrierPriorStatus': barrier?['priorStatus'],
          'barrierAttempt': barrier?['attempt'],
          'barrierProcessObserved':
              barrier?['processId'] is int &&
              (barrier!['processId']! as int) > 0,
          'recoveryReleased': state['recoveryReleased'],
          for (final kind in const ['jpeg', 'mp4', 'voice'])
            '${kind}Attempts': attempts?[kind],
        };
        if (barrier == null ||
            barrier['name'] !=
                (context.authorityMode == groupMediaDistinctAuthorityMode
                    ? 'receiver_jpeg_strict_verified_ciphertext_pre_commit'
                    : _barrierName) ||
            barrier['reached'] != true ||
            barrier['priorStatus'] !=
                (context.authorityMode == groupMediaDistinctAuthorityMode
                    ? 'pending'
                    : 'downloading') ||
            barrier['attempt'] != 1 ||
            barrier['processId'] is! int ||
            (barrier['processId']! as int) <= 0 ||
            state['recoveryReleased'] != false) {
          return null;
        }
        return state;
      },
      observation: () => observation,
    );
  }

  Future<void> _stageConfig(
    String deviceId,
    Map<String, Object?> config,
  ) async {
    await _deleteAppFile(deviceId, _resultFile);
    await _deleteAppFile(deviceId, _configFile);
    await _writeAppJsonAtomic(deviceId, _configFile, config);
  }

  Future<void> _writeAppJsonAtomic(
    String deviceId,
    String name,
    Map<String, Object?> value,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) {
      throw const FormatException('unsafe Android app file name');
    }
    final content = '${jsonEncode(value)}\n';
    final digest = sha256.convert(utf8.encode(content)).toString();
    final token = _shortDigest(
      '$deviceId:$name:${DateTime.now().microsecondsSinceEpoch}',
    );
    final hostFile = File('${Directory.systemTemp.path}/p269-$token.json');
    final remote = '/data/local/tmp/p269-$token.json';
    final pendingName = '$name.pending-$token';
    try {
      await hostFile.writeAsString(content, flush: true);
      await _requireAdb(deviceId, <String>['push', hostFile.path, remote]);
      await _requireShell(deviceId, <String>[
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _requireShell(deviceId, <String>[
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$pendingName',
      ]);
      final deviceDigest = (await _shellText(deviceId, <String>[
        'run-as',
        packageName,
        'sha256sum',
        'app_flutter/$pendingName',
      ])).trim().split(RegExp(r'\s+')).first;
      if (deviceDigest != digest) {
        throw StateError('Android staged command digest mismatch');
      }
      await _requireShell(deviceId, <String>[
        'run-as',
        packageName,
        'mv',
        'app_flutter/$pendingName',
        'app_flutter/$name',
      ]);
    } finally {
      await _adb(deviceId, <String>[
        'shell',
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
      await _adb(deviceId, <String>[
        'shell',
        'run-as',
        packageName,
        'rm',
        '-f',
        'app_flutter/$pendingName',
      ], allowFailure: true);
      if (await hostFile.exists()) await hostFile.delete();
    }
  }

  Future<Map<String, Object?>?> _readAppJson(
    String deviceId,
    String name,
  ) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      packageName,
      'cat',
      'app_flutter/$name',
    ], allowFailure: true);
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    try {
      return _object(jsonDecode('${result.stdout}'), name);
    } on FormatException {
      return null;
    }
  }

  Future<void> _deleteAppFile(String deviceId, String name) async {
    await _adb(deviceId, <String>[
      'shell',
      'run-as',
      packageName,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFailure: true);
  }

  Future<Map<String, int>> _waitForReceiverRenderedKinds() async {
    final sizeText = await _shellText(receiverDeviceId, const <String>[
      'wm',
      'size',
    ]);
    final matches = RegExp(r'(\d+)x(\d+)').allMatches(sizeText).toList();
    if (matches.isEmpty) {
      throw GroupMediaReliabilityScenarioFailure(
        'android_receiver_render_display_size_unavailable',
      );
    }
    final width = int.parse(matches.last.group(1)!);
    final height = int.parse(matches.last.group(2)!);
    final x = width ~/ 2;
    final upperY = (height * 0.28).round();
    final lowerY = (height * 0.76).round();
    final found = <String>{};
    const remote = '/sdcard/p269-group-media-render.xml';
    try {
      for (var pass = 0; pass < 18; pass++) {
        await _requireReceiverForeground();
        await _requireShell(receiverDeviceId, const <String>[
          'uiautomator',
          'dump',
          '--compressed',
          remote,
        ]);
        final xml = await _shellText(receiverDeviceId, const <String>[
          'cat',
          remote,
        ]);
        if (_renderFailureLabels.any(xml.contains)) {
          throw GroupMediaReliabilityScenarioFailure(
            'android_receiver_render_unavailable',
          );
        }
        found.addAll(groupMediaRenderedKindsFromUiXml(xml));
        if (found.length == _renderLabelsByKind.length &&
            found.containsAll(_renderLabelsByKind.keys)) {
          return <String, int>{for (final kind in found) kind: 1};
        }
        // Reverse chat lists can report either gesture direction across API
        // levels. Alternate bounded swipes and accumulate labels across dumps.
        final startY = pass.isEven ? upperY : lowerY;
        final endY = pass.isEven ? lowerY : upperY;
        await _requireShell(receiverDeviceId, <String>[
          'input',
          'swipe',
          '$x',
          '$startY',
          '$x',
          '$endY',
          '260',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      await _adb(receiverDeviceId, const <String>[
        'shell',
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
    }
    throw GroupMediaReliabilityScenarioFailure(
      androidGroupMediaRenderFailureCode(found),
    );
  }

  Future<void> _requireReceiverForeground() async {
    // Newer Android releases omit global focus from `dumpsys window windows`.
    // The `displays` section retains both exact focus owners while remaining
    // much smaller than the unfiltered full WindowManager dump.
    for (var attempt = 0; attempt < 30; attempt++) {
      final windows = await _shellText(receiverDeviceId, const <String>[
        'dumpsys',
        'window',
        'displays',
      ]);
      if (androidGroupMediaPackageOwnsForeground(
        windowsDump: windows,
        packageName: packageName,
      )) {
        return;
      }
      if (attempt < 29) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw GroupMediaReliabilityScenarioFailure(
      'android_receiver_render_foreground_lost',
    );
  }

  Future<T> _waitForValue<T>(
    String label,
    Duration timeout,
    Future<T?> Function() read, {
    Map<String, Object?> Function()? observation,
  }) => waitForAndroidGroupMediaValue(
    label,
    timeout,
    read,
    onTimeout: () => retainAndroidGroupMediaWaitTimeout(
      directory: context.proofDirectory,
      phase: label,
      senderSendCompleted: _senderSendCompleted,
      observation: observation?.call() ?? const {},
    ),
  );

  Future<String> _shellText(
    String deviceId,
    List<String> arguments, {
    bool preMutation = false,
  }) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      ...arguments,
    ], allowFailure: true);
    if (result.exitCode != 0) {
      if (preMutation) {
        throw const GroupMediaReliabilityBlocked(
          'targetUnavailable',
          'Android target property probe failed.',
        );
      }
      throw StateError('Android shell command failed');
    }
    return '${result.stdout}';
  }

  Future<void> _requireShell(String deviceId, List<String> arguments) =>
      _requireAdb(deviceId, <String>['shell', ...arguments]);

  Future<void> _requireAdb(String deviceId, List<String> arguments) async {
    final result = await _adb(deviceId, arguments, allowFailure: true);
    if (result.exitCode != 0) throw StateError('Android ADB command failed');
  }

  Future<ProcessResult> _adb(
    String deviceId,
    List<String> arguments, {
    required bool allowFailure,
  }) async {
    try {
      final result = await runner.run('adb', <String>[
        '-s',
        deviceId,
        ...arguments,
      ]);
      if (!allowFailure && result.exitCode != 0) {
        throw StateError('Android ADB command failed');
      }
      return result;
    } on ProcessException catch (error) {
      throw StateError('ADB became unavailable: ${error.message}');
    }
  }
}

final class _AndroidIdentity {
  const _AndroidIdentity({
    required this.deviceId,
    required this.accountPeerId,
    required this.transportPeerId,
    required this.qrPayload,
    required this.mlKemPublicKey,
  });

  final String deviceId;
  final String accountPeerId;
  final String transportPeerId;
  final String qrPayload;
  final String mlKemPublicKey;
}

/// Qualifies the real creator rotation and both current production admissions
/// before the controller can stage any media-send command.
/// Keep the comparison operands before validation can throw and reset removes
/// endpoint files. This closed diagnostic is not a successful authority proof.
Future<Map<String, Object?>> buildAndRetainAndroidGroupMediaAuthoritySetup({
  required Directory directory,
  required String runId,
  required Map<String, Object?> senderSetup,
  required Map<String, Object?> receiverArm,
  required Map<String, Object?> senderRefresh,
  required Map<String, Object?> receiverReady,
}) async {
  final hex = RegExp(r'^[a-f0-9]{64}$');
  Object? digestValue(Object? value) =>
      value is String && hex.hasMatch(value) ? value : null;
  Object? integer(Object? value, {int minimum = 0}) =>
      value is int && value >= minimum ? value : null;
  Object? timestamp(Object? value) =>
      value is String &&
          value.length <= 40 &&
          value.endsWith('Z') &&
          DateTime.tryParse(value) != null
      ? value
      : null;
  Map<String, Object?> observation(Object? value) {
    final row = _optionalObject(value) ?? const <String, Object?>{};
    final recipients = row['recipientTransportSha256'];
    return {
      'schema': row['schema'] == 'mknoon.group-media-authority.v1'
          ? row['schema']
          : null,
      for (final key in const [
        'groupIdSha256',
        'accountPeerIdSha256',
        'transportPeerIdSha256',
        'memberRolesSha256',
        'authoritySha256',
      ])
        key: digestValue(row[key]),
      'keyEpoch': integer(row['keyEpoch'], minimum: 1),
      'admission':
          const [
            'strict',
            'legacyUninitialized',
            'refuse',
          ].contains(row['admission'])
          ? row['admission']
          : null,
      'authorityEventAt': timestamp(row['authorityEventAt']),
      'recipientTransportSha256':
          recipients is List &&
              recipients.length <= 2 &&
              recipients.every((value) => digestValue(value) != null)
          ? recipients.toList(growable: false)
          : null,
    };
  }

  Map<String, Object?> identity(Map<String, Object?> row) => {
    'processId': integer(row['processId'], minimum: 1),
    for (final key in const ['groupId', 'accountPeerId', 'transportPeerId'])
      '${key}Sha256': row[key] is String && (row[key]! as String).length <= 180
          ? sha256.convert(utf8.encode(row[key]! as String)).toString()
          : null,
  };
  final refresh =
      _optionalObject(senderRefresh['authorityRefresh']) ?? const {};
  final receipt = {
    'schema': 'mknoon.group-media-authority-observations.v1',
    'runSha256': _scopedDigest(runId, 'authority-observations'),
    'validation': 'not_yet_compared',
    'senderSetup': identity(senderSetup),
    'receiverArm': {
      ...identity(receiverArm),
      'authorityBefore': observation(receiverArm['authorityBefore']),
    },
    'senderRefresh': {
      'processId': integer(senderRefresh['processId'], minimum: 1),
      'before': observation(refresh['before']),
      'after': observation(refresh['after']),
      for (final key in const [
        'previousEpoch',
        'currentEpoch',
        'distributedDeviceCount',
        'deferredPeerCount',
      ])
        key: integer(refresh[key]),
    },
    'receiverReady': {
      'processId': integer(receiverReady['processId'], minimum: 1),
      'authorityAfter': observation(receiverReady['authorityAfter']),
    },
  };
  final bytes = utf8.encode(jsonEncode(receipt));
  final digest = sha256.convert(bytes).toString();
  try {
    await directory.create(recursive: true);
    final file = File('${directory.path}/authority-observations-$digest.json');
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
  } on FileSystemException {
    // A diagnostic write failure must not replace the original comparison.
  }
  return buildAndroidGroupMediaAuthoritySetup(
    runId: runId,
    senderSetup: senderSetup,
    receiverArm: receiverArm,
    senderRefresh: senderRefresh,
    receiverReady: receiverReady,
  );
}

Map<String, Object?> buildAndroidGroupMediaAuthoritySetup({
  required String runId,
  required Map<String, Object?> senderSetup,
  required Map<String, Object?> receiverArm,
  required Map<String, Object?> senderRefresh,
  required Map<String, Object?> receiverReady,
}) {
  final groupId = _requiredToken(senderSetup, 'groupId', maxLength: 160);
  final senderAccount = _requiredToken(
    senderSetup,
    'accountPeerId',
    maxLength: 180,
  );
  final senderTransport = _requiredToken(
    senderSetup,
    'transportPeerId',
    maxLength: 180,
  );
  final receiverAccount = _requiredToken(
    receiverArm,
    'accountPeerId',
    maxLength: 180,
  );
  final receiverTransport = _requiredToken(
    receiverArm,
    'transportPeerId',
    maxLength: 180,
  );
  if (receiverArm['groupId'] != groupId ||
      senderAccount == receiverAccount ||
      senderTransport == receiverTransport ||
      senderAccount == senderTransport ||
      receiverAccount == receiverTransport ||
      senderSetup['processId'] is! int ||
      (senderSetup['processId']! as int) <= 0 ||
      receiverArm['processId'] is! int ||
      (receiverArm['processId']! as int) <= 0) {
    throw const FormatException(
      'Authority setup requires exact distinct live peers',
    );
  }
  final refresh = _object(
    senderRefresh['authorityRefresh'],
    'authority refresh',
  );
  final before = _object(refresh['before'], 'sender authority before');
  final after = _object(refresh['after'], 'sender authority after');
  final receiverBefore = _object(
    receiverArm['authorityBefore'],
    'receiver authority before',
  );
  final receiverAfter = _object(
    receiverReady['authorityAfter'],
    'receiver authority after',
  );
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  final hex = RegExp(r'^[a-f0-9]{64}$');
  void qualify(
    Map<String, Object?> row,
    String account,
    String transport,
    String recipient, {
    required bool settled,
  }) {
    const keys = {
      'schema',
      'groupIdSha256',
      'accountPeerIdSha256',
      'transportPeerIdSha256',
      'memberRolesSha256',
      'keyEpoch',
      'admission',
      'authoritySha256',
      'authorityEventAt',
      'recipientTransportSha256',
    };
    if (row.length != keys.length ||
        !row.keys.toSet().containsAll(keys) ||
        row['schema'] != 'mknoon.group-media-authority.v1' ||
        row['groupIdSha256'] != digest(groupId) ||
        row['accountPeerIdSha256'] != digest(account) ||
        row['transportPeerIdSha256'] != digest(transport) ||
        row['memberRolesSha256'] is! String ||
        !hex.hasMatch(row['memberRolesSha256']! as String) ||
        row['keyEpoch'] is! int ||
        (row['keyEpoch']! as int) <= 0 ||
        !const {
          'strict',
          'legacyUninitialized',
          'refuse',
        }.contains(row['admission'])) {
      throw const FormatException('Authority observation identity rejected');
    }
    if (settled &&
        (row['admission'] != 'strict' ||
            row['authoritySha256'] is! String ||
            !hex.hasMatch(row['authoritySha256']! as String) ||
            row['authorityEventAt'] is! String ||
            !(row['authorityEventAt']! as String).endsWith('Z') ||
            DateTime.tryParse(row['authorityEventAt']! as String) == null ||
            jsonEncode(row['recipientTransportSha256']) !=
                jsonEncode([digest(recipient)]))) {
      throw const FormatException(
        'Authority observation is not settled for exact peer',
      );
    }
  }

  qualify(
    before,
    senderAccount,
    senderTransport,
    receiverTransport,
    settled: false,
  );
  qualify(
    after,
    senderAccount,
    senderTransport,
    receiverTransport,
    settled: true,
  );
  qualify(
    receiverBefore,
    receiverAccount,
    receiverTransport,
    senderTransport,
    settled: false,
  );
  qualify(
    receiverAfter,
    receiverAccount,
    receiverTransport,
    senderTransport,
    settled: true,
  );
  final previous = before['keyEpoch']! as int;
  final current = after['keyEpoch']! as int;
  if (current != previous + 1 ||
      receiverBefore['keyEpoch'] != previous ||
      receiverAfter['keyEpoch'] != current ||
      refresh['previousEpoch'] != previous ||
      refresh['currentEpoch'] != current ||
      refresh['distributedDeviceCount'] != 1 ||
      refresh['deferredPeerCount'] != 0 ||
      before['memberRolesSha256'] != after['memberRolesSha256'] ||
      receiverBefore['memberRolesSha256'] !=
          receiverAfter['memberRolesSha256'] ||
      after['memberRolesSha256'] != receiverAfter['memberRolesSha256'] ||
      after['authoritySha256'] != receiverAfter['authoritySha256'] ||
      after['authorityEventAt'] != receiverAfter['authorityEventAt'] ||
      senderRefresh['processId'] != senderSetup['processId'] ||
      receiverReady['processId'] != receiverArm['processId']) {
    throw const FormatException(
      'Creator rotation and peer authority did not converge',
    );
  }
  Map<String, Object?> role(
    String account,
    String transport,
    Map<String, Object?> old,
    Map<String, Object?> fresh,
  ) => {
    'account_sha256': _scopedDigest(runId, account),
    'transport_sha256': _scopedDigest(runId, transport),
    'before_roles_sha256': old['memberRolesSha256'],
    'after_roles_sha256': fresh['memberRolesSha256'],
    'admission': 'strict',
  };
  return <String, Object?>{
    'schema': 'mknoon.group-media-authority-setup.v1',
    'group_sha256': _scopedDigest(runId, groupId),
    'previous_epoch': previous,
    'current_epoch': current,
    'authority_sha256': after['authoritySha256'],
    'authority_event_at': after['authorityEventAt'],
    'sender': role(senderAccount, senderTransport, before, after),
    'receiver': role(
      receiverAccount,
      receiverTransport,
      receiverBefore,
      receiverAfter,
    ),
  };
}

Map<String, Object?> aggregateAndroidGroupMediaReliabilityEvidence({
  Map<String, Object?>? authoritySetup,
  required GroupMediaReliabilityRunContext context,
  required String senderExportedAccountPeerId,
  required String receiverExportedAccountPeerId,
  required Map<String, Object?> senderSetup,
  required Map<String, Object?> receiverArm,
  required Map<String, Object?> senderSend,
  required Map<String, Object?> barrierState,
  required AndroidGroupMediaProcessTransitionEvidence receiverTransition,
  required Map<String, Object?> receiverRecovery,
  required Map<String, Object?> receiverRender,
  required Map<String, int> receiverRenderedKinds,
  required AndroidGroupMediaProcessTransitionEvidence senderTransition,
  required Map<String, Object?> senderProbe,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required Map<String, GroupMediaAndroidDisposableResetReceipt>
  preResetReceipts,
  required Map<String, GroupMediaAndroidDisposableResetReceipt>
  postResetReceipts,
  required AndroidGroupMediaCommandSafetyEvidence commandSafety,
  required bool appsLeftInstalled,
}) {
  if (!groupMediaAuthorityModeIsValid(context.authorityMode)) {
    throw const FormatException(
      'Android group-media authority mode is invalid',
    );
  }
  for (final receipt in [
    senderSetup,
    receiverArm,
    senderSend,
    receiverRecovery,
    receiverRender,
    senderProbe,
  ]) {
    if ((receipt.containsKey('authorityMode')
            ? receipt['authorityMode']
            : groupMediaDistinctAuthorityMode) !=
        context.authorityMode) {
      throw const FormatException(
        'Android endpoint authority mode does not match runner custody',
      );
    }
  }
  const resetRoles = <String>{'sender', 'receiver'};
  if (preResetReceipts.keys.toSet().length != resetRoles.length ||
      !preResetReceipts.keys.toSet().containsAll(resetRoles) ||
      postResetReceipts.keys.toSet().length != resetRoles.length ||
      !postResetReceipts.keys.toSet().containsAll(resetRoles) ||
      preResetReceipts.values.any((receipt) => receipt.phase != 'pre') ||
      postResetReceipts.values.any((receipt) => receipt.phase != 'post') ||
      preResetReceipts.values.any((receipt) => receipt.processId <= 0) ||
      postResetReceipts.values.any((receipt) => receipt.processId <= 0) ||
      <String>{
            ...preResetReceipts.values.map((receipt) => receipt.sha256Digest),
            ...postResetReceipts.values.map((receipt) => receipt.sha256Digest),
          }.length !=
          4 ||
      commandSafety.productionPackageCommands != 0 ||
      commandSafety.uninstallCommands != 0 ||
      commandSafety.pmClearCommands != 0 ||
      commandSafety.broadDeleteCommands != 0 ||
      !appsLeftInstalled) {
    throw const FormatException(
      'Android disposable reset and command-safety custody did not bind',
    );
  }
  final groupId = _requiredToken(senderSetup, 'groupId', maxLength: 160);
  final senderAccount = _requiredToken(
    senderSetup,
    'accountPeerId',
    maxLength: 180,
  );
  final senderTransport = _requiredToken(
    senderSetup,
    'transportPeerId',
    maxLength: 180,
  );
  final receiverAccount = _requiredToken(
    receiverArm,
    'accountPeerId',
    maxLength: 180,
  );
  final receiverTransport = _requiredToken(
    receiverArm,
    'transportPeerId',
    maxLength: 180,
  );
  if (senderAccount != senderExportedAccountPeerId ||
      receiverAccount != receiverExportedAccountPeerId ||
      !groupMediaRoleIdentityMatches(
        context.authorityMode,
        senderAccount,
        senderTransport,
      ) ||
      !groupMediaRoleIdentityMatches(
        context.authorityMode,
        receiverAccount,
        receiverTransport,
      ) ||
      <String>{
            senderAccount,
            senderTransport,
            receiverAccount,
            receiverTransport,
          }.length !=
          (context.authorityMode == groupMediaAccountBoundAuthorityMode
              ? 2
              : 4) ||
      receiverArm['groupId'] != groupId ||
      senderSend['accountPeerId'] != senderAccount ||
      senderSend['transportPeerId'] != senderTransport ||
      senderSend['receiverAccountPeerId'] != receiverAccount ||
      senderSend['receiverTransportPeerId'] != receiverTransport) {
    throw const FormatException(
      'Android group-media identity/group tuple changed during the run',
    );
  }

  final allowedPeers = _stringList(senderSend['allowedPeers'], 'allowedPeers');
  if (allowedPeers.length != 2 ||
      allowedPeers.toSet().length != 2 ||
      !allowedPeers.toSet().containsAll(<String>{
        senderTransport,
        receiverTransport,
      }) ||
      (context.authorityMode == groupMediaDistinctAuthorityMode &&
          (allowedPeers.contains(senderAccount) ||
              allowedPeers.contains(receiverAccount)))) {
    throw const FormatException(
      'Android group-media upload ACL was not the active transport roster',
    );
  }
  final uploads = _exactKindCounts(
    senderSend['uploadsPerBlob'],
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    'uploadsPerBlob',
  );
  final publications = _exactKindCounts(
    senderSend['publicationsPerMessage'],
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    'publicationsPerMessage',
  );
  final downloadAttempts = _exactKindCounts(
    receiverRecovery['downloadAttempts'],
    const <String, int>{'jpeg': 2, 'mp4': 1, 'voice': 1},
    'downloadAttempts',
  );
  final renderedKinds = _exactKindCounts(
    receiverRenderedKinds,
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    'receiverRenderedKinds',
  );

  final strict = context.authorityMode == groupMediaDistinctAuthorityMode;
  final expectedPriorStatus = strict ? 'pending' : 'downloading';
  final expectedBarrierName = strict
      ? 'receiver_jpeg_strict_verified_ciphertext_pre_commit'
      : _barrierName;
  final barrier = _object(barrierState['barrier'], 'barrier');
  final barrierPid = _positiveInt(barrier, 'processId');
  final receiverOldPid = int.parse(receiverTransition.oldPid);
  final receiverFreshPid = int.parse(receiverTransition.freshPid);
  if (barrier['name'] != expectedBarrierName ||
      barrier['reached'] != true ||
      barrier['priorStatus'] != expectedPriorStatus ||
      barrier['attempt'] != 1 ||
      barrierPid != receiverOldPid ||
      !receiverTransition.oldPidGone ||
      !receiverTransition.relaunchedWithoutGroupRoute ||
      receiverRecovery['priorStatus'] != expectedPriorStatus ||
      receiverRecovery['previousProcessId'] != receiverOldPid ||
      receiverRecovery['currentProcessId'] != receiverFreshPid ||
      receiverRecovery['processId'] != receiverFreshPid ||
      receiverRender['processId'] != receiverFreshPid ||
      receiverRender['renderProbeArmed'] != true ||
      receiverArm['processId'] != receiverOldPid) {
    throw const FormatException(
      'Android receiver process-death/prior-status proof did not bind',
    );
  }
  final senderOldPid = int.parse(senderTransition.oldPid);
  final senderFreshPid = int.parse(senderTransition.freshPid);
  if (!senderTransition.oldPidGone ||
      !senderTransition.relaunchedWithoutGroupRoute ||
      senderSend['processId'] != senderOldPid ||
      senderProbe['processId'] != senderFreshPid) {
    throw const FormatException('Android sender database reopen was not cold');
  }

  final receiverFirstUpload = _int(receiverRecovery, 'firstUploadWork');
  final receiverFirstDownload = _int(receiverRecovery, 'firstDownloadWork');
  final receiverSecondUpload = _int(receiverRecovery, 'secondUploadWork');
  final receiverSecondDownload = _int(receiverRecovery, 'secondDownloadWork');
  final senderFirstUpload = _int(senderProbe, 'firstUploadWork');
  final senderFirstDownload = _int(senderProbe, 'firstDownloadWork');
  final senderSecondUpload = _int(senderProbe, 'secondUploadWork');
  final senderSecondDownload = _int(senderProbe, 'secondDownloadWork');
  if (receiverFirstUpload != 0 ||
      receiverFirstDownload < 1 ||
      receiverFirstDownload > 3 ||
      receiverSecondUpload != 0 ||
      receiverSecondDownload != 0 ||
      senderFirstUpload != 0 ||
      senderFirstDownload != 0 ||
      senderSecondUpload != 0 ||
      senderSecondDownload != 0) {
    throw const FormatException(
      'Android explicit group-media retry passes did not converge to zero',
    );
  }

  final senderIdentityDb = _RoleDatabaseObservation.parse(
    senderSetup['roleDatabaseIdentity'],
    role: 'sender',
    runId: context.runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    requireRows: false,
  );
  final receiverIdentityDb = _RoleDatabaseObservation.parse(
    receiverArm['roleDatabaseIdentity'],
    role: 'receiver',
    runId: context.runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    requireRows: false,
  );
  final senderBeforeRestartDb = _RoleDatabaseObservation.parse(
    senderSend['roleDatabase'],
    role: 'sender',
    runId: context.runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    requireRows: true,
    requireStrictSender: strict,
  );
  final senderAfterRestartDb = _RoleDatabaseObservation.parse(
    senderProbe['roleDatabase'],
    role: 'sender',
    runId: context.runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    requireRows: true,
    requireStrictSender: strict,
  );
  final receiverAfterRestartDb = _RoleDatabaseObservation.parse(
    receiverRecovery['roleDatabase'],
    role: 'receiver',
    runId: context.runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    requireRows: true,
  );
  if (!senderIdentityDb.sameDatabase(senderBeforeRestartDb) ||
      !senderBeforeRestartDb.sameDatabase(senderAfterRestartDb) ||
      !receiverIdentityDb.sameDatabase(receiverAfterRestartDb) ||
      senderAfterRestartDb.databasePathSha256 ==
          receiverAfterRestartDb.databasePathSha256 ||
      jsonEncode(senderBeforeRestartDb.rows) !=
          jsonEncode(senderAfterRestartDb.rows)) {
    throw const FormatException(
      'Android role SQLCipher observations did not reopen the same databases',
    );
  }

  Map<String, Object?>? strictProof;
  if (strict) {
    if (authoritySetup == null) {
      throw const FormatException(
        'Current distinct Android requires strict authority setup',
      );
    }
    if (authoritySetup['group_sha256'] !=
        _scopedDigest(context.runId, groupId)) {
      throw const FormatException(
        'Strict authority setup belongs to another group',
      );
    }
    final receipts = _object(
      senderSend['strictMediaCustody'],
      'strict sender custody',
    );
    final bound = _object(barrier['strictCustodyBoundary'], 'strict barrier');
    if (jsonEncode(bound) !=
        jsonEncode(receiverRecovery['strictCustodyBoundary'])) {
      throw const FormatException(
        'strict custody changed across receiver restart',
      );
    }
    final media = <String, Object?>{};
    for (final kind in const ['jpeg', 'mp4', 'voice']) {
      final receipt = _object(receipts[kind], 'strict custody $kind');
      final recipient = sha256
          .convert(utf8.encode(receiverTransport))
          .toString();
      if (receipt['recipient_transport_sha256'] != recipient ||
          receipt['recipient_count'] != 1) {
        throw const FormatException('strict manifest receiver mismatch');
      }
      for (final db in [
        senderBeforeRestartDb,
        senderAfterRestartDb,
        receiverAfterRestartDb,
      ]) {
        final row = db.rows.singleWhere((row) => row['media_kind'] == kind);
        if (row['custody_fingerprint'] != receipt['custody_fingerprint']) {
          throw const FormatException(
            'strict manifest did not join reopened attachment',
          );
        }
        if (identical(db, senderBeforeRestartDb) ||
            identical(db, senderAfterRestartDb)) {
          if (receipt['ciphertext_sha256'] is! String ||
              !groupMediaStrictSenderPublicationMatches(
                row,
                groupSha256: _scopedDigest(context.runId, groupId),
                senderAccountSha256: _scopedDigest(
                  context.runId,
                  senderAccount,
                ),
                ciphertextSha256: receipt['ciphertext_sha256'] as String?,
              )) {
            throw const FormatException(
              'strict sender SQL publication identity did not bind',
            );
          }
        }
      }
      media[kind] = {
        ...receipt,
        'recipient_transport_sha256': _scopedDigest(
          context.runId,
          receiverTransport,
        ),
      };
    }
    strictProof = {'media': media, 'barrier': bound};
  }

  final senderTransportDigest = _scopedDigest(context.runId, senderTransport);
  final receiverTransportDigest = _scopedDigest(
    context.runId,
    receiverTransport,
  );
  final oldPidDigest = _scopedDigest(context.runId, receiverTransition.oldPid);
  final freshPidDigest = _scopedDigest(
    context.runId,
    receiverTransition.freshPid,
  );
  final artifact = <String, Object?>{
    'schema': groupMediaReliabilityArtifactSchema,
    'authority_mode': context.authorityMode,
    'strict_media_custody': ?strictProof,
    'strict_authority_setup': ?authoritySetup,
    'run_id': context.runId,
    'scenario': groupMediaForegroundRetryAclRoundtripScenario,
    'prepared_artifact': <String, Object?>{
      'profile': context.preparedArtifact.profile,
      'application_id': groupMediaReliabilityAndroidPackageName,
      'sha256': context.preparedArtifact.sha256Digest,
      'child_builds': 0,
    },
    'device_roles': <String, Object?>{
      'sender': <String, Object?>{
        'platform': 'android',
        'kind': 'physical',
        'device_sha256': senderTransportDigest,
      },
      'receiver': <String, Object?>{
        'platform': 'android',
        'kind': 'emulator',
        'device_sha256': receiverTransportDigest,
      },
    },
    'identity_fingerprints': <String, Object?>{
      'sender': <String, Object?>{
        'account_sha256': _scopedDigest(context.runId, senderAccount),
        'transport_sha256': senderTransportDigest,
      },
      'receiver': <String, Object?>{
        'account_sha256': _scopedDigest(context.runId, receiverAccount),
        'transport_sha256': receiverTransportDigest,
      },
    },
    'account_vs_transport_discriminator': <String, Object?>{
      'sender': senderAccount != senderTransport,
      'receiver': receiverAccount != receiverTransport,
    },
    'acl_entries': <Object?>[senderTransportDigest, receiverTransportDigest],
    'media': <String, Object?>{
      'uploads_per_blob': uploads,
      'publications_per_message': publications,
      'download_attempts': downloadAttempts,
      'rendered_surfaces': renderedKinds,
    },
    'role_databases': <String, Object?>{
      'sender': senderAfterRestartDb.toArtifact(),
      'receiver': receiverAfterRestartDb.toArtifact(),
    },
    'retry_passes': <String, Object?>{
      'second_upload_work': 0,
      'second_download_work': 0,
    },
    'cleanup': <String, Object?>{
      'application_id': groupMediaReliabilityAndroidPackageName,
      'artifact_sha256': context.preparedArtifact.sha256Digest,
      for (final role in const <String>['sender', 'receiver'])
        role: <String, Object?>{
          'pre_reset': _resetReceiptArtifact(
            context.runId,
            role,
            preResetReceipts[role]!,
          ),
          'post_reset': _resetReceiptArtifact(
            context.runId,
            role,
            postResetReceipts[role]!,
          ),
        },
      'receipts_distinct': true,
      'app_left_installed': true,
      'production_package_commands': commandSafety.productionPackageCommands,
      'uninstall_commands': commandSafety.uninstallCommands,
      'pm_clear_commands': commandSafety.pmClearCommands,
      'broad_delete_commands': commandSafety.broadDeleteCommands,
    },
    'flow_events': <Object?>[
      _flowEvent(1, 'sender_uploads_settled', 'sender', <String, Object?>{
        'count': 3,
      }),
      _flowEvent(2, 'sender_publications_settled', 'sender', <String, Object?>{
        'count': 3,
      }),
      _flowEvent(
        3,
        'receiver_jpeg_post_claim_pre_commit',
        'receiver',
        <String, Object?>{
          'barrier_name': expectedBarrierName,
          'marker_atomic': true,
          'prior_status': expectedPriorStatus,
          'attempt': 1,
          'old_pid_sha256': oldPidDigest,
        },
      ),
      _flowEvent(4, 'receiver_process_force_stopped', 'host', <String, Object?>{
        'old_pid_sha256': oldPidDigest,
        'old_pid_gone': true,
      }),
      _flowEvent(5, 'receiver_process_relaunched', 'host', <String, Object?>{
        'old_pid_sha256': oldPidDigest,
        'fresh_pid_sha256': freshPidDigest,
        'launcher_only': true,
        'pid_changed': true,
      }),
      _flowEvent(6, 'receiver_prior_status_read', 'receiver', <String, Object?>{
        'prior_status': expectedPriorStatus,
        'after_relaunch': true,
        'attempt': 2,
      }),
      _flowEvent(7, 'receiver_downloads_settled', 'receiver', <String, Object?>{
        'settled_attachment_count': 3,
        'first_pass_work': receiverFirstDownload,
      }),
      _flowEvent(8, 'receiver_media_rendered', 'receiver', <String, Object?>{
        'jpeg_decoder_frame': true,
        'mp4_thumbnail_frame': true,
        'voice_player_loaded': true,
      }),
      _flowEvent(9, 'second_retry_pass_zero', 'host', <String, Object?>{
        'scope': 'sender_post_render',
        'upload_work': 0,
        'download_work': 0,
      }),
    ],
  };
  final validation = validateGroupMediaReliabilityArtifact(artifact);
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(artifact);
}

Future<void> retainGroupMediaEndpointFailure({
  required Directory directory,
  required Map<String, Object?> config,
  required Map<String, Object?> result,
  required String safeErrorCode,
}) async {
  final receipt = <String, Object?>{
    for (final key in const [
      'schema',
      'scenario',
      'buildProfile',
      'stepId',
      'phase',
      'role',
      'runId',
      'nonce',
    ])
      key: result[key],
    'status': 'failed',
    'success': false,
    'errorCode': safeErrorCode,
    if (result['errorType'] is String &&
        RegExp(r'^[A-Za-z]{1,64}$').hasMatch(result['errorType'] as String))
      'errorType': result['errorType'],
    if (result['phase'] == 'receiver_recover' &&
        const {
          'priorBoundary',
          'firstUpload',
          'firstDownload',
          'secondUpload',
          'secondDownload',
          'attemptCounts',
          'roleDatabase',
        }.contains(result['recoveryStage'])) ...{
      'recoveryStage': result['recoveryStage'],
      for (final key in const [
        'firstUploadWork',
        'firstDownloadWork',
        'secondUploadWork',
        'secondDownloadWork',
      ])
        if (result[key] is int && (result[key]! as int) >= 0) key: result[key],
      if (result['downloadAttempts'] case final Map attempts)
        'downloadAttempts': <String, int>{
          for (final kind in const ['jpeg', 'mp4', 'voice'])
            if (attempts[kind] is int && (attempts[kind]! as int) >= 0)
              kind: attempts[kind]! as int,
        },
    },
    if (const [
      'authority_admission',
      'authority_rotation',
      'authority_settlement',
      'authority_membership',
      'fixture_material',
      'legacy_upload',
      'legacy_publication',
      'strict_preparation',
      'strict_publication',
      'strict_custody_join',
    ].contains(result['senderStage']))
      'senderStage': result['senderStage'],
    if (const ['jpeg', 'mp4', 'voice'].contains(result['mediaKind']))
      'mediaKind': result['mediaKind'],
    if (safeErrorCode == 'sender_strict_preparation' &&
        result['senderStage'] == 'strict_preparation' &&
        ((result['preparationState'] == 'refused' &&
                result['preparationHasDurableAuthority'] is bool) ||
            (result['preparationState'] == 'retained' &&
                result['preparationHasDurableAuthority'] == true) ||
            (result['preparationState'] == 'legacyUninitialized' &&
                result['preparationHasDurableAuthority'] == false))) ...{
      'preparationState': result['preparationState'],
      'preparationHasDurableAuthority':
          result['preparationHasDurableAuthority'],
      if (result['preparationState'] == 'retained' &&
          result['preparationUploadResponseOk'] is bool) ...{
        'preparationUploadResponseOk': result['preparationUploadResponseOk'],
        if (result['preparationUploadResponseOk'] == false &&
            const {
              'MEDIA_CUSTODY_ADMISSION_DISABLED',
              'MEDIA_CUSTODY_FULL',
              'MEDIA_CUSTODY_UNSUPPORTED',
              'MEDIA_CUSTODY_IDENTITY_CONFLICT',
              'MEDIA_CUSTODY_INELIGIBLE',
              'MEDIA_CUSTODY_NOT_AUTHORIZED',
              'MEDIA_CUSTODY_HASH_MISMATCH',
              'MEDIA_CUSTODY_ALREADY_ACKED',
              'MEDIA_CUSTODY_CLEANUP_PENDING',
              'MEDIA_CUSTODY_STORAGE_ERROR',
              'MEDIA_CUSTODY_NOT_FOUND',
              'MEDIA_CUSTODY_COMMIT_INDETERMINATE',
              'MEDIA_ERROR',
              'NOT_INITIALIZED',
              'INVALID_INPUT',
              'INTERNAL_ERROR',
              'UNKNOWN_COMMAND',
              'NULL_RESPONSE',
              'MISSING_PLUGIN',
              'PLATFORM_ERROR',
              'BRIDGE_EXCEPTION',
              'MALFORMED_RESPONSE',
            }.contains(result['preparationUploadErrorCode']))
          'preparationUploadErrorCode': result['preparationUploadErrorCode'],
      },
    },
  };
  final bytes = utf8.encode(jsonEncode(receipt));
  final digest = sha256.convert(bytes).toString();
  try {
    await directory.create(recursive: true);
    final file = File('${directory.path}/endpoint-failure-$digest.json');
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
  } on FileSystemException {
    // Preserve the source failure; cleanup still runs in the controller finally.
  }
}

Map<String, Object?> _resetReceiptArtifact(
  String runId,
  String role,
  GroupMediaAndroidDisposableResetReceipt receipt,
) => <String, Object?>{
  'phase': receipt.phase,
  'receipt_sha256': receipt.sha256Digest,
  'process_id_sha256': _scopedDigest(
    runId,
    '$role:${receipt.phase}:${receipt.processId}',
  ),
  'profile': groupMediaReliabilityAndroidBuildProfile,
  'application_id': groupMediaReliabilityAndroidPackageName,
  'secure_storage_empty': true,
  'database_absent': true,
  'allowlisted_files_absent': true,
  'contains_secrets': false,
};

Set<String> groupMediaRenderedKindsFromUiXml(String xml) => <String>{
  for (final entry in _renderLabelsByKind.entries)
    if (xml.contains(entry.value)) entry.key,
};

bool androidGroupMediaPackageOwnsForeground({
  required String windowsDump,
  required String packageName,
}) => RegExp(
  r'm(?:CurrentFocus|FocusedApp)=[^\n]*' + RegExp.escape(packageName) + r'/',
).hasMatch(windowsDump);

String androidGroupMediaRenderFailureCode(Set<String> foundKinds) {
  final missing = _renderLabelsByKind.keys
      .where((kind) => !foundKinds.contains(kind))
      .toList(growable: false);
  return missing.isEmpty
      ? 'android_receiver_render_incomplete'
      : 'android_receiver_render_missing_${missing.join('_')}';
}

final class _RoleDatabaseObservation {
  const _RoleDatabaseObservation({
    required this.roleDbPath,
    required this.databasePathSha256,
    required this.cipherVersion,
    required this.userVersion,
    required this.rows,
  });

  factory _RoleDatabaseObservation.parse(
    Object? value, {
    required String role,
    required String runId,
    required Map<String, String> messageIds,
    required Map<String, String> attachmentIds,
    required bool requireRows,
    bool requireStrictSender = false,
  }) {
    final map = _object(value, '$role roleDatabase');
    final roleDbPath = map['role_db_path'];
    final databasePathSha256 = map['database_path_sha256'];
    final cipherVersion = map['cipher_version'];
    final userVersion = map['user_version'];
    final rawRows = map['rows'];
    if (roleDbPath != '$role/group-media.sqlite' ||
        databasePathSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(databasePathSha256) ||
        cipherVersion is! String ||
        cipherVersion.trim().isEmpty ||
        cipherVersion.length > 96 ||
        userVersion != currentIdentityDatabaseVersion ||
        rawRows is! List ||
        rawRows.length != (requireRows ? 3 : 0)) {
      throw FormatException('$role SQLCipher receipt is malformed');
    }
    final rows = <Map<String, Object?>>[];
    if (requireRows) {
      for (final indexed in rawRows.indexed) {
        final kind = const <String>['jpeg', 'mp4', 'voice'][indexed.$1];
        final row = _object(indexed.$2, '$role row $kind');
        if (row['run_id'] != runId ||
            row['media_kind'] != kind ||
            row['message_id'] != messageIds[kind] ||
            row['blob_id'] != attachmentIds[kind] ||
            (requireStrictSender
                ? !groupMediaStrictSenderPublicationMatches(row)
                : row['status'] != 'done' ||
                      row.containsKey('strict_publication')) ||
            row['upload_retry_count'] != 0 ||
            row['download_retry_count'] != 0) {
          throw FormatException('$role SQLCipher row $kind did not settle');
        }
        rows.add(Map<String, Object?>.unmodifiable(row));
      }
    }
    return _RoleDatabaseObservation(
      roleDbPath: roleDbPath as String,
      databasePathSha256: databasePathSha256,
      cipherVersion: cipherVersion,
      userVersion: userVersion as int,
      rows: List<Map<String, Object?>>.unmodifiable(rows),
    );
  }

  final String roleDbPath;
  final String databasePathSha256;
  final String cipherVersion;
  final int userVersion;
  final List<Map<String, Object?>> rows;

  bool sameDatabase(_RoleDatabaseObservation other) =>
      roleDbPath == other.roleDbPath &&
      databasePathSha256 == other.databasePathSha256 &&
      cipherVersion == other.cipherVersion &&
      userVersion == other.userVersion;

  Map<String, Object?> toArtifact() => <String, Object?>{
    'role_db_path': roleDbPath,
    'database_path_sha256': databasePathSha256,
    'cipher_version': cipherVersion,
    'user_version': userVersion,
    'reopened': true,
    'rows': rows,
  };
}

Map<String, Object?> _flowEvent(
  int sequence,
  String name,
  String role,
  Map<String, Object?> facts,
) => <String, Object?>{
  'sequence': sequence,
  'name': name,
  'role': role,
  'facts': facts,
};

Map<String, int> _exactKindCounts(
  Object? value,
  Map<String, int> expected,
  String label,
) {
  final map = _object(value, label);
  if (map.keys.toSet().length != 3 ||
      !map.keys.toSet().containsAll(const <String>{'jpeg', 'mp4', 'voice'})) {
    throw FormatException('$label lacks exact media kinds');
  }
  final result = <String, int>{};
  for (final entry in expected.entries) {
    if (map[entry.key] != entry.value) {
      throw FormatException('$label has wrong ${entry.key} count');
    }
    result[entry.key] = entry.value;
  }
  return Map<String, int>.unmodifiable(result);
}

List<String> _stringList(Object? value, String label) {
  if (value is! List || value.any((entry) => entry is! String)) {
    throw FormatException('$label must be a string list');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

int _int(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! int || item < 0) {
    throw FormatException('$key must be a non-negative integer');
  }
  return item;
}

int _positiveInt(Map<String, Object?> value, String key) {
  final item = _int(value, key);
  if (item == 0) throw FormatException('$key must be positive');
  return item;
}

String _requiredToken(
  Map<String, Object?> value,
  String key, {
  required int maxLength,
}) {
  final item = value[key];
  if (item is! String ||
      item.isEmpty ||
      item.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(item)) {
    throw FormatException('$key is not a safe identifier');
  }
  return item;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$label must be an object');
  }
  return value.map<String, Object?>(
    (key, item) => MapEntry(key as String, item),
  );
}

Map<String, Object?>? _optionalObject(Object? value) {
  if (value == null) return null;
  try {
    return _object(value, 'object');
  } on FormatException {
    return null;
  }
}

bool _sameStringMap(Object? value, Map<String, String> expected) {
  final map = _optionalObject(value);
  if (map == null || map.keys.toSet().length != expected.length) return false;
  return expected.entries.every((entry) => map[entry.key] == entry.value);
}

String _shortDigest(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 24);

String _scopedDigest(String runId, String value) =>
    sha256.convert(utf8.encode('$runId\u0000$value')).toString();
