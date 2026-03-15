import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

class ComposePostResult {
  final String text;
  final PostAudience audience;

  const ComposePostResult({required this.text, required this.audience});
}

class ComposePostSheet extends StatefulWidget {
  final List<ContactModel> eligibleContacts;
  final Future<void> Function(ComposePostResult result) onSubmit;

  const ComposePostSheet({
    super.key,
    required this.eligibleContacts,
    required this.onSubmit,
  });

  @override
  State<ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<ComposePostSheet> {
  final TextEditingController _textController = TextEditingController();
  PostAudienceKind _audienceKind = PostAudienceKind.allFriends;
  final Set<String> _selectedPeerIds = <String>{};
  bool _isSubmitting = false;

  bool get _canSubmit {
    if (_textController.text.trim().isEmpty || _isSubmitting) {
      return false;
    }
    if (_audienceKind == PostAudienceKind.pickPeople &&
        _selectedPeerIds.isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      final audience = switch (_audienceKind) {
        PostAudienceKind.pickPeople => PostAudience.pickPeople(
          _selectedPeerIds.toList(),
        ),
        _ => PostAudience.allFriends(),
      };
      await widget.onSubmit(
        ComposePostResult(
          text: _textController.text.trim(),
          audience: audience,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.eligibleContacts
        .where((contact) => !contact.isArchived && !contact.isBlocked)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  maxLines: 5,
                  minLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'What do you want to share?',
                    hintStyle: const TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.35),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A1E26),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('All Friends'),
                      selected: _audienceKind == PostAudienceKind.allFriends,
                      onSelected: (_) {
                        setState(() {
                          _audienceKind = PostAudienceKind.allFriends;
                          _selectedPeerIds.clear();
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Pick People'),
                      selected: _audienceKind == PostAudienceKind.pickPeople,
                      onSelected: (_) {
                        setState(() {
                          _audienceKind = PostAudienceKind.pickPeople;
                        });
                      },
                    ),
                  ],
                ),
                if (_audienceKind == PostAudienceKind.pickPeople) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Pick People',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: contacts.length,
                      separatorBuilder: (_, _) => const Divider(
                        color: Color.fromRGBO(255, 255, 255, 0.06),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final isSelected = _selectedPeerIds.contains(
                          contact.peerId,
                        );
                        return CheckboxListTile(
                          value: isSelected,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.trailing,
                          title: Text(
                            contact.username,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            contact.peerId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color.fromRGBO(255, 255, 255, 0.45),
                              fontSize: 12,
                            ),
                          ),
                          onChanged: (_) {
                            setState(() {
                              if (isSelected) {
                                _selectedPeerIds.remove(contact.peerId);
                              } else {
                                _selectedPeerIds.add(contact.peerId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: Text(_isSubmitting ? 'Posting...' : 'Post'),
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
