import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/widgets/identity_loading_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('IdentityLoadingCard', () {
    testWidgets('renders CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(wrap(const IdentityLoadingCard(stage: 'generating_keys')));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows generating keys text for generating_keys stage', (tester) async {
      await tester.pumpWidget(wrap(const IdentityLoadingCard(stage: 'generating_keys')));
      expect(find.text('Creating identity & encryption keys...'), findsOneWidget);
      expect(find.text('This only happens once'), findsOneWidget);
    });

    testWidgets('shows saving text for saving stage', (tester) async {
      await tester.pumpWidget(wrap(const IdentityLoadingCard(stage: 'saving')));
      expect(find.text('Saving securely...'), findsOneWidget);
      expect(find.text('Almost there'), findsOneWidget);
    });

    testWidgets('renders AnimatedSwitcher', (tester) async {
      await tester.pumpWidget(wrap(const IdentityLoadingCard(stage: 'generating_keys')));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets('shows "Almost there" subtitle for saving stage', (tester) async {
      await tester.pumpWidget(wrap(const IdentityLoadingCard(stage: 'saving')));
      expect(find.text('Almost there'), findsOneWidget);
    });
  });
}
