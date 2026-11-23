import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../../booking/presentation/bookings_list.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_favorites_screen.dart';
import 'beauty_salons_screen.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// Route name of the Beauty shell; flows pop back to it.
const beautyShellRoute = 'beauty-shell';

Route<void> beautyShellRouteFor(BookingServices services) =>
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: beautyShellRoute),
      builder: (_) => BeautyScope(child: BeautyShell(services: services)),
    );

/// Beauty & Care with its own bottom navigation: Главная, Каталог, Акции, Профиль.
class BeautyShell extends StatefulWidget {
  const BeautyShell({required this.services, this.initialTab = 0, super.key});

  final BookingServices services;
  final int initialTab;

  @override
  State<BeautyShell> createState() => _BeautyShellState();
}

class _BeautyShellState extends State<BeautyShell> {
  late int _tab = widget.initialTab;
  late final BeautyFavorites _favorites =
      BeautyFavorites(widget.services.beauty)..load();

  @override
  void dispose() {
    _favorites.dispose();
    super.dispose();
  }

  void _openCatalog({String? category, String text = ''}) {
    Navigator.of(context).push(beautyRoute(BeautySalonsScreen(
      services: widget.services,
      favorites: _favorites,
      initial: BeautySalonQuery(category: category, text: text),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final pages = <Widget>[
      _BeautyHomeTab(
        services: widget.services,
        onOpenCatalog: _openCatalog,
        onOpenPromos: () => setState(() => _tab = 2),
      ),
      BeautySalonsScreen(
        services: widget.services,
        favorites: _favorites,
        embedded: true,
      ),
      BeautySalonsScreen(
        services: widget.services,
        favorites: _favorites,
        embedded: true,
        initial: const BeautySalonQuery(filter: BeautyFilter.promo),
        title: s.bPromosTitle,
        showFilters: false,
      ),
      _BeautyProfileTab(services: widget.services, favorites: _favorites),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: s.bTabHome),
          NavigationDestination(
              icon: const Icon(Icons.search),
              selectedIcon: const Icon(Icons.search),
              label: s.bTabCatalog),
          NavigationDestination(
              icon: const Icon(Icons.local_offer_outlined),
              selectedIcon: const Icon(Icons.local_offer),
              label: s.bTabPromos),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: s.bTabProfile),
        ],
      ),
    );
  }
}

class _HomeData {
  const _HomeData(this.categories, this.promotions);

  final List<BeautyCategory> categories;
  final BeautyPromotions promotions;
}

class _BeautyHomeTab extends StatelessWidget {
  const _BeautyHomeTab({
    required this.services,
    required this.onOpenCatalog,
    required this.onOpenPromos,
  });

  final BookingServices services;
  final void Function({String? category, String text}) onOpenCatalog;
  final VoidCallback onOpenPromos;

  Future<_HomeData> _load() async {
    final results = await Future.wait<Object>([
      services.beauty.categories(),
      services.beauty.promotions(),
    ]);
    return _HomeData(
      results[0] as List<BeautyCategory>,
      results[1] as BeautyPromotions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Stack(
      children: [
        Container(
          height: 270,
          decoration: const BoxDecoration(gradient: BeautyColors.hero),
          child: const Stack(
            children: [
              Positioned(
                right: -20,
                top: 40,
                child: Icon(Icons.local_florist,
                    size: 170, color: Color(0x33FFFFFF)),
              ),
              Positioned(
                right: 90,
                top: 20,
                child: Icon(Icons.spa, size: 60, color: Color(0x33FFFFFF)),
              ),
            ],
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 20),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.bHomeTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.bHomeSubtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: BeautyColors.background,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: BeautyAsync<_HomeData>(
                    load: _load,
                    builder: (context, data) => _HomeBody(
                      data: data,
                      onOpenCatalog: onOpenCatalog,
                      onOpenPromos: onOpenPromos,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.data,
    required this.onOpenCatalog,
    required this.onOpenPromos,
  });

  final _HomeData data;
  final void Function({String? category, String text}) onOpenCatalog;
  final VoidCallback onOpenPromos;

  void _more(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final lang = s.locale.languageCode;
    final rest = data.categories.where((c) => !c.featured).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BeautyColors.background,
      showDragHandle: true,
      builder: (sheet) => BeautyScope(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BeautySectionHeader(s.bAllCategories),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    for (final c in rest)
                      BeautyCategoryTile(
                        icon: beautyIcon(c.icon),
                        label: c.name(lang),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          onOpenCatalog(category: c.code);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final lang = s.locale.languageCode;
    final featured = data.categories.where((c) => c.featured).toList();
    final hasMore = data.categories.any((c) => !c.featured);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: BeautyColors.primary),
            const SizedBox(width: 6),
            Text(
              s.bCityAlmaty,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Icon(Icons.keyboard_arrow_down, color: BeautyColors.muted),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: (text) => onOpenCatalog(text: text),
          decoration: InputDecoration(
            hintText: s.bSearchHint,
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: BeautyColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: BeautyColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: BeautyColors.line),
            ),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final c in featured)
              BeautyCategoryTile(
                icon: beautyIcon(c.icon),
                label: c.name(lang),
                onTap: () => onOpenCatalog(category: c.code),
              ),
            if (hasMore)
              BeautyCategoryTile(
                icon: Icons.more_horiz,
                label: s.bMore,
                onTap: () => _more(context),
              ),
          ],
        ),
        if (data.promotions.maxPercent != null) ...[
          const SizedBox(height: 18),
          _PromoBanner(
            percent: data.promotions.maxPercent!,
            onTap: onOpenPromos,
          ),
        ],
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.percent, required this.onTap});

  final int percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: BeautyColors.hero,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.bPromoBanner(percent),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: BeautyColors.cta,
              ),
              child: const Icon(Icons.percent, color: Colors.white, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeautyProfileTab extends StatelessWidget {
  const _BeautyProfileTab({required this.services, required this.favorites});

  final BookingServices services;
  final BeautyFavorites favorites;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.bTabProfile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileTile(
            icon: Icons.event_available_outlined,
            label: s.bMyBookings,
            onTap: () => Navigator.of(context).push(beautyRoute(Scaffold(
              appBar: AppBar(title: Text(s.bMyBookings)),
              body: BookingsList(
                services: services,
                beautyEnabled: true,
              ),
            ))),
          ),
          _ProfileTile(
            icon: Icons.favorite_border,
            label: s.bFavorites,
            onTap: () => Navigator.of(context).push(beautyRoute(
              BeautyFavoritesScreen(services: services, favorites: favorites),
            )),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: BeautyColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BeautyColors.line),
          ),
          child: ListTile(
            leading: Icon(icon, color: BeautyColors.primary),
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );
}
