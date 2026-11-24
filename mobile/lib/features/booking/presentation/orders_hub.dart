import 'package:flutter/material.dart';

import 'package:kunde_ui/booking_strings.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import '../../home/presentation/home_strings.dart';

import '../../food/food_services.dart';
import '../../food/presentation/orders_tab.dart';
import '../booking_services.dart';
import 'bookings_list.dart';

/// Orders tab with two segments: food/grocery orders and service bookings. Each segment reloads its history from
/// the server whenever it is shown, so both survive an app restart.
class OrdersHubTab extends StatefulWidget {
  const OrdersHubTab({required this.food, required this.booking, super.key});

  final FoodServices food;
  final BookingServices booking;

  @override
  State<OrdersHubTab> createState() => _OrdersHubTabState();
}

class _OrdersHubTabState extends State<OrdersHubTab> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(KundeLocalizations.of(context).quickOrders,
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0,
                    label: Text(bkL10n(context).bkSegmentOrders),
                    icon: const Icon(Icons.receipt_long_outlined)),
                ButtonSegment(
                    value: 1,
                    label: Text(bkL10n(context).bkSegmentBookings),
                    icon: const Icon(Icons.event_available_outlined)),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
          Expanded(
            child: _segment == 0
                ? FoodOrdersTab(
                    key: const ValueKey('orders'),
                    services: widget.food,
                    showHeading: false)
                : BookingsList(
                    key: const ValueKey('bookings'), services: widget.booking),
          ),
        ]),
      );
}
