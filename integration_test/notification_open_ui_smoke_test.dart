import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:integration_test/integration_test.dart';

enum _HarnessScreen { home, conversation, intros, group }

class _NotificationOpenHarnessApp extends StatefulWidget {
  const _NotificationOpenHarnessApp();

  @override
  State<_NotificationOpenHarnessApp> createState() =>
      _NotificationOpenHarnessAppState();
}

class _NotificationOpenHarnessAppState
    extends State<_NotificationOpenHarnessApp> {
  static const _peerAlice = 'peer-alice';
  static const _groupWeekend = 'grp-weekend';

  final List<String> _events = <String>[];
  final Map<String, List<String>> _pendingConversationMessages =
      <String, List<String>>{
        _peerAlice: <String>['Hello from Alice', 'Offline backlog caught up'],
      };
  final Map<String, List<String>> _visibleConversationMessages =
      <String, List<String>>{};
  final Map<String, List<String>> _pendingGroupMessages =
      <String, List<String>>{
        _groupWeekend: <String>['Alice: brunch at 10?'],
      };
  final Map<String, List<String>> _visibleGroupMessages =
      <String, List<String>>{};
  final List<String> _pendingIntros = <String>[
    'Weekend Crew invite from Alice',
  ];

  _HarnessScreen _screen = _HarnessScreen.home;
  String? _activePeerId;
  String? _activeGroupId;
  List<String> _visibleIntros = <String>[];
  int _clearCount = 0;

  Future<void> _clearDeliveredNotifications() async {
    setState(() {
      _clearCount += 1;
      _events.add('clear');
    });
  }

  Future<void> _prepare(NotificationRouteTarget routeTarget) async {
    setState(() {
      _events.add('prepare:${routeTarget.toPayload()}');
    });

    final result = await prepareNotificationOpen(
      routeTarget: routeTarget,
      drainOfflineInbox: () async {
        setState(() {
          _events.add('drain:inbox');
          switch (routeTarget.kind) {
            case NotificationRouteTargetKind.conversation:
              final peerId = routeTarget.peerId;
              if (peerId != null) {
                _visibleConversationMessages[peerId] = List<String>.from(
                  _pendingConversationMessages[peerId] ?? const <String>[],
                );
              }
              break;
            case NotificationRouteTargetKind.contactRequest:
            case NotificationRouteTargetKind.intros:
              _visibleIntros = List<String>.from(_pendingIntros);
              break;
            case NotificationRouteTargetKind.group:
            case NotificationRouteTargetKind.post:
            case NotificationRouteTargetKind.postComment:
              break;
          }
        });
      },
      drainGroupOfflineInboxForGroup: (groupId) async {
        setState(() {
          _events.add('drain:group:$groupId');
          _visibleGroupMessages[groupId] = List<String>.from(
            _pendingGroupMessages[groupId] ?? const <String>[],
          );
        });
      },
    );

    if (!result.ok) {
      setState(() {
        _events.add('prepare-error:${result.error}');
      });
    }
  }

  Future<void> _route(NotificationRouteTarget routeTarget) async {
    setState(() {
      _events.add('route:${routeTarget.toPayload()}');
      switch (routeTarget.kind) {
        case NotificationRouteTargetKind.conversation:
          _activePeerId = routeTarget.peerId;
          _screen = _HarnessScreen.conversation;
          break;
        case NotificationRouteTargetKind.contactRequest:
        case NotificationRouteTargetKind.intros:
          _screen = _HarnessScreen.intros;
          break;
        case NotificationRouteTargetKind.group:
          _activeGroupId = routeTarget.groupId;
          _screen = _HarnessScreen.group;
          break;
        case NotificationRouteTargetKind.post:
        case NotificationRouteTargetKind.postComment:
          _screen = _HarnessScreen.home;
          break;
      }
    });
  }

  Future<void> _missingRouteTarget() async {
    setState(() {
      _events.add('missing');
    });
  }

  Future<void> _simulateWarmRemoteChatTap() async {
    await routeAppRootRemoteNotificationOpen(
      data: const <String, dynamic>{
        'type': 'new_message',
        'sender_id': _peerAlice,
      },
      onBeforeOpen: _clearDeliveredNotifications,
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: _missingRouteTarget,
    );
  }

  Future<void> _simulateColdRemoteChatTap() async {
    await _clearDeliveredNotifications();
    await routeInitialRemoteNotificationOpen(
      getInitialMessage: () async => const RemoteMessage(
        data: <String, dynamic>{'type': 'new_message', 'sender_id': _peerAlice},
      ),
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: _missingRouteTarget,
    );
  }

  Future<void> _simulateWarmGroupInviteTap() async {
    await routeAppRootRemoteNotificationOpen(
      data: const <String, dynamic>{
        'type': 'group_invite',
        'groupId': _groupWeekend,
      },
      onBeforeOpen: _clearDeliveredNotifications,
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: _missingRouteTarget,
    );
  }

  Future<void> _simulateWarmLocalChatTap() async {
    await routeAppRootLocalNotificationTap(
      payload: _peerAlice,
      onBeforeOpen: _clearDeliveredNotifications,
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
    );
  }

  void _goHome() {
    setState(() {
      _screen = _HarnessScreen.home;
      _activePeerId = null;
      _activeGroupId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Notification Open Smoke')),
        body: switch (_screen) {
          _HarnessScreen.home => _buildHome(),
          _HarnessScreen.conversation => _buildConversation(),
          _HarnessScreen.intros => _buildIntros(),
          _HarnessScreen.group => _buildGroup(),
        },
      ),
    );
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Notification-open smoke harness',
          key: Key('home-title'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          key: const Key('warm-remote-chat-button'),
          onPressed: _simulateWarmRemoteChatTap,
          child: const Text('Simulate Warm Remote Chat Tap'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('cold-remote-chat-button'),
          onPressed: _simulateColdRemoteChatTap,
          child: const Text('Simulate Cold Remote Chat Open'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('warm-group-invite-button'),
          onPressed: _simulateWarmGroupInviteTap,
          child: const Text('Simulate Warm Group Invite Tap'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('warm-local-chat-button'),
          onPressed: _simulateWarmLocalChatTap,
          child: const Text('Simulate Warm Local Chat Tap'),
        ),
        const SizedBox(height: 16),
        _buildEventSummary(),
      ],
    );
  }

  Widget _buildConversation() {
    final peerId = _activePeerId ?? '';
    final messages = _visibleConversationMessages[peerId] ?? const <String>[];
    return ListView(
      key: const Key('conversation-screen'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Conversation: $peerId',
          key: const Key('conversation-title'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildEventSummary(),
        const SizedBox(height: 12),
        for (final message in messages) Text(message),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('back-home-button'),
          onPressed: _goHome,
          child: const Text('Back Home'),
        ),
      ],
    );
  }

  Widget _buildIntros() {
    return ListView(
      key: const Key('intros-screen'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Intros',
          key: Key('intros-title'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildEventSummary(),
        const SizedBox(height: 12),
        for (final intro in _visibleIntros) Text(intro),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('intros-back-home-button'),
          onPressed: _goHome,
          child: const Text('Back Home'),
        ),
      ],
    );
  }

  Widget _buildGroup() {
    final groupId = _activeGroupId ?? '';
    final messages = _visibleGroupMessages[groupId] ?? const <String>[];
    return ListView(
      key: const Key('group-screen'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Group: $groupId',
          key: const Key('group-title'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildEventSummary(),
        const SizedBox(height: 12),
        for (final message in messages) Text(message),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('group-back-home-button'),
          onPressed: _goHome,
          child: const Text('Back Home'),
        ),
      ],
    );
  }

  Widget _buildEventSummary() {
    final eventSummary = _events.isEmpty ? 'none' : _events.join(' > ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Clear count: $_clearCount', key: const Key('clear-count')),
        const SizedBox(height: 8),
        Text('Events: $eventSummary', key: const Key('event-log')),
      ],
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('warm remote chat tap renders backlog before route completes', (
    tester,
  ) async {
    await tester.pumpWidget(const _NotificationOpenHarnessApp());

    await tester.tap(find.byKey(const Key('warm-remote-chat-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-screen')), findsOneWidget);
    expect(find.text('Conversation: peer-alice'), findsOneWidget);
    expect(find.text('Hello from Alice'), findsOneWidget);
    expect(find.text('Offline backlog caught up'), findsOneWidget);
    expect(
      find.textContaining(
        'clear > prepare:peer-alice > drain:inbox > route:peer-alice',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('back-home-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-title')), findsOneWidget);
  });

  testWidgets('cold remote chat open still renders conversation messages', (
    tester,
  ) async {
    await tester.pumpWidget(const _NotificationOpenHarnessApp());

    await tester.tap(find.byKey(const Key('cold-remote-chat-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-screen')), findsOneWidget);
    expect(find.text('Conversation: peer-alice'), findsOneWidget);
    expect(find.text('Hello from Alice'), findsOneWidget);
    expect(
      find.textContaining(
        'clear > prepare:peer-alice > drain:inbox > route:peer-alice',
      ),
      findsOneWidget,
    );
  });

  testWidgets('group invite tap lands on intros surface with invite visible', (
    tester,
  ) async {
    await tester.pumpWidget(const _NotificationOpenHarnessApp());

    await tester.tap(find.byKey(const Key('warm-group-invite-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('intros-screen')), findsOneWidget);
    expect(find.text('Weekend Crew invite from Alice'), findsOneWidget);
    expect(
      find.textContaining(
        'clear > prepare:intros > drain:inbox > route:intros',
      ),
      findsOneWidget,
    );
  });

  testWidgets('warm local chat tap uses the same prepare-then-route flow', (
    tester,
  ) async {
    await tester.pumpWidget(const _NotificationOpenHarnessApp());

    await tester.tap(find.byKey(const Key('warm-local-chat-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-screen')), findsOneWidget);
    expect(find.text('Hello from Alice'), findsOneWidget);
    expect(
      find.textContaining(
        'clear > prepare:peer-alice > drain:inbox > route:peer-alice',
      ),
      findsOneWidget,
    );
  });
}
