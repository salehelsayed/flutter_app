import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/foreground_call_capability.dart';
import '../../domain/call_audio_output_device.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_id.dart';

/// Visible-only inventory, read from the existing native audio owner.
class CallAudioOutputPicker extends StatefulWidget {
  const CallAudioOutputPicker({
    super.key,
    required this.callId,
    required this.capability,
    required this.onClose,
  });
  final CallId callId;
  final ForegroundCallAudioPickerCapability capability;
  final VoidCallback onClose;

  @override
  State<CallAudioOutputPicker> createState() => _CallAudioOutputPickerState();
}

class _CallAudioOutputPickerState extends State<CallAudioOutputPicker> {
  List<CallAudioOutputDevice> _devices = const [];
  // Stable row identity cancels a gesture when its endpoint disappears. Object
  // keys keep actual device identifiers out of widget diagnostics.
  final Map<String, Object> _deviceKeys = {};
  Timer? _poll;
  bool _reading = false;
  bool _choosing = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_choosing) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final devices = await widget.capability.outputDevices(widget.callId);
      if (!mounted) return;
      setState(() {
        _devices = devices.take(32).toList(growable: false);
        final ids = _devices.map((device) => device.id).toSet();
        _deviceKeys.removeWhere((id, _) => !ids.contains(id));
        for (final device in _devices) {
          _deviceKeys.putIfAbsent(device.id, Object.new);
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _devices = const [];
          _deviceKeys.clear();
          _loading = false;
          _failed = true;
        });
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _choose(CallAudioOutputDevice device) async {
    if (_choosing) return;
    setState(() {
      _choosing = true;
      _failed = false;
    });
    var succeeded = false;
    try {
      final result = await widget.capability.selectOutputDevice(
        widget.callId,
        device.id,
      );
      succeeded = result.status == ForegroundCallActionStatus.applied;
    } catch (_) {
      // Native failures are intentionally shown without native payload details.
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    setState(() {
      _choosing = false;
      _failed = !succeeded;
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _devices = const [];
    _deviceKeys.clear();
    super.dispose();
  }

  String _label(CallAudioOutputDevice device, AppLocalizations l10n) {
    return switch (device.route) {
      CallAudioOutputRoute.earpiece => l10n.call_audio_route_earpiece,
      CallAudioOutputRoute.speaker => l10n.call_speaker,
      CallAudioOutputRoute.systemDefault =>
        l10n.call_audio_route_system_default,
      CallAudioOutputRoute.wiredHeadset =>
        device.name.isEmpty ? l10n.call_audio_route_wired_headset : device.name,
      CallAudioOutputRoute.bluetooth =>
        device.name.isEmpty ? l10n.call_audio_route_bluetooth : device.name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlockSemantics(
      child: Stack(
        children: [
          ModalBarrier(
            color: Colors.black54,
            dismissible: true,
            onDismiss: widget.onClose,
          ),
          SafeArea(
            child: Center(
              child: FocusScope(
                autofocus: true,
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(l10n.call_audio_choose_output),
                              ),
                              IconButton(
                                tooltip: l10n.call_audio_refresh_outputs,
                                onPressed: _choosing
                                    ? null
                                    : () {
                                        setState(() => _failed = false);
                                        unawaited(_refresh());
                                      },
                                icon: const Icon(Icons.refresh),
                              ),
                              IconButton(
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                                onPressed: widget.onClose,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          if (_loading || _choosing)
                            const LinearProgressIndicator(),
                          if (_failed)
                            Text(
                              l10n.call_audio_output_failed,
                              semanticsLabel: l10n.call_audio_output_failed,
                            ),
                          if (!_loading && _devices.isEmpty)
                            Text(l10n.call_audio_output_unavailable),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (var i = 0; i < _devices.length; i++)
                                    Semantics(
                                      key: ValueKey('call-output-choice-$i'),
                                      identifier:
                                          'call-output-choice-${_devices[i].route.name}-$i',
                                      selected: _devices[i].selected,
                                      child: ListTile(
                                        key: ObjectKey(
                                          _deviceKeys[_devices[i].id],
                                        ),
                                        title: Text(_label(_devices[i], l10n)),
                                        trailing: _devices[i].selected
                                            ? const Icon(Icons.check)
                                            : null,
                                        enabled: !_choosing,
                                        onTap: () =>
                                            unawaited(_choose(_devices[i])),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
