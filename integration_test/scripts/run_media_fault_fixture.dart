#!/usr/bin/env dart

// H2 (MEDIA-019/038) device-run companion for the disposable Plan 347 relay.
//
//   serve <state.json>         start the fixture, write its readiness to
//                              <state.json> (0600), run until <state.json>.stop
//                              appears or SIGINT/SIGTERM, then tear down.
//   pending <state.json>       print this run's pending blob count.
//   fault <state.json> <op>    apply snapshot|remove|restore|corrupt to the
//                              newest pending blob, or expire|clock_reset.
//
// The relay address and probe capability stay in <state.json>; nothing here
// prints them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../support/direct_media_fixture_fault_client.dart';
import 'run_direct_media_blob_custody_sims.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('usage: serve|pending|fault <state.json> [op]');
    exitCode = 64;
    return;
  }
  final state = File(arguments[1]);
  switch (arguments.first) {
    case 'serve':
      exitCode = await _serve(state);
    case 'pending':
      final pending = await _client(state).pending();
      stdout.writeln('pending=${pending.length}');
    case 'fault' when arguments.length == 3:
      exitCode = await _fault(state, arguments[2]);
    default:
      stderr.writeln('usage: serve|pending|fault <state.json> [op]');
      exitCode = 64;
  }
}

Future<int> _serve(File state) async {
  final environment = Platform.environment;
  final lease = await DirectMediaBlobCustodyFixtureLease.start(
    goExecutable:
        environment['PLAN347_GO_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN347_GO_EXECUTABLE']!.trim()
        : 'go',
    hostIp: await resolveDirectMediaBlobCustodyFixtureHostIp(environment),
    environment: environment,
  );
  final stopFile = File('${state.path}.stop');
  try {
    state.writeAsStringSync(
      jsonEncode({
        'multiaddr': lease.multiaddr,
        'probeUrl': lease.probeUrl,
        'relayBinarySha256': lease.relayBinarySha256,
      }),
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', state.path]);
    }
    stdout.writeln('H2_FIXTURE_READY relaySha256=${lease.relayBinarySha256}');
    final stop = Completer<void>();
    final signals = [
      ProcessSignal.sigint.watch().listen((_) => stop.complete()),
      ProcessSignal.sigterm.watch().listen((_) => stop.complete()),
    ];
    final poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (stopFile.existsSync() && !stop.isCompleted) stop.complete();
    });
    await stop.future;
    poll.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
  } finally {
    await lease.stop();
    if (stopFile.existsSync()) stopFile.deleteSync();
    stdout.writeln('H2_FIXTURE_STOPPED');
  }
  return 0;
}

DirectMediaFixtureFaultClient _client(File state) {
  final decoded = jsonDecode(state.readAsStringSync()) as Map<String, Object?>;
  return DirectMediaFixtureFaultClient(
    Uri.parse(decoded['probeUrl'] as String),
  );
}

Future<int> _fault(File state, String wire) async {
  final op = DirectMediaFixtureFaultOp.values
      .where((candidate) => candidate.wire == wire)
      .firstOrNull;
  if (op == null) {
    stderr.writeln('unknown op $wire');
    return 64;
  }
  final client = _client(state);
  if (!op.targeted) {
    await client.apply(op);
    stdout.writeln('fault=$wire applied');
    return 0;
  }
  final pending = await client.pending();
  if (pending.isEmpty && op != DirectMediaFixtureFaultOp.restore) {
    stderr.writeln('no pending blob for $wire');
    return 2;
  }
  final target = op == DirectMediaFixtureFaultOp.restore
      ? _lastTarget(state)
      : pending.last;
  if (target == null) {
    stderr.writeln('restore needs an earlier snapshot in this state file');
    return 2;
  }
  final status = await client.apply(
    op,
    recipientPeerId: target.recipientPeerId,
    attachmentId: target.attachmentId,
  );
  if (op == DirectMediaFixtureFaultOp.snapshot) _rememberTarget(state, target);
  stdout.writeln(
    'fault=$wire lane=${target.lane} present=${status['present']} '
    'hashMatches=${status['hashMatches']}',
  );
  return 0;
}

File _targetFile(File state) => File('${state.path}.target');

void _rememberTarget(File state, DirectMediaFixtureTarget target) {
  _targetFile(state).writeAsStringSync(
    jsonEncode({
      'recipientPeerId': target.recipientPeerId,
      'attachmentId': target.attachmentId,
      'lane': target.lane,
    }),
  );
}

DirectMediaFixtureTarget? _lastTarget(File state) {
  final file = _targetFile(state);
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return (
    recipientPeerId: decoded['recipientPeerId'] as String,
    attachmentId: decoded['attachmentId'] as String,
    lane: decoded['lane'] as String? ?? '',
  );
}
