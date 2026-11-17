import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/states.dart';
import 'booking_actions.dart';
import 'booking_card.dart';
import 'booking_details_page.dart';
import 'booking_filters.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({required this.store, super.key});
  final OpsStore store;
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  DateFilter _date = DateFilter.all;
  String? _status; // history only

  OpsStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final requests = store.bookingRequests.data?.length ?? 0;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.navBookings),
              bottom: TabBar(tabs: [
                Tab(
                    text: requests > 0
                        ? '${s.tabRequests} ($requests)'
                        : s.tabRequests),
                Tab(text: s.tabUpcoming),
                Tab(text: s.tabHistory),
              ]),
            ),
            body: Column(children: [
              _Filters(
                date: _date,
                status: _status,
                onDate: (d) => setState(() => _date = d),
                onStatus: (v) => setState(() => _status = v),
              ),
              Expanded(
                child: TabBarView(children: [
                  _list(
                      context,
                      store.bookingRequests,
                      store.refreshBookingRequests,
                      Icons.inbox_outlined,
                      s.bookingsEmptyRequestsTitle,
                      s.bookingsEmptyRequestsBody),
                  _list(
                      context,
                      store.bookingUpcoming,
                      store.refreshBookingUpcoming,
                      Icons.event_available_outlined,
                      s.bookingsEmptyUpcomingTitle,
                      s.bookingsEmptyUpcomingBody),
                  _list(
                      context,
                      store.bookingHistory,
                      store.refreshBookingHistory,
                      Icons.history_rounded,
                      s.bookingsEmptyHistoryTitle,
                      s.bookingsEmptyHistoryBody,
                      history: true),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _list(
      BuildContext context,
      Loadable<List<PartnerBooking>> slot,
      Future<void> Function() refresh,
      IconData icon,
      String emptyTitle,
      String emptyBody,
      {bool history = false}) {
    final s = S.of(context);
    if (!slot.hasData) {
      return slot.failedWithoutData
          ? ErrorView(error: slot.error!, onRetry: refresh)
          : const SkeletonList();
    }
    final all = slot.data!;
    final filtered = filterBookings(all,
        date: _date, status: history ? _status : null, now: DateTime.now());
    final filtering = _date != DateFilter.all || (history && _status != null);
    return Column(children: [
      if (slot.error != null) StaleBanner(error: slot.error!),
      Expanded(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: filtered.isEmpty
              ? LayoutBuilder(
                  builder: (context, c) => ListView(children: [
                    SizedBox(
                      height: c.maxHeight,
                      child: filtering && all.isNotEmpty
                          ? MessageView(
                              icon: Icons.filter_alt_off_outlined,
                              title: s.bookingsFilterEmptyTitle,
                              body: s.bookingsFilterEmptyBody)
                          : MessageView(
                              icon: icon, title: emptyTitle, body: emptyBody),
                    ),
                  ]),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Gap.lg),
                  itemCount: filtered.length +
                      (history && store.bookingHistoryHasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: Gap.md),
                  itemBuilder: (context, i) {
                    if (i >= filtered.length) {
                      return Center(
                        child: store.loadingMoreBookings
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: store.loadMoreBookingHistory,
                                child: Text(s.loadMore)),
                      );
                    }
                    final b = filtered[i];
                    return BookingCard(
                      booking: b,
                      busy: store.isBusy(b.id),
                      onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => BookingDetailsPage(
                                  store: store, bookingId: b.id))),
                      onAction: (a) =>
                          performBookingAction(context, store, b, a),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.date,
    required this.status,
    required this.onDate,
    required this.onStatus,
  });
  final DateFilter date;
  final String? status;
  final ValueChanged<DateFilter> onDate;
  final ValueChanged<String?> onStatus;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final labels = {
      DateFilter.all: s.all,
      DateFilter.today: s.today,
      DateFilter.tomorrow: s.tomorrow,
      DateFilter.week: s.thisWeek,
    };
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
        children: [
          for (final d in DateFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: ChoiceChip(
                label: Text(labels[d]!),
                selected: date == d,
                onSelected: (_) => onDate(d),
              ),
            ),
          const VerticalDivider(width: Gap.lg, indent: 6, endIndent: 6),
          for (final st in const [null, 'COMPLETED', 'CANCELLED'])
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: ChoiceChip(
                label: Text(st == null
                    ? '${s.filterStatus}: ${s.all}'
                    : s.bookingStatus(st)),
                selected: status == st,
                onSelected: (_) => onStatus(st),
              ),
            ),
        ],
      ),
    );
  }
}
