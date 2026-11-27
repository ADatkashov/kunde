import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_api.dart';
import '../../data/partner_operations.dart';

/// «Дом и быт»: the partner's own service offers and their moderation state. Roles and ownership are the server's
/// decision (OWNER/MANAGER write; OPERATOR reads); this screen only offers the transitions the state machine allows.
class HomeServicesOffersScreen extends StatefulWidget {
  const HomeServicesOffersScreen(
      {required this.api,
      required this.partnerId,
      required this.canManage,
      this.ops,
      super.key});

  /// Needed to create offers (it lists the partner's venues and their services); without it the screen is read-and-moderate only.
  final PartnerOperations? ops;

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

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => HomeServiceOfferForm(
            ops: widget.ops!, api: widget.api, root: _root)));
    if (created == true && mounted) await _reload();
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
      floatingActionButton: widget.canManage && widget.ops != null
          ? FloatingActionButton.extended(
              key: const ValueKey('create-offer'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(t('Новое предложение', 'Жаңа ұсыныс', 'New offer')),
            )
          : null,
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

/// Pricing models the server accepts (`HomeServiceOffers.PRICING_MODELS`).
const homeServicePricingModels = [
  'FIXED',
  'FROM',
  'HOURLY',
  'PER_SQM',
  'PER_UNIT',
  'DIAGNOSTIC',
  'QUOTE',
];

/// Creates a DRAFT offer for a service of the partner's own `CLEANING` venue; moderation happens after submitting.
class HomeServiceOfferForm extends StatefulWidget {
  const HomeServiceOfferForm(
      {required this.ops, required this.api, required this.root, super.key});

  final PartnerOperations ops;
  final PartnerApi api;
  final String root;

  @override
  State<HomeServiceOfferForm> createState() => _HomeServiceOfferFormState();
}

class _HomeServiceOfferFormState extends State<HomeServiceOfferForm> {
  late Future<List<Venue>> _venues = _loadVenues();
  late Future<List<Map<String, dynamic>>> _definitions = _loadDefinitions();
  Future<List<Venue>> _loadVenues() => widget.ops
      .venues()
      .then((all) => all.where((v) => v.category == 'CLEANING').toList());

  /// The catalogue is paged by the server (at most 50 a page); every page is read so no kind of work is missing.
  Future<List<Map<String, dynamic>>> _loadDefinitions() async {
    final all = <Map<String, dynamic>>[];
    for (var offset = 0; offset <= 10000; offset += 50) {
      final page = await widget.api
          .getList('home-services/definitions?limit=50&offset=$offset');
      all.addAll(page);
      if (page.length < 50) break;
    }
    return all;
  }

  /// A failed load is shown as a failure with a retry, never as an empty list.
  Widget _failed(
          String Function(String, String, String) t, VoidCallback retry) =>
      Row(children: [
        Expanded(
            child: Text(t('Не удалось загрузить', 'Жүктеу мүмкін болмады',
                'Could not load'))),
        TextButton(
            onPressed: retry, child: Text(t('Повторить', 'Қайталау', 'Retry'))),
      ]);

  Venue? _venue;
  Future<List<VenueService>>? _services;
  VenueService? _service;
  String? _definition;
  String _model = 'FIXED';
  bool _homeVisit = true;
  final _warranty = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _warranty.dispose();
    super.dispose();
  }

  int? get _warrantyDays {
    final v = int.tryParse(_warranty.text.trim());
    return v != null && v >= 0 && v <= 1095 ? v : null;
  }

  bool get _valid =>
      _service != null && _definition != null && _warrantyDays != null;

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = S.of(context);
    try {
      await widget.api.postMap(widget.root, {
        'serviceId': _service!.id,
        'definitionCode': _definition,
        'pricingModel': _model,
        'homeVisit': _homeVisit,
        'warrantyDays': _warrantyDays,
      });
      if (!mounted) return;
      nav.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(s, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    String t(String ru, String kk, String en) => switch (locale.languageCode) {
          'kk' => kk,
          'en' => en,
          _ => ru,
        };
    String defName(Map<String, dynamic> d) => switch (locale.languageCode) {
          'kk' => '${d['nameKk']}',
          'en' => '${d['nameEn']}',
          _ => '${d['nameRu']}',
        };
    return Scaffold(
      appBar: AppBar(
          title: Text(t('Новое предложение', 'Жаңа ұсыныс', 'New offer'))),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        FutureBuilder<List<Venue>>(
          future: _venues,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (state.hasError) {
              return _failed(
                  t,
                  () => setState(() {
                        _venues = _loadVenues();
                      }));
            }
            final venues = state.data ?? const <Venue>[];
            if (venues.isEmpty) {
              return Text(t(
                  'Нет площадки «Дом и быт». Создайте её в разделе «Бизнес».',
                  '«Үй және тұрмыс» алаңы жоқ. «Бизнес» бөлімінде жасаңыз.',
                  'No Home services venue. Create one in Business.'));
            }
            return DropdownButtonFormField<Venue>(
              key: const ValueKey('venue'),
              initialValue: _venue,
              decoration:
                  InputDecoration(labelText: t('Площадка', 'Алаң', 'Venue')),
              items: [
                for (final v in venues)
                  DropdownMenuItem(value: v, child: Text(v.name)),
              ],
              onChanged: (v) => setState(() {
                _venue = v;
                _service = null;
                _services = v == null ? null : widget.ops.services(v.id);
              }),
            );
          },
        ),
        const SizedBox(height: Gap.md),
        if (_services != null)
          FutureBuilder<List<VenueService>>(
            future: _services,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (state.hasError) {
                return _failed(
                    t,
                    () => setState(() {
                          _services = widget.ops.services(_venue!.id);
                        }));
              }
              return DropdownButtonFormField<VenueService>(
                key: const ValueKey('service'),
                initialValue: _service,
                decoration: InputDecoration(
                    labelText: t('Услуга площадки', 'Алаң қызметі', 'Service')),
                items: [
                  for (final x in state.data ?? const <VenueService>[])
                    DropdownMenuItem(value: x, child: Text(x.name)),
                ],
                onChanged: (x) => setState(() => _service = x),
              );
            },
          ),
        const SizedBox(height: Gap.md),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _definitions,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (state.hasError) {
              return _failed(
                  t,
                  () => setState(() {
                        _definitions = _loadDefinitions();
                      }));
            }
            return DropdownButtonFormField<String>(
              key: const ValueKey('definition'),
              initialValue: _definition,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: t('Вид работ', 'Жұмыс түрі', 'Type of work')),
              items: [
                for (final d in state.data ?? const <Map<String, dynamic>>[])
                  DropdownMenuItem(
                      value: '${d['code']}', child: Text(defName(d))),
              ],
              onChanged: (v) => setState(() => _definition = v),
            );
          },
        ),
        const SizedBox(height: Gap.md),
        DropdownButtonFormField<String>(
          key: const ValueKey('model'),
          initialValue: _model,
          decoration: InputDecoration(
              labelText: t('Модель цены', 'Баға моделі', 'Pricing model')),
          items: [
            for (final m in homeServicePricingModels)
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _model = v ?? _model),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('Выезд на дом', 'Үйге шығу', 'Home visit')),
          value: _homeVisit,
          onChanged: (v) => setState(() => _homeVisit = v),
        ),
        TextField(
          key: const ValueKey('warranty'),
          controller: _warranty,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: t('Гарантия, дней (0–1095)', 'Кепілдік, күн (0–1095)',
                  'Warranty, days (0–1095)'),
              errorText: _warrantyDays == null
                  ? t('От 0 до 1095', '0-ден 1095-ке дейін', '0 to 1095')
                  : null),
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: Gap.lg),
        FilledButton(
          key: const ValueKey('save-offer'),
          onPressed: _valid && !_busy ? _save : null,
          child: Text(t('Сохранить черновик', 'Жобаны сақтау', 'Save draft')),
        ),
      ]),
    );
  }
}
