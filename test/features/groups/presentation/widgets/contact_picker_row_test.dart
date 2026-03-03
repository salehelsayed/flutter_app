import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

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

final contactAlice = makeContact(peerId: 'peer-alice-1234', username: 'Alice');

void main() {
  group('ContactPickerRow', () {
    Widget buildWidget({
      ContactModel? contact,
      bool isSelected = false,
      VoidCallback? onTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ContactPickerRow(
            contact: contact ?? contactAlice,
            onTap: onTap ?? () {},
            isSelected: isSelected,
          ),
        ),
      );
    }

    testWidgets('renders UserAvatar with contact peerId', (tester) async {
      await tester.pumpWidget(buildWidget());

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.peerId, contactAlice.peerId);
    });

    testWidgets('renders UserAvatar at size 36', (tester) async {
      await tester.pumpWidget(buildWidget());

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.size, 36);
    });

    testWidgets('displays contact username', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displays truncated peerId', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.text('peer-alice-1...'), findsOneWidget);
    });

    testWidgets('shows add_circle_outline icon when not selected',
        (tester) async {
      await tester.pumpWidget(buildWidget(isSelected: false));

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    });

    testWidgets('shows check_circle icon when selected', (tester) async {
      await tester.pumpWidget(buildWidget(isSelected: true));

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(buildWidget(onTap: () => called = true));

      await tester.tap(find.text('Alice'));
      expect(called, isTrue);
    });
  });
}
