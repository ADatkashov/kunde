import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ops_store.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/now_builder.dart';
import '../../widgets/states.dart';
import 'dashboard_stats.dart';

/// Home tab: what needs attention now, today's numbers, quick actions and the
/// latest events. Only confirmed backend data is shown.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.controller,
    required this.store,
    required this.onNavigate,
    super.key,
  });
  final AppController controller;
  final OpsStore store;

  /// Shell tab indexes: see [PartnerShell].
  final void Function(DashboardTarget target) onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.navHome)),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final firstLoad = !store.activeOrders.hasData &&
              !store.bookingRequests.hasData &&
              !store.activeOrders.failedWithoutData &&
              !store.bookingRequests.failedWithoutData;
          if (firstLoad) return const SkeletonList(count: 3);
          if (store.activeOrders.failedWithoutData &&
              store.bookingRequests.failedWithoutData) {
            return ErrorView(
                error: store.activeOrders.error!, onRetry: store.refreshAll);
          }
          return RefreshIndicator(
            onRefresh: store.refreshAll,
            child: NowBuilder(
              every: const Duration(seconds: 30),
              builder: (context, now) => _Content(
                controller: controller,
                store: store,
                stats: DashboardStats.from(store, now),
                now: now,
                onNavigate: onNavigate,
              ),
            ),
          );
        },
      ),
    );
  }
}

enum DashboardTarget { orders, bookings, business }

class _Content extends StatelessWidget {
  const _Content({
    required this.controller,
    required this.store,
    required this.stats,
    required this.now,
    required this.onNavigate,
  });
  final AppController controller;
  final OpsStore store;
  final DashboardStats stats;
  final DateTime now;
  final void Function(DashboardTarget) onNavigate;

  bool get _hasFood => (store.restaurants.data?.isNotEmpty ?? true);
  bool get _hasBooking => (store.venues.data?.isNotEmpty ?? true);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = context.text;
    final name = controller.partner?.name ?? '';
    final error = store.activeOrders.error ?? store.bookingRequests.error;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        if (error != null) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(Radii.control),
              child: StaleBanner(error: error)),
          const SizedBox(height: Gap.md),
        ],
        Text(s.greeting(now.hour),
            style: text.bodyMedium
                ?.copyWith(color: context.colors.onSurfaceVariant)),
        Text(name.isEmpty ? s.navBusiness : name, style: text.headlineSmall),
        const SizedBox(height: Gap.lg),
        _AttentionCard(
          stats: stats,
          showOrders: _hasFood,
          showBookings: _hasBooking,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: Gap.xl),
        Text(s.dashToday, style: text.titleMedium),
        const SizedBox(height: Gap.md),
        _KpiGrid(stats: stats, showOrders: _hasFood, showBookings: _hasBooking),
        const SizedBox(height: Gap.xl),
        Text(s.quickActions, style: text.titleMedium),
        const SizedBox(height: Gap.md),
        Wrap(spacing: Gap.md, runSpacing: Gap.md, children: [
          if (_hasFood)
            _QuickAction(
                icon: Icons.receipt_long_rounded,
                label: s.navOrders,
                onTap: () => onNavigate(DashboardTarget.orders)),
          if (_hasBooking)
            _QuickAction(
                icon: Icons.event_rounded,
                label: s.navBookings,
                onTap: () => onNavigate(DashboardTarget.bookings)),
          _QuickAction(
              icon: Icons.storefront_rounded,
              label: s.navBusiness,
              onTap: () => onNavigate(DashboardTarget.business)),
          _QuickAction(
              icon: Icons.refresh_rounded,
              label: s.refresh,
              onTap: store.refreshAll),
        ]),
        const SizedBox(height: Gap.xl),
        Text(s.recentEvents, style: text.titleMedium),
        const SizedBox(height: Gap.md),
        _EventFeed(events: stats.events),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.stats,
    required this.showOrders,
    required this.showBookings,
    required this.onNavigate,
  });
  final DashboardStats stats;
  final bool showOrders;
  final bool showBookings;
  final void Function(DashboardTarget) onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tones = context.tones;
    final newOrders = showOrders ? stats.newOrders : 0;
    final requests = showBookings ? stats.pendingRequests : 0;
    if (newOrders + requests == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, color: tones.success, size: 32),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.dashAllClearTitle, style: context.text.titleMedium),
                    Text(s.dashAllClearBody,
                        style: context.text.bodyMedium
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
                  ]),
            ),
          ]),
        ),
      );
    }
    return Semantics(
      container: true,
      label: s.dashAttentionTitle,
      child: Card(
        color: tones.warningContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.notifications_active_rounded, color: tones.warning),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(s.dashAttentionTitle,
                    style: context.text.titleMedium
                        ?.copyWith(color: context.colors.onSurface)),
              ),
            ]),
            const SizedBox(height: Gap.md),
            if (newOrders > 0) ...[
              Text(s.dashNewOrdersLine(newOrders),
                  style: context.text.titleLarge
                      ?.copyWith(color: context.colors.onSurface)),
              if (stats.soonestDeadline != null)
                NowBuilder(
                  builder: (context, now) {
                    final left = minutesLeft(stats.soonestDeadline!, now);
                    return Text(
                      stats.soonestDeadline!.isAfter(now)
                          ? '${s.replyBy(formatTime(stats.soonestDeadline!))} · ${s.minutesLeftText(left)}'
                          : s.replyOverdue,
                      style: context.text.bodyMedium
                          ?.copyWith(color: context.colors.onSurface),
                    );
                  },
                ),
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: () => onNavigate(DashboardTarget.orders),
                child: Text(s.navOrders),
              ),
            ],
            if (newOrders > 0 && requests > 0) const SizedBox(height: Gap.lg),
            if (requests > 0) ...[
              Text(s.dashRequestsLine(requests),
                  style: context.text.titleLarge
                      ?.copyWith(color: context.colors.onSurface)),
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: () => onNavigate(DashboardTarget.bookings),
                child: Text(s.navBookings),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid(
      {required this.stats,
      required this.showOrders,
      required this.showBookings});
  final DashboardStats stats;
  final bool showOrders;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tiles = <Widget>[
      if (showOrders)
        _Kpi(
            label: s.kpiNewOrders,
            value: '${stats.newOrders}',
            icon: Icons.notifications_none_rounded),
      if (showOrders)
        _Kpi(
            label: s.kpiActiveOrders,
            value: '${stats.activeOrders}',
            icon: Icons.soup_kitchen_outlined),
      if (showBookings)
        _Kpi(
            label: s.kpiRequests,
            value: '${stats.pendingRequests}',
            icon: Icons.inbox_outlined),
      if (showBookings)
        _Kpi(
            label: s.kpiUpcoming,
            value: '${stats.upcomingBookings}',
            icon: Icons.event_available_outlined),
      _Kpi(
          label: s.kpiCompleted,
          value: '${stats.completedToday}',
          icon: Icons.task_alt_rounded),
      if (showOrders)
        _Kpi(
          label: s.kpiRevenue,
          value: formatMoney(stats.revenueTodayMinor),
          note: stats.revenueComplete ? s.kpiRevenueNote : s.kpiRevenuePartial,
          icon: Icons.payments_outlined,
        ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
      final cols = c.maxWidth < 340 || scale > 1.3 ? 1 : 2;
      final width = (c.maxWidth - (cols - 1) * Gap.md) / cols;
      return Wrap(
        spacing: Gap.md,
        runSpacing: Gap.md,
        children: [for (final t in tiles) SizedBox(width: width, child: t)],
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(
      {required this.label,
      required this.value,
      required this.icon,
      this.note});
  final String label;
  final String value;
  final String? note;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: context.colors.primary),
                    const SizedBox(height: Gap.sm),
                    Text(value,
                        style: context.text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: context.text.bodyMedium
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
                    if (note != null)
                      Text(note!,
                          style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant)),
                  ]),
            ),
          ),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _EventFeed extends StatelessWidget {
  const _EventFeed({required this.events});
  final List<FeedEvent> events;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    if (events.isEmpty) {
      return Text(s.noEvents,
          style: context.text.bodyMedium
              ?.copyWith(color: context.colors.onSurfaceVariant));
    }
    return Card(
      child: Column(children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) const Divider(),
          ListTile(
            leading: Icon(
                events[i].isOrder
                    ? Icons.receipt_long_outlined
                    : Icons.event_outlined,
                color: context.colors.primary),
            title: Text(events[i].isOrder
                ? s.eventOrder(events[i].ref, events[i].status)
                : s.eventBooking(events[i].ref, events[i].status)),
            subtitle: Text(
                '${formatDateTime(events[i].at, locale)} · ${s.actorName(events[i].actor)}'),
          ),
        ],
      ]),
    );
  }
}
