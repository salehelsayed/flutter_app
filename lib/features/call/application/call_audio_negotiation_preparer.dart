import '../domain/call_engine.dart';
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
    CallStagedIceServerReader? readInitialIceServers,
    DateTime Function()? clock,
    this.requireTurnServer = false,
    CallAudioStartResultObserver? onStartResult,
  }) : _startAudio = startAudio,
       _readInitialIceServers = readInitialIceServers,
       _clock = clock ?? DateTime.now,
       _onStartResult = onStartResult;

  final StartCallAudio _startAudio;
  final CallStagedIceServerReader? _readInitialIceServers;
  final DateTime Function() _clock;
  final bool requireTurnServer;
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
    if (!accepted) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }

    final now = _clock().toUtc();
    var iceServers = configuration.iceServers
        .where((server) => server.expiresAt.isAfter(now))
        .toList(growable: true);
    final reader = _readInitialIceServers;
    if (reader != null) {
      try {
        final staged = await reader(snapshot.callId!);
        iceServers.addAll(
          staged.where((server) => server.expiresAt.isAfter(now)),
        );
      } catch (_) {
        if (requireTurnServer ||
            configuration.transportPolicy == CallTransportPolicy.relayOnly) {
          throw const CallNegotiationPortException(
            CallNegotiationPortErrorCode.iceServersUnavailable,
          );
        }
      }
    }
    final hasTurn = iceServers.any((server) => server.containsTurnUrl);
    if ((requireTurnServer ||
            configuration.transportPolicy == CallTransportPolicy.relayOnly) &&
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
