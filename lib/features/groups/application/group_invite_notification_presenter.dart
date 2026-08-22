import 'dart:ui';

import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/group_invite_android_notification_identity.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

enum GroupInviteNotificationPresentationResult {
  shown,
  foregroundSuppressed,
  publicationOutcomeUnknown,
}

/// Presents a stored direct group invite when the app is not foreground-active.
///
/// Android direct and provider-fallback publications share one native
/// `(tag, id)` identity. Reusing that identity updates an existing card without
/// creating invite-ID history, so a valid multi-use re-invite can still alert.
final class GroupInviteNotificationPresenter {
  const GroupInviteNotificationPresenter({
    required this.notificationService,
    required this.appVisibility,
    this.locale,
  });

  final NotificationService notificationService;
  final AppVisibilitySuppressionReader appVisibility;
  final Locale? locale;

  Future<GroupInviteNotificationPresentationResult> present(
    PendingGroupInvite invite,
  ) async {
    if (await _isForegroundActive(invite)) {
      _emitSuppressed(invite, reason: 'foreground_active');
      return GroupInviteNotificationPresentationResult.foregroundSuppressed;
    }
    try {
      await _show(invite);
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_NOTIFICATION_SHOWN',
        details: _safeIdentityDetails(invite),
      );
      return GroupInviteNotificationPresentationResult.shown;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_NOTIFICATION_PUBLICATION_UNKNOWN',
        details: _safeIdentityDetails(
          invite,
          extra: {'errorType': error.runtimeType.toString()},
        ),
      );
      return GroupInviteNotificationPresentationResult
          .publicationOutcomeUnknown;
    }
  }

  Future<bool> _isForegroundActive(PendingGroupInvite invite) async {
    try {
      return (await appVisibility.evaluate(null)).isForegroundActive;
    } catch (error) {
      // Missing or stale visibility authority must fail toward notifying.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_NOTIFICATION_VISIBILITY_UNAVAILABLE',
        details: _safeIdentityDetails(
          invite,
          extra: {'errorType': error.runtimeType.toString()},
        ),
      );
      return false;
    }
  }

  Future<void> _show(PendingGroupInvite invite) {
    final localizations = notificationPreviewLocalizations(locale: locale);
    return notificationService.showNotification(
      title: invite.groupName,
      body: localizations.pending_invite_invited_by(invite.senderUsername),
      payload: NotificationRouteTarget.groupInvite(
        invite.groupId,
        messageId: invite.inviteId,
      ).toPayload(),
      androidNotificationId: groupInviteAndroidNotificationId,
      androidNotificationTag: groupInviteAndroidNotificationTag(
        groupId: invite.groupId,
        inviteId: invite.inviteId,
      ),
    );
  }

  void _emitSuppressed(PendingGroupInvite invite, {required String reason}) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_NOTIFICATION_SUPPRESSED',
      details: _safeIdentityDetails(invite, extra: {'reason': reason}),
    );
  }
}

Map<String, Object?> _safeIdentityDetails(
  PendingGroupInvite invite, {
  Map<String, Object?> extra = const {},
}) => <String, Object?>{
  'groupId': _safePrefix(invite.groupId),
  'inviteId': _safePrefix(invite.inviteId),
  ...extra,
};

String _safePrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
