import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A point on the map.
@immutable
class ZtLatLng {
  const ZtLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Great-circle distance in metres.
  double distanceTo(ZtLatLng other) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  /// "32.08530, 34.78180": what [tryParse] reads back.
  String format() =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// Reads a position someone pasted, without asking any server:
  /// "32.0853, 34.7818", "geo:32.0853,34.7818?z=16", and map links that
  /// carry the numbers (".../@32.0853,34.7818,17z", "?q=32.0853,34.7818",
  /// "?mlat=..&mlon=..", "#map=16/32.0853/34.7818"). Null when it holds no
  /// position (an address needs a geocoding server, which would see it).
  static ZtLatLng? tryParse(String input) {
    final text = Uri.decodeFull(input.trim());
    if (text.isEmpty) return null;
    const num = r'(-?\d{1,3}(?:\.\d+)?)';
    final patterns = [
      RegExp('^geo:$num,$num', caseSensitive: false),
      RegExp('@$num,$num'),
      RegExp(
          '[?&](?:q|query|ll|center|destination|daddr)=(?:loc:)?$num,\\s*$num'),
      RegExp('#map=\\d+(?:\\.\\d+)?/$num/$num'),
      RegExp('^$num\\s*[,; ]\\s*$num\$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;
      final ll = ZtLatLng(double.parse(m.group(1)!), double.parse(m.group(2)!));
      if (ll.isValid) return ll;
    }
    final mlat = RegExp('[?&]mlat=$num').firstMatch(text);
    final mlon = RegExp('[?&]mlon=$num').firstMatch(text);
    if (mlat != null && mlon != null) {
      final ll =
          ZtLatLng(double.parse(mlat.group(1)!), double.parse(mlon.group(1)!));
      if (ll.isValid) return ll;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ZtLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'ZtLatLng(${format()})';
}

/// A named place with a radius ("Home", "Office", "Supermarket").
@immutable
class ZtPlace {
  const ZtPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = defaultRadius,
  });

  /// Smallest radius Android watches reliably.
  static const double minRadius = 100;
  static const double defaultRadius = 150;
  static const List<double> radiusChoices = [100, 150, 300, 500, 1000];

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  ZtLatLng get position => ZtLatLng(latitude, longitude);

  ZtPlace copyWith({String? name, double? radiusMeters, ZtLatLng? position}) =>
      ZtPlace(
        id: id,
        name: name ?? this.name,
        latitude: position?.latitude ?? latitude,
        longitude: position?.longitude ?? longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
        'radius': radiusMeters,
      };

  static ZtPlace? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final id = json['id'];
    if (lat is! num || lng is! num || id is! String) return null;
    final radius = json['radius'];
    return ZtPlace(
      id: id,
      name: json['name'] is String ? json['name'] as String : '',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      radiusMeters: radius is num
          ? math.max(minRadius, radius.toDouble())
          : defaultRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ZtPlace &&
      other.id == id &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.radiusMeters == radiusMeters;

  @override
  int get hashCode => Object.hash(id, name, latitude, longitude, radiusMeters);
}
