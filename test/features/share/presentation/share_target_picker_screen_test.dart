import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

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
    TextEditingController? captionController,
    List<ContactModel> contacts = const [],
    List<GroupModel> groups = const [],
    bool isLoading = false,
    bool isSending = false,
    Set<String> selectedContactPeerIds = const {},
    Set<String> selectedGroupIds = const {},
    ValueChanged<ContactModel>? onToggleContact,
    ValueChanged<GroupModel>? onToggleGroup,
    VoidCallback? onSend,
    VoidCallback? onCancel,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ShareTargetPickerScreen(
        sharedText: sharedText,
        sharedFilePaths: sharedFilePaths,
        captionController: captionController,
        contacts: contacts,
        groups: groups,
        isLoading: isLoading,
        isSending: isSending,
        selectedContactPeerIds: selectedContactPeerIds,
        selectedGroupIds: selectedGroupIds,
        onToggleContact: onToggleContact ?? (_) {},
        onToggleGroup: onToggleGroup ?? (_) {},
        onSend: onSend,
        onCancel: onCancel ?? () {},
        backgroundPreference: backgroundPreference,
      ),
    );
  }

  testWidgets('2a: renders shared text preview', (tester) async {
    await tester.pumpWidget(buildScreen(sharedText: 'Shared caption'));

    expect(find.text('Shared caption'), findsOneWidget);
  });

  testWidgets('shared Arabic text preview drives RTL', (tester) async {
    const sharedText = 'مرحبا';

    await tester.pumpWidget(buildScreen(sharedText: sharedText));

    expect(find.text(sharedText), findsOneWidget);
    expect(_previewText(tester, sharedText).textDirection, TextDirection.rtl);
  });

  testWidgets('shared Arabic-first mixed preview drives RTL', (tester) async {
    const sharedText = 'مرحبا Hello 123';

    await tester.pumpWidget(buildScreen(sharedText: sharedText));

    expect(find.text(sharedText), findsOneWidget);
    expect(_previewText(tester, sharedText).textDirection, TextDirection.rtl);
  });

  testWidgets('shared English-first mixed preview stays LTR', (tester) async {
    const sharedText = 'Hello مرحبا 123';

    await tester.pumpWidget(buildScreen(sharedText: sharedText));

    expect(find.text(sharedText), findsOneWidget);
    expect(_previewText(tester, sharedText).textDirection, TextDirection.ltr);
  });

  testWidgets('2b: renders shared image thumbnails', (tester) async {
    await tester.pumpWidget(
      buildScreen(sharedFilePaths: const ['/tmp/shared-photo.jpg']),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('share-preview-image')),
    );
    final provider = image.image as ResizeImage;
    expect(provider.width, 144);
    expect(provider.height, 144);
    expect(
      (provider.imageProvider as FileImage).file.path,
      '/tmp/shared-photo.jpg',
    );
  });

  testWidgets('GIF preview avoids ResizeImage cache hints', (tester) async {
    await tester.pumpWidget(
      buildScreen(sharedFilePaths: const ['/tmp/shared-animation.gif']),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('share-preview-image')),
    );
    expect(image.image, isA<FileImage>());
  });

  testWidgets('shows caption field for media shares on the picker screen', (
    tester,
  ) async {
    final captionController = TextEditingController(text: 'Initial caption');
    addTearDown(captionController.dispose);

    await tester.pumpWidget(
      buildScreen(
        sharedText: 'Initial caption',
        sharedFilePaths: const ['/tmp/shared-photo.jpg'],
        captionController: captionController,
      ),
    );

    expect(find.byKey(const ValueKey('share-caption-label')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-caption-field')), findsOneWidget);
    expect(find.text('Initial caption'), findsOneWidget);
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

  testWidgets('tapping contact toggles selection via callback', (tester) async {
    ContactModel? toggled;
    final contact = makeContact(peerId: 'alice', username: 'Alice');

    await tester.pumpWidget(
      buildScreen(
        contacts: [contact],
        onToggleContact: (value) => toggled = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(toggled?.peerId, contact.peerId);
  });

  testWidgets('tapping group toggles selection via callback', (tester) async {
    GroupModel? toggled;
    final group = makeGroup(id: 'friends', name: 'Friends');

    await tester.pumpWidget(
      buildScreen(groups: [group], onToggleGroup: (value) => toggled = value),
    );
    await tester.pump();

    await tester.tap(find.text('Friends'));
    await tester.pump();

    expect(toggled?.id, group.id);
  });

  testWidgets('selected rows show count-aware header and send CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        groups: [makeGroup(id: 'friends', name: 'Friends')],
        selectedContactPeerIds: const {'alice'},
        selectedGroupIds: const {'friends'},
        onSend: () {},
      ),
    );

    expect(find.text('Share with (2)'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('send CTA stays hidden until at least one target is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        onSend: () {},
      ),
    );

    expect(find.text('Send'), findsNothing);
  });

  testWidgets('send CTA invokes onSend when tapped', (tester) async {
    var sendCount = 0;

    await tester.pumpWidget(
      buildScreen(
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        selectedContactPeerIds: const {'alice'},
        onSend: () => sendCount++,
      ),
    );

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sendCount, 1);
  });

  testWidgets('sending state disables actions and shows progress copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        selectedContactPeerIds: const {'alice'},
        isSending: true,
        onToggleContact: (_) {},
        onSend: () {},
        onCancel: () {},
      ),
    );

    expect(find.text('Sending...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('share-contact-alice')))
          .enabled,
      isFalse,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<GestureDetector>(
            find.ancestor(
              of: find.text('Sending...'),
              matching: find.byType(GestureDetector),
            ),
          )
          .onTap,
      isNull,
    );
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

  testWidgets('shows loading indicator when isLoading is true', (tester) async {
    await tester.pumpWidget(buildScreen(isLoading: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No contacts or groups yet'), findsNothing);
  });

  testWidgets(
    'shows populated results even if isLoading remains true after data arrives',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(
          isLoading: true,
          contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('daylight lagoon keeps share picker content readable', (
    tester,
  ) async {
    final captionController = TextEditingController(text: 'Caption text');
    addTearDown(captionController.dispose);

    await tester.pumpWidget(
      buildScreen(
        sharedText: 'Hello مرحبا from share',
        captionController: captionController,
        contacts: [makeContact(peerId: 'alice', username: 'Alice')],
        groups: [makeGroup(id: 'friends', name: 'Friends')],
        selectedContactPeerIds: const {'alice'},
        onSend: () {},
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );
    await tester.pump();

    const colors = BackgroundReadableColors.representativeLight;
    final header = tester.widget<Text>(find.text('Share with (1)'));
    expectTextContrast(header.style!.color!, colors.surfaceBase);

    final captionLabel = tester.widget<Text>(
      find.byKey(const ValueKey('share-caption-label')),
    );
    expectTextContrast(captionLabel.style!.color!, colors.surfaceBase);

    final contact = tester.widget<Text>(find.text('Alice'));
    expectTextContrast(contact.style!.color!, colors.surfaceBase);

    final group = tester.widget<Text>(find.text('Friends'));
    expectTextContrast(group.style!.color!, colors.surfaceBase);
  });
}

Text _previewText(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == text,
    description: 'Text("$text")',
  );
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder);
}
