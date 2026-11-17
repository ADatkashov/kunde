import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/states.dart';

/// Read-only list of the partner's restaurants and venues (management screens
/// are added on top of this in a later step).
class BusinessScreen extends StatelessWidget {
  const BusinessScreen({required this.store, super.key});
  final OpsStore store;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.navBusiness)),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final r = store.restaurants;
          final v = store.venues;
          if (!r.hasData && !v.hasData) {
            if (r.failedWithoutData && v.failedWithoutData) {
              return ErrorView(error: r.error!, onRetry: store.refreshModules);
            }
            return const SkeletonList(count: 2);
          }
          final restaurants = r.data ?? const [];
          final venues = v.data ?? const [];
          return RefreshIndicator(
            onRefresh: store.refreshModules,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                for (final x in restaurants)
                  _Tile(
                      icon: Icons.restaurant_rounded,
                      name: x.name,
                      open: x.open),
                for (final x in venues)
                  _Tile(
                      icon: Icons.content_cut_rounded,
                      name: x.name,
                      open: x.open),
                if (restaurants.isEmpty && venues.isEmpty)
                  SizedBox(
                    height: 360,
                    child: MessageView(
                        icon: Icons.storefront_outlined,
                        title: s.businessEmptyTitle,
                        body: s.businessEmptyBody),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.name, required this.open});
  final IconData icon;
  final String name;
  final bool open;
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: context.colors.primary),
          title: Text(name, style: context.text.titleMedium),
          subtitle: Text(open ? s.openNow : s.closedNow),
        ),
      ),
    );
  }
}
