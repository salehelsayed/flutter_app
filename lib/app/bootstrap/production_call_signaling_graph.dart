import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/bridge/bridge.dart';
import '../../core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import '../../core/media/audio_recorder_service.dart';
import '../../core/services/incoming_message_router.dart';
import '../../core/services/p2p_service.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../core/utils/flow_event_emitter.dart';
import '../../features/call/application/call_cleanup_coordinator.dart';
import '../../features/call/application/call_audio_controller.dart';
import '../../features/call/application/call_audio_interruption_coordinator.dart';
import '../../features/call/application/call_audio_negotiation_preparer.dart';
import '../../features/call/application/call_control_effect_executor.dart';
import '../../features/call/application/call_coordinator.dart';
import '../../features/call/application/call_endpoint_resolver.dart';
import '../../features/call/application/call_negotiation_effect_executor.dart';
import '../../features/call/application/call_negotiation_material_store.dart';
import '../../features/call/application/call_history_projector.dart';
import '../../features/call/application/call_network_gate.dart';
import '../../features/call/application/call_scoped_media_bundle_owner.dart';
import '../../features/call/application/call_signaling_context_store.dart';
import '../../features/call/application/call_signaling_service.dart';
import '../../features/call/application/call_wake_authorization_coordinator.dart';
import '../../features/call/application/foreground_call_capability.dart';
import '../../features/call/application/handle_incoming_call_signal.dart';
import '../../features/call/application/outgoing_call_capability.dart';
import '../../features/call/data/call_history_repository_impl.dart';
import '../../features/call/domain/call_engine.dart';
import '../../features/call/domain/call_event.dart';
import '../../features/call/domain/call_id.dart';
import '../../features/call/domain/call_session_snapshot.dart';
import '../../features/call/domain/call_state.dart';
import '../../features/call/domain/call_wake_handle_grant.dart';
import '../../features/call/domain/issued_call_wake_handle_store.dart';
import '../../features/call/domain/received_call_wake_handle_store.dart';
import '../../features/call/infrastructure/bridge_call_ice_server_provider.dart';
import '../../features/call/infrastructure/android_call_lifecycle_adapter.dart';
import '../../features/call/infrastructure/call_audio_route_adapter.dart';
import '../../features/call/infrastructure/call_authority_client.dart';
import '../../features/call/infrastructure/call_foreground_audio_session_adapter.dart';
import '../../features/call/infrastructure/call_mailbox_client.dart';
import '../../features/call/infrastructure/call_media_conflict_adapter.dart';
import '../../features/call/infrastructure/call_microphone_permission_adapter.dart';
import '../../features/call/infrastructure/call_signaling_runtime.dart';
import '../../features/call/infrastructure/call_trusted_roster_provider.dart';
import '../../features/call/infrastructure/flutter_webrtc_call_engine.dart';
import '../../features/call/application/call_ringback_coordinator.dart';
import '../../features/call/infrastructure/android_call_token_coordinator.dart';
import '../../features/call/infrastructure/call_ringback_channel.dart';
import '../../features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import '../../features/call/infrastructure/ios_voip_token_coordinator.dart';
import '../../features/call/infrastructure/p2p_call_transport.dart';
import '../../features/call/infrastructure/production_call_signaling_adapters.dart';
import '../../features/call/infrastructure/secure_call_envelope_codec.dart';
import '../../features/identity/domain/models/identity_model.dart';
import 'call_signaling_composition.dart';

typedef LoadCallSignalingIdentity = Future<IdentityModel?> Function();
typedef AndroidCallLifecycleAdapterFactory =
    AndroidCallLifecycleAdapter Function({
      required CallCoordinator coordinator,
      required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
      required DateTime Function() clock,
    });
typedef IosCallLifecycleAdapterFactory =
    IosCallLifecycleAdapter Function({
      required CallCoordinator coordinator,
      required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
      required DateTime Function() clock,
    });
typedef AndroidCallTokenCoordinatorFactory =
    AndroidCallTokenCoordinator Function({
      required CallAuthorityClient authorityClient,
      required DateTime Function() clock,
      required CallTokenPublicationAllowed publicationAllowed,
    });
typedef IosVoipTokenCoordinatorFactory =
    IosVoipTokenCoordinator Function({
      required CallAuthorityClient authorityClient,
      required DateTime Function() clock,
      required IosVoipTokenPublicationAllowed publicationAllowed,
    });
typedef ProductionCallSignalingGraphObserver =
    void Function(ProductionCallSignalingGraph graph);
typedef LoadCallWakeEligibleContacts =
    Future<List<CallWakeEligibleContact>> Function();
typedef EnsureReceivedCallWakeHandle =
    Future<bool> Function(String contactAccountPeerId);

final class PreparedOutgoingCall {
  const PreparedOutgoingCall({required this.endpoint, required this.reduction});

  final ResolvedCallEndpoint endpoint;
  final CallReduction reduction;
}

/// The concrete graph behind the default-off composition latch. Every
/// dependency is call-specific except read-only shared bridge/P2P/router/DB
/// handles, none of which this graph disposes.
final class ProductionCallSignalingGraph
    implements
        CallSignalingGraphLifecycle,
        ForegroundCallCapability,
        ForegroundCallBackgroundLifecycle,
        CallSignalingCallabilityInvalidations,
        CallSignalingDeferredAdvertisementRetries,
        CallSignalingWakeDrain,
        CallWakeHandleDistributionLifecycle {
  ProductionCallSignalingGraph({
    required this.runtime,
    required this.coordinator,
    required this.signalingService,
    required this.endpointResolver,
    required this.trustedRosterProvider,
    required this.authorityClient,
    required this.wakeAuthorizationCoordinator,
    required this.issuedCallWakeHandleStore,
    required this.receivedCallWakeHandleStore,
    required this.loadWakeEligibleContacts,
    this.ensureReceivedCallWakeHandle,
    required this.localDeviceKeyEpoch,
    required this.localIdentity,
    required this.platform,
    required this.mediaOwner,
    this.androidCallLifecycleAdapter,
    this.iosCallLifecycleAdapter,
    this.iosVoipTokenCoordinator,
    this.androidCallTokenCoordinator,
    this.ringback,
    required CallNetworkEffectsAllowed networkEffectsAllowed,
    required int Function() nowMs,
  }) : assert(
         androidCallLifecycleAdapter == null || iosCallLifecycleAdapter == null,
       ),
       _networkEffectsAllowed = networkEffectsAllowed,
       _nowMs = nowMs {
    final ringbackPort = ringback;
    _ringback = ringbackPort == null
        ? null
        : CallRingbackCoordinator(
            port: ringbackPort,
            onResult: _emitRingbackResult,
          );
    _sessionSubscription = coordinator.snapshots.listen(
      _onSessionSnapshot,
      onError: (_) => _publishForeground(null),
    );
    _mediaBundleSubscription = mediaOwner.bundleChanges.listen(
      _onMediaBundleChanged,
      onError: (_) => _unbindAudio(),
    );
    final active = coordinator.activeSession;
    if (active != null) _onSessionSnapshot(active);
    _tokenInvalidationSubscription = iosVoipTokenCoordinator
        ?.authorityInvalidations
        .listen((_) => unawaited(_handleIosTokenInvalidation()));
    _tokenEpochAdvanceSubscription = iosVoipTokenCoordinator?.epochAdvances
        .listen(_emitIosTokenEpochAdvanceResult);
    final Object? nativeLifecycle = _nativeCallLifecycleAdapter;
    if (nativeLifecycle is NativeCallLifecycleInvalidations) {
      _nativeInvalidationSubscription = nativeLifecycle.invalidations.listen(
        (_) => _handleNativeLifecycleInvalidation(),
      );
    }
  }

  final CallSignalingRuntime runtime;
  final CallCoordinator coordinator;
  final CallSignalingService signalingService;
  final CallEndpointResolver endpointResolver;
  final CallTrustedRosterProvider trustedRosterProvider;
  final CallAuthorityClient authorityClient;
  final CallWakeAuthorizationCoordinator wakeAuthorizationCoordinator;
  final IssuedCallWakeHandleStore issuedCallWakeHandleStore;
  final ReceivedCallWakeHandleStore receivedCallWakeHandleStore;
  final LoadCallWakeEligibleContacts loadWakeEligibleContacts;
  final EnsureReceivedCallWakeHandle? ensureReceivedCallWakeHandle;
  final int localDeviceKeyEpoch;
  final IdentityModel localIdentity;
  final CallEndpointPlatform platform;
  final CallScopedMediaBundleOwner mediaOwner;
  final AndroidCallLifecycleAdapter? androidCallLifecycleAdapter;
  final IosCallLifecycleAdapter? iosCallLifecycleAdapter;
  final IosVoipTokenCoordinator? iosVoipTokenCoordinator;

  /// Publishes the FCM token as the relay's standard call token so an Android
  /// callee can be woken once its live connection is gone.
  final AndroidCallTokenCoordinator? androidCallTokenCoordinator;

  /// Ringback (the caller-side ringing tone). Absent on hosts without a
  /// tone player; the call is unaffected either way.
  final CallRingbackPort? ringback;
  late final CallRingbackCoordinator? _ringback;
  final CallNetworkEffectsAllowed _networkEffectsAllowed;
  final int Function() _nowMs;

  int? _advertisedPreferenceEpoch;
  String? _routingHandle;
  late final StreamSubscription<CallSessionSnapshot> _sessionSubscription;
  late final StreamSubscription<CallScopedMediaBundle?>
  _mediaBundleSubscription;
  StreamSubscription<CallAudioControlState>? _audioSubscription;
  StreamSubscription<void>? _tokenInvalidationSubscription;
  StreamSubscription<IosVoipTokenEpochAdvanceOutcome>?
  _tokenEpochAdvanceSubscription;
  StreamSubscription<void>? _nativeInvalidationSubscription;
  final StreamController<ForegroundCallProjection?> _foregroundChanges =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  final StreamController<void> _callabilityInvalidations =
      StreamController<void>.broadcast(sync: true);
  ForegroundCallProjection? _foregroundCurrent;
  CallAudioController? _observedAudioController;
  CallId? _activeConnectionSnapshotCallId;
  Future<CallConnectionSnapshot> Function()? _activeConnectionSnapshotReader;
  int _audioGeneration = 0;
  bool _shuttingDown = false;
  Future<void>? _iosNativeRollback;
  Future<void>? _iosTokenRollback;
  Future<void>? _iosEndpointRollback;
  bool _advertisementDeferredForLiveCall = false;
  final StreamController<void> _deferredAdvertisementRetries =
      StreamController<void>.broadcast(sync: true);

  NativeCallLifecycleAdapter? get _nativeCallLifecycleAdapter =>
      androidCallLifecycleAdapter ?? iosCallLifecycleAdapter;

  @override
  ForegroundCallProjection? get current => _foregroundCurrent;

  @override
  Stream<ForegroundCallProjection?> get changes => _foregroundChanges.stream;

  @override
  Stream<void> get callabilityInvalidations => _callabilityInvalidations.stream;

  @override
  Stream<void> get deferredAdvertisementRetries =>
      _deferredAdvertisementRetries.stream;

  /// A live (non-terminal) session must never be torn down over relay
  /// capability authority; a terminal-but-still-present session counts as idle.
  bool get _hasLiveSession => coordinator.activeSession?.isTerminal == false;

  /// Returns only the coarse engine snapshot for the exact active call.
  ///
  /// The reader is installed from the call-scoped media bundle and fenced
  /// both before and after its asynchronous plugin read. No engine, call
  /// command, candidate, address, SDP, credential, or raw statistic crosses
  /// this observation boundary.
  Future<CallConnectionSnapshot?> readActiveConnectionSnapshot() async {
    final session = coordinator.activeSession;
    final callId = session?.callId;
    final reader = _activeConnectionSnapshotReader;
    if (_shuttingDown ||
        session == null ||
        callId == null ||
        session.isTerminal ||
        _activeConnectionSnapshotCallId != callId ||
        reader == null) {
      return null;
    }
    final snapshot = await reader();
    final current = coordinator.activeSession;
    if (_shuttingDown ||
        current?.callId != callId ||
        current?.isTerminal != false ||
        _activeConnectionSnapshotCallId != callId ||
        !identical(_activeConnectionSnapshotReader, reader)) {
      return null;
    }
    return snapshot;
  }

  @override
  Future<bool> start() async {
    await _nativeCallLifecycleAdapter?.start();
    await iosVoipTokenCoordinator?.start();
    await androidCallTokenCoordinator?.start();
    return runtime.start();
  }

  @override
  Future<void> onResume() async {
    await runtime.onResume();
    final active = coordinator.activeSession;
    if (active != null) _onSessionSnapshot(active);
  }

  /// A native wake or relay recovery: drain the ephemeral call mailbox now.
  /// The runtime's resume is exactly that drain (listener start, network
  /// gate, page retrieval, authenticated admission, ack).
  @override
  Future<void> drainCallMailbox() => runtime.onResume();

  /// Intersects current local trust with the independently verified relay
  /// capability before the coordinator is permitted to create a session.
  Future<PreparedOutgoingCall> prepareOutgoingCall(
    String contactAccountPeerId,
  ) async {
    _requireOutgoingGraphActive();
    return runCallNetworkActionIfAllowed(
      gate: _networkEffectsAllowed,
      action: () async {
        // The network gate may itself yield while token invalidation withdraws
        // this graph. Do not begin endpoint work after that withdrawal.
        _requireOutgoingGraphActive();
        final endpoint = await _resolveEndpoint(contactAccountPeerId);
        _requireOutgoingGraphActive();
        final nativeLifecycleReady =
            await _nativeCallLifecycleAdapter?.reconcileBeforeOutgoing() ??
            true;
        if (!nativeLifecycleReady) {
          throw StateError('native call lifecycle is unavailable');
        }
        if (!await _hasCurrentOutgoingWakeAuthority(contactAccountPeerId)) {
          throw const _OutgoingCallWakeAuthorityUnavailable();
        }
        // This is the final commit boundary before placeCall enqueues the
        // event which can emit an invite.
        _requireOutgoingGraphActive();
        final reduction = await coordinator.placeCall(
          contactPeerId: contactAccountPeerId,
          localAccountPeerId: localIdentity.peerId,
          localDeviceId: localIdentity.peerId,
        );
        return PreparedOutgoingCall(endpoint: endpoint, reduction: reduction);
      },
    );
  }

  void _requireOutgoingGraphActive() {
    if (_shuttingDown) {
      throw StateError('call signaling graph is shutting down');
    }
  }

  Future<bool> _hasCurrentOutgoingWakeAuthority(
    String contactAccountPeerId,
  ) async {
    final record = await issuedCallWakeHandleStore.readForContact(
      contactAccountPeerId,
    );
    return record != null &&
        record.contactAccountPeerId == contactAccountPeerId &&
        !record.revokePending &&
        !record.distributionPending &&
        record.hasCurrentDistributionReceipt &&
        record.grant.recipientDevicePeerId == localIdentity.peerId &&
        record.grant.deviceKeyEpoch == localDeviceKeyEpoch &&
        record.grant.isValidAt(_nowMs());
  }

  @override
  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId) =>
      probeProductionCallEndpointAvailability(
        networkEffectsAllowed: _networkEffectsAllowed,
        contactAccountPeerId: contactAccountPeerId,
        resolver: endpointResolver,
        rosterProvider: trustedRosterProvider,
        authorityClient: authorityClient,
        receivedCallWakeHandleStore: receivedCallWakeHandleStore,
        ensureReceivedCallWakeHandle: ensureReceivedCallWakeHandle,
      );

  Future<ResolvedCallEndpoint> _resolveEndpoint(String contactAccountPeerId) =>
      _resolveProductionCallEndpoint(
        contactAccountPeerId: contactAccountPeerId,
        resolver: endpointResolver,
        rosterProvider: trustedRosterProvider,
        authorityClient: authorityClient,
        receivedCallWakeHandleStore: receivedCallWakeHandleStore,
      );

  @override
  Future<CallWakeHandleGrant?> resolveCallWakeHandle(
    String contactAccountPeerId,
  ) async {
    final contacts = await loadWakeEligibleContacts();
    final matches = contacts
        .where(
          (contact) => contact.contactAccountPeerId == contactAccountPeerId,
        )
        .toList(growable: false);
    if (matches.length != 1) return null;
    return wakeAuthorizationCoordinator.resolveOrIssueGrantForContact(
      contact: matches.single,
      localRecipientDevicePeerId: localIdentity.peerId,
      localDeviceKeyEpoch: localDeviceKeyEpoch,
    );
  }

  @override
  Future<bool> rearmCallWakeHandleDistribution() =>
      wakeAuthorizationCoordinator.rearmCurrentGrantDistribution();

  @override
  Future<bool> markCallWakeHandleDistributed(
    String contactAccountPeerId,
    CallWakeHandleGrant grant,
  ) => wakeAuthorizationCoordinator.markDistributed(
    contactAccountPeerId: contactAccountPeerId,
    grant: grant,
  );

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId,
  ) async {
    try {
      final prepared = await prepareOutgoingCall(contactAccountPeerId);
      return prepared.reduction.decision == CallEventDecision.applied
          ? OutgoingCallStartResult.started
          : OutgoingCallStartResult.unavailable;
    } on _OutgoingCallWakeAuthorityUnavailable {
      return OutgoingCallStartResult.unavailable;
    }
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) async {
    final ios = iosCallLifecycleAdapter;
    if (ios != null && await ios.answer(callId)) {
      // CallKit owns the answer on iOS: a Dart-only accept never activates
      // the CallKit audio session, so media start fails after the caller
      // was already told the call was accepted.
      return ForegroundCallActionResult.applied;
    }
    return _dispatchForegroundAction(CallEventType.answer, callId);
  }

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) =>
      _dispatchForegroundAction(CallEventType.decline, callId);

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) =>
      _dispatchForegroundAction(CallEventType.cancel, callId);

  @override
  Future<ForegroundCallActionResult> end(CallId callId) =>
      _dispatchForegroundAction(CallEventType.end, callId);

  @override
  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted) async {
    final controller = _currentAudioController(callId);
    if (controller == null) return ForegroundCallActionResult.unavailable;
    try {
      final state = await controller.setMuted(muted);
      return state.failure == CallAudioFailure.none && state.muted == muted
          ? ForegroundCallActionResult.applied
          : ForegroundCallActionResult.failed;
    } catch (_) {
      return ForegroundCallActionResult.failed;
    }
  }

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) async {
    final controller = _currentAudioController(callId);
    if (controller == null) return ForegroundCallActionResult.unavailable;
    final target = enabled
        ? CallAudioOutputRoute.speaker
        : _preferredNonSpeakerRoute(controller.state);
    if (target == null) return ForegroundCallActionResult.unavailable;
    try {
      final state = await controller.selectOutputRoute(target);
      if (state.failure == CallAudioFailure.unsupportedRoute) {
        return ForegroundCallActionResult.unavailable;
      }
      return state.failure == CallAudioFailure.none &&
              state.selectedRoute == target
          ? ForegroundCallActionResult.applied
          : ForegroundCallActionResult.failed;
    } catch (_) {
      return ForegroundCallActionResult.failed;
    }
  }

  Future<ForegroundCallActionResult> _dispatchForegroundAction(
    CallEventType type,
    CallId callId,
  ) async {
    final session = coordinator.activeSession;
    if (_shuttingDown ||
        session == null ||
        session.callId != callId ||
        session.isTerminal) {
      return ForegroundCallActionResult.unavailable;
    }
    try {
      final reduction = await coordinator.dispatch(
        CallEvent(
          type: type,
          eventId: 'foreground-${type.name}-${const Uuid().v4()}',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            _nowMs(),
            isUtc: true,
          ),
          callId: callId,
          contactPeerId: session.contactPeerId,
        ),
      );
      return reduction.decision == CallEventDecision.applied
          ? ForegroundCallActionResult.applied
          : ForegroundCallActionResult.unavailable;
    } catch (_) {
      return ForegroundCallActionResult.failed;
    }
  }

  @override
  Future<void> onBackgrounded() async {
    if (_nativeCallLifecycleAdapter != null) {
      _publishForeground(null);
      return;
    }
    final session = coordinator.activeSession;
    if (_shuttingDown || session == null || session.isTerminal) return;
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.appShutdown,
        eventId: 'background-shutdown-${session.callId!.value}',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs(), isUtc: true),
        callId: session.callId,
        contactPeerId: session.contactPeerId,
        localAccountPeerId: session.direction == CallDirection.outgoing
            ? session.callerAccountPeerId
            : null,
        localDeviceId: session.direction == CallDirection.outgoing
            ? session.callerDeviceId
            : null,
        remoteAccountPeerId: session.direction == CallDirection.incoming
            ? session.callerAccountPeerId
            : session.contactPeerId,
        remoteDeviceId: session.direction == CallDirection.incoming
            ? session.callerDeviceId
            : null,
      ),
    );
  }

  CallAudioController? _currentAudioController(CallId callId) {
    final session = coordinator.activeSession;
    if (_shuttingDown ||
        session?.callId != callId ||
        session?.isTerminal != false) {
      return null;
    }
    return mediaOwner.currentAudioController(callId);
  }

  void _onSessionSnapshot(CallSessionSnapshot session) {
    _ringback?.onSession(session);
    if (_shuttingDown || session.callId == null || session.isTerminal) {
      _clearConnectionSnapshotReader();
      _unbindAudio();
      if (!_shuttingDown &&
          session.isTerminal &&
          session.callId != null &&
          _foregroundCurrent?.session.callId == session.callId) {
        _publishTerminalForeground(session);
      } else {
        _publishForeground(null);
      }
      if (!_shuttingDown && session.isTerminal) _retryDeferredAdvertisement();
      return;
    }
    final callId = session.callId!;
    final controller = mediaOwner.currentAudioController(callId);
    if (!identical(_observedAudioController, controller)) {
      _bindAudio(callId, controller);
    }
    _publishForeground(
      ForegroundCallProjection(
        session: session,
        audio: controller?.state ?? CallAudioControlState.idle,
      ),
    );
  }

  void _onMediaBundleChanged(CallScopedMediaBundle? bundle) {
    if (_shuttingDown) return;
    final session = coordinator.activeSession;
    final callId = session?.callId;
    if (session == null || callId == null || session.isTerminal) {
      _clearConnectionSnapshotReader();
      _unbindAudio();
      _publishForeground(null);
      return;
    }
    if (bundle != null && bundle.callId != callId) return;
    if (bundle == null) {
      _clearConnectionSnapshotReader();
    } else {
      _activeConnectionSnapshotCallId = bundle.callId;
      _activeConnectionSnapshotReader = bundle.engine.snapshot;
    }
    final controller = bundle?.audioController;
    _bindAudio(callId, controller);
    _publishForeground(
      ForegroundCallProjection(
        session: session,
        audio: controller?.state ?? CallAudioControlState.idle,
      ),
    );
  }

  void _bindAudio(CallId callId, CallAudioController? controller) {
    _audioGeneration++;
    final generation = _audioGeneration;
    final old = _audioSubscription;
    _audioSubscription = null;
    _observedAudioController = controller;
    if (old != null) unawaited(old.cancel());
    if (controller == null) return;
    _audioSubscription = controller.stateChanges.listen((audio) {
      final session = coordinator.activeSession;
      if (_shuttingDown ||
          generation != _audioGeneration ||
          !identical(_observedAudioController, controller) ||
          session?.callId != callId ||
          session?.isTerminal != false) {
        return;
      }
      _publishForeground(
        ForegroundCallProjection(session: session!, audio: audio),
      );
    });
  }

  void _unbindAudio() {
    _audioGeneration++;
    _observedAudioController = null;
    final subscription = _audioSubscription;
    _audioSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _clearConnectionSnapshotReader() {
    _activeConnectionSnapshotCallId = null;
    _activeConnectionSnapshotReader = null;
  }

  void _publishForeground(ForegroundCallProjection? projection) {
    _foregroundCurrent = projection;
    if (!_foregroundChanges.isClosed) _foregroundChanges.add(projection);
  }

  /// The call the surface was showing ended. Its terminal snapshot is
  /// published once so the surface can show the end notice ("Call declined",
  /// "No answer"); `current` then holds null so a later resume republishes
  /// nothing.
  void _publishTerminalForeground(CallSessionSnapshot session) {
    _foregroundCurrent = null;
    if (!_foregroundChanges.isClosed) {
      _foregroundChanges.add(
        ForegroundCallProjection(
          session: session,
          audio: CallAudioControlState.idle,
        ),
      );
    }
  }

  @override
  Future<bool> advertiseCapability() async {
    var stage = 'network_gate';
    try {
      if (!await callNetworkEffectsAreAllowed(_networkEffectsAllowed)) {
        return _failCapabilityAdvertisement(stage: stage);
      }
      stage = 'voip_token';
      final tokenCoordinator = iosVoipTokenCoordinator;
      if (tokenCoordinator != null &&
          !await tokenCoordinator.publishForAuthenticatedGraph()) {
        return _failCapabilityAdvertisement(stage: stage);
      }
      stage = 'android_call_token';
      // Best effort: direct calls work without it, so a missing or rejected
      // token never blocks the endpoint advertisement.
      await androidCallTokenCoordinator?.ensurePublished();
      stage = 'wake_authority';
      if (!await wakeAuthorizationCoordinator.reconcile(
        eligibleContacts: await loadWakeEligibleContacts(),
        localRecipientDevicePeerId: localIdentity.peerId,
        localDeviceKeyEpoch: localDeviceKeyEpoch,
      )) {
        return _failCapabilityAdvertisement(stage: stage);
      }
      stage = 'identity_keys';
      final mlKemPublicKey = localIdentity.mlKemPublicKey?.trim() ?? '';
      if (mlKemPublicKey.isEmpty ||
          localIdentity.publicKey.trim().isEmpty ||
          localIdentity.privateKey.trim().isEmpty) {
        return _failCapabilityAdvertisement(stage: stage);
      }
      final now = _nowMs();
      final priorEpoch = _advertisedPreferenceEpoch;
      final preferenceEpoch = priorEpoch == null || now > priorEpoch
          ? now
          : priorEpoch + 1;
      final routingHandle =
          _routingHandle ?? const Uuid().v4().replaceAll('-', '');
      stage = 'endpoint_sign';
      final signed = await authorityClient.signEndpoint(
        record: CallEndpointRecord(
          accountPeerId: localIdentity.peerId,
          devicePeerId: localIdentity.peerId,
          capabilities: const <String>{CallEndpointResolver.voiceCapability},
          platform: platform,
          expiresAtMs: now + const Duration(hours: 6).inMilliseconds,
          preferenceEpoch: preferenceEpoch,
          deviceKeyEpoch: localDeviceKeyEpoch,
          routingHandle: routingHandle,
        ),
        senderSigningPrivateKey: localIdentity.privateKey,
      );
      _advertisedPreferenceEpoch = preferenceEpoch;
      stage = 'endpoint_publish';
      if (!await authorityClient.setEndpoint(signed)) {
        return _failCapabilityAdvertisement(stage: stage);
      }
      _routingHandle = routingHandle;
      _emitCapabilityAdvertisementResult(stage: 'ready', outcome: 'ready');
      return true;
    } catch (_) {
      return _failCapabilityAdvertisement(stage: stage, outcome: 'error');
    }
  }

  Future<bool> _failCapabilityAdvertisement({
    required String stage,
    String outcome = 'unavailable',
  }) {
    if (_hasLiveSession) {
      // A failed re-advertisement during a live call defers: nothing is
      // revoked and no native call ends. The terminal snapshot retries once.
      _advertisementDeferredForLiveCall = true;
      _emitCapabilityAdvertisementResult(
        stage: stage,
        outcome: 'deferred_live_call',
      );
      return Future<bool>.value(false);
    }
    _emitCapabilityAdvertisementResult(stage: stage, outcome: outcome);
    return _failIosAdvertisement();
  }

  void _retryDeferredAdvertisement() {
    if (!_advertisementDeferredForLiveCall) return;
    _advertisementDeferredForLiveCall = false;
    if (!_deferredAdvertisementRetries.isClosed) {
      _deferredAdvertisementRetries.add(null);
    }
  }

  /// Identifier-free record of a native refresh-epoch advance requested after
  /// the relay rejected a VoIP token registration as stale.
  void _emitIosTokenEpochAdvanceResult(
    IosVoipTokenEpochAdvanceOutcome outcome,
  ) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_VOIP_TOKEN_EPOCH_ADVANCE_RESULT',
        details: <String, Object?>{'outcome': outcome.wireName},
      );
    } catch (_) {
      // Diagnostics never change token authority.
    }
  }

  void _emitCapabilityAdvertisementResult({
    required String stage,
    required String outcome,
  }) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        details: <String, Object?>{'stage': stage, 'outcome': outcome},
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change callability authority.
    }
  }

  /// Idle advertisement failure: a transient rollback that withdraws the
  /// endpoint and fails the native adapter closed but keeps the VoIP token
  /// registration (only graph close revokes it).
  Future<bool> _failIosAdvertisement() async {
    if (iosCallLifecycleAdapter != null || iosVoipTokenCoordinator != null) {
      try {
        await _rollbackIosCallability(terminal: false);
      } catch (_) {
        // Returning false withdraws the graph; shutdown retries exact cleanup.
      }
    }
    return false;
  }

  @override
  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    _clearConnectionSnapshotReader();
    _publishForeground(null);
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    await attempt(runtime.shutdown);
    await attempt(_sessionSubscription.cancel);
    final ringbackCoordinator = _ringback;
    if (ringbackCoordinator != null) {
      await attempt(ringbackCoordinator.dispose);
    }
    await attempt(_mediaBundleSubscription.cancel);
    final tokenInvalidationSubscription = _tokenInvalidationSubscription;
    _tokenInvalidationSubscription = null;
    if (tokenInvalidationSubscription != null) {
      await attempt(tokenInvalidationSubscription.cancel);
    }
    final tokenEpochAdvanceSubscription = _tokenEpochAdvanceSubscription;
    _tokenEpochAdvanceSubscription = null;
    if (tokenEpochAdvanceSubscription != null) {
      await attempt(tokenEpochAdvanceSubscription.cancel);
    }
    final nativeInvalidationSubscription = _nativeInvalidationSubscription;
    _nativeInvalidationSubscription = null;
    if (nativeInvalidationSubscription != null) {
      await attempt(nativeInvalidationSubscription.cancel);
    }
    final audioSubscription = _audioSubscription;
    _audioSubscription = null;
    if (audioSubscription != null) {
      await attempt(audioSubscription.cancel);
    }
    await attempt(mediaOwner.close);
    await attempt(wakeAuthorizationCoordinator.close);
    final androidTokenCoordinator = androidCallTokenCoordinator;
    if (androidTokenCoordinator != null) {
      await attempt(androidTokenCoordinator.close);
    }
    if (iosCallLifecycleAdapter != null || iosVoipTokenCoordinator != null) {
      // Native iOS presentation, token authority, and endpoint authority are
      // withdrawn as one ordered unit before either native channel detaches.
      await attempt(() => _rollbackIosCallability(terminal: true));
    }
    if (!_deferredAdvertisementRetries.isClosed) {
      await attempt(_deferredAdvertisementRetries.close);
    }
    final nativeLifecycle = _nativeCallLifecycleAdapter;
    if (nativeLifecycle != null) {
      await attempt(nativeLifecycle.close);
    }
    final tokenCoordinator = iosVoipTokenCoordinator;
    if (tokenCoordinator != null) {
      await attempt(tokenCoordinator.close);
    }
    if (!_foregroundChanges.isClosed) {
      await attempt(_foregroundChanges.close);
    }
    if (!_callabilityInvalidations.isClosed) {
      await attempt(_callabilityInvalidations.close);
    }
    final preferenceEpoch = _advertisedPreferenceEpoch;
    if (preferenceEpoch != null) {
      try {
        final iosNativeCallability =
            iosCallLifecycleAdapter != null || iosVoipTokenCoordinator != null;
        if (iosNativeCallability ||
            await callNetworkEffectsAreAllowed(_networkEffectsAllowed)) {
          await authorityClient.revokeEndpoint(
            accountPeerId: localIdentity.peerId,
            preferenceEpoch: preferenceEpoch,
          );
        }
      } catch (_) {
        // Revocation is best effort; the signed endpoint also has a short TTL.
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  /// Each leg runs at most once per graph. A transient rollback (idle
  /// advertisement failure) withdraws native presentation and the endpoint;
  /// the terminal rollback (graph close, applied token invalidation) also
  /// revokes the VoIP token. Leg order for a pure terminal rollback stays
  /// native → token → endpoint.
  Future<void> _rollbackIosCallability({required bool terminal}) async {
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    await attempt(() => _iosNativeRollback ??= _rollbackIosNativeOnce());
    if (terminal) {
      await attempt(() => _iosTokenRollback ??= _revokeIosTokenOnce());
    }
    await attempt(() => _iosEndpointRollback ??= _revokeIosEndpointOnce());
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  Future<void> _rollbackIosNativeOnce() async {
    final native = iosCallLifecycleAdapter;
    if (native == null) return;
    Object? firstError;
    StackTrace? firstStack;
    // Stop new PushKit delivery before ending any current CallKit
    // presentation. Each cleanup leg remains independent so a durability or
    // native-handler failure cannot strand relay authority or the current UI.
    try {
      await native.disableCapability();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    try {
      await native.failClosed();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  Future<void> _revokeIosTokenOnce() async {
    final token = iosVoipTokenCoordinator;
    if (token != null) await token.revokeForCallabilityRollback();
  }

  Future<void> _revokeIosEndpointOnce() async {
    final preferenceEpoch = _advertisedPreferenceEpoch;
    if (preferenceEpoch == null) return;
    await authorityClient.revokeEndpoint(
      accountPeerId: localIdentity.peerId,
      preferenceEpoch: preferenceEpoch,
    );
    _advertisedPreferenceEpoch = null;
  }

  /// A native lifecycle adapter that failed closed never recovers on its
  /// own: its latch is permanent by design. Withdrawing the graph lets the
  /// next resume build a fresh adapter instead of silently rejecting every
  /// later incoming call until the process restarts.
  void _handleNativeLifecycleInvalidation() {
    if (!_callabilityInvalidations.isClosed) {
      _callabilityInvalidations.add(null);
    }
  }

  Future<void> _handleIosTokenInvalidation() async {
    if (_hasLiveSession) {
      // Token authority is applied only at the terminal snapshot: the retry
      // re-publishes the token; a failed retry then performs the idle rollback
      // and withdraws the graph. A native-lifecycle invalidation is never
      // deferred (that call is already dead).
      _advertisementDeferredForLiveCall = true;
      return;
    }
    // Withdraw composition/outgoing entry synchronously. Graph shutdown then
    // joins the same memoized rollback legs before detaching either channel.
    if (!_callabilityInvalidations.isClosed) {
      _callabilityInvalidations.add(null);
    }
    try {
      await _rollbackIosCallability(terminal: true);
    } catch (_) {
      // Shutdown propagates the fixed-shape cleanup failure after all attempts.
    }
  }
}

CallAudioOutputRoute? _preferredNonSpeakerRoute(CallAudioControlState state) {
  final selected = state.selectedRoute;
  if (selected != CallAudioOutputRoute.speaker &&
      state.supportedRoutes.contains(selected)) {
    return selected;
  }
  for (final candidate in const <CallAudioOutputRoute>[
    CallAudioOutputRoute.systemDefault,
    CallAudioOutputRoute.wiredHeadset,
    CallAudioOutputRoute.bluetooth,
    CallAudioOutputRoute.earpiece,
  ]) {
    if (state.supportedRoutes.contains(candidate)) return candidate;
  }
  return null;
}

/// Builds no crypto, coordinator, subscription, or relay authority object until
/// the default-off [CallSignalingComposition] has passed its feature gates and
/// the existing identity/contact/database/bridge prerequisites are ready.
CallSignalingComposition createProductionCallSignalingComposition({
  required Map<String, bool> featureFlags,
  required CallEndpointPlatform? platform,
  required Database database,
  required Bridge bridge,
  required P2PService p2pService,
  required IncomingMessageRouter messageRouter,
  required LoadCallSignalingIdentity loadIdentity,
  required CallNetworkEffectsAllowed networkEffectsAllowed,
  required IsVoiceNoteRecording isVoiceNoteRecording,
  required IssuedCallWakeHandleStore issuedCallWakeHandleStore,
  required ReceivedCallWakeHandleStore receivedCallWakeHandleStore,
  EnsureReceivedCallWakeHandle? ensureReceivedCallWakeHandle,
  MicrophoneCaptureLeaseCoordinator? microphoneCaptureLeases,
  CallMicrophonePermission? microphonePermission,
  EnsureOutgoingCallWakeAuthority? ensureOutgoingCallWakeAuthority,
  AwaitCallSignalingReadiness? awaitForegroundPresentationReadiness,
  IncomingCallPresenter? incomingCallPresenter,
  AndroidCallLifecycleAdapterFactory? androidCallLifecycleAdapterFactory,
  IosCallLifecycleAdapterFactory? iosCallLifecycleAdapterFactory,
  IosVoipTokenCoordinatorFactory? iosVoipTokenCoordinatorFactory,
  AndroidCallTokenCoordinatorFactory? androidCallTokenCoordinatorFactory,
  ProductionCallSignalingGraphObserver? onGraphBuilt,
  bool Function()? isForeground,
  int Function()? nowMs,
}) {
  final clock = nowMs ?? () => DateTime.now().toUtc().millisecondsSinceEpoch;
  final resolvedMicrophonePermission =
      microphonePermission ?? const CallMicrophonePermissionAdapter();
  DateTime callClock() =>
      DateTime.fromMillisecondsSinceEpoch(clock(), isUtc: true);
  IdentityModel? readyIdentity;
  late final CallSignalingComposition composition;
  composition = CallSignalingComposition(
    featureFlags: featureFlags,
    platform: platform,
    awaitForegroundPresentationReadiness: awaitForegroundPresentationReadiness,
    isForeground:
        isForeground ??
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    clock: callClock,
    requestOutgoingMicrophonePermission: resolvedMicrophonePermission.request,
    ensureOutgoingCallWakeAuthority: ensureOutgoingCallWakeAuthority,
    awaitReadiness: () async {
      if (!p2pService.currentState.isStarted) {
        throw StateError('call transport is unavailable');
      }
      if (!database.isOpen || !bridge.isInitialized) {
        throw StateError('call prerequisites are unavailable');
      }
      // A bounded schema read proves the contact authority is usable before
      // any call subscription or crypto adapter is constructed.
      await database.query(
        'contacts',
        columns: const <String>['peer_id'],
        limit: 1,
      );
      final identity = await loadIdentity();
      if (identity == null ||
          identity.peerId.trim().isEmpty ||
          identity.publicKey.trim().isEmpty ||
          identity.privateKey.trim().isEmpty ||
          (identity.mlKemPublicKey?.trim().isEmpty ?? true) ||
          (identity.mlKemSecretKey?.trim().isEmpty ?? true)) {
        throw StateError('call identity is unavailable');
      }
      readyIdentity = identity;
    },
    buildGraph: () async {
      final identity = readyIdentity;
      final endpointPlatform = platform;
      if (identity == null || endpointPlatform == null) {
        throw StateError('call graph is not ready');
      }
      final codec = SecureCallEnvelopeCodec(
        crypto: BridgeCallEnvelopeCrypto(bridge: bridge),
        nowMs: clock,
      );
      final mailbox = BridgeCallMailboxClient(bridge: bridge);
      final authority = BridgeCallAuthorityClient(bridge: bridge);
      final roster = DatabaseCallTrustedRosterProvider(database);
      final localDeviceKeyEpoch = callDeviceKeyEpochFromFingerprint(
        computeDirectContactLegacyTargetFingerprint(
          contactAccountPeerId: identity.peerId,
          accountSigningPublicKey: identity.publicKey,
          legacyMlKemPublicKey: identity.mlKemPublicKey!,
        ),
      );
      Future<List<CallWakeEligibleContact>> loadWakeEligibleContacts() =>
          _loadProductionCallWakeEligibleContacts(
            database: database,
            rosterProvider: roster,
          );
      final resolver = CallEndpointResolver(
        nowMs: clock,
        verifyEndpointSignature: (endpoint, trustedSigningPublicKey) =>
            authority.verifyEndpoint(
              endpoint,
              trustedDeviceSigningPublicKey: trustedSigningPublicKey,
            ),
      );
      Future<ResolvedCallEndpoint> resolveCurrentEndpoint(
        String contactAccountPeerId,
      ) => _resolveProductionCallEndpoint(
        contactAccountPeerId: contactAccountPeerId,
        resolver: resolver,
        rosterProvider: roster,
        authorityClient: authority,
        receivedCallWakeHandleStore: receivedCallWakeHandleStore,
      );
      Future<String> loadSenderSigningPrivateKey() async {
        final current = await loadIdentity();
        if (current == null ||
            current.peerId != identity.peerId ||
            current.privateKey.trim().isEmpty) {
          throw StateError('call identity changed');
        }
        return current.privateKey;
      }

      final signalingContextStore = CallSignalingContextStore();
      final negotiationMaterialStore = CallNegotiationMaterialStore();
      final boundEffects = _BoundCallEffectExecutor();
      late final CallScopedMediaBundleOwner mediaOwner;
      late final CallControlEffectExecutor controlExecutor;
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(
          <CallCleanupStep>[
            CallCleanupStep('call_media', (snapshot) async {
              await mediaOwner.closeCall(snapshot.callId!);
            }, requiredForTerminalAck: true),
            CallCleanupStep('call_signaling_context', (snapshot) async {
              await controlExecutor.retireOutgoingPreconnectInvite(snapshot);
              signalingContextStore.purge(snapshot.callId!);
            }, requiredForTerminalAck: true),
            CallCleanupStep('call_negotiation_material', (snapshot) async {
              negotiationMaterialStore.purgeCall(snapshot.callId!);
            }),
          ],
          stepTimeout: const Duration(seconds: 2),
          onReport: _emitTerminalCleanupResult,
        ),
        historyProjector: CallHistoryProjector(
          CallHistoryRepositoryImpl(database),
        ),
        effectExecutor: boundEffects,
        clock: callClock,
        idSource: _newCallId,
        terminalEffectTimeout: const Duration(milliseconds: 500),
        terminalHistoryTimeout: const Duration(milliseconds: 250),
        onAppliedStateTransition: (trigger, resultingState, endReason) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CALL_STATE_TRANSITION',
            details: <String, Object?>{
              'trigger': trigger.name,
              'state': resultingState.name,
              'endReason': endReason?.name ?? 'none',
            },
          );
        },
      );
      final useAndroidNativeLifecycle =
          incomingCallPresenter == null &&
          endpointPlatform == CallEndpointPlatform.android &&
          featureFlags['voice_call_android_native_enabled'] == true;
      final androidLifecycleAdapter = useAndroidNativeLifecycle
          ? (androidCallLifecycleAdapterFactory ??
                    _createMethodChannelAndroidCallLifecycleAdapter)
                .call(
                  coordinator: coordinator,
                  resolveAuthenticatedHandle: (callId) =>
                      signalingContextStore.read(callId)?.callHandle,
                  clock: callClock,
                )
          : null;
      final useIosNativeLifecycle =
          incomingCallPresenter == null &&
          endpointPlatform == CallEndpointPlatform.ios &&
          featureFlags['voice_call_ios_native_enabled'] == true;
      final iosLifecycleAdapter = useIosNativeLifecycle
          ? (iosCallLifecycleAdapterFactory ??
                    _createMethodChannelIosCallLifecycleAdapter)
                .call(
                  coordinator: coordinator,
                  resolveAuthenticatedHandle: (callId) =>
                      signalingContextStore.read(callId)?.callHandle,
                  clock: callClock,
                )
          : null;
      final iosTokenCoordinator = useIosNativeLifecycle
          ? (iosVoipTokenCoordinatorFactory ??
                    _createMethodChannelIosVoipTokenCoordinator)
                .call(
                  authorityClient: authority,
                  clock: callClock,
                  publicationAllowed: () =>
                      callNetworkEffectsAreAllowed(networkEffectsAllowed),
                )
          : null;
      final androidTokenCoordinator = useAndroidNativeLifecycle
          ? (androidCallTokenCoordinatorFactory ??
                    _createFirebaseAndroidCallTokenCoordinator)
                .call(
                  authorityClient: authority,
                  clock: callClock,
                  publicationAllowed: () =>
                      callNetworkEffectsAreAllowed(networkEffectsAllowed),
                )
          : null;
      final wakeAuthorizationCoordinator = CallWakeAuthorizationCoordinator(
        store: issuedCallWakeHandleStore,
        setWakeHandle: authority.setWakeHandle,
        revokeWakeHandle: authority.revokeWakeHandle,
        publishNativeContact:
            iosLifecycleAdapter?.publishOpaqueContact ??
            ({required wakeHandle, required displayName}) async {},
        revokeNativeContact:
            iosLifecycleAdapter?.revokeOpaqueContactHandle ??
            (wakeHandle) async {},
        generateHandle: const Uuid().v4,
        nowMs: clock,
      );
      final NativeCallLifecycleAdapter? nativeLifecycleAdapter =
          androidLifecycleAdapter ?? iosLifecycleAdapter;
      final signalingService = CallSignalingService(
        codec: codec,
        directTransport: P2PCallTransport(p2pService: p2pService),
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: networkEffectsAllowed,
      );
      final controlAdapter = ProductionCallControlSignalingAdapter(
        contextStore: signalingContextStore,
        clock: callClock,
        signalingService: signalingService,
        resolveCurrentEndpoint: resolveCurrentEndpoint,
        loadSenderSigningPrivateKey: loadSenderSigningPrivateKey,
      );
      controlExecutor = CallControlEffectExecutor(
        contextStore: signalingContextStore,
        signalingPort: controlAdapter,
        clock: callClock,
        idSource: _newCallId,
        cancelOutgoingMailboxInvite:
            ({required recipientDevicePeerId, required callHandle}) =>
                mailbox.cancel(
                  recipientDevicePeerId: recipientDevicePeerId,
                  callHandle: callHandle,
                ),
        registerOutgoingBeforeInvite: (callId) async {
          if (nativeLifecycleAdapter == null) return true;
          return nativeLifecycleAdapter.registerOutgoing(
            callId,
            expiresAt: callClock().add(
              endpointPlatform == CallEndpointPlatform.ios
                  ? IosCallLifecycleAdapter.outgoingRegistrationTtl
                  : AndroidCallLifecycleAdapter.outgoingRegistrationTtl,
            ),
          );
        },
      );
      final negotiationAdapter = ProductionCallNegotiationSignalingAdapter(
        signalingService: signalingService,
        contextStore: signalingContextStore,
        resolveCurrentEndpoint: resolveCurrentEndpoint,
        loadSenderSigningPrivateKey: loadSenderSigningPrivateKey,
        clock: callClock,
        messageIdSource: _newCallId,
      );
      final iceServerProvider = BridgeCallIceServerProvider(
        bridge: bridge,
        clock: callClock,
      );
      Future<List<CallIceServer>> readFreshIceServers(CallId callId) async {
        final servers = await iceServerProvider.read(callId);
        if (!servers.any((server) => server.containsTurnUrl)) {
          throw const CallNegotiationPortException(
            CallNegotiationPortErrorCode.iceServersUnavailable,
          );
        }
        return servers;
      }

      final transportPolicy =
          featureFlags['voice_call_always_relay_enabled'] == true
          ? CallTransportPolicy.relayOnly
          : CallTransportPolicy.all;
      mediaOwner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final session = coordinator.activeSession;
          if (session == null ||
              session.callId != callId ||
              session.isTerminal) {
            throw const CallScopedMediaBundleOwnerException(
              CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
            );
          }
          if (nativeLifecycleAdapter != null) {
            if (!nativeLifecycleAdapter.isBoundTo(callId)) {
              if (iosLifecycleAdapter != null) {
                throw const IosCallLifecycleException(
                  IosCallLifecycleErrorCode.unavailable,
                );
              }
              throw const AndroidCallLifecycleException(
                AndroidCallLifecycleErrorCode.unavailable,
              );
            }
          }
          final CallAudioRoutePort routeAdapter =
              nativeLifecycleAdapter ?? CallAudioRouteAdapter.flutterWebRtc();
          final engine = FlutterWebRtcCallEngine(
            adapter: FlutterWebRtcPeerConnectionAdapter(
              onFailureStage: (stage) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'CALL_WEBRTC_FAILURE_STAGE',
                  details: <String, Object?>{'stage': stage.name},
                );
              },
            ),
            audioRoutePort: routeAdapter,
          );
          final CallForegroundAudioSession audioSession =
              nativeLifecycleAdapter ??
              await CallForegroundAudioSessionAdapter.create();
          final audioController = CallAudioController(
            engine: engine,
            microphonePermission: resolvedMicrophonePermission,
            mediaConflicts: CallMediaConflictAdapter(
              isVoiceNoteRecording: isVoiceNoteRecording,
              microphoneCaptureLeases: microphoneCaptureLeases,
            ),
            audioSession: audioSession,
            onEngineStartFailure: (stage) {
              emitFlowEvent(
                layer: 'FL',
                event: 'CALL_AUDIO_ENGINE_START_FAILURE_STAGE',
                details: <String, Object?>{'stage': stage.name},
              );
            },
          );
          final mediaPreparer = CallAudioNegotiationPreparer(
            startAudio: audioController.start,
            readInitialIceServers: readFreshIceServers,
            clock: callClock,
            requireTurnServer: true,
            onStartResult: (status) {
              emitFlowEvent(
                layer: 'FL',
                event: 'CALL_AUDIO_START_RESULT',
                details: <String, Object?>{'status': status.name},
              );
              if (status == CallAudioStartStatus.started) {
                nativeLifecycleAdapter?.notifyNativeMuteTargetReady(callId);
              }
            },
          );
          final negotiationExecutor = CallNegotiationEffectExecutor(
            engine: engine,
            materialStore: negotiationMaterialStore,
            mediaPreparer: mediaPreparer,
            signaling: negotiationAdapter,
            configuration: CallConnectionConfiguration(
              transportPolicy: transportPolicy,
              receiveAudio: true,
              receiveVideo: false,
              captureAudio: true,
              captureVideo: false,
              iceServers: const <CallIceServer>[],
            ),
            dispatchEvent: (event) async {
              await coordinator.dispatch(event);
            },
            readActiveSnapshot: () => coordinator.activeSession,
            readStagedIceServers: readFreshIceServers,
            clock: callClock,
          );
          final interruptionCoordinator = CallAudioInterruptionCoordinator(
            intents: audioController.interruptionIntents,
            readActiveSession: () => coordinator.activeSession,
            readMediaSnapshot: engine.snapshot,
            dispatchEvent: (event) async {
              await coordinator.dispatch(event);
            },
            clock: callClock,
          );
          return CallScopedMediaBundle(
            callId: callId,
            engine: engine,
            audioController: audioController,
            negotiationExecutor: negotiationExecutor,
            close: () => _closeCallMediaBundle(
              interruptionCoordinator: interruptionCoordinator,
              audioController: audioController,
              negotiationExecutor: negotiationExecutor,
            ),
          );
        },
      );
      nativeLifecycleAdapter?.bindNativeMuteApplier((callId, muted) async {
        final audioController = mediaOwner.currentAudioController(callId);
        if (audioController == null) return false;
        final state = await audioController.setMuted(muted);
        if (state.failure != CallAudioFailure.none || state.muted != muted) {
          if (iosLifecycleAdapter != null) {
            throw const IosCallLifecycleException(
              IosCallLifecycleErrorCode.nativeFailure,
            );
          }
          throw const AndroidCallLifecycleException(
            AndroidCallLifecycleErrorCode.nativeFailure,
          );
        }
        return true;
      });
      boundEffects.bind(
        CompositeCallEffectExecutor(
          controlExecutor: controlExecutor,
          negotiationExecutor: mediaOwner,
        ),
      );
      final handler = HandleIncomingCallSignal(
        codec: codec,
        coordinator: coordinator,
        trustedRosterProvider: roster,
        localAuthorityProvider: () async {
          final current = await loadIdentity();
          if (current == null || current.peerId != identity.peerId) {
            throw StateError('call identity changed');
          }
          return CallLocalDeviceAuthority(
            accountPeerId: current.peerId,
            devicePeerId: current.peerId,
            mlKemSecretKey: current.mlKemSecretKey ?? '',
          );
        },
        incomingCallPresenter:
            incomingCallPresenter ?? nativeLifecycleAdapter ?? composition,
        provisionalNativeLifecycle: iosLifecycleAdapter,
        authenticatedDisplayNameResolver: iosLifecycleAdapter == null
            ? null
            : (contactAccountPeerId) async {
                try {
                  final rows = await database.query(
                    'contacts',
                    columns: const <String>['username'],
                    where: 'peer_id = ?',
                    whereArgs: <Object?>[contactAccountPeerId],
                    limit: 1,
                  );
                  if (rows.length != 1) return null;
                  final username = rows.single['username'];
                  if (username is! String) return null;
                  final displayName = username.trim();
                  return displayName.isEmpty || displayName.length > 128
                      ? null
                      : displayName;
                } catch (_) {
                  return null;
                }
              },
        networkEffectsAllowed: networkEffectsAllowed,
        negotiationMaterialStore: negotiationMaterialStore,
        signalingContextObserver: signalingContextStore,
      );
      final runtime = CallSignalingRuntime(
        directCallSignalStream: messageRouter.callSignalStream,
        mailboxClient: mailbox,
        handleIncoming: handler.handle,
        peekIncoming: handler.peek,
        coordinator: coordinator,
        networkEffectsAllowed: networkEffectsAllowed,
      );
      final graph = ProductionCallSignalingGraph(
        runtime: runtime,
        coordinator: coordinator,
        signalingService: signalingService,
        endpointResolver: resolver,
        trustedRosterProvider: roster,
        authorityClient: authority,
        wakeAuthorizationCoordinator: wakeAuthorizationCoordinator,
        issuedCallWakeHandleStore: issuedCallWakeHandleStore,
        receivedCallWakeHandleStore: receivedCallWakeHandleStore,
        loadWakeEligibleContacts: loadWakeEligibleContacts,
        ensureReceivedCallWakeHandle: ensureReceivedCallWakeHandle,
        localDeviceKeyEpoch: localDeviceKeyEpoch,
        localIdentity: identity,
        platform: endpointPlatform,
        mediaOwner: mediaOwner,
        androidCallLifecycleAdapter: androidLifecycleAdapter,
        iosCallLifecycleAdapter: iosLifecycleAdapter,
        iosVoipTokenCoordinator: iosTokenCoordinator,
        androidCallTokenCoordinator: androidTokenCoordinator,
        ringback: iosLifecycleAdapter != null
            ? MethodChannelCallRingbackPort.ios(
                resolveCallHandle: (callId) =>
                    signalingContextStore.read(callId)?.callHandle,
              )
            : androidLifecycleAdapter != null
            ? MethodChannelCallRingbackPort.android(
                resolveCallHandle: (callId) =>
                    signalingContextStore.read(callId)?.callHandle,
              )
            : null,
        networkEffectsAllowed: networkEffectsAllowed,
        nowMs: clock,
      );
      onGraphBuilt?.call(graph);
      return graph;
    },
  );
  // A suspended app loses its relay link; when the node recovers it, a call
  // invite that only reached the mailbox (the live transport was down) must
  // be drained without waiting for a foreground resume.
  _drainCallMailboxOnRelayRecovery(
    p2pService: p2pService,
    composition: composition,
  );
  return composition;
}

final class _OutgoingCallWakeAuthorityUnavailable implements Exception {
  const _OutgoingCallWakeAuthorityUnavailable();
}

AndroidCallLifecycleAdapter _createMethodChannelAndroidCallLifecycleAdapter({
  required CallCoordinator coordinator,
  required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
  required DateTime Function() clock,
}) {
  const methodChannel = MethodChannel(
    AndroidCallLifecycleAdapter.methodChannelName,
  );
  const eventChannel = EventChannel(
    AndroidCallLifecycleAdapter.eventChannelName,
  );
  return AndroidCallLifecycleAdapter(
    invokeMethod: (method, arguments) =>
        methodChannel.invokeMethod<Object?>(method, arguments),
    nativeEvents: eventChannel.receiveBroadcastStream().cast<Object?>(),
    coordinator: coordinator,
    resolveAuthenticatedHandle: resolveAuthenticatedHandle,
    clock: clock,
    onOutgoingRegistrationResult: _emitNativeOutgoingRegistrationResult,
  );
}

IosCallLifecycleAdapter _createMethodChannelIosCallLifecycleAdapter({
  required CallCoordinator coordinator,
  required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
  required DateTime Function() clock,
}) {
  const methodChannel = MethodChannel(
    IosCallLifecycleAdapter.methodChannelName,
  );
  const eventChannel = EventChannel(IosCallLifecycleAdapter.eventChannelName);
  return IosCallLifecycleAdapter(
    invokeMethod: (method, arguments) =>
        methodChannel.invokeMethod<Object?>(method, arguments),
    nativeEvents: eventChannel.receiveBroadcastStream().cast<Object?>(),
    coordinator: coordinator,
    resolveAuthenticatedHandle: resolveAuthenticatedHandle,
    clock: clock,
    onOutgoingRegistrationResult: _emitNativeOutgoingRegistrationResult,
  );
}

void _emitRingbackResult(CallRingbackAction action, String outcome) {
  emitFlowEvent(
    layer: 'FL',
    event: 'CALL_RINGBACK_RESULT',
    details: <String, dynamic>{'action': action.name, 'outcome': outcome},
  );
}

void _emitNativeOutgoingRegistrationResult(
  NativeOutgoingRegistrationStage stage,
  NativeOutgoingRegistrationStatus status,
  NativeOutgoingRegistrationReason reason,
) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_NATIVE_OUTGOING_REGISTRATION_RESULT',
      details: <String, Object?>{
        'stage': stage.name,
        'status': status.name,
        'reason': reason.name,
      },
    );
  } catch (_) {
    // Fixed-shape diagnostics cannot change native call authority.
  }
}

enum _TerminalCleanupStatus { ready, blocked }

enum _TerminalCleanupReason { none, callMedia, cleanupCapacity, otherRequired }

void _emitTerminalCleanupResult(CallCleanupReport report) {
  final status = report.terminalAckReady
      ? _TerminalCleanupStatus.ready
      : _TerminalCleanupStatus.blocked;
  final reason = switch (report.terminalAckReady) {
    true => _TerminalCleanupReason.none,
    false when report.failedStepNames.contains('call_media') =>
      _TerminalCleanupReason.callMedia,
    false when report.failedStepNames.contains('cleanup_capacity') =>
      _TerminalCleanupReason.cleanupCapacity,
    false => _TerminalCleanupReason.otherRequired,
  };
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_TERMINAL_CLEANUP_RESULT',
      details: <String, Object?>{'status': status.name, 'reason': reason.name},
    );
  } catch (_) {
    // Fixed-shape diagnostics cannot change terminal cleanup authority.
  }
}

AndroidCallTokenCoordinator _createFirebaseAndroidCallTokenCoordinator({
  required CallAuthorityClient authorityClient,
  required DateTime Function() clock,
  required CallTokenPublicationAllowed publicationAllowed,
}) => AndroidCallTokenCoordinator(
  authorityClient: authorityClient,
  clock: clock,
  readToken: () => FirebaseMessaging.instance.getToken(),
  // Lazy on purpose: FirebaseMessaging.instance is first touched when the
  // graph starts, after the live services initialised Firebase.
  tokenRefreshes: Stream<String>.multi((controller) {
    try {
      unawaited(
        controller.addStream(FirebaseMessaging.instance.onTokenRefresh),
      );
    } catch (error, stackTrace) {
      // No Firebase app yet: surface it as a stream error the coordinator
      // ignores, and let the next publication attempt subscribe again.
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }
  }),
  publicationAllowed: publicationAllowed,
  onResult: _emitAndroidCallTokenResult,
);

void _emitAndroidCallTokenResult(String outcome) {
  emitFlowEvent(
    layer: 'FL',
    event: 'CALL_ANDROID_TOKEN_PUBLISH_RESULT',
    details: <String, dynamic>{'outcome': outcome},
  );
}

IosVoipTokenCoordinator _createMethodChannelIosVoipTokenCoordinator({
  required CallAuthorityClient authorityClient,
  required DateTime Function() clock,
  required IosVoipTokenPublicationAllowed publicationAllowed,
}) {
  const methodChannel = MethodChannel(
    IosVoipTokenCoordinator.methodChannelName,
  );
  const eventChannel = EventChannel(IosVoipTokenCoordinator.eventChannelName);
  return IosVoipTokenCoordinator(
    invokeMethod: (method, arguments) =>
        methodChannel.invokeMethod<Object?>(method, arguments),
    nativeEvents: eventChannel.receiveBroadcastStream().cast<Object?>(),
    authorityClient: authorityClient,
    clock: clock,
    publicationAllowed: publicationAllowed,
  );
}

final class _BoundCallEffectExecutor implements CallEffectExecutor {
  CallEffectExecutor? _delegate;

  void bind(CallEffectExecutor delegate) {
    if (_delegate != null) throw StateError('call effects already bound');
    _delegate = delegate;
  }

  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) {
    final delegate = _delegate;
    if (delegate == null) {
      return Future<CallEvent?>.error(StateError('call effects unavailable'));
    }
    return delegate.execute(effect, snapshot);
  }
}

/// Test seam for the contact-specific, fail-closed production availability
/// probe. Diagnostics intentionally expose only fixed-cardinality stage data.
@visibleForTesting
Future<bool> probeProductionCallEndpointAvailability({
  required CallNetworkEffectsAllowed networkEffectsAllowed,
  required String contactAccountPeerId,
  required CallEndpointResolver resolver,
  required CallTrustedRosterProvider rosterProvider,
  required CallAuthorityClient authorityClient,
  required ReceivedCallWakeHandleStore receivedCallWakeHandleStore,
  EnsureReceivedCallWakeHandle? ensureReceivedCallWakeHandle,
}) async {
  var resolutionStarted = false;
  try {
    return await runCallNetworkActionIfAllowed(
      gate: networkEffectsAllowed,
      action: () async {
        resolutionStarted = true;
        await _resolveProductionCallEndpoint(
          contactAccountPeerId: contactAccountPeerId,
          resolver: resolver,
          rosterProvider: rosterProvider,
          authorityClient: authorityClient,
          receivedCallWakeHandleStore: receivedCallWakeHandleStore,
          ensureReceivedCallWakeHandle: ensureReceivedCallWakeHandle,
        );
        return true;
      },
    );
  } catch (_) {
    if (!resolutionStarted) {
      _emitCallEndpointResolutionResult(
        stage: 'network_gate',
        outcome: 'blocked',
        reason: 'network_effects_blocked',
      );
    }
    return false;
  }
}

Future<T> _loadCallEndpointDependency<T>({
  required String stage,
  required Future<T> Function() load,
}) async {
  try {
    return await load();
  } catch (_) {
    _emitCallEndpointResolutionResult(
      stage: stage,
      outcome: 'error',
      reason: 'dependency_error',
    );
    rethrow;
  }
}

void _emitCallEndpointResolutionResult({
  required String stage,
  required String outcome,
  required String reason,
}) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_ENDPOINT_RESOLUTION_RESULT',
      details: <String, Object?>{
        'stage': stage,
        'outcome': outcome,
        'reason': reason,
      },
    );
  } catch (_) {
    // Diagnostic observers must never change call availability.
  }
}

Future<ResolvedCallEndpoint> _resolveProductionCallEndpoint({
  required String contactAccountPeerId,
  required CallEndpointResolver resolver,
  required CallTrustedRosterProvider rosterProvider,
  required CallAuthorityClient authorityClient,
  required ReceivedCallWakeHandleStore receivedCallWakeHandleStore,
  EnsureReceivedCallWakeHandle? ensureReceivedCallWakeHandle,
}) async {
  final roster = await _loadCallEndpointDependency(
    stage: 'trusted_roster_load',
    load: () => rosterProvider.loadForContact(contactAccountPeerId),
  );
  try {
    await ensureReceivedCallWakeHandle?.call(contactAccountPeerId);
  } catch (_) {
    // Recovery is best effort. The durable store read below remains authority.
  }
  final wakeHandleGrant = await _loadCallEndpointDependency(
    stage: 'received_wake_handle_load',
    load: () => receivedCallWakeHandleStore.readForIssuer(contactAccountPeerId),
  );
  final relayEndpoint = await _loadCallEndpointDependency(
    stage: 'relay_endpoint_load',
    load: () => authorityClient.getEndpoint(contactAccountPeerId),
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CALL_ENDPOINT_RESOLUTION_INPUT',
    details: <String, Object?>{
      'contactAccepted': roster.contactAccepted,
      'contactBlocked': roster.contactBlocked,
      'trustedDeviceCount': roster.devices.length,
      'relayEndpointPresent': relayEndpoint != null,
      'wakeHandleGrantPresent': wakeHandleGrant != null,
    },
  );
  try {
    final endpoint = await resolver.resolve(
      contactAccountPeerId: contactAccountPeerId,
      contactAccepted: roster.contactAccepted,
      contactBlocked: roster.contactBlocked,
      trustedDevices: roster.devices,
      relayCapabilities: relayEndpoint == null
          ? const <SignedCallEndpointRecord>[]
          : <SignedCallEndpointRecord>[relayEndpoint],
      wakeHandleGrant: wakeHandleGrant,
    );
    _emitCallEndpointResolutionResult(
      stage: 'ready',
      outcome: 'available',
      reason: 'none',
    );
    return endpoint;
  } on CallEndpointResolutionException catch (error) {
    _emitCallEndpointResolutionResult(
      stage: 'endpoint_resolve',
      outcome: 'unavailable',
      reason: error.code.name,
    );
    rethrow;
  } catch (_) {
    _emitCallEndpointResolutionResult(
      stage: 'endpoint_resolve',
      outcome: 'error',
      reason: 'dependency_error',
    );
    rethrow;
  }
}

Future<List<CallWakeEligibleContact>> _loadProductionCallWakeEligibleContacts({
  required DatabaseExecutor database,
  required CallTrustedRosterProvider rosterProvider,
}) async {
  final rows = await database.query(
    'contacts',
    columns: const <String>['peer_id', 'username'],
    orderBy: 'peer_id ASC',
  );
  final contacts = <CallWakeEligibleContact>[];
  for (final row in rows) {
    final peerId = row['peer_id'];
    final username = row['username'];
    if (peerId is! String || username is! String) continue;
    final roster = await rosterProvider.loadForContact(peerId);
    if (!roster.contactAccepted ||
        roster.contactBlocked ||
        roster.devices.isEmpty) {
      continue;
    }
    try {
      contacts.add(
        CallWakeEligibleContact(
          contactAccountPeerId: peerId,
          displayName: username.trim(),
          authorizedSenderDevicePeerIds: roster.devices.map(
            (device) => device.devicePeerId,
          ),
        ),
      );
    } on ArgumentError {
      // One malformed local contact is not call-wake eligible and must not
      // prevent revocation/reconciliation for every other contact.
    }
  }
  return contacts;
}

Future<void> _closeCallMediaBundle({
  required CallAudioInterruptionCoordinator interruptionCoordinator,
  required CallAudioController audioController,
  required CallNegotiationEffectExecutor negotiationExecutor,
}) => _closeCallMediaBundleSteps(
  closeInterruptionCoordinator: interruptionCoordinator.close,
  closeAudioController: audioController.close,
  audioCleanupFailed: () =>
      audioController.state.failure == CallAudioFailure.cleanupFailed ||
      audioController.state.active,
  closeNegotiationExecutor: negotiationExecutor.close,
);

/// Test seam for the per-call media bundle close ordering and its
/// fixed-cardinality failure-stage diagnostics (mirrors the production
/// `close` closure of [CallScopedMediaBundle]).
@visibleForTesting
Future<void> debugCloseCallMediaBundle({
  required Future<void> Function() closeInterruptionCoordinator,
  required Future<void> Function() closeAudioController,
  required bool Function() audioCleanupFailed,
  required Future<void> Function() closeNegotiationExecutor,
}) => _closeCallMediaBundleSteps(
  closeInterruptionCoordinator: closeInterruptionCoordinator,
  closeAudioController: closeAudioController,
  audioCleanupFailed: audioCleanupFailed,
  closeNegotiationExecutor: closeNegotiationExecutor,
);

Future<void> _closeCallMediaBundleSteps({
  required Future<void> Function() closeInterruptionCoordinator,
  required Future<void> Function() closeAudioController,
  required bool Function() audioCleanupFailed,
  required Future<void> Function() closeNegotiationExecutor,
}) async {
  Object? firstError;
  StackTrace? firstStack;

  Future<bool> attempt(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
      return false;
    }
  }

  if (!await attempt(closeInterruptionCoordinator)) {
    _emitMediaCloseFailureStage('interruption_release');
  }
  await attempt(closeAudioController);
  if (audioCleanupFailed()) {
    _emitMediaCloseFailureStage('audio_cleanup');
    firstError ??= const AndroidCallLifecycleException(
      AndroidCallLifecycleErrorCode.nativeFailure,
    );
    firstStack ??= StackTrace.current;
  }
  if (!await attempt(closeNegotiationExecutor)) {
    _emitMediaCloseFailureStage('engine_release');
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStack!);
  }
}

/// Names the media-bundle close leg that failed so a blocked `call_media`
/// terminal cleanup is attributable from device logs. Fixed vocabulary only:
/// `interruption_release`, `audio_cleanup`, `engine_release`.
void _emitMediaCloseFailureStage(String stage) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_MEDIA_CLOSE_FAILURE_STAGE',
      details: <String, Object?>{'stage': stage},
    );
  } catch (_) {
    // Diagnostics never change cleanup authority.
  }
}

CallId _newCallId() => CallId.parse(const Uuid().v4());

/// Calls [CallSignalingComposition.onCallWake] each time the node's relay
/// health goes from none to at least one healthy relay. Stops after the
/// composition shut down.
void _drainCallMailboxOnRelayRecovery({
  required P2PService p2pService,
  required CallSignalingComposition composition,
}) {
  var previousHealthy = p2pService.currentState.healthyRelayCount ?? 0;
  StreamSubscription<NodeState>? subscription;
  subscription = p2pService.stateStream.listen((state) {
    if (composition.isShutdown) {
      unawaited(subscription?.cancel());
      return;
    }
    final healthy = state.healthyRelayCount ?? 0;
    final recovered = previousHealthy <= 0 && healthy > 0;
    previousHealthy = healthy;
    if (recovered) unawaited(composition.onCallWake());
  }, onError: (Object _) {});
}
