import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

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
    if (newUsername.isNotEmpty && newUsername != widget.username) {
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
    if (_isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'mknoon/',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Text(
            '@',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(
            width: 150,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _finishEditing(),
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
          const Text(
            'mknoon/',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            '@${widget.username}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.edit,
            color: AppColors.textMuted,
            size: 16,
          ),
        ],
      ),
    );
  }
}
