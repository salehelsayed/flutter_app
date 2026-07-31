import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';

void main() {
  Widget buildTestWidget({
    List<ConversationMessage> messages = const [],
    Locale locale = const Locale('en'),
    ValueChanged<String>? onSend,
    VoidCallback? onBack,
    bool isLoadingMore = false,
    bool hasMoreOlderMessages = true,
    bool initialLoadDone = false,
    bool isSyncingNewMessages = false,
    ScrollController? scrollController,
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
    String? ownPeerId = '12D3KooWMyPeerId1234567890',
    Map<String, List<MessageReaction>> reactions = const {},
    ValueChanged<String>? onRetryFailedMessage,
    ValueChanged<String>? onRetryFailedMedia,
    ValueChanged<String>? onDeleteFailedMedia,
    Future<void> Function(String messageId, String attachmentId)?
    onRetryUnavailableMedia,
    ConversationMediaViewerBuilder? mediaViewerBuilder,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          ownPeerId: ownPeerId,
          messages: messages,
          onSend: onSend ?? (_) {},
          onBack: onBack ?? () {},
          scrollController: scrollController,
          isLoadingMore: isLoadingMore,
          hasMoreOlderMessages: hasMoreOlderMessages,
          initialLoadDone: initialLoadDone,
          isSyncingNewMessages: isSyncingNewMessages,
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
          reactions: reactions,
          onRetryFailedMessage: onRetryFailedMessage,
          onRetryFailedMedia: onRetryFailedMedia,
          onDeleteFailedMedia: onDeleteFailedMedia,
          onRetryUnavailableMedia: onRetryUnavailableMedia,
          mediaViewerBuilder: mediaViewerBuilder,
          backgroundPreference: backgroundPreference,
        ),
      ),
    );
  }

  // 158 (critic-2): the 1:1 conversation surface suppresses the idle ambient glow
  // so the always-mounted chrome BackdropFilters become cacheable at rest.
  testWidgets(
    'TC-158-04: 1:1 conversation passes isChatSurface to AmbientBackground',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final ambient = tester.widget<AmbientBackground>(
        find.byType(AmbientBackground),
      );
      expect(ambient.isChatSurface, isTrue);
    },
  );

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
    String? senderPeerId,
    String? editedAt,
    bool isForwarded = false,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: '12D3KooWTestPeerId1234567890',
      senderPeerId:
          senderPeerId ??
          (isIncoming
              ? '12D3KooWTestPeerId1234567890'
              : '12D3KooWMyPeerId1234567890'),
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-02-09T15:30:01.000Z',
      isForwarded: isForwarded,
      media: media,
      quotedMessageId: quotedMessageId,
      deletedAt: deletedAt,
      deletedByPeerId: deletedByPeerId,
      hiddenAt: hiddenAt,
      transport: transport,
      editedAt: editedAt,
    );
  }

  testWidgets('screen marks only the forwarded conversation row', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        initialLoadDone: true,
        messages: [
          makeMessage(id: 'ordinary', text: 'ordinary'),
          makeMessage(id: 'forwarded', text: 'forwarded', isForwarded: true),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('direct-forwarded-marker')),
      findsOneWidget,
    );
    final forwardedCard = tester.widget<LetterCard>(
      find.descendant(
        of: find.byKey(const ValueKey('msg-forwarded')),
        matching: find.byType(LetterCard),
      ),
    );
    final ordinaryCard = tester.widget<LetterCard>(
      find.descendant(
        of: find.byKey(const ValueKey('msg-ordinary')),
        matching: find.byType(LetterCard),
      ),
    );
    expect(forwardedCard.isForwarded, isTrue);
    expect(ordinaryCard.isForwarded, isFalse);
  });

  // 145: the "catching up" affordance shown while the screen's relay drain is
  // in flight. Keyed (not text-matched) so it is robust to copy changes.
  const syncingBannerKey = ValueKey('conversation-syncing-banner');

  group('145 syncing affordance', () {
    // AmbientBackground has a repeating 8s animation that never settles, and
    // each rendered letter card schedules a zero-delay entry-animation timer —
    // so pump with a fixed duration (never pumpAndSettle) to drain those timers.
    Future<void> pumpFrames(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 500));

    testWidgets(
      'renders syncing affordance when isSyncingNewMessages is true',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'm1', text: 'stale row')],
            initialLoadDone: true,
            isSyncingNewMessages: true,
          ),
        );
        await pumpFrames(tester);

        expect(find.byKey(syncingBannerKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(syncingBannerKey),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'syncing affordance hidden when isSyncingNewMessages is false',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'm1', text: 'stale row')],
            initialLoadDone: true,
            isSyncingNewMessages: false,
          ),
        );
        await pumpFrames(tester);

        expect(find.byKey(syncingBannerKey), findsNothing);
      },
    );

    testWidgets(
      'syncing affordance is outside the message ListView and does not shift scroll',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final messages = List.generate(
          12,
          (i) => makeMessage(
            id: 'm$i',
            text: 'row $i',
            timestamp:
                '2026-02-09T15:${(10 + i).toString().padLeft(2, '0')}:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildTestWidget(
            messages: messages,
            initialLoadDone: true,
            isSyncingNewMessages: false,
            scrollController: controller,
          ),
        );
        await pumpFrames(tester);
        final offsetBefore = controller.offset;

        await tester.pumpWidget(
          buildTestWidget(
            messages: messages,
            initialLoadDone: true,
            isSyncingNewMessages: true,
            scrollController: controller,
          ),
        );
        await pumpFrames(tester);

        expect(find.byKey(syncingBannerKey), findsOneWidget);
        expect(
          controller.offset,
          offsetBefore,
          reason: 'toggling the affordance must not move the scroll position',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('messages')),
            matching: find.byKey(syncingBannerKey),
          ),
          findsNothing,
          reason: 'the affordance must live outside the message ListView',
        );
      },
    );

    testWidgets(
      'syncing affordance is distinct from the older-pagination spinner',
      (tester) async {
        // Pagination spinner present, syncing banner absent.
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'm1', text: 'stale row')],
            initialLoadDone: true,
            isLoadingMore: true,
            isSyncingNewMessages: false,
          ),
        );
        await pumpFrames(tester);
        expect(find.byKey(syncingBannerKey), findsNothing);

        // Inverse: syncing banner present, isLoadingMore false.
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'm1', text: 'stale row')],
            initialLoadDone: true,
            isLoadingMore: false,
            isSyncingNewMessages: true,
          ),
        );
        await pumpFrames(tester);
        expect(find.byKey(syncingBannerKey), findsOneWidget);
      },
    );
  });

  MediaAttachment makeImageAttachment({
    String id = 'att-1',
    String messageId = '',
    MediaOwnerLane? ownerLane,
    String localPath = '/tmp/att-1.jpg',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      ownerLane: ownerLane,
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
    String messageId = '',
    MediaOwnerLane? ownerLane,
    String localPath = '/tmp/vid-1.mp4',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      ownerLane: ownerLane,
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
    testWidgets('renders the selected cosmic background', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(backgroundPreference: BackgroundPreference.cosmic),
      );
      await tester.pump();

      expect(find.byType(CosmicBackground), findsOneWidget);
    });

    testWidgets('renders Mirror Cosmic for the default background', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          backgroundPreference: BackgroundPreference.defaultBackground,
        ),
      );
      await tester.pump();

      expect(find.byType(CosmicBackground), findsNothing);
      expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cosmic-background-mirrored-root')),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders selected daylight lagoon with light readable header text',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            backgroundPreference: BackgroundPreference.daylightLagoon,
          ),
        );
        await tester.pump();

        expect(find.byType(DaylightLagoonBackground), findsOneWidget);

        final headerName = tester.widget<Text>(find.text('Alice'));
        expect(
          headerName.style?.color,
          BackgroundReadableColors.representativeLight.textPrimary,
        );
      },
    );

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

        await tester.longPress(find.text('Connected through Noor'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
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

    testWidgets('wraps outgoing messages with swipe to quote (136 Phase 3 both '
        'directions)', (tester) async {
      // 136 Phase 3 behavior change: swipe-to-reply is now enabled on EVERY
      // balloon in BOTH directions (previously incoming-only).
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'outgoing-1',
              isIncoming: false,
              text: 'Swipe me too',
            ),
          ],
          onQuoteReply: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
    });

    testWidgets('does not wrap deleted messages with swipe to quote', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'deleted-swipe',
              text: '',
              deletedAt: '2026-02-09T15:32:00.000Z',
              deletedByPeerId: '12D3KooWTestPeerId1234567890',
            ),
          ],
          onQuoteReply: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    });

    testWidgets('deleted card suppresses stale media and viewer entry', (
      tester,
    ) async {
      const messageId = 'deleted-with-stale-media';
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: messageId,
              text: '',
              deletedAt: '2026-02-09T15:32:00.000Z',
              deletedByPeerId: '12D3KooWTestPeerId1234567890',
              media: const [
                MediaAttachment(
                  id: 'stale-deleted-image',
                  messageId: messageId,
                  mime: 'image/png',
                  size: 1,
                  mediaType: 'image',
                  localPath: '/tmp/stale-deleted-image.png',
                  downloadStatus: 'done',
                  createdAt: '2026-02-09T15:30:00.000Z',
                ),
              ],
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      final card = tester.widget<LetterCard>(
        find.descendant(
          of: find.byKey(const ValueKey('msg-$messageId')),
          matching: find.byType(LetterCard),
        ),
      );
      expect(card.media, isEmpty);
      expect(
        find.byKey(
          const ValueKey('media-grid-cell-$messageId-stale-deleted-image'),
        ),
        findsNothing,
      );
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
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

    testWidgets('renders media preview text for quoted media replies', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'quoted-media-parent',
              text: '',
              media: [makeImageAttachment(id: 'quoted-photo-1')],
            ),
            makeMessage(
              id: 'quoted-media-reply',
              text: 'Reply to a photo',
              isIncoming: false,
              quotedMessageId: 'quoted-media-parent',
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Message unavailable'), findsNothing);
    });

    testWidgets(
      'quoted replies live-resolve updated parent text after the source is edited',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(id: 'edited-parent', text: 'Original parent text'),
              makeMessage(
                id: 'reply-after-edit',
                text: 'Reply stays stable',
                isIncoming: false,
                quotedMessageId: 'edited-parent',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Original parent text'), findsWidgets);

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'edited-parent',
                text: 'Edited parent text',
                editedAt: '2026-02-09T15:40:00.000Z',
              ),
              makeMessage(
                id: 'reply-after-edit',
                text: 'Reply stays stable',
                isIncoming: false,
                quotedMessageId: 'edited-parent',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Edited parent text'), findsWidgets);
        expect(find.text('Original parent text'), findsNothing);
        expect(find.text('Reply stays stable'), findsOneWidget);
        expect(find.text('Message unavailable'), findsNothing);
      },
    );

    testWidgets(
      'after restart, conversation screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI',
      (tester) async {
        const parentId = 'restart-parent';
        const replyId = 'restart-reply';

        final preRestartMessages = [
          makeMessage(id: parentId, text: 'Quote source before restart'),
          makeMessage(
            id: 'restart-edited',
            isIncoming: false,
            text: 'Editable before restart',
            timestamp: '2026-02-09T15:31:00.000Z',
          ),
          makeMessage(
            id: 'restart-deleted',
            text: 'Delete me after restart',
            timestamp: '2026-02-09T15:32:00.000Z',
          ),
        ];

        final postRestartMessages = [
          makeMessage(id: parentId, text: 'Quote source before restart'),
          makeMessage(
            id: 'restart-edited',
            isIncoming: false,
            text: 'Edited after restart',
            timestamp: '2026-02-09T15:31:00.000Z',
            editedAt: '2026-02-09T15:40:00.000Z',
          ),
          makeMessage(
            id: 'restart-deleted',
            text: '',
            timestamp: '2026-02-09T15:32:00.000Z',
            deletedAt: '2026-02-09T15:41:00.000Z',
            deletedByPeerId: '12D3KooWTestPeerId1234567890',
          ),
          makeMessage(
            id: replyId,
            isIncoming: false,
            text: 'Reply restored after restart',
            timestamp: '2026-02-09T15:42:00.000Z',
            quotedMessageId: parentId,
          ),
        ];

        final postRestartReactions = {
          replyId: [
            MessageReaction(
              id: 'restart-reaction-1',
              messageId: replyId,
              emoji: '🔥',
              senderPeerId: '12D3KooWTestPeerId1234567890',
              timestamp: '2026-02-09T15:43:00.000Z',
              createdAt: '2026-02-09T15:43:00.000Z',
            ),
          ],
        };

        await tester.pumpWidget(
          buildTestWidget(messages: preRestartMessages, initialLoadDone: true),
        );
        await pumpFrames(tester);

        expect(find.text('Editable before restart'), findsOneWidget);
        expect(find.text('Delete me after restart'), findsOneWidget);
        expect(find.text('Reply restored after restart'), findsNothing);
        expect(find.text('(edited)'), findsNothing);
        expect(find.text('This message was deleted'), findsNothing);
        expect(find.text('🔥'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.pumpWidget(
          buildTestWidget(
            messages: postRestartMessages,
            reactions: postRestartReactions,
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Editable before restart'), findsNothing);
        expect(find.text('Delete me after restart'), findsNothing);
        expect(find.text('Edited after restart'), findsOneWidget);
        expect(find.text('Reply restored after restart'), findsOneWidget);
        expect(find.text('Quote source before restart'), findsWidgets);
        expect(find.text('(edited)'), findsOneWidget);
        expect(find.text('This message was deleted'), findsOneWidget);
        expect(find.text('🔥'), findsOneWidget);
      },
    );

    testWidgets('header shows contact name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets(
      'long-press on incoming text shows the overlay and backdrop dismisses without side effects',
      (tester) async {
        String? quotedId;
        await tester.pumpWidget(
          buildTestWidget(
            messages: [makeMessage(id: 'incoming-1', text: 'Context menu me')],
            initialLoadDone: true,
            onQuoteReply: (messageId) => quotedId = messageId,
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

        await tester.tapAt(const Offset(16, 16));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
        expect(quotedId, isNull);
        expect(find.text('Message copied to clipboard'), findsNothing);
        // 154: no copy fired, so the quiet-confirm cue must not appear either.
        expect(find.byKey(const ValueKey('quiet-confirm')), findsNothing);
      },
    );

    testWidgets(
      '1:1 text, media, and voice long-press overlays each emit one light impact',
      (tester) async {
        final platformCalls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          platformCalls.add(call);
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        Future<void> expectLightImpact({
          required ConversationMessage message,
          required Finder Function() target,
          required String variant,
        }) async {
          await tester.pumpWidget(
            buildTestWidget(
              messages: [message],
              initialLoadDone: true,
              onQuoteReply: (_) {},
            ),
          );
          await pumpFrames(tester);
          platformCalls.clear();

          final targetFinder = target();
          expect(targetFinder, findsOneWidget, reason: variant);
          await tester.longPress(targetFinder);
          await tester.pump(const Duration(milliseconds: 250));

          expect(
            find.byKey(MessageContextOverlay.overlayKey),
            findsOneWidget,
            reason: variant,
          );
          final hapticCalls = platformCalls
              .where((call) => call.method == 'HapticFeedback.vibrate')
              .toList(growable: false);
          expect(hapticCalls, hasLength(1), reason: variant);
          expect(
            hapticCalls.single.arguments,
            'HapticFeedbackType.lightImpact',
            reason: variant,
          );

          await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
        }

        await expectLightImpact(
          message: makeMessage(id: 'haptic-text', text: 'Haptic text'),
          target: () => find.text('Haptic text'),
          variant: 'text bubble',
        );
        await expectLightImpact(
          message: makeMessage(
            id: 'haptic-media',
            text: '',
            media: [
              makeImageAttachment(
                id: 'haptic-media-attachment',
                messageId: 'haptic-media',
              ),
            ],
          ),
          target: () => find.byType(MediaGridCell),
          variant: 'media bubble',
        );
        await expectLightImpact(
          message: makeMessage(
            id: 'haptic-voice',
            text: '',
            media: const [
              MediaAttachment(
                id: 'haptic-voice-attachment',
                messageId: 'haptic-voice',
                mime: 'audio/mp4',
                size: 2048,
                mediaType: 'audio',
                durationMs: 4200,
                downloadStatus: 'pending',
                createdAt: '2026-02-09T15:32:00.000Z',
                waveform: <double>[0.2, 0.6, 0.3],
              ),
            ],
          ),
          target: () => find.byKey(const ValueKey('haptic-voice-attachment')),
          variant: 'voice bubble',
        );
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

    testWidgets('rapid repeat long-press keeps a single overlay active', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage(id: 'repeat-1', text: 'Repeat overlay')],
          initialLoadDone: true,
          onQuoteReply: (_) {},
        ),
      );
      await pumpFrames(tester);

      final messageFinder = find.byKey(const ValueKey('msg-repeat-1'));
      await tester.longPress(messageFinder);
      await tester.longPress(messageFinder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);

      await tester.tap(
        find.byKey(MessageContextOverlay.backdropKey),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

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

    testWidgets(
      'edit action skips deleted outgoing rows and still targets the latest live outgoing message',
      (tester) async {
        String? editedId;
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'outgoing-live',
                isIncoming: false,
                text: 'Still editable',
              ),
              makeMessage(
                id: 'outgoing-deleted',
                isIncoming: false,
                text: '',
                timestamp: '2026-02-09T15:31:00.000Z',
                deletedAt: '2026-02-09T15:31:30.000Z',
                deletedByPeerId: '12D3KooWMyPeerId1234567890',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (messageId) => editedId = messageId,
          ),
        );
        await pumpFrames(tester);

        expect(find.text('This message was deleted'), findsOneWidget);

        await tester.longPress(find.text('Still editable'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.editActionKey), findsOneWidget);

        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(editedId, 'outgoing-live');
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

    testWidgets('edit action stays hidden for failed outgoing rows', (
      tester,
    ) async {
      String? editedId;
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'failed-outgoing-edit',
              isIncoming: false,
              text: 'Failed outgoing text',
              status: 'failed',
            ),
          ],
          initialLoadDone: true,
          onEditMessage: (messageId) => editedId = messageId,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Failed outgoing text'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      expect(editedId, isNull);
    });

    testWidgets(
      'edit action stays hidden when edit mode is disabled or the callback is not wired',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'editable-disabled',
                isIncoming: false,
                text: 'Disabled edit',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (_) {},
            allowEditAction: false,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Disabled edit'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);

        await tester.tapAt(const Offset(10, 10));
        await tester.pump(const Duration(milliseconds: 250));

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'editable-unwired',
                isIncoming: false,
                text: 'Unwired edit',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Unwired edit'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      },
    );

    testWidgets(
      'edit action stays hidden when own identity is missing, the row is incoming, or the row is owned by another peer',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'missing-identity',
                isIncoming: false,
                text: 'Missing identity',
              ),
            ],
            initialLoadDone: true,
            ownPeerId: null,
            onEditMessage: (_) {},
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Missing identity'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);

        await tester.tapAt(const Offset(10, 10));
        await tester.pump(const Duration(milliseconds: 250));

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'incoming-row',
                isIncoming: true,
                text: 'Incoming',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (_) {},
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Incoming'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);

        await tester.tapAt(const Offset(10, 10));
        await tester.pump(const Duration(milliseconds: 250));

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'foreign-row',
                isIncoming: false,
                text: 'Foreign outgoing',
                senderPeerId: '12D3KooWAnotherPeer1234567890',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (_) {},
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Foreign outgoing'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      },
    );

    Future<void> expectBusyOverlayState(
      WidgetTester tester, {
      required String description,
      List<File> pendingAttachments = const [],
      bool isUploading = false,
      bool isSending = false,
      ConversationComposerViewState? composerState,
    }) async {
      ValueNotifier<ConversationComposerViewState>? composerListenable;
      if (composerState != null) {
        composerListenable = ValueNotifier(composerState);
        addTearDown(composerListenable.dispose);
      }

      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'busy-outgoing',
              isIncoming: false,
              text: 'Busy outgoing message',
            ),
          ],
          initialLoadDone: true,
          pendingAttachments: pendingAttachments,
          isUploading: isUploading,
          isSending: isSending,
          composerStateListenable: composerListenable,
          onQuoteReply: (_) {},
          onEditMessage: (_) {},
          onDeleteMessage: (_) {},
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Busy outgoing message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(MessageContextOverlay.replyActionKey),
        findsOneWidget,
        reason: description,
      );
      expect(
        find.byKey(MessageContextOverlay.copyActionKey),
        findsOneWidget,
        reason: description,
      );
      expect(
        find.byKey(MessageContextOverlay.deleteActionKey),
        findsOneWidget,
        reason: description,
      );
      expect(
        find.byKey(MessageContextOverlay.editActionKey),
        findsNothing,
        reason: description,
      );

      await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    }

    testWidgets(
      'pending attachments keep reply copy and delete available while edit stays hidden',
      (tester) async {
        final pendingAttachment = File(
          '/tmp/conversation_busy_overlay_pending.jpg',
        );

        await expectBusyOverlayState(
          tester,
          description: 'pending attachments keep non-edit actions visible',
          pendingAttachments: [pendingAttachment],
        );
      },
    );

    testWidgets(
      'uploading attachments keep reply copy and delete available while edit stays hidden',
      (tester) async {
        final pendingAttachment = File(
          '/tmp/conversation_uploading_overlay_pending.jpg',
        );

        await expectBusyOverlayState(
          tester,
          description: 'uploading attachments keep non-edit actions visible',
          pendingAttachments: [pendingAttachment],
          isUploading: true,
        );
      },
    );

    testWidgets(
      'sending keeps reply copy and delete available while edit stays hidden',
      (tester) async {
        await expectBusyOverlayState(
          tester,
          description: 'sending keeps non-edit actions visible',
          isSending: true,
        );
      },
    );

    testWidgets(
      'processing keeps reply copy and delete available while edit stays hidden',
      (tester) async {
        await expectBusyOverlayState(
          tester,
          description: 'processing keeps non-edit actions visible',
          composerState: const ConversationComposerViewState(
            isProcessing: true,
            processingProgress: 0.4,
          ),
        );
      },
    );

    testWidgets(
      'recording keeps reply copy and delete available while edit stays hidden',
      (tester) async {
        await expectBusyOverlayState(
          tester,
          description: 'recording keeps non-edit actions visible',
          composerState: const ConversationComposerViewState(
            recordingState: VoiceRecordingState.recording,
            recordingDuration: Duration(seconds: 3),
          ),
        );
      },
    );

    testWidgets(
      'copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay',
      (tester) async {
        const copiedMessage = 'Line one\nEmoji 😄\nمرحبا بالعالم';
        String? copiedText;
        var clipboardCalls = 0;
        // 154: one handler per channel — record every platform call so we can
        // assert the haptic alongside the clipboard payload.
        final platformCalls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          platformCalls.add(call);
          if (call.method == 'Clipboard.setData') {
            clipboardCalls++;
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(id: 'copy-1', text: 'First copy'),
              makeMessage(
                id: 'copy-2',
                text: copiedMessage,
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('First copy'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(copiedText, 'First copy');
        expect(find.byKey(const ValueKey('quiet-confirm')), findsOneWidget);
        expect(find.text('Message copied to clipboard'), findsOneWidget);

        await tester.longPress(find.textContaining('Emoji 😄'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(clipboardCalls, 2);
        expect(copiedText, copiedMessage);
        expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
        // 154: the 2nd copy's hideCurrentSnackBar() inside showQuietConfirm
        // replaces the 1st cue, preserving the "replaces the prior" contract —
        // exactly one keyed quiet-confirm survives.
        expect(find.byKey(const ValueKey('quiet-confirm')), findsOneWidget);
        expect(find.text('Message copied to clipboard'), findsOneWidget);
        // One selectionClick per copy (two copies => two haptics). Assert the
        // arg, not just the shared method string.
        expect(
          platformCalls
              .where(
                (c) =>
                    c.method == 'HapticFeedback.vibrate' &&
                    c.arguments == 'HapticFeedbackType.selectionClick',
              )
              .length,
          2,
        );
      },
    );

    testWidgets(
      'copy action localizes the quiet confirm in Arabic while preserving mixed-script clipboard text',
      (tester) async {
        const copiedMessage = 'مرحبا Hello\nEmoji 😄';
        String? copiedText;
        final platformCalls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          platformCalls.add(call);
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          buildTestWidget(
            locale: const Locale('ar'),
            messages: [makeMessage(id: 'copy-ar', text: copiedMessage)],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.textContaining('مرحبا Hello'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(copiedText, copiedMessage);
        // 154: the localized cue rides the distinct keyed quiet-confirm.
        expect(find.byKey(const ValueKey('quiet-confirm')), findsOneWidget);
        expect(find.text('تم نسخ الرسالة إلى الحافظة'), findsOneWidget);
        expect(
          platformCalls.any(
            (c) =>
                c.method == 'HapticFeedback.vibrate' &&
                c.arguments == 'HapticFeedbackType.selectionClick',
          ),
          isTrue,
          reason: 'copy should fire HapticFeedback.selectionClick()',
        );
      },
    );

    testWidgets(
      'copy action stays safe when the conversation screen is disposed during the clipboard await',
      (tester) async {
        final showScreen = ValueNotifier(true);
        final clipboardCompleter = Completer<void>();
        var clipboardCalls = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls++;
            await clipboardCompleter.future;
          }
          return null;
        });
        addTearDown(() {
          if (!clipboardCompleter.isCompleted) {
            clipboardCompleter.complete();
          }
          showScreen.dispose();
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: showScreen,
                builder: (context, isVisible, _) {
                  if (!isVisible) {
                    return const SizedBox.shrink();
                  }
                  return ConversationScreen(
                    contactPeerId: '12D3KooWTestPeerId1234567890',
                    contactUsername: 'Alice',
                    connectionDate: 'February 9, 2026',
                    ownPeerId: '12D3KooWMyPeerId1234567890',
                    messages: [
                      makeMessage(
                        id: 'copy-dispose',
                        text: 'Dispose during copy',
                      ),
                    ],
                    onSend: (_) {},
                    onBack: () {},
                    initialLoadDone: true,
                  );
                },
              ),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Dispose during copy'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();

        expect(clipboardCalls, 1);

        showScreen.value = false;
        await tester.pump();

        clipboardCompleter.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Message copied to clipboard'), findsNothing);
        // 154: the screen was disposed during the await, so the 1:1
        // _copyMessageText !mounted guard returns before showQuietConfirm —
        // no cue, and no throw from a localization/messenger lookup on a dead
        // context.
        expect(find.byKey(const ValueKey('quiet-confirm')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('media-only long-press hides copy action', (tester) async {
      // 136 Phase 3: the long-press snapshot now mirrors the live balloon
      // (a width-capped media bubble), which is taller than the legacy
      // full-width card. The default 800x600 test surface is too short to fit
      // reaction bar + tall media snapshot + menu; use a realistic phone-sized
      // surface (production devices have the room).
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

    testWidgets(
      'whitespace-only long-press hides edit and copy but keeps reply and delete available',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'spaces-only',
                isIncoming: false,
                text: '   \n\t  ',
              ),
            ],
            initialLoadDone: true,
            onEditMessage: (_) {},
            onDeleteMessage: (_) {},
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.byType(LetterCard));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
        expect(
          find.byKey(MessageContextOverlay.deleteActionKey),
          findsOneWidget,
        );
      },
    );

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

    testWidgets(
      'delete taps dismiss the overlay before opening one next-frame sheet even under a rapid double tap',
      (tester) async {
        var deleteCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ConversationScreen(
                  contactPeerId: '12D3KooWTestPeerId1234567890',
                  contactUsername: 'Alice',
                  connectionDate: 'February 9, 2026',
                  ownPeerId: '12D3KooWMyPeerId1234567890',
                  messages: [
                    makeMessage(
                      id: 'delete-sequencing',
                      isIncoming: false,
                      text: 'Delete with sheet',
                    ),
                  ],
                  onSend: (_) {},
                  onBack: () {},
                  initialLoadDone: true,
                  onDeleteMessage: (_) {
                    deleteCalls++;
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('Delete sheet')),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Delete with sheet'));
        await tester.pump(const Duration(milliseconds: 250));

        final deleteAction = find.byKey(MessageContextOverlay.deleteActionKey);
        expect(deleteAction, findsOneWidget);

        await tester.tap(deleteAction);
        await tester.tap(deleteAction, warnIfMissed: false);
        await tester.pump();

        expect(deleteCalls, 1);
        expect(find.text('Delete sheet'), findsNothing);

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));

        expect(deleteCalls, 1);
        expect(find.text('Delete sheet'), findsOneWidget);
      },
    );

    testWidgets('delete action stays hidden when the callback is not wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [makeMessage(id: 'no-delete-row', text: 'No delete hook')],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('No delete hook'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
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
        String? retriedMessageId;
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
            onRetryFailedMessage: (id) => retriedMessageId = id,
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

        final textRetryKey = find.byKey(
          const ValueKey('failed-message-retry-failed-text-only'),
        );
        expect(textRetryKey, findsOneWidget);
        expect(
          find.byKey(
            const ValueKey('failed-message-retry-incoming-failed-media'),
          ),
          findsNothing,
        );

        await tester.tap(textRetryKey);
        await tester.pump();

        expect(retriedMessageId, 'failed-text-only');
      },
    );

    testWidgets(
      'incoming unavailable media retry is wired for direct conversation',
      (tester) async {
        String? retriedMessageId;
        String? retriedAttachmentId;
        const messageId = 'incoming-unavailable-media';
        const attachmentId = 'incoming-unavailable-attachment';

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: messageId,
                isIncoming: true,
                media: const [
                  MediaAttachment(
                    id: attachmentId,
                    messageId: messageId,
                    mime: 'image/jpeg',
                    size: 42,
                    mediaType: 'image',
                    downloadStatus: 'failed',
                    createdAt: '2026-02-09T15:30:00.000Z',
                  ),
                ],
              ),
            ],
            initialLoadDone: true,
            onRetryUnavailableMedia: (messageId, attachmentId) async {
              retriedMessageId = messageId;
              retriedAttachmentId = attachmentId;
            },
          ),
        );
        await pumpFrames(tester);

        final retryButton = find.byKey(
          const ValueKey('unavailable-media-retry-$messageId-$attachmentId'),
        );
        expect(retryButton, findsOneWidget);

        await tester.tap(retryButton);
        await tester.pump();

        expect(retriedMessageId, messageId);
        expect(retriedAttachmentId, attachmentId);
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
        // MediaGridCell only opens media whose local file actually exists
        // (media-unavailable policy), so the fixture needs a real file.
        // Sync I/O only: real async dart:io awaited inside testWidgets'
        // FakeAsync zone deadlocks under load (10-minute test timeout).
        final tempDir = Directory.systemTemp.createTempSync('viewer_test_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final imagePath = '${tempDir.path}/open-me.jpg';
        File(imagePath).writeAsBytesSync(const [1, 2, 3]);

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'image-msg',
                media: [
                  makeImageAttachment(
                    messageId: 'image-msg',
                    ownerLane: MediaOwnerLane.direct,
                    localPath: imagePath,
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

        await tester.tap(find.byType(MediaGridCell).first);
        // Bounded pumps (not pumpAndSettle): AmbientBackground repeats forever.
        await tester.pump();
        await pumpFrames(tester);

        expect(find.text('viewer-path:$imagePath'), findsOneWidget);
        expect(find.text('viewer-index:0'), findsOneWidget);
        expect(find.text('viewer-all:$imagePath'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a later visual attachment preserves the visual-only index order',
      (tester) async {
        // MediaGridCell only opens media whose local file actually exists
        // (media-unavailable policy), so the fixtures need real files.
        // Sync I/O only: real async dart:io awaited inside testWidgets'
        // FakeAsync zone deadlocks under load (10-minute test timeout).
        final tempDir = Directory.systemTemp.createTempSync('viewer_test_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final visual1 = '${tempDir.path}/visual-1.jpg';
        final visual2 = '${tempDir.path}/visual-2.mp4';
        final visual3 = '${tempDir.path}/visual-3.jpg';
        for (final path in [visual1, visual2, visual3]) {
          File(path).writeAsBytesSync(const [1, 2, 3]);
        }

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'multi-visual-msg',
                media: [
                  makeImageAttachment(
                    id: 'img-1',
                    messageId: 'multi-visual-msg',
                    ownerLane: MediaOwnerLane.direct,
                    localPath: visual1,
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
                    messageId: 'multi-visual-msg',
                    ownerLane: MediaOwnerLane.direct,
                    localPath: visual2,
                  ),
                  makeImageAttachment(
                    id: 'img-2',
                    messageId: 'multi-visual-msg',
                    ownerLane: MediaOwnerLane.direct,
                    localPath: visual3,
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
        // Bounded pumps (not pumpAndSettle): AmbientBackground repeats forever.
        await tester.pump();
        await pumpFrames(tester);

        expect(find.text('viewer-path:$visual3'), findsOneWidget);
        expect(find.text('viewer-index:2'), findsOneWidget);
        expect(
          find.text('viewer-all:$visual1,$visual2,$visual3'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'sender stale image/video paths open the legacy viewer from durable owned copies',
      (tester) async {
        const contactPeerId = '12D3KooWTestPeerId1234567890';
        const messageId = 'sender-legacy-owned-copy';
        const imageId = 'sender-owned-image';
        const videoId = 'sender-owned-video';
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        addTearDown(MediaFileManager.debugResetDocumentsDirCache);

        final ownedImage = File(
          '${tempDir.path}/media/$contactPeerId/$imageId.jpg',
        )..createSync(recursive: true);
        ownedImage.writeAsBytesSync(const [1, 2, 3]);
        final ownedVideo = File(
          '${tempDir.path}/media/$contactPeerId/$videoId.mp4',
        )..writeAsBytesSync(const [4, 5, 6]);
        final staleImage =
            '${tempDir.path}/pending_uploads/$messageId/$imageId.jpg';
        final staleVideo =
            '${tempDir.path}/pending_uploads/$messageId/$videoId.mp4';
        expect(File(staleImage).existsSync(), isFalse);
        expect(File(staleVideo).existsSync(), isFalse);

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: messageId,
                isIncoming: false,
                media: [
                  makeImageAttachment(
                    id: imageId,
                    messageId: messageId,
                    ownerLane: MediaOwnerLane.direct,
                    localPath: staleImage,
                  ),
                  makeVideoAttachment(
                    id: videoId,
                    messageId: messageId,
                    ownerLane: MediaOwnerLane.direct,
                    localPath: staleVideo,
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
                }) => Scaffold(
                  body: Column(
                    children: [
                      Text('viewer-path:$localPath'),
                      Text('viewer-index:$initialIndex'),
                      Text('viewer-all:${allPaths.join(",")}'),
                    ],
                  ),
                ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byType(MediaGridCell).at(1));
        await tester.pump();
        await pumpFrames(tester);

        expect(find.text('viewer-path:${ownedVideo.path}'), findsOneWidget);
        expect(find.text('viewer-index:1'), findsOneWidget);
        expect(
          find.text('viewer-all:${ownedImage.path},${ownedVideo.path}'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'sender stale image/video paths build typed viewer items from the same durable owned copies',
      (tester) async {
        const contactPeerId = '12D3KooWTestPeerId1234567890';
        const messageId = 'sender-typed-owned-copy';
        const imageId = 'typed-owned-image';
        const videoId = 'typed-owned-video';
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        addTearDown(MediaFileManager.debugResetDocumentsDirCache);

        final ownedImage =
            File('${tempDir.path}/media/$contactPeerId/$imageId.jpg')
              ..createSync(recursive: true)
              ..writeAsBytesSync(const [1, 2, 3]);
        final ownedVideo = File(
          '${tempDir.path}/media/$contactPeerId/$videoId.mp4',
        )..writeAsBytesSync(const [4, 5, 6]);
        final staleImage =
            '${tempDir.path}/pending_uploads/$messageId/$imageId.jpg';
        final staleVideo =
            '${tempDir.path}/pending_uploads/$messageId/$videoId.mp4';

        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: messageId,
                isIncoming: false,
                media: [
                  makeImageAttachment(
                    id: imageId,
                    messageId: messageId,
                    ownerLane: MediaOwnerLane.direct,
                    localPath: staleImage,
                  ),
                  makeVideoAttachment(
                    id: videoId,
                    messageId: messageId,
                    ownerLane: MediaOwnerLane.direct,
                    localPath: staleVideo,
                  ),
                ],
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byType(MediaGridCell).first);
        await tester.pump();
        await pumpFrames(tester);

        final viewer = tester.widget<FullScreenTypedMediaViewer>(
          find.byType(FullScreenTypedMediaViewer),
        );
        expect(viewer.initialIndex, 0);
        expect(viewer.items.map((item) => item.attachmentId), [
          imageId,
          videoId,
        ]);
        expect(viewer.items.map((item) => item.localPath), [
          ownedImage.path,
          ownedVideo.path,
        ]);
        expect(
          viewer.items.every((item) => item.protection.isDownloaded),
          isTrue,
        );
      },
    );
  });

  // 136 Phase 3: wire bubble grouping into the 1:1 conversation screen.
  group('ConversationScreen bubble grouping (136 Phase 3)', () {
    // The live LetterCard for [messageId] (the one rendered inside the
    // per-message ValueKey('msg-<id>') padding, NOT a long-press snapshot).
    LetterCard liveLetterCard(WidgetTester tester, String messageId) {
      return tester.widget<LetterCard>(
        find.descendant(
          of: find.byKey(ValueKey('msg-$messageId')),
          matching: find.byType(LetterCard),
        ),
      );
    }

    // 155 TC-19 — the 1:1 screen opts into the transport status glyph, so an
    // outgoing message that reached over the relay renders the cell_tower glyph
    // (not the v1 inbox_rounded). Locks the `transportStatusGlyph: true` wiring.
    testWidgets(
      '155 1:1 conversation passes transportStatusGlyph: true (outgoing relay '
      'renders cell_tower, not the v1 inbox glyph)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'wire-1',
                isIncoming: false,
                text: 'Sent over relay',
                status: 'delivered',
                transport: 'relay',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        // Source-wiring lock: the live LetterCard carries the opt-in flag.
        expect(liveLetterCard(tester, 'wire-1').transportStatusGlyph, isTrue);
        // End-to-end: the flag drives the transport glyph through the screen.
        expect(find.byIcon(Icons.cell_tower), findsOneWidget);
        expect(find.byIcon(Icons.inbox_rounded), findsNothing);
      },
    );

    testWidgets(
      'TC-17 1:1 consecutive same-sender incoming messages render no avatar on '
      'any balloon',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'in-1',
                isIncoming: true,
                text: 'First incoming',
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'in-2',
                isIncoming: true,
                text: 'Second incoming',
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        // 1:1 drops avatars entirely — no UserAvatar on any balloon inside the
        // message list (the contact avatar in the header is unrelated).
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('messages')),
            matching: find.byType(UserAvatar),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('TC-18 1:1 own consecutive messages group (second balloon not '
        'first-in-run)', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(
              id: 'out-1',
              isIncoming: false,
              text: 'My first',
              timestamp: '2026-02-09T15:30:00.000Z',
            ),
            makeMessage(
              id: 'out-2',
              isIncoming: false,
              text: 'My second',
              timestamp: '2026-02-09T15:31:00.000Z',
            ),
          ],
          initialLoadDone: true,
        ),
      );
      await pumpFrames(tester);

      // First outgoing balloon starts the run.
      expect(liveLetterCard(tester, 'out-1').isFirstInGroup, isTrue);
      // Second outgoing balloon continues the run (grouped).
      expect(liveLetterCard(tester, 'out-2').isFirstInGroup, isFalse);
      // Both render as bubbles (side-aligned chat balloons).
      expect(liveLetterCard(tester, 'out-1').bubbleLayout, isTrue);
      expect(liveLetterCard(tester, 'out-2').bubbleLayout, isTrue);
    });

    testWidgets(
      'TC-19 1:1 outgoing balloon is swipe-to-reply enabled and quotes the '
      'correct id',
      (tester) async {
        String? quotedId;
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'swipe-out-1',
                isIncoming: false,
                text: 'Swipe my outgoing',
              ),
            ],
            initialLoadDone: true,
            onQuoteReply: (id) => quotedId = id,
          ),
        );
        await pumpFrames(tester);

        // Outgoing message is now wrapped in SwipeToQuoteBubble.
        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

        // Swiping the outgoing balloon triggers a quote-reply with its id.
        await tester.drag(find.byType(SwipeToQuoteBubble), const Offset(80, 0));
        await tester.pump();

        expect(quotedId, 'swipe-out-1');
      },
    );

    testWidgets(
      'TC-20 1:1 system message breaks the run (message after system is '
      'first-in-run)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'before-sys',
                isIncoming: false,
                text: 'Before system',
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'the-sys',
                isIncoming: false,
                text: 'Connected through Noor',
                timestamp: '2026-02-09T15:30:30.000Z',
                transport: 'system',
              ),
              makeMessage(
                id: 'after-sys',
                isIncoming: false,
                text: 'After system',
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        // The system row renders through IntroSystemMessage (run-break).
        expect(find.byType(IntroSystemMessage), findsOneWidget);
        // The same-sender message after the system row starts a fresh run,
        // even though before/after share senderPeerId within the gap.
        expect(liveLetterCard(tester, 'after-sys').isFirstInGroup, isTrue);
      },
    );

    testWidgets(
      'TC-21 1:1 date separator breaks the run (first message after a new day '
      'is first-in-run)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'day1-msg',
                isIncoming: false,
                text: 'Day one message',
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'day2-msg',
                isIncoming: false,
                text: 'Day two message',
                timestamp: '2026-02-10T15:30:00.000Z',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        // A date separator intervenes between the two messages.
        expect(find.byType(DateSeparator), findsWidgets);
        // The first message of the new day starts a fresh run.
        expect(liveLetterCard(tester, 'day2-msg').isFirstInGroup, isTrue);
      },
    );

    testWidgets(
      'TC-22 1:1 per-message ValueKey(msg-<id>) preserved (sentinel)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(
                id: 'key-a',
                isIncoming: true,
                text: 'Keyed A',
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'key-b',
                isIncoming: true,
                text: 'Keyed B',
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await pumpFrames(tester);

        // Per-message keys remain at the balloon level (not hoisted to a run).
        expect(find.byKey(const ValueKey('msg-key-a')), findsOneWidget);
        expect(find.byKey(const ValueKey('msg-key-b')), findsOneWidget);
      },
    );
  });

  group('run-aware spacing (137 follow-up)', () {
    testWidgets(
      'mid-run message gets a tight gap; the run end gets the separation gap',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            initialLoadDone: true,
            messages: [
              makeMessage(
                id: 'r1',
                text: 'one',
                isIncoming: true,
                timestamp: '2026-02-09T15:30:00.000Z',
              ),
              makeMessage(
                id: 'r2',
                text: 'two',
                isIncoming: true,
                timestamp: '2026-02-09T15:31:00.000Z',
              ),
              makeMessage(
                id: 'r3',
                text: 'three',
                isIncoming: true,
                // >5 min after r2 → starts a new run.
                timestamp: '2026-02-09T15:40:00.000Z',
              ),
            ],
          ),
        );
        await pumpFrames(tester);

        double bottomOf(String id) {
          final pad = tester.widget<Padding>(find.byKey(ValueKey('msg-$id')));
          return pad.padding.resolve(TextDirection.ltr).bottom;
        }

        // r1 is mid-run (r2 continues it) → tight gap.
        expect(bottomOf('r1'), lessThan(8));
        // r2 is the last of its run (r3 starts a new run) → separation gap.
        expect(bottomOf('r2'), greaterThan(10));
        // r3 is the final message → separation gap.
        expect(bottomOf('r3'), greaterThan(10));
      },
    );
  });

  // 156 QW-11 (lists-scrolling-4): entrance animation runs ONLY for a genuinely
  // new (appended) message, not for every row on the initial paint. The
  // _AnimatedLetterCard wrapper keys on the bare message id; a non-animated row
  // keeps only its `msg-<id>` outer key.
  group('156 QW-11 entrance animation', () {
    testWidgets(
      'TC-21: existing (non-new) rows do not entrance-animate on first paint',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              makeMessage(id: 'first-row', text: 'First'),
              makeMessage(id: 'last-row', text: 'Last'),
            ],
            initialLoadDone: false,
          ),
        );
        // Duration pump drains the zero-delay entry-animation timer(s).
        await tester.pump(const Duration(milliseconds: 500));

        // The non-last row is present...
        expect(find.byKey(const ValueKey('msg-first-row')), findsOneWidget);
        // ...but is NOT entrance-animated (no _AnimatedLetterCard, which keys on
        // the bare message id).
        expect(find.byKey(const ValueKey('first-row')), findsNothing);
      },
    );

    testWidgets('TC-22: a newly-appended (isNew) message entrance-animates', (
      tester,
    ) async {
      // Positive control: the last message on the first build (when the list
      // was empty) is the "new" one and MUST animate.
      await tester.pumpWidget(
        buildTestWidget(
          messages: [
            makeMessage(id: 'older-row', text: 'Older'),
            makeMessage(id: 'newest-row', text: 'Newest'),
          ],
          initialLoadDone: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const ValueKey('newest-row')), findsOneWidget);
    });
  });

  // 159 TC-159-09b — Accepted Difference: the quoted-parent map is window-only
  // (no DB fallback), so a reply whose quoted PARENT is beyond the in-memory
  // window (evicted by the ~300 cap, or simply not loaded) renders
  // "quote-unavailable". This locks that documented behavior under the cap.
  group('159 quote into an evicted/absent parent (accepted difference)', () {
    LetterCard liveLetterCard(WidgetTester tester, String messageId) {
      return tester.widget<LetterCard>(
        find.descendant(
          of: find.byKey(ValueKey('msg-$messageId')),
          matching: find.byType(LetterCard),
        ),
      );
    }

    testWidgets(
      'TC-159-09b a reply whose quoted parent is not in the window shows '
      'quote-unavailable',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            messages: [
              // The reply is present; its quoted parent ('evicted-parent') is
              // NOT in the list (simulating eviction beyond the window cap).
              makeMessage(
                id: 'reply-1',
                isIncoming: false,
                text: 'a reply to an old message',
                quotedMessageId: 'evicted-parent',
              ),
            ],
            initialLoadDone: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          liveLetterCard(tester, 'reply-1').isQuoteUnavailable,
          isTrue,
          reason:
              'an evicted/absent quoted parent resolves to quote-unavailable',
        );
      },
    );
  });
}
