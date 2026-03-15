import 'dart:convert';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';

enum HandleIncomingPostPresenceResult {
  snapshotUpdated,
  notPostPresenceUpdate,
  unknownSender,
  blockedSender,
  invalidPayload,
  staleSnapshot,
}

const Set<String> _inactiveReasons = <String>{
  'sharing_disabled',
  'permission_revoked',
  'services_disabled',
};

Future<(HandleIncomingPostPresenceResult, ContactPresenceSnapshot?)>
handleIncomingPostPresence({
  required ChatMessage message,
  required ContactRepository contactRepo,
  required ContactPresenceSnapshotRepository snapshotRepo,
}) async {
  Map<String, dynamic> json;
  try {
    json = jsonDecode(message.content) as Map<String, dynamic>;
  } catch (_) {
    return (HandleIncomingPostPresenceResult.notPostPresenceUpdate, null);
  }

  if (json['type'] != 'post_presence_update') {
    return (HandleIncomingPostPresenceResult.notPostPresenceUpdate, null);
  }

  final senderPeerId = json['sender_peer_id'] as String?;
  final updatedAt = json['created_at'] as String? ?? message.timestamp;
  if (senderPeerId == null ||
      senderPeerId.isEmpty ||
      senderPeerId != message.from ||
      !_isIso8601(updatedAt)) {
    return (HandleIncomingPostPresenceResult.invalidPayload, null);
  }

  final sender = await contactRepo.getContact(senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostPresenceResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostPresenceResult.blockedSender, null);
  }

  final payload = json['payload'] as Map<String, dynamic>?;
  if (payload == null) {
    return (HandleIncomingPostPresenceResult.invalidPayload, null);
  }

  final statusValue = payload['status'] as String?;
  final capturedAt = payload['captured_at'] as String?;
  if (statusValue == null || !_isIso8601(capturedAt)) {
    return (HandleIncomingPostPresenceResult.invalidPayload, null);
  }

  final status = switch (statusValue) {
    'active' => ContactPresenceSnapshotStatus.active,
    'inactive' => ContactPresenceSnapshotStatus.inactive,
    _ => null,
  };
  if (status == null) {
    return (HandleIncomingPostPresenceResult.invalidPayload, null);
  }

  final snapshot = switch (status) {
    ContactPresenceSnapshotStatus.active => _buildActiveSnapshot(
      peerId: senderPeerId,
      payload: payload,
      capturedAt: capturedAt!,
      updatedAt: updatedAt,
    ),
    ContactPresenceSnapshotStatus.inactive => _buildInactiveSnapshot(
      peerId: senderPeerId,
      payload: payload,
      capturedAt: capturedAt!,
      updatedAt: updatedAt,
    ),
  };
  if (snapshot == null) {
    return (HandleIncomingPostPresenceResult.invalidPayload, null);
  }

  final existing = await snapshotRepo.load(senderPeerId);
  if (existing != null &&
      _compareIso(snapshot.capturedAt, existing.capturedAt) < 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PRESENCE_STALE_IGNORED',
      details: {'peerId': senderPeerId},
    );
    return (HandleIncomingPostPresenceResult.staleSnapshot, null);
  }

  await snapshotRepo.save(snapshot);
  return (HandleIncomingPostPresenceResult.snapshotUpdated, snapshot);
}

ContactPresenceSnapshot? _buildActiveSnapshot({
  required String peerId,
  required Map<String, dynamic> payload,
  required String capturedAt,
  required String updatedAt,
}) {
  final latE3 = payload['lat_e3'] as int?;
  final lngE3 = payload['lng_e3'] as int?;
  final accuracyM = (payload['accuracy_m'] as num?)?.toDouble();
  if (latE3 == null || lngE3 == null || accuracyM == null) {
    return null;
  }
  return ContactPresenceSnapshot(
    peerId: peerId,
    status: ContactPresenceSnapshotStatus.active,
    latE3: latE3,
    lngE3: lngE3,
    capturedAt: capturedAt,
    accuracyM: accuracyM,
    updatedAt: updatedAt,
  );
}

ContactPresenceSnapshot? _buildInactiveSnapshot({
  required String peerId,
  required Map<String, dynamic> payload,
  required String capturedAt,
  required String updatedAt,
}) {
  final reason = payload['reason'] as String?;
  if (reason == null || !_inactiveReasons.contains(reason)) {
    return null;
  }
  return ContactPresenceSnapshot(
    peerId: peerId,
    status: ContactPresenceSnapshotStatus.inactive,
    capturedAt: capturedAt,
    updatedAt: updatedAt,
  );
}

bool _isIso8601(String? value) {
  return value != null && DateTime.tryParse(value)?.toUtc() != null;
}

int _compareIso(String left, String right) {
  return DateTime.parse(left).toUtc().compareTo(DateTime.parse(right).toUtc());
}
