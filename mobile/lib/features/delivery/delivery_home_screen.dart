import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../identity/address_panel.dart';
import 'delivery_api.dart';
import 'delivery_screen.dart';
import 'delivery_strings.dart';

class DeliveryHomeScreen extends StatelessWidget {
  const DeliveryHomeScreen({
    required this.api,
    required this.synthetic,
    super.key,
  });

  final DeliveryApi api;
  final bool synthetic;

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    final addresses = s.t('Мои адреса', 'Менің мекенжайларым', 'My addresses');
    final business =
        s.t('Доставка для бизнеса', 'Бизнеске жеткізу', 'Business delivery');
    final tariff = s.t('Тарифы', 'Тарифтер', 'Rates');
    void open(WidgetBuilder builder) => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: builder),
        );
    void newShipment() =>
        open((_) => DeliveryScreen(api: api, synthetic: synthetic));
    void history({required bool activeOnly}) => open(
          (_) => DeliveryHistoryScreen(
            api: api,
            syntheticRouting: synthetic,
            activeOnly: activeOnly,
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.history,
            icon: const Icon(Icons.history_rounded),
            onPressed: () => history(activeOnly: false),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: KundePalette.heroGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('От двери до двери', 'Есіктен есікке',
                                'Door to door'),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.t(
                              'Посылки и документы по Алматы',
                              'Алматы бойынша сәлемдемелер мен құжаттар',
                              'Parcels and documents across Almaty',
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Image.asset(
                      'assets/illustrations/delivery.png',
                      width: 72,
                      height: 72,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(s.t('Алматы', 'Алматы', 'Almaty')),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(s.sendParcel),
                    onTap: newShipment,
                  ),
                  ListTile(
                    leading: const Icon(Icons.delivery_dining_outlined),
                    title: Text(s.t('Курьер по городу', 'Қала ішіндегі курьер',
                        'Courier in the city')),
                    onTap: newShipment,
                  ),
                  ListTile(
                    leading: const Icon(Icons.business_center_outlined),
                    title: Text(business),
                    subtitle: const Text('KUNDE Partner'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: Text(business),
                        content: Text(s.t(
                          'Создавайте и управляйте отправлениями организации в приложении KUNDE Partner.',
                          'Ұйым жөнелтілімдерін KUNDE Partner қолданбасында жасап, басқарыңыз.',
                          'Create and manage your organization’s shipments in KUNDE Partner.',
                        )),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: Text(s.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: Text(addresses),
                    onTap: () => open(
                      (_) => Scaffold(
                        appBar: AppBar(title: Text(addresses)),
                        body: SafeArea(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [AddressPanel(auth: api.auth)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(s.activeOrders),
              onTap: () => history(activeOnly: true),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(tariff),
              subtitle: Text(s.t(
                'Рассчитайте стоимость для вашего маршрута',
                'Бағытыңыздың құнын есептеңіз',
                'Get a price for your route',
              )),
              onTap: newShipment,
            ),
          ],
        ),
      ),
    );
  }
}
