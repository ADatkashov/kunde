import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/partner_api.dart';

/// «Дом и быт»: the partner's own service offers and their moderation state. Roles and ownership are the server's
/// decision (OWNER/MANAGER write; OPERATOR reads); this screen only offers the transitions the state machine allows.
class HomeServicesOffersScreen extends StatefulWidget {
  const HomeServicesOffersScreen(
      {required this.api,
      required this.partnerId,
      required this.canManage,
      super.key});

  final PartnerApi api;
  final String partnerId;
  final bool canManage;

  /// Partner-side transitions: a draft or rejected offer is submitted; a pending or published one is withdrawn.
  static String? actionFor(String status) => switch (status) {
        'DRAFT' || 'REJECTED' => 'SUBMIT',
        'PENDING' || 'PUBLISHED' => 'WITHDRAW',
        _ => null,
      };

  @override
  State<HomeServicesOffersScreen> createState() =>
      _HomeServicesOffersScreenState();
}

class _HomeServicesOffersScreenState extends State<HomeServicesOffersScreen> {
  String get _root =>
      'partner/partners/${Uri.encodeComponent(widget.partnerId)}/home-services/offers';
  late Future<List<Map<String, dynamic>>> _offers = widget.api.getList(_root);

  Future<void> _reload() async {
    setState(() {
      _offers = widget.api.getList(_root);
    });
    try {
      await _offers;
    } catch (_) {
      // The FutureBuilder displays the failure.
    }
  }

  Future<void> _transition(Map<String, dynamic> offer, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    try {
      await widget.api.postMap('$_root/${offer['id']}/transition',
          {'action': action, 'expectedVersion': offer['version']});
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(s, error))));
    }
    if (mounted) await _reload();
  }

  static String _status(Locale l, String status) {
    String t(String ru, String kk, String en) => switch (l.languageCode) {
          'kk' => kk,
          'en' => en,
          _ => ru,
        };
    return switch (status) {
      'DRAFT' => t('Черновик', 'Жоба', 'Draft'),
      'PENDING' => t('На модерации', 'Модерацияда', 'Pending review'),
      'PUBLISHED' => t('Опубликовано', 'Жарияланған', 'Published'),
      'REJECTED' => t('Отклонено', 'Қабылданбаған', 'Rejected'),
      'SUSPENDED' => t('Приостановлено', 'Тоқтатылған', 'Suspended'),
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    String t(String ru, String kk, String en) => switch (locale.languageCode) {
          'kk' => kk,
          'en' => en,
          _ => ru,
        };
    return Scaffold(
      appBar: AppBar(
          title: Text(t('Дом и быт: мои услуги', 'Үй және тұрмыс: қызметтерім',
              'Home services: my offers'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _offers,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(errorText(s, state.error!)),
                TextButton(
                    onPressed: _reload,
                    child: Text(t('Повторить', 'Қайталау', 'Retry'))),
              ]),
            );
          }
          final offers = state.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                if (offers.isEmpty)
                  Text(t('Предложений пока нет', 'Ұсыныстар әлі жоқ',
                      'No offers yet')),
                for (final offer in offers)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${offer['serviceName']}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('${offer['definitionCode']} · '
                              '${offer['pricingModel']} · '
                              '${_status(locale, '${offer['status']}')}'),
                          if ('${offer['status']}' == 'REJECTED' &&
                              offer['statusReason'] != null)
                            Text('${offer['statusReason']}'),
                          if (widget.canManage &&
                              HomeServicesOffersScreen.actionFor(
                                      '${offer['status']}') !=
                                  null)
                            Builder(builder: (context) {
                              final action = HomeServicesOffersScreen.actionFor(
                                  '${offer['status']}')!;
                              return TextButton(
                                key: ValueKey(
                                    '${action.toLowerCase()}-${offer['id']}'),
                                onPressed: () => _transition(offer, action),
                                child: Text(action == 'SUBMIT'
                                    ? t(
                                        'Отправить на модерацию',
                                        'Модерацияға жіберу',
                                        'Submit for review')
                                    : t('Снять с публикации', 'Жариялаудан алу',
                                        'Withdraw')),
                              );
                            }),
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
