import 'package:flutter/material.dart';
import 'package:flutter_app/features/qr_code/presentation/widgets/contact_invite_host.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class ContactInviteActions extends StatelessWidget {
  const ContactInviteActions({super.key});

  @override
  Widget build(BuildContext context) {
    final paste = ContactInviteHost.pasteActionOf(context);
    final share = ContactInviteHost.shareActionOf(context);
    if (paste == null && share == null) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (share != null) ...[
          TextButton.icon(
            onPressed: share,
            icon: const Icon(Icons.ios_share),
            label: Text(copy.contact_invite_share),
          ),
          Text(
            copy.contact_invite_share_expiry,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (paste != null)
          TextButton.icon(
            onPressed: paste,
            icon: const Icon(Icons.link),
            label: Text(copy.contact_invite_paste),
          ),
      ],
    );
  }
}
