#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e_contract.dart';

import 'group_media_ios_background_recovery_evidence.dart';
import '../support/android_app_state_guard.dart';
import '../support/group_media_android_disposable_app.dart';

const String _packageName = groupMediaAndroidDisposablePackageId;
const String _stateSchema = 'mknoon.group-media-ios-fixture-state.v1';
const String _readySchema = 'mknoon.group-media-ios-fixture-ready.v1';
const String _bundleId = groupMediaIosDisposableBundleId;
const Set<String> _actions = <String>{
  'phase-a-background-success',
  'phase-b-stop-at-post-claim',
  'phase-b-observe-recovery',
};
final RegExp _safe = RegExp(r'^[A-Za-z0-9._:-]{1,180}$');
final RegExp _iosDevice = RegExp(r'^[A-Fa-f0-9-]{24,64}$');
final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');
final Random _random = Random.secure();

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--host-probe') {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schema': 'mknoon.group-media-ios-fixture-host-probe.v1',
        'status': 'PASS',
        'containsSecrets': false,
      }),
    );
    return;
  }
  _Driver? driver;
  try {
    final options = _Options.parse(arguments, Platform.environment);
    driver = _Driver(options);
    await driver.run();
  } on _Blocked catch (error) {
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'BLOCKED',
        'blocker': error.blocker,
        'stage': driver?.failureStage ?? 'preflight',
        'containsSecrets': false,
      }),
    );
    exitCode = 78;
  } on Object catch (error) {
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'FAIL',
        'errorType': error.runtimeType.toString(),
        'stage': driver?.failureStage ?? 'preflight',
        'containsSecrets': false,
      }),
    );
    exitCode = 1;
  }
}

final class _Options {
  const _Options({
    required this.action,
    required this.runId,
    required this.senderDevice,
    required this.receiverDevice,
    required this.phaseAMessage,
    required this.phaseBMessage,
    required this.phaseAReady,
    required this.phaseBReady,
    required this.systemLog,
    required this.nativeObservation,
    required this.databaseObservation,
    required this.output,
    required this.androidArtifact,
    required this.androidArtifactSha256,
    required this.androidCommandAudit,
    required this.relayAddresses,
    this.interruptedPid,
    this.ready,
    this.cancel,
  });

  final String action;
  final String runId;
  final String senderDevice;
  final String receiverDevice;
  final String phaseAMessage;
  final String phaseBMessage;
  final String phaseAReady;
  final String phaseBReady;
  final File systemLog;
  final File nativeObservation;
  final File databaseObservation;
  final File output;
  final File androidArtifact;
  final String androidArtifactSha256;
  final File androidCommandAudit;
  final String relayAddresses;
  final int? interruptedPid;
  final File? ready;
  final File? cancel;

  static _Options parse(List<String> values, Map<String, String> environment) {
    const valued = <String>{
      '--action',
      '--run-id',
      '--sender-device',
      '--receiver-device',
      '--phase-a-message',
      '--phase-b-message',
      '--phase-a-ready',
      '--phase-b-ready',
      '--system-log',
      '--interrupted-pid',
      '--ready',
      '--cancel',
      '--native-observation',
      '--database-observation',
      '--output',
      '--android-artifact',
      '--android-artifact-sha256',
      '--android-command-audit',
    };
    final parsed = <String, String>{};
    for (var index = 0; index < values.length; index += 2) {
      if (index + 1 >= values.length ||
          !valued.contains(values[index]) ||
          parsed.containsKey(values[index])) {
        throw const _Blocked('harness');
      }
      parsed[values[index]] = values[index + 1];
    }
    final required = valued.difference(<String>{
      '--interrupted-pid',
      '--ready',
      '--cancel',
    });
    if (!parsed.keys.toSet().containsAll(required) ||
        parsed.keys.any((key) => !valued.contains(key))) {
      throw const _Blocked('harness');
    }
    String value(String key) => parsed[key]?.trim() ?? '';
    final action = value('--action');
    final runId = value('--run-id');
    final sender = value('--sender-device');
    final receiver = value('--receiver-device');
    final phaseA = value('--phase-a-message');
    final phaseB = value('--phase-b-message');
    final phaseAReady = value('--phase-a-ready');
    final phaseBReady = value('--phase-b-ready');
    final interrupted = int.tryParse(value('--interrupted-pid'));
    final expectsInterrupted = action == 'phase-b-observe-recovery';
    final expectsReady = action != 'phase-b-observe-recovery';
    final readyValue = value('--ready');
    final cancelValue = value('--cancel');
    final relay = environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
    final artifact = File(value('--android-artifact')).absolute;
    final artifactSha256 = value('--android-artifact-sha256');
    if (!_actions.contains(action) ||
        !_safe.hasMatch(runId) ||
        !_safe.hasMatch(sender) ||
        sender.startsWith('emulator-') ||
        !_iosDevice.hasMatch(receiver) ||
        sender == receiver ||
        phaseA != 'P269-A-$runId' ||
        phaseB != 'P269-B-$runId' ||
        phaseAReady != 'P269-READY-A-$runId' ||
        phaseBReady != 'P269-READY-B-$runId' ||
        expectsInterrupted != (interrupted != null && interrupted > 0) ||
        expectsReady != readyValue.isNotEmpty ||
        expectsReady != cancelValue.isNotEmpty ||
        relay.isEmpty ||
        relay.contains(RegExp(r'[\r\n]')) ||
        environment['SIMS_CHILD_BUILDS_FORBIDDEN'] != '1' ||
        !_regularFile(artifact) ||
        !_digestPattern.hasMatch(artifactSha256) ||
        sha256.convert(artifact.readAsBytesSync()).toString() !=
            artifactSha256) {
      throw const _Blocked('environment');
    }
    final systemLog = File(value('--system-log')).absolute;
    final native = File(value('--native-observation')).absolute;
    final database = File(value('--database-observation')).absolute;
    final output = File(value('--output')).absolute;
    final androidCommandAudit = File(value('--android-command-audit')).absolute;
    final ready = expectsReady ? File(readyValue).absolute : null;
    final cancel = expectsReady ? File(cancelValue).absolute : null;
    if (!_regularFile(systemLog) ||
        (systemLog.statSync().mode & 0x3f) != 0 ||
        <String>{
              native.path,
              database.path,
              output.path,
              androidCommandAudit.path,
              systemLog.path,
              if (ready != null) ready.path,
              if (cancel != null) cancel.path,
            }.length !=
            (ready == null ? 5 : 7) ||
        <File>[
          native,
          database,
          output,
          androidCommandAudit,
          ?ready,
        ].any((file) => file.existsSync()) ||
        native.parent.path != output.parent.path ||
        database.parent.path != output.parent.path ||
        androidCommandAudit.parent.path != output.parent.path ||
        (ready != null && ready.parent.path != output.parent.path) ||
        (cancel != null && cancel.parent.path != output.parent.path) ||
        cancel?.existsSync() == true) {
      throw const _Blocked('harness');
    }
    return _Options(
      action: action,
      runId: runId,
      senderDevice: sender,
      receiverDevice: receiver,
      phaseAMessage: phaseA,
      phaseBMessage: phaseB,
      phaseAReady: phaseAReady,
      phaseBReady: phaseBReady,
      systemLog: systemLog,
      nativeObservation: native,
      databaseObservation: database,
      output: output,
      androidArtifact: artifact,
      androidArtifactSha256: artifactSha256,
      androidCommandAudit: androidCommandAudit,
      relayAddresses: relay,
      interruptedPid: interrupted,
      ready: ready,
      cancel: cancel,
    );
  }
}

final class _Driver {
  _Driver(this.options);

  final _Options options;
  final GroupMediaAndroidCommandAudit _androidCommandAudit =
      GroupMediaAndroidCommandAudit();
  String failureStage = 'start';
  late final AndroidHostProcessRunner _commandRunner =
      GroupMediaAndroidCommandAuditingRunner(
        delegate: GroupMediaIosFixtureProcessRunner(),
        audit: _androidCommandAudit,
      );
  late final File _stateFile = File(
    '${options.output.parent.path}/fixture-state.json',
  );

  Future<void> run() async {
    await options.output.parent.create(recursive: true);
    await _chmod('700', options.output.parent.path);
    try {
      try {
        switch (options.action) {
          case 'phase-a-background-success':
            await _phaseA();
          case 'phase-b-stop-at-post-claim':
            await _phaseBClaim();
          case 'phase-b-observe-recovery':
            await _phaseBRecovery();
        }
      } on Object {
        await _deleteState();
        rethrow;
      }
    } finally {
      await _writeAndroidCommandAudit();
    }
  }

  Future<void> _writeAndroidCommandAudit() {
    final snapshot = _androidCommandAudit.snapshot;
    return _writePrivate(options.androidCommandAudit, <String, Object?>{
      'schema': groupMediaAndroidCommandAuditSchema,
      'run_id': options.runId,
      'action': options.action,
      'adb_command_count': snapshot.adbCommandCount,
      'journal_sha256': snapshot.journalSha256,
      'production_package_commands': snapshot.productionPackageCommands,
      'uninstall_commands': snapshot.uninstallCommands,
      'pm_clear_commands': snapshot.pmClearCommands,
      'broad_delete_commands': snapshot.broadDeleteCommands,
      'contains_secrets': false,
    });
  }

  Future<void> _phaseA() async {
    if (_stateFile.existsSync()) throw const _Blocked('harness');
    final logStart = options.systemLog.readAsStringSync().length;
    failureStage = 'phase_a_ios_identity';
    final receiver = await _endpoint(
      platform: 'ios',
      device: options.receiverDevice,
      config: _config(phase: groupMediaIosIdentityPhase, role: 'receiver'),
    );
    final receiverIdentity = _identity(receiver, role: 'receiver');
    failureStage = 'phase_a_android_sender';
    late final Map<String, Object?> observationConfig;
    final phase = await _withFreshAndroidSender((senderIdentity) async {
      failureStage = 'phase_a_contact_exchange';
      await _exchangeContacts(senderIdentity, receiverIdentity);
      failureStage = 'phase_a_group_setup';
      final prepared = await _setupPhase(
        mediaPhase: 'a',
        sender: senderIdentity,
        receiver: receiverIdentity,
      );
      observationConfig = _config(
        phase: groupMediaIosReceiverObservePhase,
        role: 'receiver',
        mediaPhase: 'a',
        messageId: prepared.messageId,
        attachmentId: prepared.attachmentId,
        marker: options.phaseAMessage,
      );
      failureStage = 'phase_a_receiver_observe_stage';
      await _stageIosReceiverObservation(
        config: observationConfig,
        expectedProcessId: receiverIdentity.processId,
      );
      failureStage = 'phase_a_ready_publication';
      await _writeReady(mediaPhase: 'a');
      failureStage = 'phase_a_home_wait';
      await _waitForHome(
        receiverPid: receiverIdentity.processId,
        logStart: logStart,
      );
      failureStage = 'phase_a_send';
      await _sendPhase(
        phase: prepared,
        mediaPhase: 'a',
        receiver: receiverIdentity,
      );
      return prepared;
    });
    failureStage = 'phase_a_receiver_observe';
    final observed = await _awaitEndpointResult(
      platform: 'ios',
      config: observationConfig,
    );
    final receiverPid = _positiveInt(observed['processId'], 'receiver pid');
    if (receiverPid != receiverIdentity.processId ||
        observed['uiEffectPublished'] != true) {
      throw const _Failure('phase A receiver process/effect binding changed');
    }
    failureStage = 'phase_a_native_observation';
    final native = await _nativeObservation(
      phase: 'a',
      pid: receiverPid,
      logStart: logStart,
      expectEnd: true,
      requireFreshPid: null,
    );
    failureStage = 'phase_a_database_observation';
    final database = _databaseObservation(
      phase: 'a',
      endpoint: observed,
      message: options.phaseAMessage,
      barrier: 'background_receive_started',
      status: 'done',
      resumeAttempts: 0,
      expectedAttempts: 1,
    );
    failureStage = 'phase_a_receipt_publication';
    await _writeBoundReceipt(
      phase: 'a',
      receiverPid: receiverPid,
      relaunchPid: null,
      barrier: 'background_receive_started',
      terminalPath: 'normal',
      nativeEndCount: 1,
      durableStatus: 'done',
      resumeAttempts: 0,
      downloadAttempts: 1,
      native: native,
      database: database,
    );
    failureStage = 'phase_a_state_publication';
    await _writeState(<String, Object?>{
      'schema': _stateSchema,
      'runId': options.runId,
      'receiverAccountPeerId': receiverIdentity.accountPeerId,
      'receiverTransportPeerId': receiverIdentity.transportPeerId,
      'receiverQrPayload': receiverIdentity.qrPayload,
      'receiverMlKemPublicKey': receiverIdentity.mlKemPublicKey,
      'phaseAMessageId': phase.messageId,
      'phaseAAttachmentId': phase.attachmentId,
      'logOffsetAfterA': options.systemLog.readAsStringSync().length,
    });
  }

  Future<void> _phaseBClaim() async {
    failureStage = 'phase_b_state_read';
    final state = _readState();
    final persistedIdentity = _Identity(
      accountPeerId: _requiredString(state, 'receiverAccountPeerId'),
      transportPeerId: _requiredString(state, 'receiverTransportPeerId'),
      qrPayload: _requiredProtectedText(
        state,
        'receiverQrPayload',
        maximumLength: 16384,
      ),
      mlKemPublicKey: _requiredProtectedText(
        state,
        'receiverMlKemPublicKey',
        maximumLength: 4096,
      ),
      processId: 1,
    );
    failureStage = 'phase_b_ios_identity';
    final identityResult = await _endpoint(
      platform: 'ios',
      device: options.receiverDevice,
      config: _config(phase: groupMediaIosIdentityPhase, role: 'receiver'),
    );
    failureStage = 'phase_b_ios_identity_validation';
    final receiverIdentity = _identity(identityResult, role: 'receiver');
    failureStage = 'phase_b_ios_identity_continuity';
    if (!receiverIdentity.sameIdentityAs(persistedIdentity)) {
      throw const _Failure('phase B receiver identity changed');
    }
    final logStart = options.systemLog.readAsStringSync().length;
    late final Map<String, Object?> observationConfig;
    final phase = await _withFreshAndroidSender((senderIdentity) async {
      await _exchangeContacts(senderIdentity, receiverIdentity);
      final prepared = await _setupPhase(
        mediaPhase: 'b',
        sender: senderIdentity,
        receiver: receiverIdentity,
      );
      observationConfig = _config(
        phase: groupMediaIosReceiverObservePhase,
        role: 'receiver',
        mediaPhase: 'b',
        messageId: prepared.messageId,
        attachmentId: prepared.attachmentId,
      );
      failureStage = 'phase_b_receiver_observe_stage';
      await _stageIosReceiverObservation(
        config: observationConfig,
        expectedProcessId: receiverIdentity.processId,
      );
      failureStage = 'phase_b_ready_publication';
      await _writeReady(mediaPhase: 'b');
      failureStage = 'phase_b_home_wait';
      await _waitForHome(
        receiverPid: receiverIdentity.processId,
        logStart: logStart,
      );
      failureStage = 'phase_b_send';
      await _sendPhase(
        phase: prepared,
        mediaPhase: 'b',
        receiver: receiverIdentity,
      );
      return prepared;
    });
    failureStage = 'phase_b_receiver_observe';
    final observed = await _awaitEndpointResult(
      platform: 'ios',
      config: observationConfig,
    );
    final receiverPid = _positiveInt(observed['processId'], 'receiver pid');
    if (receiverPid != receiverIdentity.processId ||
        observed['uiEffectPublished'] == true) {
      throw const _Failure('phase B claim process/effect binding changed');
    }
    final native = await _nativeObservation(
      phase: 'b_claim',
      pid: receiverPid,
      logStart: logStart,
      expectEnd: false,
      requireFreshPid: null,
    );
    final database = _databaseObservation(
      phase: 'b_claim',
      endpoint: observed,
      message: options.phaseBMessage,
      barrier: 'durable_post_claim_pre_commit',
      status: 'downloading',
      resumeAttempts: 0,
      expectedAttempts: 1,
    );
    await _writeBoundReceipt(
      phase: 'b_claim',
      receiverPid: receiverPid,
      relaunchPid: null,
      barrier: 'durable_post_claim_pre_commit',
      terminalPath: 'none',
      nativeEndCount: 0,
      durableStatus: 'downloading',
      resumeAttempts: 0,
      downloadAttempts: 1,
      native: native,
      database: database,
    );
    state
      ..['phaseBMessageId'] = phase.messageId
      ..['phaseBAttachmentId'] = phase.attachmentId
      ..['phaseBInterruptedPid'] = receiverPid
      ..['phaseBLogOffset'] = logStart;
    await _writeState(state);
  }

  Future<void> _phaseBRecovery() async {
    try {
      failureStage = 'phase_b_recovery_state_read';
      final state = _readState();
      final interrupted = _positiveInt(
        state['phaseBInterruptedPid'],
        'interrupted pid',
      );
      if (options.interruptedPid != interrupted) {
        throw const _Failure('interrupted process binding changed');
      }
      final persistedIdentity = _Identity(
        accountPeerId: _requiredString(state, 'receiverAccountPeerId'),
        transportPeerId: _requiredString(state, 'receiverTransportPeerId'),
        qrPayload: _requiredProtectedText(
          state,
          'receiverQrPayload',
          maximumLength: 16384,
        ),
        mlKemPublicKey: _requiredProtectedText(
          state,
          'receiverMlKemPublicKey',
          maximumLength: 4096,
        ),
        processId: 1,
      );
      failureStage = 'phase_b_recovery_ios_identity';
      final liveIdentity = _identity(
        await _endpoint(
          platform: 'ios',
          device: options.receiverDevice,
          config: _config(phase: groupMediaIosIdentityPhase, role: 'receiver'),
        ),
        role: 'receiver',
      );
      if (!liveIdentity.sameIdentityAs(persistedIdentity) ||
          liveIdentity.processId == interrupted) {
        throw const _Failure('recovery receiver identity/process changed');
      }
      final messageId = _requiredString(state, 'phaseBMessageId');
      final attachmentId = _requiredString(state, 'phaseBAttachmentId');
      final observed = await _endpoint(
        platform: 'ios',
        device: options.receiverDevice,
        config: _config(
          phase: groupMediaIosReceiverRecoverPhase,
          role: 'receiver',
          mediaPhase: 'b',
          messageId: messageId,
          attachmentId: attachmentId,
          marker: options.phaseBMessage,
        ),
      );
      final relaunched = _positiveInt(observed['processId'], 'relaunch pid');
      if (relaunched != liveIdentity.processId ||
          observed['interruptedPid'] != interrupted ||
          observed['relaunchPid'] != relaunched ||
          observed['resumeAfterDrainAttempts'] != 1 ||
          observed['firstDownloadWork'] != 1 ||
          observed['secondDownloadWork'] != 0 ||
          observed['uiEffectPublished'] != true) {
        throw const _Failure('fresh-process recovery receipt rejected');
      }
      final logStart = _nonNegativeInt(state['phaseBLogOffset'], 'log offset');
      final native = await _nativeObservation(
        phase: 'b_recovery',
        pid: interrupted,
        logStart: logStart,
        expectEnd: false,
        requireFreshPid: relaunched,
      );
      final database = _databaseObservation(
        phase: 'b_recovery',
        endpoint: observed,
        message: options.phaseBMessage,
        barrier: 'resume_after_first_group_inbox_drain',
        status: 'done',
        resumeAttempts: 1,
        expectedAttempts: 2,
      );
      await _writeBoundReceipt(
        phase: 'b_recovery',
        receiverPid: interrupted,
        relaunchPid: relaunched,
        barrier: 'resume_after_first_group_inbox_drain',
        terminalPath: 'interrupted',
        nativeEndCount: 0,
        durableStatus: 'done',
        resumeAttempts: 1,
        downloadAttempts: 2,
        native: native,
        database: database,
      );
    } finally {
      await _deleteState();
    }
  }

  Future<T> _withFreshAndroidSender<T>(
    Future<T> Function(_Identity sender) body,
  ) async {
    await _writeAndroidFile(
      'auto_setup.json',
      jsonEncode(<String, Object?>{
        'username':
            'P269Pixel${_sha256('${options.runId}:${options.action}').substring(0, 10)}',
      }),
    );
    await _launchAndroid();
    final endpoint = await _endpoint(
      platform: 'android',
      device: options.senderDevice,
      config: _config(phase: groupMediaIosIdentityPhase, role: 'sender'),
    );
    return body(_identity(endpoint, role: 'sender'));
  }

  Future<void> _exchangeContacts(_Identity sender, _Identity receiver) async {
    await _endpoint(
      platform: 'android',
      device: options.senderDevice,
      config: _config(
        phase: groupMediaIosAddContactPhase,
        role: 'sender',
        peerQrPayload: receiver.qrPayload,
        peerMlKemPublicKey: receiver.mlKemPublicKey,
      ),
    );
    await _endpoint(
      platform: 'ios',
      device: options.receiverDevice,
      config: _config(
        phase: groupMediaIosAddContactPhase,
        role: 'receiver',
        peerQrPayload: sender.qrPayload,
        peerMlKemPublicKey: sender.mlKemPublicKey,
      ),
    );
  }

  Future<_Phase> _setupPhase({
    required String mediaPhase,
    required _Identity sender,
    required _Identity receiver,
  }) async {
    final messageId = 'p269-$mediaPhase-msg-${options.runId}';
    final attachmentId = 'p269-$mediaPhase-blob-${options.runId}';
    final groupName = 'P269-GROUP-${mediaPhase.toUpperCase()}-${options.runId}';
    final readiness = mediaPhase == 'a'
        ? options.phaseAReady
        : options.phaseBReady;
    failureStage = 'phase_${mediaPhase}_sender_setup_endpoint';
    final setup = await _endpoint(
      platform: 'android',
      device: options.senderDevice,
      config: _config(
        phase: groupMediaIosSenderSetupPhase,
        role: 'sender',
        mediaPhase: mediaPhase,
        marker: groupName,
        receiverAccountPeerId: receiver.accountPeerId,
        receiverTransportPeerId: receiver.transportPeerId,
      ),
    );
    failureStage = 'phase_${mediaPhase}_sender_setup_validation';
    final groupId = _token(setup['groupId'], 'group id');
    if (setup['accountPeerId'] != sender.accountPeerId ||
        setup['transportPeerId'] != sender.transportPeerId) {
      throw const _Failure('sender setup identity changed');
    }
    failureStage = 'phase_${mediaPhase}_receiver_arm_endpoint';
    final armed = await _endpoint(
      platform: 'ios',
      device: options.receiverDevice,
      config: _config(
        phase: groupMediaIosReceiverArmPhase,
        role: 'receiver',
        mediaPhase: mediaPhase,
        groupId: groupId,
        messageId: messageId,
        attachmentId: attachmentId,
        marker: readiness,
      ),
    );
    failureStage = 'phase_${mediaPhase}_receiver_arm_validation';
    if (armed['armed'] != true ||
        armed['accountPeerId'] != receiver.accountPeerId ||
        armed['transportPeerId'] != receiver.transportPeerId) {
      throw const _Failure('receiver arm identity changed');
    }
    return _Phase(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
    );
  }

  Future<void> _sendPhase({
    required _Phase phase,
    required String mediaPhase,
    required _Identity receiver,
  }) async {
    final marker = mediaPhase == 'a'
        ? options.phaseAMessage
        : options.phaseBMessage;
    final sent = await _endpoint(
      platform: 'android',
      device: options.senderDevice,
      config: _config(
        phase: groupMediaIosSenderSendPhase,
        role: 'sender',
        mediaPhase: mediaPhase,
        groupId: phase.groupId,
        messageId: phase.messageId,
        attachmentId: phase.attachmentId,
        marker: marker,
        receiverAccountPeerId: receiver.accountPeerId,
        receiverTransportPeerId: receiver.transportPeerId,
      ),
    );
    if (sent['messagePublished'] != true ||
        sent['uploadCount'] != 1 ||
        sent['publicationCount'] != 1 ||
        sent['allowedPeerCount'] != 2 ||
        sent['parentMarkerSha256'] !=
            _sha256(
              'P269-PARENT-${mediaPhase.toUpperCase()}-${options.runId}',
            )) {
      throw const _Failure('real media send did not settle exactly once');
    }
  }

  Future<void> _writeReady({required String mediaPhase}) async {
    final target = options.ready;
    if (target == null) throw const _Blocked('harness');
    await _writePrivate(target, <String, Object?>{
      'schema': _readySchema,
      'run_id': options.runId,
      'action': options.action,
      'media_phase': mediaPhase,
      'ready_label_sha256': _sha256(
        mediaPhase == 'a' ? options.phaseAReady : options.phaseBReady,
      ),
      'foreground_arm_complete': true,
    });
  }

  Future<void> _waitForHome({
    required int receiverPid,
    required int logStart,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      _throwIfHostCancelled();
      final raw = options.systemLog.readAsStringSync();
      if (logStart > raw.length) throw const _Failure('system log truncated');
      final segment = raw.substring(logStart);
      final count = _count(
        segment,
        'MKNOON_269_IOS_NATIVE event=home_background pid=$receiverPid',
      );
      if (count == 1) return;
      if (count > 1) {
        throw const _Failure('duplicate physical Home transition observed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const _Failure('physical Home transition was not observed');
  }

  void _throwIfHostCancelled() {
    final cancel = options.cancel;
    if (cancel == null || !cancel.existsSync()) return;
    if (!_regularFile(cancel) || (cancel.statSync().mode & 0x3f) != 0) {
      throw const _Failure('host cancellation receipt is unprotected');
    }
    final value = _object(jsonDecode(cancel.readAsStringSync()), 'cancel');
    if (value.keys.toSet().length != 4 ||
        value['schema'] != 'mknoon.group-media-ios-fixture-cancel.v1' ||
        value['run_id'] != options.runId ||
        value['cancel'] != true ||
        value['contains_secrets'] != false) {
      throw const _Failure('host cancellation receipt is invalid');
    }
    throw const _Failure('host cancelled the foreground fixture action');
  }

  Map<String, Object?> _config({
    required String phase,
    required String role,
    String? mediaPhase,
    String? groupId,
    String? messageId,
    String? attachmentId,
    String? marker,
    String? receiverAccountPeerId,
    String? receiverTransportPeerId,
    String? peerQrPayload,
    String? peerMlKemPublicKey,
  }) {
    final nonce = _sha256(
      '${options.runId}:$phase:$role:${mediaPhase ?? 'none'}:${_random.nextInt(1 << 32)}',
    );
    return <String, Object?>{
      'schema': groupMediaIosBackgroundE2ECommandSchema,
      'transport_action': groupMediaIosBackgroundE2EAction,
      'scenario': groupMediaIosBackgroundScenario,
      'stepId': 'p269-ios-$phase-${options.runId}',
      'phase': phase,
      'role': role,
      'runId': options.runId,
      'nonce': nonce,
      'mediaPhase': mediaPhase,
      'groupId': groupId,
      'messageId': messageId,
      'attachmentId': attachmentId,
      'marker': marker,
      'receiverAccountPeerId': receiverAccountPeerId,
      'receiverTransportPeerId': receiverTransportPeerId,
      'peerQrPayload': peerQrPayload,
      'peerMlKemPublicKey': peerMlKemPublicKey,
    };
  }

  Future<Map<String, Object?>> _endpoint({
    required String platform,
    required String device,
    required Map<String, Object?> config,
  }) async {
    if (platform == 'android') {
      await _deleteAndroidFile('intro_e2e_result.json');
      await _writeAndroidFile('intro_e2e_config.json', jsonEncode(config));
      await _launchAndroid();
    } else {
      await _writeIosFile('intro_e2e_config.json', jsonEncode(config));
    }
    return _awaitEndpointResult(platform: platform, config: config);
  }

  Future<void> _stageIosReceiverObservation({
    required Map<String, Object?> config,
    required int expectedProcessId,
  }) async {
    await _writeIosFile('intro_e2e_config.json', jsonEncode(config));
    final accepted = await _awaitEndpointResult(
      platform: 'ios',
      config: config,
      foregroundAcceptanceOnly: true,
      timeout: const Duration(seconds: 30),
    );
    if (accepted['processId'] != expectedProcessId) {
      throw const _Failure(
        'foreground receiver observation process binding changed',
      );
    }
  }

  Future<Map<String, Object?>> _awaitEndpointResult({
    required String platform,
    required Map<String, Object?> config,
    bool foregroundAcceptanceOnly = false,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final raw = platform == 'android'
          ? await _readAndroidFile('intro_e2e_result.json')
          : await _readIosFile('intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final result = decoded.map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            );
            if (result['schema'] == groupMediaIosBackgroundE2EResultSchema &&
                result['scenario'] == groupMediaIosBackgroundScenario &&
                result['stepId'] == config['stepId'] &&
                result['runId'] == options.runId &&
                result['nonce'] == config['nonce']) {
              final foregroundAccepted =
                  platform == 'ios' &&
                  _isForegroundObservationAcceptance(result, config);
              if (foregroundAcceptanceOnly) {
                if (foregroundAccepted) return result;
                throw const _Failure(
                  'foreground receiver observation acceptance was skipped',
                );
              }
              if (foregroundAccepted) {
                await Future<void>.delayed(const Duration(milliseconds: 200));
                continue;
              }
              if (result['success'] != true || result['status'] != 'complete') {
                final errorType = result['errorType'];
                if (errorType is String &&
                    RegExp(
                      r'^[A-Za-z][A-Za-z0-9_]{0,63}$',
                    ).hasMatch(errorType)) {
                  failureStage = '${failureStage}_failed_$errorType';
                } else {
                  failureStage = '${failureStage}_failed';
                }
                throw const _Failure('installed endpoint failed');
              }
              return result;
            }
          }
        } on FormatException {
          // Retry only an incomplete file-copy observation.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    failureStage = '${failureStage}_timeout';
    throw const _Failure('installed endpoint timed out');
  }

  bool _isForegroundObservationAcceptance(
    Map<String, Object?> result,
    Map<String, Object?> config,
  ) {
    const keys = <String>{
      'schema',
      'scenario',
      'stepId',
      'phase',
      'role',
      'runId',
      'nonce',
      'status',
      'success',
      'processId',
      'foregroundArmComplete',
    };
    final processId = result['processId'];
    return result.keys.toSet().length == keys.length &&
        result.keys.toSet().containsAll(keys) &&
        result['phase'] == groupMediaIosReceiverObservePhase &&
        result['phase'] == config['phase'] &&
        result['role'] == 'receiver' &&
        result['role'] == config['role'] &&
        result['status'] == 'accepted' &&
        result['success'] == false &&
        processId is int &&
        processId > 0 &&
        result['foregroundArmComplete'] == true;
  }

  _Identity _identity(Map<String, Object?> result, {required String role}) {
    final account = _token(result['accountPeerId'], '$role account');
    final transport = _token(result['transportPeerId'], '$role transport');
    final qrPayload = result['qrPayload'];
    final mlKem = result['mlKemPublicKey'];
    final processId = _positiveInt(result['processId'], '$role process id');
    if (account == transport ||
        qrPayload is! String ||
        qrPayload.isEmpty ||
        qrPayload.length > 16384 ||
        mlKem is! String ||
        mlKem.isEmpty ||
        mlKem.length > 4096) {
      throw const _Failure('installed identity export rejected');
    }
    if (_groupMediaIosQrPublicKey(qrPayload, account) == null) {
      throw const _Failure('signed identity export is unbound');
    }
    return _Identity(
      accountPeerId: account,
      transportPeerId: transport,
      qrPayload: qrPayload,
      mlKemPublicKey: mlKem,
      processId: processId,
    );
  }

  Future<Map<String, Object?>> _nativeObservation({
    required String phase,
    required int pid,
    required int logStart,
    required bool expectEnd,
    required int? requireFreshPid,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    String segment = '';
    while (DateTime.now().isBefore(deadline)) {
      final raw = options.systemLog.readAsStringSync();
      if (logStart > raw.length) throw const _Failure('system log truncated');
      segment = raw.substring(logStart);
      final home = _count(
        segment,
        'MKNOON_269_IOS_NATIVE event=home_background pid=$pid',
      );
      final grants = _countMatch(
        segment,
        RegExp('BG_TASK_GRANTED[^\n]*pid=$pid(?![0-9])'),
      );
      final ends = _countMatch(
        segment,
        RegExp('BG_TASK_ENDED[^\n]*terminal=normal[^\n]*pid=$pid(?![0-9])'),
      );
      final fresh =
          requireFreshPid == null ||
          _count(
                segment,
                'MKNOON_269_IOS_NATIVE event=process_launch pid=$requireFreshPid',
              ) ==
              1;
      if (home == 1 && grants == 1 && ends == (expectEnd ? 1 : 0) && fresh) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final home = _count(
      segment,
      'MKNOON_269_IOS_NATIVE event=home_background pid=$pid',
    );
    final grants = _countMatch(
      segment,
      RegExp('BG_TASK_GRANTED[^\n]*pid=$pid(?![0-9])'),
    );
    final ends = _countMatch(
      segment,
      RegExp('BG_TASK_ENDED[^\n]*terminal=normal[^\n]*pid=$pid(?![0-9])'),
    );
    final expiries = _countMatch(
      segment,
      RegExp('BG_TASK_EXPIRED[^\n]*pid=$pid(?![0-9])'),
    );
    final refusals = _countMatch(
      segment,
      RegExp('BG_TASK_REFUSED[^\n]*pid=$pid(?![0-9])'),
    );
    final freshLaunches = requireFreshPid == null
        ? 0
        : _count(
            segment,
            'MKNOON_269_IOS_NATIVE event=process_launch pid=$requireFreshPid',
          );
    if (home != 1 ||
        grants != 1 ||
        ends != (expectEnd ? 1 : 0) ||
        expiries != 0 ||
        refusals != 0 ||
        (requireFreshPid != null && freshLaunches != 1)) {
      throw const _Failure('physical idevicesyslog boundary rejected');
    }
    return <String, Object?>{
      'schema': groupMediaIosNativeObservationSchema,
      'run_id': options.runId,
      'phase': phase,
      'source': 'physical_idevicesyslog',
      'receiver_device_sha256': _receiverDigest,
      'home_observed': true,
      'critical_task_granted': true,
      'terminal_path': switch (phase) {
        'a' => 'normal',
        'b_claim' => 'none',
        _ => 'interrupted',
      },
      'native_end_count': expectEnd ? 1 : 0,
      'receiver_pid': pid,
      'host_kill_observed': phase == 'b_recovery',
    };
  }

  Map<String, Object?> _databaseObservation({
    required String phase,
    required Map<String, Object?> endpoint,
    required String message,
    required String barrier,
    required String status,
    required int resumeAttempts,
    required int expectedAttempts,
  }) {
    final database = _object(endpoint['database'], 'database');
    final mediaPhase = phase == 'a' ? 'a' : 'b';
    final parentMessage =
        'P269-PARENT-${mediaPhase.toUpperCase()}-${options.runId}';
    final databasePathDigest = database['databasePathSha256'];
    if (endpoint['barrier'] !=
            (phase == 'b_recovery'
                ? 'durable_post_claim_pre_commit'
                : barrier) ||
        endpoint['durableStatus'] != status ||
        endpoint['downloadAttempts'] != expectedAttempts ||
        database['databaseReopened'] != true ||
        database['userVersion'] != 104 ||
        database['rowCount'] != 1 ||
        database['markerSha256'] != _sha256(parentMessage) ||
        databasePathDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(databasePathDigest) ||
        database['durableStatus'] != status ||
        database['downloadRetryCount'] != 0 ||
        database['cipherVersion'] is! String ||
        !RegExp(
          r'^SQLCipher [0-9]+\.[0-9]+\.[0-9]+$',
        ).hasMatch(database['cipherVersion']! as String)) {
      throw const _Failure('reopened production SQLCipher boundary rejected');
    }
    return <String, Object?>{
      'schema': groupMediaIosDatabaseObservationSchema,
      'run_id': options.runId,
      'phase': phase,
      'source': 'production_sqlcipher',
      'receiver_device_sha256': _receiverDigest,
      'parent_message_sha256': _sha256(parentMessage),
      'ui_effect_sha256': _sha256(message),
      'database_path_sha256': databasePathDigest,
      'database_reopened': true,
      'cipher_version': database['cipherVersion'],
      'user_version': 104,
      'barrier': barrier,
      'durable_status': status,
      'download_attempts': expectedAttempts,
      'resume_after_drain_attempts': resumeAttempts,
    };
  }

  Future<void> _writeBoundReceipt({
    required String phase,
    required int receiverPid,
    required int? relaunchPid,
    required String barrier,
    required String terminalPath,
    required int nativeEndCount,
    required String durableStatus,
    required int resumeAttempts,
    required int downloadAttempts,
    required Map<String, Object?> native,
    required Map<String, Object?> database,
  }) async {
    await _writePrivate(options.nativeObservation, native);
    await _writePrivate(options.databaseObservation, database);
    await _writePrivate(options.output, <String, Object?>{
      'schema': groupMediaIosFixtureReceiptSchema,
      'run_id': options.runId,
      'phase': phase,
      'sender_device_sha256': _senderDigest,
      'receiver_device_sha256': _receiverDigest,
      'ui_effect_sha256': _sha256(
        phase == 'a' ? options.phaseAMessage : options.phaseBMessage,
      ),
      'parent_message_sha256': _sha256(
        'P269-PARENT-${phase == 'a' ? 'A' : 'B'}-${options.runId}',
      ),
      'receiver_pid': receiverPid,
      'relaunch_pid': relaunchPid,
      'barrier': barrier,
      'critical_task_granted': true,
      'terminal_path': terminalPath,
      'native_end_count': nativeEndCount,
      'durable_status': durableStatus,
      'download_attempts': downloadAttempts,
      'resume_after_drain_attempts': resumeAttempts,
      'native_observation_sha256': groupMediaIosObservationDigest(native),
      'database_observation_sha256': groupMediaIosObservationDigest(database),
    });
  }

  String get _senderDigest =>
      _sha256('${options.runId}:sender:${options.senderDevice}');
  String get _receiverDigest =>
      _sha256('${options.runId}:receiver:${options.receiverDevice}');

  Future<void> _launchAndroid() async {
    final resolved = await _run('adb', <String>[
      '-s',
      options.senderDevice,
      'shell',
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '--user',
      '0',
      _packageName,
    ]);
    final component = '${resolved.stdout}'.trim().split(RegExp(r'\s+')).last;
    if (resolved.exitCode != 0 ||
        !RegExp(
          '^${RegExp.escape(_packageName)}'
          r'/[A-Za-z0-9_.$]+$',
        ).hasMatch(component)) {
      throw const _Failure('Android sender launcher resolution failed');
    }
    final result = await _run('adb', <String>[
      '-s',
      options.senderDevice,
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      component,
    ]);
    if (result.exitCode != 0 || !'${result.stdout}'.contains('Status: ok')) {
      throw const _Failure('Android sender launch failed');
    }
  }

  Future<void> _writeAndroidFile(String name, String contents) async {
    _fileName(name);
    final local = File(
      '${options.output.parent.path}/.android-$name-$pid-${_random.nextInt(1 << 32)}',
    );
    final remote = '/data/local/tmp/p269-$pid-${_random.nextInt(1 << 32)}';
    try {
      await local.writeAsString(contents, flush: true);
      await _chmod('600', local.path);
      await _required('adb', <String>[
        '-s',
        options.senderDevice,
        'push',
        local.path,
        remote,
      ]);
      await _required('adb', <String>[
        '-s',
        options.senderDevice,
        'shell',
        'run-as',
        _packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _required('adb', <String>[
        '-s',
        options.senderDevice,
        'shell',
        'run-as',
        _packageName,
        'cp',
        remote,
        'app_flutter/$name',
      ]);
    } finally {
      await _run('adb', <String>[
        '-s',
        options.senderDevice,
        'shell',
        'rm',
        '-f',
        remote,
      ]);
      if (await local.exists()) await local.delete();
    }
  }

  Future<String?> _readAndroidFile(String name) async {
    _fileName(name);
    final result = await _run('adb', <String>[
      '-s',
      options.senderDevice,
      'shell',
      'run-as',
      _packageName,
      'cat',
      'app_flutter/$name',
    ]);
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}';
  }

  Future<void> _deleteAndroidFile(String name) async {
    _fileName(name);
    await _run('adb', <String>[
      '-s',
      options.senderDevice,
      'shell',
      'run-as',
      _packageName,
      'rm',
      '-f',
      'app_flutter/$name',
    ]);
  }

  Future<void> _writeIosFile(String name, String contents) async {
    _fileName(name);
    final local = File(
      '${options.output.parent.path}/.ios-$name-$pid-${_random.nextInt(1 << 32)}',
    );
    try {
      await local.writeAsString(contents, flush: true);
      await _chmod('600', local.path);
      final result = await _run('xcrun', <String>[
        'devicectl',
        'device',
        'copy',
        'to',
        '--device',
        options.receiverDevice,
        '--source',
        local.path,
        '--destination',
        'Documents/$name',
        '--domain-type',
        'appDataContainer',
        '--domain-identifier',
        _bundleId,
        '--quiet',
      ]);
      if (result.exitCode != 0) {
        final boundedExitCode = result.exitCode.clamp(1, 255);
        failureStage = '${failureStage}_copy_to_exit_$boundedExitCode';
        throw const _Failure('iOS config staging failed');
      }
    } finally {
      if (await local.exists()) await local.delete();
    }
  }

  Future<String?> _readIosFile(String name) async {
    _fileName(name);
    final directory = await Directory.systemTemp.createTemp('p269-ios-read-');
    final destination = File('${directory.path}/$name');
    try {
      final result = await _run('xcrun', <String>[
        'devicectl',
        'device',
        'copy',
        'from',
        '--device',
        options.receiverDevice,
        '--source',
        'Documents/$name',
        '--destination',
        destination.path,
        '--domain-type',
        'appDataContainer',
        '--domain-identifier',
        _bundleId,
        '--quiet',
      ]);
      if (result.exitCode != 0) return null;
      return _regularFile(destination) ? destination.readAsStringSync() : null;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Map<String, Object?> _readState() {
    if (!_regularFile(_stateFile) || (_stateFile.statSync().mode & 0x3f) != 0) {
      throw const _Blocked('harness');
    }
    final state = _object(jsonDecode(_stateFile.readAsStringSync()), 'state');
    if (state['schema'] != _stateSchema || state['runId'] != options.runId) {
      throw const _Blocked('harness');
    }
    return state;
  }

  Future<void> _writeState(Map<String, Object?> state) =>
      _writePrivate(_stateFile, state);

  Future<void> _deleteState() async {
    if (await _stateFile.exists()) await _stateFile.delete();
  }

  Future<void> _writePrivate(File target, Object value) async {
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.pending-$pid-${_random.nextInt(1 << 32)}',
    );
    try {
      await temporary.writeAsString('${jsonEncode(value)}\n', flush: true);
      await _chmod('600', temporary.path);
      await temporary.rename(target.path);
      await _chmod('600', target.path);
      if (!_regularFile(target) || (target.statSync().mode & 0x3f) != 0) {
        throw const _Failure('protected evidence publication failed');
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _required(String executable, List<String> arguments) async {
    final result = await _run(executable, arguments);
    if (result.exitCode != 0) throw const _Failure('device command failed');
  }

  Future<ProcessResult> _run(String executable, List<String> arguments) async {
    return _commandRunner.run(executable, arguments);
  }
}

typedef GroupMediaIosFixtureProcessExecutor =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef GroupMediaIosFixtureCoreDeviceRecovery = Future<bool> Function();

Future<ProcessResult> _executeGroupMediaIosFixtureProcess(
  String executable,
  List<String> arguments,
) async {
  try {
    return await Process.run(
      executable,
      arguments,
    ).timeout(const Duration(seconds: 60));
  } on TimeoutException {
    return ProcessResult(pid, 124, '', 'device command timed out');
  } on ProcessException {
    throw const _Blocked('environment');
  }
}

Future<bool> _recoverGroupMediaIosFixtureCoreDevice() async {
  if (!Platform.isMacOS) return false;
  late final ProcessResult result;
  try {
    result = await Process.run('/usr/bin/killall', const <String>[
      '-TERM',
      'CoreDeviceService',
    ], runInShell: false).timeout(const Duration(seconds: 5));
  } on Object {
    return false;
  }
  if (result.exitCode != 0 && result.exitCode != 1) return false;
  await Future<void>.delayed(const Duration(seconds: 2));
  return true;
}

/// Recovers Apple's device service only around idempotent container copies.
///
/// A failed `copy to` can be replayed because it overwrites the same scoped
/// file. A non-zero `copy from` is normally an expected "result not ready"
/// poll and is replayed only after a host timeout. No process or app mutation
/// command is eligible.
final class GroupMediaIosFixtureProcessRunner
    implements AndroidHostProcessRunner {
  GroupMediaIosFixtureProcessRunner({
    this.execute = _executeGroupMediaIosFixtureProcess,
    this.recover = _recoverGroupMediaIosFixtureCoreDevice,
    this.maxRecoveries = 4,
  }) : assert(maxRecoveries >= 0);

  final GroupMediaIosFixtureProcessExecutor execute;
  final GroupMediaIosFixtureCoreDeviceRecovery recover;
  final int maxRecoveries;

  var _recoveries = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final result = await execute(executable, arguments);
    if (!_shouldRecover(executable, arguments, result.exitCode) ||
        _recoveries >= maxRecoveries) {
      return result;
    }
    _recoveries += 1;
    if (!await recover()) return result;
    return execute(executable, arguments);
  }

  bool _shouldRecover(String executable, List<String> arguments, int exitCode) {
    if (exitCode == 0 ||
        executable.replaceAll('\\', '/').split('/').last != 'xcrun' ||
        arguments.length < 4 ||
        arguments[0] != 'devicectl' ||
        arguments[1] != 'device' ||
        arguments[2] != 'copy') {
      return false;
    }
    if (arguments[3] == 'to') return true;
    return arguments[3] == 'from' && exitCode == 124;
  }
}

bool groupMediaIosIdentityContinuityMatches({
  required String accountPeerId,
  required String transportPeerId,
  required String qrPayload,
  required String mlKemPublicKey,
  required String otherAccountPeerId,
  required String otherTransportPeerId,
  required String otherQrPayload,
  required String otherMlKemPublicKey,
}) {
  if (accountPeerId != otherAccountPeerId ||
      transportPeerId != otherTransportPeerId ||
      mlKemPublicKey != otherMlKemPublicKey) {
    return false;
  }
  final publicKey = _groupMediaIosQrPublicKey(qrPayload, accountPeerId);
  final otherPublicKey = _groupMediaIosQrPublicKey(
    otherQrPayload,
    otherAccountPeerId,
  );
  return publicKey != null &&
      otherPublicKey != null &&
      publicKey == otherPublicKey;
}

String? _groupMediaIosQrPublicKey(
  String qrPayload,
  String expectedAccountPeerId,
) {
  try {
    final qr = jsonDecode(qrPayload);
    final publicKey = qr is Map ? qr['pk'] : null;
    if (qr is! Map ||
        qr['ns'] != expectedAccountPeerId ||
        publicKey is! String ||
        publicKey.isEmpty ||
        publicKey.length > 4096) {
      return null;
    }
    return publicKey;
  } on FormatException {
    return null;
  }
}

final class _Identity {
  const _Identity({
    required this.accountPeerId,
    required this.transportPeerId,
    required this.qrPayload,
    required this.mlKemPublicKey,
    required this.processId,
  });
  final String accountPeerId;
  final String transportPeerId;
  final String qrPayload;
  final String mlKemPublicKey;
  final int processId;

  bool sameIdentityAs(_Identity other) =>
      groupMediaIosIdentityContinuityMatches(
        accountPeerId: accountPeerId,
        transportPeerId: transportPeerId,
        qrPayload: qrPayload,
        mlKemPublicKey: mlKemPublicKey,
        otherAccountPeerId: other.accountPeerId,
        otherTransportPeerId: other.transportPeerId,
        otherQrPayload: other.qrPayload,
        otherMlKemPublicKey: other.mlKemPublicKey,
      );
}

final class _Phase {
  const _Phase({
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
  });
  final String groupId;
  final String messageId;
  final String attachmentId;
}

final class _Blocked implements Exception {
  const _Blocked(this.blocker);
  final String blocker;
}

final class _Failure implements Exception {
  const _Failure(this.detail);
  final String detail;
}

bool _regularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

String _token(Object? value, String label) {
  if (value is! String || !_safe.hasMatch(value)) {
    throw _Failure('$label rejected');
  }
  return value;
}

String _requiredString(Map<String, Object?> value, String key) =>
    _token(value[key], key);

String _requiredProtectedText(
  Map<String, Object?> value,
  String key, {
  required int maximumLength,
}) {
  final text = value[key];
  if (text is! String ||
      text.isEmpty ||
      text.length > maximumLength ||
      text.contains(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'))) {
    throw _Failure('$key rejected');
  }
  return text;
}

int _positiveInt(Object? value, String label) {
  if (value is! int || value <= 0) throw _Failure('$label rejected');
  return value;
}

int _nonNegativeInt(Object? value, String label) {
  if (value is! int || value < 0) throw _Failure('$label rejected');
  return value;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw _Failure('$label rejected');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

int _count(String source, String needle) => needle.allMatches(source).length;

int _countMatch(String source, RegExp pattern) =>
    pattern.allMatches(source).length;

void _fileName(String value) {
  if (!RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(value)) {
    throw const _Blocked('harness');
  }
}

Future<void> _chmod(String mode, String path) async {
  final result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode != 0) throw const _Blocked('harness');
}
