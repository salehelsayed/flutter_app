import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

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
            body: ContactPickerRow(contact: contactAlice, onTap: () {}),
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

    testWidgets('shows check_circle when isSelected is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactPickerRow(
              contact: contactAlice,
              onTap: () {},
              isSelected: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    });

    testWidgets('shows add_circle_outline when isSelected is false (default)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactPickerRow(contact: contactAlice, onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });
  });

  // --- Phase 2: ContactPickerScreen (Pure UI) ---

  group('ContactPickerScreen', () {
    Widget buildTestWidget({
      List<ContactModel> contacts = const [],
      bool isInviting = false,
      ValueChanged<ContactModel>? onToggle,
      Set<String> selectedPeerIds = const {},
      VoidCallback? onConfirm,
      VoidCallback? onBack,
      BackgroundPreference backgroundPreference =
          BackgroundPreference.defaultBackground,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContactPickerScreen(
          contacts: contacts,
          isInviting: isInviting,
          onToggle: onToggle ?? (_) {},
          selectedPeerIds: selectedPeerIds,
          onConfirm: onConfirm,
          onBack: onBack ?? () {},
          backgroundPreference: backgroundPreference,
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

    testWidgets('shows empty state when no contacts available', (tester) async {
      await tester.pumpWidget(buildTestWidget(contacts: []));

      expect(find.text('No contacts available'), findsOneWidget);
    });

    testWidgets('calls onToggle when contact is tapped', (tester) async {
      ContactModel? toggled;

      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob],
          onToggle: (c) => toggled = c,
        ),
      );

      await tester.tap(find.text('Alice'));
      expect(toggled?.username, equals('Alice'));
    });

    testWidgets('calls onBack when back button is tapped', (tester) async {
      var backCalled = false;

      await tester.pumpWidget(buildTestWidget(onBack: () => backCalled = true));

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      expect(backCalled, isTrue);
    });

    testWidgets('header shows "Add Members (N)" when contacts are selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob],
          selectedPeerIds: {contactAlice.peerId, contactBob.peerId},
        ),
      );

      expect(find.text('Add Members (2)'), findsOneWidget);
      expect(find.text('Add Member'), findsNothing);
    });

    testWidgets('header shows "Add Member" when nothing selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(contacts: [contactAlice], selectedPeerIds: {}),
      );

      expect(find.text('Add Member'), findsOneWidget);
    });

    testWidgets('shows check_circle for selected contacts in list', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob],
          selectedPeerIds: {contactAlice.peerId},
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    });

    testWidgets('shows Send Invites button when 1+ selected', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice],
          selectedPeerIds: {contactAlice.peerId},
          onConfirm: () {},
        ),
      );

      expect(find.text('Send Invites'), findsOneWidget);
    });

    testWidgets('hides Send Invites button when none selected', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice],
          selectedPeerIds: {},
          onConfirm: () {},
        ),
      );

      expect(find.text('Send Invites'), findsNothing);
    });

    testWidgets('calls onConfirm when Send Invites tapped', (tester) async {
      var confirmed = false;

      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice],
          selectedPeerIds: {contactAlice.peerId},
          onConfirm: () => confirmed = true,
        ),
      );

      await tester.tap(find.text('Send Invites'));
      expect(confirmed, isTrue);
    });

    testWidgets('search still works in multi-select mode', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob, contactCharlie],
          selectedPeerIds: {contactAlice.peerId},
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
        buildTestWidget(contacts: [contactAlice], isInviting: true),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('daylight lagoon keeps contact picker content readable', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          contacts: [contactAlice, contactBob],
          selectedPeerIds: {contactAlice.peerId},
          onConfirm: () {},
          backgroundPreference: BackgroundPreference.daylightLagoon,
        ),
      );

      const colors = BackgroundReadableColors.representativeLight;
      final header = tester.widget<Text>(find.text('Add Members (1)'));
      expectTextContrast(header.style!.color!, colors.surfaceBase);

      final alice = tester.widget<Text>(find.text('Alice'));
      expectTextContrast(alice.style!.color!, colors.surfaceBase);

      final peerId = tester.widget<Text>(find.text('peer-alice-1...'));
      expectTextContrast(peerId.style!.color!, colors.surfaceBase);
    });
  });
}
