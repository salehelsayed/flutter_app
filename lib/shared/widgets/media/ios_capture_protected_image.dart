import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// iOS capture-protected image surface (AVFoundation-backed platform view).
///
/// Pixels rendered through this view are excluded from screenshots and screen
/// recordings by the native `PrivateMediaProtectionCoordinator` platform view
/// registered in AppDelegate. Promoted from the full-screen viewer's private
/// wrapper (plan 301) so the protected-photo thumbnail tile can reuse the
/// exact shipped mechanism; behavior is byte-identical to the private
/// original.
///
/// [onFirstRenderedFrame] may gate the reveal (the viewer's budget-consuming
/// handshake); passing null auto-reveals after the native `prepare`/`reveal`
/// round-trip. Both failure callbacks fire at most once and fail closed —
/// callers swap in their own no-pixel presentation.
class IosCaptureProtectedImage extends StatefulWidget {
  const IosCaptureProtectedImage({
    super.key,
    required this.path,
    required this.onFirstRenderedFrame,
    required this.onPreFrameFailure,
    required this.onPostFrameFailure,
  });

  final String path;
  final Future<bool> Function()? onFirstRenderedFrame;
  final VoidCallback onPreFrameFailure;
  final VoidCallback onPostFrameFailure;

  @override
  State<IosCaptureProtectedImage> createState() =>
      _IosCaptureProtectedImageState();
}

class _IosCaptureProtectedImageState extends State<IosCaptureProtectedImage> {
  static const _viewType = 'mknoon/private_capture_protected_image';
  static const _operationTimeout = Duration(seconds: 15);

  bool _started = false;
  bool _revealed = false;
  bool _failed = false;
  bool _authorizationAccepted = false;
  MethodChannel? _channel;
  Timer? _creationWatchdog;

  @override
  void initState() {
    super.initState();
    _creationWatchdog = Timer(_operationTimeout, () {
      if (mounted && !_started) {
        _started = true;
        _failClosed();
      }
    });
  }

  Future<void> _onPlatformViewCreated(int viewId) async {
    if (_started || _failed || !mounted) return;
    _started = true;
    _creationWatchdog?.cancel();
    _creationWatchdog = null;
    final channel = MethodChannel('$_viewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    try {
      final prepared = await channel
          .invokeMapMethod<Object?, Object?>('prepare')
          .timeout(_operationTimeout);
      if (!mounted || _failed) return;
      if (!_isExactSuccess(prepared)) {
        _failClosed();
        return;
      }

      final accepted =
          await (widget.onFirstRenderedFrame?.call() ??
              Future<bool>.value(true));
      if (!mounted || _failed || !accepted) return;
      _authorizationAccepted = true;

      final revealed = await channel
          .invokeMapMethod<Object?, Object?>('reveal')
          .timeout(_operationTimeout);
      if (!mounted || _failed) return;
      if (!_isExactSuccess(revealed)) {
        _failClosed();
        return;
      }
      if (_failed) return;
      setState(() => _revealed = true);
    } catch (_) {
      if (mounted) _failClosed();
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'renderFailure' || call.arguments != null) {
      throw MissingPluginException('Unsupported protected image callback');
    }
    if (!mounted) return const <String, Object?>{'ok': false};
    _failClosed();
    return const <String, Object?>{'ok': true};
  }

  void _failClosed() {
    if (_failed) return;
    _failed = true;
    _creationWatchdog?.cancel();
    _creationWatchdog = null;
    if (_authorizationAccepted) {
      widget.onPostFrameFailure();
    } else {
      widget.onPreFrameFailure();
    }
    if (mounted) setState(() {});
  }

  bool _isExactSuccess(Map<Object?, Object?>? envelope) =>
      envelope?.length == 1 && envelope?['ok'] == true;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _creationWatchdog?.cancel();
    _creationWatchdog = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Color.fromRGBO(255, 255, 255, 0.25),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        UiKitView(
          viewType: _viewType,
          creationParams: <String, Object?>{'path': widget.path},
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        if (_revealed)
          const IgnorePointer(
            key: ValueKey('ios-capture-protected-image-revealed'),
            child: SizedBox.shrink(),
          ),
        if (!_revealed)
          const ColoredBox(
            key: ValueKey('ios-capture-protected-image-prereveal-cover'),
            color: Colors.black,
          ),
      ],
    );
  }
}
