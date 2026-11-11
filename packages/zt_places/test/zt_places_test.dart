import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zt_places/zt_places.dart';

void main() {
  group('ZtLatLng.tryParse', () {
    test('reads coordinates and map links without any server', () {
      const tlv = ZtLatLng(32.0853, 34.7818);
      for (final s in [
        '32.0853, 34.7818',
        '32.0853,34.7818',
        '32.0853 34.7818',
        'geo:32.0853,34.7818?z=16',
        'https://www.google.com/maps/place/X/@32.0853,34.7818,17z',
        'https://maps.google.com/?q=32.0853,34.7818',
        'https://www.openstreetmap.org/?mlat=32.0853&mlon=34.7818#map=16/32.0853/34.7818',
        'https://www.openstreetmap.org/#map=16/32.0853/34.7818',
        'https://maps.apple.com/?ll=32.0853,34.7818',
        'https://www.google.com/maps/search/?api=1&query=32.0853%2C34.7818',
      ]) {
        expect(ZtLatLng.tryParse(s), tlv, reason: s);
      }
    });

    test('a broken %-escape is read as typed, not an error', () {
      expect(ZtLatLng.tryParse('32.0853, 34.7818 %'), isNull);
      expect(ZtLatLng.tryParse('geo:32.0853,34.7818?q=%2'),
          const ZtLatLng(32.0853, 34.7818));
      expect(ZtLatLng.tryParse('https://maps.example/?q=%'), isNull);
    });

    test('refuses text without a position, and impossible numbers', () {
      for (final s in [
        '',
        'Dizengoff 50, Tel Aviv',
        'https://maps.app.goo.gl/abc123',
        '95.0, 34.0',
        '32.0, 190.0',
      ]) {
        expect(ZtLatLng.tryParse(s), isNull, reason: s);
      }
    });

    test('distance', () {
      const a = ZtLatLng(32.0853, 34.7818);
      const b = ZtLatLng(31.7683, 35.2137); // Jerusalem
      expect(a.distanceTo(b), closeTo(54000, 2000));
      expect(a.distanceTo(a), 0);
    });
  });

  test('ZtPlace JSON round trip, radius never under the minimum', () {
    const p = ZtPlace(
        id: 'p1',
        name: 'Home',
        latitude: 1.5,
        longitude: -2.25,
        radiusMeters: 300);
    expect(ZtPlace.fromJson(p.toJson()), p);
    expect(
        ZtPlace.fromJson({'id': 'x', 'lat': 1, 'lng': 2, 'radius': 10})!
            .radiusMeters,
        ZtPlace.minRadius);
    expect(ZtPlace.fromJson({'id': 'x', 'lat': 'a'}), isNull);
  });

  group('Android channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dev.sagron.zt_places');
    final calls = <MethodCall>[];

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'sync':
            return (call.arguments['reminders'] as List).length;
          case 'permissions':
            return {
              'fine': true,
              'coarse': true,
              'background': false,
              'notifications': true,
              'locationOn': true,
            };
          case 'currentLocation':
            return {'latitude': 1.0, 'longitude': 2.0, 'accuracy': 5.0};
          case 'takeEvents':
            return [
              {'type': 'fired', 'id': 'r1', 'payload': 'note-1'},
              {'type': 'done', 'id': 'r1', 'payload': 'note-1'},
            ];
          case 'takeLaunchTap':
            return {'id': 'r1', 'payload': 'note-1'};
        }
        return null;
      });
    });

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('sync sends the reminders and the app notification style', () async {
      final r = ZtPlaceRemindersAndroid();
      const place = ZtPlace(id: 'p', name: 'Home', latitude: 1, longitude: 2);
      final n = await r.sync([
        const ZtPlaceReminder(
            id: 'r1',
            place: place,
            trigger: ZtPlaceTrigger.leave,
            title: 'Buy milk',
            payload: 'note-1'),
      ],
          style: const ZtPlaceNotificationStyle(
              channelId: 'c',
              channelName: 'Place reminders',
              doneLabel: 'Done'));
      expect(n, 1);
      final args = calls.single.arguments as Map;
      final sent = (args['reminders'] as List).single as Map;
      expect(sent['trigger'], 'leave');
      expect(sent['radius'], ZtPlace.defaultRadius);
      expect(sent['title'], 'Buy milk');
      expect((args['config'] as Map)['doneLabel'], 'Done');
    });

    test('permissions, location and queued events', () async {
      final r = ZtPlaceRemindersAndroid();
      final p = await r.permissions();
      expect(p.precise, isTrue);
      expect(p.ready, isFalse, reason: 'no "all the time" yet');
      expect(await r.currentLocation(), const ZtLatLng(1, 2));
      final events = <ZtPlaceEvent>[];
      final sub = r.events.listen(events.add);
      await r.collect();
      await pumpEventQueue();
      expect(events, const [
        ZtPlaceEvent(ZtPlaceEventType.fired, 'r1', 'note-1'),
        ZtPlaceEvent(ZtPlaceEventType.done, 'r1', 'note-1'),
        ZtPlaceEvent(ZtPlaceEventType.tap, 'r1', 'note-1'),
      ]);
      await sub.cancel();
    });

    test('events taken while nothing listens wait for the first listener',
        () async {
      final r = ZtPlaceRemindersAndroid();
      // The native side nudges while the app is still locked: nobody
      // listens yet, and the native queue is emptied by this read.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(const MethodCall('event')),
              (_) {});
      await pumpEventQueue();
      expect(calls.map((c) => c.method), contains('takeEvents'));

      final events = <ZtPlaceEvent>[];
      final sub = r.events.listen(events.add);
      await pumpEventQueue();
      expect(events, const [
        ZtPlaceEvent(ZtPlaceEventType.fired, 'r1', 'note-1'),
        ZtPlaceEvent(ZtPlaceEventType.done, 'r1', 'note-1'),
      ]);
      await sub.cancel();
    });
  });

  test('fake: a reminder fires once, until it gets a new id', () async {
    final fake = ZtPlaceRemindersFake();
    const place = ZtPlace(id: 'p', name: 'Home', latitude: 1, longitude: 2);
    const style = ZtPlaceNotificationStyle(channelId: 'c', channelName: 'n');
    const r1 = ZtPlaceReminder(
        id: 'a', place: place, trigger: ZtPlaceTrigger.arrive, title: 't');
    await fake.sync([r1], style: style);
    fake.fire('a');
    expect(await fake.sync([r1], style: style), 0);
    const r2 = ZtPlaceReminder(
        id: 'b', place: place, trigger: ZtPlaceTrigger.arrive, title: 't');
    expect(await fake.sync([r2], style: style), 1);
  });

  group('picker', () {
    Future<ZtPlaceChoice?> open(WidgetTester tester, ZtPlaceRemindersFake fake,
        {List<ZtPlace> saved = const [],
        Locale locale = const Locale('en')}) async {
      ZtPlaceChoice? result;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('he')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await ZtPlacePickerPage.show(
                context,
                reminders: fake,
                savedPlaces: saved,
                newId: () => 'new-id'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('current location, a name and a radius', (tester) async {
      final fake = ZtPlaceRemindersFake(location: const ZtLatLng(32.1, 34.8));
      ZtPlaceChoice? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await ZtPlacePickerPage.show(
                context,
                reminders: fake,
                newId: () => 'new-id'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing is sent'), findsOneWidget);
      await tester.tap(find.text('When I leave'));
      await tester.tap(find.byKey(const Key('zt-place-current')));
      await tester.pumpAndSettle();
      expect(find.text('32.10000, 34.80000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('zt-place-done')));
      await tester.pumpAndSettle();
      expect(find.text('Give the place a name'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('zt-place-name')), 'Gym');
      await tester.tap(find.text('300 m'));
      await tester.tap(find.byKey(const Key('zt-place-done')));
      await tester.pumpAndSettle();
      expect(result!.trigger, ZtPlaceTrigger.leave);
      expect(result!.place.name, 'Gym');
      expect(result!.place.radiusMeters, 300);
      expect(result!.place.id, 'new-id');
      expect(result!.saveToPlaces, isTrue);
    });

    testWidgets('a saved place, and the permission banner asks once',
        (tester) async {
      final fake = ZtPlaceRemindersFake(
          granted: const ZtPlacePermissions(
              precise: true, locationOn: true, notifications: true));
      const home = ZtPlace(id: 'home', name: 'Home', latitude: 1, longitude: 2);
      ZtPlaceChoice? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await ZtPlacePickerPage.show(
                context,
                reminders: fake,
                savedPlaces: const [home],
                newId: () => 'x'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('All the time'), findsOneWidget);
      await tester.tap(find.byKey(const Key('zt-place-allow')));
      await tester.pumpAndSettle();
      expect(fake.calls, ['requestBackground', 'openSettings']);
      await tester.tap(find.text('Home'));
      await tester.tap(find.byKey(const Key('zt-place-done')));
      await tester.pumpAndSettle();
      expect(result!.place, home);
      expect(result!.trigger, ZtPlaceTrigger.arrive);
    });

    testWidgets('pasted text without coordinates explains why', (tester) async {
      await open(tester, ZtPlaceRemindersFake());
      await tester.enterText(
          find.byKey(const Key('zt-place-paste')), 'Dizengoff 50');
      await tester.pump();
      expect(
          find.textContaining("Addresses can't be looked up"), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('zt-place-paste')), 'geo:32.5,35.5');
      await tester.pump();
      expect(find.text('32.50000, 35.50000'), findsOneWidget);
    });

    testWidgets('Hebrew, right to left', (tester) async {
      await open(tester, ZtPlaceRemindersFake(), locale: const Locale('he'));
      expect(find.text('תזכורת לפי מיקום'), findsOneWidget);
      expect(find.text('כשאגיע'), findsOneWidget);
      // The Done button sits at the start of an RTL app bar's end: left.
      final done = tester.getCenter(find.byKey(const Key('zt-place-done')));
      expect(done.dx, lessThan(400));
    });
  });

  test('every English string has a Hebrew one', () {
    final en = ZtPlacesStrings.en;
    final he = ZtPlacesStrings.he;
    final pairs = [
      (en.title, he.title),
      (en.whenArrive, he.whenArrive),
      (en.privacy, he.privacy),
      (en.arriving('X'), he.arriving('X')),
      (en.leaving('X'), he.leaving('X')),
      (en.distance(1000), he.distance(1000)),
    ];
    for (final (e, h) in pairs) {
      expect(h, isNot(e));
      expect(RegExp('[֐-׿]').hasMatch(h), isTrue, reason: h);
    }
    expect(en.distance(1500), '1.5 km');
    expect(en.distance(150), '150 m');
  });
}
