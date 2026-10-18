import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/debug/production_journeys/production_group_media_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../shared/fakes/fake_just_audio.dart';

const _invocation = SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: 'android.e2e.production',
  scenarioId: groupNewMemberMediaJourney,
  role: 'bob',
  runId: 'f6-watch',
  nonce: 'f6-watch-nonce',
  values: {},
);
const _messageId = 'incoming-post-join-media-f6-watch';

Map<String, Object?> _command(int sequence, String operation) => {
  'invocation': _invocation.toJson(),
  'sequence': sequence,
  'operation': operation,
  'arguments': <String, Object?>{},
};

Future<ProductionJourneyController> _controller(WidgetTester tester) async {
  final directory = Directory.systemTemp.createTempSync('media-watch-test-');
  final controller = ProductionJourneyController(
    directory: directory,
    profileId: _invocation.profileId,
    invocation: _invocation,
  );
  addTearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });
  bindProductionGroupMediaControls(
    controller: controller,
    identityRepository: _UnusedIdentity(),
    groupRepository: _UnusedGroups(),
    groupMessageRepository: _UnusedMessages(),
    mediaAttachmentRepository: _UnusedAttachments(),
    mediaFileManager: _UnusedFiles(),
  );
  controller.foregroundPush.bind((_) async {});
  controller.markRuntimeReady();
  await tester.runAsync(controller.start);
  return controller;
}

Future<void> _flushPlayer(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

void _state({
  required bool playing,
  String messageId = _messageId,
  String? attachmentId,
  String processingState = 'ready',
}) => emitFlowEvent(
  layer: 'FL',
  event: audioPlayerPlaybackStateEvent,
  details: {
    'messageId': messageId,
    'attachmentId': attachmentId ?? '$messageId-voice',
    'playing': playing,
    'processingState': processingState,
  },
);

void main() {
  late JustAudioPlatform original;
  late FakeJustAudioPlatform platform;
  setUp(() {
    original = JustAudioPlatform.instance;
    platform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
  });
  tearDown(() async {
    await platform.disposeAllPlayers(DisposeAllPlayersRequest());
    JustAudioPlatform.instance = original;
  });

  testWidgets(
    'latches a real brief voice state between polling ticks on reopen',
    (tester) async {
      const observationsEnabled =
          bool.fromEnvironment('E2E_TEST_MODE') ||
          String.fromEnvironment('SIMS_BUILD_PROFILE_ID') != '';
      final controller = await _controller(tester);
      var sequence = 0;
      try {
        for (var pass = 0; pass < 2; pass++) {
          final load = platform.enqueueLoad(
            reportedDuration: const Duration(milliseconds: 560),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: AudioPlayerWidget(
                  interruptionEvents: Stream<AudioInterruptionEvent>.empty(),
                  attachment: MediaAttachment(
                    id: '$_messageId-voice',
                    messageId: _messageId,
                    mime: 'audio/mpeg',
                    size: 4406,
                    mediaType: 'audio',
                    localPath: '/tmp/f6-watch.mp3',
                    downloadStatus: 'done',
                    durationMs: 560,
                    createdAt: '2026-10-18T00:00:00Z',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await load.started;
          load.complete();
          await tester.pumpAndSettle();
          await _flushPlayer(tester);
          await controller.execute(_command(++sequence, 'media_watch_playing'));
          await tester.tap(find.byIcon(Icons.play_arrow_rounded));
          for (var i = 0; i < 5 && platform.playCallCount <= pass; i++) {
            await _flushPlayer(tester);
          }
          expect(
            platform.playCallCount,
            pass + 1,
            reason: 'join the actual platform play command before observing',
          );
          expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 10));
          await tester.tap(find.byIcon(Icons.pause_rounded));
          await _flushPlayer(tester);
          expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
          final result = await controller.execute(
            _command(++sequence, 'media_playing_result'),
          );
          expect(
            result['playingObserved'],
            observationsEnabled,
            reason: 'pass $pass',
          );
          final observations = result['observations'] as Map;
          if (observationsEnabled) {
            expect(result['seenAtMs'], greaterThanOrEqualTo(0));
            expect(
              (observations['firstPlayingState'] as Map)['durationMs'],
              560,
            );
            expect(
              (observations['firstStopRequest'] as Map)['cause'],
              'pauseTap',
            );
            expect(
              (observations['firstStoppedState'] as Map)['playing'],
              isFalse,
            );
          } else {
            expect(result['seenAtMs'], isNull);
            expect(observations, isEmpty);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await _flushPlayer(tester);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _flushPlayer(tester);
      }
    },
  );

  testWidgets(
    'ignores stale unrelated and nonplaying events and releases its sink',
    (tester) async {
      var previousEvents = 0;
      final previous = installScopedE2EFlowEventSink((_) => previousEvents++);
      addTearDown(previous.release);
      final controller = await _controller(tester);
      _state(playing: true);
      await controller.execute(_command(1, 'media_watch_playing'));
      _state(playing: false);
      _state(playing: true, messageId: 'another-message');
      _state(playing: true, attachmentId: 'unrelated-attachment');
      _state(playing: true, processingState: 'completed');
      emitFlowEvent(
        layer: 'FL',
        event: audioPlayerActionEvent,
        details: {
          'messageId': _messageId,
          'attachmentId': '$_messageId-voice',
          'action': 'play',
          'playing': true,
          'processingState': 'ready',
        },
      );
      final result = await controller.execute(
        _command(2, 'media_playing_result'),
      );
      expect(result['playingObserved'], isFalse);
      final beforeClose = previousEvents;
      _state(playing: false);
      expect(previousEvents, beforeClose + 1);
      await controller.execute(_command(3, 'media_watch_playing'));
      controller.dispose();
      final beforeDispose = previousEvents;
      _state(playing: false);
      expect(previousEvents, beforeDispose + 1);
    },
  );

  testWidgets(
    'rearm clears the prior result and the 20 second deadline fences events',
    (tester) async {
      final controller = await _controller(tester);
      await controller.execute(_command(1, 'media_watch_playing'));
      _state(playing: true);
      expect(
        (await controller.execute(
          _command(2, 'media_playing_result'),
        ))['playingObserved'],
        isTrue,
      );
      await controller.execute(_command(3, 'media_watch_playing'));
      await tester.pump(const Duration(seconds: 20));
      _state(playing: true);
      expect(
        (await controller.execute(
          _command(4, 'media_playing_result'),
        ))['playingObserved'],
        isFalse,
      );
    },
  );
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation member) => throw StateError(
    'watch must not call a repository: ${member.memberName}',
  );
}

class _UnusedIdentity extends _Unused implements IdentityRepository {}

class _UnusedGroups extends _Unused implements GroupRepository {}

class _UnusedMessages extends _Unused implements GroupMessageRepository {}

class _UnusedAttachments extends _Unused implements MediaAttachmentRepository {}

class _UnusedFiles extends _Unused implements MediaFileManager {}
