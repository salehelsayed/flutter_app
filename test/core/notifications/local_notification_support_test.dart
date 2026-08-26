import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// One entry of a `getNotificationChannels` platform reply.
///
/// Every key the plugin's own mapper dereferences is supplied: it calls
/// `Color(a['ledColor'])` and `Importance.values.firstWhere(...)` unguarded, so
/// a partial fixture throws inside the plugin rather than exercising the code
/// under test.
Map<String, Object?> _channelReply(String id, int importance) =>
    <String, Object?>{
      'id': id,
      'name': id,
      'description': null,
      'groupId': null,
      'showBadge': true,
      'importance': importance,
      'playSound': true,
      'soundSource': null,
      'enableLights': false,
      'enableVibration': true,
      'vibrationPattern': null,
      'ledColor': 0,
      'audioAttributesUsage': 5,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];
  final capturedEvents = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> eventsNamed(String event) => capturedEvents
      .where((payload) => payload['event'] == event)
      .toList(growable: false);

  setUp(() {
    flowEventLoggingEnabled = false;
    capturedEvents.clear();
    // The sink fires regardless of `flowEventLoggingEnabled`.
    debugSetFlowEventSink(capturedEvents.add);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSetFlowEventSink(null);
    log.clear();
  });

  test('ensureMknoonNotificationChannel creates the Android channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          return null;
        });

    await ensureMknoonNotificationChannel(FlutterLocalNotificationsPlugin());

    // 118 Phase 3: BOTH the high channel and the silent channel are created.
    expect(log, hasLength(2));
    expect(
      log.every((call) => call.method == 'createNotificationChannel'),
      isTrue,
    );

    final args = log.first.arguments as Map;
    expect(args['id'], mknoonMessagesChannelId);
    expect(args['name'], mknoonMessagesChannelName);
    expect(args['description'], mknoonMessagesChannelDescription);
    expect(args['importance'], Importance.high.value);
    expect(args['showBadge'], isTrue);
    expect(args['playSound'], isTrue);

    final silentArgs = log[1].arguments as Map;
    expect(silentArgs['id'], mknoonMessagesSilentChannelId);
    expect(silentArgs['importance'], Importance.low.value);
    expect(silentArgs['playSound'], isFalse);
  });

  test('ensureMknoonNotificationChannel is a no-op off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          return null;
        });

    await ensureMknoonNotificationChannel(FlutterLocalNotificationsPlugin());

    expect(log, isEmpty);
  });

  test('notification details match the channel contract', () {
    final androidDetails =
        mknoonMessagesNotificationDetails.android as AndroidNotificationDetails;
    final iosDetails =
        mknoonMessagesNotificationDetails.iOS as DarwinNotificationDetails;

    expect(androidDetails.channelId, mknoonMessagesChannelId);
    expect(androidDetails.channelName, mknoonMessagesChannelName);
    expect(androidDetails.channelDescription, mknoonMessagesChannelDescription);
    expect(androidDetails.importance, Importance.high);
    expect(androidDetails.priority, Priority.high);
    expect(androidDetails.playSound, isTrue);

    expect(iosDetails.presentSound, isTrue);
    expect(iosDetails.presentAlert, isTrue);
    expect(iosDetails.presentBadge, isTrue);
  });

  test(
    'all message channels and publications use notification audio usage',
    () {
      expect(
        mknoonMessageAudioAttributesUsage,
        AudioAttributesUsage.notification,
      );
      expect(
        mknoonMessagesChannel.audioAttributesUsage,
        mknoonMessageAudioAttributesUsage,
      );
      expect(
        mknoonMessagesSilentChannel.audioAttributesUsage,
        mknoonMessageAudioAttributesUsage,
      );

      final details = <AndroidNotificationDetails>[
        mknoonMessagesNotificationDetails.android as AndroidNotificationDetails,
        mknoonGenericNotificationDetails(androidTag: 'tag').android
            as AndroidNotificationDetails,
        mknoonMessagesSilentNotificationDetails.android
            as AndroidNotificationDetails,
        mknoonConversationNotificationDetails(
              conversationKey: 'peer-audible',
            ).android
            as AndroidNotificationDetails,
        mknoonConversationNotificationDetails(
              conversationKey: 'peer-silent',
              silent: true,
            ).android
            as AndroidNotificationDetails,
      ];
      expect(
        details.map((detail) => detail.audioAttributesUsage),
        everyElement(mknoonMessageAudioAttributesUsage),
      );
    },
  );

  test('silent notification details disable sound and vibration', () {
    final androidDetails =
        mknoonMessagesSilentNotificationDetails.android
            as AndroidNotificationDetails;
    final iosDetails =
        mknoonMessagesSilentNotificationDetails.iOS
            as DarwinNotificationDetails;

    expect(androidDetails.channelId, mknoonMessagesSilentChannelId);
    expect(androidDetails.importance, Importance.low);
    expect(androidDetails.playSound, isFalse);
    expect(androidDetails.enableVibration, isFalse);
    expect(androidDetails.onlyAlertOnce, isTrue);

    // iOS keeps the banner + badge but plays no sound.
    expect(iosDetails.presentSound, isFalse);
    expect(iosDetails.presentAlert, isTrue);
    expect(iosDetails.presentBadge, isTrue);
  });

  test(
    'silent update can retain an active primary-channel card without alerting',
    () {
      final details = mknoonConversationNotificationDetails(
        conversationKey: 'peer-primary-update',
        silent: true,
        preservePrimaryAndroidChannel: true,
      );
      final android = details.android as AndroidNotificationDetails;

      expect(android.channelId, mknoonMessagesChannelId);
      expect(android.importance, Importance.high);
      expect(android.priority, Priority.high);
      expect(android.playSound, isFalse);
      expect(android.enableVibration, isFalse);
      expect(android.onlyAlertOnce, isTrue);
      expect(android.silent, isTrue);
    },
  );

  group('shouldPreserveMknoonPrimaryChannelForSilentUpdate', () {
    test('matches the exact active id on the primary channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(
        await shouldPreserveMknoonPrimaryChannelForSilentUpdate(
          silent: true,
          notificationId: 42,
          plugin: FlutterLocalNotificationsPlugin(),
          activeNotificationsFn: () async => const <ActiveNotification>[
            ActiveNotification(id: 42, channelId: mknoonMessagesChannelId),
          ],
        ),
        isTrue,
      );
    });

    test('does not promote a first or already-silent card', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(
        await shouldPreserveMknoonPrimaryChannelForSilentUpdate(
          silent: true,
          notificationId: 42,
          plugin: FlutterLocalNotificationsPlugin(),
          activeNotificationsFn: () async => const <ActiveNotification>[
            ActiveNotification(
              id: 42,
              channelId: mknoonMessagesSilentChannelId,
            ),
          ],
        ),
        isFalse,
      );
      expect(
        await shouldPreserveMknoonPrimaryChannelForSilentUpdate(
          silent: true,
          notificationId: 42,
          plugin: FlutterLocalNotificationsPlugin(),
          activeNotificationsFn: () async => const <ActiveNotification>[],
        ),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Per-channel disablement. `mknoon_messages_silent` is a continuation of
  // `mknoon_messages`, not a separate subscription, so a user who switches
  // "Messages" off must not keep receiving the same cards through it.
  // -------------------------------------------------------------------------
  group('resolveMknoonMessagePublicationSilence', () {
    test('never reads the platform for an audible publication', () async {
      var reads = 0;

      final silent = await resolveMknoonMessagePublicationSilence(
        silent: false,
        plugin: FlutterLocalNotificationsPlugin(),
        primaryChannelEnabledFn: () async {
          reads += 1;
          return false;
        },
      );

      expect(silent, isFalse);
      // An audible publication already targets the primary channel, so there
      // is no second route to withdraw and no reason to pay for a binder call
      // on the hot path.
      expect(reads, 0);
      expect(eventsNamed('NOTIFICATION_SILENT_CHANNEL_WITHHELD'), isEmpty);
    });

    test(
      'keeps the silent channel while the primary channel is open',
      () async {
        final silent = await resolveMknoonMessagePublicationSilence(
          silent: true,
          plugin: FlutterLocalNotificationsPlugin(),
          primaryChannelEnabledFn: () async => true,
        );

        expect(silent, isTrue);
        expect(eventsNamed('NOTIFICATION_SILENT_CHANNEL_WITHHELD'), isEmpty);
      },
    );

    test(
      'withdraws the silent channel when the primary channel is blocked',
      () async {
        final silent = await resolveMknoonMessagePublicationSilence(
          silent: true,
          plugin: FlutterLocalNotificationsPlugin(),
          primaryChannelEnabledFn: () async => false,
        );

        // False routes the publication back onto the blocked primary channel,
        // where the OS refuses it — the post attempt stays real and no card
        // reaches the user on either channel.
        expect(silent, isFalse);

        final withheld = eventsNamed('NOTIFICATION_SILENT_CHANNEL_WITHHELD');
        expect(withheld, hasLength(1));
        final details = (withheld.single['details'] as Map)
            .cast<String, dynamic>();
        expect(details['primaryChannelId'], mknoonMessagesChannelId);
        expect(details['withheldChannelId'], mknoonMessagesSilentChannelId);
      },
    );

    test(
      'fails OPEN and reports the failure when the channel read throws',
      () async {
        final silent = await resolveMknoonMessagePublicationSilence(
          silent: true,
          plugin: FlutterLocalNotificationsPlugin(),
          // StateError is an Error, not an Exception: an `on Exception` catch
          // would let it escape and abort an otherwise healthy publication.
          primaryChannelEnabledFn: () async => throw StateError('channel read'),
        );

        expect(silent, isTrue);
        expect(
          eventsNamed('NOTIFICATION_CHANNEL_STATE_READ_FAILED'),
          hasLength(1),
        );
        expect(eventsNamed('NOTIFICATION_SILENT_CHANNEL_WITHHELD'), isEmpty);
      },
    );
  });

  group('mknoonPrimaryMessageChannelEnabled', () {
    void mockChannels(List<Map<String, Object?>>? reply) {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'getNotificationChannels') return reply;
            return null;
          });
    }

    test(
      'reports the live user-blocked importance of the primary channel',
      () async {
        mockChannels(<Map<String, Object?>>[
          // 0 = IMPORTANCE_NONE, what the OS reports once the user switches the
          // channel off in Settings. Nothing else in the stack moves: the app
          // still holds POST_NOTIFICATIONS and areNotificationsEnabled() stays
          // true, which is why this read is the only way to see the state.
          _channelReply(mknoonMessagesChannelId, 0),
          _channelReply(mknoonMessagesSilentChannelId, 2),
        ]);

        expect(
          await mknoonPrimaryMessageChannelEnabled(
            FlutterLocalNotificationsPlugin(),
          ),
          isFalse,
        );
        expect(
          log.map((call) => call.method),
          contains('getNotificationChannels'),
        );
      },
    );

    test('reports enabled for the channel the app actually declares', () async {
      mockChannels(<Map<String, Object?>>[
        _channelReply(mknoonMessagesChannelId, Importance.high.value),
        _channelReply(mknoonMessagesSilentChannelId, Importance.low.value),
      ]);

      expect(
        await mknoonPrimaryMessageChannelEnabled(
          FlutterLocalNotificationsPlugin(),
        ),
        isTrue,
      );
    });

    test(
      'fails OPEN when the primary channel is absent or unreadable',
      () async {
        // A blocked SILENT channel must not be mistaken for a blocked primary:
        // reading the wrong entry here would suppress every audible card.
        mockChannels(<Map<String, Object?>>[
          _channelReply(mknoonMessagesSilentChannelId, 0),
        ]);
        expect(
          await mknoonPrimaryMessageChannelEnabled(
            FlutterLocalNotificationsPlugin(),
          ),
          isTrue,
        );

        mockChannels(null);
        expect(
          await mknoonPrimaryMessageChannelEnabled(
            FlutterLocalNotificationsPlugin(),
          ),
          isTrue,
        );
      },
    );

    test('is a no-op off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            return null;
          });

      expect(
        await mknoonPrimaryMessageChannelEnabled(
          FlutterLocalNotificationsPlugin(),
        ),
        isTrue,
      );
      expect(log, isEmpty);
    });
  });
}
