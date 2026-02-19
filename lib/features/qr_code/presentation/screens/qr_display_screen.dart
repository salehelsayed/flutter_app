import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Screen that displays the user's QR code for identity sharing.
///
/// This is a pure layout widget with no business logic.
/// All actions are handled via callbacks.
class QRDisplayScreen extends StatelessWidget {
  /// The JSON string to encode in the QR code.
  final String qrData;

  /// The user's peerID for display (will be truncated).
  final String peerId;

  /// Called when the user presses the back/close button.
  final VoidCallback onClose;

  /// Called when the user presses the share button.
  /// If null, the share button is not shown.
  final VoidCallback? onShare;

  const QRDisplayScreen({
    super.key,
    required this.qrData,
    required this.peerId,
    required this.onClose,
    this.onShare,
  });

  /// Truncates the peerID for display.
  /// Example: "12D3KooWAbcdefghijk..." → "12D3KooW...ghijk"
  String _truncatePeerId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
  }

  void _copyQRData(BuildContext context) {
    Clipboard.setData(ClipboardData(text: qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR data copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = (screenWidth * 0.7).clamp(256.0, 300.0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose,
        ),
        title: const Text('My QR Code'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // QR Code Container
              GestureDetector(
                onLongPress: kDebugMode ? () => _copyQRData(context) : null,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Semantics(
                    label: 'QR code for sharing your identity',
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: qrSize,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
              ),
              if (kDebugMode)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Long-press QR to copy data',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),

              const SizedBox(height: 32),

              // Instruction Text
              Text(
                'Scan to connect with me',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // PeerID Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _truncatePeerId(peerId),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your Peer ID',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Share Button (conditional)
              if (onShare != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Share QR Code'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
