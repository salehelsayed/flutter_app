import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

const bool pushRelayRegistrationProofMode = bool.fromEnvironment(
  'MKNOON_PUSH_RELAY_REGISTRATION_PROOF',
);
const String pushRelayRegistrationProofCommandSchema =
    'mknoon.tc256-push-relay-registration-command.v1';
const String pushRelayRegistrationProofCommandSchemaV2 =
    'mknoon.tc256-push-relay-registration-command.v2';
const String pushRelayRegistrationProofCurrentTokenAuthorizationKind =
    'sdk_current_validate_only';
const String pushRelayRegistrationProofCommandFileName =
    'tc256_push_relay_registration_proof_command.json';
const String pushRelayRegistrationProofAppPrivatePath =
    'files/$pushRelayRegistrationProofCommandFileName';
const String pushRelayRegistrationProofReceiptSchema =
    'mknoon.push-relay-registration-receipt.v1';
const String pushRelayRegistrationProofReceiptSchemaV2 =
    'mknoon.push-relay-registration-receipt.v2';
const String pushRelayRegistrationProofReceiptFileName =
    'tc256_push_relay_registration_receipt.json';
const String pushRelayRegistrationProofReceiptAppPrivatePath =
    'files/$pushRelayRegistrationProofReceiptFileName';
const String _pushRelayRegistrationProofReceiptTempFileName =
    '$pushRelayRegistrationProofReceiptFileName.tmp';
const int pushRelayRegistrationProofMaxCommandBytes = 16 * 1024;

class PushRelayRegistrationProof {
  PushRelayRegistrationProof({
    this.proofSchema = pushRelayRegistrationProofCommandSchema,
    required this.commandId,
    required this.issuedAt,
    required this.maxAge,
    required this.tokenSha256,
    required this.tokenGenerationId,
    required this.refreshArtifactSha256,
    this.authorizationKind,
    this.authorizationArtifactSha256,
    this.gateACommandGenerationId,
    required this.commandSha256,
    required Future<void> Function(Map<String, Object?> receipt)
    completeCommand,
    DateTime Function()? now,
  }) : _completeCommand = completeCommand,
       _now = now ?? DateTime.now;

  final String commandId;
  final String proofSchema;
  final DateTime issuedAt;
  final Duration maxAge;
  final String tokenSha256;
  final String tokenGenerationId;
  final String refreshArtifactSha256;
  final String? authorizationKind;
  final String? authorizationArtifactSha256;
  final String? gateACommandGenerationId;
  final String commandSha256;
  final Future<void> Function(Map<String, Object?> receipt) _completeCommand;
  final DateTime Function() _now;
  bool _completed = false;
  bool _relayAttemptClaimed = false;
  String? _accountIdentitySha256;
  String? _transportIdentitySha256;

  bool matchesToken(String token) =>
      token.trim().isNotEmpty &&
      sha256.convert(utf8.encode(token.trim())).toString() == tokenSha256;

  bool bindAccountIdentity(String? accountPeerId) =>
      _bindIdentity(accountPeerId, account: true);

  bool bindTransportIdentity(String? transportPeerId) =>
      _bindIdentity(transportPeerId, account: false);

  bool _bindIdentity(String? identity, {required bool account}) {
    final normalized = identity?.trim() ?? '';
    if (normalized.isEmpty) return false;
    final identityHash = sha256.convert(utf8.encode(normalized)).toString();
    final existing = account
        ? _accountIdentitySha256
        : _transportIdentitySha256;
    if (existing != null && existing != identityHash) return false;
    if (account) {
      _accountIdentitySha256 = identityHash;
    } else {
      _transportIdentitySha256 = identityHash;
    }
    return true;
  }

  bool claimRelayAttempt() {
    if (_relayAttemptClaimed || _completed || !_isFresh()) return false;
    _relayAttemptClaimed = true;
    return true;
  }

  bool _isFresh() {
    final age = _now().toUtc().difference(issuedAt);
    return !age.isNegative && age <= maxAge;
  }

  Map<String, dynamic> safeDetails({required String platform}) =>
      <String, dynamic>{
        'proofSchema': proofSchema,
        'commandId': commandId,
        'tokenSha256': tokenSha256,
        if (proofSchema == pushRelayRegistrationProofCommandSchemaV2) ...{
          'authorizationKind': authorizationKind,
          'authorizationArtifactSha256': authorizationArtifactSha256,
          'gateACommandGenerationId': gateACommandGenerationId,
        } else ...{
          'tokenGenerationId': tokenGenerationId,
          'refreshArtifactSha256': refreshArtifactSha256,
        },
        'commandSha256': commandSha256,
        'platform': platform,
        'accountIdentitySha256': ?_accountIdentitySha256,
        'transportIdentitySha256': ?_transportIdentitySha256,
      };

  Future<void> complete({required String platform}) async {
    final accountIdentitySha256 = _accountIdentitySha256;
    final transportIdentitySha256 = _transportIdentitySha256;
    if (_completed ||
        !_relayAttemptClaimed ||
        !_isFresh() ||
        accountIdentitySha256 == null ||
        transportIdentitySha256 == null) {
      throw StateError('push relay registration proof already completed');
    }
    final receipt = <String, Object?>{
      'schema': proofSchema == pushRelayRegistrationProofCommandSchemaV2
          ? pushRelayRegistrationProofReceiptSchemaV2
          : pushRelayRegistrationProofReceiptSchema,
      'status': 'completed',
      'completedAt': _now().toUtc().toIso8601String(),
      ...safeDetails(platform: platform),
      'accountIdentitySha256': accountIdentitySha256,
      'transportIdentitySha256': transportIdentitySha256,
      'relayFrameAccepted': true,
      'tokenPersisted': true,
      'commandDeleted': true,
      'containsSecrets': false,
    };
    await _completeCommand(Map<String, Object?>.unmodifiable(receipt));
    _completed = true;
  }
}

PushRelayRegistrationProof parsePushRelayRegistrationProofCommand(
  List<int> rawBytes, {
  required DateTime now,
  Future<void> Function(Map<String, Object?> receipt)? completeCommand,
  DateTime Function()? clock,
}) {
  if (rawBytes.isEmpty ||
      rawBytes.length > pushRelayRegistrationProofMaxCommandBytes) {
    throw const FormatException('push relay proof command size rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('invalid push relay proof command JSON');
  }
  if (decoded is! Map) {
    throw const FormatException('push relay proof command is not an object');
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
  };
  final commandId = command['commandId'];
  final issuedAtRaw = command['issuedAt'];
  final issuedAt = issuedAtRaw is String
      ? DateTime.tryParse(issuedAtRaw)
      : null;
  final maxAgeSeconds = command['maxAgeSeconds'];
  final tokenSha256 = command['tokenSha256'];
  final isCurrentTokenV2 =
      command['schema'] == pushRelayRegistrationProofCommandSchemaV2;
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
        }
      : legacyKeys;
  final tokenGenerationId = isCurrentTokenV2
      ? command['gateACommandGenerationId']
      : command['tokenGenerationId'];
  final refreshArtifactSha256 = isCurrentTokenV2
      ? command['authorizationArtifactSha256']
      : command['refreshArtifactSha256'];
  final validHash = RegExp(r'^[0-9a-f]{64}$');
  if (command.keys.toSet().length != expectedKeys.length ||
      !command.keys.toSet().containsAll(expectedKeys) ||
      (!isCurrentTokenV2 &&
          command['schema'] != pushRelayRegistrationProofCommandSchema) ||
      commandId is! String ||
      !RegExp(
        r'^tc256-relay-registration-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      issuedAt == null ||
      !issuedAt.isUtc ||
      maxAgeSeconds is! int ||
      maxAgeSeconds < 30 ||
      maxAgeSeconds > 300 ||
      tokenSha256 is! String ||
      !validHash.hasMatch(tokenSha256) ||
      tokenGenerationId is! String ||
      !(isCurrentTokenV2
          ? RegExp(
              r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
            ).hasMatch(tokenGenerationId)
          : RegExp(
              r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
            ).hasMatch(tokenGenerationId)) ||
      refreshArtifactSha256 is! String ||
      !validHash.hasMatch(refreshArtifactSha256) ||
      (isCurrentTokenV2 &&
          command['authorizationKind'] !=
              pushRelayRegistrationProofCurrentTokenAuthorizationKind)) {
    throw const FormatException('invalid push relay proof command fields');
  }
  final age = now.toUtc().difference(issuedAt);
  if (age.isNegative || age > Duration(seconds: maxAgeSeconds)) {
    throw const FormatException('expired push relay proof command');
  }
  return PushRelayRegistrationProof(
    proofSchema: isCurrentTokenV2
        ? pushRelayRegistrationProofCommandSchemaV2
        : pushRelayRegistrationProofCommandSchema,
    commandId: commandId,
    issuedAt: issuedAt,
    maxAge: Duration(seconds: maxAgeSeconds),
    tokenSha256: tokenSha256,
    tokenGenerationId: tokenGenerationId,
    refreshArtifactSha256: refreshArtifactSha256,
    authorizationKind: isCurrentTokenV2
        ? pushRelayRegistrationProofCurrentTokenAuthorizationKind
        : null,
    authorizationArtifactSha256: isCurrentTokenV2
        ? refreshArtifactSha256
        : null,
    gateACommandGenerationId: isCurrentTokenV2 ? tokenGenerationId : null,
    commandSha256: sha256.convert(rawBytes).toString(),
    completeCommand: completeCommand ?? (_) async {},
    now: clock,
  );
}

Future<PushRelayRegistrationProof?> loadPushRelayRegistrationProof({
  DateTime Function()? now,
  Future<Directory> Function()? getSupportDirectory,
}) async {
  if (!pushRelayRegistrationProofMode) return null;
  final support =
      await (getSupportDirectory ?? getApplicationSupportDirectory)();
  final command = File(
    '${support.path}${Platform.pathSeparator}'
    '$pushRelayRegistrationProofCommandFileName',
  );
  final receipt = File(
    '${support.path}${Platform.pathSeparator}'
    '$pushRelayRegistrationProofReceiptFileName',
  );
  final receiptTemp = File(
    '${support.path}${Platform.pathSeparator}'
    '$_pushRelayRegistrationProofReceiptTempFileName',
  );
  if (!await command.exists()) {
    throw StateError('push relay registration proof command is missing');
  }
  if (await receipt.exists() || await receiptTemp.exists()) {
    throw StateError('stale push relay registration proof receipt exists');
  }
  final commandStat = await command.stat();
  if (commandStat.type != FileSystemEntityType.file ||
      commandStat.size <= 0 ||
      commandStat.size > pushRelayRegistrationProofMaxCommandBytes) {
    throw StateError('push relay registration proof command size rejected');
  }
  final rawBytes = await command.readAsBytes();
  return parsePushRelayRegistrationProofCommand(
    rawBytes,
    now: (now ?? DateTime.now)().toUtc(),
    clock: now,
    completeCommand: (safeReceipt) async {
      if (await command.exists()) await command.delete();
      if (await command.exists()) {
        throw StateError('push relay registration proof command survived');
      }
      await receiptTemp.writeAsString(jsonEncode(safeReceipt), flush: true);
      await receiptTemp.rename(receipt.path);
      if (!await receipt.exists() || await receiptTemp.exists()) {
        throw StateError('push relay registration proof receipt failed');
      }
    },
  );
}
