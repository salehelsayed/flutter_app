// Isolated physical-device seam: Appium/Maestro control callback completion;
// production registry, ledger, flock and native admission owners do the work.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';

void main() => runApp(const MaterialApp(home: NotificationLockFixture()));

class NotificationLockFixture extends StatefulWidget {
  const NotificationLockFixture({super.key});
  @override
  State<NotificationLockFixture> createState() => _FixtureState();
}

class _FixtureState extends State<NotificationLockFixture> {
  static const channel = MethodChannel('com.mknoon/go_bridge');
  final plugin = FlutterLocalNotificationsPlugin();
  final binding = 'v1:${'a' * 64}';
  final correlation = 'c' * 64;
  final identity = AppVisibilityConversationIdentity.tryParse(
    lane: AppVisibilityConversationLane.direct,
    value: 'fixture-peer',
  )!;
  late Directory directory;
  late DurableConversationNotificationIdRegistry registry;
  late LocalNotificationLedgerStore store;
  int? notificationId;
  int effects = 0;
  int repairs = 0;
  String result = 'initializing';
  String phase = 'unknown';
  String lock = 'unknown';
  String native = 'unknown';
  String seed = 'unknown';
  int grants = -1;
  bool ready = false;
  Completer<void>? callback;
  Future<void>? operation;
  Duration clockOffset = Duration.zero;
  DateTime now() => DateTime.now().toUtc().add(clockOffset);
  File get effectsFile => File('${directory.parent.path}/fixture-effects.json');

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    directory = Directory(
      await channel.invokeMethod<String>('fixtureDirectory') ??
          (throw StateError('fixture directory unavailable')),
    );
    await directory.create(recursive: true);
    store = LocalNotificationLedgerStore(directory: directory, nowUtc: now);
    registry = DurableConversationNotificationIdRegistry(
      directory: directory,
      localNotificationEffectCoordinator:
          DurableLocalNotificationEffectCoordinator(
            ledgerStore: store,
            nowUtc: now,
          ),
    );
    await plugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (await effectsFile.exists()) {
      final retained = jsonDecode(await effectsFile.readAsString()) as Map;
      effects = retained['effects'] as int;
      repairs = retained['repairs'] as int;
    }
    await channel.invokeMethod('fixtureAdmission', true);
    notificationId = await registry.resolve(
      'fixture-peer',
      activeNotificationIds: () async =>
          (await plugin.getActiveNotifications()).map((entry) => entry.id),
    );
    await store.initializeOrRebind(currentOpaqueBinding: binding);
    ready = true;
    result = 'ready';
    await probe();
  }

  DurableLocalNotificationEffectContext effectContext(
    String event,
    String? pause,
  ) => DurableLocalNotificationEffectContext(
    currentOpaqueBinding: binding,
    eventCorrelation: event,
    conversationDigest: identity.digest,
    producerKind: LocalNotificationProducerKind.directMessage,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    readFinalCanonicalDisposition: () async {
      if (pause == 'canonical') {
        result = 'canonical pending';
        await probe();
        await callback!.future;
      }
      return DurableLocalNotificationCanonicalDisposition.eligible;
    },
  );
  Future<DurableLocalNotificationEffectResult> run(
    String event,
    String? pause, {
    bool seedOnly = false,
  }) => registry.runFinalEffect(
    context: effectContext(event, pause),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: identity,
    conversationKey: 'fixture-peer',
    notificationId: notificationId!,
    metadata: ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.message,
      eventIdentity: event,
      generation: 'ledger:$event',
    ),
    retireCurrent: () => plugin.cancel(notificationId!),
    publishNative: () async {
      if (seedOnly) return;
      await publish(false);
      if (pause == 'native') {
        result = 'native pending';
        await probe();
        await callback!.future;
      }
    },
    publishNativeSilently: () => publish(true),
    activeNotificationIds: () async =>
        (await plugin.getActiveNotifications()).map((entry) => entry.id),
  );
  Future<void> publish(bool repair) async {
    await plugin.show(
      notificationId!,
      'Lock fixture',
      'Isolated notification',
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
      ),
      payload: 'fixture',
    );
    if (repair) {
      repairs++;
    } else {
      effects++;
    }
    await effectsFile.writeAsString(
      jsonEncode({'effects': effects, 'repairs': repairs}),
      flush: true,
    );
  }

  Future<void> reset() async {
    if (operation != null) {
      throw StateError('complete the owned operation first');
    }
    await channel.invokeMethod('fixtureAdmission', true);
    await plugin.cancelAll();
    directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
    effects = 0;
    repairs = 0;
    clockOffset = Duration.zero;
    await effectsFile.writeAsString(
      jsonEncode({'effects': 0, 'repairs': 0}),
      flush: true,
    );
    notificationId = await registry.resolve(
      'fixture-peer',
      activeNotificationIds: () async => <Object?>[],
    );
    await store.initializeOrRebind(currentOpaqueBinding: binding);
    final receipt = (await run('b' * 64, null, seedOnly: true)).receipt!;
    await registry.settleSqlReadyEffect(
      currentOpaqueBinding: binding,
      eventCorrelation: receipt.eventCorrelation,
      expectedRevision: receipt.recordRevision,
    );
    result = 'reset';
    await probe();
  }

  void start(String? pause) {
    if (operation != null) return;
    callback = pause == null ? null : Completer<void>();
    result = 'running';
    operation = () async {
      try {
        final effect = await run(correlation, pause);
        final receipt = effect.receipt;
        if (receipt != null) {
          await registry.settleSqlReadyEffect(
            currentOpaqueBinding: binding,
            eventCorrelation: receipt.eventCorrelation,
            expectedRevision: receipt.recordRevision,
          );
        }
        result = effect.disposition.name;
      } catch (error) {
        result = 'retryable ${error.runtimeType}';
      } finally {
        operation = null;
        callback = null;
        await probe();
      }
    }();
    setState(() {});
  }

  Future<void> probe() async {
    final snapshot = await channel.invokeMapMethod<String, Object>(
      'fixtureProbe',
      '${directory.path}/.coordination.lock',
    );
    lock = snapshot?['lockFree'] == true ? 'FREE' : 'HELD';
    native = snapshot?['nativeEntryPermitted'] == true
        ? 'AVAILABLE'
        : 'BLOCKED';
    grants = snapshot?['grants'] as int? ?? -1;
    if (store.ledgerFile.existsSync()) {
      final envelope = jsonDecode(store.ledgerFile.readAsStringSync()) as Map;
      final records = envelope['records'] as Map;
      phase =
          (records[correlation] as Map?)?['effectPhase'] as String? ?? 'NONE';
      seed = (records['b' * 64] as Map?)?['effectPhase'] == 'SETTLED'
          ? 'RETAINED'
          : 'MISSING';
    }
    if (mounted) setState(() {});
  }

  Widget button(String title, VoidCallback action) =>
      ElevatedButton(onPressed: ready ? action : null, child: Text(title));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notification lock fixture')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Result: $result'),
        Text('Phase: $phase'),
        Text('Lock: $lock'),
        Text('Native: $native'),
        Text('Grants: $grants'),
        Text('Effects: $effects'),
        Text('Repairs: $repairs'),
        Text('Seed: $seed'),
        button('Reset fixture', () => reset()),
        button(
          'Allow notifications',
          () => plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()!
              .requestPermissions(alert: true),
        ),
        button('Start canonical wait', () => start('canonical')),
        button('Start native wait', () => start('native')),
        button('Complete callback', () {
          callback?.complete();
        }),
        button('Refuse admission', () async {
          await channel.invokeMethod('fixtureAdmission', false);
          await probe();
        }),
        button('Allow admission', () async {
          await channel.invokeMethod('fixtureAdmission', true);
          await probe();
        }),
        button('Probe lock', () => probe()),
        button('Replay event', () => start(null)),
        button('Recover after restart', () {
          clockOffset = const Duration(seconds: 66);
          start(null);
        }),
      ],
    ),
  );
}

class _BackgroundVisibility extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 8,
    lifecycleGeneration: 12,
  );
}
