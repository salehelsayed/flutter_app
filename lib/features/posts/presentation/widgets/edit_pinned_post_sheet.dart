import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class EditPinnedPostSheet extends StatefulWidget {
  final String initialText;
  final Future<void> Function(String text) onSubmit;

  const EditPinnedPostSheet({
    super.key,
    required this.initialText,
    required this.onSubmit,
  });

  @override
  State<EditPinnedPostSheet> createState() => _EditPinnedPostSheetState();
}

class _EditPinnedPostSheetState extends State<EditPinnedPostSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late TextDirection _inputDirection;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _inputDirection = detectTextDirection(widget.initialText);
    _controller.addListener(_updateInputDirection);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateInputDirection);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EditPinnedPostSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText &&
        widget.initialText != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
      _inputDirection = detectTextDirection(widget.initialText);
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.onSubmit(text);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _updateInputDirection() {
    final nextDirection = detectTextDirection(_controller.text);
    if (nextDirection != _inputDirection) {
      setState(() => _inputDirection = nextDirection);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Edit pinned post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  textDirection: _inputDirection,
                  maxLines: 5,
                  minLines: 4,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.edit_pinned_hint,
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
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _controller.text.trim().isEmpty || _isSaving
                        ? null
                        : _submit,
                    child: Text(_isSaving ? 'Saving...' : 'Save'),
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
