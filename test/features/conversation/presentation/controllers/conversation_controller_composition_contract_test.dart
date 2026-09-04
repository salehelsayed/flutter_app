import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _directWiredPath =
    'lib/features/conversation/presentation/screens/conversation_wired.dart';
const _groupWiredPath =
    'lib/features/groups/presentation/screens/group_conversation_wired.dart';

const _controllerFiles = <String, String>{
  'ConversationComposerController':
      'lib/shared/widgets/conversation/'
      'conversation_composer_controller.dart',
  'ConversationUploadActivityController':
      'lib/shared/widgets/conversation/'
      'conversation_upload_activity_controller.dart',
  'ConversationVoiceCaptureController':
      'lib/shared/widgets/conversation/'
      'conversation_voice_capture_controller.dart',
  'ConversationReactionProjectionController':
      'lib/shared/widgets/conversation/'
      'conversation_reaction_projection_controller.dart',
};

const _controllerFields = <String, String>{
  '_composerController': 'ConversationComposerController',
  '_uploadActivityController': 'ConversationUploadActivityController',
  '_voiceCaptureController': 'ConversationVoiceCaptureController',
  '_reactionProjectionController': 'ConversationReactionProjectionController',
};

const _controllerTestPaths = <String>[
  'test/features/conversation/presentation/controllers/'
      'conversation_controller_composition_contract_test.dart',
  'test/features/conversation/presentation/controllers/'
      'conversation_composer_controller_test.dart',
  'test/features/conversation/presentation/controllers/'
      'conversation_upload_activity_controller_test.dart',
  'test/features/conversation/presentation/controllers/'
      'conversation_voice_capture_controller_test.dart',
  'test/features/conversation/presentation/controllers/'
      'conversation_reaction_projection_controller_test.dart',
];

// These are token/AST fingerprints of the public widget declarations and the
// non-DTR-15 parts of their pure-screen handoffs. The six sanctioned owner
// expressions are canonicalized separately, so TC-294-09 is GREEN on HEAD and
// remains GREEN when TC-294-01 transfers those expressions to controllers.
// 360: repinned for exactly one added optional widget field on
// `ConversationWired` — `directDeviceTrust`, the linked-device trust capability
// handed to the contact profile this screen opens from its header avatar. No
// handoff expression, controller, or pure-screen boundary changed.
// 361: repinned for exactly two added optional widget fields on
// `ConversationWired` — `modalityGate` (the injectable linked blob-free
// composer policy, defaulting to the incumbent allow-everything gate) and
// `directEventFanout` (the target-batch authoring owner; null keeps the
// incumbent single-target senders), plus the optional `directEventFanout`
// parameter on the five send/edit/delete/reaction Fn typedefs. No handoff
// expression, controller, or pure-screen boundary changed.
// 362: repinned for exactly three added optional widget fields on
// `ConversationWired`: `directLinkedMediaFanoutSelector` plus the incumbent
// blob-custody and blob-free-event flag values. Production still receives each
// const default; the injectable values make the default-build admission and
// composer-to-retry host proofs causal without a second production route.
// No controller owner or pure-screen handoff changed.
// 365: repinned for exactly one added optional widget field on
// `GroupConversationWired` — `preparedGroupMediaBlobCustodyCoordinator`, the
// initialized-authority media/voice producer seam. No controller owner or
// pure-screen handoff changed.
// 366: repinned for exactly one added defaulted widget field on
// `ConversationWired` — `sendPrivateMediaFanoutChatMessageFn`, the separately
// typed private-fanout Barrier-B dispatch seam. It defaults to the incumbent
// sender and changes no controller owner or pure-screen handoff.
// VC2-03: repinned for exactly one optional `ConversationWired` field,
// `outgoingCallCapability`. It delegates to the process-owned call composition
// and cannot manufacture availability when the capability is absent.
const _expectedDirectApiFingerprint = '6370e861';
const _expectedGroupApiFingerprint = '3ffab64f';
// 301: the direct handoff gained the reviewed `protectionCoordinator`
// pass-through (the Session-05-qualified shared screenshot-protection
// coordinator for protected thumbnail bubbles).
// 360: the `onAvatarTap` closure now forwards the linked-device trust
// capability to `ContactProfileScreen.open`, which requires a non-null
// capability. Nothing else in the handoff changed and no owner moved.
// VC2-03: the direct handoff adds only `onCall`, `showCallAction`, and
// `callActionEnabled`, all projected from the optional process-owned call
// capability. The reviewed per-contact availability and duplicate-start guards
// are part of those expressions; ConversationScreen remains presentation-only.
const _expectedDirectHandoffFingerprint = 'ffd1f021';
const _expectedGroupHandoffFingerprint = '74b2fe80';

String _compact(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isFlutterStateType(String? source) =>
    source != null &&
    RegExp(r'^(?:[A-Za-z0-9_]+\.)?State(?:<|$)').hasMatch(_compact(source));

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

String _fieldDeclaration(ClassDeclaration declaration, String variableName) {
  final matches = declaration.members.whereType<FieldDeclaration>().where(
    (field) => field.fields.variables.any(
      (variable) => variable.name.lexeme == variableName,
    ),
  );
  expect(
    matches,
    hasLength(1),
    reason: '${declaration.name.lexeme} must own $variableName exactly once',
  );
  return _compact(matches.single.toSource());
}

final class _CreationCollector extends RecursiveAstVisitor<void> {
  final calls = <({String name, ArgumentList arguments})>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    calls.add((
      name: _compact(node.constructorName.type.toSource()),
      arguments: node.argumentList,
    ));
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add((name: node.methodName.name, arguments: node.argumentList));
    super.visitMethodInvocation(node);
  }
}

Map<String, String> _screenHandoff(ClassDeclaration state, String screenType) {
  final collector = _CreationCollector();
  _method(state, 'build').accept(collector);
  final creation = collector.calls.singleWhere(
    (candidate) => candidate.name == screenType,
    orElse: () => throw TestFailure(
      '${state.name.lexeme}.build does not construct $screenType; found '
      '${collector.calls.map((candidate) => candidate.name).toList()}',
    ),
  );
  return <String, String>{
    for (final argument
        in creation.arguments.arguments.whereType<NamedExpression>())
      argument.name.label.name: _compact(argument.expression.toSource()),
  };
}

String _fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in input.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _publicApiFingerprint(ClassDeclaration declaration) {
  final parts = <String>[
    'class=${declaration.name.lexeme}',
    'extends=${_compact(declaration.extendsClause?.superclass.toSource() ?? '')}',
  ];
  for (final member in declaration.members) {
    switch (member) {
      case FieldDeclaration():
        final publicVariables = member.fields.variables.where(
          (variable) => !variable.name.lexeme.startsWith('_'),
        );
        if (publicVariables.isNotEmpty) {
          parts.add(_compact(member.toSource()));
        }
      case ConstructorDeclaration():
        if (member.name == null) parts.add(_compact(member.toSource()));
      case MethodDeclaration():
        if (member.name.lexeme == 'createState') {
          parts.add(_compact(member.toSource()));
        }
    }
  }
  return _fnv1a32(parts.join('\n'));
}

String _handoffFingerprint(Map<String, String> handoff) {
  const transferredOwners = <String>{
    'composerStateListenable',
    'uploadProgress',
    'messageUploadProgress',
    'recordingState',
    'reactions',
    'onCancelUpload',
  };
  final parts = <String>[
    for (final entry in handoff.entries)
      '${entry.key}=${transferredOwners.contains(entry.key) ? '<DTR-15-owner>' : entry.value}',
  ];
  return _fnv1a32(parts.join('\n'));
}

void _expectDirectStateHierarchy(
  ClassDeclaration declaration,
  String widgetType,
) {
  expect(
    _compact(declaration.extendsClause?.superclass.toSource() ?? ''),
    'State<$widgetType>',
  );
  expect(
    declaration.withClause?.mixinTypes
        .map((type) => _compact(type.toSource()))
        .toList(growable: false),
    <String>['WidgetsBindingObserver'],
  );
  expect(declaration.implementsClause, isNull);
}

void _expectControllerImports(
  CompilationUnit unit, {
  required String wiredPath,
}) {
  final imports = unit.directives
      .whereType<ImportDirective>()
      .map((directive) => directive.uri.stringValue)
      .whereType<String>()
      .toList(growable: false);
  for (final controllerPath in _controllerFiles.values) {
    final packageImport = 'package:flutter_app/${controllerPath.substring(4)}';
    expect(
      imports.where((uri) => uri == packageImport),
      hasLength(1),
      reason: '$wiredPath must import $packageImport exactly once',
    );
  }
}

void _expectPlainController(String className, String path, String source) {
  final unit = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  ).unit;
  final declaration = _class(unit, className, path: path);
  final forbiddenIdentifiers = RegExp(
    r'\b(BuildContext|ConversationWired|GroupConversationWired|'
    r'ConversationMessage|GroupMessage)\b',
  );
  expect(
    forbiddenIdentifiers.hasMatch(source),
    isFalse,
    reason: '$className must be presentation-mechanic and lane-model free',
  );
  expect(
    _compact(declaration.extendsClause?.superclass.toSource() ?? ''),
    'ChangeNotifier',
    reason: '$className must be a compositional notifier, not a State base',
  );
  for (final classDeclaration
      in unit.declarations.whereType<ClassDeclaration>()) {
    expect(
      _isFlutterStateType(
        classDeclaration.extendsClause?.superclass.toSource(),
      ),
      isFalse,
      reason: '$path must not hide shared Flutter State ownership',
    );
    expect(
      classDeclaration.implementsClause?.interfaces
              .map((type) => type.toSource())
              .where(_isFlutterStateType) ??
          const <String>[],
      isEmpty,
      reason: '$path must not hide shared Flutter State ownership',
    );
  }
  for (final import in unit.directives.whereType<ImportDirective>()) {
    final uri = import.uri.stringValue ?? '';
    expect(uri, isNot(contains('conversation_wired.dart')));
    expect(uri, isNot(contains('group_conversation_wired.dart')));
  }
  expect(
    RegExp(r'\bif\s*\(\s*isGroup\b').hasMatch(source),
    isFalse,
    reason: '$className must not select a lane at runtime',
  );
}

void _expectTransferredFields(ClassDeclaration state, String source) {
  final fields = _fieldNames(state);
  for (final entry in _controllerFields.entries) {
    expect(fields, contains(entry.key));
    final type = RegExp.escape(entry.value);
    final field = RegExp.escape(entry.key);
    expect(
      _fieldDeclaration(state, entry.key),
      matches(
        RegExp(
          '^(?:(?:late )?final $type(?:<[^;=]+>)? $field(?:;| =)|'
          'final $field = $type(?:<[^;=]+>)?\\()',
        ),
      ),
      reason:
          '${state.name.lexeme}.${entry.key} must be an immutable '
          '${entry.value} owner',
    );
  }

  const movedStateFields = <String>{
    '_pendingAttachments',
    '_composerState',
    '_durationSub',
    '_amplitudeSub',
    '_amplitudeBuffer',
    '_waveformSamples',
    '_pendingRecorderAbort',
    '_reactions',
    '_mediaUploadProgressSubscription',
    '_isTrackingRelayUpload',
    '_trackedUploadTotalBytes',
    '_trackedUploadCompletedBytes',
    '_trackedCurrentUploadBytes',
    '_trackedCurrentUploadId',
    '_messageUploadProgress',
    '_activeAttachmentUpload',
  };
  expect(
    fields.intersection(movedStateFields),
    isEmpty,
    reason:
        '${state.name.lexeme} retained mutable state assigned to a DTR-15 '
        'controller',
  );

  const movedOwnerTypes = <String>[
    'ValueNotifier<ConversationComposerViewState>',
    'List<PendingComposerMedia>',
    'StreamSubscription<Duration>',
    'StreamSubscription<double>',
    'AmplitudeBuffer',
    'Map<String, List<MessageReaction>>',
    'StreamSubscription<Map<String, dynamic>>',
    'Map<String, MessageUploadProgressViewState>',
    '_ActiveAttachmentUpload',
    '_GroupActiveAttachmentUpload',
  ];
  for (final field in state.members.whereType<FieldDeclaration>()) {
    final fieldSource = _compact(field.toSource());
    for (final movedType in movedOwnerTypes) {
      expect(
        fieldSource,
        isNot(contains(movedType)),
        reason:
            '${state.name.lexeme} retained or renamed a $movedType owner: '
            '$fieldSource',
      );
    }
  }

  expect(source, isNot(contains('durationStream.listen(')));
  expect(source, isNot(contains('amplitudeStream.listen(')));
  expect(source, isNot(contains('mediaUploadProgressStream.listen(')));
  expect(
    RegExp(r'\.onAutoStopped\s*=(?!=)').hasMatch(source),
    isFalse,
    reason: '${state.name.lexeme} must not assign the recorder callback',
  );
}

void _expectExactHandoff(Map<String, String> handoff, {required String owner}) {
  const expected = <String, String>{
    'composerStateListenable': '_composerController',
    'uploadProgress': '_uploadActivityController.aggregateProgress',
    'messageUploadProgress': '_uploadActivityController.messageProgress',
    'recordingState': '_composerController.value.recordingState',
    'reactions': '_reactionProjectionController.reactions',
  };
  for (final entry in expected.entries) {
    expect(
      handoff[entry.key],
      entry.value,
      reason: '$owner must delegate ${entry.key} to ${entry.value}',
    );
  }
  expect(
    handoff['onCancelUpload'],
    contains('_uploadActivityController'),
    reason: '$owner cancellation availability must follow the upload owner',
  );
}

String _singleControllerListener(
  String source,
  String controller, {
  required String operation,
}) {
  final expression = RegExp(
    '${RegExp.escape(controller)}\\.$operation\\((_[A-Za-z0-9]+)\\)',
  );
  final matches = expression.allMatches(_compact(source)).toList();
  expect(
    matches,
    hasLength(1),
    reason: '$controller.$operation must be wired exactly once',
  );
  return matches.single.group(1)!;
}

void _expectPairedParentInvalidation(String source, String owner) {
  final uploadAdd = _singleControllerListener(
    source,
    '_uploadActivityController',
    operation: 'addListener',
  );
  final reactionAdd = _singleControllerListener(
    source,
    '_reactionProjectionController',
    operation: 'addListener',
  );
  expect(
    reactionAdd,
    uploadAdd,
    reason: '$owner upload and reaction must share one parent invalidator',
  );
  expect(
    _singleControllerListener(
      source,
      '_uploadActivityController',
      operation: 'removeListener',
    ),
    uploadAdd,
  );
  expect(
    _singleControllerListener(
      source,
      '_reactionProjectionController',
      operation: 'removeListener',
    ),
    uploadAdd,
  );
  expect(source, isNot(contains('_composerController.addListener(')));
}

void _expectVoiceComposerBridge(
  ClassDeclaration state,
  String source, {
  required String owner,
}) {
  final listener = _singleControllerListener(
    source,
    '_voiceCaptureController',
    operation: 'addListener',
  );
  expect(
    _singleControllerListener(
      source,
      '_voiceCaptureController',
      operation: 'removeListener',
    ),
    listener,
  );
  final body = _compact(_method(state, listener).body.toSource());
  expect(
    body,
    contains('_voiceCaptureController.state'),
    reason: '$owner voice bridge must consume controller state',
  );
  expect(
    body,
    contains('_updateComposerState('),
    reason: '$owner voice bridge must publish through the composer seam',
  );
  expect(
    body,
    isNot(contains('setState(')),
    reason: '$owner voice ticks must not invalidate the Wired root',
  );
}

void _expectControllerDelegation(String source, {required String owner}) {
  final compactSource = _compact(source);
  expect(
    '_uploadActivityController.bindProgressStream(mediaUploadProgressStream)'
        .allMatches(compactSource),
    hasLength(1),
    reason: '$owner must bind its upload event source exactly once',
  );
  for (final delegation in const <String>[
    '_composerController.publish(',
    '_composerController.snapshot(',
    '_uploadActivityController.beginOperation(',
    '_uploadActivityController.requestCancelActive(',
    '_voiceCaptureController.start(',
    '_voiceCaptureController.stop(',
    '_voiceCaptureController.cancel(',
    '_reactionProjectionController.applyChange(',
    '_reactionProjectionController.replaceAll(',
  ]) {
    expect(
      compactSource,
      contains(delegation),
      reason: '$owner must delegate through $delegation',
    );
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

void _expectExactRegistrations(String arrayBody, String arrayName) {
  for (final path in _controllerTestPaths) {
    expect(
      RegExp(RegExp.escape('"$path"')).allMatches(arrayBody),
      hasLength(1),
      reason: '$path must occur exactly once in $arrayName',
    );
  }
}

void main() {
  test('DTR-15 transfers exact owners without a shared State hierarchy', () {
    final missingControllers = _controllerFiles.values
        .where((path) => !File(path).existsSync())
        .toList(growable: false);
    expect(
      missingControllers,
      isEmpty,
      reason:
          'DTR-15 RED: the shared compositional controller files must exist '
          'before ownership and adapter wiring can be verified: '
          '$missingControllers',
    );

    final controllerSources = <String, String>{
      for (final entry in _controllerFiles.entries)
        entry.key: File(entry.value).readAsStringSync(),
    };
    for (final entry in _controllerFiles.entries) {
      _expectPlainController(
        entry.key,
        entry.value,
        controllerSources[entry.key]!,
      );
    }

    final directSource = File(_directWiredPath).readAsStringSync();
    final groupSource = File(_groupWiredPath).readAsStringSync();
    final directUnit = _unit(_directWiredPath);
    final groupUnit = _unit(_groupWiredPath);
    final directState = _class(
      directUnit,
      '_ConversationWiredState',
      path: _directWiredPath,
    );
    final groupState = _class(
      groupUnit,
      '_GroupConversationWiredState',
      path: _groupWiredPath,
    );

    _expectDirectStateHierarchy(directState, 'ConversationWired');
    _expectDirectStateHierarchy(groupState, 'GroupConversationWired');
    _expectControllerImports(directUnit, wiredPath: _directWiredPath);
    _expectControllerImports(groupUnit, wiredPath: _groupWiredPath);
    _expectTransferredFields(directState, directSource);
    _expectTransferredFields(groupState, groupSource);
    expect(
      _fieldNames(groupState),
      contains('_allowPopDuringActiveUpload'),
      reason:
          'the group-only route/dialog pop override stays in its lane '
          'adapter, outside shared upload mechanics',
    );
    _expectExactHandoff(
      _screenHandoff(directState, 'ConversationScreen'),
      owner: '_ConversationWiredState',
    );
    _expectExactHandoff(
      _screenHandoff(groupState, 'GroupConversationScreen'),
      owner: '_GroupConversationWiredState',
    );
    _expectPairedParentInvalidation(directSource, '_ConversationWiredState');
    _expectPairedParentInvalidation(
      groupSource,
      '_GroupConversationWiredState',
    );
    _expectVoiceComposerBridge(
      directState,
      directSource,
      owner: '_ConversationWiredState',
    );
    _expectVoiceComposerBridge(
      groupState,
      groupSource,
      owner: '_GroupConversationWiredState',
    );
    _expectControllerDelegation(directSource, owner: '_ConversationWiredState');
    _expectControllerDelegation(
      groupSource,
      owner: '_GroupConversationWiredState',
    );

    for (final entry in _controllerFields.entries) {
      final disposeBody = _method(directState, 'dispose').body.toSource();
      expect(
        '${entry.key}.dispose()'.allMatches(_compact(disposeBody)),
        hasLength(1),
      );
      final groupDisposeBody = _method(groupState, 'dispose').body.toSource();
      expect(
        '${entry.key}.dispose()'.allMatches(_compact(groupDisposeBody)),
        hasLength(1),
      );
      if (entry.key == '_composerController') continue;
      expect(
        _method(groupState, '_resetForGroupChange').body.toSource(),
        contains(entry.key),
        reason: '${entry.key} must participate in group retargeting',
      );
    }
    final groupReset = _compact(
      _method(groupState, '_resetForGroupChange').body.toSource(),
    );
    expect(groupReset, contains('_updateComposerState('));
    expect(
      _compact(_method(groupState, '_updateComposerState').body.toSource()),
      contains('_composerController.publish('),
      reason:
          'group retargeting must scrub the composer through its exact '
          'controller-owned publication bridge',
    );
    expect(
      groupReset,
      contains('_uploadActivityController.rebind('),
      reason: 'group retargeting must advance the upload scope',
    );
    expect(
      groupReset,
      contains('_voiceCaptureController.invalidateSessionScope('),
      reason: 'group retargeting must invalidate the old recorder session',
    );
    expect(
      groupReset,
      contains('_reactionProjectionController.clear('),
      reason: 'group retargeting must clear the old reaction projection',
    );

    expect(directSource, isNot(contains('class _ActiveAttachmentUpload')));
    expect(groupSource, isNot(contains('class _GroupActiveAttachmentUpload')));

    final composerSource = controllerSources['ConversationComposerController']!;
    final uploadSource =
        controllerSources['ConversationUploadActivityController']!;
    final voiceSource =
        controllerSources['ConversationVoiceCaptureController']!;
    final reactionSource =
        controllerSources['ConversationReactionProjectionController']!;
    for (final token in const <String>[
      'implements ValueListenable<ConversationComposerViewState>',
      'ConversationComposerSnapshot',
      'pendingAttachments',
      'pendingAttachmentFiles',
      'publish(',
      'snapshot(',
      'restoreSnapshot(',
    ]) {
      expect(_compact(composerSource), contains(token));
    }
    for (final token in const <String>[
      'ConversationUploadOperation',
      'StreamSubscription<Map<String, dynamic>>',
      'UploadProgressViewState',
      'MessageUploadProgressViewState',
      'aggregateProgress',
      'messageProgress',
      'applyProgress(',
      'bindProgressStream(',
      'rebind(',
      'acquireWake',
      'releaseWake',
    ]) {
      expect(_compact(uploadSource), contains(token));
    }
    for (final token in const <String>[
      'class ConversationVoiceCaptureController',
      'ConversationVoiceCaptureViewState get state',
      'onAutoStopOutcome',
      'StreamSubscription<Duration>',
      'StreamSubscription<double>',
      'AmplitudeBuffer',
      'start({',
      'stop()',
      'cancel()',
      'invalidateSessionScope()',
    ]) {
      expect(_compact(voiceSource), contains(token));
    }
    for (final token in const <String>[
      'Map<String, List<MessageReaction>>',
      'reactionsFor(',
      'replaceAll(',
      'replaceForMessage(',
      'applyChange(',
      'clear(',
    ]) {
      expect(_compact(reactionSource), contains(token));
    }
  });

  test('TC-294-09 freezes public Wired APIs and screen handoffs', () {
    final directUnit = _unit(_directWiredPath);
    final groupUnit = _unit(_groupWiredPath);
    final directWidget = _class(
      directUnit,
      'ConversationWired',
      path: _directWiredPath,
    );
    final groupWidget = _class(
      groupUnit,
      'GroupConversationWired',
      path: _groupWiredPath,
    );
    final directState = _class(
      directUnit,
      '_ConversationWiredState',
      path: _directWiredPath,
    );
    final groupState = _class(
      groupUnit,
      '_GroupConversationWiredState',
      path: _groupWiredPath,
    );

    final directApi = _publicApiFingerprint(directWidget);
    final groupApi = _publicApiFingerprint(groupWidget);
    final directHandoff = _handoffFingerprint(
      _screenHandoff(directState, 'ConversationScreen'),
    );
    final groupHandoff = _handoffFingerprint(
      _screenHandoff(groupState, 'GroupConversationScreen'),
    );

    // Keep these diagnostics useful when an intentional public API migration
    // requires a separately reviewed baseline update.
    expect(
      directApi,
      _expectedDirectApiFingerprint,
      reason: 'ConversationWired public API fingerprint: $directApi',
    );
    expect(
      groupApi,
      _expectedGroupApiFingerprint,
      reason: 'GroupConversationWired public API fingerprint: $groupApi',
    );
    expect(
      directHandoff,
      _expectedDirectHandoffFingerprint,
      reason: 'ConversationScreen handoff fingerprint: $directHandoff',
    );
    expect(
      groupHandoff,
      _expectedGroupHandoffFingerprint,
      reason: 'GroupConversationScreen handoff fingerprint: $groupHandoff',
    );
  });

  test('TC-294-11 gives DTR-15 tests exact curated gate membership', () {
    final curatedSource = File('scripts/run_test_gates.sh').readAsStringSync();
    final hostSource = File(
      'scripts/run_host_test_gates.sh',
    ).readAsStringSync();
    _expectExactRegistrations(
      _arrayBody(curatedSource, 'ONE_TO_ONE_TESTS'),
      'ONE_TO_ONE_TESTS',
    );
    _expectExactRegistrations(
      _arrayBody(hostSource, 'ONE_TO_ONE_HOST_TESTS'),
      'ONE_TO_ONE_HOST_TESTS',
    );
    _expectExactRegistrations(
      _arrayBody(curatedSource, 'GROUP_TESTS'),
      'GROUP_TESTS',
    );
  });
}
