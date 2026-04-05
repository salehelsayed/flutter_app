import 'package:flutter/material.dart';

class GroupDissolvedBadge extends StatelessWidget {
  final bool dense;

  const GroupDissolvedBadge({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x33FF8A80),
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        border: Border.all(color: const Color(0x66FF8A80), width: 0.5),
      ),
      child: Text(
        'Dissolved',
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFB3AD),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
