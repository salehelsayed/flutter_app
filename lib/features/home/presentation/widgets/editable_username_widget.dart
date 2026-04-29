import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';

/// Editable username display with mknoon/ prefix.
class EditableUsernameWidget extends StatefulWidget {
  final String username;
  final ValueChanged<String>? onUsernameChanged;

  const EditableUsernameWidget({
    super.key,
    required this.username,
    this.onUsernameChanged,
  });

  @override
  State<EditableUsernameWidget> createState() => _EditableUsernameWidgetState();
}

class _EditableUsernameWidgetState extends State<EditableUsernameWidget> {
  bool _isEditing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.username);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(EditableUsernameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username && !_isEditing) {
      _controller.text = widget.username;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finishEditing();
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
    _focusNode.requestFocus();
  }

  void _finishEditing() {
    final newUsername = _controller.text.trim();
    if (newUsername.isNotEmpty &&
        newUsername != widget.username &&
        isValidUsername(newUsername)) {
      widget.onUsernameChanged?.call(newUsername);
    } else {
      _controller.text = widget.username;
    }
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final mutedTextColor = readableColors.isLightSurface
        ? readableColors.textMuted
        : AppColors.textMuted;
    final primaryTextColor = readableColors.isLightSurface
        ? readableColors.textPrimary
        : AppColors.textPrimary;

    if (_isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'mknoon/',
            style: TextStyle(
              color: mutedTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            '@',
            style: TextStyle(
              color: primaryTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: 30,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(
                      r'[a-zA-Z0-9_\-.\u00C0-\u024F\u0600-\u06FF\u0750-\u077F]',
                    ),
                  ),
                ],
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  counterText: '',
                ),
                onSubmitted: (_) => _finishEditing(),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _startEditing,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'mknoon/',
            style: TextStyle(
              color: mutedTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          Flexible(
            child: Text(
              '@${widget.username}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.edit, color: mutedTextColor, size: 14),
        ],
      ),
    );
  }
}
