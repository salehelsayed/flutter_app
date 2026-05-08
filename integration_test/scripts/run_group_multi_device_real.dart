#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultPrimaryDevice = '347FB118-10D0-40C8-A05B-B0C3BD6B8CCD';
const _defaultSiblingDevice = '5BA69F1C-B112-47BE-B1FF-8C1003728C8F';
const _goMknoonDir = 'go-mknoon';
const _testpeerBin = 'go-mknoon/bin/testpeer';
const _harnessPath = 'integration_test/group_multi_device_real_harness.dart';

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

List<String> _relayDartDefines() {
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relayAddresses == null || relayAddresses.trim().isEmpty) {
    return const [];
  }
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relayAddresses.trim()}'];
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

String _signalPath(Directory dir, String runId, String name) =>
    '${dir.path}/md004_${runId}_$name';

Future<Map<String, dynamic>> _waitForJson(
  String path, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(path);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for json: $path');
}

Future<void> _waitForSignal(
  String path, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(path);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for signal: $path');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // The harness may still flush process output after teardown closes logs.
    }
  });
}

List<String> _recipientPeerIdsForCliStore(
  Map<String, dynamic> cliGroupJoinFixture,
  String senderPeerId,
) {
  final groupConfig = cliGroupJoinFixture['groupConfig'];
  if (groupConfig is! Map) {
    throw StateError('CLI group join fixture is missing groupConfig');
  }
  final members = groupConfig['members'];
  if (members is! List) {
    throw StateError('CLI group join fixture is missing groupConfig.members');
  }

  final recipientPeerIds = members
      .whereType<Map>()
      .map((member) => member['peerId'])
      .whereType<String>()
      .where((peerId) => peerId.isNotEmpty && peerId != senderPeerId)
      .toSet()
      .toList(growable: false);
  if (recipientPeerIds.isEmpty) {
    throw StateError('CLI group inbox store requires at least one recipient');
  }
  return recipientPeerIds;
}

class TestPeer {
  Process? _process;
  final _pending = <Completer<Map<String, dynamic>>>[];
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  String? peerId;
  String? publicKey;
  String? mlKemPublicKey;

  Future<void> start() async {
    _process = await Process.start(_testpeerBin, []);
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdout);
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('PEER-ERR', line));
  }

  void _handleStdout(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      if (decoded.containsKey('event')) {
        _log('PEER-EVENT', line);
        return;
      }
      _log('PEER-RESP', line);
      if (_pending.isNotEmpty) {
        _pending.removeAt(0).complete(decoded);
      }
    } catch (_) {
      _log('PEER-WARN', 'Non-JSON stdout: $line');
    }
  }

  Future<Map<String, dynamic>> command(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending.add(completer);
    final request = <String, dynamic>{'cmd': cmd};
    if (params != null) {
      request['params'] = params;
    }
    _process!.stdin.writeln(jsonEncode(request));
    await _process!.stdin.flush();
    return completer.future.timeout(const Duration(seconds: 60));
  }

  Future<Map<String, dynamic>> commandOk(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await command(cmd, params);
    if (result['ok'] != true) {
      throw StateError(
        'Command "$cmd" failed: ${result['errorMessage'] ?? result}',
      );
    }
    return result;
  }

  Future<void> generateIdentity() async {
    final identity = await commandOk('generate_identity');
    peerId = identity['peerId'] as String;
    publicKey = identity['publicKey'] as String;

    final mlKem = await commandOk('mlkem_keygen');
    mlKemPublicKey = mlKem['publicKey'] as String;
  }

  Future<void> startNode() async {
    await commandOk('start');
    await commandOk('wait_relay', {'timeoutSec': 30});
    await commandOk('wait_circuit', {'timeoutSec': 30});
  }

  Future<void> writeFixture(String path) async {
    File(path).writeAsStringSync(
      jsonEncode({
        'peerId': peerId,
        'publicKey': publicKey,
        'mlKemPublicKey': mlKemPublicKey,
      }),
    );
  }

  Future<void> stop() async {
    try {
      await command('stop');
    } catch (_) {}
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _process?.kill();
    await _process?.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

Future<Process> _startHarnessRole({
  required String role,
  required String deviceId,
  required Directory sharedDir,
  required String cliFixturePath,
  required String runId,
}) async {
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...<String>[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$_harnessPath',
      '--publish-port',
      '--no-pub',
    ] else ...<String>['test', '--no-pub', _harnessPath],
    '--dart-define=CLI_PEER_FIXTURE=$cliFixturePath',
    '--dart-define=E2E_SHARED_DIR=${sharedDir.path}',
    '--dart-define=MD004_ROLE=$role',
    '--dart-define=MD004_RUN_ID=$runId',
    '--dart-define=E2E_DB_NAME=group_multi_device_real_${runId}_$role.db',
    ..._relayDartDefines(),
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role harness: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
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
  final sharedDir = await Directory.systemTemp.createTemp(
    'md004_multi_device_real_',
  );
  final cliFixturePath = '${sharedDir.path}/cli_peer_fixture.json';
  final phoneLog = File(
    '${sharedDir.path}/primary.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final siblingLog = File(
    '${sharedDir.path}/sibling.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final peer = TestPeer();
  Process? primary;
  Process? sibling;

  _log(
    'ORCH',
    'MD-004 shared dir: ${sharedDir.path}; primary=$primaryDevice sibling=$siblingDevice',
  );

  try {
    _log('ORCH', 'Building CLI test peer...');
    final build = await Process.run('make', [
      'testpeer',
    ], workingDirectory: _goMknoonDir);
    if (build.exitCode != 0) {
      throw StateError('make testpeer failed: ${build.stderr}');
    }

    await peer.start();
    await peer.generateIdentity();
    await peer.startNode();
    await peer.writeFixture(cliFixturePath);

    primary = await _startHarnessRole(
      role: 'primary',
      deviceId: primaryDevice,
      sharedDir: sharedDir,
      cliFixturePath: cliFixturePath,
      runId: runId,
    );
    _pipeOutput(primary.stdout, 'PRIMARY', phoneLog);
    _pipeOutput(primary.stderr, 'PRIMARY-ERR', phoneLog);

    await _waitForJson(
      _signalPath(sharedDir, runId, 'cli_group_join_fixture.json'),
      timeout: const Duration(minutes: 5),
    );
    _log('ORCH', 'Primary is ready; starting sibling harness');

    sibling = await _startHarnessRole(
      role: 'sibling',
      deviceId: siblingDevice,
      sharedDir: sharedDir,
      cliFixturePath: cliFixturePath,
      runId: runId,
    );
    _pipeOutput(sibling.stdout, 'SIBLING', siblingLog);
    _pipeOutput(sibling.stderr, 'SIBLING-ERR', siblingLog);

    final cliGroupJoinFixture = await _waitForJson(
      _signalPath(sharedDir, runId, 'cli_group_join_fixture.json'),
      timeout: const Duration(minutes: 5),
    );
    final cliRecipientPeerIds = _recipientPeerIdsForCliStore(
      cliGroupJoinFixture,
      peer.peerId!,
    );
    _log(
      'ORCH',
      'CLI joining group ${cliGroupJoinFixture['groupId']} on behalf of peer ${peer.peerId}',
    );
    await peer.commandOk('group_join', cliGroupJoinFixture);

    await _waitForSignal(
      _signalPath(sharedDir, runId, 'cli_publish_ready'),
      timeout: const Duration(minutes: 5),
    );
    _log('ORCH', 'Publishing CLI live message into the MD-004 group');
    const cliMessageId = 'md004-cli-live';
    final cliTimestamp = DateTime.now().toUtc().toIso8601String();
    await peer.commandOk('group_publish', {
      'groupId': cliGroupJoinFixture['groupId'],
      'text': 'MD-004 CLI incoming',
      'messageId': cliMessageId,
      'timestamp': cliTimestamp,
      'senderUsername': 'CLIGroupPeer',
    });
    await peer.commandOk('group_inbox_store', {
      'groupId': cliGroupJoinFixture['groupId'],
      'text': 'MD-004 CLI incoming',
      'messageId': cliMessageId,
      'timestamp': cliTimestamp,
      'senderUsername': 'CLIGroupPeer',
      'keyEpoch': cliGroupJoinFixture['keyEpoch'],
      'groupKey': cliGroupJoinFixture['groupKey'],
      'recipientPeerIds': cliRecipientPeerIds,
    });
    File(
      _signalPath(sharedDir, runId, 'cli_message_published'),
    ).writeAsStringSync('ok');

    final primaryExit = await primary.exitCode;
    final siblingExit = await sibling.exitCode;
    if (primaryExit != 0 || siblingExit != 0) {
      throw StateError(
        'Harness failure: primaryExit=$primaryExit siblingExit=$siblingExit sharedDir=${sharedDir.path}',
      );
    }

    await _waitForSignal(
      _signalPath(sharedDir, runId, 'sibling_complete'),
      timeout: const Duration(minutes: 2),
    );
    _log('ORCH', 'MD-004 proof completed successfully');
    _log('ORCH', 'Primary log: ${sharedDir.path}/primary.log');
    _log('ORCH', 'Sibling log: ${sharedDir.path}/sibling.log');
  } finally {
    try {
      if (primary != null) {
        primary.kill();
      }
    } catch (_) {}
    try {
      if (sibling != null) {
        sibling.kill();
      }
    } catch (_) {}
    await phoneLog.close();
    await siblingLog.close();
    await peer.stop();
  }
}
