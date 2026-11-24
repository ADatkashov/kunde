import 'package:flutter/material.dart';

import '../data/leisure_api.dart';
import 'package:kunde_models/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_strings.dart';
import 'leisure_ticket_screen.dart';
import 'leisure_widgets.dart';

/// My entertainment: upcoming, completed and cancelled bookings. Everything is read from the server, so a restart of the app loses nothing and
/// bookings stay available even while new Leisure bookings are switched off.
class LeisureOrdersScreen extends StatefulWidget {
  const LeisureOrdersScreen({required this.services, super.key});

  final LeisureServices services;

  @override
  State<LeisureOrdersScreen> createState() => _LeisureOrdersScreenState();
}

class _LeisureOrdersScreenState extends State<LeisureOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  static const _scopes = ['upcoming', 'completed', 'cancelled'];
  late final List<Future<List<LeisureOrder>>> _futures = [
    for (final s in _scopes) widget.services.api.orders(s)
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload(int i) => setState(() {
        _futures[i] = widget.services.api.orders(_scopes[i]);
      });

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.lzOrdersTitle),
        centerTitle: true,
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: s.lzUpcoming),
          Tab(text: s.lzCompleted),
          Tab(text: s.lzCancelled)
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        for (var i = 0; i < 3; i++)
          RefreshIndicator(
            onRefresh: () async {
              _reload(i);
              await _futures[i];
            },
            child: FutureBuilder<List<LeisureOrder>>(
              future: _futures[i],
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
                        failure: f, onRetry: () => _reload(i))
                  ]);
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return ListView(children: [
                    Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: LeisureStateView.empty(
                            title: s.lzNoOrders,
                            body: s.lzNoOrdersBody,
                            icon: Icons.confirmation_number_outlined))
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, k) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _OrderTile(
                        order: list[k],
                        onTap: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => LeisureTicketScreen(
                                      services: widget.services,
                                      orderId: list[k].id,
                                      initial: list[k])));
                          if (mounted) {
                            for (var j = 0; j < 3; j++) {
                              _reload(j);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final LeisureOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '${order.eventTitle}, ${s.lzWhen(order.startsAt)}, ${s.lzStatus(order.status)}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          elevation: 1.5,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                        width: 78,
                        height: 92,
                        child: EventPhoto(
                            url: order.photoUrl,
                            category: order.categoryCode,
                            iconSize: 30))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.eventTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(s.lzWhen(order.startsAt),
                            style: theme.textTheme.bodySmall),
                        Text(order.venueName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              MiniChip(s.lzStatus(order.status),
                                  filled: order.status == 'CONFIRMED'),
                              Text(formatTenge(order.totalMinor),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: theme.colorScheme.primary)),
                            ]),
                      ]),
                ),
                const Icon(Icons.qr_code_2_rounded),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
