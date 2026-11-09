import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../config/zt_preferences.dart';
import '../../config/zt_suite.dart';
import '../brand/zt_brand_mark.dart';

/// Whether this install has shown [ZtOnboardingScreen]: null while loading,
/// then true or false. Apps show onboarding before sign-in when it's false.
class OnboardingSeenController extends Notifier<bool?> {
  static const _key = 'onboarding_seen';
  bool _chosen = false;

  @override
  bool? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    bool seen;
    try {
      seen = await ref.read(ztPreferencesStoreProvider).read(_key) == 'true';
    } on Object {
      seen = false;
    }
    if (!_chosen) state = seen;
  }

  Future<void> markSeen() async {
    _chosen = true;
    state = true;
    try {
      await ref.read(ztPreferencesStoreProvider).write(_key, 'true');
    } on Object {
      // Shown again next launch; harmless.
    }
  }
}

final ztOnboardingSeenProvider =
    NotifierProvider<OnboardingSeenController, bool?>(
        OnboardingSeenController.new);

/// Three short pages shown once before the first sign-in: the privacy
/// promise, the recovery key, and biometric unlock. The same in every app.
///
/// [onDone] runs after the last page or Skip, once the install has been
/// marked as having seen it.
class ZtOnboardingScreen extends ConsumerStatefulWidget {
  const ZtOnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<ZtOnboardingScreen> createState() => _ZtOnboardingScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData? icon;
  final String title;
  final String body;
}

class _ZtOnboardingScreenState extends ConsumerState<ZtOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

  static List<_Page> _pagesFor(ZtLocalizations l) => [
        _Page(
          null,
          l.onlyYouCanReadYourData,
          l.everythingIsEncryptedOnThisPhone,
        ),
        _Page(
          Icons.key_outlined,
          l.keepYourRecoveryKeySafe,
          l.whenYouCreateYourAccountYou,
        ),
        _Page(
          Icons.fingerprint,
          l.unlockWithATouch,
          l.turnOnFingerprintOrFaceUnlock,
        ),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(ztOnboardingSeenProvider.notifier).markSeen();
    if (mounted) widget.onDone();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(ztAppConfigProvider);
    final app = ZtSuite.byId(config.appId);
    final pages = _pagesFor(ZtL10n.of(context));
    final last = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: last
                    ? const SizedBox(height: 48)
                    : TextButton(
                        onPressed: _finish,
                        child: Text(ZtL10n.of(context).skip)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          const SizedBox(height: 32),
                          ZtBrandMark(app: app, icon: page.icon, size: 96),
                          const SizedBox(height: 32),
                          Semantics(
                            header: true,
                            child: Text(page.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 16),
                          Text(page.body,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: ZtL10n.of(context).pageOf(_page + 1, pages.length),
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last
                      ? ZtL10n.of(context).getStarted
                      : ZtL10n.of(context).next),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
