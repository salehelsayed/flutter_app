import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:path_provider/path_provider.dart';

const _kConfigFile = 'intro_e2e_config.json';
const _kExportFile = 'intro_e2e_identity.json';
const _kResultFile = 'intro_e2e_result.json';

typedef OpenConversationForIntroE2EFn = Future<bool> Function(String peerId);

Timer? _introE2EPoller;
bool _introE2ERunInFlight = false;

Future<void> exportIdentityForIntroE2E({
  required String signedQrPayloadJson,
  required String? mlKemPublicKey,
}) async {
  if (!kDebugMode) return;
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$_kExportFile');
  await file.writeAsString(
    jsonEncode({
      'qrPayload': signedQrPayloadJson,
      'mlKemPublicKey': mlKemPublicKey,
    }),
  );
}

Future<bool> prePopulateContactsFromIntroE2EConfig({
  required ContactRepository contactRepo,
}) async {
  if (!kDebugMode || !kE2ETestMode) return false;

  final config = await _loadConfig();
  if (config == null) return false;
  final contacts = config['add_contacts'];
  if (contacts is! List<dynamic> || contacts.isEmpty) {
    return false;
  }

  for (final contactData in contacts.cast<Map<String, dynamic>>()) {
    final qrJson = contactData['qrPayload'] as String;
    final mlKemPk = contactData['mlKemPublicKey'] as String?;
    final qrMap = jsonDecode(qrJson) as Map<String, dynamic>;
    if (mlKemPk != null) {
      qrMap['mlkem'] = mlKemPk;
    }
    final contact = ContactModel.fromQRPayload(qrMap);
    await addContact(repository: contactRepo, contact: contact);
  }
  return true;
}

Future<void> runIntroE2EActions({
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required IntroductionRepository introRepo,
  required MessageRepository messageRepo,
  OpenConversationForIntroE2EFn? openConversationByPeerId,
}) async {
  if (!kDebugMode || !kE2ETestMode) return;

  final config = await _loadConfig();
  if (config == null) return;

  final resultFile = await _resultFile();
  await resultFile.writeAsString(
    jsonEncode({'stepId': config['stepId'], 'status': 'running'}),
  );

  try {
    await _waitForP2PReady(p2pService);
    await p2pService.performImmediateHealthCheck();
    await p2pService.drainOfflineInbox();

    if (config['send_contact_requests_for_added_contacts'] == true) {
      await _sendContactRequestsForAddedContacts(
        config: config,
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        contactRepo: contactRepo,
      );
    }

    final contactDelayMs =
        (config['contact_settle_delay_ms'] as num?)?.toInt() ?? 0;
    if (contactDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: contactDelayMs));
    }

    await _runContactRequestAction(
      action: (config['contact_request_action'] as String?) ?? 'none',
      bridge: bridge,
      p2pService: p2pService,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      contactRequestRepo: contactRequestRepo,
      messageRepo: messageRepo,
    );

    final nodeActionResult = await _runNodeActionBeforeIntroPhase(
      action: (config['node_action_before_intro_phase'] as String?) ?? 'none',
      p2pService: p2pService,
    );
    final nodeActionSettleDelayMs =
        (config['node_action_settle_delay_ms'] as num?)?.toInt() ?? 0;
    if (nodeActionSettleDelayMs > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: nodeActionSettleDelayMs),
      );
    }

    await _runIntroductionSends(
      config: config,
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      identityRepo: identityRepo,
      messageRepo: messageRepo,
    );

    final introDelayMs =
        (config['introduction_settle_delay_ms'] as num?)?.toInt() ?? 0;
    if (introDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: introDelayMs));
    }

    final introActionResult = await _runIntroductionAction(
      action: (config['introduction_action'] as String?) ?? 'none',
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      identityRepo: identityRepo,
      messageRepo: messageRepo,
      pollCycles: (config['poll_cycles'] as num?)?.toInt() ?? 25,
      pollIntervalMs: (config['poll_interval_ms'] as num?)?.toInt() ?? 1000,
      idleCyclesAfterSeen:
          (config['idle_cycles_after_seen'] as num?)?.toInt() ?? 3,
    );

    final chatActionResult = await _runChatMessageSends(
      config: config,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      messageRepo: messageRepo,
    );

    final chatSettleDelayMs =
        (config['chat_settle_delay_ms'] as num?)?.toInt() ?? 0;
    if (chatSettleDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: chatSettleDelayMs));
    }

    final chatExpectationResult = await _waitForExpectedChatMessages(
      config: config,
      messageRepo: messageRepo,
      p2pService: p2pService,
    );

    final uiNavigation = await _openConversationIfRequested(
      config: config,
      openConversationByPeerId: openConversationByPeerId,
    );

    final snapshot = await _collectSnapshot(
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      contactRequestRepo: contactRequestRepo,
      introRepo: introRepo,
      messageRepo: messageRepo,
    );
    await resultFile.writeAsString(
      jsonEncode({
        'stepId': config['stepId'],
        'status': 'complete',
        'success': true,
        'nodeAction': nodeActionResult,
        'introAction': introActionResult,
        'chatAction': chatActionResult,
        'chatExpectations': chatExpectationResult,
        'uiNavigation': uiNavigation,
        'snapshot': snapshot,
      }),
    );
  } catch (e, stackTrace) {
    final snapshot = await _collectSnapshot(
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      contactRequestRepo: contactRequestRepo,
      introRepo: introRepo,
      messageRepo: messageRepo,
    );
    await resultFile.writeAsString(
      jsonEncode({
        'stepId': config['stepId'],
        'status': 'failed',
        'success': false,
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
        'snapshot': snapshot,
      }),
    );
  } finally {
    await _deleteConfigIfPresent();
  }
}

void startIntroE2EPoller({
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required IntroductionRepository introRepo,
  required MessageRepository messageRepo,
  OpenConversationForIntroE2EFn? openConversationByPeerId,
  Duration initialDelay = const Duration(seconds: 2),
  Duration pollInterval = const Duration(seconds: 3),
}) {
  if (!kDebugMode || !kE2ETestMode) return;
  if (_introE2EPoller != null) return;

  Future<void> tick() async {
    if (_introE2ERunInFlight) return;
    _introE2ERunInFlight = true;
    try {
      final config = await _loadConfig();
      if (config == null) return;

      await runIntroE2EActions(
        p2pService: p2pService,
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: contactRequestRepo,
        introRepo: introRepo,
        messageRepo: messageRepo,
        openConversationByPeerId: openConversationByPeerId,
      );
    } finally {
      _introE2ERunInFlight = false;
    }
  }

  Timer(initialDelay, () {
    unawaited(tick());
  });
  _introE2EPoller = Timer.periodic(pollInterval, (_) {
    unawaited(tick());
  });
}

Future<Map<String, dynamic>?> _openConversationIfRequested({
  required Map<String, dynamic> config,
  OpenConversationForIntroE2EFn? openConversationByPeerId,
}) async {
  final requestedPeerId = (config['open_conversation_with_peer_id'] as String?)
      ?.trim();
  if (requestedPeerId == null || requestedPeerId.isEmpty) {
    return null;
  }
  if (openConversationByPeerId == null) {
    throw StateError(
      'Conversation opener missing for intro E2E peer $requestedPeerId',
    );
  }

  final opened = await openConversationByPeerId(requestedPeerId);
  if (!opened) {
    throw StateError(
      'Failed to open intro E2E conversation for $requestedPeerId',
    );
  }

  final postNavigationDelayMs =
      (config['post_navigation_delay_ms'] as num?)?.toInt() ?? 1500;
  if (postNavigationDelayMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: postNavigationDelayMs));
  }

  return {'requestedPeerId': requestedPeerId, 'opened': true};
}

Future<Map<String, dynamic>?> _loadConfig() async {
  final file = await _configFile();
  if (!await file.exists()) return null;
  final decoded = jsonDecode(await file.readAsString());
  return Map<String, dynamic>.from(decoded as Map);
}

Future<void> _deleteConfigIfPresent() async {
  final file = await _configFile();
  if (await file.exists()) {
    await file.delete();
  }
}

Future<File> _configFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_kConfigFile');
}

Future<File> _resultFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_kResultFile');
}

bool _hasUsableTransportForIntroE2E(P2PService p2pService) {
  final state = p2pService.currentState;
  if (!state.isStarted) {
    return false;
  }

  // The three-simulator harness can converge over either relay-backed
  // transport or same-host local discovery. Waiting only for relay circuits
  // blocks valid local-direct runs when the relay stays in recovering state.
  return state.circuitAddresses.isNotEmpty ||
      state.relayState == 'online' ||
      state.listenAddresses.isNotEmpty;
}

Future<void> _waitForP2PReady(P2PService p2pService) async {
  for (var i = 0; i < 90; i++) {
    if (_hasUsableTransportForIntroE2E(p2pService)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('P2P node did not expose a usable transport in time');
}

Future<void> _sendContactRequestsForAddedContacts({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required ContactRepository contactRepo,
}) async {
  final contacts = config['add_contacts'];
  if (contacts is! List<dynamic>) return;

  for (final contactData in contacts.cast<Map<String, dynamic>>()) {
    final qrJson = contactData['qrPayload'] as String;
    final qrMap = jsonDecode(qrJson) as Map<String, dynamic>;
    final peerId = qrMap['ns'] as String;
    final publicKey = qrMap['pk'] as String;
    SendContactRequestResult result = SendContactRequestResult.sendFailed;
    for (var attempt = 0; attempt < 8; attempt++) {
      result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: peerId,
        recipientPublicKey: publicKey,
      );
      if (result == SendContactRequestResult.success) {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (result != SendContactRequestResult.success) {
      throw StateError(
        'Contact request to $peerId failed in intro E2E: $result',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _runContactRequestAction({
  required String action,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required MessageRepository messageRepo,
}) async {
  if (action != 'accept_all') return;

  var sawAny = false;
  var idleAfterSeen = 0;
  for (var tick = 0; tick < 25; tick++) {
    await p2pService.drainOfflineInbox();
    final pendingRequests = await contactRequestRepo.getPendingRequests();
    if (pendingRequests.isNotEmpty) {
      sawAny = true;
      idleAfterSeen = 0;
    } else if (sawAny) {
      idleAfterSeen++;
      if (idleAfterSeen >= 3) {
        break;
      }
    }
    for (final request in pendingRequests) {
      await acceptAndReciprocateContactRequest(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        peerId: request.peerId,
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        onProfileDownloaded: (_) {},
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _runIntroductionSends({
  required Map<String, dynamic> config,
  required ContactRepository contactRepo,
  required IntroductionRepository introRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required MessageRepository messageRepo,
}) async {
  final sendPlans = config['send_introductions'];
  if (sendPlans is! List<dynamic> || sendPlans.isEmpty) return;

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('Identity missing for intro E2E send');
  }

  for (final plan in sendPlans.cast<Map<String, dynamic>>()) {
    final recipientPeerId = plan['recipientPeerId'] as String;
    final introducedPeerIds = (plan['friendPeerIds'] as List<dynamic>)
        .cast<String>()
        .toList(growable: false);
    final recipient = await contactRepo.getContact(recipientPeerId);
    if (recipient == null) {
      throw StateError('Recipient contact $recipientPeerId missing');
    }
    final friends = <ContactModel>[];
    for (final peerId in introducedPeerIds) {
      final friend = await contactRepo.getContact(peerId);
      if (friend == null) {
        throw StateError('Introduced contact $peerId missing');
      }
      friends.add(friend);
    }
    await sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      introducerPeerId: identity.peerId,
      introducerUsername: identity.username,
      recipientPeerId: recipient.peerId,
      recipientUsername: recipient.username,
      recipientMlKemPublicKey: recipient.mlKemPublicKey,
      friendsToIntroduce: friends,
    );
    await insertIntroSystemMessage(
      messageRepo: messageRepo,
      contactPeerId: recipient.peerId,
      text: formatIntroducerIntroductionSystemMessage(
        recipientUsername: recipient.username,
        introducedUsernames: friends
            .map((friend) => friend.username)
            .toList(growable: false),
      ),
      ownPeerId: identity.peerId,
    );
  }
}

Future<Map<String, dynamic>?> _runNodeActionBeforeIntroPhase({
  required String action,
  required P2PService p2pService,
}) async {
  switch (action) {
    case 'none':
      return null;
    case 'stop_node':
      final stopped = await p2pService.stopNode();
      if (!stopped) {
        throw StateError('Failed to stop node for intro E2E');
      }
      return {'action': action, 'stopped': true};
  }

  throw StateError('Unknown intro E2E node action: $action');
}

Future<Map<String, dynamic>> _runIntroductionAction({
  required String action,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required MessageRepository messageRepo,
  required int pollCycles,
  required int pollIntervalMs,
  required int idleCyclesAfterSeen,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('Identity missing for intro E2E action');
  }

  final actedOn = <String>[];
  var dropped = 0;
  var sawAny = false;
  var idleAfterSeen = 0;
  for (var tick = 0; tick < pollCycles; tick++) {
    await p2pService.drainOfflineInbox();
    final pending = await introRepo.getPendingIntroductionsForUser(
      identity.peerId,
    );
    if (pending.isNotEmpty) {
      sawAny = true;
      idleAfterSeen = 0;
    } else if (sawAny) {
      idleAfterSeen++;
      if (idleAfterSeen >= idleCyclesAfterSeen) {
        break;
      }
    }
    for (final intro in pending) {
      if (actedOn.contains(intro.id)) {
        continue;
      }

      switch (action) {
        case 'accept_all':
          await acceptIntroduction(
            introRepo: introRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            introductionId: intro.id,
            ownPeerId: identity.peerId,
            ownUsername: identity.username,
            messageRepo: messageRepo,
          );
          actedOn.add(intro.id);
          break;
        case 'pass_all':
          await passIntroduction(
            introRepo: introRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            introductionId: intro.id,
            ownPeerId: identity.peerId,
            ownUsername: identity.username,
          );
          actedOn.add(intro.id);
          break;
        case 'drop_first':
          await introRepo.deleteIntroduction(intro.id);
          actedOn.add(intro.id);
          dropped++;
          return {'action': action, 'actedOn': actedOn, 'dropped': dropped};
        case 'none':
          break;
      }
    }
    await Future<void>.delayed(Duration(milliseconds: pollIntervalMs));
  }

  return {'action': action, 'actedOn': actedOn, 'dropped': dropped};
}

Future<Map<String, dynamic>?> _runChatMessageSends({
  required Map<String, dynamic> config,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required MessageRepository messageRepo,
}) async {
  final sendPlans = config['send_chat_messages'];
  if (sendPlans is! List<dynamic> || sendPlans.isEmpty) {
    return null;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('Identity missing for intro E2E chat send');
  }

  final sent = <Map<String, dynamic>>[];
  for (final plan in sendPlans.cast<Map<String, dynamic>>()) {
    final targetPeerId = plan['targetPeerId'] as String;
    final text = plan['text'] as String;
    final recipient = await contactRepo.getContact(targetPeerId);
    if (recipient == null) {
      throw StateError('Chat target contact $targetPeerId missing');
    }

    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      bridge: bridge,
      recipientMlKemPublicKey: recipient.mlKemPublicKey,
    );
    if (result != SendChatMessageResult.success || message == null) {
      throw StateError(
        'Intro E2E chat send to $targetPeerId failed with $result',
      );
    }

    sent.add({
      'targetPeerId': targetPeerId,
      'text': text,
      'messageId': message.id,
      'transport': message.transport,
      'status': message.status,
    });
  }

  return {'sent': sent};
}

Future<Map<String, dynamic>?> _waitForExpectedChatMessages({
  required Map<String, dynamic> config,
  required MessageRepository messageRepo,
  required P2PService p2pService,
}) async {
  final expectations = config['expected_chat_messages'];
  if (expectations is! List<dynamic> || expectations.isEmpty) {
    return null;
  }

  final pending = expectations
      .cast<Map<String, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList(growable: true);
  final matched = <Map<String, dynamic>>[];
  final pollCycles = (config['chat_poll_cycles'] as num?)?.toInt() ?? 20;
  final pollIntervalMs =
      (config['chat_poll_interval_ms'] as num?)?.toInt() ?? 500;

  for (var tick = 0; tick < pollCycles; tick++) {
    await p2pService.drainOfflineInbox();

    for (var i = pending.length - 1; i >= 0; i--) {
      final expectation = pending[i];
      final contactPeerId = expectation['contactPeerId'] as String;
      final messages = await messageRepo.getMessagesForContact(contactPeerId);
      ConversationMessage? match;
      for (final message in messages) {
        if (_messageMatchesExpectation(message, expectation)) {
          match = message;
          break;
        }
      }
      if (match == null) {
        continue;
      }

      matched.add({
        'contactPeerId': contactPeerId,
        'text': match.text,
        'messageId': match.id,
        'isIncoming': match.isIncoming,
        'transport': match.transport,
        'status': match.status,
      });
      pending.removeAt(i);
    }

    if (pending.isEmpty) {
      return {'matched': matched, 'pending': const []};
    }

    await Future<void>.delayed(Duration(milliseconds: pollIntervalMs));
  }

  throw StateError(
    'Timed out waiting for intro E2E chat expectations: $pending',
  );
}

bool _messageMatchesExpectation(
  ConversationMessage message,
  Map<String, dynamic> expectation,
) {
  if (message.transport == 'system' || message.isDeleted || message.isHidden) {
    return false;
  }
  if (message.text != expectation['text']) {
    return false;
  }
  final expectedIncoming = expectation['isIncoming'];
  if (expectedIncoming is bool && message.isIncoming != expectedIncoming) {
    return false;
  }
  final expectedStatus = expectation['status'];
  if (expectedStatus is String && expectedStatus.isNotEmpty) {
    return message.status == expectedStatus;
  }
  return true;
}

Future<Map<String, dynamic>> _collectSnapshot({
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required IntroductionRepository introRepo,
  required MessageRepository messageRepo,
}) async {
  final identity = await identityRepo.loadIdentity();
  final contacts = await contactRepo.getAllContacts();
  final pendingRequests = await contactRequestRepo.getPendingRequests();
  final introductions = identity == null
      ? const <IntroductionModel>[]
      : [
          ...await introRepo.getIntroductionsByIntroducer(identity.peerId),
          ...await introRepo.getIntroductionsByRecipient(identity.peerId),
          ...await introRepo.getIntroductionsByIntroduced(identity.peerId),
        ];

  final introMap = <String, IntroductionModel>{};
  for (final intro in introductions) {
    introMap[intro.id] = intro;
  }

  final retryableOutbox = await introRepo.loadRetryableOutboxDeliveries(
    olderThan: Duration.zero,
    limit: 100,
  );

  final conversationPeerIds = <String>{
    ...contacts.map((contact) => contact.peerId),
  };
  if (identity != null) {
    for (final intro in introMap.values) {
      if (intro.introducerId != identity.peerId) {
        conversationPeerIds.add(intro.introducerId);
      }
      if (intro.recipientId != identity.peerId) {
        conversationPeerIds.add(intro.recipientId);
      }
      if (intro.introducedId != identity.peerId) {
        conversationPeerIds.add(intro.introducedId);
      }
    }
  }

  final systemMessages = <Map<String, dynamic>>[];
  final chatMessages = <Map<String, dynamic>>[];
  final sortedPeerIds = conversationPeerIds.toList()..sort();
  for (final peerId in sortedPeerIds) {
    final messages = await messageRepo.getMessagesForContact(peerId);
    final visibleSystemMessages = messages
        .where((message) => message.transport == 'system')
        .map(
          (message) => {
            'text': message.text,
            'timestamp': message.timestamp,
            'isIncoming': message.isIncoming,
          },
        )
        .toList(growable: false);
    if (visibleSystemMessages.isNotEmpty) {
      systemMessages.add({
        'contactPeerId': peerId,
        'messages': visibleSystemMessages,
      });
    }

    final visibleChatMessages = messages
        .where(
          (message) =>
              message.transport != 'system' &&
              !message.isDeleted &&
              !message.isHidden,
        )
        .map(
          (message) => {
            'id': message.id,
            'text': message.text,
            'timestamp': message.timestamp,
            'isIncoming': message.isIncoming,
            'status': message.status,
            'transport': message.transport,
          },
        )
        .toList(growable: false);
    if (visibleChatMessages.isNotEmpty) {
      chatMessages.add({
        'contactPeerId': peerId,
        'messages': visibleChatMessages,
      });
    }
  }

  return {
    'identity': identity == null
        ? null
        : {'peerId': identity.peerId, 'username': identity.username},
    'contacts': contacts
        .map(
          (contact) => {
            'peerId': contact.peerId,
            'username': contact.username,
            'introducedByPeerId': contact.introducedByPeerId,
          },
        )
        .toList(growable: false),
    'pendingContactRequests': pendingRequests
        .map(
          (request) => {
            'peerId': request.peerId,
            'username': request.username,
            'status': request.status.name,
          },
        )
        .toList(growable: false),
    'introductions': introMap.values
        .map(
          (intro) => {
            'id': intro.id,
            'introducerId': intro.introducerId,
            'recipientId': intro.recipientId,
            'introducedId': intro.introducedId,
            'recipientStatus': intro.recipientStatus.toDbString(),
            'introducedStatus': intro.introducedStatus.toDbString(),
            'overallStatus': intro.status.toDbString(),
          },
        )
        .toList(growable: false),
    'introOutboxDeliveries': retryableOutbox
        .map(
          (delivery) => {
            'deliveryId': delivery.deliveryId,
            'introductionId': delivery.introductionId,
            'targetPeerId': delivery.targetPeerId,
            'status': delivery.deliveryStatus,
            'path': delivery.deliveryPath,
            'lastError': delivery.lastError,
          },
        )
        .toList(growable: false),
    'systemMessages': systemMessages,
    'chatMessages': chatMessages,
  };
}
