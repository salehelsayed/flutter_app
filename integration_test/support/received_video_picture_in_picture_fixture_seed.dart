import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const receivedVideoPictureInPictureFixtureSha256 =
    'd10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5';
const receivedVideoPictureInPictureFixtureBytes = 2463571;
const receivedVideoPictureInPictureFixtureDurationMs = 72000;
const receivedVideoPictureInPictureFixtureRelativePath =
    'media/plan243-proof/received_video_picture_in_picture_fixture.mp4';

/// Waits for the host runner to seed the reviewed fixture into app-owned media.
///
/// The fixture is deliberately not a pubspec asset and cannot ship in a
/// production bundle. No production startup path imports this test helper.
Future<File> waitForReceivedVideoPictureInPictureFixture({
  Duration timeout = const Duration(seconds: 90),
}) async {
  final documents = await getApplicationDocumentsDirectory();
  final expectedRoot = Directory(p.join(documents.path, 'media')).absolute;
  final fixture = File(
    p.join(documents.path, receivedVideoPictureInPictureFixtureRelativePath),
  );
  final deadline = DateTime.now().add(timeout);
  while (!fixture.existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!fixture.existsSync()) {
    throw StateError('Host-seeded PiP fixture was not present before timeout.');
  }

  final canonicalRoot = expectedRoot.resolveSymbolicLinksSync();
  final canonicalFixture = fixture.resolveSymbolicLinksSync();
  if (!canonicalFixture.startsWith('$canonicalRoot${Platform.pathSeparator}')) {
    throw StateError('Host-seeded PiP fixture escaped app-owned media.');
  }
  if (fixture.lengthSync() != receivedVideoPictureInPictureFixtureBytes) {
    throw StateError('Host-seeded PiP fixture byte count did not match.');
  }
  final digest = sha256.convert(await fixture.readAsBytes()).toString();
  if (digest != receivedVideoPictureInPictureFixtureSha256) {
    throw StateError('Host-seeded PiP fixture digest did not match.');
  }
  return File(canonicalFixture);
}
