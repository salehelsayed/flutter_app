import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

const Duration _postPresenceInteractiveBudget = Duration(seconds: 4);
const _postPresenceUuid = Uuid();

Future<void> publishPostPresenceUpdate({
  required P2PService p2pService,
  required ContactRepository contactRepo,
  required String status,
  required String capturedAt,
  int? latE3,
  int? lngE3,
  double? accuracyM,
  String? reason,
  DateTime Function()? now,
}) async {
  final senderPeerId = p2pService.currentState.peerId;
  if (!p2pService.currentState.isStarted ||
      senderPeerId == null ||
      senderPeerId.isEmpty) {
    return;
  }
  if (status == 'active' &&
      (latE3 == null || lngE3 == null || accuracyM == null)) {
    return;
  }
  if (status == 'inactive' && (reason == null || reason.isEmpty)) {
    return;
  }

  final contacts = await contactRepo.getActiveContacts();
  final recipientPeerIds = contacts
      .where(
        (contact) =>
            !contact.isBlocked &&
            !contact.isArchived &&
            contact.peerId != senderPeerId,
      )
      .map((contact) => contact.peerId)
      .toSet()
      .toList(growable: false);
  if (recipientPeerIds.isEmpty) {
    return;
  }

  final createdAt = (now ?? () => DateTime.now().toUtc())()
      .toUtc()
      .toIso8601String();
  final envelope = jsonEncode({
    'type': 'post_presence_update',
    'version': '1',
    'event_id': 'evt_${_postPresenceUuid.v4()}',
    'created_at': createdAt,
    'sender_peer_id': senderPeerId,
    'payload': <String, Object?>{
      'status': status,
      'captured_at': capturedAt,
      if (status == 'active') ...<String, Object?>{
        'lat_e3': latE3,
        'lng_e3': lngE3,
        'accuracy_m': accuracyM,
      },
      if (status == 'inactive') 'reason': reason,
    },
  });

  for (final recipientPeerId in recipientPeerIds) {
    final delivered = await _sendPresenceEnvelope(
      p2pService: p2pService,
      recipientPeerId: recipientPeerId,
      envelope: envelope,
    );
    if (!delivered) {
      await p2pService.storeInInbox(recipientPeerId, envelope);
    }
  }
}

Future<bool> _sendPresenceEnvelope({
  required P2PService p2pService,
  required String recipientPeerId,
  required String envelope,
}) async {
  try {
    final result = await p2pService.sendMessageWithReply(
      recipientPeerId,
      envelope,
      timeoutMs: _postPresenceInteractiveBudget.inMilliseconds,
    );
    return result.sent;
  } catch (_) {
    return false;
  }
}
