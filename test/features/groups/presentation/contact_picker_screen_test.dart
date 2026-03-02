import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';

// --- Test contacts ---
final contactAlice = ContactModel(
  peerId: 'peer-alice-1234567890',
  publicKey: 'pk-alice',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig-alice',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-alice',
);

final contactBob = ContactModel(
  peerId: 'peer-bob-1234567890',
  publicKey: 'pk-bob',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-bob',
);

final contactCharlie = ContactModel(
  peerId: 'peer-charlie-1234567890',
  publicKey: 'pk-charlie',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Charlie',
  signature: 'sig-charlie',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-charlie',
);

void main() {
  // --- Phase 1: ContactPickerRow Widget ---

  group('ContactPickerRow', () {
    testWidgets('renders username', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactPickerRow(
              contact: contactAlice,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactPickerRow(
              contact: contactAlice,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });
  });

  // --- Phase 2: ContactPickerScreen (Pure UI) ---

  group('ContactPickerScreen', () {
    Widget buildTestWidget({
      List<ContactModel> contacts = const [],
      bool isInviting = false,
      ValueChanged<ContactModel>? onSelect,
      VoidCallback? onBack,
    }) {
      return MaterialApp(
        home: ContactPickerScreen(
          contacts: contacts,
          isInviting: isInviting,
          onSelect: onSelect ?? (_) {},
          onBack: onBack ?? () {},
        ),
      );
    }

    testWidgets('renders header with title and back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Add Member'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });

    testWidgets('renders list of contacts', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(contacts: [contactAlice, contactBob]),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows empty state when no contacts available',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(contacts: []));

      expect(find.text('No contacts available'), findsOneWidget);
    });

    testWidgets('calls onSelect when contact is tapped', (tester) async {
      ContactModel? selected;

      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob],
          onSelect: (c) => selected = c,
        ),
      );

      await tester.tap(find.text('Alice'));
      expect(selected?.username, equals('Alice'));
    });

    testWidgets('calls onBack when back button is tapped', (tester) async {
      var backCalled = false;

      await tester.pumpWidget(
        buildTestWidget(onBack: () => backCalled = true),
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      expect(backCalled, isTrue);
    });

    testWidgets('search filters contacts by username', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob, contactCharlie],
        ),
      );

      // All contacts visible initially
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);

      // Type into the search field
      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pump();

      // Only Alice should be visible
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('shows loading indicator when isInviting', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice],
          isInviting: true,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
