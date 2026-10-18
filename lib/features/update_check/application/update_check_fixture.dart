import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../domain/version_file_verifier.dart';
import '../infrastructure/update_check_fixture_contract.dart';
import '../infrastructure/version_file_fetcher.dart';
import 'update_check_switch.dart';

export '../infrastructure/update_check_fixture_contract.dart';

/// Records the actual update-action target in the opted-in disposable app.
/// This observes URL selection; it does not claim a store install succeeded.
Future<void> recordUpdateCheckFixtureStoreOpen(Uri url) async {
  if (!UpdateCheckSwitch.fromEnvironment().testProfileEnabled) return;
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/$updateCheckFixtureDirectory',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}/$updateCheckFixtureStoreOpen');
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    jsonEncode({'url': url.toString()}),
    flush: true,
  );
  await temporary.rename(file.path);
}

// Foreground and minimal-engine checks share this restricted, TEST-only source.
VersionFileVerifier? updateCheckFixtureVerifier({
  UpdateCheckSwitch? updateSwitch,
  String publicKeyBase64 = const String.fromEnvironment(
    'MKNOON_SE41_TEST_PUBLIC_KEY_B64',
  ),
}) {
  final fixture =
      (updateSwitch ?? UpdateCheckSwitch.fromEnvironment()).testProfileEnabled;
  if (!fixture) {
    if (publicKeyBase64.isNotEmpty) {
      throw StateError(
        'An SE41 test key requires the approved fixture opt-in.',
      );
    }
    return null;
  }
  return VersionFileVerifier([
    TrustedVersionKey.fromBase64(
      keyId: updateCheckFixtureKeyId,
      rank: 1,
      publicKeyBase64: publicKeyBase64,
    ),
  ]);
}

VersionFileFetcher? updateCheckFixtureFetcher({
  UpdateCheckSwitch? updateSwitch,
  Future<Directory> Function()? directoryProvider,
}) => (updateSwitch ?? UpdateCheckSwitch.fromEnvironment()).testProfileEnabled
    ? _FixtureFileFetcher(directoryProvider ?? getApplicationDocumentsDirectory)
    : null;

final class _FixtureFileFetcher extends VersionFileFetcher {
  _FixtureFileFetcher(this.directoryProvider);
  final Future<Directory> Function() directoryProvider;

  @override
  Future<Uint8List?> fetch(Uri url) async {
    if (!isAllowedVersionFileUrl(url)) return null;
    try {
      final directory = await directoryProvider();
      final file = File(
        '${directory.path}/$updateCheckFixtureDirectory/$updateCheckFixtureEnvelope',
      );
      final body = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, maxVersionFileBytes + 1)) {
        body.add(chunk);
      }
      return body.length > maxVersionFileBytes ? null : body.takeBytes();
    } on FileSystemException {
      return null;
    }
  }
}
