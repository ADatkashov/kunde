import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

const _root = 'executor/home-services';

/// The master's own rating, completed-order count and review history. Everything is computed by the server from published
/// reviews and the master's own orders; with no review there is no rating (never shown as zero).
class HomeServicesRatingScreen extends StatefulWidget {
  const HomeServicesRatingScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<HomeServicesRatingScreen> createState() =>
      _HomeServicesRatingScreenState();
}

class _HomeServicesRatingScreenState extends State<HomeServicesRatingScreen> {
  late Future<List<Map<String, dynamic>>> _data = _load();

  /// `[stats, reviews page]`.
  Future<List<Map<String, dynamic>>> _load() async {
    final stats = await widget.auth.authorizedJson('GET', '$_root/rating');
    final page =
        await widget.auth.authorizedJson('GET', '$_root/reviews?limit=50');
    return [
      (stats as Map).cast<String, dynamic>(),
      (page as Map).cast<String, dynamic>(),
    ];
  }

  void _reload() => setState(() {
        _data = _load();
      });

  String _avg(Object? value) =>
      value == null ? '—' : (value as num).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Мой рейтинг', 'Менің рейтингім', 'My rating')),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _data,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.error),
                TextButton(onPressed: _reload, child: Text(s.retry)),
              ]),
            );
          }
          final stats = state.data![0];
          final rating = (stats['rating'] as Map).cast<String, dynamic>();
          final items =
              ((state.data![1]['items'] as List?) ?? const []).cast<Map>();
          final count = (rating['count'] as num).toInt();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                rating['rating'] == null
                    ? s.t('Пока нет отзывов', 'Әзірге пікір жоқ',
                        'No reviews yet')
                    : '★ ${_avg(rating['rating'])}',
                key: const ValueKey('my-rating'),
                style: theme.textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              Text(s.t(
                  'Отзывов: $count', 'Пікірлер: $count', 'Reviews: $count')),
              Text(
                s.t(
                  'Качество: ${_avg(rating['qualityRating'])} · Пунктуальность: ${_avg(rating['punctualityRating'])}',
                  'Сапасы: ${_avg(rating['qualityRating'])} · Дәлдік: ${_avg(rating['punctualityRating'])}',
                  'Quality: ${_avg(rating['qualityRating'])} · Punctuality: ${_avg(rating['punctualityRating'])}',
                ),
                key: const ValueKey('my-details'),
              ),
              const SizedBox(height: 8),
              Text(
                s.t(
                  'Выполнено заказов: ${stats['completedOrders']}',
                  'Орындалған тапсырыстар: ${stats['completedOrders']}',
                  'Completed orders: ${stats['completedOrders']}',
                ),
                key: const ValueKey('completed-orders'),
                style: theme.textTheme.titleMedium,
              ),
              const Divider(height: 32),
              for (final r in items)
                Card(
                  key: ValueKey('my-review-${r['id']}'),
                  child: ListTile(
                    title: Text('★ ${r['rating']}'),
                    subtitle: (r['comment'] as String?)?.isNotEmpty ?? false
                        ? Text('${r['comment']}')
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
