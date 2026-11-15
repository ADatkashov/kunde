import 'package:flutter/material.dart';

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
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    label: Text('Заказы'),
                    icon: Icon(Icons.receipt_long_outlined)),
                ButtonSegment(
                    value: 1,
                    label: Text('Записи'),
                    icon: Icon(Icons.event_available_outlined)),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
          Expanded(
            child: _segment == 0
                ? FoodOrdersTab(
                    key: const ValueKey('orders'), services: widget.food)
                : BookingsList(
                    key: const ValueKey('bookings'), services: widget.booking),
          ),
        ]),
      );
}
