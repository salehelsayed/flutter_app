import 'package:flutter_app/core/services/p2p_service.dart';

typedef GroupKeyDelivery = Future<bool> Function(String peerId, String message);

/// The production key transport (production_application_bootstrap.dart): the
/// real send result, plus the inbox fallback for an unacknowledged send.
({GroupKeyDelivery send, GroupKeyDelivery inbox}) groupKeyTransport(
  P2PService p2p,
) => (
  send: (peerId, message) => p2p.sendMessage(peerId, message),
  inbox: (peerId, message) => p2p.storeInInbox(peerId, message),
);

/// Fault injection for a key update the scenario drops or holds: [intercepts]
/// claims those recipients, and every other recipient gets the real result.
/// It has no inbox fallback, which would route around the drop or hold.
GroupKeyDelivery groupKeySendIntercepting(
  P2PService p2p, {
  required bool Function(String peerId, String message) intercepts,
}) =>
    (peerId, message) async =>
        intercepts(peerId, message) ? true : p2p.sendMessage(peerId, message);
