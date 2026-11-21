import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kunde_design/kunde_design.dart';

import '../data/leisure_api.dart';
import '../data/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_event_screen.dart';
import 'leisure_list_screen.dart';
import 'leisure_orders_screen.dart';
import 'leisure_strings.dart';
import 'leisure_widgets.dart';

/// Leisure home: purple hero, search, city, category grid and sections (today, weekend, family, popular, near you).
/// Every card comes from the backend catalogue; with the switch off the server returns nothing and the screen says so.
class LeisureHomeScreen extends StatefulWidget {
  const LeisureHomeScreen({required this.services, super.key});

  final LeisureServices services;

  @override
  State<LeisureHomeScreen> createState() => _LeisureHomeScreenState();
}

class _LeisureHomeScreenState extends State<LeisureHomeScreen> {
  final _search = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locationDenied = false;
  bool _locating = false;
  late Future<List<LeisureCategory>> _categories =
      widget.services.api.categories();
  late Future<Map<String, List<EventCard>>> _home = _loadHome();
  Set<String> _favorites = {};

  Future<Map<String, List<EventCard>>> _loadHome() =>
      widget.services.api.home(lat: _lat, lng: _lng);

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
  }

  Future<void> _loadFavorites() async {
    try {
      final f = await widget.services.api.favorites();
      if (mounted) setState(() => _favorites = f);
    } on LeisureException {
      // favourites are optional on this screen
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _categories = widget.services.api.categories();
        _home = _loadHome();
      });

  void _openList(
      {String? category,
      String? preset,
      String? title,
      bool family = false,
      bool near = false,
      String query = ''}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LeisureListScreen(
        services: widget.services,
        title: title,
        initial: LeisureFilter(
          category: category,
          preset: preset,
          family: family,
          query: query,
          lat: near ? _lat : null,
          lng: near ? _lng : null,
          radiusKm: near ? 15 : null,
          sort: near ? 'distance' : (preset == 'popular' ? 'popular' : 'time'),
        ),
      ),
    ));
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationDenied = false;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationDenied = true);
        return;
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 12)));
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _home = _loadHome();
      });
    } catch (_) {
      if (mounted) setState(() => _locationDenied = true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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

  void _openEvent(EventCard c) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              LeisureEventScreen(services: widget.services, eventId: c.id)));

  void _showCity() {
    final s = lzL10n(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.radio_button_checked_rounded),
              title: Text(s.lzCity),
              onTap: () => Navigator.pop(context),
            ),
            Text(s.lzCityMore, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  void _showAllCategories(List<LeisureCategory> categories) {
    final lang = Localizations.localeOf(context).languageCode;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final c in categories)
              ListTile(
                leading: _CategoryIcon(code: c.code, size: 44),
                title: Text(c.name(lang)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  _openList(category: c.code, title: c.name(lang));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      body: RefreshIndicator(
        edgeOffset: 120,
        onRefresh: () async {
          _reload();
          await _home;
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: _Hero(
            title: s.lzTitle,
            subtitle: s.lzSubtitle,
            onBack: () => Navigator.of(context).maybePop(),
            onTickets: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    LeisureOrdersScreen(services: widget.services))),
            ticketsLabel: s.lzMyTickets,
          )),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ActionChip(
                              avatar: const Icon(Icons.location_on_rounded,
                                  size: 18),
                              label: Text(s.lzCity),
                              onPressed: _showCity,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _search,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (q) =>
                                _openList(query: q, title: s.lzSearchHint),
                            decoration: InputDecoration(
                              hintText: s.lzSearchHint,
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 18),
                          FutureBuilder<List<LeisureCategory>>(
                            future: _categories,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return const SkeletonBox(
                                    height: 190, radius: 22);
                              }
                              if (snap.hasError) {
                                final f = snap.error is LeisureException
                                    ? (snap.error as LeisureException).failure
                                    : LeisureFailure.other;
                                return LeisureStateView.error(
                                    failure: f, onRetry: _reload);
                              }
                              final cats = snap.data!;
                              if (cats.isEmpty) {
                                return LeisureStateView.empty(
                                    title: s.lzUnavailable,
                                    body: s.lzUnavailableBody,
                                    icon: Icons.pause_circle_outline_rounded);
                              }
                              return _CategoryGrid(
                                categories: cats,
                                lang: lang,
                                moreLabel: s.lzSeeAll,
                                onTap: (c) => _openList(
                                    category: c.code, title: c.name(lang)),
                                onMore: () => _showAllCategories(cats),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<Map<String, List<EventCard>>>(
                            future: _home,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return const Column(children: [
                                  EventTileSkeleton(),
                                  EventTileSkeleton()
                                ]);
                              }
                              if (snap.hasError) {
                                final f = snap.error is LeisureException
                                    ? (snap.error as LeisureException).failure
                                    : LeisureFailure.other;
                                return LeisureStateView.error(
                                    failure: f, onRetry: _reload);
                              }
                              final sections = snap.data!;
                              final blocks = <Widget>[];
                              void add(String key, String title,
                                  {VoidCallback? onAll}) {
                                final cards =
                                    sections[key] ?? const <EventCard>[];
                                if (cards.isEmpty) return;
                                blocks.add(_SectionTitle(
                                    title: title,
                                    action: s.lzSeeAll,
                                    onAction: onAll));
                                blocks.add(SizedBox(
                                  height: 248,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    itemCount: cards.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (_, i) => _FeaturedCard(
                                      card: cards[i],
                                      favorite:
                                          _favorites.contains(cards[i].id),
                                      onFavorite: () =>
                                          _toggleFavorite(cards[i]),
                                      onTap: () => _openEvent(cards[i]),
                                    ),
                                  ),
                                ));
                              }

                              add('today', s.lzToday,
                                  onAll: () => _openList(
                                      preset: 'today', title: s.lzToday));
                              add('weekend', s.lzWeekend,
                                  onAll: () => _openList(
                                      preset: 'weekend', title: s.lzWeekend));
                              add('family', s.lzFamily,
                                  onAll: () => _openList(
                                      family: true, title: s.lzFamily));
                              add('popular', s.lzPopular,
                                  onAll: () => _openList(
                                      preset: 'popular', title: s.lzPopular));
                              if (_lat != null) {
                                add('near', s.lzNearby,
                                    onAll: () => _openList(
                                        near: true, title: s.lzNearby));
                              } else {
                                blocks.add(_NearbyPrompt(
                                  label: s.lzNearbyAsk,
                                  denied:
                                      _locationDenied ? s.lzNearbyDenied : null,
                                  busy: _locating,
                                  title: s.lzNearby,
                                  onTap: _locate,
                                ));
                              }
                              if (blocks.length <= 1) {
                                blocks.insert(
                                    0,
                                    LeisureStateView.empty(
                                        title: s.lzNothing,
                                        body: s.lzNothingBody));
                              }
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: blocks);
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(s.lzDemoNote, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 32),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.title,
      required this.subtitle,
      required this.onBack,
      required this.onTickets,
      required this.ticketsLabel});

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onTickets;
  final String ticketsLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: KundePalette.heroGradient),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: 40,
          child: Icon(Icons.confirmation_number_rounded,
              size: 210, color: Colors.white.withValues(alpha: .08)),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 48),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white)),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onTickets,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      icon: const Icon(Icons.confirmation_number_outlined),
                      label: Text(ticketsLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05)),
                      ),
                      const SizedBox(height: 10),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Colors.white.withValues(alpha: .86))),
                    ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.code, this.size = 52});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = leisureGradient(code);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.last.withValues(alpha: .28),
              colors.last.withValues(alpha: .12),
            ]),
      ),
      child: Icon(leisureIcon(code),
          size: size * .5, color: colors.first.withValues(alpha: .92)),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid(
      {required this.categories,
      required this.lang,
      required this.onTap,
      required this.onMore,
      required this.moreLabel});

  final List<LeisureCategory> categories;
  final String lang;
  final void Function(LeisureCategory) onTap;
  final VoidCallback onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    final shown = categories.take(9).toList();
    final items = <Widget>[
      for (final c in shown)
        _tile(context, c.name(lang), _CategoryIcon(code: c.code),
            () => onTap(c), c.name(lang)),
      if (categories.length > 9)
        _tile(
            context,
            moreLabel,
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: const Icon(Icons.more_horiz_rounded),
            ),
            onMore,
            moreLabel),
    ];
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 520 ? 6 : 5;
      final width = box.maxWidth / columns;
      return Wrap(
          runSpacing: 10,
          children: [for (final i in items) SizedBox(width: width, child: i)]);
    });
  }

  Widget _tile(BuildContext context, String label, Widget icon,
          VoidCallback onTap, String semantic) =>
      Semantics(
        button: true,
        label: semantic,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: ExcludeSemantics(
                child: Column(children: [
                  icon,
                  const SizedBox(height: 6),
                  Text(label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(
      {required this.title, required this.action, this.onAction});

  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Expanded(
              child: Semantics(
                  header: true,
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)))),
          if (onAction != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ]),
      );
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard(
      {required this.card,
      required this.favorite,
      required this.onFavorite,
      required this.onTap});

  final EventCard card;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Semantics(
        button: true,
        label:
            '${card.title}, ${s.lzFromPrice(formatTenge(card.minPriceMinor))}',
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          elevation: 2,
          shadowColor: KundePalette.shadow,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 118,
                child: Stack(fit: StackFit.expand, children: [
                  EventPhoto(
                      url: card.photoUrl,
                      category: card.categoryCode,
                      iconSize: 42),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: Colors.white.withValues(alpha: .9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: s.lzFavorite,
                        visualDensity: VisualDensity.compact,
                        onPressed: onFavorite,
                        icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: favorite
                                ? const Color(0xFFE0405E)
                                : Colors.black54),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(card.venueName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      if (card.rating != null)
                        RatingBadge(
                            rating: card.rating!, count: card.reviewCount),
                      Text(s.lzFromPrice(formatTenge(card.minPriceMinor)),
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary)),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NearbyPrompt extends StatelessWidget {
  const _NearbyPrompt(
      {required this.label,
      required this.title,
      required this.busy,
      required this.onTap,
      this.denied});

  final String label;
  final String title;
  final String? denied;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (denied != null) ...[
            const SizedBox(height: 6),
            Text(denied!, style: theme.textTheme.bodySmall)
          ],
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: busy ? null : onTap,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.near_me_rounded),
            label: Text(label),
          ),
        ]),
      ),
    );
  }
}
