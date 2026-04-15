#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_android_app_package.dart';

const _goMknoonDir = 'go-mknoon';
const _testpeerBin = 'go-mknoon/bin/testpeer';
const _defaultMacOsBundleId = 'com.example.flutterApp';
String? _androidDeviceId;
final _appPackage = resolveAndroidAppPackage();

List<String> _relayDartDefines() {
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relayAddresses == null || relayAddresses.trim().isEmpty) {
    return const [];
  }
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relayAddresses.trim()}'];
}

String? _adbPath;
String _adb() {
  if (_adbPath != null) return _adbPath!;
  for (final base in [
    Platform.environment['ANDROID_HOME'],
    Platform.environment['ANDROID_SDK_ROOT'],
    '${Platform.environment['HOME']}/Library/Android/sdk',
  ]) {
    if (base == null) continue;
    final candidate = '$base/platform-tools/adb';
    if (File(candidate).existsSync()) {
      _adbPath = candidate;
      return candidate;
    }
  }
  _adbPath = 'adb';
  return _adbPath!;
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
        _log('EVENT', line);
        return;
      }
      _log('RESP', line);
      if (_pending.isNotEmpty) {
        _pending.removeAt(0).complete(decoded);
      }
    } catch (_) {
      _log('WARN', 'Non-JSON stdout: $line');
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
    final content = jsonEncode({
      'peerId': peerId,
      'publicKey': publicKey,
      'mlKemPublicKey': mlKemPublicKey,
    });
    await _writeFile(path, content);
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

Future<String> _pickDevice(String? deviceId) async {
  if (deviceId != null && deviceId.isNotEmpty) return deviceId;

  final result = await Process.run('flutter', ['devices', '--machine']);
  if (result.exitCode != 0) {
    throw StateError('flutter devices failed: ${result.stderr}');
  }

  final devices = jsonDecode(result.stdout as String) as List<dynamic>;
  for (final device in devices.cast<Map<String, dynamic>>()) {
    final isMobile = device['category'] == 'mobile';
    final emulator = device['emulator'] == true;
    if (isMobile || emulator) {
      return device['id'] as String;
    }
  }

  throw StateError('No simulator or mobile device found');
}

bool _isIosDeviceId(String deviceId) {
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

bool _isAndroidDeviceId(String deviceId) =>
    !_isIosDeviceId(deviceId) && deviceId != 'macos';

Future<void> _writeFile(String path, String content) async {
  if (_androidDeviceId == null) {
    File(path).writeAsStringSync(content);
    return;
  }

  final tmp = File(
    '${Directory.systemTemp.path}/group_recovery_push_${DateTime.now().millisecondsSinceEpoch}',
  );
  tmp.writeAsStringSync(content);
  try {
    final result = await Process.run(_adb(), [
      '-s',
      _androidDeviceId!,
      'push',
      tmp.path,
      path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('adb push failed: ${result.stderr}');
    }
  } finally {
    try {
      tmp.deleteSync();
    } catch (_) {}
  }
}

Future<String?> _readFile(String path) async {
  if (_androidDeviceId == null) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  final result = await Process.run(_adb(), [
    '-s',
    _androidDeviceId!,
    'shell',
    'cat',
    path,
  ]);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trimRight();
}

Future<String?> _readAppFile(String path) async {
  if (_androidDeviceId == null) {
    return _readFile(path);
  }

  final result = await Process.run(_adb(), [
    '-s',
    _androidDeviceId!,
    'shell',
    'run-as',
    _appPackage,
    'cat',
    path,
  ]);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trimRight();
}

Future<String> _createAndroidTempDir(String deviceId) async {
  final path = '/data/local/tmp/group_recovery_e2e_${DateTime.now().millisecondsSinceEpoch}';
  final mkdir = await Process.run(_adb(), [
    '-s',
    deviceId,
    'shell',
    'mkdir',
    '-p',
    path,
  ]);
  if (mkdir.exitCode != 0) {
    throw StateError('Failed to create Android temp dir: ${mkdir.stderr}');
  }
  await Process.run(_adb(), [
    '-s',
    deviceId,
    'shell',
    'chmod',
    '777',
    path,
  ]);
  return path;
}

Future<void> _cleanupAndroidTempDir(String deviceId, String path) async {
  try {
    await Process.run(_adb(), [
      '-s',
      deviceId,
      'shell',
      'rm',
      '-rf',
      path,
    ]);
  } catch (_) {}
}

Future<void> _cleanupAndroidAppWriteDir(String deviceId, String path) async {
  try {
    await Process.run(_adb(), [
      '-s',
      deviceId,
      'shell',
      'run-as',
      _appPackage,
      'rm',
      '-rf',
      path,
    ]);
  } catch (_) {}
}

Future<Map<String, dynamic>> _waitForGroupFixture(
  String path, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final raw = await _readAppFile(path);
    if (raw != null && raw.isNotEmpty) {
      return jsonDecode(raw) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for group fixture at $path');
}

Future<bool> _waitForSignal(
  String path, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final raw = await _readAppFile(path);
    if (raw != null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

String _readMacOsBundleId() {
  final config = File('macos/Runner/Configs/AppInfo.xcconfig');
  if (!config.existsSync()) return _defaultMacOsBundleId;

  final pattern = RegExp(r'^\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)\s*$');
  for (final line in config.readAsLinesSync()) {
    final match = pattern.firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
  }

  return _defaultMacOsBundleId;
}

Future<Directory> _createMacOsSharedDir() async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is not set; cannot resolve macOS app container');
  }

  final bundleId = _readMacOsBundleId();
  final dir = Directory(
    '$home/Library/Containers/$bundleId/Data/Documents/e2e_group_recovery_${DateTime.now().millisecondsSinceEpoch}',
  );
  dir.createSync(recursive: true);
  return dir;
}

Future<void> main(List<String> args) async {
  String? requestedDevice;
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      requestedDevice = args[i + 1];
      i++;
    }
  }

  final deviceId = await _pickDevice(requestedDevice);
  final isAndroid = _isAndroidDeviceId(deviceId);
  if (isAndroid) {
    _androidDeviceId = deviceId;
  }
  final hostTempDir = await Directory.systemTemp.createTemp(
    'group_recovery_e2e_',
  );
  final readDirPath = deviceId == 'macos'
      ? (await _createMacOsSharedDir()).path
      : isAndroid
      ? await _createAndroidTempDir(deviceId)
      : hostTempDir.path;
  final writeDirPath = isAndroid
      ? '/data/data/$_appPackage/cache/e2e_group_recovery'
      : readDirPath;
  final dbName =
      'group_recovery_cli_e2e_${DateTime.now().millisecondsSinceEpoch}.db';
  final cliFixturePath = '$readDirPath/cli_peer_fixture.json';
  final groupFixturePath = '$writeDirPath/group_recovery_fixture.json';
  final liveReceivedPath = '$writeDirPath/e2e_group_live_received';
  final inboxStoredPath = '$readDirPath/e2e_group_cli_inbox_stored';

  final peer = TestPeer();

  try {
    _log('ORCH', 'Building CLI test peer...');
    final build = await Process.run('make', [
      'testpeer',
    ], workingDirectory: _goMknoonDir);
    if (build.exitCode != 0) {
      throw StateError('make testpeer failed: ${build.stderr}');
    }

    _log('ORCH', 'Starting CLI test peer...');
    await peer.start();
    await peer.generateIdentity();
    await peer.startNode();
    await peer.writeFixture(cliFixturePath);

    _log('ORCH', 'Launching Flutter group recovery E2E...');
    final flutterArgs = <String>[
      if (_isIosDeviceId(deviceId)) ...<String>[
        'drive',
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/group_recovery_cli_e2e_test.dart',
        '--publish-port',
      ] else ...<String>[
        'test',
        'integration_test/group_recovery_cli_e2e_test.dart',
      ],
      '--dart-define=CLI_PEER_FIXTURE=$cliFixturePath',
      '--dart-define=E2E_TEMP_DIR=$readDirPath',
      '--dart-define=E2E_WRITE_DIR=$writeDirPath',
      '--dart-define=E2E_DB_NAME=$dbName',
      ..._relayDartDefines(),
      '-d',
      deviceId,
    ];
    final flutterProcess = await Process.start(
      'flutter',
      flutterArgs,
      mode: ProcessStartMode.inheritStdio,
    );

    final groupFixture = await _waitForGroupFixture(groupFixturePath);
    _log('ORCH', 'Group fixture received for ${groupFixture['groupId']}');

    await peer.commandOk('group_join', groupFixture);

    const liveMessageId = 'cli-live-group-message';
    var liveDelivered = false;
    for (var attempt = 1; attempt <= 8; attempt++) {
      _log('ORCH', 'Live publish attempt $attempt...');
      await peer.commandOk('group_publish', {
        'groupId': groupFixture['groupId'],
        'text': 'CLI live message',
        'messageId': liveMessageId,
        'senderUsername': 'CLIGroupPeer',
      });

      liveDelivered = await _waitForSignal(
        liveReceivedPath,
        timeout: const Duration(seconds: 5),
      );
      if (liveDelivered) break;
    }

    if (!liveDelivered) {
      throw StateError('Flutter test never confirmed live group delivery');
    }

    await peer.commandOk('group_inbox_store', {
      'groupId': groupFixture['groupId'],
      'text': 'CLI missed inbox message',
      'messageId': 'cli-missed-inbox-message',
      'senderUsername': 'CLIGroupPeer',
      'keyEpoch': groupFixture['keyEpoch'],
    });
    await _writeFile(inboxStoredPath, 'ok');
    _log('ORCH', 'Missed inbox message stored');

    final flutterExitCode = await flutterProcess.exitCode;
    if (flutterExitCode != 0) {
      throw StateError('Flutter test failed with exit code $flutterExitCode');
    }
  } finally {
    await peer.stop();
    try {
      hostTempDir.deleteSync(recursive: true);
    } catch (_) {}
    if (isAndroid) {
      await _cleanupAndroidTempDir(deviceId, readDirPath);
      await _cleanupAndroidAppWriteDir(deviceId, writeDirPath);
    } else if (readDirPath != hostTempDir.path) {
      try {
        Directory(readDirPath).deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
