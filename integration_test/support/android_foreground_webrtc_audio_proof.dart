import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';

import 'android_foreground_webrtc_audio_canonical_stack.dart';
import 'android_foreground_webrtc_audio_evidence.dart';
import 'android_foreground_webrtc_audio_probe.dart';
import 'sims_runtime_protocol.dart';

const Duration _signalingTimeout = Duration(seconds: 45);
const Duration _mediaReadyTimeout = Duration(seconds: 45);
const Duration _directionalSampleWindow = Duration(seconds: 4);
const int _maximumRendezvousResponseBytes = 256 * 1024;

enum AndroidForegroundWebRtcAudioUdpProbeOutcome {
  noMatchingResponse,
  matchingResponse,
  probeError,
}

typedef AndroidForegroundWebRtcAudioUdpProbe =
    Future<AndroidForegroundWebRtcAudioUdpProbeOutcome> Function({
      required String host,
      required int port,
      required Duration timeout,
    });

typedef AndroidForegroundWebRtcAudioTcpProbe =
    Future<bool> Function({
      required String host,
      required int port,
      required Duration timeout,
    });

/// Bounded endpoint-network precondition for the dual-URL TURN/TCP fallback.
///
/// Only fixed counts and booleans leave this object. The authority, STUN
/// transaction bytes, socket details, and any response bytes remain transient.
final class AndroidForegroundWebRtcAudioTcpFallbackPrecondition {
  const AndroidForegroundWebRtcAudioTcpFallbackPrecondition._({
    required this.applied,
    required this.udpProbeAttempts,
    required int udpMatchingResponseCount,
    required int udpProbeErrorCount,
    required this.tcpReachable,
  }) : _udpMatchingResponseCount = udpMatchingResponseCount,
       _udpProbeErrorCount = udpProbeErrorCount;

  const AndroidForegroundWebRtcAudioTcpFallbackPrecondition.notApplied()
    : this._(
        applied: false,
        udpProbeAttempts: 0,
        udpMatchingResponseCount: 0,
        udpProbeErrorCount: 0,
        tcpReachable: false,
      );

  final bool applied;
  final int udpProbeAttempts;
  final int _udpMatchingResponseCount;
  final int _udpProbeErrorCount;
  final bool tcpReachable;

  bool get proven =>
      applied &&
      udpProbeAttempts == 3 &&
      _udpMatchingResponseCount == 0 &&
      _udpProbeErrorCount == 0 &&
      tcpReachable;

  Map<String, Object?> toEvidence() => <String, Object?>{
    'applied': applied,
    'udpProbeAttempts': udpProbeAttempts,
    'udpStunResponseAbsent':
        applied && _udpMatchingResponseCount == 0 && _udpProbeErrorCount == 0,
    'tcpReachable': tcpReachable,
  };

  @override
  String toString() =>
      'AndroidForegroundWebRtcAudioTcpFallbackPrecondition(redacted)';
}

Future<AndroidForegroundWebRtcAudioTcpFallbackPrecondition>
runAndroidForegroundWebRtcAudioTcpFallbackPrecondition({
  required String host,
  required int port,
  AndroidForegroundWebRtcAudioUdpProbe? udpProbe,
  AndroidForegroundWebRtcAudioTcpProbe? tcpProbe,
  Duration udpTimeout = const Duration(milliseconds: 750),
  Duration tcpTimeout = const Duration(seconds: 2),
}) async {
  if (host.isEmpty ||
      host.length > 253 ||
      port < 1 ||
      port > 65535 ||
      udpTimeout <= Duration.zero ||
      udpTimeout > const Duration(seconds: 1) ||
      tcpTimeout <= Duration.zero ||
      tcpTimeout > const Duration(seconds: 2)) {
    throw ArgumentError('invalid bounded TCP fallback precondition');
  }
  final runUdp = udpProbe ?? _probeUdpStunBinding;
  final runTcp = tcpProbe ?? _probeTcpReachability;
  var matchingResponses = 0;
  var probeErrors = 0;
  const attempts = 3;
  for (var attempt = 0; attempt < attempts; attempt++) {
    final outcome = await runUdp(host: host, port: port, timeout: udpTimeout)
        .timeout(
          udpTimeout + const Duration(milliseconds: 100),
          onTimeout: () =>
              AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError,
        );
    switch (outcome) {
      case AndroidForegroundWebRtcAudioUdpProbeOutcome.noMatchingResponse:
        break;
      case AndroidForegroundWebRtcAudioUdpProbeOutcome.matchingResponse:
        matchingResponses++;
        break;
      case AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError:
        probeErrors++;
        break;
    }
  }
  final tcpReachable = await runTcp(
    host: host,
    port: port,
    timeout: tcpTimeout,
  ).timeout(tcpTimeout, onTimeout: () => false);
  return AndroidForegroundWebRtcAudioTcpFallbackPrecondition._(
    applied: true,
    udpProbeAttempts: attempts,
    udpMatchingResponseCount: matchingResponses,
    udpProbeErrorCount: probeErrors,
    tcpReachable: tcpReachable,
  );
}

/// Privacy-safe exception crossing only the dispatcher boundary.
///
/// It intentionally drops the original exception text and retains only the
/// invocation-bound enum context accepted by the failed-endpoint validator.
final class AndroidForegroundWebRtcAudioProofExecutionFailure
    implements Exception {
  const AndroidForegroundWebRtcAudioProofExecutionFailure({
    required this.stage,
    required this.state,
    required this.endReason,
    required this.effect,
    required this.followUp,
    required this.probeStage,
    required this.turnConfigStage,
    required this.descriptionCandidates,
    required this.descriptionSecurity,
    required this.engineError,
    required this.readinessFailure,
    required this.selectedTransport,
    required this.selectedRelayProtocol,
    required this.clientStage,
    required this.inboundOutcome,
    required this.publishedControlCount,
    required this.receivedControlCount,
  });

  final AndroidForegroundWebRtcAudioFailureStage stage;
  final String state;
  final String endReason;
  final String effect;
  final String followUp;
  final String probeStage;
  final String turnConfigStage;
  final String descriptionCandidates;
  final String descriptionSecurity;
  final String engineError;
  final String readinessFailure;
  final String selectedTransport;
  final String selectedRelayProtocol;
  final String clientStage;
  final String inboundOutcome;
  final int publishedControlCount;
  final int receivedControlCount;

  Map<String, Object?> failedEndpoint(SimsRuntimeInvocation invocation) =>
      androidForegroundWebRtcAudioFailedEndpoint(
        invocation: invocation,
        stage: stage,
        state: state,
        endReason: endReason,
        effect: effect,
        followUp: followUp,
        probeStage: probeStage,
        turnConfigStage: turnConfigStage,
        descriptionCandidates: descriptionCandidates,
        descriptionSecurity: descriptionSecurity,
        engineError: engineError,
        readinessFailure: readinessFailure,
        selectedTransport: selectedTransport,
        selectedRelayProtocol: selectedRelayProtocol,
        clientStage: clientStage,
        inboundOutcome: inboundOutcome,
        publishedControlCount: publishedControlCount,
        receivedControlCount: receivedControlCount,
      );
}

/// Runs one endpoint of the two-Android foreground audio proof.
///
/// Secure envelopes, SDP/candidates, rendezvous authorization, and RTP totals
/// stay in memory. The returned map contains only bounded hashes, counts, and
/// fixed privacy-safe canonical/media outcomes consumed by the host validator.
Future<Map<String, Object?>> runAndroidForegroundWebRtcAudioProof(
  SimsRuntimeInvocation invocation,
) async {
  final validation = validateAndroidForegroundWebRtcAudioRuntimeInvocation(
    invocation,
  );
  if (!validation.ok) throw StateError(validation.detail);

  final role = invocation.role;
  final targetKind = invocation.values['targetKind']! as String;
  final relayMode = switch (invocation.values['relayMode']) {
    'turnUdp' => AndroidForegroundWebRtcAudioRelayMode.turnUdp,
    'turnTcp' => AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    _ => null,
  };
  final turnFixture = relayMode == null
      ? null
      : AndroidForegroundWebRtcTurnFixture(
          mode: relayMode,
          urls: List<String>.from(invocation.values['turnUrls']! as List),
          username: invocation.values['turnUsername']! as String,
          password: invocation.values['turnPassword']! as String,
          expiresAtMs: invocation.values['turnExpiresAtMs']! as int,
        );
  final client = _ForegroundAudioRendezvousClient(
    baseUri: Uri.parse(invocation.values['rendezvousUrl']! as String),
    bearer: invocation.values['bearer']! as String,
  );
  AndroidForegroundWebRtcCanonicalEndpoint? stack;
  var foregroundResumed = false;
  var bothMuted = false;
  Map<String, Object?>? routeProof;
  _DirectionalPhaseResult? callerToCallee;
  _DirectionalPhaseResult? calleeToCaller;
  Map<String, Object?>? endpoint;
  var tcpFallbackPrecondition =
      const AndroidForegroundWebRtcAudioTcpFallbackPrecondition.notApplied();
  var failureStage = AndroidForegroundWebRtcAudioFailureStage.foregroundResume;

  try {
    foregroundResumed = await _waitForForeground();
    if (!foregroundResumed) {
      throw StateError('foreground WebRTC audio app was not resumed');
    }
    failureStage = AndroidForegroundWebRtcAudioFailureStage.rendezvousJoin;
    await client.join();
    if (relayMode == AndroidForegroundWebRtcAudioRelayMode.turnTcp) {
      failureStage =
          AndroidForegroundWebRtcAudioFailureStage.transportPrecondition;
      final tcpUrl = turnFixture!.urls.last;
      final authority = RegExp(
        r'^turn:([A-Za-z0-9.-]+):([0-9]{1,5})\?transport=tcp$',
      ).firstMatch(tcpUrl);
      if (authority == null) {
        throw StateError('TURN/TCP fallback authority was invalid');
      }
      tcpFallbackPrecondition =
          await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
            host: authority.group(1)!,
            port: int.parse(authority.group(2)!),
          );
      if (!tcpFallbackPrecondition.proven) {
        throw StateError('TURN/TCP fallback precondition was not proven');
      }
    }
    failureStage = AndroidForegroundWebRtcAudioFailureStage.canonicalSetup;
    stack = await AndroidForegroundWebRtcCanonicalEndpoint.create(
      role: role,
      carrier: client,
      turnFixture: turnFixture,
    );
    await client.publishControl('canonical-endpoint-ready');
    await client.waitForControl(
      endpoint: stack,
      name: 'canonical-endpoint-ready',
      timeout: _signalingTimeout,
    );

    failureStage = AndroidForegroundWebRtcAudioFailureStage.callSignaling;
    if (role == simsForegroundWebRtcCallerRole) {
      await stack.place();
      await client.waitForControl(
        endpoint: stack,
        name: 'callee-ringing-ready',
        timeout: _signalingTimeout,
      );
      if (!stack.hasSeenState(CallState.ringing)) {
        throw StateError('caller did not observe canonical ringing');
      }
      stack.capturePreAcceptBoundary();
      await client.publishControl('caller-ringing-observed');
    } else {
      await _waitForCanonicalState(
        stack,
        client,
        CallState.ringing,
        _signalingTimeout,
      );
      stack.capturePreAcceptBoundary();
      await client.publishControl('callee-ringing-ready');
      await client.waitForControl(
        endpoint: stack,
        name: 'caller-ringing-observed',
        timeout: _signalingTimeout,
      );
      await stack.answer();
    }

    failureStage = AndroidForegroundWebRtcAudioFailureStage.mediaReadiness;
    await _waitForCanonicalState(
      stack,
      client,
      CallState.connected,
      _mediaReadyTimeout,
    );
    await stack.captureConnectedReadiness();
    if (!stack.mediaReady ||
        !stack.audioOnly ||
        (relayMode == null && !stack.directSelected) ||
        (relayMode != null && !stack.expectedRelayTransportSelected)) {
      throw StateError('foreground WebRTC audio readiness was incomplete');
    }

    failureStage = AndroidForegroundWebRtcAudioFailureStage.controls;
    final controller = stack.audioController;
    final mutedState = await controller.setMuted(true);
    if (!mutedState.muted || mutedState.failure != CallAudioFailure.none) {
      throw StateError('foreground WebRTC audio mute failed');
    }
    await client.publishControl('both-muted');
    await client.waitForControl(
      endpoint: stack,
      name: 'both-muted',
      timeout: _signalingTimeout,
    );
    bothMuted = true;

    routeProof = await _exerciseRoutes(controller);
    failureStage = AndroidForegroundWebRtcAudioFailureStage.directionalMedia;
    callerToCallee = await _runDirectionalPhase(
      name: 'caller-to-callee',
      senderRole: simsForegroundWebRtcCallerRole,
      role: role,
      controller: controller,
      probe: stack.probe,
      client: client,
      endpoint: stack,
    );
    calleeToCaller = await _runDirectionalPhase(
      name: 'callee-to-caller',
      senderRole: simsForegroundWebRtcCalleeRole,
      role: role,
      controller: controller,
      probe: stack.probe,
      client: client,
      endpoint: stack,
    );
    bothMuted = controller.state.muted;
    if (!bothMuted) {
      throw StateError('foreground WebRTC audio final mute was not observed');
    }

    failureStage = AndroidForegroundWebRtcAudioFailureStage.canonicalEnd;
    if (role == simsForegroundWebRtcCallerRole) {
      await stack.end();
      await client.waitForControl(
        endpoint: stack,
        name: 'canonical-ended-observed',
        timeout: _signalingTimeout,
        terminalIsExpected: true,
      );
    } else {
      await _waitForCanonicalState(
        stack,
        client,
        CallState.ended,
        _signalingTimeout,
      );
      await client.publishControl('canonical-ended-observed');
    }
    if (!stack.hasSeenState(CallState.ended)) {
      throw StateError('foreground WebRTC audio canonical end was not applied');
    }
    final directionalRtpDelta = <String, Object?>{
      'callerToCalleeOutbound': callerToCallee.outboundAdvanced,
      'callerToCalleeInbound': callerToCallee.inboundAdvanced,
      'calleeToCallerOutbound': calleeToCaller.outboundAdvanced,
      'calleeToCallerInbound': calleeToCaller.inboundAdvanced,
    };
    final common = <String, Object?>{
      'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
      'status': 'passed',
      'role': role,
      'targetKind': targetKind,
      'bindingSha256': androidForegroundWebRtcAudioBindingSha256(invocation),
      'callBindingSha256': stack.callBindingSha256(invocation.runId),
      'foregroundResumed': foregroundResumed,
      'locallyAccepted': stack.hasSeenState(CallState.accepted),
      'permissionGranted': stack.permissionGranted,
      'audioOnly': stack.audioOnly,
      'mediaReady': stack.mediaReady,
      'bothMuted': bothMuted,
      'canonicalJourney': stack.canonicalJourney,
      'connectedReadiness': stack.connectedReadiness,
      'signalingTrace': stack.signalingTrace,
      'directionalRtpDelta': directionalRtpDelta,
      'cleanup': stack.cleanup,
    };
    endpoint = relayMode == null
        ? <String, Object?>{
            'schema': androidForegroundWebRtcAudioEndpointSchema,
            ...common,
            'directSelected': stack.directSelected,
            'route': routeProof,
          }
        : <String, Object?>{
            'schema': androidForegroundWebRtcAudioRelayEndpointSchema,
            ...common,
            'relayMode': relayMode.name,
            'bridgeCredentialPath': stack.bridgeCredentialPath,
            'relayPrivacy': stack.relayPrivacy,
            'selectedTransport': stack.selectedTransport,
            'selectedRelayProtocol': stack.selectedRelayProtocol,
            'tcpFallbackPrecondition': tcpFallbackPrecondition.toEvidence(),
            'acceptToAudioMs': stack.acceptToAudioMs,
          };
  } on Object catch (_, stackTrace) {
    final context = stack?.terminalFailureContext;
    final clientContext = client.diagnosticContext;
    Error.throwWithStackTrace(
      AndroidForegroundWebRtcAudioProofExecutionFailure(
        stage: failureStage,
        state: context?['state'] ?? 'none',
        endReason: context?['endReason'] ?? 'none',
        effect: context?['effect'] ?? 'none',
        followUp: context?['followUp'] ?? 'none',
        probeStage: context?['probeStage'] ?? 'none',
        turnConfigStage: context?['turnConfigStage'] ?? 'notRequested',
        descriptionCandidates:
            context?['descriptionCandidates'] ?? 'notCreated',
        descriptionSecurity: context?['descriptionSecurity'] ?? 'notCreated',
        engineError: context?['engineError'] ?? 'none',
        readinessFailure: context?['readinessFailure'] ?? 'notCaptured',
        selectedTransport: context?['selectedTransport'] ?? 'none',
        selectedRelayProtocol: context?['selectedRelayProtocol'] ?? 'none',
        clientStage: clientContext['clientStage']! as String,
        inboundOutcome: clientContext['inboundOutcome']! as String,
        publishedControlCount: clientContext['publishedControlCount']! as int,
        receivedControlCount: clientContext['receivedControlCount']! as int,
      ),
      stackTrace,
    );
  } finally {
    await stack?.dispose();
    client.close();
  }

  final completedEndpoint = endpoint;
  final endpointValidation = relayMode == null
      ? validateAndroidForegroundWebRtcAudioEndpoint(
          completedEndpoint,
          invocation: invocation,
        )
      : validateAndroidForegroundWebRtcAudioRelayEndpoint(
          completedEndpoint,
          invocation: invocation,
        );
  if (!endpointValidation.ok) throw StateError(endpointValidation.detail);
  return completedEndpoint;
}

Future<void> _waitForCanonicalState(
  AndroidForegroundWebRtcCanonicalEndpoint endpoint,
  _ForegroundAudioRendezvousClient client,
  CallState state,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await client.pump(endpoint);
    if (endpoint.hasSeenState(state)) return;
    final last = endpoint.coordinator.lastSnapshot;
    if (last?.isTerminal == true && state != CallState.ended) {
      throw StateError(
        'foreground WebRTC canonical call ended early '
        '(${endpoint.terminalDiagnostic})',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('foreground WebRTC canonical state timed out');
}

Future<AndroidForegroundWebRtcAudioUdpProbeOutcome> _probeUdpStunBinding({
  required String host,
  required int port,
  required Duration timeout,
}) async {
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;
  final transactionId = List<int>.generate(
    12,
    (_) => Random.secure().nextInt(256),
    growable: false,
  );
  final request = Uint8List(20);
  final header = ByteData.sublistView(request);
  header.setUint16(0, 0x0001);
  header.setUint16(2, 0);
  header.setUint32(4, 0x2112a442);
  request.setRange(8, 20, transactionId);
  final outcome = Completer<AndroidForegroundWebRtcAudioUdpProbeOutcome>();
  var sent = false;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read || outcome.isCompleted) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final bytes = datagram!.data;
          if (_isMatchingStunBindingResponse(bytes, transactionId)) {
            outcome.complete(
              AndroidForegroundWebRtcAudioUdpProbeOutcome.matchingResponse,
            );
            return;
          }
        }
      },
      onError: (_) {
        if (!outcome.isCompleted) {
          outcome.complete(
            sent
                ? AndroidForegroundWebRtcAudioUdpProbeOutcome.noMatchingResponse
                : AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError,
          );
        }
      },
    );
    final sentBytes = socket.send(request, InternetAddress(host), port);
    if (sentBytes != request.length) {
      return AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError;
    }
    sent = true;
    return await outcome.future.timeout(
      timeout,
      onTimeout: () =>
          AndroidForegroundWebRtcAudioUdpProbeOutcome.noMatchingResponse,
    );
  } on SocketException {
    return sent
        ? AndroidForegroundWebRtcAudioUdpProbeOutcome.noMatchingResponse
        : AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError;
  } finally {
    await subscription?.cancel();
    socket?.close();
  }
}

bool _isMatchingStunBindingResponse(
  List<int> response,
  List<int> transactionId,
) {
  if (response.length < 20 ||
      response[0] != 0x01 ||
      response[1] != 0x01 ||
      response[4] != 0x21 ||
      response[5] != 0x12 ||
      response[6] != 0xa4 ||
      response[7] != 0x42) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < transactionId.length; index++) {
    difference |= response[index + 8] ^ transactionId[index];
  }
  return difference == 0;
}

Future<bool> _probeTcpReachability({
  required String host,
  required int port,
  required Duration timeout,
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    return true;
  } on SocketException {
    return false;
  } finally {
    socket?.destroy();
  }
}

Future<bool> _waitForForeground() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

Future<Map<String, Object?>> _exerciseRoutes(
  CallAudioController controller,
) async {
  final supported = controller.state.supportedRoutes;
  final speakerSupported = supported.contains(CallAudioOutputRoute.speaker);
  var speakerSelected = false;
  if (speakerSupported) {
    final speaker = await controller.selectOutputRoute(
      CallAudioOutputRoute.speaker,
    );
    speakerSelected =
        speaker.failure == CallAudioFailure.none &&
        speaker.selectedRoute == CallAudioOutputRoute.speaker;
    if (!speakerSelected) {
      throw StateError('foreground WebRTC audio speaker route failed');
    }
  }
  final restored = await controller.selectOutputRoute(
    CallAudioOutputRoute.systemDefault,
  );
  if (restored.failure != CallAudioFailure.none ||
      restored.selectedRoute != CallAudioOutputRoute.systemDefault) {
    throw StateError('foreground WebRTC audio default route failed');
  }
  return <String, Object?>{
    'speakerSupported': speakerSupported,
    'speakerSelected': speakerSelected,
    'finalRoute': restored.selectedRoute.name,
  };
}

Future<_DirectionalPhaseResult> _runDirectionalPhase({
  required String name,
  required String senderRole,
  required String role,
  required CallAudioController controller,
  required AndroidForegroundWebRtcAudioProbeAdapter probe,
  required _ForegroundAudioRendezvousClient client,
  required AndroidForegroundWebRtcCanonicalEndpoint endpoint,
}) async {
  final before = await probe.audioRtpTotals();
  await client.publishControl('$name-baseline');
  await client.waitForControl(
    endpoint: endpoint,
    name: '$name-baseline',
    timeout: _signalingTimeout,
  );

  if (role == senderRole) {
    final unmuted = await controller.setMuted(false);
    if (unmuted.muted || unmuted.failure != CallAudioFailure.none) {
      throw StateError('foreground WebRTC audio phase unmute failed');
    }
    await client.publishControl('$name-unmuted');
  } else {
    await client.waitForControl(
      endpoint: endpoint,
      name: '$name-unmuted',
      timeout: _signalingTimeout,
    );
  }

  await Future<void>.delayed(_directionalSampleWindow);
  final after = await probe.audioRtpTotals();
  await client.publishControl('$name-sampled');
  await client.waitForControl(
    endpoint: endpoint,
    name: '$name-sampled',
    timeout: _signalingTimeout,
  );

  if (role == senderRole) {
    final muted = await controller.setMuted(true);
    if (!muted.muted || muted.failure != CallAudioFailure.none) {
      throw StateError('foreground WebRTC audio phase mute failed');
    }
    await client.publishControl('$name-muted');
  } else {
    await client.waitForControl(
      endpoint: endpoint,
      name: '$name-muted',
      timeout: _signalingTimeout,
    );
  }
  return _DirectionalPhaseResult(
    outboundAdvanced: after.outboundAdvancedFrom(before),
    inboundAdvanced: after.inboundAdvancedFrom(before),
  );
}

final class _DirectionalPhaseResult {
  const _DirectionalPhaseResult({
    required this.outboundAdvanced,
    required this.inboundAdvanced,
  });

  final bool outboundAdvanced;
  final bool inboundAdvanced;
}

final class _ForegroundAudioRendezvousClient
    implements AndroidForegroundWebRtcCanonicalEnvelopeCarrier {
  _ForegroundAudioRendezvousClient({
    required this.baseUri,
    required this.bearer,
  });

  final Uri baseUri;
  final String bearer;
  final HttpClient _httpClient = HttpClient();
  final Set<String> _controls = <String>{};
  int _cursor = 0;
  AndroidForegroundWebRtcAudioClientStage _clientStage =
      AndroidForegroundWebRtcAudioClientStage.none;
  String _inboundOutcome = 'none';
  int _publishedControlCount = 0;
  int _receivedControlCount = 0;

  Map<String, Object?> get diagnosticContext => <String, Object?>{
    'clientStage': _clientStage.name,
    'inboundOutcome': _inboundOutcome,
    'publishedControlCount': _publishedControlCount,
    'receivedControlCount': _receivedControlCount,
  };

  Future<void> join() async {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.joining;
    final response = await _request(
      method: 'POST',
      path: '/join',
      body: const <String, Object?>{},
    );
    if (response['accepted'] != true) {
      throw StateError('foreground WebRTC audio rendezvous rejected join');
    }
    _clientStage = AndroidForegroundWebRtcAudioClientStage.joined;
  }

  @override
  Future<void> publishEnvelope(String envelopeJson) async {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.publishingEnvelope;
    await _publish('envelope', <String, Object?>{'envelope': envelopeJson});
    _clientStage = AndroidForegroundWebRtcAudioClientStage.joined;
  }

  Future<void> publishControl(String name) async {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.publishingControl;
    await _publish('control', <String, Object?>{'name': name});
    _publishedControlCount++;
    _clientStage = AndroidForegroundWebRtcAudioClientStage.joined;
  }

  Future<void> _publish(String kind, Map<String, Object?> payload) async {
    final response = await _request(
      method: 'POST',
      path: '/event',
      body: <String, Object?>{'kind': kind, 'payload': payload},
    );
    if (response['accepted'] != true) {
      throw StateError('foreground WebRTC audio rendezvous rejected event');
    }
  }

  Future<void> waitForControl({
    required AndroidForegroundWebRtcCanonicalEndpoint endpoint,
    required String name,
    required Duration timeout,
    bool terminalIsExpected = false,
  }) async {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.waitingControl;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await pump(endpoint);
      if (_controls.remove(name)) return;
      final last = endpoint.coordinator.lastSnapshot;
      if (!terminalIsExpected && last?.isTerminal == true) {
        throw StateError(
          'foreground WebRTC canonical call ended early '
          '(${endpoint.terminalDiagnostic})',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('foreground WebRTC audio phase timed out');
  }

  Future<void> pump(AndroidForegroundWebRtcCanonicalEndpoint endpoint) async {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.polling;
    final response = await _request(
      method: 'GET',
      path: '/events?cursor=$_cursor',
    );
    final events = response['events'];
    if (events is! List || events.length > 64) {
      throw StateError('foreground WebRTC audio event batch is invalid');
    }
    for (final rawEvent in events) {
      final event = _object(rawEvent);
      final sequence = event?['sequence'];
      final kind = event?['kind'];
      final payload = _object(event?['payload']);
      if (sequence is! int ||
          sequence <= _cursor ||
          kind is! String ||
          payload == null) {
        throw StateError('foreground WebRTC audio event is invalid');
      }
      switch (kind) {
        case 'envelope':
          _clientStage =
              AndroidForegroundWebRtcAudioClientStage.handlingEnvelope;
          if (payload.length != 1 || !payload.containsKey('envelope')) {
            throw StateError('foreground WebRTC audio envelope is invalid');
          }
          final envelope = payload['envelope'];
          if (envelope is! String ||
              envelope.isEmpty ||
              envelope.length > 192 * 1024) {
            throw StateError('foreground WebRTC audio envelope is invalid');
          }
          final outcome = await endpoint.handleEnvelope(envelope);
          _inboundOutcome = outcome.name;
          if (outcome == IncomingCallSignalOutcome.deferred) return;
          _cursor = sequence;
        case 'control':
          _clientStage =
              AndroidForegroundWebRtcAudioClientStage.handlingControl;
          final name = payload['name'];
          if (name is! String ||
              name.isEmpty ||
              name.length > 80 ||
              !RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
            throw StateError('foreground WebRTC audio control is invalid');
          }
          _controls.add(name);
          _receivedControlCount++;
          _cursor = sequence;
        default:
          throw StateError('foreground WebRTC audio event kind is invalid');
      }
    }
    _clientStage = AndroidForegroundWebRtcAudioClientStage.polling;
  }

  Future<Map<String, Object?>> _request({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    try {
      final uri = baseUri.resolve(path);
      final request = method == 'POST'
          ? await _httpClient.postUrl(uri)
          : await _httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
        if (buffer.length + chunk.length > _maximumRendezvousResponseBytes) {
          throw StateError(
            'foreground WebRTC audio rendezvous response is too large',
          );
        }
        return buffer..addAll(chunk);
      });
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('foreground WebRTC audio rendezvous request failed');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final object = _object(decoded);
      if (object == null) {
        throw StateError(
          'foreground WebRTC audio rendezvous response is invalid',
        );
      }
      return object;
    } on StateError {
      rethrow;
    } on Object {
      // Network and JSON exceptions may contain the private endpoint or body.
      throw StateError('foreground WebRTC audio rendezvous request failed');
    }
  }

  void close() {
    _clientStage = AndroidForegroundWebRtcAudioClientStage.closed;
    _controls.clear();
    _httpClient.close(force: true);
  }
}

Map<String, Object?>? _object(Object? value) => value is Map
    ? value.map<String, Object?>((key, entry) => MapEntry('$key', entry))
    : null;
