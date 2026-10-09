import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/full_screen_call_access_prompt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// App-shell card that asks for Android's full-screen notification access
/// after a call rang without it (O4). Refreshes on start and on every resume,
/// so it hides as soon as the user grants the access in Settings.
///
/// Like [PushRegistrationHealthSurface], [child] keeps the same [Expanded]
/// parent whether or not the card shows, preserving the nested Navigator.
class FullScreenCallAccessSurface extends StatefulWidget {
  const FullScreenCallAccessSurface({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;

  /// Injected by tests; production uses the platform gateway.
  final FullScreenCallAccessPromptController? controller;

  @override
  State<FullScreenCallAccessSurface> createState() =>
      _FullScreenCallAccessSurfaceState();
}

class _FullScreenCallAccessSurfaceState
    extends State<FullScreenCallAccessSurface>
    with WidgetsBindingObserver {
  late final FullScreenCallAccessPromptController _controller =
      widget.controller ??
      FullScreenCallAccessPromptController(
        gateway: const PlatformFullScreenCallAccessGateway(),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller,
      builder: (context, visible, _) => Column(
        key: const ValueKey('full-screen-call-access-surface'),
        children: [
          if (visible)
            Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                bottom: false,
                child: _FullScreenCallAccessCard(
                  onOpenSettings: _controller.openSettings,
                  onDismiss: _controller.dismiss,
                ),
              ),
            ),
          Expanded(child: Semantics(container: true, child: widget.child)),
        ],
      ),
    );
  }
}

class _FullScreenCallAccessCard extends StatelessWidget {
  const _FullScreenCallAccessCard({
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final accent = readable.isLightSurface
        ? const Color(0xFF1B6E4A)
        : const Color(0xFF5FD39B);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('full-screen-call-access-card'),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.72)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.phone_in_talk_outlined,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.call_full_screen_access_title,
                    style: TextStyle(
                      color: readable.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.call_full_screen_access_body,
                    style: TextStyle(
                      color: readable.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('full-screen-call-access-open'),
                        onPressed: onOpenSettings,
                        style: TextButton.styleFrom(
                          foregroundColor: accent,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(l10n.call_full_screen_access_open),
                      ),
                      TextButton(
                        key: const ValueKey('full-screen-call-access-dismiss'),
                        onPressed: onDismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: readable.textSecondary,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(l10n.call_full_screen_access_dismiss),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
