import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'pending_joins.dart';
import 'sharing_name.dart';
import 'sharing_strings.dart';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
}

/// Asks for the name the others will see (pre-filled with the last one) and
/// remembers it. Null when cancelled.
Future<String?> ztAskSharingName(BuildContext context, WidgetRef ref,
    {required String title}) async {
  String current = '';
  try {
    current = await ref.read(ztSharingNameProvider).read();
  } on Object {
    // Locked or store not open: start empty.
  }
  if (!context.mounted) return null;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: current),
  );
  if (name == null || name.trim().isEmpty) return null;
  await ref.read(ztSharingNameProvider).save(name.trim());
  return name.trim();
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = ZtSharingStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.sharingExplain),
          const SizedBox(height: 16),
          TextField(
            key: const Key('zt-sharing-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: s.yourName, helperText: s.yourNameHint),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        TextButton(
            key: const Key('zt-sharing-name-ok'),
            onPressed: _submit,
            child: Text(s.continueLabel)),
      ],
    );
  }
}

/// One shared space: who is in it, people waiting to join, inviting, and
/// leaving or (owners) deleting it for everyone. [title] is what is shared
/// ("Groceries"); [description] adds a line about what members can do.
class ZtSpacePage extends ConsumerStatefulWidget {
  const ZtSpacePage({
    super.key,
    required this.spaceId,
    required this.title,
    this.description,
    this.inviteNow = false,
  });

  final String spaceId;
  final String title;
  final String? description;

  /// Opens the invite right away (just shared).
  final bool inviteNow;

  static Future<void> open(BuildContext context,
          {required String spaceId,
          required String title,
          String? description,
          bool inviteNow = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ZtSpacePage(
            spaceId: spaceId,
            title: title,
            description: description,
            inviteNow: inviteNow),
      ));

  @override
  ConsumerState<ZtSpacePage> createState() => _ZtSpacePageState();
}

class _ZtSpacePageState extends ConsumerState<ZtSpacePage> {
  bool _busy = false;

  /// For a space this account answered an invite to but isn't let in yet:
  /// it isn't listed among the spaces until then, so the code comes from
  /// the join kept on this phone. Null until looked up.
  Future<String?>? _pendingJoinCode;

  Future<String?> _lookUpJoinCode() async {
    try {
      final spaces = await ref.read(ztSharedSpacesProvider.future);
      return await spaces.joinCode(widget.spaceId);
    } on Object {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.inviteNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _invite();
      });
    }
  }

  Future<void> _invite() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          ZtInvitePage(spaceId: widget.spaceId, title: widget.title),
    ));
    ref.invalidate(ztPendingJoinsProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (mounted) _snack(context, ZtSharingStrings.of(context).needsInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _memberOptions(SpaceMember m) async {
    final s = ZtSharingStrings.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title:
                  Text(m.role == SpaceRole.admin ? s.makeMember : s.makeOwner),
              onTap: () => Navigator.pop(ctx, 'role'),
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(s.remove,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final spaces = ref.read(ztSpacesProvider.notifier);
    if (choice == 'role') {
      await _run(() => spaces.setRole(widget.spaceId, m.userId,
          m.role == SpaceRole.admin ? SpaceRole.member : SpaceRole.admin));
    } else if (choice == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.removeQ(m.name)),
          content: Text(s.removeExplain(widget.title)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.remove)),
          ],
        ),
      );
      if (ok == true) {
        await _run(() => spaces.remove(widget.spaceId, m.userId));
      }
    }
  }

  Future<void> _leaveOrDelete({required bool delete}) async {
    final s = ZtSharingStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(delete ? s.deleteQ(widget.title) : s.leaveQ(widget.title)),
        content: Text(delete ? s.deleteExplain : s.leaveExplain),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          TextButton(
            key: const Key('zt-space-confirm-leave'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(delete ? s.deleteForEveryone : s.leave),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final spaces = ref.read(ztSpacesProvider.notifier);
    final navigator = Navigator.of(context);
    var done = false;
    await _run(() async {
      delete
          ? await spaces.deleteSpace(widget.spaceId)
          : await spaces.leave(widget.spaceId);
      done = true;
    });
    if (done && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ZtSharingStrings.of(context);
    final entry = ref.watch(ztSpacesProvider)[widget.spaceId];
    if (entry == null) {
      final lookup = _pendingJoinCode ??= _lookUpJoinCode();
      return FutureBuilder<String?>(
        future: lookup,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          final code = snap.data;
          if (code == null) {
            return Scaffold(
                appBar: AppBar(), body: Center(child: Text(s.gone)));
          }
          return Scaffold(
            key: const Key('zt-space-waiting'),
            appBar: AppBar(title: Text(s.waitingToJoin)),
            body: ListView(padding: const EdgeInsets.all(24), children: [
              const Icon(Icons.hourglass_top, size: 48),
              const SizedBox(height: 16),
              Text(s.waitingExplain, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(code,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(letterSpacing: 3)),
            ]),
          );
        },
      );
    }
    _pendingJoinCode = null;
    final me = ref.watch(accountServiceProvider).currentUserId;
    final space = entry.space;
    final members = space?.members ?? const <SpaceMember>[];
    final waiting = space == null || !members.any((m) => m.userId == me);
    final isAdmin = entry.info.myRole == SpaceRole.admin;
    final joins = [
      for (final j
          in ref.watch(ztPendingJoinsProvider).value ?? const <PendingJoin>[])
        if (j.spaceId == widget.spaceId) j,
    ];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(waiting ? s.waitingToJoin : widget.title),
        actions: [
          IconButton(
            tooltip: s.syncNow,
            icon: const Icon(Icons.sync),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final spaces = ref.read(ztSpacesProvider.notifier);
                      await spaces.refresh();
                      await spaces.syncNow(widget.spaceId);
                      ref.invalidate(ztPendingJoinsProvider);
                    }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (waiting)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.hourglass_top, size: 48),
                const SizedBox(height: 16),
                Text(s.waitingExplain, textAlign: TextAlign.center),
                if (entry.joinCode != null) ...[
                  const SizedBox(height: 16),
                  Text(entry.joinCode!,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.displaySmall
                          ?.copyWith(letterSpacing: 3)),
                ],
              ]),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(widget.description ?? s.e2e,
                  style: theme.textTheme.bodySmall),
            ),
            for (final j in joins)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(s.joinRequest(j.name)),
                  subtitle: Text(s.joinRequestHint),
                  onTap: () =>
                      ztConfirmJoin(context, ref, j, title: widget.title),
                ),
              ),
            ListTile(
                title: Text(s.people(members.length),
                    style: theme.textTheme.titleSmall)),
            for (final m in members)
              ListTile(
                key: Key('zt-member-${m.userId}'),
                leading: CircleAvatar(
                    child: Text(m.name.isEmpty
                        ? '?'
                        : m.name.characters.first.toUpperCase())),
                title: Text(m.userId == me ? s.youName(m.name) : m.name),
                subtitle: Text(m.role == SpaceRole.admin ? s.owner : s.member),
                trailing: isAdmin && m.userId != me
                    ? const Icon(Icons.more_vert)
                    : null,
                onTap: isAdmin && m.userId != me && !_busy
                    ? () => _memberOptions(m)
                    : null,
              ),
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('zt-space-invite'),
                  onPressed: _busy ? null : _invite,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(s.invitePeople),
                ),
              ),
          ],
          const Divider(),
          ListTile(
            key: const Key('zt-space-leave'),
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(s.leave, style: TextStyle(color: scheme.error)),
            enabled: !_busy,
            onTap: () => _leaveOrDelete(delete: false),
          ),
          if (isAdmin)
            ListTile(
              key: const Key('zt-space-delete'),
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text(s.deleteForEveryone,
                  style: TextStyle(color: scheme.error)),
              enabled: !_busy,
              onTap: () => _leaveOrDelete(delete: true),
            ),
        ],
      ),
    );
  }
}

/// A link (and QR code) for one person to join [spaceId].
class ZtInvitePage extends ConsumerStatefulWidget {
  const ZtInvitePage({super.key, required this.spaceId, required this.title});
  final String spaceId;
  final String title;

  @override
  ConsumerState<ZtInvitePage> createState() => _ZtInvitePageState();
}

class _ZtInvitePageState extends ConsumerState<ZtInvitePage> {
  SpaceInviteLink? _link;
  bool _busy = false;
  bool _asOwner = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final link = await ref.read(ztSpacesProvider.notifier).invite(
          widget.spaceId,
          role: _asOwner ? SpaceRole.admin : SpaceRole.member);
      if (mounted) setState(() => _link = link);
    } on Object {
      if (mounted) _snack(context, ZtSharingStrings.of(context).needsInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ZtSharingStrings.of(context);
    final app = ref.watch(ztAppConfigProvider).displayName;
    final link = _link;
    final joins = [
      for (final j
          in ref.watch(ztPendingJoinsProvider).value ?? const <PendingJoin>[])
        if (j.spaceId == widget.spaceId) j,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.inviteTo(widget.title))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final j in joins)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text(s.joinRequest(j.name)),
                subtitle: Text(s.joinRequestHint),
                onTap: () =>
                    ztConfirmJoin(context, ref, j, title: widget.title),
              ),
            ),
          if (link == null) ...[
            Text(s.inviteIntro(app)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.inviteAsOwner),
              subtitle: Text(s.inviteAsOwnerHint),
              value: _asOwner,
              onChanged: (v) => setState(() => _asOwner = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('zt-invite-create'),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.qr_code),
              label: Text(s.createInvite),
            ),
          ] else ...[
            Text(s.inviteReady(app), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                    key: const Key('zt-invite-qr'),
                    data: link.qrData,
                    size: 240,
                    semanticsLabel: s.inviteQr),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('zt-invite-copy'),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: link.toString()));
                    if (context.mounted) _snack(context, s.linkCopied);
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(s.copyLink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('zt-invite-send'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  // The share sheet leaves the app; it mustn't lock the
                  // vault behind it.
                  onPressed: () => ref
                      .read(vaultControllerProvider.notifier)
                      .whileShowingSystemUi(() => SharePlus.instance.share(
                          ShareParams(
                              text: s.inviteMessage(
                                  widget.title, app, link.toString())))),
                  icon: const Icon(Icons.share),
                  label: Text(s.sendLink),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text(s.inviteNextSteps,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(ztPendingJoinsProvider),
                icon: const Icon(Icons.refresh),
                label: Text(s.checkForAnswers),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The owner compares the code on the other person's phone, then lets them
/// in (or turns the answer down when the codes differ).
Future<void> ztConfirmJoin(BuildContext context, WidgetRef ref, PendingJoin j,
    {required String title}) async {
  final s = ZtSharingStrings.of(context);
  final spaces = ref.read(ztSpacesProvider.notifier);
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.confirmJoinTitle(j.name, title)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.confirmJoinBody),
          const SizedBox(height: 16),
          Text(
            j.verificationCode,
            textDirection: TextDirection.ltr,
            style: Theme.of(ctx)
                .textTheme
                .headlineMedium
                ?.copyWith(letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(j.role == SpaceRole.admin ? s.owner : s.member),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'reject'),
            child: Text(s.codesDiffer)),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.later)),
        TextButton(
            key: const Key('zt-codes-match'),
            onPressed: () => Navigator.pop(ctx, 'ok'),
            child: Text(s.codesMatch)),
      ],
    ),
  );
  try {
    if (choice == 'ok') {
      await spaces.confirm(j);
      if (context.mounted) _snack(context, s.joined(j.name));
    } else if (choice == 'reject') {
      await spaces.revokeInvite(j.inviteId);
    } else {
      return;
    }
  } on Object {
    if (context.mounted) _snack(context, s.needsInternet);
  }
  ref.invalidate(ztPendingJoinsProvider);
}

/// Joins a space from an invite link (pasted, scanned, or opened from a
/// message), then shows the code to compare with the owner. Pops the
/// [JoinStarted] once done, or null.
class ZtJoinSpacePage extends ConsumerStatefulWidget {
  const ZtJoinSpacePage({super.key, this.initialLink});
  final String? initialLink;

  static Future<JoinStarted?> open(BuildContext context,
          {String? initialLink}) =>
      Navigator.of(context).push<JoinStarted>(MaterialPageRoute(
          builder: (_) => ZtJoinSpacePage(initialLink: initialLink)));

  @override
  ConsumerState<ZtJoinSpacePage> createState() => _ZtJoinSpacePageState();
}

class _ZtJoinSpacePageState extends ConsumerState<ZtJoinSpacePage> {
  late final _link = TextEditingController(text: widget.initialLink);
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  JoinStarted? _started;

  @override
  void initState() {
    super.initState();
    ref.read(ztSharingNameProvider).read().then((name) {
      if (mounted && _name.text.isEmpty) _name.text = name;
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  String? _validLink(String? v) {
    final s = ZtSharingStrings.of(context);
    final config = ref.read(ztAppConfigProvider);
    try {
      final link = SpaceInviteLink.parse(v ?? '');
      if (link.app != config.appId) return s.inviteOtherApp;
      return null;
    } on FormatException {
      return s.inviteInvalid(config.displayName);
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (text != null) setState(() => _link.text = text);
  }

  Future<void> _join() async {
    if (!_form.currentState!.validate()) return;
    final s = ZtSharingStrings.of(context);
    setState(() => _busy = true);
    try {
      final name = _name.text.trim();
      await ref.read(ztSharingNameProvider).save(name);
      final started = await ref
          .read(ztSpacesProvider.notifier)
          .answer(SpaceInviteLink.parse(_link.text), myName: name);
      if (mounted) setState(() => _started = started);
    } on SpaceRefused {
      if (mounted) _snack(context, s.inviteUsed);
    } on Object {
      if (mounted) _snack(context, s.needsInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ZtSharingStrings.of(context);
    final started = _started;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.joinTitle)),
      body: started != null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.verified_user_outlined, size: 56),
                const SizedBox(height: 16),
                Text(s.joinCodeTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(
                  started.verificationCode,
                  key: const Key('zt-join-code'),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style:
                      theme.textTheme.displaySmall?.copyWith(letterSpacing: 3),
                ),
                const SizedBox(height: 16),
                Text(s.joinCodeBody, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () => Navigator.of(context).pop(started),
                    child: Text(s.done)),
              ],
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.joinIntro),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('zt-join-link'),
                    controller: _link,
                    minLines: 1,
                    maxLines: 3,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: s.inviteLink,
                      suffixIcon: IconButton(
                        tooltip: s.scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scan,
                      ),
                    ),
                    validator: _validLink,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('zt-join-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        labelText: s.yourName, helperText: s.yourNameHint),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? s.nameRequired : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                      key: const Key('zt-join-submit'),
                      onPressed: _busy ? null : _join,
                      child: Text(s.join)),
                ],
              ),
            ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _key = GlobalKey(debugLabel: 'qr');
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(ZtSharingStrings.of(context).scanQr)),
        body: QRView(
          key: _key,
          overlay: QrScannerOverlayShape(
            borderColor: Theme.of(context).colorScheme.primary,
            borderRadius: 12,
            borderLength: 32,
            borderWidth: 8,
            cutOutSize: 260,
          ),
          onQRViewCreated: (controller) {
            controller.scannedDataStream.listen((b) {
              final code = b.code;
              if (_done || code == null) return;
              try {
                SpaceInviteLink.parse(code);
              } on FormatException {
                return;
              }
              _done = true;
              controller.pauseCamera();
              if (context.mounted) Navigator.of(context).pop(code);
            });
          },
        ),
      );
}

/// Cards for people waiting to join any space this account owns, for an
/// app's home screen. [titleOf] names each space.
class ZtJoinRequestCards extends ConsumerWidget {
  const ZtJoinRequestCards({super.key, required this.titleOf});

  final String Function(String spaceId) titleOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ZtSharingStrings.of(context);
    final joins =
        ref.watch(ztPendingJoinsProvider).value ?? const <PendingJoin>[];
    if (joins.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final j in joins)
          Card(
            key: Key('zt-join-request-${j.inviteId}'),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text(s.joinRequestFor(j.name, titleOf(j.spaceId))),
              subtitle: Text(s.joinRequestHint),
              onTap: () =>
                  ztConfirmJoin(context, ref, j, title: titleOf(j.spaceId)),
            ),
          ),
      ],
    );
  }
}
