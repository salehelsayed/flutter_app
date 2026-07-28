import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';

typedef ConversationUploadOwnerResolver = Map<String, String> Function();
typedef ConversationUploadWakeAction = Future<void> Function();
typedef ConversationUploadCancellationFinalizer<TSnapshot> =
    Future<bool> Function(ConversationUploadOperation<TSnapshot> operation);

/// Immutable identity and lane context for one upload operation.
///
/// Mutable progress, cancellation, and wake-lock state intentionally remain
/// private to [ConversationUploadActivityController]. Keeping the handle
/// immutable lets an async lane adapter retain the exact old operation across
/// a widget detach or group rebind and terminally release only that operation.
@immutable
class ConversationUploadOperation<TSnapshot> {
  final int generation;
  final String scopeId;
  final String? messageId;
  final TSnapshot? composerSnapshot;
  final ConversationUploadCancellationFinalizer<TSnapshot>? cancelFinalizer;

  const ConversationUploadOperation._({
    required this.generation,
    required this.scopeId,
    required this.messageId,
    required this.composerSnapshot,
    required this.cancelFinalizer,
  });
}

class _ConversationUploadOperationState {
  int totalBytes = 0;
  int completedBytes = 0;
  int currentBytes = 0;
  String? currentUploadId;
  bool tracking = false;
  bool wakeHeld = false;
  bool terminal = false;
  bool cancelRequested = false;
  Future<void>? startFuture;
  Future<void>? releaseFuture;
  Future<bool>? cancellationFuture;
}

/// Shared presentation mechanics for direct and group upload activity.
///
/// The controller knows only a conversation scope, visual attachment owners,
/// progress events, and lane callbacks captured by immutable operation
/// handles. Repository mutation, composer restoration, dialogs, localized
/// feedback, and direct/group cancellation policy stay in the Wired adapters.
class ConversationUploadActivityController<TSnapshot> extends ChangeNotifier {
  ConversationUploadActivityController({
    required String scopeId,
    required ConversationUploadOwnerResolver resolveActiveOwners,
    required ConversationUploadWakeAction acquireWake,
    required ConversationUploadWakeAction releaseWake,
  }) : _scopeId = scopeId,
       _resolveActiveOwners = resolveActiveOwners,
       _acquireWake = acquireWake,
       _releaseWake = releaseWake;

  String _scopeId;
  ConversationUploadOwnerResolver _resolveActiveOwners;
  final ConversationUploadWakeAction _acquireWake;
  final ConversationUploadWakeAction _releaseWake;
  final Map<
    ConversationUploadOperation<TSnapshot>,
    _ConversationUploadOperationState
  >
  _operations = {};
  final Map<String, MessageUploadProgressViewState> _messageProgress = {};

  int _generation = 0;
  bool _viewAttached = true;
  bool _disposed = false;
  StreamSubscription<Map<String, dynamic>>? _progressSubscription;
  ConversationUploadOperation<TSnapshot>? _viewOperation;
  ConversationUploadOperation<TSnapshot>? _activeOperation;

  String get scopeId => _scopeId;
  int get generation => _generation;

  ConversationUploadOperation<TSnapshot> beginOperation({
    String? messageId,
    TSnapshot? composerSnapshot,
    ConversationUploadCancellationFinalizer<TSnapshot>? cancelFinalizer,
  }) {
    if (_disposed) {
      throw StateError('Cannot begin an upload after controller disposal');
    }
    final operation = ConversationUploadOperation<TSnapshot>._(
      generation: _generation,
      scopeId: _scopeId,
      messageId: messageId,
      composerSnapshot: composerSnapshot,
      cancelFinalizer: cancelFinalizer,
    );
    _operations[operation] = _ConversationUploadOperationState();
    _viewOperation = operation;
    if (messageId != null) {
      _activeOperation = operation;
    }
    _publish();
    return operation;
  }

  ConversationUploadOperation<TSnapshot>? get activeOperation {
    final operation = _activeOperation;
    if (operation == null || !_isCurrent(operation)) return null;
    final state = _operations[operation];
    return state == null || state.terminal ? null : operation;
  }

  bool get cancelRequested {
    final operation = activeOperation;
    return operation != null &&
        (_operations[operation]?.cancelRequested ?? false);
  }

  bool isCurrentOperation(ConversationUploadOperation<TSnapshot> operation) =>
      _isCurrent(operation);

  bool cancellationRequestedFor(
    ConversationUploadOperation<TSnapshot> operation,
  ) => _operations[operation]?.cancelRequested ?? false;

  bool get isTracking {
    final operation = _viewOperation;
    if (operation == null || !_isCurrent(operation)) return false;
    final state = _operations[operation];
    return state != null && state.tracking && !state.terminal;
  }

  UploadProgressViewState? get aggregateProgress {
    final operation = _viewOperation;
    if (operation == null || !_isCurrent(operation)) return null;
    final state = _operations[operation];
    if (state == null ||
        !state.tracking ||
        state.terminal ||
        state.totalBytes <= 0) {
      return null;
    }
    return UploadProgressViewState(
      sentBytes: (state.completedBytes + state.currentBytes).clamp(
        0,
        state.totalBytes,
      ),
      totalBytes: state.totalBytes,
    );
  }

  Map<String, MessageUploadProgressViewState> get messageProgress =>
      Map<String, MessageUploadProgressViewState>.unmodifiable(
        _messageProgress,
      );

  /// Makes this controller the sole owner of the bridge progress subscription.
  void bindProgressStream(Stream<Map<String, dynamic>> progressStream) {
    if (_disposed) {
      throw StateError('Cannot bind progress after controller disposal');
    }
    final previous = _progressSubscription;
    _progressSubscription = progressStream.listen(applyProgress);
    if (previous != null) unawaited(previous.cancel());
  }

  Future<void> startTracking(
    ConversationUploadOperation<TSnapshot> operation, {
    required int totalBytes,
  }) {
    final state = _stateFor(operation);
    if (state == null || state.terminal || totalBytes <= 0) {
      return Future<void>.value();
    }
    final inFlight = state.startFuture;
    if (inFlight != null) return inFlight;

    final future = _startTracking(operation, state, totalBytes: totalBytes);
    state.startFuture = future;
    return future;
  }

  Future<void> _startTracking(
    ConversationUploadOperation<TSnapshot> operation,
    _ConversationUploadOperationState state, {
    required int totalBytes,
  }) async {
    if (state.tracking) return;
    state
      ..tracking = true
      ..totalBytes = totalBytes
      ..completedBytes = 0
      ..currentBytes = 0
      ..currentUploadId = null;
    if (_isCurrent(operation)) {
      _viewOperation = operation;
      _publish();
    }

    try {
      await _acquireWake();
      state.wakeHeld = true;
    } catch (_) {
      state
        ..tracking = false
        ..totalBytes = 0;
      if (_isCurrent(operation)) _publish();
      rethrow;
    }

    if (state.terminal) {
      await _releaseWakeOnce(state);
    }
  }

  void markUploadStarted(
    ConversationUploadOperation<TSnapshot> operation,
    String uploadId,
  ) {
    final state = _stateFor(operation);
    if (state == null ||
        state.terminal ||
        !state.tracking ||
        uploadId.isEmpty) {
      return;
    }
    if (state.currentUploadId == uploadId && state.currentBytes == 0) return;
    state
      ..currentUploadId = uploadId
      ..currentBytes = 0;
    if (_isCurrent(operation)) _publish();
  }

  void markUploadCompleted(
    ConversationUploadOperation<TSnapshot> operation,
    int sizeBytes,
  ) {
    final state = _stateFor(operation);
    if (state == null || state.terminal || !state.tracking) return;
    final nextCompleted = (state.completedBytes + sizeBytes).clamp(
      0,
      state.totalBytes,
    );
    if (nextCompleted == state.completedBytes &&
        state.currentBytes == 0 &&
        state.currentUploadId == null) {
      return;
    }
    state
      ..completedBytes = nextCompleted
      ..currentBytes = 0
      ..currentUploadId = null;
    if (_isCurrent(operation)) _publish();
  }

  void applyProgress(Map<String, dynamic> event) {
    if (!_viewAttached || _disposed) return;
    final uploadId = event['id'];
    final sentValue = event['sentBytes'];
    final recipient = event['toPeerId'];
    if (uploadId is! String ||
        uploadId.isEmpty ||
        sentValue is! num ||
        (recipient is String &&
            recipient.isNotEmpty &&
            recipient != _scopeId)) {
      return;
    }

    final activeOwners = _resolveActiveOwners();
    var changed = _pruneStaleMessageProgress(activeOwners);
    final messageId = activeOwners[uploadId];
    final existing = messageId == null ? null : _messageProgress[messageId];
    if (messageId != null) {
      final rawTotal = event['totalBytes'];
      final eventTotal = rawTotal is num ? rawTotal.toInt() : 0;
      final totalBytes = eventTotal > 0
          ? eventTotal
          : existing?.attachmentId == uploadId
          ? existing!.totalBytes
          : 0;
      var sentBytes = sentValue.toInt();
      if (sentBytes < 0) sentBytes = 0;
      if (totalBytes > 0 && sentBytes > totalBytes) {
        sentBytes = totalBytes;
      }
      final isMonotonic =
          existing?.attachmentId != uploadId ||
          sentBytes >= (existing?.sentBytes ?? 0);
      final next = MessageUploadProgressViewState(
        messageId: messageId,
        attachmentId: uploadId,
        sentBytes: sentBytes,
        totalBytes: totalBytes,
      );
      if (isMonotonic && !_messageProgressEquals(existing, next)) {
        _messageProgress[messageId] = next;
        changed = true;
      }
    }

    final operation = _viewOperation;
    final state = operation == null ? null : _stateFor(operation);
    if (operation != null &&
        state != null &&
        _isCurrent(operation) &&
        state.tracking &&
        !state.terminal &&
        (state.currentUploadId == null || state.currentUploadId == uploadId)) {
      final nextBytes = sentValue.toInt().clamp(0, state.totalBytes);
      if (nextBytes > state.currentBytes ||
          (state.currentUploadId == null && nextBytes == state.currentBytes)) {
        if (state.currentUploadId != uploadId ||
            state.currentBytes != nextBytes) {
          state
            ..currentUploadId = uploadId
            ..currentBytes = nextBytes;
          changed = true;
        }
      }
    }

    if (changed) _publish();
  }

  bool refreshOwnerProjection({bool publish = true}) {
    final changed = _pruneStaleMessageProgress(_resolveActiveOwners());
    if (changed && publish) _publish();
    return changed;
  }

  bool requestCancelActive() {
    final operation = activeOperation;
    if (operation == null) return false;
    final state = _operations[operation]!;
    if (state.cancelRequested) return false;
    state.cancelRequested = true;
    _publish();
    return true;
  }

  Future<bool> finalizeCancellation(
    ConversationUploadOperation<TSnapshot> operation,
  ) {
    final state = _stateFor(operation);
    if (state == null || !state.cancelRequested) {
      return Future<bool>.value(false);
    }
    final existing = state.cancellationFuture;
    if (existing != null) return existing;
    final future = _runCancellationFinalizer(operation, state);
    state.cancellationFuture = future;
    return future;
  }

  Future<bool> _runCancellationFinalizer(
    ConversationUploadOperation<TSnapshot> operation,
    _ConversationUploadOperationState state,
  ) async {
    final finalizer = operation.cancelFinalizer;
    if (finalizer == null) return false;
    final applied = await finalizer(operation);
    if (applied) {
      await complete(operation);
    }
    return applied;
  }

  Future<void> complete(
    ConversationUploadOperation<TSnapshot> operation,
  ) async {
    final state = _stateFor(operation);
    if (state == null) return;
    if (!state.terminal) {
      state
        ..terminal = true
        ..tracking = false
        ..totalBytes = 0
        ..completedBytes = 0
        ..currentBytes = 0
        ..currentUploadId = null;
      var changed = false;
      if (identical(_viewOperation, operation)) {
        _viewOperation = null;
        changed = true;
      }
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
        changed = true;
      }
      if (changed) _publish();
    }
    await _releaseWakeOnce(state);
  }

  /// Detaches the current UI generation without terminating its operations.
  ///
  /// Late async owners may still call [complete] to release their exact wake
  /// hold, but no old progress/cancel/composer projection can reach this view.
  void detachView() {
    if (_disposed && !_viewAttached) return;
    final shouldPublish =
        _viewAttached &&
        (_viewOperation != null ||
            _activeOperation != null ||
            _messageProgress.isNotEmpty);
    _generation++;
    _viewOperation = null;
    _activeOperation = null;
    _messageProgress.clear();
    if (shouldPublish) _publish();
    _viewAttached = false;
  }

  void rebind({
    required String scopeId,
    required ConversationUploadOwnerResolver resolveActiveOwners,
  }) {
    if (_disposed) {
      throw StateError('Cannot rebind a disposed upload controller');
    }
    if (_viewAttached) detachView();
    _scopeId = scopeId;
    _resolveActiveOwners = resolveActiveOwners;
    _viewAttached = true;
  }

  bool _isCurrent(ConversationUploadOperation<TSnapshot> operation) =>
      _viewAttached &&
      operation.generation == _generation &&
      operation.scopeId == _scopeId;

  _ConversationUploadOperationState? _stateFor(
    ConversationUploadOperation<TSnapshot> operation,
  ) => _operations[operation];

  bool _pruneStaleMessageProgress(Map<String, String> activeOwners) {
    final before = _messageProgress.length;
    _messageProgress.removeWhere(
      (messageId, progress) => activeOwners[progress.attachmentId] != messageId,
    );
    return _messageProgress.length != before;
  }

  bool _messageProgressEquals(
    MessageUploadProgressViewState? a,
    MessageUploadProgressViewState b,
  ) {
    return a != null &&
        a.messageId == b.messageId &&
        a.attachmentId == b.attachmentId &&
        a.sentBytes == b.sentBytes &&
        a.totalBytes == b.totalBytes;
  }

  Future<void> _releaseWakeOnce(_ConversationUploadOperationState state) {
    final existing = state.releaseFuture;
    if (existing != null) return existing;
    if (!state.wakeHeld) return Future<void>.value();
    state.wakeHeld = false;
    final future = _releaseWake();
    state.releaseFuture = future;
    return future;
  }

  void _publish() {
    if (_viewAttached && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    detachView();
    final progressSubscription = _progressSubscription;
    _progressSubscription = null;
    if (progressSubscription != null) {
      unawaited(progressSubscription.cancel());
    }
    _disposed = true;
    super.dispose();
  }
}
