import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';

void main() {
  Widget buildTestWidget({
    List<ConversationMessage> messages = const [],
    ValueChanged<String>? onSend,
    VoidCallback? onBack,
    bool isLoadingMore = false,
    bool hasMoreOlderMessages = true,
    bool initialLoadDone = false,
    VoidCallback? onAttach,
    List<File> pendingAttachments = const [],
    bool isUploading = false,
    ValueChanged<int>? onRemoveAttachment,
    bool isBlocked = false,
    bool isSending = false,
    ValueListenable<ConversationComposerViewState>? composerStateListenable,
    UploadProgressViewState? uploadProgress,
    VoidCallback? onCancelUpload,
    String? activeQuoteText,
    bool isActiveQuoteUnavailable = false,
    VoidCallback? onClearQuote,
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onEditMessage,
    ValueChanged<String>? onDeleteMessage,
    bool isEditingMessage = false,
    VoidCallback? onCancelEdit,
    bool allowEditAction = true,
    ValueChanged<String>? onRetryFailedMedia,
    ValueChanged<String>? onDeleteFailedMedia,
    ConversationMediaViewerBuilder? mediaViewerBuilder,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          ownPeerId: '12D3KooWMyPeerId1234567890',
          messages: messages,
          onSend: onSend ?? (_) {},
          onBack: onBack ?? () {},
          isLoadingMore: isLoadingMore,
          hasMoreOlderMessages: hasMoreOlderMessages,
          initialLoadDone: initialLoadDone,
          onAttach: onAttach,
          pendingAttachments: pendingAttachments,
          isUploading: isUploading,
          onRemoveAttachment: onRemoveAttachment,
          isBlocked: isBlocked,
          isSending: isSending,
          composerStateListenable: composerStateListenable,
          uploadProgress: uploadProgress,
          onCancelUpload: onCancelUpload,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: onClearQuote,
          onQuoteReply: onQuoteReply,
          onEditMessage: onEditMessage,
          onDeleteMessage: onDeleteMessage,
          isEditingMessage: isEditingMessage,
          onCancelEdit: onCancelEdit,
          allowEditAction: allowEditAction,
          onRetryFailedMedia: onRetryFailedMedia,
          onDeleteFailedMedia: onDeleteFailedMedia,
          mediaViewerBuilder: mediaViewerBuilder,
        ),
      ),
    );
  }

  ConversationMessage makeMessage({
    String id = 'msg-1',
    bool isIncoming = true,
    String text = 'Hello!',
    String timestamp = '2026-02-09T15:30:00.000Z',
    String status = 'delivered',
    List<MediaAttachment> media = const [],
    String? quotedMessageId,
    String? deletedAt,
    String? deletedByPeerId,
    String? hiddenAt,
    String? transport,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: '12D3KooWTestPeerId1234567890',
      senderPeerId: isIncoming
          ? '12D3KooWTestPeerId1234567890'
          : '12D3KooWMyPeerId1234567890',
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-02-09T15:30:01.000Z',
      media: media,
      quotedMessageId: quotedMessageId,
      deletedAt: deletedAt,
      deletedByPeerId: deletedByPeerId,
      hiddenAt: hiddenAt,
      transport: transport,
    );
  }

  MediaAttachment makeImageAttachment({
    String id = 'att-1',
    String localPath = '/tmp/att-1.jpg',
  }) {
    return MediaAttachment(
      id: id,
      messageId: '',
      mime: 'image/jpeg',
      size: 42,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-02-09T15:30:00.000Z',
    );
  }

  MediaAttachment makeVideoAttachment({
    String id = 'vid-1',
    String localPath = '/tmp/vid-1.mp4',
  }) {
    return MediaAttachment(
      id: id,
      messageId: '',
      mime: 'video/mp4',
      size: 4200,
      mediaType: 'video',
      localPath: localPath,
      durationMs: 15000,
      downloadStatus: 'done',
      createdAt: '2026-02-09T15:30:00.000Z',
    );
  }

  // Use pump with duration instead of pumpAndSettle because
  // AmbientBackground has a repeating 8s animation that never settles.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('ConversationScreen', () {
    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(messages: [], initialLoadDone: true),
      );
      await tester.pump();

      expect(find.text('Connected!'), findsWidgets);
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows loading shell while initial conversation page is still loading',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(messages: []));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('conversation-loading-shell')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('conversation-loading-bubble-0')),
          findsOneWidget,
        );
        expect(
          find.text('Write the first letter\nto start your conversation'),
          findsNothing,
        );
      },
    );

    testWidgets('shows letter cards when messages present', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage(id: 'msg-1', text: 'First message')],
        ),
      );
      await pumpFrames(tester);

      expect(find.text('First message'), findsOneWidget);
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsNothing,
      );
    });

    testWidgets(
      'renders intro system rows through IntroSystemMessage in order',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'msg-before',
                text: 'Before intro',
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'msg-system',
                isIncoming: false,
                text: 'Connected through Noor',
                timestamp: '2026-02-09T15:31:00.000Z',
                transport: 'system',
              ),
              makeMessage(
                id: 'msg-after',
                isIncoming: false,
                text: 'After intro',
                timestamp: '2026-02-09T15:32:00.000Z',
              ),
            ],
          ),
        );
        await pumpFrames(tester);

        expect(find.byType(IntroSystemMessage), findsOneWidget);
        expect(find.text('Connected through Noor'), findsOneWidget);
        expect(find.byType(LetterCard), findsNWidgets(2));

        final beforeY = tester
            .getTopLeft(find.byKey(const ValueKey('msg-msg-before')))
            .dy;
        final systemY = tester
            .getTopLeft(find.byKey(const ValueKey('msg-msg-system')))
            .dy;
        final afterY = tester
            .getTopLeft(find.byKey(const ValueKey('msg-msg-after')))
            .dy;
        expect(beforeY, lessThan(systemY));
        expect(systemY, lessThan(afterY));
      },
    );

    testWidgets('compose area always visible', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: []));
      await tester.pump();

      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('compose area visible with messages too', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: [makeMessage()]));
      await pumpFrames(tester);

      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('shows active quote preview above composer and clears it', (
      tester,
    ) async {
      var cleared = false;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage()],
          activeQuoteText: 'Quoted text preview',
          onClearQuote: () => cleared = true,
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Quoted text preview'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(cleared, isTrue);
    });

    testWidgets('upload banner shows cancel affordance only when supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage()],
          uploadProgress: const UploadProgressViewState(
            sentBytes: 5,
            totalBytes: 10,
          ),
        ),
      );
      await pumpFrames(tester);

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
          messages: [makeMessage()],
          uploadProgress: const UploadProgressViewState(
            sentBytes: 5,
            totalBytes: 10,
          ),
          onCancelUpload: () {},
        ),
      );
      await pumpFrames(tester);

      expect(
        find.byKey(const ValueKey('upload-progress-cancel-button')),
        findsOneWidget,
      );
    });

    testWidgets('wraps incoming messages with swipe-to-quote when enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage(id: 'incoming-1', text: 'Swipe me')],
          onQuoteReply: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
    });

    testWidgets('does not wrap outgoing messages with swipe to quote', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'outgoing-1',
              isIncoming: false,
              text: 'Do not swipe me',
            ),
          ],
          onQuoteReply: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    });

    testWidgets('renders quoted replies and unavailable fallback in list', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(id: 'original', text: 'Original text'),
            makeMessage(
              id: 'reply',
              text: 'Reply text',
              isIncoming: false,
              quotedMessageId: 'original',
            ),
            makeMessage(
              id: 'missing',
              text: 'Reply to missing',
              quotedMessageId: 'missing-id',
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Original text'), findsWidgets);
      expect(find.text('Message unavailable'), findsOneWidget);
    });

    testWidgets('header shows contact name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets(
      'long-press on incoming text shows overlay with reactions, reply, and copy',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'incoming-1', text: 'Context menu me')],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Context menu me'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
        expect(find.text('👍'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('Context menu me'),
          ),
          findsOneWidget,
        );

        final reactionRect = tester.getRect(
          find.byKey(MessageContextOverlay.reactionBarKey),
        );
        final selectedRect = tester.getRect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
        );
        final menuRect = tester.getRect(
          find.byKey(MessageContextOverlay.menuKey),
        );

        expect(reactionRect.bottom, lessThanOrEqualTo(selectedRect.top));
        expect(selectedRect.bottom, lessThanOrEqualTo(menuRect.top));
      },
    );

    testWidgets('long-press reply is available for outgoing messages', (
      tester,
    ) async {
      String? quotedId;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'outgoing-1',
              isIncoming: false,
              text: 'My own message',
            ),
          ],
          initialLoadDone: true,
          onQuoteReply: (messageId) => quotedId = messageId,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('My own message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.selectedMessageKey),
          matching: find.text('My own message'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(quotedId, 'outgoing-1');
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    });

    testWidgets(
      'edit action appears for the last sent text row even when a newer incoming row exists',
      (tester) async {
        String? editedId;
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'outgoing-last-sent',
                isIncoming: false,
                text: 'Editable text',
              ),
              makeMessage(
                id: 'incoming-newer',
                isIncoming: true,
                text: 'Newer incoming',
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (messageId) => editedId = messageId,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Editable text'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.editActionKey), findsOneWidget);

        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(editedId, 'outgoing-last-sent');
      },
    );

    testWidgets('edit action stays hidden for older sent rows', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'older-sent',
              isIncoming: false,
              text: 'Older sent',
            ),
            makeMessage(
              id: 'latest-sent',
              isIncoming: false,
              text: 'Latest sent',
              timestamp: '2026-02-09T15:31:00.000Z',
            ),
          ],
          initialLoadDone: true,
          onEditMessage: (_) {},
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Older sent'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
    });

    testWidgets('copy action copies exact text and dismisses the overlay', (
      tester,
    ) async {
      String? copiedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
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
          messages: [makeMessage(id: 'copy-1', text: 'Copy this exactly')],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Copy this exactly'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(copiedText, 'Copy this exactly');
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
      expect(find.text('Message copied to clipboard'), findsOneWidget);
    });

    testWidgets('media-only long-press hides copy action', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'media-only',
              text: '',
              media: [makeImageAttachment()],
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.byType(LetterCard));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
    });

    testWidgets('delete action is available on normal visible rows', (
      tester,
    ) async {
      String? deletedId;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage(id: 'delete-row', text: 'Delete me')],
          initialLoadDone: true,
          onDeleteMessage: (messageId) => deletedId = messageId,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Delete me'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsOneWidget);

      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await tester.pump();

      expect(deletedId, 'delete-row');
    });

    testWidgets('deleted rows render placeholder and stay inert', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'deleted-row',
              text: '',
              deletedAt: '2026-02-09T15:32:00.000Z',
              deletedByPeerId: '12D3KooWTestPeerId1234567890',
            ),
          ],
          initialLoadDone: true,
          onDeleteMessage: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(find.text('This message was deleted'), findsOneWidget);

      await tester.longPress(find.text('This message was deleted'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    });

    testWidgets('quoted deleted parents render as unavailable', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'deleted-parent',
              text: '',
              deletedAt: '2026-02-09T15:32:00.000Z',
              deletedByPeerId: '12D3KooWMyPeerId1234567890',
            ),
            makeMessage(
              id: 'reply-after-delete',
              text: 'Still replying',
              isIncoming: false,
              quotedMessageId: 'deleted-parent',
              timestamp: '2026-02-09T15:33:00.000Z',
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Message unavailable'), findsOneWidget);
    });

    testWidgets('shows edit banner and routes cancel action', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'editable-row',
              isIncoming: false,
              text: 'Editing now',
            ),
          ],
          initialLoadDone: true,
          isEditingMessage: true,
          onCancelEdit: () => cancelled = true,
        ),
      );
      await pumpFrames(tester);

      expect(find.byKey(ConversationScreen.editModeBannerKey), findsOneWidget);
      expect(find.text('Editing message'), findsOneWidget);

      await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('shows origin marker when messages present and no more older', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(messages: [makeMessage()], hasMoreOlderMessages: false),
      );
      await pumpFrames(tester);

      // Compact origin marker shows "Connected!" text
      expect(find.text('Connected!'), findsWidgets);
    });

    testWidgets('hides origin marker when hasMoreOlderMessages is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(messages: [makeMessage()], hasMoreOlderMessages: true),
      );
      await pumpFrames(tester);

      // Origin marker should not appear — more messages above
      // Only the header has the connection info, not the origin marker
      expect(find.text('Connected!'), findsNothing);
    });

    testWidgets('shows loading indicator when isLoadingMore is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage()],
          isLoadingMore: true,
          hasMoreOlderMessages: true,
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('failed outgoing media rows show retry and delete controls', (
      tester,
    ) async {
      String? retriedId;
      String? deletedId;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'failed-media',
              isIncoming: false,
              status: 'failed',
              media: [makeImageAttachment()],
            ),
          ],
          initialLoadDone: true,
          onRetryFailedMedia: (id) => retriedId = id,
          onDeleteFailedMedia: (id) => deletedId = id,
        ),
      );
      await pumpFrames(tester);

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
      'incoming and failed text-only rows do not show failed-media controls',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'incoming-failed-media',
                isIncoming: true,
                status: 'failed',
                media: [makeImageAttachment(id: 'att-incoming')],
              ),
              makeMessage(
                id: 'failed-text-only',
                isIncoming: false,
                status: 'failed',
              ),
            ],
            initialLoadDone: true,
            onRetryFailedMedia: (_) {},
            onDeleteFailedMedia: (_) {},
          ),
        );
        await pumpFrames(tester);

        expect(
          find.byKey(
            const ValueKey('failed-media-retry-incoming-failed-media'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-retry-failed-text-only')),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('failed-media-delete-incoming-failed-media'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-delete-failed-text-only')),
          findsNothing,
        );
      },
    );

    testWidgets('keeps stable message/audio keys across list updates', (
      tester,
    ) async {
      MediaAttachment makeAudio(String id) => MediaAttachment(
        id: id,
        messageId: '',
        mime: 'audio/mp4',
        size: 1234,
        mediaType: 'audio',
        durationMs: 1000,
        localPath: '/tmp/$id.m4a',
        downloadStatus: 'done',
        createdAt: '2026-02-09T15:30:00.000Z',
      );

      final first = makeMessage(
        id: 'msg-1',
        isIncoming: false,
        text: '',
        media: [makeAudio('aud-1')],
      );
      final second = makeMessage(
        id: 'msg-2',
        isIncoming: false,
        text: '',
        media: [makeAudio('aud-2')],
      );

      await tester.pumpWidget(
        buildTestWidget(messages: [first], initialLoadDone: true),
      );
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('msg-msg-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('aud-1')), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(messages: [first, second], initialLoadDone: true),
      );
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('msg-msg-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-msg-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('aud-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('aud-2')), findsOneWidget);
    });

    testWidgets(
      'composer listenable updates do not rebuild header or message list',
      (tester) async {
        final composerState = ValueNotifier(
          const ConversationComposerViewState(),
        );
        addTearDown(composerState.dispose);

        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'msg-1', text: 'First message')],
            initialLoadDone: true,
            composerStateListenable: composerState,
          ),
        );
        await pumpFrames(tester);

        final headerElement = tester.element(find.byType(ConversationHeader));
        final listElement = tester.element(
          find.byKey(const ValueKey('messages')),
        );
        final headerWidget = tester.widget<ConversationHeader>(
          find.byType(ConversationHeader),
        );
        final listWidget = tester.widget<ListView>(
          find.byKey(const ValueKey('messages')),
        );

        composerState.value = const ConversationComposerViewState(
          recordingState: VoiceRecordingState.recording,
          recordingDuration: Duration(seconds: 3),
          amplitudeValues: [0.2, 0.5, 0.8],
        );
        await tester.pump();

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0:03'), findsOneWidget);
        expect(
          identical(
            headerElement,
            tester.element(find.byType(ConversationHeader)),
          ),
          isTrue,
        );
        expect(
          identical(
            listElement,
            tester.element(find.byKey(const ValueKey('messages'))),
          ),
          isTrue,
        );
        expect(
          tester.widget<ConversationHeader>(find.byType(ConversationHeader)),
          same(headerWidget),
        );
        expect(
          tester.widget<ListView>(find.byKey(const ValueKey('messages'))),
          same(listWidget),
        );

        composerState.value = const ConversationComposerViewState(
          pendingAttachments: [],
          isProcessing: true,
          processingProgress: 0.4,
        );
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing'), findsOneWidget);
        expect(find.text('40%'), findsOneWidget);
        expect(
          tester.widget<ConversationHeader>(find.byType(ConversationHeader)),
          same(headerWidget),
        );
        expect(
          tester.widget<ListView>(find.byKey(const ValueKey('messages'))),
          same(listWidget),
        );
      },
    );
  });

  group('ConversationScreen attachments', () {
    late Directory tempDir;
    late List<File> testFiles;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('conv_screen_test_');
      testFiles = [];
      for (var i = 0; i < 2; i++) {
        final file = File('${tempDir.path}/photo_$i.jpg');
        await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
        testFiles.add(file);
      }
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'shows AttachmentPreviewStrip when pendingAttachments not empty',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage()],
            pendingAttachments: testFiles,
            onRemoveAttachment: (_) {},
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.byType(Image), findsNWidgets(2));
      },
    );

    testWidgets(
      'hides AttachmentPreviewStrip when pendingAttachments is empty',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(pendingAttachments: []));
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsNothing);
      },
    );

    testWidgets('hides preview strip when blocked even if attachments exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(pendingAttachments: testFiles, isBlocked: true),
      );
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets('passes hasAttachments to ComposeArea', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage()],
          pendingAttachments: testFiles,
          initialLoadDone: true,
        ),
      );
      // Use pumpFrames because AmbientBackground has repeating animation
      await pumpFrames(tester);
      await pumpFrames(tester);

      // Send button should be visible because hasAttachments is derived
      // from pendingAttachments.isNotEmpty
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity, isNotEmpty);
    });

    testWidgets('onAttach callback is passed through to ComposeArea', (
      tester,
    ) async {
      var attachCalled = false;
      await tester.pumpWidget(
        buildTestWidget(onAttach: () => attachCalled = true),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(attachCalled, true);
    });

    testWidgets(
      'tapping a received image opens the viewer with the image path',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'image-msg',
                media: [makeImageAttachment(localPath: '/tmp/open-me.jpg')],
              ),
            ],
            initialLoadDone: true,
            mediaViewerBuilder:
                ({
                  required localPath,
                  required allPaths,
                  required initialIndex,
                }) {
                  return Scaffold(
                    body: Column(
                      children: [
                        Text('viewer-path:$localPath'),
                        Text('viewer-index:$initialIndex'),
                        Text('viewer-all:${allPaths.join(",")}'),
                      ],
                    ),
                  );
                },
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byType(MediaGridCell).first);
        await tester.pumpAndSettle();

        expect(find.text('viewer-path:/tmp/open-me.jpg'), findsOneWidget);
        expect(find.text('viewer-index:0'), findsOneWidget);
        expect(find.text('viewer-all:/tmp/open-me.jpg'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a later visual attachment preserves the visual-only index order',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'multi-visual-msg',
                media: [
                  makeImageAttachment(
                    id: 'img-1',
                    localPath: '/tmp/visual-1.jpg',
                  ),
                  MediaAttachment(
                    id: 'aud-1',
                    messageId: '',
                    mime: 'audio/mp4',
                    size: 1024,
                    mediaType: 'audio',
                    localPath: '/tmp/ignore-audio.m4a',
                    downloadStatus: 'done',
                    createdAt: '2026-02-09T15:30:00.000Z',
                  ),
                  makeVideoAttachment(
                    id: 'vid-1',
                    localPath: '/tmp/visual-2.mp4',
                  ),
                  makeImageAttachment(
                    id: 'img-2',
                    localPath: '/tmp/visual-3.jpg',
                  ),
                ],
              ),
            ],
            initialLoadDone: true,
            mediaViewerBuilder:
                ({
                  required localPath,
                  required allPaths,
                  required initialIndex,
                }) {
                  return Scaffold(
                    body: Column(
                      children: [
                        Text('viewer-path:$localPath'),
                        Text('viewer-index:$initialIndex'),
                        Text('viewer-all:${allPaths.join(",")}'),
                      ],
                    ),
                  );
                },
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byType(MediaGridCell).at(2));
        await tester.pumpAndSettle();

        expect(find.text('viewer-path:/tmp/visual-3.jpg'), findsOneWidget);
        expect(find.text('viewer-index:2'), findsOneWidget);
        expect(
          find.text(
            'viewer-all:/tmp/visual-1.jpg,/tmp/visual-2.mp4,/tmp/visual-3.jpg',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
