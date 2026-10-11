// SE-41 version-file signing CLI. Run with `dart run tool/sign_version_file.dart`.
//
//   keygen --out <dir>
//       Writes a new Ed25519 key pair OUTSIDE the repo. The private key file
//       (signing_key.b64, base64 32-byte seed) gets 0600 permissions. Prints
//       only the base64 public key.
//   sign --key <path> --key-id <k1|k2> --in <payload.json> --out <envelope.json>
//       Validates the payload with the app's rules (both platforms required),
//       signs the raw input bytes and writes the envelope.
//   verify --pub <base64> --in <envelope.json> [--key-id <k1|k2>]
//       Runs the app's verifier with the given public key.
//
// Verification is the app's own code (lib/features/update_check/domain/),
// not a copy. Production keys are generated offline by the owner (SE-41 O2);
// never commit or paste a private key.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

const _keyRanks = {'k1': 1, 'k2': 2};
const _privateKeyFile = 'signing_key.b64';
const _publicKeyFile = 'public_key.b64';

Future<void> main(List<String> args) async {
  exitCode = await runSignVersionFile(args, stdout: stdout, stderr: stderr);
}

/// Entry point for tests; returns the exit code.
Future<int> runSignVersionFile(
  List<String> args, {
  required IOSink stdout,
  required IOSink stderr,
  Directory? repoRoot,
}) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 64;
  }
  final command = args.first;
  final Map<String, String> options;
  try {
    options = _parseOptions(args.skip(1).toList());
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}\n$_usage');
    return 64;
  }
  try {
    switch (command) {
      case 'keygen':
        return await _keygen(
          options,
          stdout,
          stderr,
          repoRoot ?? _defaultRepoRoot(),
        );
      case 'sign':
        return await _sign(options, stdout, stderr);
      case 'verify':
        return await _verify(options, stdout, stderr);
      default:
        stderr.writeln('error: unknown command "$command"\n$_usage');
        return 64;
    }
  } on _UsageError catch (e) {
    stderr.writeln('error: ${e.message}');
    return 64;
  }
}

const _usage = '''usage:
  dart run tool/sign_version_file.dart keygen --out <dir outside the repo>
  dart run tool/sign_version_file.dart sign --key <path> --key-id <k1|k2> --in <payload.json> --out <envelope.json>
  dart run tool/sign_version_file.dart verify --pub <base64> --in <envelope.json> [--key-id <k1|k2>]''';

class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    final name = args[i];
    if (!name.startsWith('--') || i + 1 >= args.length) {
      throw FormatException('expected "--name value", got "$name"');
    }
    options[name.substring(2)] = args[i + 1];
  }
  return options;
}

String _required(Map<String, String> options, String name) =>
    options[name] ?? (throw _UsageError('missing --$name'));

Directory _defaultRepoRoot() =>
    File.fromUri(Platform.script).parent.parent; // tool/ -> repo root

/// Resolves symlinks in the longest existing prefix of [path]; the missing
/// tail is appended as is (after removing `.` and `..`).
String _resolveAllowingMissing(String path) {
  var current = Uri.file(File(path).absolute.path).normalizePath().toFilePath();
  final missing = <String>[];
  while (!FileSystemEntity.isDirectorySync(current)) {
    final parent = File(current).parent.path;
    if (parent == current) break;
    missing.insert(0, current.split(Platform.pathSeparator).last);
    current = parent;
  }
  final resolved = Directory(current).resolveSymbolicLinksSync();
  return [resolved, ...missing].join(Platform.pathSeparator);
}

Future<int> _keygen(
  Map<String, String> options,
  IOSink stdout,
  IOSink stderr,
  Directory repoRoot,
) async {
  // Check BEFORE creating anything, so a refused path leaves no trace.
  final resolvedOut = _resolveAllowingMissing(_required(options, 'out'));
  final resolvedRepo = repoRoot.resolveSymbolicLinksSync();
  if (resolvedOut == resolvedRepo ||
      resolvedOut.startsWith('$resolvedRepo${Platform.pathSeparator}')) {
    stderr.writeln(
      'error: refusing to write keys inside the repo ($resolvedOut). '
      'Use a directory outside $resolvedRepo.',
    );
    return 1;
  }
  await Directory(resolvedOut).create(recursive: true);
  final privateFile = File('$resolvedOut/$_privateKeyFile');
  final publicFile = File('$resolvedOut/$_publicKeyFile');
  if (privateFile.existsSync() || publicFile.existsSync()) {
    stderr.writeln('error: $resolvedOut already holds a key; not overwriting');
    return 1;
  }
  final signingKey = nacl.SigningKey.generate();
  final publicKey = base64.encode(signingKey.verifyKey.asTypedList);

  // Create the file empty, restrict it, then write the secret.
  privateFile.createSync(exclusive: true);
  final chmod = await Process.run('chmod', ['600', privateFile.path]);
  if (chmod.exitCode != 0) {
    privateFile.deleteSync();
    stderr.writeln('error: chmod 600 failed: ${chmod.stderr}');
    return 1;
  }
  privateFile.writeAsStringSync(
    '${base64.encode(signingKey.seed.asTypedList)}\n',
    flush: true,
  );
  publicFile.writeAsStringSync('$publicKey\n', flush: true);

  stdout.writeln('private key: ${privateFile.path} (mode 0600)');
  stdout.writeln('public key file: ${publicFile.path}');
  stdout.writeln('public key (base64): $publicKey');
  return 0;
}

Future<int> _sign(
  Map<String, String> options,
  IOSink stdout,
  IOSink stderr,
) async {
  final keyId = _required(options, 'key-id');
  if (!_keyRanks.containsKey(keyId)) {
    throw _UsageError('--key-id must be k1 or k2');
  }
  final seed = base64.decode(
    File(_required(options, 'key')).readAsStringSync().trim(),
  );
  final payloadBytes = File(_required(options, 'in')).readAsBytesSync();
  final parsed = parseVersionPayload(
    payloadBytes,
    requiredPlatforms: UpdatePlatform.values.toSet(),
  );
  if (parsed.payload == null) {
    stderr.writeln(
      'error: invalid payload (${parsed.rejection!.name}); not signed',
    );
    return 1;
  }
  final signingKey = nacl.SigningKey.fromSeed(Uint8List.fromList(seed));
  final signature = signingKey.sign(payloadBytes).signature.asTypedList;
  final envelope = encodeVersionEnvelope(
    keyId: keyId,
    payloadBytes: payloadBytes,
    signature: signature,
  );
  if (envelope.length > maxVersionFileBytes) {
    stderr.writeln(
      'error: envelope is ${envelope.length} bytes, over the '
      '$maxVersionFileBytes-byte limit the app enforces',
    );
    return 1;
  }
  // Self-check with the app's verifier before writing.
  final check =
      VersionFileVerifier([
        TrustedVersionKey(
          keyId: keyId,
          rank: _keyRanks[keyId]!,
          publicKey: signingKey.verifyKey.asTypedList,
        ),
      ]).verify(
        envelope,
        highestAcceptedRank: 0,
        requiredPlatforms: UpdatePlatform.values.toSet(),
      );
  if (!check.isAccepted) {
    stderr.writeln('error: self-verify failed (${check.rejection!.name})');
    return 1;
  }
  final out = _required(options, 'out');
  File(out).writeAsBytesSync(envelope, flush: true);
  stdout.writeln(
    'signed: $out keyId=$keyId sequence=${parsed.payload!.sequence} '
    'bytes=${envelope.length}',
  );
  return 0;
}

Future<int> _verify(
  Map<String, String> options,
  IOSink stdout,
  IOSink stderr,
) async {
  final publicKey = base64.decode(_required(options, 'pub').trim());
  final envelope = File(_required(options, 'in')).readAsBytesSync();
  // Trust the given key under the requested keyId, or under the keyId the
  // file declares when none is given (only k1/k2 are ever built in).
  var keyId = options['key-id'];
  if (keyId == null) {
    try {
      final declared = (jsonDecode(utf8.decode(envelope)) as Map)['keyId'];
      keyId = declared is String ? declared : null;
    } catch (_) {
      keyId = null;
    }
  }
  if (keyId == null || !_keyRanks.containsKey(keyId)) {
    stderr.writeln('REJECTED: keyId is not k1 or k2');
    return 1;
  }
  final check =
      VersionFileVerifier([
        TrustedVersionKey(
          keyId: keyId,
          rank: _keyRanks[keyId]!,
          publicKey: publicKey,
        ),
      ]).verify(
        envelope,
        highestAcceptedRank: 0,
        requiredPlatforms: UpdatePlatform.values.toSet(),
      );
  if (!check.isAccepted) {
    stderr.writeln('REJECTED: ${check.rejection!.name}');
    return 1;
  }
  final payload = check.file!.payload;
  stdout.writeln('VALID keyId=$keyId sequence=${payload.sequence}');
  for (final entry in payload.platforms.entries) {
    stdout.writeln(
      '  ${entry.key.wireName}: latestBuild=${entry.value.latestBuild} '
      'minBuild=${entry.value.minBuild} '
      'reasonCode=${entry.value.reasonCode.wireName}',
    );
  }
  return 0;
}
