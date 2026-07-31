import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

enum PrivateMediaPickerMode { ordinary, protected, viewOnce, disappearing }

enum PrivateMediaPickerKind { photo, video, gif }

@immutable
class PrivateMediaPickerSelection {
  const PrivateMediaPickerSelection({required this.mode, this.durationSeconds});

  final PrivateMediaPickerMode mode;
  final int? durationSeconds;

  PrivateMediaPickerSelection copyWith({
    PrivateMediaPickerMode? mode,
    int? durationSeconds,
  }) {
    final nextMode = mode ?? this.mode;
    return PrivateMediaPickerSelection(
      mode: nextMode,
      durationSeconds: nextMode == PrivateMediaPickerMode.disappearing
          ? (durationSeconds ?? this.durationSeconds ?? 86400)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrivateMediaPickerSelection &&
      other.mode == mode &&
      other.durationSeconds == durationSeconds;

  @override
  int get hashCode => Object.hash(mode, durationSeconds);
}

IconData privateMediaPickerIcon(PrivateMediaPickerMode mode) => switch (mode) {
  PrivateMediaPickerMode.ordinary => Icons.photo_outlined,
  PrivateMediaPickerMode.protected => Icons.shield_outlined,
  PrivateMediaPickerMode.viewOnce => Icons.looks_one_outlined,
  PrivateMediaPickerMode.disappearing => Icons.schedule_outlined,
};

String privateMediaPickerModeLabel(
  AppLocalizations l10n,
  PrivateMediaPickerSelection selection,
) => switch (selection.mode) {
  PrivateMediaPickerMode.ordinary => l10n.private_media_ordinary,
  PrivateMediaPickerMode.protected => l10n.private_media_protected,
  PrivateMediaPickerMode.viewOnce => l10n.private_media_view_once,
  PrivateMediaPickerMode.disappearing => l10n.private_media_set_expiry,
};

String privateMediaPickerDurationLabel(
  AppLocalizations l10n,
  int? durationSeconds,
) => switch (durationSeconds) {
  3600 => l10n.private_media_duration_1h,
  604800 => l10n.private_media_duration_7d,
  _ => l10n.private_media_duration_1d,
};

String privateMediaPickerSummaryDetail(
  AppLocalizations l10n,
  PrivateMediaPickerSelection selection, {
  required String recipientName,
}) => switch (selection.mode) {
  PrivateMediaPickerMode.ordinary => l10n.private_media_summary_ordinary_detail,
  PrivateMediaPickerMode.protected =>
    l10n.private_media_summary_protected_detail,
  PrivateMediaPickerMode.viewOnce =>
    l10n.private_media_summary_view_once_detail(recipientName),
  PrivateMediaPickerMode.disappearing =>
    l10n.private_media_summary_expiry_detail(
      privateMediaPickerDurationLabel(l10n, selection.durationSeconds),
    ),
};

class PrivateMediaSummaryChip extends StatelessWidget {
  const PrivateMediaSummaryChip({
    super.key,
    required this.selection,
    required this.recipientName,
    required this.onTap,
  });

  final PrivateMediaPickerSelection selection;
  final String recipientName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final title = privateMediaPickerModeLabel(l10n, selection);
    final detail = privateMediaPickerSummaryDetail(
      l10n,
      selection,
      recipientName: recipientName,
    );
    return Semantics(
      button: true,
      label: '$title. $detail. ${l10n.private_media_summary_change}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 10, 9),
            decoration: BoxDecoration(
              color: readable.composerInputFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: readable.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  privateMediaPickerIcon(selection.mode),
                  size: 20,
                  color: readable.sendIcon,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: readable.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: readable.textSecondary,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.private_media_summary_change,
                  style: TextStyle(
                    color: readable.sendIcon,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<PrivateMediaPickerSelection?> showPrivateMediaPolicyPickerSheet({
  required BuildContext context,
  required PrivateMediaPickerSelection initialSelection,
  required PrivateMediaPickerKind kind,
  required String title,
  required String recipientName,
  required TargetPlatform targetPlatform,
  required String optionKeyPrefix,
  bool senderReopenEnabled = false,
}) {
  var provisional =
      initialSelection.mode == PrivateMediaPickerMode.viewOnce &&
          kind != PrivateMediaPickerKind.photo
      ? const PrivateMediaPickerSelection(mode: PrivateMediaPickerMode.ordinary)
      : initialSelection;
  return showModalBottomSheet<PrivateMediaPickerSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final l10n = AppLocalizations.of(context)!;
        final readable = context.backgroundReadableColors;
        final isLight = readable.isLightSurface;
        final surface = isLight
            ? readable.surfaceRaised
            : const Color.fromRGBO(18, 20, 28, 0.97);
        final border = isLight
            ? readable.surfaceBorder
            : const Color.fromRGBO(255, 255, 255, 0.10);
        final disclosure = _disclosure(
          l10n,
          provisional,
          recipientName: recipientName,
          targetPlatform: targetPlatform,
          senderReopenEnabled: senderReopenEnabled,
        );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  key: const ValueKey('private-media-policy-sheet'),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: border),
                  ),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: readable.iconMuted.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          key: const ValueKey('private-media-sheet-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: readable.textPrimary,
                            fontSize: 18,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final mode in PrivateMediaPickerMode.values.where(
                          (candidate) =>
                              candidate != PrivateMediaPickerMode.viewOnce ||
                              kind == PrivateMediaPickerKind.photo,
                        )) ...[
                          _ModeOption(
                            key: ValueKey(
                              '$optionKeyPrefix-${_modeKeySuffix(mode)}',
                            ),
                            mode: mode,
                            selected: provisional.mode == mode,
                            label: _optionLabel(l10n, mode),
                            detail: _optionDetail(
                              l10n,
                              mode,
                              recipientName: recipientName,
                            ),
                            onTap: () => setSheetState(() {
                              provisional = provisional.copyWith(mode: mode);
                            }),
                          ),
                          if (mode == PrivateMediaPickerMode.disappearing &&
                              provisional.mode ==
                                  PrivateMediaPickerMode.disappearing)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                12,
                                2,
                                12,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.private_media_delete_after,
                                    style: TextStyle(
                                      color: readable.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final duration in const [
                                        3600,
                                        86400,
                                        604800,
                                      ])
                                        ChoiceChip(
                                          key: ValueKey(
                                            '$optionKeyPrefix-disappearing-${_durationKeySuffix(duration)}',
                                          ),
                                          label: Text(
                                            privateMediaPickerDurationLabel(
                                              l10n,
                                              duration,
                                            ),
                                          ),
                                          selected:
                                              provisional.durationSeconds ==
                                              duration,
                                          onSelected: (_) => setSheetState(() {
                                            provisional = provisional.copyWith(
                                              mode: PrivateMediaPickerMode
                                                  .disappearing,
                                              durationSeconds: duration,
                                            );
                                          }),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                        Container(
                          key: const ValueKey(
                            'private-media-policy-disclosure',
                          ),
                          margin: const EdgeInsets.only(top: 4, bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: readable.composerInputFill,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: readable.inputBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                privateMediaPickerIcon(provisional.mode),
                                color: readable.sendIcon,
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  disclosure,
                                  style: TextStyle(
                                    color: readable.textSecondary,
                                    height: 1.35,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          key: const ValueKey('private-media-use-mode'),
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(provisional),
                          child: Text(
                            l10n.private_media_use_mode_cta(
                              privateMediaPickerModeLabel(l10n, provisional),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

String _optionLabel(AppLocalizations l10n, PrivateMediaPickerMode mode) =>
    switch (mode) {
      PrivateMediaPickerMode.ordinary => l10n.private_media_ordinary,
      PrivateMediaPickerMode.protected => l10n.private_media_protected,
      PrivateMediaPickerMode.viewOnce => l10n.private_media_view_once,
      PrivateMediaPickerMode.disappearing => l10n.private_media_set_expiry,
    };

String _optionDetail(
  AppLocalizations l10n,
  PrivateMediaPickerMode mode, {
  required String recipientName,
}) => switch (mode) {
  PrivateMediaPickerMode.ordinary => l10n.private_media_ordinary_detail,
  PrivateMediaPickerMode.protected => l10n.private_media_protected_detail,
  PrivateMediaPickerMode.viewOnce => l10n.private_media_view_once_copy,
  PrivateMediaPickerMode.disappearing =>
    l10n.private_media_expiry_choose_detail(recipientName),
};

String _disclosure(
  AppLocalizations l10n,
  PrivateMediaPickerSelection selection, {
  required String recipientName,
  required TargetPlatform targetPlatform,
  required bool senderReopenEnabled,
}) {
  if (selection.mode == PrivateMediaPickerMode.ordinary) {
    return l10n.private_media_summary_ordinary_detail;
  }
  final base = switch (selection.mode) {
    PrivateMediaPickerMode.protected => l10n.private_media_disclosure_protected(
      recipientName,
    ),
    PrivateMediaPickerMode.viewOnce => l10n.private_media_disclosure_view_once(
      recipientName,
    ),
    PrivateMediaPickerMode.disappearing => l10n.private_media_disclosure_expiry(
      recipientName,
    ),
    PrivateMediaPickerMode.ordinary => '',
  };
  final platformNote = switch (targetPlatform) {
    TargetPlatform.iOS => l10n.private_media_ios_capture_limit,
    TargetPlatform.android => l10n.private_media_android_capture_limit,
    _ => l10n.private_media_general_capture_limit,
  };
  final reopen = switch (selection.mode) {
    PrivateMediaPickerMode.protected when senderReopenEnabled =>
      ' ${l10n.private_media_disclosure_reopen_protected}',
    PrivateMediaPickerMode.viewOnce when senderReopenEnabled =>
      ' ${l10n.private_media_disclosure_reopen}',
    _ => '',
  };
  return '$base $platformNote.$reopen';
}

String _modeKeySuffix(PrivateMediaPickerMode mode) => switch (mode) {
  PrivateMediaPickerMode.ordinary => 'ordinary',
  PrivateMediaPickerMode.protected => 'protected',
  PrivateMediaPickerMode.viewOnce => 'view-once',
  PrivateMediaPickerMode.disappearing => 'expiry',
};

String _durationKeySuffix(int duration) => switch (duration) {
  3600 => '1h',
  604800 => '7d',
  _ => '1d',
};

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    super.key,
    required this.mode,
    required this.selected,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final PrivateMediaPickerMode mode;
  final bool selected;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? readable.composerInputFill : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  privateMediaPickerIcon(mode),
                  color: selected ? readable.sendIcon : readable.iconMuted,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: readable.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          color: readable.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                RadioGroup<PrivateMediaPickerMode>(
                  groupValue: selected ? mode : null,
                  onChanged: (_) => onTap(),
                  child: Radio<PrivateMediaPickerMode>(value: mode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
