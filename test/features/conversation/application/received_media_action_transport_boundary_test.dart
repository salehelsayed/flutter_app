import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 231 (TC-231-09): exact production egress call sites + frozen wired
/// transport baseline.
///
/// Import-only assertions cannot catch a media-action handler that reuses an
/// EXISTING delivery seam inside `conversation_wired.dart` (that file
/// legitimately imports Bridge/P2P/send use cases for messaging). So this
/// contract pins:
///  1. exactly ONE `ReceivedMediaEgressService.perform` call site, inside the
///     controller, whose imports are an exact allowlist;
///  2. zero raw-gateway/channel/share-picker/delivery symbols in every
///     media-action UI file;
///  3. the pre-plan-231 inventory of wired transport call sites, so a new
///     handler cannot silently add a delivery call (TC-231-09W drives the
///     same seam behaviorally with throwing spies).
void main() {
  const controllerPath =
      'lib/features/conversation/application/received_media_action_controller.dart';
  const wiredPath =
      'lib/features/conversation/presentation/screens/conversation_wired.dart';

  // Every file that renders or routes the 231 media actions. None of them may
  // reach a native/egress/delivery boundary directly.
  const mediaActionUiFiles = <String>[
    'lib/features/conversation/presentation/screens/conversation_screen.dart',
    'lib/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart',
    'lib/features/conversation/presentation/widgets/message_context_overlay.dart',
    'lib/features/conversation/presentation/widgets/letter_card.dart',
    'lib/shared/widgets/media/media_grid.dart',
    'lib/shared/widgets/media/media_grid_cell.dart',
    'lib/shared/widgets/media/full_screen_typed_media_viewer.dart',
  ];

  int count(String source, String needle) => needle.allMatches(source).length;

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  List<String> importTargets(String source) => source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.startsWith('import '))
      .map(
        (line) => line
            .replaceFirst('import ', '')
            .replaceAll(';', '')
            .replaceAll("'", '')
            .replaceAll('"', '')
            .trim(),
      )
      .toList();

  test('received media egress call sites and wired transport baseline are exact', () {
    // ── 1. The controller is the single egress call site. ──────────────
    final controllerSrc = read(controllerPath);
    expect(
      count(controllerSrc, '.perform('),
      1,
      reason:
          'exactly one ReceivedMediaEgressService.perform call site may '
          'exist, inside the controller',
    );

    const controllerImportAllowlist = <String>{
      'dart:io',
      'package:uuid/uuid.dart',
      'package:flutter_app/core/media/group_media_integrity_policy.dart',
      'package:flutter_app/core/media/media_file_manager.dart',
      'package:flutter_app/core/media/media_owner_lane.dart',
      'package:flutter_app/core/media/received_media_egress.dart',
      'package:flutter_app/core/media/received_media_egress_service.dart',
      'package:flutter_app/features/conversation/domain/models/conversation_message.dart',
      'package:flutter_app/features/conversation/domain/models/media_attachment.dart',
      'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart',
      'private_media_action_eligibility.dart',
    };
    final controllerImports = importTargets(controllerSrc).toSet();
    expect(
      controllerImports.difference(controllerImportAllowlist),
      isEmpty,
      reason:
          'controller gained an import outside its allowlist — no bridge, '
          'P2P, send/delete use case, share picker, or raw gateway',
    );

    // The controller never bypasses the service for the raw gateway.
    for (final forbidden in const [
      'ReceivedMediaEgressGateway',
      'ReceivedMediaEgressChannel',
      'MethodChannel(',
      'ShareTargetPicker',
      'ShareBatch',
    ]) {
      expect(
        controllerSrc.contains(forbidden),
        isFalse,
        reason: 'controller must not reference $forbidden',
      );
    }

    // ── 2. Media-action UI files invoke callbacks/controller only. ─────
    for (final path in mediaActionUiFiles) {
      final source = read(path);
      for (final forbidden in const [
        'ReceivedMediaEgressService',
        'ReceivedMediaEgressGateway',
        'ReceivedMediaEgressChannel',
        '.perform(',
        'ShareTargetPicker',
        'ShareBatch',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: '$path must not reference $forbidden',
        );
      }

      // The full-screen viewer owns one reviewed native channel for the iOS
      // capture-protected image view. It is a render-control boundary
      // (`prepare`/`reveal`), not a received-media egress route. Keep that
      // exception exact while every other media-action UI file remains at
      // zero raw MethodChannel construction.
      final allowedMethodChannelCalls =
          path == 'lib/shared/widgets/media/full_screen_typed_media_viewer.dart'
          ? 1
          : 0;
      expect(
        count(source, 'MethodChannel('),
        allowedMethodChannelCalls,
        reason: '$path has an unreviewed native channel construction',
      );
      if (allowedMethodChannelCalls == 1) {
        expect(
          source.contains(
            "static const _viewType = 'mknoon/private_capture_protected_image';",
          ),
          isTrue,
          reason:
              'the sole viewer MethodChannel must remain scoped to the '
              'capture-protected render view',
        );
      }
    }

    // ── 3. Frozen wired transport call-site inventory. ──────────────────
    // Plan 232 adds one reviewed forwarding route. Plan 249 adds one
    // separately reviewed direct-only Batch Forward route that composes the
    // existing ordinary coordinator after atomic source qualification. Plan
    // 260 adds one state-observation-only injection into ConversationScreen
    // for OfflineMessageBanner; that widget reads currentState/stateStream and
    // owns no send or egress method. It also adds one E2E-gated bridge
    // availability check before its production-path outbox fixture runs; the
    // added reference is a null check, not a transport invocation. Plan 260's
    // typed upload-outcome adapter also wraps the former direct
    // widget.uploadMediaFn invocation without adding another upload route.
    // Save/Share/Info remain local-only Plan 231 actions. These exact counts
    // keep the exceptions bounded and prevent an unreviewed delivery seam.
    const wiredTransportBaseline = <String, int>{
      'widget.p2pService': 19,
      'widget.bridge': 31,
      'widget.sendChatMessageFn(': 1,
      'widget.editChatMessageFn(': 1,
      'widget.deleteMessageForMeFn(': 1,
      'widget.deleteMessageForEveryoneFn(': 1,
      'widget.sendVoiceMessageFn(': 1,
      'widget.uploadMediaFn(': 0,
      'widget.downloadMediaFn(': 2,
      'prepareEncryptedMediaArtifactFn': 4,
      '.sendMessageWithReply(': 0,
      '.storeInInbox(': 0,
      'ShareTargetPicker': 1,
      'ShareBatch': 1,
    };
    final wiredSrc = read(wiredPath);
    for (final entry in wiredTransportBaseline.entries) {
      expect(
        count(wiredSrc, entry.key),
        entry.value,
        reason:
            'conversation_wired.dart transport call-site inventory drifted '
            'for "${entry.key}" — media actions must not add or reuse a '
            'delivery seam outside the reviewed Plan 232 / Plan 249 routes',
      );
    }

    expect(
      count(wiredSrc, 'DefaultShareBatchDeliveryCoordinator('),
      1,
      reason: 'Plan 249 owns exactly one concrete ordinary coordinator',
    );
    expect(
      count(wiredSrc, 'DirectMediaBatchForwardDeliveryCoordinator('),
      1,
      reason: 'Plan 249 owns exactly one direct matrix coordinator',
    );

    // The wired layer routes media actions through the controller and
    // never calls the egress service or raw gateway itself.
    expect(
      wiredSrc.contains('ReceivedMediaActionController'),
      isTrue,
      reason: 'wired layer must construct/inject the 231 controller',
    );
    expect(
      count(wiredSrc, '.perform('),
      0,
      reason: 'wired layer must not call the egress service directly',
    );
    for (final forbidden in const [
      'ReceivedMediaEgressGateway',
      'ReceivedMediaEgressChannel',
    ]) {
      expect(
        wiredSrc.contains(forbidden),
        isFalse,
        reason: 'wired layer must not reference $forbidden',
      );
    }
  });
}
