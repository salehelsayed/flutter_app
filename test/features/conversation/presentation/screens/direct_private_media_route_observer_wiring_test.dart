import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production registers and scopes one stable private-media observer', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final observerSource = File(
      'lib/features/conversation/presentation/navigation/'
      'direct_private_media_route_observer.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r'navigatorObservers:\s*\[directPrivateMediaRouteObserver\]',
      ).allMatches(mainSource),
      hasLength(1),
    );
    expect(
      RegExp(
        r'DirectPrivateMediaRouteObserverScope\(\s*'
        r'observer:\s*directPrivateMediaRouteObserver,',
      ).allMatches(mainSource),
      hasLength(1),
    );
    expect(
      RegExp(
        r'final RouteObserver<ModalRoute<void>> '
        r'directPrivateMediaRouteObserver',
      ).allMatches(observerSource),
      hasLength(1),
    );

    final productionCallSites = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('builder: (_) => ConversationWired(')) {
        productionCallSites.add(entity.path);
      }
    }
    expect(
      productionCallSites,
      containsAll(<String>[
        'lib/main.dart',
        'lib/features/feed/presentation/screens/feed_wired.dart',
        'lib/features/home/presentation/screens/first_time_experience_wired.dart',
        'lib/features/orbit/presentation/screens/orbit_wired.dart',
        'lib/features/posts/presentation/screens/posts_wired.dart',
      ]),
    );
    // Every call site uses the one root-scoped observer; there is no optional
    // constructor observer that an entry path can accidentally omit.
    expect(
      File(
        'lib/features/conversation/presentation/screens/conversation_wired.dart',
      ).readAsStringSync(),
      isNot(contains('this.privateMediaRouteObserver')),
    );
  });
}
