import 'package:flutter/material.dart';

import 'place.dart';
import 'place_reminders.dart';
import 'places_strings.dart';

/// What the user picked on [ZtPlacePickerPage].
@immutable
class ZtPlaceChoice {
  const ZtPlaceChoice({
    required this.place,
    required this.trigger,
    this.saveToPlaces = false,
  });

  final ZtPlace place;
  final ZtPlaceTrigger trigger;

  /// The user asked to keep [place] in "My places".
  final bool saveToPlaces;
}

/// The shared "Location reminder" screen: arrive or leave, then a place from
/// "My places", the phone's current location, or pasted coordinates / a map
/// link. No map tiles and no address search, since both would send the
/// location to a server. Pops a [ZtPlaceChoice], or null.
class ZtPlacePickerPage extends StatefulWidget {
  const ZtPlacePickerPage({
    super.key,
    required this.reminders,
    this.savedPlaces = const [],
    this.initialPlace,
    this.initialTrigger = ZtPlaceTrigger.arrive,
    this.onRemovePlace,
    required this.newId,
  });

  final ZtPlaceReminders reminders;

  /// The app's "My places" (kept in its own encrypted store).
  final List<ZtPlace> savedPlaces;
  final ZtPlace? initialPlace;
  final ZtPlaceTrigger initialTrigger;

  /// Removes a place from "My places"; no remove option when null.
  final Future<void> Function(ZtPlace place)? onRemovePlace;

  /// A fresh id for a new place.
  final String Function() newId;

  static Future<ZtPlaceChoice?> show(
    BuildContext context, {
    required ZtPlaceReminders reminders,
    List<ZtPlace> savedPlaces = const [],
    ZtPlace? initialPlace,
    ZtPlaceTrigger initialTrigger = ZtPlaceTrigger.arrive,
    Future<void> Function(ZtPlace place)? onRemovePlace,
    required String Function() newId,
  }) =>
      Navigator.of(context).push<ZtPlaceChoice>(MaterialPageRoute(
        builder: (_) => ZtPlacePickerPage(
          reminders: reminders,
          savedPlaces: savedPlaces,
          initialPlace: initialPlace,
          initialTrigger: initialTrigger,
          onRemovePlace: onRemovePlace,
          newId: newId,
        ),
      ));

  @override
  State<ZtPlacePickerPage> createState() => _ZtPlacePickerPageState();
}

class _ZtPlacePickerPageState extends State<ZtPlacePickerPage>
    with WidgetsBindingObserver {
  late ZtPlaceTrigger _trigger = widget.initialTrigger;
  late List<ZtPlace> _saved = [...widget.savedPlaces];

  /// A saved place picked from the list.
  String? _savedId;

  /// A new position (current location or pasted).
  ZtLatLng? _position;
  double _radius = ZtPlace.defaultRadius;
  final _name = TextEditingController();
  final _paste = TextEditingController();
  bool _saveToPlaces = true;
  bool _locating = false;
  String? _error;
  ZtPlacePermissions? _perms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialPlace;
    if (initial != null) {
      if (_saved.any((p) => p.id == initial.id)) {
        _savedId = initial.id;
      } else {
        _position = initial.position;
        _name.text = initial.name;
        _radius = initial.radiusMeters;
        _saveToPlaces = false;
      }
    }
    _refreshPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings page.
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _refreshPermissions() async {
    final p = await widget.reminders.permissions();
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _allow() async {
    final r = widget.reminders;
    var p = await r.permissions();
    if (!p.precise) p = await r.requestLocation();
    if (p.precise && !p.background) p = await r.requestBackground();
    if (p.precise && !p.notifications) p = await r.requestNotifications();
    if (!p.precise || !p.background) {
      // Asked before and refused: only the settings page can change it.
      final again = await r.permissions();
      if (!again.precise || !again.background) await r.openSettings();
    }
    await _refreshPermissions();
  }

  Future<void> _useCurrent() async {
    final s = ZtPlacesStrings.of(context);
    setState(() {
      _locating = true;
      _error = null;
    });
    var p = await widget.reminders.permissions();
    if (!p.precise && !p.approximate) {
      p = await widget.reminders.requestLocation();
    }
    final here = await widget.reminders.currentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _perms = p;
      if (here == null) {
        _error = s.locationFailed;
      } else {
        _position = here;
        _savedId = null;
      }
    });
  }

  void _parsePaste(String text) {
    final s = ZtPlacesStrings.of(context);
    if (text.trim().isEmpty) {
      setState(() => _error = null);
      return;
    }
    final ll = ZtLatLng.tryParse(text);
    setState(() {
      if (ll == null) {
        _error = s.pasteInvalid;
      } else {
        _error = null;
        _position = ll;
        _savedId = null;
      }
    });
  }

  Future<void> _remove(ZtPlace place) async {
    await widget.onRemovePlace?.call(place);
    if (!mounted) return;
    setState(() {
      _saved = [..._saved]..removeWhere((p) => p.id == place.id);
      if (_savedId == place.id) _savedId = null;
    });
  }

  void _done() {
    final s = ZtPlacesStrings.of(context);
    final saved = _saved.where((p) => p.id == _savedId).firstOrNull;
    if (saved != null) {
      Navigator.of(context).pop(ZtPlaceChoice(place: saved, trigger: _trigger));
      return;
    }
    final pos = _position;
    if (pos == null) {
      setState(() => _error = s.choosePlace);
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = s.nameNeeded);
      return;
    }
    final keepId = widget.initialPlace != null &&
            widget.initialPlace!.position == pos &&
            !_saved.any((p) => p.id == widget.initialPlace!.id)
        ? widget.initialPlace!.id
        : widget.newId();
    Navigator.of(context).pop(ZtPlaceChoice(
      place: ZtPlace(
        id: keepId,
        name: name,
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusMeters: _radius,
      ),
      trigger: _trigger,
      saveToPlaces: _saveToPlaces,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ZtPlacesStrings.of(context);
    final theme = Theme.of(context);
    final perms = _perms;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          TextButton(
            key: const Key('zt-place-done'),
            onPressed: widget.reminders.supported ? _done : null,
            child: Text(s.done),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          if (!widget.reminders.supported)
            _Banner(text: s.unsupported, icon: Icons.info_outline)
          else if (perms != null && !perms.locationOn)
            _Banner(text: s.locationOff, icon: Icons.location_off_outlined)
          else if (perms != null && !perms.ready)
            _Banner(
              text: s.needsPermission,
              icon: Icons.my_location,
              action: s.allow,
              onAction: _allow,
            ),
          const SizedBox(height: 8),
          SegmentedButton<ZtPlaceTrigger>(
            segments: [
              ButtonSegment(
                  value: ZtPlaceTrigger.arrive,
                  icon: const Icon(Icons.login),
                  label: Text(s.whenArrive)),
              ButtonSegment(
                  value: ZtPlaceTrigger.leave,
                  icon: const Icon(Icons.logout),
                  label: Text(s.whenLeave)),
            ],
            selected: {_trigger},
            onSelectionChanged: (v) => setState(() => _trigger = v.first),
          ),
          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(s.myPlaces, style: theme.textTheme.titleSmall),
            RadioGroup<String>(
              groupValue: _savedId,
              onChanged: (id) => setState(() {
                _savedId = id;
                _error = null;
              }),
              child: Column(children: [
                for (final p in _saved)
                  RadioListTile<String>(
                    key: Key('zt-place-${p.id}'),
                    value: p.id,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(s.distance(p.radiusMeters)),
                    secondary: widget.onRemovePlace == null
                        ? null
                        : IconButton(
                            tooltip: s.removePlace,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(p),
                          ),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('zt-place-current'),
            onPressed:
                _locating || !widget.reminders.supported ? null : _useCurrent,
            icon: _locating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: Text(_locating ? s.locating : s.useCurrent),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('zt-place-paste'),
            controller: _paste,
            decoration: InputDecoration(
              labelText: s.pasteLabel,
              prefixIcon: const Icon(Icons.link),
            ),
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            onChanged: _parsePaste,
          ),
          if (_position != null && _savedId == null) ...[
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _position!.format(),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('zt-place-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: s.placeName, hintText: s.placeNameHint),
            ),
            const SizedBox(height: 12),
            Text(s.radius, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final r in ZtPlace.radiusChoices)
                ChoiceChip(
                  label: Text(s.distance(r)),
                  selected: _radius == r,
                  onSelected: (_) => setState(() => _radius = r),
                ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _saveToPlaces,
              onChanged: (v) => setState(() => _saveToPlaces = v ?? false),
              title: Text(s.saveToPlaces),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                key: const Key('zt-place-error'),
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shield_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(s.privacy, style: theme.textTheme.bodySmall)),
          ]),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.text, required this.icon, this.action, this.onAction});

  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    style: TextStyle(color: scheme.onSecondaryContainer)),
              ),
            ]),
            if (action != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const Key('zt-place-allow'),
                  onPressed: onAction,
                  child: Text(action!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
