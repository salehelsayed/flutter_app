import 'package:flutter/foundation.dart';

/// Group bridge commands whose request and response a production journey may
/// observe: the relay inbox copy, the reliable send and the native topic
/// leave (counted per group for the durable exit evidence of H-01).
const debugObservedGroupDeliveryCommands = {
  'group:inboxStore',
  'group:sendReliable',
  'group:leave',
};

/// Receives one completed group delivery bridge exchange.
typedef GroupDeliveryDebugObserver =
    void Function(
      String cmd,
      Map<String, dynamic> payload,
      Map<dynamic, dynamic> response,
    );

GroupDeliveryDebugObserver? _observer;

/// Debug-build-only seam for production journeys whose original proof reads
/// the durable recipients of a send (catalog GE-002, GM-020). It is only
/// readable and settable in debug builds, so release and profile builds never
/// observe bridge traffic.
GroupDeliveryDebugObserver? get debugGroupDeliveryObserver =>
    kDebugMode ? _observer : null;

set debugGroupDeliveryObserver(GroupDeliveryDebugObserver? observer) {
  if (!kDebugMode) {
    throw StateError('group delivery observer is debug-only');
  }
  _observer = observer;
}

/// Receives one raw inbound group message or reaction event from the bridge.
typedef GroupInboundDebugObserver =
    void Function(String kind, Map<String, dynamic> data);

GroupInboundDebugObserver? _inboundObserver;

/// Debug-build-only seam for production journeys whose original proof counts
/// the raw group traffic a removed member still receives (catalog GM-016).
/// Only readable and settable in debug builds.
GroupInboundDebugObserver? get debugGroupInboundObserver =>
    kDebugMode ? _inboundObserver : null;

set debugGroupInboundObserver(GroupInboundDebugObserver? observer) {
  if (!kDebugMode) {
    throw StateError('group inbound observer is debug-only');
  }
  _inboundObserver = observer;
}
