/// Shared helpers for simulator benchmark harnesses.
///
/// Provides the common initialization sequence, event capture,
/// and benchmark output formatting used by all Phase 4 harnesses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

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
      state.badgeReadinessState == BadgeReadinessState.onlineDotted;
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

/// Initialize bridge, generate identity, and return the components.
Future<BenchmarkNode> createBenchmarkNode() async {
  final bridge = GoBridgeClient();
  await bridge.initialize();

  final genResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
  if (genResult['ok'] != true) {
    throw StateError('identity.generate failed: $genResult');
  }

  final identity = genResult['identity'] as Map<String, dynamic>;
  final peerId = identity['peerId'] as String;
  final privateKey = identity['privateKey'] as String;
  final publicKey = identity['publicKey'] as String;

  final service = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
  );

  return BenchmarkNode(
    bridge: bridge,
    service: service,
    peerId: peerId,
    privateKey: privateKey,
    publicKey: publicKey,
  );
}

/// Captures [FLOW] events emitted during [action].
Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  return captureFlowEventsUntil(action);
}

/// Captures `[FLOW]` events emitted during [action] and optionally waits
/// briefly for async push events that are expected to arrive just after the
/// triggering action completes.
Future<List<Map<String, dynamic>>> captureFlowEventsUntil(
  Future<void> Function() action, {
  Duration postActionTimeout = Duration.zero,
  Duration pollInterval = const Duration(milliseconds: 50),
  bool Function(List<Map<String, dynamic>> events)? until,
}) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;

  List<Map<String, dynamic>> parseEvents() {
    return printed
        .where((line) => line.startsWith('[FLOW] '))
        .map((line) {
          final json = line.substring('[FLOW] '.length);
          return jsonDecode(json) as Map<String, dynamic>;
        })
        .toList(growable: false);
  }

  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
      // Also forward to original so we see output on simulator
      originalDebugPrint(message, wrapWidth: wrapWidth);
    }
  };
  try {
    await action();
    if (postActionTimeout > Duration.zero) {
      final deadline = DateTime.now().add(postActionTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final events = parseEvents();
        if (until == null || until(events)) {
          break;
        }
        await Future<void>.delayed(pollInterval);
      }
    }
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }
  return parseEvents();
}

/// Filter events by event name.
List<Map<String, dynamic>> filterEvents(
  List<Map<String, dynamic>> events,
  String eventName,
) => events.where((e) => e['event'] == eventName).toList();

/// Returns the first matching event details, optionally scoped by phase.
Map<String, dynamic>? firstEventDetails(
  List<Map<String, dynamic>> events,
  String eventName, {
  String? phase,
}) {
  for (final event in events) {
    if (event['event'] != eventName) {
      continue;
    }
    final details = event['details'] as Map<String, dynamic>;
    if (phase == null || details['phase'] == phase) {
      return details;
    }
  }
  return null;
}

int? totalMsFromDetails(Map<String, dynamic>? details) {
  return (details?['totalMs'] as num?)?.toInt();
}

/// Returns the gap between two Phase 6 timing events when they share a proof window.
int? phaseEventGapMs(
  List<Map<String, dynamic>> events, {
  required String phase,
  required String earlierEvent,
  required String laterEvent,
}) {
  final earlier = firstEventDetails(events, earlierEvent, phase: phase);
  final later = firstEventDetails(events, laterEvent, phase: phase);
  if (earlier == null || later == null) {
    return null;
  }
  final earlierWindowId = earlier['proofWindowId'];
  final laterWindowId = later['proofWindowId'];
  if (earlierWindowId != null &&
      laterWindowId != null &&
      earlierWindowId != laterWindowId) {
    return null;
  }
  final earlierMs = totalMsFromDetails(earlier);
  final laterMs = totalMsFromDetails(later);
  if (earlierMs == null || laterMs == null) {
    return null;
  }
  return laterMs - earlierMs;
}

/// Returns the badge-honesty gap for one Phase 6 proof window.
int? badgeHonestyGapMs(
  List<Map<String, dynamic>> events, {
  required String phase,
}) {
  final sendable = firstEventDetails(
    events,
    'TIME_TO_SENDABLE_BADGE',
    phase: phase,
  );
  final firstSend = firstEventDetails(
    events,
    'FIRST_SEND_SUCCESS_IN_WINDOW',
    phase: phase,
  );
  final firstInbox = firstEventDetails(
    events,
    'FIRST_INBOX_SUCCESS_IN_WINDOW',
    phase: phase,
  );
  if (sendable == null || firstSend == null || firstInbox == null) {
    return null;
  }

  final proofWindowId = sendable['proofWindowId'];
  if (proofWindowId != null &&
      (firstSend['proofWindowId'] != proofWindowId ||
          firstInbox['proofWindowId'] != proofWindowId)) {
    return null;
  }

  final sendableMs = totalMsFromDetails(sendable);
  final firstSendMs = totalMsFromDetails(firstSend);
  final firstInboxMs = totalMsFromDetails(firstInbox);
  if (sendableMs == null || firstSendMs == null || firstInboxMs == null) {
    return null;
  }
  final usableProofMs = firstSendMs > firstInboxMs ? firstSendMs : firstInboxMs;
  return sendableMs - usableProofMs;
}

/// Compute percentile from a sorted list.
int percentile(List<int> sortedValues, int p) {
  if (sortedValues.isEmpty) return 0;
  if (sortedValues.length == 1) return sortedValues.first;
  final rank = (p / 100.0) * (sortedValues.length - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sortedValues[lower];
  return ((sortedValues[lower] + sortedValues[upper]) / 2).round();
}

/// Print a benchmark result line.
void printBenchmark(
  String metric, {
  required int p50,
  required int p95,
  required int n,
}) {
  print('[BENCHMARK] $metric p50=${p50}ms p95=${p95}ms (n=$n)');
}

/// Print a single-value benchmark result.
void printBenchmarkSingle(String metric, int value) {
  print('[BENCHMARK] $metric = ${value}ms');
}

/// Holds the initialized components for a benchmark node.
class BenchmarkNode {
  final GoBridgeClient bridge;
  final P2PServiceImpl service;
  final String peerId;
  final String privateKey;
  final String publicKey;

  BenchmarkNode({
    required this.bridge,
    required this.service,
    required this.peerId,
    required this.privateKey,
    required this.publicKey,
  });

  /// Start the node and wait for Online.
  Future<bool> startAndWaitOnline({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final started = await service.startNode(privateKey, peerId);
    if (!started) return false;
    return waitForOnline(service, timeout: timeout);
  }

  /// Start the node and wait for the first usable green badge state.
  Future<bool> startAndWaitSendable({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final started = await service.startNode(privateKey, peerId);
    if (!started) return false;
    return waitForSendableBadge(service, timeout: timeout);
  }

  /// Start the node and wait for the dotted relay-ready badge.
  Future<bool> startAndWaitRelayReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final started = await service.startNode(privateKey, peerId);
    if (!started) return false;
    return waitForRelayReadyBadge(service, timeout: timeout);
  }

  /// Stop and clean up.
  Future<void> dispose() async {
    await service.stopNode();
    service.dispose();
    bridge.dispose();
  }
}
