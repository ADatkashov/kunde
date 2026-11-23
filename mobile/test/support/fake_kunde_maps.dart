import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';
import 'package:kunde_mobile/features/maps/kunde_maps.dart';

/// A [KundeMaps] for widget tests: real SDK routing and search over the
/// given HTTP client, but no native map. Maps are drawn as text so tests can
/// assert what would be shown, and the picker returns queued points.
/// A GPS for widget tests: no platform plugin, either a fixed point or none.
class FakeLocationSource implements LocationSource {
  const FakeLocationSource([this.point]);

  final GeoPoint? point;

  @override
  Future<GpsAccess> access() async =>
      point == null ? GpsAccess.denied : GpsAccess.ok;

  @override
  Future<LocationFix?> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final fixed = point;
    return fixed == null ? null : LocationFix(fixed, 5, DateTime(2026, 11, 23));
  }

  @override
  Stream<LocationFix> watch({
    required MapsStrings strings,
    bool navigation = false,
    bool vehicle = true,
    bool notification = true,
  }) =>
      const Stream.empty();
}

class FakeKundeMaps extends KundeMaps {
  FakeKundeMaps(
    http.Client client, [
    List<PickedLocation>? picks,
    GeoPoint? here,
  ])  : picks = picks ?? [],
        super(
          client: client,
          config: MapsConfig(
            environment: MapsEnvironment.dev,
            searchUrl: 'https://search.test',
            routingUrl: 'https://routing.test',
            tileUrl: 'https://tiles.test/k.pmtiles',
            webUrl: 'https://web.test',
            language: 'en',
          ),
        ) {
    geolocation = Geolocation(FakeLocationSource(here));
  }

  final List<PickedLocation> picks;
  final titles = <String>[];
  final shown = <(List<String>, bool)>[];

  @override
  Future<PickedLocation?> pick(
    BuildContext context, {
    GeoPoint? initial,
    required String title,
  }) async {
    titles.add(title);
    return picks.isEmpty ? null : picks.removeAt(0);
  }

  @override
  Widget map(
    BuildContext context, {
    required List<MapMarker> markers,
    MapRoute? route,
    double height = 240,
    bool interactive = true,
  }) {
    final ids = [for (final m in markers) m.id];
    shown.add((ids, route != null));
    return Text('map:${ids.join(',')}:${route == null ? 'none' : 'route'}');
  }
}

PickedLocation searchResult(String name, double lat, double lon) =>
    PickedLocation(
      GeoPoint(lat, lon),
      place: MapPlace({'name': name, 'name_en': name, 'lat': lat, 'lon': lon}),
    );
