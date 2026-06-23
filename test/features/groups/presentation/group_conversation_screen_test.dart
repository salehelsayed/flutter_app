import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

const _validContentHash =
    '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';
const _validEncryptionKey = 'test-encryption-key';
const _validEncryptionNonce = 'test-encryption-nonce';
// A real, decodable 1x1 PNG so the render-boundary wiring test doesn't trip the
// thumbnail decode-error fallback (which itself shows "Media unavailable").
const _validPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

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
    Map<String, GroupMember> membersByPeerId = const {},
    bool initialLoadDone = false,
    bool isRecovering = false,
    ValueListenable<ConversationComposerViewState>? composerStateListenable,
    UploadProgressViewState? uploadProgress,
    VoidCallback? onCancelUpload,
    String? activeQuoteText,
    bool isActiveQuoteUnavailable = false,
    VoidCallback? onClearQuote,
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onRetryFailedMessage,
    ValueChanged<String>? onRetryFailedMedia,
    ValueChanged<String>? onDeleteFailedMedia,
    void Function(String messageId, String attachmentId)?
    onRetryUnavailableMedia,
    Set<String> retryingFailedMessageIds = const {},
    void Function(String messageId, int index)? onMediaTap,
    Map<String, List<MediaAttachment>> mediaMap = const {},
    Map<String, List<MessageReaction>> reactions = const {},
    void Function(String messageId, String emoji)? onReactionSelected,
    ValueChanged<String>? onSend,
    String? initialText,
    GroupBacklogRetentionNotice? backlogRetentionNotice,
    GroupHistoryGapRepairNotice? historyGapRepairNotice,
    GroupSecurityStatusViewState? securityStatus,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    String? highlightedMessageId,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupConversationScreen(
          group: group ?? testGroup,
          messages: messages,
          membersByPeerId: membersByPeerId,
          ownPeerId: 'peer-1',
          onSend: onSend ?? (_) {},
          onBack: () {},
          canWrite: canWrite,
          isSending: isSending,
          uploadProgress: uploadProgress,
          onCancelUpload: onCancelUpload,
          initialLoadDone: initialLoadDone,
          isRecovering: isRecovering,
          composerStateListenable: composerStateListenable,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: onClearQuote,
          onQuoteReply: onQuoteReply,
          onRetryFailedMessage: onRetryFailedMessage,
          onRetryFailedMedia: onRetryFailedMedia,
          onDeleteFailedMedia: onDeleteFailedMedia,
          onRetryUnavailableMedia: onRetryUnavailableMedia,
          retryingFailedMessageIds: retryingFailedMessageIds,
          onMediaTap: onMediaTap,
          mediaMap: mediaMap,
          reactions: reactions,
          onReactionSelected: onReactionSelected,
          initialText: initialText,
          backlogRetentionNotice: backlogRetentionNotice,
          historyGapRepairNotice: historyGapRepairNotice,
          securityStatus: securityStatus,
          backgroundPreference: backgroundPreference,
          highlightedMessageId: highlightedMessageId,
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

  Finder highlightShell(String messageId) =>
      find.byKey(ValueKey('grp-highlight-$messageId'));

  Finder highlightCue(String messageId) =>
      find.byKey(ValueKey('grp-highlight-cue-$messageId'));

  void expectSingleRowFocusCue(WidgetTester tester, String messageId) {
    final shell = highlightShell(messageId);
    expect(shell, findsOneWidget);
    expect(tester.widget<Stack>(shell).clipBehavior, Clip.none);
    expect(
      find.descendant(of: shell, matching: messageRow(messageId)),
      findsOneWidget,
    );

    final cue = tester.widget<AnimatedContainer>(highlightCue(messageId));
    expect(cue.constraints?.minWidth, 3);
    expect(cue.constraints?.maxWidth, 3);
    final decoration = cue.decoration;
    expect(decoration, isA<BoxDecoration>());
    final boxDecoration = decoration! as BoxDecoration;
    expect(boxDecoration.border, isNull);
    expect(boxDecoration.borderRadius, isNotNull);
  }

  testWidgets('renders messages', (tester) async {
    await tester.pumpWidget(buildTestWidget(messages: testMessages));

    expect(find.text('Hello everyone!'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('ML-016 non-contact sender labels render stable fallback', (
    tester,
  ) async {
    final messages = [
      GroupMessage(
        id: 'ml016-empty-label',
        groupId: 'group-1',
        senderPeerId: 'peer-alice-non-contact',
        senderUsername: '   ',
        text: 'Alice visible without contact',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
      GroupMessage(
        id: 'ml016-null-label',
        groupId: 'group-1',
        senderPeerId: 'peer-bob-non-contact',
        text: 'Bob visible without contact',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
    ];

    await tester.pumpWidget(buildTestWidget(messages: messages));

    expect(find.text('Alice visible without contact'), findsOneWidget);
    expect(find.text('Bob visible without contact'), findsOneWidget);
    expect(find.text('Member peer-ali'), findsOneWidget);
    expect(find.text('Member peer-bob'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets(
    'UP-009 re-added sender label prefers current member identity over stale wire username',
    (tester) async {
      final readdedAt = DateTime.now().toUtc();
      final messages = [
        GroupMessage(
          id: 'up009-charlie-after-readd',
          groupId: 'group-1',
          senderPeerId: 'peer-charlie',
          senderUsername: 'Old Charlie',
          text: 'Charlie after re-add stays visible',
          timestamp: readdedAt,
          createdAt: readdedAt,
          isIncoming: true,
        ),
      ];
      final membersByPeerId = <String, GroupMember>{
        'peer-charlie': GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Readded Charlie',
          role: MemberRole.writer,
          joinedAt: readdedAt,
        ),
      };

      await tester.pumpWidget(
        buildTestWidget(messages: messages, membersByPeerId: membersByPeerId),
      );

      expect(find.text('Charlie after re-add stays visible'), findsOneWidget);
      expect(find.text('Readded Charlie'), findsOneWidget);
      expect(find.text('Old Charlie'), findsNothing);
      expect(find.text('Member peer-cha'), findsNothing);
    },
  );

  testWidgets('renders undecryptable epoch placeholders as safe text', (
    tester,
  ) async {
    final placeholder = GroupMessage(
      id: 'msg-undecryptable',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: groupUndecryptablePlaceholderText,
      timestamp: DateTime.now().toUtc(),
      keyGeneration: 7,
      status: 'undecryptable',
      isIncoming: true,
      createdAt: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(buildTestWidget(messages: [placeholder]));

    expect(find.text(groupUndecryptablePlaceholderText), findsOneWidget);
    expect(find.textContaining('Future epoch replay'), findsNothing);
    expect(
      find.byKey(const ValueKey('failed-media-retry-msg-undecryptable')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('failed-media-delete-msg-undecryptable')),
      findsNothing,
    );
  });

  testWidgets(
    'PREREQ-FUTURE-EPOCH-KEY-REPAIR renders pending and finalized repair placeholders safely',
    (tester) async {
      final pending = GroupMessage(
        id: 'msg-pending-repair',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: groupPendingKeyRepairPlaceholderText,
        timestamp: DateTime.now().toUtc(),
        keyGeneration: 8,
        status: groupPendingKeyRepairStatusPendingKey,
        isIncoming: true,
        createdAt: DateTime.now().toUtc(),
      );
      final finalized = GroupMessage(
        id: 'msg-finalized-repair',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: groupUndecryptablePlaceholderText,
        timestamp: DateTime.now().toUtc(),
        keyGeneration: 8,
        status: groupPendingKeyRepairStatusUndecryptable,
        isIncoming: true,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(buildTestWidget(messages: [pending, finalized]));

      expect(find.text(groupPendingKeyRepairPlaceholderText), findsOneWidget);
      expect(find.text(groupUndecryptablePlaceholderText), findsOneWidget);
      expect(find.textContaining('Future epoch replay'), findsNothing);
      expect(
        find.byKey(const ValueKey('failed-media-retry-msg-pending-repair')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-delete-msg-pending-repair')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-retry-msg-finalized-repair')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('failed-media-delete-msg-finalized-repair')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'KE-022 renders key-update recovery placeholder as a visible degraded state',
    (tester) async {
      final pending = GroupMessage(
        id: 'ke022-pending-key-repair',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: groupPendingKeyRepairPlaceholderText,
        timestamp: DateTime.now().toUtc(),
        keyGeneration: 2,
        status: groupPendingKeyRepairStatusPendingKey,
        isIncoming: true,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(buildTestWidget(messages: [pending]));

      expect(find.text(groupPendingKeyRepairPlaceholderText), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('failed-media-retry-ke022-pending-key-repair'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('failed-media-delete-ke022-pending-key-repair'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('does not render group security status in the chat header', (
    tester,
  ) async {
    const securityStatus = GroupSecurityStatusViewState(
      hasCurrentKey: true,
      keyEpoch: 2,
      memberCount: 2,
      verifiedMemberCount: 1,
      identityWarningCount: 1,
      unverifiedMemberCount: 0,
    );

    await tester.pumpWidget(
      buildTestWidget(securityStatus: securityStatus, initialLoadDone: true),
    );

    expect(
      find.byKey(const ValueKey('group-conversation-security-strip')),
      findsNothing,
    );
    expect(find.text('Encrypted - key epoch 2'), findsNothing);
    expect(find.text('1 member needs verification review'), findsNothing);
  });

  testWidgets('hides healthy initial security status strip', (tester) async {
    const securityStatus = GroupSecurityStatusViewState(
      hasCurrentKey: true,
      keyEpoch: 1,
      memberCount: 2,
      verifiedMemberCount: 2,
      identityWarningCount: 0,
      unverifiedMemberCount: 0,
    );

    await tester.pumpWidget(
      buildTestWidget(securityStatus: securityStatus, initialLoadDone: true),
    );

    expect(
      find.byKey(const ValueKey('group-conversation-security-strip')),
      findsNothing,
    );
    expect(find.text('Encrypted - key epoch 1'), findsNothing);
  });

  testWidgets(
    'internal_encryption_epoch_status_is_not_rendered_as_user_visible_error',
    (tester) async {
      const securityStatus = GroupSecurityStatusViewState(
        hasCurrentKey: true,
        keyEpoch: 1,
        memberCount: 2,
        verifiedMemberCount: 2,
        identityWarningCount: 0,
        unverifiedMemberCount: 0,
      );

      await tester.pumpWidget(
        buildTestWidget(securityStatus: securityStatus, initialLoadDone: true),
      );

      expect(find.text('Encrypted - key epoch 1'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    },
  );

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
          onReactionSelected: (_, _) {},
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
      contentHash: _validContentHash,
      encryptionKeyBase64: _validEncryptionKey,
      encryptionNonce: _validEncryptionNonce,
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      createdAt: '2026-02-09T15:30:00.000Z',
    );
  }

  MediaAttachment makeVideoAttachment({
    String id = 'video-1',
    String messageId = '',
    String downloadStatus = 'pending',
    String? localPath,
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
      localPath: localPath,
      downloadStatus: downloadStatus,
      contentHash: _validContentHash,
      encryptionKeyBase64: _validEncryptionKey,
      encryptionNonce: _validEncryptionNonce,
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      createdAt: '2026-02-09T15:31:00.000Z',
    );
  }

  MediaAttachment makeAudioAttachment({
    String id = 'audio-1',
    String messageId = '',
    String downloadStatus = 'pending',
    String? localPath,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'audio/mp4',
      size: 2048,
      mediaType: 'audio',
      durationMs: 4200,
      localPath: localPath,
      downloadStatus: downloadStatus,
      contentHash: _validContentHash,
      encryptionKeyBase64: _validEncryptionKey,
      encryptionNonce: _validEncryptionNonce,
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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

  testWidgets(
    'notification focus cue stays single-row across highlighted variants and backgrounds',
    (tester) async {
      final timestamp = DateTime.utc(2026, 4, 11, 12);
      final parent = GroupMessage(
        id: 'msg-focus-parent',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Original focus parent',
        timestamp: timestamp,
        createdAt: timestamp,
        isIncoming: true,
      );
      final incoming = GroupMessage(
        id: 'msg-focus-incoming',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Incoming highlight target',
        timestamp: timestamp.add(const Duration(minutes: 1)),
        createdAt: timestamp.add(const Duration(minutes: 1)),
        isIncoming: true,
      );
      final outgoing = GroupMessage(
        id: 'msg-focus-outgoing',
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderUsername: 'You',
        text: 'Outgoing highlight target',
        timestamp: timestamp.add(const Duration(minutes: 2)),
        createdAt: timestamp.add(const Duration(minutes: 2)),
        isIncoming: false,
      );
      final quoted = GroupMessage(
        id: 'msg-focus-quoted',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Quoted highlight target',
        quotedMessageId: parent.id,
        timestamp: timestamp.add(const Duration(minutes: 3)),
        createdAt: timestamp.add(const Duration(minutes: 3)),
        isIncoming: true,
      );
      final media = GroupMessage(
        id: 'msg-focus-media',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Media highlight target',
        timestamp: timestamp.add(const Duration(minutes: 4)),
        createdAt: timestamp.add(const Duration(minutes: 4)),
        isIncoming: true,
        media: [
          makeImageAttachment(
            id: 'att-focus-media',
            messageId: 'msg-focus-media',
          ),
        ],
      );
      final reacted = GroupMessage(
        id: 'msg-focus-reacted',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Reaction highlight target',
        timestamp: timestamp.add(const Duration(minutes: 5)),
        createdAt: timestamp.add(const Duration(minutes: 5)),
        isIncoming: true,
      );
      final reactions = {
        reacted.id: [
          MessageReaction(
            id: 'rx-focus-self',
            messageId: reacted.id,
            emoji: '🔥',
            senderPeerId: 'peer-1',
            timestamp: timestamp.toIso8601String(),
            createdAt: timestamp.toIso8601String(),
          ),
        ],
      };

      Future<void> pumpHighlighted(
        List<GroupMessage> visibleMessages,
        String messageId, {
        BackgroundPreference backgroundPreference =
            BackgroundPreference.defaultBackground,
      }) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: visibleMessages,
            onQuoteReply: (_) {},
            reactions: reactions,
            backgroundPreference: backgroundPreference,
            highlightedMessageId: messageId,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await pumpHighlighted([parent, incoming], incoming.id);
      expectSingleRowFocusCue(tester, incoming.id);
      expect(highlightShell(parent.id), findsNothing);
      expectTextContrast(
        BackgroundReadableColors.dark.textPrimary,
        BackgroundReadableColors.dark.surfaceRaised,
      );

      await pumpHighlighted([outgoing], outgoing.id);
      expectSingleRowFocusCue(tester, outgoing.id);

      await pumpHighlighted([parent, quoted], quoted.id);
      expectSingleRowFocusCue(tester, quoted.id);
      expect(find.text('Original focus parent'), findsWidgets);

      await pumpHighlighted([media], media.id);
      expectSingleRowFocusCue(tester, media.id);
      expect(find.byType(MediaGridCell), findsOneWidget);

      await pumpHighlighted([reacted], reacted.id);
      expectSingleRowFocusCue(tester, reacted.id);
      expect(find.text('🔥'), findsOneWidget);

      await pumpHighlighted(
        [incoming],
        incoming.id,
        backgroundPreference: BackgroundPreference.daylightLagoon,
      );
      expectSingleRowFocusCue(tester, incoming.id);
      expectTextContrast(
        BackgroundReadableColors.representativeLight.textPrimary,
        BackgroundReadableColors.representativeLight.surfaceRaised,
      );

      await tester.pumpWidget(buildTestWidget(messages: [incoming]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(highlightShell(incoming.id), findsNothing);
      expect(highlightCue(incoming.id), findsNothing);
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
        // The video overlay renders only for DONE media whose local file
        // exists on disk (media_grid_cell gates on File.existsSync) — use a
        // real temp file, written synchronously (testWidgets sync-I/O rule).
        makeVideoAttachment(
          id: 'att-post-join-video',
          messageId: 'msg-post-join-media',
          downloadStatus: 'done',
          localPath: (File(
            '${Directory.systemTemp.path}/gcs_post_join_video.mp4',
          )..writeAsBytesSync(List<int>.filled(64, 1))).path,
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
    addTearDown(() {
      final videoFile = File(
        '${Directory.systemTemp.path}/gcs_post_join_video.mp4',
      );
      if (videoFile.existsSync()) {
        videoFile.deleteSync();
      }
    });

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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      buildTestWidget(messages: [mediaMessage], initialLoadDone: true),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('post-join text plus media'), findsOneWidget);
    expect(messageRow(mediaMessage.id), findsOneWidget);
    expect(find.byType(VideoThumbnailOverlay), findsOneWidget);
    expect(find.byType(AudioPlayerWidget), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets(
    '128 group wiring: own-sent group image with a stale display path renders '
    'from the durable owned copy keyed under media/<group.id>',
    (tester) async {
      // Locks the group-screen wiring of `ownedMediaPeerId: group.id` (the
      // sender "Media unavailable" fix, extended from 1:1 to groups). The
      // displayed attachment carries the DELETED optimistic pending path; the
      // durable owned copy lives under media/<group.id>/<blob>. If the screen
      // stops threading ownedMediaPeerId, the render gate cannot find the file
      // and this row shows "Media unavailable" — i.e. the bug returns and this
      // test fails. testWidgets sync-IO only (see feedback_testwidgets_sync_io).
      MediaGridCell.debugResetUnavailableDiagnostics();
      final tempDir = Directory.systemTemp.createTempSync('grp_media_wiring_');
      addTearDown(() {
        MediaFileManager.debugResetDocumentsDirCache();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      MediaFileManager.cacheDocumentsDir(tempDir.path);

      const blob = 'att-grp-stale-1';
      // The durable owned copy EXISTS under the group dir (testGroup.id).
      File('${tempDir.path}/media/group-1/$blob.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_validPngBytes);
      // Displayed attachment still holds the DELETED optimistic pending path.
      final stalePending =
          '${tempDir.path}/pending_uploads/msg-grp-media/$blob.jpg';
      expect(File(stalePending).existsSync(), isFalse);

      final mediaMessage = GroupMessage(
        id: 'msg-grp-media',
        groupId: 'group-1',
        senderPeerId: 'peer-1', // own-sent (ownPeerId in buildTestWidget)
        senderUsername: 'You',
        text: '',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: false,
        media: [
          makeImageAttachment(
            id: blob,
            messageId: 'msg-grp-media',
            localPath: stalePending,
          ),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(messages: [mediaMessage], initialLoadDone: true),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Render gate falls back to media/group-1/<blob>.jpg -> verified thumbnail.
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    },
  );

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

  testWidgets(
    'IR-018 shows recovering state instead of current empty state during replay catch-up',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(initialLoadDone: true, isRecovering: true),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('group-recovery-banner')), findsNothing);
      expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
      expect(find.text('No messages yet'), findsNothing);
      expect(
        find.text(
          'Catching up missed messages. New messages will still appear here.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'IR-018 keeps visible messages live while marking the group as recovering',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          initialLoadDone: true,
          isRecovering: true,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('group-recovery-banner')), findsNothing);
      expect(find.text('Hello everyone!'), findsOneWidget);
    },
  );

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
    'IR-016 shows expired backlog banner and empty-state override after retention expiry',
    (tester) async {
      final expiredGroup = testGroup.copyWith(
        lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
      );

      await tester.pumpWidget(
        buildTestWidget(
          group: expiredGroup,
          initialLoadDone: true,
          backlogRetentionNotice: groupBacklogRetentionNoticeFor(
            expiredGroup,
            l10n,
          ),
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
    'IR-016 shows mixed-window retention banner while retained messages stay visible',
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
          backlogRetentionNotice: groupBacklogRetentionNoticeFor(
            mixedGroup,
            l10n,
          ),
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
    'PREREQ-HISTORY-GAP-REPAIR shows active failed and repaired gap state separately from retention expiry',
    (tester) async {
      GroupHistoryGapRepair repair(String status) => GroupHistoryGapRepair(
        groupId: 'group-1',
        gapId: 'gap-1',
        missingAfterMessageId: 'msg-before',
        missingBeforeMessageId: 'msg-after',
        expectedRangeHash: 'range-hash',
        expectedHeadMessageId: 'msg-after',
        candidateSourcePeerIds: const ['peer-2'],
        status: status,
        createdAt: DateTime.utc(2026, 5, 1, 12),
        updatedAt: DateTime.utc(2026, 5, 1, 12),
      );

      final retentionGroup = testGroup.copyWith(
        lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
      );

      await tester.pumpWidget(
        buildTestWidget(
          group: retentionGroup,
          initialLoadDone: true,
          backlogRetentionNotice: groupBacklogRetentionNoticeFor(
            retentionGroup,
            l10n,
          ),
          historyGapRepairNotice: groupHistoryGapRepairNoticeFor(
            repair(groupHistoryGapRepairStatusRepairing),
            l10n,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('group-backlog-retention-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-history-gap-repair-banner')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Some missed messages are being repaired from trusted group members.',
        ),
        findsOneWidget,
      );
      expect(find.text('Repairing missed messages'), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(
          initialLoadDone: true,
          historyGapRepairNotice: groupHistoryGapRepairNoticeFor(
            repair(groupHistoryGapRepairStatusFailed),
            l10n,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'Some missed messages could not be repaired from trusted group members.',
        ),
        findsOneWidget,
      );
      expect(find.text('History repair needed'), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(
          initialLoadDone: true,
          historyGapRepairNotice: groupHistoryGapRepairNoticeFor(
            repair(groupHistoryGapRepairStatusRepaired),
            l10n,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Missed messages were repaired and verified.'),
        findsOneWidget,
      );
      expect(find.text('Messages repaired'), findsOneWidget);
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

  testWidgets('GFR-003 failed media controls are preserved', (tester) async {
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

  testWidgets('GFR-003 failed outgoing text-only rows show retry', (
    tester,
  ) async {
    String? retriedId;
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          GroupMessage(
            id: 'incoming-failed-text',
            groupId: 'group-1',
            senderPeerId: 'peer-2',
            senderUsername: 'Alice',
            text: 'Incoming failed text',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: true,
          ),
          GroupMessage(
            id: 'empty-failed-text',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: '   ',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
          ),
          GroupMessage(
            id: 'sent-text',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: 'Already sent',
            status: 'sent',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
          ),
          GroupMessage(
            id: 'failed-media-with-caption',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: 'Caption stays media retry',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
            media: [
              makeImageAttachment(
                id: 'att-failed-media-with-caption',
                messageId: 'failed-media-with-caption',
              ),
            ],
          ),
          GroupMessage(
            id: 'failed-text-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: 'Retry this text',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
          ),
        ],
        initialLoadDone: true,
        onRetryFailedMessage: (id) => retriedId = id,
        onRetryFailedMedia: (_) {},
        onDeleteFailedMedia: (_) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final retryKey = find.byKey(
      const ValueKey('failed-message-retry-failed-text-retry'),
    );
    expect(retryKey, findsOneWidget);
    expect(
      find.byKey(const ValueKey('failed-media-retry-failed-text-retry')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('failed-media-delete-failed-text-retry')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('failed-message-retry-incoming-failed-text')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('failed-message-retry-empty-failed-text')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('failed-message-retry-sent-text')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('failed-message-retry-failed-media-with-caption'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('failed-media-retry-failed-media-with-caption'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('failed-media-delete-failed-media-with-caption'),
      ),
      findsOneWidget,
    );

    await tester.tap(retryKey);
    await tester.pump();
    expect(retriedId, 'failed-text-retry');

    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          GroupMessage(
            id: 'failed-readonly-text',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: 'Cannot retry while read-only',
            status: 'failed',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            isIncoming: false,
          ),
        ],
        canWrite: false,
        initialLoadDone: true,
        onRetryFailedMessage: (_) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('failed-message-retry-failed-readonly-text')),
      findsNothing,
    );
  });

  testWidgets(
    'GFR-003 retry action reflects in-flight and recovery-gate state',
    (tester) async {
      var retryCalls = 0;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            GroupMessage(
              id: 'retrying-text',
              groupId: 'group-1',
              senderPeerId: 'peer-1',
              senderUsername: 'You',
              text: 'Retry is already running',
              status: 'failed',
              timestamp: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              isIncoming: false,
            ),
          ],
          initialLoadDone: true,
          retryingFailedMessageIds: const {'retrying-text'},
          onRetryFailedMessage: (_) => retryCalls++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final retryingKey = find.byKey(
        const ValueKey('failed-message-retry-retrying-text'),
      );
      expect(retryingKey, findsOneWidget);
      expect(tester.widget<OutlinedButton>(retryingKey).onPressed, isNull);
      await tester.tap(retryingKey);
      await tester.pump();
      expect(retryCalls, 0);

      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            GroupMessage(
              id: 'recovering-text',
              groupId: 'group-1',
              senderPeerId: 'peer-1',
              senderUsername: 'You',
              text: 'Recovery is active',
              status: 'failed',
              timestamp: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              isIncoming: false,
            ),
          ],
          initialLoadDone: true,
          isRecovering: true,
          onRetryFailedMessage: (_) => retryCalls++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final recoveringKey = find.byKey(
        const ValueKey('failed-message-retry-recovering-text'),
      );
      expect(recoveringKey, findsOneWidget);
      expect(tester.widget<OutlinedButton>(recoveringKey).onPressed, isNull);
      await tester.tap(recoveringKey);
      await tester.pump();
      expect(retryCalls, 0);
    },
  );

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

  testWidgets(
    'MD-012 quarantined visual media is a terminal couldn\'t-verify placeholder with NO retry (INV-DL-3)',
    (tester) async {
      var opened = false;
      var retried = false;
      final message = GroupMessage(
        id: 'msg-quarantined-media',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: '',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
        media: const [
          MediaAttachment(
            id: 'att-quarantined-media',
            messageId: 'msg-quarantined-media',
            mime: 'image/jpeg',
            size: 42,
            mediaType: 'image',
            localPath: '/tmp/quarantined.jpg',
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash:
                '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
            encryptionKeyBase64: 'key-quarantined',
            encryptionNonce: 'nonce-quarantined',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          messages: [message],
          initialLoadDone: true,
          onMediaTap: (_, _) => opened = true,
          onRetryUnavailableMedia: (_, _) => retried = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tamper gets the distinct honest label and is terminal — no retry.
      expect(find.text("Couldn't verify this media"), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'unavailable-media-retry-msg-quarantined-media-att-quarantined-media',
          ),
        ),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

      await tester.tap(find.byType(MediaGridCell));
      await tester.pump();
      expect(opened, isFalse);
      expect(retried, isFalse);
    },
  );

  testWidgets(
    'MD-012 read-only group rows can retry unavailable incoming media without resend controls',
    (tester) async {
      final retried = <String>[];
      final failed = makeImageAttachment(
        id: 'att-download-failed',
        messageId: 'msg-readonly-unavailable',
        downloadStatus: 'failed',
      );
      final quarantined = makeImageAttachment(
        id: 'att-download-quarantined',
        messageId: 'msg-readonly-unavailable',
        downloadStatus: kMediaDownloadStatusIntegrityFailed,
      );
      final message = GroupMessage(
        id: 'msg-readonly-unavailable',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: '',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
        media: [failed, quarantined],
      );

      await tester.pumpWidget(
        buildTestWidget(
          messages: [message],
          canWrite: false,
          initialLoadDone: true,
          onRetryFailedMedia: (_) {},
          onDeleteFailedMedia: (_) {},
          onRetryUnavailableMedia: (messageId, attachmentId) {
            retried.add('$messageId/$attachmentId');
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The transient `failed` attachment keeps its retry-unavailable control...
      expect(
        find.byKey(
          const ValueKey(
            'unavailable-media-retry-msg-readonly-unavailable-att-download-failed',
          ),
        ),
        findsOneWidget,
      );
      // ...but the quarantined (integrity_failed) one is terminal — no retry.
      expect(
        find.byKey(
          const ValueKey(
            'unavailable-media-retry-msg-readonly-unavailable-att-download-quarantined',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('failed-media-retry-msg-readonly-unavailable'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('failed-media-delete-msg-readonly-unavailable'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'unavailable-media-retry-msg-readonly-unavailable-att-download-failed',
          ),
        ),
      );
      await tester.pump();

      expect(retried, equals(['msg-readonly-unavailable/att-download-failed']));
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

  testWidgets(
    'wraps outgoing messages with swipe-to-quote when writable (136 Phase 4 '
    'both directions)',
    (tester) async {
      // 136 Phase 4 behavior change: swipe-to-reply is now enabled on EVERY
      // balloon in BOTH directions (outgoing balloons get the gesture too),
      // still gated by write permission.
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

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
    },
  );

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

  testWidgets(
    'GE-024 renders available and unavailable quote parents without crashing',
    (tester) async {
      final now = DateTime.now().toUtc();
      final messages = [
        GroupMessage(
          id: 'ge024-entitled-parent',
          groupId: 'group-1',
          senderPeerId: 'peer-2',
          senderUsername: 'Alice',
          text: 'GE-024 entitled parent',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
        ),
        GroupMessage(
          id: 'ge024-available-reply',
          groupId: 'group-1',
          senderPeerId: 'peer-3',
          senderUsername: 'Bob',
          text: 'GE-024 reply with available quote',
          quotedMessageId: 'ge024-entitled-parent',
          timestamp: now.add(const Duration(seconds: 1)),
          createdAt: now.add(const Duration(seconds: 1)),
          isIncoming: true,
        ),
        GroupMessage(
          id: 'ge024-unavailable-reply',
          groupId: 'group-1',
          senderPeerId: 'peer-3',
          senderUsername: 'Bob',
          text: 'GE-024 reply with unavailable quote',
          quotedMessageId: 'ge024-missing-removed-window-parent',
          timestamp: now.add(const Duration(seconds: 2)),
          createdAt: now.add(const Duration(seconds: 2)),
          isIncoming: true,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(messages: messages));

      expect(tester.takeException(), isNull);
      expect(find.text('GE-024 entitled parent'), findsWidgets);
      expect(find.text('GE-024 reply with available quote'), findsOneWidget);
      expect(find.text('GE-024 reply with unavailable quote'), findsOneWidget);
      expect(find.text('Message unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'PL-004 renders visible quote parents and unavailable fallback for missing parents',
    (tester) async {
      final now = DateTime.utc(2026, 5, 13, 20, 55);
      final parent = GroupMessage(
        id: 'pl004-visible-parent',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'PL-004 visible quote parent',
        timestamp: now,
        createdAt: now,
        isIncoming: true,
      );
      final reply = GroupMessage(
        id: 'pl004-reply',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: 'PL-004 quoted reply',
        quotedMessageId: parent.id,
        timestamp: now.add(const Duration(seconds: 1)),
        createdAt: now.add(const Duration(seconds: 1)),
        isIncoming: true,
      );

      await tester.pumpWidget(buildTestWidget(messages: [parent, reply]));
      expect(find.text('PL-004 visible quote parent'), findsWidgets);
      expect(find.text('PL-004 quoted reply'), findsOneWidget);
      expect(find.text('Message unavailable'), findsNothing);

      await tester.pumpWidget(buildTestWidget(messages: [reply]));
      await tester.pump();
      expect(find.text('PL-004 quoted reply'), findsOneWidget);
      expect(find.text('Message unavailable'), findsOneWidget);
    },
  );

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

  group('localized timestamps (finding 11 item 3)', () {
    // A fixed local wall-clock time of 14:05, constructed as a *local* DateTime
    // so toLocal() is a no-op and the assertion is timezone-independent.
    final localAfternoon = DateTime(2026, 2, 9, 14, 5);

    GroupMessage timestampMessage() => GroupMessage(
      id: 'msg-time',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Time check',
      timestamp: localAfternoon,
      createdAt: localAfternoon,
      isIncoming: true,
    );

    testWidgets('de renders 24-hour time without an AM/PM marker', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [timestampMessage()],
          locale: const Locale('de'),
        ),
      );
      await tester.pump();

      expect(find.textContaining('14:05'), findsOneWidget);
      expect(find.textContaining('PM'), findsNothing);
      expect(find.textContaining('AM'), findsNothing);
    });

    testWidgets('en keeps the 12-hour AM/PM format', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [timestampMessage()],
          locale: const Locale('en'),
        ),
      );
      await tester.pump();

      final expected = intl.DateFormat.jm('en').format(localAfternoon);
      expect(expected, contains('PM'));
      expect(find.textContaining(expected), findsOneWidget);
    });

    testWidgets('ar renders the locale-formatted time (Eastern-Arabic digits)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [timestampMessage()],
          locale: const Locale('ar'),
        ),
      );
      await tester.pump();

      final expected = intl.DateFormat.jm('ar').format(localAfternoon);
      // Sanity: the Arabic format is not the ASCII-digit Western form.
      expect(expected, isNot(contains('14:05')));
      expect(find.textContaining(expected), findsOneWidget);
    });
  });

  // 136 Phase 4: wire bubble grouping into the group conversation screen.
  group('GroupConversationScreen bubble grouping (136 Phase 4)', () {
    GroupMessage groupMsg({
      required String id,
      required String senderPeerId,
      required String senderUsername,
      required String text,
      required DateTime timestamp,
      bool isIncoming = true,
    }) => GroupMessage(
      id: id,
      groupId: 'group-1',
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      text: text,
      timestamp: timestamp,
      createdAt: timestamp,
      isIncoming: isIncoming,
    );

    // The live LetterCard rendered inside the per-message
    // ValueKey('grp-msg-<id>') padding (NOT a long-press snapshot).
    LetterCard liveLetterCard(WidgetTester tester, String messageId) {
      return tester.widget<LetterCard>(
        find.descendant(
          of: find.byKey(ValueKey('grp-msg-$messageId')),
          matching: find.byType(LetterCard),
        ),
      );
    }

    Finder avatarsInList() => find.descendant(
      of: find.byKey(const ValueKey('group-messages')),
      matching: find.byType(UserAvatar),
    );

    testWidgets(
      'TC-23 group consecutive same-sender incoming messages show avatar+name '
      'once',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              groupMsg(
                id: 'g-in-1',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'First',
                timestamp: base,
              ),
              groupMsg(
                id: 'g-in-2',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Second',
                timestamp: base.add(const Duration(minutes: 1)),
              ),
              groupMsg(
                id: 'g-in-3',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Third',
                timestamp: base.add(const Duration(minutes: 2)),
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await tester.pump();

        // Exactly ONE avatar + ONE sender-name Text for the whole run.
        expect(avatarsInList(), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);

        // The first balloon carries the run chrome; 2 and 3 hide both.
        expect(liveLetterCard(tester, 'g-in-1').showAvatar, isTrue);
        expect(liveLetterCard(tester, 'g-in-1').showSenderName, isTrue);
        expect(liveLetterCard(tester, 'g-in-2').showAvatar, isFalse);
        expect(liveLetterCard(tester, 'g-in-2').showSenderName, isFalse);
        expect(liveLetterCard(tester, 'g-in-3').showAvatar, isFalse);
        expect(liveLetterCard(tester, 'g-in-3').showSenderName, isFalse);

        // All three balloons render in bubble layout.
        expect(liveLetterCard(tester, 'g-in-1').bubbleLayout, isTrue);
        expect(liveLetterCard(tester, 'g-in-2').bubbleLayout, isTrue);
        expect(liveLetterCard(tester, 'g-in-3').bubbleLayout, isTrue);
      },
    );

    testWidgets(
      'TC-24 group outgoing run groups and never shows an avatar',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              groupMsg(
                id: 'g-out-1',
                senderPeerId: 'peer-1',
                senderUsername: 'You',
                text: 'My first',
                timestamp: base,
                isIncoming: false,
              ),
              groupMsg(
                id: 'g-out-2',
                senderPeerId: 'peer-1',
                senderUsername: 'You',
                text: 'My second',
                timestamp: base.add(const Duration(minutes: 1)),
                isIncoming: false,
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await tester.pump();

        // Outgoing never shows an avatar in either balloon.
        expect(avatarsInList(), findsNothing);
        expect(liveLetterCard(tester, 'g-out-1').showAvatar, isFalse);
        expect(liveLetterCard(tester, 'g-out-2').showAvatar, isFalse);

        // The run groups: the first is first-in-run, the second continues it.
        expect(liveLetterCard(tester, 'g-out-1').isFirstInGroup, isTrue);
        expect(liveLetterCard(tester, 'g-out-2').isFirstInGroup, isFalse);
      },
    );

    testWidgets(
      'TC-25 group system row (sys- prefix) breaks the run and never shows '
      'run chrome',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              groupMsg(
                id: 'g-before-sys',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Before the system row',
                timestamp: base,
              ),
              // System/membership row: ordinary GroupMessage with a sys- id,
              // sharing senderPeerId with the surrounding text messages.
              groupMsg(
                id: 'sys-member_joined:peer-2',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Alice joined the group',
                timestamp: base.add(const Duration(seconds: 30)),
              ),
              groupMsg(
                id: 'g-after-sys',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'After the system row',
                timestamp: base.add(const Duration(minutes: 1)),
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await tester.pump();

        // The system row is its own run (first & last) and shows no chrome.
        final sysCard = liveLetterCard(tester, 'sys-member_joined:peer-2');
        expect(sysCard.isFirstInGroup, isTrue);
        expect(sysCard.isLastInGroup, isTrue);
        expect(sysCard.showAvatar, isFalse);
        expect(sysCard.showSenderName, isFalse);

        // The same-senderPeerId text message AFTER the system row starts a
        // fresh run (it must NOT merge with the message before the system row).
        expect(liveLetterCard(tester, 'g-after-sys').isFirstInGroup, isTrue);
        expect(liveLetterCard(tester, 'g-after-sys').showAvatar, isTrue);
      },
    );

    testWidgets(
      'TC-26 group swipe-to-reply enabled both directions, preserving canWrite '
      '(present for outgoing+canWrite, absent for outgoing+readonly)',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        final outgoing = [
          groupMsg(
            id: 'g-swipe-out',
            senderPeerId: 'peer-1',
            senderUsername: 'You',
            text: 'Swipe my outgoing',
            timestamp: base,
            isIncoming: false,
          ),
        ];

        // (isSent:true, canWrite:true) -> swipe PRESENT and quotes the id.
        String? quotedId;
        await tester.pumpWidget(
          buildTestWidget(
            messages: outgoing,
            canWrite: true,
            initialLoadDone: true,
            onQuoteReply: (id) => quotedId = id,
          ),
        );
        await tester.pump();

        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
        await tester.drag(
          find.byType(SwipeToQuoteBubble),
          const Offset(80, 0),
        );
        await tester.pump();
        expect(quotedId, 'g-swipe-out');

        // (isSent:true, canWrite:false) -> swipe ABSENT (read-only preserved).
        await tester.pumpWidget(
          buildTestWidget(
            messages: outgoing,
            canWrite: false,
            initialLoadDone: true,
            onQuoteReply: (_) {},
          ),
        );
        await tester.pump();

        expect(find.byType(SwipeToQuoteBubble), findsNothing);
      },
    );

    testWidgets(
      'TC-26b group system (sys-) rows are not swipe-to-reply-able even when '
      'writable (1:1 parity — system rows are not quote-reply targets)',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              // A real outgoing message IS swipeable (TC-26 both-directions).
              groupMsg(
                id: 'g-real-out',
                senderPeerId: 'peer-1',
                senderUsername: 'You',
                text: 'A real message',
                timestamp: base,
                isIncoming: false,
              ),
              // A system/membership row must NOT be swipeable: quoting a
              // synthetic sys- id is nonsensical, and the 1:1 surface already
              // excludes system messages from swipe (IntroSystemMessage
              // early-return). Group must match for parity.
              groupMsg(
                id: 'sys-member_joined:peer-2',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Alice joined the group',
                timestamp: base.add(const Duration(seconds: 30)),
              ),
            ],
            canWrite: true,
            initialLoadDone: true,
            onQuoteReply: (_) {},
          ),
        );
        await tester.pump();

        // Exactly ONE swipe wrapper: the real message. The sys- row is excluded
        // even though canWrite is true and onQuoteReply is wired.
        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
      },
    );

    testWidgets(
      'TC-27 group run detection uses rendered list adjacency '
      '(reply-reordered, non-monotonic)',
      (tester) async {
        // Simulate orderGroupMessagesForTimeline output: a reply (later
        // timestamp) is pulled directly under its quoted parent, so the
        // RENDERED order interleaves senders and is NOT timestamp-monotonic.
        // Raw-timestamp sort would group the two peer-2 messages together
        // (and break the run differently); rendered adjacency must win.
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        final messages = [
          // peer-2 parent (earliest)
          groupMsg(
            id: 'nm-parent',
            senderPeerId: 'peer-2',
            senderUsername: 'Alice',
            text: 'Parent from Alice',
            timestamp: base,
          ),
          // peer-3 reply pulled under the parent — LATER timestamp than the
          // peer-2 message that follows it in render order.
          groupMsg(
            id: 'nm-reply',
            senderPeerId: 'peer-3',
            senderUsername: 'Bob',
            text: 'Reply from Bob',
            timestamp: base.add(const Duration(minutes: 10)),
          ),
          // peer-2 again, EARLIER timestamp than the reply above it.
          groupMsg(
            id: 'nm-alice-2',
            senderPeerId: 'peer-2',
            senderUsername: 'Alice',
            text: 'Second from Alice',
            timestamp: base.add(const Duration(minutes: 2)),
          ),
        ];

        await tester.pumpWidget(
          buildTestWidget(messages: messages, initialLoadDone: true),
        );
        await tester.pump();

        // All three balloons must render in bubble layout (RED on HEAD where
        // bubbleLayout is never passed).
        expect(liveLetterCard(tester, 'nm-parent').bubbleLayout, isTrue);
        expect(liveLetterCard(tester, 'nm-reply').bubbleLayout, isTrue);
        expect(liveLetterCard(tester, 'nm-alice-2').bubbleLayout, isTrue);

        // Run flags are computed on adjacency-as-rendered. The peer-3 reply
        // sits between two peer-2 messages, so EACH of the three balloons is
        // first-in-run by position (the neighbor differs by sender).
        expect(liveLetterCard(tester, 'nm-parent').isFirstInGroup, isTrue);
        expect(liveLetterCard(tester, 'nm-reply').isFirstInGroup, isTrue);
        expect(liveLetterCard(tester, 'nm-alice-2').isFirstInGroup, isTrue);

        // Discriminator vs the re-sort mutation: with rendered adjacency the
        // second Alice message is a FRESH incoming run head, so it shows run
        // chrome. If detection re-sorted by timestamp, the two peer-2 messages
        // would be adjacent and this balloon would lose its chrome
        // (isFirstInGroup:false, showSenderName:false).
        expect(liveLetterCard(tester, 'nm-alice-2').showSenderName, isTrue);
      },
    );

    testWidgets(
      'TC-28 group per-message ValueKey(grp-msg-<id>) + scroll-to-highlight '
      'anchor preserved (sentinel)',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              groupMsg(
                id: 'key-a',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Keyed A',
                timestamp: base,
              ),
              groupMsg(
                id: 'key-b',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Keyed B',
                timestamp: base.add(const Duration(minutes: 1)),
              ),
            ],
            highlightedMessageId: 'key-b',
            initialLoadDone: true,
          ),
        );
        await tester.pump();

        // Per-message keys remain at the balloon level (not hoisted to a run).
        expect(find.byKey(const ValueKey('grp-msg-key-a')), findsOneWidget);
        expect(find.byKey(const ValueKey('grp-msg-key-b')), findsOneWidget);

        // The scroll-to-highlight cue still targets the highlighted message.
        expectSingleRowFocusCue(tester, 'key-b');
      },
    );

    testWidgets(
      'TC-29 group long-press lifted snapshot built with matching grouping '
      'flags',
      (tester) async {
        final base = DateTime.utc(2026, 2, 9, 15, 30);
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              groupMsg(
                id: 'snap-1',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Run head',
                timestamp: base,
              ),
              groupMsg(
                id: 'snap-2',
                senderPeerId: 'peer-2',
                senderUsername: 'Alice',
                text: 'Continuation balloon',
                timestamp: base.add(const Duration(minutes: 1)),
              ),
            ],
            onQuoteReply: (_) {},
            onReactionSelected: (_, _) {},
            initialLoadDone: true,
          ),
        );
        await tester.pump();

        // The live continuation balloon (snap-2) hides its chrome.
        final liveContinuation = liveLetterCard(tester, 'snap-2');
        expect(liveContinuation.showAvatar, isFalse);
        expect(liveContinuation.isFirstInGroup, isFalse);

        // Long-press the continuation balloon to lift the context overlay.
        await tester.longPress(find.text('Continuation balloon'));
        await tester.pump(const Duration(milliseconds: 250));

        // The lifted snapshot LetterCard must carry the SAME grouping flags as
        // the live balloon — no avatar pop-in / corner-radius jump.
        final snapshotCard = tester.widget<LetterCard>(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.byType(LetterCard),
          ),
        );
        expect(snapshotCard.showAvatar, isFalse);
        expect(snapshotCard.showSenderName, isFalse);
        expect(snapshotCard.isFirstInGroup, isFalse);
        expect(snapshotCard.bubbleLayout, isTrue);
      },
    );
  });

  group('run-aware spacing + avatar outside bubble (137 follow-up)', () {
    GroupMessage incoming(String id, DateTime ts, String text) => GroupMessage(
      id: id,
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: text,
      timestamp: ts,
      createdAt: ts,
      isIncoming: true,
    );

    testWidgets(
      'mid-run tight gap, run-end separation, avatar wired outside the bubble',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            initialLoadDone: true,
            messages: [
              incoming('g1', DateTime.utc(2026, 2, 9, 15, 30), 'one'),
              incoming('g2', DateTime.utc(2026, 2, 9, 15, 31), 'two'),
              // >5 min after g2 → starts a new run.
              incoming('g3', DateTime.utc(2026, 2, 9, 15, 40), 'three'),
            ],
          ),
        );
        await tester.pump();

        double bottomOf(String id) {
          final pad = tester.widget<Padding>(
            find.byKey(ValueKey('grp-msg-$id')),
          );
          return pad.padding.resolve(TextDirection.ltr).bottom;
        }

        // g1 mid-run (g2 continues) → tight; g2 last of run A, g3 final → sep.
        expect(bottomOf('g1'), lessThan(8));
        expect(bottomOf('g2'), greaterThan(8));
        expect(bottomOf('g3'), greaterThan(8));

        LetterCard cardFor(String id) => tester.widget<LetterCard>(
          find
              .descendant(
                of: find.byKey(ValueKey('grp-msg-$id')),
                matching: find.byType(LetterCard),
              )
              .first,
        );

        // First-in-run paints the avatar OUTSIDE the bubble (avatarOutsideBubble
        // + showAvatar); the continuation reserves the gutter but paints none.
        expect(cardFor('g1').avatarOutsideBubble, isTrue);
        expect(cardFor('g1').showAvatar, isTrue);
        expect(cardFor('g2').avatarOutsideBubble, isTrue);
        expect(cardFor('g2').showAvatar, isFalse);
      },
    );
  });
}
