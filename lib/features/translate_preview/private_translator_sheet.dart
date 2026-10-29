import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "2.6 GB" in the app language. Arabic keeps Latin digits, as the approved
/// copy writes "2.6 غيغابايت".
String translatorSize(BuildContext context, int bytes) => AppLocalizations.of(
  context,
)!.translator_size_gb(_gigabytes(context, bytes));

/// "1.1 of 2.6 GB".
String translatorAmount(BuildContext context, int received, int total) =>
    AppLocalizations.of(context)!.translator_progress_amount(
      _gigabytes(context, received),
      translatorSize(context, total),
    );

String _gigabytes(BuildContext context, int bytes) {
  final language = Localizations.localeOf(context).languageCode;
  return NumberFormat(
    '0.0',
    language == 'de' ? 'de' : 'en',
  ).format(bytes / 1000000000);
}

/// The one download sheet, opened from a link or from Settings. It follows
/// [controller] in place and closes itself once the translator is ready.
Future<void> showPrivateTranslatorSheet(
  BuildContext context, {
  required ModelDeliveryController controller,
  VoidCallback? onFreeUpSpace,
}) async {
  await controller.refresh();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PrivateTranslatorSheet(
      controller: controller,
      onFreeUpSpace: onFreeUpSpace,
    ),
  );
}

class PrivateTranslatorSheet extends StatelessWidget {
  const PrivateTranslatorSheet({
    super.key,
    required this.controller,
    this.onFreeUpSpace,
  });

  final ModelDeliveryController controller;

  /// Opens the Storage section. Null where the host has no route to it; the
  /// button then shows disabled.
  final VoidCallback? onFreeUpSpace;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ModelDeliveryState>(
        valueListenable: controller.state,
        builder: (context, state, _) {
          if (state is ModelReady || state is ModelUnsupported) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 16),
              child: _body(context, state),
            ),
          );
        },
      );

  Widget _body(BuildContext context, ModelDeliveryState state) {
    final l10n = AppLocalizations.of(context)!;
    void close() => Navigator.of(context).maybePop();
    return switch (state) {
      ModelNotDownloaded(:final totalBytes, :final freeBytes, :final onWifi) =>
        _SheetLayout(
          title: l10n.translator_sheet_title,
          line: l10n.translator_sheet_line(translatorSize(context, totalBytes)),
          sizes: (
            l10n.translator_sheet_download_size(
              translatorSize(context, totalBytes),
            ),
            l10n.translator_sheet_free(translatorSize(context, freeBytes)),
          ),
          privacy: l10n.translator_sheet_privacy,
          primary: (
            onWifi
                ? l10n.translator_download_on_wifi
                : l10n.translator_download_when_wifi,
            () => unawaited(controller.start(allowMobileData: false)),
          ),
          secondary: onWifi
              ? (l10n.translator_not_now, close)
              : (
                  l10n.translator_use_mobile_data_instead,
                  () => unawaited(controller.start(allowMobileData: true)),
                ),
        ),
      ModelNotEnoughSpace(
        :final totalBytes,
        :final neededBytes,
        :final freeBytes,
      ) =>
        _SheetLayout(
          title: l10n.translator_sheet_title,
          line: l10n.translator_sheet_line(translatorSize(context, totalBytes)),
          sizes: (
            l10n.translator_sheet_needs(translatorSize(context, neededBytes)),
            l10n.translator_sheet_free(translatorSize(context, freeBytes)),
          ),
          privacy: l10n.translator_sheet_privacy,
          primary: (l10n.translator_download_on_wifi, null),
          secondary: (
            l10n.translator_free_up_space,
            onFreeUpSpace == null
                ? null
                : () {
                    close();
                    onFreeUpSpace!();
                  },
          ),
        ),
      ModelDownloading(
        :final receivedBytes,
        :final totalBytes,
        :final remaining,
      ) =>
        _SheetLayout(
          title: l10n.translator_progress_title,
          progress: (
            state.percent / 100,
            translatorAmount(context, receivedBytes, totalBytes),
            remaining == null
                ? null
                : l10n.translator_progress_minutes_left(
                    '${(remaining.inSeconds / 60).ceil().clamp(1, 999)}',
                  ),
          ),
          line: l10n.translator_progress_keeps_going,
          primary: (l10n.translator_close, close),
          secondary: (
            l10n.translator_pause,
            () => unawaited(controller.pause()),
          ),
        ),
      final ModelDeliveryInProgress waiting => _SheetLayout(
        title: l10n.translator_waiting_title,
        progress: (
          waiting.percent / 100,
          translatorAmount(context, waiting.receivedBytes, waiting.totalBytes),
          l10n.translator_paused_word,
        ),
        line: l10n.translator_waiting_line,
        primary: (
          l10n.translator_use_mobile_data,
          () => unawaited(controller.start(allowMobileData: true)),
        ),
        secondary: (l10n.translator_close, close),
      ),
      ModelFailed() => _SheetLayout(
        title: l10n.translator_failed_title,
        line: l10n.translator_failed_line,
        primary: (
          l10n.translator_try_again,
          () => unawaited(controller.retry()),
        ),
        secondary: (l10n.translator_not_now, close),
      ),
      ModelReady() || ModelUnsupported() => const SizedBox.shrink(),
    };
  }
}

typedef _Action = (String label, VoidCallback? onPressed);

class _SheetLayout extends StatelessWidget {
  const _SheetLayout({
    required this.title,
    required this.line,
    required this.primary,
    required this.secondary,
    this.sizes,
    this.privacy,
    this.progress,
  });

  final String title;
  final String line;
  final (String start, String end)? sizes;
  final String? privacy;
  final (double value, String amount, String? note)? progress;
  final _Action primary;
  final _Action secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (progress case (final value, final amount, final note)) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: value),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(amount, style: theme.textTheme.bodyMedium)),
              if (note != null)
                Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(line, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        if (sizes case (final start, final end)) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: Text(start, style: theme.textTheme.bodyMedium)),
                Text(
                  end,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
        if (privacy case final privacy?) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6, end: 8),
                child: Icon(
                  Icons.circle,
                  size: 8,
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(child: Text(privacy, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
        const SizedBox(height: 4),
        TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
      ],
    );
  }
}
