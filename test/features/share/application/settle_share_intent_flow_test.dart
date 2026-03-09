import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/settle_share_intent_flow.dart';

void main() {
  group('settleShareIntentFlow', () {
    testWidgets('marks the app settled and pushes the buffered share route', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'pending share'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: _SettleHarness(shareIntentService: shareIntentService),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.text('feed'), findsOneWidget);
      expect(find.text('picker: pending share'), findsOneWidget);
    });

    testWidgets('still marks settled when there is no buffered share', (
      tester,
    ) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});

      await tester.pumpWidget(
        MaterialApp(
          home: _SettleHarness(shareIntentService: shareIntentService),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(shareIntentService.isSettled, isTrue);
      expect(find.text('feed'), findsOneWidget);
      expect(find.textContaining('picker:'), findsNothing);
    });
  });
}

class _SettleHarness extends StatefulWidget {
  final ShareIntentService shareIntentService;

  const _SettleHarness({required this.shareIntentService});

  @override
  State<_SettleHarness> createState() => _SettleHarnessState();
}

class _SettleHarnessState extends State<_SettleHarness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settleShareIntentFlow(
        shareIntentService: widget.shareIntentService,
        navigator: Navigator.of(context),
        buildRoute: (intent) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text('picker: ${intent.text}')),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('feed'));
  }
}
