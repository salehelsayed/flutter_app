import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];
  late Directory notificationIdDirectory;
  late String? launchPayload;
  late int launchNotificationId;

  FlutterNotificationService buildService({
    DurableConversationNotificationIdRegistry? registry,
    ConversationNotificationGenerationFactory? generationFactory,
    NotificationRecoverySettlementCallback? onNotificationUpdated,
    ConversationNotificationRecoverySettlementCallback? onConversationCleared,
    NotificationRecoverySettlementCallback? onAllNotificationsCleared,
  }) {
    final resolvedRegistry =
        registry ??
        DurableConversationNotificationIdRegistry(
          directory: notificationIdDirectory,
        );
    return FlutterNotificationService(
      notificationIdRegistryResolver: () async => resolvedRegistry,
      notificationGenerationFactory: generationFactory,
      onNotificationUpdated: onNotificationUpdated,
      onConversationCleared: onConversationCleared,
      onAllNotificationsCleared: onAllNotificationsCleared,
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    log.clear();
    launchPayload = 'peer-123';
    launchNotificationId = 7;
    notificationIdDirectory = Directory.systemTemp.createTempSync(
      'flutter-notification-service-id-registry-',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return <String, Object?>{
                'notificationLaunchedApp': true,
                'notificationResponse': <String, Object?>{
                  'notificationId': launchNotificationId,
                  'actionId': null,
                  'input': null,
                  'notificationResponseType':
                      NotificationResponseType.selectedNotification.index,
                  'payload': launchPayload,
                },
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSetFlowEventSink(null);
    if (notificationIdDirectory.existsSync()) {
      notificationIdDirectory.deleteSync(recursive: true);
    }
  });

  test('initialize wires the plugin, channel, and launch payload', () async {
    final service = buildService();

    await service.initialize();

    expect(log.map((call) => call.method).toList(), <String>[
      'initialize',
      'createNotificationChannel',
      'createNotificationChannel',
      'getNotificationAppLaunchDetails',
    ]);

    final initializeArgs = log[0].arguments as Map;
    expect(initializeArgs['defaultIcon'], '@mipmap/ic_launcher');

    final channelArgs = log[1].arguments as Map;
    expect(channelArgs['id'], mknoonMessagesChannelId);
    expect(channelArgs['name'], mknoonMessagesChannelName);
    expect(channelArgs['description'], mknoonMessagesChannelDescription);
    expect(channelArgs['importance'], Importance.high.value);
  });

  test(
    'consumeInitialPayload does not re-cancel an Android auto-cancelled card',
    () async {
      final service = buildService();

      await service.initialize();

      expect(await service.consumeInitialPayload(), 'peer-123');
      expect(await service.consumeInitialPayload(), isNull);

      expect(log.where((call) => call.method == 'cancel'), isEmpty);
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
    },
  );

  test(
    'onNotificationTap forwards payload without re-cancelling on Android',
    () async {
      final service = buildService();
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;

      await service.initialize();
      await _sendNotificationResponse(payload: 'peer-456');

      expect(tapped, <String>['peer-456']);
      expect(log.where((call) => call.method == 'cancel'), isEmpty);
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
    },
  );

  test(
    'onNotificationTap ignores empty payloads without Android re-cancellation',
    () async {
      final service = buildService();
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;

      await service.initialize();
      await _sendNotificationResponse(payload: null);
      await _sendNotificationResponse(payload: '');

      expect(tapped, isEmpty);
      expect(log.where((call) => call.method == 'cancel'), isEmpty);
    },
  );

  test('showNotification forwards title, body, payload, and details', () async {
    final service = buildService();

    await service.initialize();
    await service.showNotification(
      title: 'Hello',
      body: 'World',
      payload: 'payload-123',
    );

    final showCall = log.last;
    expect(showCall.method, 'show');

    final args = showCall.arguments as Map;
    expect(args['title'], 'Hello');
    expect(args['body'], 'World');
    expect(args['payload'], 'payload-123');
    expect(args['id'], isA<int>());

    final platformSpecifics = args['platformSpecifics'] as Map;
    expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
    expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
    expect(
      platformSpecifics['channelDescription'],
      mknoonMessagesChannelDescription,
    );
  });

  test(
    'showMessageNotification forwards conversation payload and details',
    () async {
      final service = buildService();

      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'peer-789',
        senderUsername: 'Alice',
        messageText: 'Ping',
      );

      final showCall = log.last;
      expect(showCall.method, 'show');

      final args = showCall.arguments as Map;
      expect(args['title'], 'Alice');
      expect(args['body'], 'Ping');
      expect(args['payload'], 'peer-789');
      expect(args['id'], isA<int>());

      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
      expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
    },
  );

  test('durable display diagnostics contain only fixed opaque codes', () async {
    final registry = DurableConversationNotificationIdRegistry(
      directory: notificationIdDirectory,
    );
    const binding =
        'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect(
      await LocalNotificationLedgerStore(
        directory: notificationIdDirectory,
      ).initializeOrRebind(currentOpaqueBinding: binding),
      isNotNull,
    );
    final service = buildService(registry: registry);
    await service.initialize();
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    const rawPeer = 'raw-peer-never-log-9TzH8J7K6L5M4N3P2Q1';
    const rawSender = 'raw-sender-never-log';
    const rawRoute = 'group:raw-group-never-log|message:raw-event-never-log';
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: rawPeer,
    )!;
    final context = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: binding,
      eventCorrelation: 'a' * 64,
      conversationDigest: identity.digest,
      producerKind: LocalNotificationProducerKind.directMessage,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: LocalNotificationPresentationOwner.mainApp,
      readFinalCanonicalDisposition: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    );

    final result = await service.showMessageNotificationWithDurableFinalEffect(
      contactPeerId: rawPeer,
      senderUsername: rawSender,
      messageText: 'raw body never log',
      payload: rawRoute,
      contentKind: ConversationNotificationContentKind.message,
      contentEventIdentity: context.eventCorrelation,
      durableEffectContext: context,
      finalVisibility: _BackgroundVisibility(),
      conversationIdentity: identity,
      publishNative: (showNative, authorize) async {
        if (!await authorize()) return false;
        await showNative(silent: false);
        return true;
      },
    );

    expect(
      result.disposition,
      DurableLocalNotificationEffectDisposition.osPosted,
    );
    final encodedEvents = jsonEncode(events);
    expect(encodedEvents, isNot(contains(rawPeer)));
    expect(encodedEvents, isNot(contains(rawSender)));
    expect(encodedEvents, isNot(contains(rawRoute)));
    expect(encodedEvents, isNot(contains('raw body never log')));
    final shown = events.singleWhere(
      (event) => event['event'] == 'NOTIFICATION_SHOWN',
    );
    expect((shown['details'] as Map)['durable'], isTrue);
  });

  test(
    'Android native boundary runs after registry retirement and directly wraps show',
    () async {
      final service = buildService();
      await service.initialize();
      final effects = <String>[];

      await service.showMessageNotificationAtNativeBoundary(
        contactPeerId: 'peer-native-boundary',
        senderUsername: 'Alice',
        messageText: 'Prepared first',
        contentKind: ConversationNotificationContentKind.message,
        contentEventIdentity: 'message-native-boundary',
        publishNative: (showNative) async {
          effects.add('boundary_entered');
          expect(log.where((call) => call.method == 'cancel'), hasLength(1));
          expect(log.where((call) => call.method == 'show'), isEmpty);
          await showNative(silent: true);
          effects.add('boundary_returned');
        },
      );

      expect(effects, <String>['boundary_entered', 'boundary_returned']);
      final notificationEffects = log
          .where((call) => call.method == 'cancel' || call.method == 'show')
          .map((call) => call.method)
          .toList(growable: false);
      expect(notificationEffects, <String>['cancel', 'show']);
      final show = log.singleWhere((call) => call.method == 'show');
      final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
      expect(specifics['playSound'], isFalse);
    },
  );

  test(
    'android conversation card carries canonical history and uncapped number',
    () async {
      final service = buildService();

      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'peer-history',
        senderUsername: 'Alice',
        messageText: 'newest',
        snapshot: ConversationNotificationSnapshot(
          historyLines: <String>[
            'oldest eligible',
            'middle eligible',
            'newest',
          ],
          totalUnreadMessageCount: 17,
        ),
      );

      final args = log.last.arguments as Map;
      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(platformSpecifics['number'], 17);
      expect(platformSpecifics['style'], AndroidNotificationStyle.inbox.index);
      final style = platformSpecifics['styleInformation'] as Map;
      expect(style['lines'], <String>[
        'oldest eligible',
        'middle eligible',
        'newest',
      ]);
      expect(style['htmlFormatLines'], isFalse);
    },
  );

  test(
    'showMessageNotification forwards explicit group anchor payload overrides',
    () async {
      final service = buildService();

      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'group:group-789',
        senderUsername: 'Team Chat',
        messageText: 'Alice: Ping',
        payload: 'group:group-789|message:msg-789',
      );

      final showCall = log.last;
      expect(showCall.method, 'show');

      final args = showCall.arguments as Map;
      expect(args['title'], 'Team Chat');
      expect(args['body'], 'Alice: Ping');
      expect(args['payload'], 'group:group-789|message:msg-789');
      expect(
        args['id'],
        deterministicConversationNotificationId('group:group-789'),
      );
      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(
        platformSpecifics['category'],
        AndroidNotificationCategory.message.name,
      );
    },
  );

  test('showMessageNotification silent:true uses the silent channel and the '
      'per-conversation notification id', () async {
    final service = buildService();

    await service.initialize();
    await service.showMessageNotification(
      contactPeerId: 'peer-silent',
      senderUsername: 'Alice',
      messageText: 'follow-up',
      silent: true,
    );

    final showCall = log.last;
    expect(showCall.method, 'show');

    final args = showCall.arguments as Map;
    // Reuses the per-conversation id so the OS updates in place.
    expect(args['id'], deterministicConversationNotificationId('peer-silent'));

    final platformSpecifics = args['platformSpecifics'] as Map;
    expect(platformSpecifics['channelId'], mknoonMessagesSilentChannelId);
  });

  test('notification id is per-conversation and stable across a burst for both '
      'direct and group (silent updates reuse the same id)', () async {
    final service = buildService();
    await service.initialize();

    // Direct burst: different per-message payload, SAME notification id.
    await service.showMessageNotification(
      contactPeerId: 'peer-1',
      senderUsername: 'Alice',
      messageText: 'first',
      payload: 'peer-1',
    );
    final firstDirectId = (log.last.arguments as Map)['id'];
    await service.showMessageNotification(
      contactPeerId: 'peer-1',
      senderUsername: 'Alice',
      messageText: 'second',
      payload: 'peer-1',
      silent: true,
    );
    final secondDirectId = (log.last.arguments as Map)['id'];
    expect(firstDirectId, deterministicConversationNotificationId('peer-1'));
    expect(secondDirectId, firstDirectId);

    // Group burst: DIFFERENT routePayload (different embedded messageId),
    // SAME notification id — proves the per-message id does not leak in.
    await service.showMessageNotification(
      contactPeerId: 'group:g1',
      senderUsername: 'Team',
      messageText: 'g-first',
      payload: 'group:g1|message:a',
    );
    final firstGroupId = (log.last.arguments as Map)['id'];
    await service.showMessageNotification(
      contactPeerId: 'group:g1',
      senderUsername: 'Team',
      messageText: 'g-second',
      payload: 'group:g1|message:b',
      silent: true,
    );
    final secondGroupId = (log.last.arguments as Map)['id'];
    expect(firstGroupId, deterministicConversationNotificationId('group:g1'));
    expect(secondGroupId, firstGroupId);
    expect((log.last.arguments as Map)['payload'], 'group:g1|message:b');
  });

  test(
    'forced collisions keep direct, group, and announcement payloads on distinct ids',
    () async {
      final fallbackIds = <String, int>{
        'peer-collision': 701,
        'group:discussion-collision': 702,
        'group:announcement-collision': 703,
      };
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
        candidateGenerator: (key, probe) =>
            probe == 0 ? 700 : fallbackIds[key]! + probe - 1,
      );
      final service = buildService(registry: registry);
      await service.initialize();

      await service.showMessageNotification(
        contactPeerId: 'peer-collision',
        senderUsername: 'Direct',
        messageText: 'direct',
      );
      await service.showMessageNotification(
        contactPeerId: 'group:discussion-collision',
        senderUsername: 'Group',
        messageText: 'group',
        payload: 'group:discussion-collision|message:g-1',
      );
      await service.showMessageNotification(
        contactPeerId: 'group:announcement-collision',
        senderUsername: 'Announcement',
        messageText: 'announcement',
        payload: 'group:announcement-collision|message:a-1',
      );

      final ids = log
          .where((call) => call.method == 'show')
          .map((call) => (call.arguments as Map)['id'] as int)
          .toList();
      expect(ids.toSet(), hasLength(3));
      expect(ids.first, 700);
    },
  );

  test('generic anchored group payloads coalesce on the group card', () async {
    final service = buildService();
    await service.initialize();

    await service.showNotification(
      title: 'Announcements',
      body: 'first',
      payload: 'group:announcement-1|message:first',
    );
    final first = log.last.arguments as Map;
    await service.showNotification(
      title: 'Announcements',
      body: 'second',
      payload: 'group:announcement-1|message:second',
    );
    final second = log.last.arguments as Map;

    expect(first['id'], second['id']);
    expect(second['payload'], 'group:announcement-1|message:second');
  });

  test(
    'allocation storage failure never reaches the plugin show call',
    () async {
      final blocked = File('${notificationIdDirectory.path}/blocked')
        ..writeAsStringSync('not a directory');
      final service = buildService(
        registry: DurableConversationNotificationIdRegistry(
          directory: Directory(blocked.path),
        ),
      );
      await service.initialize();

      await expectLater(
        service.showMessageNotification(
          contactPeerId: 'peer-private',
          senderUsername: 'Alice',
          messageText: 'message',
        ),
        throwsA(isA<NotificationIdAllocationException>()),
      );

      expect(log.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test('clearDeliveredNotifications forwards cancelAll', () async {
    final service = buildService();

    await service.initialize();
    await service.clearDeliveredNotifications();

    expect(log.last.method, 'cancelAll');
  });

  test(
    'iOS recovery owner callbacks distinguish update, conversation, and all-clear settlements',
    () async {
      final updated = <String>[];
      final conversations = <String>[];
      var allCleared = 0;
      final service = buildService(
        onNotificationUpdated: () async => updated.add('updated'),
        onConversationCleared: (key) async => conversations.add(key),
        onAllNotificationsCleared: () async => allCleared += 1,
      );
      await service.initialize();

      await service.showMessageNotification(
        contactPeerId: 'peer-shown',
        senderUsername: 'Alice',
        messageText: 'hello',
      );
      expect(
        await service.replaceConversationNotificationGeneration(
          'group:never-allocated',
          'missing-generation',
          const CanonicalConversationNotificationReplacement(
            senderUsername: 'Family',
            messageText: 'replacement',
            routePayload: 'group:never-allocated|message:event',
            contentKind: ConversationNotificationContentKind.message,
            eventIdentity: 'event',
          ),
        ),
        isFalse,
      );
      await service.cancelConversationNotification('peer-never-allocated');
      expect(
        await service.cancelConversationNotificationGeneration(
          'group:generation-never-allocated',
          'missing-generation',
        ),
        isFalse,
      );
      await service.clearDeliveredNotifications();

      expect(updated, <String>['updated', 'updated']);
      expect(conversations, <String>[
        'peer-never-allocated',
        'group:generation-never-allocated',
      ]);
      expect(allCleared, 1);
    },
  );

  test(
    'notification update settlement runs after a native show failure',
    () async {
      var settlements = 0;
      final service = buildService(
        onNotificationUpdated: () async => settlements += 1,
      );
      await service.initialize();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'show') {
              throw PlatformException(code: 'native_show_failed');
            }
            return null;
          });

      await expectLater(
        service.showMessageNotification(
          contactPeerId: 'peer-failed-show',
          senderUsername: 'Alice',
          messageText: 'hello',
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'native_show_failed',
          ),
        ),
      );
      expect(settlements, 1);
    },
  );

  test(
    'exact conversation cancellation uses the existing id without cancelAll or allocation',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(registry: registry);
      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'group:cancel-exact',
        senderUsername: 'Team',
        messageText: 'Existing card',
      );
      final shownId = (log.last.arguments as Map)['id'];
      final ownerFilesBefore = notificationIdDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.owner'))
          .map((file) => file.path)
          .toSet();

      await service.cancelConversationNotification('group:cancel-exact');

      final cancel = log.lastWhere((call) => call.method == 'cancel');
      expect((cancel.arguments as Map)['id'], shownId);
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
      expect(
        notificationIdDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.owner'))
            .map((file) => file.path)
            .toSet(),
        ownerFilesBefore,
      );

      final cancelCount = log.where((call) => call.method == 'cancel').length;
      await service.cancelConversationNotification('group:never-allocated');
      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(cancelCount),
      );
      expect(
        notificationIdDirectory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.owner'),
        ),
        hasLength(ownerFilesBefore.length),
      );
    },
  );

  test(
    'exact conversation cancellation propagates native plugin failure',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(registry: registry);
      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'group:cancel-failure',
        senderUsername: 'Team',
        messageText: 'Existing card',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'cancel') {
              throw PlatformException(code: 'native_cancel_failed');
            }
            return null;
          });

      await expectLater(
        service.cancelConversationNotification('group:cancel-failure'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'native_cancel_failed',
          ),
        ),
      );
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
    },
  );

  test(
    'message-read cancellation preserves a reaction card and cancels a later message generation',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(registry: registry);
      await service.initialize();
      const key = 'group:shared-content-card';

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'Alice reacted to your photo',
        contentKind: ConversationNotificationContentKind.reaction,
      );
      final cancelCountBefore = log
          .where((call) => call.method == 'cancel')
          .length;

      await service.cancelConversationNotification(
        key,
        onlyIfContentKind: ConversationNotificationContentKind.message,
      );

      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(cancelCountBefore),
      );

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'Alice: hello',
        contentKind: ConversationNotificationContentKind.message,
      );
      await service.cancelConversationNotification(
        key,
        onlyIfContentKind: ConversationNotificationContentKind.message,
      );

      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(cancelCountBefore + 2),
        reason: 'one retire-before-replace plus the exact read cancellation',
      );
    },
  );

  test(
    'message-read cancellation cannot overtake a concurrent reaction replacement',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(registry: registry);
      await service.initialize();
      const key = 'group:cross-isolate-card-race';

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'Alice: hello',
        contentKind: ConversationNotificationContentKind.message,
      );

      final cancelEntered = Completer<void>();
      final releaseCancel = Completer<void>();
      final reactionShowEntered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'cancel') {
              if (!cancelEntered.isCompleted) {
                cancelEntered.complete();
                await releaseCancel.future;
              }
            } else if (call.method == 'show' &&
                !reactionShowEntered.isCompleted) {
              reactionShowEntered.complete();
            }
            return null;
          });

      final cancel = service.cancelConversationNotification(
        key,
        onlyIfContentKind: ConversationNotificationContentKind.message,
      );
      await cancelEntered.future;

      var reactionReplacementCompleted = false;
      final reactionReplacement = service
          .showMessageNotification(
            contactPeerId: key,
            senderUsername: 'Group',
            messageText: 'Alice reacted to your message',
            contentKind: ConversationNotificationContentKind.reaction,
          )
          .then((_) => reactionReplacementCompleted = true);
      final reactionOvertookCancel = await Future.any<bool>(<Future<bool>>[
        reactionShowEntered.future.then((_) => true),
        Future<void>.delayed(
          const Duration(milliseconds: 100),
        ).then((_) => false),
      ]);

      releaseCancel.complete();
      await Future.wait<void>(<Future<void>>[cancel, reactionReplacement]);
      expect(
        reactionOvertookCancel,
        isFalse,
        reason:
            'The shared durable lock must serialize replace behind the '
            'in-flight cancel.',
      );
      expect(reactionReplacementCompleted, isTrue);
      final id = await registry.lookup(key);
      expect(id, isNotNull);
      expect(
        await registry.lookupContentKind(
          conversationKey: key,
          notificationId: id!,
        ),
        ConversationNotificationContentKind.reaction,
      );
    },
  );

  test(
    'typed group card disables Android auto-cancel and persists an exact payload generation',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(
        registry: registry,
        generationFactory: () => 'generation-typed',
      );
      await service.initialize();
      const key = 'group:typed-card';
      const route = 'group:typed-card|message:message-typed';

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'Alice: hello',
        payload: route,
        contentKind: ConversationNotificationContentKind.message,
        contentEventIdentity: 'message-typed',
      );

      final showCall = log.lastWhere((call) => call.method == 'show');
      final args = showCall.arguments as Map;
      final decoded = decodeConversationNotificationPayload(
        args['payload'] as String?,
      );
      expect(decoded?.routePayload, route);
      expect(decoded?.conversationKey, key);
      expect(decoded?.metadata.eventIdentity, 'message-typed');
      expect(decoded?.metadata.generation, 'generation-typed');
      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(platformSpecifics['autoCancel'], isFalse);

      final id = args['id'] as int;
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        decoded?.metadata,
      );
    },
  );

  test(
    'untyped conversation card keeps legacy payload and auto-cancel',
    () async {
      final service = buildService();
      await service.initialize();

      await service.showMessageNotification(
        contactPeerId: 'peer-auto-cancel',
        senderUsername: 'Alice',
        messageText: 'hello',
        payload: 'peer-auto-cancel',
      );

      final args =
          log.lastWhere((call) => call.method == 'show').arguments as Map;
      expect(args['payload'], 'peer-auto-cancel');
      expect((args['platformSpecifics'] as Map)['autoCancel'], isTrue);
    },
  );

  test(
    'canonical rebuild silently replaces only the expected managed generation',
    () async {
      final generations = <String>[
        'generation-before',
        'generation-rebuilt',
        'generation-unused',
      ];
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(
        registry: registry,
        generationFactory: () => generations.removeAt(0),
      );
      await service.initialize();
      const key = 'group:canonical-rebuild';
      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Family',
        messageText: 'Reaction',
        payload: 'group:canonical-rebuild|message:target',
        contentKind: ConversationNotificationContentKind.reaction,
        contentEventIdentity: 'removed-reaction',
      );

      expect(
        await service.replaceConversationNotificationGeneration(
          key,
          'generation-before',
          const CanonicalConversationNotificationReplacement(
            senderUsername: 'Family',
            messageText: 'Alice: Photo',
            routePayload: 'group:canonical-rebuild|message:older',
            contentKind: ConversationNotificationContentKind.message,
            eventIdentity: 'older',
          ),
        ),
        isTrue,
      );
      final rebuiltShow = log.lastWhere((call) => call.method == 'show');
      final rebuiltArgs = rebuiltShow.arguments as Map;
      final envelope = decodeConversationNotificationPayload(
        rebuiltArgs['payload'] as String?,
      );
      expect(
        envelope?.metadata.kind,
        ConversationNotificationContentKind.message,
      );
      expect(envelope?.metadata.eventIdentity, 'older');
      expect(envelope?.metadata.generation, 'generation-rebuilt');
      expect((rebuiltArgs['platformSpecifics'] as Map)['autoCancel'], isFalse);
      expect(
        (rebuiltArgs['platformSpecifics'] as Map)['channelId'],
        mknoonMessagesSilentChannelId,
      );

      final operationCount = log.length;
      expect(
        await service.replaceConversationNotificationGeneration(
          key,
          'generation-before',
          const CanonicalConversationNotificationReplacement(
            senderUsername: 'Family',
            messageText: 'stale',
            routePayload: 'group:canonical-rebuild|message:stale',
            contentKind: ConversationNotificationContentKind.message,
            eventIdentity: 'stale',
          ),
        ),
        isFalse,
      );
      expect(log, hasLength(operationCount));
    },
  );

  test(
    'an old Android tap cannot dismiss a newer stable-id generation',
    () async {
      final generations = <String>['generation-old', 'generation-new'];
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final service = buildService(
        registry: registry,
        generationFactory: () => generations.removeAt(0),
      );
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;
      await service.initialize();
      const key = 'group:tap-race';

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'old message',
        payload: 'group:tap-race|message:old',
        contentKind: ConversationNotificationContentKind.message,
        contentEventIdentity: 'old',
      );
      final oldShow = log.lastWhere((call) => call.method == 'show');
      final oldArgs = oldShow.arguments as Map;
      final oldPayload = oldArgs['payload'] as String;
      final id = oldArgs['id'] as int;

      await service.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'new reaction',
        payload: 'group:tap-race|message:new-target',
        contentKind: ConversationNotificationContentKind.reaction,
        contentEventIdentity: 'new-reaction',
      );
      final newShow = log.lastWhere((call) => call.method == 'show');
      final newPayload = (newShow.arguments as Map)['payload'] as String;
      final baselineCancels = log
          .where((call) => call.method == 'cancel')
          .length;

      await _sendNotificationResponse(payload: oldPayload, notificationId: id);
      await _waitForAsyncNotificationWork();

      expect(tapped, <String>['group:tap-race|message:old']);
      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(baselineCancels),
      );
      expect(
        (await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ))?.generation,
        'generation-new',
      );

      await _sendNotificationResponse(payload: newPayload, notificationId: id);
      await _waitForAsyncNotificationWork(
        until: () async {
          if (log.where((call) => call.method == 'cancel').length !=
              baselineCancels + 1) {
            return false;
          }
          return await registry.lookupContentMetadata(
                conversationKey: key,
                notificationId: id,
              ) ==
              null;
        },
      );

      expect(tapped, <String>[
        'group:tap-race|message:old',
        'group:tap-race|message:new-target',
      ]);
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        isNull,
      );
    },
  );

  test(
    'cold launch generation CAS preserves a replacement and cancels the current card',
    () async {
      final generations = <String>[
        'generation-cold-old',
        'generation-cold-new',
      ];
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
      );
      final producer = buildService(
        registry: registry,
        generationFactory: () => generations.removeAt(0),
      );
      await producer.initialize();
      const key = 'group:cold-tap-race';

      await producer.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'old',
        payload: 'group:cold-tap-race|message:old',
        contentKind: ConversationNotificationContentKind.message,
        contentEventIdentity: 'old',
      );
      final oldShow = log.lastWhere((call) => call.method == 'show');
      final oldArgs = oldShow.arguments as Map;
      final oldPayload = oldArgs['payload'] as String;
      final id = oldArgs['id'] as int;
      await producer.showMessageNotification(
        contactPeerId: key,
        senderUsername: 'Group',
        messageText: 'new',
        payload: 'group:cold-tap-race|message:new',
        contentKind: ConversationNotificationContentKind.message,
        contentEventIdentity: 'new',
      );
      final newPayload =
          (log.lastWhere((call) => call.method == 'show').arguments
                  as Map)['payload']
              as String;
      final baselineCancels = log
          .where((call) => call.method == 'cancel')
          .length;

      launchPayload = oldPayload;
      launchNotificationId = id;
      final staleConsumer = buildService(registry: registry);
      await staleConsumer.initialize();
      expect(
        await staleConsumer.consumeInitialPayload(),
        'group:cold-tap-race|message:old',
      );
      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(baselineCancels),
      );
      expect(
        (await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ))?.generation,
        'generation-cold-new',
      );

      launchPayload = newPayload;
      final currentConsumer = buildService(registry: registry);
      await currentConsumer.initialize();
      expect(
        await currentConsumer.consumeInitialPayload(),
        'group:cold-tap-race|message:new',
      );
      expect(
        log.where((call) => call.method == 'cancel'),
        hasLength(baselineCancels + 1),
      );
    },
  );

  test('malformed managed payload neither navigates nor cancels', () async {
    final service = buildService();
    final tapped = <String>[];
    service.onNotificationTap = tapped.add;
    await service.initialize();
    final cancelCount = log.where((call) => call.method == 'cancel').length;

    await _sendNotificationResponse(
      payload: '${conversationNotificationPayloadEnvelopePrefix}damaged',
    );
    await _waitForAsyncNotificationWork();

    expect(tapped, isEmpty);
    expect(
      log.where((call) => call.method == 'cancel'),
      hasLength(cancelCount),
    );
  });
}

final class _BackgroundVisibility extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 1,
    lifecycleGeneration: 1,
  );
}

Future<void> _sendNotificationResponse({
  required String? payload,
  int notificationId = 99,
}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        const MethodChannel('dexterous.com/flutter/local_notifications').name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', <String, Object?>{
            'notificationId': notificationId,
            'actionId': null,
            'input': null,
            'notificationResponseType':
                NotificationResponseType.selectedNotification.index,
            'payload': payload,
          }),
        ),
        (_) {},
      );
}

Future<void> _waitForAsyncNotificationWork({
  FutureOr<bool> Function()? until,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  do {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (until == null || await until()) return;
  } while (DateTime.now().isBefore(deadline));
  throw StateError('timed out waiting for notification callback work');
}
