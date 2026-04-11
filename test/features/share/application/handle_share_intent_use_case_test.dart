import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/handle_share_intent_use_case.dart';

void main() {
  group('handleShareIntent', () {
    testWidgets('5b: warm start with isSettled=true pushes picker directly', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'warm hello',
          ),
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(find.text('feed'), findsNothing);
      expect(find.text('picker'), findsOneWidget);
      expect(find.text('warm hello'), findsOneWidget);
    });

    testWidgets(
      '5b2: warm start with isSettled=true overlays an already open conversation',
      (tester) async {
        final shareIntentService = ShareIntentService(resetShareIntent: () {});
        shareIntentService.isSettled = true;

        await tester.pumpWidget(
          _HandleShareHarness(
            shareIntentService: shareIntentService,
            homeLabel: 'conversation',
            intent: const ShareIntent(
              type: ShareIntentType.text,
              text: 'overlay me',
            ),
          ),
        );

        expect(find.text('conversation'), findsOneWidget);

        await tester.tap(find.text('share now'));
        await tester.pumpAndSettle();

        expect(find.text('picker'), findsOneWidget);
        expect(find.text('overlay me'), findsOneWidget);
      },
    );

    testWidgets('5c: text-only shares pass raw text to the picker', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;
      ShareIntent? capturedIntent;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'raw text',
          ),
          onRouteBuilt: (intent) => capturedIntent = intent,
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(capturedIntent, isNotNull);
      expect(capturedIntent!.text, 'raw text');
      expect(capturedIntent!.filePaths, isEmpty);
    });

    testWidgets('5d: image shares pass raw file paths to the picker', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;
      ShareIntent? capturedIntent;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.files,
            filePaths: ['/tmp/raw-image.jpg'],
          ),
          onRouteBuilt: (intent) => capturedIntent = intent,
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(capturedIntent, isNotNull);
      expect(capturedIntent!.filePaths, ['/tmp/raw-image.jpg']);
    });

    testWidgets('5e: video shares pass raw file paths to the picker', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;
      ShareIntent? capturedIntent;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.files,
            filePaths: ['/tmp/raw-video.mp4'],
          ),
          onRouteBuilt: (intent) => capturedIntent = intent,
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(capturedIntent, isNotNull);
      expect(capturedIntent!.filePaths, ['/tmp/raw-video.mp4']);
    });

    testWidgets('5e2: GIF shares pass raw file paths to the picker', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;
      ShareIntent? capturedIntent;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.files,
            filePaths: ['/tmp/raw-animation.gif'],
          ),
          onRouteBuilt: (intent) => capturedIntent = intent,
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(capturedIntent, isNotNull);
      expect(capturedIntent!.filePaths, ['/tmp/raw-animation.gif']);
    });

    testWidgets('5f: picker cancel returns to the previous screen', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      shareIntentService.isSettled = true;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'cancel me',
          ),
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();
      expect(find.text('picker'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close-picker')));
      await tester.pumpAndSettle();

      expect(find.text('feed'), findsOneWidget);
      expect(find.text('picker'), findsNothing);
    });

    testWidgets('5i: settled handling calls ShareIntentService.reset()', (
      tester,
    ) async {
      var resetCalls = 0;
      final shareIntentService = ShareIntentService(
        resetShareIntent: () => resetCalls++,
      );
      shareIntentService.isSettled = true;

      await tester.pumpWidget(
        _HandleShareHarness(
          shareIntentService: shareIntentService,
          homeLabel: 'feed',
          intent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'reset me',
          ),
        ),
      );

      await tester.tap(find.text('share now'));
      await tester.pumpAndSettle();

      expect(resetCalls, 1);
    });

    testWidgets(
      '5m: warm start with isSettled=false buffers the intent without showing the picker',
      (tester) async {
        final shareIntentService = ShareIntentService(resetShareIntent: () {});

        await tester.pumpWidget(
          _HandleShareHarness(
            shareIntentService: shareIntentService,
            homeLabel: 'onboarding',
            intent: const ShareIntent(
              type: ShareIntentType.text,
              text: 'buffer me',
            ),
          ),
        );

        await tester.tap(find.text('share now'));
        await tester.pumpAndSettle();

        expect(find.text('onboarding'), findsOneWidget);
        expect(find.text('picker'), findsNothing);
        expect(shareIntentService.hasPendingIntent, isTrue);
        expect(shareIntentService.consumePendingIntent()?.text, 'buffer me');
      },
    );

    test(
      '5m2: warm start with isSettled=false keeps raw file paths buffered',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('handle_share_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final sharedFile = File('${tempDir.path}/pending-image.jpg')
          ..writeAsStringSync('image');
        final shareIntentService = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          resetShareIntent: () {},
        );

        await handleShareIntent(
          intent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [sharedFile.path],
          ),
          shareIntentService: shareIntentService,
          navigator: null,
          buildRoute: (_) => throw UnimplementedError(),
        );

        final pending = shareIntentService.consumePendingIntent();
        expect(pending, isNotNull);
        expect(pending!.filePaths.single, contains('pending-image.jpg'));
      },
    );
  });
}

class _HandleShareHarness extends StatelessWidget {
  final ShareIntentService shareIntentService;
  final String homeLabel;
  final ShareIntent intent;
  final ValueChanged<ShareIntent>? onRouteBuilt;

  const _HandleShareHarness({
    required this.shareIntentService,
    required this.homeLabel,
    required this.intent,
    this.onRouteBuilt,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Column(
              children: [
                Text(homeLabel),
                ElevatedButton(
                  onPressed: () async {
                    await handleShareIntent(
                      intent: intent,
                      shareIntentService: shareIntentService,
                      navigator: Navigator.of(context),
                      buildRoute: (routeIntent) {
                        onRouteBuilt?.call(routeIntent);
                        return MaterialPageRoute<void>(
                          builder: (routeContext) => Scaffold(
                            body: Column(
                              children: [
                                const Text('picker'),
                                if (routeIntent.text != null)
                                  Text(routeIntent.text!),
                                IconButton(
                                  key: const ValueKey('close-picker'),
                                  onPressed: () =>
                                      Navigator.of(routeContext).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('share now'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
