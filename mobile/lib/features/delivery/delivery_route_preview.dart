import 'package:flutter/material.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import 'delivery_strings.dart';

class DeliveryRoutePreview extends StatefulWidget {
  const DeliveryRoutePreview({required this.route, super.key});

  final MapRoute route;

  @override
  State<DeliveryRoutePreview> createState() => _DeliveryRoutePreviewState();
}

class _DeliveryRoutePreviewState extends State<DeliveryRoutePreview> {
  bool _failed = false;
  int _mapVersion = 0;

  Future<void> _draw(KundeMapController controller) async {
    final route = widget.route;
    try {
      await controller.showRoutes([route], route);
      if (!mounted) return;
      await controller.markers.setAll([
        MapMarker(
            id: 'pickup', point: route.points.first, color: MapMarker.origin),
        MapMarker(
          id: 'destination',
          point: route.points.last,
          color: MapMarker.destination,
        ),
      ]);
      if (mounted) await controller.camera.fitRoute(route);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('Маршрут', 'Бағыт', 'Route'))),
      body: _failed
          ? Center(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _failed = false;
                  _mapVersion++;
                }),
                child: Text(s.retry),
              ),
            )
          : KundeMapView(
              key: ValueKey(_mapVersion),
              config: MapsConfig.fromEnvironment(language: s.language),
              dark: Theme.of(context).brightness == Brightness.dark,
              initialCenter: widget.route.points.first,
              onReady: _draw,
            ),
    );
  }
}
