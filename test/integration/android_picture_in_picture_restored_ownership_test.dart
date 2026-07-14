import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator =
      'scripts/validate_android_picture_in_picture_restored_ownership.py';
  const activitiesFixture =
      'test/fixtures/android_picture_in_picture_restored_finished_residue_activities.txt';
  const audioFixture =
      'test/fixtures/android_picture_in_picture_restored_flutter_audio.txt';
  const package = 'com.mknoon.app.pipproof';
  const flutterComponent = '$package/com.mknoon.app.MainActivity';
  const nativeComponent =
      '$package/com.mknoon.app.ReceivedVideoPictureInPictureActivity';

  Future<ProcessResult> validate({
    required String activities,
    String? audio,
  }) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final directory = Directory.systemTemp.createTempSync(
      'pip-restored-ownership-$nonce-',
    );
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final activitiesFile = File('${directory.path}/activities.txt')
      ..writeAsStringSync(activities);
    final audioFile = File('${directory.path}/audio.txt')
      ..writeAsStringSync(audio ?? File(audioFixture).readAsStringSync());
    final outputFile = File('${directory.path}/result.txt');
    return Process.run('python3', <String>[
      validator,
      '--activities',
      activitiesFile.path,
      '--audio',
      audioFile.path,
      '--flutter-component',
      flutterComponent,
      '--native-component',
      nativeComponent,
      '--uid',
      '10466',
      '--expected-audio-tracks',
      '1',
      '--output',
      outputFile.path,
    ]);
  }

  test('accepts a finished native history/window residue', () async {
    final result = await validate(
      activities: File(activitiesFixture).readAsStringSync(),
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('restoredOwnership=true'));
    expect(result.stdout.toString(), contains('finishedNativeResidue=true'));
  });

  test(
    'rejects task ID prefixes and same-component anchors from another task',
    () async {
      final accepted = File(activitiesFixture).readAsStringSync();
      final counterexamples = <String, String>{
        'focused-root task ID prefix collision': accepted.replaceFirst(
          'Task{flutter-task #845 type=standard',
          'Task{flutter-task #84 type=standard',
        ),
        'focused root from another same-component task': accepted.replaceFirst(
          'topDisplayFocusedRootTask=Task{flutter-task #845 type=standard',
          'topDisplayFocusedRootTask=Task{other-task #846 type=standard',
        ),
        'top resumed from another same-component task': accepted.replaceFirst(
          'topResumedActivity=ActivityRecord{flutter-record u0 '
              '$flutterComponent t845}',
          'topResumedActivity=ActivityRecord{other-record u0 '
              '$flutterComponent t846}',
        ),
        'resumed activity from another same-component task': accepted
            .replaceFirst(
              'ResumedActivity: ActivityRecord{flutter-record u0 '
                  '$flutterComponent t845}',
              'ResumedActivity: ActivityRecord{other-record u0 '
                  '$flutterComponent t846}',
            ),
        'current focus from another same-component task': accepted.replaceFirst(
          'mCurrentFocus=Window{flutter-window u0 $flutterComponent}',
          'mCurrentFocus=Window{other-window u0 $flutterComponent}',
        ),
        'focused app from another same-component task': accepted.replaceFirst(
          'mFocusedApp=ActivityRecord{flutter-record u0 '
              '$flutterComponent t845}',
          'mFocusedApp=ActivityRecord{other-record u0 '
              '$flutterComponent t846}',
        ),
      };

      for (final entry in counterexamples.entries) {
        final result = await validate(activities: entry.value);
        expect(
          result.exitCode,
          isNot(0),
          reason: '${entry.key}: ${result.stdout}\n${result.stderr}',
        );
      }
    },
  );

  test('rejects every active native semantic state and pinned topology', () async {
    final accepted = File(activitiesFixture).readAsStringSync();
    final counterexamples = <String, String>{
      'native resumed': accepted
          .replaceFirst(
            '* Hist  #1: ActivityRecord{native-record u0 $nativeComponent t845 f}}',
            '* Hist  #1: ActivityRecord{native-record u0 $nativeComponent t845}',
          )
          .replaceFirst(
            'state=STOPPING finishing=true',
            'state=RESUMED finishing=false',
          )
          .replaceFirst('mVisibleRequested=false', 'mVisibleRequested=true'),
      'native top resumed': accepted.replaceFirst(
        'topResumedActivity=ActivityRecord{flutter-record u0 $flutterComponent t845}',
        'topResumedActivity=ActivityRecord{native-record u0 $nativeComponent t845}',
      ),
      'native resumed activity': accepted.replaceFirst(
        'ResumedActivity: ActivityRecord{flutter-record u0 $flutterComponent t845}',
        'ResumedActivity: ActivityRecord{native-record u0 $nativeComponent t845}',
      ),
      'native current focus': accepted.replaceFirst(
        'mCurrentFocus=Window{flutter-window u0 $flutterComponent}',
        'mCurrentFocus=Window{native-window u0 $nativeComponent}',
      ),
      'native focused app': accepted.replaceFirst(
        'mFocusedApp=ActivityRecord{flutter-record u0 $flutterComponent t845}',
        'mFocusedApp=ActivityRecord{native-record u0 $nativeComponent t845}',
      ),
      'native pinned':
          '$accepted\n'
          '  * Task{native-task #846 type=standard A=10466:$package '
          'U=0 visible=true visibleRequested=true mode=pinned sz=1}\n'
          '    * Hist #0: ActivityRecord{native-record u0 '
          '$nativeComponent t846}\n',
      'duplicate fullscreen Flutter task':
          '$accepted\n'
          '  * Task{duplicate #999 type=standard I=$flutterComponent '
          'U=0 visible=true visibleRequested=true mode=fullscreen sz=1}\n',
    };

    for (final entry in counterexamples.entries) {
      final result = await validate(activities: entry.value);
      expect(
        result.exitCode,
        isNot(0),
        reason: '${entry.key}: ${result.stdout}\n${result.stderr}',
      );
    }
  });

  test(
    'rejects native MediaPlayer and duplicate Flutter AudioTrack owners',
    () async {
      final activities = File(activitiesFixture).readAsStringSync();
      final acceptedAudio = File(audioFixture).readAsStringSync();
      final counterexamples = <String, String>{
        'native MediaPlayer': acceptedAudio.replaceFirst(
          'state:released',
          'state:started',
        ),
        'duplicate AudioTrack':
            '$acceptedAudio\n'
            '  AudioPlaybackConfiguration piid:5000 deviceIds:[3] '
            'type:android.media.AudioTrack u/pid:10466/19489 state:started\n',
      };

      for (final entry in counterexamples.entries) {
        final result = await validate(
          activities: activities,
          audio: entry.value,
        );
        expect(
          result.exitCode,
          isNot(0),
          reason: '${entry.key}: ${result.stdout}\n${result.stderr}',
        );
      }
    },
  );
}
