import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../domain/repositories/fake_message_repository.dart';

const _retryUnackedPath =
    'lib/features/conversation/application/retry_unacked_messages_use_case.dart';
const _retryFailedPath =
    'lib/features/conversation/application/retry_failed_messages_use_case.dart';
const _retryUploadsPath =
    'lib/features/conversation/application/retry_incomplete_uploads_use_case.dart';
const _deletePath =
    'lib/features/conversation/application/delete_message_use_case.dart';
const _pausePath = 'lib/core/lifecycle/handle_app_paused.dart';
const _conversationPath =
    'lib/features/conversation/presentation/screens/conversation_wired.dart';
const _feedPath = 'lib/features/feed/presentation/screens/feed_wired.dart';
const _bootstrapPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _custodyLossPath =
    'lib/features/conversation/application/verify_inbox_custody_use_case.dart';

ConversationMessage _outgoing({
  required String id,
  required String status,
  String envelope = '{"type":"chat_message","version":"2","encrypted":{}}',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-target',
    senderPeerId: 'my-peer-id',
    text: 'atomic writer proof',
    timestamp: '2026-08-05T00:00:00.000Z',
    status: status,
    isIncoming: false,
    createdAt: '2026-08-05T00:00:00.000Z',
    wireEnvelope: envelope,
  );
}

Future<void> _winDelivery(
  FakeMessageRepository repository,
  ConversationMessage attempted, {
  required OutgoingOrdinarySettlementMode mode,
  required String transport,
}) async {
  final outcome = await repository.settleOutgoingOrdinaryTransport(
    messageId: attempted.id,
    expectedContactPeerId: attempted.contactPeerId,
    expectedEnvelope: attempted.wireEnvelope,
    status: 'delivered',
    transport: transport,
    relayExpiresAt: null,
    mode: mode,
  );
  expect(outcome.outcome, OutgoingOrdinaryMutationOutcome.applied);
}

void _expectFirstDeliveryFrozen(
  ConversationMessage? message, {
  required String transport,
}) {
  expect(message, isNotNull);
  expect(message!.status, 'delivered');
  expect(message.transport, transport);
  expect(message.wireEnvelope, isNull);
  expect(message.relayExpiresAt, isNull);
  expect(message.custodyCheckedAt, isNull);
}

final class _MessageRepositoryWithoutOrdinaryCapability
    implements MessageRepository {
  _MessageRepositoryWithoutOrdinaryCapability(
    Iterable<ConversationMessage> messages,
  ) : _messages = <String, ConversationMessage>{
        for (final message in messages) message.id: message,
      };

  final Map<String, ConversationMessage> _messages;
  int saveMessageCallCount = 0;
  int updateMessageStatusCallCount = 0;
  int conditionalTransitionCallCount = 0;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saveMessageCallCount++;
    _messages[message.id] = message;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    updateMessageStatusCallCount++;
    final current = _messages[id];
    if (current != null) _messages[id] = current.copyWith(status: status);
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async => _messages[id];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => _messages.values
      .where(
        (message) =>
            !message.isIncoming &&
            message.status == 'sent' &&
            (message.wireEnvelope?.isNotEmpty ?? false),
      )
      .toList(growable: false);

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async =>
      _messages.values
          .where((message) => !message.isIncoming && message.status == 'failed')
          .toList(growable: false);

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async =>
      _messages.values
          .where(
            (message) => !message.isIncoming && message.status == 'sending',
          )
          .toList(growable: false);

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    conditionalTransitionCallCount++;
    final current = _messages[id];
    if (current == null || current.status != fromStatus) return 0;
    _messages[id] = current.copyWith(status: toStatus);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _expectNoTransportFallback(FakeP2PService p2pService) {
  expect(
    <int>[
      p2pService.storeInInboxCallCount,
      p2pService.sendMessageCallCount,
      p2pService.sendMessageWithReplyCallCount,
      p2pService.discoverPeerCallCount,
      p2pService.dialPeerCallCount,
      p2pService.warmPeerCallCount,
      p2pService.sendLocalMediaCallCount,
    ],
    everyElement(0),
    reason: 'missing ordinary authority must fail before transport work',
  );
}

final class _PauseBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final command = jsonDecode(message) as Map<String, dynamic>;
    switch (command['cmd']) {
      case 'bg:begin':
        commandLog.add('bg:begin');
        return '336';
      case 'bg:end':
        commandLog.add('bg:end');
        return jsonEncode(<String, Object?>{'ok': true});
      default:
        return super.send(message);
    }
  }
}

CompilationUnit _unit(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return parseString(content: file.readAsStringSync(), path: path).unit;
}

String _topLevelFunctionBody(String path, String name) {
  final declaration = _unit(path).declarations
      .whereType<FunctionDeclaration>()
      .singleWhere((candidate) => candidate.name.lexeme == name);
  return declaration.functionExpression.body.toSource();
}

String _methodBody(String path, String className, String methodName) {
  final declaration = _unit(path).declarations
      .whereType<ClassDeclaration>()
      .singleWhere((candidate) => candidate.name.lexeme == className);
  return declaration.members
      .whereType<MethodDeclaration>()
      .singleWhere((candidate) => candidate.name.lexeme == methodName)
      .body
      .toSource();
}

int _count(String source, String token) => token.allMatches(source).length;

final class _InstanceCreationCollector extends RecursiveAstVisitor<void> {
  final creations = <InstanceCreationExpression>[];
  final invocations = <MethodInvocation>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    creations.add(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    invocations.add(node);
    super.visitMethodInvocation(node);
  }
}

String _singleConstruction(String path, String typeName) {
  final collector = _InstanceCreationCollector();
  _unit(path).accept(collector);
  final matches = <AstNode>[
    ...collector.creations.where(
      (creation) => creation.constructorName.type.toSource() == typeName,
    ),
    ...collector.invocations.where(
      (invocation) =>
          invocation.target == null && invocation.methodName.name == typeName,
    ),
  ];
  expect(matches, hasLength(1), reason: '$typeName must be constructed once');
  return matches.single.toSource();
}

void main() {
  test(
    'retry and pause custody writers preserve a concurrent delivered row',
    () async {
      final unacked = _outgoing(id: 'writer-unacked', status: 'sent');
      final unackedRepo = FakeMessageRepository()
        ..seed(<ConversationMessage>[unacked])
        ..unackedOutgoingOverride = <ConversationMessage>[unacked];
      final unackedP2p =
          FakeP2PService(
              initialState: const NodeState(
                isStarted: true,
                peerId: 'my-peer-id',
              ),
            )
            ..onStoreInInbox = (_, _, {int? timeoutMs}) async {
              await _winDelivery(
                unackedRepo,
                unacked,
                mode: OutgoingOrdinarySettlementMode.receipt,
                transport: 'relay',
              );
              return true;
            };

      expect(
        await retryUnackedMessages(
          messageRepo: unackedRepo,
          p2pService: unackedP2p,
          olderThan: Duration.zero,
        ),
        0,
      );
      _expectFirstDeliveryFrozen(
        await unackedRepo.getMessage(unacked.id),
        transport: 'relay',
      );
      expect(unackedRepo.saveMessageCallCount, 0);

      final failed = _outgoing(id: 'writer-failed', status: 'failed');
      final failedRepo = FakeMessageRepository()
        ..seed(<ConversationMessage>[failed])
        ..failedOutgoingOverride = <ConversationMessage>[failed];
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity());
      final contactRepo = FakeContactRepository()
        ..seed(<ContactModel>[
          const ContactModel(
            peerId: 'peer-target',
            publicKey: 'contact-public-key',
            rendezvous: '/memory/336',
            username: 'Target',
            signature: 'signature',
            scannedAt: '2026-08-05T00:00:00.000Z',
            mlKemPublicKey: 'ml-kem-public-key',
          ),
        ]);
      final failedP2p =
          FakeP2PService(
              initialState: const NodeState(
                isStarted: true,
                peerId: 'my-peer-id',
              ),
            )
            ..onStoreInInbox = (_, _, {int? timeoutMs}) async {
              await _winDelivery(
                failedRepo,
                failed,
                mode: OutgoingOrdinarySettlementMode.receipt,
                transport: 'direct',
              );
              return true;
            };

      expect(
        await retryFailedMessages(
          messageRepo: failedRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: failedP2p,
          bridge: FakeBridge(),
        ),
        0,
      );
      _expectFirstDeliveryFrozen(
        await failedRepo.getMessage(failed.id),
        transport: 'direct',
      );
      expect(failedRepo.saveMessageCallCount, 0);

      final paused = _outgoing(id: 'writer-paused', status: 'sending');
      final pauseRepo = FakeMessageRepository()
        ..seed(<ConversationMessage>[paused]);
      final pauseP2p =
          FakeP2PService(
              initialState: const NodeState(
                isStarted: true,
                peerId: 'my-peer-id',
              ),
            )
            ..onStoreInInbox = (_, _, {int? timeoutMs}) async {
              await _winDelivery(
                pauseRepo,
                paused,
                mode: OutgoingOrdinarySettlementMode.live,
                transport: 'wifi',
              );
              return true;
            };

      final pauseResult = await handleAppPaused(
        messageRepo: pauseRepo,
        p2pService: pauseP2p,
        bridge: _PauseBridge(),
        enablePauseFlush: true,
      );
      expect(pauseResult.flushDepositedCount, 1);
      expect(pauseResult.transitionedCount, 0);
      _expectFirstDeliveryFrozen(
        await pauseRepo.getMessage(paused.id),
        transport: 'wifi',
      );
      expect(pauseRepo.saveMessageCallCount, 0);
      expect(pauseRepo.conditionalTransitionCallCount, 0);
    },
  );

  test(
    'retry and pause fail closed when ordinary settlement capability is missing',
    () async {
      final unacked = _outgoing(
        id: 'missing-capability-unacked',
        status: 'sent',
      );
      final unackedRepo = _MessageRepositoryWithoutOrdinaryCapability(
        <ConversationMessage>[unacked],
      );
      final unackedP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      expect(
        await retryUnackedMessages(
          messageRepo: unackedRepo,
          p2pService: unackedP2p,
          olderThan: Duration.zero,
        ),
        0,
      );
      expect(
        (await unackedRepo.getMessage(unacked.id))!.toMap(),
        unacked.toMap(),
      );
      expect(unackedRepo.saveMessageCallCount, 0);
      expect(unackedRepo.updateMessageStatusCallCount, 0);
      expect(unackedRepo.conditionalTransitionCallCount, 0);
      _expectNoTransportFallback(unackedP2p);

      final failed = _outgoing(
        id: 'missing-capability-failed',
        status: 'failed',
      );
      final failedRepo = _MessageRepositoryWithoutOrdinaryCapability(
        <ConversationMessage>[failed],
      );
      final failedP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
        discoverPeerResult: null,
        dialPeerResult: true,
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity());
      final contactRepo = FakeContactRepository()
        ..seed(<ContactModel>[
          const ContactModel(
            peerId: 'peer-target',
            publicKey: 'contact-public-key',
            rendezvous: '/memory/336-missing-capability',
            username: 'Target',
            signature: 'signature',
            scannedAt: '2026-08-05T00:00:00.000Z',
            mlKemPublicKey: 'ml-kem-public-key',
          ),
        ]);

      expect(
        await retryFailedMessages(
          messageRepo: failedRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: failedP2p,
          bridge: FakeBridge(),
        ),
        0,
      );
      expect((await failedRepo.getMessage(failed.id))!.toMap(), failed.toMap());
      expect(failedRepo.saveMessageCallCount, 0);
      expect(failedRepo.updateMessageStatusCallCount, 0);
      expect(failedRepo.conditionalTransitionCallCount, 0);
      _expectNoTransportFallback(failedP2p);

      final paused = _outgoing(
        id: 'missing-capability-paused',
        status: 'sending',
      );
      final pauseRepo = _MessageRepositoryWithoutOrdinaryCapability(
        <ConversationMessage>[paused],
      );
      final pauseP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );
      final pauseBridge = _PauseBridge();

      final pauseResult = await handleAppPaused(
        messageRepo: pauseRepo,
        p2pService: pauseP2p,
        bridge: pauseBridge,
        enablePauseFlush: true,
      );

      expect(pauseResult.flushDepositedCount, 0);
      expect(pauseResult.transitionedCount, 1);
      expect(
        (await pauseRepo.getMessage(paused.id))!.toMap(),
        paused.copyWith(status: 'failed').toMap(),
      );
      expect(pauseRepo.saveMessageCallCount, 0);
      expect(pauseRepo.updateMessageStatusCallCount, 0);
      expect(pauseRepo.conditionalTransitionCallCount, 1);
      _expectNoTransportFallback(pauseP2p);
      expect(pauseBridge.commandLog, isEmpty);
    },
  );

  test('media delete UI and feed writers have no stale settlement bypass', () {
    final upload = _topLevelFunctionBody(
      _retryUploadsPath,
      'retryIncompleteUploads',
    );
    expect(upload, contains('final preUploadEnvelope = msg.wireEnvelope'));
    expect(upload, contains('.invalidateOutgoingOrdinaryEnvelope('));
    expect(upload, contains('ordinaryEnvelopeInvalidationRefused'));
    expect(upload, isNot(contains('messageRepo.saveMessage(')));

    final delete = _topLevelFunctionBody(
      _deletePath,
      'deleteMessageForEveryone',
    );
    final deleteSettlement = _topLevelFunctionBody(
      _deletePath,
      '_persistOutgoingDeleteTombstoneResult',
    );
    final retryDelete = _topLevelFunctionBody(
      _retryFailedPath,
      '_retryFailedDeletedTombstone',
    );
    final retryDeleteSettlement = _topLevelFunctionBody(
      _retryFailedPath,
      '_storeOrReplayDeleteEnvelope',
    );
    expect(delete, contains('.stageOutgoingOrdinaryAttempt('));
    expect(delete, contains('OutgoingOrdinaryAttemptKind.tombstoneInitial'));
    expect(delete, isNot(contains('messageRepo.saveMessage(')));
    expect(
      deleteSettlement,
      contains('.settleOutgoingOrdinaryDeleteTombstone('),
    );
    expect(deleteSettlement, isNot(contains('messageRepo.saveMessage(')));
    expect(retryDelete, contains('.stageOutgoingOrdinaryAttempt('));
    expect(retryDelete, contains('OutgoingOrdinaryAttemptKind.tombstoneRetry'));
    expect(
      retryDeleteSettlement,
      contains('.settleOutgoingOrdinaryDeleteTombstone('),
    );
    expect(
      '$retryDelete\n$retryDeleteSettlement',
      isNot(contains('messageRepo.saveMessage(')),
    );

    final send = _methodBody(
      _conversationPath,
      '_ConversationWiredState',
      '_onSend',
    );
    final restore = _methodBody(
      _conversationPath,
      '_ConversationWiredState',
      '_restoreComposerSnapshot',
    );
    final voice = _methodBody(
      _conversationPath,
      '_ConversationWiredState',
      '_sendVoiceRecording',
    );
    final failedCas = _methodBody(
      _conversationPath,
      '_ConversationWiredState',
      '_transitionSendingMessageToFailed',
    );
    final retriableSettlement = _methodBody(
      _conversationPath,
      '_ConversationWiredState',
      '_settleRetriableOrdinaryMessage',
    );
    for (final boundedBody in <String>[send, restore, voice]) {
      expect(boundedBody, isNot(contains('updateMessageStatus(')));
      expect(boundedBody, isNot(contains('_persistMessageStatus(')));
    }
    expect(send, contains('_settleRetriableOrdinaryMessage('));
    expect(send, contains('_transitionSendingMessageToFailed('));
    expect(restore, contains('_transitionSendingMessageToFailed('));
    expect(
      _count(voice, 'widget.messageRepo.saveMessage('),
      2,
      reason: 'only fresh failed-voice and optimistic-voice creation remain',
    );
    expect(voice, contains('_transitionSendingMessageToFailed('));
    expect(failedCas, contains('.conditionalTransitionStatus('));
    expect(failedCas, contains("fromStatus: 'sending'"));
    expect(failedCas, contains("toStatus: 'failed'"));
    expect(retriableSettlement, contains('.settleOutgoingOrdinaryTransport('));
    expect(retriableSettlement, contains("transport: 'inbox'"));
    expect(retriableSettlement, isNot(contains('saveMessage(')));

    final feed = _methodBody(
      _feedPath,
      '_FeedWiredState',
      '_sendContactComposerReply',
    );
    expect(_count(feed, 'messageRepository.saveMessage('), 0);
    expect(_count(feed, '.conditionalTransitionStatus('), 2);
    expect(feed, isNot(contains('updateMessageStatus(')));
  });

  test(
    'TC-342-07 feed composer delegates fresh preassigned text to atomic custody',
    () {
      final feed = _methodBody(
        _feedPath,
        '_FeedWiredState',
        '_sendContactComposerReply',
      );
      final dispatch = _methodBody(
        _feedPath,
        '_FeedWiredState',
        '_dispatchFeedComposerSend',
      );

      expect(
        feed,
        isNot(contains('messageRepository.saveMessage(')),
        reason:
            'the composer must not preinsert a message ahead of the atomic '
            'message-plus-custody stage',
      );
      expect(feed, contains('id: messageId'));
      expect(feed, isNot(contains('_uuid.v4()')));
      expect(feed, contains('messageId: optimisticMessage.id'));
      expect(feed, contains('preassignedMessageIdIsFresh: true'));
      expect(dispatch, contains('messageId: reply.messageId'));
    },
  );

  test(
    'TC-342-04b feed retry reuses durable authority and remints only proven never-staged work',
    () {
      final retry = _methodBody(_feedPath, '_FeedWiredState', '_onRetrySend');
      final contactRetry = _methodBody(
        _feedPath,
        '_FeedWiredState',
        '_retryContactComposerReply',
      );

      expect(retry, contains('_retryContactComposerReply(threadId, reply)'));
      expect(contactRetry, contains('reply.messageId'));
      expect(contactRetry, contains('retryFailedMessage('));
      expect(contactRetry, contains('messageId: reply.messageId'));
      expect(contactRetry, contains('_sendContactComposerReply('));

      final convergedAuthority = contactRetry.indexOf(
        'durableAuthority == true',
      );
      final unknownAuthority = contactRetry.indexOf(
        'durableAuthority != false',
      );
      final replacementMint = contactRetry.indexOf('messageId: _uuid.v4()');
      expect(convergedAuthority, greaterThanOrEqualTo(0));
      expect(unknownAuthority, greaterThan(convergedAuthority));
      expect(replacementMint, greaterThan(unknownAuthority));
      expect(_count(contactRetry, '_uuid.v4()'), 1);
      expect(contactRetry, contains('messageId: replacement.messageId'));
    },
  );

  test('production wiring and writer census close only the R1 bypass set', () {
    final messageConstruction = _singleConstruction(
      _bootstrapPath,
      'MessageRepositoryImpl',
    );
    for (final binding in const <String>[
      'dbStageOutgoingOrdinaryAttempt:',
      'dbSettleOutgoingOrdinaryTransport:',
      'dbSettleOutgoingOrdinaryDeleteTombstone:',
      'dbInvalidateOutgoingOrdinaryEnvelope:',
      'dbQuarantineUnsafeLegacyOutgoingEnvelope:',
    ]) {
      expect(
        _count(messageConstruction, binding),
        1,
        reason: 'production MessageRepositoryImpl must bind $binding once',
      );
    }
    final mediaConstruction = _singleConstruction(
      _bootstrapPath,
      'MediaAttachmentRepositoryImpl',
    );
    for (final binding in const <String>[
      'dbStageOutgoingOrdinaryAttemptWithMedia:',
      'publishOutgoingOrdinaryMutation:',
    ]) {
      expect(
        _count(mediaConstruction, binding),
        1,
        reason:
            'production MediaAttachmentRepositoryImpl must bind $binding once',
      );
    }

    final unacked = _topLevelFunctionBody(
      _retryUnackedPath,
      'retryUnackedMessages',
    );
    expect(unacked, contains('.settleOutgoingOrdinaryTransport('));
    expect(unacked, contains('.settleOutgoingOrdinaryDeleteTombstone('));
    expect(unacked, contains('.quarantineUnsafeLegacyOutgoingEnvelope('));
    expect(
      unacked,
      contains('settleOutgoingDirectPrivateTransportUnderLifecycleLock('),
    );
    expect(unacked, contains('.settlePrivateDeleteForEveryoneTombstone('));
    expect(unacked, isNot(contains('messageRepo.saveMessage(')));
    expect(unacked, isNot(contains('updateMessageStatus(')));

    final cachedRetry = _topLevelFunctionBody(
      _retryFailedPath,
      '_retryFailedMessageCandidate',
    );
    expect(cachedRetry, contains('.settleOutgoingOrdinaryTransport('));
    expect(
      cachedRetry,
      contains('settleOutgoingDirectPrivateTransportUnderLifecycleLock('),
    );
    expect(cachedRetry, isNot(contains('messageRepo.saveMessage(')));
    expect(cachedRetry, isNot(contains('updateMessageStatus(')));

    final pause = _topLevelFunctionBody(_pausePath, 'handleAppPaused');
    expect(pause, contains('.settleOutgoingOrdinaryTransport('));
    expect(pause, contains('.settleOutgoingOrdinaryDeleteTombstone('));
    expect(
      pause,
      contains('settleOutgoingDirectPrivateTransportUnderLifecycleLock('),
    );
    expect(pause, contains('.conditionalTransitionStatus('));
    expect(pause, isNot(contains('messageRepo.saveMessage(')));
    expect(pause, isNot(contains('updateMessageStatus(')));

    // The verified custody-loss downgrade remains its separately reviewed
    // exact CAS. R1 must not absorb inboxed -> sent into normal settlement.
    final custodyLoss = _topLevelFunctionBody(
      _custodyLossPath,
      '_surfaceLostCustody',
    );
    expect(custodyLoss, contains('.conditionalTransitionStatus('));
    expect(custodyLoss, contains("fromStatus: 'inboxed'"));
    expect(custodyLoss, contains("toStatus: 'sent'"));
    expect(custodyLoss, isNot(contains('settleOutgoingOrdinaryTransport(')));
  });
}
