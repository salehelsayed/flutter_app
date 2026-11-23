import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../domain/call_state.dart';

/// Presentation only: duration keeps the canonical connected timestamp.
class CallReturnBar extends StatefulWidget {
  const CallReturnBar({
    super.key,
    required this.name,
    required this.state,
    required this.connectedAt,
    required this.muted,
    required this.now,
    required this.onReturn,
    this.endedAt,
  });
  final String name;
  final CallState state;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final bool muted;
  final DateTime Function() now;
  final VoidCallback onReturn;
  @override
  State<CallReturnBar> createState() => _CallReturnBarState();
}

class _CallReturnBarState extends State<CallReturnBar> {
  Timer? _timer;

  bool get _ended => widget.state == CallState.ended;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant CallReturnBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    if (_ended) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = switch (widget.state) {
      CallState.ended => l10n.call_ended,
      CallState.preparing || CallState.inviting => l10n.call_status_calling,
      CallState.ringing => l10n.call_status_ringing,
      CallState.reconnecting => l10n.call_status_reconnecting,
      CallState.connected => l10n.call_status_connected,
      _ => l10n.call_status_connecting,
    };
    final until = _ended ? widget.endedAt : widget.now();
    final elapsed = widget.connectedAt == null
        ? null
        : until?.toUtc().difference(widget.connectedAt!.toUtc());
    final seconds = elapsed == null
        ? null
        : (elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds);
    final duration = seconds == null
        ? ''
        : '${seconds >= 3600 ? '${seconds ~/ 3600}:' : ''}'
              '${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:'
              '${(seconds % 60).toString().padLeft(2, '0')}';
    final subtitle = duration.isEmpty
        ? status
        : _ended
        ? l10n.call_row_with_duration(status, duration)
        : '$status $duration';
    final label = [
      _ended ? l10n.call_dismiss_status : l10n.call_return,
      widget.name,
      status,
      if (duration.isNotEmpty) l10n.call_duration(duration),
      if (widget.muted) l10n.call_muted,
    ].join(', ');
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Semantics(
        liveRegion: _ended,
        // Its own node: otherwise the label merges into the nearest ancestor
        // node, which reports full-screen bounds to accessibility services.
        container: true,
        button: true,
        label: label,
        onTap: widget.onReturn,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey(
            _ended ? 'call-terminal-return-bar' : 'call-return-bar',
          ),
          onTap: widget.onReturn,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.call),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.name} · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.muted) const Icon(Icons.mic_off),
                  Icon(_ended ? Icons.close : Icons.keyboard_arrow_up),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
