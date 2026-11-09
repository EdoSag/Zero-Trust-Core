import 'package:flutter/material.dart';

import '../../account/password_check.dart';

/// The strength bar under every "new password" field: a four-step bar, a
/// label ("Weak", "Strong") and one tip. Updates as the user types; the
/// estimate runs on the device.
class ZtPasswordStrengthMeter extends StatelessWidget {
  const ZtPasswordStrengthMeter({
    super.key,
    required this.controller,
    this.email,
  });

  final TextEditingController controller;

  /// The account's email, so a password built from it is marked down.
  final String? email;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        final strength = estimatePasswordStrength(value.text, email: email);
        final scheme = Theme.of(context).colorScheme;
        final color = switch (strength.score) {
          0 || 1 => scheme.error,
          2 => const Color(0xFFE09B12),
          _ => const Color(0xFF2E9E5B),
        };
        return Semantics(
          liveRegion: true,
          label: [
            'Password strength: ${strength.label}',
            if (strength.hint != null) strength.hint,
          ].join('. '),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i < strength.score
                                ? color
                                : scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: Text(
                    [strength.label, if (strength.hint != null) strength.hint]
                        .join(' · '),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
