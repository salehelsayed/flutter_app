import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitalAvatar', () {
    testWidgets('renders UserAvatar with given size', (tester) async {
      await tester.pumpWidget(wrap(const OrbitalAvatar(
        peerId: 'peer-123',
        size: 38,
        globalIndex: 0,
      )));
      // globalIndex 0 -> 0ms delay, pump past it + animation
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('renders ClipOval', (tester) async {
      await tester.pumpWidget(wrap(const OrbitalAvatar(
        peerId: 'peer-123',
        size: 38,
        globalIndex: 0,
      )));
      // Pump past the delayed timer to prevent pending timer errors.
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsWidgets);
    });

    testWidgets('renders circular border container', (tester) async {
      await tester.pumpWidget(wrap(const OrbitalAvatar(
        peerId: 'peer-123',
        size: 38,
        globalIndex: 0,
      )));
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bordered = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle && d.border != null;
      });
      expect(bordered, isNotEmpty);
    });

    testWidgets('applies custom borderWidth and borderColor', (tester) async {
      await tester.pumpWidget(wrap(const OrbitalAvatar(
        peerId: 'peer-123',
        size: 30,
        globalIndex: 0,
        borderWidth: 2.0,
        borderColor: Color(0xFF00FF00),
      )));
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bordered = containers.where((c) {
        final d = c.decoration;
        if (d is BoxDecoration && d.border is Border) {
          final border = d.border as Border;
          return border.top.width == 2.0 && border.top.color == const Color(0xFF00FF00);
        }
        return false;
      });
      expect(bordered, isNotEmpty);
    });
  });
}
