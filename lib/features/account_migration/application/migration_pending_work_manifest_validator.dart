import 'package:flutter_app/features/account_migration/application/migration_pending_work_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_pending_work_manifest.dart';

class MigrationPendingWorkManifestValidator {
  final MigrationPendingWorkManifestBuilder builder;

  const MigrationPendingWorkManifestValidator({
    this.builder = const MigrationPendingWorkManifestBuilder(),
  });

  MigrationPendingWorkManifest validateRows({
    Iterable<String> fileManifestRelativePaths = const [],
    Iterable<Map<String, Object?>> oneToOneMessageRows = const [],
    Iterable<Map<String, Object?>> oneToOneUnackedMessageRows = const [],
    Iterable<Map<String, Object?>> chatMediaRows = const [],
    Iterable<Map<String, Object?>> postMediaUploadRows = const [],
    Iterable<Map<String, Object?>> postRows = const [],
    Iterable<Map<String, Object?>> postRecipientDeliveryRows = const [],
    Iterable<Map<String, Object?>> postFollowOnEventRows = const [],
    Iterable<Map<String, Object?>> postFollowOnRecipientDeliveryRows = const [],
    Iterable<Map<String, Object?>> introductionOutboxRows = const [],
    Iterable<Map<String, Object?>> pendingIntroductionResponseRows = const [],
    Iterable<Map<String, Object?>> groupMessageRows = const [],
    Iterable<Map<String, Object?>> groupInboxRetryRows = const [],
    Iterable<Map<String, Object?>> groupPendingKeyRepairRows = const [],
    Iterable<Map<String, Object?>> groupPendingMembershipRows = const [],
    Iterable<Map<String, Object?>> groupReactionReplayRows = const [],
  }) {
    return builder.build(
      fileManifestRelativePaths: fileManifestRelativePaths,
      oneToOneMessageRows: oneToOneMessageRows,
      oneToOneUnackedMessageRows: oneToOneUnackedMessageRows,
      chatMediaRows: chatMediaRows,
      postMediaUploadRows: postMediaUploadRows,
      postRows: postRows,
      postRecipientDeliveryRows: postRecipientDeliveryRows,
      postFollowOnEventRows: postFollowOnEventRows,
      postFollowOnRecipientDeliveryRows: postFollowOnRecipientDeliveryRows,
      introductionOutboxRows: introductionOutboxRows,
      pendingIntroductionResponseRows: pendingIntroductionResponseRows,
      groupMessageRows: groupMessageRows,
      groupInboxRetryRows: groupInboxRetryRows,
      groupPendingKeyRepairRows: groupPendingKeyRepairRows,
      groupPendingMembershipRows: groupPendingMembershipRows,
      groupReactionReplayRows: groupReactionReplayRows,
      strictInputValidation: true,
    );
  }
}
