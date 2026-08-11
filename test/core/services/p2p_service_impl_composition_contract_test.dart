import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _facadePath = 'lib/core/services/p2p_service_impl.dart';
const _inboxPartPath = 'lib/core/services/p2p_impl/p2p_inbox_coordinator.dart';
const _peerPartPath =
    'lib/core/services/p2p_impl/p2p_peer_transport_coordinator.dart';
const _bootstrapPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _applicationRootPath = 'lib/app/application_root.dart';
const _contractPath =
    'test/core/services/p2p_service_impl_composition_contract_test.dart';
const _exceptionsPath =
    'tool/architecture_guard/architecture_boundary_exceptions.json';

const _implements = <String>[
  'P2PService',
  'DetailedInboxStore',
  'AckOrExpiryInboxStore',
  'MediaExpiryBoundedInboxStore',
  'ReadinessProofRecorder',
  'P2PFullInboxDrain',
  'DurableLanSender',
  'RelayPresenceLookup',
  'RelayPresenceSet',
  'PeerLivenessProbe',
  'PeerDropSignal',
  'InboxAttentionSignal',
];

const _constructorParameters = <String>[
  'required Bridge bridge',
  'LocalP2PService? localP2PService',
  'PushTokenStore? pushTokenStore',
  'Future<String?> Function()? liveFcmTokenReader',
  'ReceivedWakeTokenStore? receivedWakeTokenStore',
  'AcceptedInboxWakeTokenHashObserver? acceptedInboxWakeTokenHashObserver',
  'AccountMigrationNetworkGate accountMigrationNetworkGate = '
      'allowAccountMigrationNetworkSideEffects',
  'required InboxStagingRepository inboxStagingRepository',
  'ReplayRecoveredInboxChatMessage? replayRecoveredInboxChatMessage',
  'ReplayRecoveredInboxChatMessage? replayLiveLanChatMessage',
  'ReplayRecoveredInboxChatMessage? replayLiveDirectChatMessage',
  'ReplayRecoveredInboxIntroductionMessage? '
      'replayRecoveredInboxIntroductionMessage',
  'ReplayRecoveredInboxContactRequestMessage? '
      'replayRecoveredInboxContactRequest',
  'ReplayRecoveredInboxChatMessage? replayRecoveredInboxReaction',
  'ReplayRecoveredInboxChatMessage? replayRecoveredInboxMessageDeletion',
  'Future<String?> Function(ChatMessage message)? predecryptInboxChatEntry',
  'TransportMetrics? transportMetrics',
  'Duration? keyRotationGracePeriodOverride',
  'Stream<void>? networkChangeSignal',
  'String? Function()? activePeerId',
  // 360: the exact transport peer an ACTIVE linked-secondary credential names,
  // or null on an ordinary primary. When non-null, `startNode` qualifies the
  // peer the node actually came up as before ANY Dart warm/inbox work.
  'String? Function()? requiredTransportPeerId',
  // 360 repair: the LOGICAL account peer while a linked transport runs. The
  // account-migration side-effect gate is asked about THIS peer, never the
  // transport peer, which account authority does not cover.
  'String? Function()? logicalAccountPeerId',
];

const _publicFields = <String>{
  'refreshFailureThreshold',
  'recoveryBackoffMaxSkipTicks',
  'healthCheckInterval',
  'startupRelayRecoveryDelay',
  'startupRelayRecoveryRetryInterval',
  'warmTaskTimeout',
  'foregroundInboxTimeout',
  'maxInboxPages',
  'maxRecoverableInboxReplayEntries',
  'maxConcurrentInboxDecrypts',
};

const _publicMethods = <String>{
  'currentState',
  'stateStream',
  'messageStream',
  'incomingLocalMediaStream',
  'startNode',
  'startNodeCore',
  'warmBackground',
  'startEarlyLocalDiscovery',
  'debugLibp2pListenPort',
  'stopNode',
  'sendMessage',
  'sendMessageWithReply',
  'discoverPeer',
  'dialPeer',
  'warmPeer',
  'onNetworkChanged',
  'hasPendingResumeStarted',
  'markResumeStarted',
  'clearResumeStarted',
  'noteTransportSessionReset',
  'recordSuccessfulSendProof',
  'checkResumeAlreadyOnline',
  'storeInInbox',
  'storeInInboxDetailed',
  'storeInAckCustodyInboxDetailed',
  'storeInMediaExpiryBoundedInboxDetailed',
  'retrieveInbox',
  'registerPushToken',
  'lastRecoveryMethod',
  'consecutiveRefreshFailures',
  'performImmediateHealthCheck',
  'drainOfflineInbox',
  'drainOfflineInboxFully',
  'probeRelay',
  'lookupRelayPresence',
  'setPresence',
  'pingPeer',
  'isPeerSuspectedDropped',
  'setPeerDropSuspected',
  'countNeedsAttentionInboxEntries',
  'isConnectedToPeer',
  'isLocalPeer',
  'hasNonCircuitDirectConn',
  'lastKnownGoodTransport',
  'recordSuccessfulTransport',
  'discoverLocalPeer',
  'sendLocalMessageDurable',
  'sendLocalMessage',
  'sendLocalMedia',
  'dispose',
};

const _inboxDeclarations = <String>{'_P2PInboxPort', '_P2PInboxCoordinator'};
const _peerDeclarations = <String>{
  '_LearnedTransport',
  '_PresenceCacheEntry',
  '_WarmAttempt',
  '_PeerTransportDiagnostic',
  '_P2PPeerTransportPort',
  '_P2PPeerTransportCoordinator',
};

const _inboxFields = <String>{
  '_receivedWakeTokenStore',
  '_acceptedInboxWakeTokenHashObserver',
  '_inboxStagingRepository',
  '_replayRecoveredInboxChatMessage',
  '_replayLiveLanChatMessage',
  '_replayLiveDirectChatMessage',
  '_replayRecoveredInboxIntroductionMessage',
  '_replayRecoveredInboxContactRequest',
  '_replayRecoveredInboxReaction',
  '_replayRecoveredInboxMessageDeletion',
  '_predecryptInboxChatEntry',
  '_drainInProgress',
  '_drainInProgressWaitsAllPages',
  '_pendingStartupDrain',
  '_pendingStartupDrainWaitForAllPages',
};

const _inboxMethods = <String>{
  '_normalizeInboxTimestamp',
  '_messageTypeFromEnvelope',
  '_stagingEntryFromRawInboxMessage',
  '_stagingEntryFromDirectMessage',
  '_stagingEntryFromLanMessage',
  '_shouldDurablyStageDeferredDirectChat',
  '_messageWithoutConfirmNonce',
  '_replayUnstagedReaction',
  '_processDurablyStagedDirectChat',
  '_replayDurablyStagedLanChat',
  '_predecryptInboxChatEntries',
  '_replayStagedInboxEntries',
  '_quarantineRecoveredInboxEntry',
  '_applyRecoveredInboxOutcome',
  '_retrievePendingInboxPage',
  '_drainOfflineInbox',
  '_continueDrainingOfflineInboxDurably',
  '_drainOfflineInboxDurably',
  '_commitInboundLanChatMessage',
  '_handleMessageReceived',
  'storeInInbox',
  'storeInInboxDetailed',
  'storeInAckCustodyInboxDetailed',
  'storeInMediaExpiryBoundedInboxDetailed',
  '_waitForNodeStart',
  '_inboxStoreReadinessFailure',
  'retrieveInbox',
  'drainOfflineInbox',
  'drainOfflineInboxFully',
  '_scheduleStartupDrain',
  'countNeedsAttentionInboxEntries',
  'onNodeStateTransition',
};

const _inboxDelegates = <String>{
  'storeInInbox',
  'storeInInboxDetailed',
  'storeInAckCustodyInboxDetailed',
  'storeInMediaExpiryBoundedInboxDetailed',
  'retrieveInbox',
  'drainOfflineInbox',
  'drainOfflineInboxFully',
  'countNeedsAttentionInboxEntries',
};

const _inboxPortMembers = <String>{
  'readNodeState',
  'nodeStateStream',
  'allowsAccountNetworkSideEffects',
  'confirmDirectMessage',
  'storeInbox',
  'retrieveInbox',
  'retrievePendingInbox',
  'ackInbox',
  'emitIncomingMessage',
  'isMessageStreamClosed',
  'recordTransport',
  'recordSuccessfulInboxProof',
  'recordInboxProofFailure',
};

const _peerFields = <String>{
  '_localP2P',
  '_transportMetrics',
  '_peersUpgradedToDirect',
  '_learnedTransport',
  '_presenceCache',
  '_presenceCacheTtl',
  '_warmAttempts',
  '_activePeerId',
  '_lastNetworkRewarmAt',
  '_localDiscoveryActive',
  '_lanDialForwardedPeerIds',
  '_lanEmptyReResolvedPeerIds',
  '_resolvedAdvertQuicPort',
  '_resolvedAdvertTcpPort',
  '_localNetworkProven',
  '_lanPermProbeTimer',
  '_suspectedDroppedPeers',
  '_warmLanTimeout',
  '_warmDialTimeout',
  '_warmCooldownFloor',
  '_warmCooldownCeil',
};

const _peerMethods = <String>{
  'startEarlyLocalDiscovery',
  '_startLocalDiscovery',
  '_libp2pListenPort',
  '_setLocalDiscoveryActive',
  '_setLocalDiscoveryInactive',
  '_startLanPermProbe',
  '_recordLanAvailability',
  '_forwardLanPeersToLibp2pDial',
  '_reResolveEmptyLanPeer',
  '_maybePublishLibp2pAdvertPorts',
  '_shortPeer',
  'warmPeer',
  '_onWarmDialOutcome',
  'onNetworkChanged',
  '_shortId',
  '_recordPeerUpgrade',
  '_recordPeerDowngrade',
  '_resolveFullPeerId',
  '_inferTransportForPeer',
  'probeRelay',
  'lookupRelayPresence',
  '_relayPresenceFromString',
  'setPresence',
  'pingPeer',
  'isPeerSuspectedDropped',
  'setPeerDropSuspected',
  'isConnectedToPeer',
  'isLocalPeer',
  'hasNonCircuitDirectConn',
  '_libp2pLanMediaEnabled',
  'lastKnownGoodTransport',
  'recordSuccessfulTransport',
  'discoverLocalPeer',
  'sendLocalMessageDurable',
  'sendLocalMessage',
  'sendLocalMedia',
  '_sendLibp2pLanMedia',
};

const _peerDelegates = <String>{
  'startEarlyLocalDiscovery',
  'warmPeer',
  'onNetworkChanged',
  'probeRelay',
  'lookupRelayPresence',
  'setPresence',
  'pingPeer',
  'isPeerSuspectedDropped',
  'setPeerDropSuspected',
  'isConnectedToPeer',
  'isLocalPeer',
  'hasNonCircuitDirectConn',
  'lastKnownGoodTransport',
  'recordSuccessfulTransport',
  'discoverLocalPeer',
  'sendLocalMessageDurable',
  'sendLocalMessage',
  'sendLocalMedia',
};

const _retainedFacadeMethods = <String>{
  '_allowsAccountNetworkSideEffects',
  '_emitIncomingMessage',
  '_emitState',
  '_computeDirectReady',
  '_handlePeerConnected',
  '_handlePeerDisconnected',
  '_handleAddressesUpdated',
  '_handleRelayStateChanged',
  'startNode',
  'startNodeCore',
  'stopNode',
  'sendMessage',
  'sendMessageWithReply',
  'discoverPeer',
  'dialPeer',
  'registerPushToken',
  'dispose',
};

const _callbackSlots = <String>[
  'onMessageReceived',
  'onPeerConnected',
  'onPeerDisconnected',
  'onAddressesUpdated',
  'onRelayStateChanged',
];

String _compact(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

CompilationUnit _unit(String path) => parseString(
  content: File(path).readAsStringSync(),
  path: path,
  throwIfDiagnostics: false,
).unit;

ClassDeclaration _class(
  CompilationUnit unit,
  String name, {
  required String path,
}) => unit.declarations.whereType<ClassDeclaration>().singleWhere(
  (declaration) => declaration.name.lexeme == name,
  orElse: () => throw TestFailure('$path does not declare $name'),
);

ConstructorDeclaration _constructor(
  ClassDeclaration declaration, {
  required String path,
}) => declaration.members.whereType<ConstructorDeclaration>().singleWhere(
  (constructor) => constructor.name == null,
  orElse: () => throw TestFailure(
    '$path must declare exactly one unnamed ${declaration.name.lexeme} '
    'constructor',
  ),
);

MethodDeclaration _method(ClassDeclaration declaration, String name) =>
    declaration.members.whereType<MethodDeclaration>().singleWhere(
      (method) => method.name.lexeme == name,
      orElse: () => throw TestFailure(
        '${declaration.name.lexeme} does not declare $name',
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

Set<String> _memberNames(ClassDeclaration declaration) => {
  ..._fieldNames(declaration),
  ..._methodNames(declaration),
};

String _fieldDeclaration(ClassDeclaration declaration, String name) {
  final matches = declaration.members.whereType<FieldDeclaration>().where(
    (field) =>
        field.fields.variables.any((variable) => variable.name.lexeme == name),
  );
  expect(
    matches,
    hasLength(1),
    reason: '${declaration.name.lexeme} must declare $name exactly once',
  );
  return _compact(matches.single.toSource());
}

final class _IdentifierCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

final class _CreationCollector extends RecursiveAstVisitor<void> {
  final creations = <String, List<AstNode>>{};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = _compact(node.constructorName.type.toSource());
    creations.putIfAbsent(name, () => <AstNode>[]).add(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null) {
      creations.putIfAbsent(node.methodName.name, () => <AstNode>[]).add(node);
    }
    super.visitMethodInvocation(node);
  }
}

void _expectPrivatePart({
  required String path,
  required Set<String> declarations,
  required String portName,
}) {
  final source = File(path).readAsStringSync();
  final unit = _unit(path);
  expect(
    RegExp(
      r'''^\s*part of ['"]\.\./p2p_service_impl\.dart['"];''',
    ).hasMatch(source),
    isTrue,
    reason: '$path must be a URI part of $_facadePath',
  );
  expect(
    unit.declarations,
    everyElement(isA<ClassDeclaration>()),
    reason:
        '$path may contain only the literal private class declarations, '
        'not top-level functions, variables, typedefs, enums, mixins, or '
        'extensions',
  );
  final actualDeclarations = unit.declarations
      .whereType<ClassDeclaration>()
      .map((declaration) => declaration.name.lexeme)
      .toSet();
  expect(
    actualDeclarations,
    declarations,
    reason: '$path declaration whitelist',
  );
  expect(actualDeclarations, everyElement(startsWith('_')));

  final identifiers = _IdentifierCollector();
  unit.accept(identifiers);
  for (final forbidden in <String>{
    'P2PServiceImpl',
    'Bridge',
    'GetIt',
    'getIt',
    'serviceLocator',
    'dependencyBag',
  }) {
    expect(
      identifiers.names,
      isNot(contains(forbidden)),
      reason: '$path must not retain/recover $forbidden',
    );
    expect(
      RegExp('\\b${RegExp.escape(forbidden)}\\b').hasMatch(source),
      isFalse,
      reason: '$path source must not retain/recover $forbidden',
    );
  }
  for (final slot in _callbackSlots) {
    expect(
      RegExp('\\.${RegExp.escape(slot)}\\s*=\\s*(?!=)').hasMatch(source),
      isFalse,
      reason: '$path must not own the mutable Bridge.$slot callback slot',
    );
  }

  final port = _class(unit, portName, path: path);
  expect(port.members.whereType<FieldDeclaration>(), isNotEmpty);
  for (final field in port.members.whereType<FieldDeclaration>()) {
    expect(field.fields.isFinal, isTrue, reason: '$portName must be immutable');
    final type = _compact(field.fields.type?.toSource() ?? '');
    expect(type, isNotEmpty, reason: '$portName dependencies must be typed');
    expect(
      const <String>{'dynamic', 'Object', 'Object?'}.contains(type),
      isFalse,
      reason: '$portName must not use $type as a dependency type',
    );
  }
}

void _expectMovedOwners({
  required ClassDeclaration facade,
  required ClassDeclaration owner,
  required ClassDeclaration other,
  required Set<String> fields,
  required Set<String> methods,
  required Set<String> delegates,
  required String facadeField,
}) {
  final facadeFields = _fieldNames(facade);
  final facadeMethods = _methodNames(facade);
  final ownerFields = _fieldNames(owner);
  final ownerMethods = _methodNames(owner);
  final otherFields = _fieldNames(other);
  final otherMethods = _methodNames(other);

  for (final field in fields) {
    expect(
      ownerFields,
      contains(field),
      reason: '$field must move to ${owner.name.lexeme}',
    );
    expect(facadeFields, isNot(contains(field)));
    expect(otherFields, isNot(contains(field)));
  }
  for (final method in methods) {
    expect(
      ownerMethods,
      contains(method),
      reason: '$method must move to ${owner.name.lexeme}',
    );
    expect(otherMethods, isNot(contains(method)));
    if (delegates.contains(method)) {
      expect(facadeMethods, contains(method));
      final body = _compact(_method(facade, method).body.toSource());
      expect(
        RegExp(
          '${RegExp.escape(facadeField)}\\.${RegExp.escape(method)}\\s*\\(',
        ).allMatches(body),
        hasLength(1),
        reason: 'P2PServiceImpl.$method must be one thin delegate',
      );
    } else {
      expect(
        facadeMethods,
        isNot(contains(method)),
        reason: '$method must not retain a facade decision body',
      );
    }
  }
}

String _arrayBody(String source, String arrayName) {
  final match = RegExp(
    '^readonly\\s+${RegExp.escape(arrayName)}=\\(\\n([\\s\\S]*?)^\\)',
    multiLine: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'missing readonly $arrayName array');
  return match!.group(1)!;
}

String _fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in input.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _publicApiFingerprint(ClassDeclaration facade) {
  final constructor = _constructor(facade, path: _facadePath);
  final parts = <String>[
    'implements=${facade.implementsClause?.interfaces.map((type) => _compact(type.toSource())).join(',')}',
    for (final parameter in constructor.parameters.parameters)
      'parameter=${_compact(parameter.toSource())}',
    for (final field in facade.members.whereType<FieldDeclaration>())
      if (field.fields.variables.any(
        (variable) => !variable.name.lexeme.startsWith('_'),
      ))
        'field=${_compact(field.toSource())}',
    for (final method in facade.members.whereType<MethodDeclaration>())
      if (!method.name.lexeme.startsWith('_'))
        'method=${method.isStatic}|${method.isGetter}|${method.isSetter}|'
            '${_compact(method.returnType?.toSource() ?? '')}|'
            '${method.name.lexeme}|'
            '${_compact(method.typeParameters?.toSource() ?? '')}|'
            '${_compact(method.parameters?.toSource() ?? '')}',
  ];
  return _fnv1a32(parts.join('\n'));
}

// Token/AST fingerprint of the complete public/static facade declaration. It
// excludes bodies, so moving decisions behind coordinators does not change it.
//
// 360: repinned for exactly two added optional constructor parameters,
// `requiredTransportPeerId` and (in the bounded repair) `logicalAccountPeerId`. No public field or method was added, removed, or
// re-signed; the linked-transport qualification lives entirely in a private
// method on the existing `startNode` path.
const _expectedFacadeApiFingerprint = 'f517cea8';

void _expectCallbackOwnership(ClassDeclaration facade, String facadeSource) {
  final constructorBody = _compact(
    _constructor(facade, path: _facadePath).body.toSource(),
  );
  final disposeBody = _compact(_method(facade, 'dispose').body.toSource());
  for (final slot in _callbackSlots) {
    final assignment = RegExp('_bridge\\.${RegExp.escape(slot)}\\s*=\\s*(?!=)');
    expect(
      assignment.allMatches(constructorBody),
      hasLength(1),
      reason: '$slot must be assigned once by the facade constructor',
    );
    expect(
      RegExp(
        '_bridge\\.${RegExp.escape(slot)}\\s*=\\s*null\\s*;',
      ).allMatches(disposeBody),
      hasLength(1),
      reason: '$slot must be cleared once by facade dispose',
    );
    expect(
      assignment.allMatches(_compact(facadeSource)),
      hasLength(2),
      reason: '$slot may have only its facade assignment and clear',
    );
  }
  for (final entry in const <String, String>{
    'onPeerConnected': '_handlePeerConnected',
    'onPeerDisconnected': '_handlePeerDisconnected',
    'onAddressesUpdated': '_handleAddressesUpdated',
    'onRelayStateChanged': '_handleRelayStateChanged',
  }.entries) {
    expect(
      RegExp(
        '_bridge\\.${RegExp.escape(entry.key)}\\s*=\\s*'
        '${RegExp.escape(entry.value)}\\s*;',
      ).allMatches(constructorBody),
      hasLength(1),
      reason: '${entry.key} must stay wired to ${entry.value}',
    );
  }
}

List<({String path, AstNode creation})> _productionCreations() {
  final result = <({String path, AstNode creation})>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    if (!source.contains('P2PServiceImpl')) continue;
    final collector = _CreationCollector();
    parseString(
      content: source,
      path: entity.path,
      throwIfDiagnostics: false,
    ).unit.accept(collector);
    for (final creation
        in collector.creations['P2PServiceImpl'] ?? const <AstNode>[]) {
      result.add((path: entity.path, creation: creation));
    }
  }
  return result;
}

void main() {
  test('DTR-17 transfers exact P2P owners behind port-only coordinators', () {
    final missingParts = <String>[
      _inboxPartPath,
      _peerPartPath,
    ].where((path) => !File(path).existsSync()).toList(growable: false);
    expect(
      missingParts,
      isEmpty,
      reason:
          'DTR-17 RED: both real coordinator part files must exist before '
          'their exact declarations, owners, typed ports, and facade '
          'delegation can be verified: $missingParts',
    );

    final facadeUnit = _unit(_facadePath);
    final facade = _class(facadeUnit, 'P2PServiceImpl', path: _facadePath);
    expect(
      facadeUnit.directives
          .whereType<PartDirective>()
          .map((directive) => directive.uri.stringValue)
          .whereType<String>()
          .toSet(),
      <String>{
        'p2p_impl/p2p_inbox_coordinator.dart',
        'p2p_impl/p2p_peer_transport_coordinator.dart',
      },
      reason: 'the facade must have exactly the two DTR-17 part directives',
    );
    _expectPrivatePart(
      path: _inboxPartPath,
      declarations: _inboxDeclarations,
      portName: '_P2PInboxPort',
    );
    _expectPrivatePart(
      path: _peerPartPath,
      declarations: _peerDeclarations,
      portName: '_P2PPeerTransportPort',
    );

    final inboxUnit = _unit(_inboxPartPath);
    final peerUnit = _unit(_peerPartPath);
    final inboxPort = _class(inboxUnit, '_P2PInboxPort', path: _inboxPartPath);
    final inbox = _class(
      inboxUnit,
      '_P2PInboxCoordinator',
      path: _inboxPartPath,
    );
    final peerPort = _class(
      peerUnit,
      '_P2PPeerTransportPort',
      path: _peerPartPath,
    );
    final peer = _class(
      peerUnit,
      '_P2PPeerTransportCoordinator',
      path: _peerPartPath,
    );
    expect(
      _memberNames(inboxPort),
      _inboxPortMembers,
      reason: '_P2PInboxPort must stay the exact narrow immutable port',
    );
    expect(
      _memberNames(peerPort),
      containsAll(<String>{'readNodeState', 'allowsAccountNetworkSideEffects'}),
    );

    expect(
      _fieldDeclaration(facade, '_inboxCoordinator'),
      'late final _P2PInboxCoordinator _inboxCoordinator;',
    );
    expect(
      _fieldDeclaration(facade, '_peerTransportCoordinator'),
      'late final _P2PPeerTransportCoordinator _peerTransportCoordinator;',
    );
    _expectMovedOwners(
      facade: facade,
      owner: inbox,
      other: peer,
      fields: _inboxFields,
      methods: _inboxMethods,
      delegates: _inboxDelegates,
      facadeField: '_inboxCoordinator',
    );
    _expectMovedOwners(
      facade: facade,
      owner: peer,
      other: inbox,
      fields: _peerFields,
      methods: _peerMethods,
      delegates: _peerDelegates,
      facadeField: '_peerTransportCoordinator',
    );
    expect(_methodNames(facade), containsAll(_retainedFacadeMethods));

    final constructorSource = _compact(
      _constructor(facade, path: _facadePath).toSource(),
    );
    final facadeSource = _compact(facade.toSource());
    for (final entry in const <String, String>{
      '_inboxCoordinator': '_P2PInboxCoordinator',
      '_peerTransportCoordinator': '_P2PPeerTransportCoordinator',
    }.entries) {
      expect(
        RegExp(
          '${RegExp.escape(entry.key)}\\s*=\\s*'
          '${RegExp.escape(entry.value)}\\s*\\(',
        ).allMatches(constructorSource),
        hasLength(1),
      );
      expect(
        RegExp('${RegExp.escape(entry.value)}\\s*\\(').allMatches(facadeSource),
        hasLength(1),
        reason: '${entry.value} must have one facade-owned lifetime',
      );
    }
    for (final port in const <String>[
      '_P2PInboxPort',
      '_P2PPeerTransportPort',
    ]) {
      expect(
        RegExp('${RegExp.escape(port)}\\s*\\(').allMatches(constructorSource),
        hasLength(1),
      );
    }
    final firstCallback = constructorSource.indexOf(
      '_bridge.onMessageReceived =',
    );
    expect(firstCallback, greaterThan(-1));
    expect(
      constructorSource.indexOf('_inboxCoordinator ='),
      inInclusiveRange(0, firstCallback - 1),
    );
    expect(
      constructorSource.indexOf('_peerTransportCoordinator ='),
      inInclusiveRange(0, firstCallback - 1),
    );

    final nextCallback = constructorSource.indexOf('_bridge.onPeerConnected =');
    final directCallback = constructorSource.substring(
      firstCallback,
      nextCallback,
    );
    expect(
      RegExp(
        r'_inboxCoordinator\._handleMessageReceived\s*\(',
      ).allMatches(directCallback),
      hasLength(1),
      reason: 'the direct callback must dispatch once to the inbox owner',
    );
    final debugShim = _compact(
      _method(facade, 'debugLibp2pListenPort').body.toSource(),
    );
    expect(
      debugShim,
      contains('_P2PPeerTransportCoordinator'),
      reason: 'the public static listen-port helper must remain a thin shim',
    );
  });

  test(
    'TC-295-02 freezes the P2P facade API callback ownership and production construction',
    () {
      final facadeSource = File(_facadePath).readAsStringSync();
      final facadeUnit = _unit(_facadePath);
      final facade = _class(facadeUnit, 'P2PServiceImpl', path: _facadePath);
      expect(
        facade.implementsClause?.interfaces
            .map((type) => _compact(type.toSource()))
            .toList(growable: false),
        _implements,
      );
      final constructor = _constructor(facade, path: _facadePath);
      expect(
        constructor.parameters.parameters
            .map((parameter) => _compact(parameter.toSource()))
            .toList(growable: false),
        _constructorParameters,
      );
      expect(constructor.parameters.parameters, hasLength(22));
      expect(
        _fieldNames(facade).where((name) => !name.startsWith('_')).toSet(),
        _publicFields,
      );
      expect(
        _methodNames(facade).where((name) => !name.startsWith('_')).toSet(),
        _publicMethods,
      );
      final fingerprint = _publicApiFingerprint(facade);
      expect(
        fingerprint,
        _expectedFacadeApiFingerprint,
        reason: 'P2PServiceImpl public/static API fingerprint: $fingerprint',
      );
      _expectCallbackOwnership(facade, facadeSource);

      final creations = _productionCreations();
      expect(creations, hasLength(1));
      expect(
        File(creations.single.path).absolute.path,
        File(_bootstrapPath).absolute.path,
      );

      final rootSource = _compact(
        File(_applicationRootPath).readAsStringSync(),
      );
      for (final token in const <String>[
        'final P2PServiceImpl p2pService;',
        'required this.p2pService',
        'SetPresenceUseCase(presenceSetter: widget.p2pService)',
        'probe: widget.p2pService',
        'onDropReWarm: widget.p2pService.warmPeer',
        'onDropDrain: widget.p2pService.drainOfflineInbox',
        'onLivenessChanged: widget.p2pService.setPeerDropSuspected',
        'widget.p2pService.startEarlyLocalDiscovery()',
      ]) {
        expect(
          rootSource,
          contains(token),
          reason: 'ApplicationRoot concrete capability wiring: $token',
        );
      }
    },
  );

  test(
    'TC-295-07 clears callbacks and preserves coordinator/application teardown order',
    () {
      final facade = _class(
        _unit(_facadePath),
        'P2PServiceImpl',
        path: _facadePath,
      );
      final disposeBody = _compact(_method(facade, 'dispose').body.toSource());
      final ordered = <String>[
        '_localMessageSub?.cancel()',
        '_localPeersSub?.cancel()',
        '_localMediaSub?.cancel()',
        '_transportDiagnosticSub?.cancel()',
        '_networkChangeSub?.cancel()',
        '_peerTransportCoordinator.dispose()',
        '_stateController.close()',
        '_messageController.close()',
        '_incomingLocalMediaController.close()',
        ..._callbackSlots.map((slot) => '_bridge.$slot = null'),
      ];
      var previous = -1;
      for (final token in ordered) {
        final index = disposeBody.indexOf(token);
        expect(index, greaterThan(previous), reason: 'teardown order: $token');
        previous = index;
      }
      expect(disposeBody, isNot(contains('_lanPermProbeTimer')));

      final appState = _class(
        _unit(_applicationRootPath),
        '_MyAppState',
        path: _applicationRootPath,
      );
      final appDispose = _compact(_method(appState, 'dispose').body.toSource());
      final p2pDispose = appDispose.indexOf('widget.p2pService.dispose()');
      final bridgeDispose = appDispose.indexOf('widget.bridge.dispose()');
      expect(p2pDispose, greaterThan(-1));
      expect(
        bridgeDispose,
        greaterThan(p2pDispose),
        reason: 'ApplicationRoot must dispose P2P before Bridge',
      );
    },
  );

  test(
    'TC-295-08 registers the ownership contract in every affected lane without exception drift',
    () {
      final curated = File('scripts/run_test_gates.sh').readAsStringSync();
      final host = File('scripts/run_host_test_gates.sh').readAsStringSync();
      for (final entry in <({String source, String array})>[
        (source: curated, array: 'ONE_TO_ONE_TESTS'),
        (source: curated, array: 'TRANSPORT_TESTS'),
        (source: host, array: 'ONE_TO_ONE_HOST_TESTS'),
      ]) {
        expect(
          RegExp(
            RegExp.escape('"$_contractPath"'),
          ).allMatches(_arrayBody(entry.source, entry.array)),
          hasLength(1),
          reason: '$_contractPath must occur once in ${entry.array}',
        );
      }
      expect(host, contains("rg --files test/core -g '*_test.dart'"));

      final facadeUnit = _unit(_facadePath);
      expect(
        facadeUnit.directives
            .whereType<PartDirective>()
            .map((directive) => directive.uri.stringValue)
            .whereType<String>()
            .toSet(),
        <String>{
          'p2p_impl/p2p_inbox_coordinator.dart',
          'p2p_impl/p2p_peer_transport_coordinator.dart',
        },
      );

      final components = File('C4/components.md').readAsStringSync();
      for (final token in const <String>[
        'P2PService / P2PServiceImpl | Stable Service Facade',
        'raw Bridge callback registration/clearing',
        'node lifecycle',
        'readiness/health/recovery',
        'state projection',
        'final disposal',
        '_P2PInboxCoordinator | Private Component | Durable inbox custody/replay',
        '_P2PPeerTransportCoordinator | Private Component | Peer/LAN policy',
      ]) {
        expect(components, contains(token), reason: 'C4 owner token: $token');
      }
      final structure = File('C4/file-structure.md').readAsStringSync();
      for (final token in const <String>[
        'Stable P2PServiceImpl facade: raw Bridge callbacks, '
            'lifecycle/readiness/recovery, state projection, disposal',
        'p2p_impl/',
        'p2p_inbox_coordinator.dart',
        'Private durable inbox custody/replay coordinator',
        'p2p_peer_transport_coordinator.dart',
        'Private peer/LAN policy coordinator',
      ]) {
        expect(structure, contains(token), reason: 'C4 file token: $token');
      }

      final manifestSource = File(_exceptionsPath).readAsStringSync();
      final manifest = jsonDecode(manifestSource) as Map<String, dynamic>;
      final dependencies = manifest['dependencyExceptions'] as List<dynamic>;
      expect(dependencies, hasLength(165));
      expect(manifest['placementExceptions'] as List<dynamic>, isEmpty);
      final p2pExceptions = dependencies
          .cast<Map<String, dynamic>>()
          .where((entry) => entry['source'] == _facadePath)
          .toList(growable: false);
      expect(p2pExceptions, hasLength(8));
      expect(p2pExceptions.map((entry) => entry['target']).toSet(), <String>{
        'lib/features/account_migration/application/'
            'account_migration_runtime_network_gate.dart',
        'lib/features/p2p/domain/models/node_state.dart',
        'lib/features/p2p/domain/models/chat_message.dart',
        'lib/features/p2p/domain/models/discovered_peer.dart',
        'lib/features/p2p/domain/models/send_message_result.dart',
        'lib/features/p2p/domain/models/connection_state.dart',
        'lib/features/push/domain/push_token_store.dart',
        'lib/features/push/domain/received_wake_token_store.dart',
      });
      for (final entry in p2pExceptions) {
        expect(entry['rule'], 'core-must-not-depend-on-feature');
        expect(entry['directiveKind'], 'import');
        expect(entry['owner'], 'DTR-18');
        expect(entry['count'], 1);
      }
      for (final forbidden in const <String>[
        'DTR-17',
        'Plan 295',
        _contractPath,
        _inboxPartPath,
        _peerPartPath,
      ]) {
        expect(manifestSource, isNot(contains(forbidden)));
      }
    },
  );
}
