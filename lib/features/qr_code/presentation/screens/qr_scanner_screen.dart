import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../widgets/scan_overlay.dart';

/// QR code scanner screen with camera preview and overlay.
class QRScannerScreen extends StatefulWidget {
  /// Callback when a QR code is successfully scanned.
  final void Function(String qrData) onScanned;

  const QRScannerScreen({super.key, required this.onScanned});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        _hasScanned = true;
        widget.onScanned(barcode.rawValue!);
        Navigator.of(context).pop();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Scan overlay with cutout
          const ScanOverlay(),

          // Top bar with close button and title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildCloseButton(),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.qr_scan_title,
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
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  AppLocalizations.of(context)!.qr_scan_instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.qr_scan_subtitle,
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
                    AppLocalizations.of(context)!.qr_paste_title,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPasteDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          AppLocalizations.of(context)!.qr_paste_title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.qr_paste_hint,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText:
                    '{"pk":"...","ns":"...","rv":"...","ts":"...","sig":"..."}',
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
                AppLocalizations.of(context)!.qr_paste_button,
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
                if (!_hasScanned) {
                  _hasScanned = true;
                  widget.onScanned(text);
                  Navigator.of(context).pop();
                }
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
