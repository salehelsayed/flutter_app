import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
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
    );
  }

  // Use pump with duration instead of pumpAndSettle because
  // AmbientBackground has a repeating 8s animation that never settles.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('ConversationScreen', () {
    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: []));
      await tester.pump();

      expect(find.text('Connected!'), findsWidgets);
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsOneWidget,
      );
    });

    testWidgets('shows letter cards when messages present', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [
          makeMessage(id: 'msg-1', text: 'First message'),
        ],
      ));
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
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
      ));
      await pumpFrames(tester);

      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('header shows contact name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows origin marker when messages present and no more older', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
        hasMoreOlderMessages: false,
      ));
      await pumpFrames(tester);

      // Compact origin marker shows "Connected!" text
      expect(find.text('Connected!'), findsWidgets);
    });

    testWidgets('hides origin marker when hasMoreOlderMessages is true', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
        hasMoreOlderMessages: true,
      ));
      await pumpFrames(tester);

      // Origin marker should not appear — more messages above
      // Only the header has the connection info, not the origin marker
      expect(find.text('Connected!'), findsNothing);
    });

    testWidgets('shows loading indicator when isLoadingMore is true', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
        isLoadingMore: true,
        hasMoreOlderMessages: true,
      ));
      await pumpFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

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

    testWidgets('shows AttachmentPreviewStrip when pendingAttachments not empty',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
        pendingAttachments: testFiles,
        onRemoveAttachment: (_) {},
        initialLoadDone: true,
      ));
      await pumpFrames(tester);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('hides AttachmentPreviewStrip when pendingAttachments is empty',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        pendingAttachments: [],
      ));
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets('hides preview strip when blocked even if attachments exist',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        pendingAttachments: testFiles,
        isBlocked: true,
      ));
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets('passes hasAttachments to ComposeArea', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
        pendingAttachments: testFiles,
        initialLoadDone: true,
      ));
      // Use pumpFrames because AmbientBackground has repeating animation
      await pumpFrames(tester);
      await pumpFrames(tester);

      // Send button should be visible because hasAttachments is derived
      // from pendingAttachments.isNotEmpty
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity, isNotEmpty);
    });

    testWidgets('onAttach callback is passed through to ComposeArea',
        (tester) async {
      var attachCalled = false;
      await tester.pumpWidget(buildTestWidget(
        onAttach: () => attachCalled = true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      expect(attachCalled, true);
    });
  });
}
