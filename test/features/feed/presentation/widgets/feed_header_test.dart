import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// 211 — the connection dot migrated to the Orbit top-right chrome; the Feed
/// header keeps ONLY the username editor. 206 locks re-asserted: no avatar
/// (the settings entry lives on the Orbit center avatar), editing works.
void main() {
  Widget wrap(Widget child, {double width = 390}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  testWidgets('TC-211-24/26 header has NO connection dot, keeps 206 locks',
      (tester) async {
    // RED phase pumped `p2pService: FakeP2PService()` to prove the HEAD
    // header still mounted the dot; 211-E4 deleted the param, so the header
    // can no longer even accept a service (single layout path — TC-211-26).
    await tester.pumpWidget(
      wrap(FeedHeader(
        username: 'Alice',
        onUsernameChanged: (_) {},
      )),
    );
    await tester.pump();

    // 211: the dot now lives on Orbit — never on the Feed header.
    expect(find.byType(ConnectionStatusIndicator), findsNothing);
    // 206 locks preserved: no avatar, username editor present.
    expect(find.byType(UserAvatar), findsNothing);
    expect(find.byType(EditableUsernameWidget), findsOneWidget);
  });

  testWidgets('TC-211-25 username editing still works', (tester) async {
    String? changed;
    await tester.pumpWidget(
      wrap(FeedHeader(
        username: 'Alice',
        onUsernameChanged: (value) => changed = value,
      )),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changed, 'Bob');
  });

  testWidgets('TC-211-25 narrow width + long username, no overflow',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        FeedHeader(
          username: 'AVeryLongUsernameThatCouldOverflowTheHeader',
          onUsernameChanged: (_) {},
        ),
        width: 320,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
