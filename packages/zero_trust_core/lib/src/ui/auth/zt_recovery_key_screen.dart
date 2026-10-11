import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zt_crypto/zt_crypto.dart';

/// Shown exactly once, after sign-up or an account upgrade. The user cannot
/// continue until they confirm they saved the key.
class ZtRecoveryKeyScreen extends StatefulWidget {
  const ZtRecoveryKeyScreen({
    super.key,
    required this.recoveryKey,
    required this.onDone,
  });

  final RecoveryKey recoveryKey;
  final VoidCallback onDone;

  @override
  State<ZtRecoveryKeyScreen> createState() => _ZtRecoveryKeyScreenState();
}

class _ZtRecoveryKeyScreenState extends State<ZtRecoveryKeyScreen> {
  String? _text;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    widget.recoveryKey.format().then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Save your recovery key'),
          automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'This key is the only way back into your data if you forget your password. '
              'We can\'t reset it for you, because we never see your password or your data.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _text == null
                    ? const Center(child: CircularProgressIndicator())
                    : SelectableText(
                        _text!,
                        key: const Key('zt-recovery-key'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 1.2,
                          height: 1.6,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
              onPressed: _text == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _text!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Copied. Store it somewhere safe and offline.')),
                      );
                    },
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: const Text('I saved my recovery key somewhere safe'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saved ? widget.onDone : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
