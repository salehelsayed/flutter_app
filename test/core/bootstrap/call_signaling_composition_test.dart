import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_network_gate.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/call_wake_authorization_coordinator.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_token_coordinator.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/ios_voip_token_coordinator.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../secure_storage/fake_secure_key_store.dart';

final class _Graph
    implements
        CallSignalingGraphLifecycle,
        ForegroundCallCapability,
        ForegroundCallBackgroundLifecycle,
        CallSignalingCallabilityInvalidations,
        CallSignalingWakeDrain,
        CallWakeHandleDistributionLifecycle {
  _Graph(
    this.events, {
    this.startResult = true,
    List<bool> advertisementResults = const <bool>[true],
    this.outgoingResult = OutgoingCallStartResult.started,
    this.contactOutgoingAvailable = true,
    this.recordRearmEvent = false,
    List<bool> rearmResults = const <bool>[true],
    this.rearmCompleter,
    this.onShutdown,
    this.throwOnForegroundChanges = false,
    this.throwOnStart = false,
    this.throwOnAdvertise = false,
  }) : _advertisementResults = <bool>[...advertisementResults],
       _rearmResults = <bool>[...rearmResults];

  final List<String> events;
  final bool startResult;
  final List<bool> _advertisementResults;
  final OutgoingCallStartResult outgoingResult;
  final bool contactOutgoingAvailable;
  final bool recordRearmEvent;
  final List<bool> _rearmResults;
  final Completer<bool>? rearmCompleter;
  final void Function(_Graph graph)? onShutdown;
  final bool throwOnForegroundChanges;
  final bool throwOnStart;
  final bool throwOnAdvertise;
  Future<bool> Function()? onAdvertise;
  final StreamController<void> callabilityInvalidationsController =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get callabilityInvalidations =>
      callabilityInvalidationsController.stream;

  final List<String> outgoingPeerIds = <String>[];
  final List<String> availabilityPeerIds = <String>[];
  final List<String> wakeGrantPeerIds = <String>[];
  final List<(String, CallWakeHandleGrant)> distributedWakeGrants =
      <(String, CallWakeHandleGrant)>[];
  int backgroundCalls = 0;
  int rearmCalls = 0;
  final List<(String, CallId, bool?)> foregroundActions =
      <(String, CallId, bool?)>[];
  final StreamController<ForegroundCallProjection?> _foregroundChanges =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  ForegroundCallProjection? foregroundCurrent;

  @override
  ForegroundCallProjection? get current => foregroundCurrent;

  @override
  Stream<ForegroundCallProjection?> get changes {
    if (throwOnForegroundChanges) {
      throw StateError('private foreground binding detail');
    }
    return _foregroundChanges.stream;
  }

  void emitForeground(ForegroundCallProjection? projection) {
    foregroundCurrent = projection;
    _foregroundChanges.add(projection);
  }

  Future<ForegroundCallActionResult> _action(
    String action,
    CallId callId, [
    bool? value,
  ]) async {
    foregroundActions.add((action, callId, value));
    return ForegroundCallActionResult.applied;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) =>
      _action('answer', callId);

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) =>
      _action('decline', callId);

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) =>
      _action('cancel', callId);

  @override
  Future<ForegroundCallActionResult> end(CallId callId) =>
      _action('end', callId);

  @override
  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted) =>
      _action('muted', callId, muted);

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) => _action('speaker', callId, enabled);

  @override
  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId) async {
    availabilityPeerIds.add(contactAccountPeerId);
    return contactOutgoingAvailable;
  }

  @override
  Future<bool> advertiseCapability() async {
    events.add('advertise');
    if (throwOnAdvertise) {
      throw StateError('private capability detail');
    }
    final override = onAdvertise;
    if (override != null) return override();
    return _advertisementResults.length > 1
        ? _advertisementResults.removeAt(0)
        : _advertisementResults.single;
  }

  @override
  Future<CallWakeHandleGrant?> resolveCallWakeHandle(
    String contactAccountPeerId,
  ) async {
    wakeGrantPeerIds.add(contactAccountPeerId);
    return CallWakeHandleGrant(
      handle: '0123456789abcdef0123456789abcdef',
      recipientDevicePeerId: 'localdevice',
      deviceKeyEpoch: 7,
      generation: 1,
      issuedAtMs: 1,
      expiresAtMs: 10,
    );
  }

  @override
  Future<bool> markCallWakeHandleDistributed(
    String contactAccountPeerId,
    CallWakeHandleGrant grant,
  ) async {
    distributedWakeGrants.add((contactAccountPeerId, grant));
    return true;
  }

  @override
  Future<bool> rearmCallWakeHandleDistribution() async {
    rearmCalls++;
    if (recordRearmEvent) events.add('wake_rearm');
    final completer = rearmCompleter;
    if (completer != null) return completer.future;
    return _rearmResults.length > 1
        ? _rearmResults.removeAt(0)
        : _rearmResults.single;
  }

  @override
  Future<void> onResume() async {
    events.add('mailbox_resume');
  }

  @override
  Future<void> drainCallMailbox() async {
    events.add('call_mailbox_drain');
  }

  @override
  Future<void> onBackgrounded() async {
    backgroundCalls++;
    events.add('call_backgrounded');
  }

  @override
  Future<void> shutdown() async {
    events.add('call_shutdown');
    onShutdown?.call(this);
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId,
  ) async {
    outgoingPeerIds.add(contactAccountPeerId);
    return outgoingResult;
  }

  @override
  Future<bool> start() async {
    events.add('call_subscription');
    if (throwOnStart) {
      throw StateError('private listener detail');
    }
    return startResult;
  }
}

final class _Bridge implements Bridge {
  final List<String> commands = <String>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<String, Map<String, Object?>> responses =
      <String, Map<String, Object?>>{};
  final Map<String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>
  responseHandlers =
      <String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>{};

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final command = request['cmd']! as String;
    commands.add(command);
    final handler = responseHandlers[command];
    if (handler != null) return jsonEncode(await handler(request));
    final overridden = responses[command];
    if (overridden != null) return jsonEncode(overridden);
    return jsonEncode(switch (command) {
      'payload.sign' => const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      },
      'call_endpoint_set_v1' => const <String, Object?>{'ok': true},
      'call_endpoint_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_wake_handle_set_v1' => const <String, Object?>{'ok': true},
      'call_wake_handle_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_token_set_v1' => <String, Object?>{
        'ok': true,
        'generation': 3,
        'refreshEpoch':
            (request['payload']! as Map<String, dynamic>)['refreshEpoch'],
      },
      'call_token_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_retrieve_v1' => const <String, Object?>{
        'ok': true,
        'events': <Object?>[],
        'receiptAtMs': 1,
        'expiresAtMs': 1,
        'hasMore': false,
      },
      _ => const <String, Object?>{'ok': false},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _P2P implements P2PService {
  _P2P({NodeState? state})
    : state =
          state ?? const NodeState(peerId: 'local-account', isStarted: true);

  NodeState state;
  final StreamController<ChatMessage> messages =
      StreamController<ChatMessage>.broadcast();

  @override
  NodeState get currentState => state;

  @override
  Stream<ChatMessage> get messageStream => messages.stream;

  @override
  Stream<NodeState> get stateStream => const Stream<NodeState>.empty();

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: false, acked: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, bool> _enabledFlags() => <String, bool>{
  ...defaultVoiceCallFeatureFlags(),
  'voice_call_capability_v1': true,
  'voice_call_outgoing_enabled': true,
  'voice_call_incoming_enabled': true,
  'voice_call_turn_enabled': true,
  'voice_call_android_native_enabled': true,
};

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');
final _callNow = DateTime.utc(2026, 8, 30, 12);

ForegroundCallProjection _projection({
  CallId? callId,
  CallState state = CallState.ringing,
  CallDirection direction = CallDirection.outgoing,
  bool incomingValidated = false,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: callId ?? _callA,
    contactPeerId: 'contact-account',
    direction: direction,
    state: state,
    callerAccountPeerId: direction == CallDirection.incoming
        ? 'contact-account'
        : 'local-account',
    callerDeviceId: direction == CallDirection.incoming
        ? 'contact-device'
        : 'local-device',
    startedAt: _callNow,
    ringingAt: state == CallState.ringing ? _callNow : null,
    acceptedAt: switch (state) {
      CallState.accepted ||
      CallState.negotiating ||
      CallState.connected ||
      CallState.reconnecting ||
      CallState.ending ||
      CallState.ended => _callNow,
      _ => null,
    },
    connectedAt: switch (state) {
      CallState.connected ||
      CallState.reconnecting ||
      CallState.ending => _callNow,
      _ => null,
    },
    incomingValidated: incomingValidated,
  ),
  audio: CallAudioControlState.idle,
);

void main() {
  test(
    'production graph emits no-answer separately from presentation refusal',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final fixture = await _createProductionSpeakerRouteFixture();
      addTearDown(fixture.graph.shutdown);
      final graph = fixture.graph;
      for (final type in [
        CallEventType.incomingValidated,
        CallEventType.systemUiPresented,
      ]) {
        await graph.coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'unanswered-${type.name}',
            occurredAt: graph.coordinator.clock(),
            callId: _callA,
            contactPeerId: 'remote-account',
          ),
        );
      }
      final trace = diagnostics.traceForCall(callId: _callA.value);
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.timeout,
          timeoutKind: CallTimeoutKind.noAnswer,
          eventId: 'unanswered-deadline',
          occurredAt: graph.coordinator.clock().add(
            const Duration(seconds: 31),
          ),
          callId: _callA,
        ),
      );
      final summaries = (await diagnostics.eventsForTesting())
          .where(
            (event) =>
                event['stage'] == 'terminal' && event['action'] == 'finish',
          )
          .toList();
      expect(summaries, hasLength(1));
      expect(summaries.single['traceId'], trace);
      expect(summaries.single['outcome'], 'no_answer');
      expect(summaries.single['reason'], 'no_answer');
      expect((summaries.single['values'] as Map)['accepted'], isFalse);
    },
  );

  for (final nativeAudioAccepted in [false, true]) {
    test(
      'production factory emits ${nativeAudioAccepted ? 'engine activation' : 'native audio session'} refusal on the call trace',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final diagnostics = await CallDiagnostics.installForTesting();
        addTearDown(() async {
          await diagnostics.setEnabled(false);
          await diagnostics.dispose();
        });
        final fixture = await _createProductionIosFixture(
          outgoingContactAccountPeerId: 'remote-account',
          microphonePermission: const _GrantedCallMicrophonePermission(),
          nativeHandleOverride: '33333333-3333-4333-8333-333333333333',
          attachResponse: <String, Object?>{
            'version': 1,
            'descriptor': {
              'callHandle': '33333333-3333-4333-8333-333333333333',
              'expiresAtMs': 2045000,
              'presented': true,
              'phase': 'preStart',
              'direction': 'incoming',
            },
            'events': [
              {
                'callHandle': '33333333-3333-4333-8333-333333333333',
                'sequence': 1,
                'eventId': '44444444-4444-4444-8444-444444444444',
                'type': 'presented',
                'occurredAtMs': 2000000,
              },
            ],
            'nativeCallId': '33333333-3333-4333-8333-333333333333',
            'highestSequence': 1,
          },
          lifecycleOverride: (method, _) async =>
              method == 'activateAudio' ? nativeAudioAccepted : null,
        );
        await fixture.composition.start();
        expect(fixture.composition.isStarted, isTrue);
        final graph = fixture.graphs.single;
        final admission = await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.remoteInvite,
            eventId: 'audio-refusal-invite',
            occurredAt: graph.coordinator.clock(),
            callId: _callA,
            contactPeerId: 'remote-account',
            localAccountPeerId: 'local-account',
            localDeviceId: 'local-account',
            remoteAccountPeerId: 'remote-account',
            remoteDeviceId: 'remote-device',
            expiresAt: graph.coordinator.clock().add(
              const Duration(seconds: 45),
            ),
            transportRoute: CallRouteClass.direct,
          ),
        );
        expect(admission.decision, CallEventDecision.applied);
        expect(graph.coordinator.activeSession, isNotNull);
        expect(
          await graph.iosCallLifecycleAdapter!.present(
            IncomingCallPresentation(
              callId: _callA,
              callerAccountPeerId: 'remote-account',
              expiresAt: graph.coordinator.clock().add(
                const Duration(seconds: 45),
              ),
            ),
          ),
          isTrue,
        );
        final trace = diagnostics.traceForCall(callId: _callA.value);
        expect(trace, isNotNull);
        final wallNow = DateTime.now().millisecondsSinceEpoch;
        final credentials = <String, Object?>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': ['turn:relay.invalid:3478?transport=udp'],
          'username': 'private-turn-user',
          'password': 'private-turn-secret',
          'ttlSeconds': 600,
          'serverTimeMs': wallNow,
          'expiresAtMs': wallNow + 600000,
        };
        fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
        fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] =
            credentials;
        // Exercise the actual production bundle and preparer with its accepted
        // effect input; no diagnostic observer is invoked directly by this test.
        final failure = await graph.mediaOwner.execute(
          const CallEffect(CallEffectType.prepareAcceptedMedia),
          graph.coordinator.activeSession!.copyWith(
            state: CallState.accepted,
            acceptedAt: graph.coordinator.clock(),
          ),
        );
        expect(failure?.type, CallEventType.negotiationFailed);
        expect(fixture.lifecycleMethods, contains('activateAudio'));
        final events = await diagnostics.eventsForTesting();
        if (nativeAudioAccepted) {
          // Host WebRTC has no native plugin: connection creation fails after
          // the actual native audio adapter has accepted activation.
          expect(
            events.any(
              (event) =>
                  event['traceId'] == trace &&
                  (event['values'] as Map)['failureStage'] ==
                      'create_connection',
            ),
            isTrue,
          );
        }
        expect(
          events.any(
            (event) =>
                event['stage'] == 'audio' &&
                event['action'] == 'activate' &&
                event['outcome'] == 'failed' &&
                event['traceId'] == trace &&
                event['reason'] ==
                    (nativeAudioAccepted
                        ? 'audio_activation_failed'
                        : 'audio_session_failed'),
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) =>
                event['stage'] == 'audio' &&
                event['action'] == 'activate' &&
                event['outcome'] == 'ok',
          ),
          isFalse,
        );
        expect(jsonEncode(events), isNot(contains('private-turn-secret')));
      },
    );
  }

  for (final accepted in [false, true]) {
    test(
      'terminal diagnostics preserve ${accepted ? 'connected without RTP' : 'user decline'} through late shutdown',
      () async {
        final diagnostics = await CallDiagnostics.installForTesting();
        addTearDown(() async {
          await diagnostics.setEnabled(false);
          await diagnostics.dispose();
        });
        final fixture = await _createProductionSpeakerRouteFixture();
        final graph = fixture.graph;
        for (final type in [
          CallEventType.incomingValidated,
          CallEventType.systemUiPresented,
          if (accepted) ...[
            CallEventType.answer,
            CallEventType.negotiationReady,
            CallEventType.mediaConnected,
          ],
        ]) {
          await graph.coordinator.dispatch(
            CallEvent(
              type: type,
              eventId: 'terminal-${type.name}',
              occurredAt: graph.coordinator.clock(),
              callId: _callA,
              contactPeerId: 'remote-account',
            ),
          );
        }
        if (accepted) {
          expect(await graph.end(_callA), ForegroundCallActionResult.applied);
        } else {
          expect(
            await graph.decline(_callA),
            ForegroundCallActionResult.applied,
          );
        }
        await graph.shutdown();
        final summaries = (await diagnostics.eventsForTesting())
            .where(
              (event) =>
                  event['stage'] == 'terminal' && event['action'] == 'finish',
            )
            .toList();
        expect(summaries, hasLength(1));
        expect(
          summaries.single['outcome'],
          accepted ? 'answered_without_verified_media' : 'declined',
        );
        expect(
          summaries.single['reason'],
          accepted ? 'local_user' : 'declined',
        );
        expect(
          (summaries.single['values'] as Map)['mediaFlowVerified'],
          isFalse,
        );
      },
    );
  }

  test(
    'production graph reports media progress and preserves caller intent at terminal',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final fixture = await _createProductionSpeakerRouteFixture();
      addTearDown(fixture.graph.shutdown);
      final graph = fixture.graph;
      for (final type in [
        CallEventType.incomingValidated,
        CallEventType.systemUiPresented,
        CallEventType.answer,
        CallEventType.negotiationReady,
        CallEventType.mediaConnected,
      ]) {
        await graph.coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'diag-${type.name}',
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              2000000,
              isUtc: true,
            ),
            callId: _callA,
            contactPeerId: 'private-contact-not-exported',
          ),
        );
      }
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      final trace = diagnostics.traceForCall(callId: _callA.value);
      const sample = CallStatsSample(
        selectedPairSucceeded: true,
        selectedPairNominated: true,
        selectedRelayProtocol: CallRelayProtocol.udp,
        dtlsReady: true,
        transport: CallTransportClass.turnUdp,
        inboundAudioRtpObserved: true,
        outboundAudioRtpObserved: true,
      );
      graph.recordMediaDiagnostics(
        _callA,
        sample,
        const CallRtpProgressSample(inbound: false, outbound: false),
      );
      expect(
        (await diagnostics.eventsForTesting()).any(
          (event) => event['outcome'] == 'media_flow_verified',
        ),
        isFalse,
      );
      graph.recordMediaDiagnostics(
        _callA,
        sample,
        const CallRtpProgressSample(inbound: true, outbound: true),
      );
      await graph.end(_callA);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.any(
          (event) =>
              event['traceId'] == trace &&
              event['outcome'] == 'media_flow_verified',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event['traceId'] == trace &&
              event['outcome'] == 'completed_after_media' &&
              event['reason'] == 'local_user',
        ),
        isTrue,
      );
      expect(
        events
            .where((event) => event['traceId'] == trace)
            .every((event) => event['role'] == 'callee'),
        isTrue,
      );
      expect(jsonEncode(events), isNot(contains(_callA.value)));
    },
  );

  test(
    'production graph reports accepted media failure without claiming a successful call',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final fixture = await _createProductionSpeakerRouteFixture();
      addTearDown(fixture.graph.shutdown);
      final graph = fixture.graph;
      for (final type in [
        CallEventType.incomingValidated,
        CallEventType.systemUiPresented,
        CallEventType.answer,
        CallEventType.negotiationFailed,
      ]) {
        await graph.coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'diag-fail-${type.name}',
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              2000000,
              isUtc: true,
            ),
            callId: _callA,
            contactPeerId: 'private-contact-not-exported',
          ),
        );
      }
      final events = await diagnostics.eventsForTesting();
      expect(
        events.any(
          (event) =>
              event['outcome'] == 'media_failed' &&
              event['reason'] == 'media_failed',
        ),
        isTrue,
      );
      expect(
        events.any((event) => event['outcome'] == 'completed_after_media'),
        isFalse,
      );
    },
  );

  test(
    'explicit call recovery retries transient signaling readiness once',
    () async {
      var readinessAttempts = 0;
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        isForeground: () => true,
        awaitReadiness: () async {
          if (++readinessAttempts == 1) throw StateError('transport starting');
        },
        buildGraph: () async => graph,
        requestOutgoingMicrophonePermission: () async =>
            MicPermissionStatus.granted,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(await composition.isOutgoingCallAvailableFor('remote'), isFalse);
      expect(
        readinessAttempts,
        1,
        reason: 'passive probing cannot restart the graph',
      );
      final Object recovery = composition;
      final recovered =
          recovery is OutgoingCallReadinessRecovery &&
          await recovery.recoverOutgoingCallReadiness();
      expect(recovered, isTrue);
      expect(readinessAttempts, 2);
      expect(graph.outgoingPeerIds, isEmpty);
      expect(
        await composition.startOutgoingCall('remote'),
        OutgoingCallStartResult.started,
      );
      expect(graph.outgoingPeerIds, <String>['remote']);
    },
  );

  test(
    'explicit call recovery rebuilds after idle resume withdrawal',
    () async {
      final first = _Graph(<String>[], advertisementResults: [true, false]);
      final replacement = _Graph(<String>[]);
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        isForeground: () => true,
        awaitReadiness: () async {},
        buildGraph: () async => builds++ == 0 ? first : replacement,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      await composition.onResume();
      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(await composition.recoverOutgoingCallReadiness(), isTrue);
      expect(builds, 2);
      expect(first.events, contains('call_shutdown'));
      expect(first.outgoingPeerIds, isEmpty);
      expect(replacement.outgoingPeerIds, isEmpty);
    },
  );

  test(
    'explicit call recovery coalesces and invalidates a backgrounded intent',
    () async {
      final readiness = Completer<void>();
      final graph = _Graph(<String>[]);
      var readinessAttempts = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        isForeground: () => true,
        awaitReadiness: () {
          readinessAttempts++;
          return readiness.future;
        },
        buildGraph: () async => graph,
      );
      addTearDown(composition.shutdown);
      final first = composition.recoverOutgoingCallReadiness();
      final second = composition.recoverOutgoingCallReadiness();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(readinessAttempts, 1);
      await composition.onBackgrounded();
      readiness.complete();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(graph.outgoingPeerIds, isEmpty);
    },
  );

  test('explicit call recovery times out without late call placement', () {
    fakeAsync((async) {
      final readiness = Completer<void>();
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        isForeground: () => true,
        awaitReadiness: () => readiness.future,
        buildGraph: () async => graph,
      );
      bool? result;
      composition.recoverOutgoingCallReadiness().then(
        (value) => result = value,
      );
      async.flushMicrotasks();
      expect(result, isNull);
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(result, isFalse);
      readiness.complete();
      async.flushMicrotasks();
      expect(graph.outgoingPeerIds, isEmpty);
      expect(result, isFalse);
      unawaited(composition.shutdown());
      async.flushMicrotasks();
    });
  });

  for (final guard in [
    'disabled',
    'outgoing disabled',
    'background',
    'shutdown',
    'live call',
  ]) {
    test('explicit call recovery preserves $guard guard', () async {
      final flags = _enabledFlags();
      if (guard == 'disabled') flags['voice_call_capability_v1'] = false;
      if (guard == 'outgoing disabled') {
        flags['voice_call_outgoing_enabled'] = false;
      }
      final graph = _Graph(<String>[]);
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: flags,
        platform: CallEndpointPlatform.ios,
        isForeground: () => guard != 'background',
        awaitReadiness: () async {},
        buildGraph: () async {
          builds++;
          return graph;
        },
      );
      addTearDown(composition.shutdown);
      if (guard == 'shutdown') await composition.shutdown();
      if (guard == 'live call') {
        await composition.start();
        graph.emitForeground(_projection(state: CallState.ringing));
      }
      final initialBuilds = builds;
      final initialEvents = List<String>.of(graph.events);
      expect(await composition.recoverOutgoingCallReadiness(), isFalse);
      expect(builds, initialBuilds);
      expect(graph.events, initialEvents);
      expect(graph.outgoingPeerIds, isEmpty);
    });
  }

  test(
    'diagnostics capture unavailable attempt before any graph or network exists',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => throw StateError('must not construct a graph'),
      );
      addTearDown(composition.shutdown);
      expect(
        await composition.startOutgoingCall('private-contact-not-for-export'),
        OutgoingCallStartResult.unavailable,
      );
      final events = await diagnostics.eventsForTesting();
      expect(
        events.where(
          (event) => event['stage'] == 'attempt' && event['action'] == 'start',
        ),
        hasLength(1),
      );
      expect(
        events.any(
          (event) =>
              event['outcome'] == 'preflight_failed' &&
              event['reason'] == 'graph_unavailable',
        ),
        isTrue,
      );
      expect(
        jsonEncode(events),
        isNot(contains('private-contact-not-for-export')),
      );
    },
  );

  test(
    'diagnostics reuse explicit tap trace through microphone refusal without creating a second attempt',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () async =>
            MicPermissionStatus.denied,
        buildGraph: () async => graph,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      final traceId = diagnostics.beginAttempt();
      final result = await diagnostics.runWithTrace(
        traceId,
        () => composition.startOutgoingCall('private-contact-not-for-export'),
      );
      expect(result, OutgoingCallStartResult.failed);
      expect(graph.outgoingPeerIds, isEmpty);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.where(
          (event) => event['stage'] == 'attempt' && event['action'] == 'start',
        ),
        hasLength(1),
      );
      expect(
        events.any(
          (event) =>
              event['traceId'] == traceId &&
              event['outcome'] == 'preflight_failed' &&
              event['reason'] == 'microphone_denied',
        ),
        isTrue,
      );
    },
  );

  test(
    'mailbox polling follows native calls through hidden and background states',
    () {
      fakeAsync((time) {
        final events = <String>[];
        final graph = _Graph(events);
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.ios,
          awaitReadiness: () async {},
          buildGraph: () async => graph,
        );
        unawaited(composition.start());
        time.flushMicrotasks();
        graph.emitForeground(
          _projection(
            direction: CallDirection.incoming,
            incomingValidated: true,
          ),
        );
        // Native presentation never called composition.present().
        expect(composition.current, isNull);
        events.clear();
        time.elapse(const Duration(seconds: 2));
        expect(events, ['call_mailbox_drain']);

        graph.emitForeground(
          _projection(
            state: CallState.accepted,
            direction: CallDirection.incoming,
            incomingValidated: true,
          ),
        );
        unawaited(composition.onBackgrounded());
        time.flushMicrotasks();
        events.clear();
        for (final state in [
          CallState.negotiating,
          CallState.connected,
          CallState.reconnecting,
        ]) {
          graph.emitForeground(
            _projection(
              state: state,
              direction: CallDirection.incoming,
              incomingValidated: true,
            ),
          );
          expect(composition.current, isNull);
          time.elapse(const Duration(seconds: 2));
        }
        expect(events, List.filled(3, 'call_mailbox_drain'));

        graph.emitForeground(null);
        events.clear();
        time.elapse(const Duration(seconds: 4));
        expect(events, isEmpty);
        unawaited(composition.shutdown());
        time.flushMicrotasks();
        expect(time.periodicTimerCount, 0);
      });
    },
  );

  test(
    'production media disposal preserves the terminal notice projection',
    () async {
      final fixture = await _createProductionSpeakerRouteFixture();
      final graph = fixture.graph;
      final coordinator = graph.coordinator;
      for (final type in [
        CallEventType.incomingValidated,
        CallEventType.systemUiPresented,
        CallEventType.answer,
      ]) {
        await coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'notice-${type.name}',
            occurredAt: coordinator.clock(),
            callId: _callA,
          ),
        );
      }
      final projections = <ForegroundCallProjection?>[];
      final subscription = graph.changes.listen(projections.add);
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.negotiationFailed,
          eventId: 'notice-failure',
          occurredAt: coordinator.clock(),
          callId: _callA,
          endReason: CallEndReason.mediaFailed,
        ),
      );

      expect(graph.mediaOwner.currentAudioController(_callA), isNull);
      expect(graph.current, isNull);
      expect(projections, hasLength(1));
      expect(projections.single?.session.endReason, CallEndReason.mediaFailed);
      await subscription.cancel();
      await graph.shutdown();
    },
  );

  for (final ios in <bool>[false, true]) {
    for (final nativeResult in <String>['accepted', 'refused', 'exception']) {
      test('production ${ios ? 'iOS' : 'Android'} foreground Answer '
          'uses native authority when $nativeResult', () async {
        final diagnostics = await CallDiagnostics.installForTesting();
        addTearDown(() async {
          await diagnostics.setEnabled(false);
          await diagnostics.dispose();
        });
        const handle = '33333333-3333-4333-8333-333333333333';
        const nativeAnswerEventId = '44444444-4444-4444-8444-444444444444';
        final events = StreamController<Object?>.broadcast(sync: true);
        final answerArguments = <Map<String, Object?>>[];
        Map<String, Object?> batch({bool answer = false}) => {
          'version': 1,
          'descriptor': {
            'callHandle': handle,
            'expiresAtMs': 2_045_000,
            'presented': true,
            'phase': answer ? 'journal' : 'preStart',
            'direction': 'incoming',
          },
          'events': [
            {
              'callHandle': handle,
              'sequence': answer ? 2 : 1,
              'eventId': answer
                  ? nativeAnswerEventId
                  : '55555555-5555-4555-8555-555555555555',
              'type': answer ? 'answer' : 'presented',
              'occurredAtMs': 2_000_000,
            },
          ],
          'nativeCallId': handle,
          'highestSequence': answer ? 2 : 1,
        };
        Future<Object?> invoke(
          String method,
          Map<String, Object?> arguments,
        ) async {
          if (method == 'attach') return batch();
          if (method == 'answer') {
            answerArguments.add(Map.of(arguments));
            if (nativeResult == 'exception') {
              throw StateError('native answer refused');
            }
            return nativeResult == 'accepted';
          }
          return true;
        }

        final fixture = await _createProductionSpeakerRouteFixture(
          nativeLifecycleFactory: (coordinator) => ios
              ? IosCallLifecycleAdapter(
                  invokeMethod: invoke,
                  nativeEvents: events.stream,
                  coordinator: coordinator,
                  resolveAuthenticatedHandle: (callId) =>
                      callId == _callA ? handle : null,
                  clock: coordinator.clock,
                )
              : AndroidCallLifecycleAdapter(
                  invokeMethod: invoke,
                  nativeEvents: events.stream,
                  coordinator: coordinator,
                  resolveAuthenticatedHandle: (callId) =>
                      callId == _callA ? handle : null,
                  clock: coordinator.clock,
                ),
        );
        final graph = fixture.graph;
        final coordinator = graph.coordinator;
        addTearDown(() async {
          await graph.shutdown();
          await coordinator.dispose();
          await events.close();
        });
        await coordinator.dispatch(
          CallEvent(
            type: CallEventType.incomingValidated,
            eventId: 'foreground-answer-validated',
            occurredAt: coordinator.clock(),
            callId: _callA,
          ),
        );
        final native =
            graph.iosCallLifecycleAdapter ?? graph.androidCallLifecycleAdapter!;
        expect(
          await native.present(
            IncomingCallPresentation(
              callId: _callA,
              callerAccountPeerId: 'remote-account',
              expiresAt: coordinator.clock().add(const Duration(seconds: 45)),
            ),
          ),
          isTrue,
        );
        await coordinator.dispatch(
          CallEvent(
            type: CallEventType.systemUiPresented,
            eventId: 'foreground-answer-presented',
            occurredAt: coordinator.clock(),
            callId: _callA,
          ),
        );
        expect(coordinator.activeSession?.state, CallState.ringing);
        expect(
          await graph.answer(_callB),
          ForegroundCallActionResult.unavailable,
        );
        expect(answerArguments, isEmpty);

        expect(
          await graph.answer(_callA),
          nativeResult == 'accepted'
              ? ForegroundCallActionResult.applied
              : ForegroundCallActionResult.unavailable,
        );
        expect(answerArguments, hasLength(1));
        expect(answerArguments.single['version'], 1);
        expect(answerArguments.single['callHandle'], handle);
        final answerTrace = diagnostics.traceForCall(callId: _callA.value);
        expect(
          (answerArguments.single['diagnostics'] as Map)['traceId'],
          answerTrace,
        );
        final answerEvents = (await diagnostics.eventsForTesting())
            .where(
              (event) =>
                  event['stage'] == 'answer' && event['action'] == 'accept',
            )
            .toList();
        expect(answerEvents.map((event) => event['outcome']), [
          'started',
          nativeResult == 'accepted' ? 'ok' : 'rejected',
        ]);
        expect(
          answerEvents,
          everyElement(containsPair('traceId', answerTrace)),
        );
        if (nativeResult != 'accepted') {
          expect(answerEvents.last['reason'], 'native_answer_refused');
        }
        // Native acceptance, not the button callback, must produce the
        // canonical answer that authorizes native audio acquisition.
        expect(coordinator.activeSession?.state, CallState.ringing);
        if (nativeResult == 'accepted') {
          events.add(batch(answer: true));
          await _untilComposition(
            () => coordinator.activeSession?.state == CallState.accepted,
          );
          expect(
            coordinator.activeSession?.recentEventIds,
            contains(nativeAnswerEventId),
          );
        }
      });
    }
  }

  test(
    'production foreground Answer keeps the non-native acceptance path',
    () async {
      final fixture = await _createProductionSpeakerRouteFixture();
      final graph = fixture.graph;
      addTearDown(() async {
        await graph.shutdown();
        await graph.coordinator.dispose();
      });
      for (final type in <CallEventType>[
        CallEventType.incomingValidated,
        CallEventType.systemUiPresented,
      ]) {
        await graph.coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'non-native-${type.name}',
            occurredAt: graph.coordinator.clock(),
            callId: _callA,
          ),
        );
      }
      expect(await graph.answer(_callA), ForegroundCallActionResult.applied);
      expect(graph.coordinator.activeSession?.state, CallState.accepted);
    },
  );

  setUpAll(sqfliteFfiInit);

  test(
    'default-off flags construct no runtime and install no subscription',
    () async {
      final events = <String>[];
      final composition = CallSignalingComposition(
        featureFlags: defaultVoiceCallFeatureFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async => events.add('readiness'),
        buildGraph: () async {
          events.add('build');
          return _Graph(events);
        },
      );

      await composition.start();
      await composition.onResume();
      await composition.shutdown();

      expect(composition.isEnabled, isFalse);
      expect(events, isEmpty);
    },
  );

  test(
    'foreground call graph does not require later native lifecycle flags',
    () {
      final flags = <String, bool>{
        ...defaultVoiceCallFeatureFlags(),
        'voice_call_capability_v1': true,
        'voice_call_outgoing_enabled': true,
        'voice_call_incoming_enabled': true,
        'voice_call_turn_enabled': true,
      };
      final composition = CallSignalingComposition(
        featureFlags: flags,
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => _Graph(<String>[]),
      );

      expect(composition.isEnabled, isTrue);
    },
  );

  test(
    'foreground graph stays fail-closed while TURN gate is disabled',
    () async {
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: <String, bool>{
          ...defaultVoiceCallFeatureFlags(),
          'voice_call_capability_v1': true,
          'voice_call_outgoing_enabled': true,
          'voice_call_incoming_enabled': true,
        },
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async {
          builds++;
          return _Graph(<String>[]);
        },
      );

      await composition.start();

      expect(composition.isEnabled, isFalse);
      expect(builds, 0);
    },
  );

  test('outgoing-only flags build and advertise no call graph', () async {
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: <String, bool>{
        ...defaultVoiceCallFeatureFlags(),
        'voice_call_capability_v1': true,
        'voice_call_incoming_enabled': false,
        'voice_call_outgoing_enabled': true,
        'voice_call_turn_enabled': true,
      },
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async {
        events.add('build');
        return _Graph(events);
      },
    );

    await composition.start();
    await composition.onResume();

    expect(composition.isEnabled, isFalse);
    expect(composition.isStarted, isFalse);
    expect(composition.isOutgoingCallAvailable, isFalse);
    expect(events, isEmpty);
  });

  test(
    'incoming-only graph never exposes or invokes outgoing capability',
    () async {
      final events = <String>[];
      final graph = _Graph(events);
      final composition = CallSignalingComposition(
        featureFlags: <String, bool>{
          ...defaultVoiceCallFeatureFlags(),
          'voice_call_capability_v1': true,
          'voice_call_incoming_enabled': true,
          'voice_call_outgoing_enabled': false,
          'voice_call_turn_enabled': true,
        },
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
      );

      await composition.start();

      expect(composition.isEnabled, isTrue);
      expect(composition.isStarted, isTrue);
      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(events, <String>['call_subscription', 'advertise']);
      expect(
        await composition.startOutgoingCall('peer-must-not-be-used'),
        OutgoingCallStartResult.unavailable,
      );
      expect(graph.outgoingPeerIds, isEmpty);
    },
  );

  test(
    'outgoing capability delegates once to the current started graph only',
    () async {
      final events = <String>[];
      final first = _Graph(
        events,
        advertisementResults: const <bool>[true, true, false],
      );
      final second = _Graph(
        events,
        outgoingResult: OutgoingCallStartResult.failed,
      );
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () async =>
            MicPermissionStatus.granted,
        buildGraph: () async => builds++ == 0 ? first : second,
      );

      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(
        await composition.startOutgoingCall('peer-before-start'),
        OutgoingCallStartResult.unavailable,
      );

      await composition.start();
      expect(composition.isOutgoingCallAvailable, isTrue);
      expect(
        await composition.startOutgoingCall('  exact-account-peer-id  '),
        OutgoingCallStartResult.started,
      );
      expect(first.outgoingPeerIds, <String>['  exact-account-peer-id  ']);

      await composition.onResume();
      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(
        await composition.startOutgoingCall('peer-after-withdrawal'),
        OutgoingCallStartResult.unavailable,
      );
      expect(first.outgoingPeerIds, <String>['  exact-account-peer-id  ']);

      await composition.start();
      expect(composition.isOutgoingCallAvailable, isTrue);
      expect(
        await composition.startOutgoingCall('peer-on-replacement'),
        OutgoingCallStartResult.failed,
      );
      expect(first.outgoingPeerIds, <String>['  exact-account-peer-id  ']);
      expect(second.outgoingPeerIds, <String>['peer-on-replacement']);
    },
  );

  test(
    'outgoing refreshes caller authority after microphone grant before invite',
    () async {
      final events = <String>[];
      final wakeAuthority = Completer<bool>();
      final wakeAuthorityPeerIds = <String>[];
      final graph = _Graph(events);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () async =>
            MicPermissionStatus.granted,
        ensureOutgoingCallWakeAuthority: (contactAccountPeerId) {
          wakeAuthorityPeerIds.add(contactAccountPeerId);
          return wakeAuthority.future;
        },
        buildGraph: () async => graph,
      );
      await composition.start();

      expect(events, <String>['call_subscription', 'advertise']);
      final result = composition.startOutgoingCall('exact-contact-peer');
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>['call_subscription', 'advertise', 'advertise']);
      expect(wakeAuthorityPeerIds, <String>['exact-contact-peer']);
      expect(graph.outgoingPeerIds, isEmpty);

      wakeAuthority.complete(true);
      expect(await result, OutgoingCallStartResult.started);
      expect(graph.outgoingPeerIds, <String>['exact-contact-peer']);
    },
  );

  test(
    'failed caller wake-authority distribution blocks invite fail closed',
    () async {
      for (final throws in <bool>[false, true]) {
        final graph = _Graph(<String>[]);
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.ios,
          awaitReadiness: () async {},
          requestOutgoingMicrophonePermission: () async =>
              MicPermissionStatus.granted,
          ensureOutgoingCallWakeAuthority: (_) async {
            if (throws) {
              throw StateError('private wake-authority detail');
            }
            return false;
          },
          buildGraph: () async => graph,
        );
        addTearDown(composition.shutdown);
        await composition.start();

        expect(
          await composition.startOutgoingCall('exact-contact-peer'),
          throws
              ? OutgoingCallStartResult.failed
              : OutgoingCallStartResult.unavailable,
        );
        expect(graph.outgoingPeerIds, isEmpty);
        expect(composition.isStarted, isTrue);
      }
    },
  );

  test('wake-authority completion cannot enter a withdrawn graph', () async {
    final wakeAuthority = Completer<bool>();
    final events = <String>[];
    final first = _Graph(
      events,
      advertisementResults: const <bool>[true, true, false],
    );
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.ios,
      awaitReadiness: () async {},
      requestOutgoingMicrophonePermission: () async =>
          MicPermissionStatus.granted,
      ensureOutgoingCallWakeAuthority: (_) => wakeAuthority.future,
      buildGraph: () async => first,
    );
    await composition.start();

    final result = composition.startOutgoingCall('stale-contact-peer');
    await Future<void>.delayed(Duration.zero);
    await composition.onResume();
    expect(composition.isStarted, isFalse);

    wakeAuthority.complete(true);

    expect(await result, OutgoingCallStartResult.unavailable);
    expect(first.outgoingPeerIds, isEmpty);
  });

  test(
    'failed pre-call authority refresh withdraws before invite delegation',
    () async {
      final events = <String>[];
      final graph = _Graph(
        events,
        advertisementResults: const <bool>[true, false],
      );
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () async =>
            MicPermissionStatus.granted,
        buildGraph: () async => graph,
      );
      await composition.start();

      expect(
        await composition.startOutgoingCall('exact-contact-peer'),
        OutgoingCallStartResult.unavailable,
      );
      expect(graph.outgoingPeerIds, isEmpty);
      expect(events, <String>[
        'call_subscription',
        'advertise',
        'advertise',
        'call_shutdown',
      ]);
      expect(composition.isStarted, isFalse);
      expect(composition.isOutgoingCallAvailable, isFalse);
    },
  );

  test(
    'outgoing microphone preflight blocks graph delegation until granted',
    () async {
      final graph = _Graph(<String>[]);
      final permission = Completer<MicPermissionStatus>();
      var permissionRequests = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () {
          permissionRequests++;
          return permission.future;
        },
        buildGraph: () async => graph,
      );
      await composition.start();

      final result = composition.startOutgoingCall('exact-contact-peer');
      await Future<void>.delayed(Duration.zero);

      expect(permissionRequests, 1);
      expect(graph.outgoingPeerIds, isEmpty);

      permission.complete(MicPermissionStatus.granted);

      expect(await result, OutgoingCallStartResult.started);
      expect(graph.outgoingPeerIds, <String>['exact-contact-peer']);
    },
  );

  test('outgoing microphone refusal or failure is fixed fail-closed', () async {
    for (final permissionStatus in <MicPermissionStatus>[
      MicPermissionStatus.denied,
      // The shared gateway folds the platform restricted state into this
      // value because neither can be re-prompted in-app.
      MicPermissionStatus.permanentlyDenied,
    ]) {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        requestOutgoingMicrophonePermission: () async => permissionStatus,
        buildGraph: () async => graph,
      );
      await composition.start();

      expect(
        await composition.startOutgoingCall('peer-$permissionStatus'),
        OutgoingCallStartResult.failed,
      );
      expect(graph.outgoingPeerIds, isEmpty);
    }

    final throwingGraph = _Graph(<String>[]);
    final throwingComposition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.ios,
      awaitReadiness: () async {},
      requestOutgoingMicrophonePermission: () async =>
          throw StateError('permission adapter details must stay private'),
      buildGraph: () async => throwingGraph,
    );
    await throwingComposition.start();

    expect(
      await throwingComposition.startOutgoingCall('peer-on-throw'),
      OutgoingCallStartResult.failed,
    );
    expect(throwingGraph.outgoingPeerIds, isEmpty);
  });

  test(
    'outgoing permission completion cannot enter a withdrawn or replaced graph',
    () async {
      for (final replaceGraph in <bool>[false, true]) {
        final permission = Completer<MicPermissionStatus>();
        final events = <String>[];
        final first = _Graph(
          events,
          advertisementResults: const <bool>[true, false],
        );
        final second = _Graph(events);
        var builds = 0;
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.ios,
          awaitReadiness: () async {},
          requestOutgoingMicrophonePermission: () => permission.future,
          buildGraph: () async => builds++ == 0 ? first : second,
        );
        await composition.start();

        final result = composition.startOutgoingCall('stale-contact-peer');
        await Future<void>.delayed(Duration.zero);
        await composition.onResume();
        expect(composition.isOutgoingCallAvailable, isFalse);
        if (replaceGraph) {
          await composition.start();
          expect(composition.isOutgoingCallAvailable, isTrue);
        }

        permission.complete(MicPermissionStatus.granted);

        expect(await result, OutgoingCallStartResult.unavailable);
        expect(first.outgoingPeerIds, isEmpty);
        expect(second.outgoingPeerIds, isEmpty);
        await composition.shutdown();
      }
    },
  );

  test(
    'contact action stays hidden unless current graph resolves one endpoint',
    () async {
      final graph = _Graph(<String>[], contactOutgoingAvailable: false);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
      );
      await composition.start();

      expect(
        await composition.isOutgoingCallAvailableFor('exact-contact-peer'),
        isFalse,
      );
      expect(graph.availabilityPeerIds, <String>['exact-contact-peer']);
    },
  );

  test(
    'stable composition delegates call-wake distribution only to active graph',
    () async {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
      );

      expect(
        await composition.resolveCallWakeHandle('contact-account'),
        isNull,
      );
      await composition.start();
      final grant = await composition.resolveCallWakeHandle('contact-account');
      expect(grant, isNotNull);
      await composition.onCallWakeHandleDistributed('contact-account', grant!);

      expect(graph.wakeGrantPeerIds, <String>['contact-account']);
      expect(graph.distributedWakeGrants, <(String, CallWakeHandleGrant)>[
        ('contact-account', grant),
      ]);

      await composition.shutdown();
      expect(
        await composition.resolveCallWakeHandle('contact-account'),
        isNull,
      );
    },
  );

  test('resume rearms current call-wake grants once per process', () async {
    final events = <String>[];
    final graph = _Graph(events, recordRearmEvent: true);
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async => graph,
    );
    addTearDown(composition.shutdown);

    await composition.start();
    await composition.onResume();
    await composition.onResume();

    expect(graph.rearmCalls, 1);
    expect(events, <String>[
      'call_subscription',
      'advertise',
      'mailbox_resume',
      'advertise',
      'wake_rearm',
      'mailbox_resume',
      'advertise',
    ]);
  });

  test('resume retries call-wake rearm after a transient failure', () async {
    final graph = _Graph(<String>[], rearmResults: <bool>[false, true]);
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async => graph,
    );
    addTearDown(composition.shutdown);

    await composition.start();
    await composition.onResume();
    await composition.onResume();

    expect(graph.rearmCalls, 2);
  });

  test('concurrent resumes coalesce one call-wake rearm attempt', () async {
    final rearmCompleter = Completer<bool>();
    final graph = _Graph(<String>[], rearmCompleter: rearmCompleter);
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async => graph,
    );
    addTearDown(composition.shutdown);

    await composition.start();
    final first = composition.onResume();
    final second = composition.onResume();
    await pumpEventQueue(times: 3);
    final callsBeforeCompletion = graph.rearmCalls;
    rearmCompleter.complete(true);
    await Future.wait(<Future<void>>[first, second]);

    expect(callsBeforeCompletion, 1);
    expect(graph.rearmCalls, 1);
  });

  test('wake-handle refresh only re-publishes outgoing availability', () async {
    final events = <String>[];
    final graph = _Graph(events);
    var builds = 0;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async {
        builds += 1;
        return graph;
      },
    );
    addTearDown(composition.shutdown);
    final readiness = <bool>[];
    final subscription = composition.outgoingCallAvailabilityChanges.listen(
      readiness.add,
    );
    addTearDown(subscription.cancel);

    await composition.refreshOutgoingCallAvailability();
    expect(readiness, <bool>[false]);
    expect(builds, 0);
    expect(events, isEmpty);

    await composition.start();
    expect(readiness, <bool>[false, true]);
    expect(builds, 1);
    expect(events, <String>['call_subscription', 'advertise']);

    await composition.refreshOutgoingCallAvailability();
    expect(readiness, <bool>[false, true, true]);
    expect(builds, 1);
    expect(events, <String>['call_subscription', 'advertise']);
    expect(graph.availabilityPeerIds, isEmpty);
  });

  test(
    'contact eligibility refreshes serialize and withdraw on failed authority',
    () async {
      final events = <String>[];
      final graph = _Graph(
        events,
        advertisementResults: const <bool>[true, true, false],
      );
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.ios,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
      );

      await composition.start();
      final first = composition.onContactEligibilityChanged();
      final second = composition.onContactEligibilityChanged();
      await Future.wait(<Future<void>>[first, second]);

      expect(events, <String>[
        'call_subscription',
        'advertise',
        'advertise',
        'advertise',
        'call_shutdown',
      ]);
      expect(composition.isStarted, isFalse);
      expect(composition.isOutgoingCallAvailable, isFalse);
    },
  );

  test(
    'outgoing readiness re-emits after resume and graph replacement',
    () async {
      final events = <String>[];
      final first = _Graph(
        events,
        advertisementResults: const <bool>[true, true, false],
      );
      final second = _Graph(events);
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => builds++ == 0 ? first : second,
      );
      addTearDown(composition.shutdown);
      final readiness = <bool>[];
      final subscription = composition.outgoingCallAvailabilityChanges.listen(
        readiness.add,
      );
      addTearDown(subscription.cancel);

      await composition.start();
      await composition.onResume();
      await composition.onResume();
      await composition.start();

      expect(readiness, <bool>[true, true, false, true]);
    },
  );

  for (final contactRefresh in <bool>[false, true]) {
    for (final throws in <bool>[false, true]) {
      test(
        'late ${contactRefresh ? 'contact' : 'resume'} advertisement '
        '${throws ? 'exception' : 'failure'} preserves replacement readiness',
        () async {
          final first = _Graph(<String>[]);
          final second = _Graph(<String>[]);
          var builds = 0;
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: CallEndpointPlatform.android,
            awaitReadiness: () async {},
            requestOutgoingMicrophonePermission: () async =>
                MicPermissionStatus.granted,
            buildGraph: () async => builds++ == 0 ? first : second,
          );
          addTearDown(() async {
            await composition.shutdown();
            await first.callabilityInvalidationsController.close();
            await second.callabilityInvalidationsController.close();
          });
          await composition.start();

          final advertisementEntered = Completer<void>();
          final advertisementResult = Completer<bool>();
          first.onAdvertise = () {
            advertisementEntered.complete();
            return advertisementResult.future;
          };
          final staleRefresh = contactRefresh
              ? composition.onContactEligibilityChanged()
              : composition.onResume();
          await advertisementEntered.future;
          first.callabilityInvalidationsController.add(null);
          expect(composition.isOutgoingCallAvailable, isFalse);
          await composition.start();
          expect(composition.isStarted, isTrue);
          expect(composition.isOutgoingCallAvailable, isTrue);

          if (throws) {
            advertisementResult.completeError(StateError('old advertisement'));
          } else {
            advertisementResult.complete(false);
          }
          await staleRefresh;

          expect(composition.isStarted, isTrue);
          expect(composition.isOutgoingCallAvailable, isTrue);
          final replacement = _projection(callId: _callB);
          second.emitForeground(replacement);
          expect(composition.current, same(replacement));
          expect(second.events, isNot(contains('call_shutdown')));
          expect(
            await composition.startOutgoingCall('peer-after-replacement'),
            OutgoingCallStartResult.started,
          );
          expect(second.outgoingPeerIds, <String>['peer-after-replacement']);
          expect(first.outgoingPeerIds, isEmpty);
        },
      );
    }
  }

  test(
    'stable foreground capability replays current graph and fences stale actions',
    () async {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        isForeground: () => true,
      );
      final emitted = <ForegroundCallProjection?>[];
      final subscription = composition.changes.listen(emitted.add);
      addTearDown(subscription.cancel);
      await composition.start();

      final projection = _projection();
      graph.emitForeground(projection);

      expect(composition.current, same(projection));
      expect(emitted.last, same(projection));
      expect(
        await composition.cancel(_callB),
        same(ForegroundCallActionResult.unavailable),
      );
      expect(graph.foregroundActions, isEmpty);
      expect(
        await composition.cancel(_callA),
        same(ForegroundCallActionResult.applied),
      );
      expect(graph.foregroundActions, <(String, CallId, bool?)>[
        ('cancel', _callA, null),
      ]);

      await composition.shutdown();
      expect(composition.current, isNull);
      expect(emitted.last, isNull);
    },
  );

  test(
    'the call the surface showed passes its terminal snapshot through once',
    () async {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        isForeground: () => true,
      );
      final emitted = <ForegroundCallProjection?>[];
      final subscription = composition.changes.listen(emitted.add);
      addTearDown(subscription.cancel);
      await composition.onResume();

      final live = _projection();
      graph.emitForeground(live);
      await Future<void>.delayed(Duration.zero);
      expect(composition.current, same(live));

      // The end notice ("Call declined") needs the terminal snapshot once;
      // `current` then holds null so a resume never replays it.
      final ended = ForegroundCallProjection(
        session: live.session.copyWith(
          state: CallState.ended,
          endedAt: _callNow,
          endReason: CallEndReason.declined,
        ),
        audio: live.audio,
      );
      graph.emitForeground(ended);
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last, same(ended));
      expect(composition.current, isNull);

      // A terminal snapshot for a call the surface never showed stays hidden.
      graph.emitForeground(
        ForegroundCallProjection(
          session: _projection(callId: _callB).session.copyWith(
            state: CallState.ended,
            endedAt: _callNow,
            endReason: CallEndReason.noAnswer,
          ),
          audio: live.audio,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last, isNull);
    },
  );

  test(
    'withdrawal publishes null before shutdown and ignores old graph',
    () async {
      late final _Graph first;
      first = _Graph(
        <String>[],
        advertisementResults: const <bool>[true, false],
        onShutdown: (graph) =>
            graph.emitForeground(_projection(callId: _callB)),
      );
      final second = _Graph(<String>[]);
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => builds++ == 0 ? first : second,
        isForeground: () => true,
      );
      final emitted = <ForegroundCallProjection?>[];
      final subscription = composition.changes.listen(emitted.add);
      addTearDown(subscription.cancel);
      await composition.start();
      // A live call would block withdrawal (see the live-call resume test);
      // an ended session does not.
      final live = _projection();
      first.emitForeground(
        ForegroundCallProjection(
          session: live.session.copyWith(
            state: CallState.ended,
            endedAt: _callNow,
            endReason: CallEndReason.localHangup,
          ),
          audio: live.audio,
        ),
      );

      await composition.onResume();

      expect(composition.current, isNull);
      expect(emitted.last, isNull);
      expect(
        emitted.where((value) => value?.session.callId == _callB),
        isEmpty,
      );

      await composition.start();
      final replacement = _projection(callId: _callB);
      second.emitForeground(replacement);
      expect(composition.current, same(replacement));
    },
  );

  test(
    'incoming presentation requires foreground listener validation and expiry',
    () async {
      var foreground = true;
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        isForeground: () => foreground,
        clock: () => _callNow,
      );
      await composition.start();
      final presentation = IncomingCallPresentation(
        callId: _callA,
        callerAccountPeerId: 'contact-account',
        expiresAt: _callNow.add(const Duration(seconds: 30)),
      );
      final validated = _projection(
        direction: CallDirection.incoming,
        state: CallState.incomingValidating,
        incomingValidated: true,
      );
      graph.emitForeground(validated);

      expect(await composition.present(presentation), isFalse);
      final emitted = <ForegroundCallProjection?>[];
      final subscription = composition.changes.listen(emitted.add);
      addTearDown(subscription.cancel);

      graph.emitForeground(
        _projection(
          direction: CallDirection.incoming,
          state: CallState.incomingValidating,
          incomingValidated: false,
        ),
      );
      expect(await composition.present(presentation), isFalse);

      graph.emitForeground(validated);
      foreground = false;
      expect(await composition.present(presentation), isFalse);
      foreground = true;
      expect(await composition.present(presentation), isTrue);
      expect(composition.current, same(validated));

      await composition.dismiss(presentation);
      expect(composition.current, isNull);
      expect(emitted.last, isNull);

      expect(
        await composition.present(
          IncomingCallPresentation(
            callId: _callA,
            callerAccountPeerId: 'contact-account',
            expiresAt: _callNow,
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'backgrounding withdraws UI and terminalizes only the active call',
    () async {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        isForeground: () => true,
      );
      final subscription = composition.changes.listen((_) {});
      addTearDown(subscription.cancel);
      await composition.start();
      graph.emitForeground(_projection(state: CallState.connected));
      expect(composition.current, isNotNull);

      await composition.onBackgrounded();

      expect(composition.current, isNull);
      expect(graph.backgroundCalls, 1);
      expect(composition.isStarted, isTrue);
      expect(graph.events, isNot(contains('call_shutdown')));
    },
  );

  for (final platform in <CallEndpointPlatform>[
    CallEndpointPlatform.android,
    CallEndpointPlatform.ios,
  ]) {
    for (final arrivesInBackground in <bool>[false, true]) {
      test(
        '${arrivesInBackground ? 'background arrival' : 'foreground'} '
        '${platform.name} native ringing exposes controls only after validated presentation',
        () async {
          var foreground = !arrivesInBackground;
          final graph = _Graph(<String>[]);
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: platform,
            awaitReadiness: () async {},
            buildGraph: () async => graph,
            isForeground: () => foreground,
            clock: () => _callNow,
          );
          final subscription = composition.changes.listen((_) {});
          addTearDown(subscription.cancel);
          addTearDown(composition.shutdown);
          await composition.start();
          if (arrivesInBackground) await composition.onBackgrounded();

          // The production native presenter owns registration; composition's
          // present() is never called, even after that presenter succeeds.
          graph.emitForeground(
            _projection(
              direction: CallDirection.incoming,
              state: CallState.incomingValidating,
              incomingValidated: true,
            ),
          );
          expect(composition.current, isNull);
          expect(
            await composition.answer(_callA),
            ForegroundCallActionResult.unavailable,
          );
          graph.emitForeground(_projection(direction: CallDirection.incoming));
          expect(composition.current, isNull);

          final ringing = _projection(
            direction: CallDirection.incoming,
            incomingValidated: true,
          );
          graph.emitForeground(ringing);
          if (arrivesInBackground) {
            expect(composition.current, isNull);
            expect(graph.foregroundActions, isEmpty);
            foreground = true;
            await composition.onResume();
          }
          expect(composition.current, same(ringing));
          expect(graph.foregroundActions, isEmpty);
          expect(
            await composition.answer(_callB),
            ForegroundCallActionResult.unavailable,
          );

          foreground = false;
          await composition.onBackgrounded();
          expect(composition.current, isNull);
          graph.emitForeground(ringing);
          expect(composition.current, isNull);
          expect(
            await composition.answer(_callA),
            ForegroundCallActionResult.unavailable,
          );

          // A notification body tap only resumes the app. It neither accepts
          // the call nor needs the composition-owned presentation marker.
          foreground = true;
          await composition.onResume();
          expect(composition.current, same(ringing));
          expect(graph.foregroundActions, isEmpty);
          expect(
            await composition.answer(_callA),
            ForegroundCallActionResult.applied,
          );
          expect(graph.foregroundActions, <(String, CallId, bool?)>[
            ('answer', _callA, null),
          ]);

          graph.emitForeground(
            ForegroundCallProjection(
              session: ringing.session.copyWith(
                state: CallState.ended,
                endedAt: _callNow,
                endReason: CallEndReason.noAnswer,
              ),
              audio: ringing.audio,
            ),
          );
          expect(composition.current, isNull);
          expect(
            await composition.answer(_callA),
            ForegroundCallActionResult.unavailable,
          );
          expect(graph.foregroundActions, hasLength(1));
        },
      );
    }
  }

  test(
    'resume restores a validated incoming active call after native UI',
    () async {
      final graph = _Graph(<String>[]);
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        isForeground: () => true,
        clock: () => _callNow,
      );
      final emitted = <ForegroundCallProjection?>[];
      final subscription = composition.changes.listen(emitted.add);
      addTearDown(subscription.cancel);
      addTearDown(composition.shutdown);
      await composition.start();

      final validating = _projection(
        direction: CallDirection.incoming,
        state: CallState.incomingValidating,
        incomingValidated: true,
      );
      graph.emitForeground(validating);
      expect(
        await composition.present(
          IncomingCallPresentation(
            callId: _callA,
            callerAccountPeerId: 'contact-account',
            expiresAt: _callNow.add(const Duration(seconds: 30)),
          ),
        ),
        isTrue,
      );

      final connected = _projection(
        direction: CallDirection.incoming,
        state: CallState.connected,
        incomingValidated: true,
      );
      graph.emitForeground(connected);
      expect(composition.current, same(connected));

      await composition.onBackgrounded();
      expect(composition.current, isNull);

      await composition.onResume();

      expect(composition.current, same(connected));
      expect(emitted.last, same(connected));
      expect(graph.backgroundCalls, 1);
    },
  );

  test(
    'enabled graph starts after readiness and owns an independent lifecycle',
    () async {
      final events = <String>[];
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async => events.add('readiness'),
        buildGraph: () async {
          events.add('coordinator_constructed');
          return _Graph(events);
        },
      );

      await Future.wait(<Future<void>>[
        composition.start(),
        composition.start(),
      ]);
      expect(events, <String>[
        'readiness',
        'coordinator_constructed',
        'call_subscription',
        'advertise',
      ]);

      await composition.onResume();
      expect(events, <String>[
        'readiness',
        'coordinator_constructed',
        'call_subscription',
        'advertise',
        'mailbox_resume',
        'advertise',
      ]);

      await Future.wait(<Future<void>>[
        composition.shutdown(),
        composition.shutdown(),
      ]);
      await composition.onResume();
      expect(events.last, 'call_shutdown');
      expect(events.where((event) => event == 'call_shutdown'), hasLength(1));
    },
  );

  test(
    'start and resume diagnostics expose only identifier-free graph state',
    () async {
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => _Graph(<String>[]),
      );
      addTearDown(composition.shutdown);

      await composition.start();
      await composition.onResume();

      final diagnostics = flow
          .where(
            (payload) =>
                payload['layer'] == 'CALL_SIGNALING_COMPOSITION' &&
                (payload['event'] == 'CALL_SIGNALING_START_RESULT' ||
                    payload['event'] == 'CALL_SIGNALING_RESUME_RESULT'),
          )
          .toList(growable: false);
      expect(diagnostics.map((payload) => payload['event']), <String>[
        'CALL_SIGNALING_START_RESULT',
        'CALL_SIGNALING_RESUME_RESULT',
      ]);
      for (final payload in diagnostics) {
        final details = payload['details']! as Map<String, dynamic>;
        final isStart = payload['event'] == 'CALL_SIGNALING_START_RESULT';
        expect(details.keys, <String>{
          'outcome',
          'enabled',
          'started',
          'graphPresent',
          'outgoingAvailable',
          if (isStart) 'stage',
        });
        expect(details, <String, dynamic>{
          'outcome': 'ready',
          'enabled': true,
          'started': true,
          'graphPresent': true,
          'outgoingAvailable': true,
          if (isStart) 'stage': 'complete',
        });
      }
    },
  );

  test(
    'failed start diagnostic distinguishes capability advertisement withdrawal',
    () async {
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async =>
            _Graph(<String>[], advertisementResults: const <bool>[false]),
      );

      await composition.start();

      final payload = flow.singleWhere(
        (event) => event['event'] == 'CALL_SIGNALING_START_RESULT',
      );
      expect(payload['details'], <String, dynamic>{
        'outcome': 'advertisement_unavailable',
        'enabled': true,
        'started': false,
        'graphPresent': false,
        'outgoingAvailable': false,
        'stage': 'capabilityAdvertisement',
      });
    },
  );

  test(
    'failed start diagnostic reports the exact fixed lifecycle stage',
    () async {
      final cases =
          <
            ({
              String stage,
              CallSignalingComposition Function() buildComposition,
            })
          >[
            (
              stage: 'foregroundPresentationReadiness',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitForegroundPresentationReadiness: () async =>
                    throw StateError('private foreground readiness detail'),
                awaitReadiness: () async {},
                buildGraph: () async => _Graph(<String>[]),
              ),
            ),
            (
              stage: 'signalingReadiness',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitReadiness: () async =>
                    throw StateError('private signaling readiness detail'),
                buildGraph: () async => _Graph(<String>[]),
              ),
            ),
            (
              stage: 'graphConstruction',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitReadiness: () async {},
                buildGraph: () async =>
                    throw StateError('private graph construction detail'),
              ),
            ),
            (
              stage: 'foregroundBinding',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitReadiness: () async {},
                buildGraph: () async =>
                    _Graph(<String>[], throwOnForegroundChanges: true),
              ),
            ),
            (
              stage: 'listenerInstallation',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitReadiness: () async {},
                buildGraph: () async => _Graph(<String>[], throwOnStart: true),
              ),
            ),
            (
              stage: 'capabilityAdvertisement',
              buildComposition: () => CallSignalingComposition(
                featureFlags: _enabledFlags(),
                platform: CallEndpointPlatform.android,
                awaitReadiness: () async {},
                buildGraph: () async =>
                    _Graph(<String>[], throwOnAdvertise: true),
              ),
            ),
          ];
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      addTearDown(() => debugSetFlowEventSink(null));

      for (final testCase in cases) {
        final composition = testCase.buildComposition();
        await composition.start();
        final payload = flow.removeLast();
        final details = payload['details']! as Map<String, dynamic>;
        expect(payload['event'], 'CALL_SIGNALING_START_RESULT');
        expect(details['outcome'], 'failed');
        expect(details['stage'], testCase.stage);
        expect(details.keys, isNot(contains('error')));
        expect(details.values, isNot(contains(contains('private'))));
        await composition.shutdown();
      }
    },
  );

  test(
    'failed resume diagnostic reports post-withdrawal graph state',
    () async {
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async =>
            _Graph(<String>[], advertisementResults: const <bool>[true, false]),
      );
      await composition.start();

      await composition.onResume();

      final payload = flow.singleWhere(
        (event) => event['event'] == 'CALL_SIGNALING_RESUME_RESULT',
      );
      expect(payload['details'], <String, dynamic>{
        'outcome': 'advertisement_unavailable',
        'enabled': true,
        'started': false,
        'graphPresent': false,
        'outgoingAvailable': false,
      });
    },
  );

  test('diagnostic sink failure cannot change lifecycle outcome', () async {
    debugSetFlowEventSink((_) => throw StateError('diagnostic sink failed'));
    addTearDown(() => debugSetFlowEventSink(null));
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async => _Graph(events),
    );
    addTearDown(composition.shutdown);

    await composition.start();
    await composition.onResume();

    expect(composition.isStarted, isTrue);
    expect(events, <String>[
      'call_subscription',
      'advertise',
      'mailbox_resume',
      'advertise',
    ]);
  });

  test(
    'production start waits until foreground presentation is attached',
    () async {
      final presentationReady = Completer<void>();
      final events = <String>[];
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitForegroundPresentationReadiness: () => presentationReady.future,
        awaitReadiness: () async => events.add('prerequisites'),
        buildGraph: () async {
          events.add('graph');
          return _Graph(events);
        },
      );

      final start = composition.start();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      presentationReady.complete();
      await start;
      expect(events, <String>[
        'prerequisites',
        'graph',
        'call_subscription',
        'advertise',
      ]);
    },
  );

  test('production environment flags remain false without build defines', () {
    expect(productionVoiceCallFeatureFlags(), defaultVoiceCallFeatureFlags());
  });

  test('failed initial capability write tears down the call graph', () async {
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async {
        events.add('coordinator_constructed');
        return _Graph(events, advertisementResults: const <bool>[false]);
      },
    );

    await composition.start();

    expect(composition.isStarted, isFalse);
    expect(events, <String>[
      'readiness',
      'coordinator_constructed',
      'call_subscription',
      'advertise',
      'call_shutdown',
    ]);
  });

  test(
    'capability is never advertised when listener installation fails',
    () async {
      final events = <String>[];
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async => events.add('readiness'),
        buildGraph: () async => _Graph(events, startResult: false),
      );

      await composition.start();

      expect(composition.isStarted, isFalse);
      expect(events, <String>[
        'readiness',
        'call_subscription',
        'call_shutdown',
      ]);
      expect(events, isNot(contains('advertise')));
    },
  );

  test('network action gate fails closed before invoking the action', () async {
    var actions = 0;

    for (final gate in <CallNetworkEffectsAllowed>[
      () => false,
      () => throw StateError('private gate detail'),
    ]) {
      await expectLater(
        runCallNetworkActionIfAllowed<void>(
          gate: gate,
          action: () async {
            actions++;
          },
        ),
        throwsA(isA<CallNetworkEffectsBlockedException>()),
      );
    }

    expect(actions, 0);
  });

  test('call shutdown completes before shared owners are disposed', () async {
    final events = <String>[];
    final releaseShutdown = Completer<void>();
    final disposal = shutdownCallSignalingBeforeSharedOwners(
      shutdownCallSignaling: () async {
        events.add('call_shutdown_started');
        await releaseShutdown.future;
        events.add('call_shutdown_completed');
      },
      disposeMessageRouter: () => events.add('router_disposed'),
      disposeP2PService: () => events.add('p2p_disposed'),
      disposeBridge: () => events.add('bridge_disposed'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['call_shutdown_started']);

    releaseShutdown.complete();
    await disposal;
    expect(events, <String>[
      'call_shutdown_started',
      'call_shutdown_completed',
      'router_disposed',
      'p2p_disposed',
      'bridge_disposed',
    ]);
  });

  test('contact reconciliation during a live call defers withdrawal', () async {
    final events = <String>[];
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));
    late _Graph graph;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async => graph = _Graph(
        events,
        advertisementResults: const <bool>[true, false],
      ),
    );
    await composition.start();
    expect(composition.isStarted, isTrue);
    graph.emitForeground(_projection(state: CallState.connected));

    await composition.onContactEligibilityChanged();

    expect(composition.isStarted, isTrue);
    expect(events, isNot(contains('call_shutdown')));
    expect(events.where((event) => event == 'advertise'), hasLength(2));
    final reconcile = flowEvents
        .where((event) => event['event'] == 'CALL_SIGNALING_RECONCILE_RESULT')
        .toList(growable: false);
    expect(reconcile, hasLength(1));
    expect(
      reconcile.single['details'],
      containsPair('outcome', 'advertisement_deferred'),
    );

    await composition.shutdown();
  });

  test('call wake drains the call mailbox on a started graph', () async {
    final events = <String>[];
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.ios,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async => _Graph(events),
    );
    await composition.start();
    expect(composition.isStarted, isTrue);
    events.clear();

    await composition.onCallWake();

    expect(events, <String>['call_mailbox_drain']);
    expect(composition.isStarted, isTrue);
    final wake = flowEvents
        .where((event) => event['event'] == 'CALL_SIGNALING_WAKE_RESULT')
        .toList(growable: false);
    expect(wake, hasLength(1));
    expect(wake.single['details'], containsPair('outcome', 'drained'));
    await composition.shutdown();
  });

  test('call wake starts the graph before draining', () async {
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.ios,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async => _Graph(events),
    );
    expect(composition.isStarted, isFalse);

    await composition.onCallWake();

    expect(composition.isStarted, isTrue);
    expect(
      events,
      containsAllInOrder(<String>[
        'readiness',
        'call_subscription',
        'advertise',
        'call_mailbox_drain',
      ]),
    );
    await composition.shutdown();
  });

  test('call wake is ignored while voice calling is disabled', () async {
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: const <String, bool>{},
      platform: CallEndpointPlatform.ios,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async => _Graph(events),
    );

    await composition.onCallWake();

    expect(events, isEmpty);
    expect(composition.isStarted, isFalse);
  });

  test('failed resume refresh withdraws the active call graph', () async {
    final events = <String>[];
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async => events.add('readiness'),
      buildGraph: () async =>
          _Graph(events, advertisementResults: const <bool>[true, false]),
    );
    await composition.start();
    expect(composition.isStarted, isTrue);

    await composition.onResume();

    expect(composition.isStarted, isFalse);
    expect(
      events,
      containsAllInOrder(<String>[
        'call_subscription',
        'advertise',
        'mailbox_resume',
        'advertise',
        'call_shutdown',
      ]),
    );
  });

  test(
    'production factory defers endpoint publication until P2P starts',
    () async {
      databaseFactory = databaseFactoryFfi;
      final database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE contacts('
          'peer_id TEXT PRIMARY KEY, username TEXT, is_blocked INTEGER)',
        ),
      );
      addTearDown(database.close);
      final bridge = _Bridge();
      final p2p = _P2P(state: const NodeState(peerId: '', isStarted: false));
      addTearDown(p2p.messages.close);
      final router = IncomingMessageRouter(p2pService: p2p)..start();
      addTearDown(router.dispose);
      final identity = IdentityModel(
        peerId: 'local-account',
        publicKey: 'local-public-key',
        privateKey: 'local-private-key',
        mnemonic12: 'unused fixture words',
        mlKemPublicKey: 'local-mlkem-public-key',
        mlKemSecretKey: 'local-mlkem-secret-key',
        createdAt: '2026-08-30T00:00:00.000Z',
        updatedAt: '2026-08-30T00:00:00.000Z',
      );
      final callWakeStores = _newCallWakeStores();
      final composition = createProductionCallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        database: database,
        bridge: bridge,
        p2pService: p2p,
        messageRouter: router,
        loadIdentity: () async => identity,
        networkEffectsAllowed: () => true,
        isVoiceNoteRecording: () => false,
        issuedCallWakeHandleStore: callWakeStores.issued,
        receivedCallWakeHandleStore: callWakeStores.received,
        androidCallLifecycleAdapterFactory:
            ({
              required coordinator,
              required resolveAuthenticatedHandle,
              required clock,
            }) => AndroidCallLifecycleAdapter(
              invokeMethod: (method, arguments) async {
                if (method == 'attach') {
                  return const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
                }
                return true;
              },
              nativeEvents: const Stream<Object?>.empty(),
              coordinator: coordinator,
              resolveAuthenticatedHandle: resolveAuthenticatedHandle,
              clock: clock,
            ),
        isForeground: () => true,
        nowMs: () => 2_000_000,
      );
      addTearDown(composition.shutdown);

      await composition.start();

      expect(composition.isStarted, isFalse);
      expect(bridge.commands, isEmpty);

      p2p.state = const NodeState(peerId: 'local-account', isStarted: true);
      await composition.onResume();

      expect(composition.isStarted, isTrue);
      expect(
        bridge.commands,
        containsAllInOrder(<String>[
          'call_retrieve_v1',
          'payload.sign',
          'call_endpoint_set_v1',
        ]),
      );
    },
  );

  test(
    'an Android graph publishes the FCM token as the relay standard call token',
    () async {
      // The relay wakes an Android callee only through this record; before
      // 2026-09-05 nothing published it and a locked Pixel could not be called.
      databaseFactory = databaseFactoryFfi;
      final database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE contacts('
          'peer_id TEXT PRIMARY KEY, username TEXT, is_blocked INTEGER)',
        ),
      );
      addTearDown(database.close);
      final bridge = _Bridge();
      final p2p = _P2P(state: const NodeState(peerId: '', isStarted: false));
      addTearDown(p2p.messages.close);
      final router = IncomingMessageRouter(p2pService: p2p)..start();
      addTearDown(router.dispose);
      final identity = IdentityModel(
        peerId: 'local-account',
        publicKey: 'local-public-key',
        privateKey: 'local-private-key',
        mnemonic12: 'unused fixture words',
        mlKemPublicKey: 'local-mlkem-public-key',
        mlKemSecretKey: 'local-mlkem-secret-key',
        createdAt: '2026-08-30T00:00:00.000Z',
        updatedAt: '2026-08-30T00:00:00.000Z',
      );
      final callWakeStores = _newCallWakeStores();
      final tokenOutcomes = <String>[];
      final composition = createProductionCallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        database: database,
        bridge: bridge,
        p2pService: p2p,
        messageRouter: router,
        loadIdentity: () async => identity,
        networkEffectsAllowed: () => true,
        isVoiceNoteRecording: () => false,
        issuedCallWakeHandleStore: callWakeStores.issued,
        receivedCallWakeHandleStore: callWakeStores.received,
        androidCallLifecycleAdapterFactory:
            ({
              required coordinator,
              required resolveAuthenticatedHandle,
              required clock,
            }) => AndroidCallLifecycleAdapter(
              invokeMethod: (method, arguments) async {
                if (method == 'attach') {
                  return const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
                }
                return true;
              },
              nativeEvents: const Stream<Object?>.empty(),
              coordinator: coordinator,
              resolveAuthenticatedHandle: resolveAuthenticatedHandle,
              clock: clock,
            ),
        androidCallTokenCoordinatorFactory:
            ({
              required authorityClient,
              required clock,
              required publicationAllowed,
            }) => AndroidCallTokenCoordinator(
              authorityClient: authorityClient,
              clock: clock,
              readToken: () async => 'fcm-token-fixture',
              tokenRefreshes: const Stream<String>.empty(),
              publicationAllowed: publicationAllowed,
              onResult: tokenOutcomes.add,
            ),
        isForeground: () => true,
        nowMs: () => 2_000_000,
      );

      await composition.start();
      expect(bridge.commands, isEmpty, reason: 'nothing before P2P starts');

      p2p.state = const NodeState(peerId: 'local-account', isStarted: true);
      await composition.onResume();

      expect(
        bridge.commands,
        containsAllInOrder(<String>[
          'call_token_set_v1',
          'call_retrieve_v1',
          'payload.sign',
          'call_endpoint_set_v1',
        ]),
      );
      expect(
        bridge.commands.where((command) => command == 'call_token_set_v1'),
        hasLength(1),
        reason: 'start publishes once; the advertisement finds it unchanged',
      );
      final publication = bridge.requests.singleWhere(
        (request) => request['cmd'] == 'call_token_set_v1',
      );
      expect(publication['payload'], <String, Object?>{
        'tokenKind': 'standard_call',
        'platform': 'android',
        'token': 'fcm-token-fixture',
        'expiresAtMs': 2_000_000 + const Duration(days: 30).inMilliseconds,
      });
      expect(tokenOutcomes.first, 'published');
      expect(
        tokenOutcomes.skip(1),
        everyElement('unchanged'),
        reason: 'every later advertisement finds the token already published',
      );

      await composition.shutdown();
      expect(
        bridge.commands,
        isNot(contains('call_token_revoke_v1')),
        reason: 'the relay must keep waking the app after it closes',
      );
    },
  );

  test(
    'production factory is reachable and disposes no shared router transport',
    () async {
      databaseFactory = databaseFactoryFfi;
      final database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE contacts('
          'peer_id TEXT PRIMARY KEY, username TEXT, is_blocked INTEGER)',
        ),
      );
      addTearDown(database.close);
      final bridge = _Bridge();
      final p2p = _P2P();
      addTearDown(p2p.messages.close);
      final router = IncomingMessageRouter(p2pService: p2p)..start();
      addTearDown(router.dispose);
      final identity = IdentityModel(
        peerId: 'local-account',
        publicKey: 'local-public-key',
        privateKey: 'local-private-key',
        mnemonic12: 'unused fixture words',
        mlKemPublicKey: 'local-mlkem-public-key',
        mlKemSecretKey: 'local-mlkem-secret-key',
        createdAt: '2026-08-30T00:00:00.000Z',
        updatedAt: '2026-08-30T00:00:00.000Z',
      );
      final nativeMethods = <String>[];
      final callWakeStores = _newCallWakeStores();
      final composition = createProductionCallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        database: database,
        bridge: bridge,
        p2pService: p2p,
        messageRouter: router,
        loadIdentity: () async => identity,
        networkEffectsAllowed: () => true,
        isVoiceNoteRecording: () => false,
        issuedCallWakeHandleStore: callWakeStores.issued,
        receivedCallWakeHandleStore: callWakeStores.received,
        androidCallLifecycleAdapterFactory:
            ({
              required coordinator,
              required resolveAuthenticatedHandle,
              required clock,
            }) => AndroidCallLifecycleAdapter(
              invokeMethod: (method, arguments) async {
                nativeMethods.add(method);
                if (method == 'attach') {
                  return const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
                }
                return true;
              },
              nativeEvents: const Stream<Object?>.empty(),
              coordinator: coordinator,
              resolveAuthenticatedHandle: resolveAuthenticatedHandle,
              clock: clock,
            ),
        isForeground: () => true,
        nowMs: () => 2_000_000,
      );

      expect(bridge.commands, isEmpty);
      await Future.wait(<Future<void>>[
        composition.start(),
        composition.start(),
      ]);
      expect(composition.isStarted, isTrue);
      expect(nativeMethods, <String>['setCapabilityEnabled', 'attach']);
      expect(bridge.commands, <String>[
        'call_retrieve_v1',
        'payload.sign',
        'call_endpoint_set_v1',
      ]);

      await composition.onResume();
      expect(bridge.commands, contains('call_retrieve_v1'));
      await Future.wait(<Future<void>>[
        composition.shutdown(),
        composition.shutdown(),
      ]);

      expect(bridge.commands.last, 'call_endpoint_revoke_v1');
      expect(nativeMethods, <String>[
        'setCapabilityEnabled',
        'attach',
        'detach',
      ]);
      expect(p2p.messages.hasListener, isTrue);
    },
  );

  test(
    'production iOS publishes VoIP token before endpoint and survives background',
    () async {
      databaseFactory = databaseFactoryFfi;
      final database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE contacts('
            'peer_id TEXT PRIMARY KEY, username TEXT, public_key TEXT, '
            'ml_kem_public_key TEXT, is_blocked INTEGER)',
          );
          await runDirectLinkedDeviceAddressingMigration(db);
          await db.insert('contacts', <String, Object?>{
            'peer_id': 'remote-account',
            'username': 'Alice',
            'public_key': 'remote-public-key',
            'ml_kem_public_key': 'remote-mlkem-public-key',
            'is_blocked': 0,
          });
          await runCallHistoryMigration(db);
        },
      );
      addTearDown(database.close);
      final bridge = _Bridge();
      final p2p = _P2P();
      addTearDown(p2p.messages.close);
      final router = IncomingMessageRouter(p2pService: p2p)..start();
      addTearDown(router.dispose);
      final identity = IdentityModel(
        peerId: 'local-account',
        publicKey: 'local-public-key',
        privateKey: 'local-private-key',
        mnemonic12: 'unused fixture words',
        mlKemPublicKey: 'local-mlkem-public-key',
        mlKemSecretKey: 'local-mlkem-secret-key',
        createdAt: '2026-08-30T00:00:00.000Z',
        updatedAt: '2026-08-30T00:00:00.000Z',
      );
      final lifecycleMethods = <String>[];
      final tokenMethods = <String>[];
      final tokenEvents = StreamController<Object?>.broadcast(sync: true);
      addTearDown(tokenEvents.close);
      ProductionCallSignalingGraph? productionGraph;
      final flags = <String, bool>{
        ..._enabledFlags(),
        'voice_call_android_native_enabled': false,
        'voice_call_ios_native_enabled': true,
      };
      final callWakeStores = _newCallWakeStores();
      final composition = createProductionCallSignalingComposition(
        featureFlags: flags,
        platform: CallEndpointPlatform.ios,
        database: database,
        bridge: bridge,
        p2pService: p2p,
        messageRouter: router,
        loadIdentity: () async => identity,
        networkEffectsAllowed: () => true,
        isVoiceNoteRecording: () => false,
        issuedCallWakeHandleStore: callWakeStores.issued,
        receivedCallWakeHandleStore: callWakeStores.received,
        iosCallLifecycleAdapterFactory:
            ({
              required coordinator,
              required resolveAuthenticatedHandle,
              required clock,
            }) => IosCallLifecycleAdapter(
              invokeMethod: (method, arguments) async {
                lifecycleMethods.add(method);
                if (method == 'attach') {
                  return const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
                }
                return true;
              },
              nativeEvents: const Stream<Object?>.empty(),
              coordinator: coordinator,
              resolveAuthenticatedHandle: resolveAuthenticatedHandle,
              clock: clock,
            ),
        iosVoipTokenCoordinatorFactory:
            ({
              required authorityClient,
              required clock,
              required publicationAllowed,
            }) => IosVoipTokenCoordinator(
              invokeMethod: (method, arguments) async {
                tokenMethods.add(method);
                return <String, Object?>{
                  'version': 1,
                  'token': List<String>.filled(64, 'a').join(),
                  'environment': 'development',
                  'topic': 'com.mknoon.app.voip',
                  'capabilityVersion': 1,
                  'refreshEpoch': 9,
                  'invalidated': false,
                };
              },
              nativeEvents: tokenEvents.stream,
              authorityClient: authorityClient,
              clock: clock,
              publicationAllowed: publicationAllowed,
            ),
        onGraphBuilt: (graph) => productionGraph = graph,
        isForeground: () => true,
        nowMs: () => 2_000_000,
      );

      await composition.start();

      expect(composition.isStarted, isTrue);
      expect(lifecycleMethods, <String>[
        'setCapabilityEnabled',
        'attach',
        'publishOpaqueContact',
      ]);
      expect(tokenMethods, <String>['readCurrent']);
      final tokenSet = bridge.commands.indexOf('call_token_set_v1');
      final wakeSet = bridge.commands.indexOf('call_wake_handle_set_v1');
      final endpointSet = bridge.commands.indexOf('call_endpoint_set_v1');
      expect(tokenSet, greaterThanOrEqualTo(0));
      expect(wakeSet, greaterThan(tokenSet));
      expect(endpointSet, greaterThan(wakeSet));
      final tokenPayload = bridge.requests.firstWhere(
        (request) => request['cmd'] == 'call_token_set_v1',
      )['payload']!;
      expect(tokenPayload, containsPair('tokenKind', 'ios_voip'));
      expect(tokenPayload, containsPair('environment', 'sandbox'));

      final graph = productionGraph!;
      final activeAt = DateTime.fromMillisecondsSinceEpoch(
        2_000_000,
        isUtc: true,
      );
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteInvite,
          eventId: 'ios-background-remote-invite',
          occurredAt: activeAt,
          callId: _callA,
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-account',
          remoteAccountPeerId: 'remote-account',
          remoteDeviceId: 'remote-device',
          expiresAt: activeAt.add(const Duration(seconds: 45)),
          transportRoute: CallRouteClass.direct,
        ),
      );
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.incomingValidated,
          eventId: 'ios-background-incoming-validated',
          occurredAt: activeAt,
          callId: _callA,
          contactPeerId: 'remote-account',
        ),
      );
      expect(graph.coordinator.activeSession?.callId, _callA);

      await composition.onBackgrounded();
      expect(composition.isStarted, isTrue);
      expect(bridge.commands, isNot(contains('call_endpoint_revoke_v1')));
      expect(graph.coordinator.activeSession?.callId, _callA);
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);
      expect(
        graph.coordinator.activeSession?.recentEventIds.any(
          (eventId) => eventId.startsWith('background-shutdown-'),
        ),
        isFalse,
      );

      await composition.onResume();
      expect(
        bridge.commands.where((command) => command == 'call_token_set_v1'),
        hasLength(2),
      );

      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteTerminate,
          eventId: 'ios-background-terminal',
          occurredAt: activeAt.add(const Duration(seconds: 1)),
          callId: _callA,
          contactPeerId: 'remote-account',
        ),
      );
      expect(graph.coordinator.activeSession, isNull);

      await composition.shutdown();
      expect(
        lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
      expect(
        lifecycleMethods.where((method) => method == 'setCapabilityEnabled'),
        hasLength(2),
      );
      final tokenRevokes = bridge.requests
          .where((request) => request['cmd'] == 'call_token_revoke_v1')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList();
      expect(tokenRevokes, <Map<String, Object?>>[
        <String, Object?>{'tokenKind': 'ios_voip', 'expectedRefreshEpoch': 9},
      ]);
      expect(
        tokenRevokes.any((payload) => payload['tokenKind'] == 'standard_call'),
        isFalse,
      );
    },
  );

  test(
    'production iOS token success plus endpoint failure rolls back before detach',
    () async {
      final fixture = await _createProductionIosFixture(
        endpointSetResponse: const <String, Object?>{'ok': false},
      );

      await fixture.composition.start();
      await _untilComposition(
        () => fixture.lifecycleMethods.contains('detach'),
      );

      expect(fixture.composition.isStarted, isFalse);
      // Plan 400 B: the idle advertisement failure withdraws the endpoint
      // first (transient rollback keeps the VoIP token); graph close then
      // revokes the token, still before the native channel detaches.
      expect(
        fixture.bridge.commands,
        containsAllInOrder(<String>[
          'call_token_set_v1',
          'call_endpoint_set_v1',
          'call_endpoint_revoke_v1',
          'call_token_revoke_v1',
        ]),
      );
      expect(
        fixture.lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
      expect(fixture.capabilityArguments, <Map<String, Object?>>[
        <String, Object?>{'version': 1, 'enabled': true},
        <String, Object?>{'version': 1, 'enabled': false},
      ]);
      final revoke = fixture.bridge.requests.firstWhere(
        (request) => request['cmd'] == 'call_token_revoke_v1',
      )['payload'];
      expect(revoke, <String, Object?>{
        'tokenKind': 'ios_voip',
        'expectedRefreshEpoch': 41,
      });
    },
  );

  test(
    'production iOS token publication failure disables native callability',
    () async {
      final fixture = await _createProductionIosFixture(
        tokenSetResponse: const <String, Object?>{'ok': false},
      );

      await fixture.composition.start();
      await _untilComposition(
        () => fixture.lifecycleMethods.contains('detach'),
      );

      expect(fixture.composition.isStarted, isFalse);
      expect(fixture.bridge.commands, contains('call_token_set_v1'));
      // Plan 400 B: the relay refused this epoch, so nothing is revoked (a
      // CAS revoke would poison the refresh-epoch high-water).
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.bridge.commands, isNot(contains('call_endpoint_set_v1')));
      expect(
        fixture.lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
    },
  );

  test(
    'production iOS malformed lifecycle attach publishes no call authority',
    () async {
      final fixture = await _createProductionIosFixture(
        attachResponse: <String, Object?>{
          'version': 1,
          'descriptor': null,
          'events': <Object?>[],
          'nativeCallId': null,
          'highestSequence': 0,
          'unexpected': true,
        },
      );

      await fixture.composition.start();
      await _untilComposition(
        () => fixture.lifecycleMethods.contains('detach'),
      );

      expect(fixture.composition.isStarted, isFalse);
      expect(fixture.bridge.commands, isNot(contains('call_token_set_v1')));
      expect(fixture.bridge.commands, isNot(contains('call_endpoint_set_v1')));
      expect(
        fixture.lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'failClosed',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
    },
  );

  test(
    'production token invalidation withdraws outgoing before ordered teardown',
    () async {
      final releaseFailClosed = Completer<void>();
      final fixture = await _createProductionIosFixture(
        failClosedGate: releaseFailClosed.future,
      );
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);

      fixture.tokenEvents.add(<String, Object?>{
        'version': 1,
        'token': '',
        'environment': 'development',
        'topic': 'com.mknoon.app.voip',
        'capabilityVersion': 1,
        'refreshEpoch': 41,
        'invalidated': true,
      });
      await _untilComposition(
        () => fixture.lifecycleMethods.contains('failClosed'),
      );

      expect(fixture.composition.isStarted, isFalse);
      expect(fixture.composition.isOutgoingCallAvailable, isFalse);
      expect(fixture.lifecycleMethods, isNot(contains('detach')));

      releaseFailClosed.complete();
      await _untilComposition(
        () => fixture.lifecycleMethods.contains('detach'),
      );

      expect(
        fixture.lifecycleMethods.lastIndexOf('setCapabilityEnabled'),
        lessThan(fixture.lifecycleMethods.indexOf('failClosed')),
      );
      expect(
        fixture.lifecycleMethods.indexOf('failClosed'),
        lessThan(fixture.lifecycleMethods.indexOf('detach')),
      );
      final tokenRevokes = fixture.bridge.requests
          .where((request) => request['cmd'] == 'call_token_revoke_v1')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList();
      expect(tokenRevokes, <Map<String, Object?>>[
        <String, Object?>{'tokenKind': 'ios_voip', 'expectedRefreshEpoch': 41},
      ]);
      expect(
        tokenRevokes.any((payload) => payload['tokenKind'] == 'standard_call'),
        isFalse,
      );
      expect(fixture.bridge.commands, contains('call_endpoint_revoke_v1'));
      expect(
        fixture.lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
    },
  );

  test(
    'production shutdown during endpoint wait cannot enqueue outgoing call',
    () async {
      const contactAccountPeerId = 'remote-account';
      const nowMs = 2_000_000;
      final fixture = await _createProductionIosFixture(
        outgoingContactAccountPeerId: contactAccountPeerId,
      );
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      final roster = await graph.trustedRosterProvider.loadForContact(
        contactAccountPeerId,
      );
      final trustedDevice = roster.devices.single;
      final grant = CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: trustedDevice.devicePeerId,
        deviceKeyEpoch: trustedDevice.deviceKeyEpoch,
        generation: 1,
        issuedAtMs: nowMs - 1_000,
        expiresAtMs: nowMs + 30_000,
      );
      expect(
        await fixture.receivedCallWakeHandleStore.storeIfStrictlyNewer(
          issuerAccountPeerId: contactAccountPeerId,
          grant: grant,
          nowMs: nowMs,
        ),
        isTrue,
      );

      final endpoint = CallEndpointRecord(
        accountPeerId: contactAccountPeerId,
        devicePeerId: trustedDevice.devicePeerId,
        capabilities: const <String>{'voice_call_v1'},
        platform: CallEndpointPlatform.android,
        expiresAtMs: nowMs + 60_000,
        preferenceEpoch: 1,
        deviceKeyEpoch: trustedDevice.deviceKeyEpoch,
        routingHandle: '0123456789abcdef0123456789abcdef',
      );
      final endpointResponse = <String, Object?>{
        'ok': true,
        'found': true,
        'canonicalRecord': base64Encode(
          utf8.encode(endpoint.canonicalRecordJson),
        ),
        'endpoint': <String, Object?>{
          ...endpoint.toCanonicalMap(),
          'signature': 'c2lnbmF0dXJl',
        },
      };
      fixture.bridge.responses['payload.verify'] = const <String, Object?>{
        'ok': true,
        'valid': true,
      };
      final endpointRequested = Completer<void>();
      final releaseEndpoint = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) async {
        if (!endpointRequested.isCompleted) endpointRequested.complete();
        return releaseEndpoint.future;
      };

      final outgoing = graph.prepareOutgoingCall(contactAccountPeerId);
      await endpointRequested.future;

      // Keep runtime shutdown ahead of coordinator disposal so this proves the
      // graph guard, rather than relying on the coordinator's later guard.
      final mailboxRequested = Completer<void>();
      final releaseMailbox = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['call_retrieve_v1'] = (_) async {
        if (!mailboxRequested.isCompleted) mailboxRequested.complete();
        return releaseMailbox.future;
      };
      final resume = graph.onResume();
      await mailboxRequested.future;
      final shutdown = graph.shutdown();

      releaseEndpoint.complete(endpointResponse);
      try {
        await expectLater(
          outgoing,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'call signaling graph is shutting down',
            ),
          ),
        );
        expect(graph.coordinator.activeSession, isNull);
        expect(graph.coordinator.lastSnapshot, isNull);
      } finally {
        if (!releaseMailbox.isCompleted) {
          releaseMailbox.complete(const <String, Object?>{
            'ok': true,
            'events': <Object?>[],
            'receiptAtMs': 1,
            'expiresAtMs': 1,
            'hasMore': false,
          });
        }
        await resume;
        await shutdown;
      }
    },
  );

  test(
    'production revalidates current wake authority after endpoint wait before invite',
    () async {
      const contactAccountPeerId = 'remote-account';
      const nowMs = 2_000_000;
      final fixture = await _createProductionIosFixture(
        outgoingContactAccountPeerId: contactAccountPeerId,
      );
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      final roster = await graph.trustedRosterProvider.loadForContact(
        contactAccountPeerId,
      );
      final trustedDevice = roster.devices.single;
      final receivedGrant = CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: trustedDevice.devicePeerId,
        deviceKeyEpoch: trustedDevice.deviceKeyEpoch,
        generation: 1,
        issuedAtMs: nowMs - 1_000,
        expiresAtMs: nowMs + 30_000,
      );
      expect(
        await fixture.receivedCallWakeHandleStore.storeIfStrictlyNewer(
          issuerAccountPeerId: contactAccountPeerId,
          grant: receivedGrant,
          nowMs: nowMs,
        ),
        isTrue,
      );
      final issued = CallIssuedWakeHandleRecord(
        contactAccountPeerId: contactAccountPeerId,
        grant: CallWakeHandleGrant(
          handle: '0123456789abcdef0123456789abcdef',
          recipientDevicePeerId: graph.localIdentity.peerId,
          deviceKeyEpoch: graph.localDeviceKeyEpoch,
          generation: 1,
          issuedAtMs: nowMs - 1_000,
          expiresAtMs: nowMs + 30_000,
        ),
        authorizedSenderDevicePeerIds: <String>{trustedDevice.devicePeerId},
        distributionPending: false,
        distributionReceiptVersion:
            CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );
      await fixture.issuedCallWakeHandleStore.write(issued);

      final endpoint = CallEndpointRecord(
        accountPeerId: contactAccountPeerId,
        devicePeerId: trustedDevice.devicePeerId,
        capabilities: const <String>{'voice_call_v1'},
        platform: CallEndpointPlatform.android,
        expiresAtMs: nowMs + 60_000,
        preferenceEpoch: 1,
        deviceKeyEpoch: trustedDevice.deviceKeyEpoch,
        routingHandle: '0123456789abcdef0123456789abcdef',
      );
      final endpointResponse = <String, Object?>{
        'ok': true,
        'found': true,
        'canonicalRecord': base64Encode(
          utf8.encode(endpoint.canonicalRecordJson),
        ),
        'endpoint': <String, Object?>{
          ...endpoint.toCanonicalMap(),
          'signature': 'c2lnbmF0dXJl',
        },
      };
      fixture.bridge.responses['payload.verify'] = const <String, Object?>{
        'ok': true,
        'valid': true,
      };
      final endpointRequested = Completer<void>();
      final releaseEndpoint = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) async {
        if (!endpointRequested.isCompleted) endpointRequested.complete();
        return releaseEndpoint.future;
      };

      final outgoing = graph.startOutgoingCall(contactAccountPeerId);
      await endpointRequested.future;
      await fixture.issuedCallWakeHandleStore.write(
        issued.copyWith(distributionPending: true),
      );
      releaseEndpoint.complete(endpointResponse);

      expect(await outgoing, OutgoingCallStartResult.unavailable);
      expect(graph.coordinator.activeSession, isNull);
      expect(graph.coordinator.lastSnapshot, isNull);
    },
  );

  test(
    'native disable false or throw cannot skip the other rollback legs',
    () async {
      final failures = <String, Future<Object?> Function()>{
        'false': () async => false,
        'throw': () async => throw StateError('native details stay private'),
      };
      for (final failure in failures.entries) {
        final fixture = await _createProductionIosFixture(
          disableCapability: failure.value,
        );
        await fixture.composition.start();
        expect(fixture.composition.isStarted, isTrue, reason: failure.key);

        await fixture.composition.shutdown();

        expect(
          fixture.lifecycleMethods,
          containsAllInOrder(<String>[
            'setCapabilityEnabled',
            'attach',
            'setCapabilityEnabled',
            'failClosed',
            'detach',
          ]),
          reason: failure.key,
        );
        expect(
          fixture.bridge.commands,
          containsAllInOrder(<String>[
            'call_token_revoke_v1',
            'call_endpoint_revoke_v1',
          ]),
          reason: failure.key,
        );
      }
    },
  );

  test(
    'production gate-false shutdown still revokes exact iOS authorities',
    () async {
      var networkAllowed = true;
      final fixture = await _createProductionIosFixture(
        networkEffectsAllowed: () => networkAllowed,
      );
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);

      networkAllowed = false;
      await fixture.composition.shutdown();

      final tokenRevokes = fixture.bridge.requests
          .where((request) => request['cmd'] == 'call_token_revoke_v1')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList();
      expect(tokenRevokes, <Map<String, Object?>>[
        <String, Object?>{'tokenKind': 'ios_voip', 'expectedRefreshEpoch': 41},
      ]);
      expect(
        tokenRevokes.any((payload) => payload['tokenKind'] == 'standard_call'),
        isFalse,
      );
      expect(fixture.bridge.commands, contains('call_endpoint_revoke_v1'));
      expect(
        fixture.lifecycleMethods,
        containsAllInOrder(<String>[
          'setCapabilityEnabled',
          'attach',
          'setCapabilityEnabled',
          'failClosed',
          'detach',
        ]),
      );
    },
  );

  test(
    'production speaker-off selects an advertised non-speaker route',
    () async {
      final fixture = await _createProductionSpeakerRouteFixture();
      addTearDown(fixture.graph.shutdown);

      expect(fixture.graph.current?.audio.active, isTrue);
      expect(
        fixture.graph.current?.audio.selectedRoute,
        CallAudioOutputRoute.speaker,
      );
      expect(
        fixture.graph.current?.audio.supportedRoutes,
        <CallAudioOutputRoute>[
          CallAudioOutputRoute.earpiece,
          CallAudioOutputRoute.speaker,
        ],
      );

      final result = await fixture.graph.setSpeakerEnabled(_callA, false);

      expect(
        (
          result: result,
          route: fixture.controller.state.selectedRoute,
          failure: fixture.controller.state.failure,
        ),
        (
          result: ForegroundCallActionResult.applied,
          route: CallAudioOutputRoute.earpiece,
          failure: CallAudioFailure.none,
        ),
      );
      expect(fixture.engine.routeRequests, <CallAudioOutputRoute>[
        CallAudioOutputRoute.speaker,
        CallAudioOutputRoute.earpiece,
      ]);
    },
  );

  test(
    'production speaker routing preserves supported and unavailable cases',
    () async {
      final cases =
          <
            ({
              String name,
              List<CallAudioOutputRoute> supportedRoutes,
              CallAudioOutputRoute initialRoute,
              bool enabled,
              ForegroundCallActionResult result,
              CallAudioOutputRoute route,
              CallAudioFailure failure,
            })
          >[
            (
              name: 'speaker on',
              supportedRoutes: const <CallAudioOutputRoute>[
                CallAudioOutputRoute.earpiece,
                CallAudioOutputRoute.speaker,
              ],
              initialRoute: CallAudioOutputRoute.earpiece,
              enabled: true,
              result: ForegroundCallActionResult.applied,
              route: CallAudioOutputRoute.speaker,
              failure: CallAudioFailure.none,
            ),
            (
              name: 'advertised system default',
              supportedRoutes: const <CallAudioOutputRoute>[
                CallAudioOutputRoute.systemDefault,
                CallAudioOutputRoute.earpiece,
                CallAudioOutputRoute.speaker,
              ],
              initialRoute: CallAudioOutputRoute.speaker,
              enabled: false,
              result: ForegroundCallActionResult.applied,
              route: CallAudioOutputRoute.systemDefault,
              failure: CallAudioFailure.none,
            ),
            (
              name: 'advertised external route',
              supportedRoutes: const <CallAudioOutputRoute>[
                CallAudioOutputRoute.bluetooth,
                CallAudioOutputRoute.speaker,
              ],
              initialRoute: CallAudioOutputRoute.speaker,
              enabled: false,
              result: ForegroundCallActionResult.applied,
              route: CallAudioOutputRoute.bluetooth,
              failure: CallAudioFailure.none,
            ),
            (
              name: 'no non-speaker route',
              supportedRoutes: const <CallAudioOutputRoute>[
                CallAudioOutputRoute.speaker,
              ],
              initialRoute: CallAudioOutputRoute.speaker,
              enabled: false,
              result: ForegroundCallActionResult.unavailable,
              route: CallAudioOutputRoute.speaker,
              failure: CallAudioFailure.none,
            ),
          ];

      for (final scenario in cases) {
        final fixture = await _createProductionSpeakerRouteFixture(
          supportedRoutes: scenario.supportedRoutes,
          initialRoute: scenario.initialRoute,
        );
        try {
          final result = await fixture.graph.setSpeakerEnabled(
            _callA,
            scenario.enabled,
          );

          expect(
            (
              result: result,
              route: fixture.controller.state.selectedRoute,
              failure: fixture.controller.state.failure,
            ),
            (
              result: scenario.result,
              route: scenario.route,
              failure: scenario.failure,
            ),
            reason: scenario.name,
          );
        } finally {
          await fixture.graph.shutdown();
        }
      }
    },
  );

  test('production graph wires one coordinator to real call-only effects', () {
    final source = File(
      'lib/app/bootstrap/production_call_signaling_graph.dart',
    ).readAsStringSync();

    for (final required in const <String>[
      'CallScopedMediaBundleOwner(',
      'CallControlEffectExecutor(',
      'CallNegotiationEffectExecutor(',
      'CompositeCallEffectExecutor(',
      'effectExecutor: boundEffects',
      'signalingContextObserver: signalingContextStore',
      'negotiationMaterialStore: negotiationMaterialStore',
      "CallCleanupStep('call_media'",
      "CallCleanupStep('call_signaling_context'",
      'await controlExecutor.retireOutgoingPreconnectInvite(snapshot)',
      'cancelOutgoingMailboxInvite:',
      'mailbox.cancel(',
    ]) {
      expect(source, contains(required), reason: required);
    }
    final mailboxRetirement = source.indexOf(
      'await controlExecutor.retireOutgoingPreconnectInvite(snapshot)',
    );
    final signalingContextPurge = source.indexOf(
      'signalingContextStore.purge(snapshot.callId!)',
      mailboxRetirement,
    );
    expect(mailboxRetirement, greaterThanOrEqualTo(0));
    expect(signalingContextPurge, greaterThan(mailboxRetirement));
    expect(
      source,
      contains('terminalEffectTimeout: const Duration(milliseconds: 500)'),
    );
    expect(
      source,
      contains('terminalHistoryTimeout: const Duration(milliseconds: 250)'),
    );
    expect(source, contains('FlutterWebRtcPeerConnectionAdapter('));
    expect(source, contains('CallForegroundAudioSessionAdapter.create()'));
    expect(source, contains('CallMicrophonePermissionAdapter('));
    expect(source, contains('requestOutgoingMicrophonePermission:'));
    expect(source, contains('resolvedMicrophonePermission.request'));
    expect(
      source,
      contains('microphonePermission: resolvedMicrophonePermission'),
    );
    expect(source, contains('CallMediaConflictAdapter('));
    expect(
      source,
      contains(
        'Future<CallConnectionSnapshot?> readActiveConnectionSnapshot()',
      ),
      reason: 'the E2E observer needs one exact-active-call read-only seam',
    );
    expect(source, contains('_activeConnectionSnapshotCallId'));
    expect(source, contains('bundle.engine.snapshot'));
    expect(source, contains("event: 'CALL_AUDIO_START_RESULT'"));
    expect(source, contains("'status': status.name"));
    expect(source, contains('onAppliedStateTransition:'));
    expect(source, contains("event: 'CALL_STATE_TRANSITION'"));
    expect(source, contains("'trigger': trigger.name"));
    expect(source, contains("'state': resultingState.name"));
    expect(source, contains("'endReason': endReason?.name ?? 'none'"));
    expect(
      source,
      contains("event: 'CALL_NATIVE_OUTGOING_REGISTRATION_RESULT'"),
    );
    expect(source, contains('onOutgoingRegistrationResult:'));
    expect(source, contains("'stage': stage.name"));
    expect(source, contains("'status': status.name"));
    expect(source, contains("'reason': reason.name"));
    final registrationDiagnosticStart = source.indexOf(
      "event: 'CALL_NATIVE_OUTGOING_REGISTRATION_RESULT'",
    );
    final registrationDiagnosticEnd = source.indexOf(
      '  } catch (_)',
      registrationDiagnosticStart,
    );
    expect(registrationDiagnosticStart, greaterThanOrEqualTo(0));
    expect(registrationDiagnosticEnd, greaterThan(registrationDiagnosticStart));
    final registrationDiagnostic = source.substring(
      registrationDiagnosticStart,
      registrationDiagnosticEnd,
    );
    for (final forbidden in const <String>[
      "'callId':",
      "'callHandle':",
      "'peerId':",
      "'endpoint':",
      "'payload':",
    ]) {
      expect(registrationDiagnostic, isNot(contains(forbidden)));
    }
    expect(source, contains("event: 'CALL_TERMINAL_CLEANUP_RESULT'"));
    final cleanupDiagnosticStart = source.indexOf(
      "event: 'CALL_TERMINAL_CLEANUP_RESULT'",
    );
    final cleanupDiagnosticEnd = source.indexOf(
      '  } catch (_)',
      cleanupDiagnosticStart,
    );
    expect(cleanupDiagnosticStart, greaterThanOrEqualTo(0));
    expect(cleanupDiagnosticEnd, greaterThan(cleanupDiagnosticStart));
    final cleanupDiagnostic = source.substring(
      cleanupDiagnosticStart,
      cleanupDiagnosticEnd,
    );
    expect(cleanupDiagnostic, contains("'status': status.name"));
    expect(cleanupDiagnostic, contains("'reason': reason.name"));
    for (final forbidden in const <String>[
      "'callId':",
      "'callHandle':",
      "'peerId':",
      "'endpoint':",
      "'payload':",
      'failedStepNames',
    ]) {
      expect(cleanupDiagnostic, isNot(contains(forbidden)));
    }
    expect(source, contains("event: 'CALL_AUDIO_ENGINE_START_FAILURE_STAGE'"));
    expect(source, contains("event: 'CALL_WEBRTC_FAILURE_STAGE'"));
    expect(source, contains("'stage': stage.name"));
    expect(source, contains('BridgeCallIceServerProvider('));
    expect(source, contains('ProductionCallControlSignalingAdapter('));
    expect(source, contains('ProductionCallNegotiationSignalingAdapter('));
    expect(source, contains('type: CallEventType.appShutdown'));
    expect(source, contains('mediaOwner.bundleChanges.listen('));
    expect(
      source,
      contains(
        'Future<void> onResume() async {\n'
        '    await runtime.onResume();\n'
        '    final active = coordinator.activeSession;\n'
        '    if (active != null) _onSessionSnapshot(active);\n'
        '  }',
      ),
    );
    expect(source, contains('nativeLifecycleAdapter?.bindNativeMuteApplier('));
    expect(source, contains('await audioController.setMuted(muted);'));
    expect(source, contains('state.failure != CallAudioFailure.none'));
    expect(source, contains('state.muted != muted'));
    expect(
      source,
      isNot(contains('notifyNativeMuteTargetReady(bundle.callId)')),
    );
    expect(
      source,
      contains(
        'if (status == CallAudioStartStatus.started) {\n'
        '                nativeLifecycleAdapter?.notifyNativeMuteTargetReady(callId);\n'
        '              }',
      ),
    );
    expect(
      source,
      contains(
        'audioController.state.failure == CallAudioFailure.cleanupFailed',
      ),
    );
    expect(source, contains('audioController.state.active'));
  });

  test(
    'production native lifecycles remain platform-scoped and default-off',
    () {
      final graph = File(
        'lib/app/bootstrap/production_call_signaling_graph.dart',
      ).readAsStringSync();
      final flags = File(
        'lib/features/call/application/voice_call_feature_flags.dart',
      ).readAsStringSync();

      expect(
        graph,
        contains(
          'endpointPlatform == CallEndpointPlatform.android &&\n'
          "          featureFlags['voice_call_android_native_enabled'] == true",
        ),
      );
      expect(graph, contains('incomingCallPresenter == null &&'));
      expect(graph, contains('AndroidCallLifecycleAdapter.methodChannelName'));
      expect(graph, contains('AndroidCallLifecycleAdapter.eventChannelName'));
      expect(
        graph,
        contains(
          'endpointPlatform == CallEndpointPlatform.ios &&\n'
          "          featureFlags['voice_call_ios_native_enabled'] == true",
        ),
      );
      expect(graph, contains('IosCallLifecycleAdapter.methodChannelName'));
      expect(graph, contains('IosCallLifecycleAdapter.eventChannelName'));
      expect(graph, contains('IosVoipTokenCoordinator.methodChannelName'));
      expect(graph, contains('IosVoipTokenCoordinator.eventChannelName'));
      expect(
        graph.indexOf('publishForAuthenticatedGraph()'),
        lessThan(graph.indexOf('authorityClient.signEndpoint(')),
      );
      final nativeBackgroundGuard = graph.indexOf(
        'if (_nativeCallLifecycleAdapter != null)',
      );
      final foregroundShutdown = graph.indexOf(
        "eventId: 'background-shutdown-",
        nativeBackgroundGuard,
      );
      expect(nativeBackgroundGuard, greaterThanOrEqualTo(0));
      expect(foregroundShutdown, greaterThan(nativeBackgroundGuard));
      expect(
        graph.substring(nativeBackgroundGuard, foregroundShutdown),
        contains('return;\n    }'),
      );
      expect(flags, contains("'voice_call_android_native_enabled': false"));
      expect(flags, contains("'voice_call_ios_native_enabled': false"));
    },
  );

  test(
    'production registers native outgoing ownership before invite and audio',
    () {
      final source = File(
        'lib/app/bootstrap/production_call_signaling_graph.dart',
      ).readAsStringSync();
      final executorSource = File(
        'lib/features/call/application/call_control_effect_executor.dart',
      ).readAsStringSync();
      final outgoingPreparation = source.indexOf(
        'Future<PreparedOutgoingCall> prepareOutgoingCall(',
      );
      final endpointResolution = source.indexOf(
        'final endpoint = await _resolveEndpoint(contactAccountPeerId);',
        outgoingPreparation,
      );
      final retainedTerminalReconciliation = source.indexOf(
        'await _nativeCallLifecycleAdapter?.reconcileBeforeOutgoing()',
        endpointResolution,
      );
      final coordinatorPlacement = source.indexOf(
        'final reduction = await coordinator.placeCall(',
        retainedTerminalReconciliation,
      );
      final controlExecutor = source.indexOf(
        'controlExecutor = CallControlEffectExecutor(',
      );
      final preInviteGate = source.indexOf(
        'registerOutgoingBeforeInvite:',
        controlExecutor,
      );
      final outgoingRegistration = source.indexOf(
        'return nativeLifecycleAdapter.registerOutgoing(',
        preInviteGate,
      );
      final negotiationExecutor = source.indexOf(
        'final negotiationAdapter =',
        outgoingRegistration,
      );
      final bundleFactory = source.indexOf('createBundle: (callId) async {');
      final nativeBinding = source.indexOf(
        'nativeLifecycleAdapter.isBoundTo(callId)',
        bundleFactory,
      );
      final nativeRouteOwnership = source.indexOf(
        'final CallAudioRoutePort routeAdapter',
        bundleFactory,
      );
      final audioController = source.indexOf(
        'final audioController = CallAudioController(',
        bundleFactory,
      );
      final contextStored = executorSource.indexOf(
        'contextStore.storeOutgoing(',
      );
      final registrationAwaited = executorSource.indexOf(
        'await _registerOutgoingBeforeInvite(callId)',
        contextStored,
      );
      final inviteReady = executorSource.indexOf(
        'CallEventType.outgoingInviteReady',
        registrationAwaited,
      );

      expect(outgoingPreparation, greaterThanOrEqualTo(0));
      expect(endpointResolution, greaterThan(outgoingPreparation));
      expect(retainedTerminalReconciliation, greaterThan(endpointResolution));
      expect(coordinatorPlacement, greaterThan(retainedTerminalReconciliation));
      expect(controlExecutor, greaterThanOrEqualTo(0));
      expect(preInviteGate, greaterThan(controlExecutor));
      expect(outgoingRegistration, greaterThan(preInviteGate));
      expect(negotiationExecutor, greaterThan(outgoingRegistration));
      expect(bundleFactory, greaterThanOrEqualTo(0));
      expect(nativeBinding, greaterThan(bundleFactory));
      expect(nativeRouteOwnership, greaterThan(nativeBinding));
      expect(audioController, greaterThan(nativeRouteOwnership));
      expect(
        source.substring(bundleFactory, audioController),
        contains('nativeLifecycleAdapter.isBoundTo(callId)'),
      );
      expect(
        source.substring(bundleFactory, audioController),
        isNot(contains('registerOutgoing(')),
      );
      expect(contextStored, greaterThanOrEqualTo(0));
      expect(registrationAwaited, greaterThan(contextStored));
      expect(inviteReady, greaterThan(registrationAwaited));
    },
  );

  test('production bootstrap orders call lifecycle around shared owners', () {
    final bootstrap = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final routerStart = bootstrap.indexOf("'message_router_start'");
    final callStart = bootstrap.indexOf("'call_signaling_runtime_start'");
    final contactStart = bootstrap.indexOf("'contact_request_listener_start'");
    final factory = bootstrap.indexOf(
      'createProductionCallSignalingComposition(',
    );
    final nativeRollback = bootstrap.indexOf(
      'await enforceAndroidCallCapabilityRollback(',
    );
    final iosNativeRollback = bootstrap.indexOf(
      'await enforceIosCallCapabilityRollback(',
    );
    final detachShutdown = bootstrap.indexOf(
      'await callSignalingComposition.shutdown();',
    );
    final sharedStop = bootstrap.indexOf(
      'await p2pService.stopNode()',
      detachShutdown,
    );

    expect(factory, greaterThanOrEqualTo(0));
    expect(nativeRollback, greaterThanOrEqualTo(0));
    expect(nativeRollback, lessThan(factory));
    expect(iosNativeRollback, greaterThan(nativeRollback));
    expect(iosNativeRollback, lessThan(factory));
    expect(
      bootstrap.substring(nativeRollback, factory),
      contains('capabilityEnabled: isAndroidNativeCallCapabilityAuthorized('),
    );
    expect(
      bootstrap.substring(iosNativeRollback, factory),
      contains('capabilityEnabled: isIosNativeCallCapabilityAuthorized('),
    );
    expect(callStart, -1);
    expect(routerStart, lessThan(contactStart));
    expect(detachShutdown, greaterThanOrEqualTo(0));
    expect(detachShutdown, lessThan(sharedStop));

    final applicationRoot = File(
      'lib/app/application_root.dart',
    ).readAsStringSync();
    expect(
      applicationRoot,
      contains('afterP2PNodeStarted: widget.resumeCallSignaling'),
      reason:
          'call signaling must start from the successful primary node-start '
          'branch, not from the pre-node live-service phase',
    );
    final startupRouter = File(
      'lib/features/identity/presentation/startup_router.dart',
    ).readAsStringSync();
    final nodeSuccess = startupRouter.indexOf(
      'if (result == StartNodeResult.success)',
    );
    final linkedSecondarySkip = startupRouter.indexOf(
      'if (linkedAuthority?.isActiveLinkedSecondary == true)',
      nodeSuccess,
    );
    final postNodeCallStart = startupRouter.indexOf(
      'final afterP2PNodeStarted = widget.afterP2PNodeStarted;',
      nodeSuccess,
    );
    expect(nodeSuccess, greaterThanOrEqualTo(0));
    expect(linkedSecondarySkip, greaterThan(nodeSuccess));
    expect(postNodeCallStart, greaterThan(linkedSecondarySkip));
    expect(
      applicationRoot,
      contains('shutdownCallSignalingBeforeSharedOwners('),
    );
    expect(applicationRoot, contains('ForegroundCallOverlay('));
    expect(applicationRoot, contains('unawaited(pauseCallSignaling())'));
    expect(
      bootstrap,
      contains('foregroundCallCapability: callSignalingComposition'),
    );
    expect(
      bootstrap,
      contains('pauseCallSignaling: callSignalingComposition.onBackgrounded'),
    );
    expect(bootstrap, contains('foregroundCallPresentationReady.future'));
    expect(bootstrap, contains('onForegroundCallPresentationReady:'));
  });
}

final class _ProductionIosFixture {
  const _ProductionIosFixture({
    required this.composition,
    required this.bridge,
    required this.lifecycleMethods,
    required this.capabilityArguments,
    required this.tokenEvents,
    required this.graphs,
    required this.issuedCallWakeHandleStore,
    required this.receivedCallWakeHandleStore,
  });

  final CallSignalingComposition composition;
  final _Bridge bridge;
  final List<String> lifecycleMethods;
  final List<Map<String, Object?>> capabilityArguments;
  final StreamController<Object?> tokenEvents;
  final List<ProductionCallSignalingGraph> graphs;
  final IssuedCallWakeHandleStoreImpl issuedCallWakeHandleStore;
  final ReceivedCallWakeHandleStoreImpl receivedCallWakeHandleStore;
}

Future<_ProductionIosFixture> _createProductionIosFixture({
  Map<String, Object?>? endpointSetResponse,
  Map<String, Object?>? tokenSetResponse,
  Object? attachResponse,
  Future<void>? failClosedGate,
  Future<Object?> Function()? disableCapability,
  CallNetworkEffectsAllowed? networkEffectsAllowed,
  String? outgoingContactAccountPeerId,
  CallMicrophonePermission? microphonePermission,
  String? nativeHandleOverride,
  Future<Object?> Function(String, Map<String, Object?>)? lifecycleOverride,
}) async {
  databaseFactory = databaseFactoryFfi;
  final database = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      if (outgoingContactAccountPeerId == null) {
        await db.execute(
          'CREATE TABLE contacts('
          'peer_id TEXT PRIMARY KEY, username TEXT, is_blocked INTEGER)',
        );
        return;
      }
      await db.execute(
        'CREATE TABLE contacts('
        'peer_id TEXT PRIMARY KEY, username TEXT, public_key TEXT, '
        'ml_kem_public_key TEXT, is_blocked INTEGER)',
      );
      await runDirectLinkedDeviceAddressingMigration(db);
      await runCallHistoryMigration(db);
      await db.insert('contacts', <String, Object?>{
        'peer_id': outgoingContactAccountPeerId,
        'username': 'Remote contact',
        'public_key': 'remote-public-key',
        'ml_kem_public_key': 'remote-mlkem-public-key',
        'is_blocked': 0,
      });
    },
  );
  final bridge = _Bridge();
  if (endpointSetResponse != null) {
    bridge.responses['call_endpoint_set_v1'] = endpointSetResponse;
  }
  if (tokenSetResponse != null) {
    bridge.responses['call_token_set_v1'] = tokenSetResponse;
  }
  final p2p = _P2P();
  final router = IncomingMessageRouter(p2pService: p2p)..start();
  final lifecycleMethods = <String>[];
  final capabilityArguments = <Map<String, Object?>>[];
  final tokenEvents = StreamController<Object?>.broadcast(sync: true);
  final graphs = <ProductionCallSignalingGraph>[];
  final identity = IdentityModel(
    peerId: 'local-account',
    publicKey: 'local-public-key',
    privateKey: 'local-private-key',
    mnemonic12: 'unused fixture words',
    mlKemPublicKey: 'local-mlkem-public-key',
    mlKemSecretKey: 'local-mlkem-secret-key',
    createdAt: '2026-08-30T00:00:00.000Z',
    updatedAt: '2026-08-30T00:00:00.000Z',
  );
  final callWakeStores = _newCallWakeStores();
  final composition = createProductionCallSignalingComposition(
    featureFlags: <String, bool>{
      ..._enabledFlags(),
      'voice_call_android_native_enabled': false,
      'voice_call_ios_native_enabled': true,
    },
    platform: CallEndpointPlatform.ios,
    database: database,
    bridge: bridge,
    p2pService: p2p,
    messageRouter: router,
    loadIdentity: () async => identity,
    networkEffectsAllowed: networkEffectsAllowed ?? () => true,
    isVoiceNoteRecording: () => false,
    microphonePermission: microphonePermission,
    issuedCallWakeHandleStore: callWakeStores.issued,
    receivedCallWakeHandleStore: callWakeStores.received,
    iosCallLifecycleAdapterFactory:
        ({
          required coordinator,
          required resolveAuthenticatedHandle,
          required clock,
        }) => IosCallLifecycleAdapter(
          invokeMethod: (method, arguments) async {
            lifecycleMethods.add(method);
            if (lifecycleOverride != null) {
              final overridden = await lifecycleOverride(method, arguments);
              if (overridden != null) return overridden;
            }
            if (method == 'setCapabilityEnabled') {
              capabilityArguments.add(Map<String, Object?>.of(arguments));
            }
            if (method == 'attach') {
              return attachResponse ??
                  const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
            }
            if (method == 'failClosed' && failClosedGate != null) {
              await failClosedGate;
            }
            if (method == 'setCapabilityEnabled' &&
                arguments['enabled'] == false &&
                disableCapability != null) {
              return disableCapability();
            }
            return true;
          },
          nativeEvents: const Stream<Object?>.empty(),
          coordinator: coordinator,
          resolveAuthenticatedHandle: nativeHandleOverride == null
              ? resolveAuthenticatedHandle
              : (callId) => callId == _callA ? nativeHandleOverride : null,
          clock: clock,
        ),
    iosVoipTokenCoordinatorFactory:
        ({
          required authorityClient,
          required clock,
          required publicationAllowed,
        }) => IosVoipTokenCoordinator(
          invokeMethod: (method, arguments) async => <String, Object?>{
            'version': 1,
            'token': List<String>.filled(64, 'c').join(),
            'environment': 'development',
            'topic': 'com.mknoon.app.voip',
            'capabilityVersion': 1,
            'refreshEpoch': 41,
            'invalidated': false,
          },
          nativeEvents: tokenEvents.stream,
          authorityClient: authorityClient,
          clock: clock,
          publicationAllowed: publicationAllowed,
        ),
    isForeground: () => true,
    nowMs: () => 2_000_000,
    onGraphBuilt: graphs.add,
  );
  addTearDown(() async {
    await composition.shutdown();
    router.dispose();
    await p2p.messages.close();
    await tokenEvents.close();
    await database.close();
  });
  return _ProductionIosFixture(
    composition: composition,
    bridge: bridge,
    lifecycleMethods: lifecycleMethods,
    capabilityArguments: capabilityArguments,
    tokenEvents: tokenEvents,
    graphs: graphs,
    issuedCallWakeHandleStore: callWakeStores.issued,
    receivedCallWakeHandleStore: callWakeStores.received,
  );
}

({
  IssuedCallWakeHandleStoreImpl issued,
  ReceivedCallWakeHandleStoreImpl received,
})
_newCallWakeStores() {
  final secureKeyStore = FakeSecureKeyStore();
  return (
    issued: IssuedCallWakeHandleStoreImpl(secureKeyStore: secureKeyStore),
    received: ReceivedCallWakeHandleStoreImpl(secureKeyStore: secureKeyStore),
  );
}

Future<void> _untilComposition(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

final class _ProductionSpeakerRouteFixture {
  const _ProductionSpeakerRouteFixture({
    required this.graph,
    required this.controller,
    required this.engine,
  });

  final ProductionCallSignalingGraph graph;
  final CallAudioController controller;
  final _ProductionSpeakerRouteEngine engine;
}

Future<_ProductionSpeakerRouteFixture> _createProductionSpeakerRouteFixture({
  List<CallAudioOutputRoute> supportedRoutes = const <CallAudioOutputRoute>[
    CallAudioOutputRoute.earpiece,
    CallAudioOutputRoute.speaker,
  ],
  CallAudioOutputRoute initialRoute = CallAudioOutputRoute.speaker,
  NativeCallLifecycleAdapter Function(CallCoordinator)? nativeLifecycleFactory,
}) async {
  const nowMs = 2_000_000;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  final engine = _ProductionSpeakerRouteEngine(supportedRoutes);
  final controller = CallAudioController(
    engine: engine,
    microphonePermission: const _GrantedCallMicrophonePermission(),
    mediaConflicts: const _AvailableCallMediaConflicts(),
    audioSession: const _ActiveCallAudioSession(),
  );
  final start = await controller.start(
    locallyAccepted: true,
    configuration: const CallConnectionConfiguration(
      transportPolicy: CallTransportPolicy.relayOnly,
      receiveAudio: true,
      receiveVideo: false,
      captureAudio: true,
      captureVideo: false,
    ),
  );
  expect(start.status, CallAudioStartStatus.started);
  final initial = await controller.selectOutputRoute(initialRoute);
  expect(initial.failure, CallAudioFailure.none);

  final mediaOwner = CallScopedMediaBundleOwner(
    createBundle: (callId) => CallScopedMediaBundle(
      callId: callId,
      engine: engine,
      audioController: controller,
      negotiationExecutor: const NoopCallEffectExecutor(),
      close: controller.close,
    ),
  );
  final coordinator = CallCoordinator(
    reducer: const CallReducer(),
    cleanupCoordinator: CallCleanupCoordinator([
      CallCleanupStep(
        'call_media',
        (snapshot) => mediaOwner.closeCall(snapshot.callId!),
      ),
    ]),
    historyProjector: CallHistoryProjector(_UnusedCallHistoryRepository()),
    clock: () => now,
    idSource: () => _callA,
  );
  final mailbox = _UnusedCallMailboxClient();
  final nativeLifecycle = nativeLifecycleFactory?.call(coordinator);
  final callWakeStores = _newCallWakeStores();
  final codec = SecureCallEnvelopeCodec(
    crypto: _UnusedCallEnvelopeCrypto(),
    nowMs: () => nowMs,
  );
  final graph = ProductionCallSignalingGraph(
    runtime: CallSignalingRuntime(
      directCallSignalStream: const Stream<ChatMessage>.empty(),
      mailboxClient: mailbox,
      handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    ),
    coordinator: coordinator,
    signalingService: CallSignalingService(
      codec: codec,
      directTransport: _UnusedCallDirectTransport(),
      mailboxClient: mailbox,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    ),
    endpointResolver: CallEndpointResolver(
      nowMs: () => nowMs,
      verifyEndpointSignature: (_, _) async => true,
    ),
    trustedRosterProvider: _UnusedCallTrustedRosterProvider(),
    authorityClient: _UnusedCallAuthorityClient(),
    wakeAuthorizationCoordinator: CallWakeAuthorizationCoordinator(
      store: callWakeStores.issued,
      setWakeHandle: (_) async => true,
      revokeWakeHandle: ({required authorizedSenderPeerId}) async => true,
      publishNativeContact:
          ({required wakeHandle, required displayName}) async {},
      revokeNativeContact: (_) async {},
      generateHandle: () => '0123456789abcdef0123456789abcdef',
      nowMs: () => nowMs,
    ),
    issuedCallWakeHandleStore: callWakeStores.issued,
    receivedCallWakeHandleStore: callWakeStores.received,
    loadWakeEligibleContacts: () async => const <CallWakeEligibleContact>[],
    localDeviceKeyEpoch: 7,
    localIdentity: IdentityModel(
      peerId: 'local-account',
      publicKey: 'local-public-key',
      privateKey: 'local-private-key',
      mnemonic12: 'unused fixture words',
      mlKemPublicKey: 'local-mlkem-public-key',
      mlKemSecretKey: 'local-mlkem-secret-key',
      createdAt: '2026-08-30T00:00:00.000Z',
      updatedAt: '2026-08-30T00:00:00.000Z',
    ),
    platform: nativeLifecycle is IosCallLifecycleAdapter
        ? CallEndpointPlatform.ios
        : CallEndpointPlatform.android,
    androidCallLifecycleAdapter: nativeLifecycle is AndroidCallLifecycleAdapter
        ? nativeLifecycle
        : null,
    iosCallLifecycleAdapter: nativeLifecycle is IosCallLifecycleAdapter
        ? nativeLifecycle
        : null,
    mediaOwner: mediaOwner,
    networkEffectsAllowed: () => true,
    nowMs: () => nowMs,
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'speaker-route-remote-invite',
      occurredAt: now,
      callId: _callA,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-account',
      remoteAccountPeerId: 'remote-account',
      remoteDeviceId: 'remote-device',
      expiresAt: now.add(const Duration(seconds: 45)),
      transportRoute: CallRouteClass.direct,
    ),
  );
  await mediaOwner.execute(
    const CallEffect(CallEffectType.deliverOffer),
    coordinator.activeSession!,
  );
  return _ProductionSpeakerRouteFixture(
    graph: graph,
    controller: controller,
    engine: engine,
  );
}

final class _ProductionSpeakerRouteEngine implements CallEngine {
  _ProductionSpeakerRouteEngine(List<CallAudioOutputRoute> supportedRoutes)
    : supportedRoutes = List<CallAudioOutputRoute>.unmodifiable(
        supportedRoutes,
      );

  final List<CallAudioOutputRoute> supportedRoutes;
  CallAudioOutputRoute outputRoute = CallAudioOutputRoute.systemDefault;
  bool audioSessionActive = false;
  bool localAudioEnabled = false;
  bool closed = false;
  CallConnectionConfiguration? configuration;
  final List<CallAudioOutputRoute> routeRequests = <CallAudioOutputRoute>[];

  @override
  Stream<CallEngineEvent> get events => const Stream<CallEngineEvent>.empty();

  @override
  Stream<CallIceCandidate> get localCandidates =>
      const Stream<CallIceCandidate>.empty();

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => closed;

  @override
  int get candidateBatchCapacity => 8;

  @override
  int get iceGeneration => 0;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {
    this.configuration = configuration;
    localAudioEnabled = configuration.captureAudio;
  }

  @override
  Future<void> setAudioSessionActive(bool active) async {
    audioSessionActive = active;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    localAudioEnabled = enabled;
  }

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      supportedRoutes;

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {
    routeRequests.add(route);
    outputRoute = route;
  }

  @override
  Future<CallConnectionSnapshot> snapshot() async => CallConnectionSnapshot(
    state: CallConnectionState.connected,
    transportPolicy:
        configuration?.transportPolicy ?? CallTransportPolicy.relayOnly,
    transport: CallTransportClass.turnUdp,
    quality: CallQualityBand.good,
    localAudioCaptureTrackCount: 1,
    localVideoCaptureTrackCount: 0,
    audioReceiveTransceiverCount: 1,
    videoTransceiverCount: 0,
    audioSessionActive: audioSessionActive,
    localAudioSenderAttached: true,
    localAudioTrackLive: true,
    remoteAudioReceiverAttached: true,
    remoteAudioTrackLive: true,
    localAudioEnabled: localAudioEnabled,
    outputRoute: outputRoute,
  );

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GrantedCallMicrophonePermission
    implements CallMicrophonePermission {
  const _GrantedCallMicrophonePermission();

  @override
  Future<MicPermissionStatus> request() async => MicPermissionStatus.granted;
}

final class _AvailableCallMediaConflicts implements CallMediaConflictPort {
  const _AvailableCallMediaConflicts();

  @override
  Future<CallMediaConflictLease> acquireForCall() async =>
      const _AvailableCallMediaConflictLease();
}

final class _AvailableCallMediaConflictLease implements CallMediaConflictLease {
  const _AvailableCallMediaConflictLease();

  @override
  Future<void> release() async {}
}

final class _ActiveCallAudioSession implements CallForegroundAudioSession {
  const _ActiveCallAudioSession();

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      const Stream<CallAudioSessionInterruption>.empty();

  @override
  bool get ownsSession => true;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}
}

final class _UnusedCallHistoryRepository implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _UnusedCallMailboxClient implements CallMailboxClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallDirectTransport implements CallDirectTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallEnvelopeCrypto implements CallEnvelopeCrypto {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallTrustedRosterProvider
    implements CallTrustedRosterProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallAuthorityClient implements CallAuthorityClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
