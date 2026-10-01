import 'package:flutter/foundation.dart';

/// Group delivery bridge commands whose request and response a production
/// journey may observe: the relay inbox copy and the reliable send.
const debugObservedGroupDeliveryCommands = {
  'group:inboxStore',
  'group:sendReliable',
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
