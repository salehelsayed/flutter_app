import 'package:flutter/material.dart';

import '../../../../core/bridge/bridge.dart';
import '../../../../core/utils/flow_event_emitter.dart';
import '../../../identity/domain/repositories/identity_repository.dart';
import '../../application/build_qr_payload_use_case.dart';
import 'qr_display_screen.dart';

/// Internal state enum for QRDisplayWired
enum _QRDisplayState {
  loading,
  success,
  noIdentity,
  error,
}

/// Wired widget that connects QRDisplayScreen to the buildQRPayload use case.
///
/// This is a StatefulWidget that:
/// - Runs buildQRPayload on init
/// - Handles loading/success/error states
/// - Provides retry capability for recoverable errors
/// - Emits flow events for QR_UI_DISPLAY_OPEN and QR_UI_DISPLAY_CLOSE
class QRDisplayWired extends StatefulWidget {
  /// Repository for loading identity data.
  final IdentityRepository repo;

  /// Bridge client for cryptographic signing (callSignPayload).
  final Bridge bridgeClient;

  /// Called when user closes the screen.
  final VoidCallback onClose;

  /// Called when user taps "Scan a friend's code" card.
  final VoidCallback? onScanPressed;

  const QRDisplayWired({
    super.key,
    required this.repo,
    required this.bridgeClient,
    required this.onClose,
    this.onScanPressed,
  });

  @override
  State<QRDisplayWired> createState() => _QRDisplayWiredState();
}

class _QRDisplayWiredState extends State<QRDisplayWired> {
  _QRDisplayState _state = _QRDisplayState.loading;
  String? _qrData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_INIT',
      details: {},
    );
    _buildPayload();
  }

  @override
  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_CLOSE',
      details: {},
    );
    super.dispose();
  }

  Future<void> _buildPayload() async {
    setState(() {
      _state = _QRDisplayState.loading;
      _errorMessage = null;
    });

    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_LOADING',
      details: {},
    );

    try {
      final identity = await widget.repo.loadIdentity();

      if (identity == null) {
        setState(() {
          _state = _QRDisplayState.noIdentity;
          _errorMessage = 'No identity found. Please create one first.';
        });
        return;
      }

      Future<Map<String, dynamic>> jsSign(String dataToSign, String privateKey) {
        return callSignPayload(
          bridge: widget.bridgeClient,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repo,
        callSign: jsSign,
      );

      switch (result) {
        case BuildQRPayloadResult.success:
          setState(() {
            _state = _QRDisplayState.success;
            _qrData = qrString;
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_DISPLAY',
            details: {},
          );
          break;

        case BuildQRPayloadResult.noIdentity:
          setState(() {
            _state = _QRDisplayState.noIdentity;
            _errorMessage = 'No identity found. Please create one first.';
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_ERROR',
            details: {'reason': 'noIdentity'},
          );
          break;

        case BuildQRPayloadResult.signingError:
          setState(() {
            _state = _QRDisplayState.error;
            _errorMessage = 'Failed to sign QR code. Please try again.';
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_ERROR',
            details: {'reason': 'signingError'},
          );
          break;
      }
    } catch (e) {
      setState(() {
        _state = _QRDisplayState.error;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
      emitFlowEvent(
        layer: 'FL',
        event: 'QR_FL_SCREEN_ERROR',
        details: {'reason': 'exception', 'error': e.toString()},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _QRDisplayState.loading:
        return QRDisplayScreen(
          qrData: null,
          onClose: widget.onClose,
          onScanPressed: widget.onScanPressed,
        );

      case _QRDisplayState.success:
        return QRDisplayScreen(
          qrData: _qrData,
          onClose: widget.onClose,
          onScanPressed: widget.onScanPressed,
        );

      case _QRDisplayState.noIdentity:
        return _buildErrorScreen(
          icon: Icons.person_off,
          title: 'No Identity',
          message: _errorMessage!,
          showRetry: false,
        );

      case _QRDisplayState.error:
        return _buildErrorScreen(
          icon: Icons.error_outline,
          title: 'Error',
          message: _errorMessage!,
          showRetry: true,
        );
    }
  }

  Widget _buildErrorScreen({
    required IconData icon,
    required String title,
    required String message,
    required bool showRetry,
  }) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        title: const Text('My QR Code'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (showRetry) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _buildPayload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
