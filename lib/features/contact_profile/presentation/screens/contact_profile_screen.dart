import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Immersive "orbital dossier" profile view for a contact (friend).
///
/// Opened by tapping a friend's avatar (conversation header, friends list).
/// Leans into the app's cosmic / glassmorphic identity: the avatar is a
/// luminous body at the centre of slowly-rotating orbit rings tinted with the
/// peer's own deterministic glow colour, over a starfield backdrop, with
/// frosted-glass cards revealing nickname, peer ID, safety number and the
/// connection date in an orchestrated staggered entrance.
class ContactProfileScreen extends StatefulWidget {
  /// The contact to display.
  final ContactModel contact;

  /// Optional "message" action. When provided, a primary call-to-action is
  /// shown (e.g. from the friends list, to jump into the conversation). When
  /// null (e.g. opened from inside the conversation already) no button shows.
  final VoidCallback? onMessage;

  const ContactProfileScreen({
    super.key,
    required this.contact,
    this.onMessage,
  });

  /// Pushes the profile screen using the shared conversation route (so it
  /// inherits the iOS edge-swipe-back gesture, matching the rest of the app).
  static Future<void> open(
    BuildContext context, {
    required ContactModel contact,
    VoidCallback? onMessage,
  }) {
    return Navigator.of(context).push<void>(
      buildConversationRoute(
        builder: (_) =>
            ContactProfileScreen(contact: contact, onMessage: onMessage),
      ),
    );
  }

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _orbit;
  late final Color _accent;
  late final String? _safetyNumber;

  @override
  void initState() {
    super.initState();
    _accent = RingAvatarGenerator.glowColorForPeerId(widget.contact.peerId);
    _safetyNumber = ContactSafetyNumber.build(
      peerId: widget.contact.peerId,
      publicKey: widget.contact.publicKey,
      mlKemPublicKey: widget.contact.mlKemPublicKey,
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _orbit.dispose();
    super.dispose();
  }

  Future<void> _copy(String value, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final readable = context.backgroundReadableColors;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: readable.surfaceRaised,
          duration: const Duration(milliseconds: 1600),
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: _accent),
              const SizedBox(width: 10),
              Text(
                confirmation,
                style: TextStyle(color: readable.textPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
  }

  /// Staggered fade + slide-up reveal driven by [_entrance].
  Widget _reveal({
    required double start,
    required double end,
    double dy = 28,
    required Widget child,
  }) {
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (_, c) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * dy),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final l10n = AppLocalizations.of(context)!;
    final contact = widget.contact;

    return Scaffold(
      backgroundColor: readable.surfaceBase,
      body: Stack(
        children: [
          // Cosmic backdrop: radial peer-glow + deterministic starfield.
          Positioned.fill(
            child: CustomPaint(
              painter: _BackdropPainter(
                accent: _accent,
                isLight: isLight,
                seed: contact.peerId.hashCode,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  readable: readable,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    child: Column(
                      children: [
                        _buildHero(readable, isLight),
                        const SizedBox(height: 26),
                        _reveal(
                          start: 0.24,
                          end: 0.62,
                          child: _buildName(readable, contact.username),
                        ),
                        const SizedBox(height: 12),
                        _reveal(
                          start: 0.30,
                          end: 0.68,
                          child: _buildStatusRow(readable, l10n, contact),
                        ),
                        const SizedBox(height: 30),
                        _reveal(
                          start: 0.40,
                          end: 0.80,
                          child: _buildPeerIdCard(readable, l10n, contact.peerId),
                        ),
                        if (_safetyNumber != null) ...[
                          const SizedBox(height: 14),
                          _reveal(
                            start: 0.50,
                            end: 0.88,
                            child: _buildSafetyCard(
                              readable,
                              l10n,
                              _safetyNumber,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _reveal(
                          start: 0.58,
                          end: 0.94,
                          child: _buildMetaCard(readable, l10n, contact),
                        ),
                        if (widget.onMessage != null) ...[
                          const SizedBox(height: 28),
                          _reveal(
                            start: 0.70,
                            end: 1.0,
                            child: _buildMessageButton(readable, l10n),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero: orbit rings + avatar ──────────────────────────────────────────

  Widget _buildHero(BackgroundReadableColors readable, bool isLight) {
    const heroSize = 268.0;
    return SizedBox(
      height: heroSize,
      width: heroSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating orbit field.
          AnimatedBuilder(
            animation: _orbit,
            builder: (_, _) => Transform.rotate(
              angle: _orbit.value * 2 * pi,
              child: CustomPaint(
                size: const Size(heroSize, heroSize),
                painter: _OrbitRingsPainter(accent: _accent, isLight: isLight),
              ),
            ),
          ),
          // Avatar with entrance scale + fade.
          AnimatedBuilder(
            animation: _entrance,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: _entrance,
                curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
              ).value;
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.72 + 0.28 * t, child: child),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: isLight ? 0.45 : 0.6),
                    blurRadius: 48,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: UserAvatar(
                peerId: widget.contact.peerId,
                size: 132,
                showGlow: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildName(BackgroundReadableColors readable, String username) {
    return Text(
      username,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 28,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: readable.textPrimary,
      ),
    );
  }

  Widget _buildStatusRow(
    BackgroundReadableColors readable,
    AppLocalizations l10n,
    ContactModel contact,
  ) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          icon: Icons.verified_rounded,
          label: l10n.contact_profile_verified_peer,
          color: _accent,
          background: _accent.withValues(alpha: 0.14),
          borderColor: _accent.withValues(alpha: 0.4),
        ),
        if (contact.isBlocked)
          _Chip(
            icon: Icons.block_rounded,
            label: l10n.contact_profile_blocked,
            color: const Color(0xFFFF6B6B),
            background: const Color(0x22FF6B6B),
            borderColor: const Color(0x55FF6B6B),
          ),
        if (contact.isArchived)
          _Chip(
            icon: Icons.archive_outlined,
            label: l10n.contact_profile_archived,
            color: readable.textMuted,
            background: readable.surfaceSubtle,
            borderColor: readable.border,
          ),
      ],
    );
  }

  // ── Cards ───────────────────────────────────────────────────────────────

  Widget _buildPeerIdCard(
    BackgroundReadableColors readable,
    AppLocalizations l10n,
    String peerId,
  ) {
    return _GlassCard(
      readable: readable,
      accent: _accent,
      onTap: () => _copy(peerId, l10n.contact_profile_peer_id_copied),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(
            icon: Icons.fingerprint_rounded,
            label: l10n.contact_profile_peer_id_label,
            accent: _accent,
            trailing: Icon(
              Icons.copy_rounded,
              size: 16,
              color: readable.iconMuted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            peerId,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.5,
              letterSpacing: 0.2,
              color: readable.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.contact_profile_tap_to_copy,
            style: TextStyle(fontSize: 11, color: readable.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyCard(
    BackgroundReadableColors readable,
    AppLocalizations l10n,
    String safetyNumber,
  ) {
    return _GlassCard(
      readable: readable,
      accent: _accent,
      onTap: () => _copy(safetyNumber, l10n.contact_profile_copied),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(
            icon: Icons.shield_rounded,
            label: l10n.contact_profile_safety_number_label,
            accent: _accent,
          ),
          const SizedBox(height: 12),
          Text(
            safetyNumber,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: readable.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.contact_profile_safety_number_hint,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: readable.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard(
    BackgroundReadableColors readable,
    AppLocalizations l10n,
    ContactModel contact,
  ) {
    final connected = _formatConnectedSince(context, contact.scannedAt);
    final introducedBy = contact.introducedBy;
    return _GlassCard(
      readable: readable,
      accent: _accent,
      child: Column(
        children: [
          if (connected != null)
            _MetaRow(
              readable: readable,
              accent: _accent,
              icon: Icons.auto_awesome_rounded,
              label: l10n.contact_profile_connected_since_label,
              value: connected,
            ),
          if (connected != null &&
              introducedBy != null &&
              introducedBy.isNotEmpty)
            Divider(height: 22, color: readable.divider),
          if (introducedBy != null && introducedBy.isNotEmpty)
            _MetaRow(
              readable: readable,
              accent: _accent,
              icon: Icons.handshake_rounded,
              label: l10n.contact_profile_introduced_by_label,
              value: introducedBy,
            ),
        ],
      ),
    );
  }

  Widget _buildMessageButton(
    BackgroundReadableColors readable,
    AppLocalizations l10n,
  ) {
    return GestureDetector(
      onTap: widget.onMessage,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: LinearGradient(
            colors: [_accent, _accent.withValues(alpha: 0.75)],
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              size: 19,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              l10n.contact_profile_message_button,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _formatConnectedSince(BuildContext context, String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    try {
      final locale = Localizations.localeOf(context).toString();
      return DateFormat.yMMMMd(locale).format(dt.toLocal());
    } catch (_) {
      return DateFormat.yMMMMd().format(dt.toLocal());
    }
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onBack;

  const _TopBar({required this.readable, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: readable.glassSurface,
                    border: Border.all(color: readable.glassBorder),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: readable.iconSecondary,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final Color borderColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final BackgroundReadableColors readable;
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  const _GlassCard({
    required this.readable,
    required this.accent,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: readable.glassSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: readable.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  const _CardLabel({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: accent,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final BackgroundReadableColors readable;
  final Color accent;
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.readable,
    required this.accent,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: readable.textMuted),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: readable.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

class _OrbitRingsPainter extends CustomPainter {
  final Color accent;
  final bool isLight;

  _OrbitRingsPainter({required this.accent, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radii = [size.width * 0.30, size.width * 0.40, size.width * 0.50];

    for (var i = 0; i < radii.length; i++) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = accent.withValues(
          alpha: (isLight ? 0.22 : 0.16) - i * 0.03,
        );
      canvas.drawCircle(center, radii[i], ring);
    }

    void satellite(double radius, double angle, double dotRadius) {
      final p = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawCircle(
        p,
        dotRadius * 2.6,
        Paint()..color = accent.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        p,
        dotRadius,
        Paint()..color = accent.withValues(alpha: 0.95),
      );
    }

    satellite(radii[0], 0.6, 2.4);
    satellite(radii[1], 3.3, 2.0);
    satellite(radii[2], 5.1, 2.8);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingsPainter old) =>
      old.accent != accent || old.isLight != isLight;
}

class _BackdropPainter extends CustomPainter {
  final Color accent;
  final bool isLight;
  final int seed;

  _BackdropPainter({
    required this.accent,
    required this.isLight,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Radial glow from the upper third, tinted with the peer's accent.
    final glowCenter = Offset(size.width / 2, size.height * 0.22);
    final glowRect = Rect.fromCircle(
      center: glowCenter,
      radius: size.width * 0.95,
    );
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isLight ? 0.16 : 0.30),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(glowRect);
    canvas.drawRect(Offset.zero & size, glow);

    if (isLight) return; // Starfield reads as noise on a light surface.

    final rnd = Random(seed);
    final star = Paint();
    for (var i = 0; i < 96; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() * 1.1 + 0.2;
      star.color = Colors.white.withValues(
        alpha: rnd.nextDouble() * 0.5 + 0.08,
      );
      canvas.drawCircle(Offset(dx, dy), r, star);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.accent != accent || old.isLight != isLight || old.seed != seed;
}
