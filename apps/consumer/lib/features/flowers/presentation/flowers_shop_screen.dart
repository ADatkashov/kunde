import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../home/data/kunde_api.dart';
import '../data/flowers_models.dart';
import 'flowers_widgets.dart';

/// One flowers shop with its products grouped by category. Adding to the cart arrives with ordering (ADR-026 step 3).
class FlowersShopScreen extends StatefulWidget {
  const FlowersShopScreen({required this.api, required this.shopId, super.key});

  final KundeApi api;
  final String shopId;

  @override
  State<FlowersShopScreen> createState() => _FlowersShopScreenState();
}

class _FlowersShopScreenState extends State<FlowersShopScreen> {
  late Future<FlowersShopDetail> _detail = _load();

  Future<FlowersShopDetail> _load() async =>
      FlowersShopDetail.fromJson(await widget.api
              .flowersJson('shops/${Uri.encodeComponent(widget.shopId)}')
          as Map<String, dynamic>);

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<FlowersShopDetail>(
            future: _detail,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.error),
                    TextButton(
                        onPressed: () => setState(() => _detail = _load()),
                        child: Text(s.retry)),
                  ]),
                );
              }
              final detail = state.data!;
              final theme = Theme.of(context);
              final byCategory = <String, List<FlowersProduct>>{};
              for (final p in detail.products) {
                byCategory.putIfAbsent(p.categoryCode, () => []).add(p);
              }
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Text(detail.shop.name,
                        style: theme.textTheme.headlineSmall),
                    if (detail.shop.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(detail.shop.description,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      FlowersPill(
                          '${detail.shop.etaMinMinutes}–${detail.shop.etaMaxMinutes} ${s.t('мин', 'мин', 'min')}',
                          icon: Icons.schedule_rounded),
                      FlowersPill(
                          detail.shop.deliveryFeeMinor == 0
                              ? s.t('Доставка бесплатно', 'Жеткізу тегін',
                                  'Free delivery')
                              : '${s.t('Доставка', 'Жеткізу', 'Delivery')} ${formatKzt(detail.shop.deliveryFeeMinor)}',
                          icon: Icons.local_shipping_outlined),
                      if (!detail.shop.open)
                        FlowersPill(s.t('Закрыто', 'Жабық', 'Closed')),
                    ]),
                    for (final entry in byCategory.entries) ...[
                      const SizedBox(height: 20),
                      Text(entry.key, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final p in entry.value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FlowersProductRow(product: p),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                        s.t(
                            'Оформление заказа появится в следующем обновлении.',
                            'Тапсырыс беру келесі жаңартуда қосылады.',
                            'Ordering is coming in the next update.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]);
            },
          ),
        ),
      ),
    );
  }
}
