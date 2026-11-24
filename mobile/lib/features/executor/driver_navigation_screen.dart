import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import 'package:kunde_maps/kunde_maps.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Guides the driver from the current position to [target] with the KUNDE
/// Maps SDK: route, voice, rerouting. The trip status, orders and payments
/// stay with the Rides backend; this screen only moves the driver.
///
/// Guidance runs while this screen is open (foreground location, no
/// background service).
class DriverNavigationScreen extends StatefulWidget {
  const DriverNavigationScreen({
    required this.maps,
    required this.target,
    required this.title,
    this.location = const DeviceLocationSource(),
    this.voice,
    super.key,
  });

  final KundeMaps maps;
  final GeoPoint target;
  final String title;
  final LocationSource location;
  final VoiceGuide? voice;

  @override
  State<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

enum _Phase { locating, routing, ready, failed }

class _DriverNavigationScreenState extends State<DriverNavigationScreen> {
  _Phase _phase = _Phase.locating;
  String? _failure;
  GpsAccess? _gps;
  NavigationController? _nav;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    final attempt = ++_attempt;
    setState(() {
      _phase = _Phase.locating;
      _failure = null;
      _gps = null;
    });
    final access = await widget.location.access();
    if (!mounted || attempt != _attempt) return;
    if (access != GpsAccess.ok) {
      setState(() {
        _phase = _Phase.failed;
        _gps = access;
      });
      return;
    }
    final fix = await widget.location.current();
    if (!mounted || attempt != _attempt) return;
    if (fix == null) {
      setState(() {
        _phase = _Phase.failed;
        _failure = 'gps';
      });
      return;
    }
    setState(() => _phase = _Phase.routing);
    try {
      final routes = await widget.maps.routing.routes(
        fix.point,
        widget.target,
      );
      if (!mounted || attempt != _attempt) return;
      final nav = NavigationController(
        client: widget.maps.api,
        strings: MapsStrings(widget.maps.config.language),
        mode: RouteMode.car.apiName,
        destination: widget.target,
        route: routes.first,
        location: widget.location,
        voiceGuide: widget.voice,
        // Foreground-only guidance: no foreground service or notification.
        notificationPermission: () async => false,
      );
      if (!await nav.start()) {
        nav.dispose();
        if (!mounted || attempt != _attempt) return;
        setState(() {
          _phase = _Phase.failed;
          _failure = 'gps';
        });
        return;
      }
      if (!mounted || attempt != _attempt) {
        nav.dispose();
        return;
      }
      setState(() {
        _nav = nav;
        _phase = _Phase.ready;
      });
    } on MapsException catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = error.code;
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = 'invalid';
      });
    }
  }

  @override
  void dispose() {
    _attempt++;
    _nav?.dispose();
    super.dispose();
  }

  String _message(RideStrings s) {
    final strings = MapsStrings(widget.maps.config.language);
    return switch (_gps) {
      GpsAccess.serviceOff => strings('gpsOff'),
      GpsAccess.denied || GpsAccess.deniedForever => strings('gpsDenied'),
      _ => strings.error(_failure ?? 'invalid'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final nav = _nav;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: switch (_phase) {
        _Phase.ready when nav != null => NavigationView(
            config: widget.maps.config,
            controller: nav,
            dark: Theme.of(context).brightness == Brightness.dark,
            onStop: () => Navigator.of(context).pop(),
          ),
        _Phase.failed => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(_message(s), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _begin, child: Text(s.retry)),
                ],
              ),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
