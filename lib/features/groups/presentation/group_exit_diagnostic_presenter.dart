import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

const groupExitCodeLeftToRightIsolate = '\u2066';
const groupExitCodePopDirectionalIsolate = '\u2069';

/// The one public-code presentation vocabulary shared by exit surfaces,
/// recovery, and release Settings history.
String localizedGroupExitDiagnosticSummary(
  AppLocalizations l10n,
  GroupExitDiagnosticPublicCode code,
) => switch (code) {
  GroupExitDiagnosticPublicCode.ex01 =>
    l10n.settings_group_exit_diagnostic_ex01,
  GroupExitDiagnosticPublicCode.ex02 =>
    l10n.settings_group_exit_diagnostic_ex02,
  GroupExitDiagnosticPublicCode.ex03 =>
    l10n.settings_group_exit_diagnostic_ex03,
  GroupExitDiagnosticPublicCode.ex04 =>
    l10n.settings_group_exit_diagnostic_ex04,
  GroupExitDiagnosticPublicCode.ex05 =>
    l10n.settings_group_exit_diagnostic_ex05,
  GroupExitDiagnosticPublicCode.ex06 =>
    l10n.settings_group_exit_diagnostic_ex06,
  GroupExitDiagnosticPublicCode.ex07 =>
    l10n.settings_group_exit_diagnostic_ex07,
  GroupExitDiagnosticPublicCode.ex08 =>
    l10n.settings_group_exit_diagnostic_ex08,
  GroupExitDiagnosticPublicCode.ex09 =>
    l10n.settings_group_exit_diagnostic_ex09,
  GroupExitDiagnosticPublicCode.ex10 =>
    l10n.settings_group_exit_diagnostic_ex10,
  GroupExitDiagnosticPublicCode.ex99 =>
    l10n.settings_group_exit_diagnostic_ex99,
};

String isolatedGroupExitPublicCode(GroupExitDiagnosticPublicCode code) =>
    '$groupExitCodeLeftToRightIsolate${code.databaseValue}'
    '$groupExitCodePopDirectionalIsolate';

String presentGroupExitDiagnostic(
  AppLocalizations l10n,
  GroupExitDiagnosticPublicCode code, {
  String? leading,
}) {
  final explanation = localizedGroupExitDiagnosticSummary(l10n, code);
  final codeToken = isolatedGroupExitPublicCode(code);
  final prefix = leading?.trim();
  if (prefix == null || prefix.isEmpty) {
    return '$codeToken — $explanation';
  }
  return '$prefix $codeToken — $explanation';
}

/// Selects one actionable code for immediate presentation without changing the
/// underlying result. The first failure wins; warnings are used only when no
/// failure exists.
GroupExitDiagnosticPublicCode? primaryGroupExitPublicCode(
  Iterable<GroupExitProcessDiagnosticFact> facts,
) {
  GroupExitProcessDiagnosticFact? warning;
  for (final fact in facts) {
    if (groupExitSeverityForFact(fact) == GroupExitDiagnosticSeverity.failure) {
      return groupExitPublicCodeForFact(fact);
    }
    warning = fact;
  }
  return warning == null ? null : groupExitPublicCodeForFact(warning);
}
