import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core/services/fake_p2p_service.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

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

class _HarnessReactionRepository implements ReactionRepository {
  final Map<String, List<MessageReaction>> _reactionsByMessageId =
      <String, List<MessageReaction>>{};

  Future<void> replaceForMessageIds(
    Iterable<String> messageIds,
    Iterable<MessageReaction> reactions,
  ) async {
    for (final messageId in messageIds.toSet()) {
      _reactionsByMessageId.remove(messageId);
    }
    for (final reaction in reactions) {
      await saveReaction(reaction);
    }
  }

  @override
  Future<void> saveReaction(MessageReaction reaction) async {
    final reactions = List<MessageReaction>.from(
      _reactionsByMessageId[reaction.messageId] ?? const <MessageReaction>[],
    )..removeWhere((item) => item.senderPeerId == reaction.senderPeerId);
    reactions.add(reaction);
    reactions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _reactionsByMessageId[reaction.messageId] = reactions;
  }

  @override
  Future<List<MessageReaction>> getReactionsForMessage(String messageId) async {
    return List<MessageReaction>.from(
      _reactionsByMessageId[messageId] ?? const <MessageReaction>[],
    );
  }

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  ) async {
    final result = <String, List<MessageReaction>>{};
    for (final messageId in messageIds) {
      final reactions = await getReactionsForMessage(messageId);
      if (reactions.isNotEmpty) {
        result[messageId] = reactions;
      }
    }
    return result;
  }

  @override
  Future<int> removeReaction(String messageId, String senderPeerId) async {
    final reactions = _reactionsByMessageId[messageId];
    if (reactions == null) {
      return 0;
    }
    final before = reactions.length;
    reactions.removeWhere((item) => item.senderPeerId == senderPeerId);
    if (reactions.isEmpty) {
      _reactionsByMessageId.remove(messageId);
    }
    return before - reactions.length;
  }

  @override
  Future<int> deleteReactionsForMessage(String messageId) async {
    final removed = _reactionsByMessageId.remove(messageId);
    return removed?.length ?? 0;
  }

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async => 0;
}

class _ConversationFixture {
  final List<ConversationMessage> messages;
  final List<MessageReaction> reactions;

  const _ConversationFixture({
    required this.messages,
    this.reactions = const <MessageReaction>[],
  });
}

class _StateAwareConversationHarnessModel {
  static const selfPeerId = 'peer-self';
  static const peerAlice = 'peer-alice';

  _StateAwareConversationHarnessModel()
    : identity = IdentityModel(
        peerId: selfPeerId,
        publicKey: 'pk-self',
        privateKey: 'sk-self',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-pk-self',
        mlKemSecretKey: 'mlkem-sk-self',
        username: 'Alice',
        createdAt: '2026-04-10T09:00:00.000Z',
        updatedAt: '2026-04-10T09:00:00.000Z',
      ),
      contact = ContactModel(
        peerId: peerAlice,
        publicKey: 'pk-peer-alice',
        rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-alice',
        username: 'Bob',
        signature: 'sig-peer-alice',
        scannedAt: '2026-04-10T09:00:00.000Z',
        mlKemPublicKey: 'mlkem-pk-peer-alice',
      ) {
    identityRepo.seed(identity);
    contactRepo.addTestContact(contact);
  }

  final IdentityModel identity;
  final ContactModel contact;
  final FakeIdentityRepository identityRepo = FakeIdentityRepository();
  final InMemoryContactRepository contactRepo = InMemoryContactRepository();
  final InMemoryMessageRepository messageRepo = InMemoryMessageRepository();
  final _HarnessReactionRepository reactionRepo = _HarnessReactionRepository();
  final FakeP2PService p2pService = FakeP2PService();
  final Map<String, _ConversationFixture> _pendingFixtures =
      <String, _ConversationFixture>{};

  ChatMessageListener buildChatMessageListener() {
    return ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
    );
  }

  void setPendingFixture(String peerId, _ConversationFixture fixture) {
    _pendingFixtures[peerId] = fixture;
  }

  Future<void> preloadFixture(
    String peerId,
    _ConversationFixture fixture,
  ) async {
    await _replaceStoredFixture(peerId, fixture);
  }

  Future<void> drainPendingFixture(String peerId) async {
    final fixture = _pendingFixtures[peerId];
    if (fixture == null) {
      return;
    }
    await _replaceStoredFixture(peerId, fixture);
  }

  Future<void> _replaceStoredFixture(
    String peerId,
    _ConversationFixture fixture,
  ) async {
    final existingMessages = await messageRepo.getMessagesForContact(peerId);
    final replaceIds = <String>{
      ...existingMessages.map((message) => message.id),
      ...fixture.messages.map((message) => message.id),
    };

    await messageRepo.deleteMessagesForContact(peerId);
    await reactionRepo.replaceForMessageIds(replaceIds, fixture.reactions);
    for (final message in fixture.messages) {
      await messageRepo.saveMessage(message);
    }
  }

  void dispose() {}
}

enum _StateAwareScreen { home, conversation }

class _StateAwareConversationHarnessApp extends StatefulWidget {
  const _StateAwareConversationHarnessApp({super.key, required this.model});

  final _StateAwareConversationHarnessModel model;

  @override
  State<_StateAwareConversationHarnessApp> createState() =>
      _StateAwareConversationHarnessAppState();
}

class _StateAwareConversationHarnessAppState
    extends State<_StateAwareConversationHarnessApp> {
  final List<String> events = <String>[];
  _StateAwareScreen _screen = _StateAwareScreen.home;
  String? _activePeerId;
  int _clearCount = 0;
  int _routeVersion = 0;

  Future<void> _clearDeliveredNotifications() async {
    setState(() {
      _clearCount += 1;
      events.add('clear');
    });
  }

  Future<void> _prepare(NotificationRouteTarget routeTarget) async {
    setState(() {
      events.add('prepare:${routeTarget.toPayload()}');
    });

    final result = await prepareNotificationOpen(
      routeTarget: routeTarget,
      drainOfflineInbox: () async {
        setState(() {
          events.add('drain:conversation');
        });
        final peerId = routeTarget.peerId;
        if (peerId != null) {
          await widget.model.drainPendingFixture(peerId);
        }
      },
      drainGroupOfflineInboxForGroup: (_) async {},
    );

    if (!result.ok) {
      setState(() {
        events.add('prepare-error:${result.error}');
      });
    }
  }

  Future<void> _route(NotificationRouteTarget routeTarget) async {
    setState(() {
      events.add('route:${routeTarget.toPayload()}');
      _activePeerId = routeTarget.peerId;
      _routeVersion += 1;
      _screen = _StateAwareScreen.conversation;
    });
  }

  Future<void> simulateWarmRemoteConversationOpen() async {
    await routeAppRootRemoteNotificationOpen(
      data: const <String, dynamic>{
        'type': 'new_message',
        'sender_id': _StateAwareConversationHarnessModel.peerAlice,
      },
      onBeforeOpen: _clearDeliveredNotifications,
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: () async {
        setState(() {
          events.add('missing');
        });
      },
    );
  }

  Future<void> simulateColdRemoteConversationOpen() async {
    await _clearDeliveredNotifications();
    await routeInitialRemoteNotificationOpen(
      getInitialMessage: () async => const RemoteMessage(
        data: <String, dynamic>{
          'type': 'new_message',
          'sender_id': _StateAwareConversationHarnessModel.peerAlice,
        },
      ),
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
      onMissingRouteTarget: () async {
        setState(() {
          events.add('missing');
        });
      },
    );
  }

  Future<void> simulateWarmLocalConversationOpen() async {
    await routeAppRootLocalNotificationTap(
      payload: _StateAwareConversationHarnessModel.peerAlice,
      onBeforeOpen: _clearDeliveredNotifications,
      onBeforeRouteTarget: _prepare,
      onRouteTarget: _route,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: switch (_screen) {
        _StateAwareScreen.home => Scaffold(
          appBar: AppBar(title: const Text('State-Aware Notification Open')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text(
                'State-aware notification-open harness',
                key: Key('state-aware-home-title'),
              ),
              Text(
                'Clear count: $_clearCount',
                key: const Key('state-clear-count'),
              ),
              Text(
                'Events: ${events.isEmpty ? 'none' : events.join(' > ')}',
                key: const Key('state-event-log'),
              ),
            ],
          ),
        ),
        _StateAwareScreen.conversation => ConversationWired(
          key: ValueKey(
            'state-aware-conversation-${_activePeerId ?? 'missing'}-$_routeVersion',
          ),
          contact: widget.model.contact,
          identityRepo: widget.model.identityRepo,
          messageRepo: widget.model.messageRepo,
          chatMessageListener: widget.model.buildChatMessageListener(),
          p2pService: widget.model.p2pService,
          contactRepo: widget.model.contactRepo,
          reactionRepo: widget.model.reactionRepo,
        ),
      },
    );
  }
}

ConversationMessage _makeMessage({
  required String id,
  required String text,
  required String timestamp,
  bool isIncoming = true,
  String? quotedMessageId,
  String? editedAt,
  String? deletedAt,
  String? deletedByPeerId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: _StateAwareConversationHarnessModel.peerAlice,
    senderPeerId: isIncoming
        ? _StateAwareConversationHarnessModel.peerAlice
        : _StateAwareConversationHarnessModel.selfPeerId,
    text: text,
    timestamp: timestamp,
    status: isIncoming ? 'read' : 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
    quotedMessageId: quotedMessageId,
    editedAt: editedAt,
    deletedAt: deletedAt,
    deletedByPeerId: deletedByPeerId,
  );
}

MessageReaction _makeReaction({
  required String id,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String timestamp,
}) {
  return MessageReaction(
    id: id,
    messageId: messageId,
    emoji: emoji,
    senderPeerId: senderPeerId,
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

Future<void> _pumpUntilReadableConversationFrame(
  WidgetTester tester, {
  required bool Function() ready,
  List<String> forbiddenTexts = const <String>[],
  int maxFrames = 120,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    for (final text in forbiddenTexts) {
      expect(
        find.text(text),
        findsNothing,
        reason: 'forbidden stale text surfaced before the first readable frame',
      );
    }
    if (ready()) {
      return;
    }
    await tester.pump(step);
  }

  for (final text in forbiddenTexts) {
    expect(find.text(text), findsNothing);
  }
  expect(
    ready(),
    isTrue,
    reason: 'conversation never reached a readable frame',
  );
}

_ConversationFixture _deletedOriginalFixture(String originalText) {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'delete-target',
        text: originalText,
        timestamp: '2026-04-10T09:01:00.000Z',
      ),
    ],
  );
}

_ConversationFixture _deletedTombstoneFixture() {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'delete-target',
        text: '',
        timestamp: '2026-04-10T09:01:00.000Z',
        deletedAt: '2026-04-10T09:02:00.000Z',
        deletedByPeerId: _StateAwareConversationHarnessModel.selfPeerId,
      ),
    ],
  );
}

_ConversationFixture _backgroundPreOpenFixture() {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'bg-edit-target',
        text: 'Original background text',
        timestamp: '2026-04-10T09:10:00.000Z',
      ),
      _makeMessage(
        id: 'bg-delete-target',
        text: 'Delete me from background',
        timestamp: '2026-04-10T09:11:00.000Z',
      ),
    ],
  );
}

_ConversationFixture _backgroundUpdatedFixture() {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'bg-edit-target',
        text: 'Edited while backgrounded',
        timestamp: '2026-04-10T09:10:00.000Z',
        editedAt: '2026-04-10T09:12:00.000Z',
      ),
      _makeMessage(
        id: 'bg-delete-target',
        text: '',
        timestamp: '2026-04-10T09:11:00.000Z',
        deletedAt: '2026-04-10T09:13:00.000Z',
        deletedByPeerId: _StateAwareConversationHarnessModel.selfPeerId,
      ),
    ],
  );
}

_ConversationFixture _restartPreRelaunchFixture() {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'restart-parent',
        text: 'Quote source before restart',
        timestamp: '2026-02-09T15:30:00.000Z',
      ),
      _makeMessage(
        id: 'restart-edited',
        text: 'Editable before restart',
        timestamp: '2026-02-09T15:31:00.000Z',
        isIncoming: false,
      ),
      _makeMessage(
        id: 'restart-deleted',
        text: 'Delete me after restart',
        timestamp: '2026-02-09T15:32:00.000Z',
      ),
    ],
  );
}

_ConversationFixture _restartPostRelaunchFixture() {
  return _ConversationFixture(
    messages: <ConversationMessage>[
      _makeMessage(
        id: 'restart-parent',
        text: 'Quote source before restart',
        timestamp: '2026-02-09T15:30:00.000Z',
      ),
      _makeMessage(
        id: 'restart-edited',
        text: 'Edited after restart',
        timestamp: '2026-02-09T15:31:00.000Z',
        isIncoming: false,
        editedAt: '2026-02-09T15:40:00.000Z',
      ),
      _makeMessage(
        id: 'restart-deleted',
        text: '',
        timestamp: '2026-02-09T15:32:00.000Z',
        deletedAt: '2026-02-09T15:41:00.000Z',
        deletedByPeerId: _StateAwareConversationHarnessModel.peerAlice,
      ),
      _makeMessage(
        id: 'restart-reply',
        text: 'Reply restored after restart',
        timestamp: '2026-02-09T15:42:00.000Z',
        isIncoming: false,
        quotedMessageId: 'restart-parent',
      ),
    ],
    reactions: <MessageReaction>[
      _makeReaction(
        id: 'restart-reaction-1',
        messageId: 'restart-reply',
        emoji: '🔥',
        senderPeerId: _StateAwareConversationHarnessModel.peerAlice,
        timestamp: '2026-02-09T15:43:00.000Z',
      ),
    ],
  );
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

  testWidgets(
    'cold remote open applies a pre-open delete before the first readable conversation frame',
    (tester) async {
      final model = _StateAwareConversationHarnessModel();
      addTearDown(model.dispose);

      await model.preloadFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _deletedOriginalFixture('Delete before cold open'),
      );
      model.setPendingFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _deletedTombstoneFixture(),
      );

      final key = GlobalKey<_StateAwareConversationHarnessAppState>();
      await tester.pumpWidget(
        _StateAwareConversationHarnessApp(key: key, model: model),
      );
      await tester.pump();

      await key.currentState!.simulateColdRemoteConversationOpen();
      await tester.pump();
      await _pumpUntilReadableConversationFrame(
        tester,
        ready: () =>
            find.text('This message was deleted').evaluate().isNotEmpty,
        forbiddenTexts: const <String>['Delete before cold open'],
      );

      expect(key.currentState!.events, <String>[
        'clear',
        'prepare:peer-alice',
        'drain:conversation',
        'route:peer-alice',
      ]);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('Delete before cold open'), findsNothing);
    },
  );

  testWidgets(
    'warm local notification open after delete never surfaces the original body inside the app shell',
    (tester) async {
      final model = _StateAwareConversationHarnessModel();
      addTearDown(model.dispose);

      await model.preloadFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _deletedOriginalFixture('Delete before local open'),
      );
      model.setPendingFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _deletedTombstoneFixture(),
      );

      final key = GlobalKey<_StateAwareConversationHarnessAppState>();
      await tester.pumpWidget(
        _StateAwareConversationHarnessApp(key: key, model: model),
      );
      await tester.pump();

      await key.currentState!.simulateWarmLocalConversationOpen();
      await tester.pump();
      await _pumpUntilReadableConversationFrame(
        tester,
        ready: () =>
            find.text('This message was deleted').evaluate().isNotEmpty,
        forbiddenTexts: const <String>['Delete before local open'],
      );

      expect(key.currentState!.events, <String>[
        'clear',
        'prepare:peer-alice',
        'drain:conversation',
        'route:peer-alice',
      ]);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('Delete before local open'), findsNothing);
    },
  );

  testWidgets(
    'warm remote open after background edit and delete shows only the latest stored state on first render',
    (tester) async {
      final model = _StateAwareConversationHarnessModel();
      addTearDown(model.dispose);

      await model.preloadFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _backgroundPreOpenFixture(),
      );
      model.setPendingFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _backgroundUpdatedFixture(),
      );

      final key = GlobalKey<_StateAwareConversationHarnessAppState>();
      await tester.pumpWidget(
        _StateAwareConversationHarnessApp(key: key, model: model),
      );
      await tester.pump();

      await key.currentState!.simulateWarmRemoteConversationOpen();
      await tester.pump();
      await _pumpUntilReadableConversationFrame(
        tester,
        ready: () =>
            find.text('Edited while backgrounded').evaluate().isNotEmpty &&
            find.text('This message was deleted').evaluate().isNotEmpty &&
            find.text('(edited)').evaluate().isNotEmpty,
        forbiddenTexts: const <String>[
          'Original background text',
          'Delete me from background',
        ],
      );

      expect(key.currentState!.events, <String>[
        'clear',
        'prepare:peer-alice',
        'drain:conversation',
        'route:peer-alice',
      ]);
      expect(find.text('Edited while backgrounded'), findsOneWidget);
      expect(find.text('(edited)'), findsOneWidget);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('Original background text'), findsNothing);
      expect(find.text('Delete me from background'), findsNothing);
    },
  );

  testWidgets(
    'relaunch open rebuilds stored quote edit delete and reaction state without stale pre-restart UI',
    (tester) async {
      final model = _StateAwareConversationHarnessModel();
      addTearDown(model.dispose);

      await model.preloadFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _restartPreRelaunchFixture(),
      );

      final initialKey = GlobalKey<_StateAwareConversationHarnessAppState>();
      await tester.pumpWidget(
        _StateAwareConversationHarnessApp(key: initialKey, model: model),
      );
      await tester.pump();

      await initialKey.currentState!.simulateWarmLocalConversationOpen();
      await tester.pump();
      await _pumpUntilReadableConversationFrame(
        tester,
        ready: () =>
            find.text('Editable before restart').evaluate().isNotEmpty &&
            find.text('Delete me after restart').evaluate().isNotEmpty,
      );

      expect(find.text('Reply restored after restart'), findsNothing);
      expect(find.text('(edited)'), findsNothing);
      expect(find.text('This message was deleted'), findsNothing);
      expect(find.text('🔥'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await model.preloadFixture(
        _StateAwareConversationHarnessModel.peerAlice,
        _restartPostRelaunchFixture(),
      );

      final relaunchKey = GlobalKey<_StateAwareConversationHarnessAppState>();
      await tester.pumpWidget(
        _StateAwareConversationHarnessApp(key: relaunchKey, model: model),
      );
      await tester.pump();

      await relaunchKey.currentState!.simulateWarmLocalConversationOpen();
      await tester.pump();
      await _pumpUntilReadableConversationFrame(
        tester,
        ready: () =>
            find.text('Edited after restart').evaluate().isNotEmpty &&
            find.text('Reply restored after restart').evaluate().isNotEmpty &&
            find.text('This message was deleted').evaluate().isNotEmpty &&
            find.text('🔥').evaluate().isNotEmpty,
        forbiddenTexts: const <String>[
          'Editable before restart',
          'Delete me after restart',
        ],
      );

      expect(relaunchKey.currentState!.events, <String>[
        'clear',
        'prepare:peer-alice',
        'drain:conversation',
        'route:peer-alice',
      ]);
      expect(find.text('Edited after restart'), findsOneWidget);
      expect(find.text('Reply restored after restart'), findsOneWidget);
      expect(find.text('Quote source before restart'), findsWidgets);
      expect(find.text('(edited)'), findsOneWidget);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('Editable before restart'), findsNothing);
      expect(find.text('Delete me after restart'), findsNothing);
    },
  );
}
