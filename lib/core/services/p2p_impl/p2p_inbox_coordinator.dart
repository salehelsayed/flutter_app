part of '../p2p_service_impl.dart';

class _P2PInboxPort {
  final NodeState Function() readNodeState;
  final Stream<NodeState> nodeStateStream;
  final Future<bool> Function(String operation, {String? peerId})
  allowsAccountNetworkSideEffects;
  final Future<Map<String, dynamic>> Function({
    required String nonce,
    required bool ok,
  })
  confirmDirectMessage;
  final Future<Map<String, dynamic>> Function({
    required String toPeerId,
    required String message,
    int? timeoutMs,
    String? wakeToken,
    String? custodyContract,
    String? custodyKind,
    int? custodyExpiresAtOrBeforeMs,
  })
  storeInbox;
  final Future<Map<String, dynamic>> Function({int? timeoutMs}) retrieveInbox;
  final Future<Map<String, dynamic>> Function({
    int? timeoutMs,
    String? custodyContract,
  })
  retrievePendingInbox;
  final Future<Map<String, dynamic>> Function({
    required List<String> entryIds,
    int? timeoutMs,
    String? custodyContract,
  })
  ackInbox;
  final void Function(ChatMessage message) emitIncomingMessage;
  final bool Function() isMessageStreamClosed;
  final void Function(String transport) recordTransport;
  final void Function({required String source, required String trigger})
  recordSuccessfulInboxProof;
  final void Function({
    required String source,
    required String trigger,
    String? failureReason,
  })
  recordInboxProofFailure;

  const _P2PInboxPort({
    required this.readNodeState,
    required this.nodeStateStream,
    required this.allowsAccountNetworkSideEffects,
    required this.confirmDirectMessage,
    required this.storeInbox,
    required this.retrieveInbox,
    required this.retrievePendingInbox,
    required this.ackInbox,
    required this.emitIncomingMessage,
    required this.isMessageStreamClosed,
    required this.recordTransport,
    required this.recordSuccessfulInboxProof,
    required this.recordInboxProofFailure,
  });
}

class _P2PInboxCoordinator {
  static bool _sameProtectedRelayEntry(
    InboxStagingEntry left,
    InboxStagingEntry right,
  ) =>
      left.entryId == right.entryId &&
      left.ownerPeerId == right.ownerPeerId &&
      left.senderPeerId == right.senderPeerId &&
      left.messageType == right.messageType &&
      left.relayTimestamp == right.relayTimestamp &&
      left.envelope == right.envelope;

  static bool _isProtectedGroupEnvelopeType(String? messageType) =>
      messageType == _linkedGroupBootstrapInboxEnvelopeType ||
      messageType == _protectedGroupAuthorityInboxEnvelopeType ||
      _isProtectedGroupContentEnvelopeType(messageType);

  static bool _isProtectedGroupContentEnvelopeType(String? messageType) =>
      messageType == _protectedGroupContentInboxEnvelopeType ||
      messageType == _unverifiedProtectedGroupContentInboxEnvelopeType;

  final _P2PInboxPort _port;
  final ReceivedWakeTokenStore? _receivedWakeTokenStore;
  final AcceptedInboxWakeTokenHashObserver? _acceptedInboxWakeTokenHashObserver;
  final InboxStagingRepository _inboxStagingRepository;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxChatMessage;
  final ReplayRecoveredInboxChatMessage? _replayLiveLanChatMessage;
  final ReplayRecoveredInboxChatMessage? _replayLiveDirectChatMessage;
  final ReplayRecoveredInboxIntroductionMessage?
  _replayRecoveredInboxIntroductionMessage;
  final ReplayRecoveredInboxContactRequestMessage?
  _replayRecoveredInboxContactRequest;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxReaction;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxMessageDeletion;
  ReplayRecoveredProtectedGroupEnvelope? _replayRecoveredProtectedGroupEnvelope;
  final Future<String?> Function(ChatMessage message)?
  _predecryptInboxChatEntry;
  final int _maxInboxPages;
  final int _maxRecoverableInboxReplayEntries;
  final int _maxConcurrentInboxDecrypts;
  final Duration _foregroundInboxTimeout;

  Completer<DirectInboxDrainOutcome>? _drainInProgress;
  bool _drainInProgressWaitsAllPages = false;
  Future<DirectInboxDrainOutcome>? _backgroundDrainInProgress;
  bool _pendingStartupDrain = false;
  bool _pendingStartupDrainWaitForAllPages = false;
  bool _protectedGroupContentAdmissionPaused = false;
  Future<void>? _protectedGroupContentReplayInFlight;

  _P2PInboxCoordinator({
    required _P2PInboxPort port,
    required InboxStagingRepository inboxStagingRepository,
    ReceivedWakeTokenStore? receivedWakeTokenStore,
    AcceptedInboxWakeTokenHashObserver? acceptedInboxWakeTokenHashObserver,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxChatMessage,
    ReplayRecoveredInboxChatMessage? replayLiveLanChatMessage,
    ReplayRecoveredInboxChatMessage? replayLiveDirectChatMessage,
    ReplayRecoveredInboxIntroductionMessage?
    replayRecoveredInboxIntroductionMessage,
    ReplayRecoveredInboxContactRequestMessage?
    replayRecoveredInboxContactRequest,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxReaction,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxMessageDeletion,
    ReplayRecoveredProtectedGroupEnvelope?
    replayRecoveredProtectedGroupEnvelope,
    Future<String?> Function(ChatMessage message)? predecryptInboxChatEntry,
    required int maxInboxPages,
    required int maxRecoverableInboxReplayEntries,
    required int maxConcurrentInboxDecrypts,
    required Duration foregroundInboxTimeout,
  }) : _port = port,
       _inboxStagingRepository = inboxStagingRepository,
       _receivedWakeTokenStore = receivedWakeTokenStore,
       _acceptedInboxWakeTokenHashObserver = acceptedInboxWakeTokenHashObserver,
       _replayRecoveredInboxChatMessage = replayRecoveredInboxChatMessage,
       _replayLiveLanChatMessage = replayLiveLanChatMessage,
       _replayLiveDirectChatMessage = replayLiveDirectChatMessage,
       _replayRecoveredInboxIntroductionMessage =
           replayRecoveredInboxIntroductionMessage,
       _replayRecoveredInboxContactRequest = replayRecoveredInboxContactRequest,
       _replayRecoveredInboxReaction = replayRecoveredInboxReaction,
       _replayRecoveredInboxMessageDeletion =
           replayRecoveredInboxMessageDeletion,
       _replayRecoveredProtectedGroupEnvelope =
           replayRecoveredProtectedGroupEnvelope,
       _predecryptInboxChatEntry = predecryptInboxChatEntry,
       _maxInboxPages = maxInboxPages,
       _maxRecoverableInboxReplayEntries = maxRecoverableInboxReplayEntries,
       _maxConcurrentInboxDecrypts = maxConcurrentInboxDecrypts,
       _foregroundInboxTimeout = foregroundInboxTimeout;

  void setProtectedGroupReplayHandler(
    ReplayRecoveredProtectedGroupEnvelope? handler,
  ) {
    _replayRecoveredProtectedGroupEnvelope = handler;
  }

  void resumeProtectedGroupContentAdmission() {
    _protectedGroupContentAdmissionPaused = false;
  }

  Future<void> pauseProtectedGroupContentAdmission() async {
    _protectedGroupContentAdmissionPaused = true;
    final inFlight = _protectedGroupContentReplayInFlight;
    if (inFlight != null) await inFlight;
  }

  Future<int> drainProtectedGroupContentFixedPoint({int maxPasses = 8}) async {
    if (maxPasses < 1) return 0;
    var passes = 0;
    for (; passes < maxPasses; passes++) {
      final before = await _recoverableProtectedGroupFingerprint();
      final outcome = await _drainOfflineInbox(waitForAllPages: true);
      final after = await _recoverableProtectedGroupFingerprint();
      if (outcome.isSuccessful && !outcome.hasMore) return passes + 1;
      // A prerequisite commit removes or changes at least one recoverable row.
      // An unchanged durable fingerprint means another immediate pass would
      // only spin on relay-owned bytes.
      if (before == after) return passes + 1;
    }
    return passes;
  }

  Future<String> _recoverableProtectedGroupFingerprint() async {
    final rows = await _inboxStagingRepository.getRecoverableEntries(
      limit: _maxRecoverableInboxReplayEntries,
    );
    final protected =
        rows
            .where((entry) => _isProtectedGroupEnvelopeType(entry.messageType))
            .map(
              (entry) => <String?>[
                entry.entryId,
                entry.messageType,
                entry.status,
                entry.rejectReasonCode,
              ].join('\u0000'),
            )
            .toList(growable: false)
          ..sort();
    return protected.join('\u0001');
  }

  String _normalizeInboxTimestamp(dynamic ts) {
    if (ts is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        ts,
        isUtc: true,
      ).toIso8601String();
    }
    if (ts is String && ts.isNotEmpty) {
      return ts;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  String? _messageTypeFromEnvelope(String envelope) {
    final contentClassification = classifyProtectedGroupContentWire(envelope);
    if (contentClassification ==
        ProtectedGroupContentWireClassification.signedContent) {
      return _protectedGroupContentInboxEnvelopeType;
    }
    if (contentClassification ==
        ProtectedGroupContentWireClassification.unverifiedCandidate) {
      return _unverifiedProtectedGroupContentInboxEnvelopeType;
    }
    try {
      final decoded = jsonDecode(envelope) as Map<String, dynamic>;
      final type = decoded['type']?.toString();
      if (type != null && type.isNotEmpty) return type;
      return null;
    } catch (_) {
      return null;
    }
  }

  InboxStagingEntry? _stagingEntryFromRawInboxMessage(
    Map<String, dynamic> raw,
    String ownerPeerId,
  ) {
    final entryId = raw['id']?.toString();
    final from = raw['from']?.toString();
    final envelope = raw['message']?.toString();
    if (entryId == null ||
        entryId.isEmpty ||
        from == null ||
        from.isEmpty ||
        envelope == null ||
        envelope.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGE_SKIP_MALFORMED',
        details: {
          'hasEntryId': entryId != null && entryId.isNotEmpty,
          'hasFrom': from != null && from.isNotEmpty,
          'hasEnvelope': envelope != null && envelope.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: entryId,
      ownerPeerId: ownerPeerId,
      senderPeerId: from,
      messageType: _messageTypeFromEnvelope(envelope),
      relayTimestamp: _normalizeInboxTimestamp(raw['timestamp']),
      envelope: envelope,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  InboxStagingEntry? _stagingEntryFromDirectMessage(
    ChatMessage message, {
    String? messageType,
  }) {
    final nonce = message.confirmNonce;
    final ownerPeerId = message.to.isNotEmpty
        ? message.to
        : (_port.readNodeState().peerId ?? '');
    if (nonce == null ||
        nonce.isEmpty ||
        ownerPeerId.isEmpty ||
        message.from.isEmpty ||
        message.content.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_SKIP_MALFORMED',
        details: {
          'hasNonce': nonce != null && nonce.isNotEmpty,
          'hasOwner': ownerPeerId.isNotEmpty,
          'hasFrom': message.from.isNotEmpty,
          'hasEnvelope': message.content.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: 'direct:$nonce',
      ownerPeerId: ownerPeerId,
      senderPeerId: message.from,
      messageType: messageType ?? _messageTypeFromEnvelope(message.content),
      relayTimestamp: _normalizeInboxTimestamp(message.timestamp),
      envelope: message.content,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  InboxStagingEntry? _stagingEntryFromLanMessage(
    LocalChatMessage message, {
    required String nonce,
    String? messageType,
  }) {
    final ownerPeerId = message.to.isNotEmpty
        ? message.to
        : (_port.readNodeState().peerId ?? '');
    if (nonce.isEmpty ||
        ownerPeerId.isEmpty ||
        message.from.isEmpty ||
        message.content.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGE_SKIP_MALFORMED',
        details: {
          'hasNonce': nonce.isNotEmpty,
          'hasOwner': ownerPeerId.isNotEmpty,
          'hasFrom': message.from.isNotEmpty,
          'hasEnvelope': message.content.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: 'lan:$nonce',
      ownerPeerId: ownerPeerId,
      senderPeerId: message.from,
      messageType: messageType ?? _messageTypeFromEnvelope(message.content),
      relayTimestamp: message.timestamp.toUtc().toIso8601String(),
      envelope: message.content,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  bool _shouldDurablyStageDeferredDirectChat(
    ChatMessage message, {
    required String? envelopeType,
  }) {
    final nonce = message.confirmNonce;
    if (!message.isIncoming || nonce == null || nonce.isEmpty) {
      return false;
    }
    switch (envelopeType) {
      case 'chat_message':
        return _replayRecoveredInboxChatMessage != null;
      case 'message_reaction':
        return _replayRecoveredInboxReaction != null;
      case 'message_deletion':
        return _replayRecoveredInboxMessageDeletion != null;
      default:
        return false;
    }
  }

  ChatMessage _messageWithoutConfirmNonce(ChatMessage message) {
    return ChatMessage(
      from: message.from,
      to: message.to,
      content: message.content,
      timestamp: message.timestamp,
      isIncoming: message.isIncoming,
      transport: message.transport,
    );
  }

  Future<RecoveredInboxReplayOutcome?> _replayUnstagedReaction(
    ChatMessage message, {
    required String reason,
  }) async {
    final replay = _replayRecoveredInboxReaction;
    if (replay == null) return null;
    try {
      final outcome = await replay(_messageWithoutConfirmNonce(message));
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_REACTION_UNSTAGED_REPLAY',
        details: {
          'reason': reason,
          'disposition': outcome.disposition.name,
          'reasonCode': outcome.reasonCode,
        },
      );
      return outcome;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_REACTION_UNSTAGED_REPLAY_ERROR',
        details: {'reason': reason, 'error': e.toString()},
      );
      return null;
    }
  }

  Future<void> _processDurablyStagedDirectChat(
    ChatMessage message, {
    required InboxStagingEntry entry,
  }) async {
    final repo = _inboxStagingRepository;
    final ReplayRecoveredInboxChatMessage? selectedReplay;
    final String eventSuffix;
    switch (entry.messageType) {
      case 'message_reaction':
        selectedReplay = _replayRecoveredInboxReaction;
        eventSuffix = 'REACTION';
        break;
      case 'message_deletion':
        selectedReplay = _replayRecoveredInboxMessageDeletion;
        eventSuffix = 'DELETION';
        break;
      default:
        selectedReplay = _replayLiveDirectChatMessage;
        eventSuffix = 'CHAT';
        break;
    }
    final replayLiveDirectChatMessage = selectedReplay;
    if (replayLiveDirectChatMessage == null) {
      _port.emitIncomingMessage(message);
      return;
    }

    try {
      await repo.stageEntries([entry]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
      if (entry.messageType == 'message_reaction') {
        try {
          final outcome = await replayLiveDirectChatMessage(
            _messageWithoutConfirmNonce(message),
          );
          final isTerminal =
              outcome.disposition == RecoveredInboxChatDisposition.committed ||
              outcome.disposition == RecoveredInboxChatDisposition.rejected;
          if (isTerminal) {
            await _port.confirmDirectMessage(
              nonce: message.confirmNonce!,
              ok: true,
            );
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_DIRECT_STAGE_ERROR_REACTION_REPLAY',
            details: {
              'disposition': outcome.disposition.name,
              'reasonCode': outcome.reasonCode,
            },
          );
        } catch (replayError) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_DIRECT_STAGE_ERROR_REACTION_RETRY',
            details: {'error': replayError.toString()},
          );
        }
        return;
      }
      _port.emitIncomingMessage(message);
      return;
    }

    final nonce = message.confirmNonce!;
    try {
      await _port.confirmDirectMessage(nonce: nonce, ok: true);
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_CONFIRM_SUCCESS',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_CONFIRM_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }

    final replayMessage = _messageWithoutConfirmNonce(message);
    try {
      final outcome = await replayLiveDirectChatMessage(
        replayMessage,
        stagedEntryId: entry.entryId,
      );
      await _applyRecoveredInboxOutcome(
        repo: repo,
        entry: entry,
        outcome: outcome,
        committedEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_COMMITTED',
        retryableEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_RETRYABLE',
        rejectedEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_REJECTED',
        quarantinedEvent:
            'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_QUARANTINED',
      );
    } catch (e) {
      await repo.markRetryable(
        entry.entryId,
        reasonCode: 'processing_error',
        reasonDetail: e.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_EXCEPTION',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _replayDurablyStagedLanChat(
    ChatMessage message, {
    required InboxStagingEntry entry,
  }) async {
    final repo = _inboxStagingRepository;
    final ReplayRecoveredInboxChatMessage? replayLanChatMessage;
    final String eventSuffix;
    switch (entry.messageType) {
      case 'message_reaction':
        replayLanChatMessage = _replayRecoveredInboxReaction;
        eventSuffix = 'REACTION';
        break;
      case 'message_deletion':
        replayLanChatMessage = _replayRecoveredInboxMessageDeletion;
        eventSuffix = 'DELETION';
        break;
      default:
        replayLanChatMessage =
            _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        eventSuffix = 'CHAT';
        break;
    }
    if (replayLanChatMessage == null) {
      _port.emitIncomingMessage(message);
      return;
    }

    try {
      final outcome = await replayLanChatMessage(
        message,
        stagedEntryId: entry.entryId,
      );
      await _applyRecoveredInboxOutcome(
        repo: repo,
        entry: entry,
        outcome: outcome,
        committedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_COMMITTED',
        retryableEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_RETRYABLE',
        rejectedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_REJECTED',
        quarantinedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_QUARANTINED',
      );
    } catch (e) {
      await repo.markRetryable(
        entry.entryId,
        reasonCode: 'processing_error',
        reasonDetail: e.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_EXCEPTION',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }
  }

  Future<Map<String, String>> _predecryptInboxChatEntries(
    List<InboxStagingEntry> entries,
  ) async {
    final predecrypt = _predecryptInboxChatEntry;
    if (predecrypt == null) return const {};
    final chatEntries = entries
        .where((e) => e.messageType == 'chat_message')
        .toList(growable: false);
    if (chatEntries.isEmpty) return const {};

    final plaintextByEntryId = <String, String>{};
    var nextIndex = 0;

    Future<void> decryptNext() async {
      while (true) {
        final index = nextIndex;
        nextIndex++;
        if (index >= chatEntries.length) return;
        final entry = chatEntries[index];
        try {
          final plaintext = await predecrypt(entry.toChatMessage());
          if (plaintext != null) {
            plaintextByEntryId[entry.entryId] = plaintext;
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_INBOX_PREDECRYPT_ERROR',
            details: {
              'entryId': entry.entryId.length > 8
                  ? entry.entryId.substring(0, 8)
                  : entry.entryId,
              'error': e.toString(),
            },
          );
        }
      }
    }

    final workerCount = chatEntries.length < _maxConcurrentInboxDecrypts
        ? chatEntries.length
        : _maxConcurrentInboxDecrypts;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => decryptNext()),
    );
    return plaintextByEntryId;
  }

  Future<int> _replayStagedInboxEntries({
    List<String>? entryIds,
    Set<String>? protectedRelayAckableEntryIds,
  }) async {
    final repo = _inboxStagingRepository;

    final entries = entryIds == null
        ? await repo.getRecoverableEntries(
            limit: _maxRecoverableInboxReplayEntries,
          )
        : await repo.getRecoverableEntriesByIds(entryIds);

    final predecryptedByEntryId = await _predecryptInboxChatEntries(entries);
    var replayed = 0;

    for (final entry in entries) {
      final entryStopwatch = Stopwatch()..start();
      final message = entry.toChatMessage();
      try {
        if (_isProtectedGroupEnvelopeType(entry.messageType)) {
          if (_isProtectedGroupContentEnvelopeType(entry.messageType) &&
              _protectedGroupContentAdmissionPaused) {
            await _markProtectedGroupPrerequisiteWaiting(
              repo,
              entry,
              reasonCode: 'protected_group_content_admission_paused',
            );
            continue;
          }
          final replay = _replayRecoveredProtectedGroupEnvelope;
          if (replay == null) {
            await _markProtectedGroupPrerequisiteWaiting(
              repo,
              entry,
              reasonCode: 'protected_group_handler_unavailable',
            );
            continue;
          }
          final replayFuture = replay(message);
          if (_isProtectedGroupContentEnvelopeType(entry.messageType)) {
            _protectedGroupContentReplayInFlight = replayFuture.then<void>(
              (_) {},
              onError: (_) {},
            );
          }
          late final ProtectedGroupReplayOutcome outcome;
          try {
            outcome = await replayFuture;
          } finally {
            if (_isProtectedGroupContentEnvelopeType(entry.messageType)) {
              _protectedGroupContentReplayInFlight = null;
            }
          }
          switch (outcome.disposition) {
            case ProtectedGroupReplayDisposition.applied:
            case ProtectedGroupReplayDisposition.duplicate:
            case ProtectedGroupReplayDisposition.terminalRejected:
              // Keep terminal local evidence until the relay confirms the
              // exact ACK. If ACK fails, the staged bytes drive an idempotent
              // retry instead of depending on a later re-download.
              await _markProtectedGroupAckPending(repo, entry.entryId);
              protectedRelayAckableEntryIds?.add(entry.entryId);
              replayed++;
              break;
            case ProtectedGroupReplayDisposition.unverifiedRejected:
              // No authenticated terminal fact exists, so the relay must
              // retain its copy and this exact staged envelope must never
              // enter the ACK set. Quarantine is a terminal local keep-state.
              await repo.markQuarantined(
                entry.entryId,
                reasonCode: outcome.reasonCode,
                reasonDetail: outcome.reasonDetail,
              );
              break;
            case ProtectedGroupReplayDisposition.retryable:
              await repo.markRetryable(
                entry.entryId,
                reasonCode: outcome.reasonCode,
                reasonDetail: outcome.reasonDetail,
              );
              break;
            case ProtectedGroupReplayDisposition.prerequisiteWaiting:
              await _markProtectedGroupPrerequisiteWaiting(
                repo,
                entry,
                reasonCode: outcome.reasonCode,
                reasonDetail: outcome.reasonDetail,
              );
              break;
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_PROTECTED_GROUP_REPLAY',
            details: {
              'entryId': entry.entryId.length > 8
                  ? entry.entryId.substring(0, 8)
                  : entry.entryId,
              'messageType': entry.messageType,
              'disposition': outcome.disposition.name,
              'reasonCode': outcome.reasonCode,
            },
          );
          continue;
        }
        final ReplayRecoveredInboxChatMessage? chatReplay;
        if (entry.entryId.startsWith('direct:')) {
          chatReplay =
              _replayLiveDirectChatMessage ?? _replayRecoveredInboxChatMessage;
        } else if (entry.entryId.startsWith('lan:')) {
          chatReplay =
              _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        } else {
          chatReplay = _replayRecoveredInboxChatMessage;
        }
        if (entry.messageType == 'chat_message' && chatReplay != null) {
          final predecryptedText = predecryptedByEntryId[entry.entryId];
          final outcome = await chatReplay(
            predecryptedText != null
                ? message.copyWith(predecryptedText: predecryptedText)
                : message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxIntroductionMessage =
            _replayRecoveredInboxIntroductionMessage;
        if (entry.messageType == 'introduction' &&
            replayRecoveredInboxIntroductionMessage != null) {
          final outcome = await replayRecoveredInboxIntroductionMessage(
            message,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxContactRequest =
            _replayRecoveredInboxContactRequest;
        if (entry.messageType == 'contact_request' &&
            replayRecoveredInboxContactRequest != null) {
          final outcome = await replayRecoveredInboxContactRequest(message);
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_COMMITTED',
            retryableEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_REJECTED',
            quarantinedEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxReaction = _replayRecoveredInboxReaction;
        if (entry.messageType == 'message_reaction' &&
            replayRecoveredInboxReaction != null) {
          final outcome = await replayRecoveredInboxReaction(
            message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxMessageDeletion =
            _replayRecoveredInboxMessageDeletion;
        if (entry.messageType == 'message_deletion' &&
            replayRecoveredInboxMessageDeletion != null) {
          final outcome = await replayRecoveredInboxMessageDeletion(
            message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final forwarded = await _handleMessageReceived(message);
        if (!forwarded) {
          continue;
        }
        await repo.deleteEntry(entry.entryId);
        replayed++;

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_FORWARD_COMPLETE',
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'messageType': entry.messageType,
          },
        );
        entryStopwatch.stop();
        emitFlowEvent(
          layer: 'FL',
          event: 'INBOX_DELIVERY_TIMING',
          details: {
            'deliveryMs': entryStopwatch.elapsedMilliseconds,
            'messageId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
          },
        );
      } catch (e) {
        await repo.markRetryable(
          entry.entryId,
          reasonCode: 'processing_error',
          reasonDetail: e.toString(),
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_REPLAY_EXCEPTION',
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'error': e.toString(),
          },
        );
      }
    }

    return replayed;
  }

  Future<void> _markProtectedGroupPrerequisiteWaiting(
    InboxStagingRepository repo,
    InboxStagingEntry entry, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    if (repo is InboxStagingPrerequisiteWaitingRepository) {
      await (repo as InboxStagingPrerequisiteWaitingRepository)
          .markPrerequisiteWaiting(
            entry.entryId,
            reasonCode: reasonCode,
            reasonDetail: reasonDetail,
          );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_PROTECTED_GROUP_PREREQUISITE_WAITING',
      details: {
        'entryId': entry.entryId.length > 8
            ? entry.entryId.substring(0, 8)
            : entry.entryId,
        'reasonCode': reasonCode,
      },
    );
  }

  Future<void> _markProtectedGroupAckPending(
    InboxStagingRepository repo,
    String entryId,
  ) async {
    if (repo is InboxStagingProtectedAckPendingRepository) {
      await (repo as InboxStagingProtectedAckPendingRepository)
          .markProtectedAckPending(entryId);
    }
  }

  Future<void> _quarantineRecoveredInboxEntry({
    required InboxStagingRepository repo,
    required InboxStagingEntry entry,
    required String quarantinedEvent,
    required String reasonCode,
    String? reasonDetail,
  }) async {
    await repo.markQuarantined(
      entry.entryId,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
    final entryIdShort = entry.entryId.length > 8
        ? entry.entryId.substring(0, 8)
        : entry.entryId;
    emitFlowEvent(
      layer: 'FL',
      event: 'INBOX_STAGING_QUARANTINED',
      details: {
        'entryId': entryIdShort,
        'reasonCode': reasonCode,
        'attemptCount': entry.attemptCount + 1,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: quarantinedEvent,
      details: {'entryId': entryIdShort, 'reasonCode': reasonCode},
    );
  }

  Future<bool> _applyRecoveredInboxOutcome({
    required InboxStagingRepository repo,
    required InboxStagingEntry entry,
    required RecoveredInboxReplayOutcome outcome,
    required String committedEvent,
    required String retryableEvent,
    required String rejectedEvent,
    required String quarantinedEvent,
  }) async {
    switch (outcome.disposition) {
      case RecoveredInboxChatDisposition.committed:
        await repo.deleteEntry(entry.entryId);
        emitFlowEvent(
          layer: 'FL',
          event: committedEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return true;
      case RecoveredInboxChatDisposition.retryable:
        if (entry.attemptCount >= maxInboxReplayAttempts) {
          await _quarantineRecoveredInboxEntry(
            repo: repo,
            entry: entry,
            quarantinedEvent: quarantinedEvent,
            reasonCode: 'attempt_cap_exceeded',
            reasonDetail:
                'still ${outcome.reasonCode} after ${entry.attemptCount} attempts',
          );
          return false;
        }
        await repo.markRetryable(
          entry.entryId,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        emitFlowEvent(
          layer: 'FL',
          event: retryableEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return false;
      case RecoveredInboxChatDisposition.rejected:
        await repo.markRejected(
          entry.entryId,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        emitFlowEvent(
          layer: 'FL',
          event: rejectedEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return false;
      case RecoveredInboxChatDisposition.quarantined:
        await _quarantineRecoveredInboxEntry(
          repo: repo,
          entry: entry,
          quarantinedEvent: quarantinedEvent,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        return false;
    }
  }

  Future<
    ({
      int replayed,
      int staged,
      bool hasMore,
      bool retrieveSucceeded,
      String? failureReason,
      int retrieveMs,
      int ackMs,
      int replayMs,
    })
  >
  _retrievePendingInboxPage({required String toPeerId, int? timeoutMs}) async {
    final repo = _inboxStagingRepository;

    final retrieveSw = Stopwatch()..start();
    Map<String, dynamic> response;
    try {
      response = await _port.retrievePendingInbox(
        timeoutMs: timeoutMs,
        custodyContract: ackOrExpiryInboxCustodyContract,
      );
    } catch (e) {
      retrieveSw.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
        details: {
          'reasonCode': 'retrieve_pending_exception',
          'error': e.toString(),
        },
      );
      return (
        replayed: 0,
        staged: 0,
        hasMore: false,
        retrieveSucceeded: false,
        failureReason: e.toString(),
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }
    retrieveSw.stop();

    if (response['ok'] != true) {
      final failureReason =
          response['errorMessage']?.toString() ??
          response['errorCode']?.toString() ??
          'retrieve_pending_failed';
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
        details: {
          'reasonCode': 'retrieve_pending_error',
          'errorMessage': response['errorMessage']?.toString(),
        },
      );
      return (
        replayed: 0,
        staged: 0,
        hasMore: false,
        retrieveSucceeded: false,
        failureReason: failureReason,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }
    if (response['custodyContract'] != ackOrExpiryInboxCustodyContract) {
      const failureReason = 'custody_proof_missing_or_invalid';
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
        details: const {
          'reasonCode': failureReason,
          'errorMessage': failureReason,
        },
      );
      return (
        replayed: 0,
        staged: 0,
        hasMore: true,
        retrieveSucceeded: false,
        failureReason: failureReason,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final rawMessages =
        (response['messages'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    if (rawMessages.isEmpty) {
      return (
        replayed: 0,
        staged: 0,
        hasMore: response['hasMore'] == true,
        retrieveSucceeded: true,
        failureReason: null,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final entries = <InboxStagingEntry>[];
    var skippedMalformed = 0;
    for (final raw in rawMessages) {
      final entry = _stagingEntryFromRawInboxMessage(raw, toPeerId);
      if (entry == null) {
        skippedMalformed++;
        continue;
      }
      entries.add(entry);
    }
    if (skippedMalformed > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGE_SKIPPED_MALFORMED',
        details: {
          'rawCount': rawMessages.length,
          'stagedCount': entries.length,
          'skippedCount': skippedMalformed,
        },
      );
    }
    if (entries.isEmpty) {
      if (skippedMalformed > 0) {
        return (
          replayed: 0,
          staged: 0,
          hasMore: true,
          retrieveSucceeded: false,
          failureReason: 'malformed_inbox_rows:$skippedMalformed',
          retrieveMs: retrieveSw.elapsedMilliseconds,
          ackMs: 0,
          replayMs: 0,
        );
      }
      return (
        replayed: 0,
        staged: 0,
        hasMore: response['hasMore'] == true,
        retrieveSucceeded: true,
        failureReason: null,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final ackableEntryIds = (await repo.stageEntries(entries)).toList();
    final protectedRelayAckableEntryIds = <String>{};
    for (final entry in entries) {
      if (ackableEntryIds.contains(entry.entryId) ||
          !_isProtectedGroupEnvelopeType(entry.messageType)) {
        continue;
      }
      final existing = await repo.getEntry(entry.entryId);
      if (existing != null &&
          existing.status == 'protected_ack_pending' &&
          _sameProtectedRelayEntry(existing, entry)) {
        ackableEntryIds.add(entry.entryId);
        protectedRelayAckableEntryIds.add(entry.entryId);
      }
    }
    if (ackableEntryIds.isNotEmpty &&
        !await _port.allowsAccountNetworkSideEffects(
          'p2p_inbox_ack_after_stage',
        )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_ACK_SKIPPED_GATED',
        details: {'requested': ackableEntryIds.length},
      );
      return (
        replayed: 0,
        staged: ackableEntryIds.length,
        hasMore: true,
        retrieveSucceeded: false,
        failureReason: 'account_network_side_effects_blocked',
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }
    final replaySw = Stopwatch()..start();
    final replayed = ackableEntryIds.isEmpty
        ? 0
        : await _replayStagedInboxEntries(
            entryIds: ackableEntryIds,
            protectedRelayAckableEntryIds: protectedRelayAckableEntryIds,
          );
    replaySw.stop();

    final relayAckableEntryIds = ackableEntryIds
        .where((entryId) {
          final entry = entries
              .where((value) => value.entryId == entryId)
              .first;
          final protected = _isProtectedGroupEnvelopeType(entry.messageType);
          return !protected || protectedRelayAckableEntryIds.contains(entryId);
        })
        .toList(growable: false);

    final ackSw = Stopwatch();
    String? ackFailureReason;
    if (relayAckableEntryIds.isNotEmpty) {
      ackSw.start();
      try {
        final ackResponse = await _port.ackInbox(
          entryIds: relayAckableEntryIds,
          custodyContract: ackOrExpiryInboxCustodyContract,
        );
        if (ackResponse['ok'] != true) {
          ackFailureReason =
              ackResponse['errorMessage']?.toString() ??
              ackResponse['errorCode']?.toString() ??
              'inbox_ack_failed';
        } else if (ackResponse['custodyContract'] !=
            ackOrExpiryInboxCustodyContract) {
          ackFailureReason = 'custody_proof_missing_or_invalid';
        } else {
          final acked = (ackResponse['acked'] as num?)?.toInt();
          if (acked != relayAckableEntryIds.length) {
            ackFailureReason =
                'inbox_ack_incomplete:${acked ?? 'missing'}/'
                '${relayAckableEntryIds.length}';
          }
        }
        emitFlowEvent(
          layer: 'FL',
          event: ackFailureReason == null
              ? 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS'
              : 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_ERROR',
          details: {
            'requested': relayAckableEntryIds.length,
            'acked': ackResponse['acked'],
            'errorMessage': ?ackFailureReason,
          },
        );
      } catch (e) {
        ackFailureReason = e.toString();
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_EXCEPTION',
          details: {
            'requested': relayAckableEntryIds.length,
            'error': e.toString(),
          },
        );
      }
      ackSw.stop();
    }

    if (ackFailureReason == null && relayAckableEntryIds.isNotEmpty) {
      for (final entryId in protectedRelayAckableEntryIds) {
        if (relayAckableEntryIds.contains(entryId)) {
          await repo.deleteEntry(entryId);
        }
      }
    }

    var protectedPending = false;
    for (final entry in entries) {
      final isProtected = _isProtectedGroupEnvelopeType(entry.messageType);
      if (isProtected &&
          !relayAckableEntryIds.contains(entry.entryId) &&
          await repo.getEntry(entry.entryId) != null) {
        protectedPending = true;
        break;
      }
    }
    final pageFailureReason =
        ackFailureReason ??
        (protectedPending ? 'protected_group_handler_not_terminal' : null) ??
        (skippedMalformed > 0
            ? 'malformed_inbox_rows:$skippedMalformed'
            : null);

    return (
      replayed: replayed,
      staged: ackableEntryIds.length,
      hasMore: pageFailureReason != null || response['hasMore'] == true,
      retrieveSucceeded: pageFailureReason == null,
      failureReason: pageFailureReason,
      retrieveMs: retrieveSw.elapsedMilliseconds,
      ackMs: ackSw.elapsedMilliseconds,
      replayMs: replaySw.elapsedMilliseconds,
    );
  }

  Future<DirectInboxDrainOutcome> _drainOfflineInbox({
    bool waitForAllPages = false,
  }) async {
    while (true) {
      final backgroundDrain = _backgroundDrainInProgress;
      if (backgroundDrain != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_DRAIN_COALESCED',
          details: {
            'waitForAllPages': waitForAllPages,
            'owner': 'background_continuation',
          },
        );
        if (!waitForAllPages) {
          return const DirectInboxDrainOutcome(
            isSuccessful: false,
            hasMore: true,
            failureReason: 'continuation_in_progress',
          );
        }
        return _verifyFullDrainOutcome(await backgroundDrain);
      }

      final inFlight = _drainInProgress;
      if (inFlight == null) break;
      final inFlightCoversUs =
          _drainInProgressWaitsAllPages || !waitForAllPages;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_DRAIN_COALESCED',
        details: {'waitForAllPages': waitForAllPages},
      );
      final outcome = await inFlight.future;
      if (inFlightCoversUs) return outcome;
      if (outcome.isSuccessful && !outcome.hasMore) {
        return _verifyFullDrainOutcome(outcome);
      }
    }

    final completer = Completer<DirectInboxDrainOutcome>();
    _drainInProgress = completer;
    _drainInProgressWaitsAllPages = waitForAllPages;
    var outcome = const DirectInboxDrainOutcome(
      isSuccessful: false,
      hasMore: true,
      failureReason: 'drain_exception',
    );
    try {
      outcome = await _drainOfflineInboxDurably(
        waitForAllPages: waitForAllPages,
      );
      if (waitForAllPages) {
        outcome = await _verifyFullDrainOutcome(outcome);
      }
    } catch (e) {
      outcome = DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: e.toString(),
      );
    } finally {
      _drainInProgress = null;
      _drainInProgressWaitsAllPages = false;
      completer.complete(outcome);
    }
    return outcome;
  }

  Future<DirectInboxDrainOutcome> _verifyFullDrainOutcome(
    DirectInboxDrainOutcome outcome,
  ) async {
    if (!outcome.isSuccessful || outcome.hasMore) return outcome;
    try {
      final recoverable = await _inboxStagingRepository.getRecoverableEntries(
        limit: 1,
      );
      if (recoverable.isEmpty) return outcome;
      return const DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'staged_replay_pending',
      );
    } catch (error) {
      return DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'staged_replay_check_failed:${error.runtimeType}',
      );
    }
  }

  void _trackBackgroundDrain(Future<DirectInboxDrainOutcome> drain) {
    _backgroundDrainInProgress = drain;
    unawaited(
      drain.whenComplete(() {
        if (identical(_backgroundDrainInProgress, drain)) {
          _backgroundDrainInProgress = null;
        }
      }),
    );
  }

  Future<DirectInboxDrainOutcome> _continueDrainingOfflineInboxDurably({
    required String toPeerId,
    required int totalReplayed,
    required int totalStaged,
  }) async {
    var replayed = totalReplayed;
    var staged = totalStaged;

    try {
      for (var page = 1; page < _maxInboxPages; page++) {
        if (!await _port.allowsAccountNetworkSideEffects(
          'p2p_drain_offline_inbox_page',
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_GATED',
            details: {'page': page + 1, 'staged': staged},
          );
          return const DirectInboxDrainOutcome(
            isSuccessful: false,
            hasMore: true,
            failureReason: 'account_network_side_effects_blocked',
          );
        }
        final result = await _retrievePendingInboxPage(toPeerId: toPeerId);
        replayed += result.replayed;
        staged += result.staged;

        if (!result.retrieveSucceeded) {
          return DirectInboxDrainOutcome(
            isSuccessful: false,
            hasMore: true,
            failureReason: result.failureReason ?? 'retrieve_pending_failed',
          );
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_PAGE',
          details: {'page': page + 1, 'staged': staged, 'replayed': replayed},
        );
        if (!result.hasMore) {
          return const DirectInboxDrainOutcome(
            isSuccessful: true,
            hasMore: false,
          );
        }
        if (result.staged == 0) {
          return const DirectInboxDrainOutcome(
            isSuccessful: false,
            hasMore: true,
            failureReason: 'page_no_progress',
          );
        }
      }

      return const DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'page_cap_reached',
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_EXCEPTION',
        details: {'error': e.toString()},
      );
      return DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: e.toString(),
      );
    } finally {
      if (staged > 0 || replayed > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_BACKGROUND_COMPLETE',
          details: {'staged': staged, 'replayed': replayed},
        );
      }
    }
  }

  Future<DirectInboxDrainOutcome> _drainOfflineInboxDurably({
    bool waitForAllPages = false,
  }) async {
    try {
      final toPeerId = _port.readNodeState().peerId ?? '';
      final replayExistingSw = Stopwatch()..start();
      final replayedExisting = await _replayStagedInboxEntries();
      replayExistingSw.stop();
      final firstPage = await _retrievePendingInboxPage(
        toPeerId: toPeerId,
        timeoutMs: _foregroundInboxTimeout.inMilliseconds,
      );

      final totalReplayed = replayedExisting + firstPage.replayed;
      final totalStaged = firstPage.staged;
      DirectInboxDrainOutcome outcome;

      if (!firstPage.retrieveSucceeded) {
        outcome = DirectInboxDrainOutcome(
          isSuccessful: false,
          hasMore: true,
          failureReason: firstPage.failureReason ?? 'retrieve_pending_failed',
        );
      } else if (firstPage.hasMore && totalStaged > 0) {
        final continuation = _continueDrainingOfflineInboxDurably(
          toPeerId: toPeerId,
          totalReplayed: totalReplayed,
          totalStaged: totalStaged,
        );
        if (waitForAllPages) {
          outcome = await continuation;
        } else {
          _trackBackgroundDrain(continuation);
          outcome = const DirectInboxDrainOutcome(
            isSuccessful: false,
            hasMore: true,
            failureReason: 'continuation_scheduled',
          );
        }
      } else if (firstPage.hasMore) {
        outcome = const DirectInboxDrainOutcome(
          isSuccessful: false,
          hasMore: true,
          failureReason: 'page_no_progress',
        );
      } else {
        outcome = const DirectInboxDrainOutcome(
          isSuccessful: true,
          hasMore: false,
        );
      }

      if (replayedExisting > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_REPLAY_RECOVERED',
          details: {'count': replayedExisting},
        );
      }

      if (totalReplayed > 0 || totalStaged > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
          details: {
            'staged': totalStaged,
            'replayed': totalReplayed,
            'note': 'relay entries were staged locally before ack',
            'retrieveMs': firstPage.retrieveMs,
            'ackMs': firstPage.ackMs,
            'replayMs':
                replayExistingSw.elapsedMilliseconds + firstPage.replayMs,
          },
        );
      }
      if (firstPage.retrieveSucceeded &&
          (!waitForAllPages || outcome.isSuccessful)) {
        _port.recordSuccessfulInboxProof(
          source: 'drain_offline_inbox',
          trigger: 'system_action',
        );
      } else {
        _port.recordInboxProofFailure(
          source: 'drain_offline_inbox',
          trigger: 'system_action',
          failureReason: outcome.failureReason,
        );
      }
      return outcome;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_EXCEPTION',
        details: {'error': e.toString()},
      );
      _port.recordInboxProofFailure(
        source: 'drain_offline_inbox',
        trigger: 'system_action',
        failureReason: e.toString(),
      );
      return DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: e.toString(),
      );
    }
  }

  Future<LanInboundDecision> _commitInboundLanChatMessage(
    LocalChatMessage localMsg, {
    required String? nonce,
  }) async {
    _port.recordTransport('wifi');
    emitFlowEvent(
      layer: 'FL',
      event: 'MSG_RECEIVED_TRANSPORT',
      details: {
        'from': localMsg.from.length > 10
            ? localMsg.from.substring(0, 10)
            : localMsg.from,
        'transport': 'wifi',
      },
    );

    String? envelopeType;
    try {
      final decoded = jsonDecode(localMsg.content);
      if (decoded is Map<String, dynamic>) {
        envelopeType = decoded['type']?.toString();
      }
    } catch (_) {
      envelopeType = null;
    }

    final message = ChatMessage(
      from: localMsg.from,
      to: localMsg.to,
      content: localMsg.content,
      timestamp: localMsg.timestamp.toUtc().toIso8601String(),
      isIncoming: localMsg.isIncoming,
      transport: 'wifi',
    );

    if (!await _port.allowsAccountNetworkSideEffects(
      'p2p_inbound_message',
      peerId: localMsg.to.trim().isEmpty ? null : localMsg.to,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': 'p2p_inbound_message',
          'family': 'direct_chat',
          'from': localMsg.from.length > 10
              ? localMsg.from.substring(0, 10)
              : localMsg.from,
          'envelopeType': ?envelopeType,
        },
      );
      return LanInboundDecision.rejected('account_migration_blocked');
    }

    final safeNonce = nonce?.trim();
    final ReplayRecoveredInboxChatMessage? lanReplay;
    switch (envelopeType) {
      case 'chat_message':
        lanReplay =
            _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        break;
      case 'message_reaction':
        lanReplay = _replayRecoveredInboxReaction;
        break;
      case 'message_deletion':
        lanReplay = _replayRecoveredInboxMessageDeletion;
        break;
      default:
        lanReplay = null;
        break;
    }
    if (lanReplay == null) {
      _port.emitIncomingMessage(message);
      return const LanInboundDecision.accepted();
    }
    if (safeNonce == null || safeNonce.isEmpty) {
      if (envelopeType == 'message_reaction') {
        final outcome = await _replayUnstagedReaction(
          message,
          reason: 'lan_missing_nonce',
        );
        if (outcome?.disposition == RecoveredInboxChatDisposition.committed) {
          return const LanInboundDecision.committed();
        }
        if (outcome != null &&
            outcome.disposition != RecoveredInboxChatDisposition.retryable) {
          return const LanInboundDecision.accepted();
        }
        return LanInboundDecision.rejected(
          outcome?.reasonCode ?? 'reaction_replay_error',
        );
      }
      _port.emitIncomingMessage(message);
      return const LanInboundDecision.accepted();
    }

    final entry = _stagingEntryFromLanMessage(
      localMsg,
      nonce: safeNonce,
      messageType: envelopeType,
    );
    if (entry == null) {
      if (envelopeType == 'message_reaction') {
        final outcome = await _replayUnstagedReaction(
          message,
          reason: 'lan_stage_entry_unavailable',
        );
        return outcome?.disposition == RecoveredInboxChatDisposition.committed
            ? const LanInboundDecision.committed()
            : LanInboundDecision.rejected(
                outcome?.reasonCode ?? 'reaction_replay_error',
              );
      }
      _port.emitIncomingMessage(message);
      return const LanInboundDecision.accepted();
    }

    try {
      await _inboxStagingRepository.stageEntries([entry]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGE_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
      if (envelopeType == 'message_reaction') {
        final outcome = await _replayUnstagedReaction(
          message,
          reason: 'lan_stage_error',
        );
        if (outcome?.disposition == RecoveredInboxChatDisposition.committed) {
          return const LanInboundDecision.committed();
        }
        if (outcome != null &&
            outcome.disposition != RecoveredInboxChatDisposition.retryable) {
          return const LanInboundDecision.accepted();
        }
        return LanInboundDecision.rejected(
          outcome?.reasonCode ?? 'reaction_replay_error',
        );
      }
      _port.emitIncomingMessage(message);
      return LanInboundDecision.rejected('staging_error');
    }

    unawaited(_replayDurablyStagedLanChat(message, entry: entry));
    return const LanInboundDecision.committed();
  }

  Future<bool> _handleMessageReceived(ChatMessage message) async {
    String? envelopeType;
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map<String, dynamic>) {
        envelopeType = decoded['type'] as String?;
      }
    } catch (_) {
      envelopeType = null;
    }
    if (!await _port.allowsAccountNetworkSideEffects(
      'p2p_inbound_message',
      peerId: message.to.trim().isEmpty ? null : message.to,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': 'p2p_inbound_message',
          'family': 'direct_chat',
          'from': message.from.length > 10
              ? message.from.substring(0, 10)
              : message.from,
          'envelopeType': ?envelopeType,
        },
      );
      return false;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_MESSAGE_RECEIVED',
      details: {
        'from': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'isIncoming': message.isIncoming,
        'contentLength': message.content.length,
        'envelopeType': envelopeType,
        'streamClosed': _port.isMessageStreamClosed(),
      },
    );
    logChatTransportIncoming(
      fromPeerId: message.from,
      toPeerId: message.to,
      contentLength: message.content.length,
      isIncoming: message.isIncoming,
      envelopeType: envelopeType,
    );

    if (_shouldDurablyStageDeferredDirectChat(
      message,
      envelopeType: envelopeType,
    )) {
      final entry = _stagingEntryFromDirectMessage(
        message,
        messageType: envelopeType,
      );
      if (entry != null) {
        unawaited(_processDurablyStagedDirectChat(message, entry: entry));
        return true;
      }
    }

    if (message.isIncoming &&
        envelopeType == 'message_reaction' &&
        _replayRecoveredInboxReaction != null) {
      await _replayUnstagedReaction(message, reason: 'direct_missing_nonce');
      return true;
    }

    _port.emitIncomingMessage(message);
    return true;
  }

  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final outcome = await storeInInboxDetailed(
      toPeerId,
      message,
      timeoutMs: timeoutMs,
    );
    return outcome.accepted;
  }

  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) => _storeInInboxDetailed(toPeerId, message, timeoutMs: timeoutMs);

  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) => _storeInInboxDetailed(
    toPeerId,
    message,
    timeoutMs: timeoutMs,
    custodyKind: custodyKind,
  );

  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) => _storeInInboxDetailed(
    toPeerId,
    message,
    timeoutMs: timeoutMs,
    custodyKind: AckCustodyKind.directTextV108,
    custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
  );

  Future<InboxStoreOutcome> storeInGroupContentExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) => _storeInInboxDetailed(
    toPeerId,
    message,
    timeoutMs: timeoutMs,
    custodyKind: AckCustodyKind.groupContentV1,
    custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
  );

  Future<InboxStoreOutcome> _storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
    AckCustodyKind? custodyKind,
    int? custodyExpiresAtOrBeforeMs,
  }) async {
    if (custodyExpiresAtOrBeforeMs != null &&
        (custodyExpiresAtOrBeforeMs <= 0 ||
            (custodyKind != AckCustodyKind.directTextV108 &&
                custodyKind != AckCustodyKind.groupContentV1))) {
      return const InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'CUSTODY_INELIGIBLE',
        errorMessage:
            'Expiry-bounded custody requires an eligible kind and positive ceiling',
      );
    }
    if (!await _port.allowsAccountNetworkSideEffects('p2p_store_inbox')) {
      return const InboxStoreOutcome(status: InboxStoreStatus.failed);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_STORE_BEGIN',
      details: {'toPeerId': toPeerId},
    );

    String? wakeToken;
    final receivedWakeTokenStore = _receivedWakeTokenStore;
    if (receivedWakeTokenStore != null) {
      wakeToken = (await receivedWakeTokenStore.readTokenFor(toPeerId))?['tok'];
    }

    var bridgeTimeoutMs = timeoutMs;
    if (wakeToken != null &&
        wakeToken.isNotEmpty &&
        !_port.readNodeState().isStarted) {
      final readinessStopwatch = Stopwatch()..start();
      final totalBudgetMs = timeoutMs ?? 15000;
      if (totalBudgetMs <= 0) {
        return _inboxStoreReadinessFailure('startup_budget_exhausted');
      }
      final readinessBudgetMs = totalBudgetMs < 3000 ? totalBudgetMs : 3000;
      final started = await _waitForNodeStart(
        Duration(milliseconds: readinessBudgetMs),
      );
      final remainingMs =
          totalBudgetMs - readinessStopwatch.elapsedMilliseconds;
      if (!started || remainingMs <= 0) {
        return _inboxStoreReadinessFailure(
          started ? 'startup_budget_exhausted' : 'startup_not_ready',
        );
      }
      bridgeTimeoutMs = remainingMs;
    }

    try {
      final response = await _port.storeInbox(
        toPeerId: toPeerId,
        message: message,
        timeoutMs: bridgeTimeoutMs,
        wakeToken: wakeToken,
        custodyContract: custodyKind == null
            ? null
            : ackOrExpiryInboxCustodyContract,
        custodyKind: custodyKind?.wireValue,
        custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
      );
      var outcome = custodyKind == null
          ? InboxStoreOutcome.fromBridgeResponse(response)
          : InboxStoreOutcome.fromAckOrExpiryBridgeResponse(response);
      if (custodyExpiresAtOrBeforeMs != null &&
          (!outcome.ackOrExpiryAccepted ||
              outcome.expiresAtMs != custodyExpiresAtOrBeforeMs)) {
        outcome = InboxStoreOutcome(
          status: InboxStoreStatus.failed,
          errorCode: 'CUSTODY_EXPIRY_PROOF_MISSING_OR_INVALID',
          errorMessage: outcome.errorMessage,
          storeStatus: outcome.storeStatus,
          expiresAtMs: outcome.expiresAtMs,
          occupancy: outcome.occupancy,
          capacity: outcome.capacity,
          custodyContract: outcome.custodyContract,
        );
      }
      final wakeTokenObserver = _acceptedInboxWakeTokenHashObserver;
      if (outcome.accepted &&
          wakeTokenObserver != null &&
          wakeToken != null &&
          wakeToken.isNotEmpty) {
        try {
          wakeTokenObserver(
            toPeerIdSha256: sha256.convert(utf8.encode(toPeerId)).toString(),
            messageSha256: sha256.convert(utf8.encode(message)).toString(),
            wakeTokenSha256: sha256.convert(utf8.encode(wakeToken)).toString(),
          );
        } on Object {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_WAKE_TOKEN_E2E_OBSERVER_ERROR',
            details: const <String, Object?>{},
          );
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: outcome.accepted
            ? 'P2P_SERVICE_INBOX_STORE_SUCCESS'
            : 'P2P_SERVICE_INBOX_STORE_ERROR',
        details: {
          'toPeerId': toPeerId,
          'status': outcome.status.name,
          if (outcome.errorCode != null) 'errorCode': outcome.errorCode,
          if (outcome.expiresAtMs != null) 'expiresAtMs': outcome.expiresAtMs,
        },
      );
      return outcome;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STORE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> _waitForNodeStart(Duration timeout) async {
    if (_port.readNodeState().isStarted) return true;

    final ready = Completer<bool>();
    late final StreamSubscription<NodeState> subscription;
    subscription = _port.nodeStateStream.listen(
      (state) {
        if (state.isStarted && !ready.isCompleted) {
          ready.complete(true);
        }
      },
      onError: (_) {
        if (!ready.isCompleted) ready.complete(false);
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete(false);
      },
    );
    if (_port.readNodeState().isStarted && !ready.isCompleted) {
      ready.complete(true);
    }
    try {
      return await ready.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await subscription.cancel();
    }
  }

  InboxStoreOutcome _inboxStoreReadinessFailure(String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_STORE_ERROR',
      details: {
        'status': InboxStoreStatus.failed.name,
        'errorCode': 'INBOX_STARTUP_NOT_READY',
        'reason': reason,
      },
    );
    return InboxStoreOutcome(
      status: InboxStoreStatus.failed,
      errorCode: 'INBOX_STARTUP_NOT_READY',
      errorMessage: reason,
    );
  }

  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async {
    if (!await _port.allowsAccountNetworkSideEffects('p2p_retrieve_inbox')) {
      return const [];
    }

    final details = <String, dynamic>{};
    if (timeoutMs != null) {
      details['timeoutMs'] = timeoutMs;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_RETRIEVE_BEGIN',
      details: details,
    );

    try {
      final response = await _port.retrieveInbox(timeoutMs: timeoutMs);
      if (response['ok'] == true) {
        final messages =
            (response['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        final hasMore = response['hasMore'] == true;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_RETRIEVE_SUCCESS',
          details: {
            'count': messages.length,
            'hasMore': hasMore,
            'note': 'server deleted retrieved messages from memory',
          },
        );
        _port.recordSuccessfulInboxProof(
          source: 'retrieve_inbox',
          trigger: 'user_action',
        );
        return messages;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_ERROR',
        details: {'errorMessage': response['errorMessage']},
      );
      _port.recordInboxProofFailure(
        source: 'retrieve_inbox',
        trigger: 'user_action',
        failureReason: response['errorMessage']?.toString(),
      );
      return [];
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_EXCEPTION',
        details: {'error': e.toString()},
      );
      _port.recordInboxProofFailure(
        source: 'retrieve_inbox',
        trigger: 'user_action',
        failureReason: e.toString(),
      );
      return [];
    }
  }

  Future<void> drainOfflineInbox() async {
    if (!_port.readNodeState().isStarted) {
      _scheduleStartupDrain(waitForAllPages: false);
      return;
    }
    if (!await _port.allowsAccountNetworkSideEffects(
      'p2p_drain_offline_inbox',
    )) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN',
      details: {},
    );
    await _drainOfflineInbox();
  }

  Future<DirectInboxDrainOutcome> drainOfflineInboxFully() async {
    if (!_port.readNodeState().isStarted) {
      _scheduleStartupDrain(waitForAllPages: true);
      return const DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'node_not_started',
      );
    }
    if (!await _port.allowsAccountNetworkSideEffects(
      'p2p_drain_offline_inbox_full',
    )) {
      return const DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'account_network_side_effects_blocked',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_FULL_BEGIN',
      details: {},
    );
    return _drainOfflineInbox(waitForAllPages: true);
  }

  void _scheduleStartupDrain({required bool waitForAllPages}) {
    final wasScheduled = _pendingStartupDrain;
    _pendingStartupDrain = true;
    if (waitForAllPages) {
      _pendingStartupDrainWaitForAllPages = true;
    }
    if (!wasScheduled) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED',
        details: {'waitForAllPages': _pendingStartupDrainWaitForAllPages},
      );
    }
  }

  Future<void>? onNodeStateTransition(NodeState previous, NodeState current) {
    if (previous.isStarted || !current.isStarted || !_pendingStartupDrain) {
      return null;
    }
    final waitForAllPages = _pendingStartupDrainWaitForAllPages;
    _pendingStartupDrain = false;
    _pendingStartupDrainWaitForAllPages = false;
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED',
      details: {'waitForAllPages': waitForAllPages},
    );
    if (waitForAllPages) {
      return drainOfflineInboxFully().then<void>((_) {});
    }
    return drainOfflineInbox();
  }

  Future<int> countNeedsAttentionInboxEntries() async {
    try {
      return await _inboxStagingRepository.countNeedsAttentionEntries();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_NEEDS_ATTENTION_COUNT_ERROR',
        details: {'error': e.toString()},
      );
      return 0;
    }
  }
}
