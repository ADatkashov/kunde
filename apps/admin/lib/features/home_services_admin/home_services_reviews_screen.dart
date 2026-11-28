import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

const _adminPath = 'admin/home-services';

/// Moderation of Home Services reviews and complaints about them (`HOME_SERVICES_OPERATIONS`). Reviews with an open complaint come
/// first. Hiding, republishing and resolving need a reason; every action is sent with the version the screen saw.
class HomeServicesReviewsScreen extends StatelessWidget {
  const HomeServicesReviewsScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('Дом и быт: отзывы', 'Үй және тұрмыс: пікірлер',
              'Home services reviews')),
          bottom: TabBar(tabs: [
            Tab(
                key: const ValueKey('tab-reviews'),
                text: s.t('Отзывы', 'Пікірлер', 'Reviews')),
            Tab(
                key: const ValueKey('tab-complaints'),
                text: s.t('Жалобы', 'Шағымдар', 'Complaints')),
          ]),
        ),
        body: TabBarView(children: [
          _ReviewsTab(auth: auth),
          _ComplaintsTab(auth: auth),
        ]),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title),
    );

class _ReviewsTab extends StatefulWidget {
  const _ReviewsTab({required this.auth});

  final AuthRepository auth;

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  String? _status;
  late Future<List<Map<String, dynamic>>> _page = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final query = _status == null ? '' : '&status=$_status';
    final data = await widget.auth
        .authorizedJson('GET', '$_adminPath/reviews?limit=50$query');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> _reload() async {
    setState(() {
      _page = _load();
    });
    try {
      await _page;
    } catch (_) {
      // The FutureBuilder shows the failure.
    }
  }

  Future<void> _moderate(Map<String, dynamic> review, bool hide) async {
    final s = RideStrings(context);
    final reason = await _askReason(
      context,
      hide
          ? s.t('Скрыть отзыв', 'Пікірді жасыру', 'Hide review')
          : s.t('Вернуть отзыв', 'Пікірді қайтару', 'Republish review'),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.authorizedJson(
        'POST',
        '$_adminPath/reviews/${review['id']}/moderation',
        body: {
          'action': hide ? 'HIDE' : 'PUBLISH',
          'expectedVersion': review['version'],
          'reason': reason,
        },
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.error)));
    }
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, children: [
              for (final (value, label) in [
                (null, s.t('Все', 'Барлығы', 'All')),
                ('PUBLISHED', s.t('Опубликованы', 'Жарияланған', 'Published')),
                ('HIDDEN', s.t('Скрыты', 'Жасырылған', 'Hidden')),
              ])
                ChoiceChip(
                  key: ValueKey('rs-${value ?? 'ALL'}'),
                  label: Text(label),
                  selected: _status == value,
                  onSelected: (_) {
                    _status = value;
                    _reload();
                  },
                ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _page,
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
                final items = state.data ?? const [];
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (items.isEmpty)
                        Text(s.t('Отзывов нет', 'Пікір жоқ', 'No reviews')),
                      for (final r in items) _reviewCard(s, r),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _reviewCard(RideStrings s, Map<String, dynamic> r) {
    final hidden = r['status'] == 'HIDDEN';
    final open = (r['openComplaints'] as num?)?.toInt() ?? 0;
    return Card(
      key: ValueKey('review-${r['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '★ ${r['rating']} · ${r['bookingNumber'] ?? ''} · ${r['serviceName'] ?? ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${r['venueName'] ?? ''} · ${r['masterName'] ?? ''}'),
            if ((r['comment'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${r['comment']}'),
              ),
            if (open > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.t('Открытых жалоб: $open', 'Ашық шағымдар: $open',
                      'Open complaints: $open'),
                  key: ValueKey('open-${r['id']}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('${hidden ? 'publish' : 'hide'}-${r['id']}'),
                onPressed: () => _moderate(r, !hidden),
                child: Text(hidden
                    ? s.t('Вернуть', 'Қайтару', 'Republish')
                    : s.t('Скрыть', 'Жасыру', 'Hide')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComplaintsTab extends StatefulWidget {
  const _ComplaintsTab({required this.auth});

  final AuthRepository auth;

  @override
  State<_ComplaintsTab> createState() => _ComplaintsTabState();
}

class _ComplaintsTabState extends State<_ComplaintsTab> {
  late Future<List<Map<String, dynamic>>> _page = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await widget.auth.authorizedJson(
        'GET', '$_adminPath/review-complaints?status=OPEN&limit=50');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> _reload() async {
    setState(() {
      _page = _load();
    });
    try {
      await _page;
    } catch (_) {
      // The FutureBuilder shows the failure.
    }
  }

  Future<void> _resolve(Map<String, dynamic> complaint, bool hide) async {
    final s = RideStrings(context);
    final reason = await _askReason(
      context,
      hide
          ? s.t('Жалоба обоснована: скрыть отзыв', 'Шағым орынды: жасыру',
              'Upheld: hide the review')
          : s.t('Отклонить жалобу', 'Шағымнан бас тарту',
              'Dismiss the complaint'),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.authorizedJson(
        'POST',
        '$_adminPath/review-complaints/${complaint['id']}/resolve',
        body: {'resolution': reason, 'hideReview': hide},
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.error)));
    }
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _page,
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
            final items = state.data ?? const [];
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (items.isEmpty)
                    Text(s.t('Открытых жалоб нет', 'Ашық шағымдар жоқ',
                        'No open complaints')),
                  for (final c in items)
                    Card(
                      key: ValueKey('complaint-${c['id']}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['reason']}',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                                '★ ${c['reviewRating']} · ${c['reviewComment'] ?? ''}'),
                            Wrap(spacing: 8, children: [
                              TextButton(
                                key: ValueKey('uphold-${c['id']}'),
                                onPressed: () => _resolve(c, true),
                                child: Text(s.t('Скрыть отзыв',
                                    'Пікірді жасыру', 'Hide review')),
                              ),
                              TextButton(
                                key: ValueKey('dismiss-${c['id']}'),
                                onPressed: () => _resolve(c, false),
                                child: Text(
                                    s.t('Отклонить', 'Бас тарту', 'Dismiss')),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('reason'),
        controller: _controller,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: s.t('Причина (от 3 символов)', 'Себебі (кемінде 3 таңба)',
              'Reason (3+ characters)'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.back),
        ),
        FilledButton(
          key: const ValueKey('confirm'),
          onPressed: _controller.text.trim().length >= 3
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(s.t('Подтвердить', 'Растау', 'Confirm')),
        ),
      ],
    );
  }
}
