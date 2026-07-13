import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const cryptoChannel = MethodChannel('com.mknoon/background_push_crypto');
  final List<MethodCall> log = <MethodCall>[];

  test(
    'persists only the exact token-registration transport installation',
    () async {
      final store = FakeSecureKeyStore();

      await persistBackgroundPushRegistrationTransportPeerId(
        secureKeyStore: store,
        transportPeerId: '  transport-this-install  ',
      );
      expect(
        await store.read('push_registration_transport_peer_id'),
        'transport-this-install',
      );

      await persistBackgroundPushRegistrationTransportPeerId(
        secureKeyStore: store,
        transportPeerId: ' ',
      );
      expect(await store.read('push_registration_transport_peer_id'), isNull);
    },
  );

  setUp(() {
    flowEventLoggingEnabled = false;
    log.clear();

    final backgroundGate = RecentBackgroundNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentBackgroundNotificationGate(backgroundGate);
    addTearDown(backgroundGate.clear);

    final remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentRemoteNotificationGate(remoteGate);
    addTearDown(remoteGate.clear);

    final reactionCoordinatorDirectory = Directory.systemTemp.createTempSync(
      'background-reaction-coordinator-',
    );
    final reactionCoordinator = DurableNotificationToneLease(
      directory: reactionCoordinatorDirectory,
    );
    debugSetBackgroundReactionNotificationCoordinatorResolver(
      () async => reactionCoordinator,
    );
    addTearDown(() async {
      if (reactionCoordinatorDirectory.existsSync()) {
        reactionCoordinatorDirectory.deleteSync(recursive: true);
      }
    });

    final messageCoordinatorDirectory = Directory.systemTemp.createTempSync(
      'background-message-coordinator-',
    );
    final messageCoordinator = DurableNotificationToneLease(
      directory: messageCoordinatorDirectory,
      pendingClaimWait: Duration.zero,
    );
    debugSetBackgroundMessageNotificationCoordinatorResolver(
      () async => messageCoordinator,
    );
    addTearDown(() async {
      if (messageCoordinatorDirectory.existsSync()) {
        messageCoordinatorDirectory.deleteSync(recursive: true);
      }
    });

    final notificationIdDirectory = Directory.systemTemp.createTempSync(
      'background-notification-id-registry-',
    );
    final notificationIdRegistry = DurableConversationNotificationIdRegistry(
      directory: notificationIdDirectory,
    );
    debugSetBackgroundConversationNotificationIdRegistryResolver(
      () async => notificationIdRegistry,
    );
    addTearDown(() async {
      if (notificationIdDirectory.existsSync()) {
        notificationIdDirectory.deleteSync(recursive: true);
      }
    });

    debugSetBackgroundAccountMigrationNetworkGate(({
      String? peerId,
      required String operation,
    }) async {
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cryptoChannel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSetFlowEventSink(null);
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
    debugResetBackgroundPushNotificationResolver();
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundDirectMessageLocalStateResolver();
    debugResetBackgroundGroupMessageLocalStateResolver();
    debugResetBackgroundNotificationLocaleResolver();
    debugResetBackgroundDirectReactionLocalStateResolver();
    debugResetBackgroundGroupReactionLocalStateResolver();
    debugResetBackgroundMessageNotificationCoordinatorResolver();
    debugResetBackgroundConversationNotificationIdRegistryResolver();
    debugResetBackgroundReactionNotificationCoordinatorResolver();
    debugResetBackgroundAccountMigrationNetworkGate();
    debugResetBackgroundPushEnvelopeStager();
    debugResetBackgroundNotificationsInitialization();
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearLocaleTestValue();
  });

  group('firebaseMessagingBackgroundHandler', () {
    test(
      'group reaction background handler uses headless group crypto and stable group card',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-state-1\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\",\\"eventId\\":\\"transition-1\\"}"}''';
            });
        debugSetBackgroundGroupReactionLocalStateResolver((_) async {
          return const BackgroundGroupReactionLocalState(
            previewContext: GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
            nominationVerified: true,
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-group-reaction-id',
            data: {
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        final showCall = log.singleWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(
          showArgs['id'],
          deterministicConversationNotificationId('group:group-team'),
        );
        expect(showArgs['title'], 'Team Chat');
        expect(showArgs['body'], 'Alice reacted 👍 to your message');
        expect(showArgs['payload'], 'group:group-team|message:message-1');
      },
    );

    test(
      'group reaction parity mismatch is suppressed before event claim and display',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-state-1\\",\\"messageId\\":\\"attacker-target\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\",\\"eventId\\":\\"transition-parity\\"}"}''';
            });
        debugSetBackgroundGroupReactionLocalStateResolver((_) async {
          return const BackgroundGroupReactionLocalState(
            previewContext: GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
            nominationVerified: true,
          );
        });
        final directory = Directory.systemTemp.createTempSync(
          'background-parity-claim-',
        );
        final coordinator = DurableNotificationToneLease(directory: directory);
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: {
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-parity',
              'target_message_id': 'message-1',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(
          await coordinator.claimEvent(
            boundedReactionEventIdentity('transition-parity'),
          ),
          isTrue,
          reason: 'invalid plaintext must not poison the durable event claim',
        );
      },
    );

    test(
      'reaction background handler uses headless crypto and trusted actor copy',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-1\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\"}"}''';
            });
        debugSetBackgroundDirectReactionLocalStateResolver((_) async {
          return const BackgroundDirectReactionLocalState(
            previewContext: DirectReactionNotificationContext(
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            mlKemSecretKey: 'recipient-secret',
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-id',
            data: {
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        final showCall = log.singleWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Alice');
        expect(showArgs['body'], 'Reacted 👍 to your message');
        expect(showArgs['payload'], 'peer-alice');
      },
    );

    test(
      'reaction allocation failure releases exact claim and tone for audible retry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Reacted 👍 to your message',
            payload: 'peer-allocation-retry',
          ),
        );
        final claimDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-allocation-claim-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: claimDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-allocation-registry-',
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        var allocationAttempts = 0;
        debugSetBackgroundConversationNotificationIdRegistryResolver(() async {
          allocationAttempts++;
          if (allocationAttempts == 1) {
            throw const NotificationIdAllocationException(
              operation: 'synthetic_allocation_failure',
              errorType: 'StateError',
            );
          }
          return registry;
        });
        addTearDown(() {
          if (claimDirectory.existsSync()) {
            claimDirectory.deleteSync(recursive: true);
          }
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const message = RemoteMessage(
          data: {
            'type': 'message_reaction',
            'sender_id': 'peer-allocation-retry',
            'event_id': 'reaction-allocation-retry',
            'target_message_id': 'target-allocation-retry',
            'action': 'add',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(log.where((call) => call.method == 'show'), isEmpty);
        await firebaseMessagingBackgroundHandler(message);

        final show = log.singleWhere((call) => call.method == 'show');
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['playSound'], isTrue);
        final claimFile = File(
          '${claimDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-allocation-retry'))}',
        );
        expect(claimFile.readAsStringSync(), contains('"state":"committed"'));
      },
    );

    test(
      'reaction OS show failure releases exact claim and tone for audible retry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Reacted ❤️ to your message',
            payload: 'peer-show-retry',
          ),
        );
        final claimDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-show-claim-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: claimDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (claimDirectory.existsSync()) {
            claimDirectory.deleteSync(recursive: true);
          }
        });
        var showAttempts = 0;
        final successfulShows = <Map>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                showAttempts++;
                if (showAttempts == 1) {
                  throw PlatformException(code: 'synthetic_show_failure');
                }
                successfulShows.add(call.arguments as Map);
              }
              return null;
            });
        const message = RemoteMessage(
          data: {
            'type': 'message_reaction',
            'sender_id': 'peer-show-retry',
            'event_id': 'reaction-show-retry',
            'target_message_id': 'target-show-retry',
            'action': 'add',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        await firebaseMessagingBackgroundHandler(message);

        expect(showAttempts, 2);
        expect(successfulShows, hasLength(1));
        final specifics = successfulShows.single['platformSpecifics'] as Map;
        expect(specifics['playSound'], isTrue);
      },
    );

    test(
      'post-show reaction commit failures retain both replacement owners',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Announcements',
            body: 'Alice reacted 👍 to your announcement',
            payload: 'group:announcement-commit|message:target-commit',
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'background-reaction-commit-failure-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final claimFile = File(
          '${directory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('announcement-reaction-commit'))}',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                await _replaceBackgroundPendingToken(
                  claimFile,
                  'replacement-reaction-claim',
                );
                final toneDirectory = Directory(
                  '${directory.path}/'
                  '${DurableNotificationToneLease.toneLeasesDirectoryName}',
                );
                final pendingTone = toneDirectory
                    .listSync()
                    .whereType<File>()
                    .singleWhere(
                      (file) => file.path.endsWith(
                        DurableNotificationToneLease
                            .tonePendingReservationFileSuffix,
                      ),
                    );
                await _replaceBackgroundPendingToken(
                  pendingTone,
                  'replacement-reaction-tone',
                );
              }
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: {
              'type': 'group_reaction',
              'groupId': 'announcement-commit',
              'reactor_peer_id': 'peer-announcement-admin',
              'event_id': 'announcement-reaction-commit',
              'target_message_id': 'target-commit',
              'action': 'add',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          claimFile.readAsStringSync(),
          contains('replacement-reaction-claim'),
        );
        final names = events.map((event) => event['event']);
        expect(
          names,
          containsAll(<String>[
            'PUSH_BACKGROUND_MESSAGE_TONE_COMMIT_FAILED',
            'PUSH_BACKGROUND_MESSAGE_CLAIM_COMMIT_FAILED',
          ]),
        );
        expect(
          names,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED')),
        );
        expect(
          names,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED')),
        );
      },
    );

    test(
      'reaction becoming ineligible between policy and preview stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        var localStateReads = 0;
        debugSetBackgroundDirectReactionLocalStateResolver((_) async {
          localStateReads++;
          if (localStateReads > 1) return null;
          return const BackgroundDirectReactionLocalState(
            previewContext: DirectReactionNotificationContext(
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            mlKemSecretKey: 'recipient-secret',
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-race-id',
            data: {
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-race-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(localStateReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'real default direct handler decrypts text/media/private previews with trusted names, locales, and prior keys',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushEnvelopeStager((_) async {});
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final cases = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'direct-text-en',
            'locale': const Locale('en'),
            'text': 'Hello from encrypted text',
            'expected': 'Hello from encrypted text',
          },
          <String, Object?>{
            'id': 'direct-image-de',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image', 'mime': 'image/jpeg'},
            ],
            'expected': 'Foto',
          },
          <String, Object?>{
            'id': 'direct-video-ar',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'video', 'mime': 'video/mp4'},
            ],
            'expected': 'فيديو',
          },
          <String, Object?>{
            'id': 'direct-voice-de',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'audio', 'mime': 'audio/aac'},
            ],
            'expected': 'Sprachnachricht',
          },
          <String, Object?>{
            'id': 'direct-private-ar',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image', 'mime': 'image/jpeg'},
            ],
            'privateMedia': <String, Object?>{
              'version': 1,
              'mode': 'protected',
            },
            'expected': 'وسائط خاصة',
          },
        ];
        final byId = <String, Map<String, Object?>>{
          for (final testCase in cases) testCase['id']! as String: testCase,
        };
        final cryptoKeys = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              final arguments = Map<String, dynamic>.from(
                jsonDecode(call.arguments as String) as Map,
              );
              final secretKey = arguments['secretKey']! as String;
              cryptoKeys.add(secretKey);
              if (secretKey == 'current-key') {
                return jsonEncode(<String, Object?>{
                  'ok': false,
                  'errorCode': 'decrypt_failed',
                });
              }
              final id = (arguments['ciphertext']! as String).substring(
                'cipher-'.length,
              );
              final testCase = byId[id]!;
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'id': id,
                  'text': testCase['text'],
                  'senderPeerId': 'peer-alice',
                  'senderUsername': 'ATTACKER DECRYPTED NAME',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                  if (testCase['media'] != null) 'media': testCase['media'],
                  if (testCase['privateMedia'] != null)
                    'privateMedia': testCase['privateMedia'],
                }),
              });
            });
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          return BackgroundDirectMessageLocalState(
            previewContext: DirectMessageNotificationContext(
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice from contacts DB',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            mlKemSecretKeys: const <String>['current-key', 'prior-key'],
          );
        });

        for (final testCase in cases) {
          log.clear();
          cryptoKeys.clear();
          final id = testCase['id']! as String;
          debugSetBackgroundNotificationLocaleResolver(
            () => testCase['locale']! as Locale,
          );
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-$id',
              data: <String, dynamic>{
                'type': 'new_message',
                'sender_id': 'peer-alice',
                'message_id': id,
                'kem': 'kem-$id',
                'ciphertext': 'cipher-$id',
                'nonce': 'nonce-$id',
                'title': 'ATTACKER OUTER NAME',
              },
            ),
          );

          final show = log.singleWhere((call) => call.method == 'show');
          final arguments = show.arguments as Map;
          expect(arguments['title'], 'Alice from contacts DB', reason: id);
          expect(arguments['body'], testCase['expected'], reason: id);
          expect(arguments['payload'], 'peer-alice', reason: id);
          expect(cryptoKeys, const <String>['current-key', 'prior-key']);
          expect(
            '${arguments['title']}|${arguments['body']}',
            isNot(contains('ATTACKER')),
          );
        }
      },
    );

    test(
      'real default group and announcement handler localizes every modality and trusts only DB names',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final modalities = <Map<String, Object?>>[
          <String, Object?>{
            'name': 'text',
            'locale': const Locale('en'),
            'text': 'Encrypted hello',
            'expected': 'Encrypted hello',
          },
          <String, Object?>{
            'name': 'image',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image'},
            ],
            'expected': 'Foto',
          },
          <String, Object?>{
            'name': 'video',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'video'},
            ],
            'expected': 'فيديو',
          },
          <String, Object?>{
            'name': 'voice',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'audio'},
            ],
            'expected': 'Sprachnachricht',
          },
          <String, Object?>{
            'name': 'private',
            'locale': const Locale('ar'),
            'text': 'SECRET private caption',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image'},
            ],
            'private': true,
            'expected': 'وسائط خاصة جديدة',
          },
        ];
        final cases = <Map<String, Object?>>[
          for (final kind in const <String>['group', 'announcement'])
            for (final modality in modalities)
              <String, Object?>{
                ...modality,
                'kind': kind,
                'id': '$kind-${modality['name']}',
              },
        ];
        final byId = <String, Map<String, Object?>>{
          for (final testCase in cases) testCase['id']! as String: testCase,
        };
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              final arguments = Map<String, dynamic>.from(
                jsonDecode(call.arguments as String) as Map,
              );
              expect(arguments['groupKey'], 'group-key');
              final id = (arguments['ciphertext']! as String).substring(
                'cipher-'.length,
              );
              final testCase = byId[id]!;
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': testCase['kind'] == 'group'
                      ? 'group-team'
                      : 'group-announcements',
                  'messageId': id,
                  'senderId': 'peer-admin',
                  'groupName': 'ATTACKER DECRYPTED GROUP',
                  'senderUsername': 'ATTACKER DECRYPTED ACTOR',
                  'text': testCase['text'],
                  if (testCase['media'] != null) 'media': testCase['media'],
                  if (testCase['private'] == true) ...<String, Object?>{
                    'mediaPolicyVersion': 1,
                    'mediaLifecycle': 'viewOnce',
                    'mediaDurationSeconds': null,
                    'mediaProtected': true,
                  },
                }),
              });
            });
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          final groupId = message.data['groupId']! as String;
          return BackgroundGroupMessageLocalState(
            previewContext: GroupMessageNotificationContext(
              groupId: groupId,
              groupName: groupId == 'group-team'
                  ? 'Team from groups DB'
                  : 'Announcements from groups DB',
              localPeerId: 'peer-local',
              senderPeerId: 'peer-admin',
              senderTransportPeerId: 'transport-admin-phone',
              senderUsername: 'Admin from members DB',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
          );
        });

        for (final testCase in cases) {
          log.clear();
          final id = testCase['id']! as String;
          final groupId = testCase['kind'] == 'group'
              ? 'group-team'
              : 'group-announcements';
          debugSetBackgroundNotificationLocaleResolver(
            () => testCase['locale']! as Locale,
          );
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-$id',
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': groupId,
                'sender_id': 'peer-admin',
                'sender_transport_peer_id': 'transport-admin-phone',
                'message_id': id,
                'keyEpoch': '7',
                'ciphertext': 'cipher-$id',
                'nonce': 'nonce-$id',
                'title': 'ATTACKER OUTER GROUP',
              },
            ),
          );

          final show = log.singleWhere((call) => call.method == 'show');
          final arguments = show.arguments as Map;
          expect(
            arguments['title'],
            testCase['private'] == true
                ? 'Mknoon'
                : testCase['kind'] == 'group'
                ? 'Team from groups DB'
                : 'Announcements from groups DB',
            reason: id,
          );
          final expectedBody = testCase['private'] == true
              ? testCase['expected']
              : 'Admin from members DB: ${testCase['expected']}';
          expect(arguments['body'], expectedBody, reason: id);
          expect(
            '${arguments['title']}|${arguments['body']}',
            isNot(contains('ATTACKER')),
            reason: id,
          );
        }
      },
    );

    test(
      'group provider without authenticated transport stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': 'group-team',
                  'messageId': 'group-no-provider-actor',
                  'senderId': 'peer-alice',
                  'senderUsername': 'UNTRUSTED DECRYPTED ALICE',
                  'groupName': 'UNTRUSTED DECRYPTED GROUP',
                  'text': '',
                  'media': <Map<String, Object?>>[
                    <String, Object?>{'mediaType': 'audio'},
                  ],
                }),
              });
            });
        debugSetBackgroundGroupMessageLocalStateResolver((_) async => null);
        debugSetBackgroundNotificationLocaleResolver(() => const Locale('de'));

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-no-provider-actor',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'direct outage and flagged group preview unavailability stay generic while invalid/parity failures stay silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundNotificationLocaleResolver(() => const Locale('de'));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        var directKeys = const <String>[];
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          return BackgroundDirectMessageLocalState(
            previewContext: DirectMessageNotificationContext(
              senderPeerId: 'peer-alice',
              senderUsername: 'Trusted Alice',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            mlKemSecretKeys: directKeys,
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'no-key',
              'kem': 'SECRET-kem',
              'ciphertext': 'SECRET-ciphertext',
              'nonce': 'SECRET-nonce',
            },
          ),
        );
        var shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(1));
        var arguments = shows.single.arguments as Map;
        expect(arguments['title'], 'Trusted Alice');
        expect(arguments['body'], 'Nachricht');
        expect(
          '${arguments['title']}|${arguments['body']}',
          isNot(contains('SECRET')),
        );

        log.clear();
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          return BackgroundGroupMessageLocalState(
            previewContext: GroupMessageNotificationContext(
              groupId: 'group-team',
              groupName: 'Trusted Team',
              localPeerId: 'peer-local',
              senderPeerId: 'peer-admin',
              senderTransportPeerId: 'transport-admin-phone',
              senderUsername: 'Trusted Admin',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
          );
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': false,
                'errorCode': 'plugin_unavailable',
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-plugin-outage',
              'keyEpoch': '7',
              'ciphertext': 'SECRET-group-ciphertext',
              'nonce': 'SECRET-group-nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty, reason: 'ordinary invalid cipher fails closed');

        log.clear();
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-preview-unavailable',
              'preview_unavailable': '1',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(1));
        arguments = shows.single.arguments as Map;
        expect(arguments['title'], 'Trusted Team');
        expect(arguments['body'], 'Nachricht');

        log.clear();
        directKeys = const <String>['current-key'];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'id': 'attacker-message-id',
                  'text': 'ATTACKER CONTENT',
                  'senderPeerId': 'peer-alice',
                  'senderUsername': 'ATTACKER NAME',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                }),
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'expected-message-id',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty);

        log.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': 'group-attacker',
                  'messageId': 'group-expected-message-id',
                  'senderId': 'peer-attacker',
                  'senderUsername': 'ATTACKER NAME',
                  'text': 'ATTACKER CONTENT',
                }),
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-expected-message-id',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty);
      },
    );

    test(
      'ordinary message becoming locally ineligible between policy and preview stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        var directReads = 0;
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          directReads++;
          return directReads == 1
              ? BackgroundDirectMessageLocalState(
                  previewContext: DirectMessageNotificationContext(
                    senderPeerId: 'peer-alice',
                    senderUsername: 'Trusted Alice',
                    expectedMessageId: message.data['message_id'] as String?,
                  ),
                  mlKemSecretKeys: const <String>[],
                )
              : null;
        });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct-state-race',
            },
          ),
        );
        expect(directReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);

        log.clear();
        var groupReads = 0;
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          groupReads++;
          return groupReads == 1
              ? BackgroundGroupMessageLocalState(
                  previewContext: GroupMessageNotificationContext(
                    groupId: 'group-team',
                    groupName: 'Trusted Team',
                    localPeerId: 'peer-local',
                    senderPeerId: null,
                    senderUsername: null,
                    expectedMessageId: message.data['message_id'] as String?,
                  ),
                  groupKey: null,
                  keyEpoch: null,
                )
              : null;
        });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-state-race',
            },
          ),
        );
        expect(groupReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'committed live and NSE claims suppress exact direct and group background events',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-existing-message-claims-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final liveClaim = await coordinator.claimMessageEvent(
          type: 'new_message',
          eventIdentity: 'direct-live-claimed',
        );
        expect(liveClaim, isNotNull);
        expect(await liveClaim!.commit(), isTrue);
        final claimDirectory = Directory(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}',
        );
        await claimDirectory.create(recursive: true);
        final nseClaim = File(
          '${claimDirectory.path}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: 'group-nse-claimed')}',
        );
        await nseClaim.writeAsString('', flush: true);

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct-live-claimed',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-nse-claimed',
              'preview_unavailable': '1',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'direct and group background shows commit exact typed identities only after show',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-exact-message-claims-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-exact-claims-remote-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);
        final pendingStatesAtShow = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                final payload = (call.arguments as Map)['payload'] as String?;
                final typedIdentity = payload == 'peer-alice'
                    ? (type: 'new_message', id: 'direct/exact id')
                    : (type: 'group_message', id: 'group/exact id');
                final file = File(
                  '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: typedIdentity.type, eventIdentity: typedIdentity.id)}',
                );
                pendingStatesAtShow.add(await file.readAsString());
              }
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct/exact id',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group/exact id',
              'preview_unavailable': '1',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(2));
        expect(pendingStatesAtShow, hasLength(2));
        expect(
          pendingStatesAtShow,
          everyElement(allOf(contains('"state":"pending"'), contains('token'))),
        );
        for (final identity in const <({String type, String id})>[
          (type: 'new_message', id: 'direct/exact id'),
          (type: 'group_message', id: 'group/exact id'),
        ]) {
          final file = File(
            '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: identity.type, eventIdentity: identity.id)}',
          );
          expect(await file.readAsString(), contains('"state":"committed"'));
        }
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-alice',
            messageId: 'direct/exact id',
          ),
          isFalse,
          reason: 'exact Android events use the durable claim, not legacy gate',
        );
      },
    );

    test(
      'show error releases exact claim so redelivery can show audibly and commit',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-message-claim-redelivery-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        var showAttempts = 0;
        final playSound = <bool>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                showAttempts++;
                final specifics =
                    (call.arguments as Map)['platformSpecifics'] as Map;
                playSound.add(specifics['playSound'] as bool);
                if (showAttempts == 1) {
                  throw PlatformException(code: 'show_failed');
                }
              }
              return null;
            });
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'redelivery-after-show-error',
          },
        );
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'redelivery-after-show-error')}',
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(claimFile.existsSync(), isFalse);
        await firebaseMessagingBackgroundHandler(message);

        expect(showAttempts, 2);
        expect(playSound, const <bool>[true, true]);
        expect(await claimFile.readAsString(), contains('"state":"committed"'));
      },
    );

    test(
      'forced id collisions keep direct, group, and announcement cards distinct',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final directory = Directory.systemTemp.createTempSync(
          'background-colliding-notification-ids-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final fallbacks = <String, int>{
          'peer-id-collision': 801,
          'group:discussion-id-collision': 802,
          'group:announcement-id-collision': 803,
        };
        final registry = DurableConversationNotificationIdRegistry(
          directory: directory,
          candidateGenerator: (key, probe) =>
              probe == 0 ? 800 : fallbacks[key]! + probe - 1,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final message in const <RemoteMessage>[
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-id-collision',
              'message_id': 'direct-id-collision-message',
            },
          ),
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'discussion-id-collision',
              'message_id': 'group-id-collision-message',
              'preview_unavailable': '1',
            },
          ),
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'announcement-id-collision',
              'message_id': 'announcement-id-collision-message',
              'preview_unavailable': '1',
            },
          ),
        ]) {
          await firebaseMessagingBackgroundHandler(message);
        }

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(3));
        final ids = shows
            .map((call) => (call.arguments as Map)['id'] as int)
            .toList();
        expect(ids.toSet(), hasLength(3));
        expect(ids.first, 800);
      },
    );

    test(
      'id allocation failure releases exact claim and tone for audible redelivery',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        final coordinatorDirectory = Directory.systemTemp.createTempSync(
          'background-id-allocation-release-',
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-id-allocation-retry-',
        );
        addTearDown(() {
          if (coordinatorDirectory.existsSync()) {
            coordinatorDirectory.deleteSync(recursive: true);
          }
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        final coordinator = DurableNotificationToneLease(
          directory: coordinatorDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => throw StateError('registry unavailable'),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-id-allocation-retry',
            'message_id': 'id-allocation-retry-message',
          },
        );
        final claimFile = File(
          '${coordinatorDirectory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'id-allocation-retry-message')}',
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(claimFile.existsSync(), isFalse);

        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => DurableConversationNotificationIdRegistry(
            directory: registryDirectory,
          ),
        );
        await firebaseMessagingBackgroundHandler(message);

        final show = log.singleWhere((call) => call.method == 'show');
        final details = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(details['playSound'], isTrue);
        expect(await claimFile.readAsString(), contains('"state":"committed"'));
      },
    );

    test(
      'claim storage failure and no-id legacy messages fail open through RecentRemote compatibility',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-claim-fail-open-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => throw StateError('claim storage unavailable'),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'fcm-storage-fail-open',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-storage-fail',
              'message_id': 'storage-fail-open',
            },
          ),
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-storage-fail',
            messageId: 'storage-fail-open',
          ),
          isTrue,
        );

        final legacyDirectory = Directory.systemTemp.createTempSync(
          'background-legacy-message-claim-',
        );
        addTearDown(() {
          if (legacyDirectory.existsSync()) {
            legacyDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => DurableNotificationToneLease(
            directory: legacyDirectory,
            pendingClaimWait: Duration.zero,
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'fcm-legacy-no-id',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-legacy-no-id',
            },
          ),
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-legacy-no-id',
            messageId: null,
          ),
          isTrue,
        );
        expect(log.where((call) => call.method == 'show'), hasLength(2));
      },
    );

    test(
      'tone reservation storage failure keeps an exactly claimed message audible',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-tone-reservation-failure-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = _ThrowingToneReservationCoordinator(directory);
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-tone-storage-fail',
              'message_id': 'tone-storage-fail-open',
            },
          ),
        );

        final show = log.singleWhere((call) => call.method == 'show');
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['playSound'], isTrue);
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'tone-storage-fail-open')}',
        );
        expect(await claimFile.readAsString(), contains('"state":"committed"'));
      },
    );

    test('ordinary local-state policies fail closed for unsafe rows', () {
      const directData = <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-alice',
        'message_id': 'direct-policy',
      };
      const identity = <String, Object?>{'peer_id': 'peer-local'};
      const contact = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Trusted Alice',
        'is_blocked': 0,
        'is_archived': 0,
      };
      final direct = directMessageLocalStateFromRows(
        data: directData,
        identityRow: identity,
        contactRow: contact,
        currentMlKemSecretKey: 'current',
        priorMlKemSecretKeys: const <String>['prior', 'current', ' '],
      );
      expect(direct?.mlKemSecretKeys, const <String>['current', 'prior']);
      expect(direct?.previewContext.senderUsername, 'Trusted Alice');
      for (final unsafe
          in <({Map<String, dynamic> data, Map<String, Object?>? row})>[
            (
              data: directData,
              row: <String, Object?>{...contact, 'is_blocked': 1},
            ),
            (
              data: directData,
              row: <String, Object?>{...contact, 'is_archived': 1},
            ),
            (
              data: <String, dynamic>{...directData, 'sender_id': 'peer-local'},
              row: <String, Object?>{...contact, 'peer_id': 'peer-local'},
            ),
            (data: directData, row: null),
          ]) {
        expect(
          directMessageLocalStateFromRows(
            data: unsafe.data,
            identityRow: identity,
            contactRow: unsafe.row,
            currentMlKemSecretKey: 'current',
            priorMlKemSecretKeys: const <String>[],
          ),
          isNull,
        );
      }

      const groupData = <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-team',
        'sender_id': 'peer-admin',
        'sender_transport_peer_id': 'transport-admin-phone',
        'message_id': 'group-policy',
        'keyEpoch': '7',
      };
      const group = <String, Object?>{
        'id': 'group-team',
        'name': 'Trusted Team',
        'type': 'chat',
        'is_muted': 0,
        'is_archived': 0,
        'is_dissolved': 0,
        'dissolved_at': null,
      };
      const localMember = <String, Object?>{
        'group_id': 'group-team',
        'peer_id': 'peer-local',
        'role': 'reader',
        'devices_json':
            '[{"deviceId":"local-phone","transportPeerId":"transport-local-phone","deviceSigningPublicKey":"local-device-key","status":"active"}]',
      };
      const actorMember = <String, Object?>{
        'group_id': 'group-team',
        'peer_id': 'peer-admin',
        'username': 'Trusted Admin',
        'role': 'admin',
        'devices_json':
            '[{"deviceId":"admin-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"admin-device-key","status":"active"}]',
      };
      const groupKey = <String, Object?>{
        'group_id': 'group-team',
        'key_generation': 7,
        'encrypted_key': 'group-key',
      };
      BackgroundGroupMessageLocalState? resolveGroup({
        Map<String, dynamic> data = groupData,
        Map<String, Object?>? groupRow = group,
        Map<String, Object?>? localRow = localMember,
        Map<String, Object?>? actorRow = actorMember,
        List<Map<String, Object?>>? members,
      }) => groupMessageLocalStateFromRows(
        data: data,
        identityRow: identity,
        groupRow: groupRow,
        localMemberRow: localRow,
        memberRows: members ?? <Map<String, Object?>>[?localRow, ?actorRow],
        groupKeyRow: groupKey,
      );

      expect(resolveGroup()?.previewContext.senderUsername, 'Trusted Admin');
      expect(resolveGroup()?.previewContext.senderPeerId, 'peer-admin');
      expect(
        resolveGroup()?.previewContext.senderTransportPeerId,
        'transport-admin-phone',
        reason: 'modern account and transport identities are distinct',
      );
      expect(resolveGroup(groupRow: {...group, 'is_muted': 1}), isNull);
      expect(resolveGroup(groupRow: {...group, 'is_archived': 1}), isNull);
      expect(resolveGroup(groupRow: {...group, 'is_dissolved': 1}), isNull);
      expect(resolveGroup(localRow: null), isNull);
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_id': 'peer-local',
            'sender_transport_peer_id': 'transport-local-phone',
          },
          actorRow: localMember,
        ),
        isNull,
      );
      expect(
        resolveGroup(actorRow: {...actorMember, 'role': 'reader'}),
        isNull,
      );
      expect(
        resolveGroup(actorRow: {...actorMember, 'role': 'unknown'}),
        isNull,
      );
      expect(
        resolveGroup(
          groupRow: {...group, 'type': 'qa'},
          actorRow: {...actorMember, 'role': 'reader'},
        ),
        isNull,
      );
      expect(
        resolveGroup(groupRow: {...group, 'type': 'announcement'}),
        isNotNull,
        reason: 'locally resolved admins may publish announcements',
      );
      expect(
        resolveGroup(
          groupRow: {...group, 'type': 'announcement'},
          actorRow: {...actorMember, 'role': 'writer'},
        ),
        isNull,
        reason: 'announcement messages require a locally known admin actor',
      );

      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'transport-unknown',
          },
        ),
        isNull,
      );
      expect(
        resolveGroup(
          actorRow: <String, Object?>{
            ...actorMember,
            'devices_json':
                '[{"deviceId":"admin-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"admin-device-key","status":"revoked"}]',
          },
        ),
        isNull,
      );
      expect(
        resolveGroup(
          members: <Map<String, Object?>>[
            localMember,
            actorMember,
            <String, Object?>{
              ...actorMember,
              'peer_id': 'peer-impostor',
              'devices_json':
                  '[{"deviceId":"impostor-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"impostor-device-key","status":"active"}]',
            },
          ],
        ),
        isNull,
        reason: 'ambiguous active transport bindings fail closed',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'peer-legacy',
            'sender_id': 'peer-legacy',
          },
          actorRow: const <String, Object?>{
            'group_id': 'group-team',
            'peer_id': 'peer-legacy',
            'username': 'Legacy Writer',
            'role': 'writer',
            'public_key': 'legacy-signing-key',
            'devices_json': '[]',
          },
        )?.previewContext.senderPeerId,
        'peer-legacy',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'peer-legacy',
            'sender_id': 'peer-legacy',
          },
          actorRow: const <String, Object?>{
            'group_id': 'group-team',
            'peer_id': 'peer-legacy',
            'username': 'Malformed Legacy',
            'role': 'writer',
            'public_key': 'legacy-signing-key',
            'devices_json': '{malformed',
          },
        ),
        isNull,
        reason: 'malformed rosters are not legacy-empty',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{...groupData, 'sender_id': 'peer-other'},
        ),
        isNull,
        reason: 'an outer account hint cannot override the local binding',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': null,
          },
        ),
        isNull,
        reason: 'missing authenticated transport identity suppresses',
      );
    });

    test('reaction local-state policy requires known author and identity', () {
      const data = <String, dynamic>{
        'type': 'message_reaction',
        'sender_id': 'peer-alice',
        'event_id': 'reaction-1',
        'target_message_id': 'message-1',
        'action': 'add',
      };
      const identity = <String, Object?>{'peer_id': 'peer-bob'};
      const contact = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Alice',
        'is_blocked': 0,
      };
      const outgoingTarget = <String, Object?>{
        'id': 'message-1',
        'contact_peer_id': 'peer-alice',
        'sender_peer_id': 'peer-bob',
        'is_incoming': 0,
        'deleted_at': null,
      };

      final eligible = directReactionLocalStateFromRows(
        data: data,
        identityRow: identity,
        contactRow: contact,
        targetMessageRow: outgoingTarget,
        mlKemSecretKey: 'secret',
      );
      expect(eligible?.previewContext.actorUsername, 'Alice');

      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: null,
          contactRow: contact,
          targetMessageRow: outgoingTarget,
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          contactRow: {...contact, 'is_blocked': 1},
          targetMessageRow: outgoingTarget,
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          contactRow: contact,
          targetMessageRow: {...outgoingTarget, 'is_incoming': 1},
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
    });

    test(
      'group reaction background state hydrates the SQL secure-key reference',
      () async {
        final store = FakeSecureKeyStore();
        final keyName = groupKeyMaterialStoreName('group-team', 7);
        await store.write(keyName, 'hydrated-group-key');

        final hydrated = await hydrateBackgroundGroupKeyRow(
          groupKeyRow: <String, Object?>{
            'group_id': 'group-team',
            'key_generation': 7,
            'encrypted_key': secureStoreReferenceForKey(keyName),
          },
          secureStore: store,
        );

        expect(hydrated?['encrypted_key'], 'hydrated-group-key');

        await store.delete(keyName);
        expect(
          await hydrateBackgroundGroupKeyRow(
            groupKeyRow: <String, Object?>{
              'group_id': 'group-team',
              'key_generation': 7,
              'encrypted_key': secureStoreReferenceForKey(keyName),
            },
            secureStore: store,
          ),
          isNull,
          reason: 'missing secure material must suppress the notification',
        );
      },
    );

    test('group reaction local-state policy requires current local author', () {
      const data = <String, dynamic>{
        'type': 'group_reaction',
        'groupId': 'group-team',
        'reactor_peer_id': 'peer-alice',
        'event_id': 'transition-1',
        'target_message_id': 'message-1',
        'action': 'add',
        'keyEpoch': '7',
      };
      const identity = <String, Object?>{'peer_id': 'peer-bob'};
      const group = <String, Object?>{
        'id': 'group-team',
        'name': 'Team Chat',
        'is_muted': 0,
        'is_dissolved': 0,
        'dissolved_at': null,
      };
      final localMember = <String, Object?>{
        'peer_id': 'peer-bob',
        'devices_json': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'deviceId': 'bob-phone',
            'transportPeerId': 'transport-bob-phone',
            'deviceSigningPublicKey': 'bob-device-key',
            'status': 'active',
          },
        ]),
      };
      final actorMember = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Alice',
        'devices_json': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'deviceId': 'alice-phone',
            'transportPeerId': 'transport-alice-phone',
            'deviceSigningPublicKey': 'alice-device-key',
            'status': 'active',
          },
        ]),
      };
      const outgoingTarget = <String, Object?>{
        'id': 'message-1',
        'group_id': 'group-team',
        'sender_peer_id': 'peer-bob',
        'is_incoming': 0,
      };
      const groupKey = <String, Object?>{
        'group_id': 'group-team',
        'key_generation': 7,
        'encrypted_key': 'group-key',
      };
      const nomination = VerifiedGroupReactionNotificationNomination(
        reactorTransportPeerId: 'transport-alice-phone',
        senderPublicKey: 'alice-device-key',
      );

      final eligible = groupReactionLocalStateFromRows(
        data: data,
        identityRow: identity,
        groupRow: group,
        localMemberRow: localMember,
        actorMemberRow: actorMember,
        targetMessageRow: outgoingTarget,
        groupKeyRow: groupKey,
        latestGroupKeyRow: groupKey,
        currentReactionRow: null,
        localInstallationTransportPeerId: 'transport-bob-phone',
        verifiedNomination: nomination,
      );
      expect(eligible?.previewContext.groupName, 'Team Chat');
      expect(eligible?.previewContext.actorUsername, 'Alice');

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: {...group, 'is_muted': 1},
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: {...outgoingTarget, 'is_incoming': 1},
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: {
            ...outgoingTarget,
            'sender_peer_id': 'peer-bystander',
          },
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: {...groupKey, 'key_generation': 8},
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'a retained historical key cannot authorize a reaction card',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-revoked-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'account membership alone cannot authorize another install',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: <String, Object?>{
            ...localMember,
            'devices_json': jsonEncode(<Map<String, Object?>>[
              <String, Object?>{
                'deviceId': 'bob-phone',
                'transportPeerId': 'transport-bob-phone',
                'deviceSigningPublicKey': 'bob-device-key',
                'status': 'revoked',
                'revokedAt': '2026-07-12T09:02:00.000Z',
              },
            ]),
          },
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'a revoked local installation must fail closed',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: null,
        ),
        isNull,
        reason: 'the current install must be signed-nominated',
      );
    });

    test('completes without error for valid RemoteMessage', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox', 'peerId': '12D3KooW...'},
      );

      // Should not throw
      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'shows a fallback notification for routable data-only pushes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'msg-fallback-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.map((call) => call.method).toList(),
          containsAll(<String>[
            'initialize',
            'createNotificationChannel',
            'show',
          ]),
        );

        final channelCall = log.firstWhere(
          (call) => call.method == 'createNotificationChannel',
        );
        final channelArgs = channelCall.arguments as Map;
        expect(channelArgs['id'], mknoonMessagesChannelId);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Mknoon');
        expect(showArgs['body'], 'Message');
        expect(showArgs['payload'], '12D3KooWTestPeer');
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
        expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
        expect(
          platformSpecifics['channelDescription'],
          mknoonMessagesChannelDescription,
        );
        expect(platformSpecifics['playSound'], isTrue);
      },
    );

    test(
      'suppresses background fallback when account migration runtime gate blocks',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        final gateCalls = <String>[];
        debugSetBackgroundAccountMigrationNetworkGate(({
          String? peerId,
          required String operation,
        }) async {
          gateCalls.add(operation);
          return false;
        });

        const message = RemoteMessage(
          messageId: 'msg-migration-blocked-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(gateCalls, <String>['push_background_notification_display']);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'uses injected preview resolver before showing notification',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        debugSetBackgroundPushNotificationResolver((message) async {
          return const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Hello secret',
            payload: 'peer-alice',
          );
        });
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );

        const message = RemoteMessage(
          messageId: 'msg-decrypt-1',
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'msg-decrypt-1',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Alice');
        expect(showArgs['body'], 'Hello secret');
        expect(showArgs['payload'], 'peer-alice');
      },
    );

    test('suppresses a repeated background fallback for the same push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final gate = RecentBackgroundNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/background-fallback-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentBackgroundNotificationGate(gate);
      addTearDown(gate.clear);
      debugSetBackgroundDirectMessageLocalStateResolver(
        (message) async => _authorizedDirectMessageState(message),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            return null;
          });

      final message = RemoteMessage(
        messageId: 'msg-fallback-dedupe-1',
        sentTime: DateTime.utc(2026, 4, 4, 12),
        data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
      );

      await firebaseMessagingBackgroundHandler(message);
      await firebaseMessagingBackgroundHandler(message);

      expect(log.where((call) => call.method == 'show'), hasLength(1));
    });

    test('handles RemoteMessage with null messageId', () async {
      const message = RemoteMessage(data: {'type': 'inbox'});

      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with empty data map', () async {
      const message = RemoteMessage(messageId: 'msg-456');

      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'records a recent remote notification target even when FCM already carries a visible notification',
      () async {
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-handler-visible-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        const message = RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hey!'),
          data: {'type': 'new_message', 'sender_id': '12D3KooWVisiblePeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: '12D3KooWVisiblePeer',
          ),
          isTrue,
        );
      },
    );

    test(
      'GIRD-006 does not mark remote announcement when group fallback display fails',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-failure-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              if (call.method == 'show') {
                throw PlatformException(
                  code: 'display_failed',
                  message: 'blocked by OS notification state',
                );
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-fail',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-fail',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-fail',
            messageId: 'msg-gird006-display-fail',
          ),
          isFalse,
          reason:
              'A failed local fallback must not suppress the later listener notification.',
        );
      },
    );

    test(
      'suppresses group background fallback when display eligibility denies it',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async =>
              const PushFallbackNotificationDisplayEligibility.suppressed(
                'group_missing',
              ),
        );
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-group-display-denied-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-session03-denied',
          data: {
            'type': 'group_message',
            'groupId': 'group-session03',
            'message_id': 'msg-session03-denied',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-session03|message:msg-session03-denied',
            messageId: 'msg-session03-denied',
          ),
          isFalse,
        );
        final suppressionEvent = events.lastWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        );
        expect(
          suppressionEvent['details'],
          containsPair('reason', 'group_missing'),
        );
        expect(
          suppressionEvent['details'],
          containsPair(
            'payload',
            'group:group-session03|message:msg-session03-denied',
          ),
        );
      },
    );

    test('suppresses a muted group member end-to-end through the real fallback '
        'resolver and helper (reason "muted", no .show)', () async {
      // 04-P0 / SI-1 — Tier A regression lock (G-NM-1). Instead of stubbing
      // the outer eligibility seam with a hardcoded suppressed(...), this
      // drives the REAL resolveBackgroundPushFallbackDisplayEligibility with
      // the REAL groupMemberMessageDisplayEligibility helper (is_muted=1), so
      // the helper -> fallback-routing -> handler-suppression wiring AND the
      // literal 'muted' reason are locked end-to-end. A regression that
      // inverts the helper's mute check, or stops the fallback resolver from
      // routing a group_message to the group resolver, fails here while the
      // existing stubbed suppression tests would still pass. The encrypted-DB
      // glue (dbLoadGroup -> groupMemberMessageDisplayEligibility) is the
      // separate device Tier-B proof — the host VM cannot open the SQLCipher
      // identity.db.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (message) => resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              groupMemberMessageDisplayEligibility({'is_muted': 1}),
        ),
      );
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      final gate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/background-group-muted-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(gate.clear);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            return null;
          });

      const message = RemoteMessage(
        messageId: 'fcm-session03-muted',
        data: {
          'type': 'group_message',
          'groupId': 'group-session03-muted',
          'message_id': 'msg-session03-muted',
        },
      );

      await firebaseMessagingBackgroundHandler(message);

      expect(log.where((call) => call.method == 'show'), isEmpty);
      final suppressionEvent = events.lastWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
      );
      expect(suppressionEvent['details'], containsPair('reason', 'muted'));
    });

    test(
      'exact Android group claim replaces the recent-remote compatibility mark',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-success-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-success',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-success',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-success',
            messageId: 'msg-gird006-display-success',
          ),
          isFalse,
          reason:
              'the committed durable claim is the exact Android dedupe authority',
        );
      },
    );

    test(
      'GIRD-006 coalesces duplicate group background fallback by logical message id',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-transport-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
            'preview_unavailable': '1',
          },
        );
        const duplicateTransportMessage = RemoteMessage(
          messageId: 'fcm-gird006-transport-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        await firebaseMessagingBackgroundHandler(duplicateTransportMessage);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
      },
    );

    test(
      'shows iOS local fallback for chat pushes when Flutter surfaces only the data payload',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        IOSFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWVisiblePeer',
            'title': 'Alice',
            'body': 'Hey!',
            'message_id': 'msg-visible-chat-1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Mknoon');
        expect(showArgs['body'], 'Message');
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['presentSound'], isTrue);
        expect(platformSpecifics['presentAlert'], isTrue);
        expect(platformSpecifics['presentBadge'], isTrue);
      },
    );

    test(
      'rapid direct messages update one card with first audible and second silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        // A suspended burst of two distinct messages from the SAME sender.
        const first = RemoteMessage(
          messageId: 'm-burst-a',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerBurst',
            'message_id': 'direct-burst-a',
          },
        );
        const second = RemoteMessage(
          messageId: 'm-burst-b',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerBurst',
            'message_id': 'direct-burst-b',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        // Direct background notifications coalesce per conversation.
        expect(
          id0,
          deterministicConversationNotificationId('12D3KooWPeerBurst'),
        );
        expect(id1, id0);

        final ps0 = (shows[0].arguments as Map)['platformSpecifics'] as Map;
        final ps1 = (shows[1].arguments as Map)['platformSpecifics'] as Map;
        expect(ps0['channelId'], mknoonMessagesChannelId);
        expect(ps0['playSound'], isTrue);
        expect(ps1['playSound'], isFalse);
      },
    );

    test(
      'background group burst reuses one conversation card while the latest tap stays message-anchored',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const first = RemoteMessage(
          messageId: 'fcm-burst-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-a',
            'preview_unavailable': '1',
          },
        );
        const second = RemoteMessage(
          messageId: 'fcm-burst-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-b',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        expect(
          id0,
          deterministicConversationNotificationId('group:group-burst'),
        );
        expect(id1, id0);
        expect(
          (shows[0].arguments as Map)['payload'],
          'group:group-burst|message:gmsg-a',
        );
        expect(
          (shows[1].arguments as Map)['payload'],
          'group:group-burst|message:gmsg-b',
        );
        final secondPlatformSpecifics =
            (shows[1].arguments as Map)['platformSpecifics'] as Map;
        final firstPlatformSpecifics =
            (shows[0].arguments as Map)['platformSpecifics'] as Map;
        expect(firstPlatformSpecifics['playSound'], isTrue);
        expect(secondPlatformSpecifics['playSound'], isFalse);
        expect(
          secondPlatformSpecifics['channelId'],
          mknoonMessagesSilentChannelId,
        );
        expect(
          secondPlatformSpecifics['category'],
          AndroidNotificationCategory.message.name,
        );
      },
    );

    test(
      'different direct conversations remain independently audible',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final message in const <RemoteMessage>[
          RemoteMessage(
            data: {
              'type': 'new_message',
              'sender_id': 'peer-conversation-a',
              'message_id': 'different-conversation-a',
            },
          ),
          RemoteMessage(
            data: {
              'type': 'new_message',
              'sender_id': 'peer-conversation-b',
              'message_id': 'different-conversation-b',
            },
          ),
        ]) {
          await firebaseMessagingBackgroundHandler(message);
        }

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));
        expect(
          shows.map(
            (call) =>
                ((call.arguments as Map)['platformSpecifics']
                    as Map)['playSound'],
          ),
          everyElement(isTrue),
        );
        expect(
          shows.map((call) => (call.arguments as Map)['id']).toSet(),
          hasLength(2),
        );
      },
    );
  });

  // 04-P0 / SI-1 — the background (Android encrypted-DB) producer must honor
  // mute. The is_muted read is unit-tested via the pure `groups`-row helper so
  // it does not require a SQLCipher identity.db fixture.
  group('groupMemberMessageDisplayEligibility (background mute, 04-P0)', () {
    test('suppresses a muted group member with reason "muted"', () {
      final eligibility = groupMemberMessageDisplayEligibility({'is_muted': 1});
      expect(eligibility.shouldDisplay, isFalse);
      expect(eligibility.reason, 'muted');
    });

    test('allows an un-muted group member', () {
      final eligibility = groupMemberMessageDisplayEligibility({'is_muted': 0});
      expect(eligibility.shouldDisplay, isTrue);
      expect(eligibility.reason, 'current_member');
    });

    test('fails open (notifies) when the is_muted column is absent/null', () {
      expect(
        groupMemberMessageDisplayEligibility(<String, Object?>{}).shouldDisplay,
        isTrue,
      );
      expect(
        groupMemberMessageDisplayEligibility({'is_muted': null}).shouldDisplay,
        isTrue,
      );
    });
  });
}

BackgroundDirectMessageLocalState _authorizedDirectMessageState(
  RemoteMessage message,
) {
  final sender =
      message.data['sender_id']?.toString() ??
      message.data['senderId']?.toString() ??
      message.data['senderPeerId']?.toString() ??
      message.data['from']?.toString() ??
      'peer-test';
  final messageId =
      message.data['message_id']?.toString() ??
      message.data['messageId']?.toString();
  return BackgroundDirectMessageLocalState(
    previewContext: DirectMessageNotificationContext(
      senderPeerId: sender,
      senderUsername: null,
      expectedMessageId: messageId,
    ),
    mlKemSecretKeys: const <String>[],
  );
}

BackgroundGroupMessageLocalState _authorizedGroupMessageState(
  RemoteMessage message,
) {
  final groupId =
      message.data['groupId']?.toString() ??
      message.data['group_id']?.toString() ??
      'group-test';
  final messageId =
      message.data['message_id']?.toString() ??
      message.data['messageId']?.toString();
  return BackgroundGroupMessageLocalState(
    previewContext: GroupMessageNotificationContext(
      groupId: groupId,
      groupName: null,
      localPeerId: 'peer-local',
      senderPeerId: null,
      senderUsername: null,
      expectedMessageId: messageId,
    ),
    groupKey: null,
    keyEpoch: null,
  );
}

class _ThrowingToneReservationCoordinator extends DurableNotificationToneLease {
  _ThrowingToneReservationCoordinator(Directory directory)
    : super(directory: directory, pendingClaimWait: Duration.zero);

  @override
  Future<DurableNotificationToneReservation?> reserveTone(
    String conversationKey,
  ) async {
    throw const FileSystemException('tone storage unavailable');
  }
}

Future<void> _replaceBackgroundPendingToken(File file, String token) async {
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  decoded['token'] = token;
  await file.writeAsString(jsonEncode(decoded), flush: true);
}
