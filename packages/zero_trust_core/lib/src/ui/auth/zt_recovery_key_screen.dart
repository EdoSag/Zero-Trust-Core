import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
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

  static String _spelled(String key) =>
      key.split('-').map((group) => group.split('').join(' ')).join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(ZtL10n.of(context).saveYourRecoveryKey),
          automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              ZtL10n.of(context).thisKeyIsTheOnlyWay,
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
                        // Read out group by group, letter by letter, so
                        // it can be written down from a screen reader.
                        semanticsLabel: ZtL10n.of(context)
                            .recoveryKeySpelled(_spelled(_text!)),
                        key: const Key('zt-recovery-key'),
                        textAlign: TextAlign.center,
                        // Groups stay in reading order in Hebrew too.
                        textDirection: TextDirection.ltr,
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
              label: Text(ZtL10n.of(context).copy),
              onPressed: _text == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _text!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(ZtL10n.of(context)
                                .copiedStoreItSomewhereSafeAnd)),
                      );
                    },
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: Text(ZtL10n.of(context).iSavedMyRecoveryKeySomewhere),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saved ? widget.onDone : null,
              child: Text(ZtL10n.of(context).continueButton),
            ),
          ],
        ),
      ),
    );
  }
}
