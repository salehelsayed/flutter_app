import 'package:flutter_app/features/groups/application/group_exit_policy.dart';

GroupDissolvePreflightAuthority? _authority;

/// Installs the concrete, fail-closed authority for the separate Dissolve flow.
void setGroupDissolvePreflightAuthority(
  GroupDissolvePreflightAuthority? authority,
) {
  _authority = authority;
}

/// Resolves the authority at the last UI-to-use-case boundary.
///
/// Missing production wiring throws before signing, publishing, or native
/// mutation, rather than representing unavailable storage as an empty queue.
GroupDissolvePreflightAuthority requireGroupDissolvePreflightAuthority() {
  final authority = _authority;
  if (authority == null) {
    throw StateError('Group dissolve preflight authority is unavailable.');
  }
  return authority;
}
