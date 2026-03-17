import 'package:flutter/material.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

enum PassPostAlongSubmitOutcome { closeSheet, keepSheetOpen }

class PassPostAlongSheet extends StatefulWidget {
  final List<ContactModel> eligibleContacts;
  final Future<void> Function(List<String> recipientPeerIds)? onSubmit;
  final Future<PassPostAlongSubmitOutcome> Function(
    List<String> recipientPeerIds,
  )?
  onSubmitWithOutcome;

  const PassPostAlongSheet({
    super.key,
    required this.eligibleContacts,
    this.onSubmit,
    this.onSubmitWithOutcome,
  }) : assert(
         onSubmit != null || onSubmitWithOutcome != null,
         'Either onSubmit or onSubmitWithOutcome must be provided.',
       ),
       assert(
         onSubmit == null || onSubmitWithOutcome == null,
         'Use only one of onSubmit or onSubmitWithOutcome.',
       );

  @override
  State<PassPostAlongSheet> createState() => _PassPostAlongSheetState();
}

class _PassPostAlongSheetState extends State<PassPostAlongSheet> {
  final Set<String> _selectedPeerIds = <String>{};
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF11161D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pass along',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose who should receive this one-hop pass.',
              style: TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.eligibleContacts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'No eligible friends available right now.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.eligibleContacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final contact = widget.eligibleContacts[index];
                    final isSelected = _selectedPeerIds.contains(
                      contact.peerId,
                    );
                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: const Color(0xFF8FD6B5),
                      checkColor: const Color(0xFF11161D),
                      tileColor: const Color(0xFF171A20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      title: Text(
                        contact.username,
                        style: const TextStyle(color: Colors.white),
                      ),
                      onChanged: _isSubmitting
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedPeerIds.add(contact.peerId);
                                } else {
                                  _selectedPeerIds.remove(contact.peerId);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting || _selectedPeerIds.isEmpty
                    ? null
                    : () async {
                        setState(() => _isSubmitting = true);
                        try {
                          final outcome = await _submitPass();
                          if (outcome ==
                                  PassPostAlongSubmitOutcome.closeSheet &&
                              mounted) {
                            Navigator.of(context).pop();
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isSubmitting = false);
                          }
                        }
                      },
                child: Text(_isSubmitting ? 'Sending…' : 'Send pass'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<PassPostAlongSubmitOutcome> _submitPass() async {
    final onSubmitWithOutcome = widget.onSubmitWithOutcome;
    if (onSubmitWithOutcome != null) {
      return onSubmitWithOutcome(_selectedPeerIds.toList(growable: false));
    }

    await widget.onSubmit!(_selectedPeerIds.toList(growable: false));
    return PassPostAlongSubmitOutcome.closeSheet;
  }
}
