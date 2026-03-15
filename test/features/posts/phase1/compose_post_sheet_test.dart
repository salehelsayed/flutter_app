import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';

void main() {
  testWidgets('pick-people flow excludes blocked and archived contacts', (
    tester,
  ) async {
    ComposePostResult? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposePostSheet(
            eligibleContacts: <ContactModel>[
              _contact('peer-a', 'Alice'),
              _contact('peer-b', 'Blocked', isBlocked: true),
              _contact('peer-c', 'Archived', isArchived: true),
            ],
            onSubmit: (result) async {
              submitted = result;
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello posts');
    await tester.tap(find.text('Pick People'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Blocked'), findsNothing);
    expect(find.text('Archived'), findsNothing);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.text, 'hello posts');
    expect(submitted!.audience.kind, PostAudienceKind.pickPeople);
    expect(submitted!.audience.selectedPeerIds, <String>['peer-a']);
  });
}

ContactModel _contact(
  String peerId,
  String username, {
  bool isArchived = false,
  bool isBlocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isArchived: isArchived,
    archivedAt: isArchived ? '2026-03-15T10:00:00.000Z' : null,
    isBlocked: isBlocked,
    blockedAt: isBlocked ? '2026-03-15T10:00:00.000Z' : null,
  );
}
