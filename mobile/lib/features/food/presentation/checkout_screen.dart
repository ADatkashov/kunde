import 'package:flutter/material.dart';

import '../data/food_api.dart';
import '../data/food_models.dart';
import '../food_services.dart';
import 'order_screen.dart';
import 'food_widgets.dart';

class _AddressPreset {
  const _AddressPreset(this.label, this.text, this.lat, this.lon);

  final String label;
  final String text;
  final double lat;
  final double lon;
}

/// Synthetic Almaty addresses for DEV testing; the customer can also type their own.
const _presets = [
  _AddressPreset('Дом (тест)', 'Алматы, пр. Абая 150, кв. 12 (тестовый адрес)',
      43.2395, 76.9025),
  _AddressPreset('Офис (тест)',
      'Алматы, ул. Достык 89, офис 5 (тестовый адрес)', 43.2330, 76.9560),
  _AddressPreset(
      'Друзья (тест)',
      'Алматы, мкр. Самал-2, д. 111, кв. 30 (тестовый адрес)',
      43.2320,
      76.9570),
];

/// Checkout: delivery address, mock payment method, comment and confirmation.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen(
      {required this.services, required this.quote, super.key});

  final FoodServices services;
  final FoodQuote quote;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late Future<List<Map<String, dynamic>>> _addresses;
  String? _addressId;
  String _payment = 'TEST_CARD';
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;
  String _key = FoodApi.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _addresses = _loadAddresses();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadAddresses() async {
    final list = await widget.services.auth.addresses();
    if (_addressId == null && list.isNotEmpty && mounted) {
      // Rebuild so the confirm button (outside the FutureBuilder) enables.
      setState(() {
        _addressId = list.first['id'] as String;
      });
    }
    return list;
  }

  Future<void> _addAddress({_AddressPreset? preset}) async {
    final result = preset ??
        await showModalBottomSheet<_AddressPreset>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _AddAddressSheet(),
        );
    if (result == null || !mounted) return;
    try {
      final created = await widget.services.auth.createAddress(
          label: result.label,
          formattedAddress: result.text,
          latitude: result.lat,
          longitude: result.lon);
      if (!mounted) return;
      setState(() {
        _addressId = created['id'] as String;
        _addresses = _loadAddresses();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось сохранить адрес. Попробуйте ещё раз.')));
    }
  }

  Future<void> _submit() async {
    final restaurant = widget.services.cart.restaurant;
    if (_addressId == null || restaurant == null) {
      setState(() => _error = 'Выберите адрес доставки.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final order = await widget.services.api.placeOrder(
        CheckoutRequest(
          restaurantId: restaurant.id,
          items: [for (final l in widget.services.cart.lines) l.toRequest()],
          addressId: _addressId!,
          paymentMethod: restaurant.vertical == 'FLOWERS_GIFTS'
              ? 'DEV_NO_PAYMENT'
              : _payment,
          comment: _comment.text,
          expectedTotalMinor: restaurant.vertical == 'FLOWERS_GIFTS'
              ? widget.quote.totalMinor
              : null,
        ),
        _key,
      );
      widget.services.cart.clear();
      // Back to the app root (home / orders), then show the new order on top.
      nav.popUntil((route) => route.isFirst);
      nav.push(MaterialPageRoute<void>(
          builder: (_) => OrderScreen(
              services: widget.services,
              orderId: order.id,
              initial: order,
              justPlaced: true)));
    } on FoodException catch (error) {
      if (!mounted) return;
      // A network failure may have reached the server: keep the key so a retry cannot duplicate the order.
      if (error.failure != FoodFailure.offline) {
        _key = FoodApi.newIdempotencyKey();
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = widget.quote;
    final flowers =
        widget.services.cart.restaurant?.vertical == 'FLOWERS_GIFTS';
    final language = Localizations.localeOf(context).languageCode;
    String tx(String ru, String kk, String en) => !flowers
        ? ru
        : switch (language) {
            'kk' => kk,
            'en' => en,
            _ => ru,
          };
    final noPayment = switch (language) {
      'kk' =>
        'Бұл сынақ тапсырыс. Төлем жүргізілмейді және жеткізу орындалмайды.',
      'en' => 'This is a test order. No payment or real delivery takes place.',
      _ =>
        'Это тестовый заказ. Оплата не производится, реальная доставка не выполняется.',
    };
    return Scaffold(
      appBar: AppBar(
          title:
              Text(tx('Оформление заказа', 'Тапсырысты рәсімдеу', 'Checkout'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                OrderProgressHeader(checkout: true, flowers: flowers),
                Text(
                    tx('Адрес доставки', 'Жеткізу мекенжайы',
                        'Delivery address'),
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _addresses,
                  builder: (context, state) {
                    if (state.connectionState != ConnectionState.done) {
                      return const Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator());
                    }
                    if (state.hasError) {
                      return Column(children: [
                        Text(tx(
                            'Не удалось загрузить адреса.',
                            'Мекенжайлар жүктелмеді.',
                            'Could not load addresses.')),
                        TextButton(
                            onPressed: () => setState(() {
                                  _addresses = _loadAddresses();
                                }),
                            child: Text(tx('Повторить', 'Қайталау', 'Retry'))),
                      ]);
                    }
                    final list = state.data!;
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (list.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(tx(
                                  'У вас пока нет адресов. Добавьте тестовый адрес в Алматы.',
                                  'Мекенжай жоқ. Алматыдағы сынақ мекенжайын қосыңыз.',
                                  'No addresses yet. Add a test address in Almaty.')),
                            ),
                          RadioGroup<String>(
                            groupValue: _addressId,
                            onChanged: _busy
                                ? (_) {}
                                : (v) => setState(() => _addressId = v),
                            child: Column(children: [
                              for (final a in list)
                                RadioListTile<String>(
                                  value: a['id'] as String,
                                  title: Text(a['label'] as String),
                                  subtitle:
                                      Text(a['formattedAddress'] as String),
                                ),
                            ]),
                          ),
                          if (list.isEmpty)
                            for (final p in _presets)
                              ListTile(
                                leading:
                                    const Icon(Icons.add_location_alt_outlined),
                                title: Text(p.label),
                                subtitle: Text(p.text),
                                onTap:
                                    _busy ? null : () => _addAddress(preset: p),
                              ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _addAddress(),
                            icon: const Icon(Icons.edit_location_alt_outlined),
                            label: Text(tx('Другой адрес', 'Басқа мекенжай',
                                'Another address')),
                          ),
                        ]);
                  },
                ),
                const SizedBox(height: 24),
                Text(tx('Оплата', 'Төлем', 'Payment'),
                    style: theme.textTheme.titleLarge),
                if (flowers)
                  Text(noPayment)
                else
                  RadioGroup<String>(
                    groupValue: _payment,
                    onChanged: _busy
                        ? (_) {}
                        : (v) => setState(() => _payment = v ?? _payment),
                    child: const Column(children: [
                      RadioListTile<String>(
                        value: 'TEST_CARD',
                        title: Text('Тестовая карта (DEV)'),
                        subtitle: Text(
                            'Имитация оплаты. Данные карты не вводятся и не списываются.'),
                      ),
                      RadioListTile<String>(
                        value: 'CASH_ON_DELIVERY',
                        title: Text('Наличными при получении'),
                        subtitle: Text('Оплата курьеру при доставке.'),
                      ),
                    ]),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _comment,
                  enabled: !_busy,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: tx('Комментарий к заказу',
                          'Тапсырысқа түсініктеме', 'Order note'),
                      hintText: tx(
                          'Например: позвоните за 5 минут',
                          'Мысалы: 5 минут бұрын қоңырау шалыңыз',
                          'For example: call 5 minutes ahead'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Text(
                    '${tx('Ваш заказ', 'Тапсырысыңыз', 'Your order')} · ${quote.restaurantName}',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final l in quote.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text(
                                  '${formatQuantity(l.unit, l.quantity)}${l.unit == 'KG' ? ' ' : ' × '}${l.name}'
                                  '${l.optionsText.isEmpty ? '' : ' (${l.optionsText})'}')),
                          Text(formatTenge(l.lineTotalMinor)),
                        ]),
                  ),
                const Divider(height: 24),
                _total(tx('Блюда', 'Тауарлар', 'Items'),
                    formatTenge(quote.subtotalMinor)),
                _total(
                    tx('Доставка', 'Жеткізу', 'Delivery'),
                    quote.deliveryFeeMinor == 0
                        ? tx('Бесплатно', 'Тегін', 'Free')
                        : formatTenge(quote.deliveryFeeMinor)),
                _total(tx('Итого', 'Барлығы', 'Total'),
                    formatTenge(quote.totalMinor),
                    bold: true),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error))),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _addressId == null ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(
                          '${tx('Подтвердить заказ', 'Тапсырысты растау', 'Confirm order')} · ${formatTenge(quote.totalMinor)}'),
                ),
                const SizedBox(height: 8),
                Text(
                    flowers
                        ? noPayment
                        : 'DEV-режим: оплата и доставка имитируются, реальные деньги не списываются.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
        ),
      ),
    );
  }

  Widget _total(String label, String value, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style)
      ]),
    );
  }
}

class _AddAddressSheet extends StatefulWidget {
  const _AddAddressSheet();

  @override
  State<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<_AddAddressSheet> {
  final _label = TextEditingController(text: 'Мой адрес');
  final _text = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Другой адрес в Алматы',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _label,
                  maxLength: 80,
                  decoration: const InputDecoration(
                      labelText: 'Название', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: _text,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Улица, дом, квартира',
                      border: OutlineInputBorder())),
              const SizedBox(height: 4),
              Text('DEV: координаты адреса ставятся в центр Алматы.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final label = _label.text.trim();
                  final text = _text.text.trim();
                  if (label.isEmpty || text.isEmpty) return;
                  Navigator.of(context).pop(_AddressPreset(
                      label,
                      text.startsWith('Алматы') ? text : 'Алматы, $text',
                      43.238949,
                      76.889709));
                },
                child: const Text('Сохранить адрес'),
              ),
            ]),
      );
}
