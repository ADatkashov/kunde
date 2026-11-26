import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

const _offersPath = 'admin/home-services/offers';
const _statuses = ['PENDING', 'PUBLISHED', 'SUSPENDED', 'REJECTED', 'DRAFT'];

/// Moderation queue of Home Services offers (`HOME_SERVICES_CATALOG`): approve, reject, suspend, restore.
class HomeServicesOffersScreen extends StatefulWidget {
  const HomeServicesOffersScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<HomeServicesOffersScreen> createState() =>
      HomeServicesOffersScreenState();
}

/// Visible for testing: [actionsFor] is the screen's transition table.
class HomeServicesOffersScreenState extends State<HomeServicesOffersScreen> {
  String _status = 'PENDING';
  late Future<List<Map<String, dynamic>>> _page = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await widget.auth.authorizedJson(
      'GET',
      '$_offersPath?status=$_status',
    ) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> _reload() async {
    setState(() {
      _page = _load();
    });
    try {
      await _page;
    } catch (_) {
      // The FutureBuilder displays the request failure.
    }
  }

  /// Actions the moderation state machine allows from a status (mirrors `HomeServiceOffers`).
  static List<String> actionsFor(String status) => switch (status) {
        'PENDING' => const ['APPROVE', 'REJECT'],
        'PUBLISHED' => const ['SUSPEND'],
        'SUSPENDED' => const ['RESTORE'],
        _ => const [],
      };

  Future<void> _decide(Map<String, dynamic> offer, String action) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(action: action),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = RideStrings(context);
    try {
      await widget.auth.authorizedJson(
        'POST',
        '$_offersPath/${offer['id']}/decision',
        body: {
          'action': action,
          'expectedVersion': offer['version'],
          'reason': reason,
        },
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.error)));
    }
    if (mounted) await _reload();
  }

  static String _label(RideStrings s, String status) => switch (status) {
        'PENDING' => s.t('На модерации', 'Модерацияда', 'Pending'),
        'PUBLISHED' => s.t('Опубликованы', 'Жарияланған', 'Published'),
        'SUSPENDED' => s.t('Приостановлены', 'Тоқтатылған', 'Suspended'),
        'REJECTED' => s.t('Отклонены', 'Қабылданбаған', 'Rejected'),
        _ => s.t('Черновики', 'Жобалар', 'Drafts'),
      };

  static String _action(RideStrings s, String action) => switch (action) {
        'APPROVE' => s.t('Одобрить', 'Бекіту', 'Approve'),
        'REJECT' => s.t('Отклонить', 'Қабылдамау', 'Reject'),
        'SUSPEND' => s.t('Приостановить', 'Тоқтату', 'Suspend'),
        _ => s.t('Восстановить', 'Қалпына келтіру', 'Restore'),
      };

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Дом и быт: предложения', 'Үй және тұрмыс: ұсыныстар',
            'Home services offers')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                for (final status in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('status-$status'),
                      label: Text(_label(s, status)),
                      selected: _status == status,
                      onSelected: (_) {
                        _status = status;
                        _reload();
                      },
                    ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.error),
                          TextButton(onPressed: _reload, child: Text(s.retry)),
                        ],
                      ),
                    );
                  }
                  final items = state.data ?? [];
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (items.isEmpty)
                          Text(s.t(
                              'Предложений нет', 'Ұсыныстар жоқ', 'No offers')),
                        for (final offer in items)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${offer['definitionCode']} · '
                                    '${offer['pricingModel']}',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${offer['venueName'] ?? ''}  ·  '
                                      '${s.t('Гарантия', 'Кепілдік', 'Warranty')}: '
                                      '${offer['warrantyDays'] ?? 0}'),
                                  Wrap(spacing: 8, children: [
                                    for (final action
                                        in actionsFor('${offer['status']}'))
                                      TextButton(
                                        key: ValueKey(
                                            '${action.toLowerCase()}-${offer['id']}'),
                                        onPressed: () => _decide(offer, action),
                                        child: Text(_action(s, action)),
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
          ]),
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.action});

  final String action;

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
      title: Text(HomeServicesOffersScreenState._action(s, widget.action)),
      content: TextField(
        key: const ValueKey('reason'),
        controller: _controller,
        maxLength: 500,
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
