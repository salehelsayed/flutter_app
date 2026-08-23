import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'group_media_ios_background_e2e_contract.dart';
import 'group_reaction_notification_ios_setup_profile.dart';
export 'group_media_ios_background_e2e_contract.dart';

typedef GroupMediaIosLoadAttachment =
    Future<MediaAttachment?> Function(String attachmentId);
typedef GroupMediaIosIdentityExport = Future<Map<String, Object?>> Function();
typedef GroupMediaIosAddContact =
    Future<void> Function(String qrPayload, String? mlKemPublicKey);
typedef GroupMediaIosSetupSender =
    Future<Map<String, Object?>> Function(
      String receiverAccountPeerId,
      String receiverTransportPeerId,
      String groupName,
    );
typedef GroupMediaIosAcceptReceiver =
    Future<Map<String, Object?>?> Function(String groupId);
typedef GroupMediaIosSendFixture =
    Future<Map<String, Object?>> Function(
      String phase,
      String groupId,
      String messageId,
      String attachmentId,
      String marker,
      String receiverAccountPeerId,
      String receiverTransportPeerId,
    );
typedef GroupMediaIosDatabaseProbe =
    Future<Map<String, Object?>> Function(
      String phase,
      String messageId,
      String attachmentId,
    );
typedef GroupMediaIosDrainInbox = Future<void> Function();
typedef GroupMediaIosRetryDownloads = Future<int> Function();
typedef GroupMediaIosReleaseReceiveCriticalTask = Future<void> Function();
typedef GroupMediaIosReserveReceiveCriticalTask =
    Future<GroupMediaIosReleaseReceiveCriticalTask> Function();
typedef GroupMediaIosReceiverObservationAccepted = Future<void> Function();
typedef GroupMediaIosReceiverObservationComplete =
    Future<void> Function(Map<String, Object?> result);

@visibleForTesting
typedef GroupMediaIosBeforeAtomicStateReplace =
    Future<void> Function(String? barrier);

@visibleForTesting
typedef GroupMediaIosStateSnapshotRead = void Function(String? barrier);

@immutable
final class GroupMediaIosBackgroundE2ERequest {
  const GroupMediaIosBackgroundE2ERequest({
    required this.phase,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.mediaPhase,
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
    required this.marker,
    required this.receiverAccountPeerId,
    required this.receiverTransportPeerId,
    required this.peerQrPayload,
    required this.peerMlKemPublicKey,
  });

  factory GroupMediaIosBackgroundE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    const keys = <String>{
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'phase',
      'role',
      'runId',
      'nonce',
      'mediaPhase',
      'groupId',
      'messageId',
      'attachmentId',
      'marker',
      'receiverAccountPeerId',
      'receiverTransportPeerId',
      'peerQrPayload',
      'peerMlKemPublicKey',
    };
    if (config.keys.toSet().length != keys.length ||
        !config.keys.toSet().containsAll(keys) ||
        config['schema'] != groupMediaIosBackgroundE2ECommandSchema ||
        config['transport_action'] != groupMediaIosBackgroundE2EAction ||
        config['scenario'] != groupMediaIosBackgroundScenario) {
      throw const FormatException('iOS group-media request rejected');
    }
    final phase = _token(config['phase'], maxLength: 32);
    final role = _token(config['role'], maxLength: 16);
    final runId = _token(config['runId'], maxLength: 128);
    final nonce = _token(config['nonce'], maxLength: 128);
    final mediaPhase = _optionalToken(config['mediaPhase'], maxLength: 1);
    if (!const <String>{
          groupMediaIosIdentityPhase,
          groupMediaIosAddContactPhase,
          groupMediaIosSenderSetupPhase,
          groupMediaIosReceiverArmPhase,
          groupMediaIosSenderSendPhase,
          groupMediaIosReceiverObservePhase,
          groupMediaIosReceiverRecoverPhase,
        }.contains(phase) ||
        !const <String>{'sender', 'receiver'}.contains(role) ||
        config['stepId'] != 'p269-ios-$phase-$runId' ||
        (mediaPhase != null &&
            !const <String>{'a', 'b'}.contains(mediaPhase))) {
      throw const FormatException('iOS group-media phase tuple rejected');
    }
    final qr = _optionalText(config['peerQrPayload'], maxLength: 16384);
    final mlKem = _optionalText(config['peerMlKemPublicKey'], maxLength: 4096);
    return GroupMediaIosBackgroundE2ERequest(
      phase: phase,
      role: role,
      runId: runId,
      nonce: nonce,
      mediaPhase: mediaPhase,
      groupId: _optionalToken(config['groupId'], maxLength: 180),
      messageId: _optionalToken(config['messageId'], maxLength: 180),
      attachmentId: _optionalToken(config['attachmentId'], maxLength: 180),
      marker: _optionalToken(config['marker'], maxLength: 160),
      receiverAccountPeerId: _optionalToken(
        config['receiverAccountPeerId'],
        maxLength: 180,
      ),
      receiverTransportPeerId: _optionalToken(
        config['receiverTransportPeerId'],
        maxLength: 180,
      ),
      peerQrPayload: qr,
      peerMlKemPublicKey: mlKem,
    );
  }

  final String phase;
  final String role;
  final String runId;
  final String nonce;
  final String? mediaPhase;
  final String? groupId;
  final String? messageId;
  final String? attachmentId;
  final String? marker;
  final String? receiverAccountPeerId;
  final String? receiverTransportPeerId;
  final String? peerQrPayload;
  final String? peerMlKemPublicKey;

  String get stepId => 'p269-ios-$phase-$runId';
}

/// Durable controller for the physical-iOS post-claim interruption boundary.
///
/// Phase A records the real post-claim observation and lets the listener
/// finish. Phase B atomically records `downloading`, then intentionally never
/// releases the first process. Only a fresh process may release recovery after
/// an explicit group-inbox drain.
final class GroupMediaIosBackgroundE2EController {
  GroupMediaIosBackgroundE2EController({
    required this.enabled,
    required Directory stateDirectory,
    int? currentProcessId,
    @visibleForTesting
    GroupMediaIosBeforeAtomicStateReplace? beforeAtomicStateReplace,
    @visibleForTesting GroupMediaIosStateSnapshotRead? onStateSnapshotRead,
  }) : currentProcessId = currentProcessId ?? pid,
       _stateFile = File(
         '${stateDirectory.absolute.path}${Platform.pathSeparator}'
         'group_media_ios_background_state.json',
       ),
       _beforeAtomicStateReplace = beforeAtomicStateReplace,
       _onStateSnapshotRead = onStateSnapshotRead {
    if (enabled) _state = _readStateSnapshotSync();
    uiProofLabels = ValueNotifier<List<String>>(
      _labelsForState(_state, this.currentProcessId),
    );
  }

  factory GroupMediaIosBackgroundE2EController.forInstalledProfile({
    required Directory stateDirectory,
    String installedProfileId = const String.fromEnvironment(
      'SIMS_BUILD_PROFILE_ID',
    ),
  }) => GroupMediaIosBackgroundE2EController(
    enabled: installedProfileId == groupMediaIosBackgroundBuildProfile,
    stateDirectory: stateDirectory,
  );

  final bool enabled;
  final int currentProcessId;
  final File _stateFile;
  final GroupMediaIosBeforeAtomicStateReplace? _beforeAtomicStateReplace;
  final GroupMediaIosStateSnapshotRead? _onStateSnapshotRead;
  final Completer<void> _interruptionWait = Completer<void>();
  final _GroupMediaIosMutationQueue _stateMutations =
      _GroupMediaIosMutationQueue();
  late final ValueNotifier<List<String>> uiProofLabels;
  Map<String, Object?>? _state;
  int _writeSequence = 0;

  bool get holdsAutomaticRecovery {
    if (!enabled) return false;
    final state = _state ?? _readStateSnapshotSync();
    final phaseB = _map(_map(state?['phases'])?['b']);
    return phaseB?['barrier'] == 'durable_post_claim_pre_commit' &&
        phaseB?['recoveryReleased'] != true;
  }

  Future<void> arm({
    required String runId,
    required String phase,
    required String groupId,
    required String messageId,
    required String attachmentId,
    required String readinessMarker,
  }) async {
    _requireEnabled();
    if (!const <String>{'a', 'b'}.contains(phase) ||
        <String>[
          runId,
          groupId,
          messageId,
          attachmentId,
        ].any((value) => !_safeToken.hasMatch(value))) {
      throw const FormatException('iOS group-media barrier tuple rejected');
    }
    if (readinessMarker != 'P269-READY-${phase.toUpperCase()}-$runId') {
      throw const FormatException('iOS group-media readiness marker rejected');
    }
    await _stateMutations.run(() async {
      final current = await _readStateSnapshot();
      final next = current == null
          ? <String, Object?>{
              'schema': groupMediaIosBackgroundE2EStateSchema,
              'runId': runId,
              'phases': <String, Object?>{},
            }
          : _copyState(current);
      if (next['runId'] != runId ||
          next['schema'] != groupMediaIosBackgroundE2EStateSchema) {
        throw StateError('iOS group-media state belongs to another run');
      }
      final phases = _map(next['phases'])!;
      if (phases.containsKey(phase)) {
        throw StateError('iOS group-media phase is already armed');
      }
      phases[phase] = <String, Object?>{
        'groupId': groupId,
        'messageId': messageId,
        'attachmentId': attachmentId,
        'attempts': 0,
        'barrier': null,
        'barrierProcessId': null,
        'recoveryReleased': false,
        'recoveryProcessId': null,
        'resumeAfterDrainAttempts': 0,
        'readinessMarker': readinessMarker,
        'observationAccepted': false,
        'observationProcessId': null,
        'uiEffectMarker': null,
      };
      next['phases'] = phases;
      await _publishState(next);
    });
  }

  /// Makes the phase READY marker visible only after the foreground observer
  /// has read the exact durable tuple and published its PID-bound receipt.
  Future<void> markObservationReady({
    required String runId,
    required String phase,
    required String messageId,
    required String attachmentId,
  }) async {
    _requireEnabled();
    if (!const <String>{'a', 'b'}.contains(phase) ||
        <String>[
          runId,
          messageId,
          attachmentId,
        ].any((value) => !_safeToken.hasMatch(value))) {
      throw const FormatException(
        'iOS group-media observation readiness tuple rejected',
      );
    }
    final marked = await _mutateStateIfPresent<bool>((state) {
      final phases = _map(state['phases']);
      final phaseState = _map(phases?[phase]);
      if (state['runId'] != runId ||
          phaseState?['messageId'] != messageId ||
          phaseState?['attachmentId'] != attachmentId ||
          phaseState?['readinessMarker'] !=
              'P269-READY-${phase.toUpperCase()}-$runId') {
        throw StateError(
          'iOS group-media observation readiness lacks the armed tuple',
        );
      }
      if (phaseState?['observationAccepted'] == true ||
          phaseState?['observationProcessId'] != null) {
        throw StateError(
          'iOS group-media observation readiness is already claimed',
        );
      }
      phaseState!['observationAccepted'] = true;
      phaseState['observationProcessId'] = currentProcessId;
      phases![phase] = phaseState;
      state['phases'] = phases;
      return const _GroupMediaIosStateUpdate.changed(true);
    });
    if (marked != true) {
      throw StateError('iOS group-media observation readiness state is absent');
    }
  }

  Future<void> onPostClaimPreCommit({
    required MediaAttachment attachment,
    required GroupMediaIosLoadAttachment loadCurrentAttachment,
  }) async {
    if (!enabled) return;
    final shouldBlock = await _mutateStateIfPresent<bool>((state) async {
      final phases = _map(state['phases']);
      if (phases == null) {
        return const _GroupMediaIosStateUpdate.unchanged(false);
      }
      String? matchingPhase;
      Map<String, Object?>? phaseState;
      for (final phase in const <String>['a', 'b']) {
        final candidate = _map(phases[phase]);
        if (candidate?['attachmentId'] == attachment.id &&
            candidate?['messageId'] == attachment.messageId) {
          matchingPhase = phase;
          phaseState = candidate;
          break;
        }
      }
      if (matchingPhase == null || phaseState == null) {
        return const _GroupMediaIosStateUpdate.unchanged(false);
      }
      final current = await loadCurrentAttachment(attachment.id);
      if (current == null ||
          current.messageId != attachment.messageId ||
          current.downloadStatus != 'downloading') {
        throw StateError('iOS barrier lacks a durable downloading claim');
      }
      final attempts = ((phaseState['attempts'] as num?)?.toInt() ?? 0) + 1;
      phaseState['attempts'] = attempts;
      phaseState['barrierProcessId'] ??= currentProcessId;
      if (matchingPhase == 'a') {
        if (attempts != 1) {
          throw StateError('iOS fast path attempted the attachment twice');
        }
        phaseState['barrier'] = 'background_receive_started';
        phases[matchingPhase] = phaseState;
        state['phases'] = phases;
        return const _GroupMediaIosStateUpdate.changed(false);
      }
      if (attempts == 1) {
        phaseState['barrier'] = 'durable_post_claim_pre_commit';
        phases[matchingPhase] = phaseState;
        state['phases'] = phases;
        return const _GroupMediaIosStateUpdate.changed(true);
      }
      if (attempts != 2 || phaseState['recoveryReleased'] != true) {
        throw StateError('iOS interrupted phase retried outside recovery');
      }
      phases[matchingPhase] = phaseState;
      state['phases'] = phases;
      return const _GroupMediaIosStateUpdate.changed(false);
    });
    if (shouldBlock == true) await _interruptionWait.future;
  }

  Future<Map<String, Object?>> releaseRecoveryAfterInboxDrain({
    required String runId,
    required GroupMediaIosLoadAttachment loadCurrentAttachment,
  }) async {
    _requireEnabled();
    final result = await _mutateStateIfPresent<Map<String, Object?>>((
      state,
    ) async {
      final phases = _map(state['phases']);
      final phaseB = _map(phases?['b']);
      final oldPid = (phaseB?['barrierProcessId'] as num?)?.toInt();
      final attachmentId = phaseB?['attachmentId'];
      if (state['runId'] != runId ||
          phaseB?['barrier'] != 'durable_post_claim_pre_commit' ||
          phaseB?['recoveryReleased'] == true ||
          oldPid == null ||
          oldPid == currentProcessId ||
          attachmentId is! String) {
        throw StateError('iOS recovery lacks a fresh interrupted process');
      }
      final current = await loadCurrentAttachment(attachmentId);
      if (current == null || current.downloadStatus != 'downloading') {
        throw StateError('iOS recovery lost prior downloading authority');
      }
      phaseB!['recoveryReleased'] = true;
      phaseB['recoveryProcessId'] = currentProcessId;
      phaseB['resumeAfterDrainAttempts'] = 1;
      phases!['b'] = phaseB;
      state['phases'] = phases;
      return _GroupMediaIosStateUpdate.changed(<String, Object?>{
        'priorStatus': current.downloadStatus,
        'interruptedPid': oldPid,
        'relaunchPid': currentProcessId,
        'resumeAfterDrainAttempts': 1,
      });
    });
    if (result == null) {
      throw StateError('iOS group-media recovery state is absent');
    }
    return result;
  }

  /// Publishes the only XCTest-visible media effect after the exact durable
  /// attachment has settled. An ordinary parent message cannot create this
  /// compile-gated marker.
  Future<void> publishDurableUiEffect({
    required String runId,
    required String phase,
    required String marker,
    required GroupMediaIosLoadAttachment loadCurrentAttachment,
  }) async {
    _requireEnabled();
    if (!const <String>{'a', 'b'}.contains(phase) ||
        marker != 'P269-${phase.toUpperCase()}-$runId') {
      throw const FormatException('iOS durable UI effect tuple rejected');
    }
    final published = await _mutateStateIfPresent<bool>((state) async {
      final phases = _map(state['phases']);
      final phaseState = _map(phases?[phase]);
      final attachmentId = phaseState?['attachmentId'];
      final attempts = (phaseState?['attempts'] as num?)?.toInt();
      final hasFastBarrier =
          phaseState?['barrier'] == 'background_receive_started';
      final recoveryReleased = phaseState?['recoveryReleased'] == true;
      if (state['runId'] != runId ||
          attachmentId is! String ||
          phaseState?['uiEffectMarker'] != null ||
          attempts != (phase == 'a' ? 1 : 2) ||
          (phase == 'a' ? !hasFastBarrier : !recoveryReleased)) {
        throw StateError('iOS durable UI effect lacks settled authority');
      }
      final current = await loadCurrentAttachment(attachmentId);
      if (current == null || current.downloadStatus != 'done') {
        throw StateError('iOS durable UI effect preceded media settlement');
      }
      phaseState!['uiEffectMarker'] = marker;
      phases![phase] = phaseState;
      state['phases'] = phases;
      return const _GroupMediaIosStateUpdate.changed(true);
    });
    if (published != true) {
      throw StateError('iOS durable UI effect state is absent');
    }
  }

  Future<Map<String, Object?>> observe({
    required String runId,
    required String phase,
    required String messageId,
    required String attachmentId,
    required GroupMediaIosLoadAttachment loadCurrentAttachment,
  }) async {
    _requireEnabled();
    // Polling reads the durable file and never publishes over an in-flight
    // copy-on-write mutation.
    final state = await _readStateSnapshot();
    final phaseState = _map(_map(state?['phases'])?[phase]);
    if (state?['runId'] != runId ||
        phaseState == null ||
        phaseState['messageId'] != messageId ||
        phaseState['attachmentId'] != attachmentId) {
      throw StateError('iOS group-media phase state is absent');
    }
    final current = await loadCurrentAttachment(attachmentId);
    if (current != null &&
        (current.id != attachmentId || current.messageId != messageId)) {
      throw StateError('iOS group-media durable row tuple changed');
    }
    return <String, Object?>{
      'barrier': phaseState['barrier'],
      'barrierProcessId': phaseState['barrierProcessId'],
      'recoveryProcessId': phaseState['recoveryProcessId'],
      'durableStatus': current?.downloadStatus ?? 'absent',
      'downloadAttempts': phaseState['attempts'],
      'resumeAfterDrainAttempts': phaseState['resumeAfterDrainAttempts'],
      'uiEffectMarker': phaseState['uiEffectMarker'],
    };
  }

  Future<Map<String, Object?>?> _readStateSnapshot() async {
    if (!await _stateFile.exists()) return null;
    final decoded = _validateState(jsonDecode(await _stateFile.readAsString()));
    _onStateSnapshotRead?.call(_currentBarrier(decoded));
    return decoded;
  }

  Map<String, Object?>? _readStateSnapshotSync() {
    if (!_stateFile.existsSync()) return null;
    return _validateState(jsonDecode(_stateFile.readAsStringSync()));
  }

  Map<String, Object?> _validateState(Object? value) {
    final state = _map(value);
    if (state == null ||
        state['schema'] != groupMediaIosBackgroundE2EStateSchema ||
        state['runId'] is! String ||
        _map(state['phases']) == null) {
      throw StateError('iOS group-media state is corrupt');
    }
    return state;
  }

  Future<T?> _mutateStateIfPresent<T>(
    FutureOr<_GroupMediaIosStateUpdate<T>> Function(Map<String, Object?> state)
    mutation,
  ) => _stateMutations.run(() async {
    final current = await _readStateSnapshot();
    if (current == null) return null;
    final next = _copyState(current);
    final update = await mutation(next);
    if (update.shouldPersist) await _publishState(next);
    return update.value;
  });

  Future<void> _publishState(Map<String, Object?> state) async {
    await _writeStateSnapshot(state);
    _state = _copyState(state);
    uiProofLabels.value = _labelsForState(state, currentProcessId);
  }

  Future<void> _writeStateSnapshot(Map<String, Object?> state) async {
    await _stateFile.parent.create(recursive: true);
    final sequence = ++_writeSequence;
    final temporary = File(
      '${_stateFile.path}.pending-$currentProcessId-$sequence',
    );
    try {
      await temporary.writeAsString('${jsonEncode(state)}\n', flush: true);
      await _beforeAtomicStateReplace?.call(_currentBarrier(state));
      // iOS is POSIX: rename replaces the old file atomically. Deleting the
      // live state first would create a force-termination data-loss window.
      await temporary.rename(_stateFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void _requireEnabled() {
    if (!enabled) throw StateError('iOS group-media E2E controller disabled');
  }
}

final class _GroupMediaIosStateUpdate<T> {
  const _GroupMediaIosStateUpdate.changed(this.value) : shouldPersist = true;

  const _GroupMediaIosStateUpdate.unchanged(this.value) : shouldPersist = false;

  final T value;
  final bool shouldPersist;
}

/// One-process serialization whose tail is never poisoned by a failed write.
final class _GroupMediaIosMutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

Map<String, Object?> _copyState(Map<String, Object?> source) =>
    source.map<String, Object?>(
      (key, value) => MapEntry<String, Object?>(key, _copyStateValue(value)),
    );

Object? _copyStateValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => map.map<String, Object?>(
    (key, item) =>
        MapEntry<String, Object?>(key.toString(), _copyStateValue(item)),
  ),
  List<Object?> list => list.map<Object?>(_copyStateValue).toList(),
  _ => value,
};

String? _currentBarrier(Map<String, Object?> state) {
  final phases = _map(state['phases']);
  for (final phase in const <String>['b', 'a']) {
    final barrier = _map(phases?[phase])?['barrier'];
    if (barrier is String) return barrier;
  }
  return null;
}

List<String> _labelsForState(
  Map<String, Object?>? state,
  int currentProcessId,
) {
  final phases = _map(state?['phases']);
  if (phases == null) return const <String>[];
  final labels = <String>[];
  for (final phase in const <String>['a', 'b']) {
    final phaseState = _map(phases[phase]);
    final effect = phaseState?['uiEffectMarker'];
    final readiness = phaseState?['readinessMarker'];
    final observationAccepted =
        phaseState?['observationAccepted'] == true &&
        phaseState?['observationProcessId'] == currentProcessId;
    if (effect is String) {
      labels.add(effect);
    } else if (readiness is String && observationAccepted) {
      labels.add(readiness);
    }
  }
  return List<String>.unmodifiable(labels);
}

Future<Map<String, Object?>> runGroupMediaIosBackgroundE2EAction({
  required Map<String, dynamic> config,
  required GroupMediaIosBackgroundE2EController controller,
  required GroupMediaIosLoadAttachment loadAttachment,
  required GroupMediaIosIdentityExport exportIdentity,
  required GroupMediaIosAddContact addContact,
  required GroupMediaIosSetupSender setupSender,
  required GroupMediaIosAcceptReceiver acceptReceiver,
  required GroupMediaIosSendFixture sendFixture,
  required GroupMediaIosDatabaseProbe probeDatabase,
  required GroupMediaIosDrainInbox drainGroupInbox,
  required GroupMediaIosRetryDownloads retryDownloads,
  required GroupMediaIosReserveReceiveCriticalTask reserveReceiveCriticalTask,
  GroupMediaIosReceiverObservationAccepted? onReceiverObservationAccepted,
  GroupMediaIosReceiverObservationComplete? onReceiverObservationComplete,
  String installedProfileId = const String.fromEnvironment(
    'SIMS_BUILD_PROFILE_ID',
  ),
}) async {
  final request = GroupMediaIosBackgroundE2ERequest.fromConfig(config);
  if (!const <String>{
    groupMediaIosBackgroundBuildProfile,
    groupMediaIosAndroidSenderBuildProfile,
  }.contains(installedProfileId)) {
    throw StateError('iOS group-media fixture profile rejected');
  }
  final expectedRole = installedProfileId == groupMediaIosBackgroundBuildProfile
      ? 'receiver'
      : 'sender';
  if (request.role != expectedRole) {
    throw StateError('iOS group-media fixture role/profile mismatch');
  }
  final base = <String, Object?>{
    'schema': groupMediaIosBackgroundE2EResultSchema,
    'scenario': groupMediaIosBackgroundScenario,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'status': 'complete',
    'success': true,
    'processId': pid,
  };

  switch (request.phase) {
    case groupMediaIosIdentityPhase:
      return <String, Object?>{...base, ...await exportIdentity()};
    case groupMediaIosAddContactPhase:
      final qr = request.peerQrPayload;
      if (qr == null) throw const FormatException('peer QR is absent');
      await addContact(qr, request.peerMlKemPublicKey);
      return <String, Object?>{...base, 'contactAdded': true};
    case groupMediaIosSenderSetupPhase:
      final receiverAccount = request.receiverAccountPeerId;
      final receiverTransport = request.receiverTransportPeerId;
      final groupName = request.marker;
      if (request.role != 'sender' ||
          receiverAccount == null ||
          receiverTransport == null ||
          groupName == null) {
        throw const FormatException('sender setup tuple rejected');
      }
      return <String, Object?>{
        ...base,
        ...await setupSender(receiverAccount, receiverTransport, groupName),
      };
    case groupMediaIosReceiverArmPhase:
      final mediaPhase = request.mediaPhase;
      final groupId = request.groupId;
      final messageId = request.messageId;
      final attachmentId = request.attachmentId;
      if (request.role != 'receiver' ||
          mediaPhase == null ||
          groupId == null ||
          messageId == null ||
          attachmentId == null) {
        throw const FormatException('receiver arm tuple rejected');
      }
      final accepted = await acceptReceiver(groupId);
      if (accepted == null) throw StateError('group invite was not accepted');
      await controller.arm(
        runId: request.runId,
        phase: mediaPhase,
        groupId: groupId,
        messageId: messageId,
        attachmentId: attachmentId,
        readinessMarker: request.marker ?? '',
      );
      return <String, Object?>{...base, ...accepted, 'armed': true};
    case groupMediaIosSenderSendPhase:
      final mediaPhase = request.mediaPhase;
      final groupId = request.groupId;
      final messageId = request.messageId;
      final attachmentId = request.attachmentId;
      final marker = request.marker;
      final receiverAccount = request.receiverAccountPeerId;
      final receiverTransport = request.receiverTransportPeerId;
      if (request.role != 'sender' ||
          mediaPhase == null ||
          groupId == null ||
          messageId == null ||
          attachmentId == null ||
          marker == null ||
          receiverAccount == null ||
          receiverTransport == null) {
        throw const FormatException('sender fixture tuple rejected');
      }
      return <String, Object?>{
        ...base,
        ...await sendFixture(
          mediaPhase,
          groupId,
          messageId,
          attachmentId,
          marker,
          receiverAccount,
          receiverTransport,
        ),
      };
    case groupMediaIosReceiverObservePhase:
      final mediaPhase = request.mediaPhase;
      final messageId = request.messageId;
      final attachmentId = request.attachmentId;
      if (request.role != 'receiver' ||
          mediaPhase == null ||
          messageId == null ||
          attachmentId == null ||
          onReceiverObservationAccepted == null ||
          onReceiverObservationComplete == null) {
        throw const FormatException('receiver observation tuple rejected');
      }
      final releaseReceiveCriticalTask = await reserveReceiveCriticalTask();
      try {
        final observation = await _waitForGroupMediaIosObservation(
          controller: controller,
          runId: request.runId,
          phase: mediaPhase,
          messageId: messageId,
          attachmentId: attachmentId,
          loadCurrentAttachment: loadAttachment,
          expectedStatus: mediaPhase == 'a' ? 'done' : 'downloading',
          expectedBarrier: mediaPhase == 'a'
              ? 'background_receive_started'
              : 'durable_post_claim_pre_commit',
          onFirstDurableObservation: () async {
            await onReceiverObservationAccepted();
            await controller.markObservationReady(
              runId: request.runId,
              phase: mediaPhase,
              messageId: messageId,
              attachmentId: attachmentId,
            );
          },
        );
        final database = await probeDatabase(
          mediaPhase,
          messageId,
          attachmentId,
        );
        if (mediaPhase == 'a') {
          final marker = request.marker;
          if (marker == null) {
            throw const FormatException('receiver UI effect marker is absent');
          }
          await controller.publishDurableUiEffect(
            runId: request.runId,
            phase: mediaPhase,
            marker: marker,
            loadCurrentAttachment: loadAttachment,
          );
        }
        final result = <String, Object?>{
          ...base,
          ...observation,
          'uiEffectPublished': mediaPhase == 'a',
          'database': database,
        };
        await onReceiverObservationComplete(result);
        return result;
      } finally {
        await releaseReceiveCriticalTask();
      }
    case groupMediaIosReceiverRecoverPhase:
      final messageId = request.messageId;
      final attachmentId = request.attachmentId;
      if (request.role != 'receiver' ||
          request.mediaPhase != 'b' ||
          messageId == null ||
          attachmentId == null) {
        throw const FormatException('receiver recovery tuple rejected');
      }
      await drainGroupInbox();
      final released = await controller.releaseRecoveryAfterInboxDrain(
        runId: request.runId,
        loadCurrentAttachment: loadAttachment,
      );
      final firstWork = await retryDownloads();
      final secondWork = await retryDownloads();
      final observation = await _waitForGroupMediaIosObservation(
        controller: controller,
        runId: request.runId,
        phase: 'b',
        messageId: messageId,
        attachmentId: attachmentId,
        loadCurrentAttachment: loadAttachment,
        expectedStatus: 'done',
        expectedBarrier: 'durable_post_claim_pre_commit',
      );
      final database = await probeDatabase('b', messageId, attachmentId);
      final marker = request.marker;
      if (marker == null) {
        throw const FormatException('recovery UI effect marker is absent');
      }
      await controller.publishDurableUiEffect(
        runId: request.runId,
        phase: 'b',
        marker: marker,
        loadCurrentAttachment: loadAttachment,
      );
      return <String, Object?>{
        ...base,
        ...released,
        ...observation,
        'firstDownloadWork': firstWork,
        'secondDownloadWork': secondWork,
        'uiEffectPublished': true,
        'database': database,
      };
  }
  throw StateError('unreachable iOS group-media action');
}

/// Exact release-mode exceptions for signed physical-iOS E2E profiles.
/// Arbitrary release builds remain ineligible even if a caller accidentally
/// sets `E2E_TEST_MODE`. Plan 397's setup profile owns only the temporary
/// identity/config file channel; it does not become a disposable P269 build.
bool allowsGroupMediaIosIntroFileChannel({
  required bool isDebugMode,
  required bool e2eTestMode,
  required String installedProfileId,
}) =>
    e2eTestMode &&
    (isDebugMode ||
        installedProfileId == groupMediaIosBackgroundBuildProfile ||
        installedProfileId == groupReactionNotificationIosSetupBuildProfile);

Future<Map<String, Object?>> _waitForGroupMediaIosObservation({
  required GroupMediaIosBackgroundE2EController controller,
  required String runId,
  required String phase,
  required String messageId,
  required String attachmentId,
  required GroupMediaIosLoadAttachment loadCurrentAttachment,
  required String expectedStatus,
  required String expectedBarrier,
  GroupMediaIosReceiverObservationAccepted? onFirstDurableObservation,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  var durableObservationAccepted = false;
  while (DateTime.now().isBefore(deadline)) {
    Map<String, Object?>? observation;
    try {
      observation = await controller.observe(
        runId: runId,
        phase: phase,
        messageId: messageId,
        attachmentId: attachmentId,
        loadCurrentAttachment: loadCurrentAttachment,
      );
    } on Object catch (error) {
      lastError = error;
    }
    if (observation != null) {
      if (!durableObservationAccepted) {
        await onFirstDurableObservation?.call();
        durableObservationAccepted = true;
      }
      if (observation['durableStatus'] == expectedStatus &&
          observation['barrier'] == expectedBarrier) {
        return observation;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'iOS group-media $phase did not reach $expectedStatus '
    '(${lastError?.runtimeType ?? 'no observation'}).',
    timeout,
  );
}

Map<String, Object?> groupMediaIosBackgroundE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  final request = GroupMediaIosBackgroundE2ERequest.fromConfig(config);
  return <String, Object?>{
    'schema': groupMediaIosBackgroundE2EResultSchema,
    'scenario': groupMediaIosBackgroundScenario,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'status': 'failed',
    'success': false,
    'processId': pid,
    'errorType': error.runtimeType.toString(),
  };
}

Map<String, Object?> groupMediaIosBackgroundE2EAcceptedReceipt({
  required Map<String, dynamic> config,
  int? currentProcessId,
}) {
  final request = GroupMediaIosBackgroundE2ERequest.fromConfig(config);
  final processId = currentProcessId ?? pid;
  if (request.phase != groupMediaIosReceiverObservePhase ||
      request.role != 'receiver' ||
      request.mediaPhase == null ||
      request.messageId == null ||
      request.attachmentId == null ||
      processId <= 0) {
    throw const FormatException(
      'iOS group-media foreground observation acceptance rejected',
    );
  }
  return <String, Object?>{
    'schema': groupMediaIosBackgroundE2EResultSchema,
    'scenario': groupMediaIosBackgroundScenario,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'status': 'accepted',
    'success': false,
    'processId': processId,
    'foregroundArmComplete': true,
  };
}

final RegExp _safeToken = RegExp(r'^[A-Za-z0-9._:-]{1,180}$');

String _token(Object? value, {required int maxLength}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !_safeToken.hasMatch(value)) {
    throw const FormatException('iOS group-media token rejected');
  }
  return value;
}

String? _optionalToken(Object? value, {required int maxLength}) {
  if (value == null || value == '') return null;
  return _token(value, maxLength: maxLength);
}

String? _optionalText(Object? value, {required int maxLength}) {
  if (value == null || value == '') return null;
  if (value is! String ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'))) {
    throw const FormatException('iOS group-media protected text rejected');
  }
  return value;
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}
