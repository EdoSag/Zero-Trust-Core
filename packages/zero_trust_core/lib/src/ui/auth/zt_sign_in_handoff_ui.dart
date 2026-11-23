import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_handoff.dart';
import '../../core_providers.dart';
import '../../handoff/zt_sign_in_handoff.dart';
import '../../l10n/zt_l10n.dart';
import 'zt_auth_messages.dart';
import 'zt_confirm_identity.dart';

/// Lets other Zero-Trust apps on this phone sign in, or unlock, with this
/// app's account (S-2, "sign in once per phone").
///
/// When another app asks, this asks the person whether to share the account
/// with it, then for their fingerprint or password (as for any sensitive
/// action), and hands it over. It works whether this app is unlocked or
/// locked, as long as it is signed in.
///
/// Put it inside the `MaterialApp`, around the app's first screen, so it can
/// show dialogs:
///
/// ```dart
/// MaterialApp(home: const ZtSignInHandoffScope(child: AppGate()))
/// ```
class ZtSignInHandoffScope extends ConsumerStatefulWidget {
  const ZtSignInHandoffScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ZtSignInHandoffScope> createState() =>
      _ZtSignInHandoffScopeState();
}

class _ZtSignInHandoffScopeState extends ConsumerState<ZtSignInHandoffScope> {
  StreamSubscription<ZtHandoffRequest>? _requests;
  final _queue = <ZtHandoffRequest>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _requests = ref.read(ztSignInHandoffProvider).requests.listen((r) {
      _queue.add(r);
      _next();
    });
  }

  @override
  void dispose() {
    _requests?.cancel();
    super.dispose();
  }

  /// One request at a time: a second one waits for the first's dialogs.
  Future<void> _next() async {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    try {
      await _handle(_queue.removeAt(0));
    } on Object {
      // _handle answers every request; nothing else to do.
    } finally {
      _busy = false;
      if (mounted) unawaited(_next());
    }
  }

  Future<void> _handle(ZtHandoffRequest request) async {
    final handoff = ref.read(ztSignInHandoffProvider);
    final account = ref.read(accountServiceProvider);
    final email = account.currentEmail;
    if (account.currentUserId == null || email == null) {
      await handoff.refuse(request, ZtHandoffRefusal.signedOut);
      return;
    }
    final signIn = request.mode == ZtHandoffMode.signIn;
    if (!mounted ||
        Navigator.maybeOf(context) == null ||
        (signIn && !account.canHandOffSession)) {
      await handoff.refuse(request, ZtHandoffRefusal.failed);
      return;
    }
    final l = ZtL10n.of(context);
    final name = request.from.label;
    final title = signIn ? l.handoffAskSignIn(name) : l.handoffAskUnlock(name);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(request.from.app.icon, color: request.from.app.accent),
        title: Text(title),
        content: Text(l.handoffAskBody(name, email)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.notNow)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.handoffAllow)),
        ],
      ),
    );
    if (yes != true || !mounted) {
      await handoff.refuse(request, ZtHandoffRefusal.declined);
      return;
    }
    final proof = await ztConfirmIdentity(
      context,
      ref,
      title: title,
      message: l.handoffConfirm(name),
      action: l.handoffAllow,
    );
    if (proof == null) {
      await handoff.refuse(request, ZtHandoffRefusal.declined);
      return;
    }
    ZtHandoffGrant? grant;
    try {
      grant = await account.handoffGrant(proof, withSession: signIn);
      if (!await handoff.answer(request, grant)) {
        throw StateError(l.handoffFailed(name));
      }
    } on Object catch (e) {
      await handoff.refuse(request, ZtHandoffRefusal.failed);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(ztErrorMessage(e))));
      }
    } finally {
      proof.dek.fillRange(0, proof.dek.length, 0);
      grant?.wipe();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Sign in with ZT Notes" (or "Unlock with …") on the sign-in and unlock
/// screens: shown only when another Zero-Trust app on this phone could hand
/// its account over. While it waits, it says where to confirm and offers
/// Cancel. [onGrant] uses the grant (it is wiped afterwards); problems go to
/// [onError] as one sentence.
class ZtHandoffButton extends ConsumerStatefulWidget {
  const ZtHandoffButton({
    super.key,
    required this.mode,
    required this.onGrant,
    required this.onError,
    this.enabled = true,
  });

  final ZtHandoffMode mode;
  final Future<void> Function(ZtHandoffGrant grant) onGrant;
  final void Function(String message) onError;
  final bool enabled;

  @override
  ConsumerState<ZtHandoffButton> createState() => _ZtHandoffButtonState();
}

class _ZtHandoffButtonState extends ConsumerState<ZtHandoffButton> {
  ZtHandoffApp? _waitingFor;
  late final ZtSignInHandoff _handoff = ref.read(ztSignInHandoffProvider);

  @override
  void dispose() {
    if (_waitingFor != null) _handoff.cancel();
    super.dispose();
  }

  Future<void> _start(List<ZtHandoffApp> givers) async {
    final giver = givers.length == 1 ? givers.first : await _pick(givers);
    if (giver == null || !mounted) return;
    setState(() => _waitingFor = giver);
    ZtHandoffGrant? grant;
    try {
      grant = await _handoff.ask(giver, widget.mode);
      if (!mounted) return;
      setState(() => _waitingFor = null);
      await widget.onGrant(grant);
    } on ZtHandoffCancelled {
      // The person stopped waiting.
    } on TimeoutException {
      if (mounted) {
        widget.onError(ZtL10n.of(context).handoffNoAnswer(giver.label));
      }
    } on Object catch (e) {
      if (mounted) widget.onError(ztErrorMessage(e));
    } finally {
      grant?.wipe();
      if (mounted && _waitingFor != null) setState(() => _waitingFor = null);
    }
  }

  Future<ZtHandoffApp?> _pick(List<ZtHandoffApp> givers) =>
      showModalBottomSheet<ZtHandoffApp>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(ZtL10n.of(context).handoffPickApp,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final g in givers)
                ListTile(
                  leading: Icon(g.app.icon, color: g.app.accent),
                  title: Text(g.label),
                  onTap: () => Navigator.pop(context, g),
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final givers =
        ref.watch(ztHandoffGiversProvider).value ?? const <ZtHandoffApp>[];
    if (givers.isEmpty) return const SizedBox.shrink();
    final l = ZtL10n.of(context);
    final waiting = _waitingFor;
    if (waiting != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(l.handoffWaiting(waiting.label),
                textAlign: TextAlign.center),
          ),
          TextButton(onPressed: _handoff.cancel, child: Text(l.cancel)),
        ],
      );
    }
    final signIn = widget.mode == ZtHandoffMode.signIn;
    final label = givers.length == 1
        ? (signIn
            ? l.handoffSignInWith(givers.first.label)
            : l.handoffUnlockWith(givers.first.label))
        : (signIn ? l.handoffSignInWithAnother : l.handoffUnlockWithAnother);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: widget.enabled ? () => _start(givers) : null,
        icon: Icon(givers.length == 1 ? givers.first.app.icon : Icons.apps),
        label: Text(label),
      ),
    );
  }
}
