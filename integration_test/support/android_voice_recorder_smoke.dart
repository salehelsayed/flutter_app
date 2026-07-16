import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real native recording retained for a later production transport action.
///
/// The caller owns [delete]. Keeping this separate from the recorder smoke is
/// important for the full voice-message campaign: the same bytes recorded by
/// the Android plugin must be sent, received, hash-matched, and played. A host
/// fixture or generated zero-filled file cannot substitute for this object.
final class AndroidVoiceRecordingFixture {
  const AndroidVoiceRecordingFixture({
    required this.file,
    required this.durationMs,
    required this.sizeBytes,
    required this.mime,
    required this.sha256Digest,
  });

  final File file;
  final int durationMs;
  final int sizeBytes;
  final String mime;
  final String sha256Digest;

  AudioRecording get recording => AudioRecording(
    filePath: file.path,
    durationMs: durationMs,
    sizeBytes: sizeBytes,
    mime: mime,
  );

  Future<bool> delete() async {
    if (await file.exists()) await file.delete();
    return !await file.exists();
  }
}

/// Records a real AAC/M4A fixture through the production Android plugin.
///
/// This is an endpoint prerequisite, not a claim of voice-message E2E. The
/// full proof must subsequently use [AndroidVoiceRecordingFixture.recording]
/// with the production send path and compare [sha256Digest] after the receiver
/// has downloaded and played the attachment.
Future<AndroidVoiceRecordingFixture> recordAndroidVoiceMessageFixture({
  Duration captureDuration = const Duration(seconds: 2),
}) async {
  final recorder = RecordAudioRecorderService();
  File? outputFile;
  var completed = false;

  try {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'the production voice recorder prerequisite requires Android',
    );

    final hasPermission = await _safeHasPermission(recorder);
    expect(
      hasPermission,
      isTrue,
      reason:
          'RECORD_AUDIO must be pregranted. Missing permission or a '
          'missing native record plugin is a blocked/failed proof, not a skip.',
    );

    await recorder.start(outputPath: '').timeout(const Duration(seconds: 10));
    expect(recorder.isRecording, true);

    await Future<void>.delayed(captureDuration);

    final recording = await recorder.stop().timeout(
      const Duration(seconds: 15),
    );
    expect(recording, isNotNull);
    if (recording == null) {
      throw StateError('production recorder returned no recording');
    }
    expect(recording.durationMs, greaterThan(1500));
    expect(recording.mime, 'audio/mp4');

    final file = File(recording.filePath);
    outputFile = file;
    expect(await file.exists(), true);
    expect(recording.sizeBytes, greaterThan(0));
    expect(await file.length(), recording.sizeBytes);

    final bytes = await file.readAsBytes();
    expect(
      bytes.length,
      greaterThanOrEqualTo(12),
      reason: 'native recorder output is too short to be an MP4/M4A file',
    );
    expect(
      String.fromCharCodes(bytes.sublist(4, 8)),
      'ftyp',
      reason: 'native recorder output is missing the MP4/M4A ftyp box',
    );

    final fixture = AndroidVoiceRecordingFixture(
      file: file,
      durationMs: recording.durationMs,
      sizeBytes: recording.sizeBytes,
      mime: recording.mime,
      sha256Digest: sha256.convert(bytes).toString(),
    );
    completed = true;
    return fixture;
  } finally {
    try {
      if (recorder.isRecording) {
        await recorder.cancel().timeout(const Duration(seconds: 5));
      }
      if (!completed && outputFile != null && await outputFile.exists()) {
        await outputFile.delete();
      }
    } finally {
      await recorder.dispose();
    }
  }
}

/// Exercises the production Android `record` plugin and cleans up its output.
///
/// The host harness owns physical-target selection and RECORD_AUDIO pregrant.
/// Keeping the proof callable lets the universal sims APK dispatch it only
/// after its runtime invocation has been acknowledged.
Future<Map<String, Object?>> runAndroidVoiceRecorderSmoke() async {
  final fixture = await recordAndroidVoiceMessageFixture();
  var temporaryFileDeleted = false;

  try {
    expect(await fixture.file.exists(), isTrue);
  } finally {
    temporaryFileDeleted = await fixture.delete();
  }

  return <String, Object?>{
    'scenario': 'android.voice_recorder_native_smoke',
    'status': 'passed',
    'permissionPregranted': true,
    'realRecordPlugin': true,
    'mime': fixture.mime,
    'sizeBytes': fixture.sizeBytes,
    'durationMs': fixture.durationMs,
    'recordedPlaintextSha256': fixture.sha256Digest,
    'decodable': true,
    'temporaryFileDeleted': temporaryFileDeleted,
  };
}

Future<bool> _safeHasPermission(RecordAudioRecorderService recorder) async {
  try {
    return await recorder.hasPermission();
  } on MissingPluginException {
    return false;
  }
}
