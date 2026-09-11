import '../domain/call_engine.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_audio_controller.dart';
import 'call_negotiation_effect_executor.dart';

typedef StartCallAudio =
    Future<CallAudioStartResult> Function({
      required bool locallyAccepted,
      required CallConnectionConfiguration configuration,
    });
typedef CallAudioStartResultObserver =
    void Function(CallAudioStartStatus status);

/// Adapts reducer-proven acceptance into the foreground audio owner without
/// giving the negotiation executor direct permission/plugin knowledge.
final class CallAudioNegotiationPreparer
    implements CallNegotiationMediaPreparer {
  CallAudioNegotiationPreparer({
    required StartCallAudio startAudio,
    required this.isCurrentCall,
    CallStagedIceServerReader? readInitialIceServers,
    DateTime Function()? clock,
    CallAudioStartResultObserver? onStartResult,
  }) : _startAudio = startAudio,
       _readInitialIceServers = readInitialIceServers,
       _clock = clock ?? DateTime.now,
       _onStartResult = onStartResult;

  final StartCallAudio _startAudio;
  final CallStagedIceServerReader? _readInitialIceServers;
  final DateTime Function() _clock;
  final bool Function(CallId callId) isCurrentCall;
  final CallAudioStartResultObserver? _onStartResult;

  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) async {
    final accepted =
        snapshot.acceptedAt != null &&
        switch (snapshot.state) {
          CallState.accepted ||
          CallState.negotiating ||
          CallState.reconnecting => true,
          _ => false,
        };
    if (!accepted ||
        snapshot.callId == null ||
        !isCurrentCall(snapshot.callId!)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }

    final reader = _readInitialIceServers;
    // The bounded reader alone classifies transient failure. Never swallow an
    // authentication/validation exception merely because direct ICE is allowed.
    final staged = reader == null
        ? const <CallIceServer>[]
        : await reader(snapshot.callId!);
    if (!isCurrentCall(snapshot.callId!)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
    // Recheck expiry after the wait, including approved preconfigured STUN.
    final now = _clock().toUtc();
    var iceServers = [
      ...configuration.iceServers,
      ...staged,
    ].where((server) => server.expiresAt.isAfter(now)).toList();
    final hasTurn = iceServers.any((server) => server.containsTurnUrl);
    if (configuration.transportPolicy == CallTransportPolicy.relayOnly &&
        !hasTurn) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.iceServersUnavailable,
      );
    }
    iceServers = List<CallIceServer>.unmodifiable(iceServers);
    final effectiveConfiguration = CallConnectionConfiguration(
      transportPolicy: configuration.transportPolicy,
      receiveAudio: configuration.receiveAudio,
      receiveVideo: configuration.receiveVideo,
      captureAudio: configuration.captureAudio,
      captureVideo: configuration.captureVideo,
      iceServers: iceServers,
    );

    final result = await _startAudio(
      locallyAccepted: true,
      configuration: effectiveConfiguration,
    );
    // Failed startup can close the engine and terminate its call during
    // cleanup. Preserve that call-bound failure diagnostic, but never report
    // a late success that could notify native audio readiness for a stale call.
    if (!isCurrentCall(snapshot.callId!) &&
        result.status == CallAudioStartStatus.started) {
      return;
    }
    _onStartResult?.call(result.status);
    switch (result.status) {
      case CallAudioStartStatus.started:
        return;
      case CallAudioStartStatus.permissionDenied:
      case CallAudioStartStatus.permissionFailed:
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.permissionDenied,
        );
      case CallAudioStartStatus.notLocallyAccepted:
      case CallAudioStartStatus.invalidConfiguration:
      case CallAudioStartStatus.mediaConflict:
      case CallAudioStartStatus.audioSessionFailed:
      case CallAudioStartStatus.engineFailed:
      case CallAudioStartStatus.closed:
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.mediaUnavailable,
        );
    }
  }
}
