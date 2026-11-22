import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import '../maps/kunde_maps.dart';
import 'ride_api.dart';
import 'ride_strings.dart';

GeoPoint pointOf(RideAddress address) => GeoPoint.parse(
      address.point['latitude'],
      address.point['longitude'],
    );

/// Turns a picked map point into the address the Rides API accepts. A search
/// result keeps its real name; a dropped pin is labelled by its coordinates,
/// because the Maps Platform has no reverse geocoder and nothing is invented.
RideAddress addressFrom(PickedLocation picked, String language) {
  final name = picked.label(language)?.trim();
  final lat = picked.point.lat;
  final lon = picked.point.lon;
  return RideAddress(
    name != null && name.isNotEmpty
        ? name
        : '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
    {'latitude': lat, 'longitude': lon},
  );
}

/// Pickup and destination on a map with the road route and its typical time.
/// The price is not computed here: the server issues it with the quote.
class RideRoutePreviewPanel extends StatefulWidget {
  const RideRoutePreviewPanel({
    required this.maps,
    required this.pickup,
    required this.destination,
    this.quotedRoute,
    super.key,
  });

  final KundeMaps maps;
  final RideAddress pickup;
  final RideAddress destination;
  final MapRoute? quotedRoute;

  @override
  State<RideRoutePreviewPanel> createState() => _RideRoutePreviewPanelState();
}

class _RideRoutePreviewPanelState extends State<RideRoutePreviewPanel> {
  RoutePreviewData? _preview;
  String? _error;
  bool _loading = false;
  Completer<void>? _abort;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(RideRoutePreviewPanel old) {
    super.didUpdateWidget(old);
    if (old.pickup != widget.pickup || old.destination != widget.destination) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _abort?.complete();
    final abort = Completer<void>();
    _abort = abort;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await widget.maps.routing.preview(
        pointOf(widget.pickup),
        pointOf(widget.destination),
        abort: abort.future,
      );
      if (!mounted || abort.isCompleted) return;
      setState(() => _preview = preview);
    } on MapsException catch (error) {
      if (mounted && !abort.isCompleted) setState(() => _error = error.code);
    } catch (_) {
      if (mounted && !abort.isCompleted) setState(() => _error = 'invalid');
    } finally {
      if (mounted && !abort.isCompleted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _abort?.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.maps.config.language;
    final strings = MapsStrings(language);
    final quoted = widget.quotedRoute;
    final preview = quoted == null ? _preview : RoutePreviewData([quoted]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.maps.map(
              context,
              markers: [
                MapMarker(
                  id: 'pickup',
                  point: pointOf(widget.pickup),
                  color: MapMarker.origin,
                ),
                MapMarker(
                  id: 'destination',
                  point: pointOf(widget.destination),
                  color: MapMarker.destination,
                  radius: 8,
                ),
              ],
              route: preview?.route,
            ),
            const SizedBox(height: 12),
            if (_loading && quoted == null) const LinearProgressIndicator(),
            if (preview != null)
              RoutePreview(data: preview, language: language),
            if (_error != null && quoted == null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  strings.error(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _loading ? null : _load,
                  child: Text(RideStrings(context).retry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The assigned driver's last position while a trip is active. The server
/// withholds stale positions, so a missing location simply hides this panel.
class RideDriverMapPanel extends StatelessWidget {
  const RideDriverMapPanel({
    required this.maps,
    required this.location,
    this.label,
    super.key,
  });

  final KundeMaps maps;
  final RideDriverLocation location;

  /// Accessibility label; defaults to the driver text.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final point = GeoPoint.parse(location.latitude, location.longitude);
    return Semantics(
      label: label ??
          RideStrings(context).t(
            'Местоположение водителя на карте',
            'Жүргізушінің картадағы орны',
            'Driver location on the map',
          ),
      child: maps.map(
        context,
        height: 220,
        markers: [
          MapMarker(
              id: 'driver', point: point, color: MapMarker.vehicle, radius: 9),
        ],
      ),
    );
  }
}
