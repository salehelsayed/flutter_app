import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/app/bootstrap/android_production_audio_call_e2e_observer.dart';
import 'package:flutter_app/core/debug/android_production_audio_call_e2e.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'observer is read-only profile-bound privacy-safe and nonce-bound',
    () async {
      expect(
        AndroidProductionAudioCallE2EObserver.tryCreate(
          enabled: false,
          isAndroid: true,
          installedProfileId: androidProductionAudioCallE2EBuildProfile,
        ),
        isNull,
      );
      expect(
        AndroidProductionAudioCallE2EObserver.tryCreate(
          enabled: true,
          isAndroid: true,
          installedProfileId: 'android.e2e.unrelated',
        ),
        isNull,
      );
      expect(
        AndroidProductionAudioCallE2EObserver.tryCreate(
          enabled: true,
          isAndroid: false,
          installedProfileId: androidProductionAudioCallE2EBuildProfile,
        ),
        isNull,
      );

      final sessionChanges = StreamController<CallSessionSnapshot>.broadcast(
        sync: true,
      );
      final foregroundChanges =
          StreamController<ForegroundCallProjection?>.broadcast(sync: true);
      addTearDown(sessionChanges.close);
      addTearDown(foregroundChanges.close);
      CallSessionSnapshot? currentSession;
      ForegroundCallProjection? currentForeground;
      var mediaReads = 0;
      var currentRtpObserved = true;
      final observer = AndroidProductionAudioCallE2EObserver.tryCreate(
        enabled: true,
        isAndroid: true,
        installedProfileId: androidProductionAudioCallE2EBuildProfile,
      )!;
      addTearDown(observer.dispose);
      final source = AndroidProductionAudioCallObservationSource(
        readCurrentSession: () => currentSession,
        sessionChanges: sessionChanges.stream,
        readCurrentForeground: () => currentForeground,
        foregroundChanges: foregroundChanges.stream,
        readActiveConnectionSnapshot: () async {
          mediaReads++;
          return CallConnectionSnapshot(
            state: CallConnectionState.connected,
            transportPolicy: CallTransportPolicy.relayOnly,
            transport: CallTransportClass.turnUdp,
            quality: CallQualityBand.good,
            localAudioCaptureTrackCount: 1,
            localVideoCaptureTrackCount: 0,
            audioReceiveTransceiverCount: 1,
            videoTransceiverCount: 0,
            selectedPairSucceeded: true,
            selectedPairNominated: true,
            selectedRelayProtocol: CallRelayProtocol.udp,
            dtlsReady: true,
            audioSessionActive: true,
            localAudioSenderAttached: true,
            localAudioTrackLive: true,
            remoteAudioReceiverAttached: true,
            remoteAudioTrackLive: true,
            localAudioEnabled: true,
            inboundAudioRtpObserved: currentRtpObserved,
            outboundAudioRtpObserved: currentRtpObserved,
          );
        },
        readOutgoingCallWakeAuthorityReady: (_) async => false,
      );
      observer.bind(source);
      expect(
        () => observer.bind(source),
        returnsNormally,
        reason: 'a rebuilt production graph may replace the read-only source',
      );

      final arm = _request(operation: androidProductionAudioCallArmOperation);
      final armed = await observer.run(arm);
      expect(armed['status'], 'armed');
      expect(armed['stateSequence'], isEmpty);

      final callId = CallId.parse('123e4567-e89b-42d3-a456-426614174000');
      void publish(CallState state, {CallEndReason? endReason}) {
        final now = DateTime.utc(2026, 9, 2, 12, 0);
        final session = CallSessionSnapshot.active(
          callId: callId,
          contactPeerId: 'raw-contact-peer-must-not-escape',
          direction: CallDirection.outgoing,
          state: state,
          callerAccountPeerId: 'raw-account-peer-must-not-escape',
          callerDeviceId: 'raw-device-peer-must-not-escape',
          startedAt: now,
          ringingAt: state.index >= CallState.ringing.index ? now : null,
          acceptedAt: state.index >= CallState.accepted.index ? now : null,
          connectedAt: state.index >= CallState.connected.index ? now : null,
          endedAt: state == CallState.ended ? now : null,
          endReason: endReason,
        );
        currentSession = session;
        sessionChanges.add(session);
        currentForeground = state == CallState.ended
            ? null
            : ForegroundCallProjection(
                session: session,
                audio: CallAudioControlState(
                  muted: false,
                  selectedRoute: CallAudioOutputRoute.earpiece,
                  supportedRoutes: const <CallAudioOutputRoute>[
                    CallAudioOutputRoute.earpiece,
                    CallAudioOutputRoute.speaker,
                  ],
                  active: state.index >= CallState.accepted.index,
                  failure: CallAudioFailure.none,
                ),
              );
        foregroundChanges.add(currentForeground);
      }

      publish(CallState.inviting);
      publish(CallState.ringing);
      publish(CallState.accepted);
      publish(CallState.connected);
      await Future<void>.delayed(Duration.zero);

      final sample = await observer.run(
        _request(operation: androidProductionAudioCallSampleOperation),
      );
      expect(sample['status'], 'observing');
      expect(sample['stateSequence'], <String>[
        'outgoing',
        'ringing',
        'accepted',
        'connected',
      ]);
      expect(sample['activeCallSurfaceObserved'], isTrue);
      expect(sample['structuralMediaReadyObserved'], isTrue);
      expect(sample['relayOnlyObserved'], isTrue);
      expect(sample['selectedRelayTransport'], 'turn_udp');
      expect(sample['localAudioEnabledObserved'], isTrue);
      expect(sample['inboundAudioRtpObserved'], isTrue);
      expect(sample['outboundAudioRtpObserved'], isTrue);
      expect(mediaReads, greaterThan(0));

      currentRtpObserved = false;
      final stickySample = await observer.run(
        _request(operation: androidProductionAudioCallSampleOperation),
      );
      expect(stickySample['inboundAudioRtpObserved'], isTrue);
      expect(stickySample['outboundAudioRtpObserved'], isTrue);

      publish(CallState.ended, endReason: CallEndReason.localHangup);
      await Future<void>.delayed(Duration.zero);
      final completed = await observer.run(
        _request(operation: androidProductionAudioCallStopOperation),
      );
      expect(completed['status'], 'complete');
      expect(completed['terminalObserved'], isTrue);
      expect(completed['stateSequence'], <String>[
        'outgoing',
        'ringing',
        'accepted',
        'connected',
        'terminal',
      ]);
      expect(
        completed['callBindingSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(completed['containsPrivateMaterial'], isFalse);

      expect(completed.keys.toSet(), <String>{
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
      });
      final encoded = jsonEncode(completed);
      for (final privateValue in const <String>[
        '123e4567-e89b-42d3-a456-426614174000',
        'raw-contact-peer-must-not-escape',
        'raw-account-peer-must-not-escape',
        'raw-device-peer-must-not-escape',
        'candidate:',
        'turn:',
        '192.168.',
      ]) {
        expect(encoded, isNot(contains(privateValue)));
      }

      final requestWithControlAuthority = <String, dynamic>{
        ..._request(operation: androidProductionAudioCallArmOperation),
        'answer': true,
      };
      expect(
        () => AndroidProductionAudioCallE2ERequest.fromConfig(
          requestWithControlAuthority,
        ),
        throwsFormatException,
      );
      expect(
        () => observer.run(
          _request(
            operation: androidProductionAudioCallSampleOperation,
            nonce: 'different-nonce',
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'armed observer rebinds to a rebuilt graph without control impact',
    () async {
      final sessionsA = StreamController<CallSessionSnapshot>.broadcast(
        sync: true,
      );
      final foregroundA = StreamController<ForegroundCallProjection?>.broadcast(
        sync: true,
      );
      final sessionsB = StreamController<CallSessionSnapshot>.broadcast(
        sync: true,
      );
      final foregroundB = StreamController<ForegroundCallProjection?>.broadcast(
        sync: true,
      );
      addTearDown(sessionsA.close);
      addTearDown(foregroundA.close);
      addTearDown(sessionsB.close);
      addTearDown(foregroundB.close);

      CallSessionSnapshot? currentA;
      CallSessionSnapshot? currentB;
      final observer = AndroidProductionAudioCallE2EObserver.tryCreate(
        enabled: true,
        isAndroid: true,
        installedProfileId: androidProductionAudioCallE2EBuildProfile,
      )!;
      addTearDown(observer.dispose);
      final sourceA = AndroidProductionAudioCallObservationSource(
        readCurrentSession: () => currentA,
        sessionChanges: sessionsA.stream,
        readCurrentForeground: () => null,
        foregroundChanges: foregroundA.stream,
        readActiveConnectionSnapshot: () async => null,
        readOutgoingCallWakeAuthorityReady: (_) async => false,
      );
      final sourceB = AndroidProductionAudioCallObservationSource(
        readCurrentSession: () => currentB,
        sessionChanges: sessionsB.stream,
        readCurrentForeground: () => null,
        foregroundChanges: foregroundB.stream,
        readActiveConnectionSnapshot: () async => null,
        readOutgoingCallWakeAuthorityReady: (_) async => false,
      );

      observer.bind(sourceA);
      await observer.run(
        _request(operation: androidProductionAudioCallArmOperation),
      );
      currentA = _session(CallState.inviting);
      sessionsA.add(currentA);

      expect(() => observer.bind(sourceB), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      expect(sessionsA.hasListener, isFalse);
      expect(foregroundA.hasListener, isFalse);
      expect(sessionsB.hasListener, isTrue);
      expect(foregroundB.hasListener, isTrue);

      currentA = _session(CallState.ringing);
      sessionsA.add(currentA);
      currentB = _session(CallState.accepted);
      sessionsB.add(currentB);
      final result = await observer.run(
        _request(operation: androidProductionAudioCallSampleOperation),
      );

      expect(result['stateSequence'], <String>['outgoing', 'accepted']);
      expect(result['ringingObserved'], isFalse);
      expect(result['acceptedObserved'], isTrue);

      final firstDispose = observer.dispose();
      final secondDispose = observer.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);
      await firstDispose;
      expect(sessionsB.hasListener, isFalse);
      expect(foregroundB.hasListener, isFalse);
      expect(() => observer.bind(sourceA), returnsNormally);
    },
  );

  test(
    'readiness is one-shot exact read-only and never reflects peer material',
    () async {
      final sessions = StreamController<CallSessionSnapshot>.broadcast();
      final foreground =
          StreamController<ForegroundCallProjection?>.broadcast();
      addTearDown(sessions.close);
      addTearDown(foreground.close);
      const peerId = '12D3KooWprivate-contact-account-peer';
      var sessionReads = 0;
      var foregroundReads = 0;
      var connectionReads = 0;
      final readinessReads = <String>[];
      var ready = true;
      final observer = AndroidProductionAudioCallE2EObserver.tryCreate(
        enabled: true,
        isAndroid: true,
        installedProfileId: androidProductionAudioCallE2EBuildProfile,
      )!;
      addTearDown(observer.dispose);
      observer.bind(
        AndroidProductionAudioCallObservationSource(
          readCurrentSession: () {
            sessionReads++;
            return null;
          },
          sessionChanges: sessions.stream,
          readCurrentForeground: () {
            foregroundReads++;
            return null;
          },
          foregroundChanges: foreground.stream,
          readActiveConnectionSnapshot: () async {
            connectionReads++;
            return null;
          },
          readOutgoingCallWakeAuthorityReady: (contactAccountPeerId) async {
            readinessReads.add(contactAccountPeerId);
            return ready;
          },
        ),
      );

      final readyReceipt = await observer.run(
        _request(
          operation: androidProductionAudioCallReadinessOperation,
          contactAccountPeerId: peerId,
        ),
      );
      expect(readyReceipt['status'], 'ready');
      expect(readyReceipt['success'], isTrue);
      expect(readyReceipt['wakeAuthorityReady'], isTrue);
      expect(readyReceipt['callBindingSha256'], isNull);
      expect(readinessReads, <String>[peerId]);
      expect(sessionReads, 0);
      expect(foregroundReads, 0);
      expect(connectionReads, 0);
      expect(sessions.hasListener, isFalse);
      expect(foreground.hasListener, isFalse);
      expect(jsonEncode(readyReceipt), isNot(contains(peerId)));
      final failureReceipt = androidProductionAudioCallE2EFailureReceipt(
        config: _request(
          operation: androidProductionAudioCallReadinessOperation,
          contactAccountPeerId: peerId,
        ),
      );
      expect(failureReceipt['wakeAuthorityReady'], isFalse);
      expect(jsonEncode(failureReceipt), isNot(contains(peerId)));

      ready = false;
      final notReadyReceipt = await observer.run(
        _request(
          operation: androidProductionAudioCallReadinessOperation,
          contactAccountPeerId: peerId,
        ),
      );
      expect(notReadyReceipt['status'], 'not_ready');
      expect(notReadyReceipt['success'], isTrue);
      expect(notReadyReceipt['wakeAuthorityReady'], isFalse);
      expect(readinessReads, <String>[peerId, peerId]);

      expect(
        () => AndroidProductionAudioCallE2ERequest.fromConfig(
          _request(operation: androidProductionAudioCallReadinessOperation),
        ),
        throwsFormatException,
      );
      expect(
        () => AndroidProductionAudioCallE2ERequest.fromConfig(
          _request(
            operation: androidProductionAudioCallReadinessOperation,
            contactAccountPeerId: '../private peer',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => AndroidProductionAudioCallE2ERequest.fromConfig(
          _request(
            operation: androidProductionAudioCallArmOperation,
            contactAccountPeerId: peerId,
          ),
        ),
        throwsFormatException,
        reason: 'peer identity is accepted only by the readiness operation',
      );
    },
  );

  test('exact current issued wake authority predicate fails closed', () {
    const peerId = '12D3KooWcontact-account';
    const expectedRecipientDevicePeerId = '12D3KooWrecipient-device';
    const expectedDeviceKeyEpoch = 1;
    const nowMs = 2000000;
    CallIssuedWakeHandleRecord record({
      bool distributionPending = false,
      bool revokePending = false,
      int? distributionReceiptVersion =
          CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      int issuedAtMs = 1000000,
      int expiresAtMs = 3000000,
      String contactAccountPeerId = peerId,
      String recipientDevicePeerId = expectedRecipientDevicePeerId,
      int deviceKeyEpoch = expectedDeviceKeyEpoch,
    }) => CallIssuedWakeHandleRecord(
      contactAccountPeerId: contactAccountPeerId,
      grant: CallWakeHandleGrant(
        handle: '0123456789abcdef0123456789abcdef',
        recipientDevicePeerId: recipientDevicePeerId,
        deviceKeyEpoch: deviceKeyEpoch,
        generation: 1,
        issuedAtMs: issuedAtMs,
        expiresAtMs: expiresAtMs,
      ),
      authorizedSenderDevicePeerIds: const <String>{'12D3KooWsender-device'},
      distributionPending: distributionPending,
      revokePending: revokePending,
      distributionReceiptVersion: distributionReceiptVersion,
    );

    bool isReady(CallIssuedWakeHandleRecord? candidate) =>
        hasExactCurrentProductionCallWakeAuthority(
          record: candidate,
          contactAccountPeerId: peerId,
          expectedRecipientDevicePeerId: expectedRecipientDevicePeerId,
          expectedDeviceKeyEpoch: expectedDeviceKeyEpoch,
          nowMs: nowMs,
        );

    expect(isReady(record()), isTrue);
    expect(isReady(null), isFalse);
    expect(
      isReady(
        record(distributionPending: true, distributionReceiptVersion: null),
      ),
      isFalse,
    );
    expect(isReady(record(distributionReceiptVersion: null)), isFalse);
    expect(isReady(record(distributionReceiptVersion: 2)), isFalse);
    expect(
      isReady(record(revokePending: true, distributionReceiptVersion: null)),
      isFalse,
    );
    expect(isReady(record(expiresAtMs: nowMs)), isFalse);
    expect(isReady(record(issuedAtMs: nowMs + 1)), isFalse);
    expect(
      isReady(record(contactAccountPeerId: '12D3KooWother-contact')),
      isFalse,
    );
    expect(
      isReady(record(recipientDevicePeerId: '12D3KooWother-device')),
      isFalse,
    );
    expect(
      isReady(record(deviceKeyEpoch: expectedDeviceKeyEpoch + 1)),
      isFalse,
    );
  });
}

CallSessionSnapshot _session(CallState state) {
  final now = DateTime.utc(2026, 9, 2, 12);
  return CallSessionSnapshot.active(
    callId: CallId.parse('123e4567-e89b-42d3-a456-426614174000'),
    contactPeerId: 'private-contact',
    direction: CallDirection.outgoing,
    state: state,
    callerAccountPeerId: 'private-account',
    callerDeviceId: 'private-device',
    startedAt: now,
    ringingAt: state == CallState.ringing ? now : null,
    acceptedAt: state == CallState.accepted ? now : null,
  );
}

Map<String, dynamic> _request({
  required String operation,
  String nonce = 'run-nonce-399',
  String? contactAccountPeerId,
}) {
  const role = androidProductionAudioCallCallerRole;
  const runId = 'run-399-observer';
  return <String, dynamic>{
    'schema': androidProductionAudioCallE2ERequestSchema,
    'transport_action': androidProductionAudioCallE2EAction,
    'scenario': androidProductionAudioCallE2EScenario,
    'buildProfile': androidProductionAudioCallE2EBuildProfile,
    'role': role,
    'operation': operation,
    'stepId': androidProductionAudioCallStepId(
      role: role,
      operation: operation,
      runId: runId,
    ),
    'runId': runId,
    'nonce': nonce,
    'profileSha256': 'a' * 64,
    'apkSha256': 'b' * 64,
    'contactAccountPeerId': ?contactAccountPeerId,
  };
}
