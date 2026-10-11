// TEST-ONLY Ed25519 keys and envelope builders for the SE-41 update check.
// These fixed seeds are public and protect nothing. They must never be
// built into the app or used to sign a real version file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/features/update_check/domain/update_check_state.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_state_store.dart';
import 'package:flutter_app/features/update_check/infrastructure/version_file_fetcher.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

final nacl.SigningKey testOnlyK1 = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x11)),
);
final nacl.SigningKey testOnlyK2 = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x22)),
);
final nacl.SigningKey testOnlyRogue = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x99)),
);

TrustedVersionKey trustedK1() => TrustedVersionKey(
  keyId: 'k1',
  rank: 1,
  publicKey: testOnlyK1.verifyKey.asTypedList,
);

TrustedVersionKey trustedK2() => TrustedVersionKey(
  keyId: 'k2',
  rank: 2,
  publicKey: testOnlyK2.verifyKey.asTypedList,
);

VersionFileVerifier testVerifier({bool withK1 = true, bool withK2 = true}) =>
    VersionFileVerifier([if (withK1) trustedK1(), if (withK2) trustedK2()]);

/// Payload JSON bytes. Pass `null` for a section to leave it out.
Uint8List payloadBytes({
  int schemaVersion = 1,
  int sequence = 1,
  int issuedAt = 1760000000,
  Map<String, Object?>? ios = const {
    'latestBuild': 120,
    'minBuild': 100,
    'reasonCode': 'general',
  },
  Map<String, Object?>? android = const {
    'latestBuild': 120,
    'minBuild': 100,
    'reasonCode': 'general',
  },
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'schemaVersion': schemaVersion,
      'sequence': sequence,
      'issuedAt': issuedAt,
      'ios': ?ios,
      'android': ?android,
    }),
  ),
);

Map<String, Object?> section(int latestBuild, int minBuild, [Object? reason]) =>
    {
      'latestBuild': latestBuild,
      'minBuild': minBuild,
      'reasonCode': ?reason,
    };

/// A signed envelope. [signer] defaults to the key that matches [keyId].
Uint8List signedEnvelope(
  List<int> payload, {
  String keyId = 'k1',
  nacl.SigningKey? signer,
}) {
  final key = signer ?? (keyId == 'k2' ? testOnlyK2 : testOnlyK1);
  return encodeVersionEnvelope(
    keyId: keyId,
    payloadBytes: payload,
    signature: key.sign(Uint8List.fromList(payload)).signature.asTypedList,
  );
}

/// Replays a queue of download results; null = failed download.
class FakeVersionFileFetcher extends VersionFileFetcher {
  FakeVersionFileFetcher([List<Uint8List?>? responses])
    : responses = responses ?? [];

  final List<Uint8List?> responses;
  int calls = 0;

  @override
  Future<Uint8List?> fetch(Uri url) async {
    calls++;
    return responses.isEmpty ? null : responses.removeAt(0);
  }
}

/// A store in a temp directory.
class TempStateStore {
  TempStateStore._(this.directory)
    : store = UpdateCheckStateStore(directoryProvider: () async => directory);

  static Future<TempStateStore> create() async => TempStateStore._(
    await Directory.systemTemp.createTemp('se41_update_check_'),
  );

  final Directory directory;
  final UpdateCheckStateStore store;

  File get file => File('${directory.path}/${UpdateCheckStateStore.fileName}');

  Future<UpdateCheckState> load() => store.load();

  Future<void> dispose() => directory.delete(recursive: true);
}
