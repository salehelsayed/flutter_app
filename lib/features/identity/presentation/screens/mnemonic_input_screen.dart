import 'package:flutter/material.dart';

class MnemonicInputScreen extends StatefulWidget {
  final Future<void> Function(String mnemonic) onRestorePressed;

  const MnemonicInputScreen({
    super.key,
    required this.onRestorePressed,
  });

  @override
  State<MnemonicInputScreen> createState() => _MnemonicInputScreenState();
}

class _MnemonicInputScreenState extends State<MnemonicInputScreen> {
  final TextEditingController _mnemonicController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _handleRestorePressed() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onRestorePressed(_mnemonicController.text);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter Recovery Phrase',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter your 12-word recovery phrase below',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _mnemonicController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'word1 word2 word3 word4\nword5 word6 word7 word8\nword9 word10 word11 word12',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRestorePressed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Restore identity',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
