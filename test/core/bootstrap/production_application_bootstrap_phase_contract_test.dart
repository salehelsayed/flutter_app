import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
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

const _expectedSendChatMessageCallers =
    <
      String,
      ({_SendChatMessageCallerKind kind, String callee, String? freshIntent})
    >{
      'lib/core/debug/intro_e2e_runner.dart': (
        kind: _SendChatMessageCallerKind.generatedIdFresh,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
      'lib/core/debug/keepalive_drop_e2e.dart': (
        kind: _SendChatMessageCallerKind.generatedIdFresh,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
      'lib/features/conversation/application/'
          'retry_failed_messages_use_case.dart': (
        kind: _SendChatMessageCallerKind.excludedRetry,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
      'lib/features/conversation/application/'
          'retry_incomplete_uploads_use_case.dart': (
        kind: _SendChatMessageCallerKind.excludedMedia,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
      'lib/features/conversation/application/send_chat_message_use_case.dart': (
        kind: _SendChatMessageCallerKind.excludedEdit,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
      'lib/features/conversation/application/send_voice_message_use_case.dart':
          (
            kind: _SendChatMessageCallerKind.excludedVoice,
            callee: 'sendChatMessage',
            freshIntent: 'preassignedMessageIdIsFresh',
          ),
      'lib/features/conversation/presentation/screens/conversation_wired.dart':
          (
            kind: _SendChatMessageCallerKind.preassignedIdFresh,
            callee: 'sendChatMessageFn',
            freshIntent: 'stagesFreshDirectTextCustody',
          ),
      'lib/features/feed/presentation/screens/feed_wired.dart': (
        kind: _SendChatMessageCallerKind.preassignedIdFresh,
        callee: 'sendChatMessage',
        freshIntent: 'true',
      ),
      'lib/features/share/application/share_batch_delivery_coordinator.dart': (
        kind: _SendChatMessageCallerKind.generatedIdFresh,
        callee: 'sendChatMessage',
        freshIntent: null,
      ),
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
        'storeInInboxDetailed: p2pService.storeInInboxDetailed'.allMatches(
          composite,
        ),
        hasLength(2),
        reason: 'both families must replay through the typed relay outcome',
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
            r'class P2PServiceImpl\s+implements[\s\S]*?\bDetailedInboxStore\b',
          ),
        ),
        reason:
            'the production reaction caller omits an explicit store override, '
            'so its concrete P2P service must expose typed inbox outcomes',
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
        hasLength(_expectedSendChatMessageCallers.length),
        reason:
            'the exact caller inventory must reject missing and duplicate '
            'call sites as well as new files',
      );

      for (final expected in _expectedSendChatMessageCallers.entries) {
        final matches = callers
            .where((caller) => caller.path == expected.key)
            .toList(growable: false);
        expect(
          matches,
          hasLength(1),
          reason: '${expected.key} must own exactly one classified invocation',
        );
        final caller = matches.single;
        final arguments = caller.namedArguments;
        expect(
          caller.callee,
          expected.value.callee,
          reason: _sendCallerLabel(caller),
        );

        switch (expected.value.kind) {
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
              expected.value.freshIntent,
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
            expect(arguments['mediaAttachments'], 'fullAttachmentList');
            expect(arguments, contains('messageId'));
            expect(arguments, isNot(contains('preassignedMessageIdIsFresh')));
          case _SendChatMessageCallerKind.excludedVoice:
            expect(arguments['mediaAttachments'], '[uploaded]');
            expect(arguments, contains('messageId'));
            expect(
              arguments['preassignedMessageIdIsFresh'],
              expected.value.freshIntent,
            );
        }
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
        },
        reason:
            'only classified existing edit/retry/media attempts may pass a '
            'messageId without explicit fresh-custody intent',
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
}
