import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';

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
    ValueListenable<ConversationComposerViewState>? composerStateListenable,
  }) {
    return MaterialApp(
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
          composerStateListenable: composerStateListenable,
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

    testWidgets('header shows contact name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
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
          isRecording: true,
          recordingDuration: Duration(seconds: 3),
          amplitudeValues: [0.2, 0.5, 0.8],
        );
        await tester.pump();

        expect(find.text('Slide to cancel'), findsOneWidget);
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
  });
}
