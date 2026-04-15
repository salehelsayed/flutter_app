/// Simulator Benchmark: Notification Tap to Message Visible
///
/// Measures the routed notification-open path on one simulator. The transport
/// layer is not involved here; the metric is the app-shell prepare/drain/route
/// flow plus the first readable conversation frame.
@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core/services/fake_p2p_service.dart';
import '../test/features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';
import 'benchmark_helpers.dart';

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
      originalDebugPrint(message, wrapWidth: wrapWidth);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }
  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map((line) {
        final json = line.substring('[FLOW] '.length);
        return jsonDecode(json) as Map<String, dynamic>;
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _filterEvents(
  List<Map<String, dynamic>> events,
  String eventName,
) => events.where((event) => event['event'] == eventName).toList();

ConversationMessage _buildMessage({
  required String id,
  required String text,
  required String timestamp,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: _NotificationBenchmarkModel.peerId,
    senderPeerId: _NotificationBenchmarkModel.peerId,
    text: text,
    timestamp: timestamp,
    status: 'read',
    isIncoming: true,
    createdAt: timestamp,
  );
}

class _NotificationBenchmarkModel {
  static const selfPeerId = 'peer-self';
  static const peerId = 'peer-notification-bench';

  _NotificationBenchmarkModel()
    : identity = IdentityModel(
        peerId: selfPeerId,
        publicKey: 'pk-self',
        privateKey: 'sk-self',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-pk-self',
        mlKemSecretKey: 'mlkem-sk-self',
        username: 'Bench Self',
        createdAt: '2026-04-15T08:00:00.000Z',
        updatedAt: '2026-04-15T08:00:00.000Z',
      ),
      contact = ContactModel(
        peerId: peerId,
        publicKey: 'pk-peer',
        rendezvous:
            '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-notification-bench',
        username: 'Bench Alice',
        signature: 'sig-peer',
        scannedAt: '2026-04-15T08:00:00.000Z',
        mlKemPublicKey: 'mlkem-pk-peer',
      ) {
    identityRepo.seed(identity);
    contactRepo.addTestContact(contact);
  }

  final IdentityModel identity;
  final ContactModel contact;
  final FakeIdentityRepository identityRepo = FakeIdentityRepository();
  final InMemoryContactRepository contactRepo = InMemoryContactRepository();
  final InMemoryMessageRepository messageRepo = InMemoryMessageRepository();
  final FakeReactionRepository reactionRepo = FakeReactionRepository();
  final FakeP2PService p2pService = FakeP2PService();
  List<ConversationMessage> _pendingMessages = const <ConversationMessage>[];

  ChatMessageListener buildChatMessageListener() {
    return ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
    );
  }

  void setPendingMessages(List<ConversationMessage> messages) {
    _pendingMessages = List<ConversationMessage>.from(messages);
  }

  Future<void> drainPendingMessages() async {
    await messageRepo.deleteMessagesForContact(peerId);
    for (final message in _pendingMessages) {
      await messageRepo.saveMessage(message);
    }
  }

  void dispose() {}
}

enum _HarnessScreen { home, conversation }

class _NotificationBenchmarkApp extends StatefulWidget {
  const _NotificationBenchmarkApp({super.key, required this.model});

  final _NotificationBenchmarkModel model;

  @override
  State<_NotificationBenchmarkApp> createState() =>
      _NotificationBenchmarkAppState();
}

class _NotificationBenchmarkAppState extends State<_NotificationBenchmarkApp> {
  _HarnessScreen _screen = _HarnessScreen.home;
  int _routeVersion = 0;
  DateTime? _notificationTappedAt;

  Future<void> _prepare(NotificationRouteTarget routeTarget) async {
    await prepareNotificationOpen(
      routeTarget: routeTarget,
      drainOfflineInbox: () => widget.model.drainPendingMessages(),
      drainGroupOfflineInboxForGroup: (_) async {},
    );
  }

  Future<void> _route(NotificationRouteTarget routeTarget) async {
    setState(() {
      _routeVersion += 1;
      _screen = _HarnessScreen.conversation;
    });
  }

  Future<void> simulateColdConversationOpen() async {
    _notificationTappedAt = DateTime.now();
    await routeInitialRemoteNotificationOpen(
      getInitialMessage: () async => const RemoteMessage(
        data: <String, dynamic>{
          'type': 'new_message',
          'sender_id': _NotificationBenchmarkModel.peerId,
        },
      ),
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: () async {},
    );
  }

  Future<void> simulateWarmConversationOpen() async {
    _notificationTappedAt = DateTime.now();
    await routeAppRootRemoteNotificationOpen(
      data: const <String, dynamic>{
        'type': 'new_message',
        'sender_id': _NotificationBenchmarkModel.peerId,
      },
      onBeforeOpen: () async {},
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: () async {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: switch (_screen) {
        _HarnessScreen.home => const Scaffold(
          body: Center(
            child: Text(
              'Notification benchmark home',
              key: Key('notification-benchmark-home'),
            ),
          ),
        ),
        _HarnessScreen.conversation => ConversationWired(
          key: ValueKey('notification-bench-conversation-$_routeVersion'),
          contact: widget.model.contact,
          identityRepo: widget.model.identityRepo,
          messageRepo: widget.model.messageRepo,
          chatMessageListener: widget.model.buildChatMessageListener(),
          p2pService: widget.model.p2pService,
          contactRepo: widget.model.contactRepo,
          reactionRepo: widget.model.reactionRepo,
          notificationTappedAt: _notificationTappedAt,
        ),
      },
    );
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  String text, {
  int maxFrames = 180,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(find.text(text), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('N1: Notification tap cold (app killed)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: NOTIFICATION TAP — COLD OPEN (N1)');
    print('${'═' * 60}\n');

    final model = _NotificationBenchmarkModel();
    addTearDown(model.dispose);
    model.setPendingMessages([
      _buildMessage(
        id: 'notif-cold-1',
        text: 'Cold notification hello',
        timestamp: '2026-04-15T08:01:00.000Z',
      ),
    ]);

    final key = GlobalKey<_NotificationBenchmarkAppState>();
    await tester.pumpWidget(_NotificationBenchmarkApp(key: key, model: model));
    await tester.pump();

    final events = await _captureFlowEvents(() async {
      await key.currentState!.simulateColdConversationOpen();
      await tester.pump();
      await _pumpUntilVisible(tester, 'Cold notification hello');
    });

    final timings = _filterEvents(events, 'NOTIFICATION_TAP_TO_MESSAGE_TIMING');
    expect(timings, isNotEmpty, reason: 'Cold open should emit timing');
    final details = timings.first['details'] as Map<String, dynamic>;
    printBenchmarkSingle(
      'sim_notification_tap_cold_ms',
      details['elapsedMs'] as int,
    );
    print(
      '[BENCHMARK] sim_notification_tap_cold_route_kind = '
      '${details['routeKind']}',
    );
  });

  testWidgets('N2: Notification tap warm (app backgrounded)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: NOTIFICATION TAP — WARM OPEN (N2)');
    print('${'═' * 60}\n');

    final model = _NotificationBenchmarkModel();
    addTearDown(model.dispose);
    model.setPendingMessages([
      _buildMessage(
        id: 'notif-warm-1',
        text: 'Warm notification hello',
        timestamp: '2026-04-15T08:02:00.000Z',
      ),
    ]);

    final key = GlobalKey<_NotificationBenchmarkAppState>();
    await tester.pumpWidget(_NotificationBenchmarkApp(key: key, model: model));
    await tester.pump();

    final events = await _captureFlowEvents(() async {
      await key.currentState!.simulateWarmConversationOpen();
      await tester.pump();
      await _pumpUntilVisible(tester, 'Warm notification hello');
    });

    final timings = _filterEvents(events, 'NOTIFICATION_TAP_TO_MESSAGE_TIMING');
    expect(timings, isNotEmpty, reason: 'Warm open should emit timing');
    final details = timings.first['details'] as Map<String, dynamic>;
    printBenchmarkSingle(
      'sim_notification_tap_warm_ms',
      details['elapsedMs'] as int,
    );
    print(
      '[BENCHMARK] sim_notification_tap_warm_route_kind = '
      '${details['routeKind']}',
    );
  });
}
