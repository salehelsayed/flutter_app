import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'group_media_ios_disposable_profile.dart';
import 'group_media_reliability_authority_target.dart';

const String groupMediaReliabilityE2EBuildProfile =
    groupMediaAndroidDisposableBuildProfile;
const String groupMediaReliabilityBarrierName =
    'receiver_jpeg_post_claim_pre_commit';
const String groupMediaReliabilityStrictBarrierName =
    'receiver_jpeg_strict_verified_ciphertext_pre_commit';

typedef LoadGroupMediaReliabilityStrictCustody =
    Future<List<DirectMediaBlobCustodyRow>> Function({
      required String groupId,
      required String messageId,
    });

const String groupMediaReliabilityE2EAction = 'group_media_reliability_android';
const String groupMediaReliabilityE2ECommandSchema =
    'mknoon.group-media-reliability-command.v1';
const String groupMediaReliabilityE2EResultSchema =
    'mknoon.group-media-reliability-endpoint.v1';

const String groupMediaReliabilityIdentityPhase = 'identity_probe';
const String groupMediaReliabilitySenderSetupPhase = 'sender_setup';
const String groupMediaReliabilityReceiverArmPhase = 'receiver_accept_arm';
const String groupMediaReliabilitySenderSendPhase = 'sender_send';
const String groupMediaReliabilitySenderAuthorityPhase =
    'sender_authority_refresh';
const String groupMediaReliabilityReceiverAuthorityPhase =
    'receiver_authority_ready';
const String groupMediaReliabilityReceiverRecoverPhase = 'receiver_recover';
const String groupMediaReliabilityReceiverRenderPhase = 'receiver_render_probe';
const String groupMediaReliabilitySenderProbePhase = 'sender_probe';

const Map<String, String> groupMediaReliabilityRenderLabelsByKind =
    <String, String>{
      'jpeg': 'P269 receiver JPEG decoded',
      'mp4': 'P269 receiver MP4 thumbnail decoded',
      'voice': 'P269 receiver voice player ready',
    };

const String groupMediaReliabilityAuthorityModeDefine =
    'P269_GROUP_MEDIA_AUTHORITY_MODE';
const String configuredGroupMediaReliabilityAuthorityModeName =
    String.fromEnvironment(
      groupMediaReliabilityAuthorityModeDefine,
      defaultValue: 'distinctAccountAndTransport',
    );

GroupMediaReliabilityAuthorityMode parseGroupMediaReliabilityAuthorityMode(
  String name,
) {
  for (final mode in GroupMediaReliabilityAuthorityMode.values) {
    if (mode.name == name) return mode;
  }
  throw const FormatException('group-media authority mode rejected');
}

bool groupMediaReliabilityIdentityMatches({
  required GroupMediaReliabilityAuthorityMode mode,
  required String accountPeerId,
  required String transportPeerId,
}) =>
    accountPeerId.isNotEmpty &&
    accountPeerId.trim() == accountPeerId &&
    transportPeerId.isNotEmpty &&
    transportPeerId.trim() == transportPeerId &&
    (mode == GroupMediaReliabilityAuthorityMode.accountBoundLegacy
        ? accountPeerId == transportPeerId
        : accountPeerId != transportPeerId);

enum GroupMediaReliabilityAuthorityMode {
  distinctAccountAndTransport,
  accountBoundLegacy,
}

bool groupMediaReliabilityAuthorityMatches({
  required GroupMediaReliabilityAuthorityMode mode,
  required String localAccountPeerId,
  required String localTransportPeerId,
  required String remoteAccountPeerId,
  required String remoteTransportPeerId,
  required Iterable<String> allowedPeers,
}) {
  final localAccount = localAccountPeerId.trim();
  final localTransport = localTransportPeerId.trim();
  final remoteAccount = remoteAccountPeerId.trim();
  final remoteTransport = remoteTransportPeerId.trim();
  final peers = allowedPeers.map((peer) => peer.trim()).toList(growable: false);
  if (localAccount.isEmpty ||
      localTransport.isEmpty ||
      remoteAccount.isEmpty ||
      remoteTransport.isEmpty ||
      localAccount != localAccountPeerId ||
      localTransport != localTransportPeerId ||
      remoteAccount != remoteAccountPeerId ||
      remoteTransport != remoteTransportPeerId ||
      localAccount == remoteAccount ||
      peers.length != 2 ||
      peers.any((peer) => peer.isEmpty) ||
      peers.toSet().length != 2 ||
      !peers.toSet().containsAll(<String>{localTransport, remoteTransport})) {
    return false;
  }
  return switch (mode) {
    GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport =>
      localTransport != localAccount &&
          remoteTransport != remoteAccount &&
          !peers.toSet().contains(localAccount) &&
          !peers.toSet().contains(remoteAccount),
    GroupMediaReliabilityAuthorityMode.accountBoundLegacy =>
      localTransport == localAccount && remoteTransport == remoteAccount,
  };
}

String groupMediaReliabilityDatabasePathFingerprint({
  required String runId,
  required String transportPeerId,
  required String databasePath,
}) {
  final normalizedTransportPeerId = transportPeerId.trim();
  if (runId.isEmpty ||
      normalizedTransportPeerId.isEmpty ||
      databasePath.isEmpty) {
    throw ArgumentError(
      'group-media database fingerprint inputs must be non-empty',
    );
  }
  return sha256
      .convert(
        utf8.encode(
          '$runId\u0000$normalizedTransportPeerId\u0000$databasePath',
        ),
      )
      .toString();
}

typedef LoadGroupMediaReliabilityAttachment =
    Future<MediaAttachment?> Function(String attachmentId);

@visibleForTesting
typedef GroupMediaReliabilityBeforeAtomicStateReplace =
    Future<void> Function(bool barrierReached);

@visibleForTesting
typedef GroupMediaReliabilityStateSnapshotRead =
    void Function(bool barrierReached);

typedef GroupMediaReliabilitySetupSender =
    Future<Map<String, Object?>> Function(
      String receiverAccountPeerId,
      String receiverTransportPeerId,
    );
typedef GroupMediaReliabilityAuthorityProbe =
    Future<Map<String, Object?>> Function(
      String groupId, {
      required bool requireSettled,
      GroupMediaReliabilityAuthorityTarget? expectedAuthority,
    });
typedef GroupMediaReliabilityAuthorityRefresh =
    Future<Map<String, Object?>> Function(
      String groupId,
      String receiverAccountPeerId,
      String receiverTransportPeerId,
    );
typedef GroupMediaReliabilityIdentityProbe =
    Future<Map<String, Object?>> Function(String role);
typedef GroupMediaReliabilityAcceptReceiver =
    Future<Map<String, Object?>?> Function(String groupId);
typedef GroupMediaReliabilitySendMedia =
    Future<Map<String, Object?>> Function(
      String groupId,
      Map<String, String> messageIds,
      Map<String, String> attachmentIds,
      String receiverAccountPeerId,
      String receiverTransportPeerId,
    );
typedef GroupMediaReliabilityRoleProbe =
    Future<Map<String, Object?>> Function(
      String role,
      Map<String, String> messageIds,
      Map<String, String> attachmentIds,
    );
typedef GroupMediaReliabilityRetryPass = Future<int> Function();
typedef GroupMediaReliabilityRenderReceiver =
    Future<Map<String, Object?>> Function(
      String groupId,
      Map<String, String> messageIds,
      Map<String, String> attachmentIds,
    );

@immutable
final class GroupMediaReliabilityE2ERequest {
  const GroupMediaReliabilityE2ERequest({
    required this.phase,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.groupId,
    required this.receiverAccountPeerId,
    required this.receiverTransportPeerId,
    required this.messageIds,
    required this.attachmentIds,
    this.expectedAuthority,
  });

  factory GroupMediaReliabilityE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    final keys = <String>{
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'phase',
      'role',
      'runId',
      'nonce',
      'groupId',
      'receiverAccountPeerId',
      'receiverTransportPeerId',
      'messageIds',
      'attachmentIds',
      if (config['phase'] == groupMediaReliabilityReceiverAuthorityPhase)
        'expectedAuthority',
    };
    if (config.keys.toSet().length != keys.length ||
        !config.keys.toSet().containsAll(keys) ||
        config['schema'] != groupMediaReliabilityE2ECommandSchema ||
        config['transport_action'] != groupMediaReliabilityE2EAction ||
        config['scenario'] != 'group_media_foreground_retry_acl_roundtrip') {
      throw const FormatException('group-media reliability request rejected');
    }
    final phase = _safeToken(config['phase'], maxLength: 32);
    final role = _safeToken(config['role'], maxLength: 16);
    final runId = _safeToken(config['runId'], maxLength: 128);
    final nonce = _safeToken(config['nonce'], maxLength: 128);
    if (!const <String>{
          groupMediaReliabilityIdentityPhase,
          groupMediaReliabilitySenderSetupPhase,
          groupMediaReliabilityReceiverArmPhase,
          groupMediaReliabilitySenderSendPhase,
          groupMediaReliabilitySenderAuthorityPhase,
          groupMediaReliabilityReceiverAuthorityPhase,
          groupMediaReliabilityReceiverRecoverPhase,
          groupMediaReliabilityReceiverRenderPhase,
          groupMediaReliabilitySenderProbePhase,
        }.contains(phase) ||
        !const <String>{'sender', 'receiver'}.contains(role) ||
        config['stepId'] != 'group-media-$phase-$runId') {
      throw const FormatException('group-media reliability phase rejected');
    }
    final messageIds = _kindMap(config['messageIds']);
    final attachmentIds = _kindMap(config['attachmentIds']);
    final groupId = _optionalSafeToken(config['groupId'], maxLength: 160);
    final expectedAuthority =
        phase == groupMediaReliabilityReceiverAuthorityPhase
        ? GroupMediaReliabilityAuthorityTarget.fromJson(
            config['expectedAuthority'],
          )
        : null;
    if (expectedAuthority != null &&
        (groupId == null || !expectedAuthority.isForGroup(groupId))) {
      throw const FormatException(
        'group-media authority target group rejected',
      );
    }
    return GroupMediaReliabilityE2ERequest(
      phase: phase,
      role: role,
      runId: runId,
      nonce: nonce,
      groupId: groupId,
      receiverAccountPeerId: _optionalSafeToken(
        config['receiverAccountPeerId'],
        maxLength: 180,
      ),
      receiverTransportPeerId: _optionalSafeToken(
        config['receiverTransportPeerId'],
        maxLength: 180,
      ),
      messageIds: messageIds,
      attachmentIds: attachmentIds,
      expectedAuthority: expectedAuthority,
    );
  }

  final String phase;
  final String role;
  final String runId;
  final String nonce;
  final String? groupId;
  final String? receiverAccountPeerId;
  final String? receiverTransportPeerId;
  final Map<String, String> messageIds;
  final Map<String, String> attachmentIds;
  final GroupMediaReliabilityAuthorityTarget? expectedAuthority;

  String get stepId => 'group-media-$phase-$runId';
}

/// Executes one nonce-bound command in the normal main-app dependency graph.
/// Host file transport remains owned by `intro_e2e_runner.dart`.
Future<Map<String, Object?>> runGroupMediaReliabilityE2EAction({
  required Map<String, dynamic> config,
  required GroupMediaReliabilityE2EController controller,
  required LoadGroupMediaReliabilityAttachment loadAttachment,
  required GroupMediaReliabilityIdentityProbe probeIdentity,
  required GroupMediaReliabilitySetupSender setupSender,
  required GroupMediaReliabilityAcceptReceiver acceptReceiver,
  required GroupMediaReliabilitySendMedia sendMedia,
  required GroupMediaReliabilityRoleProbe probeRole,
  required GroupMediaReliabilityRetryPass retryUploads,
  required GroupMediaReliabilityRetryPass retryDownloads,
  GroupMediaReliabilityRenderReceiver? renderReceiver,
  GroupMediaReliabilityAuthorityProbe? probeAuthority,
  GroupMediaReliabilityAuthorityRefresh? refreshAuthority,
  LoadGroupMediaReliabilityStrictCustody? loadStrictCustody,
  String installedProfileId = const String.fromEnvironment(
    'SIMS_BUILD_PROFILE_ID',
  ),
  String authorityModeName = configuredGroupMediaReliabilityAuthorityModeName,
}) async {
  final request = GroupMediaReliabilityE2ERequest.fromConfig(config);
  if (!controller.enabled ||
      installedProfileId != groupMediaReliabilityE2EBuildProfile) {
    throw StateError(
      'group-media reliability requires android.e2e.group_media_269',
    );
  }
  final authorityMode = parseGroupMediaReliabilityAuthorityMode(
    authorityModeName,
  );
  final base = <String, Object?>{
    'authorityMode': authorityMode.name,
    'schema': groupMediaReliabilityE2EResultSchema,
    'status': 'complete',
    'success': true,
    'scenario': 'group_media_foreground_retry_acl_roundtrip',
    'buildProfile': groupMediaReliabilityE2EBuildProfile,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'processId': controller.currentProcessId,
  };

  switch (request.phase) {
    case groupMediaReliabilityIdentityPhase:
      return <String, Object?>{...base, ...await probeIdentity(request.role)};
    case groupMediaReliabilitySenderSetupPhase:
      final receiverAccount = request.receiverAccountPeerId;
      final receiverTransport = request.receiverTransportPeerId;
      if (request.role != 'sender' ||
          receiverAccount == null ||
          receiverTransport == null) {
        throw const FormatException('sender setup tuple rejected');
      }
      return <String, Object?>{
        ...base,
        ...await setupSender(receiverAccount, receiverTransport),
        'roleDatabaseIdentity': await probeRole(
          request.role,
          const <String, String>{},
          const <String, String>{},
        ),
      };
    case groupMediaReliabilitySenderAuthorityPhase:
      if (authorityMode !=
              GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport ||
          request.role != 'sender' ||
          request.groupId == null ||
          request.receiverAccountPeerId == null ||
          request.receiverTransportPeerId == null ||
          refreshAuthority == null) {
        throw const FormatException('sender authority refresh tuple rejected');
      }
      return <String, Object?>{
        ...base,
        'authorityRefresh': await refreshAuthority(
          request.groupId!,
          request.receiverAccountPeerId!,
          request.receiverTransportPeerId!,
        ),
      };
    case groupMediaReliabilityReceiverAuthorityPhase:
      if (authorityMode !=
              GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport ||
          request.role != 'receiver' ||
          request.groupId == null ||
          request.expectedAuthority == null ||
          probeAuthority == null) {
        throw const FormatException(
          'receiver authority readiness tuple rejected',
        );
      }
      return <String, Object?>{
        ...base,
        'authorityAfter': await probeAuthority(
          request.groupId!,
          requireSettled: true,
          expectedAuthority: request.expectedAuthority,
        ),
      };
    case groupMediaReliabilityReceiverArmPhase:
      final groupId = request.groupId;
      if (request.role != 'receiver' || groupId == null) {
        throw const FormatException('receiver arm tuple rejected');
      }
      final accepted = await acceptReceiver(groupId);
      if (accepted == null) {
        throw StateError('receiver did not accept the exact group invite');
      }
      await controller.arm(
        GroupMediaReliabilityBarrierRequest(
          runId: request.runId,
          groupId: groupId,
          jpegMessageId: request.messageIds['jpeg']!,
          jpegAttachmentId: request.attachmentIds['jpeg']!,
          mediaMessageIds: request.messageIds,
          mediaAttachmentIds: request.attachmentIds,
        ),
      );
      return <String, Object?>{
        ...base,
        'status': 'armed',
        'groupId': groupId,
        if (authorityMode ==
                GroupMediaReliabilityAuthorityMode
                    .distinctAccountAndTransport &&
            probeAuthority != null)
          'authorityBefore': await probeAuthority(
            groupId,
            requireSettled: false,
          ),
        ...accepted,
        'roleDatabaseIdentity': await probeRole(
          request.role,
          const <String, String>{},
          const <String, String>{},
        ),
      };
    case groupMediaReliabilitySenderSendPhase:
      final groupId = request.groupId;
      final receiverAccount = request.receiverAccountPeerId;
      final receiverTransport = request.receiverTransportPeerId;
      if (request.role != 'sender' ||
          groupId == null ||
          receiverAccount == null ||
          receiverTransport == null) {
        throw const FormatException('sender media tuple rejected');
      }
      final sent = await sendMedia(
        groupId,
        request.messageIds,
        request.attachmentIds,
        receiverAccount,
        receiverTransport,
      );
      return <String, Object?>{
        ...base,
        ...sent,
        'roleDatabase': await probeRole(
          request.role,
          request.messageIds,
          request.attachmentIds,
        ),
      };
    case groupMediaReliabilityReceiverRecoverPhase:
      if (request.role != 'receiver') {
        throw const FormatException('receiver recovery role rejected');
      }
      var stage = GroupMediaReliabilityRecoveryStage.priorBoundary;
      final work = <String, int>{};
      Map<String, int>? attempts;
      try {
        final prior = await controller.releaseRecoveryAfterPriorStatus(
          loadCurrentAttachment: loadAttachment,
          loadStrictCustody: loadStrictCustody,
        );
        stage = GroupMediaReliabilityRecoveryStage.firstUpload;
        work['firstUploadWork'] = await retryUploads();
        stage = GroupMediaReliabilityRecoveryStage.firstDownload;
        work['firstDownloadWork'] = await retryDownloads();
        stage = GroupMediaReliabilityRecoveryStage.secondUpload;
        work['secondUploadWork'] = await retryUploads();
        stage = GroupMediaReliabilityRecoveryStage.secondDownload;
        work['secondDownloadWork'] = await retryDownloads();
        stage = GroupMediaReliabilityRecoveryStage.attemptCounts;
        attempts = await controller.loadAttemptCounts();
        stage = GroupMediaReliabilityRecoveryStage.roleDatabase;
        final roleDatabase = await probeRole(
          request.role,
          request.messageIds,
          request.attachmentIds,
        );
        return <String, Object?>{
          ...base,
          'priorStatus': prior.priorStatus,
          if (prior.strictCustody != null)
            'strictCustodyBoundary': prior.strictCustody,
          'previousProcessId': prior.previousProcessId,
          'currentProcessId': prior.currentProcessId,
          ...work,
          'downloadAttempts': attempts,
          'roleDatabase': roleDatabase,
        };
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(
          GroupMediaReliabilityRecoveryFailure._(
            stage: stage,
            cause: error,
            work: Map.unmodifiable(work),
            attempts: attempts == null ? null : Map.unmodifiable(attempts),
          ),
          stack,
        );
      }
    case groupMediaReliabilityReceiverRenderPhase:
      final groupId = request.groupId;
      final render = renderReceiver;
      if (request.role != 'receiver' || groupId == null || render == null) {
        throw const FormatException('receiver render tuple rejected');
      }
      await controller.requireRenderReady(request);
      return <String, Object?>{
        ...base,
        ...await render(groupId, request.messageIds, request.attachmentIds),
      };
    case groupMediaReliabilitySenderProbePhase:
      if (request.role != 'sender') {
        throw const FormatException('sender probe role rejected');
      }
      final firstUploadWork = await retryUploads();
      final firstDownloadWork = await retryDownloads();
      final secondUploadWork = await retryUploads();
      final secondDownloadWork = await retryDownloads();
      return <String, Object?>{
        ...base,
        'firstUploadWork': firstUploadWork,
        'firstDownloadWork': firstDownloadWork,
        'secondUploadWork': secondUploadWork,
        'secondDownloadWork': secondDownloadWork,
        'roleDatabase': await probeRole(
          request.role,
          request.messageIds,
          request.attachmentIds,
        ),
      };
  }
  throw StateError('unreachable group-media phase');
}

// Native media-custody codes plus closed bridge envelopes. Keep the host
// retention allowlist equally strict: no native errorMessage is evidence.
String? groupMediaReliabilityClosedUploadErrorCode(Object? value) =>
    value is String &&
        const {
          'MEDIA_CUSTODY_ADMISSION_DISABLED',
          'MEDIA_CUSTODY_FULL',
          'MEDIA_CUSTODY_UNSUPPORTED',
          'MEDIA_CUSTODY_IDENTITY_CONFLICT',
          'MEDIA_CUSTODY_INELIGIBLE',
          'MEDIA_CUSTODY_NOT_AUTHORIZED',
          'MEDIA_CUSTODY_HASH_MISMATCH',
          'MEDIA_CUSTODY_ALREADY_ACKED',
          'MEDIA_CUSTODY_CLEANUP_PENDING',
          'MEDIA_CUSTODY_STORAGE_ERROR',
          'MEDIA_CUSTODY_NOT_FOUND',
          'MEDIA_CUSTODY_COMMIT_INDETERMINATE',
          'MEDIA_ERROR',
          'NOT_INITIALIZED',
          'INVALID_INPUT',
          'INTERNAL_ERROR',
          'UNKNOWN_COMMAND',
          'NULL_RESPONSE',
          'MISSING_PLUGIN',
          'PLATFORM_ERROR',
          'BRIDGE_EXCEPTION',
          'MALFORMED_RESPONSE',
        }.contains(value)
    ? value
    : null;

/// Closed fixture diagnostics; no exception text, paths or authority material.
final class GroupMediaReliabilitySenderFailure implements Exception {
  const GroupMediaReliabilitySenderFailure(
    this.stage, {
    this.kind,
    this.preparationState,
    this.preparationHasDurableAuthority,
    this.preparationUploadResponseOk,
    this.preparationUploadErrorCode,
  });
  final String stage;
  final String? kind;
  final String? preparationState;
  final bool? preparationHasDurableAuthority;
  final bool? preparationUploadResponseOk;
  final String? preparationUploadErrorCode;
  bool get hasClosedPreparationResult =>
      closedStage == 'strict_preparation' &&
      ((preparationState == 'refused' &&
              preparationHasDurableAuthority != null) ||
          (preparationState == 'retained' &&
              preparationHasDurableAuthority == true) ||
          (preparationState == 'legacyUninitialized' &&
              preparationHasDurableAuthority == false));

  String get closedStage =>
      const {
        'authority_admission',
        'authority_rotation',
        'authority_settlement',
        'authority_membership',
        'fixture_material',
        'legacy_upload',
        'legacy_publication',
        'strict_preparation',
        'strict_publication',
        'strict_custody_join',
      }.contains(stage)
      ? stage
      : 'unexpected_error';
}

enum GroupMediaReliabilityRecoveryStage {
  priorBoundary,
  firstUpload,
  firstDownload,
  secondUpload,
  secondDownload,
  attemptCounts,
  roleDatabase,
}

/// Retains only the actual failed checkpoint and completed work counts.
/// The underlying exception is classified without exporting its text.
final class GroupMediaReliabilityRecoveryFailure implements Exception {
  const GroupMediaReliabilityRecoveryFailure._({
    required this.stage,
    required this.cause,
    required this.work,
    required this.attempts,
  });

  final GroupMediaReliabilityRecoveryStage stage;
  final Object cause;
  final Map<String, int> work;
  final Map<String, int>? attempts;
}

Map<String, Object?> groupMediaReliabilityE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  final request = GroupMediaReliabilityE2ERequest.fromConfig(config);
  return <String, Object?>{
    'schema': groupMediaReliabilityE2EResultSchema,
    'status': 'failed',
    'success': false,
    'scenario': 'group_media_foreground_retry_acl_roundtrip',
    'buildProfile': groupMediaReliabilityE2EBuildProfile,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'errorType':
        (error is GroupMediaReliabilityRecoveryFailure ? error.cause : error)
            .runtimeType
            .toString(),
    'errorCode': _groupMediaReliabilityE2EFailureCode(error),
    if (error is GroupMediaReliabilityRecoveryFailure) ...{
      'recoveryStage': error.stage.name,
      ...error.work,
      if (error.attempts != null) 'downloadAttempts': error.attempts,
    },
    if (error is GroupMediaReliabilitySenderFailure) ...{
      'senderStage': error.closedStage,
      if (error.hasClosedPreparationResult) ...{
        'preparationState': error.preparationState,
        'preparationHasDurableAuthority': error.preparationHasDurableAuthority,
        if (error.preparationState == 'retained' &&
            error.preparationUploadResponseOk != null) ...{
          'preparationUploadResponseOk': error.preparationUploadResponseOk,
          if (error.preparationUploadResponseOk == false)
            'preparationUploadErrorCode':
                ?groupMediaReliabilityClosedUploadErrorCode(
                  error.preparationUploadErrorCode,
                ),
        },
      },
      if (const {'jpeg', 'mp4', 'voice'}.contains(error.kind))
        'mediaKind': error.kind,
    },
  };
}

String _groupMediaReliabilityE2EFailureCode(Object error) {
  if (error is GroupMediaReliabilityRecoveryFailure) {
    return _groupMediaReliabilityE2EFailureCode(error.cause);
  }
  if (error is GroupMediaReliabilitySenderFailure) {
    return 'sender_${error.closedStage}';
  }
  final message = switch (error) {
    StateError stateError => stateError.message,
    FormatException formatError => formatError.message,
    _ => null,
  };
  return switch (message) {
    'group-media disposable identity authority did not settle' =>
      'identity_authority',
    'group-media sender lacks distinct account/transport authority' ||
    'group-media sender lacks configured account/transport authority' =>
      'sender_authority',
    'group-media sender group/invite setup did not settle' =>
      'sender_group_invite_settle',
    'group-media role SQLCipher facts rejected' => 'role_sqlcipher_facts',
    'receiver did not accept the exact group invite' =>
      'receiver_invite_accept',
    'group-media send identity discriminator failed' =>
      'send_identity_discriminator',
    'group-media ACL did not select receiver transport' =>
      'receiver_transport_acl',
    'group-media authority policy rejected' => 'authority_policy',
    'group-media fixture IDs are incomplete or reused' => 'fixture_id_contract',
    'group-media fixture attachment lease was denied' => 'fixture_lease_denied',
    'group-media voice fixture lacks RECORD_AUDIO' => 'voice_permission',
    'group-media voice fixture recording is invalid' =>
      'voice_recording_invalid',
    'group-media voice fixture is not AAC/M4A' => 'voice_format_invalid',
    'periodic group upload retry is not wired' => 'upload_retry_not_wired',
    'periodic group download retry is not wired' => 'download_retry_not_wired',
    'group-media role database lacks transport authority' =>
      'role_database_transport',
    'group-media recovery lacks a fresh process boundary' =>
      'recovery_process_boundary',
    'recovery attachment does not match the persisted JPEG tuple' =>
      'recovery_attachment_tuple',
    'strict custody reload unavailable' => 'recovery_custody_loader',
    'strict custody reload ambiguous' => 'recovery_custody_row_count',
    'strict barrier requires exact committed custody without local or ACK source' =>
      'recovery_custody_boundary',
    'strict custody changed across process death' => 'recovery_custody_changed',
    'JPEG did not retain priorStatus=downloading' => 'recovery_legacy_status',
    'group-media reliability state is absent' => 'recovery_state_absent',
    'group-media receiver jpeg row did not settle exactly' =>
      'receiver_jpeg_not_settled',
    'group-media receiver mp4 row did not settle exactly' =>
      'receiver_mp4_not_settled',
    'group-media receiver voice row did not settle exactly' =>
      'receiver_voice_not_settled',
    _ => 'unexpected_error',
  };
}

/// Compile-gated, durable request for the one Android process-death barrier.
///
/// The host chooses all IDs before publication. The controller therefore
/// cannot accidentally block an unrelated download that happens to be JPEG.
@immutable
final class GroupMediaReliabilityBarrierRequest {
  const GroupMediaReliabilityBarrierRequest({
    required this.runId,
    required this.groupId,
    required this.jpegMessageId,
    required this.jpegAttachmentId,
    required this.mediaMessageIds,
    required this.mediaAttachmentIds,
  });

  final String runId;
  final String groupId;
  final String jpegMessageId;
  final String jpegAttachmentId;
  final Map<String, String> mediaMessageIds;
  final Map<String, String> mediaAttachmentIds;
}

@immutable
final class GroupMediaReliabilityBarrierReached {
  const GroupMediaReliabilityBarrierReached({
    required this.priorStatus,
    required this.attempt,
    required this.processId,
  });

  final String priorStatus;
  final int attempt;
  final int processId;
}

@immutable
final class GroupMediaReliabilityPriorStatusEvidence {
  const GroupMediaReliabilityPriorStatusEvidence({
    required this.priorStatus,
    required this.previousProcessId,
    required this.currentProcessId,
    this.strictCustody,
  });

  final String priorStatus;
  final int previousProcessId;
  final int currentProcessId;
  final Map<String, Object?>? strictCustody;
}

/// Main-app-only owner for the host-controlled post-claim/pre-commit barrier.
///
/// Production builds construct this disabled. `android.e2e.main` constructs it
/// enabled and passes [onPostClaimPreCommit] into the ordinary-group download
/// leaf. State is replaced atomically, so a host can force-stop immediately
/// after observing the marker without accepting a partially written proof.
final class GroupMediaReliabilityE2EController {
  GroupMediaReliabilityE2EController({
    required this.enabled,
    required Directory stateDirectory,
    int? currentProcessId,
    @visibleForTesting
    GroupMediaReliabilityBeforeAtomicStateReplace? beforeAtomicStateReplace,
    @visibleForTesting
    GroupMediaReliabilityStateSnapshotRead? onStateSnapshotRead,
  }) : _stateFile = File(
         '${stateDirectory.absolute.path}${Platform.pathSeparator}'
         'group_media_reliability_state.json',
       ),
       currentProcessId = currentProcessId ?? pid,
       _beforeAtomicStateReplace = beforeAtomicStateReplace,
       _onStateSnapshotRead = onStateSnapshotRead {
    if (enabled) {
      _state = _readStateSnapshotSync();
    }
  }

  factory GroupMediaReliabilityE2EController.forInstalledProfile({
    required Directory stateDirectory,
    String installedProfileId = const String.fromEnvironment(
      'SIMS_BUILD_PROFILE_ID',
    ),
  }) => GroupMediaReliabilityE2EController(
    enabled:
        kDebugMode &&
        installedProfileId == groupMediaReliabilityE2EBuildProfile,
    stateDirectory: stateDirectory,
  );

  final bool enabled;
  final int currentProcessId;
  final File _stateFile;
  final GroupMediaReliabilityBeforeAtomicStateReplace?
  _beforeAtomicStateReplace;
  final GroupMediaReliabilityStateSnapshotRead? _onStateSnapshotRead;
  final Completer<void> _firstJpegBarrierRelease = Completer<void>();
  final _GroupMediaReliabilityMutationQueue _stateMutations =
      _GroupMediaReliabilityMutationQueue();
  Map<String, Object?>? _state;
  int _writeSequence = 0;

  bool get holdsAutomaticRecovery {
    if (!enabled) return false;
    final state = _state ?? _readStateSnapshotSync();
    if (state == null) return false;
    final barrier = _map(state['barrier']);
    return barrier?['reached'] == true && state['recoveryReleased'] != true;
  }

  Future<void> arm(GroupMediaReliabilityBarrierRequest request) async {
    _requireEnabled();
    _validateRequest(request);
    await _stateMutations.run(() async {
      if (await _stateFile.exists()) {
        throw StateError('group-media reliability state already exists');
      }
      final next = <String, Object?>{
        'schema': 'mknoon.group-media-reliability-state.v1',
        'runId': request.runId,
        'groupId': request.groupId,
        'jpegMessageId': request.jpegMessageId,
        'jpegAttachmentId': request.jpegAttachmentId,
        'mediaMessageIds': Map<String, Object?>.from(request.mediaMessageIds),
        'mediaAttachmentIds': Map<String, Object?>.from(
          request.mediaAttachmentIds,
        ),
        'attempts': <String, Object?>{'jpeg': 0, 'mp4': 0, 'voice': 0},
        'barrier': null,
        'recoveryReleased': false,
      };
      await _writeStateSnapshot(next);
      _state = _copyState(next);
    });
  }

  /// Called once for each admitted ordinary automatic-group download run,
  /// before local encrypted-companion recovery or a relay transfer begins.
  Future<void> onAutomaticDownloadAttemptStarted({
    required MediaAttachment attachment,
  }) async {
    if (!enabled) return;
    await _mutateStateIfPresent<bool>((state) {
      final kind = _targetKind(state, attachment);
      if (kind == null) {
        return const _GroupMediaReliabilityStateUpdate.unchanged(false);
      }
      final attempts = _map(state['attempts'])!;
      attempts[kind] = ((attempts[kind] as num?)?.toInt() ?? 0) + 1;
      state['attempts'] = attempts;
      return const _GroupMediaReliabilityStateUpdate.changed(true);
    });
  }

  /// Called only after the ordinary-group download claim and successful relay
  /// response, immediately before validation/promotion/commit.
  Future<void> onPostClaimPreCommit({
    required MediaAttachment attachment,
    required LoadGroupMediaReliabilityAttachment loadCurrentAttachment,
  }) async {
    if (!enabled) return;
    final outcome =
        await _mutateStateIfPresent<_GroupMediaReliabilityPostClaimOutcome>((
          state,
        ) async {
          final kind = _targetKind(state, attachment);
          if (kind == null) {
            return const _GroupMediaReliabilityStateUpdate.unchanged(
              _GroupMediaReliabilityPostClaimOutcome.ignored(),
            );
          }

          final current = await loadCurrentAttachment(attachment.id);
          if (current == null ||
              current.id != attachment.id ||
              current.messageId != attachment.messageId ||
              current.downloadStatus != 'downloading') {
            throw StateError(
              'group-media barrier requires the exact durable downloading claim',
            );
          }

          final attempts = _map(state['attempts'])!;
          final currentAttempt = (attempts[kind] as num?)?.toInt() ?? 0;
          if (currentAttempt <= 0) {
            throw StateError(
              'group-media barrier observed an uncounted attempt',
            );
          }

          final existingBarrier = _map(state['barrier']);
          final isFirstJpeg =
              kind == 'jpeg' && currentAttempt == 1 && existingBarrier == null;
          if (!isFirstJpeg) {
            return const _GroupMediaReliabilityStateUpdate.unchanged(
              _GroupMediaReliabilityPostClaimOutcome.observed(),
            );
          }
          if (attachment.id != state['jpegAttachmentId'] ||
              attachment.messageId != state['jpegMessageId']) {
            throw StateError('group-media JPEG barrier tuple changed');
          }
          state['barrier'] = <String, Object?>{
            'name': groupMediaReliabilityBarrierName,
            'reached': true,
            'priorStatus': current.downloadStatus,
            'attempt': currentAttempt,
            'processId': currentProcessId,
          };
          return _GroupMediaReliabilityStateUpdate.changed(
            _GroupMediaReliabilityPostClaimOutcome.barrier(
              shouldBlock: state['recoveryReleased'] != true,
            ),
          );
        });

    if (outcome?.shouldBlock == true) {
      // The Android host force-stops this process. A normal completion is not a
      // valid proof leg; only tests may explicitly release the completer.
      await _firstJpegBarrierRelease.future;
    }
  }

  /// Strict counterpart of the ordinary post-claim barrier. The owner has
  /// verified ciphertext but has not decrypted, promoted, or committed an ACK.
  Future<void> onStrictVerifiedCiphertext({
    required MediaAttachment attachment,
    required DirectMediaBlobCustodyRow custody,
    required LoadGroupMediaReliabilityAttachment loadCurrentAttachment,
  }) async {
    if (!enabled) return;
    final outcome =
        await _mutateStateIfPresent<_GroupMediaReliabilityPostClaimOutcome>((
          state,
        ) async {
          final kind = _targetKind(state, attachment);
          if (kind == null) {
            return const _GroupMediaReliabilityStateUpdate.unchanged(
              _GroupMediaReliabilityPostClaimOutcome.ignored(),
            );
          }
          final current = await loadCurrentAttachment(attachment.id);
          final proof = _strictBoundary(
            current,
            custody,
            groupId: state['groupId'] as String,
          );
          if (current == null ||
              current.messageId != attachment.messageId ||
              current.groupMediaBlobCustodyFingerprint !=
                  attachment.groupMediaBlobCustodyFingerprint) {
            throw StateError('strict barrier attachment changed');
          }
          final attempt = (_map(state['attempts'])![kind] as num).toInt();
          if (attempt <= 0) {
            throw StateError('strict barrier attempt was not counted');
          }
          if (kind != 'jpeg' || attempt != 1 || state['barrier'] != null) {
            return const _GroupMediaReliabilityStateUpdate.unchanged(
              _GroupMediaReliabilityPostClaimOutcome.observed(),
            );
          }
          if (attachment.id != state['jpegAttachmentId'] ||
              attachment.messageId != state['jpegMessageId']) {
            throw StateError('strict barrier tuple changed');
          }
          state['barrier'] = <String, Object?>{
            'name': groupMediaReliabilityStrictBarrierName,
            'reached': true,
            'priorStatus': current.downloadStatus,
            'attempt': attempt,
            'processId': currentProcessId,
            'strictCustodyBoundary': proof,
          };
          return _GroupMediaReliabilityStateUpdate.changed(
            _GroupMediaReliabilityPostClaimOutcome.barrier(
              shouldBlock: state['recoveryReleased'] != true,
            ),
          );
        });
    if (outcome?.shouldBlock == true) await _firstJpegBarrierRelease.future;
  }

  Map<String, Object?> _strictBoundary(
    MediaAttachment? attachment,
    DirectMediaBlobCustodyRow custody, {
    required String groupId,
  }) {
    if (attachment == null ||
        attachment.groupMediaBlobCustodyFingerprint == null ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.contentHash != custody.contentHash ||
        attachment.localPath?.isNotEmpty == true ||
        attachment.downloadStatus != 'pending' ||
        custody.ownerLane != MediaBlobCustodyOwnerLane.group ||
        custody.groupId != groupId ||
        custody.attachmentId != attachment.id ||
        custody.messageId != attachment.messageId ||
        custody.state != DirectMediaBlobCustodyState.incomingCommitted ||
        custody.direction != DirectMediaBlobCustodyDirection.incoming ||
        custody.custodyRelayPeerId != null) {
      throw StateError(
        'strict barrier requires exact committed custody without local or ACK source',
      );
    }
    return <String, Object?>{
      'state': 'incoming_committed',
      'local_ready': false,
      'ack_source_present': false,
      'custody_fingerprint': attachment.groupMediaBlobCustodyFingerprint,
      'custody_projection_sha256': sha256
          .convert(utf8.encode(jsonEncode(custody.toMap())))
          .toString(),
      'ciphertext_sha256': custody.contentHash,
      'ciphertext_size': custody.ciphertextSize,
      'custody_blob_id_sha256': sha256
          .convert(utf8.encode(custody.custodyBlobId))
          .toString(),
    };
  }

  String? _targetKind(Map<String, Object?> state, MediaAttachment attachment) {
    final ids = _map(state['mediaAttachmentIds']);
    for (final kind in const <String>['jpeg', 'mp4', 'voice']) {
      if (ids?[kind] == attachment.id) return kind;
    }
    return null;
  }

  Future<GroupMediaReliabilityBarrierReached> waitForBarrierReached({
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async {
    _requireEnabled();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      // Poll the durable file without publishing the snapshot into [_state].
      // A read that races an in-progress copy-on-write mutation may see the
      // old version, but it can never replace or corrupt the pending version.
      final state = await _readStateSnapshot();
      final barrier = _map(state?['barrier']);
      if (barrier?['reached'] == true) {
        return GroupMediaReliabilityBarrierReached(
          priorStatus: barrier!['priorStatus']! as String,
          attempt: (barrier['attempt']! as num).toInt(),
          processId: (barrier['processId']! as num).toInt(),
        );
      }
      await Future<void>.delayed(pollInterval);
    }
    throw TimeoutException('group-media JPEG barrier was not reached', timeout);
  }

  /// Fresh-process gate: revalidate the exact legacy claim or strict committed
  /// custody boundary before permitting attempt two.
  Future<GroupMediaReliabilityPriorStatusEvidence>
  releaseRecoveryAfterPriorStatus({
    required LoadGroupMediaReliabilityAttachment loadCurrentAttachment,
    LoadGroupMediaReliabilityStrictCustody? loadStrictCustody,
  }) async {
    _requireEnabled();
    final evidence =
        await _mutateStateIfPresent<GroupMediaReliabilityPriorStatusEvidence>((
          state,
        ) async {
          final barrier = _map(state['barrier']);
          final previousProcessId = (barrier?['processId'] as num?)?.toInt();
          final jpegAttachmentId = state['jpegAttachmentId'];
          if (barrier?['reached'] != true ||
              previousProcessId == null ||
              previousProcessId == currentProcessId ||
              jpegAttachmentId is! String) {
            throw StateError(
              'group-media recovery lacks a fresh process boundary',
            );
          }
          final current = await loadCurrentAttachment(jpegAttachmentId);
          if (current == null ||
              current.id != jpegAttachmentId ||
              current.messageId != state['jpegMessageId']) {
            throw StateError(
              'recovery attachment does not match the persisted JPEG tuple',
            );
          }
          Map<String, Object?>? strictProof;
          if (barrier?['name'] == groupMediaReliabilityStrictBarrierName) {
            if (loadStrictCustody == null) {
              throw StateError('strict custody reload unavailable');
            }
            final rows = await loadStrictCustody(
              groupId: state['groupId'] as String,
              messageId: current.messageId,
            );
            final exact = rows
                .where((row) => row.attachmentId == current.id)
                .toList();
            if (exact.length != 1) {
              throw StateError('strict custody reload ambiguous');
            }
            strictProof = _strictBoundary(
              current,
              exact.single,
              groupId: state['groupId'] as String,
            );
            if (jsonEncode(strictProof) !=
                jsonEncode(barrier?['strictCustodyBoundary'])) {
              throw StateError('strict custody changed across process death');
            }
          } else if (current.downloadStatus != 'downloading') {
            throw StateError('JPEG did not retain priorStatus=downloading');
          }
          state['recoveryReleased'] = true;
          state['recoveryProcessId'] = currentProcessId;
          return _GroupMediaReliabilityStateUpdate.changed(
            GroupMediaReliabilityPriorStatusEvidence(
              priorStatus: current.downloadStatus,
              strictCustody: strictProof,
              previousProcessId: previousProcessId,
              currentProcessId: currentProcessId,
            ),
          );
        });
    if (evidence == null) {
      throw StateError('group-media reliability state is absent');
    }
    return evidence;
  }

  Future<Map<String, int>> loadAttemptCounts() async {
    final state = await _readStateSnapshot();
    final attempts = _map(state?['attempts']);
    if (attempts == null) return const <String, int>{};
    return Map<String, int>.unmodifiable(<String, int>{
      for (final kind in const <String>['jpeg', 'mp4', 'voice'])
        kind: (attempts[kind] as num?)?.toInt() ?? 0,
    });
  }

  /// Rejects any render command that is not bound to this exact durable run
  /// after fresh-process recovery and the expected attempt cardinality.
  Future<void> requireRenderReady(
    GroupMediaReliabilityE2ERequest request,
  ) async {
    _requireEnabled();
    final state = await _readStateSnapshot();
    final barrier = _map(state?['barrier']);
    final attempts = _map(state?['attempts']);
    final storedMessages = _map(state?['mediaMessageIds']);
    final storedAttachments = _map(state?['mediaAttachmentIds']);
    bool exactKindMap(
      Map<String, Object?>? stored,
      Map<String, String> expected,
    ) =>
        stored != null &&
        stored.keys.toSet().length == 3 &&
        stored.keys.toSet().containsAll(const <String>{
          'jpeg',
          'mp4',
          'voice',
        }) &&
        expected.entries.every((entry) => stored[entry.key] == entry.value);
    if (state == null ||
        state['runId'] != request.runId ||
        state['groupId'] != request.groupId ||
        state['jpegMessageId'] != request.messageIds['jpeg'] ||
        state['jpegAttachmentId'] != request.attachmentIds['jpeg'] ||
        !exactKindMap(storedMessages, request.messageIds) ||
        !exactKindMap(storedAttachments, request.attachmentIds) ||
        barrier?['reached'] != true ||
        state['recoveryReleased'] != true ||
        state['recoveryProcessId'] != currentProcessId ||
        attempts?['jpeg'] != 2 ||
        attempts?['mp4'] != 1 ||
        attempts?['voice'] != 1) {
      throw StateError(
        'group-media render requires exact settled recovery authority',
      );
    }
  }

  @visibleForTesting
  void releaseFirstBarrierForTest() {
    if (!_firstJpegBarrierRelease.isCompleted) {
      _firstJpegBarrierRelease.complete();
    }
  }

  void _requireEnabled() {
    if (!enabled) {
      throw StateError('group-media reliability E2E controller is disabled');
    }
  }

  void _validateRequest(GroupMediaReliabilityBarrierRequest request) {
    final safe = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    if (!safe.hasMatch(request.runId) ||
        !safe.hasMatch(request.groupId) ||
        !safe.hasMatch(request.jpegMessageId) ||
        !safe.hasMatch(request.jpegAttachmentId) ||
        request.mediaMessageIds.keys.toSet().length != 3 ||
        !request.mediaMessageIds.keys.toSet().containsAll(const <String>{
          'jpeg',
          'mp4',
          'voice',
        }) ||
        request.mediaMessageIds.values.toSet().length != 3 ||
        request.mediaMessageIds.values.any((value) => !safe.hasMatch(value)) ||
        request.mediaAttachmentIds.keys.toSet().length != 3 ||
        !request.mediaAttachmentIds.keys.toSet().containsAll(const <String>{
          'jpeg',
          'mp4',
          'voice',
        }) ||
        request.mediaAttachmentIds.values.toSet().length != 3 ||
        request.mediaAttachmentIds.values.any(
          (value) => !safe.hasMatch(value),
        ) ||
        request.mediaMessageIds['jpeg'] != request.jpegMessageId ||
        request.mediaAttachmentIds['jpeg'] != request.jpegAttachmentId) {
      throw const FormatException('group-media barrier request rejected');
    }
  }

  Map<String, Object?>? _readStateSnapshotSync() {
    if (!_stateFile.existsSync()) return null;
    try {
      final decoded = _map(jsonDecode(_stateFile.readAsStringSync()));
      if (decoded == null) {
        throw const FormatException('state root is not an object');
      }
      return decoded;
    } on Object {
      throw StateError('group-media reliability state is corrupt');
    }
  }

  Future<Map<String, Object?>?> _readStateSnapshot() async {
    if (!await _stateFile.exists()) return null;
    late final Map<String, Object?> decoded;
    try {
      final candidate = _map(jsonDecode(await _stateFile.readAsString()));
      if (candidate == null) {
        throw const FormatException('state root is not an object');
      }
      decoded = candidate;
    } on Object {
      throw StateError('group-media reliability state is corrupt');
    }
    _onStateSnapshotRead?.call(_barrierReached(decoded));
    return decoded;
  }

  Future<T?> _mutateStateIfPresent<T>(
    FutureOr<_GroupMediaReliabilityStateUpdate<T>> Function(
      Map<String, Object?> state,
    )
    mutation,
  ) => _stateMutations.run(() async {
    final current = await _readStateSnapshot();
    if (current == null) return null;
    final next = _copyState(current);
    final update = await mutation(next);
    if (update.shouldPersist) {
      await _writeStateSnapshot(next);
      // Publish only a private copy after the durable atomic replace succeeds.
      _state = _copyState(next);
    }
    return update.value;
  });

  Future<void> _writeStateSnapshot(Map<String, Object?> state) async {
    await _stateFile.parent.create(recursive: true);
    final sequence = ++_writeSequence;
    final temporary = File(
      '${_stateFile.path}.pending-$currentProcessId-$sequence',
    );
    try {
      await temporary.writeAsString('${jsonEncode(state)}\n', flush: true);
      await _beforeAtomicStateReplace?.call(_barrierReached(state));
      // Android and the host tests run on POSIX filesystems, where rename over
      // the existing file is one atomic directory operation. Never delete the
      // durable state first: a force-stop in that gap would erase the proof.
      await temporary.rename(_stateFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final class _GroupMediaReliabilityStateUpdate<T> {
  const _GroupMediaReliabilityStateUpdate.changed(this.value)
    : shouldPersist = true;

  const _GroupMediaReliabilityStateUpdate.unchanged(this.value)
    : shouldPersist = false;

  final T value;
  final bool shouldPersist;
}

final class _GroupMediaReliabilityPostClaimOutcome {
  const _GroupMediaReliabilityPostClaimOutcome.ignored() : shouldBlock = false;

  const _GroupMediaReliabilityPostClaimOutcome.observed() : shouldBlock = false;

  const _GroupMediaReliabilityPostClaimOutcome.barrier({
    required this.shouldBlock,
  });

  final bool shouldBlock;
}

/// One-process serial queue whose tail always settles successfully.
///
/// Errors are delivered only through the individual operation future, so one
/// rejected mutation cannot poison every later state transition.
final class _GroupMediaReliabilityMutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

Map<String, Object?> _copyState(Map<String, Object?> source) =>
    source.map<String, Object?>(
      (key, value) => MapEntry<String, Object?>(key, _copyStateValue(value)),
    );

Object? _copyStateValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => map.map<String, Object?>(
    (key, item) =>
        MapEntry<String, Object?>(key.toString(), _copyStateValue(item)),
  ),
  List<Object?> list => list.map<Object?>(_copyStateValue).toList(),
  _ => value,
};

bool _barrierReached(Map<String, Object?> state) =>
    _map(state['barrier'])?['reached'] == true;

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

String _safeToken(Object? value, {required int maxLength}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw const FormatException('group-media command token rejected');
  }
  return value;
}

String? _optionalSafeToken(Object? value, {required int maxLength}) {
  if (value == null || value == '') return null;
  return _safeToken(value, maxLength: maxLength);
}

Map<String, String> _kindMap(Object? value) {
  final map = _map(value);
  if (map == null ||
      map.keys.toSet().length != 3 ||
      !map.keys.toSet().containsAll(const <String>{'jpeg', 'mp4', 'voice'})) {
    throw const FormatException('group-media kind map rejected');
  }
  final result = <String, String>{
    for (final kind in const <String>['jpeg', 'mp4', 'voice'])
      kind: _safeToken(map[kind], maxLength: 160),
  };
  if (result.values.toSet().length != 3) {
    throw const FormatException('group-media kind IDs must be distinct');
  }
  return Map<String, String>.unmodifiable(result);
}
