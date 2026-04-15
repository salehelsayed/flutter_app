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

  /// Stop and clean up.
  Future<void> dispose() async {
    await service.stopNode();
    service.dispose();
    bridge.dispose();
  }
}
