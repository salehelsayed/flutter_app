import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

void main() {
  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  final testMessages = [
    GroupMessage(
      id: 'msg-1',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Hello everyone!',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    ),
  ];

  Widget buildTestWidget({
    List<GroupMessage> messages = const [],
    bool canWrite = true,
    bool isSending = false,
    GroupModel? group,
    bool initialLoadDone = false,
    ValueListenable<ConversationComposerViewState>? composerStateListenable,
    UploadProgressViewState? uploadProgress,
    VoidCallback? onCancelUpload,
    String? activeQuoteText,
    bool isActiveQuoteUnavailable = false,
    VoidCallback? onClearQuote,
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onRetryFailedMedia,
    ValueChanged<String>? onDeleteFailedMedia,
    Map<String, List<MediaAttachment>> mediaMap = const {},
    Map<String, List<MessageReaction>> reactions = const {},
    void Function(String messageId, String emoji)? onReactionSelected,
    ValueChanged<String>? onSend,
    String? initialText,
    GroupBacklogRetentionNotice? backlogRetentionNotice,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupConversationScreen(
          group: group ?? testGroup,
          messages: messages,
          ownPeerId: 'peer-1',
          onSend: onSend ?? (_) {},
          onBack: () {},
          canWrite: canWrite,
          isSending: isSending,
          uploadProgress: uploadProgress,
          onCancelUpload: onCancelUpload,
          initialLoadDone: initialLoadDone,
          composerStateListenable: composerStateListenable,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: onClearQuote,
          onQuoteReply: onQuoteReply,
          onRetryFailedMedia: onRetryFailedMedia,
          onDeleteFailedMedia: onDeleteFailedMedia,
          mediaMap: mediaMap,
          reactions: reactions,
          onReactionSelected: onReactionSelected,
          initialText: initialText,
          backlogRetentionNotice: backlogRetentionNotice,
          backgroundPreference: backgroundPreference,
        ),
      ),
    );
  }

  Finder messageRow(String messageId) =>
      find.byKey(ValueKey('grp-msg-$messageId'));

  Finder rowBackdropFilter(String messageId) => find.descendant(
    of: messageRow(messageId),
    matching: find.byType(BackdropFilter),
  );

  testWidgets('renders messages', (tester) async {
    await tester.pumpWidget(buildTestWidget(messages: testMessages));

    expect(find.text('Hello everyone!'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('renders sender identity with UserAvatar in conversation rows', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(messages: testMessages));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
  });

  testWidgets(
    'keeps non-photo fallback identity readable in conversation rows',
    (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: testMessages));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hello everyone!'), findsOneWidget);
      expect(find.byType(RingAvatar), findsOneWidget);
    },
  );

  testWidgets('shows compose area when canWrite is true', (tester) async {
    await tester.pumpWidget(buildTestWidget(canWrite: true));

    expect(find.text('Write something...'), findsOneWidget);
  });

  testWidgets(
    'long-press opens one coherent context surface with selected preview and supported actions',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          onQuoteReply: (_) {},
          onReactionSelected: (_, __) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('Hello everyone!'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.reactionBarKey), findsOneWidget);
      expect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
        findsOneWidget,
      );
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.selectedMessageKey),
          matching: find.text('Hello everyone!'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('long-press reply uses the existing quote-reply path', (
    tester,
  ) async {
    String? quotedMessageId;

    await tester.pumpWidget(
      buildTestWidget(
        messages: testMessages,
        onQuoteReply: (messageId) => quotedMessageId = messageId,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.longPress(find.text('Hello everyone!'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(quotedMessageId, 'msg-1');
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
  });

  testWidgets('long-press copy action copies exact text and dismisses once', (
    tester,
  ) async {
    const copiedMessage = 'Hello\nEmoji 😄';
    String? copiedText;
    var clipboardCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardCalls++;
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      buildTestWidget(
        messages: [testMessages.first.copyWith(text: copiedMessage)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.longPress(find.textContaining('Hello'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(clipboardCalls, 1);
    expect(copiedText, copiedMessage);
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Message copied to clipboard'), findsOneWidget);
  });

  testWidgets(
    'local-only long-press actions remain available when reactions are unavailable',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(messages: testMessages, onQuoteReply: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('Hello everyone!'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
    },
  );

  testWidgets('long-press reaction selection preserves the reaction path', (
    tester,
  ) async {
    String? reactedMessageId;
    String? reactedEmoji;

    await tester.pumpWidget(
      buildTestWidget(
        messages: testMessages,
        onQuoteReply: (_) {},
        onReactionSelected: (messageId, emoji) {
          reactedMessageId = messageId;
          reactedEmoji = emoji;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.longPress(find.text('Hello everyone!'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('👍'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(reactedMessageId, 'msg-1');
    expect(reactedEmoji, '👍');
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
  });

  MediaAttachment makeImageAttachment({
    String id = 'att-1',
    String messageId = '',
    String localPath = '/tmp/att-1.jpg',
    String downloadStatus = 'done',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 42,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-02-09T15:30:00.000Z',
    );
  }

  MediaAttachment makeVideoAttachment({
    String id = 'video-1',
    String messageId = '',
    String downloadStatus = 'pending',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'video/mp4',
      size: 4096,
      mediaType: 'video',
      width: 1280,
      height: 720,
      durationMs: 12_000,
      downloadStatus: downloadStatus,
      createdAt: '2026-02-09T15:31:00.000Z',
    );
  }

  MediaAttachment makeAudioAttachment({
    String id = 'audio-1',
    String messageId = '',
    String downloadStatus = 'pending',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'audio/mp4',
      size: 2048,
      mediaType: 'audio',
      durationMs: 4200,
      downloadStatus: downloadStatus,
      createdAt: '2026-02-09T15:32:00.000Z',
      waveform: const <double>[0.2, 0.6, 0.3],
    );
  }

  testWidgets('passes isSending through to the compose send affordance', (
    tester,
  ) async {
    String? sentText;

    await tester.pumpWidget(
      buildTestWidget(
        isSending: true,
        initialText: 'Blocked send',
        onSend: (text) => sentText = text,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(sentText, isNull);
  });

  testWidgets(
    'group rows keep a single glass shell across text, quote, reaction, and media variants',
    (tester) async {
      final timestamp = DateTime.utc(2026, 4, 11, 12);
      final parent = GroupMessage(
        id: 'msg-parent',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Original parent',
        timestamp: timestamp,
        createdAt: timestamp,
        isIncoming: true,
      );
      final quoted = GroupMessage(
        id: 'msg-quoted',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Quoted child',
        quotedMessageId: parent.id,
        timestamp: timestamp.add(const Duration(minutes: 1)),
        createdAt: timestamp.add(const Duration(minutes: 1)),
        isIncoming: true,
      );
      final media = GroupMessage(
        id: 'msg-media',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: '',
        timestamp: timestamp.add(const Duration(minutes: 2)),
        createdAt: timestamp.add(const Duration(minutes: 2)),
        isIncoming: true,
        media: [makeImageAttachment(id: 'att-media', messageId: 'msg-media')],
      );

      await tester.pumpWidget(
        buildTestWidget(messages: [parent], onQuoteReply: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(messageRow(parent.id), findsOneWidget);
      expect(rowBackdropFilter(parent.id), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(
          messages: [parent, quoted],
          onQuoteReply: (_) {},
          reactions: {
            'msg-quoted': [
              MessageReaction(
                id: 'rx-1',
                messageId: 'msg-quoted',
                emoji: '👍',
                senderPeerId: 'peer-1',
                timestamp: timestamp.toIso8601String(),
                createdAt: timestamp.toIso8601String(),
              ),
            ],
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(messageRow(quoted.id), findsOneWidget);
      expect(rowBackdropFilter(quoted.id), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(messages: [media], onQuoteReply: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(messageRow(media.id), findsOneWidget);
      expect(rowBackdropFilter(media.id), findsOneWidget);
    },
  );

  testWidgets(
    'row shell stays single after reaction and media enrichment updates',
    (tester) async {
      final timestamp = DateTime.utc(2026, 4, 11, 12);
      final message = GroupMessage(
        id: 'msg-enriched',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Will enrich',
        timestamp: timestamp,
        createdAt: timestamp,
        isIncoming: true,
      );

      await tester.pumpWidget(
        buildTestWidget(messages: [message], onQuoteReply: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(messageRow(message.id), findsOneWidget);
      expect(rowBackdropFilter(message.id), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            message.copyWith(
              media: [
                makeImageAttachment(
                  id: 'att-enriched',
                  messageId: 'msg-enriched',
                ),
              ],
            ),
          ],
          onQuoteReply: (_) {},
          reactions: {
            'msg-enriched': [
              MessageReaction(
                id: 'rx-enriched',
                messageId: 'msg-enriched',
                emoji: '❤️',
                senderPeerId: 'peer-1',
                timestamp: timestamp.toIso8601String(),
                createdAt: timestamp.toIso8601String(),
              ),
            ],
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(messageRow(message.id), findsOneWidget);
      expect(rowBackdropFilter(message.id), findsOneWidget);
    },
  );

  testWidgets('renders text plus video, voice, and failed media rows visibly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final timestamp = DateTime.utc(2026, 4, 29, 12);
    final mediaMessage = GroupMessage(
      id: 'msg-post-join-media',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'post-join text plus media',
      timestamp: timestamp,
      createdAt: timestamp,
      isIncoming: true,
      media: [
        makeVideoAttachment(
          id: 'att-post-join-video',
          messageId: 'msg-post-join-media',
        ),
        makeAudioAttachment(
          id: 'att-post-join-voice',
          messageId: 'msg-post-join-media',
        ),
        makeImageAttachment(
          id: 'att-post-join-failed',
          messageId: 'msg-post-join-media',
          localPath: '',
          downloadStatus: 'failed',
        ),
      ],
    );

    await tester.pumpWidget(
      buildTestWidget(messages: [mediaMessage], initialLoadDone: true),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('post-join text plus media'), findsOneWidget);
    expect(messageRow(mediaMessage.id), findsOneWidget);
    expect(find.byType(VideoThumbnailOverlay), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.byType(AudioPlayerWidget), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('renders active quote preview and dismisses it', (tester) async {
    var cleared = false;

    await tester.pumpWidget(
      buildTestWidget(
        activeQuoteText: 'Quoted target',
        onClearQuote: () => cleared = true,
      ),
    );

    expect(find.text('Quoted target'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('upload banner shows cancel affordance only when supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: testMessages,
        uploadProgress: const UploadProgressViewState(
          sentBytes: 5,
          totalBytes: 10,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('upload-progress-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('upload-progress-cancel-button')),
      findsNothing,
    );

    await tester.pumpWidget(
      buildTestWidget(
        messages: testMessages,
        uploadProgress: const UploadProgressViewState(
          sentBytes: 5,
          totalBytes: 10,
        ),
        onCancelUpload: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('upload-progress-cancel-button')),
      findsOneWidget,
    );
  });

  testWidgets('shows loading shell while initial group page is still loading', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-loading-bubble-0')),
      findsOneWidget,
    );
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('shows empty state once group load completes with no messages', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(initialLoadDone: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('hides compose area for readers in announcement group', (
    tester,
  ) async {
    final announcementGroup = GroupModel(
      id: 'group-2',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'topic-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );

    await tester.pumpWidget(
      buildTestWidget(group: announcementGroup, canWrite: false),
    );

    expect(
      find.text('Only admins can send messages in this group'),
      findsOneWidget,
    );
  });

  testWidgets('shows dissolved read-only copy and badge for ended groups', (
    tester,
  ) async {
    final dissolvedGroup = testGroup.copyWith(
      isDissolved: true,
      dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
      dissolvedBy: 'peer-admin',
    );

    await tester.pumpWidget(
      buildTestWidget(
        group: dissolvedGroup,
        canWrite: false,
        initialLoadDone: true,
      ),
    );

    expect(find.text('Dissolved'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-read-only-banner')),
      findsOneWidget,
    );
    expect(
      find.text(
        'This group has been dissolved. History stays available, but new messages are disabled.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Only admins can send messages in this group'),
      findsNothing,
    );
  });

  testWidgets(
    'shows expired backlog banner and empty-state override after retention expiry',
    (tester) async {
      final expiredGroup = testGroup.copyWith(
        lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
      );

      await tester.pumpWidget(
        buildTestWidget(
          group: expiredGroup,
          initialLoadDone: true,
          backlogRetentionNotice: groupBacklogRetentionNoticeFor(expiredGroup),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('group-backlog-retention-banner')),
        findsOneWidget,
      );
      expect(find.text('Older backlog expired'), findsOneWidget);
      expect(find.text('No messages yet'), findsNothing);
      expect(
        find.text(
          'Missed messages older than 7 days expired while you were away.',
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'shows mixed-window retention banner while retained messages stay visible',
    (tester) async {
      final mixedGroup = testGroup.copyWith(
        lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
        lastBacklogRetainedAt: DateTime.utc(2026, 4, 6, 12),
      );

      await tester.pumpWidget(
        buildTestWidget(
          group: mixedGroup,
          messages: testMessages,
          initialLoadDone: true,
          backlogRetentionNotice: groupBacklogRetentionNoticeFor(mixedGroup),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('group-backlog-retention-banner')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Older missed messages expired after 7 days. Recent messages were recovered.',
        ),
        findsOneWidget,
      );
      expect(find.text('Hello everyone!'), findsOneWidget);
    },
  );

  testWidgets(
    'composer listenable updates do not rebuild header or message list',
    (tester) async {
      final composerState = ValueNotifier(
        const ConversationComposerViewState(),
      );
      addTearDown(composerState.dispose);

      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          composerStateListenable: composerState,
        ),
      );
      await tester.pump();

      final headerElement = tester.element(
        find.byKey(const ValueKey('group-header')),
      );
      final listElement = tester.element(
        find.byKey(const ValueKey('group-messages')),
      );

      composerState.value = const ConversationComposerViewState(
        recordingState: VoiceRecordingState.recording,
        recordingDuration: Duration(seconds: 4),
        amplitudeValues: [0.1, 0.3, 0.8],
      );
      await tester.pump();

      expect(find.text('0:04'), findsOneWidget);
      expect(
        identical(
          headerElement,
          tester.element(find.byKey(const ValueKey('group-header'))),
        ),
        isTrue,
      );
      expect(
        identical(
          listElement,
          tester.element(find.byKey(const ValueKey('group-messages'))),
        ),
        isTrue,
      );

      composerState.value = const ConversationComposerViewState(
        isProcessing: true,
        processingProgress: 0.6,
        processingCurrent: 3,
        processingTotal: 5,
      );
      await tester.pump();

      expect(find.text('Processing (3/5)'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(
        identical(
          headerElement,
          tester.element(find.byKey(const ValueKey('group-header'))),
        ),
        isTrue,
      );
      expect(
        identical(
          listElement,
          tester.element(find.byKey(const ValueKey('group-messages'))),
        ),
        isTrue,
      );
    },
  );

  testWidgets('failed outgoing media rows show retry and delete controls', (
    tester,
  ) async {
    String? retriedId;
    String? deletedId;
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          GroupMessage(
            id: 'failed-media',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: '',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
            media: [
              makeImageAttachment(
                id: 'att-failed-media',
                messageId: 'failed-media',
              ),
            ],
          ),
        ],
        initialLoadDone: true,
        onRetryFailedMedia: (id) => retriedId = id,
        onDeleteFailedMedia: (id) => deletedId = id,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final retryKey = find.byKey(
      const ValueKey('failed-media-retry-failed-media'),
    );
    final deleteKey = find.byKey(
      const ValueKey('failed-media-delete-failed-media'),
    );
    expect(retryKey, findsOneWidget);
    expect(deleteKey, findsOneWidget);

    await tester.tap(retryKey);
    await tester.pump();
    await tester.tap(deleteKey);
    await tester.pump();

    expect(retriedId, 'failed-media');
    expect(deletedId, 'failed-media');
  });

  testWidgets(
    'incoming, text-only, and read-only announcement rows do not show failed-media controls',
    (tester) async {
      final failedMedia = makeImageAttachment(
        id: 'att-incoming',
        messageId: 'incoming-failed-media',
      );

      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            GroupMessage(
              id: 'incoming-failed-media',
              groupId: 'group-1',
              senderPeerId: 'peer-2',
              senderUsername: 'Alice',
              text: '',
              status: 'failed',
              timestamp: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              isIncoming: true,
              media: [failedMedia],
            ),
            GroupMessage(
              id: 'failed-text-only',
              groupId: 'group-1',
              senderPeerId: 'peer-1',
              senderUsername: 'You',
              text: 'text only',
              status: 'failed',
              timestamp: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              isIncoming: false,
            ),
            GroupMessage(
              id: 'failed-reader-media',
              groupId: 'group-1',
              senderPeerId: 'peer-1',
              senderUsername: 'You',
              text: '',
              status: 'failed',
              timestamp: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              isIncoming: false,
              media: [
                makeImageAttachment(
                  id: 'att-reader',
                  messageId: 'failed-reader-media',
                ),
              ],
            ),
          ],
          canWrite: false,
          initialLoadDone: true,
          onRetryFailedMedia: (_) {},
          onDeleteFailedMedia: (_) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('failed-media-retry-incoming-failed-media')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-retry-failed-text-only')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-retry-failed-reader-media')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-delete-incoming-failed-media')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-delete-failed-text-only')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-delete-failed-reader-media')),
        findsNothing,
      );
    },
  );

  testWidgets('wraps incoming messages with swipe-to-quote when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(messages: testMessages, onQuoteReply: (_) {}),
    );

    expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
  });

  testWidgets('does not wrap outgoing messages with swipe-to-quote', (
    tester,
  ) async {
    final outgoing = [
      GroupMessage(
        id: 'msg-out',
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderUsername: 'You',
        text: 'Sent by me',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: false,
      ),
    ];

    await tester.pumpWidget(
      buildTestWidget(messages: outgoing, onQuoteReply: (_) {}),
    );

    expect(find.byType(SwipeToQuoteBubble), findsNothing);
  });

  testWidgets(
    'does not wrap incoming messages with swipe-to-quote for readers',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          canWrite: false,
          onQuoteReply: (_) {},
        ),
      );

      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    },
  );

  testWidgets('renders quoted replies from existing parent messages', (
    tester,
  ) async {
    final messages = [
      GroupMessage(
        id: 'msg-parent',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Original group message',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
      GroupMessage(
        id: 'msg-reply',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: 'Reply message',
        quotedMessageId: 'msg-parent',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
    ];

    await tester.pumpWidget(buildTestWidget(messages: messages));

    expect(find.text('Original group message'), findsWidgets);
    expect(find.text('Reply message'), findsOneWidget);
  });

  testWidgets('renders unavailable fallback when quoted parent is missing', (
    tester,
  ) async {
    final messages = [
      GroupMessage(
        id: 'msg-reply',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: 'Reply message',
        quotedMessageId: 'missing-parent',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
    ];

    await tester.pumpWidget(buildTestWidget(messages: messages));

    expect(find.text('Message unavailable'), findsOneWidget);
  });

  testWidgets('resolves quoted media-only parent from mediaMap', (
    tester,
  ) async {
    final parent = GroupMessage(
      id: 'msg-media-parent',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: '',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    );
    final reply = GroupMessage(
      id: 'msg-media-reply',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Replying to the photo',
      quotedMessageId: 'msg-media-parent',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    );
    final mediaAttachment = MediaAttachment(
      id: 'blob-parent-1',
      messageId: 'msg-media-parent',
      mime: 'image/jpeg',
      size: 1024,
      mediaType: 'image',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    await tester.pumpWidget(
      buildTestWidget(
        messages: [parent, reply],
        mediaMap: {
          'msg-media-parent': [mediaAttachment],
        },
      ),
    );

    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Message unavailable'), findsNothing);
  });

  testWidgets('daylight lagoon keeps group conversation chrome readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: testMessages,
        canWrite: false,
        initialLoadDone: true,
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    const colors = BackgroundReadableColors.representativeLight;
    final title = tester.widget<Text>(find.text('Test Group'));
    expectTextContrast(title.style!.color!, colors.surfaceBase);

    final readOnly = tester.widget<Text>(
      find.text('Only admins can send messages in this group'),
    );
    expectTextContrast(readOnly.style!.color!, colors.surfaceBase);
  });
}
