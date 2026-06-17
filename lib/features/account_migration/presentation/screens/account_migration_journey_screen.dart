import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/presentation/models/account_migration_ui_state.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AccountMigrationJourneyScreen extends StatelessWidget {
  final AccountMigrationRole role;
  final AccountMigrationQrPresentationState qrState;
  final AccountMigrationOldPhonePresentationState oldPhoneState;
  final AccountMigrationProgressStage? progressStage;
  final String? progressErrorText;

  /// Determinate fraction (0..1) for the transferring stage's progress bar;
  /// null keeps the bar indeterminate.
  final double? transferProgressFraction;

  /// Short caption under the bar, e.g. "12 of 34 · about 15s left".
  final String? transferProgressDetail;
  final VoidCallback? onClose;
  final VoidCallback? onRetryQr;
  final VoidCallback? onScanQr;
  final VoidCallback? onStartTransfer;
  final VoidCallback? onCancelTransfer;
  final VoidCallback? onRetryTransfer;
  final BackgroundPreference backgroundPreference;

  const AccountMigrationJourneyScreen({
    super.key,
    required this.role,
    this.qrState = const AccountMigrationQrPresentationState.loading(),
    this.oldPhoneState =
        const AccountMigrationOldPhonePresentationState.waitingForScan(),
    this.progressStage,
    this.progressErrorText,
    this.transferProgressFraction,
    this.transferProgressDetail,
    this.onClose,
    this.onRetryQr,
    this.onScanQr,
    this.onStartTransfer,
    this.onCancelTransfer,
    this.onRetryTransfer,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = BackgroundReadableColors.resolve(
      backgroundPreference,
    );
    final isNewPhone = role == AccountMigrationRole.newPhone;

    return Scaffold(
      backgroundColor: readableColors.surfaceBase,
      body: AmbientBackground(
        preference: backgroundPreference,
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      isNewPhone
                          ? Icons.phone_iphone_outlined
                          : Icons.phonelink_setup_outlined,
                      color: AppColors.primaryAccent,
                      size: 44,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isNewPhone
                          ? 'Move from old phone'
                          : 'Move account to new phone',
                      key: const ValueKey('account-migration-journey-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: readableColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isNewPhone
                          ? 'Use your old phone to scan this migration QR.'
                          : 'Scan the migration QR shown on your new phone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: readableColors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (progressStage != null)
                      AccountMigrationProgressWakeLock(
                        stage: progressStage,
                        active: true,
                        child: _ProgressPanel(
                          stage: progressStage!,
                          errorText: progressErrorText,
                          progressFraction: transferProgressFraction,
                          progressDetail: transferProgressDetail,
                          onCancel: onCancelTransfer,
                          onRetry: onRetryTransfer,
                        ),
                      )
                    else if (isNewPhone)
                      _NewPhonePanel(qrState: qrState, onRetry: onRetryQr)
                    else
                      _OldPhonePanel(
                        state: oldPhoneState,
                        onScanQr: onScanQr,
                        onStartTransfer: onStartTransfer,
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filledTonal(
                  key: const ValueKey('account-migration-close'),
                  tooltip: AppLocalizations.of(context)!.account_migration_back,
                  style: IconButton.styleFrom(
                    backgroundColor: readableColors.surfaceRaised,
                    foregroundColor: readableColors.iconPrimary,
                    side: BorderSide(color: readableColors.border),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountMigrationProgressWakeLock extends StatefulWidget {
  final AccountMigrationProgressStage? stage;
  final bool active;
  final Widget child;

  const AccountMigrationProgressWakeLock({
    super.key,
    required this.stage,
    required this.active,
    required this.child,
  });

  @override
  State<AccountMigrationProgressWakeLock> createState() =>
      _AccountMigrationProgressWakeLockState();
}

class _AccountMigrationProgressWakeLockState
    extends State<AccountMigrationProgressWakeLock> {
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _syncWakeLock();
  }

  @override
  void didUpdateWidget(AccountMigrationProgressWakeLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWakeLock();
  }

  @override
  void dispose() {
    if (_held) {
      _held = false;
      unawaited(UploadWakeLockController.release());
    }
    super.dispose();
  }

  void _syncWakeLock() {
    final shouldHold = widget.active && (widget.stage?.holdsWakeLock ?? false);
    if (shouldHold == _held) {
      return;
    }
    _held = shouldHold;
    if (shouldHold) {
      unawaited(UploadWakeLockController.acquire());
    } else {
      unawaited(UploadWakeLockController.release());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NewPhonePanel extends StatelessWidget {
  final AccountMigrationQrPresentationState qrState;
  final VoidCallback? onRetry;

  const _NewPhonePanel({required this.qrState, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    switch (qrState.status) {
      case AccountMigrationQrPresentationStatus.loading:
        return const _GlassPanel(
          key: ValueKey('account-migration-qr-loading'),
          child: _CenteredStatus(
            icon: Icons.hourglass_top_outlined,
            title: 'Creating secure pairing code',
            body: 'Keep this screen open while the migration QR is prepared.',
            showSpinner: true,
          ),
        );
      case AccountMigrationQrPresentationStatus.ready:
        return _GlassPanel(
          key: const ValueKey('account-migration-qr-ready'),
          child: Column(
            children: [
              Text(
                l10n.account_migration_qr_heading,
                key: const ValueKey('account-migration-qr-heading'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: readableColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _MigrationQrImage(data: qrState.qrJson!),
              const SizedBox(height: 12),
              Text(
                l10n.account_migration_qr_confirm_label,
                key: const ValueKey(
                  'account-migration-new-phone-confirmation-label',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: readableColors.textMuted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                qrState.confirmationCode!,
                key: const ValueKey(
                  'account-migration-new-phone-confirmation-code',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: readableColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.account_migration_qr_expires_at(
                  _formatTime(qrState.expiresAt!),
                ),
                key: const ValueKey('account-migration-qr-expiry'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: readableColors.textMuted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      case AccountMigrationQrPresentationStatus.keygenFailed:
        return _FailurePanel(
          key: const ValueKey('account-migration-qr-keygen-failed'),
          title: 'Could not create migration keys',
          body: 'The new phone could not prepare a secure pairing code.',
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      case AccountMigrationQrPresentationStatus.persistenceFailed:
        return _FailurePanel(
          key: const ValueKey('account-migration-qr-persistence-failed'),
          title: 'Could not save pairing session',
          body:
              'The migration QR was not shown because the session could not be saved.',
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      case AccountMigrationQrPresentationStatus.receiverFailed:
        return _FailurePanel(
          key: const ValueKey('account-migration-qr-receiver-failed'),
          title: 'Could not start local transfer',
          body:
              qrState.errorText ??
              'This phone could not listen for the old phone. Try again.',
          actionLabel: 'Try again',
          onAction: onRetry,
        );
    }
  }
}

class _OldPhonePanel extends StatelessWidget {
  final AccountMigrationOldPhonePresentationState state;
  final VoidCallback? onScanQr;
  final VoidCallback? onStartTransfer;

  const _OldPhonePanel({
    required this.state,
    this.onScanQr,
    this.onStartTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    switch (state.status) {
      case AccountMigrationOldPhoneStatus.waitingForScan:
        return _GlassPanel(
          key: const ValueKey('account-migration-old-phone-scan'),
          child: Column(
            children: [
              const _CenteredStatus(
                icon: Icons.qr_code_scanner_outlined,
                title: 'Scan the migration QR',
                body: 'Only Move Account QR codes are accepted here.',
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                key: const ValueKey('account-migration-scan-action'),
                icon: Icons.qr_code_scanner_outlined,
                label: AppLocalizations.of(context)!.account_migration_scan_action,
                onPressed: onScanQr,
              ),
            ],
          ),
        );
      case AccountMigrationOldPhoneStatus.authorizing:
        return const _GlassPanel(
          key: ValueKey('account-migration-authorizing'),
          child: _CenteredStatus(
            icon: Icons.verified_user_outlined,
            title: 'Checking migration QR',
            body: 'Confirming this is a Move Account pairing request.',
            showSpinner: true,
          ),
        );
      case AccountMigrationOldPhoneStatus.confirmationReady:
        return _GlassPanel(
          key: const ValueKey('account-migration-confirmation-ready'),
          child: Column(
            children: [
              const _CenteredStatus(
                icon: Icons.password_outlined,
                title: 'Confirm the code',
                body: 'Make sure the same six digits are shown on both phones.',
              ),
              const SizedBox(height: 16),
              Text(
                state.confirmationCode!,
                key: const ValueKey('account-migration-confirmation-code'),
                style: TextStyle(
                  color: readableColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
              if (state.sizeEstimate != null) ...[
                const SizedBox(height: 14),
                Text(
                  accountMigrationSizeEstimateLabel(
                    state.sizeEstimate!.totalBytes,
                  ),
                  key: const ValueKey('account-migration-size-estimate'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: readableColors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              if (state.sizeCapBlockedMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.sizeCapBlockedMessage!,
                  key: const ValueKey('account-migration-size-cap-blocked'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: readableColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _PrimaryButton(
                key: const ValueKey('account-migration-start-transfer'),
                icon: Icons.play_arrow_rounded,
                label: AppLocalizations.of(context)!.account_migration_start_transfer,
                onPressed: state.sizeCapBlockedMessage == null
                    ? onStartTransfer
                    : null,
              ),
            ],
          ),
        );
      case AccountMigrationOldPhoneStatus.failed:
        return _FailurePanel(
          key: const ValueKey('account-migration-old-phone-failed'),
          title: 'Migration QR rejected',
          body: state.errorText ?? 'This QR code could not be used.',
          actionLabel: 'Scan again',
          onAction: onScanQr,
        );
    }
  }
}

class _ProgressPanel extends StatelessWidget {
  final AccountMigrationProgressStage stage;
  final String? errorText;
  final double? progressFraction;
  final String? progressDetail;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  const _ProgressPanel({
    required this.stage,
    this.errorText,
    this.progressFraction,
    this.progressDetail,
    this.onCancel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final copy = _copyFor(stage);
    final terminal = stage.isTerminal;

    return _GlassPanel(
      key: ValueKey('account-migration-progress-${stage.name}'),
      child: Column(
        children: [
          Icon(
            terminal ? Icons.info_outline : Icons.sync_rounded,
            color: terminal
                ? readableColors.iconMuted
                : AppColors.primaryAccent,
            size: 36,
          ),
          const SizedBox(height: 14),
          Text(
            copy.title,
            key: ValueKey('account-migration-progress-title-${stage.name}'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: readableColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: readableColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (!terminal) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                key: const ValueKey('account-migration-progress-bar'),
                // Determinate while segment counts stream in; indeterminate
                // for the stages without a measurable denominator.
                value: progressFraction,
                minHeight: 6,
                backgroundColor: const Color(0x3327F5D8),
                color: AppColors.primaryAccent,
              ),
            ),
            if (progressDetail != null) ...[
              const SizedBox(height: 8),
              Text(
                progressDetail!,
                key: const ValueKey('account-migration-progress-detail'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: readableColors.textMuted,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SecondaryButton(
              key: const ValueKey('account-migration-cancel-transfer'),
              label: l10n.account_migration_cancel_transfer,
              onPressed: onCancel,
            ),
          ] else if (stage == AccountMigrationProgressStage.failed) ...[
            const SizedBox(height: 18),
            _PrimaryButton(
              key: const ValueKey('account-migration-retry-transfer'),
              icon: Icons.refresh,
              label: l10n.account_migration_retry,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }

  _ProgressCopy _copyFor(AccountMigrationProgressStage stage) {
    switch (stage) {
      case AccountMigrationProgressStage.preparing:
        return const _ProgressCopy(
          'Preparing transfer',
          'Checking account data before anything leaves this phone.',
        );
      case AccountMigrationProgressStage.connecting:
        return const _ProgressCopy(
          'Connecting phones',
          'Keeping the foreground session active while the phones pair.',
        );
      case AccountMigrationProgressStage.encrypting:
        return const _ProgressCopy(
          'Encrypting account bundle',
          'Preparing encrypted account data for the new phone.',
        );
      case AccountMigrationProgressStage.transferringDatabase:
        return const _ProgressCopy(
          'Transferring database',
          'Moving messages, contacts, settings, and local account records.',
        );
      case AccountMigrationProgressStage.transferringMedia:
        return const _ProgressCopy(
          'Transferring media',
          'Moving local attachments that belong with your account.',
        );
      case AccountMigrationProgressStage.checking:
        return const _ProgressCopy(
          'Checking transferred data',
          'Verifying the new phone can read the moved account bundle.',
        );
      case AccountMigrationProgressStage.finishing:
        return const _ProgressCopy(
          'Finishing move',
          'Waiting for the final migration handoff to complete.',
        );
      case AccountMigrationProgressStage.completed:
        return const _ProgressCopy(
          'Transfer complete',
          'The migration transfer finished on this phone.',
        );
      case AccountMigrationProgressStage.cancelled:
        return const _ProgressCopy(
          'Move cancelled',
          'No account data was erased by this screen.',
        );
      case AccountMigrationProgressStage.failed:
        return _ProgressCopy(
          'Move failed',
          errorText ?? 'The account move stopped before final handoff.',
        );
    }
  }
}

class _MigrationQrImage extends StatelessWidget {
  final String data;

  const _MigrationQrImage({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(220.0, 300.0).toDouble()
            : 300.0;

        return Center(
          child: Container(
            key: const ValueKey('account-migration-qr-image'),
            width: side,
            height: side,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.greenGlow.withValues(alpha: 0.25),
                  blurRadius: 32,
                ),
              ],
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;

  const _GlassPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: readableColors.glassSurface,
        border: Border.all(color: readableColors.glassBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool showSpinner;

  const _CenteredStatus({
    required this.icon,
    required this.title,
    required this.body,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Column(
      children: [
        Icon(icon, color: AppColors.primaryAccent, size: 36),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: readableColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: readableColors.textMuted,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (showSpinner) ...[
          const SizedBox(height: 16),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}

class _FailurePanel extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  const _FailurePanel({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return _GlassPanel(
      child: Column(
        children: [
          const _CenteredStatus(
            icon: Icons.error_outline,
            title: 'Move Account needs attention',
            body: 'Review the message below and try again.',
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: readableColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: readableColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            icon: Icons.refresh,
            label: actionLabel,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryAccent,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(46),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.backgroundReadableColors.textPrimary,
        minimumSize: const Size.fromHeight(44),
      ),
      child: Text(label),
    );
  }
}

class _ProgressCopy {
  final String title;
  final String body;

  const _ProgressCopy(this.title, this.body);
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
