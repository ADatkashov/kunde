import 'package:flutter/material.dart';

/// Displays a server response without exposing raw JSON to business operators.
/// Lists are extracted only from known collection keys; unknown shapes get
/// a safe informational state rather than a misleading count.
class PartnerRecords extends StatelessWidget {
  const PartnerRecords({required this.payload, required this.title, this.onOrderAction, this.onBookingAction, super.key});

  final Map<String, dynamic> payload;
  final String title;
  final Future<void> Function(String orderId, String status)? onOrderAction;
  final Future<void> Function(String bookingId, String action)? onBookingAction;

  static List<Map<String, dynamic>> records(Map<String, dynamic> payload) {
    for (final key in ['items', 'orders', 'bookings', 'restaurants', 'data']) {
      final value = payload[key];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'PLACED': return 'Новый';
      case 'ACCEPTED': return 'Принят';
      case 'PREPARING': return 'Готовится';
      case 'ON_THE_WAY': return 'В доставке';
      case 'DELIVERED': return 'Завершён';
      case 'CANCELLED': return 'Отменён';
      case 'REQUESTED': return 'Ожидает ответа';
      case 'CONFIRMED': return 'Подтверждена';
      case 'REJECTED': return 'Отклонена';
      case 'COMPLETED': return 'Завершена';
      default: return status;
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'PLACED':
      case 'REQUESTED': return Icons.notifications_active_outlined;
      case 'ACCEPTED':
      case 'CONFIRMED': return Icons.check_circle_outline;
      case 'CANCELLED':
      case 'REJECTED': return Icons.cancel_outlined;
      case 'DELIVERED':
      case 'COMPLETED': return Icons.task_alt;
      default: return Icons.info_outline;
    }
  }

  static String _actionLabel(String status) {
    switch (status) {
      case 'ACCEPTED': return 'Принять';
      case 'PREPARING': return 'Готовится';
      case 'ON_THE_WAY': return 'Передать в доставку';
      case 'DELIVERED': return 'Завершить';
      case 'CANCELLED': return 'Отклонить';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = records(payload);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 52,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Нет записей', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Новые данные появятся здесь после обновления.',
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final id = item['id']?.toString() ?? '—';
        final status = item['status']?.toString() ?? '—';
        final name = item['name']?.toString() ??
            item['customerName']?.toString() ?? title;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(name,
                      style: Theme.of(context).textTheme.titleMedium)),
                  const SizedBox(width: 8),
                  Chip(avatar: Icon(_statusIcon(status), size: 18),
                    label: Text(_statusLabel(status))),
                ]),
                const SizedBox(height: 6),
                Text('№ $id', style: Theme.of(context).textTheme.bodySmall),
                if (onBookingAction != null && item['id'] != null &&
                    item['status'] == 'REQUESTED') ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    FilledButton(
                      onPressed: () => onBookingAction!(id, 'CONFIRM'),
                      child: const Text('Подтвердить'),
                    ),
                    OutlinedButton(
                      onPressed: () => onBookingAction!(id, 'REJECT'),
                      child: const Text('Отклонить'),
                    ),
                  ]),
                ],
                if (onOrderAction != null &&
                    item['allowedNext'] is List &&
                    item['id'] != null) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final next in (item['allowedNext'] as List).whereType<String>())
                      OutlinedButton(
                        onPressed: () async => onOrderAction!(id, next),
                        child: Text(_actionLabel(next)),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
