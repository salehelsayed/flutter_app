import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/role_aware_deferred_runtime_start.dart';
import 'package:flutter_app/app/bootstrap/direct_blob_free_linked_services.dart';
import 'package:flutter_app/core/application/protected_group_content_runtime_quiescence.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/linked_group_status_refresh.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/linked_group_conversation_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _productionPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _canonicalDirectProjectionPath =
    'lib/app/bootstrap/production_canonical_direct_projection_composition.dart';
const _canonicalDirectReplayPath =
    'lib/app/bootstrap/production_canonical_direct_replay_composition.dart';
const _applicationRootPath = 'lib/app/application_root.dart';
const _handlerPath =
    'lib/features/push/application/background_message_handler.dart';

enum _SendChatMessageCallerKind {
  generatedIdFresh,
  preassignedIdFresh,
  excludedEdit,
  excludedRetry,
  excludedMedia,
  excludedVoice,
}

final class _ExpectedSendChatMessageCaller {
  const _ExpectedSendChatMessageCaller({
    required this.kind,
    this.callee = 'sendChatMessage',
    this.freshIntent,
    this.mediaAttachments,
  });

  final _SendChatMessageCallerKind kind;
  final String callee;
  final String? freshIntent;
  final String? mediaAttachments;
}

const _expectedSendChatMessageCallers =
    <String, List<_ExpectedSendChatMessageCaller>>{
      'lib/core/debug/intro_e2e_runner.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.generatedIdFresh,
        ),
      ],
      'lib/core/debug/keepalive_drop_e2e.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.generatedIdFresh,
        ),
      ],
      'lib/features/conversation/application/'
          'retry_failed_messages_use_case.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.excludedRetry,
        ),
      ],
      'lib/features/conversation/application/'
          'retry_incomplete_uploads_use_case.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.excludedMedia,
          mediaAttachments: 'fullAttachmentList',
        ),
      ],
      'lib/features/conversation/application/send_chat_message_use_case.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.excludedEdit,
        ),
      ],
      'lib/features/conversation/application/send_voice_message_use_case.dart':
          [
            _ExpectedSendChatMessageCaller(
              kind: _SendChatMessageCallerKind.excludedVoice,
              freshIntent: 'preassignedMessageIdIsFresh',
              mediaAttachments: 'attachments',
            ),
          ],
      'lib/features/conversation/presentation/screens/conversation_wired.dart':
          [
            _ExpectedSendChatMessageCaller(
              kind: _SendChatMessageCallerKind.preassignedIdFresh,
              callee: 'sendChatMessageFn',
              freshIntent: 'stagesFreshDirectTextCustody',
            ),
          ],
      'lib/features/feed/presentation/screens/feed_wired.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.preassignedIdFresh,
          freshIntent: 'true',
        ),
      ],
      'lib/features/share/application/share_batch_delivery_coordinator.dart': [
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.generatedIdFresh,
        ),
        _ExpectedSendChatMessageCaller(
          kind: _SendChatMessageCallerKind.excludedMedia,
          mediaAttachments: 'completedAttachments',
        ),
      ],
    };

final class _SendChatMessageInvocationCollector
    extends RecursiveAstVisitor<void> {
  final invocations = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name case 'sendChatMessage' || 'sendChatMessageFn') {
      invocations.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

final class _DirectReactionAuthoringInvocationCollector
    extends RecursiveAstVisitor<void> {
  final invocations = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final namesP2pService = node.argumentList.arguments
        .whereType<NamedExpression>()
        .any((argument) => argument.name.label.name == 'p2pService');
    if (name == 'sendReactionFn' ||
        name == 'removeReactionFn' ||
        ((name == 'sendReaction' || name == 'removeReaction') &&
            namesP2pService)) {
      invocations.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

List<({String path, String callee})>
_discoverDirectReactionAuthoringInvocations() {
  final paths =
      Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where((path) => path.endsWith('.dart'))
          .toList(growable: false)
        ..sort();
  final discovered = <({String path, String callee})>[];
  for (final path in paths) {
    final source = File(path).readAsStringSync();
    if (!RegExp(
      r'\b(?:sendReaction|sendReactionFn|removeReaction|removeReactionFn)\s*\(',
    ).hasMatch(source)) {
      continue;
    }
    final unit = parseString(content: source, path: path).unit;
    final collector = _DirectReactionAuthoringInvocationCollector();
    unit.accept(collector);
    for (final invocation in collector.invocations) {
      discovered.add((path: path, callee: invocation.methodName.name));
    }
  }
  return discovered;
}

List<
  ({String path, int line, String callee, Map<String, String> namedArguments})
>
_discoverSendChatMessageInvocations() {
  final paths =
      Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where((path) => path.endsWith('.dart'))
          .toList(growable: false)
        ..sort();
  final discovered =
      <
        ({
          String path,
          int line,
          String callee,
          Map<String, String> namedArguments,
        })
      >[];
  for (final path in paths) {
    final source = File(path).readAsStringSync();
    if (!RegExp(r'\bsendChatMessage(?:Fn)?\s*\(').hasMatch(source)) {
      continue;
    }
    final parsed = parseString(content: source, path: path);
    final collector = _SendChatMessageInvocationCollector();
    parsed.unit.accept(collector);
    for (final invocation in collector.invocations) {
      discovered.add((
        path: path,
        line: parsed.lineInfo.getLocation(invocation.offset).lineNumber,
        callee: invocation.methodName.name,
        namedArguments: <String, String>{
          for (final argument
              in invocation.argumentList.arguments.whereType<NamedExpression>())
            argument.name.label.name: argument.expression.toSource(),
        },
      ));
    }
  }
  return discovered;
}

String _sendCallerLabel(
  ({String path, int line, String callee, Map<String, String> namedArguments})
  caller,
) => '${caller.path}:${caller.line} (${caller.callee})';

bool _matchesExpectedSendChatMessageCaller(
  ({String path, int line, String callee, Map<String, String> namedArguments})
  caller,
  _ExpectedSendChatMessageCaller expected,
) {
  if (caller.callee != expected.callee) return false;
  final arguments = caller.namedArguments;
  return switch (expected.kind) {
    _SendChatMessageCallerKind.generatedIdFresh => !arguments.containsKey(
      'messageId',
    ),
    _SendChatMessageCallerKind.preassignedIdFresh =>
      arguments.containsKey('messageId') &&
          arguments['preassignedMessageIdIsFresh'] == expected.freshIntent,
    _SendChatMessageCallerKind.excludedEdit =>
      arguments['action'] == 'MessagePayload.actionEdit',
    _SendChatMessageCallerKind.excludedRetry =>
      arguments['action'] == 'retryAction',
    _SendChatMessageCallerKind.excludedMedia =>
      arguments.containsKey('messageId') &&
          arguments['mediaAttachments'] == expected.mediaAttachments,
    _SendChatMessageCallerKind.excludedVoice =>
      arguments['mediaAttachments'] == expected.mediaAttachments &&
          arguments['preassignedMessageIdIsFresh'] == expected.freshIntent,
  };
}

ClassDeclaration _productionClass(String source) {
  final unit = parseString(content: source, path: _productionPath).unit;
  return unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (declaration) =>
        declaration.name.lexeme == 'ProductionApplicationBootstrap',
  );
}

MethodDeclaration _method(ClassDeclaration declaration, String name) {
  return declaration.members.whereType<MethodDeclaration>().singleWhere(
    (method) => method.name.lexeme == name,
  );
}

Map<String, String> _localFunctionBodies(MethodDeclaration method) {
  final body = method.body;
  expect(body, isA<BlockFunctionBody>());
  final block = (body as BlockFunctionBody).block;
  return <String, String>{
    for (final statement
        in block.statements.whereType<FunctionDeclarationStatement>())
      statement.functionDeclaration.name.lexeme: statement
          .functionDeclaration
          .functionExpression
          .body
          .toSource(),
  };
}

final class _SentinelPrepared implements PreparedApplication {
  const _SentinelPrepared();

  @override
  Future<Widget> buildRootWidget() async => const Placeholder();

  @override
  void afterRunApp() {}
}

void main() {
  test('handled production reset bypasses normal composition', () async {
    var resetCalls = 0;
    var normalPrepareCalls = 0;
    final bootstrap = ProductionApplicationBootstrap(
      disposableProfileOverride: () => true,
      disposableResetOverride: () async {
        resetCalls += 1;
        return true;
      },
      normalPrepareOverride: () async {
        normalPrepareCalls += 1;
        return const _SentinelPrepared();
      },
    );

    final prepared = await bootstrap.prepare();
    expect(resetCalls, 1);
    expect(normalPrepareCalls, 0);
    expect(await prepared.buildRootWidget(), isA<SizedBox>());
    prepared.afterRunApp();
    expect(normalPrepareCalls, 0);
  });

  test(
    'TC-343-06a production wires capable reaction custody and one causal composite lifecycle drain',
    () {
      final production = File(_productionPath).readAsStringSync();
      final applicationRoot = File(_applicationRootPath).readAsStringSync();
      final normalMethod = _method(
        _productionClass(production),
        '_prepareNormalApplication',
      );
      final localBodies = _localFunctionBodies(normalMethod);

      expect(
        'Future<int> drainDirectInboxCustodyFamilies()'.allMatches(production),
        hasLength(1),
        reason: 'production must construct one shared direct-custody closure',
      );
      final composite = localBodies['drainDirectInboxCustodyFamilies']!;
      expect(
        RegExp(
          r'\bdrainDirectInboxCustodyOutbox\s*\(',
        ).allMatches(composite).length,
        1,
      );
      expect(
        RegExp(
          r'\bdrainDirectReactionInboxCustodyOutbox\s*\(',
        ).allMatches(composite).length,
        1,
      );
      expect(composite, contains('custodyRepository: messageRepository'));
      expect(composite, contains('custodyRepository: reactionRepository'));
      expect(
        'storeInAckCustodyInboxDetailed:'.allMatches(composite),
        hasLength(2),
        reason:
            'Plan 344 production composes v108 and v109 drains with ack custody store',
      );
      expect(
        'p2pService.storeInAckCustodyInboxDetailed'.allMatches(composite),
        hasLength(2),
      );
      expect(
        RegExp(r'\btry\s*\{').allMatches(composite),
        hasLength(2),
        reason: 'text and reaction drains need separate fault boundaries',
      );
      expect(
        RegExp(r'\bcatch\s*\(').allMatches(composite),
        hasLength(2),
        reason: 'either custody family throwing must preserve its sibling',
      );
      expect(
        composite.indexOf('drainDirectReactionInboxCustodyOutbox('),
        greaterThan(composite.indexOf('drainDirectInboxCustodyOutbox(')),
        reason: 'the existing text family retains deterministic first order',
      );
      for (final binding in const <String>[
        'dbStageOutgoingDirectTextInboxCustody:',
        'dbLoadDirectInboxCustodyOutbox:',
        'dbLoadDirectInboxCustodyOutboxForMessage:',
        'dbLoadDirectInboxCustodyOutboxOwnerForMessageId:',
        'dbRecordDirectInboxCustodyFailureIfExact:',
        'dbCompleteAcceptedDirectInboxCustodyIfExact:',
      ]) {
        expect(
          binding.allMatches(production),
          hasLength(1),
          reason: 'production must wire exactly one complete $binding seam',
        );
      }
      for (final binding in const <String>[
        'dbStageOutgoingDirectReactionInboxCustody:',
        'dbLoadDirectReactionInboxCustodyOutbox:',
        'dbLoadDirectReactionInboxCustodyOutboxForEvent:',
        'dbRecordDirectReactionInboxCustodyFailureIfExact:',
        'dbCompleteAcceptedDirectReactionInboxCustodyIfExact:',
      ]) {
        expect(
          binding.allMatches(production),
          hasLength(1),
          reason:
              'production must wire exactly one capable reaction $binding seam',
        );
      }
      expect(
        'drainDirectInboxCustodyOutboxFn: drainDirectInboxCustodyFamilies'
            .allMatches(production),
        hasLength(1),
        reason: 'the background retrier must receive the composite drain',
      );
      expect(
        'drainDirectInboxCustodyOutbox: drainDirectInboxCustodyFamilies'
            .allMatches(production),
        hasLength(1),
        reason: 'the app-resume root must receive the same composite closure',
      );
      expect(
        applicationRoot,
        contains(
          'drainDirectInboxCustodyOutboxFn: '
          'widget.drainDirectInboxCustodyOutbox',
        ),
      );
    },
  );

  test(
    'TC-345-03c production bootstrap wires combined media custody and shared v108 drain',
    () {
      final production = File(_productionPath).readAsStringSync();

      expect(
        'dbStageOutgoingDirectMediaInboxCustody:'.allMatches(production),
        hasLength(1),
        reason: 'production must wire one combined media custody delegate',
      );
      expect(
        RegExp(
          r'\)\s*=>\s*dbStageOutgoingDirectMediaInboxCustody\s*\(',
        ).allMatches(production),
        hasLength(1),
        reason: 'the delegate must call the real atomic DB authority',
      );
      expect(
        'dbProjectOutgoingDirectMediaCustodyUploadFailure:'.allMatches(
          production,
        ),
        hasLength(1),
        reason:
            'token-bearing upload failures need the exact transactional '
            'projection in production',
      );
      expect(
        RegExp(
          r'\)\s*=>\s*dbProjectOutgoingDirectMediaCustodyUploadFailure\s*\(',
        ).allMatches(production),
        hasLength(1),
        reason: 'the failure delegate must call the real DB authority',
      );
      expect(
        'Future<int> drainDirectInboxCustodyFamilies()'.allMatches(production),
        hasLength(1),
        reason: 'media reuses the existing v108 lifecycle drain',
      );
      expect(
        RegExp(r'\bdrainDirectInboxCustodyOutbox\s*\(').allMatches(production),
        hasLength(1),
        reason: 'media must not introduce a sibling v108 worker',
      );
      expect(
        RegExp(
          r'\bdbCompleteAcceptedDirectInboxCustodyIfExact\s*\(',
        ).allMatches(production),
        hasLength(1),
        reason: 'text and media share the exact v108 completion authority',
      );
    },
  );

  test('TC-347-07b production composes one blob custody drain', () {
    final production = File(_productionPath).readAsStringSync();
    final normalMethod = _method(
      _productionClass(production),
      '_prepareNormalApplication',
    );
    final localBodies = _localFunctionBodies(normalMethod);

    expect(
      'final directMediaBlobCustodyDrain ='.allMatches(production),
      hasLength(1),
      reason: 'production must construct one shared v111 lifecycle owner',
    );
    expect('DirectMediaBlobCustodyDrain('.allMatches(production), hasLength(1));
    expect(
      'StrictDirectMediaBlobDownloadAckOwner('.allMatches(production),
      hasLength(1),
      reason: 'download and lifecycle ACK retry share one strict native owner',
    );
    final localCleanup = localBodies['cleanupDirectMediaBlobCustodyLocally']!;
    final networkDrain = localBodies['drainDirectMediaBlobCustody']!;
    expect(localCleanup, contains('directMediaBlobCustodyDrain'));
    expect(localCleanup, contains('runLocalCleanupBounded()'));
    expect(networkDrain, contains('directMediaBlobCustodyDrain'));
    expect(networkDrain, contains('runNetworkBounded()'));
    // 362: the restricted linked runtime gets its own converger, wired to the
    // SAME single drain instance through the linked-scoped entry point. It was
    // declared and awaited by the application root but never supplied, so the
    // linked resume drain was inert in production.
    final linkedNetworkDrain =
        localBodies['drainLinkedDirectMediaBlobCustody']!;
    expect(linkedNetworkDrain, contains('directMediaBlobCustodyDrain'));
    expect(linkedNetworkDrain, contains('runNetworkBoundedLinked()'));
    expect(
      'drainLinkedDirectMediaBlobCustody: drainLinkedDirectMediaBlobCustody,'
          .allMatches(production),
      hasLength(2),
      reason:
          'the linked converger is supplied at BOTH cold start (linked '
          'services) and resume (application root)',
    );

    for (final binding in const <String>[
      'dbStageOutgoingDirectMediaBlobGeneration:',
      'dbStageIncomingDirectMediaBlobCustody:',
      'dbCommitIncomingDirectMediaBlobLocalPath:',
      'dbDeleteIncomingDirectMediaBlobAckPendingIfExact:',
      'dbDeleteIncomingDirectMediaBlobIfExpired:',
    ]) {
      expect(
        binding.allMatches(production),
        hasLength(1),
        reason: 'production must wire one exact $binding delegate',
      );
    }
    // 358: the strict local-path commit carries the strict owner's own clock
    // sample. The production delegate must forward it unchanged, so a
    // disappearing deadline recheck can never be inferred from the caller's
    // formatted audit timestamp.
    final commitDelegate = RegExp(
      r'dbCommitIncomingDirectMediaBlobLocalPath:[\s\S]*?\),\n',
    ).firstMatch(production)!.group(0)!;
    expect(commitDelegate, contains('required nowMs,'));
    expect(commitDelegate, contains('nowMs: nowMs,'));
    expect(
      'drainDirectMediaBlobCustodyFn:'.allMatches(production),
      hasLength(1),
      reason: 'the background retrier receives the one network drain closure',
    );
    expect(
      'drainDirectMediaBlobCustody: drainDirectMediaBlobCustody'.allMatches(
        production,
      ),
      hasLength(1),
      reason: 'resume receives that same network drain closure',
    );
    expect(
      'directMediaBlobLocalCleanup: cleanupDirectMediaBlobCustodyLocally'
          .allMatches(production),
      hasLength(1),
      reason: 'resume receives the local-only sibling on the same drain',
    );
    expect(
      "'direct_media_blob_local_cleanup'".allMatches(production),
      hasLength(1),
      reason: 'cold-start local cleanup is composed exactly once',
    );
  });

  test(
    'TC-356-01d production wires private deletion stage to physical v109',
    () {
      final unit = parseString(
        content: File(_productionPath).readAsStringSync(),
        path: _productionPath,
      ).unit;
      final visitor = _MessageRepositoryConstructionVisitor();
      unit.accept(visitor);

      expect(
        visitor.constructions,
        hasLength(1),
        reason: 'production composes exactly one MessageRepositoryImpl',
      );
      final argument = visitor.constructions.single.arguments
          .whereType<NamedExpression>()
          .where(
            (named) =>
                named.name.label.name ==
                'dbStageOutgoingDirectPrivateDeletionInboxCustody',
          )
          .toList(growable: false);
      expect(
        argument,
        hasLength(1),
        reason:
            'the private deletion custody capability must be wired exactly once',
      );

      // The delegate must call the REAL atomic helper, not a local shim.
      final calls = _InvokedFunctionNameVisitor();
      argument.single.expression.accept(calls);
      expect(
        calls.names,
        contains('dbStageOutgoingDirectPrivateDeletionInboxCustody'),
        reason:
            'the wired capability must delegate to the shared physical v109 '
            'stage helper',
      );
      expect(
        calls.names.where(
          (name) => name.startsWith('dbCommitOutgoingDirectPrivateDelete'),
        ),
        isEmpty,
        reason:
            'the staging capability must never fall back to the tombstone-only '
            'commit',
      );
    },
  );

  test('TC-348-02c production wires fresh blob stage exactly once', () {
    final production = File(_productionPath).readAsStringSync();

    expect(
      'dbStageFreshOutgoingDirectMediaBlobGeneration:'.allMatches(production),
      hasLength(1),
      reason:
          'production must expose the absent-parent v111 capability exactly '
          'once',
    );
    expect(
      RegExp(
        r'\)\s*=>\s*dbStageFreshOutgoingDirectMediaBlobGeneration\s*\(',
      ).allMatches(production),
      hasLength(1),
      reason: 'the capability must delegate to the real atomic SQLite helper',
    );
  });

  test(
    'TC-366-01b production composes the plural private generation and Barrier-B delegates',
    () {
      final production = File(_productionPath).readAsStringSync();
      final unit = parseString(content: production, path: _productionPath).unit;
      final mediaVisitor = _MediaAttachmentRepositoryConstructionVisitor();
      final messageVisitor = _MessageRepositoryConstructionVisitor();
      unit.accept(mediaVisitor);
      unit.accept(messageVisitor);

      expect(
        mediaVisitor.constructions,
        hasLength(1),
        reason: 'production composes exactly one media repository',
      );
      expect(
        messageVisitor.constructions,
        hasLength(1),
        reason: 'production composes exactly one message repository',
      );

      NamedExpression exactDelegate(ArgumentList construction, String name) {
        final matches = construction.arguments
            .whereType<NamedExpression>()
            .where((argument) => argument.name.label.name == name)
            .toList(growable: false);
        expect(
          matches,
          hasLength(1),
          reason: 'production must compose exactly one $name delegate',
        );
        return matches.single;
      }

      final privateGeneration = exactDelegate(
        mediaVisitor.constructions.single,
        'dbStageOutgoingDirectPrivateMediaBlobFanoutGeneration',
      );
      final generationCalls = _InvokedFunctionNameVisitor();
      privateGeneration.expression.accept(generationCalls);
      expect(
        generationCalls.names,
        contains('dbStageOutgoingDirectPrivateMediaBlobFanoutGeneration'),
        reason: 'the capability must call the real plural SQLite authority',
      );
      final generationSource = privateGeneration.expression.toSource();
      for (final parameter in const <String>[
        'expectedParentRow',
        'expectedAttachmentRow',
        'preparedAttachmentRow',
        'custodyRows',
        'contactAccountPeerId',
        'expectedSnapshot',
      ]) {
        expect(
          '$parameter: $parameter'.allMatches(generationSource),
          hasLength(1),
          reason: '$parameter must pass through the plural generation verbatim',
        );
      }
      expect(
        RegExp(r'\bcustodyRow\b').hasMatch(generationSource),
        isFalse,
        reason: 'production must not collapse N v114 rows to the singular API',
      );

      final privateBarrierB = exactDelegate(
        messageVisitor.constructions.single,
        'dbCommitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody',
      );
      final barrierCalls = _InvokedFunctionNameVisitor();
      privateBarrierB.expression.accept(barrierCalls);
      expect(
        barrierCalls.names,
        contains(
          'dbCommitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody',
        ),
        reason: 'Barrier B must call the real plural v108 SQLite authority',
      );
      final barrierSource = privateBarrierB.expression.toSource();
      for (final parameter in const <String>[
        'expectedPendingLocalPath',
        'hasOwnedPendingCompletion',
        'senderTransportPeerId',
        'contactAccountPeerId',
        'authority',
        'expectedSnapshot',
        'targetBindings',
      ]) {
        expect(
          '$parameter: $parameter'.allMatches(barrierSource),
          hasLength(1),
          reason: '$parameter must pass through plural Barrier B verbatim',
        );
      }
      expect(
        RegExp(r'\btargetBinding\b').hasMatch(barrierSource),
        isFalse,
        reason: 'production must not select one target before Barrier B',
      );
    },
  );

  test('TC-350-02c production wires fresh forward authorization exactly once', () {
    final production = File(_productionPath).readAsStringSync();

    expect(
      'authorizedForwardDedupKey'.allMatches(production),
      hasLength(6),
      reason:
          'exactly two delegate declarations plus one verbatim named '
          'pass-through per delegate: fresh single-target and fresh linked '
          'fanout',
    );
    expect(
      'authorizedForwardDedupKey: authorizedForwardDedupKey'.allMatches(
        production,
      ),
      hasLength(2),
      reason:
          'both fresh-generation delegates reach their SQLite helper '
          'unmodified',
    );
    expect(
      production,
      matches(
        RegExp(
          r'dbStageFreshOutgoingDirectMediaBlobGeneration:\s*\n?\s*\(\{[\s\S]{0,400}?'
          r'authorizedForwardDedupKey,\s*\n?\s*\}\)\s*=>\s*'
          r'dbStageFreshOutgoingDirectMediaBlobGeneration\s*\([\s\S]{0,400}?'
          r'authorizedForwardDedupKey:\s*authorizedForwardDedupKey,',
        ),
      ),
      reason:
          'the wired capability must forward the caller-supplied token verbatim',
    );
    expect(
      production,
      matches(
        RegExp(
          r'dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration:\s*\n?\s*\(\{[\s\S]{0,600}?'
          r'authorizedForwardDedupKey,\s*\n?\s*\}\)\s*=>\s*'
          r'dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration\s*\([\s\S]{0,600}?'
          r'authorizedForwardDedupKey:\s*authorizedForwardDedupKey,',
        ),
      ),
      reason:
          'the linked-fanout capability must forward the caller-supplied '
          'token verbatim',
    );
  });

  test(
    'TC-343-06a direct reaction caller census stays on the capable wired route',
    () {
      final callers = _discoverDirectReactionAuthoringInvocations();
      expect(callers, hasLength(2));
      expect(
        callers.map((caller) => '${caller.path}::${caller.callee}').toSet(),
        <String>{
          'lib/features/conversation/presentation/screens/'
              'conversation_wired.dart::sendReactionFn',
          'lib/features/conversation/presentation/screens/'
              'conversation_wired.dart::removeReactionFn',
        },
        reason:
            'every app-owned ADD/REMOVE authoring route must traverse the '
            'custody-capable ConversationWired injection seams',
      );

      final p2pImplementation = File(
        'lib/core/services/p2p_service_impl.dart',
      ).readAsStringSync();
      expect(
        p2pImplementation,
        matches(
          RegExp(
            r'class P2PServiceImpl\s+implements[\s\S]*?\bAckOrExpiryInboxStore\b',
          ),
        ),
        reason:
            'the production reaction caller must expose strict inbox custody',
      );
    },
  );

  test(
    'TC-342-07 app-owned sendChatMessage caller census classifies custody intent',
    () {
      final callers = _discoverSendChatMessageInvocations();
      final unexpected = callers
          .where(
            (caller) =>
                !_expectedSendChatMessageCallers.containsKey(caller.path),
          )
          .map(_sendCallerLabel)
          .toList(growable: false);
      expect(
        unexpected,
        isEmpty,
        reason:
            'every new app-owned sendChatMessage caller must declare whether '
            'it authors a generated-ID fresh attempt, explicitly opts a '
            'preassigned fresh ID into custody, or is an excluded existing '
            'edit/retry/media/voice attempt',
      );
      expect(
        callers,
        hasLength(
          _expectedSendChatMessageCallers.values.fold<int>(
            0,
            (count, expected) => count + expected.length,
          ),
        ),
        reason:
            'the exact caller inventory must reject missing and duplicate '
            'call sites as well as new files',
      );

      for (final expected in _expectedSendChatMessageCallers.entries) {
        final matches = callers
            .where((caller) => caller.path == expected.key)
            .toList();
        expect(
          matches,
          hasLength(expected.value.length),
          reason: '${expected.key} must own exactly the classified invocations',
        );
        for (final expectedCaller in expected.value) {
          final candidates = matches
              .where(
                (caller) => _matchesExpectedSendChatMessageCaller(
                  caller,
                  expectedCaller,
                ),
              )
              .toList(growable: false);
          expect(
            candidates,
            hasLength(1),
            reason:
                '${expected.key} must have one ${expectedCaller.kind.name} '
                'invocation',
          );
          final caller = candidates.single;
          matches.remove(caller);
          final arguments = caller.namedArguments;

          switch (expectedCaller.kind) {
            case _SendChatMessageCallerKind.generatedIdFresh:
              expect(
                arguments,
                isNot(contains('messageId')),
                reason:
                    '${_sendCallerLabel(caller)} must let sendChatMessage '
                    'generate the fresh attempt ID',
              );
              expect(
                arguments,
                isNot(contains('preassignedMessageIdIsFresh')),
                reason: _sendCallerLabel(caller),
              );
              expect(arguments, isNot(contains('action')));
            case _SendChatMessageCallerKind.preassignedIdFresh:
              expect(
                arguments,
                contains('messageId'),
                reason:
                    '${_sendCallerLabel(caller)} is the reviewed preassigned-ID '
                    'fresh producer',
              );
              expect(
                arguments['preassignedMessageIdIsFresh'],
                expectedCaller.freshIntent,
                reason:
                    '${_sendCallerLabel(caller)} must carry explicit custody '
                    'intent whenever it preassigns a fresh message ID',
              );
              expect(arguments, isNot(contains('action')));
            case _SendChatMessageCallerKind.excludedEdit:
              expect(arguments['action'], 'MessagePayload.actionEdit');
              expect(arguments, contains('messageId'));
              expect(arguments, isNot(contains('preassignedMessageIdIsFresh')));
            case _SendChatMessageCallerKind.excludedRetry:
              expect(arguments['action'], 'retryAction');
              expect(arguments, contains('messageId'));
              expect(arguments, isNot(contains('preassignedMessageIdIsFresh')));
            case _SendChatMessageCallerKind.excludedMedia:
              expect(
                arguments['mediaAttachments'],
                expectedCaller.mediaAttachments,
              );
              expect(arguments, contains('messageId'));
              expect(arguments, isNot(contains('preassignedMessageIdIsFresh')));
            case _SendChatMessageCallerKind.excludedVoice:
              expect(
                arguments['mediaAttachments'],
                expectedCaller.mediaAttachments,
              );
              expect(arguments, contains('messageId'));
              expect(
                arguments['preassignedMessageIdIsFresh'],
                expectedCaller.freshIntent,
              );
          }
        }
        expect(matches, isEmpty);
      }

      final preassignedWithoutFreshIntent = callers
          .where(
            (caller) =>
                caller.namedArguments.containsKey('messageId') &&
                !caller.namedArguments.containsKey(
                  'preassignedMessageIdIsFresh',
                ),
          )
          .map((caller) => caller.path)
          .toSet();
      expect(
        preassignedWithoutFreshIntent,
        {
          'lib/features/conversation/application/'
              'retry_failed_messages_use_case.dart',
          'lib/features/conversation/application/'
              'retry_incomplete_uploads_use_case.dart',
          'lib/features/conversation/application/'
              'send_chat_message_use_case.dart',
          'lib/features/share/application/share_batch_delivery_coordinator.dart',
        },
        reason:
            'only classified existing edit/retry or pre-owned media attempts '
            'may pass a messageId without explicit fresh-custody intent',
      );
    },
  );

  test(
    'TC-398-08 exact-profile receipt arms before the share join and advances through bootstrap milestones',
    () {
      final production = File(_productionPath).readAsStringSync();
      final productionClass = _productionClass(production);
      final normal = _method(
        productionClass,
        '_prepareNormalApplication',
      ).body.toSource();
      final debugRoot = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();

      const armMethod =
          'armGroupReactionNotificationIosSetupBootstrapReadinessIfConfigured';
      const shareStage =
          'GroupReactionNotificationIosSetupBootstrapStage.shareLaunch';
      const databaseStage =
          'GroupReactionNotificationIosSetupBootstrapStage.database';
      const identityStoreStage =
          'GroupReactionNotificationIosSetupBootstrapStage.identityStore';
      const autoSetupStage =
          'GroupReactionNotificationIosSetupBootstrapStage.autoSetup';

      final documentsProbe = normal.indexOf(
        'final appDocDirProbe = getApplicationDocumentsDirectory()',
      );
      final shareArm = normal.indexOf(shareStage);
      final probeJoin = normal.indexOf('await Future.wait<Object?>(');
      final shareReady = normal.indexOf(
        "StartupTiming.instance.mark('share_launch_probe_complete')",
      );
      final documentsReady = normal.indexOf(
        "StartupTiming.instance.mark('documents_dir_ready')",
      );
      final databaseArm = normal.indexOf(databaseStage);
      final databaseReady = normal.indexOf(
        "StartupTiming.instance.mark('database_ready')",
      );
      final identityStoreArm = normal.indexOf(identityStoreStage);
      final identityStoreReady = normal.indexOf(
        "StartupTiming.instance.mark('identity_store_ready')",
      );
      final autoSetupArm = normal.indexOf(autoSetupStage);
      final autoSetup = normal.indexOf('runSimulatorAutoSetupIfConfigured(');

      expect(documentsProbe, greaterThanOrEqualTo(0));
      expect(
        documentsProbe,
        lessThan(shareArm),
        reason: 'the documents path must exist before its durable receipt arm',
      );
      expect(
        shareArm,
        lessThan(probeJoin),
        reason:
            'a stalled share-intent probe must leave a current-attempt receipt',
      );
      expect(probeJoin, lessThan(shareReady));
      expect(shareReady, lessThan(documentsReady));
      expect(documentsReady, lessThan(databaseArm));
      expect(databaseArm, lessThan(databaseReady));
      expect(databaseReady, lessThan(identityStoreArm));
      expect(identityStoreArm, lessThan(identityStoreReady));
      expect(identityStoreReady, lessThan(autoSetupArm));
      expect(autoSetupArm, lessThan(autoSetup));

      for (final stage in const <String>[
        shareStage,
        databaseStage,
        identityStoreStage,
        autoSetupStage,
      ]) {
        expect(
          stage.allMatches(normal),
          hasLength(1),
          reason: 'each Plan-398 pre-entry boundary has one production owner',
        );
      }
      expect(
        '$armMethod('.allMatches(normal),
        hasLength(4),
        reason: 'ordinary bootstrap must not gain a second receipt owner',
      );

      final armDeclaration = debugRoot.indexOf('$armMethod({');
      final setupDeclaration = debugRoot.indexOf(
        'static Future<void> runSimulatorAutoSetupIfConfigured(',
      );
      expect(armDeclaration, greaterThanOrEqualTo(0));
      expect(setupDeclaration, greaterThan(armDeclaration));
      final armBody = debugRoot.substring(armDeclaration, setupDeclaration);
      for (final exactGate in const <String>[
        'resolveGroupReactionNotificationIosSetupReadinessAttempt(',
        'if (setupReadinessAttempt == null) return;',
        'writeGroupReactionNotificationIosSetupReadinessReceipt(',
      ]) {
        expect(
          armBody,
          contains(exactGate),
          reason: 'pre-entry writer is missing exact gate $exactGate',
        );
      }
    },
  );

  test(
    'DTR-14 production bootstrap owns each reachable phase exactly once',
    () {
      final production = File(_productionPath).readAsStringSync();
      final handler = File(_handlerPath).readAsStringSync();
      final productionClass = _productionClass(production);
      final prepare = _method(productionClass, 'prepare').body.toSource();
      final normalMethod = _method(
        productionClass,
        '_prepareNormalApplication',
      );
      final normal = normalMethod.body.toSource();
      final localBodies = _localFunctionBodies(normalMethod);
      expect(
        localBodies.keys,
        containsAll(<String>['_buildRootWidget', '_afterRunApp']),
      );
      final root = localBodies['_buildRootWidget']!;
      final post = localBodies['_afterRunApp']!;

      final reset = prepare.indexOf('runDisposableResetIfRequested()');
      final inertReturn = prepare.indexOf(
        'return _CallbackPreparedApplication(',
      );
      final normalCall = prepare.lastIndexOf('_prepareNormalApplication()');
      expect(reset, greaterThanOrEqualTo(0));
      expect(inertReturn, greaterThan(reset));
      expect(normalCall, greaterThan(inertReturn));
      expect(prepare, contains('if (resetHandled)'));
      expect(prepare, contains('return prepareOverride();'));

      expect(normal, contains("StartupTiming.instance.mark('app_start')"));
      final firebase = normal.indexOf(
        'final firebaseReadiness = FirebaseReadiness(',
      );
      const backgroundRegistrationToken =
          'FirebaseMessaging.onBackgroundMessage(';
      final backgroundRegistration = normal.indexOf(
        backgroundRegistrationToken,
      );
      final initializerEnd = normal.indexOf(
        "StartupTiming.instance.mark('firebase_ready')",
      );
      expect(firebase, greaterThanOrEqualTo(0));
      expect(backgroundRegistration, greaterThan(firebase));
      expect(initializerEnd, greaterThan(backgroundRegistration));
      expect(
        backgroundRegistrationToken.allMatches(normal),
        hasLength(1),
        reason: 'the successful Firebase initializer registers FCM once',
      );
      expect(
        normal.substring(backgroundRegistration, initializerEnd),
        contains('firebaseMessagingBackgroundHandler'),
      );

      const awaitedPrepopulation =
          'await debugE2EComposition?.prepopulateContactsBeforeRunApp(';
      final prepopulation = root.indexOf(awaitedPrepopulation);
      final myApp = root.indexOf('return MyApp(');
      expect(prepopulation, greaterThanOrEqualTo(0));
      expect(myApp, greaterThan(prepopulation));
      for (final moveAccountBinding in const <String>[
        'accountMigrationRunTransfer:',
        'accountMigrationTransferRuntime.runOldPhoneTransfer',
        'accountMigrationSizeGate: accountMigrationSizeGate',
        'accountMigrationStartReceiver:',
        'accountMigrationTransferRuntime.startNewPhoneReceiver',
        'accountMigrationStopReceiver:',
        'accountMigrationTransferRuntime.stopNewPhoneReceiver',
        'accountMigrationReceiverEvents:',
        'accountMigrationTransferRuntime.receiverEvents',
        'accountMigrationRecoverExportPause:',
        'restoreActiveAfterExportInterrupted()',
      ]) {
        expect(
          moveAccountBinding.allMatches(root),
          hasLength(1),
          reason: 'reachable MyApp construction must bind $moveAccountBinding',
        );
      }

      final sender = post.indexOf('startIosSenderProjectionAfterRunApp(');
      final runAppCalled = post.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      final recovery = post.indexOf('ensurePrivateMediaColdRecovery()');
      final postsSweep = post.indexOf('sweepExpiredPosts(');
      final invitesSweep = post.indexOf('sweepExpiredGroupInvites(');
      final deletionReconciliation = post.indexOf(
        'groupMediaDeletionReconciler.runBounded()',
      );
      final poller = post.indexOf('startIntroPollerAfterColdRecovery(');
      expect(sender, greaterThanOrEqualTo(0));
      expect(runAppCalled, greaterThan(sender));
      expect(recovery, greaterThan(runAppCalled));
      expect(postsSweep, greaterThan(runAppCalled));
      expect(invitesSweep, greaterThan(runAppCalled));
      expect(deletionReconciliation, greaterThan(runAppCalled));
      expect(poller, greaterThan(runAppCalled));
      for (final postLaunchPhase in const <String>[
        'startIosSenderProjectionAfterRunApp(',
        "StartupTiming.instance.mark('run_app_called')",
        'ensurePrivateMediaColdRecovery()',
        'sweepExpiredPosts(',
        'sweepExpiredGroupInvites(',
        'groupMediaDeletionReconciler.runBounded()',
        'startIntroPollerAfterColdRecovery(',
      ]) {
        expect(
          postLaunchPhase.allMatches(post),
          hasLength(1),
          reason:
              'post-launch phase must remain reachable exactly once: '
              '$postLaunchPhase',
        );
      }

      expect(
        normal,
        matches(
          RegExp(
            r'buildRootWidget:\s*_buildRootWidget,\s*'
            r'afterRunApp:\s*_afterRunApp',
          ),
        ),
      );
      expect(production, isNot(contains('runApp(')));

      expect(handler, contains("@pragma('vm:entry-point')"));
      expect(
        handler,
        contains('Future<void> firebaseMessagingBackgroundHandler('),
      );
      expect(handler, isNot(contains('application_bootstrap.dart')));
      expect(handler, isNot(contains('production_application_bootstrap.dart')));
      expect(
        handler,
        isNot(contains("import 'package:flutter_app/main.dart'")),
      );
    },
  );

  test(
    'TC-354-05e production wires private retention before strict download',
    () {
      final production = File(_productionPath).readAsStringSync();

      // The drain's incoming-download policy callback is the only place the
      // startup path can reach the strict owner. Plan 354 requires it to
      // retain a protected/View-Once parent WITHOUT network, so its explicit
      // user-intent boundary in downloadMedia stays the sole entry.
      final callback = production.indexOf(
        'retryIncomingDownload: (row) async {',
      );
      expect(
        callback,
        greaterThan(-1),
        reason: 'the drain must own one explicit incoming-download policy',
      );
      final callbackEnd = production.indexOf(
        'strictDownloadAckOwner',
        callback,
      );
      final scanEnd = callbackEnd > callback ? callbackEnd : production.length;
      final body = production.substring(
        callback,
        (callback + 4000) < scanEnd ? callback + 4000 : scanEnd,
      );
      expect(
        body.contains('directMediaBlobDrainMayDownloadIncomingParent(parent)'),
        isTrue,
        reason:
            'the drain must consult the ONE shared predicate; a redacted '
            'parent is retained without network by design',
      );
      final redactionGuard = body.indexOf(
        'directMediaBlobDrainMayDownloadIncomingParent(parent)',
      );
      // The guard must return false (retain) rather than fall through.
      expect(body.substring(redactionGuard).contains('return false;'), isTrue);

      // The private strict entry lives behind explicit user intent in the
      // download use case, and it claims the transfer token plus the DB
      // downloading claim before the strict owner is constructed.
      final downloadSource = File(
        'lib/features/conversation/application/download_media_use_case.dart',
      ).readAsStringSync();
      final privateEntry = downloadSource.indexOf(
        'requiresDirectPrivateCommit &&\n      effectiveIntent == MediaDownloadIntent.explicitUser',
      );
      expect(
        privateEntry,
        greaterThan(-1),
        reason: 'the private strict entry must require explicit user intent',
      );
      final entryBody = downloadSource.substring(
        privateEntry,
        privateEntry + 8200,
      );
      final claimIndex = entryBody.indexOf(
        'beginDirectPrivateMediaDownloadWithinLock',
      );
      final tokenIndex = entryBody.indexOf(
        'directPrivateMediaTransferRegistry.tryBegin',
      );
      final ownerIndex = entryBody.indexOf('attachment: claim.row,');
      expect(tokenIndex, greaterThan(-1));
      expect(claimIndex, greaterThan(tokenIndex));
      expect(
        ownerIndex,
        greaterThan(claimIndex),
        reason:
            'the transfer token and the DB downloading claim must both be '
            'acquired BEFORE the strict owner can make its first network call',
      );
      expect(
        entryBody.contains('privateDeterministicStaging: true'),
        isTrue,
        reason:
            'the private entry must use the deterministic convention-owned '
            'staging pair private cleanup can enumerate',
      );
    },
  );
  test('TC-355-04e production notification policies exclude terminal private '
      'media', () {
    final production = File(_productionPath).readAsStringSync();
    final canonicalDirectProjection = File(
      _canonicalDirectProjectionPath,
    ).readAsStringSync();

    expect(
      'buildProductionCanonicalDirectProjectionComposition('.allMatches(
        production,
      ),
      hasLength(1),
      reason:
          'foreground must delegate to the one canonical direct projection '
          'composition shared with headless recovery',
    );

    // 1. Canonical KEEP: a consumed/expired private parent must be retired
    //    from canonical notification history like a deleted one.
    final keep = canonicalDirectProjection.indexOf(
      'DirectNotificationCanonicalContentDecision.keep',
    );
    expect(keep, greaterThan(-1));
    final keepStart = canonicalDirectProjection.lastIndexOf(
      'return message.contactPeerId',
      keep,
    );
    expect(keepStart, greaterThan(-1));
    final keepBody = canonicalDirectProjection.substring(keepStart, keep);
    for (final guard in const <String>[
      'message.isIncoming',
      'message.readAt == null',
      '!message.isDeleted',
      'message.hiddenAt == null',
      '!message.privateMediaState.isTerminal',
    ]) {
      expect(
        keepBody.contains(guard),
        isTrue,
        reason: 'canonical keep must require: \$guard',
      );
    }

    // 2. Display PROJECTION: the same terminal states suppress the card.
    final projection = canonicalDirectProjection.indexOf(
      'projectDisplay: (entry) async {',
    );
    expect(projection, greaterThan(-1));
    final messageProjection = canonicalDirectProjection.indexOf(
      'case DirectNotificationDisplayOutboxKind.message:',
      projection,
    );
    expect(messageProjection, greaterThan(projection));
    final projectionBody = canonicalDirectProjection.substring(
      messageProjection,
      canonicalDirectProjection.indexOf(
        'final presentation = await maybeShowNotification(',
        messageProjection,
      ),
    );
    for (final guard in const <String>[
      'message.isDeleted',
      'message.hiddenAt != null',
      'message.privateMediaState.isTerminal',
    ]) {
      expect(
        projectionBody.contains(guard),
        isTrue,
        reason: 'display projection must suppress: $guard',
      );
    }

    // 3. REPLACEMENT: the shared canonical snapshot builder filters the
    //    same terminal states before any replacement is produced.
    final snapshot = File(
      'lib/features/conversation/application/'
      'direct_conversation_notification_snapshot.dart',
    ).readAsStringSync();
    for (final guard in const <String>[
      '!message.isDeleted',
      '!message.isHidden',
      '!message.privateMediaState.isTerminal',
    ]) {
      expect(
        snapshot.contains(guard),
        isTrue,
        reason: 'canonical replacement must exclude: \$guard',
      );
    }

    // 4. The drain wires the ONE shared predicate rather than a copy.
    expect(
      'directMediaBlobDrainMayDownloadIncomingParent('.allMatches(production),
      hasLength(1),
    );
  });

  group('TC-360-01a role-aware deferred runtime start', () {
    LinkedInstallationAuthoritySnapshot snapshot(
      LinkedInstallationDisposition disposition,
    ) {
      return LinkedInstallationAuthoritySnapshot(
        disposition: disposition,
        credential: disposition == LinkedInstallationDisposition.active
            ? const LinkedTransportCredential(
                state: LinkedTransportCredentialState.active,
                accountPeerId: 'account-peer',
                accountPublicKey: 'account-public-key',
                deviceId: 'installation-1',
                transportPeerId: 'transport-peer',
                transportPublicKey: 'transport-public-key',
                transportPrivateKey: 'transport-private-key',
                createdAt: '2026-01-01T00:00:00.000Z',
                activatedAt: '2026-01-01T00:00:00.000Z',
              )
            : null,
        failClosedReason:
            disposition == LinkedInstallationDisposition.failClosed
            ? 'corrupt_credential'
            : null,
      );
    }

    test('TC-360-01a linked-secondary transport identity is distinct stable '
        'and fail-closed', () async {
      var primaryStarts = 0;
      var linkedFoundationStarts = 0;

      RoleAwareDeferredRuntimeStart build(
        LinkedInstallationDisposition disposition,
      ) {
        return RoleAwareDeferredRuntimeStart(
          loadLinkedAuthority: () async => snapshot(disposition),
          startPrimaryRuntimeServices: () async {
            primaryStarts += 1;
            return true;
          },
          startLinkedFoundationPrerequisites: () async {
            linkedFoundationStarts += 1;
            return true;
          },
        );
      }

      // ── Ordinary primary keeps the incumbent full runtime startup. ──
      final primary = build(LinkedInstallationDisposition.primary);
      expect(await primary.start(), isTrue);
      expect(primaryStarts, 1);
      expect(linkedFoundationStarts, 0);
      expect(
        primary.lastOutcome,
        RoleAwareRuntimeStartOutcome.primaryRuntimeStarted,
      );

      // ── Active linked secondary starts ONLY the foundation prerequisites
      // and calls generic runtime startup ZERO times.
      //
      // Firebase/push registration, the listener fleet, contact and
      // key-exchange retry, group recovery, message retry and inbox drain all
      // assume a single primary installation on one account mailbox. Plan 361
      // makes them device-aware; until then they must not run here. ──
      primaryStarts = 0;
      linkedFoundationStarts = 0;
      final linked = build(LinkedInstallationDisposition.active);
      expect(await linked.start(), isTrue);
      expect(
        primaryStarts,
        0,
        reason: 'generic runtime startup must run zero times in linked mode',
      );
      expect(linkedFoundationStarts, 1);
      expect(
        linked.lastOutcome,
        RoleAwareRuntimeStartOutcome.linkedFoundationStarted,
      );

      // ── Partial or fail-closed authority starts NEITHER path. ──
      for (final disposition in const <LinkedInstallationDisposition>[
        LinkedInstallationDisposition.awaitingCredential,
        LinkedInstallationDisposition.preparing,
        LinkedInstallationDisposition.failClosed,
      ]) {
        primaryStarts = 0;
        linkedFoundationStarts = 0;
        final refused = build(disposition);
        expect(await refused.start(), isFalse, reason: disposition.name);
        expect(primaryStarts, 0, reason: disposition.name);
        expect(linkedFoundationStarts, 0, reason: disposition.name);
        expect(
          refused.lastOutcome,
          RoleAwareRuntimeStartOutcome.refused,
          reason: disposition.name,
        );
      }

      // ── The logical ACCOUNT peer is published too, and the P2P service is
      // asked about THAT peer by the account-migration gate — never the
      // transport peer, which account authority does not cover. ──
      final wiring = File(_productionPath).readAsStringSync();
      final accountPublisher = build(LinkedInstallationDisposition.active);
      await accountPublisher.start();
      expect(accountPublisher.activeLinkedAccountPeerId, 'account-peer');
      final accountRefuser = build(LinkedInstallationDisposition.preparing);
      await accountRefuser.start();
      expect(accountRefuser.activeLinkedAccountPeerId, isNull);
      expect(
        build(LinkedInstallationDisposition.primary).activeLinkedAccountPeerId,
        isNull,
      );
      expect(wiring, contains('logicalAccountPeerId: () =>'));
      expect(wiring, contains('activeLinkedAccountPeerId,'));

      // ── Bootstrap binds the authority load to the CURRENT account peer.
      // Without it a credential bound to a DIFFERENT logical account resolves
      // as a usable `active` snapshot instead of `failClosed`. ──
      expect(
        wiring,
        allOf(
          contains('return linkedInstallationAuthority.load('),
          contains('expectedAccountPeerId: identity?.peerId,'),
        ),
      );

      // ── Both Move protections are on the REAL journey, not just injected
      // helpers. ──
      expect(
        wiring,
        contains('accountMigrationStartReceiver: (output) async {'),
      );
      expect(wiring, contains('evaluateAccountMigrationImportPrecondition('));
      expect(wiring, contains('.linkedSecondaryInstallation'));
      expect(
        File(
          'lib/features/account_migration/presentation/screens/'
          'account_migration_journey_wired.dart',
        ).readAsStringSync(),
        contains('linkedInstallationAuthority: LinkedInstallationAuthority('),
        reason: 'the real export decision must receive the linked guard',
      );

      // ── The restricted setup route and the known-contact scan action are
      // supplied by the production composition roots, so the authority is
      // reachable rather than dead code behind a default-off flag. ──
      expect(
        File(
          'lib/features/identity/presentation/startup_router.dart',
        ).readAsStringSync(),
        contains('linkedDeviceSetupBuilder: (_) => LinkedDeviceSetupWired('),
      );
      expect(
        File(
          'lib/features/orbit/presentation/screens/orbit_wired.dart',
        ).readAsStringSync(),
        contains('onDirectLinkedDeviceQrScanned:'),
      );

      // ── An unreadable authority is fail-closed, never "assume primary".
      primaryStarts = 0;
      linkedFoundationStarts = 0;
      final throwing = RoleAwareDeferredRuntimeStart(
        loadLinkedAuthority: () async => throw StateError('keystore down'),
        startPrimaryRuntimeServices: () async {
          primaryStarts += 1;
          return true;
        },
        startLinkedFoundationPrerequisites: () async {
          linkedFoundationStarts += 1;
          return true;
        },
      );
      expect(await throwing.start(), isFalse);
      expect(primaryStarts, 0);
      expect(linkedFoundationStarts, 0);

      // ── The decision is wired PRE-ROUTER: production bootstrap hands the
      // role-aware owner to the one unconditional `deferredRuntimeStartup`
      // callback `MyApp.initState` invokes. Deciding later, at navigation
      // time, would be a race — the deferred start has already fired. ──
      final productionSource = File(_productionPath).readAsStringSync();
      expect(
        productionSource,
        contains('deferredRuntimeStartup: roleAwareDeferredRuntimeStart.start'),
      );
      expect(
        productionSource,
        isNot(contains('deferredRuntimeStartup: startLiveServicesIfAllowed')),
      );
      expect(
        File(_applicationRootPath).readAsStringSync(),
        contains('startRuntime: widget.deferredRuntimeStartup'),
        reason:
            'ApplicationRoot keeps its incumbent unconditional callback; only '
            'what it delegates to changed',
      );
    });
  });

  test(
    'TC-373-02b active linked iOS registers its exact physical paired route without starting unrelated live services',
    () async {
      var firebaseReady = false;
      var registrationStarts = 0;
      var primaryStarts = 0;
      var restrictedOwnerStarts = 0;
      var unrelatedStarts = 0;

      final linkedServices = DirectBlobFreeLinkedServices(
        initializeBridge: () async {},
        startMessageRouter: () => restrictedOwnerStarts += 1,
        startChatMessageListener: () => restrictedOwnerStarts += 1,
        startReactionListener: () => restrictedOwnerStarts += 1,
        startMessageDeletionListener: () => restrictedOwnerStarts += 1,
        startDeliveryReceiptListener: () => restrictedOwnerStarts += 1,
        startLinkedTransport: () async => true,
        afterLinkedTransportQualified: () async {
          if (!firebaseReady) throw StateError('Firebase not ready');
          registrationStarts += 1;
        },
        drainOfflineInbox: () async {},
        drainExactBlobFreeFanoutOutboxes: () async => 0,
      );
      final runtime = RoleAwareDeferredRuntimeStart(
        loadLinkedAuthority: () async =>
            const LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.active,
              credential: LinkedTransportCredential(
                state: LinkedTransportCredentialState.active,
                accountPeerId: 'account-peer',
                accountPublicKey: 'account-public-key',
                deviceId: 'linked-device',
                transportPeerId: 'transport-peer',
                transportPublicKey: 'transport-public-key',
                transportPrivateKey: 'transport-private-key',
                createdAt: '2026-08-16T00:00:00.000Z',
                activatedAt: '2026-08-16T00:00:00.000Z',
              ),
              failClosedReason: null,
            ),
        startPrimaryRuntimeServices: () async {
          primaryStarts += 1;
          unrelatedStarts += 1;
          return true;
        },
        startLinkedFoundationPrerequisites: linkedServices.start,
      );

      // A transient Firebase/readiness miss must not publish a successful role
      // outcome or permanently latch the deferred startup owner.
      expect(await runtime.start(), isFalse);
      expect(runtime.lastOutcome, isNull);
      expect(runtime.activeLinkedTransportPeerId, 'transport-peer');
      expect(registrationStarts, 0);
      expect(primaryStarts, 0);
      expect(unrelatedStarts, 0);

      firebaseReady = true;
      expect(await runtime.start(), isTrue);
      expect(
        runtime.lastOutcome,
        RoleAwareRuntimeStartOutcome.linkedFoundationStarted,
      );
      expect(registrationStarts, 1);
      expect(primaryStarts, 0);
      expect(unrelatedStarts, 0);
      expect(restrictedOwnerStarts, 10);

      // The ordinary-primary owner has the same retry contract. Listener
      // arming belongs to the latch's successful-runtime callback, so a false
      // first attempt cannot consume the only post-Firebase arm opportunity.
      var primaryAttempts = 0;
      var listenerArms = 0;
      final retryingPrimary = RoleAwareDeferredRuntimeStart(
        loadLinkedAuthority: () async =>
            const LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.primary,
              credential: null,
              failClosedReason: null,
            ),
        startPrimaryRuntimeServices: () async => ++primaryAttempts > 1,
        startLinkedFoundationPrerequisites: () async => false,
      );
      final primaryLatch = AccountMigrationRuntimeStartupLatch(
        startRuntime: retryingPrimary.start,
        onStarted: () => listenerArms += 1,
      );
      await primaryLatch.ensureStarted();
      expect(primaryAttempts, 1);
      expect(listenerArms, 0);
      expect(retryingPrimary.lastOutcome, isNull);
      await primaryLatch.ensureStarted();
      expect(primaryAttempts, 2);
      expect(listenerArms, 1);
      expect(
        retryingPrimary.lastOutcome,
        RoleAwareRuntimeStartOutcome.primaryRuntimeStarted,
      );

      final source = File(_productionPath).readAsStringSync();
      final hook = source.indexOf('afterLinkedTransportQualified:');
      final drain = source.indexOf('drainOfflineInbox:', hook);
      expect(hook, isNonNegative);
      expect(drain, greaterThan(hook));
      final exactHook = source.substring(hook, drain);
      // Plan 375: the one linked hook is platform-parameterized (iOS and
      // Android), reads the shared live consumer readiness before Firebase or
      // registration work, and still owns zero raw registration paths.
      expect(exactHook, contains('(Platform.isIOS || Platform.isAndroid)'));
      expect(
        exactHook,
        contains(
          'opaqueWakePlatformConsumerReadiness.isReadyFor(\n'
          '                    platformName,',
        ),
      );
      expect(
        exactHook,
        contains(r'linked $platformName Firebase is not ready'),
      );
      expect(exactHook, contains('await registration.ensureStarted();'));
      expect(exactHook, isNot(contains('registerPushToken(')));
      final appRoot = File(_applicationRootPath).readAsStringSync();
      final latchStart = appRoot.indexOf(
        'runtimeStartupLatch = AccountMigrationRuntimeStartupLatch(',
      );
      final latchEnd = appRoot.indexOf(
        '_setPresenceUseCase = SetPresenceUseCase(',
        latchStart,
      );
      final latchSource = appRoot.substring(latchStart, latchEnd);
      expect(
        latchSource,
        contains('_armPushListenersAfterSuccessfulRuntimeStart();'),
      );
      expect(
        appRoot,
        allOf(
          contains('bool _firebaseReadinessListenerInstalled = false;'),
          contains('readiness.addOnReadyListener(() {'),
          contains('if (mounted) _setupPushListeners();'),
        ),
      );
      expect(
        source,
        allOf(
          contains('publishQualifiedIosNseTransport:'),
          contains('iosNseInboxTransportProjection.publishAndReadBack('),
        ),
      );
    },
  );

  testWidgets(
    'TC-364-04a linked runtime exposes only protected blob-free group content',
    (tester) async {
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      final phases = <String>[];
      final phaseQuiescence = ProtectedGroupContentRuntimeQuiescence(
        pauseInboundAdmission: () async => phases.add('pause'),
        resumeInboundAdmission: () => phases.add('resume'),
      );
      final runtime = DirectBlobFreeLinkedServices(
        initializeBridge: () async => phases.add('bridge'),
        startMessageRouter: () => phases.add('router'),
        startChatMessageListener: () => phases.add('chat'),
        startReactionListener: () => phases.add('reaction'),
        startMessageDeletionListener: () => phases.add('deletion'),
        startDeliveryReceiptListener: () => phases.add('receipt'),
        startLinkedTransport: () async {
          phases.add('transport');
          return true;
        },
        pauseLinkedGroupContentAdmission: phaseQuiescence.pause,
        drainOfflineInbox: () async => phases.add('inbox'),
        materializeLinkedGroupBootstrap: () async => phases.add('bootstrap'),
        replayLinkedGroupAuthority: () async => phases.add('authority'),
        resumeLinkedGroupContentAdmission: (contentPause) =>
            contentPause.resume(),
        replayLinkedGroupContent: () async {
          phases.add('content');
          return 2;
        },
        retryLinkedGroupContent: () async {
          phases.add('retry');
          return 1;
        },
        drainLinkedGroupNotificationDisplayCustody: () async =>
            phases.add('notification'),
        refreshLinkedGroupList: () async => phases.add('refresh'),
        drainExactBlobFreeFanoutOutboxes: () async {
          phases.add('direct');
          return 0;
        },
      );
      expect(await runtime.start(), isTrue);
      expect(phases, <String>[
        'bridge',
        'router',
        'chat',
        'reaction',
        'deletion',
        'receipt',
        'transport',
        'pause',
        'inbox',
        'bootstrap',
        'authority',
        'resume',
        'content',
        'retry',
        'notification',
        'refresh',
        'direct',
      ]);

      final refusedRecovery = <String>[];
      final refusedRuntime = DirectBlobFreeLinkedServices(
        initializeBridge: () async => refusedRecovery.add('bridge'),
        startMessageRouter: () => refusedRecovery.add('router'),
        startChatMessageListener: () => refusedRecovery.add('chat'),
        startReactionListener: () => refusedRecovery.add('reaction'),
        startMessageDeletionListener: () => refusedRecovery.add('deletion'),
        startDeliveryReceiptListener: () => refusedRecovery.add('receipt'),
        startLinkedTransport: () async {
          refusedRecovery.add('transport-refused');
          return false;
        },
        drainOfflineInbox: () async => refusedRecovery.add('must-not-drain'),
        drainExactBlobFreeFanoutOutboxes: () async {
          refusedRecovery.add('must-not-fanout');
          return 0;
        },
      );
      expect(await refusedRuntime.start(), isFalse);
      expect(refusedRecovery, <String>[
        'bridge',
        'router',
        'chat',
        'reaction',
        'deletion',
        'receipt',
        'transport-refused',
      ]);

      // Pause closes outgoing admission before its first await and then joins
      // the in-flight protected store/CAS with inbound replay quiescence.
      final custodyRows = <String>['strict-row'];
      final storeEntered = Completer<void>();
      final releaseStore = Completer<void>();
      final lifecycle = <String>[];
      var retryStarts = 0;
      final quiescence = ProtectedGroupContentRuntimeQuiescence(
        pauseInboundAdmission: () async {
          lifecycle.add('inbound-paused');
        },
        resumeInboundAdmission: () {
          lifecycle.add('inbound-resumed');
        },
      );
      Future<int> retry() => quiescence.runOutgoing<int>(
        blockedValue: 0,
        operation: () async {
          retryStarts += 1;
          lifecycle.add('retry-$retryStarts');
          if (retryStarts == 1) {
            storeEntered.complete();
            await releaseStore.future;
            return 0;
          }
          custodyRows.clear();
          return 1;
        },
      );

      final heldRetry = retry();
      await storeEntered.future;
      var pauseCompleted = false;
      var pauseFlushStarts = 0;
      final pauseLease = quiescence.pause();
      final pause = pauseLease.quiesced.then<void>((_) async {
        pauseCompleted = true;
        pauseFlushStarts += 1;
      });
      await tester.pump();
      expect(lifecycle, contains('inbound-paused'));
      expect(pauseCompleted, isFalse);
      expect(pauseFlushStarts, 0, reason: 'pause flush waits for held custody');
      expect(await retry(), 0, reason: 'paused admission starts no new retry');
      expect(retryStarts, 1);
      expect(custodyRows, <String>['strict-row']);

      releaseStore.complete();
      expect(await heldRetry, 0);
      await pause;
      expect(pauseCompleted, isTrue);
      expect(pauseFlushStarts, 1);
      expect(await retry(), 0, reason: 'pause stays closed after draining');
      expect(await pauseLease.resume(), isTrue);
      expect(lifecycle.last, 'inbound-resumed');
      expect(await retry(), 1);
      expect(retryStarts, 2);
      expect(custodyRows, isEmpty, reason: 'resumed retry converges custody');

      // Lifecycle callbacks are unawaited. A newer background pause must
      // invalidate an older resume recovery before it can reopen admission.
      final resumeDrainGate = Completer<void>();
      final resumeRecoveryPause = quiescence.pause();
      await resumeRecoveryPause.quiesced;
      final staleResume = (() async {
        await resumeDrainGate.future;
        return resumeRecoveryPause.resume();
      })();
      final newerBackgroundPause = quiescence.pause();
      await newerBackgroundPause.quiesced;
      resumeDrainGate.complete();
      expect(await staleResume, isFalse);
      expect(
        lifecycle.where((phase) => phase == 'inbound-resumed'),
        hasLength(1),
      );
      expect(await retry(), 0, reason: 'newer pause remains closed');
      expect(retryStarts, 2);

      final nextResumePause = quiescence.pause();
      await nextResumePause.quiesced;
      expect(await nextResumePause.resume(), isTrue);
      expect(await retry(), 1);
      expect(retryStarts, 3);

      final independentRuntime = ProtectedGroupContentRuntimeQuiescence(
        pauseInboundAdmission: () async {},
        resumeInboundAdmission: () {},
      );
      expect(
        await independentRuntime.runOutgoing<int>(
          blockedValue: 0,
          operation: () async => 7,
        ),
        7,
        reason: 'pause state is runtime-local, never process-global',
      );

      final group = GroupModel(
        id: 'linked-group',
        name: 'Linked',
        type: GroupType.chat,
        topicName: 'unused-topic',
        createdAt: DateTime.utc(2026, 8, 13),
        createdBy: 'peer-a',
        myRole: GroupRole.member,
      );
      final ordinary = GroupMessage(
        id: 'ordinary',
        groupId: group.id,
        senderPeerId: 'peer-a',
        text: 'ordinary text',
        timestamp: DateTime.utc(2026, 8, 13),
        createdAt: DateTime.utc(2026, 8, 13),
      );
      var currentProjection = group;
      final markedReadGroupIds = <String>[];
      final tracker = ActiveConversationTracker();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LinkedGroupConversationWired(
            group: group,
            loadCurrentGroup: (_) async => currentProjection,
            loadProtectedMessages: (_) async => <GroupMessage>[ordinary],
            loadProtectedReactions: (_) async => const {},
            markVisibleMessagesRead: (groupId, messageIds) async {
              expectSync(messageIds, <String>[ordinary.id]);
              markedReadGroupIds.add(groupId);
            },
            groupConversationTracker: tracker,
            isAuthoritySettled: (_) async => true,
            canAuthorProtectedContent: (_) async => true,
            sendProtectedText: (_, _) async => true,
            toggleProtectedReaction:
                ({
                  required groupId,
                  required message,
                  required emoji,
                  required remove,
                }) async => true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(markedReadGroupIds, <String>[group.id]);
      expect(find.text('Write something...'), findsOneWidget);
      currentProjection = group.copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 8, 13, 1),
        dissolvedBy: 'peer-a',
      );
      await refreshLinkedGroupStatusProjection();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-read-only-banner')),
        findsOneWidget,
      );
      expect(find.text('Write something...'), findsNothing);
      expect(isEligibleLinkedProtectedGroupMessage(group, ordinary), isTrue);
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group.copyWith(type: GroupType.announcement),
          ordinary,
        ),
        isTrue,
        reason: 'ordinary announcement rows remain reaction eligible',
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group.copyWith(type: GroupType.qa),
          ordinary,
        ),
        isFalse,
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group,
          ordinary.copyWith(text: r'{"__sys":"member_removed"}'),
        ),
        isFalse,
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group,
          ordinary.copyWith(quotedMessageId: 'parent'),
        ),
        isTrue,
        reason: 'ordinary quoted rows remain protected-content eligible',
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group,
          ordinary.copyWith(isForwarded: true),
        ),
        isFalse,
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group,
          ordinary.copyWith(
            privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          ),
        ),
        isFalse,
      );
      expect(
        isEligibleLinkedProtectedGroupMessage(
          group,
          ordinary.copyWith(
            media: const <MediaAttachment>[
              MediaAttachment(
                id: 'blob',
                messageId: 'ordinary',
                mime: 'image/jpeg',
                size: 1,
                mediaType: 'image',
                downloadStatus: 'done',
                createdAt: '2026-08-13T00:00:00.000Z',
              ),
            ],
          ),
        ),
        isFalse,
      );

      final evidencedMessage = ordinary.copyWith(
        transportPeerId: 'transport-a',
        logicalDeliveryId: ordinary.id,
        keyGeneration: 1,
      );
      final messageAt = fixedGroupContentUtc(evidencedMessage.timestamp);
      final messageEvidence = <String, Object?>{
        'group_id': group.id,
        'event_type': protectedGroupMessageEventType,
        'source_peer_id': evidencedMessage.senderPeerId,
        'source_event_id': protectedGroupMessageSourceEventId(
          evidencedMessage.id,
        ),
        'source_timestamp': messageAt,
        'canonical_payload': jsonEncode(<String, Object?>{
          'custodyKind': groupContentCustodyKind,
          'groupId': group.id,
          'payloadType': groupOfflineReplayPayloadTypeMessage,
          'contentEventId': evidencedMessage.id,
          'logicalSenderPeerId': evidencedMessage.senderPeerId,
          'senderTransportPeerId': evidencedMessage.transportPeerId,
          'authorityKeyEpoch': evidencedMessage.keyGeneration,
          'payload': <String, Object?>{
            'groupId': group.id,
            'messageId': evidencedMessage.id,
            'senderId': evidencedMessage.senderPeerId,
            'transportPeerId': evidencedMessage.transportPeerId,
            'logicalDeliveryId': evidencedMessage.logicalDeliveryId,
            'keyEpoch': evidencedMessage.keyGeneration,
            'text': evidencedMessage.text,
            'timestamp': messageAt,
          },
        }),
      };
      expect(
        isExactLinkedProtectedMessageEvidence(
          groupId: group.id,
          message: evidencedMessage,
          evidenceRow: messageEvidence,
          terminalRows: const [],
        ),
        isTrue,
      );
      expect(
        isExactLinkedProtectedMessageEvidence(
          groupId: group.id,
          message: evidencedMessage.copyWith(text: 'legacy mutation'),
          evidenceRow: messageEvidence,
          terminalRows: const [],
        ),
        isFalse,
      );
      final messageTerminal = <String, Object?>{
        'group_id': group.id,
        'event_type': protectedGroupContentTerminalEventType,
        'canonical_payload': jsonEncode(<String, Object?>{
          'reasonCode': 'authority_reconciliation_invalidated',
          'payloadType': groupOfflineReplayPayloadTypeMessage,
          'contentEventId': evidencedMessage.id,
        }),
      };
      expect(
        isExactLinkedProtectedMessageEvidence(
          groupId: group.id,
          message: evidencedMessage,
          evidenceRow: messageEvidence,
          terminalRows: [messageTerminal],
        ),
        isFalse,
      );

      Map<String, Object?> reactionEvidence({
        required String action,
        required DateTime authoredAt,
      }) {
        final timestamp = fixedGroupContentUtc(authoredAt);
        final transition = buildGroupReactionTransitionId(
          groupId: group.id,
          messageId: evidencedMessage.id,
          logicalActorPeerId: 'peer-a',
          action: action,
          emoji: '👍',
          timestamp: authoredAt,
        );
        final payload = <String, Object?>{
          'id': deterministicGroupReactionStateId(
            groupId: group.id,
            messageId: evidencedMessage.id,
            logicalActorPeerId: 'peer-a',
          ),
          'messageId': evidencedMessage.id,
          'emoji': '👍',
          'action': action,
          'senderPeerId': 'peer-a',
          'timestamp': timestamp,
          'eventId': transition,
        };
        return <String, Object?>{
          'group_id': group.id,
          'event_type': protectedGroupReactionEventType,
          'source_peer_id': 'peer-a',
          'source_event_id': protectedGroupReactionSourceEventId(transition),
          'source_timestamp': timestamp,
          'canonical_payload': jsonEncode(<String, Object?>{
            'custodyKind': groupContentCustodyKind,
            'groupId': group.id,
            'payloadType': groupOfflineReplayPayloadTypeReaction,
            'contentEventId': transition,
            'logicalSenderPeerId': 'peer-a',
            'payload': payload,
          }),
        };
      }

      final addEvidence = reactionEvidence(
        action: 'add',
        authoredAt: DateTime.utc(2026, 8, 13, 12),
      );
      final addPayload =
          jsonDecode(addEvidence['canonical_payload']! as String)['payload']
              as Map<String, dynamic>;
      final reaction = MessageReaction(
        id: addPayload['id'] as String,
        messageId: addPayload['messageId'] as String,
        emoji: addPayload['emoji'] as String,
        senderPeerId: addPayload['senderPeerId'] as String,
        timestamp: addPayload['timestamp'] as String,
        createdAt: addPayload['timestamp'] as String,
      );
      expect(
        isExactLinkedProtectedReactionEvidence(
          groupId: group.id,
          reaction: reaction,
          evidenceRows: [addEvidence],
          terminalRows: const [],
        ),
        isTrue,
      );
      expect(
        isExactLinkedProtectedReactionEvidence(
          groupId: group.id,
          reaction: reaction,
          evidenceRows: [
            addEvidence,
            reactionEvidence(
              action: 'remove',
              authoredAt: DateTime.utc(2026, 8, 13, 12, 0, 1),
            ),
          ],
          terminalRows: const [],
        ),
        isFalse,
        reason: 'the latest exact transition, including REMOVE, owns display',
      );

      final production = File(_productionPath).readAsStringSync();
      final sharedProtectedReplay = File(
        'lib/app/bootstrap/'
        'production_canonical_group_replay_composition.dart',
      ).readAsStringSync();
      final root = File(_applicationRootPath).readAsStringSync();
      final restrictedRuntime = File(
        'lib/app/bootstrap/direct_blob_free_linked_services.dart',
      ).readAsStringSync();
      final list = File(
        'lib/features/identity/presentation/screens/'
        'linked_device_setup_wired.dart',
      ).readAsStringSync();
      final narrow = File(
        'lib/features/groups/presentation/screens/'
        'linked_group_conversation_wired.dart',
      ).readAsStringSync();
      expect(
        'replayLinkedGroupContent:'.allMatches(production),
        hasLength(2),
        reason: 'cold and resume composition both reach the fixed point',
      );
      expect(
        'strictContentOnly: true'.allMatches(production),
        hasLength(2),
        reason: 'the restricted retry can never drain legacy group work',
      );
      expect(
        'linkedGroupContentQuiescence.runOutgoing<int>('.allMatches(production),
        hasLength(2),
        reason: 'cold and resume strict retries share one runtime pause owner',
      );
      expect(
        'linkedGroupContentQuiescence.runOutgoing<bool>('.allMatches(
          production,
        ),
        hasLength(2),
        reason: 'fresh linked message and reaction custody share that owner',
      );
      expect(
        'linkedGroupContentQuiescence.pause'.allMatches(production),
        hasLength(2),
      );
      expect('contentPause.resume()'.allMatches(production), hasLength(2));
      final resumeFixedPointStages = <int>[
        root.indexOf('await widget.replayLinkedGroupAuthority?.call();'),
        root.indexOf(
          'final groupDrain = await '
          'drainProtectedGroupContentMediaFixedPoint(',
        ),
        root.indexOf('replayContent: widget.replayLinkedGroupContent,'),
        root.indexOf(
          'drainOutgoingMedia: widget.drainLinkedGroupOutgoingMedia,',
        ),
        root.indexOf('retryContent: widget.retryLinkedGroupContent,'),
        root.indexOf(
          'drainIncomingMedia: widget.drainLinkedGroupIncomingMedia,',
        ),
        root.indexOf(
          'await widget.drainLinkedGroupNotificationDisplayCustody?.call();',
        ),
        root.indexOf('await widget.refreshLinkedGroupList?.call();'),
        root.indexOf(
          'await widget.drainDirectBlobFreeLinkedOutboxes?.call() ?? 0;',
        ),
      ];
      expect(resumeFixedPointStages, everyElement(greaterThanOrEqualTo(0)));
      expect(
        resumeFixedPointStages,
        orderedEquals(<int>[...resumeFixedPointStages]..sort()),
        reason:
            'linked resume uses the shared strict content/media fixed point '
            'before display, refresh, and the blob-free direct drain',
      );

      final coldFixedPointStages = <int>[
        restrictedRuntime.indexOf('await replayLinkedGroupAuthority?.call();'),
        restrictedRuntime.indexOf(
          'await drainProtectedGroupContentMediaFixedPoint(',
        ),
        restrictedRuntime.indexOf('replayContent: replayLinkedGroupContent,'),
        restrictedRuntime.indexOf(
          'drainOutgoingMedia: drainLinkedGroupOutgoingMedia,',
        ),
        restrictedRuntime.indexOf('retryContent: retryLinkedGroupContent,'),
        restrictedRuntime.indexOf(
          'drainIncomingMedia: drainLinkedGroupIncomingMedia,',
        ),
        restrictedRuntime.indexOf(
          'await drainLinkedGroupNotificationDisplayCustody?.call();',
        ),
        restrictedRuntime.indexOf('await refreshLinkedGroupList?.call();'),
        restrictedRuntime.indexOf('await drainExactBlobFreeFanoutOutboxes();'),
      ];
      expect(coldFixedPointStages, everyElement(greaterThanOrEqualTo(0)));
      expect(
        coldFixedPointStages,
        orderedEquals(<int>[...coldFixedPointStages]..sort()),
        reason:
            'the restricted cold runtime shares the same fixed-point helper '
            'and remains blob-free after protected convergence',
      );
      final linkedPause = root.indexOf('final linkedGroupContentPause =');
      final linkedPauseCall = root.indexOf(
        'widget.pauseLinkedGroupContentAdmission',
        linkedPause,
      );
      final linkedPauseCallEnd = root.indexOf('.call();', linkedPauseCall);
      final linkedPauseContinuation = root.indexOf('unawaited(', linkedPause);
      final linkedPauseLocalSweep = root.indexOf(
        'final result = await handleAppPaused(',
        linkedPause,
      );
      final linkedPauseFlush = root.indexOf(
        'await widget.flushLinkedGroupAuthorityOnPause?.call();',
        linkedPause,
      );
      expect(linkedPause, greaterThanOrEqualTo(0));
      expect(linkedPause, lessThan(linkedPauseCall));
      expect(linkedPauseCall, lessThan(linkedPauseCallEnd));
      expect(linkedPauseCallEnd, lessThan(linkedPauseContinuation));
      expect(linkedPauseContinuation, lessThan(linkedPauseLocalSweep));
      expect(linkedPauseLocalSweep, lessThan(linkedPauseFlush));
      expect(
        root,
        contains('await widget.resumeLinkedGroupContentAdmission?.call('),
      );
      expect(
        root,
        contains('linkedGroupContentPause,'),
        reason: 'resume is generation-bound to its exact recovery pause',
      );

      expect(list, contains('isLinkedGroupAuthoritySettled!(group.id)'));
      expect(list, contains('linkedGroupConversationBuilder!'));
      expect(list, contains('group.type == GroupType.qa'));
      expect(narrow, contains('isEligibleLinkedProtectedGroupMessage'));
      expect(narrow, contains('message.privateMediaPolicy =='));
      expect(narrow, contains('message.media.isEmpty'));
      expect(
        narrow,
        isNot(contains('message.quotedMessageId == null')),
        reason: 'ordinary quote metadata is a protected-content projection',
      );
      expect(narrow, contains('!message.isForwarded'));
      expect(narrow, contains('final generation = ++_reloadGeneration;'));
      expect(
        'widget.isAuthoritySettled(widget.group.id)'.allMatches(narrow).length,
        greaterThanOrEqualTo(3),
        reason:
            'slow reload and the shared per-tap requalification both recheck '
            'settled authority',
      );
      expect(narrow, contains('generation != _reloadGeneration'));
      expect(narrow, contains('widget.loadCurrentGroup(widget.group.id)'));
      expect(narrow, contains('group: _currentGroup'));
      expect(narrow, contains('message.isIncoming && message.readAt == null'));
      expect(narrow, contains('with WidgetsBindingObserver'));
      expect(narrow, contains('if (_isLifecycleResumed &&'));
      expect(
        production,
        contains('markVisibleMessagesRead: (groupId, messageIds) async {'),
      );
      expect(production, contains('AND read_at IS NULL AND id IN ('));
      expect(narrow, contains('unreadVisibleIds.isNotEmpty'));
      expect(narrow, contains('groupConversationTracker.isViewing('));
      expect(narrow, contains('groupConversationTracker.setActive('));
      expect(narrow, contains('groupConversationTracker.clearIfActive('));
      expect(
        'groupMessageListener.retryPendingNotificationDisplays'.allMatches(
          production,
        ),
        hasLength(3),
        reason:
            'cold, resume, and exact visible-read retirement drain READY '
            'protected display custody',
      );
      expect(narrow, contains('bool get _canCompose =>'));
      expect(
        narrow,
        contains(
          'bool get _canReact => _hasActiveAuthority && _authoringQualified;',
        ),
      );
      expect(narrow, contains('widget.canAuthorProtectedContent('));
      expect(narrow, contains('canWrite: _canCompose'));
      expect(narrow, contains('onReactionSelected: _canReact'));
      expect(narrow, contains('onReactionTap: _canReact'));
      expect(narrow, isNot(contains('onReactionSelected: _canCompose')));
      expect(narrow, isNot(contains('onReactionTap: _canCompose')));
      expect(
        production,
        contains('loadCurrentGroup: groupRepository.getGroup'),
      );
      expect(
        RegExp(r'(?<!Linked)\bGroupConversationWired\(').hasMatch(narrow),
        isFalse,
      );
      expect(
        narrow,
        contains('onAttach: _canCompose && widget.attachOrdinaryMedia != null'),
        reason:
            'Plan 365 admits only the narrow strict-media capability through '
            'the linked protected surface',
      );
      expect(
        narrow,
        contains(
          'onRecordStart: _canCompose && '
          'widget.startVoiceRecording != null',
        ),
        reason:
            'voice remains the same qualified ordinary-media capability, not '
            'a generic group runtime',
      );
      for (final forbidden in const <String>[
        'onOpenPrivateMedia:',
        'onMediaShare:',
        'onQuoteReply:',
        'onInfo:',
      ]) {
        expect(narrow, isNot(contains(forbidden)));
      }
      expect(
        sharedProtectedReplay,
        contains('reconcileProtectedGroupContentForAuthority('),
        reason: 'later authority must reconcile before COMPLETE/UI exposure',
      );
      expect(
        production,
        contains(
          'protectedGroupAuthoritySupport.reconcileCompletedContentAuthority(',
        ),
        reason: 'foreground reconciliation must reuse the canonical support',
      );
      expect(
        production,
        contains('hasUnfinishedProtectedContentAuthority(groupId)'),
        reason: 'linked UI and authoring fail closed during reconciliation',
      );
      expect(
        production,
        contains(
          'protectedGroupAuthoritySupport.hasUnfinishedContentAuthority('
          'groupId)',
        ),
        reason: 'foreground pending checks must reuse the canonical support',
      );
      expect(
        sharedProtectedReplay,
        contains("reasonCode: 'authority_reconciliation_pending'"),
        reason: 'strict ingress waits without consuming a retry attempt',
      );
      expect(
        production,
        contains(
          'setGroupContentAuthoringResolver(\n'
          '      groupRepository,\n'
          '      resolveGroupContentAuthoringForSend,',
        ),
        reason: 'every production caller reaches one strict authoring owner',
      );
      final authoringResolverSource = File(
        'lib/features/groups/application/'
        'protected_group_content_authoring_resolver.dart',
      ).readAsStringSync();
      expect(
        authoringResolverSource,
        contains('installation.isOrdinaryPrimary'),
        reason:
            'the reusable production resolver must support ordinary primary',
      );
      final sendSource = File(
        'lib/features/groups/application/send_group_message_use_case.dart',
      ).readAsStringSync();
      expect(
        sendSource,
        contains("'strict_group_content_authority_unavailable'"),
        reason: 'initialized callers never fall through on a null context',
      );
      final reactionSource = File(
        'lib/features/groups/application/send_group_reaction_use_case.dart',
      ).readAsStringSync();
      expect(
        reactionSource.indexOf(
          'final snapshot = await runGroupAuthorityPhase(',
        ),
        lessThan(reactionSource.indexOf('resolveGroupContentAuthoring(')),
        reason: 'reaction authority resolves inside the keyed snapshot phase',
      );
      expect(
        reactionSource,
        contains('authorityMatchesAssumingPhase'),
        reason:
            'strict reaction staging and completion recheck the exact snapshot',
      );

      final runner = File(
        'integration_test/_support/invite_reliability_runner_contract.dart',
      ).readAsStringSync();
      expect(runner, contains('physical-Android first'));
      expect(runner, contains('Android-emulator'));
    },
  );

  test(
    'TC-365-04a linked restricted runtime owns only strict group media',
    () async {
      final phases = <String>[];
      var fixedPointPass = 0;
      final runtime = DirectBlobFreeLinkedServices(
        initializeBridge: () async => phases.add('bridge'),
        startMessageRouter: () => phases.add('router'),
        startChatMessageListener: () => phases.add('chat'),
        startReactionListener: () => phases.add('reaction'),
        startMessageDeletionListener: () => phases.add('deletion'),
        startDeliveryReceiptListener: () => phases.add('receipt'),
        startLinkedTransport: () async {
          phases.add('transport');
          return true;
        },
        drainOfflineInbox: () async => phases.add('inbox'),
        materializeLinkedGroupBootstrap: () async => phases.add('bootstrap'),
        replayLinkedGroupAuthority: () async => phases.add('authority'),
        replayLinkedGroupContent: () async {
          phases.add('content');
          return fixedPointPass == 0 ? 1 : 0;
        },
        drainLinkedGroupOutgoingMedia: () async {
          phases.add('group-media-outgoing');
          return fixedPointPass == 0 ? 2 : 0;
        },
        retryLinkedGroupContent: () async {
          phases.add('content-retry');
          return fixedPointPass == 0 ? 1 : 0;
        },
        drainLinkedGroupIncomingMedia: () async {
          phases.add('group-media-incoming');
          final progress = fixedPointPass == 0 ? 3 : 0;
          fixedPointPass += 1;
          return progress;
        },
        drainLinkedGroupNotificationDisplayCustody: () async =>
            phases.add('notification'),
        refreshLinkedGroupList: () async => phases.add('refresh'),
        drainExactBlobFreeFanoutOutboxes: () async {
          phases.add('direct');
          return 0;
        },
      );
      expect(await runtime.start(), isTrue);
      expect(phases, <String>[
        'bridge',
        'router',
        'chat',
        'reaction',
        'deletion',
        'receipt',
        'transport',
        'inbox',
        'bootstrap',
        'authority',
        'content',
        'group-media-outgoing',
        'content-retry',
        'group-media-incoming',
        'content',
        'group-media-outgoing',
        'content-retry',
        'group-media-incoming',
        'notification',
        'refresh',
        'direct',
      ]);

      final outgoingQuiesced = Completer<void>();
      final incomingQuiesced = Completer<void>();
      final lifecycle = <String>[];
      final quiescence = ProtectedGroupContentRuntimeQuiescence(
        pauseInboundAdmission: () async => lifecycle.add('content-paused'),
        resumeInboundAdmission: () => lifecycle.add('content-resumed'),
        quiesceOutgoingMedia: () async {
          lifecycle.add('outgoing-media-quiescing');
          await outgoingQuiesced.future;
        },
        quiesceIncomingMedia: () async {
          lifecycle.add('incoming-media-quiescing');
          await incomingQuiesced.future;
        },
        resumeMedia: () => lifecycle.add('media-resumed'),
      );
      final lease = quiescence.pause();
      var pauseCompleted = false;
      final paused = lease.quiesced.then((_) => pauseCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        lifecycle,
        containsAll(<String>[
          'content-paused',
          'outgoing-media-quiescing',
          'incoming-media-quiescing',
        ]),
      );
      expect(pauseCompleted, isFalse);
      outgoingQuiesced.complete();
      await Future<void>.delayed(Duration.zero);
      expect(pauseCompleted, isFalse);
      incomingQuiesced.complete();
      await paused;
      expect(await lease.resume(), isTrue);
      expect(lifecycle.sublist(lifecycle.length - 2), <String>[
        'content-resumed',
        'media-resumed',
      ]);

      final production = File(_productionPath).readAsStringSync();
      final groupCleanup = production.indexOf(
        "'group_media_blob_local_cleanup'",
      );
      final networkBackfill = production.indexOf("'group_context_backfill'");
      expect(groupCleanup, greaterThanOrEqualTo(0));
      expect(groupCleanup, lessThan(networkBackfill));
      expect(
        production,
        contains(
          'preparedGroupMediaBlobCustodyCoordinator\n'
          '          .drainOutgoingCleanupAndOrphans(',
        ),
        reason:
            'cold startup must retire terminal rows and crash-orphan artifacts '
            'through the existing strict group-media lifecycle owner',
      );
      final uploadRetry = File(
        'lib/features/groups/application/'
        'retry_incomplete_group_uploads_use_case.dart',
      ).readAsStringSync();
      expect(
        uploadRetry,
        contains('.drainOutgoingCleanupAndOrphans('),
        reason:
            'automatic upload recovery must keep cleanup convergence alive '
            'after cold startup without adding another scheduler',
      );
    },
  );

  test(
    'TC-363-03a linked startup defers without identity and orders protected recovery before read-only refresh',
    () async {
      var hasIdentity = false;
      var authorityLoads = 0;
      var linkedStarts = 0;
      final runtime = RoleAwareDeferredRuntimeStart(
        hasIdentity: () async => hasIdentity,
        loadLinkedAuthority: () async {
          authorityLoads += 1;
          return const LinkedInstallationAuthoritySnapshot(
            disposition: LinkedInstallationDisposition.active,
            credential: LinkedTransportCredential(
              state: LinkedTransportCredentialState.active,
              accountPeerId: 'account-peer',
              accountPublicKey: 'account-public-key',
              deviceId: 'linked-device',
              transportPeerId: 'linked-transport',
              transportPublicKey: 'transport-public-key',
              transportPrivateKey: 'transport-private-key',
              createdAt: '2026-08-13T00:00:00.000Z',
              activatedAt: '2026-08-13T00:00:00.000Z',
            ),
            failClosedReason: null,
          );
        },
        startPrimaryRuntimeServices: () async => true,
        startLinkedFoundationPrerequisites: () async {
          linkedStarts += 1;
          return true;
        },
      );
      expect(await runtime.start(), isFalse);
      expect(
        runtime.lastOutcome,
        RoleAwareRuntimeStartOutcome.deferredNoIdentity,
      );
      expect(authorityLoads, 0);
      expect(linkedStarts, 0);
      hasIdentity = true;
      expect(await runtime.start(), isTrue);
      expect(authorityLoads, 1);
      expect(linkedStarts, 1);

      final cold = File(
        'lib/app/bootstrap/direct_blob_free_linked_services.dart',
      ).readAsStringSync();
      final coldStart = cold.indexOf('Future<bool> start() async');
      final coldDrain = cold.indexOf('await drainOfflineInbox();', coldStart);
      final coldBootstrap = cold.indexOf(
        'await materializeLinkedGroupBootstrap?.call();',
        coldStart,
      );
      final coldAuthority = cold.indexOf(
        'await replayLinkedGroupAuthority?.call();',
        coldStart,
      );
      final coldContent = cold.indexOf(
        'replayContent: replayLinkedGroupContent,',
        coldStart,
      );
      final coldRetry = cold.indexOf(
        'retryContent: retryLinkedGroupContent,',
        coldStart,
      );
      final coldRefresh = cold.indexOf(
        'await refreshLinkedGroupList?.call();',
        coldStart,
      );
      final coldNotification = cold.indexOf(
        'await drainLinkedGroupNotificationDisplayCustody?.call();',
        coldStart,
      );
      final coldDirect = cold.indexOf(
        'await drainExactBlobFreeFanoutOutboxes();',
        coldStart,
      );
      expect(<int>[
        coldDrain,
        coldBootstrap,
        coldAuthority,
        coldContent,
        coldRetry,
        coldNotification,
        coldRefresh,
        coldDirect,
      ], everyElement(isNonNegative));
      expect(
        <int>[
          coldDrain,
          coldBootstrap,
          coldAuthority,
          coldContent,
          coldRetry,
          coldNotification,
          coldRefresh,
          coldDirect,
        ],
        orderedEquals(
          <int>[
            coldDrain,
            coldBootstrap,
            coldAuthority,
            coldContent,
            coldRetry,
            coldNotification,
            coldRefresh,
            coldDirect,
          ]..sort(),
        ),
      );

      final root = File(_applicationRootPath).readAsStringSync();
      final linkedResume = root.indexOf(
        'if (widget.isLinkedBlobFreeRuntime?.call() ?? false)',
        root.indexOf('Future<void> _onResumed() async'),
      );
      final resumeDrain = root.indexOf(
        'final inboxDrain = await widget.p2pService.drainOfflineInboxFully();',
        linkedResume,
      );
      final resumeBootstrap = root.indexOf(
        'await widget.drainLinkedGroupBootstrap?.call();',
        linkedResume,
      );
      final resumeAuthority = root.indexOf(
        'await widget.replayLinkedGroupAuthority?.call();',
        linkedResume,
      );
      final resumeContent = root.indexOf(
        'replayContent: widget.replayLinkedGroupContent,',
        linkedResume,
      );
      final resumeRetry = root.indexOf(
        'retryContent: widget.retryLinkedGroupContent,',
        linkedResume,
      );
      final resumeRefresh = root.indexOf(
        'await widget.refreshLinkedGroupList?.call();',
        linkedResume,
      );
      final resumeNotification = root.indexOf(
        'await widget.drainLinkedGroupNotificationDisplayCustody?.call();',
        linkedResume,
      );
      expect(<int>[
        resumeDrain,
        resumeBootstrap,
        resumeAuthority,
        resumeContent,
        resumeRetry,
        resumeNotification,
        resumeRefresh,
      ], everyElement(isNonNegative));
      expect(
        <int>[
          resumeDrain,
          resumeBootstrap,
          resumeAuthority,
          resumeContent,
          resumeRetry,
          resumeNotification,
          resumeRefresh,
        ],
        orderedEquals(
          <int>[
            resumeDrain,
            resumeBootstrap,
            resumeAuthority,
            resumeContent,
            resumeRetry,
            resumeNotification,
            resumeRefresh,
          ]..sort(),
        ),
      );

      final startup = File(
        'lib/features/identity/presentation/startup_router.dart',
      ).readAsStringSync();
      expect(
        startup.indexOf('linkedAuthority?.isActiveLinkedSecondary == true'),
        lessThan(startup.indexOf('contactRepository.getContactCount()')),
      );
      final setup = File(
        'lib/features/identity/presentation/screens/linked_device_setup_wired.dart',
      ).readAsStringSync();
      expect(setup, contains('await widget.onSetupSuccess?.call();'));
      expect(setup, contains('LinkedGroupReadOnlyStatus('));
      expect(
        File(_productionPath).readAsStringSync(),
        contains('groupPendingBroadcastRunner.drainProtectedAll()'),
      );
      final protectedRunner = File(
        'lib/features/groups/application/group_pending_broadcast_runner.dart',
      ).readAsStringSync();
      expect(
        File(_productionPath).readAsStringSync(),
        contains('protectedInboxStore: p2pService'),
        reason: 'production supplies the typed per-target custody capability',
      );
      expect(
        protectedRunner,
        contains('? await _pushProtected(broadcast)'),
        reason:
            'protected bootstrap/authority rows never route through generic '
            'group_store rePush',
      );
      expect(
        protectedRunner,
        allOf(
          contains('storeInAckCustodyInboxDetailed('),
          contains('AckCustodyKind.groupAuthorityV1'),
        ),
      );
      final production = File(_productionPath).readAsStringSync();
      expect(
        production,
        allOf(
          contains('dbCommitGroupKeyWithAuthorityComplete('),
          contains('dbCommitProtectedDissolvedGroup('),
          contains('recoverPreparedProtectedGroupDissolve('),
          contains('recoverPreparedProtectedGroupKey('),
          contains('discoverLocalPreparedAuthorities('),
          contains('discoverPreparedAuthorities:'),
          allOf(
            contains('resumePreparedSurvivors'),
            contains('pendingDissolves.any('),
            contains('dbLoadUnfinishedProtectedAuthorityPage('),
            contains('sourcePeerId: identity.peerId'),
            contains('activeDevicesWithLegacyFallback()'),
            contains('deliveryReplayDataByTransportPeerId'),
          ),
        ),
        reason:
            'common key authority and the recoverable two-phase dissolve '
            'must be composed on the production repository/runner path',
      );
    },
  );
  test('TC-361-03b linked runtime starts only direct blob-free event owners — '
      'production composes one reverse transport authority, one restricted '
      'linked service set and the exact route-push fanout seams', () {
    final production = File(_productionPath).readAsStringSync();
    final canonicalDirectReplay = File(
      _canonicalDirectReplayPath,
    ).readAsStringSync();

    // ONE shared physical->logical reverse authority, wired into all four
    // direct event listeners plus the shared recovered-inbox replay owner.
    expect(
      'final directTransportAuthority = DatabaseDirectTransportAuthority('
          .allMatches(production),
      hasLength(1),
      reason: 'exactly one shared reverse transport authority',
    );
    expect(
      'transportAuthority: directTransportAuthority,'.allMatches(production),
      hasLength(5),
      reason:
          'chat/reaction/deletion/receipt listeners and the canonical replay '
          'owner all share the ONE authority',
    );
    expect(
      'ProductionCanonicalDirectReplayComposition('.allMatches(production),
      hasLength(1),
      reason: 'foreground constructs the shared direct replay owner once',
    );
    expect(
      'transportAuthority: transportAuthority,'.allMatches(
        canonicalDirectReplay,
      ),
      hasLength(2),
      reason:
          'the shared owner delegates that same authority to reaction and '
          'deletion replay',
    );

    // ONE restricted linked composition and ONE exact blob-free drain.
    expect(
      'DirectBlobFreeLinkedServices('.allMatches(production),
      hasLength(1),
      reason: 'the restricted linked owner set is composed exactly once',
    );
    expect(
      'startLinkedTransport: () async {'.allMatches(production),
      hasLength(1),
      reason: 'one exact linked transport start owner precedes recovery',
    );
    expect(
      'await startP2PNode('.allMatches(production),
      hasLength(1),
      reason:
          'the restricted cold owner starts the qualified node exactly once',
    );
    expect(
      production,
      contains('currentNode.peerId == expectedTransportPeerId'),
      reason:
          'a recovery retry reuses the already-qualified linked node instead '
          'of issuing a second start',
    );
    expect(
      'Future<int> drainDirectBlobFreeLinkedOutboxes() =>'.allMatches(
        production,
      ),
      hasLength(1),
      reason: 'one exact v113 blob-free linked drain',
    );
    expect(
      "operation: 'direct_blob_free_linked_fanout_drain',".allMatches(
        production,
      ),
      hasLength(1),
      reason: 'the linked drain runs under the account-runtime gate',
    );

    // The route-push seams reach MyApp exactly once each.
    expect(
      'directEventFanoutResolver: () {'.allMatches(production),
      hasLength(1),
      reason: 'fanout authoring is resolved at route-push time',
    );
    expect(
      'isLinkedBlobFreeRuntime: () =>'.allMatches(production),
      hasLength(1),
      reason: 'the restricted-surface fact is a live callback',
    );
    expect(
      'drainDirectBlobFreeLinkedOutboxes: drainDirectBlobFreeLinkedOutboxes,'
          .allMatches(production),
      hasLength(1),
      reason: 'the exact drain is the resume seam for the linked role',
    );
  });

  test(
    'TC-370-07 production composes one default-off outcome admission and one shared drain callback',
    () {
      final production = File(_productionPath).readAsStringSync();
      final applicationRoot = File(_applicationRootPath).readAsStringSync();
      final bridgeClient = File(
        'lib/core/bridge/p2p_bridge_client.dart',
      ).readAsStringSync();
      final canonicalDirectProjection = File(
        _canonicalDirectProjectionPath,
      ).readAsStringSync();

      expect(
        bridgeClient,
        contains(
          "const bool kWakeOutcomeCoordinatorAdmissionEnabled = bool.fromEnvironment(",
        ),
      );
      expect(
        bridgeClient,
        contains("defaultValue: false"),
        reason: 'the combined capability/producer/drain admission stays dark',
      );
      expect(
        'NotificationCompletedOutcomeDrainComposition('.allMatches(production),
        hasLength(1),
        reason:
            'bootstrap owns exactly one production-tested drain composition',
      );
      final unit = parseString(content: production, path: _productionPath).unit;
      final compositionVisitor =
          _NotificationCompletedOutcomeDrainCompositionVisitor();
      unit.accept(compositionVisitor);
      expect(
        compositionVisitor.constructions,
        hasLength(1),
        reason: 'the single composition must be structurally discoverable',
      );
      final compositionArguments = <String, String>{
        for (final argument
            in compositionVisitor.constructions.single.arguments
                .whereType<NamedExpression>())
          argument.name.label.name: argument.expression.toSource(),
      };
      expect(
        compositionArguments['admissionEnabled'],
        'kWakeOutcomeCoordinatorAdmissionEnabled',
        reason: 'the shared default-off seam must gate the production drainer',
      );
      expect(
        compositionArguments['sendOutcome'],
        '({required correlation}) => '
        'callP2PInboxWakeOutcome(bridge, correlation: correlation)',
        reason: 'production must send through the strict real bridge call',
      );
      expect(
        compositionArguments['runNetworkAction'],
        "(action) => runAccountRuntimeNetworkVoidAction(operation: "
        "'notification_completed_outcome_drain', action: action)",
        reason:
            'the drainer must remain inside the account-migration network gate',
      );
      expect(
        'notificationCompletedOutcomeDrainKick = '
                'drainNotificationCompletedOutcomes;'
            .allMatches(production),
        hasLength(1),
        reason: 'post-commit kicks must reach the production-owned callback',
      );
      expect(
        'completedOutcomeProducerEnabled: '
                'kWakeOutcomeCoordinatorAdmissionEnabled,'
            .allMatches(production),
        hasLength(1),
        reason: 'the group producer uses the combined admission directly',
      );
      expect(
        production,
        contains(
          'completedOutcomeProducerEnabled:\n'
          '                kWakeOutcomeCoordinatorAdmissionEnabled,',
        ),
        reason:
            'foreground delegates the same combined admission into the '
            'canonical direct projection composition',
      );
      expect(
        canonicalDirectProjection,
        contains(
          'completedOutcomeProducerEnabled:\n'
          '        dependencies.completedOutcomeProducerEnabled,',
        ),
        reason:
            'the shared composition reuses the delegated admission for the '
            'direct producer',
      );
      // Plan 375: one live platform consumer resolver is read at each drain
      // kick, each producer event and immediately before every registration
      // send — never a cached constructor boolean and never a second flag.
      expect(
        compositionArguments['readPlatformConsumerReady'],
        '() => opaqueWakePlatformConsumerReadiness'
        '.isReadyFor(currentPushPlatformName())',
        reason: 'the drain kick reads the one live platform readiness',
      );
      expect(
        'readCompletedOutcomeProducerReady: () =>'.allMatches(production),
        hasLength(2),
        reason:
            'both producer owners (direct projection and group listener) '
            'read the same live resolver at event time',
      );
      expect(
        '.isReadyFor'.allMatches(production),
        hasLength(5),
        reason:
            'drain kick, registration tear-off, two producer owners and the '
            'linked hook all consult the one shared readiness resolver',
      );
      expect(
        'readOpaqueWakePlatformConsumerReadiness:\n'
                '          opaqueWakePlatformConsumerReadiness.isReadyFor,'
            .allMatches(production),
        hasLength(1),
        reason: 'registration reads the same resolver before the bridge send',
      );
      expect(
        'readAndroidConsumer: androidOpaqueWakeReadiness?.isConsumerReady,'
            .allMatches(production),
        hasLength(1),
        reason: 'Android supplies exactly one live consumer read-back',
      );
      expect(
        'installPushRegistrationRetryNow('.allMatches(production),
        hasLength(1),
        reason:
            'the one coordinator retry owner is late-installed exactly once',
      );
      expect(
        production,
        isNot(contains('_reregisterStoredPushTokenIfAvailable')),
        reason: 'no raw bootstrap re-registration bypass exists',
      );
      expect(
        'if (completed && outcome != null) {'.allMatches(production),
        hasLength(2),
        reason: 'both atomic display owners kick only after an outcome commit',
      );
      expect(
        'drainNotificationCompletedOutcomesFn: '
                'drainNotificationCompletedOutcomes,'
            .allMatches(production),
        hasLength(1),
        reason: 'the pending retrier receives the one shared callback',
      );
      expect(
        'drainNotificationCompletedOutcomes: '
                'drainNotificationCompletedOutcomes,'
            .allMatches(production),
        hasLength(1),
        reason: 'ApplicationRoot receives that same callback for resume',
      );
      expect(
        applicationRoot,
        contains(
          'drainNotificationCompletedOutcomesFn:\n'
          '            widget.drainNotificationCompletedOutcomes,',
        ),
        reason: 'the root passes the bootstrap owner into handleAppResumed',
      );
    },
  );
}

/// Collects every `MessageRepositoryImpl(...)` construction in a unit.
///
/// An unresolved parse represents an implicit-new constructor call as a
/// [MethodInvocation], so both shapes are collected.
class _MessageRepositoryConstructionVisitor extends RecursiveAstVisitor<void> {
  final List<ArgumentList> constructions = <ArgumentList>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'MessageRepositoryImpl') {
      constructions.add(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        node.methodName.name == 'MessageRepositoryImpl') {
      constructions.add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

final class _NotificationCompletedOutcomeDrainCompositionVisitor
    extends RecursiveAstVisitor<void> {
  final List<ArgumentList> constructions = <ArgumentList>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme ==
        'NotificationCompletedOutcomeDrainComposition') {
      constructions.add(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        node.methodName.name ==
            'NotificationCompletedOutcomeDrainComposition') {
      constructions.add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects every `MediaAttachmentRepositoryImpl(...)` construction in a unit.
///
/// Mirrors [_MessageRepositoryConstructionVisitor] so the private v114 and
/// v108 composition proof resolves named delegates structurally instead of
/// accepting an unrelated source-string occurrence.
class _MediaAttachmentRepositoryConstructionVisitor
    extends RecursiveAstVisitor<void> {
  final List<ArgumentList> constructions = <ArgumentList>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme ==
        'MediaAttachmentRepositoryImpl') {
      constructions.add(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        node.methodName.name == 'MediaAttachmentRepositoryImpl') {
      constructions.add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects the simple names of every function invoked inside an expression.
class _InvokedFunctionNameVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier) names.add(function.name);
    super.visitFunctionExpressionInvocation(node);
  }
}
