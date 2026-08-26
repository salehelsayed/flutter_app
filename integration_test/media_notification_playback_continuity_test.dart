@Tags(<String>['device'])
library;

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/received_video_picture_in_picture_fixture_seed.dart';

const _proofPlatform = String.fromEnvironment(
  'MEDIA_NOTIFICATION_PLAYBACK_PROOF_PLATFORM',
);

const _sameChatPeerId = 'playback-proof-same-chat-peer';
const _voiceOtherChatPeerId = 'playback-proof-voice-other-chat-peer';
const _videoOtherChatPeerId = 'playback-proof-video-other-chat-peer';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'normal incoming chat notifications never interrupt active voice or video',
    (tester) async {
      expect(_proofPlatform, 'android');

      final fixture = await waitForReceivedVideoPictureInPictureFixture();
      final contentRegistry = _MemoryContentRegistry();
      final notificationService = FlutterNotificationService(
        requestApplePermissions: false,
        notificationIdResolver: (conversationKey) async =>
            switch (conversationKey) {
              _sameChatPeerId => 45101,
              _voiceOtherChatPeerId => 45102,
              _videoOtherChatPeerId => 45103,
              _ => 45199,
            },
        notificationContentRegistryResolver: () async => contentRegistry,
      );
      await notificationService.initialize();
      await notificationService.clearDeliveredNotifications();
      addTearDown(() async {
        await notificationService.clearDeliveredNotifications();
        notificationService.dispose();
      });

      final inspector = FlutterLocalNotificationsPlugin();
      final android = inspector
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      expect(android, isNotNull);
      await _waitFor(
        () async => await android!.areNotificationsEnabled() == true,
        reason:
            'The disposable proof package did not receive POST_NOTIFICATIONS.',
      );
      await _expectAudiblePrimaryChannel(android!);

      final voice = UserInitiatedVoicePlaybackPolicy.createPlayer();
      final voiceStates = <PlayerState>[];
      var monitorVoiceContinuity = false;
      var voicePauseTransitions = 0;
      final voiceStateSubscription = voice.playerStateStream.listen((state) {
        voiceStates.add(state);
        if (monitorVoiceContinuity &&
            !state.playing &&
            state.processingState != ProcessingState.completed) {
          voicePauseTransitions++;
        }
      });
      addTearDown(() async {
        await voiceStateSubscription.cancel();
        await voice.dispose();
      });

      await voice.setFilePath(fixture.path);
      final audioSession = await AudioSession.instance;
      await audioSession.configure(
        UserInitiatedVoicePlaybackPolicy.audioSessionConfiguration,
      );
      unawaited(voice.play());
      await _waitFor(() async => voice.playing, reason: 'Voice did not start.');
      await _waitForPositionAdvance(
        position: () => voice.position,
        isPlaying: () => voice.playing,
        reason: 'Voice position did not begin advancing.',
      );
      monitorVoiceContinuity = true;

      final voiceSameChatBefore = voice.position;
      final sameChatResult = await maybeShowNotification(
        notificationService: notificationService,
        appVisibility: _ProofVisibility(visibleConversation: _sameChatPeerId),
        contactPeerId: _sameChatPeerId,
        senderUsername: 'User A',
        messageText: 'same-chat playback continuity proof',
        messageId: 'same-chat-playback-proof-message',
      );
      expect(
        sameChatResult,
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      await _holdContinuityWindow(
        duration: const Duration(seconds: 1),
        isPlaying: () => voice.playing,
      );
      expect(
        await inspector.getActiveNotifications(),
        isEmpty,
        reason:
            'A visible same-chat message must not enter the native notification '
            'boundary, so it cannot produce a tone.',
      );
      expect(voice.position, greaterThan(voiceSameChatBefore));
      expect(voicePauseTransitions, 0, reason: '$voiceStates');
      debugPrint(
        '[MEDIA_NOTIFICATION_PLAYBACK_PROOF] SAME_CHAT '
        'nativeCards=0 voicePlaying=true voicePauseTransitions=0',
      );

      final voiceOtherChatBefore = voice.position;
      final voiceNotificationResult = await maybeShowNotification(
        notificationService: notificationService,
        appVisibility: _ProofVisibility(),
        contactPeerId: _voiceOtherChatPeerId,
        senderUsername: 'User A',
        messageText: 'different-chat voice continuity proof',
        messageId: 'different-chat-voice-playback-proof-message',
      );
      expect(voiceNotificationResult, NotificationPresentationResult.osPosted);
      final voiceCard = await _waitForNativeCard(
        inspector,
        title: 'User A',
        body: 'different-chat voice continuity proof',
      );
      expect(voiceCard.channelId, mknoonMessagesChannelId);
      await _holdContinuityWindow(
        duration: const Duration(seconds: 2),
        isPlaying: () => voice.playing,
      );
      expect(voice.position, greaterThan(voiceOtherChatBefore));
      expect(voicePauseTransitions, 0, reason: '$voiceStates');
      debugPrint(
        '[MEDIA_NOTIFICATION_PLAYBACK_PROOF] DIFFERENT_CHAT_VOICE '
        'nativeCard=true channel=$mknoonMessagesChannelId '
        'voicePlaying=true voicePauseTransitions=0',
      );

      monitorVoiceContinuity = false;
      await voice.pause();
      await notificationService.clearDeliveredNotifications();

      final video = VideoPlayerControllerAdapter(fixture.path);
      var monitorVideoContinuity = false;
      var videoPauseTransitions = 0;
      var lastVideoPlaying = false;
      void recordVideoState() {
        final playing = video.isPlaying;
        if (monitorVideoContinuity && lastVideoPlaying && !playing) {
          videoPauseTransitions++;
        }
        lastVideoPlaying = playing;
      }

      video.addListener(recordVideoState);
      addTearDown(() async {
        video.removeListener(recordVideoState);
        await video.dispose();
      });
      await video.initialize();
      await video.play();
      await _waitFor(
        () async => video.isPlaying,
        reason: 'Video did not start.',
      );
      await _waitForPositionAdvance(
        position: () => video.position,
        isPlaying: () => video.isPlaying,
        reason: 'Video position did not begin advancing.',
      );
      lastVideoPlaying = video.isPlaying;
      monitorVideoContinuity = true;

      final videoSameChatBefore = video.position;
      final videoSameChatResult = await maybeShowNotification(
        notificationService: notificationService,
        appVisibility: _ProofVisibility(visibleConversation: _sameChatPeerId),
        contactPeerId: _sameChatPeerId,
        senderUsername: 'User A',
        messageText: 'same-chat video continuity proof',
        messageId: 'same-chat-video-playback-proof-message',
      );
      expect(
        videoSameChatResult,
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      await _holdContinuityWindow(
        duration: const Duration(seconds: 1),
        isPlaying: () => video.isPlaying,
      );
      expect(await inspector.getActiveNotifications(), isEmpty);
      expect(video.position, greaterThan(videoSameChatBefore));
      expect(videoPauseTransitions, 0);

      final videoOtherChatBefore = video.position;
      final videoNotificationResult = await maybeShowNotification(
        notificationService: notificationService,
        appVisibility: _ProofVisibility(),
        contactPeerId: _videoOtherChatPeerId,
        senderUsername: 'User A',
        messageText: 'different-chat video continuity proof',
        messageId: 'different-chat-video-playback-proof-message',
      );
      expect(videoNotificationResult, NotificationPresentationResult.osPosted);
      final videoCard = await _waitForNativeCard(
        inspector,
        title: 'User A',
        body: 'different-chat video continuity proof',
      );
      expect(videoCard.channelId, mknoonMessagesChannelId);
      await _holdContinuityWindow(
        duration: const Duration(seconds: 2),
        isPlaying: () => video.isPlaying,
      );
      expect(video.position, greaterThan(videoOtherChatBefore));
      expect(videoPauseTransitions, 0);
      debugPrint(
        '[MEDIA_NOTIFICATION_PLAYBACK_PROOF] DIFFERENT_CHAT_VIDEO '
        'nativeCard=true channel=$mknoonMessagesChannelId '
        'videoPlaying=true videoPauseTransitions=0',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _expectAudiblePrimaryChannel(
  AndroidFlutterLocalNotificationsPlugin android,
) async {
  final channels = await android.getNotificationChannels();
  final primary = channels?.where((channel) {
    return channel.id == mknoonMessagesChannelId;
  }).singleOrNull;
  expect(primary, isNotNull);
  expect(primary!.importance, Importance.high);
  expect(primary.playSound, isTrue);
  expect(primary.audioAttributesUsage, AudioAttributesUsage.notification);
}

Future<ActiveNotification> _waitForNativeCard(
  FlutterLocalNotificationsPlugin inspector, {
  required String title,
  required String body,
}) async {
  ActiveNotification? matched;
  await _waitFor(() async {
    final active = await inspector.getActiveNotifications();
    matched = active.where((card) {
      return card.title == title && card.body == body;
    }).firstOrNull;
    return matched != null;
  }, reason: 'The expected native notification card was not active.');
  return matched!;
}

Future<void> _waitForPositionAdvance({
  required Duration Function() position,
  required bool Function() isPlaying,
  required String reason,
}) async {
  final baseline = position();
  await _waitFor(
    () async => isPlaying() && position() > baseline,
    reason: reason,
  );
}

Future<void> _holdContinuityWindow({
  required Duration duration,
  required bool Function() isPlaying,
}) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    expect(isPlaying(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  expect(isPlaying(), isTrue);
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  required String reason,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure(reason);
}

final class _ProofVisibility extends AppVisibilitySuppressionReader {
  _ProofVisibility({this.visibleConversation});

  final String? visibleConversation;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    return AppVisibilityEvaluation(
      isForegroundActive: true,
      maySuppress:
          identity != null && identity.normalizedValue == visibleConversation,
    );
  }
}

final class _MemoryContentRegistry
    implements ConversationNotificationContentRegistry {
  final _metadata = <String, ConversationNotificationContentMetadata>{};

  String _key(String conversationKey, int notificationId) =>
      '$conversationKey::$notificationId';

  @override
  Future<ConversationNotificationContentReplacementResult> replaceContent({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  }) async {
    final key = _key(conversationKey, notificationId);
    final current = _metadata[key];
    if (current?.eventIdentity == metadata.eventIdentity &&
        current?.kind == metadata.kind) {
      return ConversationNotificationContentReplacementResult.alreadyCurrent;
    }
    await replace();
    _metadata[key] = metadata;
    return ConversationNotificationContentReplacementResult.shownAndRecorded;
  }

  @override
  Future<bool> replaceContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String expectedGeneration,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  }) async {
    final key = _key(conversationKey, notificationId);
    if (_metadata[key]?.generation != expectedGeneration) return false;
    await replace();
    _metadata[key] = metadata;
    return true;
  }

  @override
  Future<bool> cancelContentIfKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
    ConversationNotificationContentCancellationPredicate? shouldCancel,
    required Future<void> Function() cancel,
  }) async {
    final key = _key(conversationKey, notificationId);
    final current = _metadata[key];
    if (current == null ||
        current.kind != kind ||
        (shouldCancel != null && !await shouldCancel(current))) {
      return false;
    }
    await cancel();
    _metadata.remove(key);
    return true;
  }

  @override
  Future<bool> cancelContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String generation,
    required Future<void> Function() cancel,
  }) async {
    final key = _key(conversationKey, notificationId);
    if (_metadata[key]?.generation != generation) return false;
    await cancel();
    _metadata.remove(key);
    return true;
  }

  @override
  Future<void> recordContentMetadata({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
  }) async {
    _metadata[_key(conversationKey, notificationId)] = metadata;
  }

  @override
  Future<ConversationNotificationContentMetadata?> lookupContentMetadata({
    required String conversationKey,
    required int notificationId,
  }) async => _metadata[_key(conversationKey, notificationId)];

  @override
  Future<void> recordContentKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
  }) async {
    _metadata[_key(conversationKey, notificationId)] =
        ConversationNotificationContentMetadata(kind: kind);
  }

  @override
  Future<ConversationNotificationContentKind?> lookupContentKind({
    required String conversationKey,
    required int notificationId,
  }) async => _metadata[_key(conversationKey, notificationId)]?.kind;

  @override
  Future<void> clearContentKind({
    required String conversationKey,
    required int notificationId,
  }) async {
    _metadata.remove(_key(conversationKey, notificationId));
  }
}
