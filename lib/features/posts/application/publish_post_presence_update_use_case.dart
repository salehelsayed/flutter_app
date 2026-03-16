import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';

const Duration _postPresenceInteractiveBudget = Duration(seconds: 4);
const _postPresenceUuid = Uuid();
const int defaultPostPresenceDeliveryConcurrency = 1;

Future<void> publishPostPresenceUpdate({
  required P2PService p2pService,
  required ContactRepository contactRepo,
  required String status,
  required String capturedAt,
  int? latE3,
  int? lngE3,
  double? accuracyM,
  String? reason,
  int maxConcurrentRecipients = defaultPostPresenceDeliveryConcurrency,
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

  await fanoutPostFollowOnEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
    interactiveBudget: _postPresenceInteractiveBudget,
    fallbackToInboxOnDirectSendError: true,
  );
}
