import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/bridge.dart';
import '../../../../core/utils/flow_event_emitter.dart';
import '../../../identity/domain/repositories/identity_repository.dart';
import '../../../settings/domain/models/background_preference.dart';
import '../../application/build_qr_payload_use_case.dart';
import 'qr_display_screen.dart';

/// Internal state enum for QRDisplayWired
enum _QRDisplayState { loading, success, noIdentity, error }

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
  final BackgroundPreference backgroundPreference;

  const QRDisplayWired({
    super.key,
    required this.repo,
    required this.bridgeClient,
    required this.onClose,
    this.onScanPressed,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
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
    emitFlowEvent(layer: 'FL', event: 'QR_FL_SCREEN_INIT', details: {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildPayload();
    });
  }

  @override
  void dispose() {
    emitFlowEvent(layer: 'FL', event: 'QR_FL_SCREEN_CLOSE', details: {});
    super.dispose();
  }

  Future<void> _buildPayload() async {
    if (!mounted) return;
    setState(() {
      _state = _QRDisplayState.loading;
      _qrData = null;
      _errorMessage = null;
    });

    emitFlowEvent(layer: 'FL', event: 'QR_FL_SCREEN_LOADING', details: {});

    try {
      final identity = await widget.repo.loadIdentity();
      if (!mounted) return;

      if (identity == null) {
        setState(() {
          _state = _QRDisplayState.noIdentity;
          _qrData = null;
          _errorMessage = _noIdentityDetail();
        });
        return;
      }

      Future<Map<String, dynamic>> jsSign(
        String dataToSign,
        String privateKey,
      ) {
        return callSignPayload(
          bridge: widget.bridgeClient,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repo,
        callSign: jsSign,
        cachedIdentity: identity,
      );
      if (!mounted) return;

      switch (result) {
        case BuildQRPayloadResult.success:
          final qrData = qrString?.trim();
          if (qrData == null || qrData.isEmpty) {
            setState(() {
              _state = _QRDisplayState.error;
              _qrData = null;
              _errorMessage = _unexpectedError();
            });
            emitFlowEvent(
              layer: 'FL',
              event: 'QR_FL_SCREEN_ERROR',
              details: {'reason': 'emptyPayload'},
            );
            break;
          }
          setState(() {
            _state = _QRDisplayState.success;
            _qrData = qrData;
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
            _qrData = null;
            _errorMessage = _noIdentityDetail();
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
            _qrData = null;
            _errorMessage = _signFailed();
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_ERROR',
            details: {'reason': 'signingError'},
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _QRDisplayState.error;
        _qrData = null;
        _errorMessage = _unexpectedError();
      });
      emitFlowEvent(
        layer: 'FL',
        event: 'QR_FL_SCREEN_ERROR',
        details: {'reason': 'exception', 'error': e.toString()},
      );
    }
  }

  String _noIdentityDetail() {
    return AppLocalizations.of(context)?.qr_no_identity_detail ??
        'No identity found. Please create one first.';
  }

  String _signFailed() {
    return AppLocalizations.of(context)?.qr_sign_failed ??
        'Failed to sign QR code. Please try again.';
  }

  String _unexpectedError() {
    return AppLocalizations.of(context)?.qr_unexpected_error ??
        'An unexpected error occurred. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _QRDisplayState.loading:
        return QRDisplayScreen(
          qrData: null,
          onClose: widget.onClose,
          onScanPressed: widget.onScanPressed,
          backgroundPreference: widget.backgroundPreference,
        );

      case _QRDisplayState.success:
        return QRDisplayScreen(
          qrData: _qrData,
          onClose: widget.onClose,
          onScanPressed: widget.onScanPressed,
          backgroundPreference: widget.backgroundPreference,
        );

      case _QRDisplayState.noIdentity:
        return _buildErrorScreen(
          icon: Icons.person_off,
          title: AppLocalizations.of(context)!.qr_no_identity,
          message: _errorMessage!,
          showRetry: false,
        );

      case _QRDisplayState.error:
        return _buildErrorScreen(
          icon: Icons.error_outline,
          title: AppLocalizations.of(context)!.qr_error,
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
        title: Text(AppLocalizations.of(context)!.qr_my_code),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.error),
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
                  label: Text(AppLocalizations.of(context)!.qr_try_again),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
