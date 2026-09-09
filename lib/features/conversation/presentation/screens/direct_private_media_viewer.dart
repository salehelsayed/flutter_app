import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

typedef DirectPrivateMediaSafeActionHandler =
    Future<void> Function(DirectPrivateMediaAction action);

class DirectPrivateMediaViewer extends StatefulWidget {
  const DirectPrivateMediaViewer({
    super.key,
    required this.grant,
    required this.controller,
    this.onSafeAction,
    this.capturePlatformOverride,
  });

  final DirectPrivateMediaViewerGrant grant;
  final DirectPrivateMediaViewerController controller;
  final DirectPrivateMediaSafeActionHandler? onSafeAction;
  final TargetPlatform? capturePlatformOverride;

  @override
  State<DirectPrivateMediaViewer> createState() =>
      _DirectPrivateMediaViewerState();
}

class _DirectPrivateMediaViewerState extends State<DirectPrivateMediaViewer>
    with WidgetsBindingObserver {
  StreamSubscription<PrivateMediaProtectionEvent>? _eventSubscription;
  late final bool _failClosedBeforeFirstBuild;
  bool _covered = false;
  bool _closing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _eventSubscription = widget.controller.protectionEvents.listen(
      _onProtectionEvent,
      onError: (_, _) => _coverAndClose(DirectPrivateMediaExitReason.capture),
      onDone: () => _coverAndClose(DirectPrivateMediaExitReason.capture),
    );
    final latched = widget.controller.latchedProtectionEvent;
    _failClosedBeforeFirstBuild = latched != null;
    if (latched != null) {
      // A critical incident that predates route subscription must never allow
      // the local path to reach a byte-bearing viewer, even under an opaque
      // overlay. Render only the fail-closed surface until dismissal.
      _covered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onProtectionEvent(latched);
      });
    }
    widget.controller.armDisappearingDeadline(
      widget.grant,
      () => _close(DirectPrivateMediaExitReason.expiry),
    );
  }

  void _onProtectionEvent(PrivateMediaProtectionEvent event) {
    switch (event) {
      case PrivateMediaProtectionEvent.captureStopped:
      case PrivateMediaProtectionEvent.foreground:
        return;
      case PrivateMediaProtectionEvent.screenshot:
      case PrivateMediaProtectionEvent.captureStarted:
      case PrivateMediaProtectionEvent.inactive:
      case PrivateMediaProtectionEvent.background:
      case PrivateMediaProtectionEvent.channelFailure:
        _coverAndClose(DirectPrivateMediaExitReason.capture);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _coverAndClose(DirectPrivateMediaExitReason.background);
    }
  }

  void _coverAndClose(DirectPrivateMediaExitReason reason) {
    if (_closing) return;
    if (mounted) setState(() => _covered = true);
    unawaited(_close(reason));
  }

  Future<void> _close(DirectPrivateMediaExitReason reason) async {
    if (_closing) return;
    _closing = true;
    if (mounted && !_covered) setState(() => _covered = true);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
      if (reason == DirectPrivateMediaExitReason.background ||
          reason == DirectPrivateMediaExitReason.capture) {
        await widget.controller.revalidateForLifecycleEvent(widget.grant);
      }
    } catch (_) {
      // Protection incidents remain fail-closed even when persistence cannot
      // be re-read. The covered route must still be removed before native
      // protection ownership is released.
    }
    try {
      await widget.controller.settle(
        widget.grant,
        reason,
        releaseProtection: false,
      );
    } catch (_) {
      // Best-effort lifecycle settlement must not strand a byte-bearing route.
    }

    final route = mounted ? ModalRoute.of(context) : null;
    try {
      if (mounted && route != null) {
        final navigator = Navigator.of(context);
        setState(() => _allowPop = true);
        // Publish the updated PopScope while the black cover is still native-
        // protected. Calling maybePop in the same build would observe the old
        // canPop value and could strand the grant.
        await WidgetsBinding.instance.endOfFrame;

        final routesAbove = <TransitionRoute<dynamic>>{};
        navigator.popUntil((candidate) {
          if (identical(candidate, route)) return true;
          if (candidate is TransitionRoute<dynamic>) routesAbove.add(candidate);
          return false;
        });
        for (final coveringRoute in routesAbove) {
          await coveringRoute.completed;
        }

        if (route.isActive) {
          final routeCompleted = route.completed;
          navigator.removeRoute(route);
          await routeCompleted;
        }
      }
    } catch (_) {
      // Never trade an uncertain still-mounted private route for early native
      // release. A later route disposal performs the final balanced release.
    } finally {
      if (!mounted || route == null || !route.isActive) {
        await widget.controller.releaseProtectionOwner(widget.grant);
      }
    }
  }

  Future<void> _dispatchSafe(DirectPrivateMediaAction action) async {
    final callback = widget.onSafeAction;
    if (callback == null || _closing) return;
    if (action == DirectPrivateMediaAction.deleteForMe && mounted) {
      setState(() => _covered = true);
    }
    final dispatched = await widget.controller.dispatchSafeAction(
      widget.grant,
      action,
      () => callback(action),
    );
    if (action == DirectPrivateMediaAction.deleteForMe) {
      if (dispatched) {
        await _close(DirectPrivateMediaExitReason.close);
      } else if (mounted) {
        setState(() => _covered = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    if (!widget.grant.protectionReleased) {
      unawaited(_settleAfterRouteDisposal());
    }
    super.dispose();
  }

  Future<void> _settleAfterRouteDisposal() async {
    try {
      await widget.controller.settle(
        widget.grant,
        DirectPrivateMediaExitReason.dispose,
        releaseProtection: false,
      );
    } catch (_) {
      // The route is already gone, so native ownership must still be balanced.
    } finally {
      await widget.controller.releaseProtectionOwner(widget.grant);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failClosedBeforeFirstBuild) {
      return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _coverAndClose(DirectPrivateMediaExitReason.close);
        },
        child: const ColoredBox(
          key: ValueKey('private-media-cover'),
          color: Colors.black,
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final grant = widget.grant;
    final item = MediaViewerItem(
      attachmentId: grant.identity.attachmentId,
      messageId: grant.identity.messageId,
      kind: grant.kind,
      mime: 'application/octet-stream',
      owner: MediaOwnerLane.direct,
      localPath: grant.localPath,
      canEnterPictureInPicture: false,
      protection: const MediaViewerProtection(isProtected: true),
    );
    final isIosCapturePlatform =
        widget.capturePlatformOverride == TargetPlatform.iOS ||
        (widget.capturePlatformOverride == null && Platform.isIOS);
    final captureLimitCopy = isIosCapturePlatform
        ? item.kind == MediaViewerKind.video
              ? l10n.private_media_ios_capture_limit
              : l10n.private_media_ios_image_capture_limit
        : l10n.private_media_android_capture_limit;
    final minimalViewerChrome =
        grant.mode == PrivateMediaMode.viewOnce &&
        grant.kind == MediaViewerKind.image;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _coverAndClose(DirectPrivateMediaExitReason.close);
      },
      // The viewer route hosts raw Text overlays; without a Material ancestor
      // they render with the framework's yellow-underline fallback style.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          key: const ValueKey('direct-private-media-viewer'),
          children: [
            FullScreenTypedMediaViewer(
              items: [item],
              privacyMinimized: true,
              onFirstRenderedFrame: () async {
                final accepted = await widget.controller.markFirstFrame(grant);
                if (!accepted) {
                  _coverAndClose(DirectPrivateMediaExitReason.postFrameFailure);
                }
                return accepted;
              },
              onPreFrameFailure: () => _coverAndClose(
                DirectPrivateMediaExitReason.preFrameDecodeFailure,
              ),
              onPostFrameFailure: () =>
                  _coverAndClose(DirectPrivateMediaExitReason.postFrameFailure),
              onBackRequested: () async {
                await Navigator.of(context).maybePop();
              },
            ),
            if (!minimalViewerChrome)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.private_media_notification_body,
                        key: const ValueKey('private-media-generic-copy'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        captureLimitCopy,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      if (widget.onSafeAction != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PrivateActionButton(
                              action: DirectPrivateMediaAction.reply,
                              icon: Icons.reply_rounded,
                              tooltip: l10n.media_viewer_action_reply,
                              onPressed: _dispatchSafe,
                            ),
                            _PrivateActionButton(
                              action: DirectPrivateMediaAction.info,
                              icon: Icons.info_outline_rounded,
                              tooltip: l10n.media_viewer_action_info,
                              onPressed: _dispatchSafe,
                            ),
                            _PrivateActionButton(
                              action: DirectPrivateMediaAction.deleteForMe,
                              icon: Icons.delete_outline_rounded,
                              tooltip: l10n.media_viewer_action_delete,
                              onPressed: _dispatchSafe,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_covered)
              const Positioned.fill(
                child: ColoredBox(
                  key: ValueKey('private-media-cover'),
                  color: Colors.black,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrivateActionButton extends StatelessWidget {
  const _PrivateActionButton({
    required this.action,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final DirectPrivateMediaAction action;
  final IconData icon;
  final String tooltip;
  final Future<void> Function(DirectPrivateMediaAction action) onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('private-action-${action.name}'),
    icon: Icon(icon, color: Colors.white),
    tooltip: tooltip,
    onPressed: () => onPressed(action),
  );
}

class DirectPrivateMediaTerminalPlaceholder extends StatelessWidget {
  const DirectPrivateMediaTerminalPlaceholder({
    super.key,
    required this.state,
    required this.mode,
    this.direction = PrivateMediaDirection.incoming,
    this.onReply,
    this.onInfo,
    this.onDelete,
  });

  final PrivateMediaLifecycleState state;
  final PrivateMediaMode mode;
  final PrivateMediaDirection direction;
  final VoidCallback? onReply;
  final VoidCallback? onInfo;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final senderConsumed =
        direction == PrivateMediaDirection.outgoing &&
        state == PrivateMediaLifecycleState.consumed;
    final copy = state == PrivateMediaLifecycleState.consumed
        ? senderConsumed
              ? l10n.private_media_sender_consumed
              : l10n.private_media_consumed
        : l10n.private_media_expired;
    if (mode == PrivateMediaMode.viewOnce &&
        state == PrivateMediaLifecycleState.consumed) {
      final photoLabel = l10n.shared_media_kind_photo;
      return Semantics(
        label: '$photoLabel. $copy',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('private-terminal-${state.name}'),
          padding: const EdgeInsets.all(12),
          child: Row(
            key: const ValueKey('private-terminal-view-once-consumed-summary'),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.visibility_off_outlined),
              const SizedBox(width: 8),
              Text(photoLabel),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: copy,
      child: Container(
        key: ValueKey('private-terminal-${state.name}'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined),
            const SizedBox(height: 6),
            if (senderConsumed) ...[
              Text(
                l10n.private_media_notification_body,
                key: const ValueKey('private-media-terminal-generic-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
            ],
            Text(copy, textAlign: TextAlign.center),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('private-action-reply'),
                  tooltip: l10n.media_viewer_action_reply,
                  onPressed: onReply,
                  icon: const Icon(Icons.reply_rounded),
                ),
                IconButton(
                  key: const ValueKey('private-action-info'),
                  tooltip: l10n.media_viewer_action_info,
                  onPressed: onInfo ?? () {},
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                IconButton(
                  key: const ValueKey('private-action-deleteForMe'),
                  tooltip: l10n.media_viewer_action_delete,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Human-readable label for a private policy mode, matching the composer
/// selector's vocabulary so the bubble and the compose chip agree.
String privateMediaModeLabel(AppLocalizations l10n, PrivateMediaPolicy policy) {
  return switch (policy.mode) {
    PrivateMediaMode.protected => l10n.private_media_protected,
    PrivateMediaMode.viewOnce => l10n.private_media_view_once,
    PrivateMediaMode.disappearing when policy.durationSeconds == 3600 =>
      l10n.private_media_disappearing_1h,
    PrivateMediaMode.disappearing when policy.durationSeconds == 86400 =>
      l10n.private_media_disappearing_1d,
    PrivateMediaMode.disappearing => l10n.private_media_disappearing_7d,
    _ => l10n.private_media_ordinary,
  };
}

/// Privacy-safe card chrome shared by direct and group private-media slots.
/// The visual is intentionally icon/gradient-only: private pixels never enter
/// this widget through a path, provider, attachment, or byte payload.
class PrivateMediaVisualCard extends StatelessWidget {
  PrivateMediaVisualCard({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    this.titleKey,
    this.action,
    this.onTap,
    this.opening = false,
    this.tapLabel,
    this.openingLabel,
  }) : assert(
         onTap == null || (tapLabel != null && tapLabel.trim().isNotEmpty),
         'tapLabel must be non-empty when onTap is provided.',
       ),
       assert(
         onTap == null ||
             (openingLabel != null && openingLabel.trim().isNotEmpty),
         'openingLabel must be non-empty when onTap is provided.',
       );

  final String? title;
  final String? body;
  final IconData icon;
  final Key? titleKey;
  final Widget? action;
  final VoidCallback? onTap;
  final bool opening;
  final String? tapLabel;
  final String? openingLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onTap == null)
            Container(
              key: const ValueKey('private-media-card-visual'),
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.primary.withValues(alpha: 0.30),
                    colors.tertiary.withValues(alpha: 0.14),
                    colors.surfaceContainerHighest.withValues(alpha: 0.78),
                  ],
                ),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Center(
                child: Icon(icon, size: 38, color: colors.onSurfaceVariant),
              ),
            )
          else
            _PrivateMediaTappableTile(
              icon: icon,
              onTap: onTap!,
              opening: opening,
              tapLabel: tapLabel!,
              openingLabel: openingLabel!,
            ),
          const SizedBox(height: 10),
          if (title != null) ...[
            if (onTap == null)
              Text(
                title!,
                key: titleKey,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              )
            else
              ExcludeSemantics(
                child: Text(
                  title!,
                  key: titleKey,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 4),
          ],
          if (body != null)
            Text(body!, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class _PrivateMediaTappableTile extends StatefulWidget {
  const _PrivateMediaTappableTile({
    required this.icon,
    required this.onTap,
    required this.opening,
    required this.tapLabel,
    required this.openingLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool opening;
  final String tapLabel;
  final String openingLabel;

  @override
  State<_PrivateMediaTappableTile> createState() =>
      _PrivateMediaTappableTileState();
}

class _PrivateMediaTappableTileState extends State<_PrivateMediaTappableTile> {
  bool _pressed = false;
  int? _activePointer;
  Offset? _pointerDownPosition;

  @override
  void didUpdateWidget(_PrivateMediaTappableTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opening) {
      _pressed = false;
      _activePointer = null;
      _pointerDownPosition = null;
    }
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _setPressed(true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || !_pressed) return;
    final downPosition = _pointerDownPosition;
    if (downPosition != null &&
        (event.position - downPosition).distance > kTouchSlop) {
      _setPressed(false);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pointerDownPosition = null;
    _setPressed(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pointerEnabled = !widget.opening;

    return Semantics(
      container: true,
      excludeSemantics: true,
      enabled: pointerEnabled,
      button: true,
      label: widget.tapLabel,
      value: widget.opening ? widget.openingLabel : null,
      onTap: pointerEnabled ? widget.onTap : null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: pointerEnabled ? _handlePointerDown : null,
        onPointerMove: pointerEnabled ? _handlePointerMove : null,
        onPointerUp: pointerEnabled ? _handlePointerEnd : null,
        onPointerCancel: pointerEnabled ? _handlePointerEnd : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: pointerEnabled ? widget.onTap : null,
          onTapDown: pointerEnabled ? (_) => _setPressed(true) : null,
          onTapUp: pointerEnabled ? (_) => _setPressed(false) : null,
          onTapCancel: pointerEnabled ? () => _setPressed(false) : null,
          child: AnimatedScale(
            scale: pointerEnabled && _pressed ? 0.975 : 1,
            duration: const Duration(milliseconds: 120),
            child: Opacity(
              opacity: widget.opening ? 0.62 : 1,
              child: Container(
                key: const ValueKey('private-media-card-visual'),
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: 0.30),
                      colors.tertiary.withValues(alpha: 0.14),
                      colors.surfaceContainerHighest.withValues(alpha: 0.78),
                    ],
                  ),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Center(
                  child: widget.opening
                      ? const SizedBox.square(
                          dimension: 38,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Icon(
                          widget.icon,
                          size: 38,
                          color: colors.onSurfaceVariant,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool privateMediaCardUsesVideoCopy(PrivateMediaAttachmentKind kind) =>
    kind == PrivateMediaAttachmentKind.video;

String privateMediaDurationLabel(AppLocalizations l10n, int? durationSeconds) {
  return switch (durationSeconds) {
    3600 => l10n.private_media_duration_1h,
    86400 => l10n.private_media_duration_1d,
    _ => l10n.private_media_duration_7d,
  };
}

String privateMediaCardTitle(
  AppLocalizations l10n,
  PrivateMediaPolicy policy,
  PrivateMediaAttachmentKind kind,
) {
  final video = privateMediaCardUsesVideoCopy(kind);
  return switch (policy.mode) {
    PrivateMediaMode.viewOnce =>
      video
          ? l10n.private_media_card_title_view_once_video
          : l10n.private_media_card_title_view_once_photo,
    PrivateMediaMode.disappearing =>
      video
          ? l10n.private_media_card_title_expiry_video(
              privateMediaDurationLabel(l10n, policy.durationSeconds),
            )
          : l10n.private_media_card_title_expiry_photo(
              privateMediaDurationLabel(l10n, policy.durationSeconds),
            ),
    _ =>
      video
          ? l10n.private_media_card_title_protected_video
          : l10n.private_media_card_title_protected_photo,
  };
}

IconData privateMediaCardIcon(PrivateMediaPolicy policy) {
  return switch (policy.mode) {
    PrivateMediaMode.viewOnce => Icons.looks_one_outlined,
    PrivateMediaMode.disappearing => Icons.timer_outlined,
    _ => Icons.lock_outline_rounded,
  };
}

class DirectPrivateMediaOpenPlaceholder extends StatelessWidget {
  const DirectPrivateMediaOpenPlaceholder({
    super.key,
    required this.onOpen,
    required this.contactDisplayName,
    this.opening = false,
    this.policy,
    this.kind = PrivateMediaAttachmentKind.image,
  });

  final VoidCallback? onOpen;
  final String contactDisplayName;
  final bool opening;
  final PrivateMediaPolicy? policy;
  final PrivateMediaAttachmentKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labeledPolicy = policy;
    final tapTileKind =
        kind == PrivateMediaAttachmentKind.image ||
        kind == PrivateMediaAttachmentKind.video;
    final tapTileMode =
        labeledPolicy?.mode == PrivateMediaMode.protected ||
        labeledPolicy?.mode == PrivateMediaMode.disappearing ||
        labeledPolicy?.mode == PrivateMediaMode.viewOnce;
    final usesTapTile = tapTileKind && tapTileMode && onOpen != null;
    final minimalViewOnceImage =
        usesTapTile &&
        labeledPolicy?.mode == PrivateMediaMode.viewOnce &&
        kind == PrivateMediaAttachmentKind.image;
    final actionLabel = labeledPolicy?.mode == PrivateMediaMode.viewOnce
        ? (privateMediaCardUsesVideoCopy(kind)
              ? l10n.private_media_view_video
              : l10n.private_media_view_photo)
        : (privateMediaCardUsesVideoCopy(kind)
              ? l10n.private_media_open_video
              : l10n.private_media_open_photo);
    final button = FilledButton.tonalIcon(
      key: const ValueKey('private-media-open'),
      onPressed: opening ? null : onOpen,
      icon: opening
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lock_outline_rounded),
      label: Text(
        opening
            ? l10n.private_media_opening
            : labeledPolicy == null
            ? l10n.private_media_open
            : actionLabel,
      ),
    );
    if (labeledPolicy == null || !labeledPolicy.isPrivate) {
      return button;
    }
    final title = privateMediaCardTitle(l10n, labeledPolicy, kind);
    final body = switch (labeledPolicy.mode) {
      PrivateMediaMode.protected || PrivateMediaMode.disappearing
          when tapTileKind =>
        l10n.private_media_protected_body_received_compact(contactDisplayName),
      PrivateMediaMode.protected || PrivateMediaMode.disappearing =>
        l10n.private_media_protected_body_received(contactDisplayName),
      PrivateMediaMode.viewOnce => l10n.private_media_view_once_body_received,
      _ => null,
    };
    final card = PrivateMediaVisualCard(
      title:
          minimalViewOnceImage ||
              (usesTapTile && labeledPolicy.mode == PrivateMediaMode.protected)
          ? null
          : title,
      titleKey: const ValueKey('private-media-mode-label'),
      body: minimalViewOnceImage
          ? null
          : body ?? privateMediaModeLabel(l10n, labeledPolicy),
      icon: privateMediaCardIcon(labeledPolicy),
      action: usesTapTile ? null : button,
      onTap: usesTapTile ? onOpen : null,
      opening: opening,
      tapLabel: usesTapTile ? title : null,
      openingLabel: usesTapTile ? l10n.private_media_opening : null,
    );
    if (usesTapTile) return card;
    return Semantics(label: title, child: card);
  }
}

/// Sender-side bubble content for an outgoing private message. Protected and
/// view-once senders keep an Open affordance; the promise beside it forks by
/// mode — protected re-opens without limit, view-once keeps its one more look.
/// Disappearing shows the mode alone.
class DirectPrivateMediaOutgoingPlaceholder extends StatelessWidget {
  const DirectPrivateMediaOutgoingPlaceholder({
    super.key,
    required this.policy,
    required this.contactDisplayName,
    this.kind = PrivateMediaAttachmentKind.image,
    this.onOpen,
    this.opening = false,
    this.localMediaAvailable = true,
  });

  final PrivateMediaPolicy policy;
  final String contactDisplayName;
  final PrivateMediaAttachmentKind kind;
  final VoidCallback? onOpen;
  final bool opening;
  final bool localMediaAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = privateMediaCardTitle(l10n, policy, kind);
    final minimalViewOnceImage =
        policy.mode == PrivateMediaMode.viewOnce &&
        kind == PrivateMediaAttachmentKind.image &&
        localMediaAvailable &&
        onOpen != null;
    if (minimalViewOnceImage) {
      return KeyedSubtree(
        key: const ValueKey('private-media-outgoing'),
        child: PrivateMediaVisualCard(
          title: null,
          body: null,
          icon: privateMediaCardIcon(policy),
          onTap: onOpen,
          opening: opening,
          tapLabel: label,
          openingLabel: l10n.private_media_opening,
        ),
      );
    }
    final supportsSenderReopen =
        policy.mode == PrivateMediaMode.protected ||
        policy.mode == PrivateMediaMode.viewOnce;
    final reopenPromise = policy.mode == PrivateMediaMode.protected
        ? l10n.private_media_disclosure_reopen_protected
        : l10n.private_media_disclosure_reopen;
    final body = !localMediaAvailable
        ? l10n.private_media_sender_local_missing_body
        : supportsSenderReopen
        ? '${l10n.private_media_outgoing_body(contactDisplayName)}\n'
              '$reopenPromise'
        : l10n.private_media_outgoing_body(contactDisplayName);
    final action = supportsSenderReopen && localMediaAvailable && onOpen != null
        ? FilledButton.tonalIcon(
            key: const ValueKey('private-media-open'),
            onPressed: opening ? null : onOpen,
            icon: opening
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility_outlined),
            label: Text(
              opening ? l10n.private_media_opening : l10n.private_media_open,
            ),
          )
        : null;
    return Semantics(
      label: label,
      child: KeyedSubtree(
        key: const ValueKey('private-media-outgoing'),
        child: PrivateMediaVisualCard(
          title: label,
          titleKey: const ValueKey('private-media-mode-label'),
          body: body,
          icon: privateMediaCardIcon(policy),
          action: action,
        ),
      ),
    );
  }
}

/// Typed private-open failure presentation. Safe availability copy is shown
/// only when settlement proved the exact row rolled back; every other
/// disposition remains deliberately non-committal.
class DirectPrivateMediaOpenFailurePlaceholder extends StatelessWidget {
  const DirectPrivateMediaOpenFailurePlaceholder({
    super.key,
    required this.direction,
    required this.kind,
    required this.settleResult,
    required this.canRetry,
    this.localMediaMissing = false,
    this.onRetry,
  });

  final PrivateMediaDirection direction;
  final PrivateMediaAttachmentKind kind;
  final DirectPrivateMediaSettleResult? settleResult;
  final bool canRetry;
  final bool localMediaMissing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = privateMediaCardUsesVideoCopy(kind)
        ? l10n.private_media_open_failed_title_video
        : l10n.private_media_open_failed_title_photo;
    final rolledBack =
        settleResult?.disposition ==
        DirectPrivateMediaSettleDisposition.rolledBackAvailable;
    final String body;
    if (localMediaMissing && direction == PrivateMediaDirection.outgoing) {
      body = l10n.private_media_sender_local_missing_body;
    } else if (rolledBack) {
      body = direction == PrivateMediaDirection.incoming
          ? l10n.private_media_open_failed_view_safe
          : l10n.private_media_open_failed_reopen_safe;
    } else {
      body = l10n.private_media_notification_body;
    }
    final retryEnabled = canRetry && onRetry != null && !localMediaMissing;
    return PrivateMediaVisualCard(
      key: const ValueKey('private-media-open-failure'),
      title: title,
      body: body,
      icon: Icons.warning_amber_rounded,
      action: retryEnabled
          ? FilledButton.tonal(
              key: const ValueKey('private-media-try-again'),
              onPressed: onRetry,
              child: Text(l10n.private_media_try_again),
            )
          : null,
    );
  }
}

class DirectPrivateMediaUnsupportedPlaceholder extends StatelessWidget {
  const DirectPrivateMediaUnsupportedPlaceholder({
    super.key,
    this.requiresUpdate = true,
    this.onReply,
    this.onInfo,
    this.onDelete,
  });

  /// Only a newer wire policy indicates that updating may help. Verification
  /// failures and malformed current-version metadata still fail closed.
  final bool requiresUpdate;
  final VoidCallback? onReply;
  final VoidCallback? onInfo;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: const ValueKey('private-media-unsupported'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            requiresUpdate
                ? Icons.system_update_alt_rounded
                : Icons.error_outline_rounded,
          ),
          const SizedBox(height: 6),
          Text(
            requiresUpdate
                ? l10n.private_media_unsupported
                : l10n.media_could_not_verify,
            textAlign: TextAlign.center,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('private-action-reply'),
                tooltip: l10n.media_viewer_action_reply,
                onPressed: onReply,
                icon: const Icon(Icons.reply_rounded),
              ),
              IconButton(
                key: const ValueKey('private-action-info'),
                tooltip: l10n.media_viewer_action_info,
                onPressed: onInfo ?? () {},
                icon: const Icon(Icons.info_outline_rounded),
              ),
              IconButton(
                key: const ValueKey('private-action-deleteForMe'),
                tooltip: l10n.media_viewer_action_delete,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
