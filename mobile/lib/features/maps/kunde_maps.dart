import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

/// The Super App's single entry point to the KUNDE Maps SDK.
///
/// Product screens (Taxi, Delivery, ...) receive a [KundeMaps] only when the
/// backend reports `mapsEnabled` together with their own product flag, so a
/// missing instance means "no map UI" and the existing list-based flow stays.
/// Widgets that need a native map are reached through the methods below, which
/// tests override so they never need a platform view.
class KundeMaps {
  KundeMaps({required this.config, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null {
    api = MapsClient(config, _client);
    search = PlaceSearch(api);
    routing = Routing(api);
  }

  /// Builds the production instance for the current UI language.
  factory KundeMaps.forContext(BuildContext context) => KundeMaps(
        config: MapsConfig.fromEnvironment(language: languageOf(context)),
      );

  final MapsConfig config;
  final http.Client _client;
  final bool _ownsClient;
  late final MapsClient api;
  late final PlaceSearch search;
  late final Routing routing;
  Geolocation geolocation = const Geolocation();

  void close() {
    if (_ownsClient) _client.close();
  }

  /// `ru`, `kk` or `en` for the SDK; anything else reads as Russian.
  static String languageOf(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return MapsConfig.supportedLanguages.contains(code) ? code : 'ru';
  }

  /// Full-screen point picker. Resolves to null when the user goes back.
  Future<PickedLocation?> pick(
    BuildContext context, {
    GeoPoint? initial,
    required String title,
  }) =>
      Navigator.of(context).push<PickedLocation>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (page) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: LocationPicker(
              config: config,
              search: search,
              geolocation: geolocation,
              initial: initial,
              dark: Theme.of(page).brightness == Brightness.dark,
              title: title,
              onPicked: (picked) => Navigator.of(page).pop(picked),
            ),
          ),
        ),
      );

  /// A map with [markers] and an optional route, fitted to what it shows.
  Widget map(
    BuildContext context, {
    required List<MapMarker> markers,
    MapRoute? route,
    double height = 240,
    bool interactive = true,
  }) =>
      SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _ShowMap(
            config: config,
            dark: Theme.of(context).brightness == Brightness.dark,
            markers: markers,
            route: route,
            interactive: interactive,
          ),
        ),
      );
}

class _ShowMap extends StatefulWidget {
  const _ShowMap({
    required this.config,
    required this.dark,
    required this.markers,
    required this.route,
    required this.interactive,
  });

  final MapsConfig config;
  final bool dark;
  final List<MapMarker> markers;
  final MapRoute? route;
  final bool interactive;

  @override
  State<_ShowMap> createState() => _ShowMapState();
}

class _ShowMapState extends State<_ShowMap> {
  KundeMapController? _map;
  MapRoute? _drawn;
  bool _fitted = false;

  @override
  void didUpdateWidget(_ShowMap old) {
    super.didUpdateWidget(old);
    _paint();
  }

  Future<void> _paint() async {
    final map = _map;
    if (map == null) return;
    try {
      if (!identical(_drawn, widget.route)) {
        _drawn = widget.route;
        final route = widget.route;
        await map.showRoutes(route == null ? const [] : [route], route);
      }
      await map.markers.setAll(widget.markers);
      if (!_fitted && widget.route != null) {
        _fitted = true;
        await map.camera.fitRoute(widget.route!, top: 40, bottom: 40);
      } else if (widget.route == null && widget.markers.isNotEmpty) {
        await map.camera.moveTo(widget.markers.first.point, zoom: 15);
      }
    } catch (_) {
      // The map is decoration for a flow that does not depend on it.
    }
  }

  @override
  Widget build(BuildContext context) => KundeMapView(
        config: widget.config,
        dark: widget.dark,
        interactive: widget.interactive,
        initialCenter:
            widget.markers.isEmpty ? almaty : widget.markers.first.point,
        initialZoom: widget.markers.isEmpty ? 11 : 14,
        onReady: (controller) {
          _map = controller;
          _paint();
        },
      );
}
