@Tags(['device'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

const fixtureImageSha256 =
    '5f9a120f909900543cc05debbc500d4c2bb8a624d11bb6af4d5e6cfa91bf923d';
const fixtureVideoSha256 =
    'f49ead6c99aae9827a143e6778ea74d25b0594a414acc846a6176b99b20149ea';

const platformProof = String.fromEnvironment('MEDIA_EGRESS_PLATFORM');
const androidMode = String.fromEnvironment('MEDIA_EGRESS_ANDROID_MODE');
const permissionScenario = String.fromEnvironment(
  'MEDIA_EGRESS_PERMISSION_SCENARIO',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // This proof is intentionally operator-driven while native chooser/picker UI
  // owns focus. Live test bindings otherwise consume physical touches and print
  // finder suggestions instead of delivering them to the Pass/Fail controls.
  binding.shouldPropagateDevicePointerEvents = true;

  testWidgets(
    'android scoped and legacy native egress proof',
    (tester) async {
      if (platformProof != 'android') return;
      expect(androidMode, anyOf('scoped', 'legacy'));
      if (androidMode == 'legacy') {
        expect(permissionScenario, anyOf('deny', 'allow'));
      }
      await _runProof(tester, includeFiles: false);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'ios photos files and share native egress proof',
    (tester) async {
      if (platformProof != 'ios') return;
      expect(permissionScenario, anyOf('deny', 'allow'));
      await _runProof(tester, includeFiles: permissionScenario == 'allow');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _runProof(
  WidgetTester tester, {
  required bool includeFiles,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final directory = await Directory(
    p.join(docs.path, 'media', 'egress-proof-$runId'),
  ).create(recursive: true);
  final image = await _copyFixture(
    'integration_test/fixtures/received_media_egress_fixture.jpg',
    p.join(directory.path, 'proof_image_$runId.jpg'),
  );
  final video = await _copyFixture(
    'integration_test/fixtures/received_media_egress_fixture.mp4',
    p.join(directory.path, 'proof_video_$runId.mp4'),
  );
  final before = [image.readAsBytesSync(), video.readAsBytesSync()];
  expect(sha256.convert(before[0]).toString(), fixtureImageSha256);
  expect(sha256.convert(before[1]).toString(), fixtureVideoSha256);
  final selection = [
    ReceivedMediaEgressCandidate(
      attachmentId: 'proof_image_$runId',
      storedPath: image.path,
      mime: 'image/jpeg',
    ),
    ReceivedMediaEgressCandidate(
      attachmentId: 'proof_video_$runId',
      storedPath: video.path,
      mime: 'video/mp4',
    ),
  ];
  final service = ReceivedMediaEgressService();
  final expectedImageName = 'proof_image_$runId.jpg';
  final expectedVideoName = 'proof_video_$runId.mp4';

  await _requireOperatorPass(
    tester,
    'PRECONDITION — permission reset\n'
    'Confirm the app was reinstalled/reset and the requested Photos/storage '
    'permission is notDetermined (no prior allow/deny decision).',
  );
  debugPrint(
    '[MEDIA_EGRESS_LEDGER] run=$runId platform=$platformProof '
    'mode=$androidMode scenario=$permissionScenario '
    'expected=$expectedImageName,$expectedVideoName '
    'sourceBefore=$fixtureImageSha256,$fixtureVideoSha256',
  );

  await _requireOperatorPass(
    tester,
    'ACTION — Photos/Gallery\nChoose '
    '${permissionScenario.isEmpty ? 'Allow' : permissionScenario}.\n'
    'Expected outputs: $expectedImageName and $expectedVideoName.',
  );
  final photos = await service.perform(
    requestId: 'photos_$runId',
    destination: MediaEgressDestination.photos,
    selection: selection,
  );
  expect(
    photos.outcome,
    permissionScenario == 'deny'
        ? MediaEgressOutcome.permissionDenied
        : MediaEgressOutcome.saved,
  );
  if (permissionScenario == 'deny') {
    await _requireOperatorPass(
      tester,
      'VERIFY — denial created no output\n'
      'Confirm neither $expectedImageName nor $expectedVideoName exists in '
      'Photos/Gallery. Select Fail if either output exists.',
    );
  } else {
    await _requireOperatorPass(
      tester,
      'VERIFY — Photos/Gallery output\n'
      'Confirm both $expectedImageName and $expectedVideoName are visible. '
      'Select Fail if either is absent.',
    );
  }

  if (includeFiles) {
    await _requireOperatorPass(
      tester,
      'ACTION — Files cancellation\nCancel the copy picker.',
    );
    final cancelled = await service.perform(
      requestId: 'files_cancel_$runId',
      destination: MediaEgressDestination.files,
      selection: selection,
    );
    expect(cancelled.outcome, MediaEgressOutcome.cancelled);
    await _requireOperatorPass(
      tester,
      'VERIFY — cancellation created no output\nConfirm no test output exists '
      'at the cancelled destination.',
    );
    await _requireOperatorPass(
      tester,
      'ACTION — Files copy\nChoose a destination and confirm both items.\n'
      'Expected outputs: $expectedImageName and $expectedVideoName.',
    );
    final files = await service.perform(
      requestId: 'files_save_$runId',
      destination: MediaEgressDestination.files,
      selection: selection,
    );
    expect(files.outcome, MediaEgressOutcome.saved);
    await _requireOperatorPass(
      tester,
      'VERIFY — Files copy\nConfirm both exact expected names exist and '
      'are readable. Select Fail otherwise.',
    );
  }

  await _requireOperatorPass(
    tester,
    'ACTION — Share\nOn Android choose the Mknoon egress proof receiver; '
    'on iOS dismiss after presentation.',
  );
  final shared = await service.perform(
    requestId: 'share_$runId',
    destination: MediaEgressDestination.share,
    selection: selection,
  );
  expect(shared.outcome, MediaEgressOutcome.presented);
  expect(image.readAsBytesSync(), before[0]);
  expect(video.readAsBytesSync(), before[1]);
  await _requireOperatorPass(
    tester,
    platformProof == 'android'
        ? 'VERIFY — receiver truth\nConfirm count=2 and ordered hashes:\n'
              '0: $fixtureImageSha256\n1: $fixtureVideoSha256'
        : 'VERIFY — share presentation\nConfirm the activity controller was '
              'presented once and dismissed without altering either source.',
  );
  expect(
    sha256.convert(image.readAsBytesSync()).toString(),
    fixtureImageSha256,
  );
  expect(
    sha256.convert(video.readAsBytesSync()).toString(),
    fixtureVideoSha256,
  );
  await _requireOperatorPass(
    tester,
    'CLEANUP LEDGER\nRemove only this run’s outputs:\n'
    '$expectedImageName\n$expectedVideoName\n'
    'Confirm cleanup is complete, or Fail to keep the run non-green.',
  );
  debugPrint(
    '[MEDIA_EGRESS_LEDGER] run=$runId verdict=PASS '
    'sourceAfter=$fixtureImageSha256,$fixtureVideoSha256 cleanup=confirmed',
  );
}

Future<File> _copyFixture(String asset, String destination) async {
  final data = await rootBundle.load(asset);
  return File(destination).writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<void> _requireOperatorPass(WidgetTester tester, String message) async {
  final completer = Completer<bool>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => completer.complete(false),
                        child: const Text('Fail'),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: () => completer.complete(true),
                        child: const Text('Pass'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final passed = await completer.future.timeout(const Duration(minutes: 3));
  expect(
    passed,
    isTrue,
    reason: 'Operator marked this proof step Fail: $message',
  );
}
