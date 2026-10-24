import 'dart:convert';
import 'dart:io';

import 'production_journey_peer.dart';

/// Existing intro runner only: stop its native node after the generic preamble,
/// perform a real UI action inside its bounded settle delay, then read the
/// existing SQL-backed snapshot. No decisions/sends are made by this probe.
/// This source draft has not been compiled or exercised.
Future<Map<String, Object?>> withProductionIntroductionStoppedNodeSnapshot(
  ProductionJourneyPeer peer, {
  required String expectedPeerId,
  required Future<void> Function() action,
  int settleDelaySeconds = 120,
}) async {
  if (!{120, 240}.contains(settleDelaySeconds)) {
    throw ArgumentError(
      'only bounded single or nested offline windows are supported',
    );
  }
  if (peer.isIosSimulator) {
    throw StateError('offline intro probe is Android-only');
  }
  final identity = await peer.command('identity');
  if (identity['peerId'] != expectedPeerId || identity['online'] != true) {
    throw StateError('offline window must start from this invocation online');
  }
  final found = await peer.adb(['shell', 'pidof', peer.packageName]);
  final pid = '${found.stdout}'.trim();
  if (!RegExp(r'^[0-9]+$').hasMatch(pid)) {
    throw StateError('ambiguous owned process');
  }
  Future<void> verifyProcess() async {
    final current = await peer.adb(['shell', 'pidof', peer.packageName]);
    final command = await peer.adb([
      'exec-out',
      'run-as',
      peer.packageName,
      'cat',
      '/proc/$pid/cmdline',
    ]);
    if ('${current.stdout}'.trim() != pid ||
        '${command.stdout}'.split('\u0000').first != peer.packageName) {
      throw StateError('offline introduction process ownership changed');
    }
  }

  await verifyProcess();
  Future<String> flowLog() async {
    await verifyProcess();
    final result = await peer.adb([
      'logcat',
      '-b',
      'main',
      '-d',
      '-v',
      'raw',
      '--pid=$pid',
      '-t',
      '2000',
    ]);
    return '${result.stdout}';
  }

  Map<String, Object?>? record(String line) {
    final offset = line.indexOf('[FLOW] ');
    if (offset < 0) return null;
    try {
      final decoded = jsonDecode(line.substring(offset + 7));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  final baseline = await flowLog();
  final prior = const LineSplitter().convert(baseline).toSet();
  final step =
      'catalog-intro-offline-${peer.invocation.nonce}-${DateTime.now().microsecondsSinceEpoch}';
  await File(
    '${peer.output.path}/$step-flow-before.txt',
  ).writeAsString(baseline);
  await peer.writeAppFile('intro_e2e_config.json', {
    'stepId': step,
    'node_action_before_intro_phase': 'stop_node',
    'node_action_settle_delay_ms': settleDelaySeconds * 1000,
  });
  Future<Map<String, Object?>?> currentReceipt() async {
    final result = await peer.adb([
      'exec-out',
      'run-as',
      peer.packageName,
      'cat',
      'app_flutter/intro_e2e_result.json',
    ], allowFailure: true);
    if (result.exitCode != 0) return null;
    try {
      final value = jsonDecode('${result.stdout}');
      return value is Map && value['stepId'] == step
          ? Map<String, Object?>.from(value)
          : null;
    } on FormatException {
      return null;
    }
  }

  final stopped = await waitForProductionObservation(
    'fresh owned-process native stop success inside the current intro command',
    const Duration(seconds: 90),
    () async {
      final receipt = await currentReceipt();
      if (receipt == null) return null;
      if (receipt['status'] != 'running') {
        await File(
          '${peer.output.path}/$step-early-terminal.json',
        ).writeAsString(jsonEncode(receipt));
        throw StateError('offline UI window ended before action');
      }
      if (receipt['phase'] != 'actions') return null;
      final log = await flowLog();
      for (final line in const LineSplitter().convert(log)) {
        if (prior.contains(line)) continue;
        final event = record(line);
        if (event?['event'] != 'P2P_SERVICE_STOP_NODE_SUCCESS' ||
            DateTime.tryParse('${event?['ts']}') == null) {
          continue;
        }
        await File(
          '${peer.output.path}/$step-flow-stopped.txt',
        ).writeAsString(log);
        return event!;
      }
      return null;
    },
  );
  await verifyProcess();
  final before = await peer.command('identity');
  if (before['peerId'] != expectedPeerId || before['online'] != false) {
    throw StateError('native stop was not retained before UI action');
  }
  final actionStarted = DateTime.now().toUtc();
  await action();
  final actionCompleted = DateTime.now().toUtc();
  final after = await peer.command('identity');
  final window = await currentReceipt();
  if (after['peerId'] != expectedPeerId ||
      after['online'] != false ||
      window?['status'] != 'running' ||
      window?['phase'] != 'actions') {
    throw StateError(
      'UI action did not finish inside the verified stopped-node snapshot window',
    );
  }
  final receipt = await waitForProductionObservation(
    'existing stopped-node introduction snapshot',
    const Duration(minutes: 3),
    () async {
      final value = await currentReceipt();
      if (value == null || !{'complete', 'failed'}.contains(value['status'])) {
        return null;
      }
      await File(
        '${peer.output.path}/$step.json',
      ).writeAsString(jsonEncode(value));
      final node = value['nodeAction'];
      final snapshot = value['snapshot'];
      if (value['success'] != true ||
          node is! Map ||
          node['action'] != 'stop_node' ||
          node['stopped'] != true ||
          snapshot is! Map ||
          snapshot['identity'] is! Map ||
          (snapshot['identity'] as Map)['peerId'] != expectedPeerId) {
        throw StateError(
          'current stopped-node introduction receipt failed; raw evidence retained',
        );
      }
      return value;
    },
  );
  return {
    ...receipt,
    'observedRunId': peer.invocation.runId,
    'observedNonce': peer.invocation.nonce,
    'observedRole': peer.invocation.role,
    'probePreambleDrainsInbox': true,
    'offlineWindow': {
      'freshOwnedPidStopEvent': stopped,
      'onlineBeforeProbe': true,
      'onlineBeforeAction': before['online'],
      'onlineAfterAction': after['online'],
      'actionStartedAt': actionStarted.toIso8601String(),
      'actionCompletedAt': actionCompleted.toIso8601String(),
      'actionFinishedBeforeSnapshot': true,
      'settleDelayMs': settleDelaySeconds * 1000,
      'flowBeforePath': '${peer.output.path}/$step-flow-before.txt',
      'flowStoppedPath': '${peer.output.path}/$step-flow-stopped.txt',
    },
  };
}
