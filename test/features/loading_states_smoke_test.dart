import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/qr_code_section.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';

void main() {
  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Loading states smoke', () {
    testWidgets('Feed loading skeleton renders without overflow', (
      tester,
    ) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedScreen(
              username: 'Alice',
              feedItems: const <FeedItem>[],
              feedLoaded: false,
              onSwitchView: (_) {},
              activeTab: 'feed',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Group list loading renders without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupListScreen(
              groups: [],
              isLoading: true,
              onGroupTap: (_) {},
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Share picker loading renders without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareTargetPickerScreen(
              contacts: [],
              groups: [],
              isLoading: true,
              onContactSelected: (_) {},
              onGroupSelected: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('QR shimmer renders and animates without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: QRCodeSection(qrData: null))),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Compose area renders with isSending true without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ComposeArea(isSending: true, onSend: (_) {})),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Identity choice renders with null callbacks without overflow',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IdentityChoiceScreen(onNewHere: null, onLoadMyKey: null),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1300));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Share picker empty state renders without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareTargetPickerScreen(
              contacts: [],
              groups: [],
              isLoading: false,
              onContactSelected: (_) {},
              onGroupSelected: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('No contacts or groups yet'), findsOneWidget);
    });
  });
}
