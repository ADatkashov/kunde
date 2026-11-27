import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Opens an external map for an address; returns false when no map application can handle it.
typedef OpenMap = Future<bool> Function(String address);

Future<bool> openMapsFor(String address) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': address,
    'travelmode': 'driving',
  });
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Courier work for Groceries (and Food) orders handed over by stores: open tasks, accept (first courier wins),
/// collect at the store, route to the customer through an installed map app, deliver. Needs an approved courier profile
/// (registered in the Delivery mode). No distance or ETA is shown: stores have no coordinates, and none is invented.
class FoodWorkScreen extends StatefulWidget {
  const FoodWorkScreen(
      {required this.auth,
      this.openMap = openMapsFor,
      this.basePath = 'executor/food',
      this.title,
      super.key});

  final AuthRepository auth;
  final OpenMap openMap;

  /// API prefix of the task endpoints: `executor/food` (stores) or `executor/flowers` (flowers and gifts).
  /// Both return tasks of the same shape and share the courier profile of the Delivery mode.
  final String basePath;

  /// Screen title; defaults to «Заказы магазинов».
  final String? title;

  @override
  State<FoodWorkScreen> createState() => _FoodWorkScreenState();
}

class _FoodWorkScreenState extends State<FoodWorkScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _mine = [];
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<dynamic> _call(String method, String path,
          {Set<int> expected = const {200}}) =>
      widget.auth.authorizedJson(method, path, expected: expected);

  Future<void> _load({bool silent = false}) async {
    try {
      Map<String, dynamic>? profile;
      try {
        profile = await _call('GET', 'executor/deliveries/profile')
            as Map<String, dynamic>;
      } on IdentityApiError catch (e) {
        if (e.code != 'DELIVERY_COURIER_NOT_FOUND') rethrow;
      }
      var open = <Map<String, dynamic>>[];
      var mine = <Map<String, dynamic>>[];
      if (profile != null && profile['status'] == 'APPROVED') {
        mine = (await _call('GET', '${widget.basePath}/tasks/mine') as List)
            .cast<Map<String, dynamic>>();
        if (profile['online'] == true) {
          open = (await _call('GET', '${widget.basePath}/tasks/open') as List)
              .cast<Map<String, dynamic>>();
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _open = open;
        _mine = mine;
        _loaded = true;
        _error = null;
      });
    } on IdentityApiError catch (e) {
      if (mounted && !(silent && _loaded)) {
        setState(() => _error = e.code ?? 'ERROR');
      }
    } catch (_) {
      if (mounted && !(silent && _loaded)) setState(() => _error = 'OFFLINE');
    }
  }

  Future<void> _act(Future<dynamic> Function() action) async {
    if (_busy) return;
    final s = RideStrings(context);
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on IdentityApiError catch (e) {
      if (!mounted) return;
      final text = switch (e.code) {
        'TASK_UNAVAILABLE' => s.t('Заказ уже взял другой курьер',
            'Тапсырысты басқа курьер алды', 'Another courier took this order'),
        'COURIER_BUSY' => s.t(
            'Сначала завершите текущие заказы',
            'Алдымен ағымдағы тапсырыстарды аяқтаңыз',
            'Finish your current orders first'),
        'TASK_STATE_INVALID' => s.t('Этот шаг сейчас недоступен',
            'Бұл қадам қазір қолжетімсіз', 'This step is not available now'),
        _ => s.t('Не удалось выполнить действие', 'Әрекет орындалмады',
            'The action failed'),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.t('Нет связи. Повторите.',
                'Байланыс жоқ. Қайталаңыз.', 'No connection. Retry.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _route(String address) async {
    final s = RideStrings(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await widget.openMap(address)) return;
    // No map application: the address is copied so it can be pasted into any navigator.
    await Clipboard.setData(ClipboardData(text: address));
    messenger.showSnackBar(SnackBar(
        content: Text(s.t(
            'Карты недоступны — адрес скопирован',
            'Карта қолжетімсіз — мекенжай көшірілді',
            'No map app — address copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final profile = _profile;
    final approved = profile?['status'] == 'APPROVED';
    final online = profile?['online'] == true;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title ??
              s.t('Заказы магазинов', 'Дүкен тапсырыстары', 'Store orders'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(s.t(
                    'Не удалось загрузить заказы',
                    'Тапсырыстарды жүктеу мүмкін болмады',
                    'Could not load orders')),
                trailing: TextButton(
                    onPressed: _load,
                    child: Text(s.t('Повторить', 'Қайталау', 'Retry'))),
              ),
            ),
          if (!_loaded && _error == null)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator())),
          if (_loaded && !approved)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.t(
                    'Нужен одобренный профиль курьера: зарегистрируйтесь в режиме «Доставка» и дождитесь одобрения.',
                    'Мақұлданған курьер профилі қажет: «Жеткізу» режимінде тіркеліп, мақұлдауды күтіңіз.',
                    'An approved courier profile is required: register in Delivery mode and wait for approval.')),
              ),
            ),
          if (approved) ...[
            SwitchListTile(
              key: const Key('food-online'),
              value: online,
              title: Text(online
                  ? s.t('Онлайн', 'Онлайн', 'Online')
                  : s.t('Офлайн', 'Офлайн', 'Offline')),
              onChanged: _busy
                  ? null
                  : (v) => _act(() async {
                        await widget.auth.authorizedJson(
                            'PUT', 'executor/deliveries/availability',
                            body: {'online': v});
                      }),
            ),
            if (_mine.any(
                (t) => t['status'] == 'ASSIGNED' || t['status'] == 'PICKED_UP'))
              _section(s.t(
                  'Текущие заказы', 'Ағымдағы тапсырыстар', 'Current orders')),
            for (final t in _mine.where(
                (t) => t['status'] == 'ASSIGNED' || t['status'] == 'PICKED_UP'))
              _activeCard(t, s),
            if (online) ...[
              _section(s.t('Доступные заказы', 'Қолжетімді тапсырыстар',
                  'Available orders')),
              if (_open.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t(
                      'Пока нет заказов. Новые появятся здесь.',
                      'Әзірге тапсырыс жоқ. Жаңалары осында шығады.',
                      'No orders yet. New ones will appear here.')),
                ),
              for (final t in _open) _openCard(t, s),
            ] else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.t(
                    'Включите «Онлайн», чтобы видеть заказы.',
                    '«Онлайн» қосыңыз — тапсырыстар көрінеді.',
                    'Go online to see orders.')),
              ),
            if (_mine.any((t) =>
                t['status'] == 'DELIVERED' || t['status'] == 'CANCELLED')) ...[
              _section(s.t('История', 'Тарих', 'History')),
              for (final t in _mine.where((t) =>
                  t['status'] == 'DELIVERED' || t['status'] == 'CANCELLED'))
                ListTile(
                  leading: Icon(t['status'] == 'DELIVERED'
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined),
                  title: Text('№ ${t['shortRef']} · ${t['storeName']}'),
                  subtitle: Text(t['status'] == 'DELIVERED'
                      ? s.t('Доставлен', 'Жеткізілді', 'Delivered')
                      : s.t('Отменён', 'Бас тартылды', 'Cancelled')),
                ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
      );

  String _money(num minor) {
    final whole = (minor / 100).round().toString();
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(' ');
      b.write(whole[i]);
    }
    return '$b ₸';
  }

  Widget _openCard(Map<String, dynamic> t, RideStrings s) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('№ ${t['shortRef']} · ${t['storeName']}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (t['storeAddress'] != null) Text(t['storeAddress'] as String),
            const SizedBox(height: 4),
            Text(
                '${s.t('Позиций', 'Позиция', 'Items')}: ${t['itemCount']} · ${_money(t['totalMinor'] as num)}'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _act(() => _call(
                      'POST', '${widget.basePath}/tasks/${t['id']}/accept')),
              child: Text(s.t('Взять заказ', 'Тапсырысты алу', 'Accept order')),
            ),
          ]),
        ),
      );

  Widget _activeCard(Map<String, dynamic> t, RideStrings s) {
    final pickedUp = t['status'] == 'PICKED_UP';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('№ ${t['shortRef']} · ${t['storeName']}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _address(
              pickedUp
                  ? Icons.home_outlined
                  : Icons.store_mall_directory_outlined,
              pickedUp
                  ? s.t(
                      'Адрес доставки', 'Жеткізу мекенжайы', 'Delivery address')
                  : s.t('Забрать в магазине', 'Дүкеннен алу',
                      'Pick up at the store'),
              (pickedUp ? t['deliveryAddress'] : t['storeAddress']) as String?),
          if (pickedUp && t['comment'] != null)
            Text(
                '${s.t('Комментарий', 'Түсініктеме', 'Comment')}: ${t['comment']}'),
          if (t['collectOnDelivery'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${s.t('Получить наличными', 'Қолма-қол алу', 'Collect cash')}: ${_money(t['totalMinor'] as num)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _act(() => _call('POST',
                      '${widget.basePath}/tasks/${t['id']}/${pickedUp ? 'deliver' : 'pickup'}')),
              child: Text(pickedUp
                  ? s.t('Доставлено', 'Жеткізілді', 'Delivered')
                  : s.t('Забрал заказ', 'Тапсырысты алдым', 'Picked up')),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _address(IconData icon, String label, String? address) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(address ?? '—'),
          ]),
        ),
        if (address != null)
          IconButton.filledTonal(
            key: const Key('food-route'),
            tooltip: RideStrings(context)
                .t('Построить маршрут', 'Бағыт салу', 'Route'),
            onPressed: () => _route(address),
            icon: const Icon(Icons.directions_outlined),
          ),
      ]);
}
