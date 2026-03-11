import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_progress_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/choice_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('IdentityProgressScreen', () {
    testWidgets(
      'renders generating progress surface with exact copy and spinner',
      (tester) async {
        final stage = ValueNotifier<String>('generating_keys');

        await tester.pumpWidget(
          wrap(IdentityProgressScreen(stageListenable: stage)),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Creating your secure identity'), findsOneWidget);
        expect(
          find.text(
            'Generating encryption keys on this device. This only happens once.',
          ),
          findsOneWidget,
        );
        expect(find.text('Generate keys'), findsOneWidget);
        expect(find.text('Save to device'), findsOneWidget);
        expect(find.text('Please keep the app open.'), findsOneWidget);
        expect(find.text("I'm new here"), findsNothing);
        expect(find.text('Load my key'), findsNothing);
        expect(find.byType(ChoiceCard), findsNothing);
      },
    );

    testWidgets(
      'renders saving progress surface with exact copy and step state',
      (tester) async {
        final stage = ValueNotifier<String>('saving');

        await tester.pumpWidget(
          wrap(IdentityProgressScreen(stageListenable: stage)),
        );

        expect(find.text('Securing your identity'), findsOneWidget);
        expect(
          find.text('Saving your identity to secure storage.'),
          findsOneWidget,
        );
        expect(find.text('Almost there.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('identity-progress-step-0-complete')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('identity-progress-step-1-active')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'updates copy when stage changes from generating_keys to saving',
      (tester) async {
        final stage = ValueNotifier<String>('generating_keys');

        await tester.pumpWidget(
          wrap(IdentityProgressScreen(stageListenable: stage)),
        );

        expect(find.text('Creating your secure identity'), findsOneWidget);

        stage.value = 'saving';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Creating your secure identity'), findsNothing);
        expect(find.text('Securing your identity'), findsOneWidget);
      },
    );

    testWidgets(
      'does not paint both stage copies on top of each other during transition',
      (tester) async {
        final stage = ValueNotifier<String>('generating_keys');

        await tester.pumpWidget(
          wrap(IdentityProgressScreen(stageListenable: stage)),
        );

        stage.value = 'saving';
        await tester.pump(const Duration(milliseconds: 90));

        expect(find.text('Creating your secure identity'), findsNothing);
        expect(find.text('Securing your identity'), findsOneWidget);
        expect(find.text('Please keep the app open.'), findsNothing);
        expect(find.text('Almost there.'), findsOneWidget);
      },
    );

    testWidgets('prevents back navigation while progress is active', (
      tester,
    ) async {
      final stage = ValueNotifier<String>('generating_keys');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            IdentityProgressScreen(stageListenable: stage),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(IdentityProgressScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(IdentityProgressScreen), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets(
      'does not render onboarding choice actions on the progress route',
      (tester) async {
        final stage = ValueNotifier<String>('generating_keys');

        await tester.pumpWidget(
          wrap(IdentityProgressScreen(stageListenable: stage)),
        );

        expect(find.text("I'm new here"), findsNothing);
        expect(find.text('Load my key'), findsNothing);
        expect(find.byType(ChoiceCard), findsNothing);
      },
    );
  });
}
