import 'dart:async';

/// Aggregate progress from one bounded protected-content/media fixed point.
///
/// The four owners deliberately remain separate so callers can expose exact
/// lifecycle diagnostics without giving the restricted linked runtime access
/// to any generic group retry service.
final class ProtectedGroupContentMediaDrainProgress {
  const ProtectedGroupContentMediaDrainProgress({
    required this.contentReplayed,
    required this.outgoingMedia,
    required this.contentRetried,
    required this.incomingMedia,
    required this.passes,
  });

  final int contentReplayed;
  final int outgoingMedia;
  final int contentRetried;
  final int incomingMedia;
  final int passes;
}

/// Repeats the four strict owners until a whole pass reports no progress.
///
/// Media callbacks are the opt-in marker for Plan-365. When both are absent,
/// the historical blob-free runtime performs exactly one content replay/retry
/// pass. A hard bound prevents a corrupt or adversarial progress reporter from
/// monopolizing startup/resume; durable rows remain available for the next
/// lifecycle drain.
Future<ProtectedGroupContentMediaDrainProgress>
drainProtectedGroupContentMediaFixedPoint({
  Future<int> Function()? replayContent,
  Future<int> Function()? drainOutgoingMedia,
  Future<int> Function()? retryContent,
  Future<int> Function()? drainIncomingMedia,
  int maxPasses = 8,
}) async {
  assert(maxPasses > 0);
  final mediaEnabled = drainOutgoingMedia != null || drainIncomingMedia != null;
  var replayed = 0;
  var outgoing = 0;
  var retried = 0;
  var incoming = 0;
  var passes = 0;

  do {
    passes += 1;
    final replayProgress = await replayContent?.call() ?? 0;
    final outgoingProgress = await drainOutgoingMedia?.call() ?? 0;
    final retryProgress = await retryContent?.call() ?? 0;
    final incomingProgress = await drainIncomingMedia?.call() ?? 0;
    replayed += replayProgress;
    outgoing += outgoingProgress;
    retried += retryProgress;
    incoming += incomingProgress;

    if (!mediaEnabled ||
        replayProgress + outgoingProgress + retryProgress + incomingProgress <=
            0) {
      break;
    }
  } while (passes < maxPasses);

  return ProtectedGroupContentMediaDrainProgress(
    contentReplayed: replayed,
    outgoingMedia: outgoing,
    contentRetried: retried,
    incomingMedia: incoming,
    passes: passes,
  );
}

/// Runtime-local pause barrier for strict linked group-content custody.
///
/// The owner closes outgoing admission synchronously, before either pause leg
/// can await. Operations that entered before that close remain owned until
/// their store/CAS future settles; operations offered afterwards receive their
/// caller-supplied blocked value without starting. Inbound admission is paused
/// by the injected runtime owner and is reopened before outgoing admission on
/// resume.
final class ProtectedGroupContentRuntimeQuiescence {
  ProtectedGroupContentRuntimeQuiescence({
    required Future<void> Function() pauseInboundAdmission,
    required void Function() resumeInboundAdmission,
    Future<void> Function()? quiesceOutgoingMedia,
    Future<void> Function()? quiesceIncomingMedia,
    void Function()? resumeMedia,
  }) : _pauseInboundAdmission = pauseInboundAdmission,
       _resumeInboundAdmission = resumeInboundAdmission,
       _quiesceOutgoingMedia = quiesceOutgoingMedia,
       _quiesceIncomingMedia = quiesceIncomingMedia,
       _resumeMedia = resumeMedia;

  final Future<void> Function() _pauseInboundAdmission;
  final void Function() _resumeInboundAdmission;
  final Future<void> Function()? _quiesceOutgoingMedia;
  final Future<void> Function()? _quiesceIncomingMedia;
  final void Function()? _resumeMedia;

  bool _outgoingAdmissionOpen = true;
  int _outgoingInFlight = 0;
  int _pauseGeneration = 0;
  Completer<void>? _outgoingDrained;
  Future<void>? _pauseBarrier;

  /// Runs one strict outgoing store/retry/authoring operation when admitted.
  ///
  /// Entry accounting happens before [operation] is invoked, so a synchronous
  /// lifecycle pause cannot miss an operation that has already been admitted.
  Future<T> runOutgoing<T>({
    required T blockedValue,
    required Future<T> Function() operation,
  }) {
    if (!_outgoingAdmissionOpen) return Future<T>.value(blockedValue);

    _outgoingInFlight += 1;
    late final Future<T> result;
    try {
      result = operation();
    } catch (error, stackTrace) {
      _leaveOutgoing();
      return Future<T>.error(error, stackTrace);
    }
    return result.whenComplete(_leaveOutgoing);
  }

  /// Synchronously refuses new outgoing work and returns a generation lease.
  ///
  /// Every pause intent gets a new generation even when custody is already
  /// quiescent. Consequently, a foreground recovery may resume only the exact
  /// pause it began; any newer background edge invalidates that lease.
  ProtectedGroupContentPauseLease pause() {
    _outgoingAdmissionOpen = false;
    final generation = ++_pauseGeneration;
    final barrier = _pauseBarrier ??= _pauseBothCustodyLegs();
    return ProtectedGroupContentPauseLease._(this, generation, barrier);
  }

  Future<void> _pauseBothCustodyLegs() async {
    final outgoingDrained = _outgoingInFlight == 0
        ? Future<void>.value()
        : (_outgoingDrained ??= Completer<void>()).future;
    await Future.wait<void>([
      _pauseInboundAdmission(),
      outgoingDrained,
      if (_quiesceOutgoingMedia != null) _quiesceOutgoingMedia(),
      if (_quiesceIncomingMedia != null) _quiesceIncomingMedia(),
    ]);
  }

  Future<bool> _resume(int generation, Future<void> barrier) async {
    await barrier;
    if (generation != _pauseGeneration) return false;
    _resumeInboundAdmission();
    _resumeMedia?.call();
    _outgoingAdmissionOpen = true;
    _pauseBarrier = null;
    return true;
  }

  void _leaveOutgoing() {
    _outgoingInFlight -= 1;
    if (_outgoingInFlight != 0) return;
    final drained = _outgoingDrained;
    _outgoingDrained = null;
    if (drained != null && !drained.isCompleted) drained.complete();
  }
}

/// One exact pause intent. A newer pause makes [resume] a fail-closed no-op.
final class ProtectedGroupContentPauseLease {
  ProtectedGroupContentPauseLease._(
    this._owner,
    this._generation,
    this.quiesced,
  );

  final ProtectedGroupContentRuntimeQuiescence _owner;
  final int _generation;

  /// Completes only after inbound replay and admitted outgoing custody drain.
  final Future<void> quiesced;

  Future<bool>? _resumeResult;

  /// Reopens inbound first and outgoing second iff this remains the newest
  /// pause intent. Returns false when a later lifecycle pause superseded it.
  Future<bool> resume() =>
      _resumeResult ??= _owner._resume(_generation, quiesced);
}
