import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// `4.8 (12)`: only ever built from a rating the server computed; callers skip it while there is no review.
String ratingLabel(double rating, int count) =>
    '${rating.toStringAsFixed(1)} ($count)';

/// Five stars; tappable when [onChanged] is set (rating 1–5), read-only otherwise.
class HomeServiceStars extends StatelessWidget {
  const HomeServiceStars({
    required this.value,
    this.onChanged,
    this.size = 22,
    this.keyPrefix = 'star',
    super.key,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFB020);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            key: ValueKey('$keyPrefix-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null ? null : () => onChanged!(i),
            child: Padding(
              padding: EdgeInsets.all(onChanged == null ? 0 : 4),
              child: Icon(
                i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color:
                    i <= value ? gold : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

/// Published reviews of an offer or a master (`path` is the reviews endpoint) with the computed rating on top; pages on demand.
class HomeServiceReviewsScreen extends StatefulWidget {
  const HomeServiceReviewsScreen({
    required this.auth,
    required this.path,
    this.pageSize = 20,
    super.key,
  });

  final AuthRepository auth;
  final String path;
  final int pageSize;

  @override
  State<HomeServiceReviewsScreen> createState() =>
      _HomeServiceReviewsScreenState();
}

class _HomeServiceReviewsScreenState extends State<HomeServiceReviewsScreen> {
  final _items = <Map<String, dynamic>>[];
  Map<String, dynamic>? _summary;
  int _total = 0;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.auth.authorizedJson(
        'GET',
        '${widget.path}?limit=${widget.pageSize}&offset=${_items.length}',
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _summary = page['summary'] as Map<String, dynamic>?;
        _total = (page['total'] as num).toInt();
        _items.addAll((page['items'] as List).cast<Map<String, dynamic>>());
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final rating = (_summary?['rating'] as num?)?.toDouble();
    final count = (_summary?['count'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('Отзывы', 'Пікірлер', 'Reviews'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _body(s, theme, rating, count),
        ),
      ),
    );
  }

  Widget _body(RideStrings s, ThemeData theme, double? rating, int count) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.error),
            TextButton(onPressed: _load, child: Text(s.retry)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (rating != null)
          Row(
            children: [
              Text(
                rating.toStringAsFixed(1),
                key: const ValueKey('summary-rating'),
                style: theme.textTheme.displaySmall,
              ),
              const SizedBox(width: 12),
              HomeServiceStars(value: rating.round(), size: 24),
              const SizedBox(width: 8),
              Text(s.t('$count отзывов', '$count пікір', '$count reviews')),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                s.t('Пока нет отзывов', 'Әзірге пікір жоқ', 'No reviews yet'),
                key: const ValueKey('no-reviews'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final r in _items) _ReviewTile(review: r),
        if (_failed)
          TextButton(onPressed: _load, child: Text(s.retry))
        else if (_items.length < _total)
          Center(
            child: TextButton(
              key: const ValueKey('more-reviews'),
              onPressed: _loading ? null : _load,
              child: Text(s.t('Показать ещё', 'Тағы көрсету', 'Show more')),
            ),
          ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comment = review['comment'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HomeServiceStars(value: (review['rating'] as num).toInt()),
                const Spacer(),
                Text(
                  '${review['authorName']}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment),
            ],
          ],
        ),
      ),
    );
  }
}

/// The customer's review of a completed order: «Leave a review» until one exists, then the review itself.
/// Only shown for a COMPLETED Home Services order; the server refuses anyone else.
class HomeServiceReviewCard extends StatefulWidget {
  const HomeServiceReviewCard({
    required this.auth,
    required this.bookingId,
    super.key,
  });

  final AuthRepository auth;
  final String bookingId;

  @override
  State<HomeServiceReviewCard> createState() => _HomeServiceReviewCardState();
}

class _HomeServiceReviewCardState extends State<HomeServiceReviewCard> {
  Map<String, dynamic>? _review;
  bool _loading = true;
  bool _failed = false;

  String get _path => 'home-services/bookings/${widget.bookingId}/review';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final review = await widget.auth.authorizedJson('GET', _path);
      if (mounted) setState(() => _review = review as Map<String, dynamic>);
    } on IdentityApiError catch (e) {
      if (mounted) setState(() => _failed = e.status != 404);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _leave() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(auth: widget.auth, path: _path),
    );
    if (submitted == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final review = _review;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _failed
            ? Row(
                children: [
                  Expanded(child: Text(s.error)),
                  TextButton(onPressed: _load, child: Text(s.retry)),
                ],
              )
            : review == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t(
                          'Как прошла работа мастера?',
                          'Шебердің жұмысы қалай өтті?',
                          'How was the master’s work?',
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const ValueKey('leave-review'),
                        onPressed: _leave,
                        icon: const Icon(Icons.star_rounded),
                        label: Text(
                          s.t('Оставить отзыв', 'Пікір қалдыру',
                              'Leave a review'),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t('Ваш отзыв', 'Сіздің пікіріңіз', 'Your review'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      HomeServiceStars(
                        value: (review['rating'] as num).toInt(),
                        keyPrefix: 'mine',
                      ),
                      if ((review['comment'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${review['comment']}'),
                        ),
                      if (review['status'] == 'HIDDEN')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            s.t(
                              'Отзыв скрыт модератором',
                              'Пікірді модератор жасырды',
                              'Hidden by a moderator',
                            ),
                            key: const ValueKey('review-hidden'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.auth, required this.path});

  final AuthRepository auth;
  final String path;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();
  int _rating = 0;
  int _quality = 0;
  int _punctuality = 0;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.auth.authorizedJson(
        'POST',
        widget.path,
        body: {
          'rating': _rating,
          if (_quality > 0) 'qualityRating': _quality,
          if (_punctuality > 0) 'punctualityRating': _punctuality,
          if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
        },
        expected: const {200, 201},
      );
      if (mounted) Navigator.of(context).pop(true);
    } on IdentityApiError catch (e) {
      // Already reviewed (another device): the card reloads and shows that review.
      if (e.status == 409 && mounted) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  Widget _row(String label, int value, ValueChanged<int> set, String key) =>
      Row(
        children: [
          Expanded(child: Text(label)),
          HomeServiceStars(
            value: value,
            onChanged: (v) => setState(() => set(v)),
            keyPrefix: key,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('Оцените работу', 'Жұмысты бағалаңыз', 'Rate the work'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _row(
              s.t('Общая оценка', 'Жалпы баға', 'Overall'),
              _rating,
              (v) => _rating = v,
              'rating',
            ),
            _row(
              s.t('Качество работы', 'Жұмыс сапасы', 'Quality'),
              _quality,
              (v) => _quality = v,
              'quality',
            ),
            _row(
              s.t('Пунктуальность', 'Дәлдік', 'Punctuality'),
              _punctuality,
              (v) => _punctuality = v,
              'punctuality',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('review-comment'),
              controller: _comment,
              maxLength: 1000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: s.t(
                  'Комментарий (необязательно)',
                  'Пікір (міндетті емес)',
                  'Comment (optional)',
                ),
              ),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  s.error,
                  key: const ValueKey('review-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('submit-review'),
                onPressed: _rating > 0 && !_busy ? _submit : null,
                child: Text(s.t('Отправить', 'Жіберу', 'Submit')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
