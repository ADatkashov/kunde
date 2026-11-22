import 'package:flutter/material.dart';

import 'delivery_api.dart';
import 'delivery_strings.dart';

class DeliveryTimeline extends StatefulWidget {
  const DeliveryTimeline({required this.api, required this.order, super.key});

  final DeliveryApi api;
  final DeliveryOrder order;

  @override
  State<DeliveryTimeline> createState() => _DeliveryTimelineState();
}

class _DeliveryTimelineState extends State<DeliveryTimeline> {
  Future<List<DeliveryEvent>>? _events;

  @override
  void didUpdateWidget(covariant DeliveryTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_events != null && oldWidget.order.status != widget.order.status) {
      _events = widget.api.timeline(widget.order.id);
    }
  }

  void _load() {
    final events = widget.api.timeline(widget.order.id);
    setState(() {
      _events = events;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    return ExpansionTile(
      title: Text(s.t('Ход доставки', 'Жеткізу барысы', 'Delivery progress')),
      onExpansionChanged: (open) {
        if (open && _events == null) _load();
      },
      children: [
        FutureBuilder(
          future: _events,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(
                title: Text(s.error),
                subtitle: TextButton(onPressed: _load, child: Text(s.retry)),
              );
            }
            final events = snapshot.data;
            if (events == null) return const LinearProgressIndicator();
            final localizations = MaterialLocalizations.of(context);
            return Column(
              children: [
                for (final event in events)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(s.status(event.status)),
                    subtitle: Text(
                      '${localizations.formatCompactDate(event.occurredAt.toLocal())} '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(event.occurredAt.toLocal()))}',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
