import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_name_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

// --- Test data ---

ContactModel makeContact({
  required String peerId,
  required String username,
}) =>
    ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'mlkem-pk-$peerId',
    );

final contactAlice = makeContact(peerId: 'peer-alice', username: 'Alice');
final contactBob = makeContact(peerId: 'peer-bob', username: 'Bob');
final contactCharlie = makeContact(peerId: 'peer-charlie', username: 'Charlie');

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('CreateGroupPickerScreen', () {
    late Set<String> selectedPeerIds;
    ContactModel? lastToggled;
    bool backCalled = false;

    setUp(() {
      selectedPeerIds = {};
      lastToggled = null;
      backCalled = false;
    });

    Widget buildWidget({
      List<ContactModel>? contacts,
      Set<String>? selected,
      bool isCreating = false,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CreateGroupPickerScreen(
          contacts: contacts ?? [contactAlice, contactBob, contactCharlie],
          selectedPeerIds: selected ?? selectedPeerIds,
          onToggle: (contact) => lastToggled = contact,
          onStartGroup: (_) {},
          onBack: () => backCalled = true,
          isCreating: isCreating,
        ),
      );
    }

    testWidgets('renders header with New Group title', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('New Group'), findsOneWidget);
    });

    testWidgets('renders search field', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('Search contacts...'), findsOneWidget);
    });

    testWidgets('renders contact rows', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.byType(ContactPickerRow), findsNWidgets(3));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('shows empty state when no contacts', (tester) async {
      await tester.pumpWidget(buildWidget(contacts: []));
      await pumpFrames(tester);

      expect(find.text('No contacts available'), findsOneWidget);
    });

    testWidgets('search filters contacts by username', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Enter search term
      await tester.enterText(find.byType(TextField).first, 'Ali');
      await pumpFrames(tester);

      // Only Alice should be visible
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('tapping contact calls onToggle', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      await tester.tap(find.text('Alice'));
      expect(lastToggled?.peerId, 'peer-alice');
    });

    testWidgets('GroupNamePanel hidden when no contacts selected',
        (tester) async {
      await tester.pumpWidget(buildWidget(selected: {}));
      await pumpFrames(tester);

      expect(find.byType(GroupNamePanel), findsNothing);
    });

    testWidgets('GroupNamePanel visible when contacts selected',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        selected: {'peer-alice'},
      ));
      await pumpFrames(tester);

      expect(find.byType(GroupNamePanel), findsOneWidget);
      expect(find.text('Start group chat'), findsOneWidget);
    });

    testWidgets('back button calls onBack', (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      expect(backCalled, isTrue);
    });

    testWidgets('shows loading state when isCreating', (tester) async {
      await tester.pumpWidget(buildWidget(
        selected: {'peer-alice'},
        isCreating: true,
      ));
      await pumpFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
