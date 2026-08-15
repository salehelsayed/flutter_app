import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _facadePath =
    'lib/features/groups/application/group_message_listener.dart';
const _contractTestPath =
    'test/features/groups/application/'
    'group_message_listener_decomposition_contract_test.dart';
const _deviceAnnounceTestPath =
    'test/features/groups/application/'
    'group_message_listener_device_announce_test.dart';
const _architectureExceptionsPath =
    'tool/architecture_guard/architecture_boundary_exceptions.json';

final class _ComponentContract {
  const _ComponentContract({
    required this.path,
    required this.className,
    required this.facadeField,
    required this.helperClasses,
    required this.ownedFieldDeclarations,
    required this.ownedMethods,
    this.delegatedPublicMethods = const <String>{},
  });

  final String path;
  final String className;
  final String facadeField;
  final Set<String> helperClasses;
  final Map<String, String> ownedFieldDeclarations;
  final Set<String> ownedMethods;
  final Set<String> delegatedPublicMethods;
}

const _systemComponent = _ComponentContract(
  path:
      'lib/features/groups/application/'
      'group_message_listener_system_transition_processor.dart',
  className: '_GroupMessageSystemTransitionProcessor',
  facadeField: '_systemTransitionProcessor',
  helperClasses: <String>{
    '_SignedTransitionAuditActorBinding',
    '_RemoteMemberRemovalFollowUp',
  },
  ownedFieldDeclarations: <String, String>{
    '_groupConfigWorkQueue':
        'final Map<String, Future<void>> _groupConfigWorkQueue = {};',
    '_acceptedSignedTransitionAuditHashesBySourceId':
        'final Map<String, String> '
        '_acceptedSignedTransitionAuditHashesBySourceId = {};',
  },
  ownedMethods: <String>{
    '_shouldBufferPreJoinSystemMessage',
    '_handleSystemMessage',
    '_handleDeviceAnnounce',
    '_isBoundSystemEventSenderDevice',
    '_shouldRelaxSnapshotBackedPreTransitionHash',
    '_expectedSignedAuditActorBindingForSystemEvent',
    '_canBootstrapSnapshotBackedSignedAuditActorDevice',
    '_canAcceptLegacySnapshotBackedAccountSender',
    '_isLegacyAccountSystemTransport',
    '_canBootstrapSnapshotBackedSenderDevice',
    '_signedTransitionAuditActorBinding',
    '_trimToNull',
    '_allowsSnapshotBackedSystemSender',
    '_shouldRequireSignedTransitionAudit',
    '_resolveActorSigningPublicKey',
    '_emitSignedTransitionAuditRejected',
    '_requiresMembershipEventAuthorization',
    '_isAuthorizedMembershipEventSender',
    '_isAuthorizedTrustedPrivateMemberModerator',
    '_isAuthorizedTrustedPrivateMessageDelete',
    '_canApplyIncomingMemberRoleUpdate',
    '_findGroupConfigMember',
    '_isAuthorizedJoinEventSender',
    '_handleMemberAdded',
    '_handleMembersAdded',
    '_handleMemberJoined',
    '_handleMemberRemoved',
    '_maybeRotateGroupKeyAfterRemoteRemoval',
    '_retainSelfRemovedLocalHistory',
    '_closeGroupForEmptyMembership',
    '_handleMemberBanned',
    '_handleMemberUnbanned',
    '_handleGroupMessageDeleted',
    '_handleMemberRoleUpdated',
    '_handleGroupMetadataUpdated',
    '_verifyGroupMetadataActorEvent',
    '_emitMetadataSignatureRejected',
    '_buildMetadataTimelineText',
    '_handleGroupDissolved',
    '_terminalizeExitWorkAfterRemoteDissolve',
    '_emitGroupMessageIfActive',
    '_emitGroupRemovedIfActive',
    '_enqueueGroupConfigWork',
    '_saveTimelineMessagePreservingReadState',
    '_buildTrustedPrivateMemberTombstoneMessage',
    '_buildTrustedPrivateMessageDeleteTombstoneMessage',
    '_emitTrustedPrivateSystemEventIgnored',
    '_emitMemberKeyMaterialRejected',
    '_parseMembershipEventAt',
    '_resolveIncomingMembershipVersion',
    '_isDuplicateMembersAddedReplayAlreadyApplied',
    '_timelineAddedMembersForReplay',
    '_shouldIgnoreStaleMembershipEvent',
    '_storedMembershipEventIdAt',
    '_membershipAddAdvancesLocalMember',
    '_canApplyAddForMissingMember',
    '_membershipAddTimelineExists',
    '_shouldIgnoreStaleMemberRemovedEvent',
    '_resolveMembershipEventWatermark',
    '_shouldIgnoreStaleMetadataEvent',
    '_metadataReplayRepairsVisibleFields',
    '_shouldRetryAcceptedSignedMetadataAvatarRecovery',
    '_applyAuthoritativeGroupConfigSnapshot',
    '_buildLocalGroupConfigSnapshot',
    '_resolveAuthoritativeSnapshotJoinedAt',
    '_recordMembershipEventWatermark',
    '_existingMemberForMembershipAddEvent',
    '_syncGroupConfig',
  },
);

const _membershipComponent = _ComponentContract(
  path:
      'lib/features/groups/application/'
      'group_message_listener_membership_dependent_message_buffer.dart',
  className: '_GroupMembershipDependentMessageBuffer',
  facadeField: '_membershipDependentMessageBuffer',
  helperClasses: <String>{'_PendingMembershipDependentMessage'},
  ownedFieldDeclarations: <String, String>{
    '_pendingMembershipDependentMessagesByGroup':
        'final Map<String, List<_PendingMembershipDependentMessage>> '
        '_pendingMembershipDependentMessagesByGroup = {};',
  },
  ownedMethods: <String>{
    'flushPendingMembershipDependentMessagesForGroup',
    '_shouldBufferMembershipDependentMessage',
    '_bufferMembershipDependentMessage',
    '_saveDurableMembershipDependentMessage',
    '_bufferPersistedMembershipDependentMessage',
    '_flushMembershipDependentMessages',
    '_flushMembershipDependentMessageLeaf',
    '_requestDeferredMembershipMessageKeyRepair',
    '_isExactPendingMembershipMessage',
    '_pendingMembershipDependentMessageFromDurable',
    '_pendingMembershipDependentMessageKey',
    '_deleteDurableMembershipDependentMessage',
    '_flushStartupDurableMembershipDependentMessages',
    '_deleteContentMessagesAtOrAfterRemoval',
  },
  delegatedPublicMethods: <String>{
    'flushPendingMembershipDependentMessagesForGroup',
  },
);

const _reactionComponent = _ComponentContract(
  path:
      'lib/features/groups/application/'
      'group_message_listener_reaction_ingress_processor.dart',
  className: '_GroupReactionIngressProcessor',
  facadeField: '_reactionIngressProcessor',
  helperClasses: <String>{},
  ownedFieldDeclarations: <String, String>{},
  ownedMethods: <String>{
    '_samePendingReaction',
    '_flushPendingReactionsForMessage',
    '_flushPendingReactionLocked',
    '_flushStartupDurablePendingReactions',
    '_handleReaction',
    '_loadReactionDerivativeTarget',
    '_maybeNotifyGroupReaction',
  },
);

const _mediaComponent = _ComponentContract(
  path:
      'lib/features/groups/application/'
      'group_message_listener_media_receive_coordinator.dart',
  className: '_GroupMediaReceiveCoordinator',
  facadeField: '_mediaReceiveCoordinator',
  helperClasses: <String>{'_GroupMediaReceiveCriticalTaskLease'},
  ownedFieldDeclarations: <String, String>{
    '_groupMediaReceiveCriticalTaskLease':
        '_GroupMediaReceiveCriticalTaskLease? '
        '_groupMediaReceiveCriticalTaskLease;',
    '_groupMediaReceiveCriticalTaskLeaseAcquisition':
        'Future<_GroupMediaReceiveCriticalTaskLease>? '
        '_groupMediaReceiveCriticalTaskLeaseAcquisition;',
    '_groupMediaReceiveCriticalTaskLeaseEnd':
        'Future<void>? _groupMediaReceiveCriticalTaskLeaseEnd;',
  },
  ownedMethods: <String>{
    'reserveGroupMediaReceiveCriticalTaskForForegroundHandoff',
    '_hasAutomaticMediaRecovery',
    '_recoverAutomaticMedia',
    '_shouldOwnReceiveCriticalTask',
    '_beginReceiveCriticalTask',
    '_acquireReceiveCriticalTaskLease',
    '_releaseReceiveCriticalTaskLease',
    '_endReceiveCriticalTask',
    '_autoDownloadMedia',
  },
  delegatedPublicMethods: <String>{
    'reserveGroupMediaReceiveCriticalTaskForForegroundHandoff',
  },
);

const _components = <_ComponentContract>[
  _systemComponent,
  _membershipComponent,
  _reactionComponent,
  _mediaComponent,
];

const _retainedFacadeFields = <String>{
  '_getSelfPeerId',
  '_groupDiagnosticEvents',
  '_subscription',
  '_reactionSubscription',
  '_diagnosticSubscription',
  '_messageController',
  '_removedController',
  '_reactionChangeController',
  '_userMessageWorkQueue',
  '_inFlightHandlers',
  '_dispatcherOverflowRecovery',
  '_stopFuture',
  '_durableNotificationCoordinatorFuture',
  '_cachedSelfPeerId',
  '_hasResolvedSelfPeerId',
  '_selfPeerIdLoadFuture',
  '_isStopping',
  '_isDisposed',
};

const _retainedFacadeMethods = <String>{
  '_resolveDurableNotificationCoordinator',
  '_openDurableNotificationCoordinator',
  '_resolveSelfPeerId',
  '_canEmitToStreams',
  '_emitGroupMessage',
  '_emitGroupRemoved',
  '_emitReactionChange',
  '_handleLiveMessage',
  '_handleLiveReaction',
  '_handleLiveDiagnosticEvent',
  '_allowsInboundAccountSideEffects',
  '_trackInFlight',
  '_awaitInFlightHandlers',
  '_userMessageWorkKey',
  '_handleQueuedUserMessage',
  '_handleGroupDiagnosticEvent',
  '_handleGroupDispatcherOverflow',
  '_requestGroupPushLossRecovery',
  '_groupPushLossRecoveryDiagnosticDetails',
  '_liveGroupPushLossDiagnostic',
  '_groupMessageEventSchemaRejectReason',
  '_emitGroupMessageSchemaRejected',
  '_handleMessage',
  '_requestReceivedMessageKeyRepairIfLocalEpochIsBehind',
  'retryPendingKeyRepairsForGroupEpoch',
  'start',
  'stop',
  'dispose',
};

const _expectedConstructorParameters = <String>[
  'required GroupRepository groupRepo',
  'required GroupMessageRepository msgRepo',
  'Bridge? bridge',
  'Future<String?> Function()? getSelfPeerId',
  'MediaAttachmentRepository? mediaAttachmentRepo',
  'MediaFileManager? mediaFileManager',
  'NotificationService? notificationService',
  'AppVisibilitySuppressionReader? appVisibility',
  'ActiveConversationTracker? groupConversationTracker',
  'NotificationToneTracker? notificationToneTracker',
  'GroupNotificationPresentationCoordinator? '
      'notificationPresentationCoordinator',
  'Future<DurableNotificationToneLease> Function()? '
      'durableNotificationCoordinatorResolver',
  'AppLifecycleState Function()? getAppLifecycleState',
  'RecentRemoteNotificationGate? remoteNotificationGate',
  'ReactionRepository? reactionRepo',
  'GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo',
  'DownloadGroupAvatarFn? downloadGroupAvatarFn',
  'AppendGroupEventLogEntry? appendGroupEventLogEntry',
  'Stream<Map<String, dynamic>>? groupDiagnosticEvents',
  'GroupPendingKeyRepairRepository? pendingKeyRepairRepo',
  'GroupPendingMembershipMessageRepository? pendingMembershipMessageRepo',
  'GroupPendingReactionRepository? pendingReactionRepo',
  'RequestGroupKeyRepair? requestGroupKeyRepair',
  'RecoverGroupDispatcherOverflow? recoverFromDispatcherOverflow',
  'RotateGroupKeyAfterRemoteRemoval? rotateGroupKeyAfterRemoteRemoval',
  'TerminalizeGroupExitWorkAfterRemoteDissolve? '
      'terminalizeGroupExitWorkAfterRemoteDissolve',
  'AccountMigrationNetworkGate accountMigrationNetworkGate = '
      'allowAccountMigrationNetworkSideEffects',
  'HoldPendingSiblingDeviceFn? holdPendingSiblingDevice',
  'GroupPrivateMediaAvailability privateMediaAvailability = '
      'productionGroupPrivateMediaAvailability',
  'PendingConversationNotificationOverlayStore? '
      'pendingConversationNotificationOverlay',
  'GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator',
  'GroupNotificationDisplayOutboxRepository? notificationDisplayOutbox',
  'GroupNotificationReconciliationOutboxRepository? '
      'notificationReconciliationOutbox',
  'LoadLatestUnreadGroupNotificationMessage? '
      'loadLatestUnreadNotificationMessage',
  'IsActiveGroupNotificationReaction? isActiveGroupNotificationReaction',
  'LoadLatestActiveGroupNotificationReaction? '
      'loadLatestActiveNotificationReaction',
  'GroupNotificationEventAcknowledgedResolver? '
      'isGroupNotificationEventAcknowledged',
  'Future<String?> Function()? resolveCompletedOutcomePhysicalPeerId',
  'bool completedOutcomeProducerEnabled = false',
  'BeginGroupMediaReceiveCriticalTask? beginGroupMediaReceiveCriticalTask',
  'EndGroupMediaReceiveCriticalTask? endGroupMediaReceiveCriticalTask',
];

const _expectedPublicMembers = <String>{
  'getter|groupMessageStream|Stream<GroupMessage>|',
  'getter|groupRemovedStream|Stream<String>|',
  'getter|groupReactionChangeStream|Stream<ReactionChange>|',
  'getter|appendGroupEventLogEntry|AppendGroupEventLogEntry?|',
  // Plan 325: the accept-invite drain lane already receives this listener,
  // so it forwards the SAME pending-reaction repository instance rather than
  // threading it separately through four widget public APIs. Exposing it is a
  // deliberate, second exception to DTR-16's no-collaborator rule.
  'getter|pendingReactionRepository|GroupPendingReactionRepository?|',
  // Plan 329: an offline reaction may use the stable listener facade only when
  // its canonical reaction dependencies are composed. This exposes capability,
  // not collaborator state.
  'getter|canHandleReplayReactions|bool|',
  // Plan 330: canonical recovery brackets presentation so an early-page ADD
  // cannot alert before a later-page REMOVE. These are lifecycle commands,
  // not exposed collaborator state.
  'method|retryPendingNotificationDisplays|Future<void>|()',
  'method|beginCanonicalNotificationRecovery|void|()',
  'method|endCanonicalNotificationRecovery|Future<void>|'
      '({required bool canonicalStateComplete, '
      'bool releaseStartupHold = false})',
  'method|handleReplayEnvelope|Future<void>|'
      '(Map<String, dynamic> data, {GroupMessageRepository? msgRepoOverride, '
      'bool rethrowOnError = false, bool allowMembershipBuffer = false, '
      'bool membershipPhaseHeld = false, '
      'GroupMessageDeliveryDisposition? deliveryDisposition})',
  'method|handleReplayReaction|Future<void>|'
      '(Map<String, dynamic> data, {bool rethrowOnError = false})',
  'method|start|void|'
      '(Stream<Map<String, dynamic>> incomingGroupMessages, '
      '{Stream<Map<String, dynamic>>? incomingGroupReactions})',
  'method|flushPendingMembershipDependentMessagesForGroup|Future<void>|'
      '(String groupId, {GroupMessageRepository? msgRepoOverride})',
  'method|retryPendingKeyRepairsForGroupEpoch|Future<int>|'
      '({required String groupId, required int keyEpoch})',
  'method|reserveGroupMediaReceiveCriticalTaskForForegroundHandoff|'
      'Future<GroupMediaReceiveCriticalTaskReservation>|()',
  'method|stop|Future<void>|()',
  'method|dispose|void|()',
};

String _compact(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

CompilationUnit _unit(String path) {
  final result = parseString(
    content: File(path).readAsStringSync(),
    path: path,
    throwIfDiagnostics: false,
  );
  expect(
    result.errors,
    isEmpty,
    reason:
        '$path must parse without diagnostics:\n${result.errors.join('\n')}',
  );
  return result.unit;
}

ClassDeclaration _class(
  CompilationUnit unit,
  String name, {
  required String path,
}) => unit.declarations.whereType<ClassDeclaration>().singleWhere(
  (declaration) => declaration.name.lexeme == name,
  orElse: () => throw TestFailure('$path does not declare $name'),
);

ConstructorDeclaration _unnamedConstructor(
  ClassDeclaration declaration, {
  required String path,
}) => declaration.members.whereType<ConstructorDeclaration>().singleWhere(
  (constructor) => constructor.name == null,
  orElse: () => throw TestFailure(
    '$path does not declare exactly one unnamed ${declaration.name.lexeme} '
    'constructor',
  ),
);

Set<String> _fieldNames(ClassDeclaration declaration) => {
  for (final field in declaration.members.whereType<FieldDeclaration>())
    for (final variable in field.fields.variables) variable.name.lexeme,
};

Set<String> _methodNames(ClassDeclaration declaration) => {
  for (final method in declaration.members.whereType<MethodDeclaration>())
    method.name.lexeme,
};

MethodDeclaration _methodDeclaration(
  ClassDeclaration declaration,
  String methodName,
) {
  final matches = declaration.members.whereType<MethodDeclaration>().where(
    (method) => method.name.lexeme == methodName,
  );
  expect(
    matches,
    hasLength(1),
    reason: '${declaration.name.lexeme} must declare $methodName exactly once',
  );
  return matches.single;
}

String _fieldDeclaration(ClassDeclaration declaration, String fieldName) {
  final matches = declaration.members.whereType<FieldDeclaration>().where(
    (field) => field.fields.variables.any(
      (variable) => variable.name.lexeme == fieldName,
    ),
  );
  expect(
    matches,
    hasLength(1),
    reason: '${declaration.name.lexeme} must own $fieldName exactly once',
  );
  return _compact(matches.single.toSource());
}

String _publicMemberShape(MethodDeclaration method) {
  final kind = method.isGetter ? 'getter' : 'method';
  return '$kind|${method.name.lexeme}|'
      '${_compact(method.returnType?.toSource() ?? '')}|'
      '${_compact(method.parameters?.toSource() ?? '')}';
}

Map<String, String> _namedArguments(ArgumentList arguments) => {
  for (final argument in arguments.arguments.whereType<NamedExpression>())
    argument.name.label.name: _compact(argument.expression.toSource()),
};

final class _CreationCollector extends RecursiveAstVisitor<void> {
  final creations = <String, List<ArgumentList>>{};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = _compact(node.constructorName.type.toSource());
    creations.putIfAbsent(type, () => <ArgumentList>[]).add(node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name.startsWith('_Group')) {
      creations
          .putIfAbsent(name, () => <ArgumentList>[])
          .add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

void _expectPublicFacadeContract(
  CompilationUnit facadeUnit,
  ClassDeclaration facade,
) {
  final declarationSource = _compact(facade.toSource());
  expect(
    declarationSource,
    startsWith('class GroupMessageListener {'),
    reason:
        'GroupMessageListener must remain an ordinary subclassable class, '
        'not final/base/sealed/interface/mixin/abstract',
  );
  expect(facade.extendsClause, isNull);
  expect(facade.withClause, isNull);
  expect(facade.implementsClause, isNull);

  final constructor = _unnamedConstructor(facade, path: _facadePath);
  final actualParameters = constructor.parameters.parameters
      .map((parameter) => _compact(parameter.toSource()))
      .toList(growable: false);
  expect(
    actualParameters,
    _expectedConstructorParameters,
    reason:
        'the public GroupMessageListener constructor parameter order, types, '
        'required markers, nullability, and defaults are frozen',
  );

  final publicMembers = facade.members
      .whereType<MethodDeclaration>()
      .where((method) => !method.name.lexeme.startsWith('_'))
      .map(_publicMemberShape)
      .toSet();
  expect(
    publicMembers,
    _expectedPublicMembers,
    reason:
        'the overridable getters and replay/recovery/start/flush/retry/reserve/'
        'stop/dispose public methods are the complete stable facade API',
  );

  final publicFields = facade.members
      .whereType<FieldDeclaration>()
      .expand((field) => field.fields.variables)
      .where((variable) => !variable.name.lexeme.startsWith('_'))
      .map((variable) => variable.name.lexeme);
  expect(
    publicFields,
    isEmpty,
    reason: 'DTR-16 must not expose collaborators or new public facade state',
  );

  expect(
    facadeUnit.declarations.whereType<ClassDeclaration>().where(
      (declaration) => declaration.name.lexeme == 'GroupMessageListener',
    ),
    hasLength(1),
  );
}

void _expectRealComponent(
  _ComponentContract contract,
  CompilationUnit unit,
  ClassDeclaration processor,
) {
  final source = File(contract.path).readAsStringSync();
  expect(
    source,
    startsWith("part of 'group_message_listener.dart';"),
    reason: '${contract.path} must be a reachable private part of the facade',
  );
  expect(
    RegExp(r'\bGroupMessageListener\b').allMatches(source),
    isEmpty,
    reason:
        '${contract.className} must use typed callback ports, not a facade '
        'back-reference',
  );
  expect(
    RegExp(
      r'^\s*(?:base\s+|final\s+|sealed\s+)?mixin\s+',
      multiLine: true,
    ).allMatches(source),
    isEmpty,
    reason: '${contract.className} must be an object, not a mixin split',
  );
  expect(
    RegExp(r'^\s*extension(?:\s+type)?\s+', multiLine: true).allMatches(source),
    isEmpty,
    reason: '${contract.className} must be an object, not an extension split',
  );

  final classNames = unit.declarations
      .whereType<ClassDeclaration>()
      .map((declaration) => declaration.name.lexeme)
      .toSet();
  expect(
    classNames,
    <String>{contract.className, ...contract.helperClasses},
    reason:
        '${contract.path} may declare only its real processor and exact moved '
        'helper model(s), never an aggregate context/dependency bag',
  );
  expect(
    unit.declarations.whereType<FunctionDeclaration>(),
    isEmpty,
    reason:
        'moved helpers must be owned by ${contract.className}, not remain '
        'library-wide ceremonial functions',
  );

  final processorFields = processor.members
      .whereType<FieldDeclaration>()
      .toList(growable: false);
  for (final field in processorFields) {
    final type = _compact(field.fields.type?.toSource() ?? '');
    expect(
      const <String>{'dynamic', 'Object', 'Object?'}.contains(type),
      isFalse,
      reason:
          '${contract.className} constructor state must use typed ports, not '
          '$type',
    );
    for (final variable in field.fields.variables) {
      expect(
        RegExp(
          r'^_?(?:context|dependencies|dependencyBag|services|ports|facade|listener)$',
          caseSensitive: false,
        ).hasMatch(variable.name.lexeme),
        isFalse,
        reason:
            '${contract.className} must not hide its dependencies in a god '
            'context field',
      );
    }
  }

  expect(
    _fieldDeclaration(processor, '_isStoppingOrDisposed'),
    'final bool Function() _isStoppingOrDisposed;',
    reason:
        '${contract.className} must consult a live lifecycle predicate rather '
        'than capture a constructor-time boolean',
  );
  expect(
    RegExp(r'\b_isStoppingOrDisposed\s*\(\s*\)').allMatches(source),
    isNotEmpty,
    reason:
        '${contract.className} must invoke its live lifecycle predicate; '
        'storing an unused callback behind an analyzer suppression is not a '
        'real lifecycle port',
  );
  expect(
    processor.members.whereType<ConstructorDeclaration>(),
    hasLength(1),
    reason: '${contract.className} must have one constructor-owned lifetime',
  );

  final fields = _fieldNames(processor);
  for (final entry in contract.ownedFieldDeclarations.entries) {
    expect(fields, contains(entry.key));
    expect(
      _fieldDeclaration(processor, entry.key),
      entry.value,
      reason:
          '${entry.key} must move with its exact state shape into '
          '${contract.className}',
    );
  }

  final methods = _methodNames(processor);
  expect(
    methods,
    containsAll(contract.ownedMethods),
    reason:
        '${contract.className} must own its complete moved method/helper '
        'family',
  );
}

void _expectConstructorOwnedComponents(
  ClassDeclaration facade,
  Map<_ComponentContract, ClassDeclaration> processors,
) {
  final constructor = _unnamedConstructor(facade, path: _facadePath);
  final constructorSource = _compact(constructor.toSource());
  final facadeSource = _compact(facade.toSource());
  final collector = _CreationCollector();
  constructor.accept(collector);

  for (final contract in _components) {
    expect(
      _fieldDeclaration(facade, contract.facadeField),
      'late final ${contract.className} ${contract.facadeField};',
      reason:
          '${contract.className} must be stored once for the entire facade '
          'lifetime, including awaited stop/restart',
    );

    final assignment = RegExp(
      '(?:this\\.)?${RegExp.escape(contract.facadeField)}\\s*=\\s*'
      '${RegExp.escape(contract.className)}\\s*\\(',
    );
    expect(
      assignment.allMatches(constructorSource),
      hasLength(1),
      reason:
          '${contract.facadeField} must be initialized exactly once in the '
          'unnamed facade constructor',
    );
    expect(
      assignment.allMatches(facadeSource),
      hasLength(1),
      reason:
          '${contract.facadeField} must never be recreated lazily, per call, '
          'or from start()',
    );
    expect(
      RegExp(
        '${RegExp.escape(contract.className)}\\s*\\(',
      ).allMatches(facadeSource),
      hasLength(1),
      reason:
          '${contract.className} must have exactly one facade-owned creation '
          'site',
    );

    final creations = collector.creations[contract.className] ?? const [];
    expect(
      creations,
      hasLength(1),
      reason:
          '${contract.className} must be created in the unnamed facade '
          'constructor',
    );
    final arguments = _namedArguments(creations.single);
    expect(
      arguments['isStoppingOrDisposed'],
      '() => _isStopping || _isDisposed',
      reason:
          '${contract.className} must receive the live facade lifecycle '
          'predicate, not a captured bool',
    );
    expect(
      RegExp(r'_isStoppingOrDisposed\s*=\s*isStoppingOrDisposed').allMatches(
        _compact(
          _unnamedConstructor(
            processors[contract]!,
            path: contract.path,
          ).toSource(),
        ),
      ),
      hasLength(1),
      reason:
          '${contract.className} must store the live lifecycle predicate in '
          '_isStoppingOrDisposed',
    );

    final componentFields = _fieldNames(processors[contract]!);
    expect(
      componentFields,
      isNot(contains('_subscription')),
      reason: 'subscriptions remain facade-owned',
    );
    expect(
      componentFields,
      isNot(contains('_reactionSubscription')),
      reason: 'reaction scheduling remains facade-owned',
    );
  }

  final systemArguments = _namedArguments(
    collector.creations[_systemComponent.className]!.single,
  );
  expect(systemArguments['getSelfPeerId'], '_getSelfPeerId');
  expect(systemArguments['resolveSelfPeerId'], '_resolveSelfPeerId');
  expect(
    _fieldDeclaration(processors[_systemComponent]!, '_getSelfPeerId'),
    'final Future<String?> Function()? _getSelfPeerId;',
    reason:
        'system self-removal/dissolve logic must retain the raw nullable '
        'identity loader port',
  );
  expect(
    _fieldDeclaration(processors[_systemComponent]!, '_resolveSelfPeerId'),
    'final Future<String?> Function() _resolveSelfPeerId;',
    reason:
        'system authorization must retain the distinct cached identity '
        'resolver port',
  );

  final reactionArguments = _namedArguments(
    collector.creations[_reactionComponent.className]!.single,
  );
  expect(reactionArguments['resolveSelfPeerId'], '_resolveSelfPeerId');
  expect(
    _fieldDeclaration(processors[_reactionComponent]!, '_resolveSelfPeerId'),
    'final Future<String?> Function() _resolveSelfPeerId;',
  );
}

void _expectExactOwnership(
  CompilationUnit facadeUnit,
  ClassDeclaration facade,
  Map<_ComponentContract, CompilationUnit> partUnits,
  Map<_ComponentContract, ClassDeclaration> processors,
) {
  final facadeFields = _fieldNames(facade);
  final facadeMethods = _methodNames(facade);

  expect(facadeFields, containsAll(_retainedFacadeFields));
  expect(facadeMethods, containsAll(_retainedFacadeMethods));

  final facadeTopLevelClasses = facadeUnit.declarations
      .whereType<ClassDeclaration>()
      .map((declaration) => declaration.name.lexeme)
      .toSet();
  final facadeTopLevelFunctions = facadeUnit.declarations
      .whereType<FunctionDeclaration>()
      .map((declaration) => declaration.name.lexeme)
      .toSet();

  for (final owner in _components) {
    for (final field in owner.ownedFieldDeclarations.keys) {
      expect(
        facadeFields,
        isNot(contains(field)),
        reason: '$field must leave the facade and move to ${owner.className}',
      );
      for (final other in _components.where((item) => item != owner)) {
        expect(
          _fieldNames(processors[other]!),
          isNot(contains(field)),
          reason: '$field belongs only to ${owner.className}',
        );
      }
    }

    for (final method in owner.ownedMethods) {
      if (!owner.delegatedPublicMethods.contains(method)) {
        expect(
          facadeMethods,
          isNot(contains(method)),
          reason:
              '$method must be implemented only by ${owner.className}, not '
              'duplicated on the facade',
        );
      } else {
        expect(
          facadeMethods,
          contains(method),
          reason: '$method remains a stable public facade delegate',
        );
      }
      for (final other in _components.where((item) => item != owner)) {
        expect(
          _methodNames(processors[other]!),
          isNot(contains(method)),
          reason: '$method belongs only to ${owner.className}',
        );
      }
    }

    for (final helper in owner.helperClasses) {
      expect(
        facadeTopLevelClasses,
        isNot(contains(helper)),
        reason: '$helper must move into ${owner.path}',
      );
      for (final other in _components.where((item) => item != owner)) {
        final otherClasses = partUnits[other]!.declarations
            .whereType<ClassDeclaration>()
            .map((declaration) => declaration.name.lexeme);
        expect(
          otherClasses,
          isNot(contains(helper)),
          reason: '$helper belongs only to ${owner.path}',
        );
      }
    }
  }

  expect(
    facadeTopLevelFunctions,
    isNot(contains('_samePendingReaction')),
    reason:
        '_samePendingReaction must become reaction-processor-owned behavior',
  );
  expect(
    facadeMethods,
    contains('_handleMessage'),
    reason:
        'the persist -> emit -> reaction -> repair -> notification -> tracked '
        'media ordering seam deliberately remains facade-owned',
  );
  expect(
    facadeMethods,
    containsAll(<String>{'start', 'stop', 'dispose'}),
    reason: 'subscription and lifecycle ownership deliberately stays central',
  );

  final flushBody = _compact(
    _methodDeclaration(
      facade,
      'flushPendingMembershipDependentMessagesForGroup',
    ).body.toSource(),
  );
  expect(
    flushBody,
    matches(
      RegExp(
        r'\breturn\s+_membershipDependentMessageBuffer\s*\.\s*'
        r'flushPendingMembershipDependentMessagesForGroup\s*\(',
      ),
    ),
    reason:
        'the stable flush method must delegate to the constructor-owned '
        'membership buffer',
  );

  final reservationBody = _compact(
    _methodDeclaration(
      facade,
      'reserveGroupMediaReceiveCriticalTaskForForegroundHandoff',
    ).body.toSource(),
  );
  expect(
    reservationBody,
    matches(
      RegExp(
        r'\breturn\s+_mediaReceiveCoordinator\s*\.\s*'
        r'reserveGroupMediaReceiveCriticalTaskForForegroundHandoff\s*\(',
      ),
    ),
    reason:
        'the stable reservation method must delegate to the constructor-owned '
        'media coordinator',
  );
}

String _arrayBody(String source, String arrayName) {
  final match = RegExp(
    '^readonly\\s+${RegExp.escape(arrayName)}=\\(\\n([\\s\\S]*?)^\\)',
    multiLine: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'missing readonly $arrayName array');
  return match!.group(1)!;
}

void _expectExactGroupRegistration(String groupArray, String path) {
  expect(
    RegExp(
      '^\\s*${RegExp.escape('"$path"')}\\s*\$',
      multiLine: true,
    ).allMatches(groupArray),
    hasLength(1),
    reason:
        '$path must occur exactly once as a live, uncommented GROUP_TESTS '
        'entry',
  );
}

void main() {
  test(
    'DTR-16 extracts four state-owning collaborators behind the stable facade',
    () {
      final facadeUnit = _unit(_facadePath);
      final facade = _class(
        facadeUnit,
        'GroupMessageListener',
        path: _facadePath,
      );
      _expectPublicFacadeContract(facadeUnit, facade);

      final missingParts = _components
          .where((component) => !File(component.path).existsSync())
          .map((component) => component.path)
          .toList(growable: false);
      expect(
        missingParts,
        isEmpty,
        reason:
            'DTR-16 RED: four real collaborator part files must exist before '
            'their state, methods, ports, and facade delegation can be '
            'verified: $missingParts',
      );

      final partUnits = <_ComponentContract, CompilationUnit>{
        for (final component in _components) component: _unit(component.path),
      };
      final processors = <_ComponentContract, ClassDeclaration>{
        for (final component in _components)
          component: _class(
            partUnits[component]!,
            component.className,
            path: component.path,
          ),
      };

      for (final component in _components) {
        _expectRealComponent(
          component,
          partUnits[component]!,
          processors[component]!,
        );
      }
      final systemProcessor = processors[_systemComponent]!;
      for (final entry in const <String, String>{
        '_emitGroupMessageIfActive': '_emitGroupMessage(message)',
        '_emitGroupRemovedIfActive': '_emitGroupRemoved(groupId)',
      }.entries) {
        expect(
          _compact(
            _methodDeclaration(systemProcessor, entry.key).body.toSource(),
          ),
          '{if (_isStoppingOrDisposed()) return; ${entry.value};}',
          reason:
              '${entry.key} must fence only the processor-to-facade emission '
              'boundary while accepted durable transition work remains '
              'in-flight through stop',
        );
      }
      expect(
        RegExp(
          r'\b_isStoppingOrDisposed\s*\(\s*\)',
        ).allMatches(File(_systemComponent.path).readAsStringSync()),
        hasLength(2),
        reason:
            'the system processor lifecycle predicate belongs only at its two '
            'facade-emission boundaries, not as an early durable-work abort',
      );
      _expectConstructorOwnedComponents(facade, processors);
      _expectExactOwnership(facadeUnit, facade, partUnits, processors);
    },
  );

  test('TC-296-07 keeps DTR-16 registration and architecture scope exact', () {
    final gateSource = File('scripts/run_test_gates.sh').readAsStringSync();
    final groupArray = _arrayBody(gateSource, 'GROUP_TESTS');
    _expectExactGroupRegistration(groupArray, _contractTestPath);
    _expectExactGroupRegistration(groupArray, _deviceAnnounceTestPath);

    final facadeUnit = _unit(_facadePath);
    final actualParts = facadeUnit.directives
        .whereType<PartDirective>()
        .map((directive) => directive.uri.stringValue)
        .whereType<String>()
        .toSet();
    final expectedParts = _components
        .map((component) => component.path.split('/').last)
        .toSet();
    expect(
      actualParts,
      expectedParts,
      reason:
          'the four DTR-16 files must be reachable exclusively through exact '
          'facade part directives',
    );

    final hostGateSource = File(
      'scripts/run_host_test_gates.sh',
    ).readAsStringSync();
    expect(
      RegExp(
        r'''^\s*rg --files test/features -g '\*_test\.dart' '''
        r'''\| sort >"\$plan_file"\s*$''',
        multiLine: true,
      ).allMatches(hostGateSource),
      hasLength(1),
      reason:
          'feature-host-all must retain one live test/features discovery '
          'command',
    );
    final hostGatePlan = Process.runSync('bash', <String>[
      'scripts/run_host_test_gates.sh',
      'feature-host-all',
      '--list',
    ]);
    expect(
      hostGatePlan.exitCode,
      0,
      reason:
          'the live feature-host-all selector must remain executable:\n'
          '${hostGatePlan.stderr}',
    );
    expect(
      RegExp(
        "^\\s*\\d+\\.\\s+flutter test "
        "'${RegExp.escape(_contractTestPath)}'\\s*\$",
        multiLine: true,
      ).allMatches(hostGatePlan.stdout as String),
      hasLength(1),
      reason:
          'the live feature-host-all plan must select the decomposition '
          'contract exactly once',
    );

    final manifestSource = File(_architectureExceptionsPath).readAsStringSync();
    final manifest = jsonDecode(manifestSource) as Map<String, dynamic>;
    final dependencyExceptions =
        manifest['dependencyExceptions'] as List<dynamic>;
    expect(
      dependencyExceptions,
      hasLength(165),
      reason:
          'DTR-16 must not add or rebaseline a dependency exception; '
          'DTR-18 removed only its reviewed resume rows',
    );
    expect(
      (manifest['placementExceptions'] as List<dynamic>),
      isEmpty,
      reason:
          'DTR-16 must not add or rebaseline a placement exception; '
          'DTR-18 closed the reviewed placement family',
    );
    for (final forbidden in <String>{
      'DTR-16',
      'Plan 296',
      _contractTestPath,
      ..._components.map((component) => component.path),
    }) {
      expect(
        manifestSource,
        isNot(contains(forbidden)),
        reason:
            'DTR-16 part/test reachability must not be purchased with an '
            'architecture exception: $forbidden',
      );
    }

    final facadeExceptions = dependencyExceptions
        .cast<Map<String, dynamic>>()
        .where(
          (entry) =>
              entry['source'] == _facadePath || entry['target'] == _facadePath,
        )
        .toList(growable: false);
    expect(
      facadeExceptions,
      isEmpty,
      reason:
          'DTR-18 removed the old resume-to-listener exception; neither that '
          'identity nor an app-path retarget may remain',
    );
  });
}
