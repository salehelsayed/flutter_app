import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The people a Thought went to lately, newest first. They stay on this
/// phone: the key is not in Move Account's secure storage list.
class ThoughtRecentPicks {
  ThoughtRecentPicks(this._store);

  static const _key = 'thought_recent_picks_v1';
  static const _keep = 3;

  final SecureKeyStore _store;

  Future<List<List<String>>> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null) return const [];
      return [
        for (final pick in jsonDecode(raw) as List)
          [for (final id in pick as List) id as String],
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> remember(List<String> peerIds) async {
    if (peerIds.isEmpty) return;
    final chosen = peerIds.toSet();
    final picks = [
      peerIds,
      for (final pick in await load())
        if (pick.toSet().length != chosen.length ||
            !pick.toSet().containsAll(chosen))
          pick,
    ].take(_keep).toList();
    await _store.write(_key, jsonEncode(picks));
  }
}

/// "to friends · 41" or the picked faces with "to 3 people". Tapping it
/// opens the two-row audience menu.
class ThoughtAudienceChip extends StatelessWidget {
  const ThoughtAudienceChip({
    super.key,
    required this.friendCount,
    required this.picked,
    required this.onTap,
  });

  final int friendCount;
  final List<ContactModel> picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    final label = picked.isEmpty
        ? l10n.thought_audience_to_friends(friendCount)
        : l10n.thought_audience_to_people(picked.length);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('thought-audience-chip'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
              decoration: BoxDecoration(
                color: rc.composerInputFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rc.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (picked.isEmpty)
                    _Dot(color: rc.ring2)
                  else
                    _Faces(peerIds: [for (final c in picked) c.peerId]),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: picked.isEmpty ? rc.textSecondary : rc.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: rc.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum ThoughtAudienceChoice { friends, selectPeople }

/// The audience menu under the chip: friends, or a one-off pick.
Future<ThoughtAudienceChoice?> showThoughtAudienceMenu(
  BuildContext chipContext, {
  required int friendCount,
  required bool picking,
}) {
  final l10n = AppLocalizations.of(chipContext)!;
  final rc = chipContext.backgroundReadableColors;
  final box = chipContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(chipContext).context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(
    Offset(0, box.size.height),
    ancestor: overlay,
  );
  Widget row({
    required Key key,
    required Widget lead,
    required String title,
    required String subtitle,
    required bool selected,
    String? trailing,
  }) => Row(
    key: key,
    children: [
      lead,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: rc.textPrimary, fontSize: 15)),
            Text(subtitle, style: TextStyle(color: rc.textMuted, fontSize: 12)),
          ],
        ),
      ),
      if (trailing != null)
        Text(trailing, style: TextStyle(color: rc.textSecondary, fontSize: 12)),
      if (selected) ...[
        const SizedBox(width: 8),
        Icon(Icons.check_circle_rounded, size: 20, color: rc.accent),
      ],
    ],
  );
  return showMenu<ThoughtAudienceChoice>(
    context: chipContext,
    color: rc.surfaceRaised.withValues(alpha: 1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: rc.divider),
    ),
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
    position: RelativeRect.fromRect(
      topLeft & const Size(280, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: ThoughtAudienceChoice.friends,
        height: 56,
        child: Semantics(
          selected: !picking,
          child: row(
            key: const ValueKey('thought-audience-friends'),
            lead: _Dot(color: rc.ring2, size: 8),
            title: l10n.thought_audience_friends,
            subtitle: l10n.thought_audience_friends_desc,
            trailing: '$friendCount',
            selected: !picking,
          ),
        ),
      ),
      PopupMenuItem(
        value: ThoughtAudienceChoice.selectPeople,
        height: 56,
        child: Semantics(
          selected: picking,
          child: row(
            key: const ValueKey('thought-audience-select'),
            lead: Icon(
              Icons.person_add_alt_rounded,
              size: 18,
              color: rc.accent,
            ),
            title: l10n.thought_audience_select,
            subtitle: l10n.thought_audience_select_desc,
            selected: picking,
          ),
        ),
      ),
    ],
  );
}

/// "Who sees this": a one-off pick of friends for this Thought only.
/// Pops with the chosen peer ids, or null on Cancel.
class ThoughtPeoplePickerSheet extends StatefulWidget {
  const ThoughtPeoplePickerSheet({
    super.key,
    required this.contacts,
    required this.initial,
    this.recentPicks = const [],
  });

  final List<ContactModel> contacts;
  final Set<String> initial;
  final List<List<String>> recentPicks;

  @override
  State<ThoughtPeoplePickerSheet> createState() =>
      _ThoughtPeoplePickerSheetState();
}

class _ThoughtPeoplePickerSheetState extends State<ThoughtPeoplePickerSheet> {
  late final Set<String> _chosen = {...widget.initial};
  final TextEditingController _search = TextEditingController();

  late final Map<String, ContactModel> _byId = {
    for (final contact in widget.contacts) contact.peerId: contact,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String peerId) => setState(
    () =>
        _chosen.contains(peerId) ? _chosen.remove(peerId) : _chosen.add(peerId),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final contact in widget.contacts)
        if (query.isEmpty || contact.username.toLowerCase().contains(query))
          contact,
    ];
    final picks = [
      for (final pick in widget.recentPicks)
        [for (final id in pick) ?_byId[id]],
    ].where((pick) => pick.isNotEmpty).toList();
    final chosen = [
      for (final contact in widget.contacts)
        if (_chosen.contains(contact.peerId)) contact,
    ];
    final section = TextStyle(color: rc.textMuted, fontSize: 12);
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: rc.surfaceRaised.withValues(alpha: 1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 2),
                child: Row(
                  children: [
                    TextButton(
                      key: const ValueKey('thought-pick-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: rc.textSecondary,
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      child: Text(l10n.btn_cancel),
                    ),
                    Expanded(
                      child: Text(
                        l10n.thought_pick_title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: rc.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      key: const ValueKey('thought-pick-done'),
                      onPressed: _chosen.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(<String>{
                              for (final contact in chosen) contact.peerId,
                            }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rc.accent,
                        foregroundColor: rc.accent.computeLuminance() > .3
                            ? const Color(0xFF0A0A0F)
                            : Colors.white,
                        disabledBackgroundColor: rc.disabledSurface,
                        disabledForegroundColor: rc.disabledForeground,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        minimumSize: const Size(72, 36),
                      ),
                      child: Text(l10n.thought_pick_done(chosen.length)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: TextField(
                  key: const ValueKey('thought-pick-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: rc.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: l10n.thought_pick_search,
                    hintStyle: TextStyle(color: rc.placeholderText),
                    prefixIcon: Icon(Icons.search_rounded, color: rc.iconMuted),
                    isDense: true,
                    filled: true,
                    fillColor: rc.composerInputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: rc.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: rc.divider),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (chosen.isNotEmpty)
                      SizedBox(
                        height: 82,
                        child: ListView(
                          key: const ValueKey('thought-pick-chosen'),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          children: [
                            for (final contact in chosen)
                              _ChosenFace(
                                contact: contact,
                                onRemove: () => _toggle(contact.peerId),
                              ),
                          ],
                        ),
                      ),
                    if (query.isEmpty && picks.isNotEmpty) ...[
                      _Section(l10n.thought_pick_recent, style: section),
                      for (final pick in picks)
                        _RecentPickRow(
                          pick: pick,
                          onTap: () => setState(
                            () => _chosen
                              ..clear()
                              ..addAll([for (final c in pick) c.peerId]),
                          ),
                        ),
                    ],
                    _Section(
                      l10n.thought_pick_everyone(widget.contacts.length),
                      style: section,
                    ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          l10n.thought_pick_no_match,
                          style: TextStyle(color: rc.textMuted),
                        ),
                      ),
                    for (final contact in shown)
                      _PersonRow(
                        contact: contact,
                        checked: _chosen.contains(contact.peerId),
                        onTap: () => _toggle(contact.peerId),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: _Dot(color: rc.textMuted, size: 6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.thought_pick_footer,
                        key: const ValueKey('thought-pick-footer'),
                        style: TextStyle(
                          color: rc.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, {required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Semantics(header: true, child: Text(label, style: style)),
  );
}

class _ChosenFace extends StatelessWidget {
  const _ChosenFace({required this.contact, required this.onRemove});

  final ContactModel contact;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final rc = context.backgroundReadableColors;
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(peerId: contact.peerId, size: 44),
              PositionedDirectional(
                end: -10,
                top: -10,
                child: Semantics(
                  container: true,
                  button: true,
                  label: AppLocalizations.of(
                    context,
                  )!.thought_pick_remove(contact.username),
                  onTap: onRemove,
                  excludeSemantics: true,
                  child: InkResponse(
                    key: ValueKey('thought-pick-remove-${contact.peerId}'),
                    onTap: onRemove,
                    radius: 22,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: rc.surfaceSubtle,
                            shape: BoxShape.circle,
                            border: Border.all(color: rc.divider),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: rc.iconSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            contact.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: rc.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _RecentPickRow extends StatelessWidget {
  const _RecentPickRow({required this.pick, required this.onTap});

  final List<ContactModel> pick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.backgroundReadableColors;
    final names = [for (final c in pick) c.username].join(', ');
    return InkWell(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: names,
        onTap: onTap,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _Faces(peerIds: [for (final c in pick) c.peerId], size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: rc.textPrimary, fontSize: 15),
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.contact,
    required this.checked,
    required this.onTap,
  });

  final ContactModel contact;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.backgroundReadableColors;
    return Semantics(
      checked: checked,
      label: contact.username,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('thought-pick-${contact.peerId}'),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                UserAvatar(peerId: contact.peerId, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    contact.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: rc.textPrimary, fontSize: 15),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: checked ? rc.accent : Colors.transparent,
                    border: Border.all(
                      color: checked ? rc.accent : rc.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: checked
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: rc.accent.computeLuminance() > .3
                              ? const Color(0xFF0A0A0F)
                              : Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three overlapping faces.
class _Faces extends StatelessWidget {
  const _Faces({required this.peerIds, this.size = 20});

  final List<String> peerIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = peerIds.take(3).toList();
    final step = size * .7;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            PositionedDirectional(
              start: step * i,
              child: UserAvatar(peerId: shown[i], size: size),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// "layla, omar and nour see this for 24 hours", from the picked names.
String thoughtPickedLifetime(AppLocalizations l10n, List<String> names) =>
    switch (names) {
      [final a] => l10n.thought_compose_lifetime_one(a),
      [final a, final b] => l10n.thought_compose_lifetime_two(a, b),
      [final a, final b, final c] => l10n.thought_compose_lifetime_three(
        a,
        b,
        c,
      ),
      [final a, final b, ...final rest] => l10n.thought_compose_lifetime_more(
        a,
        b,
        rest.length,
      ),
      [] => l10n.thought_compose_lifetime,
    };
