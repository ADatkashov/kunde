import 'dart:async';

import 'package:flutter/material.dart';

import '../data/leisure_api.dart';
import '../data/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_event_screen.dart';
import 'leisure_strings.dart';
import 'leisure_widgets.dart';

/// Catalogue list of one category or search: quick chips (today, weekend, district), a full filter sheet, sorting and the result count.
class LeisureListScreen extends StatefulWidget {
  const LeisureListScreen(
      {required this.services, required this.initial, this.title, super.key});

  final LeisureServices services;
  final LeisureFilter initial;
  final String? title;

  @override
  State<LeisureListScreen> createState() => _LeisureListScreenState();
}

class _LeisureListScreenState extends State<LeisureListScreen> {
  late LeisureFilter _filter = widget.initial;
  late Future<List<EventCard>> _cards = _load();
  Set<String> _favorites = {};
  final _search = TextEditingController();
  Timer? _debounce;

  static const _districts = [
    'Бостандыкский',
    'Алмалинский',
    'Ауэзовский',
    'Медеуский',
    'Турксибский',
    'Жетысуский',
    'Алатауский',
    'Наурызбайский'
  ];

  @override
  void initState() {
    super.initState();
    _search.text = _filter.query;
    unawaited(widget.services.api.favorites().then((f) {
      if (mounted) setState(() => _favorites = f);
    }).catchError((_) {}));
  }

  Future<List<EventCard>> _load() => widget.services.api.events(_filter);

  void _apply(LeisureFilter f) => setState(() {
        _filter = f;
        _cards = _load();
      });

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite(EventCard c) async {
    final on = !_favorites.contains(c.id);
    setState(() => _favorites =
        on ? {..._favorites, c.id} : ({..._favorites}..remove(c.id)));
    try {
      await widget.services.api.setFavorite(c.id, on);
    } on LeisureException {
      if (mounted) {
        setState(() => _favorites =
            on ? ({..._favorites}..remove(c.id)) : {..._favorites, c.id});
      }
    }
  }

  void _pickDistrict() async {
    final s = lzL10n(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          RadioGroup<String>(
            groupValue: _filter.district ?? '',
            onChanged: (v) => Navigator.pop(context, v ?? ''),
            child: Column(children: [
              RadioListTile<String>(value: '', title: Text(s.lzAnyDistrict)),
              for (final d in _districts)
                RadioListTile<String>(value: d, title: Text(d)),
            ]),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    _apply(_filter.copyWith(district: picked.isEmpty ? null : picked));
  }

  void _pickSort() async {
    final s = lzL10n(context);
    final options = {
      'time': s.lzSortTime,
      'popular': s.lzSortPopular,
      'price': s.lzSortPrice,
      if (_filter.lat != null) 'distance': s.lzSortDistance,
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _filter.sort,
          onChanged: (v) => Navigator.pop(context, v),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in options.entries)
              RadioListTile<String>(value: e.key, title: Text(e.value)),
          ]),
        ),
      ),
    );
    if (picked != null) _apply(_filter.copyWith(sort: picked));
  }

  void _openFilters() async {
    final result = await showModalBottomSheet<LeisureFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (result != null) _apply(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final sortLabel = switch (_filter.sort) {
      'price' => s.lzSortPrice,
      'popular' => s.lzSortPopular,
      'distance' => s.lzSortDistance,
      _ => s.lzSortTime,
    };
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title ??
              (widget.services.isEvents ? s.evTitle : s.lzTitle)),
          centerTitle: true),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400),
                  () => _apply(_filter.copyWith(query: q)));
            },
            decoration: InputDecoration(
              hintText:
                  widget.services.isEvents ? s.evSearchHint : s.lzSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                FilterChip(
                  label: Text(s.lzToday),
                  selected: _filter.preset == 'today',
                  onSelected: (v) =>
                      _apply(_filter.copyWith(preset: v ? 'today' : null)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(s.lzWeekend),
                  selected: _filter.preset == 'weekend',
                  onSelected: (v) =>
                      _apply(_filter.copyWith(preset: v ? 'weekend' : null)),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: Text(_filter.district ?? s.lzDistrict),
                  selected: _filter.district != null,
                  avatar: const Icon(Icons.expand_more_rounded, size: 18),
                  onPressed: _pickDistrict,
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: Text(_filter.activeCount == 0
                      ? s.lzFilters
                      : '${s.lzFilters} · ${_filter.activeCount}'),
                  selected: _filter.activeCount > 0,
                  avatar: const Icon(Icons.tune_rounded, size: 18),
                  onPressed: _openFilters,
                ),
              ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(children: [
            TextButton.icon(
                onPressed: _pickSort,
                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                label: Text(sortLabel)),
            const Spacer(),
            FutureBuilder<List<EventCard>>(
              future: _cards,
              builder: (_, snap) => snap.hasData
                  ? Semantics(
                      liveRegion: true,
                      child: Text(s.lzFound(snap.data!.length),
                          style: theme.textTheme.bodySmall))
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _apply(_filter);
              await _cards;
            },
            child: FutureBuilder<List<EventCard>>(
              future: _cards,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return ListView(children: const [LeisureStateView.loading()]);
                }
                if (snap.hasError) {
                  final f = snap.error is LeisureException
                      ? (snap.error as LeisureException).failure
                      : LeisureFailure.other;
                  return ListView(children: [
                    LeisureStateView.error(
                        failure: f, onRetry: () => _apply(_filter))
                  ]);
                }
                final cards = snap.data!;
                if (cards.isEmpty) {
                  return ListView(children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: LeisureStateView.empty(
                          title: s.lzNothing, body: s.lzNothingBody),
                    ),
                    if (_filter.activeCount > 0 ||
                        _filter.preset != null ||
                        _filter.district != null)
                      Center(
                          child: TextButton(
                              onPressed: () => _apply(
                                  LeisureFilter(category: _filter.category)),
                              child: Text(s.lzReset))),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: cards.length,
                  itemBuilder: (_, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: EventTile(
                        card: cards[i],
                        favorite: _favorites.contains(cards[i].id),
                        onFavorite: () => _toggleFavorite(cards[i]),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => LeisureEventScreen(
                                    services: widget.services,
                                    eventId: cards[i].id))),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final LeisureFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late LeisureFilter _f = widget.initial;
  late final _min = TextEditingController(
      text: _f.minPriceMinor == null ? '' : '${_f.minPriceMinor! ~/ 100}');
  late final _max = TextEditingController(
      text: _f.maxPriceMinor == null ? '' : '${_f.maxPriceMinor! ~/ 100}');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _tenge(String v) {
    final n = int.tryParse(v.trim());
    return n == null || n < 0 ? null : n * 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final today = DateTime.now().toUtc().add(const Duration(hours: 5));
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(today.year, today.month, today.day + i)
    ];
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.lzFilters,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(s.lzDate, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                  label: Text(s.lzAnyDate),
                  selected: _f.date == null,
                  onSelected: (_) =>
                      setState(() => _f = _f.copyWith(date: null))),
              for (final d in days)
                ChoiceChip(
                  label: Text('${s.weekday(d)} ${d.day}'),
                  selected: _f.date == d,
                  onSelected: (_) =>
                      setState(() => _f = _f.copyWith(date: d, preset: null)),
                ),
            ]),
            const SizedBox(height: 16),
            Text(s.lzPrice, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.lzPriceFrom,
                          border: const OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.lzPriceTo,
                          border: const OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            Text(s.lzGuests, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: Text(s.lzAll),
                  selected: _f.guests == null,
                  onSelected: (_) =>
                      setState(() => _f = _f.copyWith(guests: null))),
              for (final g in [1, 2, 4, 6, 10])
                ChoiceChip(
                    label: Text('$g'),
                    selected: _f.guests == g,
                    onSelected: (_) =>
                        setState(() => _f = _f.copyWith(guests: g))),
            ]),
            const SizedBox(height: 16),
            Text(s.lzAge, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: Text(s.lzAll),
                  selected: _f.age == null,
                  onSelected: (_) =>
                      setState(() => _f = _f.copyWith(age: null))),
              for (final a in [0, 6, 12, 16, 18])
                ChoiceChip(
                    label: Text('$a'),
                    selected: _f.age == a,
                    onSelected: (_) =>
                        setState(() => _f = _f.copyWith(age: a))),
            ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.lzOnlyAvailable),
                value: _f.availableOnly,
                onChanged: (v) =>
                    setState(() => _f = _f.copyWith(availableOnly: v))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.lzFamilyOnly),
                value: _f.family,
                onChanged: (v) => setState(() => _f = _f.copyWith(family: v))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.lzRatingFrom),
                value: _f.minRating != null,
                onChanged: (v) => setState(
                    () => _f = _f.copyWith(minRating: v ? 4.0 : null))),
            if (_f.lat != null)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.lzRadius),
                  value: _f.radiusKm != null,
                  onChanged: (v) => setState(
                      () => _f = _f.copyWith(radiusKm: v ? 10.0 : null))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                      context,
                      LeisureFilter(
                          category: _f.category,
                          query: _f.query,
                          sort: _f.sort,
                          lat: _f.lat,
                          lng: _f.lng)),
                  child: Text(s.lzReset),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                      context,
                      _f.copyWith(
                          minPriceMinor: _tenge(_min.text),
                          maxPriceMinor: _tenge(_max.text))),
                  child: Text(s.lzApply),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
