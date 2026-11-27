import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_camera_tap_diagnostics.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_localizations.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';

/// Optional video presentation alongside independently owned audio controls.
/// All product and accessibility wording is supplied by the binding owner.
class CallVideoControls extends StatelessWidget {
  const CallVideoControls({
    super.key,
    required this.presentation,
    required this.audioControls,
    required this.onIntent,
    required this.controlsLabel,
    required this.statusLabel,
    required this.localCameraLabel,
    required this.remoteCameraLabel,
    required this.actionLabel,
    this.preAnswer = false,
    this.peerDisplayName,
  });

  final bool preAnswer;
  final String? peerDisplayName;
  final CallVideoPresentation presentation;
  final Widget audioControls;
  final ValueChanged<CallVideoIntent> onIntent;
  final String controlsLabel;
  final String Function(CallVideoStatus) statusLabel;
  final String Function(CallCameraState) localCameraLabel;
  final String Function(CallCameraState) remoteCameraLabel;
  final String Function(CallVideoAction) actionLabel;

  @override
  Widget build(BuildContext context) {
    if (!presentation.isVisible) return audioControls;
    if (preAnswer) {
      return _buildEntryControls(
        context,
        CallVideoLocalizations(AppLocalizations.of(context)!),
      );
    }
    final colors = context.backgroundReadableColors;
    final audio = audioControls;
    final l10n = AppLocalizations.of(context);
    final cardHeading = l10n == null ? null : _cardHeading(l10n);
    final cardActions = cardHeading == null
        ? const <CallVideoAction>[]
        : switch (presentation.status) {
            CallVideoStatus.incomingUpgrade
                when presentation.agreedMedia == CallMediaKind.audio =>
              const [
                CallVideoAction.declineUpgrade,
                CallVideoAction.acceptUpgrade,
              ],
            CallVideoStatus.outgoingUpgrade
                when presentation.agreedMedia == CallMediaKind.audio =>
              const [CallVideoAction.cancelUpgrade],
            _ => const <CallVideoAction>[],
          };
    if (presentation.acceptedMedia != null &&
        presentation.agreedMedia == CallMediaKind.video &&
        audio is CallControls) {
      final labels = CallVideoLocalizations(AppLocalizations.of(context)!);
      final cameraAction = presentation.localCamera == CallCameraState.off
          ? CallVideoAction.turnCameraOn
          : CallVideoAction.turnCameraOff;
      return Semantics(
        identifier: 'call_video_controls',
        container: true,
        explicitChildNodes: true,
        label: controlsLabel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cardHeading != null) ...[
              _card(
                cardHeading,
                cardActions,
                l10n!,
                colors,
                statusIdentifier: 'call_video_upgrade_status',
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              identifier: 'call_video_status',
              container: true,
              explicitChildNodes: true,
              liveRegion: true,
              label: statusLabel(presentation.status),
              child: audio.withVideoControls([
                _roundButton(
                  CallVideoAction.switchCamera,
                  labels.flipCaption,
                  colors,
                ),
                _roundButton(cameraAction, labels.cameraCaption, colors),
              ]),
            ),
            // A paused camera has two existing intents: resume and revoke.
            // Keep resume available in addition to the row's immediate stop.
            if (presentation.localCamera == CallCameraState.paused)
              _button(
                CallVideoAction.turnCameraOn,
                MediaQuery.sizeOf(context).width - 32,
                colors,
              ),
            // Camera-off and switching the agreed medium to audio are distinct.
            if (presentation.actions.contains(CallVideoAction.useAudioOnly))
              _button(
                CallVideoAction.useAudioOnly,
                MediaQuery.sizeOf(context).width - 32,
                colors,
              ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'call_video_controls',
          container: true,
          explicitChildNodes: true,
          label: controlsLabel,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cardHeading != null)
                  _card(cardHeading, cardActions, l10n!, colors)
                else
                  _state(
                    'call_video_status',
                    statusLabel(presentation.status),
                    colors.textPrimary,
                    primary: true,
                  ),
                const SizedBox(height: 6),
                _state(
                  'call_video_local_camera',
                  localCameraLabel(presentation.localCamera),
                  colors.textSecondary,
                ),
                _state(
                  'call_video_remote_camera',
                  remoteCameraLabel(presentation.remoteCamera),
                  colors.textSecondary,
                ),
                if (presentation.actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in presentation.actions)
                        if (!cardActions.contains(action))
                          _button(action, constraints.maxWidth, colors),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Optional video never owns audio availability or its callbacks.
        audioControls,
      ],
    );
  }

  String? _cardHeading(AppLocalizations l10n) {
    if (presentation.acceptedMedia == null) return null;
    final name = peerDisplayName?.trim();
    final hasName = name != null && name.isNotEmpty;
    switch (presentation.status) {
      case CallVideoStatus.incomingUpgrade
          when presentation.agreedMedia == CallMediaKind.audio:
        return hasName
            ? l10n.call_video_incoming_upgrade_from(name)
            : statusLabel(presentation.status);
      case CallVideoStatus.outgoingUpgrade
          when presentation.agreedMedia == CallMediaKind.audio:
        return hasName
            ? l10n.call_video_waiting_for_acceptance(name)
            : statusLabel(presentation.status);
      case CallVideoStatus.switchingToVideo:
        return l10n.call_video_switching;
      default:
        break;
    }
    // Pending includes permission, lease and PiP restoration work; it is not
    // sensor readiness, nor does agreement authorize starting the camera.
    if (presentation.isConnected &&
        !presentation.isReconnecting &&
        presentation.agreedMedia == CallMediaKind.video &&
        presentation.switchingTo == null &&
        presentation.videoActionPending &&
        presentation.localCamera != CallCameraState.on) {
      return l10n.call_video_camera_starting;
    }
    return null;
  }

  Widget _card(
    String heading,
    List<CallVideoAction> actions,
    AppLocalizations l10n,
    BackgroundReadableColors colors, {
    String statusIdentifier = 'call_video_status',
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.surfaceBorder),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: ValueKey(statusIdentifier),
            identifier: statusIdentifier,
            liveRegion: true,
            child: Text(
              heading,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  _button(
                    action,
                    constraints.maxWidth,
                    colors,
                    caption: action == CallVideoAction.declineUpgrade
                        ? l10n.mic_perm_not_now
                        : null,
                    wrapCaption: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildEntryControls(
    BuildContext context,
    CallVideoLocalizations labels,
  ) {
    final action = CallVideoAction.useAudioOnly;
    final enabled = presentation.isAvailable(action);
    void emit() {
      if (!context.mounted) return;
      final intent = presentation.intentFor(action);
      if (intent != null) onIntent(intent);
    }

    return Semantics(
      identifier: 'call_video_status',
      container: true,
      explicitChildNodes: true,
      label: labels.statusLabel(presentation.status),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: audioControls),
            if (presentation.actions.contains(action))
              Expanded(
                child: Semantics(
                  key: ValueKey(action.identifier),
                  identifier: action.identifier,
                  button: true,
                  enabled: enabled,
                  label: labels.actionLabel(action),
                  onTap: enabled ? emit : null,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? emit : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: labels.actionLabel(action),
                          onPressed: enabled ? emit : null,
                          icon: const Icon(Icons.call_outlined),
                          iconSize: 30,
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(68),
                            backgroundColor:
                                BackgroundReadableColors.dark.surfaceRaised,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          labels.actionLabel(action),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ).withPressFeedback(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(
    CallVideoAction action,
    String caption,
    BackgroundReadableColors colors,
  ) {
    final enabled = presentation.isAvailable(action);
    final camera = action != CallVideoAction.switchCamera;
    final off = camera && presentation.localCamera == CallCameraState.off;
    final label = actionLabel(action);
    void emit() {
      final intent = presentation.intentFor(action);
      if (intent != null) onIntent(intent);
    }

    return Semantics(
      key: ValueKey(action.identifier),
      identifier: action.identifier,
      container: true,
      button: true,
      enabled: enabled,
      toggled: camera ? presentation.localCamera == CallCameraState.on : null,
      label: camera
          ? '$label. ${localCameraLabel(presentation.localCamera)}'
          : label,
      onTap: enabled ? emit : null,
      excludeSemantics: true,
      child: _observeDisabledCameraTap(
        action,
        enabled,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? emit : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: label,
                onPressed: enabled ? emit : null,
                icon: Icon(
                  camera
                      ? (off
                            ? Icons.videocam_off_outlined
                            : Icons.videocam_outlined)
                      : Icons.cameraswitch_outlined,
                ),
                iconSize: 28,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(56),
                  backgroundColor: off ? Colors.white : colors.surfaceRaised,
                  foregroundColor: off
                      ? const Color(0xFF10141E)
                      : colors.iconPrimary,
                  disabledBackgroundColor: colors.disabledSurface,
                  disabledForegroundColor: colors.disabledForeground,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled
                      ? colors.textSecondary
                      : colors.disabledForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ).withPressFeedback(),
      ),
    );
  }

  Widget _state(
    String identifier,
    String text,
    Color color, {
    bool primary = false,
  }) => Semantics(
    key: ValueKey(identifier),
    identifier: identifier,
    container: true,
    liveRegion: true,
    label: text,
    excludeSemantics: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: primary ? 14 : 12,
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );

  Widget _button(
    CallVideoAction action,
    double maxWidth,
    BackgroundReadableColors colors, {
    String? caption,
    bool wrapCaption = false,
  }) {
    final enabled = presentation.isAvailable(action);
    final label = caption ?? actionLabel(action);
    final cameraAction =
        action == CallVideoAction.turnCameraOn ||
        action == CallVideoAction.turnCameraOff;
    void emit() {
      final intent = presentation.intentFor(action);
      if (intent != null) onIntent(intent);
    }

    return Semantics(
      key: ValueKey(action.identifier),
      identifier: action.identifier,
      container: true,
      button: true,
      enabled: enabled,
      toggled: cameraAction
          ? presentation.localCamera == CallCameraState.on
          : null,
      label: cameraAction
          ? '$label. ${localCameraLabel(presentation.localCamera)}'
          : label,
      onTap: enabled ? emit : null,
      excludeSemantics: true,
      child: _observeDisabledCameraTap(
        action,
        enabled,
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 48,
            minHeight: 48,
            maxWidth: maxWidth,
          ),
          child: OutlinedButton(
            onPressed: enabled ? emit : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              foregroundColor: colors.iconPrimary,
              disabledForegroundColor: colors.disabledForeground,
              backgroundColor: colors.surfaceRaised,
              disabledBackgroundColor: colors.disabledSurface,
              side: BorderSide(color: colors.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(action), size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: wrapCaption ? null : 2,
                    overflow: wrapCaption
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? colors.textPrimary
                          : colors.disabledForeground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _observeDisabledCameraTap(
    CallVideoAction action,
    bool enabled,
    Widget child,
  ) {
    if (!kDebugMode ||
        enabled ||
        !const {
          CallVideoAction.turnCameraOn,
          CallVideoAction.turnCameraOff,
          CallVideoAction.switchCamera,
        }.contains(action)) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      // Observe only: the button and its accessibility action stay disabled.
      onTap: () => reportCallCameraTap(
        action,
        CallCameraTapOutcome.refused,
        presentation.videoActionPending
            ? CallCameraTapReason.actionPending
            : CallCameraTapReason.notReady,
      ),
      child: child,
    );
  }

  IconData _icon(CallVideoAction action) => switch (action) {
    CallVideoAction.requestVideo => Icons.video_call_outlined,
    CallVideoAction.acceptUpgrade => Icons.check_circle_outline,
    CallVideoAction.declineUpgrade => Icons.call_outlined,
    CallVideoAction.cancelUpgrade => Icons.close,
    CallVideoAction.turnCameraOn => Icons.videocam_outlined,
    CallVideoAction.turnCameraOff => Icons.videocam_off_outlined,
    CallVideoAction.switchCamera => Icons.cameraswitch_outlined,
    CallVideoAction.useAudioOnly => Icons.call_outlined,
  };
}
