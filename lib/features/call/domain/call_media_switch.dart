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

final class _Transaction {
  _Transaction(
    this.request,
    this.deadline,
    this.stageDeadline,
    this.localCamera,
  );
  final MediaSwitchRequest request;
  final int deadline;
  int stageDeadline;
  CallCameraState localCamera;
  MediaSwitchPhase phase = MediaSwitchPhase.decision;
  bool selected = false;
  bool offerApplied = false;
  bool answerApplied = false;
  MediaSwitchDescription? pendingDescription;
  MediaSwitchEffect? lastResult;
  int get revision => request.baseRevision + 1;
  bool get open => switch (phase) {
    MediaSwitchPhase.decision ||
    MediaSwitchPhase.negotiating ||
    MediaSwitchPhase.commit ||
    MediaSwitchPhase.acknowledgement => true,
    _ => false,
  };
}

/// Pure per-call transaction state. Inputs have already passed authenticated
/// identity/schema checks. No effect may close the live audio transport.
final class CallMediaSwitchMachine {
  CallMediaSwitchMachine({
    required this.localIsCaller,
    required this.wireVersion,
    required this.videoEnabled,
    required this.connected,
    required CallMediaKind settledMedia,
    int settledRevision = 0,
    required int Function() nowMs,
  }) : _settledMedia = settledMedia,
       _settledRevision = settledRevision,
       _videoGatesOpen = settledMedia == CallMediaKind.video,
       _nowMs = nowMs;

  final bool localIsCaller;
  final CallWireVersion wireVersion;
  final bool videoEnabled;
  final bool connected;
  final int Function() _nowMs;
  final Map<String, _Transaction> _transactions = {};
  _Transaction? _current;
  _Transaction? _latestSelected;
  CallMediaKind _settledMedia;
  int _settledRevision;
  bool _videoGatesOpen;
  bool _switchingDisabled = false;
  bool _terminal = false;
  bool _requiresReconciliation = false;
  String? _repairId;
  int? _repairDeadline;
  bool _rollbackPending = false;
  String? _reconciliationId;
  int? _reconciliationDeadline;
  int _uncertainties = 0;

  CallMediaKind get settledMedia => _settledMedia;
  int get settledRevision => _settledRevision;
  bool get videoGatesOpen => _videoGatesOpen;
  bool get switchingDisabled => _switchingDisabled;
  bool get terminal => _terminal;
  bool get requiresReconciliation => _requiresReconciliation;
  String? get currentSwitchId => _current?.request.id;
  MediaSwitchRequest? get currentRequest => null;
  String? get selectedSwitchId => _latestSelected?.request.id;
  MediaSwitchPhase? get phase => _current?.phase;
  int? get stageDeadlineMs =>
      _current?.open == true ? _current?.stageDeadline : null;

  /// Nearest immutable stage, native-repair or terminal delivery deadline.
  int? get nextDeadlineMs {
    final deadlines = [
      stageDeadlineMs,
      _repairDeadline,
      _reconciliationDeadline,
    ].whereType<int>();
    return deadlines.isEmpty ? null : deadlines.reduce(_min);
  }

  bool get _available =>
      !_terminal &&
      !_switchingDisabled &&
      connected &&
      videoEnabled &&
      wireVersion == CallWireVersion.v2;
  int _min(int a, int b) => a < b ? a : b;

  MediaSwitchEffect _effect(
    _Transaction t,
    MediaSwitchEffectKind kind, {
    MediaSwitchResponse? response,
    MediaSwitchAbortReason? reason,
    MediaSwitchEffectKind? replayOf,
  }) => MediaSwitchEffect(
    kind,
    switchId: t.request.id,
    baseRevision: t.request.baseRevision,
    revision: t.selected ? t.revision : t.request.baseRevision,
    media: t.phase == MediaSwitchPhase.aborted
        ? CallMediaKind.audio
        : t.request.target,
    deadlineMs: switch (kind) {
      MediaSwitchEffectKind.sendAbort => _nowMs() + 30000,
      MediaSwitchEffectKind.repairAudio ||
      MediaSwitchEffectKind.awaitAudioRepair ||
      MediaSwitchEffectKind.rollbackOffer => _repairDeadline ?? t.deadline,
      _ => t.deadline,
    },
    camera: t.localCamera,
    response: response,
    abortReason: reason,
    replayOf: replayOf,
  );

  void _send(
    _Transaction t,
    MediaSwitchEffectKind kind,
    List<MediaSwitchEffect> out, {
    MediaSwitchResponse? response,
    MediaSwitchAbortReason? reason,
  }) {
    final effect = _effect(t, kind, response: response, reason: reason);
    t.lastResult = effect;
    out.add(effect);
  }

  void _replay(_Transaction t, List<MediaSwitchEffect> out) {
    final recorded = t.lastResult;
    if (recorded == null) return;
    if (recorded.kind == MediaSwitchEffectKind.sendAbort &&
        recorded.deadlineMs <= _nowMs()) {
      // A corrective abort gets a fresh bounded delivery envelope only. Its
      // tombstone, consent and repair budget are never renewed.
      _send(
        t,
        MediaSwitchEffectKind.sendAbort,
        out,
        reason: recorded.abortReason,
      );
      return;
    }
    out.add(
      MediaSwitchEffect(
        MediaSwitchEffectKind.replayRecorded,
        switchId: recorded.switchId,
        baseRevision: recorded.baseRevision,
        revision: recorded.revision,
        media: recorded.media,
        deadlineMs: recorded.deadlineMs,
        camera: recorded.camera,
        response: recorded.response,
        abortReason: recorded.abortReason,
        replayOf: recorded.kind,
      ),
    );
  }

  void _close(_Transaction t, List<MediaSwitchEffect> out) {
    _videoGatesOpen = false;
    t.localCamera = CallCameraState.off;
    out.add(_effect(t, MediaSwitchEffectKind.closeVideo));
  }

  void _retire(
    _Transaction t,
    MediaSwitchPhase phase,
    List<MediaSwitchEffect> out,
  ) {
    t.phase = phase;
    t.localCamera = CallCameraState.off;
    if (t.lastResult?.kind == MediaSwitchEffectKind.sendRequest) {
      t.lastResult = null;
    }
    out.add(_effect(t, MediaSwitchEffectKind.discardCapture));
  }

  void _select(_Transaction t, List<MediaSwitchEffect> out) {
    t.selected = true;
    t.phase = MediaSwitchPhase.negotiating;
    t.stageDeadline = _min(t.deadline, _nowMs() + 10000);
    _latestSelected = t;
    if (localIsCaller) out.add(_effect(t, MediaSwitchEffectKind.createOffer));
  }

  bool _sameRequest(MediaSwitchRequest a, MediaSwitchRequest b) =>
      a.id == b.id &&
      a.baseRevision == b.baseRevision &&
      a.target == b.target &&
      a.requesterIsCaller == b.requesterIsCaller &&
      a.createdAtMs == b.createdAtMs &&
      a.deadlineMs == b.deadlineMs &&
      a.camera == b.camera;

  MediaSwitchDecision request(
    MediaSwitchRequest request, {
    bool freshUpgradeAdmitted = false,
    bool negotiationBusy = false,
  }) {
    final out = _advance();
    if (_terminal) return MediaSwitchDecision(false, out);
    final local = request.requesterIsCaller == localIsCaller;
    final pending = _current;
    // A local stop does not wait for consent, glare or an uncertain result.
    if (local &&
        request.target == CallMediaKind.audio &&
        pending != null &&
        pending.open &&
        pending.request.target == CallMediaKind.video) {
      if (pending.selected) {
        _abort(pending, out, MediaSwitchAbortReason.cancelled);
      } else {
        _close(pending, out);
        _retire(pending, MediaSwitchPhase.declined, out);
      }
      return MediaSwitchDecision(true, out);
    }
    final known = _transactions[request.id];
    if (known != null) {
      if (_sameRequest(known.request, request)) _replay(known, out);
      return MediaSwitchDecision(false, out);
    }
    final now = _nowMs();
    final deadline = _min(request.deadlineMs, request.createdAtMs + 30000);
    final t = _Transaction(
      request,
      deadline,
      _min(deadline, request.createdAtMs + 15000),
      local ? request.camera : CallCameraState.off,
    );
    MediaSwitchDecision reject(MediaSwitchResponse response) {
      // A busy response is final for this request ID, not a deferred prompt.
      t.phase = MediaSwitchPhase.declined;
      t.localCamera = CallCameraState.off;
      if (request.id.isNotEmpty) _transactions[request.id] = t;
      if (!local) {
        _send(t, MediaSwitchEffectKind.sendResponse, out, response: response);
      }
      return MediaSwitchDecision(false, out);
    }

    if (local && request.target == CallMediaKind.audio) _close(t, out);
    if (!_available ||
        (request.target == CallMediaKind.video && !freshUpgradeAdmitted)) {
      return reject(MediaSwitchResponse.unsupported);
    }
    if (request.id.isEmpty ||
        request.baseRevision != _settledRevision ||
        request.target == _settledMedia ||
        request.createdAtMs > now ||
        t.stageDeadline <= now ||
        (request.target == CallMediaKind.audio &&
            request.camera != CallCameraState.off)) {
      return reject(MediaSwitchResponse.stale);
    }
    if (negotiationBusy || _repairId != null || _requiresReconciliation) {
      return reject(MediaSwitchResponse.busy);
    }
    if (pending != null && pending.open) {
      if (pending.selected ||
          pending.request.requesterIsCaller == request.requesterIsCaller) {
        return reject(MediaSwitchResponse.busy);
      }
      if (pending.request.requesterIsCaller) {
        t.phase = MediaSwitchPhase.superseded;
        _transactions[request.id] = t;
        if (!local) {
          _send(
            t,
            MediaSwitchEffectKind.sendResponse,
            out,
            response: MediaSwitchResponse.superseded,
          );
        }
        return MediaSwitchDecision(false, out);
      }
      // The caller's unselected request wins; abandoned local consent is lost.
      _retire(pending, MediaSwitchPhase.superseded, out);
    }
    _transactions[request.id] = t;
    _current = t;
    if (!local && request.target == CallMediaKind.audio) _close(t, out);
    if (local) {
      _send(t, MediaSwitchEffectKind.sendRequest, out);
    } else if (request.target == CallMediaKind.audio) {
      _send(
        t,
        MediaSwitchEffectKind.sendResponse,
        out,
        response: MediaSwitchResponse.accept,
      );
      _select(t, out);
    } else {
      out.add(_effect(t, MediaSwitchEffectKind.prompt));
    }
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision respond({
    required String id,
    required int baseRevision,
    required bool fromCaller,
    required MediaSwitchResponse response,
    CallCameraState camera = CallCameraState.off,
  }) {
    final out = _advance();
    final t = _current;
    if (_terminal ||
        t == null ||
        t.request.id != id ||
        t.request.baseRevision != baseRevision ||
        fromCaller == t.request.requesterIsCaller ||
        t.phase != MediaSwitchPhase.decision) {
      return MediaSwitchDecision(false, out);
    }
    if ((response != MediaSwitchResponse.accept ||
            t.request.target == CallMediaKind.audio) &&
        camera != CallCameraState.off) {
      return MediaSwitchDecision(false, out);
    }
    if (fromCaller == localIsCaller) {
      t.localCamera = response == MediaSwitchResponse.accept
          ? camera
          : CallCameraState.off;
      _send(t, MediaSwitchEffectKind.sendResponse, out, response: response);
    }
    if (response != MediaSwitchResponse.accept) {
      _retire(t, MediaSwitchPhase.declined, out);
    } else {
      _select(t, out);
    }
    return MediaSwitchDecision(true, out);
  }

  bool _bound(_Transaction? t, String id, int revision, CallMediaKind media) =>
      t != null &&
      identical(t, _latestSelected) &&
      t.selected &&
      t.request.id == id &&
      t.revision == revision &&
      t.request.target == media;

  /// Records an admitted native apply before awaiting it. This is pending
  /// work, never evidence that an offer or answer was applied successfully.
  MediaSwitchDecision descriptionStarted({
    required String id,
    required int revision,
    required CallMediaKind media,
    required MediaSwitchDescription description,
    required bool local,
  }) {
    final out = _advance();
    final t = _current;
    if (_terminal ||
        !_bound(t, id, revision, media) ||
        t!.phase != MediaSwitchPhase.negotiating ||
        t.pendingDescription != null ||
        local !=
            (description == MediaSwitchDescription.offer
                ? localIsCaller
                : !localIsCaller) ||
        (description == MediaSwitchDescription.offer
            ? t.offerApplied
            : (!t.offerApplied || t.answerApplied))) {
      return MediaSwitchDecision(false, out);
    }
    t.pendingDescription = description;
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision descriptionApplied({
    required String id,
    required int revision,
    required CallMediaKind media,
    required MediaSwitchDescription description,
    required bool local,
  }) {
    final out = _advance();
    final t = _current;
    if (!_terminal &&
        _bound(t, id, revision, media) &&
        t!.answerApplied &&
        t.phase != MediaSwitchPhase.aborted) {
      if (description == MediaSwitchDescription.answer &&
          !local &&
          localIsCaller) {
        _replay(t, out);
      } else if (description == MediaSwitchDescription.offer &&
          !local &&
          !localIsCaller) {
        out.add(
          _effect(
            t,
            MediaSwitchEffectKind.replayRecorded,
            replayOf: MediaSwitchEffectKind.createAnswer,
          ),
        );
      }
      return MediaSwitchDecision(false, out);
    }
    if (_terminal ||
        !_bound(t, id, revision, media) ||
        t!.phase != MediaSwitchPhase.negotiating ||
        local !=
            (description == MediaSwitchDescription.offer
                ? localIsCaller
                : !localIsCaller)) {
      return MediaSwitchDecision(false, out);
    }
    if (description == MediaSwitchDescription.offer) {
      if (t.offerApplied) return MediaSwitchDecision(false, out);
      t.pendingDescription = null;
      t.offerApplied = true;
      if (!localIsCaller) {
        out.add(_effect(t, MediaSwitchEffectKind.createAnswer));
      }
    } else {
      if (!t.offerApplied || t.answerApplied) {
        return MediaSwitchDecision(false, out);
      }
      t.pendingDescription = null;
      t.answerApplied = true;
      t.phase = localIsCaller
          ? MediaSwitchPhase.acknowledgement
          : MediaSwitchPhase.commit;
      t.stageDeadline = _min(t.deadline, _nowMs() + 5000);
      if (localIsCaller) _send(t, MediaSwitchEffectKind.sendCommit, out);
    }
    return MediaSwitchDecision(true, out);
  }

  void _settle(_Transaction t, List<MediaSwitchEffect> out) {
    t.phase = MediaSwitchPhase.committed;
    _settledRevision = t.revision;
    _settledMedia = t.request.target;
    _requiresReconciliation = false;
    _reconciliationId = null;
    _reconciliationDeadline = null;
    if (_settledMedia == CallMediaKind.video) {
      _videoGatesOpen = true;
      out.add(_effect(t, MediaSwitchEffectKind.openVideo));
    } else {
      _close(t, out);
    }
  }

  MediaSwitchDecision receiveCommit({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) {
    final out = _advance();
    final t = _current;
    if (_terminal ||
        localIsCaller ||
        !_bound(t, id, revision, media) ||
        !t!.answerApplied) {
      return MediaSwitchDecision(false, out);
    }
    if (t.phase == MediaSwitchPhase.committed) {
      _replay(t, out);
      return MediaSwitchDecision(false, out);
    }
    if (t.phase != MediaSwitchPhase.commit) {
      return MediaSwitchDecision(false, out);
    }
    _send(t, MediaSwitchEffectKind.sendAck, out);
    _settle(t, out);
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision receiveAck({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) {
    final out = _advance();
    final t = _current;
    if (_terminal ||
        !localIsCaller ||
        !_bound(t, id, revision, media) ||
        t!.phase != MediaSwitchPhase.acknowledgement ||
        !t.answerApplied) {
      return MediaSwitchDecision(false, out);
    }
    _settle(t, out);
    return MediaSwitchDecision(true, out);
  }

  void _abort(
    _Transaction t,
    List<MediaSwitchEffect> out,
    MediaSwitchAbortReason reason,
  ) {
    if (t.phase == MediaSwitchPhase.aborted) return;
    final pending = _current;
    if (pending != null && !identical(pending, t) && pending.open) {
      _retire(pending, MediaSwitchPhase.superseded, out);
    }
    _current = t;
    t.phase = MediaSwitchPhase.aborted;
    _settledRevision = t.revision;
    _settledMedia = CallMediaKind.audio;
    _close(t, out);
    out.add(_effect(t, MediaSwitchEffectKind.discardCapture));
    _send(t, MediaSwitchEffectKind.sendAbort, out, reason: reason);
    _requiresReconciliation = true;
    // The connected send path can complete without a reconnect event. Arm its
    // exact result now, independently of the fixed native repair budget.
    _reconciliationId = t.request.id;
    _reconciliationDeadline = t.lastResult!.deadlineMs;
    if (t.answerApplied || t.offerApplied || t.pendingDescription != null) {
      _repairId = t.request.id;
      _repairDeadline = _nowMs() + 15000;
      _rollbackPending = !t.answerApplied || t.pendingDescription != null;
      if (!_rollbackPending) {
        out.add(
          _effect(
            t,
            localIsCaller
                ? MediaSwitchEffectKind.repairAudio
                : MediaSwitchEffectKind.awaitAudioRepair,
          ),
        );
      } else {
        out.add(_effect(t, MediaSwitchEffectKind.rollbackOffer));
      }
    }
  }

  MediaSwitchDecision abort({
    required String id,
    required int baseRevision,
    required int revision,
    bool remote = false,
    MediaSwitchAbortReason reason = MediaSwitchAbortReason.cancelled,
  }) {
    final out = _advance();
    if (_terminal) return MediaSwitchDecision(false, out);
    final t = _transactions[id];
    if (t == null ||
        t.request.baseRevision != baseRevision ||
        t.revision != revision) {
      return MediaSwitchDecision(false, out);
    }
    if (!t.selected) {
      if (remote || !t.open || !identical(t, _current)) {
        return MediaSwitchDecision(false, out);
      }
      _retire(t, MediaSwitchPhase.declined, out);
      return MediaSwitchDecision(true, out);
    }
    if (!identical(t, _latestSelected) || t.phase == MediaSwitchPhase.aborted) {
      return MediaSwitchDecision(false, out);
    }
    _abort(t, out, reason);
    return MediaSwitchDecision(true, out);
  }

  void _disable(_Transaction t, List<MediaSwitchEffect> out) {
    if (_switchingDisabled) return;
    _switchingDisabled = true;
    if (t.selected && t.phase != MediaSwitchPhase.aborted) {
      _abort(t, out, MediaSwitchAbortReason.transport);
    }
    _close(t, out);
    out.add(_effect(t, MediaSwitchEffectKind.disableSwitching));
  }

  List<MediaSwitchEffect> _advance() {
    final out = <MediaSwitchEffect>[];
    if (_terminal) return out;
    final now = _nowMs();
    final t = _current;
    if (t != null && t.open && now >= t.stageDeadline) {
      if (t.selected) {
        _abort(t, out, MediaSwitchAbortReason.timeout);
      } else {
        _retire(t, MediaSwitchPhase.declined, out);
      }
    }
    if (_repairId != null && now >= _repairDeadline!) {
      final repair = _transactions[_repairId]!;
      _repairId = null;
      _repairDeadline = null;
      _disable(repair, out);
    }
    if (_reconciliationId != null && now >= _reconciliationDeadline!) {
      final result = _transactions[_reconciliationId]!;
      _reconciliationId = null;
      _reconciliationDeadline = null;
      _uncertainties++;
      if (_uncertainties >= 2) _disable(result, out);
    }
    return out;
  }

  MediaSwitchDecision tick() => MediaSwitchDecision(false, _advance());

  /// Native pending-offer reconciliation completes before any repair offer.
  /// The fixed abort-time budget includes this wait; callbacks never renew it.
  MediaSwitchDecision rollbackCompleted({
    required String id,
    required bool success,
  }) {
    final out = _advance();
    if (_terminal ||
        _repairId != id ||
        !_rollbackPending ||
        _latestSelected?.request.id != id) {
      return MediaSwitchDecision(false, out);
    }
    _rollbackPending = false;
    final t = _transactions[id]!;
    if (!success) {
      _repairId = null;
      _repairDeadline = null;
      _disable(t, out);
    } else {
      out.add(
        _effect(
          t,
          localIsCaller
              ? MediaSwitchEffectKind.repairAudio
              : MediaSwitchEffectKind.awaitAudioRepair,
        ),
      );
    }
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision repairCompleted({
    required String id,
    required bool success,
  }) {
    final out = _advance();
    if (_terminal ||
        _repairId != id ||
        _rollbackPending ||
        _latestSelected?.request.id != id) {
      return MediaSwitchDecision(false, out);
    }
    _repairId = null;
    _repairDeadline = null;
    if (!success) _disable(_transactions[id]!, out);
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision reconnect() {
    final out = _advance();
    final t = _latestSelected;
    if (_terminal || t == null || t.lastResult == null) {
      return MediaSwitchDecision(false, out);
    }
    _replay(t, out);
    if (!t.open) {
      _requiresReconciliation = true;
      if (_reconciliationId == null) {
        _reconciliationId = t.request.id;
        _reconciliationDeadline = _nowMs() + 30000;
      }
    }
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision reconciliationCompleted({
    required String id,
    required bool delivered,
  }) {
    final out = _advance();
    if (_terminal ||
        _reconciliationId != id ||
        _latestSelected?.request.id != id) {
      return MediaSwitchDecision(false, out);
    }
    _reconciliationId = null;
    _reconciliationDeadline = null;
    if (delivered) {
      _requiresReconciliation = false;
      _uncertainties = 0;
    } else {
      _uncertainties++;
      if (_uncertainties >= 2) _disable(_transactions[id]!, out);
    }
    return MediaSwitchDecision(true, out);
  }

  MediaSwitchDecision terminate() {
    final out = <MediaSwitchEffect>[];
    if (_terminal) return MediaSwitchDecision(false, out);
    _terminal = true;
    _videoGatesOpen = false;
    _repairId = null;
    _repairDeadline = null;
    _reconciliationId = null;
    _reconciliationDeadline = null;
    final t = _current;
    if (t != null) {
      _close(t, out);
      _retire(t, MediaSwitchPhase.aborted, out);
    }
    return MediaSwitchDecision(true, out);
  }
}
