import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unmarked dialog and bottom sheet atomically retain their exact covered conversation',
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

      unawaited(
        showDialog<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('chat-dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      expect(registry.currentTopConversation, _directA);
      expect(await authority.maySuppress(_directA), isTrue);
      expect(
        bridge.publishedConversationDigests,
        isNot(contains(null)),
        reason: 'the popup handoff must never publish a transient null',
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await registry.settle();

      unawaited(
        navigatorKey.currentState!.push<void>(
          AppVisibilityInheritedConversationRoute<void>(
            identity: _directA,
            builder: (_) => const Scaffold(body: Text('inherited-media')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      unawaited(
        showModalBottomSheet<void>(
          context: navigatorKey.currentContext!,
          builder: (_) =>
              const SizedBox(height: 120, child: Text('chat-bottom-sheet')),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      expect(registry.currentTopConversation, _directA);
      expect(await authority.maySuppress(_directA), isTrue);
      expect(
        bridge.publishedConversationDigests,
        isNot(contains(null)),
        reason:
            'a popup over an inherited chat route must retain the same identity atomically',
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await registry.settle();
      expect(registry.currentTopConversation, _directA);
      expect(bridge.publishedConversationDigests, isNot(contains(null)));

      registry.dispose();
      authority.dispose();
    },
  );

  testWidgets('popup over a non-conversation route remains fail closed', (
    tester,
  ) async {
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
        home: const Scaffold(body: Text('settings')),
      ),
    );
    await tester.pumpAndSettle();
    await registry.settle();

    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('settings-dialog')),
      ),
    );
    await tester.pumpAndSettle();
    await registry.settle();

    expect(registry.currentTopConversation, isNull);
    expect(await authority.maySuppress(_directA), isFalse);
    expect(bridge.snapshot.visibleConversationDigest, isNull);

    registry.dispose();
    authority.dispose();
  });

  for (final testCase
      in <({AppVisibilityConversationLane lane, String value, String label})>[
        (
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-A',
          label: 'direct',
        ),
        (
          lane: AppVisibilityConversationLane.group,
          value: 'group:team-1',
          label: 'group',
        ),
      ]) {
    testWidgets(
      'active ${testCase.label} conversation remains visible while its full-screen media viewer is top',
      (tester) async {
        final bridge = _RoutePlatformBridge();
        final authority = AppVisibilityAuthority(platformBridge: bridge);
        final registry = AppVisibilityRouteRegistry(authority: authority);
        final observer = AppVisibilityRouteObserver();
        final navigatorKey = GlobalKey<NavigatorState>();
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: testCase.lane,
          value: testCase.value,
        )!;

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: <NavigatorObserver>[observer],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => DirectPrivateMediaRouteObserverScope(
              observer: observer,
              appVisibilityRouteRegistry: registry,
              child: child!,
            ),
            home: _BoundConversation(
              lane: testCase.lane,
              value: testCase.value,
              label: '${testCase.label}-conversation',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await registry.settle();
        expect(await authority.maySuppress(identity), isTrue);

        unawaited(
          navigatorKey.currentState!.push<void>(
            AppVisibilityInheritedConversationRoute(
              identity: identity,
              builder: (_) => const FullScreenTypedMediaViewer(
                items: <MediaViewerItem>[
                  MediaViewerItem(
                    attachmentId: 'attachment-1',
                    messageId: 'message-1',
                    kind: MediaViewerKind.image,
                    mime: 'image/jpeg',
                    localPath: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await registry.settle();

        expect(
          registry.currentTopConversation,
          identity,
          reason:
              'the media viewer is still part of the conversation notification context',
        );
        expect(
          await authority.maySuppress(identity),
          isTrue,
          reason:
              'a same-chat message must remain in-chat/no-native-notification',
        );
        expect(
          bridge.publishedConversationDigests,
          isNot(contains(null)),
          reason:
              'the route handoff must not create a notification-eligible transition window',
        );

        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        await registry.settle();
        expect(registry.currentTopConversation, identity);
        expect(bridge.publishedConversationDigests, isNot(contains(null)));

        registry.dispose();
        authority.dispose();
      },
    );
  }

  testWidgets(
    'inherited route cannot manufacture visibility for a different conversation',
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

      unawaited(
        navigatorKey.currentState!.push<void>(
          AppVisibilityInheritedConversationRoute<void>(
            identity: _groupB,
            builder: (_) => const Scaffold(body: Text('wrong-group-media')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      expect(registry.currentTopConversation, isNull);
      expect(await authority.maySuppress(_directA), isFalse);
      expect(await authority.maySuppress(_groupB), isFalse);
      expect(bridge.publishedConversationDigests.last, isNull);

      registry.dispose();
      authority.dispose();
    },
  );

  testWidgets(
    'inherited replacement is atomic only for the exact covered conversation',
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

      unawaited(
        navigatorKey.currentState!.push<void>(
          AppVisibilityInheritedConversationRoute<void>(
            identity: _directA,
            builder: (_) => const Scaffold(body: Text('direct-media-a')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();
      bridge.publishedConversationDigests.clear();

      unawaited(
        navigatorKey.currentState!.pushReplacement<void, void>(
          AppVisibilityInheritedConversationRoute<void>(
            identity: _directA,
            builder: (_) =>
                const Scaffold(body: Text('direct-media-a-replacement')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      expect(registry.currentTopConversation, _directA);
      expect(find.text('direct-media-a-replacement'), findsOneWidget);
      expect(
        bridge.publishedConversationDigests,
        isEmpty,
        reason: 'an exact replacement must hand off without publishing null',
      );

      unawaited(
        navigatorKey.currentState!.pushReplacement<void, void>(
          AppVisibilityInheritedConversationRoute<void>(
            identity: _groupB,
            builder: (_) =>
                const Scaffold(body: Text('mismatched-group-media')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await registry.settle();

      expect(registry.currentTopConversation, isNull);
      expect(find.text('mismatched-group-media'), findsOneWidget);
      expect(
        bridge.publishedConversationDigests,
        <String?>[null],
        reason:
            'a mismatched replacement must fail closed with one final clear',
      );
      expect(bridge.snapshot.visibleConversationDigest, isNull);

      registry.dispose();
      authority.dispose();
    },
  );

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

  testWidgets(
    'TC-393-02 exact activation cleanup is generation safe and read independent',
    (tester) async {
      final bridge = _RoutePlatformBridge();
      final authority = AppVisibilityAuthority(platformBridge: bridge);
      final generations = _HeldGenerationCancellation()
        ..put('peer-A', 'generation-a-1')
        ..put('peer-B', 'generation-b-1')
        ..holdNextLookup();
      final registry = AppVisibilityRouteRegistry(
        authority: authority,
        onExactConversationActivated: (identity) async {
          final metadata = await generations
              .lookupConversationNotificationContentMetadata(
                identity.normalizedValue,
              );
          final generation = metadata?.generation?.trim();
          if (generation == null || generation.isEmpty) return;
          await generations.cancelConversationNotificationGeneration(
            identity.normalizedValue,
            generation,
          );
        },
      );
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
          home: const Scaffold(body: Text('settings')),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => const _BoundConversation(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-A',
          label: 'direct-a',
        ),
      );
      unawaited(navigatorKey.currentState!.push<void>(route));
      await tester.pumpAndSettle();
      await generations.lookupCaptured.future;

      expect(
        registry.currentTopConversation,
        _directA,
        reason: 'top identity must be synchronous before cleanup awaits',
      );
      generations.put('peer-A', 'generation-a-2');
      generations.releaseLookup();
      await registry.settle();

      expect(generations.generationFor('peer-A'), 'generation-a-2');
      expect(generations.generationFor('peer-B'), 'generation-b-1');
      expect(generations.cancelledGenerations, isEmpty);

      bridge.transition(AppVisibilityLifecycle.background);
      authority.invalidateSynchronously();
      bridge.transition(AppVisibilityLifecycle.foregroundActive);
      expect(await authority.synchronize(), isTrue);
      generations.put('peer-A', 'generation-a-3');
      expect(await registry.republishCurrentTopConversation(), isTrue);
      await registry.settle();

      expect(generations.generationFor('peer-A'), isNull);
      expect(generations.cancelledGenerations, <String>['generation-a-3']);
      expect(bridge.readSideEffects, 0);

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
  final List<String?> publishedConversationDigests = <String?>[];

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
    publishedConversationDigests.add(visibleConversationDigest);
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

final class _HeldGenerationCancellation
    implements ConversationNotificationGenerationCancellation {
  final Map<String, ConversationNotificationContentMetadata> _metadata =
      <String, ConversationNotificationContentMetadata>{};
  final List<String> cancelledGenerations = <String>[];
  Completer<void> lookupCaptured = Completer<void>();
  Completer<void>? _lookupRelease;

  void put(String conversationKey, String generation) {
    _metadata[conversationKey] = ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.message,
      eventIdentity: 'event-$generation',
      generation: generation,
    );
  }

  String? generationFor(String conversationKey) =>
      _metadata[conversationKey]?.generation;

  void holdNextLookup() {
    lookupCaptured = Completer<void>();
    _lookupRelease = Completer<void>();
  }

  void releaseLookup() => _lookupRelease?.complete();

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async {
    final captured = _metadata[conversationKey];
    final release = _lookupRelease;
    if (release != null) {
      if (!lookupCaptured.isCompleted) lookupCaptured.complete();
      await release.future;
      if (identical(_lookupRelease, release)) _lookupRelease = null;
    }
    return captured;
  }

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (_metadata[conversationKey]?.generation != generation) return false;
    _metadata.remove(conversationKey);
    cancelledGenerations.add(generation);
    return true;
  }
}
