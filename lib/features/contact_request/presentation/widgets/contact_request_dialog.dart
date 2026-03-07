import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Dialog shown when receiving a contact request.
///
/// Displays the sender's avatar and username with Accept/Decline buttons.
/// Buttons are disabled after the first tap to prevent double-tap issues.
class ContactRequestDialog extends StatefulWidget {
  final ContactRequestModel request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const ContactRequestDialog({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<ContactRequestDialog> createState() => _ContactRequestDialogState();
}

class _ContactRequestDialogState extends State<ContactRequestDialog> {
  bool _isProcessing = false;

  void _handleAccept() {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    widget.onAccept();
  }

  void _handleDecline() {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppColors.primaryAccent.withValues(alpha: 0.3),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          // Sender's ring avatar
          UserAvatar(peerId: widget.request.peerId, size: 80),
          const SizedBox(height: 16),
          // Username
          Text(
            widget.request.username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Connection request message
          Text(
            'wants to connect with you',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              // Decline button
              Expanded(
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : _handleDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: BorderSide(
                      color: AppColors.textMuted.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Accept button
              Expanded(
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handleAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
