import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';

/// A thought's two-line preview. Read state changes only its text weight.
class OrbitThoughtNoteBubble extends StatelessWidget {
  static const tailHeight = 11.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 9, vertical: 6);

  final OrbitThoughtNote note;
  final VoidCallback? onTap;

  const OrbitThoughtNoteBubble({super.key, required this.note, this.onTap});

  static TextStyle textStyle({required bool isRead}) => TextStyle(
    color: const Color(0xFFF5F5F5),
    fontSize: 11.5,
    height: 1.22,
    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
  );

  /// Includes the tail. Uses the same direction, text scaler and weight as the
  /// rendered text, so collision geometry remains valid for accessibility.
  static Size measure(BuildContext context, OrbitThoughtNote note) {
    final painter = TextPainter(
      text: TextSpan(
        text: note.text,
        style: textStyle(isRead: note.isRead),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 78);
    final result = Size(
      (painter.width + 18).clamp(40.0, 96.0).toDouble(),
      painter.height + 12 + tailHeight,
    );
    painter.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final size = measure(context, note);
    return Semantics(
      button: onTap != null,
      label: note.text,
      excludeSemantics: true,
      child: GestureDetector(
        // Retire an in-flight press when a newer thought replaces this one.
        key: ValueKey('orbit-thought-tap-${note.postId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(
            children: [
              Container(
                width: size.width,
                height: size.height - tailHeight,
                padding: _padding,
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  note.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textStyle(isRead: note.isRead),
                ),
              ),
              const SizedBox(height: 2),
              const _ThoughtTailDot(size: 5),
              const SizedBox(height: 1),
              const _ThoughtTailDot(size: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThoughtTailDot extends StatelessWidget {
  final double size;
  const _ThoughtTailDot({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0xFF262626),
      shape: BoxShape.circle,
    ),
  );
}
