import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../data/partner_api.dart';

/// «Дом и быт»: reviews of the partner's own venues, the organisation's and each master's rating (computed by the server from
/// published reviews; no review means no rating), a rating filter, and a complaint about a review (the platform decides).
class HomeServicesReviewsScreen extends StatefulWidget {
  const HomeServicesReviewsScreen({
    required this.api,
    required this.partnerId,
    this.canComplain = true,
    super.key,
  });

  final PartnerApi api;
  final String partnerId;
  final bool canComplain;

  @override
  State<HomeServicesReviewsScreen> createState() =>
      _HomeServicesReviewsScreenState();
}

class _HomeServicesReviewsScreenState extends State<HomeServicesReviewsScreen> {
  String get _root =>
      'partner/partners/${Uri.encodeComponent(widget.partnerId)}/home-services/reviews';
  int? _rating;
  String? _masterId;
  late Future<List<Map<String, dynamic>>> _data = _load();

  /// `[summary, page]`.
  Future<List<Map<String, dynamic>>> _load() async {
    final query = [
      'limit=50',
      if (_rating != null) 'rating=$_rating',
      if (_masterId != null) 'masterId=$_masterId',
    ].join('&');
    final summary = await widget.api.getMap('$_root/summary');
    final page = await widget.api.getMap('$_root?$query');
    return [summary, page];
  }

  Future<void> _reload() async {
    setState(() {
      _data = _load();
    });
    try {
      await _data;
    } catch (_) {
      // The FutureBuilder displays the failure.
    }
  }

  Future<void> _complain(Map<String, dynamic> review) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ComplaintDialog(),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final sent =
        _t(context, 'Жалоба отправлена', 'Шағым жіберілді', 'Complaint sent');
    try {
      await widget.api
          .postMap('$_root/${review['id']}/complaint', {'reason': reason});
      messenger.showSnackBar(SnackBar(content: Text(sent)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(s, error))));
    }
  }

  static String _t(BuildContext context, String ru, String kk, String en) =>
      switch (Localizations.localeOf(context).languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String t(String ru, String kk, String en) => _t(context, ru, kk, en);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Дом и быт: отзывы', 'Үй және тұрмыс: пікірлер',
            'Home services: reviews')),
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
                Text(errorText(s, state.error!)),
                TextButton(onPressed: _reload, child: Text(s.retry)),
              ]),
            );
          }
          final summary = state.data![0];
          final page = state.data![1];
          final org = (summary['organization'] as Map).cast<String, dynamic>();
          final masters =
              ((summary['masters'] as List?) ?? const []).cast<Map>();
          final items = ((page['items'] as List?) ?? const []).cast<Map>();
          final rating = (org['rating'] as num?)?.toDouble();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  rating == null
                      ? t('Пока нет отзывов', 'Әзірге пікір жоқ',
                          'No reviews yet')
                      : '★ ${rating.toStringAsFixed(1)} · ${org['count']} ${t('отзывов', 'пікір', 'reviews')}',
                  key: const ValueKey('org-rating'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                for (final m in masters)
                  ListTile(
                    key: ValueKey('master-${m['masterId']}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m['masterName']}'),
                    trailing: Text(m['rating'] == null
                        ? '—'
                        : '★ ${(m['rating'] as num).toStringAsFixed(1)} (${m['count']})'),
                    selected: _masterId == m['masterId'],
                    onTap: () {
                      _masterId = _masterId == m['masterId']
                          ? null
                          : '${m['masterId']}';
                      _reload();
                    },
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                    key: const ValueKey('rating-all'),
                    label: Text(t('Все', 'Барлығы', 'All')),
                    selected: _rating == null,
                    onSelected: (_) {
                      _rating = null;
                      _reload();
                    },
                  ),
                  for (var i = 5; i >= 1; i--)
                    ChoiceChip(
                      key: ValueKey('rating-$i'),
                      label: Text('★ $i'),
                      selected: _rating == i,
                      onSelected: (_) {
                        _rating = i;
                        _reload();
                      },
                    ),
                ]),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  Text(t('Отзывов нет', 'Пікір жоқ', 'No reviews')),
                for (final r in items)
                  Card(
                    key: ValueKey('review-${r['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('★ ${r['rating']} · ${r['masterName'] ?? ''}',
                              style: Theme.of(context).textTheme.titleMedium),
                          if ((r['comment'] as String?)?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${r['comment']}'),
                            ),
                          if (widget.canComplain)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: ValueKey('complain-${r['id']}'),
                                onPressed: () =>
                                    _complain(r.cast<String, dynamic>()),
                                child: Text(
                                    t('Пожаловаться', 'Шағымдану', 'Report')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComplaintDialog extends StatefulWidget {
  const _ComplaintDialog();

  @override
  State<_ComplaintDialog> createState() => _ComplaintDialogState();
}

class _ComplaintDialogState extends State<_ComplaintDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String t(String ru, String kk, String en) =>
        _HomeServicesReviewsScreenState._t(context, ru, kk, en);
    return AlertDialog(
      title: Text(t('Жалоба на отзыв', 'Пікірге шағым', 'Report a review')),
      content: TextField(
        key: const ValueKey('complaint-reason'),
        controller: _controller,
        maxLength: 300,
        decoration: InputDecoration(
          labelText: t('Причина (от 3 символов)', 'Себебі (кемінде 3 таңба)',
              'Reason (3+ characters)'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          key: const ValueKey('send-complaint'),
          onPressed: _controller.text.trim().length >= 3
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(t('Отправить', 'Жіберу', 'Send')),
        ),
      ],
    );
  }
}
