import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_name_panel.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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

void main() {
  group('GroupNamePanel', () {
    late TextEditingController nameController;

    setUp(() {
      nameController = TextEditingController();
    });

    tearDown(() {
      nameController.dispose();
    });

    Widget buildWidget({
      required List<ContactModel> selectedContacts,
      bool isCreating = false,
      VoidCallback? onStartGroup,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GroupNamePanel(
            selectedContacts: selectedContacts,
            nameController: nameController,
            onStartGroup: onStartGroup ?? () {},
            isCreating: isCreating,
          ),
        ),
      );
    }

    testWidgets('renders overlapping UserAvatars for selected contacts',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice, contactBob],
      ));

      expect(find.byType(UserAvatar), findsNWidgets(2));
    });

    testWidgets('displays comma-separated usernames', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice, contactBob],
      ));

      expect(find.text('Alice, Bob'), findsOneWidget);
    });

    testWidgets('shows group name text field with placeholder', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
      ));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Group name (optional)'), findsOneWidget);
    });

    testWidgets('shows Start group chat button', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
      ));

      expect(find.text('Start group chat'), findsOneWidget);
      expect(find.byIcon(Icons.people), findsOneWidget);
    });

    testWidgets('calls onStartGroup when button tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
        onStartGroup: () => called = true,
      ));

      await tester.tap(find.text('Start group chat'));
      expect(called, isTrue);
    });

    testWidgets('passes text field value to nameController', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
      ));

      await tester.enterText(find.byType(TextField), 'My Group');
      expect(nameController.text, 'My Group');
    });

    testWidgets('shows loading indicator when isCreating', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
        isCreating: true,
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Button text should still be there but not tappable
    });

    testWidgets('renders correctly with 1 contact', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice],
      ));

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displays +N suffix for 3+ contacts', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedContacts: [contactAlice, contactBob, contactCharlie],
      ));

      expect(find.text('Alice, Bob +1'), findsOneWidget);
    });
  });
}
