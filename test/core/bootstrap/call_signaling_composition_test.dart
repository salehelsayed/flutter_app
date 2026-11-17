import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/call_picture_in_picture.dart';

import '../../features/call/support/fake_call_picture_in_picture_bridge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_wake_channel.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/application/call_privacy_preference_use_cases.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/app/bootstrap/call_wake_contact_key_backfill.dart';
import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/app/bootstrap/production_headless_call_admission.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/application/missed_call_notifier.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/network_path_source.dart';
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
import 'package:flutter_app/features/call/application/locked_call_presentation.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/data/call_history_conversation_timeline_source.dart';
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_environment.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_policy.dart';
import 'package:flutter_app/features/call/infrastructure/platform_call_video_quality_environment_source.dart';
import 'package:flutter_app/features/call/application/call_video_presentation.dart';
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
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
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
    this.onStart,
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
  final FutureOr<void> Function(_Graph graph)? onShutdown;
  final Future<void> Function()? onStart;
  final bool throwOnForegroundChanges;
  final bool throwOnStart;
  final bool throwOnAdvertise;
  Future<bool> Function()? onAdvertise;
  Future<void> Function()? onMailboxDrain;
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
    await onMailboxDrain?.call();
  }

  @override
  Future<void> onBackgrounded() async {
    backgroundCalls++;
    events.add('call_backgrounded');
  }

  @override
  Future<void> shutdown() async {
    events.add('call_shutdown');
    await onShutdown?.call(this);
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId, {
    OutgoingCallStartRequest? request,
  }) async {
    outgoingPeerIds.add(contactAccountPeerId);
    return outgoingResult;
  }

  @override
  Future<bool> start() async {
    events.add('call_subscription');
    await onStart?.call();
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
      // SE-42 D27: this build's Go broker grants call-media protection, so
      // the media owner opens media. A bare refusal here would keep every
      // call in its pending state until the media-preparation budget ends.
      'call_media:protection' => _protectionAnswer(
        request['payload']! as Map<String, dynamic>,
      ),
      _ => const <String, Object?>{'ok': false},
    });
  }

  static Map<String, Object?> _protectionAnswer(Map<String, dynamic> payload) =>
      payload['held'] == true
      ? <String, Object?>{
          'ok': true,
          'held': true,
          'generation': payload['generation'],
          'incarnation': 1,
        }
      : const <String, Object?>{'ok': true, 'held': false, 'released': true};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _P2P implements P2PService {
  _P2P({NodeState? state})
    : state =
          state ?? const NodeState(peerId: 'local-account', isStarted: true);

  NodeState state;
  final List<String> sentMessages = [];
  bool acceptMessages = false;
  final StreamController<ChatMessage> messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<NodeState> states =
      StreamController<NodeState>.broadcast();

  void updateState(NodeState next) {
    state = next;
    states.add(next);
  }

  @override
  NodeState get currentState => state;

  @override
  Stream<ChatMessage> get messageStream => messages.stream;

  @override
  Stream<NodeState> get stateStream => states.stream;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sentMessages.add(message);
    return SendMessageResult(sent: acceptMessages, acked: acceptMessages);
  }

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

// Stream cancellation can return a future created outside the binding's fake
// clock. Let those real-zone microtasks retire before advancing the next timer.
Future<void> _pumpCallLifecycle(
  WidgetTester tester, [
  Duration elapsed = Duration.zero,
]) async {
  await tester.pump(elapsed);
  for (var turn = 0; turn < 8; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

final class _StalledCallCheckpointStore extends FakeSecureKeyStore {
  _StalledCallCheckpointStore(this.operation);

  final String operation;
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> _hold(String current) async {
    if (operation != current || entered.isCompleted) return;
    entered.complete();
    await release.future;
  }

  @override
  Future<String?> read(String key) async {
    await _hold('read');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _hold('write');
    await super.write(key, value);
  }
}

final class _CapturedFirstCallCheckpointStore extends FakeSecureKeyStore {
  final written = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == 'vc2_active_call_history_v1' && !written.isCompleted) {
      written.complete();
      await release.future;
    }
  }
}

void main() {
  _b7ActivityTests();
  _vui7TerminalMediaTests();
  _vui7LegacyAndBridgeTests();
  _vui7JoinedBridgeTests();
  Future<void> flushPip() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> turnCameraOn(_ProductionIosFixture fixture) async {
    final graph = fixture.graphs.single;
    expect(
      await graph.applyVideoIntent(
        _callA,
        generation: graph.current!.video!.generation,
        intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
      ),
      ForegroundCallActionResult.applied,
    );
  }

  test('PiP graph gate OFF never constructs the bridge', () async {
    var factories = 0;
    final fixture = await _createProductionIosFixture(
      pictureInPictureBridgeFactory: () {
        factories++;
        return FakeCallPictureInPictureBridge();
      },
    );
    await fixture.composition.start();
    await fixture.composition.onBackgrounded();
    expect(factories, 0);
  });

  test(
    'PiP graph OS-paused user camera resumes without a permission prompt',
    () async {
      final pip = FakeCallPictureInPictureBridge();
      var prompts = 0;
      var reads = 0;
      final (fixture, engine) = await _connectedGraphVideo(
        pictureInPictureBridgeFactory: () => pip,
        permission: () async {
          prompts++;
          return true;
        },
        checkCameraPermission: () async {
          reads++;
          return true;
        },
      );
      engine.video!.replaceRemoteTrack();
      await turnCameraOn(fixture);
      await flushPip();
      expect(pip.arms, hasLength(1));
      await fixture.composition.onBackgrounded();
      await flushPip();
      expect(pip.enters, hasLength(1));
      expect(engine.video!.cameraOn, isFalse);
      expect(
        fixture.graphs.single.coordinator.activeSession!.isTerminal,
        isFalse,
      );
      await fixture.composition.onResume();
      await flushPip();
      expect(engine.video!.cameraOn, isTrue);
      expect(engine.video!.cameraStarts, 2);
      expect(prompts, 1);
      expect(reads, greaterThan(0));
    },
  );

  test(
    'PiP graph supported continuation keeps existing camera authority',
    () async {
      final pip = FakeCallPictureInPictureBridge()..cameraInPip = true;
      final (fixture, engine) = await _connectedGraphVideo(
        pictureInPictureBridgeFactory: () => pip,
        checkCameraPermission: () async => true,
      );
      engine.video!.replaceRemoteTrack();
      await turnCameraOn(fixture);
      await flushPip();
      expect(pip.arms, hasLength(1));
      await fixture.composition.onBackgrounded();
      await flushPip();
      expect(engine.video!.cameraOn, isTrue);
      expect(engine.video!.lastCameraGrant!.isCurrent(), isTrue);
      await fixture.composition.onResume();
      expect(engine.video!.cameraStarts, 1);
    },
  );

  for (final fallback in [
    'unsupported',
    'no-source',
    'preparing',
    'entry-rejected',
    'failed',
    'blocked',
  ]) {
    test(
      'PiP fallback $fallback never restores ordinary background camera',
      () async {
        final pip = FakeCallPictureInPictureBridge();
        if (fallback == 'unsupported') pip.supported = false;
        if (fallback == 'preparing') pip.pendingArm = Completer<bool>();
        if (fallback == 'entry-rejected') pip.enterResult = false;
        final (fixture, engine) = await _connectedGraphVideo(
          pictureInPictureBridgeFactory: () => pip,
          checkCameraPermission: () async => true,
        );
        if (fallback != 'no-source') engine.video!.replaceRemoteTrack();
        await turnCameraOn(fixture);
        await flushPip();
        expect(engine.video!.cameraOn, isTrue);
        await fixture.composition.onBackgrounded();
        await flushPip();
        if (fallback == 'failed' || fallback == 'blocked') {
          expect(pip.arms, hasLength(1));
          final id = pip.arms.single;
          pip.emit(id, 1, CallPipEventType.entered);
          pip.emit(
            id,
            2,
            fallback == 'failed'
                ? CallPipEventType.failed
                : CallPipEventType.blocked,
            fallback == 'failed' ? 'trackLost' : 'locked',
          );
        }
        await fixture.composition.onResume();
        await flushPip();
        expect(engine.video!.cameraOn, isFalse);
        expect(engine.video!.cameraStarts, 1);
        expect(
          fixture.graphs.single.coordinator.activeSession!.isTerminal,
          isFalse,
        );
        if (fallback == 'preparing') {
          pip.pendingArm!.complete(true);
          await flushPip();
          expect(engine.video!.cameraOn, isFalse);
        }
      },
    );
  }

  test('PiP graph permission loss keeps an OS-paused camera off', () async {
    final pip = FakeCallPictureInPictureBridge();
    var granted = true;
    var prompts = 0;
    final (fixture, engine) = await _connectedGraphVideo(
      pictureInPictureBridgeFactory: () => pip,
      permission: () async {
        prompts++;
        return true;
      },
      checkCameraPermission: () async => granted,
    );
    engine.video!.replaceRemoteTrack();
    await turnCameraOn(fixture);
    await flushPip();
    expect(pip.arms, hasLength(1));
    await fixture.composition.onBackgrounded();
    granted = false;
    await fixture.composition.onResume();
    await flushPip();
    expect(engine.video!.cameraOn, isFalse);
    expect(engine.video!.cameraStarts, 1);
    expect(prompts, 1);
  });

  test('PiP graph explicit off fences a late automatic resume', () async {
    final pip = FakeCallPictureInPictureBridge();
    final permission = Completer<bool>();
    final (fixture, engine) = await _connectedGraphVideo(
      pictureInPictureBridgeFactory: () => pip,
      checkCameraPermission: () => permission.future,
    );
    engine.video!.replaceRemoteTrack();
    await turnCameraOn(fixture);
    await flushPip();
    expect(pip.arms, hasLength(1));
    await fixture.composition.onBackgrounded();
    final resume = fixture.composition.onResume();
    await flushPip();
    final graph = fixture.graphs.single;
    expect(
      await graph.applyVideoIntent(
        _callA,
        generation: graph.current!.video!.generation,
        intent: const CallVideoIntent(CallVideoAction.turnCameraOff),
      ),
      ForegroundCallActionResult.applied,
    );
    permission.complete(true);
    await resume;
    await flushPip();
    expect(engine.video!.cameraOn, isFalse);
    expect(engine.video!.cameraStarts, 1);
  });

  test('PiP graph critical thermal state prevents OS-pause resume', () async {
    final pip = FakeCallPictureInPictureBridge();
    final quality = _GraphQualitySource(initial: _graphCellularQuality);
    final (fixture, engine) = await _connectedGraphVideo(
      pictureInPictureBridgeFactory: () => pip,
      qualityEnvironmentSourceFactory: () => quality,
      checkCameraPermission: () async => true,
    );
    engine.video!.replaceRemoteTrack();
    await turnCameraOn(fixture);
    await flushPip();
    expect(pip.arms, hasLength(1));
    await fixture.composition.onBackgrounded();
    quality.emit(_graphCriticalQuality);
    await fixture.composition.onResume();
    await flushPip();
    expect(engine.video!.cameraOn, isFalse);
    expect(engine.video!.cameraStarts, 1);
  });

  test('PiP graph enter and restore never supply camera consent', () async {
    final pip = FakeCallPictureInPictureBridge()..cameraInPip = true;
    var prompts = 0;
    final (fixture, engine) = await _connectedGraphVideo(
      pictureInPictureBridgeFactory: () => pip,
      permission: () async {
        prompts++;
        return true;
      },
      checkCameraPermission: () async => true,
    );
    engine.video!.replaceRemoteTrack();
    await flushPip();
    expect(pip.arms, hasLength(1));
    final id = pip.arms.single;
    await fixture.composition.onBackgrounded();
    pip.emit(id, 1, CallPipEventType.entered);
    pip.emit(id, 2, CallPipEventType.exited, 'restored');
    await fixture.composition.onResume();
    await flushPip();
    expect(engine.video!.cameraStarts, 0);
    expect(prompts, 0);
  });

  test(
    'PiP graph close keeps audio call; explicit End terminates it',
    () async {
      final pip = FakeCallPictureInPictureBridge();
      final (fixture, engine) = await _connectedGraphVideo(
        pictureInPictureBridgeFactory: () => pip,
        checkCameraPermission: () async => true,
      );
      engine.video!.replaceRemoteTrack();
      await flushPip();
      expect(pip.arms, hasLength(1));
      final first = pip.arms.single;
      await fixture.composition.onBackgrounded();
      pip.emit(first, 1, CallPipEventType.entered);
      pip.emit(first, 2, CallPipEventType.exited, 'closed');
      await flushPip();
      expect(
        fixture.graphs.single.coordinator.activeSession!.isTerminal,
        isFalse,
      );
      await fixture.composition.onResume();
      await flushPip();
      expect(pip.arms, hasLength(2));
      final current = pip.arms.last;
      await fixture.composition.onBackgrounded();
      pip.emit(current, 1, CallPipEventType.entered);
      pip.emit(current, 2, CallPipEventType.action, 'end');
      await flushPip();
      expect(
        fixture.graphs.single.coordinator.activeSession?.isTerminal ?? true,
        isTrue,
      );
      expect(pip.disarms, contains(current));
    },
  );

  for (final supported in [false, true]) {
    test(
      'PiP graph explicit camera tap requires background capability=$supported',
      () async {
        final pip = FakeCallPictureInPictureBridge()..cameraInPip = supported;
        var prompts = 0;
        final (fixture, engine) = await _connectedGraphVideo(
          pictureInPictureBridgeFactory: () => pip,
          permission: () async {
            prompts++;
            return true;
          },
          checkCameraPermission: () async => true,
        );
        engine.video!.replaceRemoteTrack();
        await flushPip();
        expect(pip.arms, hasLength(1));
        await fixture.composition.onBackgrounded();
        final id = pip.arms.single;
        pip.emit(id, 1, CallPipEventType.entered);
        expect(engine.video!.cameraStarts, 0);
        pip.emit(id, 2, CallPipEventType.action, 'camera');
        await flushPip();
        expect(engine.video!.cameraOn, supported);
        expect(engine.video!.cameraStarts, supported ? 1 : 0);
        expect(prompts, 0);
      },
    );
  }

  for (final enabled in [false, true]) {
    test(
      'U3j-GQ default platform source follows video gate=$enabled',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel(
          PlatformCallVideoQualityEnvironmentSource.eventChannelName,
        );
        final methods = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final fixture = await _createProductionIosFixture(
          privacyFlags: {'video_call_v2_enabled': enabled},
          usePlatformQualityEnvironment: true,
        );
        await fixture.composition.start();
        if (enabled) await _untilComposition(() => methods.contains('listen'));
        expect(methods.where((m) => m == 'listen'), hasLength(enabled ? 1 : 0));
        expect(fixture.composition.isOutgoingCallAvailable, isTrue);
        expect(fixture.graphs.single.coordinator.activeSession, isNull);
        await fixture.composition.shutdown();
        expect(methods.where((m) => m == 'cancel'), hasLength(enabled ? 1 : 0));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  test('U3j-GQ gate off does not construct the optional source', () async {
    var factories = 0;
    final fixture = await _createProductionIosFixture(
      qualityEnvironmentSourceFactory: () {
        factories++;
        throw StateError('disabled source must not be constructed');
      },
    );
    await fixture.composition.start();
    expect(fixture.composition.isOutgoingCallAvailable, isTrue);
    await fixture.composition.shutdown();
    expect(factories, 0);
  });

  test(
    'U3j-GQ pending observation start cannot block audio readiness or close',
    () async {
      final gate = Completer<void>();
      final source = _GraphQualitySource(startGate: gate);
      final fixture = await _createProductionIosFixture(
        privacyFlags: const {'video_call_v2_enabled': true},
        qualityEnvironmentSourceFactory: () => source,
      );
      await fixture.composition.start().timeout(const Duration(seconds: 2));
      expect(source.starts, 1);
      expect(gate.isCompleted, isFalse);
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);
      await fixture.composition.shutdown().timeout(const Duration(seconds: 2));
      expect(source.closes, 1);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(source.listens, 1);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'U3j-GQ observation failure stays unknown and leaves audio ready',
    () async {
      final source = _GraphQualitySource(failStart: true);
      final fixture = await _createProductionIosFixture(
        privacyFlags: const {'video_call_v2_enabled': true},
        qualityEnvironmentSourceFactory: () => source,
      );
      await fixture.composition.start();
      await _untilComposition(() => source.starts == 1);
      expect(source.starts, 1);
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);
      await fixture.composition.shutdown();
      expect(source.closes, 1);
    },
  );

  test(
    'U3j-GQ current input reaches the canonical session without camera consent',
    () async {
      final source = _GraphQualitySource(initial: _graphCellularQuality);
      var permissions = 0;
      final (fixture, engine) = await _connectedGraphVideo(
        qualityEnvironmentSourceFactory: () => source,
        permission: () async {
          permissions++;
          return true;
        },
      );
      final video = engine.video!;
      expect(video.qualityEnvironments.lastOrNull, same(_graphCellularQuality));
      source.emit(_graphCriticalQuality);
      await _untilComposition(
        () => identical(
          video.qualityEnvironments.lastOrNull,
          _graphCriticalQuality,
        ),
      );
      expect(video.qualityEnvironments.last, same(_graphCriticalQuality));
      expect(video.cameraStarts, 0);
      expect(permissions, 0);
      expect(engine.binds, 1);
      expect(engine.candidateSubscriptions, 1);
      expect(fixture.lifecycleMethods, isNot(contains('setLocalCameraActive')));
      expect(source.starts, 1);
      expect(source.listens, 1);
    },
  );

  test(
    'U3j-GQ source errors become unknown for the same current session',
    () async {
      final source = _GraphQualitySource(initial: _graphCriticalQuality);
      final (_, engine) = await _connectedGraphVideo(
        qualityEnvironmentSourceFactory: () => source,
      );
      expect(
        engine.video!.qualityEnvironments.lastOrNull,
        same(_graphCriticalQuality),
      );
      source.emitError();
      await _untilComposition(
        () => identical(
          engine.video!.qualityEnvironments.lastOrNull,
          CallVideoQualityEnvironment.unknown,
        ),
      );
      expect(
        engine.video!.qualityEnvironments.last,
        same(CallVideoQualityEnvironment.unknown),
      );
      expect(engine.video!.cameraStarts, 0);
    },
  );

  for (final platform in [
    CallEndpointPlatform.ios,
    CallEndpointPlatform.android,
  ]) {
    test(
      'U3j-GQ environment delivery preserves explicit camera authority on $platform',
      () async {
        final source = _GraphQualitySource(initial: _graphCellularQuality);
        var permissions = 0;
        final (fixture, engine) = await _connectedGraphVideo(
          platform: platform,
          qualityEnvironmentSourceFactory: () => source,
          permission: () async {
            permissions++;
            return true;
          },
        );
        final graph = fixture.graphs.single;
        expect(
          engine.video!.qualityEnvironments.lastOrNull,
          same(_graphCellularQuality),
        );
        final capability =
            (fixture.composition as Object) as ForegroundCallVideoCapability;
        expect(
          await capability.applyVideoIntent(
            _callA,
            generation: graph.current!.video!.generation,
            intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
          ),
          ForegroundCallActionResult.applied,
        );
        expect(
          engine.video!.environmentAtCameraStart,
          same(_graphCellularQuality),
        );
        expect(permissions, 1);
        expect(engine.video!.cameraStarts, 1);
        if (platform == CallEndpointPlatform.android) {
          expect(fixture.lifecycleMethods, contains('setLocalCameraActive'));
        }
        await fixture.composition.onBackgrounded();
        source.emit(_graphCriticalQuality);
        await fixture.composition.onResume();
        source.emit(_graphCellularQuality);
        await Future<void>.delayed(Duration.zero);
        expect(engine.video!.cameraOn, isFalse);
        expect(engine.video!.cameraStarts, 1);
        expect(permissions, 1);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  test(
    'U3j-GQ terminal and graph shutdown fence late environment events',
    () async {
      final source = _GraphQualitySource(initial: _graphCellularQuality);
      final (fixture, engine) = await _connectedGraphVideo(
        qualityEnvironmentSourceFactory: () => source,
      );
      final video = engine.video!;
      expect(video.qualityEnvironments.lastOrNull, same(_graphCellularQuality));
      expect(
        await fixture.composition.end(_callA),
        ForegroundCallActionResult.applied,
      );
      final afterEnd = video.qualityEnvironments.length;
      source.emit(_graphCriticalQuality);
      await Future<void>.delayed(Duration.zero);
      expect(video.qualityEnvironments, hasLength(afterEnd));
      await fixture.composition.shutdown();
      expect(source.closes, 1);
      expect(source.cancellations, 1);
      source.emit(_graphCellularQuality);
      await Future<void>.delayed(Duration.zero);
      expect(video.qualityEnvironments, hasLength(afterEnd));
      expect(video.cameraStarts, 0);
    },
  );
  test('endpoint repair coalesces through delayed publication', () async {
    const contact = 'remote-account';
    var repairs = 0;
    final fixture = await _createProductionIosFixture(
      outgoingContactAccountPeerId: contact,
      repairMissingEndpoint: (_, {beforeRequest}) async {
        await beforeRequest?.call();
        repairs++;
        return true;
      },
    );
    await fixture.composition.start();
    await _configureCancellationEndpoint(fixture, contact);
    final published = fixture.bridge.responses['call_endpoint_get_v1']!;
    fixture.bridge.responses['call_endpoint_get_v1'] = <String, Object?>{
      'ok': true,
      'found': false,
    };
    final first = fixture.composition.recoverOutgoingCallAvailabilityFor(
      contact,
      request: OutgoingCallStartRequest(),
    );
    await _untilComposition(() => repairs == 1);
    // Join after the authenticated request finished but before publication.
    await Future<void>.delayed(Duration.zero);
    final second = fixture.composition.recoverOutgoingCallAvailabilityFor(
      contact,
      request: OutgoingCallStartRequest(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(repairs, 1);
    fixture.bridge.responses['call_endpoint_get_v1'] = published;
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(repairs, 1);
  });

  for (final publicationAccepted in [true, false]) {
    test('endpoint repair advertisement exports outcome with FLOW off '
        'accepted=$publicationAccepted', () async {
      final previousFlow = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      addTearDown(() => flowEventLoggingEnabled = previousFlow);
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final fixture = await _createProductionIosFixture(
        endpointSetResponse: {'ok': publicationAccepted},
      );
      await fixture.composition.start();
      final exported = await diagnostics.exportPreview();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      final publications = (decoded['events'] as List)
          .where(
            (event) =>
                event['stage'] == 'authority' &&
                event['action'] == 'publish' &&
                (event['values'] as Map)['authorityKind'] == 'endpoint',
          )
          .toList();
      expect(publications, hasLength(1));
      expect(
        publications.single['outcome'],
        publicationAccepted ? 'ok' : 'failed',
      );
      expect(
        publications.single['reason'],
        publicationAccepted ? 'none' : 'capability_publish_failed',
      );
      for (final sensitive in [
        'local-account',
        'local-private-key',
        'local-mlkem-secret-key',
        'com.mknoon.app.voip',
        List<String>.filled(64, 'c').join(),
      ]) {
        expect(exported, isNot(contains(sensitive)));
      }
    });
  }

  for (final change in ['rekey', 'delete and re-add']) {
    test(
      'VC-026 admission witness survives $change during authenticated native name wait',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vc026-admission-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final database = await _openKilledCallDatabase(
          '${directory.path}/original.sqlite',
        );
        addTearDown(() async {
          if (database.isOpen) await database.close();
        });
        await database.insert('identity', <String, Object?>{
          'id': 1,
          'peer_id': 'local-account',
          'public_key': 'local-public-key',
          'username': 'Local',
          'private_key': null,
          'mnemonic12': null,
          'ml_kem_public_key': 'local-mlkem-public-key',
          'ml_kem_secret_key': null,
          'created_at': '2026-08-30T00:00:00.000Z',
          'updated_at': '2026-08-30T00:00:00.000Z',
        });
        await database.insert('contacts', <String, Object?>{
          'peer_id': 'remote-account',
          'public_key': 'remote-public-key',
          'ml_kem_public_key': 'remote-mlkem-public-key',
          'rendezvous': 'fixture-rendezvous',
          'username': 'Remote contact',
          'signature': 'fixture-signature',
          'scanned_at': '2026-08-30T00:00:00.000Z',
          'is_blocked': 0,
        });
        final originalConsent = (await database.query(
          'contact_relationship_consent',
          where: 'peer_id = ?',
          whereArgs: ['remote-account'],
        )).single['revision'];
        final originalFingerprint = computeDirectContactLegacyTargetFingerprint(
          contactAccountPeerId: 'remote-account',
          accountSigningPublicKey: 'remote-public-key',
          legacyMlKemPublicKey: 'remote-mlkem-public-key',
        );
        final keys = _CapturedFirstCallCheckpointStore();
        final authenticated = Completer<void>();
        final releaseNative = Completer<void>();
        final terminal = Completer<void>();
        final fixture = await _createProductionIosFixture(
          databaseOverride: database,
          privacyStore: keys,
          callEngineFactory: (_) => _ProcessLossEngine(),
          lifecycleOverride: (method, _) async {
            if (method == 'updateAuthenticatedContact' &&
                !authenticated.isCompleted) {
              authenticated.complete();
              await releaseNative.future;
            }
            return null;
          },
        );
        await fixture.composition.start();
        final graph = fixture.graphs.single;
        final subscription = graph.coordinator.snapshots.listen((snapshot) {
          if (snapshot.callId == _callA &&
              snapshot.isTerminal &&
              !terminal.isCompleted) {
            terminal.complete();
          }
        });
        try {
          final signal = CallSignal.create(
            callId: _callA,
            messageId: '00000000-0000-4000-8000-000000000023',
            event: CallSignalType.invite,
            senderAccountPeerId: 'remote-account',
            senderDevicePeerId: 'remote-account',
            recipientAccountPeerId: 'local-account',
            recipientDevicePeerId: 'local-account',
            senderSequence: 1,
            iceGeneration: 0,
            createdAtMs: 2_000_000,
            expiresAtMs: 2_045_000,
          );
          fixture.bridge.responses['payload.verify'] = {
            'ok': true,
            'valid': true,
          };
          fixture.bridge.responses['message.decrypt'] = {
            'ok': true,
            'plaintext': jsonEncode(signal.toMap()),
          };
          fixture.p2p.messages.add(
            ChatMessage(
              from: 'remote-account',
              to: 'local-account',
              content: jsonEncode({
                'type': 'call_signal',
                'version': '1',
                'message_id': signal.messageId,
                'call_handle': '33333333-3333-4333-8333-333333333333',
                'expires_at_ms': signal.expiresAtMs,
                'kem': base64Encode([1]),
                'ciphertext': base64Encode([2]),
                'nonce': base64Encode([3]),
                'signature': base64Encode([4]),
              }),
              timestamp: _callNow.toIso8601String(),
              isIncoming: true,
              transport: 'direct',
            ),
          );
          await authenticated.future.timeout(const Duration(seconds: 2));
          expect(await keys.read('vc2_active_call_history_v1'), isNull);
          if (change == 'rekey') {
            await database.update(
              'contacts',
              {'public_key': 'replacement-remote-key'},
              where: 'peer_id = ?',
              whereArgs: ['remote-account'],
            );
          } else {
            final contact = (await database.query(
              'contacts',
              where: 'peer_id = ?',
              whereArgs: ['remote-account'],
            )).single;
            await database.delete(
              'contacts',
              where: 'peer_id = ?',
              whereArgs: ['remote-account'],
            );
            await database.insert('contacts', contact);
          }
          releaseNative.complete();
          await Future.any<void>([
            keys.written.future,
            terminal.future,
          ]).timeout(const Duration(seconds: 2));
          final raw = await keys.read('vc2_active_call_history_v1');
          if (raw != null) {
            final record = jsonDecode(raw) as Map<String, dynamic>;
            expect(
              record['remote_fingerprint'],
              originalFingerprint,
              reason:
                  'the first checkpoint cannot adopt keys that did not authenticate this invite',
            );
            expect(
              record['relationship_revision'],
              originalConsent,
              reason:
                  'the first checkpoint cannot renew a deleted relationship',
            );
          }

          final captured = FakeSecureKeyStore();
          for (final entry in (await keys.readAll()).entries) {
            await captured.write(entry.key, entry.value);
          }
          final snapshotPath = '${directory.path}/at-kill.sqlite';
          await database.execute('VACUUM INTO ?', [snapshotPath]);
          keys.release.complete();
          await fixture.composition.shutdown();
          final restoredDatabase = await _openKilledCallDatabase(snapshotPath);
          try {
            final existingRows = await restoredDatabase.query('call_history');
            final restored = await _createProductionIosFixture(
              databaseOverride: restoredDatabase,
              privacyStore: captured,
              clockMs: () => 2_120_000,
            );
            try {
              await restored.composition.start();
              expect(
                await restoredDatabase.query('call_history'),
                existingRows,
                reason:
                    'restart cannot recover this invite under replacement authority',
              );
              expect(restored.graphs.single.coordinator.activeSession, isNull);
            } finally {
              await restored.composition.shutdown();
            }
          } finally {
            if (restoredDatabase.isOpen) await restoredDatabase.close();
          }
        } finally {
          if (!releaseNative.isCompleted) releaseNative.complete();
          if (!keys.release.isCompleted) keys.release.complete();
          await subscription.cancel();
          await fixture.composition.shutdown();
        }
      },
    );
  }

  for (final operation in ['read', 'write']) {
    test(
      'VC-026 stalled checkpoint $operation cannot block hangup or dispose',
      () {
        fakeAsync((time) {
          final store = _StalledCallCheckpointStore(operation);
          var cleanupCalls = 0;
          Object? admissionFailure;
          var admissionSettled = false;
          var hangupSettled = false;
          var disposed = false;
          final coordinator = CallCoordinator(
            reducer: const CallReducer(),
            cleanupCoordinator: CallCleanupCoordinator([
              CallCleanupStep('release_media', (_) async => cleanupCalls++),
            ]),
            historyProjector: CallHistoryProjector(
              _UnusedCallHistoryRepository(),
            ),
            clock: () => _callNow,
            idSource: () => _callA,
            effectTimeout: const Duration(milliseconds: 10),
            terminalHistoryTimeout: const Duration(milliseconds: 10),
            persistActiveCall: (snapshot) async {
              await store.read('vc2_active_call_history_v1');
              await store.write(
                'vc2_active_call_history_v1',
                snapshot.callId!.value,
              );
            },
          );
          unawaited(
            coordinator
                .placeCall(
                  contactPeerId: 'remote-account',
                  localAccountPeerId: 'local-account',
                  localDeviceId: 'local-account',
                )
                .then<void>(
                  (_) {
                    admissionSettled = true;
                  },
                  onError: (Object error) {
                    admissionFailure = error;
                    admissionSettled = true;
                  },
                ),
          );
          time.flushMicrotasks();
          expect(store.entered.isCompleted, isTrue);
          unawaited(
            coordinator
                .dispatch(
                  CallEvent(
                    type: CallEventType.end,
                    eventId: 'vc026-hangup-during-checkpoint-$operation',
                    occurredAt: _callNow,
                    callId: _callA,
                  ),
                )
                .then<void>((_) {
                  hangupSettled = true;
                }),
          );
          unawaited(
            coordinator.dispose().then<void>((_) {
              disposed = true;
            }),
          );
          try {
            time.elapse(const Duration(milliseconds: 11));
            time.flushMicrotasks();
            expect(
              disposed,
              isTrue,
              reason:
                  'checkpoint I/O must obey the existing effect budget so terminal cleanup can advance',
            );
            expect(cleanupCalls, 1);
            expect(coordinator.activeSession, isNull);
            expect(admissionFailure, isA<TimeoutException>());
            expect(admissionSettled, isTrue);
            expect(hangupSettled, isTrue);
          } finally {
            store.release.complete();
            time.flushMicrotasks();
          }
        });
      },
    );
  }

  for (final scenario in [
    'ringing',
    'connected',
    'connected late observation',
    'headless connected',
    'headless checkpoint read failure',
    'headless never connected',
    'headless no checkpoint',
    'headless unrelated checkpoint',
    'headless wrong handle',
    'headless wrong account',
    'headless wrong device',
    'headless blocked contact',
    'headless rekeyed contact',
    'headless deleted and re-added contact',
    'headless rekeyed identity',
    'Android ringing',
    'blocked contact',
    'rekeyed contact',
    'deleted and re-added contact',
    'rekeyed identity',
  ]) {
    final headless = scenario.startsWith('headless ');
    final connected =
        scenario.startsWith('connected') ||
        (headless &&
            scenario != 'headless never connected' &&
            scenario != 'headless no checkpoint');
    final android = scenario == 'Android ringing' || headless;
    final revoked =
        headless &&
        const [
          'headless blocked contact',
          'headless rekeyed contact',
          'headless deleted and re-added contact',
          'headless rekeyed identity',
        ].contains(scenario);
    final checkpointReadFailure =
        scenario == 'headless checkpoint read failure';
    final wrongBinding = scenario.startsWith('headless wrong ');
    final unrelated = scenario == 'headless unrelated checkpoint';
    final shouldRecover = headless
        ? !revoked
        : scenario == 'ringing' || connected || android;
    test(
      'VC-026 killed-side $scenario history after restart without a fresh invite',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vc026-history-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final original = await _openKilledCallDatabase(
          '${directory.path}/original.sqlite',
        );
        addTearDown(() async {
          if (original.isOpen) await original.close();
        });
        await original.insert('identity', <String, Object?>{
          'id': 1,
          'peer_id': 'local-account',
          'public_key': 'local-public-key',
          'private_key': null,
          'mnemonic12': null,
          'username': 'Local',
          'ml_kem_public_key': 'local-mlkem-public-key',
          'ml_kem_secret_key': null,
          'created_at': '2026-08-30T00:00:00.000Z',
          'updated_at': '2026-08-30T00:00:00.000Z',
        });
        await original.insert('contacts', <String, Object?>{
          'peer_id': 'remote-account',
          'public_key': 'remote-public-key',
          'ml_kem_public_key': 'remote-mlkem-public-key',
          'rendezvous': 'fixture-rendezvous',
          'username': 'Remote contact',
          'signature': 'fixture-signature',
          'scanned_at': '2026-08-30T00:00:00.000Z',
          'is_blocked': 0,
        });
        final consent = await original.query(
          'contact_relationship_consent',
          where: 'peer_id = ?',
          whereArgs: ['remote-account'],
        );
        expect(consent, hasLength(1));
        final keys = FakeSecureKeyStore();
        String? registeredHandle;
        int? registeredExpiresAt;
        var audioActive = false;
        late final _ProductionIosFixture first;
        first = await _createProductionIosFixture(
          databaseOverride: original,
          privacyStore: keys,
          outgoingContactAccountPeerId: 'remote-account',
          nativePlatform: android
              ? CallEndpointPlatform.android
              : CallEndpointPlatform.ios,
          privacyFlags: {
            if (android) 'voice_call_android_native_enabled': false,
          },
          callEngineFactory: (_) => _ProcessLossEngine(),
          lifecycleOverride: (method, arguments) async {
            if (method == 'registerOutgoingAuthenticated') {
              registeredHandle = arguments['callHandle']! as String;
              registeredExpiresAt = arguments['expiresAtMs']! as int;
              return true;
            }
            if (method == 'attach' && registeredHandle != null) {
              return <String, Object?>{
                'version': 1,
                'descriptor': <String, Object?>{
                  'callHandle': registeredHandle,
                  'expiresAtMs': registeredExpiresAt,
                  'presented': true,
                  'phase': 'preStart',
                  'direction': 'outgoing',
                },
                'nativeCallId': registeredHandle,
                'highestSequence': 1,
                'events': [
                  <String, Object?>{
                    'callHandle': registeredHandle,
                    'sequence': 1,
                    'eventId': '00000000-0000-4000-8000-000000000001',
                    'type': 'presented',
                    'occurredAtMs': 2_000_000,
                  },
                ],
              };
            }
            if (method == 'activateAudio') audioActive = true;
            if (method == 'deactivateAudio' ||
                method == 'failClosed' ||
                method == 'end') {
              audioActive = false;
            }
            if (method == 'readAudioState') {
              return <String, Object?>{
                'version': 1,
                'active': audioActive,
                'muted': false,
                'route': 'system_default',
                'availableRoutes': ['system_default', 'speaker'],
              };
            }
            return null;
          },
          microphonePermission: const _GrantedCallMicrophonePermission(),
          ensureOutgoingCallWakeAuthority: (peer) async {
            final issued = await first.issuedCallWakeHandleStore.readForContact(
              peer,
            );
            return issued != null &&
                await first.graphs.single.markCallWakeHandleDistributed(
                  peer,
                  issued.grant,
                );
          },
        );
        if (headless) {
          // The incoming call was visible before process loss. Android's
          // foreground presenter requires a mounted projection listener.
          final presentation = first.composition.changes.listen((_) {});
          addTearDown(presentation.cancel);
        }
        await first.composition.start();
        await _configureCancellationEndpoint(first, 'remote-account');
        final graph = first.graphs.single;
        if (headless) {
          final invite = _killedCallSignal(CallSignalType.invite);
          first.bridge.responses['message.decrypt'] = {
            'ok': true,
            'plaintext': jsonEncode(invite.toMap()),
          };
          first.p2p.messages.add(
            ChatMessage(
              from: 'remote-account',
              to: 'local-account',
              content: _killedCallEnvelope(invite, _killedCallHandle),
              timestamp: _callNow.toIso8601String(),
              isIncoming: true,
              transport: 'direct',
            ),
          );
          await _untilComposition(
            () =>
                graph.coordinator.activeSession?.incomingValidated == true &&
                graph.coordinator.activeSession?.state == CallState.ringing,
          );
        } else {
          expect(
            await graph.startOutgoingCall('remote-account'),
            OutgoingCallStartResult.started,
          );
          await graph.coordinator.dispatch(
            CallEvent(
              type: CallEventType.remoteRinging,
              eventId: 'vc026-authenticated-remote-ringing',
              occurredAt: graph.coordinator.clock(),
              callId: graph.coordinator.activeSession!.callId,
              contactPeerId: 'remote-account',
            ),
          );
        }
        final callId = graph.coordinator.activeSession!.callId!;
        final startedAt = graph.coordinator.activeSession!.startedAt;
        expect(graph.coordinator.activeSession?.state, CallState.ringing);
        if (connected) {
          final turnNow = DateTime.now().millisecondsSinceEpoch;
          final credentials = <String, Object?>{
            'ok': true,
            'schema': 'turn_credentials',
            'version': 1,
            'urls': ['turn:relay.invalid:3478?transport=udp'],
            'username': 'fixture-user',
            'password': 'fixture-password',
            'ttlSeconds': 600,
            'serverTimeMs': turnNow,
            'expiresAtMs': turnNow + 600000,
          };
          first.bridge.responses['relay:turn_credentials_v1'] = credentials;
          first.bridge.responses['turn_credentials_with_diagnostics_v1'] =
              credentials;
          Future<void> event(CallEventType type) async {
            await graph.coordinator.dispatch(
              CallEvent(
                type: type,
                eventId: 'vc026-${type.name}',
                occurredAt: graph.coordinator.clock(),
                callId: callId,
                contactPeerId: 'remote-account',
              ),
            );
          }

          await event(
            headless ? CallEventType.answer : CallEventType.remoteAccept,
          );
          if (graph.coordinator.activeSession?.state == CallState.accepted) {
            await event(CallEventType.negotiationReady);
          }
          if (graph.coordinator.activeSession?.state == CallState.negotiating) {
            await event(CallEventType.mediaConnected);
          }
          expect(graph.coordinator.activeSession?.state, CallState.connected);
        }
        final connectedAt = graph.coordinator.activeSession?.connectedAt;
        if (scenario == 'connected late observation' ||
            (headless && connected)) {
          const checkpointKey = 'vc2_active_call_history_v1';
          final checkpoint =
              jsonDecode((await keys.read(checkpointKey))!)
                  as Map<String, dynamic>;
          expect(checkpoint['call_id'], callId.value);
          expect(checkpoint['connected_at'], connectedAt!.toIso8601String());
          // Model a periodic save without advancing the canonical snapshot.
          checkpoint['observed_at'] = connectedAt
              .add(const Duration(seconds: 30))
              .toIso8601String();
          await keys.write(checkpointKey, jsonEncode(checkpoint));
          final late = await graph.coordinator.dispatch(
            CallEvent(
              type: CallEventType.directAccepted,
              eventId: 'vc026-connected-late-observation',
              occurredAt: connectedAt,
              callId: callId,
            ),
          );
          expect(late.decision, CallEventDecision.applied);
          expect(graph.coordinator.activeSession?.state, CallState.connected);
        }
        expect(
          await graph.coordinator.historyProjector.repository.getByCallId(
            callId,
          ),
          isNull,
        );

        // Capture the durable bytes at process loss before graceful teardown can
        // write a terminal row. VACUUM includes committed WAL data.
        final captured = _FailingHeadlessCheckpointReadStore();
        for (final entry in (await keys.readAll()).entries) {
          await captured.write(entry.key, entry.value);
        }
        final snapshotPath = '${directory.path}/at-kill.sqlite';
        await original.execute('VACUUM INTO ?', [snapshotPath]);
        await first.composition.shutdown();
        final restoredDatabase = await _openKilledCallDatabase(snapshotPath);
        addTearDown(() async {
          if (restoredDatabase.isOpen) await restoredDatabase.close();
        });
        expect(await restoredDatabase.query('call_history'), isEmpty);
        Future<void> revokeAuthority() async {
          switch (headless
              ? scenario.substring('headless '.length)
              : scenario) {
            case 'blocked contact':
              await restoredDatabase.update(
                'contacts',
                {'is_blocked': 1},
                where: 'peer_id = ?',
                whereArgs: ['remote-account'],
              );
            case 'rekeyed contact':
              await restoredDatabase.update(
                'contacts',
                {'public_key': 'different-remote-key'},
                where: 'peer_id = ?',
                whereArgs: ['remote-account'],
              );
            case 'deleted and re-added contact':
              final contact = (await restoredDatabase.query(
                'contacts',
                where: 'peer_id = ?',
                whereArgs: ['remote-account'],
              )).single;
              await restoredDatabase.delete(
                'contacts',
                where: 'peer_id = ?',
                whereArgs: ['remote-account'],
              );
              await restoredDatabase.insert('contacts', contact);
            case 'rekeyed identity':
              await restoredDatabase.update('identity', {
                'public_key': 'different-local-key',
              }, where: 'id = 1');
          }
        }

        if (!headless) await revokeAuthority();
        final missedCards = <String>[];
        List<Map<String, Object?>>? headlessRows;
        Future<void> Function()? replayHeadless;
        if (headless) {
          const checkpointKey = 'vc2_active_call_history_v1';
          final raw = (await captured.read(checkpointKey))!;
          final checkpoint = jsonDecode(raw) as Map<String, dynamic>;
          expect(checkpoint['direction'], 'incoming');
          expect(checkpoint['connected_at'], connectedAt?.toIso8601String());
          if (unrelated || wrongBinding) {
            final field = switch (scenario) {
              'headless unrelated checkpoint' => 'call_id',
              'headless wrong handle' => 'call_handle',
              'headless wrong account' => 'contact',
              _ => 'remote_device',
            };
            checkpoint[field] = field == 'call_id' || field == 'call_handle'
                ? '99999999-9999-4999-8999-999999999999'
                : 'unrelated-account';
            await captured.write(checkpointKey, jsonEncode(checkpoint));
          }
          if (scenario == 'headless no checkpoint') {
            await captured.delete(checkpointKey);
          }
          final beforeHeadless = await captured.read(checkpointKey);
          replayHeadless = () => _runKilledCallHeadlessTerminal(
            database: restoredDatabase,
            secureKeyStore: captured,
            localIdentity: graph.localIdentity,
            missedCards: missedCards,
            afterAuthentication: revoked ? revokeAuthority : null,
          );
          captured.failCheckpointRead = checkpointReadFailure;
          try {
            await replayHeadless();
          } finally {
            captured.failCheckpointRead = false;
          }
          headlessRows = await restoredDatabase.query('call_history');
          if (checkpointReadFailure) {
            expect(
              headlessRows,
              isEmpty,
              reason:
                  'checkpoint read uncertainty must not fall through to a weaker terminal history write',
            );
            expect(missedCards, isEmpty);
            expect(captured.failedCheckpointReads, greaterThan(0));
            expect(
              await captured.read(checkpointKey),
              beforeHeadless,
              reason:
                  'failed headless reads must retain the original checkpoint for recovery',
            );
            return;
          }
          if (revoked || wrongBinding) {
            expect(
              headlessRows,
              isEmpty,
              reason:
                  'authenticated terminal must not weak-fallback past a revoked or mismatched checkpoint',
            );
            expect(missedCards, isEmpty);
            if (wrongBinding) {
              expect(await captured.read(checkpointKey), beforeHeadless);
              return;
            }
          } else {
            expect(headlessRows, hasLength(1));
            final firstRow = (await CallHistoryRepositoryImpl(
              restoredDatabase,
            ).getByCallId(callId))!;
            expect(firstRow.direction, CallDirection.incoming);
            if (connected && !unrelated) {
              expect(
                firstRow.status,
                CallHistoryStatus.completed,
                reason:
                    'the first durable headless row must preserve the connected checkpoint before foreground recovery',
              );
              expect(firstRow.startedAt, startedAt);
              expect(firstRow.connectedAt, connectedAt);
              expect(firstRow.duration, const Duration(seconds: 30));
              expect(
                firstRow.endedAt,
                connectedAt!.add(const Duration(seconds: 30)),
              );
              expect(missedCards, isEmpty);
              expect(await captured.read(checkpointKey), isNull);
            } else {
              expect(firstRow.connectedAt, isNull);
              expect(
                firstRow.status,
                isIn([CallHistoryStatus.missed, CallHistoryStatus.cancelled]),
              );
              expect(missedCards, hasLength(1));
            }
            if (unrelated) {
              expect(
                await captured.read(checkpointKey),
                beforeHeadless,
                reason:
                    'headless settlement must not consume another call checkpoint',
              );
              await replayHeadless();
              expect(
                await restoredDatabase.query('call_history'),
                headlessRows,
              );
              expect(missedCards, hasLength(1));
              return;
            }
          }
        }
        var historyAtNativeAttach = false;
        final announcedHistory = <(CallId, bool)>[];
        final restored = await _createProductionIosFixture(
          databaseOverride: restoredDatabase,
          privacyStore: captured,
          onCallHistoryProjected: (entry, inserted) =>
              announcedHistory.add((entry.callId, inserted)),
          nativePlatform: android
              ? CallEndpointPlatform.android
              : CallEndpointPlatform.ios,
          privacyFlags: {
            if (android) 'voice_call_android_native_enabled': false,
          },
          clockMs: () => 2_120_000, // The original invite has expired.
          lifecycleOverride: (method, _) async {
            if (method == 'attach') {
              historyAtNativeAttach =
                  (await restoredDatabase.query(
                    'call_history',
                    where: 'call_id = ?',
                    whereArgs: [callId.value],
                  )).length ==
                  1;
            }
            return null;
          },
        );
        // No incoming message, fresh invite, or authenticated context is supplied.
        await restored.composition.start();
        final restarted = restored.graphs.single;
        final row = await restarted.coordinator.historyProjector.repository
            .getByCallId(callId);
        if (!shouldRecover) {
          expect(
            row,
            isNull,
            reason: 'a revoked authority must not resurrect old call history',
          );
          expect(historyAtNativeAttach, isFalse);
          expect(announcedHistory, isEmpty);
          return;
        }
        expect(
          row,
          isNotNull,
          reason: 'the killed side must retain its authenticated call history',
        );
        expect(row!.contactAccountPeerId, 'remote-account');
        expect(
          row.direction,
          headless ? CallDirection.incoming : CallDirection.outgoing,
        );
        expect(
          row.status,
          connected
              ? CallHistoryStatus.completed
              : headless
              ? CallHistoryStatus.cancelled
              : CallHistoryStatus.failed,
        );
        expect(row.connectedAt, connectedAt);
        if (!headless || connected) expect(row.startedAt, startedAt);
        if (scenario == 'connected late observation' ||
            (headless && connected)) {
          expect(row.duration, const Duration(seconds: 30));
          expect(row.endedAt, connectedAt!.add(const Duration(seconds: 30)));
        }
        expect(
          announcedHistory,
          scenario == 'headless never connected'
              ? [(callId, false)]
              : headless
              ? <(CallId, bool)>[]
              : [(callId, true)],
          reason:
              'mounted history consumers must hear the existing durable-row notification',
        );
        if (android) {
          expect(
            restored.lifecycleMethods,
            isEmpty,
            reason:
                'Android recovery must work without a retained native journal',
          );
        } else {
          expect(
            historyAtNativeAttach,
            isTrue,
            reason:
                'history must be durable before native orphan cleanup can acknowledge it',
          );
        }
        expect(restarted.coordinator.activeSession, isNull);
        await restored.composition.start();
        await restored.composition.onResume();
        expect(
          announcedHistory,
          scenario == 'headless never connected'
              ? [(callId, false)]
              : headless
              ? <(CallId, bool)>[]
              : [(callId, true)],
          reason:
              'repeated start or resume must not announce another recovered row',
        );
        expect(
          await restarted.coordinator.historyProjector.repository
              .listForContact('remote-account'),
          hasLength(1),
        );
        if (headless) {
          await replayHeadless!();
          expect(
            await restoredDatabase.query('call_history'),
            headlessRows,
            reason:
                'foreground restart and authenticated terminal replay must leave the first row byte-for-byte unchanged',
          );
          expect(missedCards, connected ? isEmpty : hasLength(1));
        }
      },
    );
  }

  for (final platform in [
    CallEndpointPlatform.android,
    CallEndpointPlatform.ios,
  ]) {
    for (final warm in [false, true]) {
      test(
        'resume pipeline advertises once (${platform.name}, warm=$warm)',
        () async {
          final events = <String>[];
          final graph = _Graph(events);
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: platform,
            awaitReadiness: () async {},
            buildGraph: () async => graph,
            isForeground: () => true,
          );
          addTearDown(composition.shutdown);
          var pendingChecks = 0;
          var retries = 0;
          Future<bool> resumeWithBackfill() =>
              resumeCallSignalingAndBackfillCallWake(
                resumeCallSignaling: composition.onResume,
                reconcileCallWakeEligibility:
                    composition.onContactEligibilityChanged,
                hasPendingCallWakeDistribution: () async {
                  pendingChecks++;
                  return true;
                },
                retryCallWakeDistribution:
                    ({required trigger, required requireFresh}) async {
                      expect(requireFresh, isTrue);
                      retries++;
                      return 1;
                    },
              );
          if (warm) await composition.start();
          events.clear();

          expect(await resumeWithBackfill(), isTrue);
          expect(events.where((event) => event == 'advertise'), hasLength(1));
          expect(composition.isStarted, isTrue);
          expect(pendingChecks, 1);
          expect(retries, 1);

          events.clear();
          expect(await resumeWithBackfill(), isTrue);
          expect(events.where((event) => event == 'advertise'), hasLength(1));
          expect(pendingChecks, 2);
          expect(retries, 2);

          await composition.onContactEligibilityChanged();
          expect(events.where((event) => event == 'advertise'), hasLength(2));
        },
      );
    }
  }

  test('failed resume advertisement still reconciles', () async {
    final events = <String>[];
    final graph = _Graph(events, advertisementResults: [true, false, true]);
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      buildGraph: () async => graph,
      isForeground: () => true,
    );
    addTearDown(composition.shutdown);
    await composition.start();
    graph.emitForeground(_projection(state: CallState.connected));
    events.clear();
    var retries = 0;

    expect(
      await resumeCallSignalingAndBackfillCallWake(
        resumeCallSignaling: composition.onResume,
        reconcileCallWakeEligibility: composition.onContactEligibilityChanged,
        hasPendingCallWakeDistribution: () async => true,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              retries++;
              return 1;
            },
      ),
      isTrue,
    );

    expect(events.where((event) => event == 'advertise'), hasLength(2));
    expect(events, isNot(contains('call_shutdown')));
    expect(composition.isStarted, isTrue);
    expect(retries, 1);
  });

  test('production graph feeds path epochs to the active call and lets the '
      'source go on shutdown', () async {
    final outcomes = StreamController<NetworkPathOutcome>.broadcast(sync: true);
    addTearDown(outcomes.close);
    final fixture = await _createProductionSpeakerRouteFixture(
      networkPathOutcomes: outcomes.stream,
    );
    final graph = fixture.graph;
    expect(outcomes.hasListener, isTrue);
    expect(graph.coordinator.activeSession?.pendingPathEpoch, isNull);

    outcomes.add(
      const NetworkPathOutcome(
        generation: 2,
        epoch: 7,
        stage: NetworkPathStage.changing,
      ),
    );
    for (var turn = 0; turn < 8; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(graph.coordinator.activeSession?.pendingPathEpoch, 7);

    await graph.shutdown();
    expect(outcomes.hasListener, isFalse);
  });

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

  for (final direction in CallDirection.values) {
    for (final policyCase in [
      (choice: null, available: true, forced: false),
      (choice: 'false', available: true, forced: false),
      (choice: 'true', available: true, forced: false),
      (choice: 'unreadable-version', available: true, forced: false),
      (choice: 'true', available: false, forced: false),
      (choice: 'false', available: true, forced: true),
    ]) {
      final choice = policyCase.choice;
      test(
        'production $direction freezes privacy=$policyCase before media',
        () async {
          TestWidgetsFlutterBinding.ensureInitialized();
          final store = FakeSecureKeyStore();
          if (choice != null) {
            await store.write(alwaysRelayCallsStorageKey, choice);
          }
          final fixture = await _createProductionIosFixture(
            outgoingContactAccountPeerId: 'remote-account',
            privacyStore: store,
            privacyFlags: {
              'voice_call_always_relay_enabled': policyCase.available,
              'voice_call_force_relay_enabled': policyCase.forced,
              'voice_call_ios_native_enabled':
                  direction == CallDirection.incoming,
            },
            nativeHandleOverride: '33333333-3333-4333-8333-333333333333',
          );
          await fixture.composition.start();
          final graph = fixture.graphs.single;
          if (direction == CallDirection.outgoing) {
            final device = (await graph.trustedRosterProvider.loadForContact(
              'remote-account',
            )).devices.single;
            final nowMs = graph.coordinator.clock().millisecondsSinceEpoch;
            expect(
              await fixture.receivedCallWakeHandleStore.storeIfStrictlyNewer(
                issuerAccountPeerId: 'remote-account',
                grant: CallWakeHandleGrant(
                  handle: 'fedcba9876543210fedcba9876543210',
                  recipientDevicePeerId: device.devicePeerId,
                  deviceKeyEpoch: device.deviceKeyEpoch,
                  generation: 1,
                  issuedAtMs: nowMs - 1000,
                  expiresAtMs: nowMs + 60000,
                ),
                nowMs: nowMs,
              ),
              isTrue,
            );
          }
          final endpointRead = Completer<void>();
          final endpointResult = Completer<Map<String, Object?>>();
          fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) {
            if (!endpointRead.isCompleted) endpointRead.complete();
            return endpointResult.future;
          };
          final placement = graph.coordinator.dispatch(
            CallEvent(
              type: direction == CallDirection.incoming
                  ? CallEventType.remoteInvite
                  : CallEventType.place,
              eventId: 'privacy-call',
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
            ),
          );
          try {
            if (direction == CallDirection.incoming) {
              await placement;
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
                true,
              );
            } else {
              // Hold unrelated endpoint work while checking the same production
              // bundle from the reducer's real outgoing session.
              await Future.any<void>([
                endpointRead.future,
                placement.then<void>((_) {
                  if (!endpointRead.isCompleted) {
                    throw TestFailure(
                      'Outgoing placement ended before the held endpoint lookup',
                    );
                  }
                }),
              ]).timeout(const Duration(seconds: 5));
            }
            final bundles = <CallScopedMediaBundle>[];
            final sub = graph.mediaOwner.bundleChanges.listen((b) {
              if (b != null) bundles.add(b);
            });
            addTearDown(sub.cancel);
            final snapshot = graph.coordinator.activeSession!;
            expect(snapshot.direction, direction);
            // A change while ringing/preparing must already belong to the next
            // call, before the lazy media bundle or native PC exists.
            await saveAlwaysRelayCallsPreference(
              secureKeyStore: store,
              alwaysRelay: choice == null || choice == 'false',
            );
            await graph.mediaOwner.execute(
              const CallEffect(CallEffectType.queueIceCandidate),
              snapshot,
            );
            final executor =
                bundles.single.negotiationExecutor
                    as CallNegotiationEffectExecutor;
            final expected =
                !policyCase.forced && (choice == null || choice == 'false')
                ? CallTransportPolicy.all
                : CallTransportPolicy.relayOnly;
            expect(executor.configuration.transportPolicy, expected);
            await saveAlwaysRelayCallsPreference(
              secureKeyStore: store,
              alwaysRelay: expected == CallTransportPolicy.all,
            );
            await graph.mediaOwner.execute(
              const CallEffect(CallEffectType.queueIceCandidate),
              snapshot,
            );
            expect(bundles, hasLength(1));
            expect(executor.configuration.transportPolicy, expected);
            expect(
              await resolveCallTransportPolicy(
                secureKeyStore: store,
                forceRelay: false,
              ),
              expected == CallTransportPolicy.all
                  ? CallTransportPolicy.relayOnly
                  : CallTransportPolicy.all,
            );
          } finally {
            endpointResult.complete({'ok': false});
            await placement;
          }
        },
      );
    }
  }

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
        final terminals = <CallSessionSnapshot>[];
        final subscription = graph.coordinator.snapshots
            .where((snapshot) => snapshot.isTerminal)
            .listen(terminals.add);
        addTearDown(subscription.cancel);
        final failure = await graph.mediaOwner.execute(
          const CallEffect(CallEffectType.prepareAcceptedMedia),
          graph.coordinator.activeSession!.copyWith(
            state: CallState.accepted,
            acceptedAt: graph.coordinator.clock(),
          ),
        );
        // Startup cleanup closes the engine before preparation settles. The
        // preparer's typed result owns the outcome, so the engine's closed
        // event must not pre-empt it with an untyped failure (a blocked
        // microphone has to end as permissionDenied, not mediaFailed). This
        // direct execute only observes the result; the coordinator dispatches.
        expect(failure?.type, CallEventType.negotiationFailed);
        expect(failure?.endReason, isNull);
        expect(terminals, isEmpty);
        await graph.coordinator.dispatch(failure!);
        expect(terminals, hasLength(1));
        expect(terminals.single.callId, _callA);
        expect(terminals.single.endReason, CallEndReason.mediaFailed);
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
        selectedLocalCandidateFamily: CallAddressFamily.ipv6,
        selectedRemoteCandidateFamily: CallAddressFamily.ipv4,
        pairRelayInvolvement: CallPairRelayInvolvement.local,
        selectedLocalTransport: CallTransportClass.turnUdp,
        selectedLocalRelayProtocol: CallRelayProtocol.udp,
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
      final media = events.firstWhere((event) => event['stage'] == 'media');
      expect(
        media['values'],
        containsPair('selectedLocalCandidateFamily', 'ipv6'),
      );
      expect(
        media['values'],
        containsPair('selectedRemoteCandidateFamily', 'ipv4'),
      );
      expect(
        media['values'],
        containsPair('localTurnConnectionFamily', 'unknown'),
      );
      expect(media['values'], containsPair('transport', 'turn_udp'));
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

  group('outgoing start diagnostics', () {
    test('report not_started before any start', () {
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => _Graph(<String>[]),
        isForeground: () => true,
        isTransportStarted: () => false,
      );
      addTearDown(composition.shutdown);
      expect(composition.outgoingCallStartDiagnostics(), <String, Object?>{
        'startStage': 'not_started',
        'startOutcome': 'not_started',
        'withdrawalFailed': false,
        'foreground': true,
        'transportStarted': false,
      });
    });

    test('name a P2P startup timeout during signaling readiness', () async {
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async =>
            throw TimeoutException('p2p', const Duration(seconds: 8)),
        buildGraph: () async => throw StateError('must not construct'),
        isForeground: () => true,
        isTransportStarted: () => false,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      final values = composition.outgoingCallStartDiagnostics();
      expect(values['startStage'], 'signaling_readiness');
      expect(values['startOutcome'], 'transport_startup_timeout');
      expect(values['transportStarted'], isFalse);
    });

    test('keep other readiness failures as failed', () async {
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async => throw StateError('identity'),
        buildGraph: () async => throw StateError('must not construct'),
        isForeground: () => true,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      final values = composition.outgoingCallStartDiagnostics();
      expect(values['startStage'], 'signaling_readiness');
      expect(values['startOutcome'], 'failed');
      expect(values.containsKey('transportStarted'), isFalse);
    });

    test('name a failed capability advertisement', () async {
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async =>
            _Graph(<String>[], advertisementResults: const <bool>[false]),
        isForeground: () => true,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      final values = composition.outgoingCallStartDiagnostics();
      expect(values['startStage'], 'capability_advertisement');
      expect(values['startOutcome'], 'advertisement_unavailable');
    });

    test('report in_flight while a start is running, then ready', () async {
      final readiness = Completer<void>();
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () => readiness.future,
        buildGraph: () async => _Graph(<String>[]),
        isForeground: () => true,
      );
      addTearDown(composition.shutdown);
      final start = composition.start();
      expect(
        composition.outgoingCallStartDiagnostics()['startOutcome'],
        'in_flight',
      );
      readiness.complete();
      await start;
      final values = composition.outgoingCallStartDiagnostics();
      expect(values['startStage'], 'complete');
      expect(values['startOutcome'], 'ready');
    });

    test('every value passes the closed call diagnostic schema', () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async =>
            throw TimeoutException('p2p', const Duration(seconds: 8)),
        buildGraph: () async => throw StateError('must not construct'),
        isForeground: () => true,
        isTransportStarted: () => false,
      );
      addTearDown(composition.shutdown);
      await composition.start();
      final traceId = diagnostics.beginAttempt();
      diagnostics.finishAttempt(
        traceId: traceId,
        outcome: 'preflight_failed',
        reason: 'transport_startup_timeout',
        values: composition.outgoingCallStartDiagnostics(),
      );
      final terminal = (await diagnostics.eventsForTesting()).singleWhere(
        (event) => event['stage'] == 'terminal',
      );
      expect(terminal['reason'], 'transport_startup_timeout');
      expect(terminal['values'], <String, Object?>{
        'startStage': 'signaling_readiness',
        'startOutcome': 'transport_startup_timeout',
        'withdrawalFailed': false,
        'foreground': true,
        'transportStarted': false,
        'terminal': true,
      });
      expect(CallDiagnostics.validateEvent(terminal), isNotNull);
    });
  });

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
      expect(result, OutgoingCallStartResult.microphoneDenied);
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

  for (final platform in CallEndpointPlatform.values) {
    test(
      'foreground idle mailbox polling respects ${platform.name} lifecycle',
      () {
        fakeAsync((time) {
          final events = <String>[];
          var foreground = true;
          final graph = _Graph(events);
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: platform,
            isForeground: () => foreground,
            awaitReadiness: () async {},
            buildGraph: () async => graph,
          );
          unawaited(composition.start());
          time.flushMicrotasks();
          expect(composition.isStarted, isTrue);
          expect(composition.current, isNull);
          events.clear();
          time.elapse(const Duration(seconds: 3));
          expect(events, isEmpty);
          time.elapse(const Duration(seconds: 1));
          expect(events, ['call_mailbox_drain']);

          foreground = false;
          unawaited(composition.onBackgrounded());
          time.flushMicrotasks();
          events.clear();
          time.elapse(const Duration(seconds: 12));
          expect(events, isEmpty);
          expect(time.periodicTimerCount, 0);

          foreground = true;
          unawaited(composition.onResume());
          time.flushMicrotasks();
          events.clear();
          time.elapse(const Duration(seconds: 4));
          expect(events, ['call_mailbox_drain']);
          expect(time.periodicTimerCount, 1);
          unawaited(composition.shutdown());
          time.flushMicrotasks();
          events.clear();
          time.elapse(const Duration(seconds: 20));
          expect(events, isEmpty);
          expect(time.periodicTimerCount, 0);
        });
      },
    );
  }

  for (final platform in CallEndpointPlatform.values) {
    for (final failOnResume in [false, true]) {
      testWidgets(
        'foreground start retry restores ${platform.name} idle polling '
        'after unavailable ${failOnResume ? 'resume' : 'startup'}',
        (tester) async {
          final events = <String>[];
          final unavailable = _Graph(
            events,
            advertisementResults: [true, false],
          );
          if (!failOnResume) {
            unavailable.onAdvertise = () async =>
                throw const CallAuthorityException(
                  CallAuthorityErrorCode.bridgeFailure,
                  relayErrorCode: 'CALL_CONTROL_UNAVAILABLE',
                );
          }
          final recovered = _Graph(events);
          var builds = 0;
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: platform,
            isForeground: () => true,
            awaitReadiness: () async {},
            buildGraph: () async => builds++ == 0 ? unavailable : recovered,
          );
          unawaited(composition.start());
          await _pumpCallLifecycle(tester);
          if (failOnResume) {
            expect(composition.isStarted, isTrue);
            unawaited(composition.onResume());
            await _pumpCallLifecycle(tester);
          }
          expect(composition.isStarted, isFalse);
          expect(events.where((e) => e == 'call_shutdown'), hasLength(1));
          await _pumpCallLifecycle(tester, const Duration(milliseconds: 4999));
          expect(builds, 1);
          await _pumpCallLifecycle(tester, const Duration(milliseconds: 1));
          expect(builds, 2);
          expect(composition.isStarted, isTrue);
          events.clear();
          await _pumpCallLifecycle(tester, const Duration(seconds: 25));
          expect(events, List.filled(6, 'call_mailbox_drain'));
          expect(builds, 2);
          unawaited(composition.shutdown());
          await _pumpCallLifecycle(tester);
        },
      );
    }
  }

  testWidgets(
    'foreground start retry backs off at 5, 15, 30 and then 60 seconds',
    (tester) async {
      final attempts = <Duration>[];
      final began = tester.binding.clock.now();
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        isForeground: () => true,
        awaitReadiness: () async {},
        buildGraph: () async {
          attempts.add(tester.binding.clock.now().difference(began));
          return _Graph([], advertisementResults: [false]);
        },
      );
      unawaited(composition.start());
      await _pumpCallLifecycle(tester);
      for (final delay in [5, 15, 30, 60, 60]) {
        final before = attempts.length;
        await _pumpCallLifecycle(
          tester,
          Duration(milliseconds: delay * 1000 - 1),
        );
        expect(attempts, hasLength(before));
        await _pumpCallLifecycle(tester, const Duration(milliseconds: 1));
        expect(attempts, hasLength(before + 1));
      }
      expect(
        attempts,
        [0, 5, 20, 50, 110, 170].map((s) => Duration(seconds: s)),
      );
      unawaited(composition.shutdown());
      await _pumpCallLifecycle(tester);
      await _pumpCallLifecycle(tester, const Duration(minutes: 5));
      expect(attempts, hasLength(6));
    },
  );

  testWidgets(
    'foreground start retry shares an in-flight start with call wakes',
    (tester) async {
      final startGate = Completer<void>();
      final events = <String>[];
      final recovered = _Graph(events, onStart: () => startGate.future);
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        isForeground: () => true,
        awaitReadiness: () async {},
        buildGraph: () async => builds++ == 0
            ? _Graph([], advertisementResults: [false])
            : recovered,
      );
      unawaited(composition.start());
      await _pumpCallLifecycle(tester);
      await _pumpCallLifecycle(tester, const Duration(seconds: 5));
      expect(builds, 2);
      unawaited(composition.onCallWake());
      unawaited(composition.onCallWake());
      await _pumpCallLifecycle(tester, const Duration(minutes: 2));
      expect(builds, 2);
      startGate.complete();
      await _pumpCallLifecycle(tester);
      expect(composition.isStarted, isTrue);
      events.clear();
      await _pumpCallLifecycle(tester, const Duration(seconds: 4));
      expect(events, ['call_mailbox_drain']);
      expect(builds, 2);
      unawaited(composition.shutdown());
      await _pumpCallLifecycle(tester);
    },
  );

  testWidgets(
    'foreground start retry cancels on background and resumes fresh',
    (tester) async {
      var foreground = true;
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        isForeground: () => foreground,
        awaitReadiness: () async {},
        buildGraph: () async {
          builds++;
          return _Graph([], advertisementResults: [false]);
        },
      );
      unawaited(composition.start());
      await _pumpCallLifecycle(tester);
      await _pumpCallLifecycle(tester, const Duration(seconds: 5));
      expect(builds, 2);
      foreground = false;
      unawaited(composition.onBackgrounded());
      await _pumpCallLifecycle(tester);
      await _pumpCallLifecycle(tester, const Duration(minutes: 2));
      expect(builds, 2);
      foreground = true;
      unawaited(composition.onResume());
      await _pumpCallLifecycle(tester);
      expect(builds, 3);
      await _pumpCallLifecycle(tester, const Duration(seconds: 5));
      expect(builds, 4);
      unawaited(composition.shutdown());
      await _pumpCallLifecycle(tester);
    },
  );

  testWidgets(
    'foreground start retry lets a call wake recover before the deadline',
    (tester) async {
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        isForeground: () => true,
        awaitReadiness: () async {},
        buildGraph: () async => builds++ == 0
            ? _Graph([], advertisementResults: [false])
            : _Graph([]),
      );
      unawaited(composition.start());
      await _pumpCallLifecycle(tester);
      await _pumpCallLifecycle(tester, const Duration(seconds: 2));
      unawaited(composition.onCallWake());
      await _pumpCallLifecycle(tester);
      expect(composition.isStarted, isTrue);
      expect(builds, 2);
      await _pumpCallLifecycle(tester, const Duration(minutes: 2));
      expect(builds, 2);
      unawaited(composition.shutdown());
      await _pumpCallLifecycle(tester);
    },
  );

  testWidgets('foreground start retry never bypasses failed graph cleanup', (
    tester,
  ) async {
    var builds = 0;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      isForeground: () => true,
      awaitReadiness: () async {},
      buildGraph: () async {
        builds++;
        return _Graph(
          [],
          advertisementResults: [false],
          onShutdown: (_) {
            throw StateError('native release unproven');
          },
        );
      },
    );
    unawaited(composition.start());
    await _pumpCallLifecycle(tester);
    await _pumpCallLifecycle(tester, const Duration(minutes: 5));
    expect(composition.isStarted, isFalse);
    expect(builds, 1);
    unawaited(composition.shutdown());
    await _pumpCallLifecycle(tester);
  });

  testWidgets('foreground start retry stops after callability invalidation '
      'during an advertisement', (tester) async {
    final advertisement = Completer<bool>();
    final invalidated = _Graph([])..onAdvertise = () => advertisement.future;
    var builds = 0;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.ios,
      isForeground: () => true,
      awaitReadiness: () async {},
      buildGraph: () async => switch (builds++) {
        0 => _Graph([], advertisementResults: [false]),
        1 => invalidated,
        _ => _Graph([]),
      },
    );
    unawaited(composition.start());
    await _pumpCallLifecycle(tester);
    await _pumpCallLifecycle(tester, const Duration(seconds: 2));
    unawaited(composition.onCallWake());
    await _pumpCallLifecycle(tester);
    expect(builds, 2);
    invalidated.callabilityInvalidationsController.add(null);
    await _pumpCallLifecycle(tester);
    advertisement.complete(false);
    await _pumpCallLifecycle(tester);
    await _pumpCallLifecycle(tester, const Duration(minutes: 2));
    expect(builds, 2);
    expect(composition.isStarted, isFalse);
    // The existing explicit resume may still build a fresh native owner.
    unawaited(composition.onResume());
    await _pumpCallLifecycle(tester);
    expect(builds, 3);
    expect(composition.isStarted, isTrue);
    unawaited(composition.shutdown());
    await _pumpCallLifecycle(tester);
  });

  for (final returnsFromBackground in [false, true]) {
    test('terminal idle mailbox probe continues after '
        '${returnsFromBackground ? 'resume' : 'foreground terminal'}', () {
      fakeAsync((time) {
        final events = <String>[];
        var foreground = true;
        final graph = _Graph(events);
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.android,
          isForeground: () => foreground,
          awaitReadiness: () async {},
          buildGraph: () async => graph,
        );
        unawaited(composition.start());
        time.flushMicrotasks();
        expect(composition.isStarted, isTrue);
        graph.emitForeground(
          _projection(
            direction: CallDirection.incoming,
            incomingValidated: true,
          ),
        );
        events.clear();
        time.elapse(const Duration(seconds: 2));
        expect(events, ['call_mailbox_drain']);
        if (returnsFromBackground) {
          foreground = false;
          unawaited(composition.onBackgrounded());
          time.flushMicrotasks();
        }
        graph.emitForeground(
          ForegroundCallProjection(
            session:
                _projection(
                  direction: CallDirection.incoming,
                  incomingValidated: true,
                ).session.copyWith(
                  state: CallState.ended,
                  endedAt: _callNow,
                  endReason: returnsFromBackground
                      ? CallEndReason.expired
                      : CallEndReason.callerCancelled,
                ),
            audio: CallAudioControlState.idle,
          ),
        );
        // Production publishes terminal once while its current value is null.
        graph.foregroundCurrent = null;
        if (returnsFromBackground) {
          events.clear();
          time.elapse(const Duration(seconds: 25));
          expect(events, isEmpty);
          expect(time.periodicTimerCount, 0);
          foreground = true;
          unawaited(composition.onResume());
          time.flushMicrotasks();
          expect(composition.isStarted, isTrue);
        }
        events.clear();
        time.elapse(const Duration(seconds: 25));
        expect(events, List.filled(6, 'call_mailbox_drain'));
        expect(time.periodicTimerCount, 1);
        graph.emitForeground(null);
        events.clear();
        time.elapse(const Duration(seconds: 25));
        expect(events, List.filled(6, 'call_mailbox_drain'));
        expect(time.periodicTimerCount, 1);
        unawaited(composition.shutdown());
        time.flushMicrotasks();
        expect(time.periodicTimerCount, 0);
      });
    });
  }

  test('foreground idle mailbox polling follows graph replacement', () async {
    final oldEvents = <String>[];
    final newEvents = <String>[];
    final oldGraph = _Graph(oldEvents, advertisementResults: [true, false]);
    final newGraph = _Graph(newEvents);
    final drained = Completer<void>();
    newGraph.onMailboxDrain = () async {
      if (!drained.isCompleted) drained.complete();
    };
    var builds = 0;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      isForeground: () => true,
      awaitReadiness: () async {},
      buildGraph: () async => builds++ == 0 ? oldGraph : newGraph,
    );
    addTearDown(composition.shutdown);
    await composition.start();
    await composition.onContactEligibilityChanged();
    expect(composition.isStarted, isFalse);
    expect(oldEvents, contains('call_shutdown'));
    await composition.start();
    expect(composition.isStarted, isTrue);
    expect(builds, 2);
    oldEvents.clear();
    newEvents.clear();
    oldGraph.emitForeground(_projection(state: CallState.connected));
    await drained.future.timeout(const Duration(seconds: 8));
    expect(oldEvents, isEmpty);
    expect(newEvents, ['call_mailbox_drain']);
  });

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

  for (final outgoing in [false, true]) {
    test(
      'production iOS ${outgoing ? 'outgoing' : 'incoming'} name projection '
      'reaches CallKit after native binding and rejects stale calls',
      () async {
        const handle = '33333333-3333-4333-8333-333333333333';
        final updates = <Map<String, Object?>>[];
        var registered = false;
        final fixture = await _createProductionSpeakerRouteFixture(
          outgoing: outgoing,
          nativeLifecycleFactory: (coordinator) => IosCallLifecycleAdapter(
            invokeMethod: (method, arguments) async {
              if (method == 'attach') {
                return <String, Object?>{
                  'version': 1,
                  'descriptor': registered
                      ? {
                          'callHandle': handle,
                          'expiresAtMs': 2_045_000,
                          'presented': true,
                          'phase': 'journal',
                          'direction': 'outgoing',
                        }
                      : null,
                  'events': <Object?>[
                    if (registered)
                      {
                        'callHandle': handle,
                        'sequence': 1,
                        'eventId': '55555555-5555-4555-8555-555555555555',
                        'type': 'presented',
                        'occurredAtMs': 2_000_000,
                      },
                  ],
                  'nativeCallId': registered ? handle : null,
                  'highestSequence': registered ? 1 : 0,
                };
              }
              if (method == 'registerOutgoingAuthenticated') registered = true;
              if (method == 'updateAuthenticatedContact') {
                updates.add(Map.of(arguments));
              }
              return true;
            },
            nativeEvents: const Stream<Object?>.empty(),
            coordinator: coordinator,
            resolveAuthenticatedHandle: (callId) =>
                callId == _callA ? handle : null,
            clock: coordinator.clock,
          ),
        );
        final graph = fixture.graph;
        addTearDown(() async {
          await graph.shutdown();
          await graph.coordinator.dispose();
        });
        LockedCallPresentation presentation(String name) =>
            LockedCallPresentation(
              displayName: name,
              avatarPng: null,
              state: 'connected',
              connectedAtMs: 2_000_000,
              light: false,
              muted: false,
              muteAvailable: true,
              speakerOn: false,
              speakerAvailable: true,
              routeLabel: 'Speaker',
            );
        await graph.updateLockedPresentation(
          _callA,
          presentation('Local contact'),
        );
        expect(updates, isEmpty);
        final native = graph.iosCallLifecycleAdapter!;
        expect(
          graph.coordinator.activeSession?.direction,
          outgoing ? CallDirection.outgoing : CallDirection.incoming,
        );
        expect(graph.coordinator.activeSession?.isTerminal, isFalse);
        await native.start();
        if (outgoing) {
          expect(
            await native.registerOutgoing(
              _callA,
              expiresAt: graph.coordinator.clock().add(
                const Duration(seconds: 45),
              ),
            ),
            isTrue,
          );
        } else {
          await graph.coordinator.dispatch(
            CallEvent(
              type: CallEventType.incomingValidated,
              eventId: 'name-validated',
              occurredAt: graph.coordinator.clock(),
              callId: _callA,
            ),
          );
          expect(
            await native.present(
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
        }
        expect(updates, [
          {'version': 1, 'callHandle': handle, 'displayName': 'Local contact'},
        ]);
        await graph.updateLockedPresentation(
          _callA,
          presentation('Renamed contact'),
        );
        expect(updates.last, {
          'version': 1,
          'callHandle': handle,
          'displayName': 'Renamed contact',
        });
        expect(updates, hasLength(2));
        await graph.updateLockedPresentation(
          _callB,
          presentation('Stale contact'),
        );
        expect(updates, hasLength(2));
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.appShutdown,
            eventId: 'name-ended',
            occurredAt: graph.coordinator.clock(),
            callId: _callA,
          ),
        );
        await graph.updateLockedPresentation(
          _callA,
          presentation('Ended contact'),
        );
        expect(updates, hasLength(2));
      },
    );
  }

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

  test('production Answer waits for voice capture before accepting', () async {
    final stopGate = Completer<void>();
    var handoffs = 0;
    final captures = MicrophoneCaptureLeaseCoordinator(
      isCaptureActive: () => false,
    );
    late final MicrophoneCaptureLease recordingLease;
    recordingLease = captures.acquire(
      prepareForCall: () async {
        handoffs++;
        await stopGate.future;
        recordingLease.release();
      },
    );
    final fixture = await _createProductionSpeakerRouteFixture(
      microphoneCaptureLeases: captures,
    );
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
          eventId: 'capture-answer-${type.name}',
          occurredAt: graph.coordinator.clock(),
          callId: _callA,
        ),
      );
    }

    final answering = graph.answer(_callA);
    await Future<void>.delayed(Duration.zero);
    expect(handoffs, 1);
    expect(graph.coordinator.activeSession?.state, CallState.ringing);
    stopGate.complete();
    expect(await answering, ForegroundCallActionResult.applied);
    expect(graph.coordinator.activeSession?.state, CallState.accepted);
  });

  setUpAll(sqfliteFfiInit);

  for (final callerRequests in [true, false]) {
    test(
      'BL16-CANCEL two graphs dismiss peer prompt without consuming revision caller=$callerRequests',
      () async {
        final (caller, callerEngine) = await _connectedOutgoingGraphAudio();
        final id = caller.graphs.single.coordinator.activeSession!.callId!;
        final (callee, calleeEngine) = await _connectedGraphVideo(
          acceptedMedia: CallMediaKind.audio,
          callId: id,
        );
        final requester = callerRequests ? caller : callee;
        final responder = callerRequests ? callee : caller;
        final graph = requester.graphs.single;
        final peer = responder.graphs.single;
        final actions = requester.composition as ForegroundCallVideoCapability;
        expect(
          await actions.applyVideoIntent(
            id,
            generation: graph.current!.video!.generation,
            intent: const CallVideoIntent(CallVideoAction.requestVideo),
          ),
          ForegroundCallActionResult.applied,
        );
        await _untilGraphVideo(
          () => _upgradeSignals(requester, 'media_request').isNotEmpty,
        );
        final request = _upgradeSignals(requester, 'media_request').single;
        await _deliverUpgradeSignal(responder, request);
        await _untilGraphVideo(
          () => peer.current!.video!.presentation.incomingUpgradeId != null,
        );
        final requestId = graph.current!.video!.presentation.outgoingUpgradeId!;
        expect(
          await actions.applyVideoIntent(
            id,
            generation: graph.current!.video!.generation,
            intent: CallVideoIntent(
              CallVideoAction.cancelUpgrade,
              upgradeId: requestId,
            ),
          ),
          ForegroundCallActionResult.applied,
        );
        expect(graph.current!.video!.presentation.outgoingUpgradeId, isNull);
        await _untilGraphVideo(
          () => _upgradeSignals(requester, 'media_abort').isNotEmpty,
        );
        final abort = _upgradeSignals(requester, 'media_abort').single;
        expect((abort['payload'] as Map)['media_revision'], 1);
        expect((abort['payload'] as Map)['media'], 'audio');
        await _deliverUpgradeSignal(responder, abort);
        await _untilGraphVideo(
          () => peer.current!.video!.presentation.incomingUpgradeId == null,
        );
        await _untilGraphVideo(
          () => _upgradeSignals(responder, 'media_response').isNotEmpty,
        );
        final decline = _upgradeSignals(responder, 'media_response').single;
        expect((decline['payload'] as Map)['decision'], 'decline');
        await _deliverUpgradeSignal(requester, decline);
        await _untilGraphVideo(
          () => !graph
              .videoOwners![id]!
              .mediaSwitch!
              .machine
              .requiresReconciliation,
        );
        await _deliverUpgradeSignal(responder, abort, mailbox: true);
        await _deliverUpgradeSignal(responder, request, mailbox: true);
        expect(peer.current!.video!.presentation.incomingUpgradeId, isNull);
        for (final owner in [graph, peer]) {
          expect(owner.coordinator.activeSession!.state, CallState.connected);
          expect(
            owner.videoOwners![id]!.mediaSwitch!.machine.settledRevision,
            0,
          );
          expect(
            owner.current!.video!.presentation.status,
            CallVideoStatus.audioOnly,
          );
        }
        expect(callerEngine.video!.cameraStarts, 0);
        expect(calleeEngine.video!.cameraStarts, 0);
        expect(
          await actions.applyVideoIntent(
            id,
            generation: graph.current!.video!.generation,
            intent: const CallVideoIntent(CallVideoAction.requestVideo),
          ),
          ForegroundCallActionResult.applied,
        );
        await _untilGraphVideo(
          () => _upgradeSignals(requester, 'media_request').length == 2,
        );
        expect(
          (_upgradeSignals(requester, 'media_request').last['payload']
              as Map)['base_revision'],
          0,
        );
      },
    );
  }

  for (final callerEnds in [true, false]) {
    for (final boundary in [
      'endpoint',
      'signing',
      'shutdown drain',
      'shutdown terminal',
    ]) {
      test(
        'BL16-TERMINAL ${callerEnds ? "caller" : "callee"} retains delivery after cleanup at $boundary',
        () async {
          final (caller, callerEngine) = await _connectedOutgoingGraphAudio();
          final id = caller.graphs.single.coordinator.activeSession!.callId!;
          final (callee, calleeEngine) = await _connectedGraphVideo(
            acceptedMedia: CallMediaKind.audio,
            callId: id,
          );
          final sender = callerEnds ? caller : callee;
          final peer = callerEnds ? callee : caller;
          final engine = callerEnds ? callerEngine : calleeEngine;
          final graph = sender.graphs.single;
          final held = _holdTerminalAuthorization(
            sender,
            engine,
            boundary.startsWith('shutdown') ? 'endpoint' : boundary,
          );
          sender.p2p.acceptMessages = true;
          final ending = boundary == 'shutdown terminal'
              ? graph.shutdown()
              : graph.end(id).then<void>((result) {
                  expect(result, ForegroundCallActionResult.applied);
                });
          final authorized = await held.entered.future
              .then((_) => true)
              .timeout(const Duration(seconds: 2), onTimeout: () => false);
          if (!authorized) {
            held.entered.complete();
            held.release.complete();
            await ending;
          }
          expect(
            authorized,
            isTrue,
            reason:
                'owned terminal must enter authorization before shutdown closes signaling',
          );
          await _untilGraphVideo(() => graph.coordinator.activeSession == null);
          expect(graph.videoContexts!.read(id), isNull);
          expect(engine.closed, isTrue);
          expect(engine.video!.cameraOn, isFalse);
          expect(held.release.isCompleted, isFalse);
          expect(_terminalTransportIds(sender), isEmpty);
          final shutdown = boundary == 'shutdown drain'
              ? graph.shutdown()
              : null;
          held.release.complete();
          await ending;
          await _untilGraphVideo(
            () => _terminalTransportIds(sender).isNotEmpty,
          );
          await shutdown;
          final wire = _upgradeSignals(sender, 'terminate').single;
          final messageId = wire['message_id'];
          expect(_terminalTransportIds(sender), contains(messageId));
          expect(
            sender.p2p.sentMessages.map(
              (raw) => (jsonDecode(raw) as Map)['message_id'],
            ),
            contains(messageId),
          );
          await _deliverUpgradeSignal(peer, wire, mailbox: !callerEnds);
          await _untilGraphVideo(
            () => peer.graphs.single.coordinator.activeSession == null,
          );
          expect(
            peer.graphs.single.coordinator.lastSnapshot!.endReason,
            boundary == 'shutdown terminal'
                ? CallEndReason.appShutdown
                : CallEndReason.remoteHangup,
          );
        },
      );
    }
  }

  for (final invalidation in [
    'revoked',
    'replaced',
    'successor',
    'successor cleared',
    'closed',
    'expired',
  ]) {
    test('BL16-TERMINAL retained send is fenced by $invalidation', () async {
      var now = 2000000;
      final (fixture, engine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
        clockMs: () => now,
      );
      final graph = fixture.graphs.single;
      final held = _holdTerminalAuthorization(fixture, engine, 'endpoint');
      final ending = graph.end(_callA);
      await held.entered.future.timeout(const Duration(seconds: 2));
      await _untilGraphVideo(() => graph.coordinator.activeSession == null);
      expect(graph.videoContexts!.read(_callA), isNull);
      expect(engine.closed, isTrue);
      if (invalidation == 'revoked') {
        fixture.bridge.responses['call_endpoint_get_v1'] = {
          'ok': true,
          'found': false,
        };
      } else if (invalidation == 'replaced') {
        final response = fixture.bridge.responses['call_endpoint_get_v1']!;
        final endpoint = Map<String, Object?>.from(
          response['endpoint']! as Map,
        );
        endpoint['preferenceEpoch'] = 2;
        final canonical =
            jsonDecode(
                  utf8.decode(
                    base64Decode(response['canonicalRecord']! as String),
                  ),
                )
                as Map<String, dynamic>;
        canonical['preferenceEpoch'] = 2;
        fixture.bridge.responses['call_endpoint_get_v1'] = {
          ...response,
          'endpoint': endpoint,
          'canonicalRecord': base64Encode(utf8.encode(jsonEncode(canonical))),
        };
      } else if (invalidation.startsWith('successor')) {
        await ending;
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.remoteInvite,
            eventId: 'terminal-successor-admitted',
            contactPeerId: 'video-contact',
            remoteAccountPeerId: 'video-contact',
            remoteDeviceId: 'video-contact',
            occurredAt: graph.coordinator.clock(),
            callId: _callB,
          ),
        );
        expect(graph.coordinator.lastSnapshot!.callId, _callB);
        if (invalidation == 'successor cleared') {
          await graph.coordinator.dispatch(
            CallEvent(
              type: CallEventType.remoteTerminate,
              eventId: 'terminal-successor-cleared',
              occurredAt: graph.coordinator.clock(),
              callId: _callB,
            ),
          );
          expect(graph.coordinator.activeSession, isNull);
        }
      } else if (invalidation == 'closed') {
        await graph.shutdown();
      } else {
        now += 60001;
      }
      held.release.complete();
      await ending;
      // Shutdown drains tracked terminal continuations before transport closes.
      await graph.shutdown();
      expect(_terminalTransportIds(fixture), isEmpty);
      expect(_upgradeSignals(fixture, 'terminate'), isEmpty);
    });
  }

  test(
    'BL16-UPGRADE no consent times out both graphs after direct and mailbox duplicate',
    () async {
      final (caller, callerEngine) = await _connectedOutgoingGraphAudio();
      final callerGraph = caller.graphs.single;
      final id = callerGraph.coordinator.activeSession!.callId!;
      final (callee, calleeEngine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
        callId: id,
      );
      final calleeGraph = callee.graphs.single;
      final changes = <CallVideoPresentation>[];
      final sub = calleeGraph.changes.listen((p) {
        if (p?.video != null) changes.add(p!.video!.presentation);
      });
      addTearDown(sub.cancel);
      expect(
        await (caller.composition as ForegroundCallVideoCapability)
            .applyVideoIntent(
              id,
              generation: callerGraph.current!.video!.generation,
              intent: const CallVideoIntent(CallVideoAction.requestVideo),
            ),
        ForegroundCallActionResult.applied,
      );
      await _untilGraphVideo(
        () => _upgradeSignals(caller, 'media_request').isNotEmpty,
      );
      final request = _upgradeSignals(caller, 'media_request').single;
      // Initial invite/offer consumed sequence1/2 in the receiving fixture.
      expect(request['sender_sequence'], greaterThan(2));
      final callerMachine = callerGraph.videoOwners![id]!.mediaSwitch!.machine;
      final originalDeadline = callerMachine.stageDeadlineMs;
      expect(
        originalDeadline! - callerMachine.currentRequest!.createdAtMs,
        15000,
      );
      expect(
        callerMachine.currentRequest!.deadlineMs -
            callerMachine.currentRequest!.createdAtMs,
        30000,
      );
      await _deliverUpgradeSignal(callee, request);
      await _untilGraphVideo(
        () =>
            calleeGraph.current!.video!.presentation.incomingUpgradeId != null,
      );
      final calleeMachine = calleeGraph.videoOwners![id]!.mediaSwitch!.machine;
      final incomingDeadline = calleeMachine.stageDeadlineMs;
      await _deliverUpgradeSignal(callee, request, mailbox: true);
      expect(calleeMachine.stageDeadlineMs, incomingDeadline);
      expect(callerMachine.stageDeadlineMs, originalDeadline);
      expect(calleeMachine.phase, MediaSwitchPhase.decision);
      expect(_upgradeSignals(callee, 'media_response'), isEmpty);
      expect(callerEngine.video!.cameraStarts, 0);
      expect(calleeEngine.video!.cameraStarts, 0);
      // Exercise the production Stopwatch and scheduled15s decision deadline;
      // no fake clock, shortened budget, direct tick, or automatic response.
      await Future<void>.delayed(const Duration(seconds: 16));
      expect(callerMachine.phase, MediaSwitchPhase.declined);
      expect(calleeMachine.phase, MediaSwitchPhase.declined);
      for (final graph in [callerGraph, calleeGraph]) {
        final machine = graph.videoOwners![id]!.mediaSwitch!.machine;
        final presentation = graph.current!.video!.presentation;
        expect(
          machine.currentRequest,
          isNotNull,
          reason: 'retain replay history',
        );
        expect(machine.stageDeadlineMs, isNull);
        expect(machine.settledRevision, 0);
        expect(presentation.agreedMedia, CallMediaKind.audio);
        expect(presentation.incomingUpgradeId, isNull);
        expect(presentation.outgoingUpgradeId, isNull);
        expect(presentation.switchingTo, isNull);
        expect(presentation.status, CallVideoStatus.audioOnly);
        expect(presentation.localCamera, CallCameraState.off);
        expect(presentation.remoteCamera, CallCameraState.off);
        expect(graph.coordinator.activeSession!.state, CallState.connected);
      }
      expect(
        changes.where((p) => p.status == CallVideoStatus.switchingToVideo),
        isEmpty,
      );
      expect(callerEngine.video!.cameraStarts, 0);
      expect(calleeEngine.video!.cameraStarts, 0);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'VUI3b public cancellation projects the actual current outcome',
    () async {
      final (fixture, engine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
      );
      final graph = fixture.graphs.single;
      final actions = fixture.composition as ForegroundCallVideoCapability;
      final observed = <ForegroundCallProjection?>[];
      final subscription = (fixture.composition as ForegroundCallCapability)
          .changes
          .listen(observed.add);
      addTearDown(subscription.cancel);
      expect(
        await actions.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.requestVideo),
        ),
        ForegroundCallActionResult.applied,
      );
      await _untilGraphVideo(
        () => graph.current!.video!.presentation.outgoingUpgradeId != null,
      );
      final request =
          graph.videoOwners![_callA]!.mediaSwitch!.machine.currentRequest!;
      expect(
        await actions.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: CallVideoIntent(
            CallVideoAction.cancelUpgrade,
            upgradeId: request.id,
          ),
        ),
        ForegroundCallActionResult.applied,
      );
      await Future<void>.delayed(Duration.zero);
      final outcome = graph.current!.video!.upgradeOutcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, MediaSwitchOutcomeKind.cancelled);
      expect(outcome.switchId, request.id);
      expect(outcome.baseRevision, request.baseRevision);
      expect(
        observed.any((p) => p?.video?.upgradeOutcome?.switchId == request.id),
        isTrue,
      );
      expect(
        graph.current!.video!.presentation.agreedMedia,
        CallMediaKind.audio,
      );
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      expect(engine.video!.cameraStarts, 0);
    },
  );

  test(
    'VUI3b authenticated explicit decline reaches the requesting graph',
    () async {
      final (requester, requesterEngine) = await _connectedOutgoingGraphAudio();
      final graph = requester.graphs.single;
      final id = graph.coordinator.activeSession!.callId!;
      final (responder, responderEngine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
        callId: id,
      );
      final peer = responder.graphs.single;
      final actions = requester.composition as ForegroundCallVideoCapability;
      expect(
        await actions.applyVideoIntent(
          id,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.requestVideo),
        ),
        ForegroundCallActionResult.applied,
      );
      await _untilGraphVideo(
        () => _upgradeSignals(requester, 'media_request').isNotEmpty,
      );
      final wire = _upgradeSignals(requester, 'media_request').single;
      await _deliverUpgradeSignal(responder, wire);
      await _untilGraphVideo(
        () => peer.current!.video!.presentation.incomingUpgradeId != null,
      );
      final request =
          graph.videoOwners![id]!.mediaSwitch!.machine.currentRequest!;
      expect(
        await (responder.composition as ForegroundCallVideoCapability)
            .applyVideoIntent(
              id,
              generation: peer.current!.video!.generation,
              intent: CallVideoIntent(
                CallVideoAction.declineUpgrade,
                upgradeId: request.id,
              ),
            ),
        ForegroundCallActionResult.applied,
      );
      await _untilGraphVideo(
        () => _upgradeSignals(responder, 'media_response').isNotEmpty,
      );
      final decline = _upgradeSignals(responder, 'media_response').single;
      expect((decline['payload'] as Map)['decision'], 'decline');
      await _deliverUpgradeSignal(requester, decline);
      await _untilGraphVideo(
        () => graph.current!.video!.presentation.outgoingUpgradeId == null,
      );
      final outcome = graph.current!.video!.upgradeOutcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, MediaSwitchOutcomeKind.declined);
      expect(outcome.switchId, request.id);
      expect(outcome.baseRevision, request.baseRevision);
      expect(
        graph.current!.video!.presentation.agreedMedia,
        CallMediaKind.audio,
      );
      expect(
        peer.current!.video!.presentation.agreedMedia,
        CallMediaKind.audio,
      );
      expect(requesterEngine.video!.cameraStarts, 0);
      expect(responderEngine.video!.cameraStarts, 0);
    },
  );

  testWidgets(
    'VUI3b real graph cancellation drives the overlay notice lifetime',
    (tester) async {
      final connected = await tester.runAsync(
        () => _connectedGraphVideo(
          acceptedMedia: CallMediaKind.audio,
          cleanupTimeout: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 5)),
      );
      expect(connected, isNotNull);
      final (fixture, engine) = connected!;
      final graph = fixture.graphs.single;
      final capability = fixture.composition as ForegroundCallCapability;
      final actions = fixture.composition as ForegroundCallVideoCapability;
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
            home: ForegroundCallOverlay(
              capability: capability,
              loadContactDisplayName: (_) async => 'Video contact',
              now: graph.coordinator.clock,
              child: const Scaffold(),
            ),
          ),
        );
        await _pumpCallLifecycle(tester);
        await tester.runAsync(() async {
          expect(
            await actions
                .applyVideoIntent(
                  _callA,
                  generation: graph.current!.video!.generation,
                  intent: const CallVideoIntent(CallVideoAction.requestVideo),
                )
                .timeout(const Duration(seconds: 5)),
            ForegroundCallActionResult.applied,
          );
          await _untilGraphVideo(
            () => graph.current!.video!.presentation.outgoingUpgradeId != null,
          );
        });
        await _pumpCallLifecycle(tester);
        final requestId = graph.current!.video!.presentation.outgoingUpgradeId!;
        await tester.runAsync(() async {
          expect(
            await actions
                .applyVideoIntent(
                  _callA,
                  generation: graph.current!.video!.generation,
                  intent: CallVideoIntent(
                    CallVideoAction.cancelUpgrade,
                    upgradeId: requestId,
                  ),
                )
                .timeout(const Duration(seconds: 5)),
            ForegroundCallActionResult.applied,
          );
        });
        await _pumpCallLifecycle(tester);
        final text = lookupAppLocalizations(const Locale('en'))
            .call_video_request_cancelled;
        expect(find.text(text), findsOneWidget);
        final outcome = graph.current!.video!.upgradeOutcome;
        expect(outcome, isNotNull);
        expect(outcome!.kind, MediaSwitchOutcomeKind.cancelled);
        expect(outcome.switchId, requestId);
        for (final action in ['mute', 'speaker', 'end']) {
          final control = find.bySemanticsIdentifier('call_$action');
          expect(control, findsOneWidget);
          await tester.ensureVisible(control);
          await tester.pump();
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(
          graph.current!.video!.presentation.agreedMedia,
          CallMediaKind.audio,
        );
        expect(graph.coordinator.activeSession!.state, CallState.connected);
        expect(engine.video!.cameraStarts, 0);
        await tester.pump(const Duration(milliseconds: 2999));
        expect(find.text(text), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text(text), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Shutdown crosses real-zone streams and fake-zone subscriptions. Keep
        // both queues moving instead of awaiting it inside runAsync, which
        // prevents the binding from flushing its fake-zone microtasks.
        var shutdownComplete = false;
        Object? shutdownError;
        StackTrace? shutdownStack;
        unawaited(
          fixture.composition.shutdown().then<void>(
            (_) {
              shutdownComplete = true;
            },
            onError: (Object error, StackTrace stack) {
              shutdownError = error;
              shutdownStack = stack;
              shutdownComplete = true;
            },
          ),
        );
        final shutdownDeadline = Stopwatch()..start();
        while (!shutdownComplete &&
            shutdownDeadline.elapsed < const Duration(seconds: 5)) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump();
        expect(
          shutdownComplete,
          isTrue,
          reason: 'VUI3b graph shutdown did not complete within 5 real seconds',
        );
        if (shutdownError != null) {
          Error.throwWithStackTrace(shutdownError!, shutdownStack!);
        }
        await _pumpCallLifecycle(tester);
      }
    },
    timeout: const Timeout.factor(1),
  );

  test(
    'BL16-UPGRADE user cancel clears the retained outgoing request',
    () async {
      final (fixture, engine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
      );
      final graph = fixture.graphs.single;
      final video = fixture.composition as ForegroundCallVideoCapability;
      expect(
        await video.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.requestVideo),
        ),
        ForegroundCallActionResult.applied,
      );
      await _untilGraphVideo(
        () => graph.current!.video!.presentation.outgoingUpgradeId != null,
      );
      final requestId = graph.current!.video!.presentation.outgoingUpgradeId!;
      expect(
        await video.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: CallVideoIntent(
            CallVideoAction.cancelUpgrade,
            upgradeId: requestId,
          ),
        ),
        ForegroundCallActionResult.applied,
      );
      final p = graph.current!.video!.presentation;
      expect(p.status, CallVideoStatus.audioOnly);
      expect(p.switchingTo, isNull);
      expect(p.outgoingUpgradeId, isNull);
      expect(
        graph.videoOwners![_callA]!.mediaSwitch!.machine.currentRequest!.id,
        requestId,
      );
      expect(engine.video!.cameraStarts, 0);
      expect(graph.coordinator.activeSession!.state, CallState.connected);
    },
  );

  for (final phase in [
    MediaSwitchPhase.declined,
    MediaSwitchPhase.aborted,
    MediaSwitchPhase.negotiating,
    MediaSwitchPhase.commit,
    MediaSwitchPhase.acknowledgement,
    MediaSwitchPhase.committed,
  ]) {
    test(
      'BL16-UPGRADE graph projects $phase from retained transaction',
      () async {
        final (fixture, engine) = phase == MediaSwitchPhase.acknowledgement
            ? await _connectedOutgoingGraphAudio()
            : await _connectedGraphVideo(acceptedMedia: CallMediaKind.audio);
        final graph = fixture.graphs.single;
        final id = graph.coordinator.activeSession!.callId!;
        final owner = graph.videoOwners![id]!.mediaSwitch!;
        final machine = owner.machine;
        final now = owner.nowMs();
        const switchId = '77777777-7777-4777-8777-777777777778';
        expect(
          machine
              .request(
                MediaSwitchRequest(
                  id: switchId,
                  baseRevision: 0,
                  target: CallMediaKind.video,
                  requesterIsCaller: true,
                  createdAtMs: now,
                  deadlineMs: now + 30000,
                ),
                freshUpgradeAdmitted: true,
              )
              .accepted,
          isTrue,
        );
        expect(
          machine
              .respond(
                id: switchId,
                baseRevision: 0,
                fromCaller: false,
                response: phase == MediaSwitchPhase.declined
                    ? MediaSwitchResponse.decline
                    : MediaSwitchResponse.accept,
              )
              .accepted,
          isTrue,
        );
        if (phase == MediaSwitchPhase.commit ||
            phase == MediaSwitchPhase.acknowledgement ||
            phase == MediaSwitchPhase.committed) {
          for (final description in MediaSwitchDescription.values) {
            expect(
              machine
                  .descriptionApplied(
                    id: switchId,
                    revision: 1,
                    media: CallMediaKind.video,
                    description: description,
                    local: description == MediaSwitchDescription.offer
                        ? machine.localIsCaller
                        : !machine.localIsCaller,
                  )
                  .accepted,
              isTrue,
            );
          }
        }
        if (phase == MediaSwitchPhase.committed) {
          expect(
            machine
                .receiveCommit(
                  id: switchId,
                  revision: 1,
                  media: CallMediaKind.video,
                )
                .accepted,
            isTrue,
          );
        } else if (phase == MediaSwitchPhase.aborted) {
          expect(
            machine
                .abort(
                  id: switchId,
                  baseRevision: 0,
                  revision: 1,
                  reason: MediaSwitchAbortReason.cancelled,
                )
                .accepted,
            isTrue,
          );
        }
        expect(machine.phase, phase);
        await graph.onResume();
        final p = graph.current!.video!.presentation;
        final active =
            phase == MediaSwitchPhase.negotiating ||
            phase == MediaSwitchPhase.commit ||
            phase == MediaSwitchPhase.acknowledgement;
        expect(p.switchingTo, active ? CallMediaKind.video : null);
        expect(
          p.agreedMedia,
          phase == MediaSwitchPhase.committed
              ? CallMediaKind.video
              : CallMediaKind.audio,
        );
        expect(p.incomingUpgradeId, isNull);
        expect(p.outgoingUpgradeId, isNull);
        expect(p.localCamera, CallCameraState.off);
        expect(engine.video!.cameraStarts, 0);
        expect(machine.currentRequest!.id, switchId);
      },
    );
  }

  for (final enabled in [false, true]) {
    test(
      'U3j-G signed endpoint advertises video only when enabled=$enabled',
      () async {
        final fixture = await _createProductionIosFixture(
          privacyFlags: {'video_call_v2_enabled': enabled},
        );
        await fixture.composition.start();
        final record =
            fixture.bridge.requests.singleWhere(
                  (r) => r['cmd'] == 'call_endpoint_set_v1',
                )['payload']
                as Map;
        expect(
          record['capabilities'],
          enabled ? ['video_call_v2', 'voice_call_v1'] : ['voice_call_v1'],
        );
        expect(record['signature'], isNotEmpty);
        expect(
          fixture.capabilityArguments.single['video'],
          enabled ? true : null,
        );
      },
    );
  }

  test(
    'U3j-G background during microphone prompt cancels video admission',
    () async {
      final permission = Completer<MicPermissionStatus>();
      final microphone = _VideoEntryMicrophonePermission(gate: permission);
      addTearDown(() {
        if (!permission.isCompleted) {
          permission.complete(MicPermissionStatus.denied);
        }
      });
      final fixture = await _createProductionIosFixture(
        microphonePermission: microphone,
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(
        fixture,
        'video-contact',
        video: true,
      );
      final Object capability = fixture.composition;
      expect(capability, isA<OutgoingVideoCallCapability>());
      final video = capability as OutgoingVideoCallCapability;
      final pending = video.startOutgoingVideoCall('video-contact');
      await _untilComposition(() => microphone.requests == 1);
      await fixture.composition.onBackgrounded();
      permission.complete(MicPermissionStatus.granted);
      expect(await pending, OutgoingCallStartResult.canceled);
      expect(video.isOutgoingVideoCallAvailable, isFalse);
      expect(fixture.graphs.single.coordinator.activeSession, isNull);
      expect(
        fixture.bridge.commands.where((c) => c == 'message.encrypt'),
        isEmpty,
      );
    },
  );

  test(
    'U3j-G refreshed endpoint can withdraw passive video availability',
    () async {
      final fixture = await _createProductionIosFixture(
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(
        fixture,
        'video-contact',
        video: true,
      );
      final Object capability = fixture.composition;
      expect(capability, isA<OutgoingVideoCallCapability>());
      final video = capability as OutgoingVideoCallCapability;
      expect(
        await video.isOutgoingVideoCallAvailableFor('video-contact'),
        isTrue,
      );
      final response = fixture.bridge.responses['call_endpoint_get_v1']!;
      final endpoint = Map<String, Object?>.from(response['endpoint']! as Map);
      endpoint['capabilities'] = ['voice_call_v1'];
      final canonical = Map<String, Object?>.from(endpoint)
        ..remove('signature');
      fixture.bridge.responses['call_endpoint_get_v1'] = {
        ...response,
        'endpoint': endpoint,
        'canonicalRecord': base64Encode(utf8.encode(jsonEncode(canonical))),
      };
      expect(
        await video.isOutgoingVideoCallAvailableFor('video-contact'),
        isFalse,
      );
      expect(fixture.graphs.single.coordinator.activeSession, isNull);
    },
  );

  test(
    'U3j-G authenticated incoming video projects choice without capture',
    () async {
      var engineBuilds = 0;
      final fixture = await _createProductionIosFixture(
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
        callEngineFactory: (_) {
          engineBuilds++;
          return _ProductionSpeakerRouteEngine(const []);
        },
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(
        fixture,
        'video-contact',
        video: true,
      );
      await _deliverGraphVideoInvite(fixture);
      final graph = fixture.graphs.single;
      final video = graph.current!.video;
      expect(video, isNotNull);
      expect(video!.presentation.requestedMedia, CallMediaKind.video);
      expect(video.presentation.acceptedMedia, isNull);
      expect(video.presentation.localCamera, CallCameraState.off);
      expect(video.localView, isNull);
      expect(video.remoteView, isNull);
      expect(engineBuilds, 0);
      final Object capability = fixture.composition;
      expect(capability, isA<ForegroundCallVideoCapability>());
      expect(
        await (capability as ForegroundCallVideoCapability).applyVideoIntent(
          _callA,
          generation: video.generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        ),
        ForegroundCallActionResult.unavailable,
      );
      expect(capability, isA<ForegroundCallMediaAnswerCapability>());
      final stale = await (capability as ForegroundCallMediaAnswerCapability)
          .answerWithMedia(
            _callA,
            generation: video.generation + 1,
            acceptedMedia: CallMediaKind.video,
          );
      expect(stale, ForegroundCallActionResult.unavailable);
      expect(fixture.lifecycleMethods, isNot(contains('answer')));
      expect(fixture.lifecycleMethods, isNot(contains('setLocalCameraActive')));
      expect(graph.coordinator.activeSession!.state, CallState.ringing);
    },
  );

  for (final media in CallMediaKind.values) {
    test(
      'U3j-G explicit incoming ${media.name} choice waits for native journal',
      () async {
        final fixture = await _createProductionIosFixture(
          microphonePermission: const _GrantedCallMicrophonePermission(),
          outgoingContactAccountPeerId: 'video-contact',
          privacyFlags: const {'video_call_v2_enabled': true},
        );
        await fixture.composition.start();
        await _configureCancellationEndpoint(
          fixture,
          'video-contact',
          video: true,
        );
        await _deliverGraphVideoInvite(fixture);
        final graph = fixture.graphs.single;
        final video = graph.current!.video;
        expect(video, isNotNull);
        final Object capability = fixture.composition;
        expect(capability, isA<ForegroundCallMediaAnswerCapability>());
        final result = await (capability as ForegroundCallMediaAnswerCapability)
            .answerWithMedia(
              _callA,
              generation: video!.generation,
              acceptedMedia: media,
            );
        expect(result, ForegroundCallActionResult.applied);
        expect(fixture.lifecycleMethods, contains('answer'));
        expect(graph.coordinator.activeSession!.state, CallState.ringing);
        expect(graph.current!.video!.presentation.acceptedMedia, isNull);
        expect(
          fixture.lifecycleMethods,
          isNot(contains('setLocalCameraActive')),
        );
        final signals = fixture.bridge.requests
            .where((r) => r['cmd'] == 'message.encrypt')
            .map(
              (r) =>
                  jsonDecode((r['payload'] as Map)['plaintext'] as String)
                      as Map,
            );
        expect(signals.where((s) => s['event'] == 'accept'), isEmpty);
      },
    );
  }

  for (final choice in ['video', 'audio', 'native-audio']) {
    test(
      'U3j-G native journal emits the selected v2 accept media choice=$choice',
      () async {
        final events = StreamController<Object?>.broadcast(sync: true);
        addTearDown(events.close);
        var audioActive = false;
        final engines = <_InitialVideoGraphEngine>[];
        final fixture = await _createProductionIosFixture(
          microphonePermission: const _GrantedCallMicrophonePermission(),
          outgoingContactAccountPeerId: 'video-contact',
          privacyFlags: const {'video_call_v2_enabled': true},
          lifecycleEventStream: events.stream,
          callEngineFactory: (_) {
            final engine = _InitialVideoGraphEngine();
            engines.add(engine);
            return engine;
          },
          lifecycleOverride: (method, _) async {
            if (method == 'activateAudio') audioActive = true;
            if (method == 'deactivateAudio' || method == 'end') {
              audioActive = false;
            }
            if (method == 'readAudioState') {
              return {
                'version': 1,
                'active': audioActive,
                'muted': false,
                'route': 'system_default',
                'availableRoutes': ['system_default', 'speaker'],
              };
            }
            return null;
          },
        );
        await fixture.composition.start();
        await _configureCancellationEndpoint(
          fixture,
          'video-contact',
          video: true,
        );
        final wallNow = DateTime.now().millisecondsSinceEpoch;
        final credentials = <String, Object?>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': ['turn:relay.invalid:3478?transport=udp'],
          'username': 'fixture-user',
          'password': 'fixture-secret',
          'ttlSeconds': 600,
          'serverTimeMs': wallNow,
          'expiresAtMs': wallNow + 600000,
        };
        fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
        fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] =
            credentials;
        await _deliverGraphVideoInvite(fixture);
        final graph = fixture.graphs.single;
        expect(graph.current!.video, isNotNull);
        if (choice != 'native-audio') {
          final Object capability = fixture.composition;
          expect(capability, isA<ForegroundCallMediaAnswerCapability>());
          expect(
            await (capability as ForegroundCallMediaAnswerCapability)
                .answerWithMedia(
                  _callA,
                  generation: graph.current!.video!.generation,
                  acceptedMedia: choice == 'video'
                      ? CallMediaKind.video
                      : CallMediaKind.audio,
                ),
            ForegroundCallActionResult.applied,
          );
        }
        const handle = '33333333-3333-4333-8333-333333333333';
        events.add({
          'version': 1,
          'descriptor': {
            'callHandle': handle,
            'expiresAtMs': 2040000,
            'presented': true,
            'phase': 'journal',
            'direction': 'incoming',
          },
          'nativeCallId': handle,
          'highestSequence': 2,
          'events': [
            {
              'callHandle': handle,
              'sequence': 1,
              'eventId': '55555555-5555-4555-8555-555555555555',
              'type': 'presented',
              'occurredAtMs': 2000000,
            },
            {
              'callHandle': handle,
              'sequence': 2,
              'eventId': '66666666-6666-4666-8666-666666666666',
              'type': 'answer',
              'occurredAtMs': 2000001,
            },
          ],
        });
        List<Map> accepts() => fixture.bridge.requests
            .where((r) => r['cmd'] == 'message.encrypt')
            .map(
              (r) =>
                  jsonDecode((r['payload'] as Map)['plaintext'] as String)
                      as Map,
            )
            .where((s) => s['event'] == 'accept')
            .toList();
        await _untilComposition(
          () =>
              accepts().isNotEmpty ||
              graph.coordinator.activeSession?.isTerminal == true,
        );
        expect(accepts(), hasLength(1));
        expect(accepts().single['schema'], CallSignalV2.schema);
        expect(
          (accepts().single['payload'] as Map)['media'],
          choice == 'video' ? 'video' : 'audio',
        );
        expect((accepts().single['payload'] as Map)['camera'], 'off');
        expect(engines, hasLength(1));
        expect(
          engines.single.binds,
          0,
          reason:
              'Answer prepares audio; only an authenticated offer binds v2 SDP',
        );
        expect(engines.single.configuration!.captureVideo, isFalse);
        expect(
          fixture.lifecycleMethods.where((m) => m == 'setLocalCameraActive'),
          isEmpty,
        );
      },
    );
  }

  for (final platform in [
    CallEndpointPlatform.ios,
    CallEndpointPlatform.android,
  ]) {
    test(
      'CAM-READY permission pending publishes disabled controls on ${platform.name}',
      () async {
        final permission = Completer<bool>();
        var requests = 0;
        final (fixture, engine) = await _connectedGraphVideo(
          platform: platform,
          permission: () {
            requests++;
            return permission.future;
          },
        );
        final graph = fixture.graphs.single;
        final video =
            (fixture.composition as Object) as ForegroundCallVideoCapability;
        final generation = graph.current!.video!.generation;
        final published = <CallVideoPresentation>[];
        final subscription = graph.changes.listen((projection) {
          final presentation = projection?.video?.presentation;
          if (presentation != null) published.add(presentation);
        });
        addTearDown(subscription.cancel);
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final first = video.applyVideoIntent(
          _callA,
          generation: generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        );
        try {
          await _untilComposition(() => requests == 1);
          expect(
            published.any(
              (p) =>
                  p.videoActionPending &&
                  !p.isAvailable(CallVideoAction.turnCameraOn),
            ),
            isTrue,
            reason:
                'The UI must receive the pending state before permission completes',
          );
          expect(engine.video!.cameraStarts, 0);
          expect(
            await video.applyVideoIntent(
              _callA,
              generation: generation,
              intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
            ),
            ForegroundCallActionResult.unavailable,
          );
          expect(requests, 1);
          permission.complete(true);
          expect(await first, ForegroundCallActionResult.applied);
          expect(engine.video!.cameraStarts, 1);
          expect(published.last.videoActionPending, isFalse);
          expect(published.last.localCamera, CallCameraState.on);
          final taps = flow
              .where((e) => e['event'] == 'CALL_CAMERA_TAP')
              .map((e) => e['details'] as Map)
              .toList();
          expect(taps.map((e) => e['outcome']), [
            'pending',
            'refused',
            'accepted',
          ]);
          expect(taps.map((e) => e['reason']), [
            'actionStarted',
            'actionPending',
            'completed',
          ]);
          for (final tap in taps) {
            expect(tap.keys.toSet(), {'action', 'outcome', 'reason'});
            expect(tap['action'], 'turnCameraOn');
          }
        } finally {
          if (!permission.isCompleted) permission.complete(false);
          await first;
        }
      },
    );
  }

  test('CAM-READY stale generation logs refusal before permission', () async {
    var requests = 0;
    final (fixture, engine) = await _connectedGraphVideo(
      permission: () async {
        requests++;
        return true;
      },
    );
    final graph = fixture.graphs.single;
    final flow = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flow.add);
    addTearDown(() => debugSetFlowEventSink(null));
    final video =
        (fixture.composition as Object) as ForegroundCallVideoCapability;
    expect(
      await video.applyVideoIntent(
        _callA,
        generation: graph.current!.video!.generation - 1,
        intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
      ),
      ForegroundCallActionResult.unavailable,
    );
    expect(requests, 0);
    expect(engine.video!.cameraStarts, 0);
    final taps = flow.where((e) => e['event'] == 'CALL_CAMERA_TAP').toList();
    expect(taps, hasLength(1));
    expect(taps.single['details'], {
      'action': 'turnCameraOn',
      'outcome': 'refused',
      'reason': 'staleOwner',
    });
  });

  test(
    'CAM-READY diagnostic failures cannot change explicit camera consent',
    () async {
      final (fixture, engine) = await _connectedGraphVideo();
      final graph = fixture.graphs.single;
      var attempts = 0;
      debugSetFlowEventSink((event) {
        if (event['event'] == 'CALL_CAMERA_TAP') {
          attempts++;
          throw StateError('fixture diagnostic sink');
        }
      });
      addTearDown(() => debugSetFlowEventSink(null));
      final video =
          (fixture.composition as Object) as ForegroundCallVideoCapability;
      expect(
        await video.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        ),
        ForegroundCallActionResult.applied,
      );
      expect(engine.video!.cameraStarts, 1);
      expect(attempts, 2);
    },
  );

  for (final platform in [
    CallEndpointPlatform.ios,
    CallEndpointPlatform.android,
  ]) {
    test(
      'U3j-G explicit camera consent captures once on ${platform.name}',
      () async {
        var permissions = 0;
        final leases = <bool>[];
        final (fixture, engine) = await _connectedGraphVideo(
          platform: platform,
          permission: () async {
            permissions++;
            return true;
          },
          nativeOverride: (method, args) async {
            if (method == 'setLocalCameraActive') {
              leases.add(args['active']! as bool);
            }
            return null;
          },
        );
        final graph = fixture.graphs.single;
        final Object capability = fixture.composition;
        expect(capability, isA<ForegroundCallVideoCapability>());
        final video = capability as ForegroundCallVideoCapability;
        expect(permissions, 0);
        expect(engine.video!.cameraStarts, 0);
        final generation = graph.current!.video!.generation;
        expect(
          await video.applyVideoIntent(
            _callA,
            generation: generation,
            intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
          ),
          ForegroundCallActionResult.applied,
        );
        expect(permissions, 1);
        expect(engine.video!.cameraStarts, 1);
        expect(engine.binds, 1);
        expect(engine.video!.cameraOn, isTrue);
        expect(graph.current!.video!.localView, isNotNull);
        expect(
          leases.where((v) => v),
          platform == CallEndpointPlatform.android ? [true] : isEmpty,
        );
        expect(
          await video.applyVideoIntent(
            _callA,
            generation: generation,
            intent: const CallVideoIntent(CallVideoAction.switchCamera),
          ),
          ForegroundCallActionResult.applied,
        );
        expect(permissions, 1);
        expect(engine.video!.cameraStarts, 1);
        expect(engine.video!.cameraSwitches, 1);
        expect(engine.video!.readsBeforeSubscription, 0);
      },
    );
  }

  test(
    'U3j-G background fences a late camera permission without capture',
    () async {
      final gate = Completer<bool>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete(false);
      });
      var permissions = 0;
      final (fixture, engine) = await _connectedGraphVideo(
        permission: () {
          permissions++;
          return gate.future;
        },
      );
      final graph = fixture.graphs.single;
      final video =
          (fixture.composition as Object) as ForegroundCallVideoCapability;
      final pending = video.applyVideoIntent(
        _callA,
        generation: graph.current!.video!.generation,
        intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
      );
      await _untilComposition(() => permissions == 1);
      await fixture.composition.onBackgrounded();
      gate.complete(true);
      expect(await pending, ForegroundCallActionResult.unavailable);
      expect(engine.video!.cameraStarts, 0);
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      await fixture.composition.onResume();
      expect(engine.video!.cameraStarts, 0);
      expect(permissions, 1);
    },
  );

  test('U3j-G Android refused camera lease cannot start capture', () async {
    final (fixture, engine) = await _connectedGraphVideo(
      platform: CallEndpointPlatform.android,
      nativeOverride: (method, args) async =>
          method == 'setLocalCameraActive' && args['active'] == true
          ? false
          : null,
    );
    final graph = fixture.graphs.single;
    final video =
        (fixture.composition as Object) as ForegroundCallVideoCapability;
    final result = await video.applyVideoIntent(
      _callA,
      generation: graph.current!.video!.generation,
      intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
    );
    expect(result.status, ForegroundCallActionStatus.unavailable);
    expect(result.cameraFailure, ForegroundCallCameraFailure.unavailable);
    expect(engine.video!.cameraStarts, 0);
    expect(graph.coordinator.activeSession!.state, CallState.connected);
  });

  test(
    'U3j-G background releases Android lease before slow capture cleanup',
    () async {
      final leases = <bool>[];
      final (fixture, engine) = await _connectedGraphVideo(
        platform: CallEndpointPlatform.android,
        nativeOverride: (method, args) async {
          if (method == 'setLocalCameraActive') {
            leases.add(args['active']! as bool);
          }
          return null;
        },
      );
      final graph = fixture.graphs.single;
      final video =
          (fixture.composition as Object) as ForegroundCallVideoCapability;
      expect(
        await video.applyVideoIntent(
          _callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        ),
        ForegroundCallActionResult.applied,
      );
      final cleanup = Completer<bool>();
      engine.video!.stopGate = cleanup;
      addTearDown(() {
        if (!cleanup.isCompleted) cleanup.complete(true);
      });
      await fixture.composition.onBackgrounded();
      expect(engine.video!.cameraOn, isFalse);
      await _untilComposition(() => leases.isNotEmpty && leases.last == false);
      expect(cleanup.isCompleted, isFalse);
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      cleanup.complete(true);
    },
  );

  test(
    'U3j-G remote track replacement republishes owner views without another engine',
    () async {
      final (fixture, engine) = await _connectedGraphVideo();
      final graph = fixture.graphs.single;
      engine.video!.replaceRemoteTrack();
      await _untilComposition(() => graph.current!.video!.remoteView != null);
      final first = graph.current!.video!.remoteView!.textureId;
      engine.video!.replaceRemoteTrack();
      await _untilComposition(
        () => graph.current!.video!.remoteView?.textureId != first,
      );
      expect(
        engine.video!.attachments.where(
          (s) => s == CallVideoRendererSlot.remote,
        ),
        hasLength(2),
      );
      expect(engine.video!.readsBeforeSubscription, 0);
      expect(engine.binds, 1);
      expect(engine.video!.cameraStarts, 0);
    },
  );

  test('U3j-G stale generation refuses camera before permission', () async {
    var permissions = 0;
    final (fixture, engine) = await _connectedGraphVideo(
      permission: () async {
        permissions++;
        return true;
      },
    );
    final graph = fixture.graphs.single;
    final video =
        (fixture.composition as Object) as ForegroundCallVideoCapability;
    expect(
      await video.applyVideoIntent(
        _callA,
        generation: graph.current!.video!.generation + 1,
        intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
      ),
      ForegroundCallActionResult.unavailable,
    );
    expect(permissions, 0);
    expect(engine.video!.cameraStarts, 0);
  });

  test(
    'U3j-G sole candidate listener routes v2 ICE with no legacy duplicate',
    () async {
      final (fixture, engine) = await _connectedGraphVideo();
      expect(engine.eventSubscriptions, 1);
      expect(engine.candidateSubscriptions, 1);
      engine.candidateController.add(
        const CallIceCandidate(
          value: 'fixture-candidate',
          mediaId: 'video',
          mediaLineIndex: 1,
        ),
      );
      List<Map> ice() => fixture.bridge.requests
          .where((r) => r['cmd'] == 'message.encrypt')
          .map(
            (r) =>
                jsonDecode((r['payload'] as Map)['plaintext'] as String) as Map,
          )
          .where((s) => s['event'] == 'ice')
          .toList();
      await _untilGraphVideo(() => ice().isNotEmpty);
      expect(ice(), hasLength(1));
      expect(ice().single['schema'], CallSignalV2.schema);
      expect(
        (ice().single['payload'] as Map)['negotiation_id'],
        engine.video!.token!.negotiationId,
      );
      expect(engine.binds, 1);
    },
  );

  for (final caller in [true, false]) {
    test(
      'BL26-HA v1 ${caller ? 'caller' : 'callee'} completes recovery within shared lookup ceiling',
      () async {
        final (fixture, engine) = await _connectedLegacyRecovery(
          caller: caller,
        );
        final graph = fixture.graphs.single;
        final id = graph.coordinator.activeSession!.callId!;
        final response = fixture.bridge.responses['call_endpoint_get_v1']!;
        var lookups = 0;
        fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) async {
          lookups++;
          return response;
        };
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.mediaLost,
            eventId: 'bl26-v1-loss',
            occurredAt: graph.coordinator.clock(),
            callId: id,
          ),
        );
        if (caller) {
          await _untilGraphVideo(
            () => _upgradeSignals(
              fixture,
              'offer',
            ).any((signal) => signal['ice_generation'] == 1),
          );
          await _deliverLegacyRecovery(fixture, CallSignalType.answer, 80, 1, {
            'description': 'fixture-recovery-answer',
            'fingerprint': _ProcessLossEngine._fingerprint,
          });
        } else {
          await _untilGraphVideo(
            () => _upgradeSignals(fixture, 'ice_restart').isNotEmpty,
          );
          await _deliverLegacyRecovery(
            fixture,
            CallSignalType.iceRestart,
            80,
            1,
            {},
          );
          await _untilGraphVideo(() => engine.restarts == 1);
          await _deliverLegacyRecovery(fixture, CallSignalType.offer, 81, 1, {
            'description': 'fixture-recovery-offer',
            'fingerprint': _ProcessLossEngine._fingerprint,
          });
          await _untilGraphVideo(
            () => _upgradeSignals(
              fixture,
              'answer',
            ).any((signal) => signal['ice_generation'] == 1),
          );
        }
        await _untilGraphVideo(() => engine.remoteDescriptions == 2);
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.mediaRecovered,
            eventId: 'bl26-v1-recovered',
            occurredAt: graph.coordinator.clock(),
            callId: id,
            reconnectGeneration:
                graph.coordinator.activeSession!.reconnectGeneration,
          ),
        );
        expect(graph.coordinator.activeSession!.state, CallState.connected);
        expect(engine.restarts, 1);
        expect(engine.localDescriptions, 2);
        expect(lookups, greaterThan(0));
        expect(lookups, lessThanOrEqualTo(3));
        expect(graph.videoContexts!.read(id)!.wireVersion, CallWireVersion.v1);
      },
    );
  }

  test(
    'BL26-HA caller recovery caps remote lookup across fresh authorization',
    () async {
      final (fixture, engine) = await _connectedOutgoingGraphAudio();
      engine.video!.recoveryReconciliation =
          CallVideoSdpReconciliationOutcome.alreadyStable;
      final graph = fixture.graphs.single;
      final id = graph.coordinator.activeSession!.callId!;
      final response = fixture.bridge.responses['call_endpoint_get_v1']!;
      var lookups = 0;
      fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) async {
        lookups++;
        return response;
      };
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.mediaLost,
          eventId: 'bl26-ha-caller-transport-loss',
          occurredAt: graph.coordinator.clock(),
          callId: id,
        ),
      );
      await _untilGraphVideo(
        () => _upgradeSignals(
          fixture,
          'offer',
        ).any((signal) => signal['ice_generation'] == 1),
      );
      final offer = _upgradeSignals(
        fixture,
        'offer',
      ).singleWhere((signal) => signal['ice_generation'] == 1);
      await _deliverUpgradeSignal(fixture, {
        'schema': CallSignalV2.schema,
        'call_id': id.value,
        'message_id': '00000000-0000-4000-8000-000000000081',
        'event': 'answer',
        'sender_sequence': 80,
        'ice_generation': 1,
        'created_at_ms': 2000000,
        'expires_at_ms': 2015000,
        'payload': Map<String, Object?>.from(offer['payload'] as Map),
      });
      await _untilGraphVideo(() => engine.video!.commits == 2);
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.mediaRecovered,
          eventId: 'bl26-ha-caller-recovered',
          occurredAt: graph.coordinator.clock(),
          callId: id,
          reconnectGeneration:
              graph.coordinator.activeSession!.reconnectGeneration,
        ),
      );
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      expect(engine.restarts, 1);
      expect(lookups, greaterThan(0));
      expect(
        lookups,
        lessThanOrEqualTo(3),
        reason:
            'One recovery episode shares the remote ceiling across all authorization passes',
      );
    },
  );

  test(
    'BL26-HA callee recovery caps remote lookup across fresh authorization',
    () async {
      final (fixture, engine) = await _connectedGraphVideo(
        acceptedMedia: CallMediaKind.audio,
      );
      engine.video!.recoveryReconciliation =
          CallVideoSdpReconciliationOutcome.alreadyStable;
      final graph = fixture.graphs.single;
      final id = graph.coordinator.activeSession!.callId!;
      final response = fixture.bridge.responses['call_endpoint_get_v1']!;
      var lookups = 0;
      fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) async {
        lookups++;
        return response;
      };
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.mediaLost,
          eventId: 'bl26-ha-callee-transport-loss',
          occurredAt: graph.coordinator.clock(),
          callId: id,
        ),
      );
      await _untilGraphVideo(
        () => _upgradeSignals(fixture, 'ice_restart').isNotEmpty,
      );
      const negotiation = '88888888-8888-4888-8888-888888888888';
      Map<String, dynamic> remote(
        String event,
        int sequence,
        Map<String, Object?> payload,
      ) => {
        'schema': CallSignalV2.schema,
        'call_id': id.value,
        'message_id': '00000000-0000-4000-8000-00000000008$sequence',
        'event': event,
        'sender_sequence': 80 + sequence,
        'ice_generation': 1,
        'created_at_ms': 2000000,
        'expires_at_ms': 2015000,
        'payload': payload,
      };
      await _deliverUpgradeSignal(
        fixture,
        remote('ice_restart', 2, {
          'negotiation_id': negotiation,
          'media_revision': 0,
        }),
      );
      await _untilGraphVideo(() => engine.restarts == 1);
      await _deliverUpgradeSignal(
        fixture,
        remote('offer', 3, {
          'negotiation_id': negotiation,
          'purpose': 'ice_restart',
          'switch_id': null,
          'media_revision': 0,
          'media': 'audio',
          'description': 'fixture-sdp',
          'fingerprint': 'fixture-fingerprint',
        }),
      );
      await _untilGraphVideo(() => engine.video!.commits == 2);
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.mediaRecovered,
          eventId: 'bl26-ha-callee-recovered',
          occurredAt: graph.coordinator.clock(),
          callId: id,
          reconnectGeneration:
              graph.coordinator.activeSession!.reconnectGeneration,
        ),
      );
      expect(graph.coordinator.activeSession!.state, CallState.connected);
      expect(
        _upgradeSignals(
          fixture,
          'answer',
        ).where((signal) => signal['ice_generation'] == 1),
        hasLength(1),
      );
      expect(engine.restarts, 1);
      expect(lookups, greaterThan(0));
      expect(
        lookups,
        lessThanOrEqualTo(3),
        reason:
            'The callee request and answer share one episode lookup ceiling',
      );
    },
  );

  test(
    'BL26-HA stalled caller endpoint releases restart within lookup slice',
    () async {
      final (fixture, engine) = await _connectedOutgoingGraphAudio();
      engine.video!.recoveryReconciliation =
          CallVideoSdpReconciliationOutcome.alreadyStable;
      final graph = fixture.graphs.single;
      final id = graph.coordinator.activeSession!.callId!;
      final response = fixture.bridge.responses['call_endpoint_get_v1']!;
      final held = Completer<Map<String, Object?>>();
      var lookups = 0;
      fixture.bridge.responseHandlers['call_endpoint_get_v1'] = (_) {
        lookups++;
        return held.future;
      };
      try {
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.mediaLost,
            eventId: 'bl26-ha-stalled-caller-transport-loss',
            occurredAt: graph.coordinator.clock(),
            callId: id,
          ),
        );
        await _untilGraphVideo(() => lookups > 0);
        // Real SQLite composition requires its native event loop. The exact 2s
        // boundary is a unit contract; this allows scheduling overhead while
        // distinguishing it from the authority client's existing 10s wait.
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(
          engine.restarts,
          1,
          reason:
              'The admitted endpoint must become usable after a typed slice timeout and fresh local checks',
        );
        expect(graph.coordinator.activeSession!.state, CallState.reconnecting);
        expect(lookups, lessThanOrEqualTo(3));
      } finally {
        fixture.bridge.responseHandlers.remove('call_endpoint_get_v1');
        await fixture.composition.end(id);
        final restartsAtEnd = engine.restarts;
        final writesAtEnd = _upgradeSignals(fixture, 'offer').length;
        held.complete(response);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(engine.restarts, restartsAtEnd);
        expect(_upgradeSignals(fixture, 'offer').length, writesAtEnd);
      }
    },
  );

  test(
    'U3j-G reconnect observer runs after capture revocation and keeps one bundle',
    () async {
      _InitialVideoGraphEngine? engine;
      final cameraAtObserver = <bool>[];
      final (fixture, connectedEngine) = await _connectedGraphVideo(
        timerObserver: (id, kind, scheduledAt, requested, effective) {
          if (kind == CallTimeoutKind.reconnect) {
            expect(id, _callA);
            expect(effective, lessThanOrEqualTo(requested));
            cameraAtObserver.add(engine!.video!.cameraOn);
            throw StateError(
              'external observer cannot interrupt owned recovery',
            );
          }
        },
      );
      engine = connectedEngine;
      final graph = fixture.graphs.single;
      final generation = graph.current!.video!.generation;
      final capability =
          (fixture.composition as Object) as ForegroundCallVideoCapability;
      expect(
        await capability.applyVideoIntent(
          _callA,
          generation: generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        ),
        ForegroundCallActionResult.applied,
      );
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.audioInterrupted,
          eventId: 'graph-video-focus-loss',
          occurredAt: graph.coordinator.clock(),
          callId: _callA,
        ),
      );
      expect(cameraAtObserver, [false]);
      expect(graph.coordinator.activeSession!.state, CallState.reconnecting);
      expect(graph.current!.video!.generation, generation);
      expect(engine.binds, 1);
      expect(engine.eventSubscriptions, 1);
      expect(engine.candidateSubscriptions, 1);
    },
  );

  test('U3j-G terminal call fences a late camera permission', () async {
    final permission = Completer<bool>();
    addTearDown(() {
      if (!permission.isCompleted) permission.complete(false);
    });
    var requested = false;
    final (fixture, engine) = await _connectedGraphVideo(
      permission: () {
        requested = true;
        return permission.future;
      },
    );
    final graph = fixture.graphs.single;
    final capability =
        (fixture.composition as Object) as ForegroundCallVideoCapability;
    final pending = capability.applyVideoIntent(
      _callA,
      generation: graph.current!.video!.generation,
      intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
    );
    await _untilGraphVideo(() => requested);
    expect(
      await fixture.composition.end(_callA),
      ForegroundCallActionResult.applied,
    );
    permission.complete(true);
    expect(await pending, ForegroundCallActionResult.unavailable);
    expect(engine.video!.cameraStarts, 0);
    expect(graph.current, isNull);
  });

  test(
    'U3j-G disabled video entry has no permission or endpoint effects',
    () async {
      final microphone = _VideoEntryMicrophonePermission();
      final fixture = await _createProductionIosFixture(
        microphonePermission: microphone,
        outgoingContactAccountPeerId: 'video-contact',
      );
      await fixture.composition.start();
      final Object capability = fixture.composition;
      expect(capability, isA<OutgoingVideoCallCapability>());
      final video = capability as OutgoingVideoCallCapability;
      final prior = fixture.bridge.requests.length;
      expect(video.isOutgoingVideoCallAvailable, isFalse);
      expect(
        await video.isOutgoingVideoCallAvailableFor('video-contact'),
        isFalse,
      );
      expect(
        await video.startOutgoingVideoCall('video-contact'),
        OutgoingCallStartResult.unavailable,
      );
      expect(microphone.requests, 0);
      expect(fixture.bridge.requests, hasLength(prior));
      expect(fixture.graphs.single.coordinator.activeSession, isNull);
      expect(fixture.capabilityArguments.single.containsKey('video'), isFalse);
    },
  );

  for (final supported in [false, true]) {
    test(
      'U3j-G passive video availability uses fresh signed capabilities video=$supported',
      () async {
        final microphone = _VideoEntryMicrophonePermission();
        var engineBuilds = 0;
        final fixture = await _createProductionIosFixture(
          microphonePermission: microphone,
          outgoingContactAccountPeerId: 'video-contact',
          privacyFlags: const {'video_call_v2_enabled': true},
          callEngineFactory: (_) {
            engineBuilds++;
            return _ProductionSpeakerRouteEngine(const []);
          },
        );
        await fixture.composition.start();
        await _configureCancellationEndpoint(
          fixture,
          'video-contact',
          video: supported,
        );
        final Object capability = fixture.composition;
        expect(capability, isA<OutgoingVideoCallCapability>());
        final video = capability as OutgoingVideoCallCapability;
        expect(video.isOutgoingVideoCallAvailable, isTrue);
        for (var attempt = 0; attempt < 2; attempt++) {
          expect(
            await video.isOutgoingVideoCallAvailableFor('video-contact'),
            supported,
          );
        }
        expect(
          fixture.bridge.commands.where((c) => c == 'call_endpoint_get_v1'),
          hasLength(2),
        );
        expect(microphone.requests, 0);
        expect(engineBuilds, 0);
        expect(fixture.graphs.single.coordinator.activeSession, isNull);
      },
    );
  }

  for (final mode in [
    'legacy',
    'enabled-legacy',
    'enabled-audio',
    'explicit-video',
  ]) {
    final mutations = mode == 'enabled-audio' || mode == 'explicit-video'
        ? [
            'none',
            'preference',
            'capability',
            'expired',
            'signature',
            'cancelled',
          ]
        : ['none'];
    for (final mutation in mutations) {
      test(
        mutation == 'none'
            ? 'U3j-G production invitation preserves explicit media choice mode=$mode'
            : 'B9-U1 admission refuses changed $mutation endpoint mode=$mode',
        () async {
          final request = OutgoingCallStartRequest();
          var cameraPermissionRequests = 0;
          var endpointLookups = 0;
          String? registeredHandle;
          int? registeredExpiresAt;
          late final _ProductionIosFixture fixture;
          fixture = await _createProductionIosFixture(
            microphonePermission: const _GrantedCallMicrophonePermission(),
            outgoingContactAccountPeerId: 'video-contact',
            privacyFlags: {'video_call_v2_enabled': mode != 'legacy'},
            requestCameraPermission: () async {
              cameraPermissionRequests++;
              return true;
            },
            // Preflight refresh rotates the short fixture grant. Model delivery
            // of the current replacement instead of trusting the old receipt.
            ensureOutgoingCallWakeAuthority: (peer) async {
              final issued = await fixture.issuedCallWakeHandleStore
                  .readForContact(peer);
              return issued != null &&
                  await fixture.graphs.single.markCallWakeHandleDistributed(
                    peer,
                    issued.grant,
                  );
            },
            lifecycleOverride: (method, arguments) async {
              if (method == 'registerOutgoingAuthenticated') {
                registeredHandle = arguments['callHandle']! as String;
                registeredExpiresAt = arguments['expiresAtMs']! as int;
                return true;
              }
              if (method == 'attach' && registeredHandle != null) {
                return <String, Object?>{
                  'version': 1,
                  'descriptor': <String, Object?>{
                    'callHandle': registeredHandle,
                    'expiresAtMs': registeredExpiresAt,
                    'presented': true,
                    'phase': 'preStart',
                    'direction': 'outgoing',
                  },
                  'nativeCallId': registeredHandle,
                  'highestSequence': 1,
                  'events': [
                    <String, Object?>{
                      'callHandle': registeredHandle,
                      'sequence': 1,
                      'eventId': '00000000-0000-4000-8000-000000000001',
                      'type': 'presented',
                      'occurredAtMs': 2_000_000,
                    },
                  ],
                };
              }
              return null;
            },
          );
          await fixture.composition.start();
          await _configureCancellationEndpoint(
            fixture,
            'video-contact',
            video: mode != 'enabled-legacy',
          );
          if (mutation != 'none') {
            final original = Map<String, Object?>.from(
              fixture.bridge.responses['call_endpoint_get_v1']!,
            );
            fixture.bridge.responseHandlers['call_endpoint_get_v1'] =
                (_) async {
                  endpointLookups++;
                  if (mutation == 'cancelled') request.cancel();
                  if (endpointLookups == 1) return original;
                  if (mutation == 'signature') {
                    fixture.bridge.responses['payload.verify'] = {
                      'ok': true,
                      'valid': false,
                    };
                  }
                  final record = Map<String, dynamic>.from(
                    jsonDecode(
                      utf8.decode(
                        base64Decode(original['canonicalRecord']! as String),
                      ),
                    ) as Map,
                  );
                  if (mutation == 'preference') record['preferenceEpoch'] = 2;
                  if (mutation == 'capability') {
                    record['capabilities'] = ['voice_call_v1'];
                  }
                  if (mutation == 'expired') record['expiresAtMs'] = 2_000_000;
                  return {
                    ...original,
                    'canonicalRecord': base64Encode(
                      utf8.encode(jsonEncode(record)),
                    ),
                    'endpoint': {...record, 'signature': 'c2lnbmF0dXJl'},
                  };
                };
          }
          final Future<OutgoingCallStartResult> starting;
          if (mode == 'explicit-video') {
            final Object capability = fixture.composition;
            expect(capability, isA<OutgoingVideoCallCapability>());
            starting = (capability as OutgoingVideoCallCapability)
                .startOutgoingVideoCall('video-contact', request: request);
          } else {
            starting = fixture.composition.startOutgoingCall(
              'video-contact',
              request: request,
            );
          }
          final outcome = await starting;
          if (mutation == 'none') {
            expect(outcome, OutgoingCallStartResult.started);
          }
          final invitations = fixture.bridge.requests
              .where((r) => r['cmd'] == 'message.encrypt')
              .map(
                (r) =>
                    jsonDecode((r['payload'] as Map)['plaintext'] as String)
                        as Map,
              )
              .where((r) => r['event'] == 'invite')
              .toList();
          expect(cameraPermissionRequests, 0);
          expect(
            fixture.lifecycleMethods.where((m) => m == 'setLocalCameraActive'),
            isEmpty,
          );
          if (mutation != 'none') {
            if (mutation == 'cancelled') {
              expect(outcome, OutgoingCallStartResult.canceled);
              expect(endpointLookups, 1);
            } else {
              expect(endpointLookups, greaterThanOrEqualTo(2));
            }
            expect(invitations, isEmpty);
            return;
          }
          expect(invitations, hasLength(1));
          final invite = invitations.single;
          expect(
            invite['schema'],
            mode == 'explicit-video' || mode == 'enabled-audio'
                ? 'mknoon.call_signal.v2'
                : 'mknoon.call_signal.v1',
          );
          final payload = invite['payload'] as Map;
          if (mode == 'explicit-video' || mode == 'enabled-audio') {
            expect(
              payload['media'],
              mode == 'explicit-video' ? 'video' : 'audio',
            );
            expect(payload['camera'], 'off');
            final graph = fixture.graphs.single;
            final context = graph.videoContexts!.read(
              graph.coordinator.activeSession!.callId!,
            )!;
            expect(context.wireVersion, CallWireVersion.v2);
            expect(
              context.requestedMedia,
              mode == 'explicit-video' ? CallMediaKind.video : CallMediaKind.audio,
            );
            expect(context.initialAcceptedMedia, isNull);
          } else {
            expect(payload.containsKey('media'), isFalse);
            expect(payload.containsKey('camera'), isFalse);
          }
          expect(
            fixture.lifecycleMethods.where((m) => m == 'setLocalCameraActive'),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'U3j-G unsupported video endpoint cannot fall back to an audio invite',
    () async {
      final fixture = await _createProductionIosFixture(
        microphonePermission: const _GrantedCallMicrophonePermission(),
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(fixture, 'video-contact');
      final Object capability = fixture.composition;
      expect(capability, isA<OutgoingVideoCallCapability>());
      expect(
        await (capability as OutgoingVideoCallCapability)
            .startOutgoingVideoCall('video-contact'),
        isNot(OutgoingCallStartResult.started),
      );
      expect(
        fixture.bridge.commands.where((c) => c == 'message.encrypt'),
        isEmpty,
      );
      expect(fixture.graphs.single.coordinator.activeSession, isNull);
    },
  );

  test(
    'U3j-G canceled video permission wait cannot admit an invitation',
    () async {
      final permission = Completer<MicPermissionStatus>();
      addTearDown(() {
        if (!permission.isCompleted) {
          permission.complete(MicPermissionStatus.denied);
        }
      });
      final microphone = _VideoEntryMicrophonePermission(gate: permission);
      final fixture = await _createProductionIosFixture(
        microphonePermission: microphone,
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(
        fixture,
        'video-contact',
        video: true,
      );
      final Object capability = fixture.composition;
      expect(capability, isA<OutgoingVideoCallCapability>());
      final request = OutgoingCallStartRequest();
      final pending = (capability as OutgoingVideoCallCapability)
          .startOutgoingVideoCall('video-contact', request: request);
      await _untilComposition(() => microphone.requests == 1);
      request.cancel();
      permission.complete(MicPermissionStatus.granted);
      expect(await pending, OutgoingCallStartResult.canceled);
      expect(
        fixture.bridge.commands.where((c) => c == 'message.encrypt'),
        isEmpty,
      );
      expect(fixture.graphs.single.coordinator.activeSession, isNull);
    },
  );

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

  for (final boundary in ['microphone', 'capability', 'wake']) {
    test(
      'cancel during $boundary preflight fences late completion and allows retry',
      () async {
        final reached = Completer<void>();
        final release = Completer<void>();
        var shouldBlock = true;
        Future<void> block(String stage) async {
          if (stage != boundary || !shouldBlock) return;
          if (!reached.isCompleted) reached.complete();
          await release.future;
        }

        var advertisements = 0;
        final graph = _Graph(<String>[])
          ..onAdvertise = () async {
            if (advertisements++ > 0) await block('capability');
            return true;
          };
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.android,
          awaitReadiness: () async {},
          requestOutgoingMicrophonePermission: () async {
            await block('microphone');
            return MicPermissionStatus.granted;
          },
          ensureOutgoingCallWakeAuthority: (_) async {
            await block('wake');
            return true;
          },
          buildGraph: () async => graph,
        );
        await composition.start();
        addTearDown(composition.shutdown);
        final request = OutgoingCallStartRequest();
        final pending = composition.startOutgoingCall(
          'canceled-peer',
          request: request,
        );
        await reached.future;
        request.cancel();
        shouldBlock = false;
        expect(
          await composition.startOutgoingCall('next-peer'),
          OutgoingCallStartResult.started,
        );
        release.complete();
        expect(await pending, OutgoingCallStartResult.canceled);
        expect(graph.outgoingPeerIds, ['next-peer']);
      },
    );
  }

  test(
    'outgoing microphone refusal is typed while adapter failure stays generic',
    () async {
      for (final permissionStatus in <MicPermissionStatus>[
        MicPermissionStatus.denied,
        // The shared gateway folds the platform restricted state into this
        // value because neither can be re-prompted in-app.
        MicPermissionStatus.permanentlyDenied,
      ]) {
        final graph = _Graph(<String>[]);
        var permissionRequests = 0;
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.ios,
          awaitReadiness: () async {},
          requestOutgoingMicrophonePermission: () async {
            permissionRequests++;
            return permissionStatus;
          },
          buildGraph: () async => graph,
        );
        await composition.start();

        expect(
          await composition.startOutgoingCall('peer-$permissionStatus'),
          OutgoingCallStartResult.microphoneDenied,
        );
        expect(graph.outgoingPeerIds, isEmpty);
        expect(permissionRequests, 1);
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
    },
  );

  test('canceling preflight wins over a late microphone denial', () async {
    final permission = Completer<MicPermissionStatus>();
    final graph = _Graph(<String>[]);
    var permissionRequests = 0;
    final composition = CallSignalingComposition(
      featureFlags: _enabledFlags(),
      platform: CallEndpointPlatform.android,
      awaitReadiness: () async {},
      requestOutgoingMicrophonePermission: () {
        permissionRequests++;
        return permission.future;
      },
      buildGraph: () async => graph,
    );
    addTearDown(composition.shutdown);
    await composition.start();
    final request = OutgoingCallStartRequest();
    final pending = composition.startOutgoingCall('peer', request: request);
    expect(permissionRequests, 1);
    request.cancel();
    permission.complete(MicPermissionStatus.denied);
    expect(await pending, OutgoingCallStartResult.canceled);
    expect(graph.outgoingPeerIds, isEmpty);
    expect(request.isAdmitted, isFalse);
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
          expect(
            first.events.where((event) => event == 'call_shutdown'),
            hasLength(1),
          );
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

  for (final heldBoundary in ['cancel', 'detach']) {
    test(
      'replacement preserves native Answer after old $heldBoundary completes',
      () async {
        const handle = '33333333-3333-4333-8333-333333333333';
        final entered = Completer<void>();
        final release = Completer<void>();
        final firstClosed = Completer<void>();
        final nativeStreams = <StreamController<Object?>>[];
        final coordinators = <CallCoordinator>[];
        final adapters = <AndroidCallLifecycleAdapter>[];
        final graphs = <_Graph>[];
        final acknowledgements = <Map<String, Object?>>[];
        var nativeAttached = false;
        var detachCalls = 0;
        Future<void> holdFirst(int index, String boundary) async {
          if (index == 0 && boundary == heldBoundary) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          // onCancel and detach both clear this engine's current native sink.
          nativeAttached = false;
        }

        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.android,
          awaitReadiness: () async {},
          isForeground: () => true,
          buildGraph: () async {
            final index = graphs.length;
            final native = StreamController<Object?>(
              sync: true,
              onCancel: () => holdFirst(index, 'cancel'),
            );
            nativeStreams.add(native);
            final coordinator = CallCoordinator(
              reducer: const CallReducer(),
              cleanupCoordinator: CallCleanupCoordinator(const []),
              historyProjector: CallHistoryProjector(
                _UnusedCallHistoryRepository(),
              ),
              clock: () => _callNow,
              idSource: () => _callA,
            );
            coordinators.add(coordinator);
            final adapter = AndroidCallLifecycleAdapter(
              coordinator: coordinator,
              resolveAuthenticatedHandle: (_) => handle,
              clock: () => _callNow,
              nativeEvents: native.stream,
              invokeMethod: (method, arguments) async {
                if (method == 'attach') {
                  nativeAttached = true;
                  return const <String, Object?>{
                    'version': 1,
                    'descriptor': null,
                    'events': <Object?>[],
                    'nativeCallId': null,
                    'highestSequence': 0,
                  };
                }
                if (method == 'detach') {
                  detachCalls++;
                  await holdFirst(index, 'detach');
                }
                if (method == 'acknowledge') {
                  acknowledgements.add(Map.of(arguments));
                }
                return true;
              },
            );
            adapters.add(adapter);
            final graph = _Graph(
              <String>[],
              onStart: adapter.start,
              onShutdown: (_) async {
                await adapter.close();
                if (index == 0) firstClosed.complete();
              },
            );
            graphs.add(graph);
            return graph;
          },
        );
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await composition.shutdown();
          for (final coordinator in coordinators) {
            await coordinator.dispose();
          }
          for (final native in nativeStreams) {
            await native.close();
          }
        });
        await composition.start();
        graphs.single.callabilityInvalidationsController.add(null);
        await entered.future;
        final replacement = composition.start();
        final resumed = composition.onResume();
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        final buildsWhileOldOwnerHeld = graphs.length;
        release.complete();
        await Future.wait([replacement, resumed, firstClosed.future]);
        expect(graphs, hasLength(2));
        expect(detachCalls, 1);
        expect(
          nativeAttached,
          isTrue,
          reason: 'Old native cleanup must precede replacement attach',
        );
        expect(buildsWhileOldOwnerHeld, 1);

        final coordinator = coordinators.last;
        await coordinator.dispatch(
          CallEvent(
            type: CallEventType.remoteInvite,
            eventId: 'replacement-invite',
            occurredAt: _callNow,
            callId: _callA,
            contactPeerId: 'remote-account',
            localAccountPeerId: 'local-account',
            localDeviceId: 'local-device',
            remoteAccountPeerId: 'remote-account',
            remoteDeviceId: 'remote-device',
            expiresAt: _callNow.add(const Duration(seconds: 45)),
            transportRoute: CallRouteClass.direct,
          ),
        );
        await coordinator.dispatch(
          CallEvent(
            type: CallEventType.incomingValidated,
            eventId: 'replacement-validated',
            occurredAt: _callNow,
            callId: _callA,
            contactPeerId: 'remote-account',
          ),
        );
        expect(
          await adapters.last.present(
            IncomingCallPresentation(
              callId: _callA,
              callerAccountPeerId: 'remote-account',
              expiresAt: _callNow.add(const Duration(seconds: 45)),
            ),
          ),
          isTrue,
        );
        void emit(int sequence, String type) {
          if (!nativeAttached) return;
          nativeStreams.last.add(<String, Object?>{
            'version': 1,
            'descriptor': <String, Object?>{
              'callHandle': handle,
              'expiresAtMs': _callNow
                  .add(const Duration(seconds: 45))
                  .millisecondsSinceEpoch,
              'presented': true,
              'phase': sequence == 1 ? 'preStart' : 'journal',
              'direction': 'incoming',
            },
            'events': <Object?>[
              <String, Object?>{
                'callHandle': handle,
                'sequence': sequence,
                'eventId': '00000000-0000-4000-8000-00000000000$sequence',
                'type': type,
                'occurredAtMs': _callNow.millisecondsSinceEpoch,
              },
            ],
            'nativeCallId': handle,
            'highestSequence': sequence,
          });
        }

        emit(1, 'presented');
        await _untilComposition(
          () => acknowledgements.any(
            (ack) =>
                ack['throughSequence'] == 1 && ack['disposition'] == 'ADOPTED',
          ),
        );
        await coordinator.dispatch(
          CallEvent(
            type: CallEventType.systemUiPresented,
            eventId: 'replacement-presented',
            occurredAt: _callNow,
            callId: _callA,
            contactPeerId: 'remote-account',
          ),
        );
        expect(coordinator.activeSession?.state, CallState.ringing);
        expect(await adapters.last.answerNatively(_callA), isTrue);
        emit(2, 'answer');
        await _untilComposition(
          () => coordinator.activeSession?.state == CallState.accepted,
        );
        expect(
          acknowledgements.where((ack) => ack['throughSequence'] == 1),
          hasLength(1),
        );
      },
    );
  }

  for (final queueReplacement in [false, true]) {
    test(
      'shutdown waits for withdrawn owner with queued replacement=$queueReplacement',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final graph = _Graph(
          <String>[],
          onShutdown: (_) async {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          },
        );
        var builds = 0;
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.android,
          awaitReadiness: () async {},
          buildGraph: () async {
            builds++;
            return graph;
          },
          isForeground: () => true,
        );
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await composition.shutdown();
        });
        await composition.start();
        graph.callabilityInvalidationsController.add(null);
        await entered.future;
        final queuedStart = queueReplacement
            ? composition.start()
            : Future<void>.value();
        var shutdownCompleted = false;
        final shutdown = composition.shutdown().then(
          (_) => shutdownCompleted = true,
        );
        final repeatedShutdown = composition.shutdown();
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(shutdownCompleted, isFalse);
        expect(builds, 1);
        release.complete();
        await Future.wait([queuedStart, shutdown, repeatedShutdown]);
        await composition.start();
        expect(builds, 1);
        expect(composition.isStarted, isFalse);
        expect(
          graph.events.where((event) => event == 'call_shutdown'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'failed graph withdrawal forbids replacement on indeterminate native owner',
    () async {
      final graph = _Graph(
        <String>[],
        advertisementResults: const [true, false],
        onShutdown: (_) => throw StateError('private native close failure'),
      );
      var builds = 0;
      final composition = CallSignalingComposition(
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async {
          builds++;
          return graph;
        },
        isForeground: () => true,
      );
      await composition.start();
      await composition.onResume();
      await composition.start();
      await composition.onResume();
      await composition.shutdown();
      expect(builds, 1);
      expect(composition.isStarted, isFalse);
      expect(composition.isOutgoingCallAvailable, isFalse);
      expect(
        graph.events.where((event) => event == 'call_shutdown'),
        hasLength(1),
      );
    },
  );

  for (final boundary in ['listener', 'advertisement']) {
    for (final terminal in [false, true]) {
      test(
        '${terminal ? 'shutdown' : 'invalidation'} fences late startup $boundary',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          Future<void> hold() async {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }

          final first = _Graph(
            <String>[],
            onStart: boundary == 'listener' ? hold : null,
          );
          if (boundary == 'advertisement') {
            first.onAdvertise = () async {
              await hold();
              return true;
            };
          }
          final second = _Graph(<String>[]);
          var builds = 0;
          final composition = CallSignalingComposition(
            featureFlags: _enabledFlags(),
            platform: CallEndpointPlatform.android,
            awaitReadiness: () async {},
            buildGraph: () async => builds++ == 0 ? first : second,
            isForeground: () => true,
          );
          addTearDown(() async {
            if (!release.isCompleted) release.complete();
            await composition.shutdown();
          });
          final starting = composition.start();
          await entered.future;
          Future<void>? shutdown;
          if (terminal) {
            shutdown = composition.shutdown();
          } else {
            first.callabilityInvalidationsController.add(null);
            await _untilComposition(
              () => first.events.contains('call_shutdown'),
            );
          }
          release.complete();
          await starting;
          await shutdown;
          expect(composition.isStarted, isFalse);
          expect(composition.isOutgoingCallAvailable, isFalse);
          expect(
            first.events.where((event) => event == 'call_shutdown'),
            hasLength(1),
          );
          if (boundary == 'listener') {
            expect(first.events, isNot(contains('advertise')));
          }
          await composition.start();
          expect(builds, terminal ? 1 : 2);
          expect(composition.isStarted, !terminal);
        },
      );
    }
  }

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
      await expectLater(
        composition.present(presentation),
        throwsA(isA<IncomingCallPresentationUnavailable>()),
      );
      foreground = true;
      expect(await composition.present(presentation), isTrue);
      expect(composition.current, same(validated));

      await composition.dismiss(presentation);
      expect(composition.current, isNull);

      // O1 (beta 2026-10-08): after onBackgrounded the app cannot ring;
      // this must read as unavailable, not as a failed presentation.
      await composition.onBackgrounded();
      graph.emitForeground(validated);
      await expectLater(
        composition.present(presentation),
        throwsA(isA<IncomingCallPresentationUnavailable>()),
      );
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
    'failed start diagnostic names the error type without its message',
    () async {
      // A swallowed start failure used to leave only `outcome: failed` and
      // the stage, so a device failure at listenerInstallation was opaque.
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final failures = <({Object error, Map<String, dynamic> expected})>[
        (
          error: StateError('private listener detail'),
          expected: <String, dynamic>{'errorType': 'StateError'},
        ),
        (
          error: PlatformException(
            code: 'call_native_unavailable',
            message: 'private native detail',
          ),
          expected: <String, dynamic>{
            'errorType': 'PlatformException',
            'errorCode': 'call_native_unavailable',
          },
        ),
      ];
      for (final failure in failures) {
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: CallEndpointPlatform.android,
          awaitReadiness: () async {},
          buildGraph: () async =>
              _Graph(<String>[], onStart: () async => throw failure.error),
        );
        await composition.start();

        final details =
            flow.lastWhere(
                  (event) => event['event'] == 'CALL_SIGNALING_START_RESULT',
                )['details']!
                as Map<String, dynamic>;
        expect(details['outcome'], 'failed');
        expect(details['stage'], 'listenerInstallation');
        expect(
          details,
          containsPair('errorType', failure.expected['errorType']),
        );
        expect(details['errorCode'], failure.expected['errorCode']);
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

  for (final platform in [
    CallEndpointPlatform.android,
    CallEndpointPlatform.ios,
  ]) {
    test(
      '${platform.name} call wake drains the call mailbox on a started graph',
      () async {
        final events = <String>[];
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final composition = CallSignalingComposition(
          featureFlags: _enabledFlags(),
          platform: platform,
          awaitReadiness: () async => events.add('readiness'),
          buildGraph: () async => _Graph(events),
        );
        await composition.start();
        expect(composition.isStarted, isTrue);
        events.clear();

        if (platform == CallEndpointPlatform.android) {
          final channel = AndroidCallWakeChannel(
            onCallWake: composition.onCallWake,
          );
          await channel.install();
          addTearDown(channel.dispose);
          const wire = StandardMethodCodec();
          final reply = await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                AndroidCallWakeChannel.channelName,
                wire.encodeMethodCall(
                  const MethodCall(AndroidCallWakeChannel.wakeMethod),
                ),
                (_) {},
              );
          expect(wire.decodeEnvelope(reply!), isTrue);
        } else {
          await composition.onCallWake();
        }

        expect(events, <String>['call_mailbox_drain']);
        expect(composition.isStarted, isTrue);
        final wake = flowEvents
            .where((event) => event['event'] == 'CALL_SIGNALING_WAKE_RESULT')
            .toList(growable: false);
        expect(wake, hasLength(1));
        expect(wake.single['details'], containsPair('outcome', 'drained'));
        await composition.shutdown();
      },
    );
  }

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
      addTearDown(p2p.states.close);
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
        secureKeyStore: FakeSecureKeyStore(),
        featureFlags: _enabledFlags(),
        platform: CallEndpointPlatform.android,
        database: database,
        bridge: bridge,
        p2pService: p2p,
        messageRouter: router,
        loadIdentity: () async => identity,
        callTransportStartupWait: const Duration(seconds: 2),
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

      final starting = composition.start();
      await Future<void>.delayed(Duration.zero);

      expect(composition.isStarted, isFalse);
      expect(bridge.commands, isEmpty);

      p2p.updateState(
        const NodeState(peerId: 'local-account', isStarted: true),
      );
      await starting;
      expect(composition.isStarted, isTrue);
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
      var tokenValue = 'fcm-token-fixture';
      final tokenRead = Completer<void>();
      final composition = createProductionCallSignalingComposition(
        secureKeyStore: FakeSecureKeyStore(),
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
              readToken: () async {
                await tokenRead.future;
                return tokenValue;
              },
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
      final resumed = composition.onResume();

      // Beta O6 (2026-10-08): the slow token publication (about 2 s on a
      // cold start) must not hold back the mailbox drain that delivers a
      // pending invite.
      for (
        var i = 0;
        i < 50 && !bridge.commands.contains('call_retrieve_v1');
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(bridge.commands, contains('call_retrieve_v1'));
      expect(bridge.commands, isNot(contains('call_token_set_v1')));
      expect(bridge.commands, isNot(contains('call_endpoint_set_v1')));

      tokenRead.complete();
      await resumed;

      expect(
        bridge.commands,
        containsAllInOrder(<String>[
          'call_retrieve_v1',
          'call_token_set_v1',
          'payload.sign',
          'call_endpoint_set_v1',
        ]),
      );
      expect(
        bridge.commands.where((command) => command == 'call_token_set_v1'),
        hasLength(greaterThanOrEqualTo(2)),
        reason: 'advertisements restore tokens revoked after a failed wake',
      );
      final publication = bridge.requests.firstWhere(
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
        everyElement('published'),
        reason: 'every later advertisement renews the token on the relay',
      );

      final tokenSetsBefore = bridge.requests
          .where((request) => request['cmd'] == 'call_token_set_v1')
          .length;
      final endpointSetsBefore = bridge.commands
          .where((command) => command == 'call_endpoint_set_v1')
          .length;
      tokenValue = 'rotated-fcm-token-fixture';
      await resumeCallSignalingAndBackfillCallWake(
        resumeCallSignaling: composition.onResume,
        reconcileCallWakeEligibility: composition.onContactEligibilityChanged,
        hasPendingCallWakeDistribution: () async => false,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async => 0,
      );
      final refreshedTokens = bridge.requests
          .where((request) => request['cmd'] == 'call_token_set_v1')
          .skip(tokenSetsBefore)
          .toList();
      expect(refreshedTokens, hasLength(1));
      expect(
        refreshedTokens.single['payload'],
        containsPair('token', tokenValue),
      );
      expect(
        bridge.commands.where((command) => command == 'call_endpoint_set_v1'),
        hasLength(endpointSetsBefore + 1),
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
        secureKeyStore: FakeSecureKeyStore(),
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
      final publishedNames = <String>[];
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
        secureKeyStore: FakeSecureKeyStore(),
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
                if (method == 'publishOpaqueContact') {
                  publishedNames.add(arguments['displayName']! as String);
                }
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

      expect(publishedNames, isNotEmpty);
      expect(publishedNames, everyElement('Alice'));
      for (final invalidName in [' ', 'remote-account']) {
        await database.update(
          'contacts',
          {'username': invalidName},
          where: 'peer_id = ?',
          whereArgs: ['remote-account'],
        );
        final eligible = await graph.loadWakeEligibleContacts();
        expect(eligible, hasLength(1));
        expect(eligible.single.displayName, 'Mknoon call');
        expect(
          await graph.wakeAuthorizationCoordinator.reconcile(
            eligibleContacts: eligible,
            localRecipientDevicePeerId: graph.localIdentity.peerId,
            localDeviceKeyEpoch: graph.localDeviceKeyEpoch,
          ),
          isTrue,
        );
        expect(publishedNames.last, 'Mknoon call');
      }

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

  for (final cancelPreflight in [false, true]) {
    test(
      'production fences endpoint wait before invite (canceled: $cancelPreflight)',
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

        final request = OutgoingCallStartRequest();
        final outgoing = graph.startOutgoingCall(
          contactAccountPeerId,
          request: request,
        );
        await endpointRequested.future;
        if (cancelPreflight) {
          request.cancel();
        } else {
          await fixture.issuedCallWakeHandleStore.write(
            issued.copyWith(distributionPending: true),
          );
        }
        releaseEndpoint.complete(endpointResponse);

        expect(
          await outgoing,
          cancelPreflight
              ? OutgoingCallStartResult.canceled
              : OutgoingCallStartResult.unavailable,
        );
        expect(graph.coordinator.activeSession, isNull);
        expect(graph.coordinator.lastSnapshot, isNull);
      },
    );
  }

  test(
    'local callback generation reaches production graph admission and preserves admitted busy call',
    () async {
      const contact = 'remote-account';
      final issued = _GatedIssuedWakeStore(_newCallWakeStores().issued);
      late final _ProductionIosFixture fixture;
      fixture = await _createProductionIosFixture(
        outgoingContactAccountPeerId: contact,
        issuedStore: issued,
        privacyFlags: {'voice_call_ios_native_enabled': false},
        microphonePermission: const _GrantedCallMicrophonePermission(),
        ensureOutgoingCallWakeAuthority: (peer) async {
          final record = await issued.readForContact(peer);
          if (record == null) return false;
          return fixture.graphs.single.markCallWakeHandleDistributed(
            peer,
            record.grant,
          );
        },
      );
      await fixture.composition.start();
      await _configureCancellationEndpoint(fixture, contact);
      final graph = fixture.graphs.single;
      final repository = graph.coordinator.historyProjector.repository;
      final history = CallHistoryConversationTimelineSource(repository);
      final stamp = graph.coordinator.clock().subtract(
        const Duration(minutes: 1),
      );
      CallHistoryEntry missed(CallId id, int micros) => CallHistoryEntry(
        callId: id,
        contactAccountPeerId: contact,
        direction: CallDirection.incoming,
        status: CallHistoryStatus.missed,
        terminalReason: CallEndReason.noAnswer,
        startedAt: stamp.add(Duration(microseconds: micros)),
        connectedAt: null,
        endedAt: stamp.add(const Duration(seconds: 30)),
        transportRoute: null,
        createdAt: stamp.add(const Duration(seconds: 30)),
        updatedAt: stamp.add(const Duration(seconds: 30)),
      );
      await repository.upsertTerminal(missed(_callA, 0));
      final results = <OutgoingCallStartResult>[];
      final handler = CallBackActionHandler(
        history: () => history,
        ready: () async => true,
        redial: CallRedialController(
          capability: () => fixture.composition,
          contactAllowed: (_) async => true,
        ),
        onResult: results.add,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      issued.holdNextRead = () async {
        entered.complete();
        await release.future;
      };
      final a = handler.submit(_callA);
      await entered.future.timeout(const Duration(seconds: 2));
      expect(graph.coordinator.activeSession, isNull);
      await repository.upsertTerminal(missed(_callB, 1));
      final b = handler.submit(_callB);
      release.complete();
      await Future.wait([a, b]);
      expect(results, [
        OutgoingCallStartResult.canceled,
        OutgoingCallStartResult.started,
      ]);
      final admitted = graph.coordinator.activeSession!;
      expect(admitted.callId, isNot(anyOf(_callA, _callB)));
      expect(admitted.state, CallState.inviting);
      expect(
        fixture.bridge.requests.where((r) => r['cmd'] == 'call_store_v1'),
        hasLength(1),
      );
      final third = CallId.parse('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
      await repository.upsertTerminal(missed(third, 2));
      await handler.submit(third);
      expect(results.last, OutgoingCallStartResult.unavailable);
      expect(graph.coordinator.activeSession?.callId, admitted.callId);
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);
      expect(
        fixture.bridge.requests.where((r) => r['cmd'] == 'call_store_v1'),
        hasLength(1),
      );
      await handler.submit(_callA);
      await handler.submit(_callB);
      expect(graph.coordinator.activeSession?.callId, admitted.callId);
    },
  );

  for (final boundary in <String>[
    'native reconciliation',
    'final wake authority',
  ]) {
    test('production cancellation fences $boundary before admission', () async {
      const contact = 'remote-account';
      const oldHandle = '33333333-3333-4333-8333-333333333333';
      const nowMs = 2_000_000;
      final nativeEvents = StreamController<Object?>.broadcast(sync: true);
      final issued = _GatedIssuedWakeStore(_newCallWakeStores().issued);
      final entered = Completer<void>();
      final release = Completer<void>();
      var terminalAckAllowed = false;
      var holdTerminalAck = false;
      var terminalAckCount = 0;
      var terminalAcksBeforeWait = 0;
      final registrations = <String>[];
      Map<String, Object?>? latestBatch;
      Map<String, Object?> batch(
        String handle, {
        bool terminal = false,
        bool outgoing = false,
      }) => <String, Object?>{
        'version': 1,
        'descriptor': <String, Object?>{
          'callHandle': handle,
          'expiresAtMs': nowMs + 45_000,
          'presented': true,
          'phase': terminal ? 'journal' : 'preStart',
          'direction': outgoing ? 'outgoing' : 'incoming',
        },
        'events': <Object?>[
          <String, Object?>{
            'callHandle': handle,
            'sequence': 1,
            'eventId': '55555555-5555-4555-8555-555555555555',
            'type': 'presented',
            'occurredAtMs': nowMs,
          },
          if (terminal)
            <String, Object?>{
              'callHandle': handle,
              'sequence': 2,
              'eventId': '66666666-6666-4666-8666-666666666666',
              'type': 'remoteCancelled',
              'occurredAtMs': nowMs,
            },
        ],
        'nativeCallId': handle,
        'highestSequence': terminal ? 2 : 1,
      };
      if (boundary == 'native reconciliation') latestBatch = batch(oldHandle);
      final fixture = await _createProductionIosFixture(
        nativePlatform: CallEndpointPlatform.android,
        issuedStore: issued,
        lifecycleEventStream: nativeEvents.stream,
        outgoingContactAccountPeerId: contact,
        nativeHandleOverride: oldHandle,
        lifecycleOverride: (method, arguments) async {
          if (method == 'attach') return latestBatch;
          if (method == 'acknowledge' &&
              arguments['disposition'] == 'TERMINAL') {
            terminalAckCount++;
            expect(arguments['callHandle'], oldHandle);
            expect(arguments['throughSequence'], 2);
            if (holdTerminalAck) {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              latestBatch = null;
              return true;
            }
            return terminalAckAllowed;
          }
          if (method == 'registerOutgoingAuthenticated') {
            final handle = arguments['callHandle']! as String;
            registrations.add(handle);
            latestBatch = batch(handle, outgoing: true);
            nativeEvents.add(latestBatch);
          }
          return null;
        },
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        terminalAckAllowed = true;
        holdTerminalAck = false;
        await nativeEvents.close();
      });
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      expect(graph.androidCallLifecycleAdapter, isNotNull);
      expect(graph.iosCallLifecycleAdapter, isNull);
      final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
      if (boundary == 'native reconciliation') {
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.remoteInvite,
            eventId: 'prior-native-invite',
            occurredAt: now,
            callId: _callA,
            contactPeerId: contact,
            localAccountPeerId: 'local-account',
            localDeviceId: 'local-account',
            remoteAccountPeerId: contact,
            remoteDeviceId: 'remote-device',
            expiresAt: now.add(const Duration(seconds: 45)),
            transportRoute: CallRouteClass.direct,
          ),
        );
        await graph.coordinator.dispatch(
          CallEvent(
            type: CallEventType.incomingValidated,
            eventId: 'prior-native-validated',
            occurredAt: now,
            callId: _callA,
            contactPeerId: contact,
          ),
        );
        expect(
          await graph.androidCallLifecycleAdapter!.present(
            IncomingCallPresentation(
              callId: _callA,
              callerAccountPeerId: contact,
              expiresAt: now.add(const Duration(seconds: 45)),
            ),
          ),
          isTrue,
        );
        latestBatch = batch(oldHandle, terminal: true);
        nativeEvents.add(latestBatch);
        await _untilComposition(
          () => terminalAckCount > 0 && graph.coordinator.activeSession == null,
        );
        expect(graph.coordinator.terminalCleanupAckReady(_callA), isTrue);
        expect(graph.androidCallLifecycleAdapter!.isBoundTo(_callA), isTrue);
        // Drain earlier native/snapshot work, retaining the refused terminal.
        // The next held ACK must belong to graph preflight reconciliation.
        expect(
          await graph.androidCallLifecycleAdapter!.reconcileBeforeOutgoing(),
          isFalse,
        );
        terminalAcksBeforeWait = terminalAckCount;
        holdTerminalAck = true;
      }
      await _configureCancellationEndpoint(fixture, contact);
      final priorSnapshot = graph.coordinator.lastSnapshot;
      final originalRequests = fixture.bridge.requests.length;
      final authorityReadsBefore = issued.reads;
      if (boundary == 'final wake authority') {
        issued.holdNextRead = () async {
          entered.complete();
          await release.future;
        };
      }
      final request = OutgoingCallStartRequest();
      var completed = false;
      final outgoing = graph
          .startOutgoingCall(contact, request: request)
          .whenComplete(() => completed = true);
      await entered.future.timeout(const Duration(seconds: 2));
      // This proves the specific native ACK/store read has entered and the
      // original request is still suspended, rather than relying on a delay.
      expect(completed, isFalse);
      expect(request.isAdmitted, isFalse);
      expect(graph.coordinator.activeSession, isNull);
      expect(registrations, isEmpty);
      expect(
        fixture.bridge.requests
            .skip(originalRequests)
            .where((r) => r['cmd'] == 'call_endpoint_get_v1'),
        hasLength(1),
      );
      if (boundary == 'final wake authority') {
        expect(issued.heldReads, 1);
        expect(issued.reads, authorityReadsBefore + 1);
      } else {
        expect(terminalAckCount, terminalAcksBeforeWait + 1);
        expect(issued.reads, authorityReadsBefore);
      }
      request.cancel();
      expect(completed, isFalse);
      release.complete();
      expect(await outgoing, OutgoingCallStartResult.canceled);
      expect(request.isAdmitted, isFalse);
      expect(graph.coordinator.activeSession, isNull);
      expect(graph.coordinator.lastSnapshot, same(priorSnapshot));
      if (boundary == 'native reconciliation') {
        expect(
          issued.reads,
          authorityReadsBefore,
          reason:
              'Canceled native completion must not reach final authority read',
        );
        expect(graph.androidCallLifecycleAdapter!.isBoundTo(_callA), isFalse);
      }
      expect(registrations, isEmpty);
      expect(
        fixture.bridge.requests
            .skip(originalRequests)
            .where(
              (r) =>
                  r['cmd'] == 'call_store_v1' || r['cmd'] == 'message.encrypt',
            ),
        isEmpty,
      );
      final invalidationsBeforeRetry = fixture.lifecycleMethods
          .where((m) => m == 'failClosed')
          .length;
      expect(invalidationsBeforeRetry, 0);

      holdTerminalAck = false;
      terminalAckAllowed = true;
      final retry = OutgoingCallStartRequest();
      expect(
        await graph.startOutgoingCall(contact, request: retry),
        OutgoingCallStartResult.started,
      );
      expect(retry.isAdmitted, isTrue);
      final successor = graph.coordinator.activeSession!;
      expect(successor.callId, isNot(_callA));
      expect(successor.state, CallState.inviting);
      expect(registrations, hasLength(1));
      final invites = fixture.bridge.requests
          .skip(originalRequests)
          .where((r) => r['cmd'] == 'call_store_v1')
          .toList();
      expect(invites, hasLength(1));
      expect(
        (invites.single['payload']! as Map)['callHandle'],
        registrations.single,
      );
      expect(
        graph.androidCallLifecycleAdapter!.isBoundTo(successor.callId!),
        isTrue,
      );
      final encrypted = fixture.bridge.requests
          .skip(originalRequests)
          .where((r) => r['cmd'] == 'message.encrypt')
          .single;
      final signal =
          jsonDecode((encrypted['payload']! as Map)['plaintext'] as String)
              as Map;
      expect(signal['call_id'], successor.callId!.value);
      expect(signal['event'], 'invite');
      expect(request.isAdmitted, isFalse);
      expect(fixture.lifecycleMethods.where((m) => m == 'failClosed'), isEmpty);
      await graph.coordinator.dispatch(
        CallEvent(
          type: CallEventType.cancel,
          eventId: 'successor-fixture-cleanup',
          occurredAt: now,
          callId: successor.callId,
          contactPeerId: contact,
        ),
      );
      expect(graph.coordinator.activeSession, isNull);
      expect(
        graph.coordinator.terminalCleanupAckReady(successor.callId!),
        isTrue,
      );
    });
  }

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
        'await runtime.onResume();\n'
        '    final active = coordinator.activeSession;\n'
        '    if (active != null) _onSessionSnapshot(active);\n'
        '    _pip?.foreground();\n'
        '    _refreshVideo();\n'
        '    await _resumePipCamera();\n'
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

final class _GatedIssuedWakeStore implements IssuedCallWakeHandleStore {
  _GatedIssuedWakeStore(this.delegate);
  final IssuedCallWakeHandleStore delegate;
  Future<void> Function()? holdNextRead;
  int heldReads = 0;
  int reads = 0;
  @override
  Future<CallIssuedWakeHandleRecord?> readForContact(String contact) async {
    reads++;
    final record = await delegate.readForContact(contact);
    final hold = holdNextRead;
    if (hold != null) {
      holdNextRead = null;
      heldReads++;
      await hold();
    }
    return record;
  }

  @override
  Future<List<CallIssuedWakeHandleRecord>> readAll() => delegate.readAll();
  @override
  Future<void> write(CallIssuedWakeHandleRecord record) =>
      delegate.write(record);
  @override
  Future<void> removeForContact(String contact) =>
      delegate.removeForContact(contact);
  @override
  Future<void> clear() => delegate.clear();
}

({Completer<void> entered, Completer<void> release}) _holdTerminalAuthorization(
  _ProductionIosFixture fixture,
  _InitialVideoGraphEngine engine,
  String boundary,
) {
  final entered = Completer<void>();
  final release = Completer<void>();
  // Hold media cleanup only until authorization has entered; after that it
  // must finish while network authorization is still suspended.
  engine.closeGate = entered.future;
  addTearDown(() {
    if (!entered.isCompleted) entered.complete();
    if (!release.isCompleted) release.complete();
  });
  final command = boundary == 'endpoint'
      ? 'call_endpoint_get_v1'
      : 'payload.sign';
  fixture.bridge.responseHandlers[command] = (request) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return fixture.bridge.responses[command] ??
        {'ok': true, 'signature': 'c2lnbmF0dXJl'};
  };
  return (entered: entered, release: release);
}

List<Object?> _terminalTransportIds(_ProductionIosFixture fixture) {
  final ids = _upgradeSignals(
    fixture,
    'terminate',
  ).map((s) => s['message_id']).toSet();
  return fixture.bridge.requests
      .where((r) => r['cmd'] == 'call_store_v1')
      .map((r) => (r['payload'] as Map)['messageId'])
      .where(ids.contains)
      .toList();
}

Future<void> _untilGraphVideo(bool Function() predicate) async {
  final elapsed = Stopwatch()..start();
  while (!predicate() && elapsed.elapsed < const Duration(seconds: 5)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    predicate(),
    isTrue,
    reason: 'production graph fixture did not reach the expected boundary',
  );
}

Future<void> _deliverGraphVideoInvite(
  _ProductionIosFixture fixture, {
  CallId? callId,
  String messageId = '00000000-0000-4000-8000-000000000023',
  String callHandle = '33333333-3333-4333-8333-333333333333',
}) async {
  final graph = fixture.graphs.single;
  final device = (await graph.trustedRosterProvider.loadForContact(
    'video-contact',
  )).devices.single;
  final signal = CallSignalV2.fromMap({
    'schema': CallSignalV2.schema,
    'call_id': (callId ?? _callA).value,
    'message_id': messageId,
    'event': 'invite',
    'sender_account_peer_id': 'video-contact',
    'sender_device_peer_id': device.devicePeerId,
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-account',
    'sender_sequence': 1,
    'ice_generation': 0,
    'created_at_ms': 2_000_000,
    'expires_at_ms': 2_040_000,
    'payload': {
      'media': 'video',
      'camera': 'off',
      'capabilities': ['audio', 'video'],
    },
  }, videoEnabled: true);
  fixture.bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(signal.toMap()),
  };
  fixture.p2p.messages.add(
    ChatMessage(
      from: device.devicePeerId,
      to: 'local-account',
      content: jsonEncode({
        'type': 'call_signal',
        'version': '1',
        'message_id': signal.messageId,
        'call_handle': callHandle,
        'expires_at_ms': signal.expiresAtMs,
        'kem': base64Encode([1]),
        'ciphertext': base64Encode([2]),
        'nonce': base64Encode([3]),
        'signature': base64Encode([4]),
      }),
      timestamp: _callNow.toIso8601String(),
      isIncoming: true,
      transport: 'direct',
    ),
  );
  await _untilComposition(
    () => graph.coordinator.activeSession?.state == CallState.ringing,
  );
}

Future<(_ProductionIosFixture, _InitialVideoGraphEngine)> _connectedGraphVideo({
  Duration? cleanupTimeout,
  EnsureOutgoingCallWakeAuthority? ensureOutgoingCallWakeAuthority,
  CallEndpointPlatform platform = CallEndpointPlatform.ios,
  CallMediaKind acceptedMedia = CallMediaKind.video,
  int Function()? clockMs,
  CallId? callId,
  Future<bool> Function()? permission,
  Future<Object?> Function(String, Map<String, Object?>)? nativeOverride,
  CallScheduledTimerObserver? timerObserver,
  CallVideoQualityEnvironmentSource Function()? qualityEnvironmentSourceFactory,
  CallPictureInPictureBridge Function()? pictureInPictureBridgeFactory,
  Future<bool> Function()? checkCameraPermission,
  CaptureCallActivityMark? captureCallActivityMark,
  Duration Function()? monotonicNow,
  CallTimerScheduler? timerScheduler,
  Database? databaseOverride,
  SecureKeyStore? privacyStore,
  Future<void> Function(_ProductionIosFixture)? beforeCall,
  Future<void> Function(_ProductionIosFixture)? whileRinging,
  Future<void> Function(_ProductionIosFixture)? beforeConnected,
}) async {
  final connectedCallId = callId ?? _callA;
  final events = StreamController<Object?>.broadcast(sync: true);
  if (cleanupTimeout == null) {
    addTearDown(events.close);
  } else {
    addTearDown(() => events.close().timeout(cleanupTimeout));
  }
  var audioActive = false;
  final engine = _InitialVideoGraphEngine();
  final fixture = await _createProductionIosFixture(
    cleanupTimeout: cleanupTimeout,
    ensureOutgoingCallWakeAuthority: ensureOutgoingCallWakeAuthority,
    nativePlatform: platform,
    clockMs: clockMs,
    microphonePermission: const _GrantedCallMicrophonePermission(),
    requestCameraPermission: permission ?? () async => true,
    onCallTimerScheduled: timerObserver,
    captureCallActivityMark: captureCallActivityMark,
    monotonicNow: monotonicNow,
    timerScheduler: timerScheduler,
    databaseOverride: databaseOverride,
    privacyStore: privacyStore,
    qualityEnvironmentSourceFactory: qualityEnvironmentSourceFactory,
    pictureInPictureBridgeFactory: pictureInPictureBridgeFactory,
    checkCameraPermission: checkCameraPermission,
    outgoingContactAccountPeerId: 'video-contact',
    privacyFlags: const {'video_call_v2_enabled': true},
    lifecycleEventStream: events.stream,
    callEngineFactory: (_) => engine,
    lifecycleOverride: (method, arguments) async {
      final overridden = await nativeOverride?.call(method, arguments);
      if (overridden != null) return overridden;
      if (method == 'activateAudio') audioActive = true;
      if (method == 'deactivateAudio' || method == 'end') audioActive = false;
      if (method == 'readAudioState') {
        return {
          'version': 1,
          'active': audioActive,
          'muted': false,
          'route': 'system_default',
          'availableRoutes': ['system_default', 'speaker'],
        };
      }
      return null;
    },
  );
  await fixture.composition.start();
  await _configureCancellationEndpoint(fixture, 'video-contact', video: true);
  final wall = DateTime.now().millisecondsSinceEpoch;
  final credentials = <String, Object?>{
    'ok': true,
    'schema': 'turn_credentials',
    'version': 1,
    'urls': ['turn:relay.invalid:3478?transport=udp'],
    'username': 'fixture-user',
    'password': 'fixture-secret',
    'ttlSeconds': 600,
    'serverTimeMs': wall,
    'expiresAtMs': wall + 600000,
  };
  fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
  fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] =
      credentials;
  if (beforeCall != null) {
    await _b7Bound(beforeCall(fixture));
  }
  await _deliverGraphVideoInvite(fixture, callId: connectedCallId);
  if (whileRinging != null) {
    await _b7Bound(whileRinging(fixture));
  }
  final graph = fixture.graphs.single;
  expect(graph.current!.video, isNotNull);
  final Object capability = fixture.composition;
  expect(capability, isA<ForegroundCallMediaAnswerCapability>());
  expect(
    await (capability as ForegroundCallMediaAnswerCapability).answerWithMedia(
      connectedCallId,
      generation: graph.current!.video!.generation,
      acceptedMedia: acceptedMedia,
    ),
    ForegroundCallActionResult.applied,
  );
  const handle = '33333333-3333-4333-8333-333333333333';
  events.add({
    'version': 1,
    'descriptor': {
      'callHandle': handle,
      'expiresAtMs': 2040000,
      'presented': true,
      'phase': 'journal',
      'direction': 'incoming',
    },
    'nativeCallId': handle,
    'highestSequence': 2,
    'events': [
      {
        'callHandle': handle,
        'sequence': 1,
        'eventId': '55555555-5555-4555-8555-555555555555',
        'type': 'presented',
        'occurredAtMs': 2000000,
      },
      {
        'callHandle': handle,
        'sequence': 2,
        'eventId': '66666666-6666-4666-8666-666666666666',
        'type': 'answer',
        'occurredAtMs': 2000001,
      },
    ],
  });
  await _untilGraphVideo(
    () => fixture.bridge.requests
        .where((r) => r['cmd'] == 'message.encrypt')
        .any(
          (r) =>
              (jsonDecode((r['payload'] as Map)['plaintext'] as String)
                  as Map)['event'] ==
              'accept',
        ),
  );
  final device = (await graph.trustedRosterProvider.loadForContact(
    'video-contact',
  )).devices.single;
  final offer = CallSignalV2.fromMap({
    'schema': CallSignalV2.schema,
    'call_id': connectedCallId.value,
    'message_id': '00000000-0000-4000-8000-000000000024',
    'event': 'offer',
    'sender_account_peer_id': 'video-contact',
    'sender_device_peer_id': device.devicePeerId,
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-account',
    'sender_sequence': 2,
    'ice_generation': 0,
    'created_at_ms': 2000000,
    'expires_at_ms': 2040000,
    'payload': {
      'negotiation_id': '77777777-7777-4777-8777-777777777777',
      'purpose': 'initial',
      'switch_id': null,
      'media_revision': 0,
      'media': acceptedMedia.name,
      'description': 'fixture-sdp',
      'fingerprint': 'fixture-fingerprint',
    },
  }, videoEnabled: true);
  fixture.bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(offer.toMap()),
  };
  fixture.p2p.messages.add(
    ChatMessage(
      from: device.devicePeerId,
      to: 'local-account',
      content: jsonEncode({
        'type': 'call_signal',
        'version': '1',
        'message_id': offer.messageId,
        'call_handle': handle,
        'expires_at_ms': offer.expiresAtMs,
        'kem': base64Encode([1]),
        'ciphertext': base64Encode([2]),
        'nonce': base64Encode([3]),
        'signature': base64Encode([4]),
      }),
      timestamp: _callNow.toIso8601String(),
      isIncoming: true,
      transport: 'direct',
    ),
  );
  await _untilGraphVideo(() => engine.video?.commits == 1);
  if (beforeConnected != null) {
    await _b7Bound(beforeConnected(fixture));
  }
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.mediaConnected,
      eventId: 'graph-video-media-connected',
      occurredAt: graph.coordinator.clock(),
      callId: connectedCallId,
    ),
  );
  expect(graph.coordinator.activeSession!.state, CallState.connected);
  expect(graph.current!.video!.presentation.agreedMedia, acceptedMedia);
  return (fixture, engine);
}

// Each production fixture has its own local-account/video-contact namespace.
// Keep call, message and switch identities and timestamps when crossing that
// boundary; only map peer addresses to the receiving fixture's trusted roster.
Future<void> _deliverUpgradeSignal(
  _ProductionIosFixture fixture,
  Map<String, dynamic> wire, {
  bool mailbox = false,
}) async {
  final graph = fixture.graphs.single;
  final callId = graph.coordinator.activeSession!.callId!;
  final context = graph.videoContexts!.read(callId)!;
  final device = (await graph.trustedRosterProvider.loadForContact(
    'video-contact',
  )).devices.single;
  final signal = CallSignalV2.fromMap({
    ...wire,
    'sender_account_peer_id': 'video-contact',
    'sender_device_peer_id': device.devicePeerId,
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-account',
  }, videoEnabled: true);
  final envelope = jsonEncode({
    'type': 'call_signal',
    'version': '1',
    'message_id': signal.messageId,
    'call_handle': context.callHandle,
    'expires_at_ms': signal.expiresAtMs,
    'kem': base64Encode([1]),
    'ciphertext': base64Encode([2]),
    'nonce': base64Encode([3]),
    'signature': base64Encode([4]),
  });
  fixture.bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(signal.toMap()),
  };
  if (mailbox) {
    fixture.bridge.responses['call_retrieve_v1'] = {
      'ok': true,
      'events': [
        {
          'callHandle': context.callHandle,
          'messageId': signal.messageId,
          'senderPeerId': device.devicePeerId,
          'recipientDevicePeerId': 'local-account',
          'envelope': envelope,
          'receiptAtMs': signal.createdAtMs,
          'expiresAtMs': signal.expiresAtMs,
        },
      ],
      'receiptAtMs': signal.createdAtMs,
      'expiresAtMs': signal.expiresAtMs,
      'hasMore': false,
    };
    fixture.bridge.responses['call_ack_v1'] = {'ok': true, 'acked': 1};
    final beforeDrain = fixture.bridge.requests.length;
    await fixture.composition.onCallWake();
    final drainRequests = fixture.bridge.requests.skip(beforeDrain).toList();
    expect(
      drainRequests.where((r) => r['cmd'] == 'call_retrieve_v1'),
      isNotEmpty,
    );
    expect(
      drainRequests
          .where((r) => r['cmd'] == 'call_ack_v1')
          .expand((r) => (r['payload'] as Map)['messageIds'] as List),
      contains(signal.messageId),
    );
    fixture.bridge.responses['call_retrieve_v1'] = {
      'ok': true,
      'events': [],
      'receiptAtMs': signal.createdAtMs,
      'expiresAtMs': signal.expiresAtMs,
      'hasMore': false,
    };
  } else {
    fixture.p2p.messages.add(
      ChatMessage(
        from: device.devicePeerId,
        to: 'local-account',
        content: envelope,
        timestamp: _callNow.toIso8601String(),
        isIncoming: true,
        transport: 'direct',
      ),
    );
  }
}

List<Map<String, dynamic>> _upgradeSignals(
  _ProductionIosFixture fixture,
  String event,
) => fixture.bridge.requests
    .where((r) => r['cmd'] == 'message.encrypt')
    .map(
      (r) =>
          jsonDecode((r['payload'] as Map)['plaintext'] as String)
              as Map<String, dynamic>,
    )
    .where((r) => r['event'] == event)
    .toList();

Future<(_ProductionIosFixture, _ProcessLossEngine)> _connectedLegacyRecovery({
  required bool caller,
}) async {
  final engine = _ProcessLossEngine();
  late final _ProductionIosFixture fixture;
  fixture = await _createProductionIosFixture(
    nativePlatform: CallEndpointPlatform.android,
    outgoingContactAccountPeerId: 'remote-account',
    privacyFlags: const {
      'video_call_v2_enabled': true,
      'voice_call_android_native_enabled': false,
    },
    microphonePermission: const _GrantedCallMicrophonePermission(),
    callEngineFactory: (_) => engine,
    ensureOutgoingCallWakeAuthority: (peer) async {
      final issued = await fixture.issuedCallWakeHandleStore.readForContact(
        peer,
      );
      return issued != null &&
          await fixture.graphs.single.markCallWakeHandleDistributed(
            peer,
            issued.grant,
          );
    },
  );
  final presentation = fixture.composition.changes.listen((_) {});
  addTearDown(presentation.cancel);
  await fixture.composition.start();
  await _configureCancellationEndpoint(fixture, 'remote-account');
  final wall = DateTime.now().millisecondsSinceEpoch;
  final credentials = <String, Object?>{
    'ok': true,
    'schema': 'turn_credentials',
    'version': 1,
    'urls': ['turn:relay.invalid:3478?transport=udp'],
    'username': 'fixture-user',
    'password': 'fixture-secret',
    'ttlSeconds': 600,
    'serverTimeMs': wall,
    'expiresAtMs': wall + 600000,
  };
  fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
  fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] =
      credentials;
  final graph = fixture.graphs.single;
  if (caller) {
    expect(
      await fixture.composition.startOutgoingCall('remote-account'),
      OutgoingCallStartResult.started,
    );
    await _deliverLegacyRecovery(fixture, CallSignalType.accept, 2, 0, {});
    await _untilGraphVideo(() => _upgradeSignals(fixture, 'offer').isNotEmpty);
    await _deliverLegacyRecovery(fixture, CallSignalType.answer, 3, 0, {
      'description': 'fixture-initial-answer',
      'fingerprint': _ProcessLossEngine._fingerprint,
    });
  } else {
    final invite = _killedCallSignal(CallSignalType.invite);
    fixture.bridge.responses['message.decrypt'] = {
      'ok': true,
      'plaintext': jsonEncode(invite.toMap()),
    };
    fixture.p2p.messages.add(
      ChatMessage(
        from: 'remote-account',
        to: 'local-account',
        content: _killedCallEnvelope(invite, _killedCallHandle),
        timestamp: _callNow.toIso8601String(),
        isIncoming: true,
        transport: 'direct',
      ),
    );
    await _untilGraphVideo(
      () =>
          graph.coordinator.activeSession?.incomingValidated == true &&
          graph.coordinator.activeSession?.state == CallState.ringing,
    );
    await graph.coordinator.dispatch(
      CallEvent(
        type: CallEventType.answer,
        eventId: 'bl26-v1-answer',
        occurredAt: graph.coordinator.clock(),
        callId: invite.callId,
      ),
    );
    await _deliverLegacyRecovery(fixture, CallSignalType.offer, 2, 0, {
      'description': 'fixture-initial-offer',
      'fingerprint': _ProcessLossEngine._fingerprint,
    });
    await _untilGraphVideo(() => _upgradeSignals(fixture, 'answer').isNotEmpty);
  }
  await _untilGraphVideo(
    () => engine.localDescriptions == 1 && engine.remoteDescriptions == 1,
  );
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.mediaConnected,
      eventId: 'bl26-v1-connected',
      occurredAt: graph.coordinator.clock(),
      callId: graph.coordinator.activeSession!.callId,
    ),
  );
  expect(graph.coordinator.activeSession!.state, CallState.connected);
  expect(
    graph.videoContexts!
        .read(graph.coordinator.activeSession!.callId!)!
        .wireVersion,
    CallWireVersion.v1,
  );
  return (fixture, engine);
}

Future<void> _deliverLegacyRecovery(
  _ProductionIosFixture fixture,
  CallSignalType type,
  int sequence,
  int generation,
  Map<String, Object?> payload,
) async {
  final graph = fixture.graphs.single;
  final id = graph.coordinator.activeSession!.callId!;
  final context = graph.videoContexts!.read(id)!;
  final device = (await graph.trustedRosterProvider.loadForContact(
    'remote-account',
  )).devices.single;
  final signal = CallSignal.create(
    callId: id,
    messageId:
        '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
    event: type,
    senderAccountPeerId: 'remote-account',
    senderDevicePeerId: device.devicePeerId,
    recipientAccountPeerId: 'local-account',
    recipientDevicePeerId: 'local-account',
    senderSequence: sequence,
    iceGeneration: generation,
    createdAtMs: 2000000,
    expiresAtMs: 2040000,
    payload: payload,
  );
  fixture.bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(signal.toMap()),
  };
  fixture.p2p.messages.add(
    ChatMessage(
      from: device.devicePeerId,
      to: 'local-account',
      content: _killedCallEnvelope(signal, context.callHandle),
      timestamp: _callNow.toIso8601String(),
      isIncoming: true,
      transport: 'direct',
    ),
  );
}

Future<(_ProductionIosFixture, _InitialVideoGraphEngine)>
_connectedOutgoingGraphAudio({
  Duration? cleanupTimeout,
  CaptureCallActivityMark? captureCallActivityMark,
  Duration Function()? monotonicNow,
  CallTimerScheduler? timerScheduler,
  int Function()? clockMs,
  Database? databaseOverride,
  SecureKeyStore? privacyStore,
  Future<void> Function(_ProductionIosFixture)? beforeCall,
  Future<void> Function(_ProductionIosFixture)? whileRinging,
  Future<void> Function(_ProductionIosFixture)? beforeConnected,
}) async {
  String? handle;
  int? expires;
  final engine = _InitialVideoGraphEngine();
  late final _ProductionIosFixture fixture;
  fixture = await _createProductionIosFixture(
    cleanupTimeout: cleanupTimeout,
    captureCallActivityMark: captureCallActivityMark,
    monotonicNow: monotonicNow,
    timerScheduler: timerScheduler,
    clockMs: clockMs,
    databaseOverride: databaseOverride,
    privacyStore: privacyStore,
    microphonePermission: const _GrantedCallMicrophonePermission(),
    outgoingContactAccountPeerId: 'video-contact',
    privacyFlags: const {'video_call_v2_enabled': true},
    callEngineFactory: (_) => engine,
    ensureOutgoingCallWakeAuthority: (peer) async {
      final issued = await fixture.issuedCallWakeHandleStore.readForContact(
        peer,
      );
      return issued != null &&
          await fixture.graphs.single.markCallWakeHandleDistributed(
            peer,
            issued.grant,
          );
    },
    lifecycleOverride: (method, arguments) async {
      if (method == 'registerOutgoingAuthenticated') {
        handle = arguments['callHandle']! as String;
        expires = arguments['expiresAtMs']! as int;
        return true;
      }
      if (method == 'readAudioState') {
        return {
          'version': 1,
          'active': true,
          'muted': false,
          'route': 'system_default',
          'availableRoutes': ['system_default'],
        };
      }
      if (method == 'attach' && handle != null) {
        return {
          'version': 1,
          'descriptor': {
            'callHandle': handle,
            'expiresAtMs': expires,
            'presented': true,
            'phase': 'preStart',
            'direction': 'outgoing',
          },
          'nativeCallId': handle,
          'highestSequence': 1,
          'events': [
            {
              'callHandle': handle,
              'sequence': 1,
              'eventId': '00000000-0000-4000-8000-000000000001',
              'type': 'presented',
              'occurredAtMs': 2000000,
            },
          ],
        };
      }
      return null;
    },
  );
  await fixture.composition.start();
  await _configureCancellationEndpoint(fixture, 'video-contact', video: true);
  final wall = DateTime.now().millisecondsSinceEpoch;
  final credentials = {
    'ok': true,
    'schema': 'turn_credentials',
    'version': 1,
    'urls': ['turn:relay.invalid:3478?transport=udp'],
    'username': 'fixture-user',
    'password': 'fixture-secret',
    'ttlSeconds': 600,
    'serverTimeMs': wall,
    'expiresAtMs': wall + 600000,
  };
  fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
  fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] =
      credentials;
  if (beforeCall != null) {
    await _b7Bound(beforeCall(fixture));
  }
  expect(
    await (fixture.composition as OutgoingVideoCallCapability)
        .startOutgoingVideoCall('video-contact'),
    OutgoingCallStartResult.started,
  );
  if (whileRinging != null) {
    await _b7Bound(whileRinging(fixture));
  }
  final graph = fixture.graphs.single;
  final id = graph.coordinator.activeSession!.callId!;
  Map<String, dynamic> remote(
    String event,
    int sequence,
    Map<String, Object?> payload,
  ) => {
    'schema': CallSignalV2.schema,
    'call_id': id.value,
    'message_id': '00000000-0000-4000-8000-00000000003$sequence',
    'event': event,
    'sender_sequence': sequence,
    'ice_generation': 0,
    'created_at_ms': 2000000,
    'expires_at_ms': 2040000,
    'payload': payload,
  };
  await _deliverUpgradeSignal(
    fixture,
    remote('accept', 1, {'media': 'audio', 'camera': 'off'}),
  );
  await _untilGraphVideo(() => _upgradeSignals(fixture, 'offer').isNotEmpty);
  final offer = _upgradeSignals(fixture, 'offer').single;
  await _deliverUpgradeSignal(
    fixture,
    remote('answer', 2, Map<String, Object?>.from(offer['payload'] as Map)),
  );
  await _untilGraphVideo(() => engine.video?.commits == 1);
  if (beforeConnected != null) {
    await _b7Bound(beforeConnected(fixture));
  }
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.mediaConnected,
      eventId: 'upgrade-caller-connected',
      occurredAt: graph.coordinator.clock(),
      callId: id,
    ),
  );
  expect(graph.current!.video!.presentation.agreedMedia, CallMediaKind.audio);
  return (fixture, engine);
}

Future<void> _configureCancellationEndpoint(
  _ProductionIosFixture fixture,
  String contact, {
  bool video = false,
}) async {
  const nowMs = 2_000_000;
  final graph = fixture.graphs.single;
  final device = (await graph.trustedRosterProvider.loadForContact(
    contact,
  )).devices.single;
  expect(
    await fixture.receivedCallWakeHandleStore.storeIfStrictlyNewer(
      issuerAccountPeerId: contact,
      grant: CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: device.devicePeerId,
        deviceKeyEpoch: device.deviceKeyEpoch,
        generation: 1,
        issuedAtMs: nowMs - 1000,
        expiresAtMs: nowMs + 60_000,
      ),
      nowMs: nowMs,
    ),
    isTrue,
  );
  await fixture.issuedCallWakeHandleStore.write(
    CallIssuedWakeHandleRecord(
      contactAccountPeerId: contact,
      grant: CallWakeHandleGrant(
        handle: '0123456789abcdef0123456789abcdef',
        recipientDevicePeerId: graph.localIdentity.peerId,
        deviceKeyEpoch: graph.localDeviceKeyEpoch,
        generation: 1,
        issuedAtMs: nowMs - 1000,
        expiresAtMs: nowMs + 60_000,
      ),
      authorizedSenderDevicePeerIds: <String>{device.devicePeerId},
      distributionPending: false,
      distributionReceiptVersion:
          CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
    ),
  );
  final endpoint = CallEndpointRecord(
    accountPeerId: contact,
    devicePeerId: device.devicePeerId,
    capabilities: <String>{'voice_call_v1', if (video) 'video_call_v2'},
    platform: CallEndpointPlatform.android,
    expiresAtMs: nowMs + 60_000,
    preferenceEpoch: 1,
    deviceKeyEpoch: device.deviceKeyEpoch,
    routingHandle: '0123456789abcdef0123456789abcdef',
  );
  fixture.bridge.responses['call_endpoint_get_v1'] = <String, Object?>{
    'ok': true,
    'found': true,
    'canonicalRecord': base64Encode(utf8.encode(endpoint.canonicalRecordJson)),
    'endpoint': <String, Object?>{
      ...endpoint.toCanonicalMap(),
      'signature': 'c2lnbmF0dXJl',
    },
  };
  fixture.bridge.responses['payload.verify'] = const <String, Object?>{
    'ok': true,
    'valid': true,
  };
  fixture.bridge.responses['message.encrypt'] = const <String, Object?>{
    'ok': true,
    'kem': 'a2Vt',
    'ciphertext': 'Y2lwaGVy',
    'nonce': 'bm9uY2U=',
  };
  fixture.bridge.responseHandlers['call_store_v1'] = (request) async =>
      <String, Object?>{
        'ok': true,
        'storeStatus': 'stored',
        'receiptAtMs': nowMs,
        'expiresAtMs': (request['payload']! as Map)['expiresAtMs'],
        'eventCount': 1,
        'totalBytes': 128,
        'pendingHandles': 1,
        'wake': 'none',
      };
  fixture.bridge.responses['call_cancel_v1'] = const <String, Object?>{
    'ok': true,
    'canceled': true,
  };
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
    required this.p2p,
  });

  final CallSignalingComposition composition;
  final _Bridge bridge;
  final List<String> lifecycleMethods;
  final List<Map<String, Object?>> capabilityArguments;
  final StreamController<Object?> tokenEvents;
  final List<ProductionCallSignalingGraph> graphs;
  final IssuedCallWakeHandleStore issuedCallWakeHandleStore;
  final ReceivedCallWakeHandleStoreImpl receivedCallWakeHandleStore;
  final _P2P p2p;
}

Future<_ProductionIosFixture> _createProductionIosFixture({
  Duration? cleanupTimeout,
  CallEndpointPlatform nativePlatform = CallEndpointPlatform.ios,
  IssuedCallWakeHandleStore? issuedStore,
  Stream<Object?>? lifecycleEventStream,
  SecureKeyStore? privacyStore,
  Database? databaseOverride,
  int Function()? clockMs,
  CallEngine Function(CallId)? callEngineFactory,
  void Function(CallHistoryEntry entry, bool inserted)? onCallHistoryProjected,
  CallScheduledTimerObserver? onCallTimerScheduled,
  CaptureCallActivityMark? captureCallActivityMark,
  Duration Function()? monotonicNow,
  CallTimerScheduler? timerScheduler,
  Map<String, bool> privacyFlags = const {},
  Map<String, Object?>? endpointSetResponse,
  Map<String, Object?>? tokenSetResponse,
  Object? attachResponse,
  Future<void>? failClosedGate,
  Future<Object?> Function()? disableCapability,
  CallNetworkEffectsAllowed? networkEffectsAllowed,
  String? outgoingContactAccountPeerId,
  CallMicrophonePermission? microphonePermission,
  Future<bool> Function()? requestCameraPermission,
  CallVideoQualityEnvironmentSource Function()? qualityEnvironmentSourceFactory,
  CallPictureInPictureBridge Function()? pictureInPictureBridgeFactory,
  Future<bool> Function()? checkCameraPermission,
  bool usePlatformQualityEnvironment = false,
  EnsureOutgoingCallWakeAuthority? ensureOutgoingCallWakeAuthority,
  RepairCallEndpoint? repairMissingEndpoint,
  String? nativeHandleOverride,
  Future<Object?> Function(String, Map<String, Object?>)? lifecycleOverride,
}) async {
  databaseFactory = databaseFactoryFfi;
  final database =
      databaseOverride ??
      await openDatabase(
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
    secureKeyStore: privacyStore ?? FakeSecureKeyStore(),
    featureFlags: <String, bool>{
      ..._enabledFlags(),
      'voice_call_android_native_enabled':
          nativePlatform == CallEndpointPlatform.android,
      'voice_call_ios_native_enabled':
          nativePlatform == CallEndpointPlatform.ios,
      ...privacyFlags,
    },
    platform: nativePlatform,
    database: database,
    bridge: bridge,
    p2pService: p2p,
    messageRouter: router,
    loadIdentity: () async => identity,
    networkEffectsAllowed: networkEffectsAllowed ?? () => true,
    isVoiceNoteRecording: () => false,
    microphonePermission: microphonePermission,
    requestCameraPermission: requestCameraPermission,
    pictureInPictureBridgeFactory: pictureInPictureBridgeFactory,
    checkCameraPermission: checkCameraPermission,
    qualityEnvironmentSourceFactory: usePlatformQualityEnvironment
        ? null
        : qualityEnvironmentSourceFactory ?? () => _GraphQualitySource(),
    callEngineFactory: callEngineFactory,
    onCallHistoryProjected: onCallHistoryProjected,
    onCallTimerScheduled: onCallTimerScheduled,
    captureCallActivityMark: captureCallActivityMark,
    monotonicNow: monotonicNow,
    timerScheduler: timerScheduler,
    ensureOutgoingCallWakeAuthority: ensureOutgoingCallWakeAuthority,
    repairMissingEndpoint: repairMissingEndpoint,
    issuedCallWakeHandleStore: issuedStore ?? callWakeStores.issued,
    receivedCallWakeHandleStore: callWakeStores.received,
    androidCallLifecycleAdapterFactory:
        ({
          required coordinator,
          required resolveAuthenticatedHandle,
          required clock,
        }) => AndroidCallLifecycleAdapter(
          videoEnabled: privacyFlags['video_call_v2_enabled'] == true,
          invokeMethod: (method, arguments) async {
            lifecycleMethods.add(method);
            final overridden = await lifecycleOverride?.call(method, arguments);
            if (overridden != null) return overridden;
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
            return true;
          },
          nativeEvents: lifecycleEventStream ?? const Stream<Object?>.empty(),
          coordinator: coordinator,
          resolveAuthenticatedHandle: (callId) =>
              callId == _callA && nativeHandleOverride != null
              ? nativeHandleOverride
              : resolveAuthenticatedHandle(callId),
          clock: clock,
        ),
    iosCallLifecycleAdapterFactory:
        ({
          required coordinator,
          required resolveAuthenticatedHandle,
          required clock,
        }) => IosCallLifecycleAdapter(
          videoEnabled: privacyFlags['video_call_v2_enabled'] == true,
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
          nativeEvents: lifecycleEventStream ?? const Stream<Object?>.empty(),
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
    nowMs: clockMs ?? () => 2_000_000,
    onGraphBuilt: graphs.add,
  );
  if (cleanupTimeout == null) {
    addTearDown(() async {
      await composition.shutdown();
      router.dispose();
      await p2p.messages.close();
      await tokenEvents.close();
      if (databaseOverride == null) await database.close();
    });
  } else {
    // Registered teardowns run in reverse order, outside the widget fake zone.
    // Separate callbacks preserve every failure and still release later owners
    // if shutdown or a stream close exceeds its real-time bound.
    if (databaseOverride == null) {
      addTearDown(() => database.close().timeout(cleanupTimeout));
    }
    addTearDown(() => tokenEvents.close().timeout(cleanupTimeout));
    addTearDown(() => p2p.messages.close().timeout(cleanupTimeout));
    addTearDown(router.dispose);
    addTearDown(() => composition.shutdown().timeout(cleanupTimeout));
  }
  return _ProductionIosFixture(
    composition: composition,
    bridge: bridge,
    lifecycleMethods: lifecycleMethods,
    capabilityArguments: capabilityArguments,
    tokenEvents: tokenEvents,
    graphs: graphs,
    issuedCallWakeHandleStore: issuedStore ?? callWakeStores.issued,
    receivedCallWakeHandleStore: callWakeStores.received,
    p2p: p2p,
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
  // Zero-delay turns alone ran out under CPU load while real async work was
  // still settling, so finish on a wall-clock bound instead.
  final waited = Stopwatch()..start();
  while (!predicate() && waited.elapsed < const Duration(seconds: 5)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
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
  bool outgoing = false,
  List<CallAudioOutputRoute> supportedRoutes = const <CallAudioOutputRoute>[
    CallAudioOutputRoute.earpiece,
    CallAudioOutputRoute.speaker,
  ],
  CallAudioOutputRoute initialRoute = CallAudioOutputRoute.speaker,
  NativeCallLifecycleAdapter Function(CallCoordinator)? nativeLifecycleFactory,
  MicrophoneCaptureLeaseCoordinator? microphoneCaptureLeases,
  Stream<NetworkPathOutcome>? networkPathOutcomes,
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
    microphoneCaptureLeases: microphoneCaptureLeases,
    networkPathOutcomes: networkPathOutcomes,
    networkEffectsAllowed: () => true,
    nowMs: () => nowMs,
  );
  await coordinator.dispatch(
    CallEvent(
      type: outgoing ? CallEventType.place : CallEventType.remoteInvite,
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

class _ProductionSpeakerRouteEngine implements CallEngine {
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

final class _InitialVideoGraphEngine extends _ProductionSpeakerRouteEngine
    implements CallVideoEngine {
  _InitialVideoGraphEngine()
    : super(const [
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.speaker,
      ]);
  final eventController = StreamController<CallEngineEvent>.broadcast(
    sync: true,
  );
  final candidateController = StreamController<CallIceCandidate>.broadcast(
    sync: true,
  );
  Future<void>? closeGate;
  int restarts = 0;
  @override
  int get iceGeneration => restarts;
  @override
  Future<int> restartIce({List<CallIceServer>? iceServers}) async => ++restarts;
  int eventSubscriptions = 0;
  int candidateSubscriptions = 0;
  @override
  Stream<CallEngineEvent> get events {
    eventSubscriptions++;
    return eventController.stream;
  }

  @override
  Stream<CallIceCandidate> get localCandidates {
    candidateSubscriptions++;
    return candidateController.stream;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    await closeGate;
    await super.close();
    await eventController.close();
    await candidateController.close();
  }

  int binds = 0;
  _GraphVideoSession? video;
  @override
  CallVideoSession bindV2Video({
    required CallId callId,
    required bool localIsCaller,
    required CallWireVersion wireVersion,
    required bool Function() canApply,
    bool videoEnabled = false,
  }) {
    expect(videoEnabled, isTrue);
    expect(wireVersion, CallWireVersion.v2);
    binds++;
    return video ??= _GraphVideoSession(callId, canApply);
  }
}

final class _GraphVideoToken implements CallVideoNegotiation {
  _GraphVideoToken(
    this.callId,
    this.negotiationId,
    this.mediaRevision,
    this.media,
  );
  @override
  final CallId callId;
  @override
  final String negotiationId;
  @override
  final int mediaRevision;
  @override
  final CallMediaKind media;
}

final class _GraphVideoSession
    implements
        CallVideoSession,
        CallVideoPictureInPictureSource,
        CallVideoPresentationSource,
        CallVideoCameraSwitch,
        CallVideoQualityEnvironmentConsumer,
        CallVideoSdpReconciler {
  _GraphVideoSession(this.callId, this.canApply);
  CallVideoSdpReconciliationOutcome recoveryReconciliation =
      CallVideoSdpReconciliationOutcome.unreconciled;
  @override
  Future<CallVideoSdpReconciliationOutcome> reconcilePending(
    CallVideoNegotiation token, {
    required bool Function() canApply,
  }) async =>
      !closed &&
          (identical(this.token, token) || identical(retiredToken, token)) &&
          canApply()
      ? recoveryReconciliation
      : CallVideoSdpReconciliationOutcome.unreconciled;
  int pipEpoch = 0;
  @override
  Stream<void> get pictureInPictureSourceChanges =>
      controller.stream.map((_) {});
  @override
  CallPipSource? get pictureInPictureSource {
    final current = token;
    final epoch = pipEpoch;
    if (closed || current == null || !remoteTrack) return null;
    return CallPipSource(
      negotiation: current,
      rendererEpoch: epoch,
      peerConnectionId: 'graph-peer',
      remoteTrackId: 'remote-$epoch',
      isCurrent: () =>
          !closed &&
          identical(token, current) &&
          remoteTrack &&
          pipEpoch == epoch,
    );
  }

  final qualityEnvironments = <CallVideoQualityEnvironment>[];
  CallVideoQualityEnvironment? environmentAtCameraStart;
  @override
  void updateQualityEnvironment(CallVideoQualityEnvironment environment) {
    qualityEnvironments.add(environment);
  }

  @override
  final CallId callId;
  final bool Function() canApply;
  final controller = StreamController<CallVideoPresentationState>.broadcast(
    sync: true,
  );
  final views = <CallVideoRendererSlot, CallVideoView>{};
  final attachments = <CallVideoRendererSlot>[];
  CallVideoNegotiation? token;
  CallVideoNegotiation? retiredToken;
  int commits = 0;
  int cameraStarts = 0;
  CallLocalCameraGrant? lastCameraGrant;
  int cameraSwitches = 0;
  int readsBeforeSubscription = 0;
  bool cameraOn = false;
  bool remoteTrack = false;
  bool closed = false;
  Completer<bool>? stopGate;
  @override
  bool get hasPendingCleanup => stopGate != null && !stopGate!.isCompleted;
  @override
  Stream<CallVideoPresentationState> get presentationChanges =>
      controller.stream;
  CallVideoPresentationState _state(CallVideoRendererSlot slot) =>
      CallVideoPresentationState(
        callId: callId,
        negotiation: token,
        slot: slot,
        hasTrack: slot == CallVideoRendererSlot.local ? cameraOn : remoteTrack,
        view: views[slot],
      );
  @override
  CallVideoPresentationState presentationFor(CallVideoRendererSlot slot) {
    if (!controller.hasListener) readsBeforeSubscription++;
    return _state(slot);
  }

  void emit(CallVideoRendererSlot slot) {
    if (!controller.isClosed) controller.add(_state(slot));
  }

  void replaceRemoteTrack() {
    pipEpoch++;
    views.remove(CallVideoRendererSlot.remote);
    remoteTrack = true;
    emit(CallVideoRendererSlot.remote);
  }

  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) => token = _GraphVideoToken(callId, negotiationId, mediaRevision, media);
  CallSessionDescription _description(CallSessionDescriptionType type) =>
      CallSessionDescription(
        type: type,
        value: 'fixture-sdp',
        fingerprint: 'fixture-fingerprint',
      );
  @override
  Future<CallSessionDescription> createOffer(
    CallVideoNegotiation token,
  ) async => _description(CallSessionDescriptionType.offer);
  @override
  Future<CallSessionDescription> createAnswer(
    CallVideoNegotiation token,
  ) async => _description(CallSessionDescriptionType.answer);
  @override
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {}
  @override
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {}
  @override
  Future<void> commit(CallVideoNegotiation token) async {
    commits++;
  }

  @override
  Future<bool> rollbackPending(CallVideoNegotiation token) async => true;
  @override
  Future<bool> setLocalCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  ) async {
    if (!canApply() || !identical(this.token, token) || !grant.isCurrent()) {
      return false;
    }
    environmentAtCameraStart = qualityEnvironments.lastOrNull;
    lastCameraGrant = grant;
    cameraStarts++;
    cameraOn = true;
    emit(CallVideoRendererSlot.local);
    return true;
  }

  @override
  Future<bool> stopLocalCamera() {
    cameraOn = false;
    views.remove(CallVideoRendererSlot.local);
    emit(CallVideoRendererSlot.local);
    return stopGate?.future ?? Future.value(true);
  }

  @override
  Future<CallVideoView?> attachRenderer(
    CallVideoNegotiation token,
    CallVideoRendererSlot slot,
  ) async {
    if (closed || !identical(this.token, token)) return null;
    attachments.add(slot);
    final view = CallVideoView(
      textureId: 100 + attachments.length,
      width: 640,
      height: 480,
    );
    views[slot] = view;
    emit(slot);
    return view;
  }

  @override
  Future<bool> detachRenderer(CallVideoRendererSlot slot) async {
    views.remove(slot);
    emit(slot);
    return true;
  }

  @override
  Future<bool> switchCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  ) async {
    if (!cameraOn || !grant.isCurrent() || !identical(this.token, token)) {
      return false;
    }
    cameraSwitches++;
    return true;
  }

  @override
  Future<bool> retireVideo() async {
    cameraOn = false;
    remoteTrack = false;
    retiredToken = token ?? retiredToken;
    token = null;
    views.clear();
    for (final slot in CallVideoRendererSlot.values) {
      emit(slot);
    }
    return true;
  }

  @override
  Future<bool> retryCleanup() async => !hasPendingCleanup;
  @override
  Future<bool> close() async {
    closed = true;
    await retireVideo();
    await controller.close();
    return true;
  }
}

final class _VideoEntryMicrophonePermission
    implements CallMicrophonePermission {
  _VideoEntryMicrophonePermission({this.gate});
  final Completer<MicPermissionStatus>? gate;
  int requests = 0;
  @override
  Future<MicPermissionStatus> request() async {
    requests++;
    return gate == null ? MicPermissionStatus.granted : await gate!.future;
  }
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

final class _FailingHeadlessCheckpointReadStore extends FakeSecureKeyStore {
  bool failCheckpointRead = false;
  int failedCheckpointReads = 0;

  @override
  Future<String?> read(String key) async {
    if (failCheckpointRead && key == 'vc2_active_call_history_v1') {
      failedCheckpointReads++;
      throw StateError('fixture checkpoint storage unavailable');
    }
    return super.read(key);
  }
}

const _killedCallHandle = '33333333-3333-4333-8333-333333333333';

CallSignal _killedCallSignal(CallSignalType event) => CallSignal.create(
  callId: _callA,
  messageId: event == CallSignalType.invite
      ? '00000000-0000-4000-8000-000000000023'
      : '00000000-0000-4000-8000-000000000024',
  event: event,
  senderAccountPeerId: 'remote-account',
  senderDevicePeerId: 'remote-account',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-account',
  senderSequence: event == CallSignalType.invite ? 1 : 2,
  iceGeneration: 0,
  createdAtMs: event == CallSignalType.invite ? 2_000_000 : 2_035_000,
  expiresAtMs: event == CallSignalType.invite ? 2_045_000 : 2_080_000,
  payload: event == CallSignalType.invite
      ? const <String, Object?>{}
      : const <String, Object?>{'reason': 'local_hangup'},
);

String _killedCallEnvelope(CallSignal signal, String handle) => jsonEncode({
  'type': 'call_signal',
  'version': '1',
  'message_id': signal.messageId,
  'call_handle': handle,
  'expires_at_ms': signal.expiresAtMs,
  'kem': base64Encode([1]),
  'ciphertext': base64Encode([2]),
  'nonce': base64Encode([3]),
  'signature': base64Encode([4]),
});

/// Runs the production admission, recorder, SQL projector and missed-card
/// policy. Only transport/crypto responses and notification delivery are fake.
Future<void> _runKilledCallHeadlessTerminal({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required IdentityModel localIdentity,
  required List<String> missedCards,
  Future<void> Function()? afterAuthentication,
}) async {
  final terminal = _killedCallSignal(CallSignalType.terminate);
  final bridge = _Bridge();
  bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
  bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(terminal.toMap()),
  };
  bridge.responses['call_retrieve_v1'] = {
    'ok': true,
    'events': [
      {
        'callHandle': _killedCallHandle,
        'messageId': terminal.messageId,
        'senderPeerId': 'remote-account',
        'recipientDevicePeerId': 'local-account',
        'envelope': _killedCallEnvelope(terminal, _killedCallHandle),
        'receiptAtMs': terminal.createdAtMs,
        'expiresAtMs': terminal.expiresAtMs,
      },
    ],
    'receiptAtMs': terminal.createdAtMs,
    'expiresAtMs': terminal.expiresAtMs,
    'hasMore': false,
  };
  bridge.responses['call_ack_v1'] = {'ok': true, 'acked': 1};
  final admission = IncomingCallPrePresentationAdmission(
    codec: SecureCallEnvelopeCodec(
      crypto: BridgeCallEnvelopeCrypto(bridge: bridge),
      nowMs: () => terminal.createdAtMs,
    ),
    trustedRosterProvider: DatabaseCallTrustedRosterProvider(database),
    localAuthorityProvider: () async => const CallLocalDeviceAuthority(
      accountPeerId: 'local-account',
      devicePeerId: 'local-account',
      mlKemSecretKey: 'local-mlkem-secret-key',
    ),
  );
  var authenticated = false;
  final session = MailboxProductionHeadlessCallAdmissionSession(
    mailboxClient: BridgeCallMailboxClient(bridge: bridge),
    authenticateEvent: ({required invocation, required event}) async {
      final admitted = await admission.authenticateMailboxEvent(
        nativeCallId: invocation.callId,
        wakeExpiresAtMs: invocation.expiresAtMs,
        event: event,
      );
      authenticated = true;
      await afterAuthentication?.call();
      return HeadlessAuthenticatedMailboxEvent(
        event: admitted.signal.event,
        signal: admitted.signal,
        rollbackReplay: admitted.rollbackReplay,
      );
    },
    historyRecorder: createProductionHeadlessCallHistoryRecorder(
      database: database,
      secureKeyStore: secureKeyStore,
      localIdentity: localIdentity,
      notifier: MissedCallNotifier(
        post:
            ({
              required contactAccountPeerId,
              required title,
              required body,
            }) async {
              missedCards.add(body);
            },
        resolveContactName: (_) async => 'Remote contact',
        isSuppressed: (_) async => false,
        missedBody: 'Missed voice call',
        unknownCallerTitle: 'Unknown caller',
      ),
    ),
    closeResources: () async => const HeadlessCallAdmissionCleanup(
      databaseClosed: true,
      leaseReleased: true,
    ),
  );
  expect(
    await session.evaluate(
      HeadlessCallAdmissionInvocation(
        nonce: '11111111-1111-4111-8111-111111111111',
        callId: _killedCallHandle,
        wakeHandle: '33333333333343338333333333333333',
        expiresAtMs: terminal.expiresAtMs,
      ),
    ),
    HeadlessCallAdmissionDisposition.terminal,
  );
  expect(
    authenticated,
    isTrue,
    reason: 'the real admission gate must authenticate before history work',
  );
  await session.close();
}

Future<Database> _openKilledCallDatabase(String path) {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

final class _ProcessLossEngine extends _ProductionSpeakerRouteEngine {
  int restarts = 0;
  int localDescriptions = 0;
  int remoteDescriptions = 0;
  @override
  int get iceGeneration => restarts;
  final _events = StreamController<CallEngineEvent>.broadcast(sync: true);
  @override
  Stream<CallEngineEvent> get events => _events.stream;
  @override
  Future<void> close() async {
    if (isClosed) return;
    await super.close();
    await _events.close();
  }

  _ProcessLossEngine()
    : super(const [
        CallAudioOutputRoute.earpiece,
        CallAudioOutputRoute.speaker,
      ]);
  static const _fingerprint =
      'sha-256 AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:'
      'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA';
  @override
  Future<CallSessionDescription> createOffer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.offer,
        value: 'fixture-local-offer',
        fingerprint: _fingerprint,
      );
  @override
  Future<CallSessionDescription> createAnswer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.answer,
        value: 'fixture-local-answer',
        fingerprint: _fingerprint,
      );
  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    localDescriptions++;
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    remoteDescriptions++;
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}
  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) async =>
      ++restarts;
}

const _graphCellularQuality = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.cellular,
  lowDataMode: false,
  metered: true,
  thermalState: CallVideoThermalState.nominal,
);
const _graphCriticalQuality = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.wifi,
  lowDataMode: false,
  metered: false,
  thermalState: CallVideoThermalState.critical,
);

final class _GraphQualitySource implements CallVideoQualityEnvironmentSource {
  _GraphQualitySource({
    CallVideoQualityEnvironment initial = CallVideoQualityEnvironment.unknown,
    this.startGate,
    this.failStart = false,
  }) : _current = initial {
    addTearDown(() async {
      final gate = startGate;
      if (gate != null && !gate.isCompleted) gate.complete();
      await close();
    });
  }
  final Completer<void>? startGate;
  final bool failStart;
  final _events = StreamController<CallVideoQualityEnvironment>.broadcast(
    sync: true,
  );
  CallVideoQualityEnvironment _current;
  bool _closed = false;
  int starts = 0, listens = 0, cancellations = 0, closes = 0;
  @override
  CallVideoQualityEnvironment get current => _current;
  @override
  Stream<CallVideoQualityEnvironment> get changes {
    listens++;
    return Stream<CallVideoQualityEnvironment>.multi((subscriber) {
      subscriber.add(_current);
      final live = _events.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = () {
        cancellations++;
        return live.cancel();
      };
    });
  }

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('optional observation failed');
    await startGate?.future;
  }

  void emit(CallVideoQualityEnvironment environment) {
    _current = environment;
    if (!_events.isClosed) _events.add(environment);
  }

  void emitError() => _events.addError(StateError('optional source error'));
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closes++;
    _current = CallVideoQualityEnvironment.unknown;
    await _events.close();
  }
}

const _vui7Bound = Duration(seconds: 5);

Future<ForegroundCallProjection> _vui7EndProjection(
  _ProductionIosFixture fixture, {
  CallEventType? event,
  CallEndReason? reason,
}) async {
  final graph = fixture.graphs.single;
  final id = graph.coordinator.activeSession!.callId!;
  final terminal = Completer<ForegroundCallProjection>();
  final sub = (fixture.composition as ForegroundCallCapability).changes.listen((p) {
    if (p != null && p.session.callId == id && p.session.isTerminal &&
        !terminal.isCompleted) terminal.complete(p);
  });
  try {
    if (event == null) {
      expect(await fixture.composition.end(id).timeout(_vui7Bound),
          ForegroundCallActionResult.applied);
    } else {
      await graph.coordinator.dispatch(CallEvent(
        type: event,
        eventId: 'vui7-terminal-${event.name}',
        callId: id,
        occurredAt: graph.coordinator.clock(),
        endReason: reason,
        timeoutKind: event == CallEventType.timeout ? CallTimeoutKind.noAnswer : null,
      )).timeout(_vui7Bound);
    }
    return await terminal.future.timeout(_vui7Bound);
  } finally {
    await sub.cancel().timeout(_vui7Bound);
  }
}

/// Drive the real machine's acknowledged settlement, using the existing graph
/// phase fixture seam. onResume is the public projection refresh already used
/// by BL16-UPGRADE above; no terminal projection is fabricated.
Future<void> _vui7Settle(
  ProductionCallSignalingGraph graph, CallMediaKind media,
) async {
  final id = graph.coordinator.activeSession!.callId!;
  final owner = graph.videoOwners![id]!.mediaSwitch!;
  final machine = owner.machine;
  final revision = machine.settledRevision;
  final now = owner.nowMs();
  const switchId = '77777777-7777-4777-8777-777777777779';
  expect(machine.request(MediaSwitchRequest(
    id: switchId, baseRevision: revision, target: media,
    requesterIsCaller: true, createdAtMs: now, deadlineMs: now + 30000,
  ), freshUpgradeAdmitted: true).accepted, isTrue);
  if (media == CallMediaKind.video) {
    expect(machine.respond(id: switchId, baseRevision: revision,
      fromCaller: false, response: MediaSwitchResponse.accept).accepted, isTrue);
  }
  for (final description in MediaSwitchDescription.values) {
    expect(machine.descriptionApplied(id: switchId, revision: revision + 1,
      media: media, description: description,
      local: description == MediaSwitchDescription.offer
          ? machine.localIsCaller : !machine.localIsCaller).accepted, isTrue);
  }
  expect(machine.receiveCommit(id: switchId, revision: revision + 1,
    media: media).accepted, isTrue);
  expect(machine.settledMedia, media);
  await graph.onResume().timeout(_vui7Bound);
  expect(graph.current!.video!.presentation.agreedMedia, media);
}

void _vui7TerminalMediaTests() {
  for (final row in [
    'video', 'audio answer', 'upgrade', 'downgrade', 'pending upgrade',
    'camera off', 'reconnect after upgrade',
  ]) {
    test('VUI7 terminal media uses last agreement: $row', () async {
      final initiallyAudio = ['audio answer', 'upgrade', 'pending upgrade',
        'reconnect after upgrade'].contains(row);
      final (fixture, engine) = await _connectedGraphVideo(
        cleanupTimeout: _vui7Bound,
        acceptedMedia: initiallyAudio ? CallMediaKind.audio : CallMediaKind.video,
      ).timeout(_vui7Bound);
      final graph = fixture.graphs.single;
      var expected = initiallyAudio ? CallMediaKind.audio : CallMediaKind.video;
      if (row == 'upgrade' || row == 'reconnect after upgrade') {
        await _vui7Settle(graph, CallMediaKind.video);
        expected = CallMediaKind.video;
      } else if (row == 'downgrade') {
        await _vui7Settle(graph, CallMediaKind.audio);
        expected = CallMediaKind.audio;
      } else if (row == 'pending upgrade') {
        expect(await graph.applyVideoIntent(_callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.requestVideo),
        ).timeout(_vui7Bound), ForegroundCallActionResult.applied);
        await _untilGraphVideo(
          () => graph.current!.video!.presentation.outgoingUpgradeId != null,
        );
        expect(graph.current!.video!.presentation.outgoingUpgradeId, isNotNull);
        expect(graph.current!.video!.presentation.agreedMedia, CallMediaKind.audio);
      } else if (row == 'camera off') {
        expect(engine.video!.cameraStarts, 0);
        expect(engine.video!.cameraOn, isFalse);
        // Off is an available intent only after a genuine explicit Camera tap.
        // The normal fixture permission callback grants the current request;
        // no consent token or media state is installed by the test.
        expect(await graph.applyVideoIntent(_callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOn),
        ).timeout(_vui7Bound), ForegroundCallActionResult.applied);
        expect(engine.video!.cameraStarts, 1);
        expect(engine.video!.cameraOn, isTrue);
        expect(graph.current!.video!.presentation.localCamera, CallCameraState.on);
        expect(await graph.applyVideoIntent(_callA,
          generation: graph.current!.video!.generation,
          intent: const CallVideoIntent(CallVideoAction.turnCameraOff),
        ).timeout(_vui7Bound), ForegroundCallActionResult.applied);
        expect(graph.current!.video!.presentation.localCamera, CallCameraState.off);
        expect(engine.video!.cameraOn, isFalse);
        expect(graph.current!.video!.presentation.agreedMedia, CallMediaKind.video);
      }
      if (row == 'reconnect after upgrade') {
        await graph.coordinator.dispatch(CallEvent(
          type: CallEventType.mediaLost, eventId: 'vui7-media-lost',
          callId: _callA, occurredAt: graph.coordinator.clock(),
        )).timeout(_vui7Bound);
        expect(graph.coordinator.activeSession!.state, CallState.reconnecting);
        expect(graph.videoOwners![_callA]!.mediaSwitch, isNull,
          reason: 'terminal classification must survive unavailable live media owner');
      }
      final terminal = await _vui7EndProjection(fixture);
      expect(terminal.terminalMedia, expected);
      expect(terminal.session.callId, _callA);
      expect(terminal.video, isNull);
      expect(graph.current, isNull);
      expect(engine.video!.cameraStarts, row == 'camera off' ? 1 : 0);
      expect(engine.configuration!.captureVideo, isFalse);
    }, timeout: const Timeout.factor(1));
  }

  for (final ending in ['unanswered', 'declined', 'busy']) {
    test('VUI7 unanswered requested video retains type after $ending', () async {
      final fixture = await _createProductionIosFixture(
        cleanupTimeout: _vui7Bound,
        outgoingContactAccountPeerId: 'video-contact',
        privacyFlags: const {'video_call_v2_enabled': true},
      ).timeout(_vui7Bound);
      await fixture.composition.start().timeout(_vui7Bound);
      await _configureCancellationEndpoint(fixture, 'video-contact', video: true)
          .timeout(_vui7Bound);
      await _deliverGraphVideoInvite(fixture).timeout(_vui7Bound);
      expect(fixture.graphs.single.coordinator.activeSession!.state, CallState.ringing);
      final terminal = await _vui7EndProjection(fixture,
        event: ending == 'unanswered' ? CallEventType.timeout : CallEventType.remoteReject,
        reason: ending == 'busy' ? CallEndReason.busy : null,
      );
      expect(terminal.terminalMedia, CallMediaKind.video);
      expect(terminal.session.connectedAt, isNull);
      expect(terminal.session.endReason, ending == 'busy' ? CallEndReason.busy
          : ending == 'declined' ? CallEndReason.declined : CallEndReason.noAnswer);
      expect(terminal.video, isNull);
    }, timeout: const Timeout.factor(1));
  }

  test('VUI7 successor requested video cannot inherit predecessor settled audio', () async {
    const priorHandle = '33333333-3333-4333-8333-333333333333';
    var terminalCommitted = false;
    var terminalAcknowledged = false;
    final (fixture, _) = await _connectedGraphVideo(
      cleanupTimeout: _vui7Bound,
      nativeOverride: (method, arguments) async {
        if (arguments['callHandle'] == priorHandle &&
            ((method == 'project' && arguments['state'] == 'ended') ||
                method == 'end')) {
          terminalCommitted = true;
        }
        // Native project/end commits its terminal journal before returning.
        // Keep that exact receipt available until the adapter acknowledges it.
        if (method == 'attach' && terminalCommitted && !terminalAcknowledged) {
          return {
            'version': 1,
            'descriptor': {
              'callHandle': priorHandle,
              'expiresAtMs': 2040000,
              'presented': true,
              'phase': 'journal',
              'direction': 'incoming',
            },
            'nativeCallId': priorHandle,
            'highestSequence': 3,
            'events': [
              {
                'callHandle': priorHandle,
                'sequence': 3,
                'eventId': '66666666-6666-4666-8666-666666666669',
                'type': 'end',
                'occurredAtMs': 2000002,
              },
            ],
          };
        }
        if (method == 'acknowledge' &&
            arguments['callHandle'] == priorHandle &&
            arguments['disposition'] == 'TERMINAL' &&
            arguments['throughSequence'] == 3) {
          terminalAcknowledged = true;
        }
        return null;
      },
    ).timeout(_vui7Bound);
    final graph = fixture.graphs.single;
    await _vui7Settle(graph, CallMediaKind.audio);
    final previous = await _vui7EndProjection(fixture);
    await _untilGraphVideo(() => terminalAcknowledged &&
        !graph.iosCallLifecycleAdapter!.isBoundTo(_callA));
    expect(terminalCommitted, isTrue);
    expect(terminalAcknowledged, isTrue);
    expect(graph.iosCallLifecycleAdapter!.isBoundTo(_callA), isFalse);
    await _vui7DeliverSuccessor(fixture).timeout(_vui7Bound);
    expect(graph.coordinator.activeSession!.callId, _callB);
    final successor = await _vui7EndProjection(fixture, event: CallEventType.decline);
    expect(successor.terminalMedia, CallMediaKind.video);
    expect(previous.terminalMedia, CallMediaKind.audio);
    expect(previous.session.callId, _callA);
    expect(successor.session.callId, _callB);
    expect(successor.video, isNull);
  }, timeout: const Timeout.factor(1));
}

// A successor needs fresh replay and native presentation identities.
Future<void> _vui7DeliverSuccessor(_ProductionIosFixture fixture) async {
  final graph = fixture.graphs.single;
  final device = (await graph.trustedRosterProvider.loadForContact(
    'video-contact',
  )).devices.single;
  final signal = CallSignalV2.fromMap({
    'schema': CallSignalV2.schema,
    'call_id': _callB.value,
    'message_id': '00000000-0000-4000-8000-000000000093',
    'event': 'invite',
    'sender_account_peer_id': 'video-contact',
    'sender_device_peer_id': device.devicePeerId,
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-account',
    'sender_sequence': 1,
    'ice_generation': 0,
    'created_at_ms': 2_000_000,
    'expires_at_ms': 2_040_000,
    'payload': {
      'media': 'video',
      'camera': 'off',
      'capabilities': ['audio', 'video'],
    },
  }, videoEnabled: true);
  fixture.bridge.responses['message.decrypt'] = {
    'ok': true,
    'plaintext': jsonEncode(signal.toMap()),
  };
  fixture.p2p.messages.add(
    ChatMessage(
      from: device.devicePeerId,
      to: 'local-account',
      content: jsonEncode({
        'type': 'call_signal',
        'version': '1',
        'message_id': signal.messageId,
        'call_handle': '33333333-3333-4333-8333-333333333339',
        'expires_at_ms': signal.expiresAtMs,
        'kem': base64Encode([1]),
        'ciphertext': base64Encode([2]),
        'nonce': base64Encode([3]),
        'signature': base64Encode([4]),
      }),
      timestamp: _callNow.toIso8601String(),
      isIncoming: true,
      transport: 'direct',
    ),
  );
  await _untilComposition(
    () => graph.coordinator.activeSession?.state == CallState.ringing,
  );
}

void _vui7LegacyAndBridgeTests() {
  test('VUI7 accepted audio before connection outranks requested video', () async {
    final events = StreamController<Object?>.broadcast(sync: true);
    addTearDown(() => events.close().timeout(_vui7Bound));
    final fixture = await _createProductionIosFixture(
      cleanupTimeout: _vui7Bound,
      outgoingContactAccountPeerId: 'video-contact',
      privacyFlags: const {'video_call_v2_enabled': true},
      microphonePermission: const _GrantedCallMicrophonePermission(),
      lifecycleEventStream: events.stream,
      callEngineFactory: (_) => _InitialVideoGraphEngine(),
      lifecycleOverride: (method, _) async => method == 'readAudioState'
          ? {'version': 1, 'active': true, 'muted': false,
             'route': 'system_default', 'availableRoutes': ['system_default']}
          : null,
    ).timeout(_vui7Bound);
    await fixture.composition.start().timeout(_vui7Bound);
    await _configureCancellationEndpoint(fixture, 'video-contact', video: true)
        .timeout(_vui7Bound);
    _vui7ConfigureTurn(fixture);
    await _deliverGraphVideoInvite(fixture).timeout(_vui7Bound);
    final graph = fixture.graphs.single;
    expect(await graph.answerWithMedia(_callA,
      generation: graph.current!.video!.generation,
      acceptedMedia: CallMediaKind.audio).timeout(_vui7Bound),
      ForegroundCallActionResult.applied);
    const handle = '33333333-3333-4333-8333-333333333333';
    events.add({
      'version': 1,
      'descriptor': {'callHandle': handle, 'expiresAtMs': 2040000,
        'presented': true, 'phase': 'journal', 'direction': 'incoming'},
      'nativeCallId': handle, 'highestSequence': 2,
      'events': [
        {'callHandle': handle, 'sequence': 1,
          'eventId': '55555555-5555-4555-8555-555555555555',
          'type': 'presented', 'occurredAtMs': 2000000},
        {'callHandle': handle, 'sequence': 2,
          'eventId': '66666666-6666-4666-8666-666666666666',
          'type': 'answer', 'occurredAtMs': 2000001},
      ],
    });
    await _untilGraphVideo(() =>
      graph.videoContexts!.read(_callA)?.initialAcceptedMedia == CallMediaKind.audio &&
      _upgradeSignals(fixture, 'accept').isNotEmpty);
    expect(graph.videoContexts!.read(_callA)!.requestedMedia, CallMediaKind.video);
    expect(graph.coordinator.activeSession!.connectedAt, isNull);
    final terminal = await _vui7EndProjection(fixture);
    expect(terminal.terminalMedia, CallMediaKind.audio);
    expect(terminal.session.connectedAt, isNull);
    expect(terminal.video, isNull);
  }, timeout: const Timeout.factor(1));

  test('VUI7 known legacy voice terminal retains audio type', () async {
    final fixture = await _createProductionIosFixture(
      cleanupTimeout: _vui7Bound,
      outgoingContactAccountPeerId: 'remote-account',
      privacyFlags: const {'video_call_v2_enabled': true},
    ).timeout(_vui7Bound);
    await fixture.composition.start().timeout(_vui7Bound);
    await _configureCancellationEndpoint(fixture, 'remote-account')
        .timeout(_vui7Bound);
    final invite = _killedCallSignal(CallSignalType.invite);
    fixture.bridge.responses['message.decrypt'] = {
      'ok': true, 'plaintext': jsonEncode(invite.toMap()),
    };
    fixture.p2p.messages.add(ChatMessage(
      from: 'remote-account', to: 'local-account',
      content: _killedCallEnvelope(invite, _killedCallHandle),
      timestamp: _callNow.toIso8601String(), isIncoming: true, transport: 'direct',
    ));
    await _untilGraphVideo(() =>
      fixture.graphs.single.coordinator.activeSession?.incomingValidated == true);
    final graph = fixture.graphs.single;
    expect(graph.videoContexts!.read(invite.callId)!.wireVersion, CallWireVersion.v1);
    final terminal = await _vui7EndProjection(fixture, event: CallEventType.decline);
    expect(terminal.terminalMedia, CallMediaKind.audio);
    expect(terminal.video, isNull);
  }, timeout: const Timeout.factor(1));

  test('VUI7 real terminal through redial creates fresh video invite with camera off', () async {
    const priorHandle = '33333333-3333-4333-8333-333333333333';
    var terminalCommitted = false;
    var terminalAcknowledged = false;
    late final _ProductionIosFixture fixture;
    final engine = _InitialVideoGraphEngine();
    String? outgoingHandle;
    int? outgoingExpiry;
    var cameraPermissionRequests = 0;
    fixture = await _createProductionIosFixture(
      cleanupTimeout: _vui7Bound,
      microphonePermission: const _GrantedCallMicrophonePermission(),
      outgoingContactAccountPeerId: 'video-contact',
      privacyFlags: const {'video_call_v2_enabled': true},
      callEngineFactory: (_) => engine,
      requestCameraPermission: () async {
        cameraPermissionRequests++;
        return true;
      },
      lifecycleOverride: (method, arguments) async {
        if (arguments['callHandle'] == priorHandle &&
            ((method == 'project' && arguments['state'] == 'declined') ||
                method == 'end')) {
          terminalCommitted = true;
        }
        if (method == 'attach' && terminalCommitted && !terminalAcknowledged) {
          return {
            'version': 1,
            'descriptor': {
              'callHandle': priorHandle,
              'expiresAtMs': 2040000,
              'presented': true,
              'phase': 'journal',
              'direction': 'incoming',
            },
            'nativeCallId': priorHandle,
            'highestSequence': 2,
            'events': [
              {
                'callHandle': priorHandle,
                'sequence': 1,
                'eventId': '55555555-5555-4555-8555-555555555591',
                'type': 'presented',
                'occurredAtMs': 2000000,
              },
              {
                'callHandle': priorHandle,
                'sequence': 2,
                'eventId': '66666666-6666-4666-8666-666666666691',
                'type': 'decline',
                'occurredAtMs': 2000001,
              },
            ],
          };
        }
        if (method == 'acknowledge' &&
            arguments['callHandle'] == priorHandle &&
            arguments['disposition'] == 'TERMINAL' &&
            arguments['throughSequence'] == 2) {
          terminalAcknowledged = true;
        }
        if (method == 'registerOutgoingAuthenticated') {
          outgoingHandle = arguments['callHandle']! as String;
          outgoingExpiry = arguments['expiresAtMs']! as int;
          return true;
        }
        if (method == 'attach' && outgoingHandle != null) {
          return {
            'version': 1,
            'descriptor': {'callHandle': outgoingHandle, 'expiresAtMs': outgoingExpiry,
              'presented': true, 'phase': 'preStart', 'direction': 'outgoing'},
            'nativeCallId': outgoingHandle, 'highestSequence': 1,
            'events': [{'callHandle': outgoingHandle, 'sequence': 1,
              'eventId': '00000000-0000-4000-8000-000000000091',
              'type': 'presented', 'occurredAtMs': 2000000}],
          };
        }
        return null;
      },
      ensureOutgoingCallWakeAuthority: (peer) async {
        final issued = await fixture.issuedCallWakeHandleStore.readForContact(peer);
        return issued != null && await fixture.graphs.single
            .markCallWakeHandleDistributed(peer, issued.grant);
      },
    ).timeout(_vui7Bound);
    await fixture.composition.start().timeout(_vui7Bound);
    await _configureCancellationEndpoint(fixture, 'video-contact', video: true)
        .timeout(_vui7Bound);
    _vui7ConfigureTurn(fixture);
    await _deliverGraphVideoInvite(fixture).timeout(_vui7Bound);
    final terminal = await _vui7EndProjection(fixture, event: CallEventType.decline);
    expect(terminal.terminalMedia, CallMediaKind.video);
    final projectionWait = Stopwatch()..start();
    while (!terminalCommitted && projectionWait.elapsed < _vui7Bound) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(terminalCommitted, isTrue,
        reason: 'The native fixture must commit the actual project(declined) journal before waiting for its ACK.');
    await _untilGraphVideo(() => terminalAcknowledged &&
        !fixture.graphs.single.iosCallLifecycleAdapter!.isBoundTo(terminal.session.callId!));
    expect(terminalCommitted, isTrue);
    expect(terminalAcknowledged, isTrue);
    expect(fixture.graphs.single.iosCallLifecycleAdapter!.isBoundTo(terminal.session.callId!), isFalse);
    final controller = CallRedialController(
      capability: () => fixture.composition,
      contactAllowed: (peer) async => peer == 'video-contact',
    );
    expect(await controller.start('video-contact', media: terminal.terminalMedia!,
      isCurrent: () => true).timeout(_vui7Bound), OutgoingCallStartResult.started);
    final fresh = fixture.graphs.single.coordinator.activeSession!;
    expect(fresh.callId, isNot(terminal.session.callId));
    expect(fresh.contactPeerId, terminal.session.contactPeerId);
    await _untilGraphVideo(() => _upgradeSignals(fixture, 'invite').isNotEmpty);
    final invite = _upgradeSignals(fixture, 'invite').single;
    expect(invite['call_id'], fresh.callId!.value);
    expect((invite['payload'] as Map)['media'], 'video');
    expect((invite['payload'] as Map)['camera'], 'off');
    expect(cameraPermissionRequests, 0);
    expect(engine.video?.cameraStarts ?? 0, 0);
    expect(engine.configuration?.captureVideo ?? false, isFalse);
    // No explicit Camera intent was supplied; this leg proves fresh invitation
    // and no capture admission, not native permission behavior after agreement.
  }, timeout: const Timeout.factor(1));
}

void _vui7ConfigureTurn(_ProductionIosFixture fixture) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final credentials = <String, Object?>{
    'ok': true, 'schema': 'turn_credentials', 'version': 1,
    'urls': ['turn:relay.invalid:3478?transport=udp'],
    'username': 'fixture-user', 'password': 'fixture-secret',
    'ttlSeconds': 600, 'serverTimeMs': now, 'expiresAtMs': now + 600000,
  };
  fixture.bridge.responses['relay:turn_credentials_v1'] = credentials;
  fixture.bridge.responses['turn_credentials_with_diagnostics_v1'] = credentials;
}

Future<void> _vui7JoinedPumpUntil(
  WidgetTester tester,
  bool Function() ready,
  String boundary,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < _vui7Bound) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
  await tester.pump();
  expect(ready(), isTrue, reason: 'VUI7 joined $boundary exceeded five seconds');
}

void _vui7JoinedBridgeTests() {
  for (final closeDuringPreflight in [false, true]) {
    testWidgets(
      'VUI7 real graph joined overlay redial ${closeDuringPreflight ? 'Close cancels admission' : 'creates fresh video invitation'}',
      (tester) async {
        const priorHandle = '33333333-3333-4333-8333-333333333333';
        late final _ProductionIosFixture fixture;
        String? outgoingHandle;
        int? outgoingExpiry;
        ({String handle, int sequence, int expiry, String direction})?
            nativeTerminal;
        var priorTerminalAcknowledged = false;
        var cameraPermissions = 0;
        var nativeCameraStarts = 0;
        final connected = await tester.runAsync(
          () => _connectedGraphVideo(
            cleanupTimeout: _vui7Bound,
            permission: () async {
              cameraPermissions++;
              return true;
            },
            ensureOutgoingCallWakeAuthority: (peer) async {
              final issued = await fixture.issuedCallWakeHandleStore.readForContact(peer);
              return issued != null && await fixture.graphs.single
                  .markCallWakeHandleDistributed(peer, issued.grant);
            },
            nativeOverride: (method, arguments) async {
              if (method == 'setLocalCameraActive' && arguments['active'] == true) {
                nativeCameraStarts++;
              }
              final handle = arguments['callHandle'];
              if (handle is String &&
                  ((method == 'project' && arguments['state'] == 'ended') ||
                      method == 'end')) {
                nativeTerminal = (
                  handle: handle,
                  sequence: handle == priorHandle ? 3 : 2,
                  expiry: handle == priorHandle ? 2040000 : outgoingExpiry!,
                  direction: handle == priorHandle ? 'incoming' : 'outgoing',
                );
              }
              if (method == 'registerOutgoingAuthenticated') {
                outgoingHandle = arguments['callHandle']! as String;
                outgoingExpiry = arguments['expiresAtMs']! as int;
              }
              final terminal = nativeTerminal;
              if (method == 'acknowledge' && terminal != null &&
                  arguments['callHandle'] == terminal.handle &&
                  arguments['throughSequence'] == terminal.sequence &&
                  arguments['disposition'] == 'TERMINAL') {
                if (terminal.handle == priorHandle) priorTerminalAcknowledged = true;
                nativeTerminal = null;
              }
              if (method == 'attach' && terminal != null) {
                return {
                  'version': 1,
                  'descriptor': {'callHandle': terminal.handle,
                    'expiresAtMs': terminal.expiry, 'presented': true,
                    'phase': 'journal', 'direction': terminal.direction},
                  'nativeCallId': terminal.handle,
                  'highestSequence': terminal.sequence,
                  'events': [{'callHandle': terminal.handle,
                    'sequence': terminal.sequence,
                    'eventId': terminal.handle == priorHandle
                        ? '66666666-6666-4666-8666-666666666693'
                        : '66666666-6666-4666-8666-666666666692',
                    'type': 'end', 'occurredAtMs': 2000002}],
                };
              }
              if (method == 'attach' && outgoingHandle != null) {
                return {
                  'version': 1,
                  'descriptor': {'callHandle': outgoingHandle,
                    'expiresAtMs': outgoingExpiry, 'presented': true,
                    'phase': 'preStart', 'direction': 'outgoing'},
                  'nativeCallId': outgoingHandle, 'highestSequence': 1,
                  'events': [{'callHandle': outgoingHandle, 'sequence': 1,
                    'eventId': '00000000-0000-4000-8000-000000000094',
                    'type': 'presented', 'occurredAtMs': 2000000}],
                };
              }
              return null;
            },
          ).timeout(_vui7Bound),
        );
        expect(connected, isNotNull);
        final (created, engine) = connected!;
        fixture = created;
        final graph = fixture.graphs.single;
        final capability = fixture.composition as ForegroundCallCapability;
        final oldId = graph.current!.session.callId!;
        final oldPeer = graph.current!.session.contactPeerId!;
        final releaseContact = Completer<bool>();
        var contactEntered = false;
        OutgoingCallStartResult? retryResult;
        ForegroundCallActionResult? endResult;
        ForegroundCallProjection? terminalProjection;
        final errors = <Object>[];
        final redial = CallRedialController(
          capability: () => fixture.composition,
          contactAllowed: (peer) async {
            expect(peer, oldPeer);
            contactEntered = true;
            if (!await releaseContact.future.timeout(_vui7Bound)) return false;
            final contacts = await graph.loadWakeEligibleContacts().timeout(_vui7Bound);
            return contacts.any((contact) => contact.contactAccountPeerId == peer);
          },
        );
        final terminalSubscription = capability.changes.listen((projection) {
          if (projection?.session.callId == oldId &&
              projection!.session.isTerminal) {
            terminalProjection = projection;
          }
        });
        try {
          expect(graph.current!.video!.presentation.agreedMedia, CallMediaKind.video);
          expect(graph.current!.video!.presentation.localCamera, CallCameraState.off);
          expect(engine.configuration!.captureVideo, isFalse);
          expect(engine.video!.cameraStarts, 0);
          await tester.pumpWidget(MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
            home: ForegroundCallOverlay(
              capability: capability,
              loadContactDisplayName: (_) async => 'Video contact',
              now: graph.coordinator.clock,
              onCallAgain: (peer, {required media, required isCurrent}) async {
                final result = await redial.start(peer, media: media, isCurrent: isCurrent);
                retryResult = result;
                return result;
              },
              child: const Scaffold(body: Text('Joined retained route')),
            ),
          ));
          await _pumpCallLifecycle(tester);
          expect(find.bySemanticsIdentifier('call_end'), findsOneWidget);
          unawaited(capability.end(oldId).then<void>(
            (result) => endResult = result,
            onError: (Object error, StackTrace _) { errors.add(error); },
          ));
          await _vui7JoinedPumpUntil(tester,
            () => endResult != null || errors.isNotEmpty, 'real End');
          expect(errors, isEmpty);
          expect(endResult, ForegroundCallActionResult.applied);
          await _vui7JoinedPumpUntil(tester,
            () => terminalProjection != null && priorTerminalAcknowledged &&
                !graph.iosCallLifecycleAdapter!.isBoundTo(oldId),
            'terminal projection and native binding release');
          expect(terminalProjection!.terminalMedia, CallMediaKind.video);
          expect(terminalProjection!.video, isNull);
          expect(capability.current, isNull);
          final l10n = lookupAppLocalizations(const Locale('en'));
          final again = find.text(l10n.call_video_call_again);
          final close = find.text(l10n.call_video_close);
          expect(again, findsOneWidget);
          await tester.ensureVisible(again);
          await tester.tap(again);
          await _vui7JoinedPumpUntil(tester, () => contactEntered, 'contact preflight');
          expect(graph.coordinator.activeSession, isNull);
          final button = find.ancestor(of: again,
            matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
          expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
          if (closeDuringPreflight) {
            await tester.ensureVisible(close);
            await tester.tap(close);
            await _pumpCallLifecycle(tester);
            expect(find.byKey(const ValueKey('foreground-call-terminal-notice')), findsNothing);
          }
          releaseContact.complete(true);
          await _vui7JoinedPumpUntil(tester, () => retryResult != null, 'redial result');
          if (closeDuringPreflight) {
            expect(retryResult, OutgoingCallStartResult.canceled);
            expect(graph.coordinator.activeSession, isNull);
            expect(_upgradeSignals(fixture, 'invite'), isEmpty);
            expect(find.text('Joined retained route').hitTestable(), findsOneWidget);
          } else {
            expect(retryResult, OutgoingCallStartResult.started);
            await _vui7JoinedPumpUntil(tester,
              () => _upgradeSignals(fixture, 'invite').isNotEmpty, 'fresh invite');
            final fresh = graph.coordinator.activeSession!;
            expect(fresh.callId, isNot(oldId));
            expect(fresh.contactPeerId, oldPeer);
            final invite = _upgradeSignals(fixture, 'invite').single;
            expect(invite['call_id'], fresh.callId!.value);
            expect((invite['payload'] as Map)['media'], 'video');
            expect((invite['payload'] as Map)['camera'], 'off');
            expect(graph.current!.video!.presentation.localCamera, CallCameraState.off);
            expect(find.byKey(const ValueKey('foreground-call-terminal-notice')), findsNothing);
            expect(find.bySemanticsIdentifier('call_cancel'), findsOneWidget);
          }
          expect(cameraPermissions, 0);
          expect(nativeCameraStarts, 0);
          expect(engine.video!.cameraStarts, 0);
          expect(tester.takeException(), isNull);
          // Invitation-only proof. The retained engine configuration above
          // belongs to the ended call; no fresh-agreement/native capture claim.
        } finally {
          if (!releaseContact.isCompleted) releaseContact.complete(false);
          try {
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            try {
              await terminalSubscription.cancel().timeout(_vui7Bound);
            } finally {
              var shutdownDone = false;
              Object? shutdownError;
              StackTrace? shutdownStack;
              unawaited(fixture.composition.shutdown().then<void>(
                (_) { shutdownDone = true; },
                onError: (Object error, StackTrace stack) {
                  shutdownError = error;
                  shutdownStack = stack;
                  shutdownDone = true;
                },
              ));
              await _vui7JoinedPumpUntil(tester, () => shutdownDone, 'shutdown');
              if (shutdownError != null) {
                Error.throwWithStackTrace(shutdownError!, shutdownStack!);
              }
            }
          }
        }
      },
      timeout: const Timeout.factor(1),
    );
  }
}

const _b7Limit = Duration(seconds: 2);
const _b7ProfileA =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b7ProfileB =
    'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Future<T> _b7Bound<T>(Future<T> future) => future.timeout(_b7Limit);

Future<void> _b7Turn() => _b7Bound(() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}());

Future<void> _b7Until(bool Function() predicate) => _b7Bound(() async {
  final elapsed = Stopwatch()..start();
  while (!predicate() && elapsed.elapsed < _b7Limit) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(predicate(), isTrue, reason: 'B7 fixture boundary was not reached');
}());

final class _B7Timer implements CallTimerHandle {
  _B7Timer(this.due, this.callback);
  final Duration due;
  final Future<void> Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  void cancel() => active = false;
}

final class _B7Clock implements CallTimerScheduler {
  Duration now = Duration.zero;
  final timers = <_B7Timer>[];
  final failures = <Object>[];
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final timer = _B7Timer(now + delay, callback);
    timers.add(timer);
    return timer;
  }

  void _fire(_B7Timer timer) {
    timer.active = false;
    // DartCallTimerScheduler does not await a callback. A checkpoint waiting
    // for the serial call lane must not block an independent activity timer.
    unawaited(timer.callback().catchError((Object error) {
      failures.add(error);
    }));
  }

  Future<void> elapse(Duration delta) => _b7Bound(() async {
    final target = now + delta;
    for (var count = 0; count < 1000; count++) {
      final due = timers.where((t) => t.active && t.due <= target).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) {
        now = target;
        await _b7Turn();
        expect(failures, isEmpty);
        return;
      }
      now = due.first.due;
      _fire(due.first);
      await _b7Turn();
    }
    fail('B7 timer fixture did not quiesce');
  }());

  Future<void> fireQueued(Iterable<_B7Timer> queued) => _b7Bound(() async {
    for (final timer in queued) {
      _fire(timer);
    }
    await _b7Turn();
    expect(failures, isEmpty);
  }());
}

final class _B7CheckpointStore extends FakeSecureKeyStore {
  bool Function()? holdWhen;
  bool failWrite = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  int checkpoints = 0;
  @override
  Future<void> write(String key, String value) async {
    if (key == 'vc2_active_call_history_v1') {
      checkpoints++;
      if (holdWhen?.call() == true && !entered.isCompleted) {
        entered.complete();
        await _b7Bound(release.future);
        if (failWrite) {
          throw StateError('B7 checkpoint fixture failure');
        }
      }
    }
    await super.write(key, value);
  }
}

final class _B7ActivityRig {
  final clock = _B7Clock();
  final reporter = ActiveIdentityReporter(statePath: '/tmp/b7-unused-state.json');
  final store = _B7CheckpointStore();
  final marks = <Map<String, dynamic>>[];
  final capturedAccounts = <String>[];
  _ProductionIosFixture? fixture;
  int wallMs = 2000000;
  int epoch = 71;
  int revision = 0;
  int eventSequence = 0;
  bool initiallyUnarmed = false;
  int handoffs = 0;
  ProductionCallSignalingGraph get graph => fixture!.graphs.single;

  CallActivityMark? capture(String ownAccount) {
    capturedAccounts.add(ownAccount);
    final token = reporter.captureOwner(expectedAccountPeerId: ownAccount);
    if (token == null) {
      return null;
    }
    return () {
      handoffs++;
      reporter.markCaptured(token);
    };
  }

  Future<void> arm({bool enabled = true, String profile = _b7ProfileA}) async {
    reporter.observeIdentity(
      accountPeerId: 'local-account',
      rootPrivateKeyBase64: 'b7-private-root-fixture',
      profileBinding: profile,
    );
    await _b7Bound(reporter.observeConsent((
      enabled: enabled,
      consentEpoch: epoch,
    )));
    await _b7Turn();
  }

  Future<void> _prepare(_ProductionIosFixture created) async {
    fixture = created;
    created.bridge.responseHandlers['active_identity_reporter_v1'] =
        (request) async {
      final payload = Map<String, dynamic>.from(request['payload'] as Map);
      if (payload['op'] == 'configure') {
        revision++;
      }
      if (payload['op'] == 'mark') {
        marks.add(payload);
      }
      return <String, Object?>{
        'ok': true,
        'data': <String, Object?>{
          'revision': payload['op'] == 'configure'
              ? revision
              : payload['revision'],
          'consentEpoch': payload['consentEpoch'],
          if (payload['op'] == 'configure')
            'configured': payload['enabled'] == true,
          if (payload['op'] == 'mark') 'accepted': true,
          if (payload['op'] == 'flush') 'queued': true,
        },
      };
    };
    addTearDown(() {
      if (!store.release.isCompleted) {
        store.release.complete();
      }
    });
    addTearDown(() => _b7Bound(reporter.dispose()));
    reporter.attachBridge(created.bridge);
    await arm();
    final control = reporter.captureOwner(expectedAccountPeerId: 'local-account');
    expect(control, isNotNull);
    reporter.markCaptured(control!);
    await _b7Until(() => marks.length == 1);
    expect(marks.single['accountPeerId'], 'local-account');
    expect(marks.single['consentEpoch'], epoch);
    expect(marks.single['profileBinding'], _b7ProfileA);
    marks.clear();
    if (initiallyUnarmed) {
      await arm(enabled: false);
    }
  }

  Future<void> connect({
    bool incoming = true,
    bool durableCheckpoint = false,
    Future<void> Function(_ProductionIosFixture)? whileRinging,
    Future<void> Function(_ProductionIosFixture)? beforeConnected,
  }) => _b7Bound(() async {
    Database? database;
    if (durableCheckpoint) {
      final ownedDatabase =
          await _b7Bound(_openKilledCallDatabase(inMemoryDatabasePath));
      database = ownedDatabase;
      addTearDown(() => _b7Bound(ownedDatabase.close()));
      await _b7Bound(ownedDatabase.insert('identity', <String, Object?>{
        'id': 1,
        'peer_id': 'local-account',
        'public_key': 'local-public-key',
        'private_key': null,
        'mnemonic12': null,
        'username': 'Local',
        'ml_kem_public_key': 'local-mlkem-public-key',
        'created_at': '2026-08-30T00:00:00.000Z',
        'updated_at': '2026-08-30T00:00:00.000Z',
      }));
      await _b7Bound(ownedDatabase.insert('contacts', <String, Object?>{
        'peer_id': 'video-contact',
        'public_key': 'remote-public-key',
        'ml_kem_public_key': 'remote-mlkem-public-key',
        'rendezvous': 'fixture-rendezvous',
        'username': 'Remote contact',
        'signature': 'fixture-signature',
        'scanned_at': '2026-08-30T00:00:00.000Z',
        'is_blocked': 0,
      }));
    }
    if (incoming) {
      await _b7Bound(_connectedGraphVideo(
        cleanupTimeout: _b7Limit,
        acceptedMedia: CallMediaKind.audio,
        captureCallActivityMark: capture,
        monotonicNow: () => clock.now,
        timerScheduler: clock,
        clockMs: () => wallMs,
        databaseOverride: database,
        privacyStore: durableCheckpoint ? store : null,
        beforeCall: _prepare,
        whileRinging: whileRinging,
        beforeConnected: beforeConnected,
      ));
    } else {
      await _b7Bound(_connectedOutgoingGraphAudio(
        cleanupTimeout: _b7Limit,
        captureCallActivityMark: capture,
        monotonicNow: () => clock.now,
        timerScheduler: clock,
        clockMs: () => wallMs,
        databaseOverride: database,
        privacyStore: durableCheckpoint ? store : null,
        beforeCall: _prepare,
        whileRinging: whileRinging,
        beforeConnected: beforeConnected,
      ));
    }
    expect(graph.coordinator.activeSession!.state, CallState.connected);
  }());

  Future<CallReduction> event(CallEventType type, {CallId? callId}) =>
      _b7Bound(graph.coordinator.dispatch(CallEvent(
        type: type,
        eventId: 'b7-${++eventSequence}',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true),
        callId: callId ?? graph.coordinator.activeSession!.callId,
      )));

  Future<void> end() async {
    await event(CallEventType.end);
    await _b7Turn();
    expect(graph.coordinator.activeSession, isNull);
  }
}

void _b7ActivityTests() {
  for (final incoming in [false, true]) {
    test('B7 partial ${incoming ? 'incoming' : 'outgoing'} marks at10 connected seconds', () async {
      final rig = _B7ActivityRig();
      await rig.connect(incoming: incoming);
      expect(rig.marks, isEmpty);
      await rig.clock.elapse(const Duration(milliseconds: 9999));
      expect(rig.marks, isEmpty);
      await rig.clock.elapse(const Duration(milliseconds: 1));
      expect(rig.marks, hasLength(1), reason: 'real production call must hand the original capture to the armed reporter');
      expect(rig.marks.single['accountPeerId'], 'local-account');
      expect(rig.capturedAccounts, ['local-account']);
      await rig.clock.elapse(const Duration(seconds: 10));
      expect(rig.marks, hasLength(1));
      expect(rig.handoffs, 1);
    });
  }

  test('B7 partial ringing Answer and negotiated media earn no connected time', () async {
    final rig = _B7ActivityRig();
    await rig.connect(
      whileRinging: (_) async {
        expect(rig.graph.coordinator.activeSession!.state, CallState.ringing);
        await rig.clock.elapse(const Duration(seconds: 8));
        expect(rig.marks, isEmpty);
      },
      beforeConnected: (_) async {
        expect(rig.graph.coordinator.activeSession!.connectedAt, isNull);
        await rig.clock.elapse(const Duration(seconds: 8));
        expect(rig.marks, isEmpty);
      },
    );
    await rig.clock.elapse(const Duration(milliseconds: 9999));
    expect(rig.marks, isEmpty);
    await rig.clock.elapse(const Duration(milliseconds: 1));
    expect(rig.marks, hasLength(1));
  });

  test('B7 partial canonical connection earns10 while checkpoint save is held', () async {
    final rig = _B7ActivityRig();
    final connection = rig.connect(
      durableCheckpoint: true,
      beforeConnected: (_) async {
        rig.store.holdWhen = () => rig.graph.coordinator.activeSession?.state == CallState.connected;
      },
    );
    await _b7Bound(rig.store.entered.future);
    try {
      expect(rig.graph.coordinator.activeSession!.state, CallState.connected);
      expect(rig.graph.current!.session.state, isNot(CallState.connected));
      await rig.clock.elapse(const Duration(milliseconds: 9999));
      expect(rig.marks, isEmpty);
      await rig.clock.elapse(const Duration(milliseconds: 1));
      expect(rig.marks, hasLength(1));
    } finally {
      rig.store.release.complete();
      await _b7Bound(connection);
    }
  });

  test('B7 partial reconnect pauses aggregate6 plus4 across held persistence', () async {
    final rig = _B7ActivityRig();
    await rig.connect(durableCheckpoint: true);
    await rig.clock.elapse(const Duration(seconds: 6));
    rig.store.holdWhen = () => rig.graph.coordinator.activeSession?.state == CallState.reconnecting;
    final reconnect = rig.event(CallEventType.audioInterrupted);
    await _b7Bound(rig.store.entered.future);
    try {
      expect(rig.graph.coordinator.activeSession!.state, CallState.reconnecting);
      await rig.clock.elapse(const Duration(seconds: 5));
      expect(rig.marks, isEmpty, reason: 'held persistence and reconnect add no connected time');
    } finally {
      rig.store.release.complete();
      await _b7Bound(reconnect);
    }
    await rig.event(CallEventType.mediaRecovered);
    await rig.clock.elapse(const Duration(milliseconds: 3999));
    expect(rig.marks, isEmpty);
    await rig.clock.elapse(const Duration(milliseconds: 1));
    expect(rig.marks, hasLength(1));
    expect(rig.capturedAccounts, ['local-account']);
  });

  test('B7 partial quiet checkpoint refresh neither resets nor duplicates mark', () async {
    final rig = _B7ActivityRig();
    await rig.connect(durableCheckpoint: true);
    final original = rig.graph.coordinator.activeSession;
    final writes = rig.store.checkpoints;
    await rig.clock.elapse(const Duration(seconds: 10));
    await _b7Until(() => rig.store.checkpoints > writes);
    expect(rig.graph.coordinator.activeSession, same(original));
    expect(rig.marks, hasLength(1));
    await rig.clock.elapse(const Duration(seconds: 10));
    expect(rig.marks, hasLength(1));
    expect(rig.capturedAccounts, ['local-account']);
  });

  for (final stop in ['End', 'dispose']) {
    test('B7 partial queued timer after $stop cannot mark old lifetime', () async {
      final rig = _B7ActivityRig();
      await rig.connect();
      await rig.clock.elapse(const Duration(seconds: 9));
      final queued = rig.clock.timers.where((t) => t.active).toList();
      if (stop == 'End') {
        await rig.end();
      } else {
        await _b7Bound(rig.fixture!.composition.shutdown());
      }
      await rig.clock.elapse(const Duration(seconds: 1));
      await rig.clock.fireQueued(queued);
      expect(rig.marks, isEmpty);
    });
  }

  test('B7 partial stale sameID connected event cannot revive ended lifetime', () async {
    final rig = _B7ActivityRig();
    await rig.connect();
    final id = rig.graph.coordinator.activeSession!.callId!;
    await rig.clock.elapse(const Duration(seconds: 9));
    await rig.end();
    final stale = await rig.event(CallEventType.mediaConnected, callId: id);
    expect(stale.decision, isNot(CallEventDecision.applied));
    await rig.clock.elapse(const Duration(seconds: 20));
    expect(rig.marks, isEmpty);
  });

  test('B7 partial queued predecessor timer cannot count a ringing successor', () async {
    final rig = _B7ActivityRig();
    await rig.connect();
    await rig.clock.elapse(const Duration(seconds: 9));
    final queued = rig.clock.timers.where((t) => t.active).toList();
    await rig.end();
    final successor = CallId.parse('99999999-9999-4999-8999-999999999999');
    await _b7Bound(_deliverGraphVideoInvite(
      rig.fixture!,
      callId: successor,
      messageId: '99999999-9999-4999-8999-999999999990',
      callHandle: '99999999-9999-4999-8999-999999999991',
    ));
    expect(rig.graph.coordinator.activeSession!.callId, successor);
    expect(rig.graph.coordinator.activeSession!.state, CallState.ringing);
    await rig.clock.elapse(const Duration(seconds: 1));
    await rig.clock.fireQueued(queued);
    expect(rig.marks, isEmpty);
  });

  test('B7 partial checkpoint failure preserves the original caller error', () async {
    final rig = _B7ActivityRig();
    await rig.connect(durableCheckpoint: true);
    await rig.clock.elapse(const Duration(seconds: 6));
    rig.store.holdWhen = () =>
        rig.graph.coordinator.activeSession?.state == CallState.reconnecting;
    rig.store.failWrite = true;
    final reconnect = rig.event(CallEventType.audioInterrupted);
    final error = expectLater(reconnect, throwsA(isA<StateError>()));
    await _b7Bound(rig.store.entered.future);
    rig.store.release.complete();
    await _b7Bound(error);
    expect(rig.graph.coordinator.internalFailureCount, greaterThan(0));
    expect(rig.graph.coordinator.lastSnapshot!.isTerminal, isTrue);
    await rig.clock.elapse(const Duration(seconds: 10));
    expect(rig.marks, isEmpty);
  });

  for (final change in ['OFF', 'OFF then ON', 'profile', 'identity']) {
    test('B7 partial original capture stays stale after $change', () async {
      final rig = _B7ActivityRig();
      await rig.connect();
      await rig.clock.elapse(const Duration(seconds: 9));
      if (change == 'OFF' || change == 'OFF then ON') {
        rig.epoch++;
        await rig.arm(enabled: false);
        if (change == 'OFF then ON') {
          rig.epoch++;
          await rig.arm();
        }
      } else if (change == 'profile') {
        await rig.arm(profile: _b7ProfileB);
      } else {
        rig.reporter.observeIdentity(
          accountPeerId: 'replacement-account',
          rootPrivateKeyBase64: 'replacement-root-fixture',
          profileBinding: _b7ProfileB,
        );
        await _b7Turn();
      }
      await rig.clock.elapse(const Duration(seconds: 11));
      expect(rig.marks, isEmpty);
    });
  }

  test('B7 partial initial null capture is never reacquired after enable', () async {
    final rig = _B7ActivityRig()..initiallyUnarmed = true;
    await rig.connect();
    await rig.clock.elapse(const Duration(seconds: 5));
    rig.epoch++;
    await rig.arm();
    await rig.clock.elapse(const Duration(seconds: 15));
    expect(rig.marks, isEmpty);
  });

  test('B7 partial wall clock jumps cannot change monotonic threshold', () async {
    final rig = _B7ActivityRig();
    await rig.connect();
    rig.wallMs += const Duration(days: 40).inMilliseconds;
    await rig.clock.elapse(const Duration(seconds: 5));
    expect(rig.marks, isEmpty);
    rig.wallMs -= const Duration(days: 80).inMilliseconds;
    await rig.clock.elapse(const Duration(milliseconds: 4999));
    expect(rig.marks, isEmpty);
    await rig.clock.elapse(const Duration(milliseconds: 1));
    expect(rig.marks, hasLength(1));
  });
}
