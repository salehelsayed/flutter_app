import 'call_media.dart';

enum MediaSwitchResponse {
  accept,
  decline,
  busy,
  stale,
  superseded,
  unsupported,
}

enum MediaSwitchDescription { offer, answer }

enum MediaSwitchAbortReason {
  cancelled,
  timeout,
  permission,
  negotiation,
  transport,
  superseded,
}

enum MediaSwitchPhase {
  decision,
  negotiating,
  commit,
  acknowledgement,
  committed,
  aborted,
  declined,
  superseded,
}

enum MediaSwitchEffectKind {
  sendRequest,
  prompt,
  sendResponse,
  createOffer,
  createAnswer,
  sendCommit,
  sendAck,
  sendAbort,
  closeVideo,
  discardCapture,
  rollbackOffer,
  repairAudio,
  awaitAudioRepair,
  openVideo,
  replayRecorded,
  disableSwitching,
}

final class MediaSwitchRequest {
  const MediaSwitchRequest({
    required this.id,
    required this.baseRevision,
    required this.target,
    required this.requesterIsCaller,
    required this.createdAtMs,
    required this.deadlineMs,
    this.camera = CallCameraState.off,
  });
  final String id;
  final int baseRevision;
  final CallMediaKind target;
  final bool requesterIsCaller;

  /// Monotonic creation time and the authenticated wire deadline translated
  /// into the same clock. Translation must not extend the remaining wire budget.
  final int createdAtMs;
  final int deadlineMs;
  final CallCameraState camera;
}

/// A pure decision. The adapter owns execution and caches exact wire messages:
/// [MediaSwitchEffectKind.replayRecorded] reuses bytes/IDs, never new consent.
final class MediaSwitchEffect {
  const MediaSwitchEffect(
    this.kind, {
    required this.switchId,
    required this.baseRevision,
    required this.revision,
    required this.media,
    required this.deadlineMs,
    this.camera = CallCameraState.off,
    this.response,
    this.replayOf,
    this.abortReason,
  });
  final MediaSwitchEffectKind kind;
  final String switchId;
  final int baseRevision;
  final int revision;
  final CallMediaKind media;
  final int deadlineMs;
  final CallCameraState camera;
  final MediaSwitchResponse? response;
  final MediaSwitchEffectKind? replayOf;
  final MediaSwitchAbortReason? abortReason;
}

final class MediaSwitchDecision {
  MediaSwitchDecision(this.accepted, Iterable<MediaSwitchEffect> effects)
    : effects = List.unmodifiable(effects);
  final bool accepted;
  final List<MediaSwitchEffect> effects;
}

final class CallMediaSwitchMachine {
  CallMediaSwitchMachine({
    required this.localIsCaller,
    required this.wireVersion,
    required this.videoEnabled,
    required this.connected,
    required CallMediaKind settledMedia,
    int settledRevision = 0,
    required int Function() nowMs,
  }) : settledMedia = settledMedia,
       settledRevision = settledRevision,
       _nowMs = nowMs;
  final bool localIsCaller;
  final CallWireVersion wireVersion;
  final bool videoEnabled;
  final bool connected;
  final int Function() _nowMs;
  CallMediaKind settledMedia;
  int settledRevision;
  bool videoGatesOpen = false;
  bool switchingDisabled = false;
  bool terminal = false;
  bool requiresReconciliation = false;
  String? get currentSwitchId => null;
  String? get selectedSwitchId => null;
  MediaSwitchPhase? get phase => null;
  int? get stageDeadlineMs => null;
  MediaSwitchDecision request(
    MediaSwitchRequest request, {
    bool freshUpgradeAdmitted = false,
    bool negotiationBusy = false,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision respond({
    required String id,
    required int baseRevision,
    required bool fromCaller,
    required MediaSwitchResponse response,
    CallCameraState camera = CallCameraState.off,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision descriptionApplied({
    required String id,
    required int revision,
    required CallMediaKind media,
    required MediaSwitchDescription description,
    required bool local,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision receiveCommit({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision receiveAck({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision abort({
    required String id,
    required int baseRevision,
    required int revision,
    bool remote = false,
    MediaSwitchAbortReason reason = MediaSwitchAbortReason.cancelled,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision tick() {
    _nowMs();
    return MediaSwitchDecision(false, []);
  }

  MediaSwitchDecision terminate() => MediaSwitchDecision(false, []);
  MediaSwitchDecision rollbackCompleted({
    required String id,
    required bool success,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision repairCompleted({
    required String id,
    required bool success,
  }) => MediaSwitchDecision(false, []);
  MediaSwitchDecision reconnect() => MediaSwitchDecision(false, []);
  MediaSwitchDecision reconciliationCompleted({
    required String id,
    required bool delivered,
  }) => MediaSwitchDecision(false, []);
}
