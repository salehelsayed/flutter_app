import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/presentation/group_invite_status_presentation.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('groupInviteStatusLabel maps every status without crashing', () {
    // Exhaustive over the enum — locks that revoked/declined have labels.
    for (final status in GroupInviteDeliveryStatus.values) {
      final label = groupInviteStatusLabel(l10n, status);
      expect(label, isNotEmpty);
    }
  });

  test('revoked and declined produce their dedicated localized labels', () {
    expect(
      groupInviteStatusLabel(l10n, GroupInviteDeliveryStatus.revoked),
      l10n.invite_status_revoked,
    );
    expect(
      groupInviteStatusLabel(l10n, GroupInviteDeliveryStatus.declined),
      l10n.invite_status_declined,
    );
  });
}
