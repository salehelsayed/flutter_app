import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e.dart';
import 'package:flutter_app/core/debug/android_voice_message_e2e.dart';
import 'package:flutter_app/core/debug/connectivity_restore_e2e_contract.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/debug/group_reaction_e2e_probe.dart';
import 'package:flutter_app/core/debug/keepalive_drop_e2e.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/debug/wake_token_directionality_e2e.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/folded_introduction_response_use_case.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const _kConfigFile = 'intro_e2e_config.json';
const _kExportFile = 'intro_e2e_identity.json';
const _kResultFile = 'intro_e2e_result.json';

const bool directTextRelayTokenProofMode = bool.fromEnvironment(
  'MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF',
);
const String directTextRelayTokenProofCommandSchema =
    'mknoon.direct-text-relay-token-command.v1';
const String directTextRelayTokenProofCommandSchemaV2 =
    'mknoon.direct-text-relay-token-command.v2';
const String directTextRelayTokenProofReceiptSchema =
    'mknoon.direct-text-relay-token-receipt.v1';
const String directTextRelayTokenProofReceiptSchemaV2 =
    'mknoon.direct-text-relay-token-receipt.v2';
const String directTextRelayTokenProofCurrentTokenAuthorizationKind =
    'sdk_current_validate_only';
const int directTextRelayTokenProofMaxCommandBytes = 16 * 1024;

class DirectTextRelayTokenProofCommand {
  const DirectTextRelayTokenProofCommand({
    this.proofSchema = directTextRelayTokenProofCommandSchema,
    required this.commandId,
    required this.issuedAt,
    required this.maxAge,
    required this.tokenSha256,
    required this.authorizationGenerationId,
    required this.authorizationArtifactSha256,
    this.authorizationKind,
    required this.gateAArtifactSha256,
    required this.accountIdentitySha256,
    required this.transportIdentitySha256,
    required this.commandSha256,
  });

  final String proofSchema;
  final String commandId;
  final DateTime issuedAt;
  final Duration maxAge;
  final String tokenSha256;
  final String authorizationGenerationId;
  final String authorizationArtifactSha256;
  final String? authorizationKind;
  final String gateAArtifactSha256;
  final String accountIdentitySha256;
  final String transportIdentitySha256;
  final String commandSha256;
}

DirectTextRelayTokenProofCommand parseDirectTextRelayTokenProofCommand(
  List<int> rawBytes, {
  required DateTime now,
}) {
  if (rawBytes.isEmpty ||
      rawBytes.length > directTextRelayTokenProofMaxCommandBytes) {
    throw const FormatException(
      'direct-text token proof command size rejected',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException(
      'direct-text token proof command JSON rejected',
    );
  }
  if (decoded is! Map) {
    throw const FormatException(
      'direct-text token proof command is not an object',
    );
  }
  final command = decoded.cast<String, Object?>();
  const legacyKeys = <String>{
    'schema',
    'commandId',
    'issuedAt',
    'maxAgeSeconds',
    'tokenSha256',
    'tokenGenerationId',
    'refreshArtifactSha256',
    'gateAArtifactSha256',
    'accountIdentitySha256',
    'transportIdentitySha256',
  };
  final isCurrentTokenV2 =
      command['schema'] == directTextRelayTokenProofCommandSchemaV2;
  final expectedKeys = isCurrentTokenV2
      ? const <String>{
          'schema',
          'commandId',
          'issuedAt',
          'maxAgeSeconds',
          'tokenSha256',
          'authorizationKind',
          'authorizationArtifactSha256',
          'gateACommandGenerationId',
          'gateAArtifactSha256',
          'accountIdentitySha256',
          'transportIdentitySha256',
        }
      : legacyKeys;
  final commandId = command['commandId'];
  final issuedAtRaw = command['issuedAt'];
  final issuedAt = issuedAtRaw is String
      ? DateTime.tryParse(issuedAtRaw)
      : null;
  final maxAgeSeconds = command['maxAgeSeconds'];
  final tokenSha256 = command['tokenSha256'];
  final authorizationGenerationId = isCurrentTokenV2
      ? command['gateACommandGenerationId']
      : command['tokenGenerationId'];
  final authorizationArtifactSha256 = isCurrentTokenV2
      ? command['authorizationArtifactSha256']
      : command['refreshArtifactSha256'];
  final gateAArtifactSha256 = command['gateAArtifactSha256'];
  final accountIdentitySha256 = command['accountIdentitySha256'];
  final transportIdentitySha256 = command['transportIdentitySha256'];
  final hashPattern = RegExp(r'^[0-9a-f]{64}$');
  if (command.keys.toSet().length != expectedKeys.length ||
      !command.keys.toSet().containsAll(expectedKeys) ||
      (!isCurrentTokenV2 &&
          command['schema'] != directTextRelayTokenProofCommandSchema) ||
      commandId is! String ||
      !RegExp(
        r'^direct-text-relay-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      issuedAt == null ||
      !issuedAt.isUtc ||
      maxAgeSeconds is! int ||
      maxAgeSeconds < 30 ||
      maxAgeSeconds > 300 ||
      tokenSha256 is! String ||
      !hashPattern.hasMatch(tokenSha256) ||
      authorizationGenerationId is! String ||
      !(isCurrentTokenV2
          ? RegExp(
              r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
            ).hasMatch(authorizationGenerationId)
          : RegExp(
              r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
            ).hasMatch(authorizationGenerationId)) ||
      authorizationArtifactSha256 is! String ||
      !hashPattern.hasMatch(authorizationArtifactSha256) ||
      (isCurrentTokenV2 &&
          command['authorizationKind'] !=
              directTextRelayTokenProofCurrentTokenAuthorizationKind) ||
      gateAArtifactSha256 is! String ||
      !hashPattern.hasMatch(gateAArtifactSha256) ||
      accountIdentitySha256 is! String ||
      !hashPattern.hasMatch(accountIdentitySha256) ||
      transportIdentitySha256 is! String ||
      !hashPattern.hasMatch(transportIdentitySha256)) {
    throw const FormatException(
      'direct-text token proof command fields rejected',
    );
  }
  final age = now.toUtc().difference(issuedAt);
  if (age.isNegative || age > Duration(seconds: maxAgeSeconds)) {
    throw const FormatException('direct-text token proof command expired');
  }
  return DirectTextRelayTokenProofCommand(
    proofSchema: command['schema']! as String,
    commandId: commandId,
    issuedAt: issuedAt,
    maxAge: Duration(seconds: maxAgeSeconds),
    tokenSha256: tokenSha256,
    authorizationGenerationId: authorizationGenerationId,
    authorizationArtifactSha256: authorizationArtifactSha256,
    authorizationKind: command['authorizationKind'] as String?,
    gateAArtifactSha256: gateAArtifactSha256,
    accountIdentitySha256: accountIdentitySha256,
    transportIdentitySha256: transportIdentitySha256,
    commandSha256: sha256.convert(rawBytes).toString(),
  );
}

Future<Map<String, Object?>> evaluateDirectTextRelayTokenProof({
  required DirectTextRelayTokenProofCommand command,
  required Future<String?> Function() getToken,
  required DateTime now,
}) async {
  final age = now.toUtc().difference(command.issuedAt);
  if (age.isNegative || age > command.maxAge) {
    throw StateError('direct-text token proof command expired');
  }
  final token = (await getToken())?.trim() ?? '';
  if (token.isEmpty ||
      sha256.convert(utf8.encode(token)).toString() != command.tokenSha256) {
    throw StateError('direct-text token proof mismatch');
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'schema': command.proofSchema == directTextRelayTokenProofCommandSchemaV2
        ? directTextRelayTokenProofReceiptSchemaV2
        : directTextRelayTokenProofReceiptSchema,
    'status': 'completed',
    'completedAt': now.toUtc().toIso8601String(),
    'commandId': command.commandId,
    'commandSha256': command.commandSha256,
    'tokenSha256': command.tokenSha256,
    if (command.proofSchema == directTextRelayTokenProofCommandSchemaV2) ...{
      'authorizationKind': command.authorizationKind,
      'authorizationArtifactSha256': command.authorizationArtifactSha256,
      'gateACommandGenerationId': command.authorizationGenerationId,
    } else ...{
      'tokenGenerationId': command.authorizationGenerationId,
      'refreshArtifactSha256': command.authorizationArtifactSha256,
    },
    'gateAArtifactSha256': command.gateAArtifactSha256,
    'accountIdentitySha256': command.accountIdentitySha256,
    'transportIdentitySha256': command.transportIdentitySha256,
    'tokenSha256Matched': true,
    'commandDeleted': true,
    'containsSecrets': false,
  });
}

typedef OpenConversationForIntroE2EFn = Future<bool> Function(String peerId);
typedef ResolveWakeTokenForIntroE2EFn = Future<String?> Function(String peerId);

Timer? _introE2EPoller;
bool _introE2ERunInFlight = false;

Future<bool> runDirectTextRelayTokenProofIfPresent({
  Future<String?> Function()? getToken,
  DateTime Function()? now,
  Future<Directory> Function()? getDocumentsDirectory,
  bool? proofModeOverride,
}) async {
  if (!kDebugMode || !(proofModeOverride ?? directTextRelayTokenProofMode)) {
    return false;
  }
  final directory =
      await (getDocumentsDirectory ?? getApplicationDocumentsDirectory)();
  final commandFile = File('${directory.path}/$_kConfigFile');
  if (!await commandFile.exists()) return false;
  final resultFile = File('${directory.path}/$_kResultFile');
  final resultTemp = File('${resultFile.path}.tmp');
  if (await resultFile.exists() || await resultTemp.exists()) {
    throw StateError('stale direct-text token proof receipt exists');
  }
  final stat = await commandFile.stat();
  if (stat.type != FileSystemEntityType.file ||
      stat.size <= 0 ||
      stat.size > directTextRelayTokenProofMaxCommandBytes) {
    throw StateError('direct-text token proof command size rejected');
  }
  final rawBytes = await commandFile.readAsBytes();
  final clock = now ?? DateTime.now;
  final command = parseDirectTextRelayTokenProofCommand(
    rawBytes,
    now: clock().toUtc(),
  );

  Map<String, Object?> receipt;
  try {
    receipt = await evaluateDirectTextRelayTokenProof(
      command: command,
      getToken: getToken ?? FirebaseMessaging.instance.getToken,
      now: clock().toUtc(),
    );
  } on Object {
    receipt = <String, Object?>{
      'schema': command.proofSchema == directTextRelayTokenProofCommandSchemaV2
          ? directTextRelayTokenProofReceiptSchemaV2
          : directTextRelayTokenProofReceiptSchema,
      'status': 'failed',
      'completedAt': clock().toUtc().toIso8601String(),
      'commandId': command.commandId,
      'commandSha256': command.commandSha256,
      'tokenSha256': command.tokenSha256,
      if (command.proofSchema == directTextRelayTokenProofCommandSchemaV2) ...{
        'authorizationKind': command.authorizationKind,
        'authorizationArtifactSha256': command.authorizationArtifactSha256,
        'gateACommandGenerationId': command.authorizationGenerationId,
      } else ...{
        'tokenGenerationId': command.authorizationGenerationId,
        'refreshArtifactSha256': command.authorizationArtifactSha256,
      },
      'gateAArtifactSha256': command.gateAArtifactSha256,
      'accountIdentitySha256': command.accountIdentitySha256,
      'transportIdentitySha256': command.transportIdentitySha256,
      'reason': 'token_hash_mismatch_or_unavailable',
      'commandDeleted': true,
      'containsSecrets': false,
    };
  }

  await commandFile.delete();
  if (await commandFile.exists()) {
    throw StateError('direct-text token proof command survived');
  }
  await resultTemp.writeAsString(jsonEncode(receipt), flush: true);
  await resultTemp.rename(resultFile.path);
  if (!await resultFile.exists() || await resultTemp.exists()) {
    throw StateError('direct-text token proof receipt failed');
  }
  return true;
}

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
  ResolveWakeTokenForIntroE2EFn? resolveWakeToken,
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

    // Main-app device campaigns learn peer QR payloads only after both app
    // processes have launched. Make the existing `add_contacts` contract work
    // for those live configs as well as configs staged before startup. The add
    // use case is idempotent, so pre-populated simulator contacts remain safe.
    await prePopulateContactsFromIntroE2EConfig(contactRepo: contactRepo);

    if (config['send_contact_requests_for_added_contacts'] == true) {
      await _sendContactRequestsForAddedContacts(
        config: config,
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        contactRepo: contactRepo,
        resolveWakeToken: resolveWakeToken,
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

    Map<String, dynamic>? introDeliveryCustody;
    if (config['require_introducer_acceptance_custody'] == true) {
      final identity = await identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError(
          'Identity missing for intro E2E introducer-custody proof',
        );
      }
      final timeoutMs =
          ((config['introducer_acceptance_custody_timeout_ms'] as num?)
                      ?.toInt() ??
                  120000)
              .clamp(1000, 180000)
              .toInt();
      introDeliveryCustody = await awaitIntroducerAcceptanceCustodyForIntroE2E(
        introActionResult: introActionResult,
        ownPeerId: identity.peerId,
        introRepo: introRepo,
        p2pService: p2pService,
        timeout: Duration(milliseconds: timeoutMs),
      );
    }

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
        'introDeliveryCustody': introDeliveryCustody,
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

Future<void> _runConnectivityRestoreObservation({
  required Map<String, dynamic> config,
  required MessageRepository messageRepo,
}) async {
  final events = <String>[];
  var captureInstalled = false;
  String? runId;
  String? nonce;
  try {
    runId = _requiredConnectivityToken(config, 'runId', maxLength: 80);
    nonce = _requiredConnectivityToken(config, 'nonce', maxLength: 128);
    final contactPeerId = _requiredConnectivityToken(
      config,
      'contactPeerId',
      maxLength: 160,
    );
    if (config['schema'] != connectivityRestoreObserveRequestSchema ||
        config['transport_action'] != connectivityRestoreObserveAction ||
        config['scenario'] != connectivityRestoreScenarioId ||
        config['role'] != 'receiver' ||
        config['receiverNetwork'] != 'disconnected' ||
        config['appForeground'] != true ||
        config['stepId'] != 'connectivity-observe-$runId') {
      throw const FormatException('connectivity observation request rejected');
    }

    // Install the production flow sink before acknowledging the offline
    // window. The host does not restore Android connectivity until it sees the
    // nonce-bound `armed` result below.
    setE2EFlowEventSink((payload) {
      final event = payload['event'];
      if (event is String && event.isNotEmpty) events.add(event);
    });
    captureInstalled = true;
    await _writeIntroE2EResult(<String, dynamic>{
      'schema': connectivityRestoreObserveResultSchema,
      'stepId': config['stepId'],
      'status': 'armed',
      'success': true,
      'runId': runId,
      'nonce': nonce,
      'observedMessageCount': 0,
    });

    final expectedTexts = connectivityRestoreExpectedTexts(runId);
    final expectedSet = expectedTexts.toSet();
    final timeoutMs = ((config['timeoutMs'] as num?)?.toInt() ?? 120000)
        .clamp(1000, 180000)
        .toInt();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    var observedMessageCount = 0;
    while (DateTime.now().isBefore(deadline)) {
      final messages = await messageRepo.getMessagesForContact(contactPeerId);
      final matching = messages
          .where(
            (message) =>
                message.isIncoming &&
                !message.isDeleted &&
                !message.isHidden &&
                message.transport != 'system' &&
                expectedSet.contains(message.text),
          )
          .toList(growable: false);
      final byText = <String, List<ConversationMessage>>{};
      for (final message in matching) {
        byText
            .putIfAbsent(message.text, () => <ConversationMessage>[])
            .add(message);
      }
      if (byText.values.any((matches) => matches.length > 1)) {
        throw StateError('duplicate run-bound connectivity message observed');
      }
      final ids = matching.map((message) => message.id).toSet();
      observedMessageCount = byText.length;
      const requiredEvents = <String>{
        'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
        'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
        'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
      };
      final eventSet = events.toSet();
      if (byText.length == 3 &&
          ids.length == 3 &&
          requiredEvents.difference(eventSet).isEmpty) {
        final drainStart = events.indexOf(
          'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
        );
        if (events.indexOf('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS') <=
                drainStart ||
            events.indexOf('P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM') <=
                drainStart) {
          throw StateError('connectivity restore events are out of order');
        }
        await _writeIntroE2EResult(<String, dynamic>{
          'schema': connectivityRestoreObserveResultSchema,
          'stepId': config['stepId'],
          'status': 'complete',
          'success': true,
          'runId': runId,
          'nonce': nonce,
          'observedMessageCount': 3,
          'events': List<String>.unmodifiable(events),
          'resumeEventsDuringWindow': events
              .where((event) => event.startsWith('APP_LIFECYCLE_RESUME_'))
              .length,
        });
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError(
      'connectivity observation timed out at $observedMessageCount messages',
    );
  } catch (error) {
    final failure = <String, dynamic>{
      'schema': connectivityRestoreObserveResultSchema,
      'stepId': config['stepId'],
      'status': 'failed',
      'success': false,
      'errorType': error.runtimeType.toString(),
    };
    if (runId != null) failure['runId'] = runId;
    if (nonce != null) failure['nonce'] = nonce;
    await _writeIntroE2EResult(failure);
  } finally {
    if (captureInstalled) setE2EFlowEventSink(null);
    await _deleteConfigIfPresent();
  }
}

String _requiredConnectivityToken(
  Map<String, dynamic> config,
  String key, {
  required int maxLength,
}) {
  final value = config[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw FormatException('connectivity request has invalid $key');
  }
  return value;
}

Future<void> _writeIntroE2EResult(Map<String, dynamic> value) async {
  final file = await _resultFile();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  if (await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

Future<void> _runGroupReactionE2EProbe({
  required Map<String, dynamic> config,
  required Database database,
  required SecureKeyStore secureKeyStore,
}) async {
  try {
    final result = await runGroupReactionE2EProbeAction(
      database: database,
      secureKeyStore: secureKeyStore,
      config: config.cast<String, Object?>(),
    );
    await _writeIntroE2EResult(Map<String, dynamic>.from(result));
  } catch (error) {
    String boundToken(String key, String fallback) {
      final value = config[key];
      return value is String &&
              value.isNotEmpty &&
              value.length <= 180 &&
              RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)
          ? value
          : fallback;
    }

    await _writeIntroE2EResult(<String, dynamic>{
      'schema': groupReactionE2EProbeResultSchema,
      'transport_action': boundToken('transport_action', 'invalid-action'),
      'scenario': boundToken('scenario', 'invalid-scenario'),
      'stepId': boundToken('stepId', 'invalid-step'),
      'runId': boundToken('runId', 'invalid-run'),
      'nonce': boundToken('nonce', 'invalid-nonce'),
      'status': 'failed',
      'success': false,
      'errorType': error.runtimeType.toString(),
    });
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
  required PushEnvelopeStagingStore pushEnvelopeStagingStore,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required Database groupReactionProbeDatabase,
  required SecureKeyStore groupReactionProbeSecureKeyStore,
  required WakeTokenStore wakeTokenStore,
  required ReceivedWakeTokenStore receivedWakeTokenStore,
  required RegisterWakeTokensForE2E registerWakeTokens,
  required DetailedInboxStore detailedInboxStore,
  required WakeTokenAcceptedAttachmentObserver wakeTokenAttachmentObserver,
  PrivateMediaOutboxE2EController? privateMediaOutboxE2EController,
  ResolveWakeTokenForIntroE2EFn? resolveWakeToken,
  OpenConversationForIntroE2EFn? openConversationByPeerId,
  Duration initialDelay = const Duration(seconds: 2),
  Duration pollInterval = const Duration(seconds: 3),
}) {
  if (!kDebugMode || (!kE2ETestMode && !directTextRelayTokenProofMode)) {
    return;
  }
  if (_introE2EPoller != null) return;

  Future<void> tick() async {
    if (_introE2ERunInFlight) return;
    _introE2ERunInFlight = true;
    try {
      if (directTextRelayTokenProofMode) {
        await runDirectTextRelayTokenProofIfPresent();
        return;
      }
      final config = await _loadConfig();
      if (config == null) return;

      // This action must execute before runIntroE2EActions: the generic path
      // performs a health check and an inbox drain, which would invalidate a
      // proof that Android's network-change callback caused the drain.
      if (config['transport_action'] == connectivityRestoreObserveAction) {
        await _runConnectivityRestoreObservation(
          config: config,
          messageRepo: messageRepo,
        );
        return;
      }

      // This production-conversation action must also run before the generic
      // health-check/inbox-drain preamble. Its sender endpoint captures the
      // genuine offline upload and the restored-edge retry; a generic drain or
      // health check would erase that causal boundary.
      if (config['transport_action'] == privateMediaOutboxE2EAction) {
        // Consume this request before publishing progress or a terminal
        // receipt. A host may stage the next phase as soon as it observes
        // completion, so terminal cleanup could otherwise delete that phase.
        await _deleteConfigIfPresent();
        try {
          requirePrivateMediaOutboxE2EBuildProfile();
          final controller = privateMediaOutboxE2EController;
          if (controller == null) {
            throw StateError('private-media outbox controller is not wired');
          }
          final request = PrivateMediaOutboxE2ERequest.fromConfig(config);
          await ensurePrivateMediaOutboxE2EEndpoint(
            controller: controller,
            request: request,
            openConversationByPeerId: openConversationByPeerId,
          );
          final result = await controller.run(
            request,
            (progress) =>
                _writeIntroE2EResult(Map<String, dynamic>.from(progress)),
            _waitForPrivateMediaOutboxE2EHostRelease,
          );
          await _writeIntroE2EResult(Map<String, dynamic>.from(result));
        } catch (error) {
          await _writeIntroE2EResult(
            Map<String, dynamic>.from(
              privateMediaOutboxE2EFailureReceipt(config: config, error: error),
            ),
          );
        }
        return;
      }

      if (isGroupReactionE2EProbeAction(config['transport_action'])) {
        await _runGroupReactionE2EProbe(
          config: config,
          database: groupReactionProbeDatabase,
          secureKeyStore: groupReactionProbeSecureKeyStore,
        );
        return;
      }

      // The Android notification campaign owns relay custody, production FCM
      // staging, and the offline tap window. It must arm its observers before
      // the host sends or taps, and must not fall through the generic health
      // check/inbox drain that would destroy those causal boundaries.
      if (isAndroidNotificationPayloadE2EAction(config['transport_action'])) {
        try {
          final result = await runAndroidNotificationPayloadE2EAction(
            config: config,
            p2pService: p2pService,
            bridge: bridge,
            messageRepo: messageRepo,
            pushEnvelopeStagingStore: pushEnvelopeStagingStore,
            writeProgress: (progress) =>
                _writeIntroE2EResult(Map<String, dynamic>.from(progress)),
          );
          await _writeIntroE2EResult(Map<String, dynamic>.from(result));
        } catch (error) {
          await _writeIntroE2EResult(
            Map<String, dynamic>.from(
              androidNotificationPayloadE2EFailureReceipt(
                config: config,
                error: error,
              ),
            ),
          );
        } finally {
          await _deleteConfigIfPresent();
        }
        return;
      }

      // Keepalive phases also bypass the generic health-check/inbox preamble:
      // the dropped-send action must observe the existing production latch and
      // delimit only the real send, while recovery observation must arm before
      // the host relaunches the peer.
      if (isKeepaliveDropE2EAction(config['transport_action'])) {
        try {
          await runKeepaliveDropE2EAction(
            config: config,
            p2pService: p2pService,
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            messageRepo: messageRepo,
            writeResult: _writeIntroE2EResult,
          );
        } finally {
          await _deleteConfigIfPresent();
        }
        return;
      }

      // The wake-token proof owns two hash-only actions. The issuer crosses
      // the real mint/persist/register boundary; the presenter independently
      // reads the production receive store and observes an accepted real
      // inbox-store attachment. Neither action may fall through the generic
      // health/drain preamble or serialize opaque token material.
      if (isWakeTokenDirectionalityAction(config['transport_action'])) {
        try {
          final action = config['transport_action'];
          final result = action == wakeTokenIssuerAction
              ? await runWakeTokenIssuerE2EAction(
                  config: config,
                  wakeTokenStore: wakeTokenStore,
                  registerWakeTokens: registerWakeTokens,
                  onWaitCycle: p2pService.drainOfflineInbox,
                )
              : await runWakeTokenPresenterE2EAction(
                  config: config,
                  receivedWakeTokenStore: receivedWakeTokenStore,
                  detailedInboxStore: detailedInboxStore,
                  attachmentObserver: wakeTokenAttachmentObserver,
                  onWaitCycle: p2pService.drainOfflineInbox,
                );
          await _writeIntroE2EResult(Map<String, dynamic>.from(result));
        } catch (error) {
          await _writeIntroE2EResult(
            Map<String, dynamic>.from(
              wakeTokenE2EFailureReceipt(config: config, error: error),
            ),
          );
        } finally {
          await _deleteConfigIfPresent();
        }
        return;
      }

      // Voice owns a full two-peer production action: the physical Android
      // records and sends while the emulator persists, downloads, and plays
      // the exact nonce-bound attachment. It must bypass the generic intro
      // preamble so the receiver can publish its armed receipt before send.
      if (config['transport_action'] == androidVoiceMessageE2EAction) {
        try {
          final result = await runAndroidVoiceMessageE2EAction(
            config: config,
            p2pService: p2pService,
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: audioRecorderService,
            writeProgress: (progress) =>
                _writeIntroE2EResult(Map<String, dynamic>.from(progress)),
          );
          await _writeIntroE2EResult(Map<String, dynamic>.from(result));
        } catch (error) {
          await _writeIntroE2EResult(
            Map<String, dynamic>.from(
              androidVoiceMessageE2EFailureReceipt(
                config: config,
                error: error,
              ),
            ),
          );
        } finally {
          await _deleteConfigIfPresent();
        }
        return;
      }

      await runIntroE2EActions(
        p2pService: p2pService,
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: contactRequestRepo,
        introRepo: introRepo,
        messageRepo: messageRepo,
        resolveWakeToken: resolveWakeToken,
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

  // Cross-sim introduction acceptance can take tens of seconds to propagate
  // under 4-simulator load, and the app-side opener only polls ~7.5s for the
  // contact row to exist. Retry inside a bounded budget instead of failing on
  // the first attempt — a genuine wiring failure still fails once the budget
  // is exhausted, well inside the orchestrator's 240s per-step deadline.
  final retryCycles =
      (config['open_conversation_retry_cycles'] as num?)?.toInt() ?? 10;
  final retryIntervalMs =
      (config['open_conversation_retry_interval_ms'] as num?)?.toInt() ?? 2000;
  var opened = await openConversationByPeerId(requestedPeerId);
  for (var attempt = 0; !opened && attempt < retryCycles; attempt++) {
    await Future<void>.delayed(Duration(milliseconds: retryIntervalMs));
    opened = await openConversationByPeerId(requestedPeerId);
  }
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

Future<void> _waitForPrivateMediaOutboxE2EHostRelease(
  PrivateMediaOutboxE2ERequest request,
) async {
  final deadline = DateTime.now().add(request.timeout);
  while (DateTime.now().isBefore(deadline)) {
    final file = await _privateMediaOutboxE2EHostReleaseFile();
    if (!await file.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      continue;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException(
        'private-media outbox host release is not an object',
      );
    }
    validatePrivateMediaOutboxE2EHostRelease(
      request,
      Map<String, dynamic>.from(decoded),
    );
    await file.delete();
    return;
  }
  throw TimeoutException(
    'private-media outbox timed out waiting for host release',
  );
}

Future<File> _privateMediaOutboxE2EHostReleaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$privateMediaOutboxE2EHostReleaseFileName');
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
  ResolveWakeTokenForIntroE2EFn? resolveWakeToken,
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
        resolveWakeToken: resolveWakeToken,
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

  if (action == 'accept_folded_all' || action == 'pass_folded_all') {
    return _runFoldedIntroductionAction(
      action: action,
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      identityPeerId: identity.peerId,
      identityUsername: identity.username,
      messageRepo: messageRepo,
      pollCycles: pollCycles,
      pollIntervalMs: pollIntervalMs,
      idleCyclesAfterSeen: idleCyclesAfterSeen,
    );
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

/// Debug-E2E handshake for acceptance-notification campaigns.
///
/// [acceptIntroduction] completes after its first bounded delivery attempt,
/// even when the durable introducer row remains `sent` or `failed`. This
/// helper retries fresh rows without the production 60-second anti-race age
/// gate and returns only after every acted-on introduction has no outstanding
/// acceptance row for its introducer. The host still treats the real
/// notification card as the authoritative end-to-end proof.
@visibleForTesting
Future<Map<String, dynamic>> awaitIntroducerAcceptanceCustodyForIntroE2E({
  required Map<String, dynamic> introActionResult,
  required String ownPeerId,
  required IntroductionRepository introRepo,
  required P2PService p2pService,
  Duration timeout = const Duration(seconds: 120),
  Duration retryInterval = const Duration(seconds: 2),
}) async {
  if (introActionResult['action'] != 'accept_all') {
    throw StateError(
      'Introducer-custody proof requires introduction_action=accept_all',
    );
  }
  final rawActedOn = introActionResult['actedOn'];
  if (rawActedOn is! List<dynamic> || rawActedOn.isEmpty) {
    throw StateError(
      'Introducer-custody proof requires at least one acted-on introduction',
    );
  }
  final introductionIds = <String>[];
  for (final value in rawActedOn) {
    if (value is! String || value.isEmpty) {
      throw StateError(
        'Introducer-custody proof received an invalid introduction id',
      );
    }
    if (!introductionIds.contains(value)) introductionIds.add(value);
  }
  if (ownPeerId.isEmpty || timeout <= Duration.zero) {
    throw StateError('Introducer-custody proof received an invalid bound');
  }

  final stopwatch = Stopwatch()..start();
  var retryPasses = 0;
  while (true) {
    var pendingIntroducerRows = 0;
    for (final introductionId in introductionIds) {
      final intro = await introRepo.getIntroduction(introductionId);
      if (intro == null) {
        throw StateError(
          'Acted-on introduction disappeared before custody confirmation',
        );
      }
      final ownAccepted = intro.recipientId == ownPeerId
          ? intro.recipientStatus == IntroductionStatus.accepted
          : intro.introducedId == ownPeerId
          ? intro.introducedStatus == IntroductionStatus.accepted
          : false;
      if (!ownAccepted) {
        throw StateError(
          'Acted-on introduction was not durably accepted by this party',
        );
      }
      final deliveries = await introRepo.loadOutboxDeliveriesForIntroduction(
        introductionId,
      );
      pendingIntroducerRows += deliveries
          .where(
            (delivery) =>
                delivery.action == 'accept' &&
                delivery.targetPeerId == intro.introducerId,
          )
          .length;
    }

    if (pendingIntroducerRows == 0) {
      stopwatch.stop();
      emitFlowEvent(
        layer: 'E2E',
        event: 'INTRO_E2E_INTRODUCER_CUSTODY_CONFIRMED',
        details: {
          'introductionCount': introductionIds.length,
          'retryPasses': retryPasses,
        },
      );
      return <String, dynamic>{
        'status': 'confirmed',
        'introductionCount': introductionIds.length,
        'retryPasses': retryPasses,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      };
    }

    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException(
        'Introducer acceptance delivery did not reach confirmed custody',
        timeout,
      );
    }
    retryPasses++;
    await retryPendingIntroductionDeliveries(
      introRepo: introRepo,
      p2pService: p2pService,
      olderThan: Duration.zero,
    );
    if (retryInterval > Duration.zero) {
      await Future<void>.delayed(retryInterval);
    }
  }
}

Future<Map<String, dynamic>> _runFoldedIntroductionAction({
  required String action,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String identityPeerId,
  required String identityUsername,
  required MessageRepository messageRepo,
  required int pollCycles,
  required int pollIntervalMs,
  required int idleCyclesAfterSeen,
}) async {
  final actedOn = <String>[];
  final foldedTargets = <Map<String, dynamic>>[];
  final processedTargetPeerIds = <String>{};
  var sawAny = false;
  var idleAfterSeen = 0;

  for (var tick = 0; tick < pollCycles; tick++) {
    await p2pService.drainOfflineInbox();
    final pending = await introRepo.getPendingIntroductionsForUser(
      identityPeerId,
    );
    final foldedItems =
        foldIntroductionsForReview(
              introductions: pending,
              ownPeerId: identityPeerId,
            )
            .where((item) {
              return item.pendingCurrentViewerDecisionIntroIds.isNotEmpty &&
                  !processedTargetPeerIds.contains(item.targetPeerId);
            })
            .toList(growable: false);

    if (foldedItems.isNotEmpty) {
      sawAny = true;
      idleAfterSeen = 0;
    } else if (sawAny) {
      idleAfterSeen++;
      if (idleAfterSeen >= idleCyclesAfterSeen) {
        break;
      }
    }

    for (final foldedItem in foldedItems) {
      final FoldedIntroductionActionBatchResult result;
      switch (action) {
        case 'accept_folded_all':
          result = await acceptFoldedIntroduction(
            introRepo: introRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            foldedIntroduction: foldedItem,
            ownPeerId: identityPeerId,
            ownUsername: identityUsername,
            messageRepo: messageRepo,
          );
          break;
        case 'pass_folded_all':
          result = await passFoldedIntroduction(
            introRepo: introRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            foldedIntroduction: foldedItem,
            ownPeerId: identityPeerId,
            ownUsername: identityUsername,
          );
          break;
        default:
          throw StateError('Unknown folded intro E2E action: $action');
      }

      actedOn.addAll(result.appliedResults.map((item) => item.introductionId));
      processedTargetPeerIds.add(foldedItem.targetPeerId);
      foldedTargets.add(_foldedActionResultToJson(foldedItem, result));
    }

    await Future<void>.delayed(Duration(milliseconds: pollIntervalMs));
  }

  return {
    'action': action,
    'actedOn': actedOn,
    'dropped': 0,
    'foldedTargets': foldedTargets,
  };
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

  final foldedReviewItems = identity == null
      ? const <FoldedIntroductionReviewItem>[]
      : foldIntroductionsForReview(
          introductions: introMap.values.toList(growable: false),
          ownPeerId: identity.peerId,
        );

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
    'foldedReviewItems': foldedReviewItems
        .map(_foldedReviewItemToJson)
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

Map<String, dynamic> _foldedReviewItemToJson(
  FoldedIntroductionReviewItem item,
) {
  return {
    'targetPeerId': item.targetPeerId,
    'targetDisplayName': item.targetDisplayName,
    'displaySourceIntroductionId': item.displaySourceIntroductionId,
    'introductionIds': item.introductionIds,
    'introducerAttributions': item.introducerAttributions
        .map(
          (attribution) => {
            'introducerId': attribution.introducerId,
            'displayName': attribution.displayName,
          },
        )
        .toList(growable: false),
    'pendingCurrentViewerDecisionIntroIds':
        item.pendingCurrentViewerDecisionIntroIds,
    'acceptedCurrentViewerDecisionIntroIds':
        item.acceptedCurrentViewerDecisionIntroIds,
    'passedCurrentViewerDecisionIntroIds':
        item.passedCurrentViewerDecisionIntroIds,
  };
}

Map<String, dynamic> _foldedActionResultToJson(
  FoldedIntroductionReviewItem item,
  FoldedIntroductionActionBatchResult result,
) {
  return {
    'targetPeerId': item.targetPeerId,
    'targetDisplayName': item.targetDisplayName,
    'displaySourceIntroductionId': item.displaySourceIntroductionId,
    'introductionIds': item.introductionIds,
    'results': result.results
        .map(_foldedSingleActionResultToJson)
        .toList(growable: false),
    'appliedIntroIds': result.appliedResults
        .map((item) => item.introductionId)
        .toList(growable: false),
    'skippedNotPendingIntroIds': result.skippedNotPendingResults
        .map((item) => item.introductionId)
        .toList(growable: false),
    'failedIntroIds': result.failedResults
        .map((item) => item.introductionId)
        .toList(growable: false),
  };
}

Map<String, dynamic> _foldedSingleActionResultToJson(
  FoldedIntroductionActionResult result,
) {
  final intro = result.introduction;
  return {
    'introductionId': result.introductionId,
    'outcome': result.outcome.name,
    'recipientStatus': intro?.recipientStatus.toDbString(),
    'introducedStatus': intro?.introducedStatus.toDbString(),
    'overallStatus': intro?.status.toDbString(),
  };
}
