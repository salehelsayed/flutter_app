// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/waveform_seek_bar.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../fakes/fake_just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserInitiatedVoicePlaybackPolicy', () {
    Future<void> flushInterruptionTasks() =>
        Future<void>.delayed(Duration.zero);

    test('disables the plugin default interruption handler', () {
      expect(
        UserInitiatedVoicePlaybackPolicy.handlePluginInterruptions,
        isFalse,
      );
    });

    test(
      'mixes notification audio on iOS and ducks instead of pausing on Android',
      () {
        final configuration =
            UserInitiatedVoicePlaybackPolicy.audioSessionConfiguration;

        expect(
          configuration.avAudioSessionCategory,
          AVAudioSessionCategory.playback,
        );
        expect(
          configuration.avAudioSessionMode,
          AVAudioSessionMode.spokenAudio,
        );
        expect(
          configuration.avAudioSessionCategoryOptions,
          AVAudioSessionCategoryOptions.mixWithOthers,
        );
        expect(
          configuration.androidAudioAttributes?.contentType,
          AndroidAudioContentType.speech,
        );
        expect(
          configuration.androidAudioAttributes?.usage,
          AndroidAudioUsage.media,
        );
        expect(
          configuration.androidAudioFocusGainType,
          AndroidAudioFocusGainType.gain,
        );
        expect(configuration.androidWillPauseWhenDucked, isFalse);
      },
    );

    test('duck interruption begin and end preserve voice playback state', () {
      var pauseCalls = 0;
      var resumeCalls = 0;
      final handler = UserInitiatedVoiceInterruptionHandler(
        isPlaying: () => true,
        pause: () async => pauseCalls++,
        resume: () async => resumeCalls++,
      );

      handler.handle(AudioInterruptionEvent(true, AudioInterruptionType.duck));
      handler.handle(AudioInterruptionEvent(false, AudioInterruptionType.duck));

      expect(pauseCalls, 0);
      expect(resumeCalls, 0);
    });

    test(
      'pause interruption pauses active voice and owns exactly one resume',
      () async {
        var playing = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => playing,
          pause: () async {
            pauseCalls++;
            playing = false;
          },
          resume: () async {
            resumeCalls++;
            playing = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        expect(pauseCalls, 1);
        expect(playing, isFalse);

        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();

        expect(resumeCalls, 1);
        expect(playing, isTrue);
      },
    );

    test(
      'pause interruption never restarts already paused or cancelled voice',
      () async {
        var playing = false;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => playing,
          pause: () async {
            pauseCalls++;
            playing = false;
          },
          resume: () async {
            resumeCalls++;
            playing = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        expect(pauseCalls, 0);
        expect(resumeCalls, 0);

        playing = true;
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.cancelPendingResume();
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();
        expect(pauseCalls, 1);
        expect(resumeCalls, 0);
      },
    );

    test(
      'cancelling an in-flight interruption resume prevents a stale restart',
      () async {
        var playing = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final resumeStarted = Completer<void>();
        final allowResumeToSettle = Completer<void>();
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => playing,
          pause: () async {
            pauseCalls++;
            playing = false;
          },
          resume: () async {
            resumeCalls++;
            resumeStarted.complete();
            await allowResumeToSettle.future;
            playing = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();
        expect(pauseCalls, 1);
        expect(playing, isFalse);

        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await resumeStarted.future;
        expect(resumeCalls, 1);

        // Models a source change or disposal after resume has started but
        // before its asynchronous platform command settles.
        handler.cancelPendingResume();
        allowResumeToSettle.complete();
        await flushInterruptionTasks();

        expect(playing, isFalse);
        expect(pauseCalls, greaterThan(1));
      },
    );

    test(
      'a second pause interruption supersedes an in-flight auto-resume',
      () async {
        var playing = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final firstResumeStarted = Completer<void>();
        final allowFirstResumeToSettle = Completer<void>();
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => playing,
          pause: () async {
            pauseCalls++;
            playing = false;
          },
          resume: () async {
            resumeCalls++;
            if (resumeCalls == 1) {
              firstResumeStarted.complete();
              await allowFirstResumeToSettle.future;
            }
            playing = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await firstResumeStarted.future;

        // The platform resume command is unresolved and has not reported the
        // player as active yet. This second interruption must still supersede
        // it, own a new pause/resume cycle, and ignore duplicate callbacks.
        expect(playing, isFalse);
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );

        allowFirstResumeToSettle.complete();
        for (var i = 0; i < 5; i++) {
          await flushInterruptionTasks();
        }

        expect(
          pauseCalls,
          3,
          reason:
              'initial pause, second interruption pause, and stale-resume re-pause',
        );
        expect(resumeCalls, 2, reason: 'one resume per completed interruption');
        expect(playing, isTrue);
      },
    );

    test(
      'cancelling an in-flight resume denies a later pause cycle resume authority',
      () async {
        var playing = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final firstResumeStarted = Completer<void>();
        final allowFirstResumeToSettle = Completer<void>();
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => playing,
          pause: () async {
            pauseCalls++;
            playing = false;
          },
          resume: () async {
            resumeCalls++;
            firstResumeStarted.complete();
            await allowFirstResumeToSettle.future;
            playing = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await firstResumeStarted.future;

        // A user pause, source change, or disposal revokes the first cycle's
        // authority while its already-issued platform play call is unresolved.
        handler.cancelPendingResume();
        expect(playing, isFalse);

        // The cancelled in-flight command must not make this callback look as
        // though active playback entered a new reversible interruption.
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );

        allowFirstResumeToSettle.complete();
        for (var i = 0; i < 5; i++) {
          await flushInterruptionTasks();
        }

        expect(resumeCalls, 1, reason: 'cancellation denies a second resume');
        expect(playing, isFalse, reason: 'the stale play command is re-paused');
        expect(pauseCalls, 3);
      },
    );

    test(
      'unknown loss clears pause ownership and never auto-resumes voice',
      () async {
        var isPlaying = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => isPlaying,
          pause: () async {
            pauseCalls++;
            isPlaying = false;
          },
          resume: () async {
            resumeCalls++;
            isPlaying = true;
          },
        );

        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.unknown),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.unknown),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();

        expect(pauseCalls, 1);
        expect(resumeCalls, 0);
        expect(isPlaying, isFalse);

        isPlaying = true;
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.unknown),
        );
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.unknown),
        );
        await flushInterruptionTasks();

        expect(pauseCalls, 2);
        expect(resumeCalls, 0);
        expect(isPlaying, isFalse);
      },
    );

    test(
      'becoming noisy pauses and cancels any pending automatic resume',
      () async {
        var isPlaying = true;
        var pauseCalls = 0;
        var resumeCalls = 0;
        final handler = UserInitiatedVoiceInterruptionHandler(
          isPlaying: () => isPlaying,
          pause: () async {
            pauseCalls++;
            isPlaying = false;
          },
          resume: () async {
            resumeCalls++;
            isPlaying = true;
          },
        );

        handler.handleBecomingNoisy();
        expect(pauseCalls, 1);
        expect(isPlaying, isFalse);

        isPlaying = true;
        handler.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        handler.handleBecomingNoisy();
        handler.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flushInterruptionTasks();

        expect(pauseCalls, 2);
        expect(resumeCalls, 0);
        expect(isPlaying, isFalse);
      },
    );
  });

  Widget buildApp(
    MediaAttachment attachment, {
    bool requireVerifiedContentHash = false,
    VoidCallback? onRetryUnavailableMedia,
    String? renderedSemanticsLabel,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AudioPlayerWidget(
          attachment: attachment,
          requireVerifiedContentHash: requireVerifiedContentHash,
          onRetryUnavailableMedia: onRetryUnavailableMedia,
          renderedSemanticsLabel: renderedSemanticsLabel,
        ),
      ),
    );
  }

  const baseAttachment = MediaAttachment(
    id: 'att-audio-001',
    messageId: 'msg-001',
    mime: 'audio/mp4',
    size: 10000,
    mediaType: 'audio',
    durationMs: 5000,
    downloadStatus: 'done',
    createdAt: '2026-02-26T10:00:00.000Z',
    // localPath intentionally null so player stays in unloaded state
    // (avoids needing a real audio file)
  );

  MediaAttachment availableAttachment({
    required String id,
    required String localPath,
    required int? durationMs,
  }) {
    return MediaAttachment(
      id: id,
      messageId: 'msg-$id',
      mime: 'audio/mp4',
      size: 10000,
      mediaType: 'audio',
      durationMs: durationMs,
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-07-11T20:00:00.000Z',
      waveform: const [0.2, 0.7, 0.4],
    );
  }

  Future<void> flushAsyncPlayerTasks(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  Future<void> settleCompletedLoad(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await flushAsyncPlayerTasks(tester);
  }

  group('AudioPlayerWidget', () {
    late JustAudioPlatform originalPlatform;
    late _TrackingFakeJustAudioPlatform fakePlatform;

    setUp(() {
      originalPlatform = JustAudioPlatform.instance;
      fakePlatform = _TrackingFakeJustAudioPlatform();
      JustAudioPlatform.instance = fakePlatform;
    });

    tearDown(() async {
      await fakePlatform.disposeAllPlayers(DisposeAllPlayersRequest());
      JustAudioPlatform.instance = originalPlatform;
    });

    testWidgets('renders WaveformSeekBar when attachment has waveform data', (
      tester,
    ) async {
      final attachment = baseAttachment.copyWith(
        waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
      );
      await tester.pumpWidget(buildApp(attachment));

      expect(find.byType(WaveformSeekBar), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('falls back to Slider when waveform is null', (tester) async {
      await tester.pumpWidget(buildApp(baseAttachment));

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(WaveformSeekBar), findsNothing);
    });

    testWidgets('play/pause button is always present', (tester) async {
      await tester.pumpWidget(buildApp(baseAttachment));
      // Should find the play icon
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets(
      'transient pause retains an offscreen player through its owned resume',
      (tester) async {
        final interruptions =
            StreamController<AudioInterruptionEvent>.broadcast(sync: true);
        final scrollController = ScrollController();
        addTearDown(interruptions.close);
        addTearDown(scrollController.dispose);
        final load = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 6),
        );
        final attachment = availableAttachment(
          id: 'transient-offscreen',
          localPath: '/tmp/transient_offscreen.m4a',
          durationMs: 6000,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ListView.builder(
                controller: scrollController,
                itemCount: 24,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return SizedBox(
                      height: 120,
                      child: AudioPlayerWidget(
                        key: const ValueKey('transient-offscreen-player'),
                        attachment: attachment,
                        interruptionEvents: interruptions.stream,
                      ),
                    );
                  }
                  return SizedBox(height: 400, child: Text('Tall row $index'));
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await load.started;
        load.complete();
        await settleCompletedLoad(tester);

        expect(scrollController.offset, 0);
        expect(find.byType(AudioPlayerWidget), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        final playButton = tester.widget<GestureDetector>(
          find.ancestor(
            of: find.byIcon(Icons.play_arrow_rounded),
            matching: find.byType(GestureDetector),
          ),
        );
        expect(playButton.onTap, isNotNull);
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        for (var i = 0; i < 5 && fakePlatform.playCallCount == 0; i++) {
          await flushAsyncPlayerTasks(tester);
        }
        expect(fakePlatform.playCallCount, 1);

        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();
        expect(fakePlatform.disposePlayerCallCount, 0);

        interruptions.add(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        await flushAsyncPlayerTasks(tester);

        expect(
          fakePlatform.disposePlayerCallCount,
          0,
          reason:
              'an interruption-owned pause must not release offscreen playback',
        );
        expect(fakePlatform.activePlayerIds, hasLength(1));

        interruptions.add(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flushAsyncPlayerTasks(tester);

        expect(fakePlatform.playCallCount, 2);
        expect(fakePlatform.disposePlayerCallCount, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'known attachment duration renders before delayed local source load completes',
      (tester) async {
        final load = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 6),
        );
        final attachment = availableAttachment(
          id: 'known-duration',
          localPath: '/tmp/known_duration.m4a',
          durationMs: 5500,
        );

        var loadStarted = false;
        var knownLabelCount = 0;
        var placeholderCount = 0;
        var playCallsWhileLoading = -1;
        try {
          await tester.pumpWidget(buildApp(attachment));
          await tester.pump();
          await load.started;

          loadStarted = load.hasStarted;
          knownLabelCount = find.text('0:05').evaluate().length;
          placeholderCount = find.text('--:--').evaluate().length;
          await tester.tap(find.byIcon(Icons.play_arrow_rounded));
          await tester.pump();
          playCallsWhileLoading = fakePlatform.playCallCount;
        } finally {
          load.complete();
          await settleCompletedLoad(tester);
        }

        expect(loadStarted, isTrue);
        expect(knownLabelCount, 1);
        expect(placeholderCount, 0);
        expect(playCallsWhileLoading, 0);
      },
    );

    testWidgets(
      'known duration stays visible while replacement audio source loads',
      (tester) async {
        final firstLoad = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 6),
        );
        final replacementLoad = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 7),
        );
        final initialAttachment = availableAttachment(
          id: 'replacement-duration',
          localPath: '/tmp/replacement_initial.m4a',
          durationMs: 5500,
        );
        final replacementAttachment = availableAttachment(
          id: 'replacement-duration',
          localPath: '/tmp/replacement_next.m4a',
          durationMs: 5500,
        );

        var replacementStarted = false;
        var knownLabelCount = 0;
        var placeholderCount = 0;
        var loadedPaths = <String>[];
        try {
          await tester.pumpWidget(buildApp(initialAttachment));
          await tester.pump();
          await firstLoad.started;
          firstLoad.complete();
          await settleCompletedLoad(tester);

          await tester.pumpWidget(buildApp(replacementAttachment));
          await tester.pump();
          for (var i = 0; i < 5 && !replacementLoad.hasStarted; i++) {
            await flushAsyncPlayerTasks(tester);
          }

          replacementStarted = replacementLoad.hasStarted;
          knownLabelCount = find.text('0:05').evaluate().length;
          placeholderCount = find.text('--:--').evaluate().length;
          loadedPaths = fakePlatform.loadedUris
              .map((uri) => Uri.parse(uri).path)
              .toList();
        } finally {
          firstLoad.complete();
          replacementLoad.complete();
          await settleCompletedLoad(tester);
        }

        expect(replacementStarted, isTrue);
        expect(knownLabelCount, 1);
        expect(placeholderCount, 0);
        expect(loadedPaths, contains('/tmp/replacement_initial.m4a'));
        expect(loadedPaths, contains('/tmp/replacement_next.m4a'));
      },
    );

    testWidgets(
      'player duration supersedes attachment duration after delayed load completes',
      (tester) async {
        final load = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 6),
        );
        final attachment = availableAttachment(
          id: 'player-duration',
          localPath: '/tmp/player_duration.m4a',
          durationMs: 5500,
        );

        await tester.pumpWidget(buildApp(attachment));
        await tester.pump();
        await load.started;
        load.complete();
        await settleCompletedLoad(tester);

        expect(find.text('0:06'), findsOneWidget);
        expect(find.text('0:05'), findsNothing);
      },
    );

    testWidgets(
      'P269 voice render semantics appears only after the real player load settles',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final load = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(seconds: 2),
        );
        final attachment = availableAttachment(
          id: 'p269-voice',
          localPath: '/tmp/p269_voice.m4a',
          durationMs: 1700,
        );

        await tester.pumpWidget(
          buildApp(
            attachment,
            renderedSemanticsLabel: 'P269 receiver voice rendered',
          ),
        );
        await tester.pump();
        await load.started;
        expect(
          find.bySemanticsLabel(RegExp('P269 receiver voice rendered')),
          findsNothing,
        );

        load.complete();
        await settleCompletedLoad(tester);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'P269 receiver voice rendered',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('P269 receiver voice rendered')),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'unknown available audio keeps placeholder until player reports duration',
      (tester) async {
        for (final durationMs in <int?>[null, 0]) {
          final load = fakePlatform.enqueueLoad(
            reportedDuration: const Duration(seconds: 6),
          );
          final attachment = availableAttachment(
            id: 'unknown-duration-${durationMs ?? 'null'}',
            localPath: '/tmp/unknown_duration_${durationMs ?? 'null'}.m4a',
            durationMs: durationMs,
          );

          await tester.pumpWidget(buildApp(attachment));
          await tester.pump();
          await load.started;
          final placeholderBeforeLoad = find.text('--:--').evaluate().length;
          final zeroBeforeLoad = find.text('0:00').evaluate().length;

          load.complete();
          await settleCompletedLoad(tester);

          expect(placeholderBeforeLoad, 1);
          expect(zeroBeforeLoad, 0);
          expect(find.text('0:06'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'quarantined (integrity_failed) audio shows the couldn\'t-verify terminal '
      'label and NO retry (INV-DL-3)',
      (tester) async {
        var retried = false;
        final quarantined = baseAttachment.copyWith(
          localPath: '/tmp/quarantined.m4a',
          downloadStatus: kMediaDownloadStatusIntegrityFailed,
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'key-audio',
          encryptionNonce: 'nonce-audio',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        await tester.pumpWidget(
          buildApp(
            quarantined,
            requireVerifiedContentHash: true,
            onRetryUnavailableMedia: () => retried = true,
          ),
        );

        // Tamper gets the distinct honest label and is NOT retryable — retrying
        // the same descriptor would just re-fail.
        expect(find.text("Couldn't verify this media"), findsOneWidget);
        expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);
        expect(find.byType(WaveformSeekBar), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(retried, isFalse);
      },
    );

    testWidgets(
      'transient failed audio under the ceiling still exposes a retry affordance',
      (tester) async {
        var retried = false;
        final failed = baseAttachment.copyWith(
          localPath: '/tmp/failed.m4a',
          downloadStatus: kMediaDownloadStatusFailed,
          downloadRetryCount: 1,
        );

        await tester.pumpWidget(
          buildApp(failed, onRetryUnavailableMedia: () => retried = true),
        );

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Retry unavailable media'),
          findsOneWidget,
        );

        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await tester.pump();
        expect(retried, isTrue);
      },
    );

    testWidgets(
      'terminal download_failed audio shows the unavailable label and NO retry',
      (tester) async {
        var retried = false;
        final terminal = baseAttachment.copyWith(
          localPath: '/tmp/terminal.m4a',
          downloadStatus: kMediaDownloadStatusDownloadFailed,
          downloadRetryCount: kMaxDownloadRetries,
        );

        await tester.pumpWidget(
          buildApp(terminal, onRetryUnavailableMedia: () => retried = true),
        );

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);
        expect(find.byType(WaveformSeekBar), findsNothing);
        expect(retried, isFalse);
      },
    );

    testWidgets('229: evicted audio shows removed state and explicit retry', (
      tester,
    ) async {
      var retryCount = 0;
      final attachment = baseAttachment.copyWith(
        downloadStatus: kMediaDownloadStatusEvicted,
        waveform: [0.2, 0.6, 0.4],
      );
      await tester.pumpWidget(
        buildApp(attachment, onRetryUnavailableMedia: () => retryCount++),
      );
      await tester.pump();

      // Truthful removed state — not a disabled player, not the generic
      // unavailable pill, no loader.
      expect(
        find.byKey(const ValueKey('evicted-media-audio-att-audio-001')),
        findsOneWidget,
      );
      expect(find.text('Local copy removed'), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byType(WaveformSeekBar), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Explicit, user-authoritative Retry: exactly one transfer request
      // per tap, none on build.
      expect(retryCount, 0);
      final retryKey = const ValueKey(
        'evicted-media-retry-msg-001-att-audio-001',
      );
      expect(find.byKey(retryKey), findsOneWidget);
      await tester.tap(find.byKey(retryKey));
      await tester.pump();
      expect(retryCount, 1);
    });
  });
}

class _TrackingFakeJustAudioPlatform extends FakeJustAudioPlatform {
  final Map<String, AudioPlayerPlatform> _activePlayers = {};
  int disposePlayerCallCount = 0;

  Iterable<String> get activePlayerIds => _activePlayers.keys;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = await super.init(request);
    _activePlayers[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    disposePlayerCallCount++;
    _activePlayers.remove(request.id);
    return super.disposePlayer(request);
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    _activePlayers.clear();
    return super.disposeAllPlayers(request);
  }
}
