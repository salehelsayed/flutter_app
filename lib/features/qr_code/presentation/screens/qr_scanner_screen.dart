import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../widgets/scan_overlay.dart';

class QRScannerScreenCopy {
  final String title;
  final String instruction;
  final String subtitle;
  final String pasteTitle;
  final String pasteHint;
  final String pasteButton;
  final String pastePayloadHintText;

  const QRScannerScreenCopy({
    required this.title,
    required this.instruction,
    required this.subtitle,
    required this.pasteTitle,
    required this.pasteHint,
    required this.pasteButton,
    required this.pastePayloadHintText,
  });

  factory QRScannerScreenCopy.contactDefaults(AppLocalizations l10n) {
    return QRScannerScreenCopy(
      title: l10n.qr_scan_title,
      instruction: l10n.qr_scan_instruction,
      subtitle: l10n.qr_scan_subtitle,
      pasteTitle: l10n.qr_paste_title,
      pasteHint: l10n.qr_paste_hint,
      pasteButton: l10n.qr_paste_button,
      pastePayloadHintText:
          '{"pk":"...","ns":"...","rv":"...","ts":"...","sig":"..."}',
    );
  }
}

/// QR code scanner screen with camera preview and overlay.
class QRScannerScreen extends StatefulWidget {
  /// Callback when a QR code is successfully scanned.
  final void Function(String qrData) onScanned;
  final QRScannerScreenCopy? copy;
  final Future<bool> Function() openAppSettings;
  final Future<bool> Function() isCameraDenied;

  const QRScannerScreen({
    super.key,
    required this.onScanned,
    this.copy,
    this.openAppSettings = ph.openAppSettings,
    this.isCameraDenied = _osCameraDenied,
  });

  static Future<bool> _osCameraDenied() async {
    final status = await ph.Permission.camera.status;
    return status.isDenied || status.isPermanentlyDenied || status.isRestricted;
  }

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    cameraResolution: const Size(1280, 720),
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;
  bool _cameraDenied = false;
  bool _cameraDeniedChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onScannerState);
  }

  // Coming back from Settings: retry once the OS reports access.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _cameraDenied) {
      unawaited(_retryAfterSettings());
    }
  }

  Future<void> _retryAfterSettings() async {
    final denied = await widget.isCameraDenied().catchError((_) => true);
    if (denied || !mounted || !_cameraDenied) return;
    setState(() {
      _cameraDenied = false;
      _cameraDeniedChecked = false;
    });
    try {
      await _controller.start();
    } on MobileScannerException {
      // The listener reads the new error state.
    }
  }

  // iOS can report a refused camera as a generic start error, so any start
  // error asks the OS once.
  Future<void> _onScannerState() async {
    final value = _controller.value;
    final error = value.error;
    if (error == null) {
      _cameraDeniedChecked = false;
      if (_cameraDenied && value.isRunning && mounted) {
        setState(() => _cameraDenied = false);
      }
      return;
    }
    if (_cameraDenied || _cameraDeniedChecked) return;
    _cameraDeniedChecked = true;
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied ||
        await widget.isCameraDenied().catchError((_) => false);
    if (denied && mounted) setState(() => _cameraDenied = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onScannerState);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        _completeScan(barcode.rawValue!);
        return;
      }
    }
  }

  void _completeScan(String qrData) {
    if (_hasScanned) return;
    _hasScanned = true;
    final navigator = Navigator.of(context);
    final scannerRoute = ModalRoute.of(context);
    widget.onScanned(qrData);
    // A handler may synchronously replace the scanner with its destination.
    if (mounted && scannerRoute?.isCurrent == true) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(context);
    final denied = _cameraDenied;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                denied ? _buildCameraDenied() : _buildScannerError(error),
          ),

          if (!denied) const ScanOverlay(),

          // Top bar with close button and title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildCloseButton(),
                  Expanded(
                    child: Text(
                      copy.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildFlashButton(),
                ],
              ),
            ),
          ),

          // Instructions at bottom
          if (!denied)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    copy.instruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primaryAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // Debug: Paste QR button (only in debug mode)
          if (kDebugMode)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: TextButton.icon(
                  onPressed: _showPasteDialog,
                  icon: const Icon(
                    Icons.paste,
                    color: Colors.white70,
                    size: 18,
                  ),
                  label: Text(
                    copy.pasteTitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerError(MobileScannerException error) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              error.errorCode.message,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraDenied() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white70,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.perm_camera,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: widget.openAppSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.compose_open_settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  QRScannerScreenCopy _copyFor(BuildContext context) {
    return widget.copy ??
        QRScannerScreenCopy.contactDefaults(AppLocalizations.of(context)!);
  }

  void _showPasteDialog() {
    final controller = TextEditingController();
    final copy = _copyFor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          copy.pasteTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.pasteHint,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: copy.pastePayloadHintText,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primaryAccent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  controller.text = data!.text!;
                }
              },
              child: Text(
                copy.pasteButton,
                style: TextStyle(color: AppColors.primaryAccent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)!.btn_cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                _completeScan(text);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: Colors.black,
            ),
            child: Text(AppLocalizations.of(context)!.btn_submit),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildFlashButton() {
    return ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, state, child) {
        final torchState = state.torchState;
        return GestureDetector(
          onTap: () => _controller.toggleTorch(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
              color: torchState == TorchState.on
                  ? AppColors.primaryAccent
                  : Colors.white,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
