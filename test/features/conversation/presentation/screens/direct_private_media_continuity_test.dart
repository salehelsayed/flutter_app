import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const messageId = 'private-message';
  const attachmentId = 'private-attachment';

  ConversationMessage message({
    String downloadStatus = 'pending',
    String? localPath,
  }) {
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 3,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-19T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
    return ConversationMessage(
      id: messageId,
      contactPeerId: 'contact-1',
      senderPeerId: 'contact-1',
      text: '',
      timestamp: '2026-07-19T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-19T10:00:00.000Z',
      privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
      privateMediaState: PrivateMediaLifecycleState.available,
      privateMediaReceivedAtMs: 100,
      privateMediaClockHighWaterMs: 100,
      media: [attachment],
    );
  }

  Future<void> pumpConversation(
    WidgetTester tester, {
    required ConversationMessage current,
    required Future<void> Function(String messageId, String attachmentId)
    onDownload,
    required DirectPrivateMediaResultLauncher onOpen,
    required DirectPrivateMediaAppLifecycleSnapshotProvider lifecycle,
  }) async {
    final observer = RouteObserver<ModalRoute<void>>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => DirectPrivateMediaRouteObserverScope(
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: ConversationScreen(
            contactPeerId: 'contact-1',
            contactUsername: 'Alice',
            connectionDate: 'July 19, 2026',
            messages: [current],
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
            onRetryUnavailableMedia: onDownload,
            onOpenPrivateMediaResult: onOpen,
            appLifecycleState: lifecycle().state,
            appLifecycleGeneration: lifecycle().generation,
            appLifecycleSnapshotProvider: lifecycle,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> flushFrames(WidgetTester tester) async {
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  const displayedSettlement = DirectPrivateMediaSettleResult(
    disposition: DirectPrivateMediaSettleDisposition.noLease,
    exitReason: DirectPrivateMediaExitReason.close,
    firstFrameRecorded: true,
  );

  testWidgets(
    'rapid double tap downloads then auto-continues under one single-flight',
    (tester) async {
      final downloadGate = Completer<void>();
      var lifecycle = (state: AppLifecycleState.resumed, generation: 0);
      var downloads = 0;
      var opens = 0;
      await pumpConversation(
        tester,
        current: message(),
        lifecycle: () => lifecycle,
        onDownload: (_, _) async {
          downloads++;
          await downloadGate.future;
        },
        onOpen: (identity, guard) async {
          opens++;
          expect(identity.messageId, messageId);
          expect(guard.state, DirectPrivateMediaContinuityState.valid);
          return const DirectPrivateMediaOpenResult.displayed(
            displayedSettlement,
          );
        },
      );

      final tile = find.byKey(const ValueKey('private-media-card-visual'));
      await tester.tap(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(downloads, 1);
      expect(opens, 0);
      expect(
        find.descendant(
          of: tile,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      downloadGate.complete();
      await flushFrames(tester);

      expect(downloads, 1);
      expect(opens, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'download-held route cover invalidates auto-open and a later tap requalifies',
    (tester) async {
      final downloadGate = Completer<void>();
      var lifecycle = (state: AppLifecycleState.resumed, generation: 0);
      var downloads = 0;
      var opens = 0;
      await pumpConversation(
        tester,
        current: message(),
        lifecycle: () => lifecycle,
        onDownload: (_, _) async {
          downloads++;
          await downloadGate.future;
        },
        onOpen: (_, _) async {
          opens++;
          return const DirectPrivateMediaOpenResult.displayed(
            displayedSettlement,
          );
        },
      );

      final tile = find.byKey(const ValueKey('private-media-card-visual'));
      await tester.tap(tile);
      await tester.pump();
      final navigator = Navigator.of(
        tester.element(find.byType(ConversationScreen)),
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covering route')),
          ),
        ),
      );
      await flushFrames(tester);
      navigator.pop();
      await flushFrames(tester);

      downloadGate.complete();
      await flushFrames(tester);
      expect(downloads, 1);
      expect(opens, 0);

      await tester.tap(tile);
      await flushFrames(tester);
      expect(downloads, 2);
      expect(opens, 1);
    },
  );

  testWidgets('pause-resume during download cannot auto-open', (tester) async {
    final downloadGate = Completer<void>();
    var lifecycle = (state: AppLifecycleState.resumed, generation: 0);
    var downloads = 0;
    var opens = 0;
    await pumpConversation(
      tester,
      current: message(),
      lifecycle: () => lifecycle,
      onDownload: (_, _) async {
        downloads++;
        await downloadGate.future;
      },
      onOpen: (_, _) async {
        opens++;
        return const DirectPrivateMediaOpenResult.displayed(
          displayedSettlement,
        );
      },
    );

    final tile = find.byKey(const ValueKey('private-media-card-visual'));
    await tester.tap(tile);
    await tester.pump();
    expect(downloads, 1);
    expect(
      find.descendant(
        of: tile,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    lifecycle = (state: AppLifecycleState.paused, generation: 1);
    lifecycle = (state: AppLifecycleState.resumed, generation: 2);
    downloadGate.complete();
    await flushFrames(tester);

    expect(downloads, 1);
    expect(opens, 0);
    expect(tile, findsOneWidget);
    expect(
      find.descendant(
        of: tile,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('typed pre-frame failure renders truthful retry and clears it', (
    tester,
  ) async {
    final file = File(
      '${Directory.systemTemp.path}/private-continuity-${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(const <int>[1, 2, 3]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    var lifecycle = (state: AppLifecycleState.resumed, generation: 0);
    var opens = 0;
    const rollback = DirectPrivateMediaSettleResult(
      disposition: DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      exitReason: DirectPrivateMediaExitReason.routePushFailure,
      firstFrameRecorded: false,
    );
    await pumpConversation(
      tester,
      current: message(downloadStatus: 'done', localPath: file.path),
      lifecycle: () => lifecycle,
      onDownload: (_, _) async {},
      onOpen: (_, _) async {
        opens++;
        if (opens == 1) {
          return const DirectPrivateMediaOpenResult.failed(
            DirectPrivateMediaOpenFailureReason.routePushFailure,
            settleResult: rollback,
            canRetry: true,
          );
        }
        return const DirectPrivateMediaOpenResult.displayed(
          displayedSettlement,
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('private-media-card-visual')));
    await flushFrames(tester);
    expect(
      find.byKey(const ValueKey('private-media-open-failure')),
      findsOneWidget,
    );
    expect(find.text('Your one view is still available.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('private-media-try-again')));
    await flushFrames(tester);
    expect(opens, 2);
    expect(
      find.byKey(const ValueKey('private-media-open-failure')),
      findsNothing,
    );
  });
}
