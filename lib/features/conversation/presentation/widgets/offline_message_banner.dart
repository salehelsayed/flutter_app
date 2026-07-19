import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Service-authoritative offline notice shared by direct and group chats.
///
/// [P2PService.stateStream] is a broadcast stream and does not replay. Seed
/// from [P2PService.currentState] before subscribing so an initially-offline
/// conversation renders truthfully on its first frame.
class OfflineMessageBanner extends StatefulWidget {
  final P2PService p2pService;

  const OfflineMessageBanner({super.key, required this.p2pService});

  @override
  State<OfflineMessageBanner> createState() => _OfflineMessageBannerState();
}

class _OfflineMessageBannerState extends State<OfflineMessageBanner> {
  late BadgeReadinessState _badgeState;
  StreamSubscription<NodeState>? _subscription;

  @override
  void initState() {
    super.initState();
    _bind(widget.p2pService);
  }

  @override
  void didUpdateWidget(OfflineMessageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.p2pService, widget.p2pService)) return;
    _subscription?.cancel();
    _bind(widget.p2pService);
  }

  void _bind(P2PService service) {
    _badgeState = service.currentState.badgeReadinessState;
    _subscription = service.stateStream.listen(_onState);
  }

  void _onState(NodeState state) {
    final next = state.badgeReadinessState;
    if (!mounted || next == _badgeState) return;
    setState(() => _badgeState = next);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_badgeState != BadgeReadinessState.offline) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${l10n.offline_banner_title}. ${l10n.offline_banner_body}',
      child: Container(
        key: const ValueKey('offline-message-banner'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: readableColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: readableColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 20,
              color: readableColors.iconPrimary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.offline_banner_title,
                    style: TextStyle(
                      color: readableColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.offline_banner_body,
                    style: TextStyle(
                      color: readableColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
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
