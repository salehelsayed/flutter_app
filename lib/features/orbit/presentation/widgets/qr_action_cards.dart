import 'package:flutter/material.dart';

/// Two side-by-side QR action cards at the bottom of the friends list.
class QRActionCards extends StatelessWidget {
  final VoidCallback onMyQR;
  final VoidCallback onScanQR;

  const QRActionCards({
    super.key,
    required this.onMyQR,
    required this.onScanQR,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.qr_code,
            title: 'My QR Code',
            subtitle: 'Share to add friends',
            onTap: onMyQR,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionCard(
            icon: Icons.camera_alt_outlined,
            title: 'Scan QR',
            subtitle: 'Add a friend instantly',
            onTap: onScanQR,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0x141DB954), // rgba(29,185,84,0.08)
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0x331DB954), // rgba(29,185,84,0.2)
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x331DB954), // rgba(29,185,84,0.2)
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFF1DB954)),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
