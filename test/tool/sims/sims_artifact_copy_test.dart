import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_orchestrator.dart';

/// The prepared iOS bundle and its cache copy must keep the artifact digest
/// (bytes, permissions and links) whichever copy path runs.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('sims-copy-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a copied tree keeps bytes, modes and links', () {
    final source = Directory('${root.path}/src')..createSync();
    File('${source.path}/Runner.app/Runner')
      ..createSync(recursive: true)
      ..writeAsStringSync('binary');
    Process.runSync('chmod', ['755', '${source.path}/Runner.app/Runner']);
    File('${source.path}/Runner.app/Info.plist').writeAsStringSync('plist');
    Process.runSync('chmod', ['600', '${source.path}/Runner.app/Info.plist']);
    Link('${source.path}/Runner.app/Current').createSync('Runner');
    final destination = Directory('${root.path}/dst')..createSync();

    simsCopyArtifactDirectory(source, destination);

    expect(
      sha256.convert(simsPreparedArtifactDigestBytes(destination)),
      sha256.convert(simsPreparedArtifactDigestBytes(source)),
    );
    expect(
      Link('${destination.path}/Runner.app/Current').targetSync(),
      'Runner',
    );
    expect(
      File('${destination.path}/Runner.app/Runner').statSync().mode & 0x1ff,
      0x1ed,
    );
  });
}
