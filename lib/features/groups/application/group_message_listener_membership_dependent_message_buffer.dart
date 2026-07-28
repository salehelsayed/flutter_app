part of 'group_message_listener.dart';

const _maxPendingMembershipDependentMessagesPerGroup = 50;

class _PendingMembershipDependentMessage {
  _PendingMembershipDependentMessage({
    required this.data,
    required this.senderPeerId,
    required this.messageId,
    required this.receivedAt,
    this.durableId,
  });

  final Map<String, dynamic> data;
  final String senderPeerId;
  final String? messageId;
  final DateTime receivedAt;
  final String? durableId;
}

typedef _ReplayMembershipDependentMessage =
    Future<void> Function(
      Map<String, dynamic> data, {
      required GroupMessageRepository msgRepo,
      required bool membershipPhaseHeld,
    });

typedef _RequestMembershipDependentMessageKeyRepair =
    Future<void> Function(GroupMessage message);

class _GroupMembershipDependentMessageBuffer {
  _GroupMembershipDependentMessageBuffer({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    required GroupPendingMembershipMessageRepository?
    pendingMembershipMessageRepo,
    required bool Function() isStoppingOrDisposed,
    required _ReplayMembershipDependentMessage replayMessage,
    required _RequestMembershipDependentMessageKeyRepair requestKeyRepair,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _pendingMembershipMessageRepo = pendingMembershipMessageRepo,
       _isStoppingOrDisposed = isStoppingOrDisposed,
       _replayMessage = replayMessage,
       _requestKeyRepair = requestKeyRepair;

  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final GroupPendingMembershipMessageRepository? _pendingMembershipMessageRepo;
  final bool Function() _isStoppingOrDisposed;
  final _ReplayMembershipDependentMessage _replayMessage;
  final _RequestMembershipDependentMessageKeyRepair _requestKeyRepair;
  final Map<String, List<_PendingMembershipDependentMessage>>
  _pendingMembershipDependentMessagesByGroup = {};

  Future<void> flushPendingMembershipDependentMessagesForGroup(
    String groupId, {
    GroupMessageRepository? msgRepoOverride,
  }) async {
    final members = await _groupRepo.getMembers(groupId);
    if (members.isEmpty) return;
    await _flushMembershipDependentMessages(
      groupId: groupId,
      memberPeerIds: members.map((member) => member.peerId),
      msgRepo: msgRepoOverride ?? _msgRepo,
    );
  }

  Future<bool> _shouldBufferMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required GroupMessageRepository msgRepo,
    required Map<String, dynamic> data,
  }) async {
    if (senderId.isEmpty) return false;
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) return false;
    if (await _groupRepo.getMember(groupId, senderId) != null) return false;
    final incomingKeyEpoch = data['keyEpoch'];
    final latestKey = incomingKeyEpoch is int && incomingKeyEpoch > 0
        ? await _groupRepo.getLatestKey(groupId)
        : null;
    if (latestKey != null &&
        latestKey.keyGeneration > 0 &&
        incomingKeyEpoch is int &&
        incomingKeyEpoch < latestKey.keyGeneration) {
      return false;
    }
    final membershipWatermark = group.lastMembershipEventAt?.toUtc();
    final messageTimestamp = DateTime.tryParse(
      data['timestamp'] as String? ?? '',
    )?.toUtc();
    final removalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (removalCutoff != null &&
        (messageTimestamp == null ||
            messageTimestamp.isBefore(removalCutoff))) {
      return false;
    }
    if (membershipWatermark != null &&
        messageTimestamp != null &&
        !messageTimestamp.isAfter(membershipWatermark)) {
      return false;
    }
    if (messageId != null &&
        messageId.isNotEmpty &&
        await msgRepo.getMessage(messageId) != null) {
      return false;
    }
    final text = data['text'];
    final isSystemPayload = text is String && text.startsWith('{"__sys":');
    return !isSystemPayload;
  }

  Future<void> _bufferMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required Map<String, dynamic> data,
  }) async {
    final pendingData = Map<String, dynamic>.from(data);
    final receivedAt = DateTime.now().toUtc();
    final durable = await _saveDurableMembershipDependentMessage(
      groupId: groupId,
      senderId: senderId,
      messageId: messageId,
      data: pendingData,
      receivedAt: receivedAt,
    );
    final queue = _pendingMembershipDependentMessagesByGroup.putIfAbsent(
      groupId,
      () => <_PendingMembershipDependentMessage>[],
    );
    if (messageId != null && messageId.isNotEmpty) {
      queue.removeWhere((pending) => pending.messageId == messageId);
    }
    queue.add(
      _PendingMembershipDependentMessage(
        data: pendingData,
        senderPeerId: senderId,
        messageId: messageId,
        receivedAt: receivedAt,
        durableId: durable?.id,
      ),
    );
    while (queue.length > _maxPendingMembershipDependentMessagesPerGroup) {
      queue.removeAt(0);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_BUFFERED',
      details: {
        'groupId': _membershipFlowId(groupId),
        'senderId': _membershipFlowId(senderId),
        if (messageId != null && messageId.isNotEmpty)
          'messageId': _membershipFlowId(messageId),
        'queueDepth': queue.length,
      },
    );
  }

  Future<GroupPendingMembershipMessage?>
  _saveDurableMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required Map<String, dynamic> data,
    required DateTime receivedAt,
  }) async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null) return null;
    final payloadJson = jsonEncode(data);
    final pending = GroupPendingMembershipMessage(
      id: groupPendingMembershipMessageId(
        groupId: groupId,
        senderPeerId: senderId,
        messageId: messageId,
        receivedAt: receivedAt,
        payloadJson: payloadJson,
      ),
      groupId: groupId,
      senderPeerId: senderId,
      messageId: messageId,
      payloadJson: payloadJson,
      receivedAt: receivedAt,
      createdAt: receivedAt,
      updatedAt: receivedAt,
    );
    final saved = await pendingRepo.savePendingMessage(pending);
    await pendingRepo.pruneGroup(
      groupId,
      maxRows: _maxPendingMembershipDependentMessagesPerGroup,
    );
    return saved;
  }

  Future<void> _bufferPersistedMembershipDependentMessage(
    GroupMessage message,
  ) async {
    if (message.id.startsWith('sys-')) return;
    if (message.text.isEmpty && message.media.isEmpty) return;

    await _bufferMembershipDependentMessage(
      groupId: message.groupId,
      senderId: message.senderPeerId,
      messageId: message.id,
      data: {
        'groupId': message.groupId,
        'senderId': message.senderPeerId,
        if (message.senderUsername != null)
          'senderUsername': message.senderUsername,
        if (message.transportPeerId != null)
          'transportPeerId': message.transportPeerId,
        if (message.transportPeerId != null)
          'senderDeviceId': message.transportPeerId,
        'keyEpoch': message.keyGeneration,
        'text': message.text,
        'timestamp': message.timestamp.toUtc().toIso8601String(),
        'messageId': message.id,
        if (message.quotedMessageId != null)
          'quotedMessageId': message.quotedMessageId,
        if (message.isForwarded) 'isForwarded': true,
        ...?message.mediaPolicy.toWireExtras(),
        if (message.media.isNotEmpty)
          'media': message.media
              .map((attachment) => attachment.toJson())
              .toList(growable: false),
      },
    );
  }

  Future<void> _flushMembershipDependentMessages({
    required String groupId,
    required Iterable<String> memberPeerIds,
    required GroupMessageRepository msgRepo,
  }) async {
    final allowedSenders = memberPeerIds
        .where((peerId) => peerId.isNotEmpty)
        .toSet();
    if (allowedSenders.isEmpty) return;

    final ready = <_PendingMembershipDependentMessage>[];
    final queue = _pendingMembershipDependentMessagesByGroup[groupId];
    if (queue != null && queue.isNotEmpty) {
      queue.removeWhere((pending) {
        final shouldFlush = allowedSenders.contains(pending.senderPeerId);
        if (shouldFlush) ready.add(pending);
        return shouldFlush;
      });
      if (queue.isEmpty) {
        _pendingMembershipDependentMessagesByGroup.remove(groupId);
      }
    }

    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo != null) {
      final durable = await pendingRepo.getPendingMessagesForGroupAndSenders(
        groupId: groupId,
        senderPeerIds: allowedSenders,
        limit: _maxPendingMembershipDependentMessagesPerGroup,
      );
      for (final pending in durable) {
        ready.add(_pendingMembershipDependentMessageFromDurable(pending));
      }
    }

    if (ready.isEmpty) return;

    final deduped = <String, _PendingMembershipDependentMessage>{};
    for (final pending in ready) {
      final key = _pendingMembershipDependentMessageKey(pending);
      final existing = deduped[key];
      if (existing == null ||
          (existing.durableId == null && pending.durableId != null)) {
        deduped[key] = pending;
      }
    }
    ready
      ..clear()
      ..addAll(deduped.values);
    ready.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSHED',
      details: {'groupId': _membershipFlowId(groupId), 'count': ready.length},
    );
    for (final pending in ready) {
      final text = pending.data['text'] as String? ?? '';
      if (text.startsWith('{"__sys":')) {
        // Listener membership callbacks stay outside the non-reentrant phase;
        // a replayed B3 transition owns its own lock and cuts off later work.
        await _flushMembershipDependentMessageLeaf(
          groupId: groupId,
          pending: pending,
          msgRepo: msgRepo,
          membershipPhaseHeld: false,
        );
        final group = await _groupRepo.getGroup(groupId);
        if (group == null || group.selfRemovedAt != null) return;
        continue;
      }

      final guarded = await runSelfRemovedGroupLifecycleLeaf<void>(
        groupRepo: _groupRepo,
        groupId: groupId,
        action: (_) => _flushMembershipDependentMessageLeaf(
          groupId: groupId,
          pending: pending,
          msgRepo: msgRepo,
          membershipPhaseHeld: true,
        ),
      );
      if (guarded.didRun) {
        await _requestDeferredMembershipMessageKeyRepair(pending, msgRepo);
      }
    }
  }

  Future<void> _flushMembershipDependentMessageLeaf({
    required String groupId,
    required _PendingMembershipDependentMessage pending,
    required GroupMessageRepository msgRepo,
    required bool membershipPhaseHeld,
  }) async {
    if (!await _isExactPendingMembershipMessage(pending)) return;
    if (!membershipPhaseHeld) {
      final currentGroup = await _groupRepo.getGroup(groupId);
      if (currentGroup == null || currentGroup.selfRemovedAt != null) return;
    }
    final member = await _groupRepo.getMember(groupId, pending.senderPeerId);
    final pendingTimestamp = DateTime.tryParse(
      pending.data['timestamp'] as String? ?? '',
    )?.toUtc();
    if (member != null &&
        pendingTimestamp != null &&
        pendingTimestamp.isBefore(member.joinedAt.toUtc())) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_SENDER_BEFORE_JOINED_REJECTED',
        details: {
          'groupId': _membershipFlowId(groupId),
          'senderId': _membershipFlowId(pending.senderPeerId),
          'joinedAt': member.joinedAt.toUtc().toIso8601String(),
        },
      );
      await _deleteDurableMembershipDependentMessage(pending);
      return;
    }
    try {
      await _replayMessage(
        pending.data,
        msgRepo: msgRepo,
        membershipPhaseHeld: membershipPhaseHeld,
      );
      await _deleteDurableMembershipDependentMessage(pending);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSH_ERROR',
        details: {
          'groupId': _membershipFlowId(groupId),
          'senderId': _membershipFlowId(pending.senderPeerId),
          if (pending.messageId != null && pending.messageId!.isNotEmpty)
            'messageId': _membershipFlowId(pending.messageId!),
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _requestDeferredMembershipMessageKeyRepair(
    _PendingMembershipDependentMessage pending,
    GroupMessageRepository msgRepo,
  ) async {
    final messageId = pending.messageId;
    if (messageId == null || messageId.isEmpty) return;
    final stored = await msgRepo.getMessage(messageId);
    if (stored != null) {
      // This runs only after the leaf released its membership phase. The
      // guarded request sender may now acquire its own bounded network phase
      // without nesting the non-reentrant lock.
      await _requestKeyRepair(stored);
    }
  }

  Future<bool> _isExactPendingMembershipMessage(
    _PendingMembershipDependentMessage loaded,
  ) async {
    final durableId = loaded.durableId;
    if (durableId == null || durableId.isEmpty) return true;
    final repo = _pendingMembershipMessageRepo;
    if (repo == null) return false;
    final rows = await repo.getPendingMessagesForGroupAndSenders(
      groupId: loaded.data['groupId'] as String? ?? '',
      senderPeerIds: <String>{loaded.senderPeerId},
      limit: _maxPendingMembershipDependentMessagesPerGroup,
    );
    for (final current in rows) {
      if (current.id == durableId &&
          current.senderPeerId == loaded.senderPeerId &&
          current.messageId == loaded.messageId &&
          current.payloadJson == jsonEncode(loaded.data) &&
          current.receivedAt.toUtc().isAtSameMomentAs(
            loaded.receivedAt.toUtc(),
          )) {
        return true;
      }
    }
    return false;
  }

  _PendingMembershipDependentMessage
  _pendingMembershipDependentMessageFromDurable(
    GroupPendingMembershipMessage pending,
  ) {
    return _PendingMembershipDependentMessage(
      data: jsonDecode(pending.payloadJson) as Map<String, dynamic>,
      senderPeerId: pending.senderPeerId,
      messageId: pending.messageId,
      receivedAt: pending.receivedAt,
      durableId: pending.id,
    );
  }

  String _pendingMembershipDependentMessageKey(
    _PendingMembershipDependentMessage pending,
  ) {
    final messageId = pending.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      return 'message:$messageId';
    }
    final durableId = pending.durableId;
    if (durableId != null && durableId.isNotEmpty) {
      return 'durable:$durableId';
    }
    return 'payload:${jsonEncode(pending.data)}';
  }

  Future<void> _deleteDurableMembershipDependentMessage(
    _PendingMembershipDependentMessage pending,
  ) async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null) return;
    final durableId = pending.durableId;
    if (durableId != null && durableId.isNotEmpty) {
      await pendingRepo.deletePendingMessage(durableId);
      return;
    }
    final messageId = pending.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      final groupId = pending.data['groupId'] as String?;
      if (groupId != null && groupId.isNotEmpty) {
        await pendingRepo.deletePendingMessageByGroupAndMessageId(
          groupId: groupId,
          messageId: messageId,
        );
      }
    }
  }

  Future<void> _flushStartupDurableMembershipDependentMessages() async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null || _isStoppingOrDisposed()) return;
    try {
      final pending = await pendingRepo.getPendingMessages(
        limit: _maxPendingMembershipDependentMessagesPerGroup * 4,
      );
      final readyByGroup = <String, Set<String>>{};
      for (final row in pending) {
        if (_isStoppingOrDisposed()) return;
        final member = await _groupRepo.getMember(
          row.groupId,
          row.senderPeerId,
        );
        if (member == null) continue;
        readyByGroup
            .putIfAbsent(row.groupId, () => <String>{})
            .add(row.senderPeerId);
      }
      for (final entry in readyByGroup.entries) {
        if (_isStoppingOrDisposed()) return;
        await _flushMembershipDependentMessages(
          groupId: entry.key,
          memberPeerIds: entry.value,
          msgRepo: _msgRepo,
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_STARTUP_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<int> _deleteContentMessagesAtOrAfterRemoval({
    required String groupId,
    required String removedPeerId,
    required DateTime? removedAt,
    DateTime? beforeRejoinAt,
    required GroupMessageRepository msgRepo,
  }) async {
    if (removedPeerId.isEmpty || removedAt == null) {
      return 0;
    }
    final normalizedRemovedAt = removedAt.toUtc();
    final messages = <GroupMessage>[];
    const pageSize = 200;
    var offset = 0;
    while (true) {
      final page = await msgRepo.getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      messages.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }

    var deleted = 0;
    final normalizedBeforeRejoinAt = beforeRejoinAt?.toUtc();
    final repairDeletionRepo =
        msgRepo is GroupMembershipRepairDeletionRepository
        ? msgRepo as GroupMembershipRepairDeletionRepository
        : null;
    for (final message in messages) {
      if (message.id.startsWith('sys-')) continue;
      if (message.senderPeerId != removedPeerId) continue;
      final messageTimestamp = message.timestamp.toUtc();
      if (messageTimestamp.isBefore(normalizedRemovedAt)) continue;
      if (normalizedBeforeRejoinAt != null &&
          !messageTimestamp.isBefore(normalizedBeforeRejoinAt)) {
        continue;
      }
      await _bufferPersistedMembershipDependentMessage(message);
      if (repairDeletionRepo != null) {
        await repairDeletionRepo.deleteMessageForMembershipRepair(message.id);
      } else {
        await msgRepo.deleteMessage(message.id);
      }
      deleted++;
    }
    if (deleted > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_REPAIRED',
        details: {
          'groupId': _membershipFlowId(groupId),
          'removedPeerId': _membershipFlowId(removedPeerId),
          'removedAt': normalizedRemovedAt.toIso8601String(),
          'deletedCount': deleted,
        },
      );
    }
    return deleted;
  }
}
