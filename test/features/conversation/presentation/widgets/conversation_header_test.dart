import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onBack,
    VoidCallback? onOverflow,
    VoidCallback? onCall,
    bool showCallAction = false,
    bool callActionEnabled = true,
    bool callActionInFlight = false,
    String callUnavailableMessage =
        'Voice calling is unavailable for this device',
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Theme(
        data: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
        child: Scaffold(
          body: ConversationHeader(
            contactPeerId: '12D3KooWTestPeerId1234567890',
            contactUsername: 'Alice',
            connectionDate: 'February 9, 2026',
            onBack: onBack ?? () {},
            onOverflow: onOverflow,
            onCall: onCall,
            showCallAction: showCallAction,
            callActionEnabled: callActionEnabled,
            callActionInFlight: callActionInFlight,
            callUnavailableMessage: callUnavailableMessage,
          ),
        ),
      ),
    );
  }

  group('ConversationHeader', () {
    testWidgets('displays contact username', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('exposes a conversation-specific route marker', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final marker = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'mknoon.conversation.Alice',
        ),
      );
      expect(marker.container, isTrue);
    });

    testWidgets('displays connection date', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Connected February 9, 2026'), findsOneWidget);
    });

    testWidgets('shows back chevron icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('shows overflow menu icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('back button fires onBack callback', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(
        buildTestWidget(onBack: () => backPressed = true),
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(backPressed, true);
    });

    testWidgets('overflow button fires onOverflow callback', (tester) async {
      var overflowPressed = false;
      await tester.pumpWidget(
        buildTestWidget(onOverflow: () => overflowPressed = true),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      expect(overflowPressed, true);
    });

    testWidgets('hides phone action without a resolved call endpoint', (
      tester,
    ) async {
      var callCount = 0;
      await tester.pumpWidget(buildTestWidget(onCall: () => callCount += 1));

      expect(find.byIcon(Icons.call_outlined), findsNothing);
      expect(find.byTooltip('Start voice call'), findsNothing);
      expect(callCount, 0);
    });

    testWidgets('resolved call-capable endpoint exposes phone action', (
      tester,
    ) async {
      var callCount = 0;
      await tester.pumpWidget(
        buildTestWidget(showCallAction: true, onCall: () => callCount += 1),
      );

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('Start voice call'));
      expect(callCount, 1);
    });

    testWidgets(
      'resolved call action exposes its label and tap on one semantic node',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var callCount = 0;
          await tester.pumpWidget(
            buildTestWidget(showCallAction: true, onCall: () => callCount += 1),
          );

          final action = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Start voice call',
          );
          expect(action, findsOneWidget);
          final marker = tester.widget<Semantics>(action);
          final data = tester.getSemantics(action).getSemanticsData();
          expect(marker.properties.onTap, isNotNull);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          tester.semantics.performAction(
            find.semantics.byLabel('Start voice call'),
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(callCount, 1);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('disabled call action explains without starting a session', (
      tester,
    ) async {
      const reason = 'Voice calling is unavailable for this device';
      var callCount = 0;
      await tester.pumpWidget(
        buildTestWidget(
          showCallAction: true,
          callActionEnabled: false,
          callUnavailableMessage: reason,
          onCall: () => callCount += 1,
        ),
      );

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      expect(find.byTooltip(reason), findsOneWidget);
      await tester.tap(find.byTooltip(reason), warnIfMissed: false);
      await tester.pump();

      expect(callCount, 0);
      expect(find.text(reason), findsOneWidget);
    });

    testWidgets(
      'start-in-flight uses truthful copy and stays non-dispatching',
      (tester) async {
        var callCount = 0;
        await tester.pumpWidget(
          buildTestWidget(
            showCallAction: true,
            callActionEnabled: false,
            callActionInFlight: true,
            onCall: () => callCount += 1,
          ),
        );

        expect(find.byTooltip('Starting voice call'), findsOneWidget);
        expect(
          find.byTooltip('Voice calling is unavailable for this device'),
          findsNothing,
        );
        await tester.tap(find.byIcon(Icons.call_outlined), warnIfMissed: false);
        await tester.pump();

        expect(callCount, 0);
        expect(
          find.text('Voice calling is unavailable for this device'),
          findsNothing,
        );
      },
    );

    testWidgets('renders RingAvatar with 36px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.size, 36);
    });

    testWidgets('uses representative light readable roles', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          readableColors: BackgroundReadableColors.representativeLight,
        ),
      );

      final name = tester.widget<Text>(find.text('Alice'));
      expect(
        name.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );

      final backIcon = tester.widget<Icon>(find.byIcon(Icons.chevron_left));
      expect(
        backIcon.color,
        BackgroundReadableColors.representativeLight.iconSecondary,
      );

      final headerContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient is LinearGradient,
        ),
      );
      final decoration = headerContainer.decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;
      expect(
        gradient.colors.first,
        BackgroundReadableColors.representativeLight.glassSurface,
      );
    });
  });
}
