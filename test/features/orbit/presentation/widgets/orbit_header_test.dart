import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitHeader', () {
    testWidgets('renders UserAvatar widget', (tester) async {
      await tester.pumpWidget(wrap(const OrbitHeader(userPeerId: 'peer123')));
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('works with null userPeerId', (tester) async {
      await tester.pumpWidget(wrap(const OrbitHeader(userPeerId: null)));
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('works with null avatarBytes', (tester) async {
      await tester.pumpWidget(wrap(const OrbitHeader(
        userPeerId: 'peer123',
        avatarBytes: null,
      )));
      expect(find.byType(UserAvatar), findsOneWidget);
    });
  });
}
