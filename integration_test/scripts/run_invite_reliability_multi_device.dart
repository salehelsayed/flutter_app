#!/usr/bin/env dart
//
// Two-device relay orchestrator for the Review-08 invite-reliability scenario
// (slices C revoke, F decline-ack, D config-pull). Launches the SAME
// `group_multi_device_real_harness.dart` binary as the MD-004 proof (0 new
// build targets) in two roles on two sims:
//   - primary = Alice (admin / inviter)
//   - sibling = Bob   (invitee)
// They exchange real invite / decline-ack / revocation / config envelopes over
// the relay (storeInInbox + drainOfflineInbox) and coordinate via shared files.
// No Go CLI peer is needed — both ends are Dart stacks.
//
// Usage: dart integration_test/scripts/run_invite_reliability_multi_device.dart
//        [-d <primarySim>,<siblingSim>]
// Relay: defaults to the prod relay unless MKNOON_RELAY_ADDRESSES is set.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _harnessPath = 'integration_test/group_multi_device_real_harness.dart';
const _defaultPrimaryDevice = '347FB118-10D0-40C8-A05B-B0C3BD6B8CCD'; // iPhone Air
const _defaultSiblingDevice = '5BA69F1C-B112-47BE-B1FF-8C1003728C8F'; // iPhone 17
const _defaultRelayAddresses =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
    ',/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

String _relayAddresses() {
  final env = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  return _defaultRelayAddresses;
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // Output may still flush after teardown closes logs.
    }
  });
}

Future<Process> _startRole({
  required String role,
  required String deviceId,
  required Directory sharedDir,
  required String runId,
  required String relayAddresses,
}) async {
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...<String>[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$_harnessPath',
      '--publish-port',
      '--no-pub',
    ] else ...<String>['test', '--no-pub', _harnessPath],
    '--dart-define=E2E_SHARED_DIR=${sharedDir.path}',
    '--dart-define=MD004_ROLE=$role',
    '--dart-define=MD004_RUN_ID=$runId',
    '--dart-define=MD004_SCENARIO=invite_reliability',
    '--dart-define=E2E_DB_NAME=invite_reliability_${runId}_$role.db',
    '--dart-define=MKNOON_RELAY_ADDRESSES=$relayAddresses',
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

Future<void> _waitForFile(File file, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TimeoutException('Timed out waiting for ${file.path}');
}

void _parseDevices(List<String> args, List<String> out) {
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      out.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    }
  }
  if (out.isEmpty) {
    out.addAll([_defaultPrimaryDevice, _defaultSiblingDevice]);
  }
  if (out.length != 2) {
    throw ArgumentError(
      'Expected exactly two device IDs via -d <primary,sibling> or defaults',
    );
  }
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  _parseDevices(args, devices);
  final primaryDevice = devices[0];
  final siblingDevice = devices[1];
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final relayAddresses = _relayAddresses();
  final sharedDir = await Directory.systemTemp.createTemp(
    'invite_reliability_multi_device_',
  );
  final primaryLog = File(
    '${sharedDir.path}/primary.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final siblingLog = File(
    '${sharedDir.path}/sibling.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);

  _log(
    'ORCH',
    'invite-reliability shared dir: ${sharedDir.path}; '
        'primary=$primaryDevice sibling=$siblingDevice',
  );
  _log('ORCH', 'Relay: $relayAddresses');

  Process? primary;
  Process? sibling;
  try {
    // Launch primary first; wait until it has built + is running (it writes
    // alice_identity.json once its stack is up) before launching the sibling,
    // so the two flutter builds don't contend on the global startup lock.
    primary = await _startRole(
      role: 'primary',
      deviceId: primaryDevice,
      sharedDir: sharedDir,
      runId: runId,
      relayAddresses: relayAddresses,
    );
    _pipeOutput(primary.stdout, 'PRIMARY', primaryLog);
    _pipeOutput(primary.stderr, 'PRIMARY-ERR', primaryLog);

    _log('ORCH', 'Waiting for primary to build + come online...');
    await _waitForFile(
      File('${sharedDir.path}/md004_${runId}_alice_identity.json'),
      const Duration(minutes: 12),
    );
    _log('ORCH', 'Primary online; launching sibling');

    sibling = await _startRole(
      role: 'sibling',
      deviceId: siblingDevice,
      sharedDir: sharedDir,
      runId: runId,
      relayAddresses: relayAddresses,
    );
    _pipeOutput(sibling.stdout, 'SIBLING', siblingLog);
    _pipeOutput(sibling.stderr, 'SIBLING-ERR', siblingLog);

    final primaryExit = await primary.exitCode;
    final siblingExit = await sibling.exitCode;
    _log('ORCH', 'primaryExit=$primaryExit siblingExit=$siblingExit');
    _log('ORCH', 'Primary log: ${sharedDir.path}/primary.log');
    _log('ORCH', 'Sibling log: ${sharedDir.path}/sibling.log');
    if (primaryExit != 0 || siblingExit != 0) {
      throw StateError(
        'invite-reliability harness failure: primary=$primaryExit '
        'sibling=$siblingExit sharedDir=${sharedDir.path}',
      );
    }
    _log('ORCH', 'invite-reliability two-device proof completed successfully');
  } finally {
    try {
      primary?.kill();
    } catch (_) {}
    try {
      sibling?.kill();
    } catch (_) {}
    await primaryLog.close();
    await siblingLog.close();
  }
}
