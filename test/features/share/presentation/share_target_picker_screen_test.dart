import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';

void main() {
  ContactModel makeContact({required String peerId, required String username}) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: '2026-03-09T08:00:00.000Z',
    );
  }

  GroupModel makeGroup({required String id, required String name}) {
    return GroupModel(
      id: id,
      name: name,
      type: GroupType.chat,
      topicName: 'topic-$id',
      createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
      createdBy: 'me',
      myRole: GroupRole.admin,
    );
  }

  Widget buildScreen({
    String? sharedText,
    List<String> sharedFilePaths = const [],
    List<ContactModel> contacts = const [],
    List<GroupModel> groups = const [],
    ValueChanged<ContactModel>? onContactSelected,
    ValueChanged<GroupModel>? onGroupSelected,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: ShareTargetPickerScreen(
        sharedText: sharedText,
        sharedFilePaths: sharedFilePaths,
        contacts: contacts,
        groups: groups,
        onContactSelected: onContactSelected ?? (_) {},
        onGroupSelected: onGroupSelected ?? (_) {},
        onCancel: onCancel ?? () {},
      ),
    );
  }

  testWidgets('2a: renders shared text preview', (tester) async {
    await tester.pumpWidget(buildScreen(sharedText: 'Shared caption'));

    expect(find.text('Shared caption'), findsOneWidget);
  });

  testWidgets('2b: renders shared image thumbnails', (tester) async {
    await tester.pumpWidget(
      buildScreen(sharedFilePaths: const ['/tmp/shared-photo.jpg']),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as FileImage;
    expect(provider.file.path, '/tmp/shared-photo.jpg');
  });

  testWidgets('2c and 2d: renders contact and group sections', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        groups: [makeGroup(id: 'friends', name: 'Friends')],
      ),
    );
    await tester.pump();

    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('2e: tapping contact calls onContactSelected', (tester) async {
    ContactModel? selected;
    final contact = makeContact(peerId: 'alice', username: 'Alice');

    await tester.pumpWidget(
      buildScreen(
        contacts: [contact],
        onContactSelected: (value) => selected = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(selected?.peerId, contact.peerId);
  });

  testWidgets('2f: tapping group calls onGroupSelected', (tester) async {
    GroupModel? selected;
    final group = makeGroup(id: 'friends', name: 'Friends');

    await tester.pumpWidget(
      buildScreen(
        groups: [group],
        onGroupSelected: (value) => selected = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Friends'));
    await tester.pump();

    expect(selected?.id, group.id);
  });

  testWidgets('2g: search filters both contacts and groups', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        sharedText: 'Shared caption',
        contacts: [
          makeContact(peerId: 'alice', username: 'Alice'),
          makeContact(peerId: 'bob', username: 'Bob'),
        ],
        groups: [
          makeGroup(id: 'friends', name: 'Friends'),
          makeGroup(id: 'work', name: 'Work'),
        ],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Work'), findsNothing);
  });

  testWidgets('2h: cancel button calls onCancel', (tester) async {
    var cancelCount = 0;

    await tester.pumpWidget(buildScreen(onCancel: () => cancelCount++));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(cancelCount, 1);
  });

  testWidgets('2i: empty contacts/groups shows empty state', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('No contacts or groups yet'), findsOneWidget);
  });
}
