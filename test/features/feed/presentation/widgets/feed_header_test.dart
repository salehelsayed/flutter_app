import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../../../core/services/fake_p2p_service.dart';

/// 206 — the Feed header avatar was removed (the settings entry migrated to the
/// Orbit center avatar). The header keeps the username editor + connection dot.
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

  testWidgets('TC-206-13 header renders username + connection dot, NO avatar',
      (tester) async {
    final p2p = FakeP2PService();
    await tester.pumpWidget(
      wrap(FeedHeader(
        username: 'Alice',
        onUsernameChanged: (_) {},
        p2pService: p2p,
      )),
    );
    await tester.pump();

    // The avatar (and therefore any avatar-based settings entry) is gone.
    expect(find.byType(UserAvatar), findsNothing);
    // Username editor + connection dot are preserved.
    expect(find.byType(EditableUsernameWidget), findsOneWidget);
    expect(find.byType(ConnectionStatusIndicator), findsOneWidget);
  });

  testWidgets('TC-206-15 username editing still works', (tester) async {
    String? changed;
    await tester.pumpWidget(
      wrap(FeedHeader(
        username: 'Alice',
        onUsernameChanged: (value) => changed = value,
        p2pService: FakeP2PService(),
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

  testWidgets('TC-206-16 narrow width + long username, no overflow',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        FeedHeader(
          username: 'AVeryLongUsernameThatCouldOverflowTheHeader',
          onUsernameChanged: (_) {},
          p2pService: FakeP2PService(),
        ),
        width: 320,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
