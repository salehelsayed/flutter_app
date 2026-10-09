import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import '../../../../core/services/p2p_service.dart';
import '../../../../core/utils/flow_event_emitter.dart';
import '../../domain/models/node_state.dart';

/// Legacy relay-health helper derived from [NodeState].
///
/// Kept for existing transport benchmarks and integration tests until the
/// heavier Session 3 acceptance surfaces migrate to the Phase 6 contract.
enum ConnectionHealth {
  /// Node is started and has circuit relay addresses.
  online,

  /// Node is started but has no circuit relay addresses.
  degraded,

  /// Node is not started.
  offline,
}

enum ConnectionStatusIndicatorStyle { capsule, plain }

/// Derives relay-only [ConnectionHealth] from a [NodeState].
ConnectionHealth healthFromState(NodeState state) {
  if (!state.isStarted) return ConnectionHealth.offline;
  if (state.relayState == 'online' || state.circuitAddresses.isNotEmpty) {
    return ConnectionHealth.online;
  }
  return ConnectionHealth.degraded;
}

bool _isReadyBadgeState(BadgeReadinessState state) {
  return state == BadgeReadinessState.online ||
      state == BadgeReadinessState.onlineDotted ||
      state == BadgeReadinessState.onlineDirect;
}

ConnectionHealth _legacyHealthForBadgeState(BadgeReadinessState state) {
  return switch (state) {
    BadgeReadinessState.offline => ConnectionHealth.offline,
    BadgeReadinessState.connecting => ConnectionHealth.degraded,
    BadgeReadinessState.online ||
    BadgeReadinessState.onlineDotted ||
    BadgeReadinessState.onlineDirect => ConnectionHealth.online,
  };
}

String _labelForBadgeState(BadgeReadinessState state, AppLocalizations l10n) {
  return switch (state) {
    BadgeReadinessState.offline => l10n.connection_offline,
    BadgeReadinessState.connecting => l10n.connection_connecting,
    BadgeReadinessState.online => l10n.connection_online,
    BadgeReadinessState.onlineDotted => '${l10n.connection_online}.',
    // FDC-14: a distinct, non-linear cue (NOT a third punctuation-only variant
    // on the relay-dot ladder — directly-reachable is decoupled from relay).
    BadgeReadinessState.onlineDirect => '${l10n.connection_online} ✦',
  };
}

String _semanticsLabelForBadgeState(
  BadgeReadinessState state,
  AppLocalizations l10n,
) {
  return switch (state) {
    BadgeReadinessState.offline => l10n.connection_semantics_offline,
    BadgeReadinessState.connecting => l10n.connection_semantics_connecting,
    BadgeReadinessState.online => l10n.connection_semantics_online,
    BadgeReadinessState.onlineDotted => l10n.connection_semantics_reserved,
    // FDC-14: the binding distinctness lives here (a screen reader must hear
    // "directly reachable", not the relay-reservation phrasing).
    BadgeReadinessState.onlineDirect => l10n.connection_semantics_direct,
  };
}

/// A compact indicator showing the P2P connection status.
///
/// Displays one of five states from the service-owned Phase 6 contract:
/// - "Offline"
/// - "Connecting"
/// - "Online"
/// - "Online." (also relay-reserved)
/// - "Online ✦" (FDC-14: also directly reachable)
class ConnectionStatusIndicator extends StatefulWidget {
  /// Largest text scale the pill follows; see the build method.
  static const double maxTextScaleFactor = 1.5;

  final P2PService? p2pService;
  final BadgeReadinessState? previewState;
  final int previewConnectionCount;
  final ConnectionStatusIndicatorStyle style;

  const ConnectionStatusIndicator({
    super.key,
    required P2PService this.p2pService,
    this.style = ConnectionStatusIndicatorStyle.capsule,
  }) : previewState = null,
       previewConnectionCount = 0;

  const ConnectionStatusIndicator.preview({
    super.key,
    required BadgeReadinessState state,
    int connectionCount = 0,
    this.style = ConnectionStatusIndicatorStyle.capsule,
  }) : p2pService = null,
       previewState = state,
       previewConnectionCount = connectionCount;

  @override
  State<ConnectionStatusIndicator> createState() =>
      _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator> {
  late BadgeReadinessState _displayedBadgeState;
  late int _connectionCount;
  StreamSubscription<NodeState>? _sub;

  @override
  void initState() {
    super.initState();
    _bindWidget();
  }

  void _bindWidget() {
    final previewState = widget.previewState;
    if (previewState != null) {
      _displayedBadgeState = previewState;
      _connectionCount = widget.previewConnectionCount;
      return;
    }
    final service = widget.p2pService!;
    final initial = service.currentState;
    _displayedBadgeState = initial.badgeReadinessState;
    _connectionCount = initial.connections.length;
    _sub = service.stateStream.listen(_onState);
  }

  @override
  void didUpdateWidget(covariant ConnectionStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.p2pService == widget.p2pService &&
        oldWidget.previewState == widget.previewState &&
        oldWidget.previewConnectionCount == widget.previewConnectionCount) {
      return;
    }
    _sub?.cancel();
    _sub = null;
    _bindWidget();
  }

  void _onState(NodeState state) {
    final incoming = state.badgeReadinessState;
    final count = state.connections.length;

    if (incoming == _displayedBadgeState) {
      if (count != _connectionCount) {
        setState(() => _connectionCount = count);
      }
      return;
    }

    final wasReady = _isReadyBadgeState(_displayedBadgeState);
    final isReady = _isReadyBadgeState(incoming);
    if (isReady && !wasReady) {
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE_WIDGET',
        details: {
          'widgetTransitionMs': 0,
          'previousHealth': _legacyHealthForBadgeState(
            _displayedBadgeState,
          ).name,
        },
      );
    }

    setState(() {
      _displayedBadgeState = incoming;
      _connectionCount = count;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    final badgeState = _displayedBadgeState;
    final connectionCount = _connectionCount;
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;

    final Color baseColor;
    final Color textColor;
    switch (badgeState) {
      case BadgeReadinessState.online:
      case BadgeReadinessState.onlineDotted:
      case BadgeReadinessState.onlineDirect:
        baseColor = isLightSurface
            ? readableColors.connectedHeading
            : Colors.green;
        textColor = isLightSurface
            ? readableColors.connectedHeading
            : Colors.green[300]!;
      case BadgeReadinessState.connecting:
        baseColor = Colors.amber;
        textColor = isLightSurface
            ? const Color(0xFF8A5D00)
            : Colors.amber[300]!;
      case BadgeReadinessState.offline:
        baseColor = Colors.grey;
        textColor = isLightSurface
            ? readableColors.textMuted
            : Colors.grey[400]!;
    }
    final plain = widget.style == ConnectionStatusIndicatorStyle.plain;
    final label = plain && _isReadyBadgeState(badgeState)
        ? l10n.connection_online
        : _labelForBadgeState(badgeState, l10n);
    final semanticsLabel = _semanticsLabelForBadgeState(badgeState, l10n);

    final contents = Row(
      key: plain ? const ValueKey('connection-status-plain') : null,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: plain ? 6 : 8,
          height: plain ? 6 : 8,
          decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (plain && _isReadyBadgeState(badgeState) && connectionCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '· $connectionCount',
            style: TextStyle(color: textColor, fontSize: 11),
          ),
        ] else if (kDebugMode &&
            _isReadyBadgeState(badgeState) &&
            connectionCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '($connectionCount)',
            style: TextStyle(
              // 248 (TC-29) — full semantic opacity: the old 0.7 alpha
              // faded #236143 to ~2.43:1 on the rendered light pill.
              color: textColor,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );

    // Beta O12 h (2026-10-09): Orbit gives the pill a fixed 40 pt slot beside
    // the FAB. At iOS's largest accessibility sizes (about 3x) the text was
    // cut off; 1.5x still fits. The full status stays in [semanticsLabel].
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: ConnectionStatusIndicator.maxTextScaleFactor,
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: plain
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: contents,
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: baseColor.withValues(
                      alpha: isLightSurface ? 0.12 : 0.2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: baseColor.withValues(
                        alpha: isLightSurface ? 0.32 : 0.4,
                      ),
                      width: 1,
                    ),
                  ),
                  child: contents,
                ),
        ),
      ),
    );
  }
}
