import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'TC-371-03 one root route owner clears covered chats and restores only the frontmost conversation',
    (tester) async {
      final bridge = _RoutePlatformBridge();
      final authority = AppVisibilityAuthority(platformBridge: bridge);
      final registry = AppVisibilityRouteRegistry(authority: authority);
      final observer = AppVisibilityRouteObserver();
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: <NavigatorObserver>[observer],
          builder: (context, child) => DirectPrivateMediaRouteObserverScope(
            observer: observer,
            appVisibilityRouteRegistry: registry,
            child: child!,
          ),
          home: const _BoundConversation(
            lane: AppVisibilityConversationLane.direct,
            value: 'peer-A',
            label: 'direct-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();
      expect(
        registry.isCurrentTopConversationValue(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-A',
        ),
        isTrue,
      );
      expect(bridge.snapshot.visibleConversationDigest, _directA.digest);

      final groupRoute = MaterialPageRoute<void>(
        builder: (_) => const _BoundConversation(
          lane: AppVisibilityConversationLane.group,
          value: 'group:team-1|message:m-7',
          label: 'group-b',
        ),
      );
      unawaited(navigatorKey.currentState!.push<void>(groupRoute));
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _groupB);
      expect(bridge.snapshot.visibleConversationDigest, _groupB.digest);

      final settingsRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('settings')),
      );
      unawaited(navigatorKey.currentState!.push<void>(settingsRoute));
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, isNull);
      expect(bridge.snapshot.visibleConversationDigest, isNull);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _groupB);
      expect(bridge.snapshot.visibleConversationDigest, _groupB.digest);

      final replacementRoute = MaterialPageRoute<void>(
        builder: (_) => const _BoundConversation(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-A',
          label: 'direct-a-replacement',
        ),
      );
      unawaited(
        navigatorKey.currentState!.pushReplacement<void, void>(
          replacementRoute,
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _directA);

      final newerGroupRoute = MaterialPageRoute<void>(
        builder: (_) => const _BoundConversation(
          lane: AppVisibilityConversationLane.group,
          value: 'group:team-1',
          label: 'group-b-newer',
        ),
      );
      unawaited(navigatorKey.currentState!.push<void>(newerGroupRoute));
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _groupB);

      // Disposing a covered older binding cannot clear its newer sibling.
      navigatorKey.currentState!.removeRoute(replacementRoute);
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _groupB);
      expect(bridge.snapshot.visibleConversationDigest, _groupB.digest);

      // Removing the top route restores the actual underlying route, not the
      // most recently disposed route.
      navigatorKey.currentState!.removeRoute(newerGroupRoute);
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _directA);
      expect(bridge.snapshot.visibleConversationDigest, _directA.digest);

      // Open-route dedupe remains a process-local top-route query while the
      // durable suppression lease is synchronously invalidated in background.
      authority.invalidateSynchronously();
      bridge.transition(AppVisibilityLifecycle.background);
      expect(registry.currentTopConversation, _directA);
      expect(await authority.maySuppress(_directA), isFalse);
      expect(
        registry.isCurrentTopConversation(_directA),
        isTrue,
        reason: 'top-route identity is deliberately independent of freshness',
      );

      bridge.transition(AppVisibilityLifecycle.foregroundActive);
      expect(await authority.synchronize(), isTrue);
      expect(await registry.republishCurrentTopConversation(), isTrue);
      expect(bridge.snapshot.visibleConversationDigest, _directA.digest);

      expect(bridge.readSideEffects, 0);
      expect(bridge.notificationCancellationSideEffects, 0);

      for (final path in <String>[
        'lib/features/conversation/presentation/screens/conversation_wired.dart',
        'lib/features/groups/presentation/screens/group_conversation_wired.dart',
        'lib/features/groups/presentation/screens/linked_group_conversation_wired.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          'AppVisibilityRouteBinding('.allMatches(source),
          hasLength(1),
          reason: path,
        );
        expect(
          source,
          contains('DirectPrivateMediaRouteObserverScope.maybeRegistryOf('),
          reason: path,
        );
      }

      registry.dispose();
      authority.dispose();
    },
  );
}

final AppVisibilityConversationIdentity _directA =
    AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: 'peer-A',
    )!;
final AppVisibilityConversationIdentity _groupB =
    AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:team-1',
    )!;

final class _BoundConversation extends StatelessWidget {
  const _BoundConversation({
    required this.lane,
    required this.value,
    required this.label,
  });

  final AppVisibilityConversationLane lane;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: lane,
      value: value,
    );
    final registry = DirectPrivateMediaRouteObserverScope.maybeRegistryOf(
      context,
    );
    return AppVisibilityRouteBinding(
      registry: registry!,
      identity: identity!,
      observer: DirectPrivateMediaRouteObserverScope.maybeOf(context),
      child: Scaffold(body: Text(label)),
    );
  }
}

final class _RoutePlatformBridge implements AppVisibilityPlatformBridge {
  AppVisibilitySnapshotV1 snapshot = const AppVisibilitySnapshotV1(
    schemaVersion: appVisibilitySnapshotSchemaVersion,
    revision: 1,
    lifecycleGeneration: 1,
    lifecycle: AppVisibilityLifecycle.foregroundActive,
    visibleConversationDigest: null,
    updatedMonotonicMs: 1000,
    bootSession: 'test:route-boot',
  );
  int nowMs = 1001;
  int readSideEffects = 0;
  int notificationCancellationSideEffects = 0;

  void transition(AppVisibilityLifecycle lifecycle) {
    nowMs++;
    snapshot = AppVisibilitySnapshotV1(
      schemaVersion: appVisibilitySnapshotSchemaVersion,
      revision: snapshot.revision + 1,
      lifecycleGeneration: snapshot.lifecycleGeneration + 1,
      lifecycle: lifecycle,
      visibleConversationDigest: null,
      updatedMonotonicMs: nowMs,
      bootSession: 'test:route-boot',
    );
  }

  @override
  Future<AppVisibilityPlatformRead?> readSnapshot() async =>
      AppVisibilityPlatformRead(
        snapshot: snapshot,
        currentMonotonicMs: nowMs,
        currentBootSession: 'test:route-boot',
      );

  @override
  Future<AppVisibilityPlatformWrite?> publishVisibleConversation({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  }) async {
    if (snapshot.lifecycle != AppVisibilityLifecycle.foregroundActive ||
        lifecycleGeneration != snapshot.lifecycleGeneration) {
      return AppVisibilityPlatformWrite(
        committed: false,
        snapshot: snapshot,
        currentMonotonicMs: nowMs,
        currentBootSession: 'test:route-boot',
      );
    }
    nowMs++;
    snapshot = AppVisibilitySnapshotV1(
      schemaVersion: appVisibilitySnapshotSchemaVersion,
      revision: snapshot.revision + 1,
      lifecycleGeneration: snapshot.lifecycleGeneration,
      lifecycle: snapshot.lifecycle,
      visibleConversationDigest: visibleConversationDigest,
      updatedMonotonicMs: nowMs,
      bootSession: snapshot.bootSession,
    );
    return AppVisibilityPlatformWrite(
      committed: true,
      snapshot: snapshot,
      currentMonotonicMs: nowMs,
      currentBootSession: 'test:route-boot',
    );
  }
}
