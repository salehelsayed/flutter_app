import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';

import 'media_playback_adapter.dart';
import 'media_video_resume_controller.dart';
import 'media_viewer_item.dart';

enum MediaPictureInPicturePolicyState {
  ordinary,
  protected,
  viewOnce,
  expired,
  quarantined,
  unsupported,
  terminal,
}

@immutable
class MediaPictureInPictureAuthorization {
  const MediaPictureInPictureAuthorization({
    required this.item,
    required this.generation,
    required this.policyState,
    required this.isIncoming,
    required this.isTransferComplete,
    required this.routeActive,
  });

  final MediaViewerItem item;
  final int generation;
  final MediaPictureInPicturePolicyState policyState;
  final bool isIncoming;
  final bool isTransferComplete;
  final bool routeActive;
}

enum MediaPictureInPictureDenial {
  allowed,
  untrustedOwner,
  notIncoming,
  nonVideo,
  transferIncomplete,
  unavailable,
  protected,
  laneDenied,
  missingPath,
  routeInactive,
  invalidGeneration,
}

@immutable
class MediaPictureInPicturePolicyDecision {
  const MediaPictureInPicturePolicyDecision(this.denial);

  final MediaPictureInPictureDenial denial;

  bool get isAllowed => denial == MediaPictureInPictureDenial.allowed;
}

abstract final class MediaPictureInPicturePolicy {
  static MediaPictureInPicturePolicyDecision evaluate(
    MediaPictureInPictureAuthorization authorization,
  ) {
    final item = authorization.item;
    if (authorization.generation < 0) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.invalidGeneration,
      );
    }
    if (!authorization.routeActive) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.routeInactive,
      );
    }
    if (!authorization.isIncoming) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.notIncoming,
      );
    }
    if (!item.hasOwner) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.untrustedOwner,
      );
    }
    if (!item.isVideo) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.nonVideo,
      );
    }
    if (!authorization.isTransferComplete) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.transferIncomplete,
      );
    }
    if (!item.protection.isDownloaded || !item.protection.isIntegrityVerified) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.unavailable,
      );
    }
    if (item.protection.isProtected ||
        authorization.policyState !=
            MediaPictureInPicturePolicyState.ordinary) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.protected,
      );
    }
    if (!item.canEnterPictureInPicture) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.laneDenied,
      );
    }
    if (item.localPath == null || item.localPath!.trim().isEmpty) {
      return const MediaPictureInPicturePolicyDecision(
        MediaPictureInPictureDenial.missingPath,
      );
    }
    return const MediaPictureInPicturePolicyDecision(
      MediaPictureInPictureDenial.allowed,
    );
  }
}

typedef MediaPictureInPictureCurrentAuthorizer =
    Future<MediaPictureInPictureAuthorization?> Function();
typedef MediaPictureInPictureRestorePlayback =
    Future<void> Function(MediaPictureInPictureRestore restore);
typedef MediaPictureInPictureSessionIdFactory = String Function();

@immutable
class MediaPictureInPictureRestore {
  const MediaPictureInPictureRestore({
    required this.item,
    required this.positionMs,
    required this.shouldPlay,
  });

  final MediaViewerItem item;
  final int positionMs;
  final bool shouldPlay;
}

enum MediaPictureInPictureStartOutcome {
  started,
  hidden,
  denied,
  alreadyActive,
  nativeRejected,
}

class MediaPictureInPictureController {
  MediaPictureInPictureController({
    required PictureInPictureGateway gateway,
    required AppOwnedMediaPathAuthority pathAuthority,
    required MediaPictureInPictureCurrentAuthorizer reloadCurrent,
    required MediaViewerResumeStore resumeStore,
    required MediaPictureInPictureRestorePlayback restorePlayback,
    Stream<void> authorizationChanges = const Stream<void>.empty(),
    Stream<void>? pollTicks,
    MediaPictureInPictureSessionIdFactory? sessionIdFactory,
  }) : _gateway = gateway,
       _pathAuthority = pathAuthority,
       _reloadCurrent = reloadCurrent,
       _resumeStore = resumeStore,
       _restorePlayback = restorePlayback,
       _sessionIdFactory = sessionIdFactory ?? _newOpaqueSessionId {
    _gatewaySubscription = _gateway.events.listen(
      _scheduleGatewayEvent,
      onError: (_, _) => _scheduleAuthorizationLoss(),
      onDone: _scheduleAuthorizationLoss,
      cancelOnError: false,
    );
    _authorizationSubscription = authorizationChanges.listen(
      (_) => _scheduleAuthorizationCheck(),
      onError: (_, _) => _scheduleAuthorizationLoss(),
      onDone: () {},
      cancelOnError: false,
    );
    final ticks =
        pollTicks ??
        Stream<void>.periodic(const Duration(milliseconds: 250), (_) {});
    _pollSubscription = ticks.listen(
      (_) => _scheduleAuthorizationCheck(),
      onError: (_, _) => _scheduleAuthorizationLoss(),
      cancelOnError: false,
    );
  }

  final PictureInPictureGateway _gateway;
  final AppOwnedMediaPathAuthority _pathAuthority;
  final MediaPictureInPictureCurrentAuthorizer _reloadCurrent;
  final MediaViewerResumeStore _resumeStore;
  final MediaPictureInPictureRestorePlayback _restorePlayback;
  final MediaPictureInPictureSessionIdFactory _sessionIdFactory;
  StreamSubscription<PictureInPictureEvent>? _gatewaySubscription;
  StreamSubscription<void>? _authorizationSubscription;
  StreamSubscription<void>? _pollSubscription;
  Future<void> _operationTail = Future<void>.value();
  Future<void> _authorizationCheckFuture = Future<void>.value();
  final Set<Future<void>> _priorityStops = <Future<void>>{};
  PictureInPictureEvent? _pendingCheckpoint;
  bool _checkpointFlushScheduled = false;
  bool _authorizationCheckRunning = false;
  bool _authorizationCheckPending = false;
  int _authorizationEpoch = 0;
  int _authorizationLossEpoch = 0;
  _MediaPictureInPictureSession? _session;
  bool _disposing = false;
  bool _disposed = false;

  /// Reads platform support without authorizing media or touching playback.
  /// The viewer uses this to keep the control absent on iOS/other platforms
  /// and unsupported Android devices before any current-row/path handoff.
  Future<PictureInPictureCapability> capability() async {
    if (_disposing || _disposed) {
      return const PictureInPictureCapability.channelFailure();
    }
    try {
      return await _gateway.capability();
    } catch (_) {
      return const PictureInPictureCapability.channelFailure();
    }
  }

  Future<MediaPictureInPictureStartOutcome> start({
    required MediaPictureInPictureAuthorization authorization,
    required MediaPlaybackAdapter playback,
  }) => _serialize(
    () => _start(authorization: authorization, playback: playback),
  );

  Future<MediaPictureInPictureStartOutcome> _start({
    required MediaPictureInPictureAuthorization authorization,
    required MediaPlaybackAdapter playback,
  }) async {
    if (_disposing || _disposed) {
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }
    if (_session != null) {
      return MediaPictureInPictureStartOutcome.alreadyActive;
    }
    if (!MediaPictureInPicturePolicy.evaluate(authorization).isAllowed) {
      return MediaPictureInPictureStartOutcome.denied;
    }
    final handoffLossEpoch = _authorizationLossEpoch;
    var handoffEpoch = _authorizationEpoch;

    var current = await _reloadCurrentFailClosed();
    if (!_sameAuthorizedIdentity(authorization, current)) {
      return MediaPictureInPictureStartOutcome.denied;
    }
    final initialPath = await _authorizePathFailClosed(
      authorization.item.localPath,
    );
    final currentPath = await _authorizePathFailClosed(current!.item.localPath);
    if (initialPath == null ||
        currentPath == null ||
        initialPath != currentPath) {
      return MediaPictureInPictureStartOutcome.denied;
    }

    PictureInPictureCapability capability;
    try {
      capability = await _gateway.capability();
    } catch (_) {
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }
    if (!capability.isVisible) {
      return MediaPictureInPictureStartOutcome.hidden;
    }
    if (!capability.isSupported) {
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }

    var handoffFence = await _reauthorizeHandoffIfChanged(
      expected: authorization,
      current: current,
      canonicalPath: currentPath,
      observedEpoch: handoffEpoch,
      observedLossEpoch: handoffLossEpoch,
    );
    if (!_handoffFenceIsCurrent(handoffFence, handoffLossEpoch)) {
      return _disposing || _disposed
          ? MediaPictureInPictureStartOutcome.nativeRejected
          : MediaPictureInPictureStartOutcome.denied;
    }
    current = handoffFence!.authorization;
    handoffEpoch = handoffFence.epoch;

    final adapterDurationMs = playback.duration.inMilliseconds;
    final knownDurationMs =
        current.item.durationMs ??
        (adapterDurationMs > 0 ? adapterDurationMs : null);
    final positionMs = _normalizePosition(
      playback.position.inMilliseconds,
      knownDurationMs,
    );
    final wasPlaying = playback.isPlaying;
    final sessionId = _sessionIdFactory();
    if (sessionId.trim().isEmpty) {
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }

    await _resumeStore.writeResumePosition(current.item, positionMs);
    handoffFence = await _reauthorizeHandoffIfChanged(
      expected: authorization,
      current: current,
      canonicalPath: currentPath,
      observedEpoch: handoffEpoch,
      observedLossEpoch: handoffLossEpoch,
      forceReload: true,
    );
    if (!_handoffFenceIsCurrent(handoffFence, handoffLossEpoch)) {
      return _disposing || _disposed
          ? MediaPictureInPictureStartOutcome.nativeRejected
          : MediaPictureInPictureStartOutcome.denied;
    }
    current = handoffFence!.authorization;
    handoffEpoch = handoffFence.epoch;
    try {
      await playback.pause();
      await playback.dispose();
    } catch (_) {
      await _restoreIfCurrent(
        authorization: current,
        canonicalPath: currentPath,
        positionMs: positionMs,
        shouldPlay: wasPlaying,
      );
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }

    handoffFence = await _reauthorizeHandoffIfChanged(
      expected: authorization,
      current: current,
      canonicalPath: currentPath,
      observedEpoch: handoffEpoch,
      observedLossEpoch: handoffLossEpoch,
      forceReload: true,
    );
    if (!_handoffFenceIsCurrent(handoffFence, handoffLossEpoch)) {
      final outcome = _disposing || _disposed
          ? MediaPictureInPictureStartOutcome.nativeRejected
          : MediaPictureInPictureStartOutcome.denied;
      if (!_disposing && !_disposed) {
        await _restoreIfCurrent(
          authorization: current,
          canonicalPath: currentPath,
          positionMs: positionMs,
          shouldPlay: wasPlaying,
        );
      }
      return outcome;
    }
    current = handoffFence!.authorization;

    final session = _MediaPictureInPictureSession(
      id: sessionId,
      attachment: current.item.attachmentId,
      generation: current.generation,
      canonicalPath: currentPath,
      item: current.item,
      wasPlaying: wasPlaying,
      handoffPositionMs: positionMs,
      knownDurationMs: knownDurationMs,
    );
    _session = session;
    PictureInPictureStartOutcome nativeOutcome;
    try {
      nativeOutcome = await _gateway.start(
        PictureInPictureRequest(
          session: session.id,
          attachment: session.attachment,
          path: session.canonicalPath,
          positionMs: positionMs,
          durationMs: session.knownDurationMs,
        ),
      );
    } catch (_) {
      nativeOutcome = PictureInPictureStartOutcome.platformFailure;
    }
    if (!_sessionCanContinue(session)) {
      return MediaPictureInPictureStartOutcome.nativeRejected;
    }
    if (nativeOutcome == PictureInPictureStartOutcome.started) {
      return MediaPictureInPictureStartOutcome.started;
    }
    if (identical(_session, session)) _session = null;
    await _restoreIfCurrent(
      authorization: current,
      canonicalPath: currentPath,
      positionMs: positionMs,
      shouldPlay: wasPlaying,
    );
    return nativeOutcome == PictureInPictureStartOutcome.hidden ||
            nativeOutcome == PictureInPictureStartOutcome.unsupportedPlatform
        ? MediaPictureInPictureStartOutcome.hidden
        : MediaPictureInPictureStartOutcome.nativeRejected;
  }

  void _scheduleGatewayEvent(PictureInPictureEvent event) {
    if (event.state == PictureInPictureState.checkpoint) {
      _enqueueCheckpoint(event);
      return;
    }
    _serialize(() => _handleGatewayEvent(event));
  }

  void _enqueueCheckpoint(PictureInPictureEvent event) {
    final session = _session;
    if (_disposing ||
        _disposed ||
        session == null ||
        session.stopIssued ||
        session.terminalDelivered ||
        event.session != session.id ||
        event.attachment != session.attachment) {
      return;
    }
    _pendingCheckpoint = event;
    _scheduleCheckpointFlush();
  }

  void _scheduleCheckpointFlush() {
    if (_checkpointFlushScheduled || _pendingCheckpoint == null) return;
    _checkpointFlushScheduled = true;
    _serialize(() async {
      try {
        final checkpoint = _pendingCheckpoint;
        _pendingCheckpoint = null;
        if (checkpoint != null) await _handleGatewayEvent(checkpoint);
      } finally {
        _checkpointFlushScheduled = false;
        if (!_disposing && !_disposed && _pendingCheckpoint != null) {
          _scheduleCheckpointFlush();
        }
      }
    });
  }

  Future<void> _handleGatewayEvent(PictureInPictureEvent event) async {
    final session = _session;
    if (session == null ||
        session.stopIssued ||
        session.terminalDelivered ||
        event.session != session.id ||
        event.attachment != session.attachment) {
      return;
    }
    switch (event.state) {
      case PictureInPictureState.nativeReady:
        final current = await _reloadAuthorized(session);
        if (current == null) {
          await _stopForAuthorizationLoss(session);
          return;
        }
        if (!_sessionCanContinue(session)) return;
        PictureInPictureCommandResult activated;
        try {
          activated = await _gateway.activate(session.id, session.attachment);
        } catch (_) {
          activated = const PictureInPictureCommandResult.rejected(
            PictureInPictureFailureReason.channelFailure,
          );
        }
        if (!activated.accepted) {
          await _settleActivationFailure(session, current);
        }
      case PictureInPictureState.active:
        return;
      case PictureInPictureState.checkpoint:
        final current = await _reloadAuthorized(session);
        if (current == null) {
          await _stopForAuthorizationLoss(session);
          return;
        }
        if (!_sessionCanContinue(session)) return;
        session.knownDurationMs =
            event.durationMs ??
            current.item.durationMs ??
            session.knownDurationMs;
        final positionMs = _normalizePosition(
          event.positionMs,
          session.knownDurationMs,
        );
        await _resumeStore.writeResumePosition(current.item, positionMs);
      case PictureInPictureState.restoring ||
          PictureInPictureState.stopped ||
          PictureInPictureState.completed ||
          PictureInPictureState.failed:
        await _settleTerminal(session, event);
    }
  }

  Future<void> _settleTerminal(
    _MediaPictureInPictureSession session,
    PictureInPictureEvent event,
  ) async {
    if (!identical(_session, session) || session.terminalDelivered) return;
    session.terminalDelivered = true;
    _pendingCheckpoint = null;
    final current = await _reloadAuthorized(session);
    _session = null;
    if (current == null) return;
    session.knownDurationMs =
        event.durationMs ?? current.item.durationMs ?? session.knownDurationMs;
    final positionMs = event.state == PictureInPictureState.completed
        ? 0
        : _normalizePosition(event.positionMs, session.knownDurationMs);
    await _resumeStore.writeResumePosition(current.item, positionMs);

    final shouldRestore =
        event.state == PictureInPictureState.restoring ||
        (event.state == PictureInPictureState.stopped &&
            event.reason == PictureInPictureTerminalReason.systemClose);
    if (!shouldRestore) return;
    await _restorePlayback(
      MediaPictureInPictureRestore(
        item: current.item,
        positionMs: positionMs,
        shouldPlay:
            event.state == PictureInPictureState.restoring &&
            session.wasPlaying,
      ),
    );
  }

  Future<void> _settleActivationFailure(
    _MediaPictureInPictureSession session,
    MediaPictureInPictureAuthorization current,
  ) async {
    if (!identical(_session, session) || session.terminalDelivered) return;
    session.terminalDelivered = true;
    _pendingCheckpoint = null;
    _session = null;
    await _restorePlayback(
      MediaPictureInPictureRestore(
        item: current.item,
        positionMs: session.handoffPositionMs,
        shouldPlay: session.wasPlaying,
      ),
    );
  }

  Future<void> _reauthorizeActive() async {
    final session = _session;
    if (session == null || session.stopIssued || session.terminalDelivered) {
      return;
    }
    if (await _reloadAuthorized(session) == null) {
      await _stopForAuthorizationLoss(session);
    }
  }

  bool _sessionCanContinue(_MediaPictureInPictureSession session) =>
      identical(_session, session) &&
      !session.stopIssued &&
      !session.terminalDelivered;

  Future<_MediaPictureInPictureHandoffFence?> _reauthorizeHandoffIfChanged({
    required MediaPictureInPictureAuthorization expected,
    required MediaPictureInPictureAuthorization current,
    required String canonicalPath,
    required int observedEpoch,
    required int observedLossEpoch,
    bool forceReload = false,
  }) async {
    if (_disposing ||
        _disposed ||
        observedLossEpoch != _authorizationLossEpoch) {
      return null;
    }
    if (!forceReload && observedEpoch == _authorizationEpoch) {
      return _MediaPictureInPictureHandoffFence(
        authorization: current,
        epoch: observedEpoch,
      );
    }

    final reloadEpoch = _authorizationEpoch;
    final reloaded = await _reloadCurrentFailClosed();
    if (!_sameAuthorizedIdentity(expected, reloaded)) return null;
    final reloadedPath = await _authorizePathFailClosed(
      reloaded!.item.localPath,
    );
    if (_disposing ||
        _disposed ||
        observedLossEpoch != _authorizationLossEpoch ||
        reloadEpoch != _authorizationEpoch ||
        reloadedPath != canonicalPath) {
      return null;
    }
    return _MediaPictureInPictureHandoffFence(
      authorization: reloaded,
      epoch: reloadEpoch,
    );
  }

  bool _handoffFenceIsCurrent(
    _MediaPictureInPictureHandoffFence? fence,
    int observedLossEpoch,
  ) =>
      fence != null &&
      !_disposing &&
      !_disposed &&
      observedLossEpoch == _authorizationLossEpoch &&
      fence.epoch == _authorizationEpoch;

  void _scheduleAuthorizationCheck() {
    if (_disposing || _disposed) return;
    _authorizationEpoch++;
    _authorizationCheckPending = true;
    if (_authorizationCheckRunning) return;
    _authorizationCheckRunning = true;
    _authorizationCheckFuture = _runAuthorizationChecks();
  }

  Future<void> _runAuthorizationChecks() async {
    try {
      while (_authorizationCheckPending && !_disposing && !_disposed) {
        _authorizationCheckPending = false;
        await _reauthorizeActive();
      }
    } finally {
      _authorizationCheckRunning = false;
      if (_authorizationCheckPending && !_disposing && !_disposed) {
        _scheduleAuthorizationCheck();
      }
    }
  }

  void _scheduleAuthorizationLoss() {
    if (_disposed) return;
    _authorizationEpoch++;
    _authorizationLossEpoch++;
    final stop = _authorizationLost();
    _priorityStops.add(stop);
    unawaited(
      stop.whenComplete(() {
        _priorityStops.remove(stop);
      }),
    );
  }

  Future<void> _authorizationLost() async {
    final session = _session;
    if (session != null) await _stopForAuthorizationLoss(session);
  }

  Future<void> _stopForAuthorizationLoss(
    _MediaPictureInPictureSession session,
  ) async {
    if (!identical(_session, session) ||
        session.terminalDelivered ||
        session.stopIssued) {
      return;
    }
    session.stopIssued = true;
    _pendingCheckpoint = null;
    try {
      await _gateway.stop(session.id, session.attachment);
    } catch (_) {
      // Dart authority is already revoked; native failure cannot restore it.
    }
    session.terminalDelivered = true;
    if (identical(_session, session)) _session = null;
  }

  Future<MediaPictureInPictureAuthorization?> _reloadAuthorized(
    _MediaPictureInPictureSession session,
  ) async {
    final current = await _reloadCurrentFailClosed();
    if (current == null ||
        current.generation != session.generation ||
        current.item.attachmentId != session.attachment ||
        current.item.messageId != session.item.messageId ||
        current.item.owner != session.item.owner ||
        !MediaPictureInPicturePolicy.evaluate(current).isAllowed) {
      return null;
    }
    final currentPath = await _authorizePathFailClosed(current.item.localPath);
    if (currentPath != session.canonicalPath) return null;
    return current;
  }

  Future<void> _restoreIfCurrent({
    required MediaPictureInPictureAuthorization authorization,
    required String canonicalPath,
    required int positionMs,
    required bool shouldPlay,
  }) async {
    final current = await _reloadCurrentFailClosed();
    if (!_sameAuthorizedIdentity(authorization, current)) return;
    final currentPath = await _authorizePathFailClosed(current!.item.localPath);
    if (currentPath != canonicalPath) return;
    await _restorePlayback(
      MediaPictureInPictureRestore(
        item: current.item,
        positionMs: positionMs,
        shouldPlay: shouldPlay,
      ),
    );
  }

  bool _sameAuthorizedIdentity(
    MediaPictureInPictureAuthorization expected,
    MediaPictureInPictureAuthorization? current,
  ) =>
      current != null &&
      current.generation == expected.generation &&
      current.item.attachmentId == expected.item.attachmentId &&
      current.item.messageId == expected.item.messageId &&
      current.item.owner == expected.item.owner &&
      MediaPictureInPicturePolicy.evaluate(current).isAllowed;

  Future<MediaPictureInPictureAuthorization?> _reloadCurrentFailClosed() async {
    try {
      return await _reloadCurrent();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _authorizePathFailClosed(String? candidatePath) async {
    try {
      return await _pathAuthority.authorize(candidatePath);
    } catch (_) {
      return null;
    }
  }

  int _normalizePosition(int positionMs, int? durationMs) {
    if (positionMs < 0) return 0;
    if (durationMs != null && durationMs > 0 && positionMs > durationMs) {
      return durationMs;
    }
    return positionMs;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> drain() async {
    while (true) {
      final observedOperations = _operationTail;
      final observedAuthorization = _authorizationCheckFuture;
      final observedStops = List<Future<void>>.of(_priorityStops);
      await Future.wait(<Future<void>>[
        observedOperations,
        observedAuthorization,
        ...observedStops,
      ]);
      // Awaiting the observed futures has already yielded to their completion
      // callbacks. Re-check their identities and the scheduler flags directly:
      // an extra timer or microtask here would deadlock callers in a FakeAsync
      // zone when they await [drain] without pumping a frame.
      if (identical(observedOperations, _operationTail) &&
          identical(observedAuthorization, _authorizationCheckFuture) &&
          _priorityStops.isEmpty &&
          !_checkpointFlushScheduled &&
          _pendingCheckpoint == null &&
          !_authorizationCheckRunning &&
          !_authorizationCheckPending) {
        return;
      }
    }
  }

  Future<void> dispose() async {
    if (_disposing || _disposed) return;
    _disposing = true;
    _pendingCheckpoint = null;
    final session = _session;
    final priorityStop = session == null
        ? Future<void>.value()
        : _stopForAuthorizationLoss(session);
    final operationBarrier = _serialize(() async {});
    await _gatewaySubscription?.cancel();
    await _authorizationSubscription?.cancel();
    await _pollSubscription?.cancel();
    await Future.wait(<Future<void>>[
      operationBarrier,
      priorityStop,
      _authorizationCheckFuture,
      ...List<Future<void>>.of(_priorityStops),
    ]);
    await _gateway.dispose();
    _disposed = true;
  }
}

class _MediaPictureInPictureHandoffFence {
  const _MediaPictureInPictureHandoffFence({
    required this.authorization,
    required this.epoch,
  });

  final MediaPictureInPictureAuthorization authorization;
  final int epoch;
}

class _MediaPictureInPictureSession {
  _MediaPictureInPictureSession({
    required this.id,
    required this.attachment,
    required this.generation,
    required this.canonicalPath,
    required this.item,
    required this.wasPlaying,
    required this.handoffPositionMs,
    required this.knownDurationMs,
  });

  final String id;
  final String attachment;
  final int generation;
  final String canonicalPath;
  final MediaViewerItem item;
  final bool wasPlaying;
  final int handoffPositionMs;
  int? knownDurationMs;
  bool stopIssued = false;
  bool terminalDelivered = false;
}

String _newOpaqueSessionId() {
  final random = Random.secure();
  return List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
