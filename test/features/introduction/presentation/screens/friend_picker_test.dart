import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

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
    BackgroundReadableColors? readableColors,
    Locale locale = const Locale('en'),
    TextScaler? textScaler,
  }) {
    final screen = SizedBox(
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
    );

    return MaterialApp(
      locale: locale,
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: readableColors == null
            ? screen
            : Theme(
                data: ThemeData(extensions: [readableColors]),
                child: screen,
              ),
      ),
    );
  }

  testWidgets('UI25 introduction refresh cannot select the replacement friend', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(buildSubject(onToggleFriend: selected.add));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Alice')));
    await tester.pumpWidget(buildSubject(
      availableFriends: [friends[1], friends[0], friends[2]], onToggleFriend: selected.add,
    ));
    await gesture.up();
    await tester.pump();
    expect(selected, isEmpty);
    await tester.tap(find.text('Bob'));
    expect(selected, ['peer-B']);
  });

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
    expect(tester.getSize(find.byKey(const ValueKey('peer-A'))).height, 60);
  });

  for (final (locale, direction, friendName) in const [
    (Locale('en'), TextDirection.ltr, 'Alexandra Riverside'),
    (Locale('ar'), TextDirection.rtl, 'عبد الرحمن الطويل'),
  ]) {
    for (final scale in [1.0, 3.0]) {
      testWidgets(
        'BL-110 friend and Introduce labels fit at ${scale}x ${direction.name}',
        (tester) async {
          const deadline = Duration(seconds: 3);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.reset);
          final toggles = <String>[];
          var introductions = 0;
          await tester
              .pumpWidget(
                buildSubject(
                  locale: locale,
                  textScaler: TextScaler.linear(scale),
                  availableFriends: [makeContact('peer-long', friendName)],
                  selectedPeerIds: {'peer-long'},
                  onToggleFriend: toggles.add,
                  onSend: () => introductions++,
                ),
              )
              .timeout(deadline);

          final context = tester.element(find.byType(FriendPickerScreen));
          expect(Directionality.of(context), direction);
          final introduce = AppLocalizations.of(context)!
              .picker_introduce_count(1);
          final row = find.byKey(const ValueKey('peer-long'));
          final button = find.byType(ElevatedButton);
          final clipped = <String>[];
          for (final (label, control) in [
            (friendName, row),
            (introduce, button),
          ]) {
            final text = find.text(label);
            expect(text.hitTestable(), findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            final visible = tester
                .getRect(text)
                .intersect(tester.getRect(control))
                .shift(-paragraph.localToGlobal(Offset.zero));
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            );
            if (boxes.isEmpty ||
                boxes.any(
                  (box) =>
                      box.top < visible.top - 1 ||
                      box.bottom > visible.bottom + 1,
                )) {
              clipped.add(label);
            }
          }
          expect(tester.takeException(), isNull);
          expect(
            clipped,
            isEmpty,
            reason: 'All painted glyphs fit vertically in their controls',
          );
          await tester.tap(find.text(friendName)).timeout(deadline);
          await tester.tap(find.text(introduce)).timeout(deadline);
          expect(toggles, ['peer-long']);
          expect(introductions, 1);
        },
      );
    }
  }

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

  testWidgets('daylight readable roles are applied across picker content', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(
      buildSubject(selectedPeerIds: {'peer-A'}, readableColors: colors),
    );

    final surfaceContainer = tester.widget<Container>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    colors.surfaceBase,
          )
          .first,
    );
    final surfaceDecoration = surfaceContainer.decoration as BoxDecoration;
    expect(surfaceDecoration.color, colors.surfaceBase);

    final headerColor = tester
        .widget<Text>(find.text('Introduce to Eve'))
        .style
        ?.color;
    final friendColor = tester.widget<Text>(find.text('Alice')).style?.color;
    final hintColor = tester
        .widget<TextField>(find.byType(TextField))
        .decoration
        ?.hintStyle
        ?.color;

    expect(headerColor, colors.textPrimary);
    expect(friendColor, colors.textPrimary);
    expect(hintColor, colors.placeholderText);
    expectTextContrast(headerColor!, colors.surfaceBase);
    expectTextContrast(friendColor!, colors.surfaceBase);
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
