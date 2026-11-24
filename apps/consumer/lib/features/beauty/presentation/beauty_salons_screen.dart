import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import 'package:kunde_ui/beauty_strings.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_models/beauty_models.dart';
import 'beauty_salon_screen.dart';
import 'package:kunde_ui/beauty_support.dart';
import 'package:kunde_ui/beauty_widgets.dart';

/// «Салоны красоты»: server-side filters (Все / Рядом / Рейтинг / Акции), search, price and distance, pagination.
class BeautySalonsScreen extends StatefulWidget {
  const BeautySalonsScreen({
    required this.services,
    required this.favorites,
    this.initial = const BeautySalonQuery(),
    this.embedded = false,
    this.title,
    this.showFilters = true,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautySalonQuery initial;

  /// Inside the Beauty shell (no back button).
  final bool embedded;
  final String? title;
  final bool showFilters;

  @override
  State<BeautySalonsScreen> createState() => _BeautySalonsScreenState();
}

class _BeautySalonsScreenState extends State<BeautySalonsScreen> {
  static const _page = 20;

  late BeautySalonQuery _query = widget.initial;
  final _scroll = ScrollController();
  late final _search = TextEditingController(text: widget.initial.text);
  Timer? _debounce;
  final _salons = <BeautySalon>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _searching = false;
  ({double lat, double lng})? _where;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _searching = widget.initial.text.isNotEmpty;
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) unawaited(_loadMore());
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.services.beauty.salons(
        _query,
        lat: _where?.lat,
        lng: _where?.lng,
        limit: _page,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _salons
          ..clear()
          ..addAll(result.salons);
        _total = result.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _salons.length >= _total) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.services.beauty.salons(
        _query,
        lat: _where?.lat,
        lng: _where?.lng,
        limit: _page,
        offset: _salons.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _salons.addAll(result.salons);
        _total = result.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Device position for «Рядом»; null when location is off or denied (the server then keeps the default order).
  Future<void> _locate() async {
    if (_where != null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _where = (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // Plugin missing, timeout or denied: fall back to the city.
    }
  }

  Future<void> _setFilter(BeautyFilter filter) async {
    if (filter == BeautyFilter.nearby) {
      await _locate();
      if (!mounted) return;
      if (_where == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(KundeLocalizations.of(context).bDistanceNeedsLocation),
        ));
      }
    }
    setState(() => _query = _query.copyWith(filter: filter));
    unawaited(_reload());
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _query = _query.copyWith(text: text));
      unawaited(_reload());
    });
  }

  Future<void> _openFilters() async {
    await _locate();
    if (!mounted) return;
    final result = await showModalBottomSheet<BeautySalonQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeautyColors.background,
      showDragHandle: true,
      builder: (_) => BeautyScope(
        child: _FiltersSheet(query: _query, hasLocation: _where != null),
      ),
    );
    if (result == null) return;
    setState(() => _query = result);
    unawaited(_reload());
  }

  void _open(BeautySalon salon) {
    Navigator.of(context).push(beautyRoute(BeautySalonScreen(
      services: widget.services,
      favorites: widget.favorites,
      salon: salon,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final chips = {
      BeautyFilter.all: s.bFilterAll,
      BeautyFilter.nearby: s.bFilterNearby,
      BeautyFilter.rating: s.bFilterRating,
      BeautyFilter.promo: s.bFilterPromo,
    };
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(widget.title ?? s.bSalonsTitle),
        actions: [
          IconButton(
            tooltip: s.bSearchSalons,
            onPressed: () => setState(() => _searching = !_searching),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: widget.initial.text.isEmpty,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: s.bSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: BeautyColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          if (widget.showFilters)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final entry in chips.entries) ...[
                    BeautyFilterChip(
                      label: entry.value,
                      selected: _query.filter == entry.key,
                      onTap: () => _setFilter(entry.key),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _loading && _salons.isEmpty ? '' : s.bFound(_total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: BeautyColors.muted),
                  ),
                ),
                if (widget.showFilters)
                  IconButton(
                    tooltip: s.bFilters,
                    onPressed: _openFilters,
                    icon: Badge(
                      isLabelVisible: _query.hasExtraFilters,
                      child: const Icon(Icons.tune),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(KundeLocalizations s) {
    if (_loading && _salons.isEmpty) return const BeautySkeleton();
    if (_error != null && _salons.isEmpty) {
      return BeautyErrorView(error: _error, onRetry: _reload);
    }
    if (_salons.isEmpty) {
      return BeautyEmptyView(
        icon: Icons.search_off,
        title: s.bNothingFound,
        hint: s.bNothingFoundHint,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 24),
        itemCount: _salons.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: BeautyColors.line),
        itemBuilder: (context, index) {
          if (index >= _salons.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final salon = _salons[index];
          return ListenableBuilder(
            listenable: widget.favorites,
            builder: (context, _) => BeautySalonCard(
              salon: salon,
              favorite: widget.favorites.contains(salon.id),
              onTap: () => _open(salon),
              onFavorite: () =>
                  toggleFavorite(context, widget.favorites, salon.id),
            ),
          );
        },
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.query, required this.hasLocation});

  final BeautySalonQuery query;
  final bool hasLocation;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final _from = TextEditingController(
      text: widget.query.minPriceMinor == null
          ? ''
          : '${widget.query.minPriceMinor! ~/ 100}');
  late final _to = TextEditingController(
      text: widget.query.maxPriceMinor == null
          ? ''
          : '${widget.query.maxPriceMinor! ~/ 100}');
  late int? _distance = widget.query.maxDistanceMeters;
  late bool _verified = widget.query.verifiedOnly;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int? _tenge(TextEditingController c) {
    final value = int.tryParse(c.text.trim());
    return value == null || value < 0 ? null : value * 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BeautySectionHeader(s.bFilters),
            Text(s.bPrice, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: s.bFrom, border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: s.bTo, border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(s.bDistance,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (widget.hasLocation)
              Wrap(
                spacing: 8,
                children: [
                  for (final meters in const [1000, 3000, 5000, 10000])
                    BeautyFilterChip(
                      label: s.bKm(meters),
                      selected: _distance == meters,
                      onTap: () => setState(() =>
                          _distance = _distance == meters ? null : meters),
                    ),
                ],
              )
            else
              Text(s.bDistanceNeedsLocation,
                  style: const TextStyle(color: BeautyColors.muted)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              onChanged: (value) => setState(() => _verified = value),
              title: Text(s.bVerifiedOnly),
              activeThumbColor: BeautyColors.primary,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(widget.query
                      .copyWith(
                          clearPrice: true,
                          clearDistance: true,
                          verifiedOnly: false)),
                  child: Text(s.bReset),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BeautyPrimaryButton(
                    label: s.bApply,
                    onPressed: () => Navigator.of(context).pop(
                      BeautySalonQuery(
                        filter: widget.query.filter,
                        category: widget.query.category,
                        text: widget.query.text,
                        minPriceMinor: _tenge(_from),
                        maxPriceMinor: _tenge(_to),
                        maxDistanceMeters: _distance,
                        verifiedOnly: _verified,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
