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
  });
  final String name;
  final CallState state;
  final DateTime? connectedAt;
  final bool muted;
  final DateTime Function() now;
  final VoidCallback onReturn;
  @override
  State<CallReturnBar> createState() => _CallReturnBarState();
}

class _CallReturnBarState extends State<CallReturnBar> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    final status = widget.state == CallState.reconnecting
        ? l10n.call_status_reconnecting
        : widget.state == CallState.connected
        ? l10n.call_status_connected
        : l10n.call_status_connecting;
    final elapsed = widget.connectedAt == null
        ? null
        : widget.now().toUtc().difference(widget.connectedAt!.toUtc());
    final seconds = elapsed == null
        ? null
        : (elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds);
    final duration = seconds == null
        ? ''
        : '${seconds >= 3600 ? '${seconds ~/ 3600}:' : ''}'
              '${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:'
              '${(seconds % 60).toString().padLeft(2, '0')}';
    final label = [
      l10n.call_return,
      widget.name,
      status,
      if (duration.isNotEmpty) l10n.call_duration(duration),
      if (widget.muted) l10n.call_muted,
    ].join(', ');
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Semantics(
        button: true,
        label: label,
        onTap: widget.onReturn,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('call-return-bar'),
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
                      '${widget.name} · $status $duration',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.muted) const Icon(Icons.mic_off),
                  const Icon(Icons.keyboard_arrow_up),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
