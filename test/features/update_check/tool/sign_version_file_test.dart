import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/sign_version_file.dart';
import '../support/update_check_test_keys.dart';

class _Captured {
  final _out = StringBuffer();
  final _err = StringBuffer();
  late final IOSink stdout = _sink(_out);
  late final IOSink stderr = _sink(_err);

  static IOSink _sink(StringBuffer buffer) {
    final controller = StreamController<List<int>>();
    controller.stream.listen((bytes) => buffer.write(utf8.decode(bytes)));
    return IOSink(controller);
  }

  String get out => _out.toString();
  String get err => _err.toString();
}

void main() {
  late Directory temp;
  final repoRoot = Directory.current;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('se41_cli_');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<(int, _Captured)> run(List<String> args) async {
    final io = _Captured();
    final code = await runSignVersionFile(
      args,
      stdout: io.stdout,
      stderr: io.stderr,
      repoRoot: repoRoot,
    );
    await io.stdout.flush();
    await io.stderr.flush();
    await Future<void>.delayed(Duration.zero);
    return (code, io);
  }

  test(
    'round trip: keygen -> sign -> the app verifier accepts (AC7)',
    () async {
      final keys = '${temp.path}/keys';
      final (keygenCode, keygen) = await run(['keygen', '--out', keys]);
      expect(keygenCode, 0, reason: keygen.err);
      final publicKey = File('$keys/public_key.b64').readAsStringSync().trim();
      expect(keygen.out, contains('public key (base64): $publicKey'));
      final privateKey = File(
        '$keys/signing_key.b64',
      ).readAsStringSync().trim();
      expect(keygen.out, isNot(contains(privateKey)), reason: 'never printed');
      final mode = File('$keys/signing_key.b64').statSync().modeString();
      expect(mode, 'rw-------');

      final payload = File('${temp.path}/payload.json')
        ..writeAsBytesSync(payloadBytes(sequence: 7));
      final envelopePath = '${temp.path}/envelope.json';
      final (signCode, sign) = await run([
        'sign',
        '--key',
        '$keys/signing_key.b64',
        '--key-id',
        'k2',
        '--in',
        payload.path,
        '--out',
        envelopePath,
      ]);
      expect(signCode, 0, reason: sign.err);

      // The app's verifier, with the generated public key built in as k2.
      final check =
          VersionFileVerifier([
            TrustedVersionKey.fromBase64(
              keyId: 'k2',
              rank: 2,
              publicKeyBase64: publicKey,
            ),
          ]).verify(
            File(envelopePath).readAsBytesSync(),
            highestAcceptedRank: 0,
            requiredPlatforms: {UpdatePlatform.ios},
          );
      expect(check.isAccepted, isTrue);
      expect(check.file!.payload.sequence, 7);
      // Raw input bytes were signed, not a re-encoding.
      expect(check.file!.payloadBytes, payload.readAsBytesSync());

      final (verifyCode, verify) = await run([
        'verify',
        '--pub',
        publicKey,
        '--in',
        envelopePath,
      ]);
      expect(verifyCode, 0, reason: verify.err);
      expect(verify.out, contains('VALID keyId=k2 sequence=7'));

      // Tampered envelope: flip one payload byte.
      final envelope =
          jsonDecode(File(envelopePath).readAsStringSync())
              as Map<String, Object?>;
      final raw = base64.decode(envelope['payload']! as String)..[3] ^= 1;
      envelope['payload'] = base64.encode(raw);
      final tampered = File('${temp.path}/tampered.json')
        ..writeAsStringSync(jsonEncode(envelope));
      final (tamperedCode, tamperedIo) = await run([
        'verify',
        '--pub',
        publicKey,
        '--in',
        tampered.path,
      ]);
      expect(tamperedCode, 1);
      expect(tamperedIo.err, contains('REJECTED: badSignature'));
    },
  );

  test('keygen refuses a path inside the repo and creates nothing', () async {
    final inside = '${repoRoot.path}/build/se41_keygen_must_not_exist';
    final (code, io) = await run(['keygen', '--out', inside]);
    expect(code, 1);
    expect(io.err, contains('refusing to write keys inside the repo'));
    expect(Directory(inside).existsSync(), isFalse);

    // Through a symlink that points into the repo.
    final link = Link('${temp.path}/sneaky')..createSync(repoRoot.path);
    final (linkCode, linkIo) = await run(['keygen', '--out', '${link.path}/k']);
    expect(linkCode, 1);
    expect(linkIo.err, contains('refusing'));
    expect(Directory('${repoRoot.path}/k').existsSync(), isFalse);
  });

  test('sign refuses an invalid payload', () async {
    final keys = '${temp.path}/keys';
    expect((await run(['keygen', '--out', keys])).$1, 0);
    final cases = {
      'one platform only': payloadBytes(android: null),
      'min above latest': payloadBytes(ios: section(10, 20)),
      'bad schema': payloadBytes(schemaVersion: 2),
      'negative sequence': payloadBytes(sequence: -1),
      'not json': utf8.encode('nope'),
    };
    for (final entry in cases.entries) {
      final input = File('${temp.path}/bad.json')
        ..writeAsBytesSync(entry.value);
      final out = '${temp.path}/never.json';
      final (code, io) = await run([
        'sign',
        '--key',
        '$keys/signing_key.b64',
        '--key-id',
        'k1',
        '--in',
        input.path,
        '--out',
        out,
      ]);
      expect(code, 1, reason: entry.key);
      expect(io.err, contains('invalid payload'), reason: entry.key);
      expect(File(out).existsSync(), isFalse, reason: entry.key);
    }
  });

  test('sign refuses an unknown key id', () async {
    final keys = '${temp.path}/keys';
    expect((await run(['keygen', '--out', keys])).$1, 0);
    final input = File('${temp.path}/p.json')..writeAsBytesSync(payloadBytes());
    final (code, _) = await run([
      'sign',
      '--key',
      '$keys/signing_key.b64',
      '--key-id',
      'k9',
      '--in',
      input.path,
      '--out',
      '${temp.path}/e.json',
    ]);
    expect(code, 64);
  });
}
