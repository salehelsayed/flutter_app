import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<ContactModel> friends;

  ContactModel makeContact(String id, String name) => ContactModel(
    peerId: id,
    publicKey: 'pk-$id',
    rendezvous: '/ip4/127.0.0.1/tcp/0',
    username: name,
    signature: 'sig-$id',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    friends = [
      makeContact('peer-A', 'Alice'),
      makeContact('peer-B', 'Bob'),
      makeContact('peer-C', 'Charlie'),
    ];
  });

  Widget buildSubject({
    String recipientUsername = 'Eve',
    List<ContactModel>? availableFriends,
    Set<String> selectedPeerIds = const {},
    String searchQuery = '',
    bool isSending = false,
    int sendCompletedCount = 0,
    int sendTotalCount = 0,
    ValueChanged<String>? onSearchChanged,
    ValueChanged<String>? onToggleFriend,
    VoidCallback? onSend,
    VoidCallback? onClose,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: FriendPickerScreen(
            recipientUsername: recipientUsername,
            availableFriends: availableFriends ?? friends,
            selectedPeerIds: selectedPeerIds,
            searchQuery: searchQuery,
            isSending: isSending,
            sendCompletedCount: sendCompletedCount,
            sendTotalCount: sendTotalCount,
            onSearchChanged: onSearchChanged ?? (_) {},
            onToggleFriend: onToggleFriend ?? (_) {},
            onSend: onSend ?? () {},
            onClose: onClose ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('header shows "Introduce to [username]"', (tester) async {
    await tester.pumpWidget(buildSubject(recipientUsername: 'Eve'));
    expect(find.text('Introduce to Eve'), findsOneWidget);
  });

  testWidgets('displays all available friends', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.shrinkWrap, isFalse);
    expect(listView.itemExtent, 60);
  });

  testWidgets('search filters list by name', (tester) async {
    await tester.pumpWidget(buildSubject(searchQuery: 'Ali'));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Charlie'), findsNothing);
  });

  testWidgets('empty state shown when no friends match search', (tester) async {
    await tester.pumpWidget(buildSubject(searchQuery: 'xyz'));
    expect(find.textContaining('No friends matching'), findsOneWidget);
  });

  testWidgets('empty state when no available friends', (tester) async {
    await tester.pumpWidget(buildSubject(availableFriends: []));
    expect(find.text('No friends available to introduce'), findsOneWidget);
  });

  testWidgets('selecting a friend shows check icon', (tester) async {
    await tester.pumpWidget(buildSubject(selectedPeerIds: {'peer-A'}));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('deselecting shows empty circle', (tester) async {
    await tester.pumpWidget(buildSubject(selectedPeerIds: {}));
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('"Introduce (N)" button shows correct count', (tester) async {
    await tester.pumpWidget(
      buildSubject(selectedPeerIds: {'peer-A', 'peer-B'}),
    );
    expect(find.text('Introduce (2)'), findsOneWidget);
  });

  testWidgets('button shows "Introduce" when 0 selected', (tester) async {
    await tester.pumpWidget(buildSubject(selectedPeerIds: {}));
    expect(find.text('Introduce'), findsOneWidget);
  });

  testWidgets('button is disabled when 0 selected', (tester) async {
    await tester.pumpWidget(buildSubject(selectedPeerIds: {}));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('button is enabled when friends selected', (tester) async {
    await tester.pumpWidget(buildSubject(selectedPeerIds: {'peer-A'}));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('sending progress is shown while send is in flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        selectedPeerIds: {'peer-A', 'peer-B'},
        isSending: true,
        sendCompletedCount: 1,
        sendTotalCount: 2,
      ),
    );

    expect(find.text('Sending 1 of 2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('button stays disabled while sending', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        selectedPeerIds: {'peer-A'},
        isSending: true,
        sendCompletedCount: 0,
        sendTotalCount: 1,
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping friend row triggers onToggleFriend', (tester) async {
    String? toggledPeerId;
    await tester.pumpWidget(
      buildSubject(onToggleFriend: (id) => toggledPeerId = id),
    );

    // Tap the first friend row (Alice).
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(toggledPeerId, 'peer-A');
  });

  testWidgets('onSend callback triggered', (tester) async {
    var sendCalled = false;
    await tester.pumpWidget(
      buildSubject(
        selectedPeerIds: {'peer-A'},
        onSend: () => sendCalled = true,
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(sendCalled, isTrue);
  });

  testWidgets('close button triggers onClose', (tester) async {
    var closeCalled = false;
    await tester.pumpWidget(buildSubject(onClose: () => closeCalled = true));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(closeCalled, isTrue);
  });

  testWidgets('multiple friends can be selected simultaneously', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(selectedPeerIds: {'peer-A', 'peer-B', 'peer-C'}),
    );
    expect(find.byIcon(Icons.check), findsNWidgets(3));
  });
}
