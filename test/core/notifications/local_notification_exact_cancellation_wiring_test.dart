import 'dart:io';

import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    setGroupExitIntentAccessSinks(
      forGroup: (_) async => null,
      all: () async => const <GroupExitIntent>[],
    );
  });
  tearDown(setGroupExitIntentAccessSinks);

  test(
    'main keeps local opens exact while validated remote opens retain clear-all',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final initialLocal = _between(
        source,
        'Future<void> _handleInitialLocalNotificationLaunch() async {',
        'Future<void> _onNotificationTap(String payload) async {',
      );
      final warmLocal = _between(
        source,
        'Future<void> _onNotificationTap(String payload) async {',
        'Future<NotificationOpenRouteDisposition> _handleNotificationRouteTarget(',
      );
      final remote = _between(
        source,
        'Future<void> _routeRemoteNotificationOpen(Map<String, dynamic> data) async {',
        'Future<T> _withContactRequestPresentationSuppressed<T>({',
      );

      expect(
        initialLocal,
        contains('routeAppRootInitialLocalNotificationOpen('),
      );
      expect(initialLocal, isNot(contains('clearDeliveredNotifications')));
      expect(initialLocal, isNot(contains('cancelAll')));
      expect(warmLocal, contains('routeAppRootLocalNotificationTap('));
      expect(warmLocal, isNot(contains('clearDeliveredNotifications')));
      expect(warmLocal, isNot(contains('cancelAll')));

      expect(remote, contains('routeAppRootRemoteNotificationOpenWithResult('));
      expect(remote, isNot(contains('onBeforeOpen:')));
      expect(
        remote,
        contains('widget.notificationService.clearDeliveredNotifications'),
      );
    },
  );

  test('cold warm and remote opens build one immutable pair after validation', () {
    final source = File('lib/main.dart').readAsStringSync();
    final initialLocal = _between(
      source,
      'Future<void> _handleInitialLocalNotificationLaunch() async {',
      'Future<void> _onNotificationTap(String payload) async {',
    );
    final warmLocal = _between(
      source,
      'Future<void> _onNotificationTap(String payload) async {',
      'Future<NotificationOpenRouteCompletion> _dispatchPreparedNotificationRoute(',
    );
    final remote = _between(
      source,
      'Future<void> _routeRemoteNotificationOpen(Map<String, dynamic> data) async {',
      'Future<T> _withContactRequestPresentationSuppressed<T>({',
    );

    _expectPairedContextWiring(
      initialLocal,
      routeCall: 'routeAppRootInitialLocalNotificationOpen(',
    );
    _expectPairedContextWiring(
      warmLocal,
      routeCall: 'routeAppRootLocalNotificationTap(',
    );
    _expectEarlyRemoteContextWiring(remote);
  });

  test(
    'tap timing state is coordinator-owned and never independently writable',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final state = _between(
        source,
        'class _MyAppState extends State<MyApp> with WidgetsBindingObserver {',
        'bool _startupHomeReady = false;',
      );

      expect(
        state,
        contains(
          'final NotificationOpenRouteCoordinator _notificationRouteCoordinator =',
        ),
      );
      expect(state, contains('_notificationRouteCoordinator.activeTappedAt'));
      expect(
        RegExp(r'_notificationTappedAt\s*=(?![=>])').hasMatch(source),
        isFalse,
      );
      expect(source, isNot(contains('_notificationTapContextGeneration')));
      expect(source, isNot(contains('_deferredNotificationRouteTarget')));
    },
  );

  test(
    'deferred flush keeps ownership, retries once, and catches internally',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final flush = _between(
        source,
        'Future<void> _flushDeferredNotificationRouteTarget() async {',
        'void _onStartupHomeReady()',
      );
      final pendingCheck = flush.indexOf(
        '_notificationRouteCoordinator.deferred == null',
      );
      final attempt = flush.indexOf(
        '_notificationRouteCoordinator.runDeferredAttempt(',
      );

      expect(pendingCheck, greaterThan(0));
      expect(attempt, greaterThan(pendingCheck));
      expect(
        flush,
        contains('maxAttempts: _maxDeferredNotificationRouteAttempts'),
      );
      expect(flush, contains('onRouteContext: _handleNotificationRouteTarget'));
      expect(flush, contains('NotificationOpenDeferredAttemptStatus.retry'));
      expect(flush, contains("'willRetry': true"));
      expect(flush, contains("'willRetry': false"));
      expect(
        flush,
        contains('_deferredNotificationRouteRetryScheduler.schedule('),
      );
      expect(flush, contains('ownerOrdinal: retryContext.ordinal'));
      expect(
        flush,
        contains(
          '_notificationRouteCoordinator.deferred?.ordinal !=\n                      retryContext.ordinal',
        ),
      );
      expect(flush, contains('.cancelIfOwnedBy('));
      expect(flush, contains('NOTIFICATION_DEFERRED_ROUTE_FLUSH_ERROR'));
      expect(flush, isNot(contains('takeDeferred()')));
      expect(flush, isNot(contains('_deferredNotificationRouteRetryTimer')));
    },
  );

  test('validated paired context reaches intro direct and group conversations', () {
    final source = File('lib/main.dart').readAsStringSync();
    final notificationRouter = _between(
      source,
      'Future<NotificationOpenRouteDisposition> _handleNotificationRouteTarget(',
      'void _revealPostsSurface()',
    );
    final groupRoute = _between(
      notificationRouter,
      'case NotificationRouteTargetKind.group:',
      'case NotificationRouteTargetKind.conversation:',
    );
    final directRoute = _between(
      notificationRouter,
      'case NotificationRouteTargetKind.conversation:',
      'case NotificationRouteTargetKind.post:',
    );

    expect(
      notificationRouter,
      contains('_notificationRouteCoordinator.defer(context)'),
    );
    expect(
      notificationRouter,
      contains('notificationTappedAt: context.tappedAt'),
    );
    expect(
      RegExp(
        r'notificationTappedAt: context\.tappedAt',
      ).allMatches(notificationRouter),
      hasLength(greaterThanOrEqualTo(3)),
    );
    expect(groupRoute, contains('GroupConversationWired('));
    expect(groupRoute, contains('notificationTappedAt: context.tappedAt'));
    expect(directRoute, contains('_openConversationForContact('));
    expect(directRoute, contains('notificationTappedAt: context.tappedAt'));
    expect(directRoute, contains('if (contact == null)'));
    expect(
      directRoute,
      contains(
        "throw StateError(\n            'Notification conversation contact is not available yet.',",
      ),
    );
    expect(
      directRoute,
      isNot(
        contains(
          'if (contact == null) {\n          return NotificationOpenRouteDisposition.routed;',
        ),
      ),
    );
  });

  test(
    'missing group is routed only by invite redirect or mounted feedback fallback',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final notificationRouter = _between(
        source,
        'Future<NotificationOpenRouteDisposition> _handleNotificationRouteTarget(',
        'void _revealPostsSurface()',
      );
      final groupRoute = _between(
        notificationRouter,
        'case NotificationRouteTargetKind.group:',
        'case NotificationRouteTargetKind.conversation:',
      );
      final pendingInvite = groupRoute.indexOf(
        'if (resolution.hasPendingInvite) {',
      );
      final pendingInviteHandled = groupRoute.indexOf(
        'return NotificationOpenRouteDisposition.routed;',
        pendingInvite,
      );
      final unmounted = groupRoute.indexOf(
        'if (!navigator.mounted) {',
        pendingInviteHandled,
      );
      final nonRoutedFailure = groupRoute.indexOf(
        "throw StateError(\n              'Group notification fallback navigator is not available.',",
        unmounted,
      );
      final visibleFeedback = groupRoute.indexOf(
        'showGroupMissingNotificationFeedback(',
        nonRoutedFailure,
      );
      final feedbackHandled = groupRoute.indexOf(
        'return NotificationOpenRouteDisposition.routed;',
        visibleFeedback,
      );

      expect(pendingInvite, isNonNegative);
      expect(pendingInviteHandled, greaterThan(pendingInvite));
      expect(unmounted, greaterThan(pendingInviteHandled));
      expect(nonRoutedFailure, greaterThan(unmounted));
      expect(visibleFeedback, greaterThan(nonRoutedFailure));
      expect(feedbackHandled, greaterThan(visibleFeedback));
    },
  );

  test('prepared dispatch validates identity and enters coordinator', () {
    final source = File('lib/main.dart').readAsStringSync();
    final dispatch = _between(
      source,
      'Future<NotificationOpenRouteCompletion> _dispatchPreparedNotificationRoute(',
      'Future<NotificationOpenRouteDispatch> _dispatchNotificationRouteContext(',
    );

    expect(dispatch, contains('preparedContext == null'));
    expect(
      dispatch,
      contains('!identical(preparedContext.routeTarget, routeTarget)'),
    );
    expect(
      dispatch,
      contains('await _dispatchNotificationRouteContext(preparedContext)'),
    );
    expect(dispatch, contains('return dispatch.completion'));
  });

  test(
    'startup initial remote open carries one pair through prepare and route',
    () {
      final source = File(
        'lib/features/identity/presentation/startup_router.dart',
      ).readAsStringSync();
      final initialRemote = _between(
        source,
        'Future<void> _handleInitialPushOpen() async {',
        'Future<void> _withContactRequestPresentationSuppressed({',
      );
      final slot = initialRemote.indexOf(
        'NotificationOpenRouteContext? preparedContext;',
      );
      final beforeTarget = initialRemote.indexOf(
        'onBeforeRouteTarget: (resolvedRouteTarget) async {',
      );
      final factory = initialRemote.indexOf(
        'final createContext = widget.createNotificationRouteContext;',
        beforeTarget,
      );
      final create = initialRemote.indexOf(
        'preparedContext = createContext(resolvedRouteTarget);',
        factory,
      );
      final prepare = initialRemote.indexOf(
        'await _prepareNotificationRouteTarget(resolvedRouteTarget);',
        create,
      );
      final route = initialRemote.indexOf(
        'onRouteTarget: (resolvedRouteTarget) async {',
        prepare,
      );
      final identityCheck = initialRemote.indexOf(
        '!identical(context.routeTarget, resolvedRouteTarget)',
        route,
      );
      final dispatch = initialRemote.indexOf(
        'await widget.onNotificationRouteContext!(context);',
        identityCheck,
      );

      expect(slot, isNonNegative);
      expect(beforeTarget, greaterThan(slot));
      expect(factory, greaterThan(beforeTarget));
      expect(create, greaterThan(factory));
      expect(prepare, greaterThan(create));
      expect(route, greaterThan(prepare));
      expect(identityCheck, greaterThan(route));
      expect(dispatch, greaterThan(identityCheck));
    },
  );

  test('startup initial remote begins then observes deferred completion', () {
    final source = File('lib/main.dart').readAsStringSync();
    final begin = _between(
      source,
      'Future<void> _beginStartupNotificationRouteContext(',
      'Future<void> _observeNotificationRouteCompletion(',
    );
    final build = _between(
      source,
      'home: StartupRouter(',
      'debugShowCheckedModeBanner: false,',
    );

    expect(begin, contains('await _dispatchNotificationRouteContext(context)'));
    expect(begin, contains('unawaited('));
    expect(begin, contains('_observeNotificationRouteCompletion('));
    expect(
      build,
      contains(
        'createNotificationRouteContext: _createNotificationOpenRouteContext',
      ),
    );
    expect(
      build,
      contains(
        'onNotificationRouteContext: _beginStartupNotificationRouteContext',
      ),
    );
  });

  test('remote dedupe commits only from actual route completion', () {
    final source = File('lib/main.dart').readAsStringSync();
    final remote = _between(
      source,
      'Future<void> _routeRemoteNotificationOpen(Map<String, dynamic> data) async {',
      'Future<T> _withContactRequestPresentationSuppressed<T>({',
    );

    expect(
      remote,
      contains('NotificationOpenRouteCompletion? routeCompletion'),
    );
    expect(remote, contains('routeCompletion = await'));
    expect(remote, contains('didNotificationOpenRouteSucceed('));
    expect(remote, contains('routeTargetResolved: routeTargetResolved'));
    expect(remote, contains('completion: routeCompletion'));
    expect(
      remote,
      contains(
        '_remoteNotificationOpenDedupeGate.finish(data, success: routeSucceeded)',
      ),
    );
    expect(remote, contains('REMOTE_NOTIFICATION_ROUTE_ERROR'));
  });
}

void _expectPairedContextWiring(String source, {required String routeCall}) {
  final localSlot = source.indexOf(
    'NotificationOpenRouteContext? preparedContext;',
  );
  final route = source.indexOf(routeCall);
  final beforeTarget = source.indexOf(
    'onBeforeRouteTarget: (target) async {',
    route,
  );
  final create = source.indexOf(
    'preparedContext = _createNotificationOpenRouteContext(target);',
    beforeTarget,
  );
  final prepare = source.indexOf(
    'await _prepareNotificationRouteTarget(target);',
    create,
  );
  final onRoute = source.indexOf('onRouteTarget: (target) async {', prepare);
  final dispatch = source.indexOf(
    'await _dispatchPreparedNotificationRoute(',
    onRoute,
  );

  expect(localSlot, isNonNegative);
  expect(route, greaterThan(localSlot));
  expect(beforeTarget, greaterThan(route));
  expect(create, greaterThan(beforeTarget));
  expect(prepare, greaterThan(create));
  expect(onRoute, greaterThan(prepare));
  expect(dispatch, greaterThan(onRoute));
  expect(
    RegExp(r'_notificationTappedAt\s*=(?![=>])').hasMatch(source),
    isFalse,
  );
}

void _expectEarlyRemoteContextWiring(String source) {
  final slot = source.indexOf('NotificationOpenRouteContext? preparedContext;');
  final validate = source.indexOf(
    'NotificationRouteTarget.fromRemoteMessageData(data)',
    slot,
  );
  final create = source.indexOf(
    '_createNotificationOpenRouteContext(routeTarget)',
    validate,
  );
  final recentAnnouncementIo = source.indexOf(
    'await markRemoteNotificationOpenAsRecentAnnouncement(',
    create,
  );
  final route = source.indexOf(
    'routeAppRootRemoteNotificationOpenWithResult(',
    recentAnnouncementIo,
  );
  final prevalidated = source.indexOf(
    'prevalidatedRouteTarget: preparedContext?.routeTarget',
    route,
  );
  final beforeTarget = source.indexOf(
    'onBeforeRouteTarget: (target) async {',
    prevalidated,
  );
  final clear = source.indexOf(
    'await widget.notificationService.clearDeliveredNotifications();',
    beforeTarget,
  );
  final prepare = source.indexOf(
    'await _prepareNotificationRouteTarget(context.routeTarget);',
    clear,
  );
  final onRoute = source.indexOf('onRouteTarget: (target) async {', prepare);
  final dispatch = source.indexOf(
    'await _dispatchPreparedNotificationRoute(',
    onRoute,
  );

  expect(slot, isNonNegative);
  expect(validate, greaterThan(slot));
  expect(create, greaterThan(validate));
  expect(recentAnnouncementIo, greaterThan(create));
  expect(route, greaterThan(recentAnnouncementIo));
  expect(prevalidated, greaterThan(route));
  expect(beforeTarget, greaterThan(prevalidated));
  expect(clear, greaterThan(beforeTarget));
  expect(prepare, greaterThan(clear));
  expect(onRoute, greaterThan(prepare));
  expect(dispatch, greaterThan(onRoute));
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: 'missing start marker: $startMarker');
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, greaterThan(start), reason: 'missing end marker: $endMarker');
  return source.substring(start, end);
}
