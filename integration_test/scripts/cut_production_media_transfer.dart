import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

typedef MediaCutProcess = Future<ProcessResult> Function(String, List<String>);

/// Only bridges the held relay-body checkpoint to an abrupt owned Android
/// package stop. Appium MCP retains all UI, permission and viewer ownership.
Future<Map<String, Object?>> cutProductionMediaTransfer({
  required Uri fixtureProbe,
  required String gateId,
  required String attachmentId,
  required String deviceId,
  required String packageName,
  required File output,
  Duration wait = const Duration(seconds: 30),
  MediaCutProcess? process,
}) async {
  final address = InternetAddress.tryParse(fixtureProbe.host);
  final bytes = address?.rawAddress;
  final privateHost =
      address?.isLoopback == true ||
      (bytes != null &&
          bytes.length == 4 &&
          (bytes[0] == 10 ||
              bytes[0] == 192 && bytes[1] == 168 ||
              bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31));
  if (fixtureProbe.scheme != 'http' ||
      !privateHost ||
      fixtureProbe.userInfo.isNotEmpty ||
      gateId.isEmpty ||
      attachmentId.isEmpty ||
      deviceId.isEmpty ||
      !RegExp(
        r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$',
      ).hasMatch(packageName)) {
    throw const FormatException(
      'owned private fixture and explicit target/package required',
    );
  }
  final run =
      process ??
      (String name, List<String> args) =>
          Process.run(name, args, runInShell: false);
  final endpoint = fixtureProbe.replace(
    path: '${fixtureProbe.path}/transfer-checkpoint',
  );
  final attachmentHash = sha256.convert(utf8.encode(attachmentId)).toString();
  final proof = <String, Object?>{
    'schema': 'mknoon.media-transfer-cut.v1',
    'gateId': gateId,
    'deviceId': deviceId,
    'packageName': packageName,
    'status': 'RUNNING',
  };
  await output.parent.create(recursive: true);
  Future<void> persist() => output.writeAsString(jsonEncode(proof));
  Future<Map<String, Object?>> request([bool release = false]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.openUrl(release ? 'POST' : 'GET', endpoint);
      if (release) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'op': 'release', 'gateId': gateId}));
      }
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != HttpStatus.ok) {
        throw StateError('checkpoint probe refused');
      }
      final value = jsonDecode(
        await utf8.decodeStream(res).timeout(const Duration(seconds: 2)),
      );
      return Map<String, Object?>.from(value as Map);
    } finally {
      client.close(force: true);
    }
  }

  bool sameHeld(Map<String, Object?> value) =>
      value['schema'] == 'mknoon.media-transfer-checkpoint.v1' &&
      value['gateId'] == gateId &&
      value['attachmentSha256'] == attachmentHash &&
      value['bound'] == true &&
      value['held'] == true &&
      value['released'] == false &&
      value['timedOut'] == false &&
      value['bytesTransferred'] is int &&
      value['totalBytes'] is int &&
      (value['bytesTransferred']! as int) > 0 &&
      (value['bytesTransferred']! as int) < (value['totalBytes']! as int);
  var ownsGate = false;
  try {
    await persist();
    final timer = Stopwatch()..start();
    Map<String, Object?>? before;
    while (timer.elapsed < wait) {
      final value = await request();
      if (value['gateId'] != gateId) {
        throw StateError('checkpoint belongs to another run');
      }
      ownsGate = true;
      if (sameHeld(value)) {
        before = value;
        break;
      }
      if (value['released'] == true || value['timedOut'] == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (before == null) {
      throw StateError('causal partial-body checkpoint unavailable');
    }
    proof['gateBeforeKill'] = before;
    await persist();
    Future<ProcessResult> adb(List<String> args) => run('adb', [
      '-s',
      deviceId,
      ...args,
    ]).timeout(const Duration(seconds: 5));
    final prior = await adb(['shell', 'pidof', packageName]);
    if (prior.exitCode != 0 ||
        !RegExp(r'^\d+(\s+\d+)*$').hasMatch('${prior.stdout}'.trim())) {
      throw StateError('owned package process is not running');
    }
    final stopped = await adb(['shell', 'am', 'force-stop', packageName]);
    if (stopped.exitCode != 0) {
      throw StateError('owned package force-stop failed');
    }
    final absent = await adb(['shell', 'pidof', packageName]);
    proof['verifiedProcessAbsent'] =
        absent.exitCode == 1 &&
        '${absent.stdout}'.trim().isEmpty &&
        '${absent.stderr}'.trim().isEmpty;
    proof['gateAfterKill'] = await request();
    await persist();
    if (proof['verifiedProcessAbsent'] != true ||
        !sameHeld(proof['gateAfterKill']! as Map<String, Object?>)) {
      throw StateError(
        'held partial transfer did not span verified process death',
      );
    }
    proof['status'] = 'PASS';
  } catch (_) {
    proof['status'] = 'FAIL';
    proof['failure'] =
        'causal cut incomplete; inspect original checkpoint and ADB evidence';
    rethrow;
  } finally {
    try {
      if (ownsGate) proof['releasedCheckpoint'] = await request(true);
    } catch (_) {
      proof['status'] = 'FAIL';
      proof['cleanupFailure'] = 'owned checkpoint release failed';
    }
    await persist();
  }
  return proof;
}

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final names = [
    '--probe',
    '--gate-id',
    '--attachment-id',
    '--device',
    '--package',
    '--output',
  ];
  if (names.any((name) => option(name) == null)) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/cut_production_media_transfer.dart ${names.map((n) => '$n <value>').join(' ')}',
    );
    exitCode = 64;
    return;
  }
  try {
    final proof = await cutProductionMediaTransfer(
      fixtureProbe: Uri.parse(option('--probe')!),
      gateId: option('--gate-id')!,
      attachmentId: option('--attachment-id')!,
      deviceId: option('--device')!,
      packageName: option('--package')!,
      output: File(option('--output')!),
    );
    stdout.writeln(
      jsonEncode({
        'status': proof['status'],
        'scope':
            'owned Android process cut only; full-content recovery is not evaluated',
      }),
    );
    exitCode = proof['status'] == 'PASS' ? 0 : 1;
  } catch (_) {
    stderr.writeln(
      'Transfer cut failed; preserve the local first-attempt receipt.',
    );
    exitCode = 1;
  }
}
