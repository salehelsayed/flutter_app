import 'package:flutter_app/l10n/app_localizations.dart';

import '../domain/update_check_models.dart';

/// Built-in text per reason code. Unknown codes were already mapped to
/// [UpdateReasonCode.general] when the payload was parsed.
String updateRequiredBody(AppLocalizations l10n, UpdateReasonCode code) =>
    switch (code) {
      UpdateReasonCode.general => l10n.update_required_body_general,
      UpdateReasonCode.security => l10n.update_required_body_security,
      UpdateReasonCode.protocolChange =>
        l10n.update_required_body_protocol_change,
      UpdateReasonCode.criticalFix => l10n.update_required_body_critical_fix,
    };

String updateAvailableMessage(AppLocalizations l10n, UpdateReasonCode code) =>
    switch (code) {
      UpdateReasonCode.general => l10n.update_available_general,
      UpdateReasonCode.security => l10n.update_available_security,
      UpdateReasonCode.protocolChange => l10n.update_available_protocol_change,
      UpdateReasonCode.criticalFix => l10n.update_available_critical_fix,
    };
