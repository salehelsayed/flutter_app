import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/role_aware_deferred_runtime_start.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_test/flutter_test.dart';

const _productionPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
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
          mediaAttachments: 'uploadResult.attachments',
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

  test('TC-350-02c production wires fresh forward authorization exactly once', () {
    final production = File(_productionPath).readAsStringSync();

    expect(
      'authorizedForwardDedupKey'.allMatches(production),
      hasLength(3),
      reason:
          'exactly one declaration plus one verbatim pass-through: production '
          'must never drop the token and never derive a second one',
    );
    expect(
      'authorizedForwardDedupKey: authorizedForwardDedupKey'.allMatches(
        production,
      ),
      hasLength(1),
      reason: 'the token reaches the SQLite helper unmodified',
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

    // 1. Canonical KEEP: a consumed/expired private parent must be retired
    //    from canonical notification history like a deleted one.
    final keep = production.indexOf(
      'DirectNotificationCanonicalContentDecision.keep',
    );
    expect(keep, greaterThan(-1));
    final keepStart = production.lastIndexOf(
      'return message.contactPeerId',
      keep,
    );
    expect(keepStart, greaterThan(-1));
    final keepBody = production.substring(keepStart, keep);
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
    final projection = production.indexOf('projectDisplay: (entry) async {');
    expect(projection, greaterThan(-1));
    final projectionBody = production.substring(
      projection,
      production.indexOf('return maybeShowNotification(', projection),
    );
    for (final guard in const <String>[
      'message.isDeleted',
      'message.hiddenAt != null',
      'message.privateMediaState.isTerminal',
    ]) {
      expect(
        projectionBody.contains(guard),
        isTrue,
        reason: 'display projection must suppress: \$guard',
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
