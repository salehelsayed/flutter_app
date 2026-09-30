import 'package:flutter/material.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'observer sees actual navigation; release stops only its own subscription',
    (tester) async {
      final observer = AppVisibilityRouteObserver();
      final key = GlobalKey<NavigatorState>();
      final first = <String>[];
      final second = <String>[];
      final release = observer.observeNavigation(
        (op, route) => first.add('$op:${route.settings.name}'),
      );
      final releaseSecond = observer.observeNavigation(
        (op, route) => second.add('$op:${route.settings.name}'),
      );
      addTearDown(releaseSecond);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          home: const Text('home'),
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'real-chat'),
          builder: (_) => const Text('chat'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      expect(first, ['push:/', 'push:real-chat']);
      release();
      release();
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(first, ['push:/', 'push:real-chat']);
      expect(second, ['push:/', 'push:real-chat', 'pop:real-chat']);
    },
  );

  testWidgets(
    'failing observation cannot prevent navigation or another observer',
    (tester) async {
      final observer = AppVisibilityRouteObserver();
      final key = GlobalKey<NavigatorState>();
      final observed = <String>[];
      observer.observeNavigation(
        (_, _) => throw StateError('broken diagnostics'),
      );
      observer.observeNavigation((op, _) => observed.add(op));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          home: const Text('home'),
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('real destination')),
      );
      await tester.pumpAndSettle();
      expect(find.text('real destination'), findsOneWidget);
      expect(observed, ['push', 'push']);
      expect(tester.takeException(), isNull);
    },
  );
}
