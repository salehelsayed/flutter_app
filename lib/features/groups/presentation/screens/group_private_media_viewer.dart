import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_private_media_viewer_controller.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

class GroupPrivateMediaViewer extends StatefulWidget {
  const GroupPrivateMediaViewer({
    super.key,
    required this.grant,
    required this.controller,
    this.capturePlatformOverride,
  });

  final GroupPrivateMediaViewerGrant grant;
  final GroupPrivateMediaViewerController controller;
  final TargetPlatform? capturePlatformOverride;

  @override
  State<GroupPrivateMediaViewer> createState() =>
      _GroupPrivateMediaViewerState();
}

class _GroupPrivateMediaViewerState extends State<GroupPrivateMediaViewer>
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
      onError: (_, _) => _coverAndClose(GroupPrivateMediaExitReason.capture),
      onDone: () => _coverAndClose(GroupPrivateMediaExitReason.capture),
    );
    final latched = widget.controller.latchedProtectionEvent;
    _failClosedBeforeFirstBuild = latched != null;
    if (latched != null) {
      _covered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onProtectionEvent(latched);
      });
    }
    widget.controller.armDisappearingDeadline(
      widget.grant,
      () => _close(GroupPrivateMediaExitReason.expiry),
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
        _coverAndClose(GroupPrivateMediaExitReason.capture);
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
        _coverAndClose(GroupPrivateMediaExitReason.background);
    }
  }

  void _coverAndClose(GroupPrivateMediaExitReason reason) {
    if (_closing) return;
    if (mounted) setState(() => _covered = true);
    unawaited(_close(reason));
  }

  Future<void> _close(GroupPrivateMediaExitReason reason) async {
    if (_closing) return;
    _closing = true;
    if (mounted && !_covered) setState(() => _covered = true);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
      if (reason == GroupPrivateMediaExitReason.background ||
          reason == GroupPrivateMediaExitReason.capture) {
        await widget.controller.revalidateForLifecycleEvent(widget.grant);
      }
    } catch (_) {}
    try {
      await widget.controller.settle(
        widget.grant,
        reason,
        releaseProtection: false,
      );
    } catch (_) {}

    final route = mounted ? ModalRoute.of(context) : null;
    try {
      if (mounted && route != null) {
        final navigator = Navigator.of(context);
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (route.isActive) {
          final completed = route.completed;
          navigator.removeRoute(route);
          await completed;
        }
      }
    } catch (_) {
      // Route disposal performs the final balanced release.
    } finally {
      if (!mounted || route == null || !route.isActive) {
        await widget.controller.releaseProtectionOwner(widget.grant);
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
        GroupPrivateMediaExitReason.dispose,
        releaseProtection: false,
      );
    } catch (_) {
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
          if (!didPop) _coverAndClose(GroupPrivateMediaExitReason.close);
        },
        child: const ColoredBox(
          key: ValueKey('group-private-media-cover'),
          color: Colors.black,
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final data = widget.grant.data;
    final item = MediaViewerItem(
      attachmentId: data.attachmentId,
      messageId: data.messageId,
      kind: data.kind,
      mime: 'application/octet-stream',
      owner: MediaOwnerLane.group,
      localPath: data.localPath,
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

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _coverAndClose(GroupPrivateMediaExitReason.close);
      },
      child: Stack(
        key: const ValueKey('group-private-media-viewer'),
        children: [
          FullScreenTypedMediaViewer(
            items: [item],
            privacyMinimized: true,
            onFirstRenderedFrame: () async {
              final accepted = await widget.controller.markFirstFrame(
                widget.grant,
              );
              if (!accepted) {
                _coverAndClose(GroupPrivateMediaExitReason.postFrameFailure);
              }
              return accepted;
            },
            onPreFrameFailure: () => _coverAndClose(
              GroupPrivateMediaExitReason.preFrameDecodeFailure,
            ),
            onPostFrameFailure: () =>
                _coverAndClose(GroupPrivateMediaExitReason.postFrameFailure),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.group_private_media_notification_body,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    captureLimitCopy,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    l10n.private_media_general_capture_limit,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (_covered)
            const Positioned.fill(
              child: ColoredBox(
                key: ValueKey('group-private-media-cover'),
                color: Colors.black,
              ),
            ),
        ],
      ),
    );
  }
}
