/// Shared node-readiness waiters for integration-test harnesses.
///
/// Canonical home for the `waitFor` / `waitForOnline` readiness loops (plus
/// the badge-state predicates and badge waiters) that many harnesses
/// historically re-declared inline as `_waitForOnline` / `_waitFor`.
///
/// Lifted verbatim from `benchmark_helpers.dart`, which now re-exports these
/// symbols for back-compat. New harnesses should import this file directly.
library;

import 'dart:async';

import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// Wait for [condition] to return true, polling every [interval].
Future<bool> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 500),
  String label = '',
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (condition()) {
      sw.stop();
      print('[WAIT] "$label" satisfied after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(interval);
  }
  sw.stop();
  print('[WAIT] "$label" TIMED OUT after ${sw.elapsedMilliseconds}ms');
  return false;
}

/// Wait for the P2P service to reach Online state.
Future<bool> waitForOnline(
  P2PServiceImpl service, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return waitFor(
    () => healthFromState(service.currentState) == ConnectionHealth.online,
    timeout: timeout,
    label: 'Online',
  );
}

bool isSendableBadgeState(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.online ||
      state.badgeReadinessState == BadgeReadinessState.onlineDotted ||
      state.badgeReadinessState == BadgeReadinessState.onlineDirect;
}

bool isPlainOnlineBadgeState(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.online;
}

bool isRelayReadyBadgeState(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.onlineDotted;
}

/// Wait for the service-owned badge to reach a usable green state.
Future<bool> waitForSendableBadge(
  P2PServiceImpl service, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return waitFor(
    () => isSendableBadgeState(service.currentState),
    timeout: timeout,
    label: 'Sendable badge',
  );
}

/// Wait for the badge to reach plain `Online` before dotted relay-ready.
Future<bool> waitForPlainOnlineBadge(
  P2PServiceImpl service, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return waitFor(
    () => isPlainOnlineBadgeState(service.currentState),
    timeout: timeout,
    label: 'Plain Online badge',
  );
}

/// Wait for the badge to reach the dotted relay-ready state.
Future<bool> waitForRelayReadyBadge(
  P2PServiceImpl service, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return waitFor(
    () => isRelayReadyBadgeState(service.currentState),
    timeout: timeout,
    label: 'Online. badge',
  );
}
