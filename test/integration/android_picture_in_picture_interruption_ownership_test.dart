import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _validator =
    'scripts/validate_android_picture_in_picture_interruption.py';
const _cleanupValidator =
    'scripts/validate_android_picture_in_picture_interruption_cleanup.py';
const _fixtureRoot = 'test/fixtures';
const _appComponent =
    'com.mknoon.app.pipproof/com.mknoon.app.'
    'ReceivedVideoPictureInPictureActivity';
const _helperComponent =
    'com.mknoon.app.pipproof.test/com.mknoon.app.pipproof.'
    'PictureInPictureAudioFocusInterruptionProofActivity';
const _nonce = '0123456789abcdef0123456789abcdef';

void main() {
  test(
    'accepts one causally bound cross-UID audio-focus interruption',
    () async {
      final result = await _runValidator();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        File(result.outputPath).readAsStringSync(),
        'interruptionProof=true helperTaskId=858 helperTopResumed=true '
        'helperFocused=true focusGain=GAIN distinctUid=true nativeTerminals=1 '
        'alternateTerminals=0 pinnedTasks=0 nativeActive=false '
        'proofStartedPlayers=0\n',
      );
    },
  );

  test('accepts API 36 task headers without an intent component', () async {
    final activities = _fixture(
      'android_picture_in_picture_interruption_post_activities.txt',
    ).replaceAll('I=$_helperComponent', 'A=10472:com.mknoon.app.pipproof.test');
    final result = await _runValidator(postActivities: activities);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      File(result.outputPath).readAsStringSync(),
      contains('interruptionProof=true helperTaskId=858'),
    );
  });

  test(
    'accepts retained final-4 request history bound to the current helper UID',
    () async {
      final result = await _runValidator(
        preActivities: _fixture(
          'android_picture_in_picture_interruption_pre_activities.txt',
        ).replaceAll('10471', '10476'),
        preAudio: _fixture(
          'android_picture_in_picture_interruption_pre_audio.txt',
        ).replaceAll('10471', '10476'),
        postAudio: _fixture(
          'android_picture_in_picture_interruption_post_audio_final4_history.txt',
        ),
        logcat: _fixture(
          'android_picture_in_picture_interruption_logcat.txt',
        ).replaceAll('uid=10472', 'uid=10477'),
        appUid: '10476',
        helperUid: '10477',
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        File(result.outputPath).readAsStringSync(),
        contains('interruptionProof=true helperTaskId=858'),
      );
    },
  );

  test('rejects resolver chooser multiple and malformed components', () async {
    for (final component in <String>[
      'android/com.android.internal.app.ResolverActivity\n',
      'android/com.android.internal.app.ChooserActivity\n',
      '$_helperComponent\ncom.example/.OtherActivity\n',
      'priority=0 preferredOrder=0\n$_helperComponent\n',
      'not-a-component\n',
    ]) {
      await _expectRejected(component: component);
    }
  });

  test(
    'rejects denied same-UID missing duplicate wrong and reordered terminals',
    () async {
      final good = _fixture(
        'android_picture_in_picture_interruption_logcat.txt',
      );
      for (final logcat in <String>[
        good.replaceFirst('result=granted', 'result=denied'),
        good.replaceFirst('uid=10472', 'uid=10471'),
        good.replaceFirst(
          '[MKNOON_PIP] TERMINAL state=stopped reason=interrupted',
          '[MKNOON_PIP] TERMINAL state=stopped reason=system_close',
        ),
        good.replaceFirst(
          RegExp(r'^.*\[MKNOON_PIP\] TERMINAL.*$', multiLine: true),
          '',
        ),
        '$good${good.split('\n').lastWhere((line) => line.contains('[MKNOON_PIP] TERMINAL'))}\n',
        '${good.split('\n').lastWhere((line) => line.contains('[MKNOON_PIP] TERMINAL'))}\n'
            '${good.split('\n').first}\n',
      ]) {
        await _expectRejected(logcat: logcat);
      }
    },
  );

  test(
    'rejects missing foreground focus and mismatched helper task anchors',
    () async {
      final good = _fixture(
        'android_picture_in_picture_interruption_post_activities.txt',
      );
      final flutter = 'com.mknoon.app.pipproof/com.mknoon.app.MainActivity';
      for (final activities in <String>[
        good.replaceFirst(
          'topResumedActivity=ActivityRecord{helperRecord',
          'topResumedActivity=ActivityRecord{wrongRecord',
        ),
        good.replaceFirst(
          'mCurrentFocus=Window{helperWindow',
          'mCurrentFocus=Window{wrongWindow',
        ),
        good.replaceFirst(
          'mFocusedApp=ActivityRecord{helperRecord',
          'mFocusedApp=ActivityRecord{wrongRecord',
        ),
        good
            .replaceFirst(
              'topDisplayFocusedRootTask=Task{helper #858',
              'topDisplayFocusedRootTask=Task{flutter #856',
            )
            .replaceFirst('I=$_helperComponent}', 'I=$flutter}'),
      ]) {
        await _expectRejected(postActivities: activities);
      }
    },
  );

  test(
    'rejects cross-task duplicate and numeric-collision helper identities',
    () async {
      final good =
          _fixture(
            'android_picture_in_picture_interruption_post_activities.txt',
          ).replaceAll(
            'I=$_helperComponent',
            'A=10472:com.mknoon.app.pipproof.test',
          );
      final duplicate =
          '$good\n'
          '  * Task{duplicate #859 type=standard '
          'A=10472:com.mknoon.app.pipproof.test U=0 visible=true '
          'visibleRequested=true mode=fullscreen translucent=false sz=1}\n'
          '    * Hist #0: ActivityRecord{duplicateRecord u0 '
          '$_helperComponent t859}\n'
          '      state=RESUMED mVisibleRequested=true nowVisible=true\n'
          '      windows=[Window{duplicateWindow u0 $_helperComponent}]\n';
      for (final activities in <String>[
        good.replaceFirst(
          '* Hist  #0: ActivityRecord{helperRecord u0 $_helperComponent t858}',
          '* Hist  #0: ActivityRecord{helperRecord u0 $_helperComponent t859}',
        ),
        duplicate,
        good.replaceFirst(
          'Task{helper #858 type=standard',
          'Task{helper #8580 type=standard',
        ),
        good.replaceFirst(
          '$_helperComponent t858',
          '${_helperComponent}Collision t858',
        ),
      ]) {
        await _expectRejected(postActivities: activities);
      }
    },
  );

  test(
    'rejects non-nearest parents duplicate task IDs and inexact task fields',
    () async {
      final good =
          _fixture(
            'android_picture_in_picture_interruption_post_activities.txt',
          ).replaceAll(
            'I=$_helperComponent',
            'A=10472:com.mknoon.app.pipproof.test',
          );
      final nearestParentMismatch = good.replaceFirst(
        '    * Hist  #0: ActivityRecord{helperRecord u0 '
            '$_helperComponent t858}\n'
            '      state=RESUMED mVisibleRequested=true nowVisible=true\n'
            '      windows=[Window{helperWindow u0 $_helperComponent}]',
        '    * Task{child #999 type=standard '
            'A=10472:com.mknoon.app.pipproof.test U=0 visible=true '
            'visibleRequested=true mode=fullscreen translucent=false sz=1}\n'
            '      * Hist  #0: ActivityRecord{helperRecord u0 '
            '$_helperComponent t858}\n'
            '        state=RESUMED mVisibleRequested=true nowVisible=true\n'
            '        windows=[Window{helperWindow u0 $_helperComponent}]',
      );
      final duplicateTaskId =
          '$good\n'
          '  * Task{duplicate #858 type=standard '
          'A=10472:com.mknoon.app.pipproof.test U=0 visible=false '
          'visibleRequested=false mode=fullscreen translucent=false sz=0}\n';
      final inexactFields = good.replaceFirst(
        'visible=true visibleRequested=true mode=fullscreen',
        'visible=trueish visibleRequested=trueish mode=fullscreenish',
      );
      final conflictingRepeatedTaskObject =
          '$good\n'
          'ACTIVITY MANAGER ROOT TASKS (dumpsys activity containers)\n'
          '  * Task{conflicting #858 type=standard '
          'A=10472:com.mknoon.app.pipproof.test U=0 visible=true '
          'visibleRequested=true mode=fullscreen translucent=false sz=1}\n';
      final conflictingRepeatedTaskHeader =
          '$good\n'
          'ACTIVITY MANAGER ROOT TASKS (dumpsys activity containers)\n'
          '  * Task{helper #858 type=standard '
          'A=10472:com.mknoon.app.pipproof.test U=0 visible=false '
          'visibleRequested=true mode=fullscreen translucent=false sz=1}\n';
      final duplicateHistoryIndex = good.replaceFirst(
        '  * Task{flutter #856',
        '    * Hist #0: ActivityRecord{otherRecord u0 '
            'com.example/.OtherActivity t858}\n'
            '      state=STOPPED mVisibleRequested=false nowVisible=false\n'
            '  * Task{flutter #856',
      );
      for (final activities in <String>[
        nearestParentMismatch,
        duplicateTaskId,
        inexactFields,
        conflictingRepeatedTaskObject,
        conflictingRepeatedTaskHeader,
        duplicateHistoryIndex,
      ]) {
        await _expectRejected(postActivities: activities);
      }
    },
  );

  test('rejects retained pinned native and proof playback ownership', () async {
    final activities = _fixture(
      'android_picture_in_picture_interruption_post_activities.txt',
    );
    await _expectRejected(
      postActivities:
          '$activities\n'
          '  * Task{stale #999 type=standard A=10471:com.mknoon.app.pipproof '
          'U=0 visible=true visibleRequested=true mode=pinned sz=1}\n',
    );
    await _expectRejected(
      postActivities:
          '$activities\n'
          '  * Task{native #999 type=standard A=10471:com.mknoon.app.pipproof '
          'U=0 visible=true visibleRequested=true mode=fullscreen sz=1}\n'
          '    * Hist #0: ActivityRecord{nativeRecord u0 $_appComponent t999}\n'
          '      state=RESUMED mVisibleRequested=true nowVisible=true\n',
    );
    final audio = _fixture(
      'android_picture_in_picture_interruption_post_audio.txt',
    );
    await _expectRejected(
      postAudio:
          '$audio\n'
          'AudioPlaybackConfiguration piid:7 type:android.media.MediaPlayer '
          'u/pid:10471/24452 state:started\n',
    );
  });

  test('rejects duplicate pre owners and repeated activity sections', () async {
    final pre = _fixture(
      'android_picture_in_picture_interruption_pre_activities.txt',
    );
    await _expectRejected(preActivities: '$pre\n$pre');
    final nativeHistory = pre
        .split('\n')
        .skipWhile((line) => !line.contains('* Hist'))
        .take(4)
        .join('\n');
    await _expectRejected(preActivities: '$pre\n$nativeHistory\n');
  });

  test('rejects absent wrong and non-distinct focus transfer', () async {
    final good = _fixture(
      'android_picture_in_picture_interruption_post_audio.txt',
    );
    for (final audio in <String>[
      good.replaceFirst(
        'source:android.os.BinderProxy@helper -- pack: com.mknoon.app.pipproof.test',
        'source:android.os.BinderProxy@helper -- pack: com.mknoon.app.pipproof',
      ),
      good.replaceFirst(
        ' -- gain: GAIN ',
        ' -- gain: GAIN_TRANSIENT_MAY_DUCK ',
      ),
      good.replaceFirst(' -- uid: 10472 ', ' -- uid: 10471 '),
      good.replaceFirst(RegExp(r'^  source:.*$', multiLine: true), ''),
      good.replaceFirst(
        'No external focus policy',
        '  source:android.os.BinderProxy@proof -- pack: com.mknoon.app.pipproof '
            '-- client: $_appComponent -- gain: GAIN -- loss: none -- uid: 10471\n'
            'No external focus policy',
      ),
    ]) {
      await _expectRejected(postAudio: audio);
    }
  });

  test(
    'rejects ambiguous malformed or later stale helper request history',
    () async {
      final good = _fixture(
        'android_picture_in_picture_interruption_post_audio_final4_history.txt',
      );
      const currentRequest =
          '07-14 00:36:44:794 requestAudioFocus() from uid/pid 10477/31062 '
          'AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE '
          'clientId=android.media.AudioManager@8653a73com.mknoon.app.pipproof.'
          'PictureInPictureAudioFocusInterruptionProofActivity'
          r'$$ExternalSyntheticLambda0@2db1d30 '
          'callingPack=com.mknoon.app.pipproof.test req=1 flags=0x0 sdk=36';
      const staleRequest =
          '07-13 23:38:10:661 requestAudioFocus() from uid/pid 10475/27729 '
          'AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE '
          'clientId=android.media.AudioManager@8653a73com.mknoon.app.pipproof.'
          'PictureInPictureAudioFocusInterruptionProofActivity'
          r'$$ExternalSyntheticLambda0@2db1d30 '
          'callingPack=com.mknoon.app.pipproof.test req=1 flags=0x0 sdk=36';
      final variants = <String>[
        good.replaceFirst(currentRequest, ''),
        '$good$currentRequest\n',
        good.replaceFirst(
          '10477/31062 AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE',
          '10477/31062 AA=USAGE_MEDIA_GAME/CONTENT_TYPE_MOVIE',
        ),
        good.replaceFirst(
          '10477/31062 AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE clientId=',
          '10477/31062 AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE clientId=wrong-',
        ),
        good.replaceFirst(
          '10477/31062 AA=USAGE_MEDIA/CONTENT_TYPE_MOVIE',
          '10477/31062 AA=USAGE_MEDIA/CONTENT_TYPE_MUSIC',
        ),
        good.replaceFirst(
          currentRequest,
          currentRequest.replaceFirst(' req=1 ', ' req=2 '),
        ),
        good.replaceFirst(
          currentRequest,
          'requestAudioFocus() malformed '
          'callingPack=com.mknoon.app.pipproof.test\n$currentRequest',
        ),
        '$good$staleRequest\n',
      ];
      for (final postAudio in variants) {
        await _expectRejected(
          preActivities: _fixture(
            'android_picture_in_picture_interruption_pre_activities.txt',
          ).replaceAll('10471', '10476'),
          preAudio: _fixture(
            'android_picture_in_picture_interruption_pre_audio.txt',
          ).replaceAll('10471', '10476'),
          postAudio: postAudio,
          logcat: _fixture(
            'android_picture_in_picture_interruption_logcat.txt',
          ).replaceAll('uid=10472', 'uid=10477'),
          appUid: '10476',
          helperUid: '10477',
        );
      }
    },
  );

  test(
    'rejects duplicate focus sections and substring focus identities',
    () async {
      final pre = _fixture(
        'android_picture_in_picture_interruption_pre_audio.txt',
      );
      final post = _fixture(
        'android_picture_in_picture_interruption_post_audio.txt',
      );
      const conflictingSection =
          'Audio Focus stack entries (last is top of stack):\n'
          '  source:android.os.BinderProxy@wrong -- pack: com.example.wrong '
          '-- client: android.media.AudioManager@wrong -- gain: GAIN -- '
          'loss: none -- uid: 99999 -- attr: AudioAttributes: '
          'usage=USAGE_MEDIA content=CONTENT_TYPE_MOVIE\n'
          'No external focus policy\n';
      await _expectRejected(preAudio: '$pre\n$conflictingSection');
      await _expectRejected(postAudio: '$post\n$conflictingSection');
      await _expectRejected(
        preAudio: pre.replaceFirst(
          'ReceivedVideoPictureInPictureActivity\$\$ExternalSyntheticLambda7',
          'ReceivedVideoPictureInPictureActivityCollision'
              '\$\$ExternalSyntheticLambda7',
        ),
      );
      await _expectRejected(
        postAudio: post.replaceFirst(
          'PictureInPictureAudioFocusInterruptionProofActivity@listener',
          'PictureInPictureAudioFocusInterruptionProofActivityCollision@listener',
        ),
      );
      await _expectRejected(
        postAudio: post.replaceFirst(
          'usage=USAGE_MEDIA content=CONTENT_TYPE_MOVIE',
          'usage=USAGE_MEDIA_GAME content=CONTENT_TYPE_MOVIE_TRAILER',
        ),
      );
      await _expectRejected(
        postAudio: post.replaceFirst(
          'Audio Focus stack entries (last is top of stack):',
          'Audio Focus stack entries (last is top of stack):\n'
              '  hidden-owner: com.example.unparsed',
        ),
      );
    },
  );

  test(
    'rejects duplicate current windows and alternate helper focus attempts',
    () async {
      final activities = _fixture(
        'android_picture_in_picture_interruption_post_activities.txt',
      );
      await _expectRejected(
        postActivities: activities.replaceFirst(
          'mCurrentFocus=Window{helperWindow u0 $_helperComponent}',
          'mCurrentFocus=Window{helperWindow u0 $_helperComponent} '
              'Window{helperWindow u0 $_helperComponent}',
        ),
      );
      final logcat = _fixture(
        'android_picture_in_picture_interruption_logcat.txt',
      );
      for (final alternate in <String>[
        '[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST '
            'nonce=ffffffffffffffffffffffffffffffff gain=GAIN '
            'usage=USAGE_MEDIA content=CONTENT_TYPE_MOVIE '
            'result=denied uid=10472',
        '[MKNOON_PIP_INTERRUPT] REJECTED '
            'nonce=ffffffffffffffffffffffffffffffff reason=malformed',
        '[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST_REJECTED reason=bad_nonce',
      ]) {
        await _expectRejected(logcat: '$logcat\n$alternate\n');
      }
    },
  );

  test('rejects start output nonce UID and pre-owner mismatches', () async {
    final start = _fixture('android_picture_in_picture_interruption_start.txt');
    await _expectRejected(
      start: start.replaceFirst('Status: ok', 'Status: timeout'),
    );
    await _expectRejected(
      start: start.replaceFirst(
        'Activity: $_helperComponent',
        'Activity: com.example/.Other',
      ),
    );
    await _expectRejected(nonce: 'malformed');
    await _expectRejected(appUid: '10472');
    final preAudio = _fixture(
      'android_picture_in_picture_interruption_pre_audio.txt',
    );
    await _expectRejected(
      preAudio: preAudio.replaceFirst(
        ' -- gain: GAIN ',
        ' -- gain: GAIN_TRANSIENT ',
      ),
    );
  });

  test('cleanup focus validator rejects proof ownership fail-closed', () async {
    final clean = _fixture(
      'android_picture_in_picture_interruption_cleanup_audio.txt',
    );
    final accepted = await _runCleanupValidator(clean);
    expect(
      accepted.exitCode,
      0,
      reason: '${accepted.stdout}\n${accepted.stderr}',
    );
    expect(
      File(accepted.outputPath).readAsStringSync(),
      'cleanupFocusReleased=true appFocusOwners=0 helperFocusOwners=0\n',
    );
    for (final audio in <String>[
      _fixture('android_picture_in_picture_interruption_post_audio.txt'),
      _fixture('android_picture_in_picture_interruption_pre_audio.txt'),
      '$clean\n$clean',
      clean.replaceFirst(
        'Audio Focus stack entries (last is top of stack):',
        'Audio Focus stack entries (last is top of stack):\n'
            '  hidden-owner: com.mknoon.app.pipproof.test uid=10472',
      ),
    ]) {
      final rejected = await _runCleanupValidator(audio);
      expect(rejected.exitCode, isNot(0));
      expect(File(rejected.outputPath).existsSync(), isFalse);
    }
  });
}

String _fixture(String name) => File('$_fixtureRoot/$name').readAsStringSync();

Future<void> _expectRejected({
  String? component,
  String? start,
  String? preActivities,
  String? preAudio,
  String? postActivities,
  String? postAudio,
  String? logcat,
  String nonce = _nonce,
  String appUid = '10471',
  String helperUid = '10472',
}) async {
  final result = await _runValidator(
    component: component,
    start: start,
    preActivities: preActivities,
    preAudio: preAudio,
    postActivities: postActivities,
    postAudio: postAudio,
    logcat: logcat,
    nonce: nonce,
    appUid: appUid,
    helperUid: helperUid,
  );
  expect(
    result.exitCode,
    isNot(0),
    reason: '${result.stdout}\n${result.stderr}',
  );
  expect(File(result.outputPath).existsSync(), isFalse);
}

Future<({int exitCode, String stdout, String stderr, String outputPath})>
_runValidator({
  String? component,
  String? start,
  String? preActivities,
  String? preAudio,
  String? postActivities,
  String? postAudio,
  String? logcat,
  String nonce = _nonce,
  String appUid = '10471',
  String helperUid = '10472',
}) async {
  final directory = Directory.systemTemp.createTempSync('pip-interruption-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final inputs = <String, String>{
    'component':
        component ??
        _fixture('android_picture_in_picture_interruption_component.txt'),
    'start':
        start ?? _fixture('android_picture_in_picture_interruption_start.txt'),
    'pre-activities':
        preActivities ??
        _fixture('android_picture_in_picture_interruption_pre_activities.txt'),
    'pre-audio':
        preAudio ??
        _fixture('android_picture_in_picture_interruption_pre_audio.txt'),
    'post-activities':
        postActivities ??
        _fixture('android_picture_in_picture_interruption_post_activities.txt'),
    'post-audio':
        postAudio ??
        _fixture('android_picture_in_picture_interruption_post_audio.txt'),
    'logcat':
        logcat ??
        _fixture('android_picture_in_picture_interruption_logcat.txt'),
  };
  final paths = <String, String>{};
  for (final entry in inputs.entries) {
    final path = '${directory.path}/${entry.key}.txt';
    File(path).writeAsStringSync(entry.value);
    paths[entry.key] = path;
  }
  final output = '${directory.path}/result.txt';
  final result = await Process.run('python3', [
    _validator,
    '--resolved-component',
    paths['component']!,
    '--start-output',
    paths['start']!,
    '--pre-activities',
    paths['pre-activities']!,
    '--pre-audio',
    paths['pre-audio']!,
    '--post-activities',
    paths['post-activities']!,
    '--post-audio',
    paths['post-audio']!,
    '--logcat',
    paths['logcat']!,
    '--app-component',
    _appComponent,
    '--helper-component',
    _helperComponent,
    '--app-package',
    'com.mknoon.app.pipproof',
    '--helper-package',
    'com.mknoon.app.pipproof.test',
    '--app-uid',
    appUid,
    '--helper-uid',
    helperUid,
    '--nonce',
    nonce,
    '--output',
    output,
  ]);
  return (
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
    outputPath: output,
  );
}

Future<({int exitCode, String stdout, String stderr, String outputPath})>
_runCleanupValidator(String audio) async {
  final directory = Directory.systemTemp.createTempSync('pip-cleanup-focus-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final audioPath = '${directory.path}/audio.txt';
  final output = '${directory.path}/result.txt';
  File(audioPath).writeAsStringSync(audio);
  final result = await Process.run('python3', [
    _cleanupValidator,
    '--audio',
    audioPath,
    '--app-package',
    'com.mknoon.app.pipproof',
    '--helper-package',
    'com.mknoon.app.pipproof.test',
    '--app-uid',
    '10471',
    '--helper-uid',
    '10472',
    '--output',
    output,
  ]);
  return (
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
    outputPath: output,
  );
}
