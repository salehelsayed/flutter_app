import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class OrbitIntroDock extends StatelessWidget {
  final List<FoldedIntroductionReviewItem> foldedReviewItems;
  final int pendingGroupInviteCount;
  final int unseenCount;
  final bool dismissed;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const OrbitIntroDock({
    super.key,
    required this.foldedReviewItems,
    required this.pendingGroupInviteCount,
    required this.unseenCount,
    required this.dismissed,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    if (dismissed) {
      // container:true keeps this a single clean a11y node; the visuals are
      // excluded so only the l10n button label is announced.
      return Semantics(
        container: true,
        button: true,
        label: AppLocalizations.of(context)!.orbit_intro_remnant_semantics,
        child: GestureDetector(
          key: const ValueKey('orbit-intro-remnant'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _DashedPillPainter(
                color: Colors.white.withValues(alpha: 0.42),
              ),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final label = l10n.orbit_intro_dock_label(unseenCount);
    final semanticsLabel = l10n.orbit_intro_dock_semantics(unseenCount);

    return Dismissible(
      key: const ValueKey('orbit-intro-dock-dismissible'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismissed(),
      // container:true fences the dock into its own a11y node so the
      // Dismissible's drag actions stay outside it; the facepile/label
      // visuals are excluded so only the l10n button label is announced.
      child: Semantics(
        container: true,
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          key: const ValueKey('orbit-intro-dock'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Container(
              height: 40,
              padding: const EdgeInsets.only(left: 8, right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF157A39),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF42D779), width: 0.8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Facepile(
                    foldedReviewItems: foldedReviewItems,
                    pendingGroupInviteCount: pendingGroupInviteCount,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Facepile extends StatelessWidget {
  final List<FoldedIntroductionReviewItem> foldedReviewItems;
  final int pendingGroupInviteCount;

  const _Facepile({
    required this.foldedReviewItems,
    required this.pendingGroupInviteCount,
  });

  @override
  Widget build(BuildContext context) {
    final avatarItems = foldedReviewItems.take(2).toList(growable: false);
    final chips = <Widget>[
      for (var index = 0; index < avatarItems.length; index++)
        Transform.translate(
          offset: Offset(index * -6, 0),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF157A39), width: 1.4),
            ),
            child: ClipOval(
              child: UserAvatar(
                peerId: avatarItems[index].targetPeerId,
                size: 26,
              ),
            ),
          ),
        ),
      if (pendingGroupInviteCount > 0)
        Transform.translate(
          offset: Offset(avatarItems.length * -6, 0),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF0E5D2D),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF157A39), width: 1.4),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
    ];

    if (chips.isEmpty) {
      return const Icon(Icons.groups_2_outlined, size: 18, color: Colors.white);
    }

    final width = 28 + (chips.length - 1) * 22;
    return SizedBox(
      width: width.toDouble(),
      height: 28,
      child: Stack(clipBehavior: Clip.none, children: chips),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  final Color color;

  const _DashedPillPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.8), Radius.circular(16));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPillPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
