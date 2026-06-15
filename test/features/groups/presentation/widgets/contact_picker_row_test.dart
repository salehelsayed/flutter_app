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

    testWidgets(
        'onTap fires when an empty (non-name) region of the row is tapped',
        (tester) async {
      var called = false;
      // A short username leaves genuine transparent space in the row, and a
      // bounded width with the row at its NATURAL (~52px) height makes the
      // vertical padding band a real unpainted region — NOT the full 800x600
      // surface (which would make almost any tap land on a painted child and
      // mask the bug).
      final shortNameContact = makeContact(peerId: 'p-bo', username: 'Bo');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: ContactPickerRow(
                  contact: shortNameContact,
                  onTap: () => called = true,
                ),
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(ContactPickerRow));
      // Inside the row rect but over the bottom vertical-padding band, where
      // no avatar/name/icon is painted. Fails under deferToChild (the default),
      // passes once the GestureDetector uses HitTestBehavior.opaque.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 3));
      await tester.pump();

      expect(
        called,
        isTrue,
        reason: 'the whole row should be tappable, not only painted children',
      );
    });
  });
}
