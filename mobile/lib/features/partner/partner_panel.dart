import 'package:flutter/material.dart';

import '../../core/localization/kunde_formats.dart';
import '../identity/auth_repository.dart';

/// Parses a KZT amount typed by a partner into tiyn (minor units, D-04: one
/// final price, no fees). Empty input means "no price yet" (null). Returns
/// [invalidPrice] for anything that is not a plain amount with at most two
/// decimals.
const invalidPrice = -1;

int? parseKztToTiyn(String input) {
  final text = input.replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d{1,8})(?:[.,](\d{1,2}))?$').firstMatch(text);
  if (match == null) return invalidPrice;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(fraction);
}

String _t(BuildContext context, String ru, String kk, String en) {
  final locale = Localizations.localeOf(context).languageCode;
  return locale == 'kk'
      ? kk
      : locale == 'en'
          ? en
          : ru;
}

String _statusLabel(BuildContext context, String status) => switch (status) {
      'APPROVED' => _t(context, 'Одобрен', 'Мақұлданды', 'Approved'),
      'INFO_REQUESTED' =>
        _t(context, 'Нужна информация', 'Ақпарат қажет', 'Information needed'),
      'LIMITED' => _t(context, 'Ограничен', 'Шектелген', 'Limited'),
      'SUSPENDED' => _t(context, 'Приостановлен', 'Тоқтатылды', 'Suspended'),
      'REJECTED' => _t(context, 'Отклонён', 'Қабылданбады', 'Rejected'),
      _ => _t(context, 'На проверке', 'Тексеруде', 'Under review'),
    };

String _roleLabel(BuildContext context, String role) => switch (role) {
      'OWNER' => _t(context, 'Владелец', 'Иесі', 'Owner'),
      'MANAGER' => _t(context, 'Менеджер', 'Менеджер', 'Manager'),
      _ => _t(context, 'Оператор', 'Оператор', 'Operator'),
    };

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Partner onboarding (ADR-018): apply, then see partners the user belongs to.
/// Shown only when the build has PARTNER_FEATURES_ENABLED; nothing is public
/// until KUNDE approves the partner, and no demo partners exist.
class PartnerPanel extends StatefulWidget {
  const PartnerPanel({required this.auth, super.key});
  final AuthRepository auth;

  @override
  State<PartnerPanel> createState() => _PartnerPanelState();
}

class _PartnerPanelState extends State<PartnerPanel> {
  late Future<List<Map<String, dynamic>>> _partners;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _partners = widget.auth.partners();
  }

  Future<void> _apply() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.auth.applyAsPartner(name);
      // The partner scope is derived at token issue, so refresh before listing.
      await widget.auth.refreshTokens();
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _toast(
          context,
          error is SessionExpired
              ? _t(context, 'Сессия истекла', 'Сессия аяқталды',
                  'Session expired')
              : error is IdentityApiError && error.status == 409
                  ? _t(context, 'Слишком много заявок', 'Өтініштер тым көп',
                      'Too many applications')
                  : _t(
                      context,
                      'Не удалось отправить заявку. Повторите позже.',
                      'Өтінішті жіберу мүмкін болмады. Кейінірек қайталаңыз.',
                      'Could not send the application. Try again later.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t(context, 'Партнёрам', 'Серіктестерге', 'For partners'),
              style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _partners,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_reload),
                  child: Text(_t(context, 'Ошибка загрузки — повторить',
                      'Жүктеу қатесі — қайталау', 'Loading failed — retry')),
                );
              }
              final partners = snapshot.data ?? const [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (partners.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_t(
                          context,
                          'Подайте заявку, чтобы управлять своими предложениями. '
                              'Они появятся в каталоге только после проверки KUNDE.',
                          'Өз ұсыныстарыңызды басқару үшін өтініш беріңіз. '
                              'Олар KUNDE тексергеннен кейін ғана каталогта көрінеді.',
                          'Apply to manage your offerings. They appear in the '
                              'catalog only after KUNDE reviews them.')),
                    ),
                  for (final partner in partners)
                    ListTile(
                      key: ValueKey(partner['id']),
                      contentPadding: EdgeInsets.zero,
                      title: Text(partner['displayName'] as String),
                      subtitle: Text(
                          '${_statusLabel(context, partner['verificationStatus'] as String)}'
                          ' · ${_roleLabel(context, partner['role'] as String)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PartnerOfferingsPage(
                              auth: widget.auth, partner: partner))),
                    ),
                  if (partners.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _busy ? null : _apply,
                        child: Text(_t(context, 'Стать партнёром',
                            'Серіктес болу', 'Become a partner')),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_t(context, 'Заявка партнёра', 'Серіктес өтініші',
            'Partner application')),
        content: TextField(
          controller: _controller,
          maxLength: 120,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: _t(context, 'Название заведения', 'Мекеме атауы',
                  'Business name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, _controller.text.trim()),
              child: Text(_t(context, 'Отправить', 'Жіберу', 'Send'))),
        ],
      );
}

/// Offerings of one partner: create, edit, price in KZT, availability, and
/// publish/unpublish. Publishing is offered only for APPROVED partners; the
/// server enforces it. Operators can read but not change anything.
class PartnerOfferingsPage extends StatefulWidget {
  const PartnerOfferingsPage(
      {required this.auth, required this.partner, super.key});
  final AuthRepository auth;
  final Map<String, dynamic> partner;

  @override
  State<PartnerOfferingsPage> createState() => _PartnerOfferingsPageState();
}

class _PartnerOfferingsPageState extends State<PartnerOfferingsPage> {
  late Future<List<Map<String, dynamic>>> _offerings;
  bool _busy = false;

  String get _partnerId => widget.partner['id'] as String;
  bool get _approved => widget.partner['verificationStatus'] == 'APPROVED';
  bool get _canWrite => widget.partner['role'] != 'OPERATOR';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _offerings = widget.auth.partnerOfferings(_partnerId);
  }

  String _name(Map<String, dynamic> offering) {
    final locale = Localizations.localeOf(context).languageCode;
    return (locale == 'kk'
            ? offering['nameKk']
            : locale == 'en'
                ? offering['nameEn'] ?? offering['nameRu']
                : offering['nameRu']) as String? ??
        '';
  }

  void _failure(Object error) {
    if (!mounted) return;
    final code = error is IdentityApiError ? error.status : 0;
    _toast(
        context,
        error is SessionExpired
            ? _t(
                context, 'Сессия истекла', 'Сессия аяқталды', 'Session expired')
            : code == 409
                ? _t(
                    context,
                    'Нельзя выполнить: проверьте одобрение, цену и обновите список',
                    'Орындау мүмкін емес: мақұлдауды, бағаны тексеріп, тізімді жаңартыңыз',
                    'Not possible: check approval, price and refresh the list')
                : _t(
                    context,
                    'Не удалось выполнить. Повторите позже.',
                    'Орындау мүмкін болмады. Кейінірек қайталаңыз.',
                    'Could not complete. Try again later.'));
    if (code == 409) setState(_reload);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(_reload);
    } catch (error) {
      _failure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? offering]) async {
    List<Map<String, dynamic>> categories = const [];
    if (offering == null) {
      try {
        categories = await widget.auth.partnerCategories();
      } catch (error) {
        _failure(error);
        return;
      }
    }
    if (!mounted) return;
    final draft = await showDialog<_OfferingDraft>(
      context: context,
      builder: (context) =>
          _OfferingDialog(offering: offering, categories: categories),
    );
    if (draft == null) return;
    await _run(() async {
      if (offering == null) {
        await widget.auth.createPartnerOffering(_partnerId,
            categoryId: draft.categoryId!,
            kind: draft.kind,
            nameRu: draft.nameRu,
            nameKk: draft.nameKk,
            nameEn: draft.nameEn,
            priceMinor: draft.priceMinor,
            available: draft.available);
      } else {
        await widget.auth.updatePartnerOffering(
            _partnerId, offering['id'] as String,
            nameRu: draft.nameRu,
            nameKk: draft.nameKk,
            nameEn: draft.nameEn,
            priceMinor: draft.priceMinor,
            available: draft.available,
            version: offering['version'] as int);
      }
    });
  }

  Future<void> _togglePublished(Map<String, dynamic> offering) =>
      _run(() => widget.auth.setPartnerOfferingPublished(
          _partnerId, offering['id'] as String,
          published: offering['status'] != 'PUBLISHED',
          version: offering['version'] as int));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.partner['displayName'] as String)),
        floatingActionButton: _canWrite
            ? FloatingActionButton.extended(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.add),
                label: Text(_t(context, 'Добавить', 'Қосу', 'Add')))
            : null,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_approved)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    '${_statusLabel(context, widget.partner['verificationStatus'] as String)}. '
                    '${_t(context, 'Публикация станет доступна после одобрения KUNDE.', 'Жариялау KUNDE мақұлдағаннан кейін қолжетімді болады.', 'Publishing becomes available after KUNDE approves the partner.')}'),
              ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _offerings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () => setState(_reload),
                    child: Text(_t(context, 'Ошибка загрузки — повторить',
                        'Жүктеу қатесі — қайталау', 'Loading failed — retry')),
                  );
                }
                final offerings = snapshot.data ?? const [];
                if (offerings.isEmpty) {
                  return Text(_t(context, 'Предложений пока нет',
                      'Әзірге ұсыныстар жоқ', 'No offerings yet'));
                }
                return Column(children: [
                  for (final offering in offerings)
                    _OfferingTile(
                      key: ValueKey(offering['id']),
                      title: _name(offering),
                      offering: offering,
                      approved: _approved,
                      canWrite: _canWrite && !_busy,
                      onEdit: () => _edit(offering),
                      onToggle: () => _togglePublished(offering),
                    ),
                ]);
              },
            ),
          ],
        ),
      );
}

class _OfferingTile extends StatelessWidget {
  const _OfferingTile({
    required this.title,
    required this.offering,
    required this.approved,
    required this.canWrite,
    required this.onEdit,
    required this.onToggle,
    super.key,
  });
  final String title;
  final Map<String, dynamic> offering;
  final bool approved;
  final bool canWrite;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final price = offering['priceMinor'] as int?;
    final published = offering['status'] == 'PUBLISHED';
    final lines = [
      price == null
          ? _t(context, 'Цена не указана', 'Бағасы көрсетілмеген',
              'No price set')
          : KundeFormats.money(price, 'KZT', Localizations.localeOf(context)),
      offering['availability'] == 'AVAILABLE'
          ? _t(context, 'В наличии', 'Қолжетімді', 'Available')
          : _t(context, 'Недоступно', 'Қолжетімсіз', 'Unavailable'),
      published
          ? _t(context, 'Опубликовано', 'Жарияланған', 'Published')
          : _t(context, 'Черновик', 'Қолжазба', 'Draft'),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(lines.join(' · ')),
      trailing: canWrite
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: _t(context, 'Изменить', 'Өзгерту', 'Edit'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined)),
              TextButton(
                // Withdrawing is always allowed; publishing needs approval.
                onPressed: published || approved ? onToggle : null,
                child: Text(published
                    ? _t(context, 'Снять', 'Алу', 'Withdraw')
                    : _t(context, 'Опубликовать', 'Жариялау', 'Publish')),
              ),
            ])
          : null,
    );
  }
}

class _OfferingDraft {
  const _OfferingDraft({
    required this.categoryId,
    required this.kind,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.priceMinor,
    required this.available,
  });
  final String? categoryId;
  final String kind;
  final String nameRu;
  final String nameKk;
  final String? nameEn;
  final int? priceMinor;
  final bool available;
}

class _OfferingDialog extends StatefulWidget {
  const _OfferingDialog({required this.offering, required this.categories});
  final Map<String, dynamic>? offering;
  final List<Map<String, dynamic>> categories;

  @override
  State<_OfferingDialog> createState() => _OfferingDialogState();
}

class _OfferingDialogState extends State<_OfferingDialog> {
  late final _ru =
      TextEditingController(text: widget.offering?['nameRu'] as String? ?? '');
  late final _kk =
      TextEditingController(text: widget.offering?['nameKk'] as String? ?? '');
  late final _en =
      TextEditingController(text: widget.offering?['nameEn'] as String? ?? '');
  late final _price = TextEditingController(text: _initialPrice());
  late bool _available = widget.offering?['availability'] == 'AVAILABLE';
  String? _categoryId;
  String _kind = 'PRODUCT';

  bool get _creating => widget.offering == null;

  @override
  void initState() {
    super.initState();
    if (_creating && widget.categories.isNotEmpty) {
      _categoryId = widget.categories.first['id'] as String;
    }
  }

  String _initialPrice() {
    final minor = widget.offering?['priceMinor'] as int?;
    if (minor == null) return '';
    final fraction = minor % 100;
    return fraction == 0
        ? '${minor ~/ 100}'
        : '${minor ~/ 100}.${fraction.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ru.dispose();
    _kk.dispose();
    _en.dispose();
    _price.dispose();
    super.dispose();
  }

  String _categoryName(Map<String, dynamic> category) {
    final locale = Localizations.localeOf(context).languageCode;
    return (locale == 'kk'
        ? category['nameKk']
        : locale == 'en'
            ? category['nameEn'] ?? category['nameRu']
            : category['nameRu']) as String;
  }

  bool get _valid =>
      _ru.text.trim().isNotEmpty &&
      _kk.text.trim().isNotEmpty &&
      parseKztToTiyn(_price.text) != invalidPrice &&
      (!_creating || _categoryId != null);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_creating
            ? _t(context, 'Новое предложение', 'Жаңа ұсыныс', 'New offering')
            : _t(context, 'Изменить предложение', 'Ұсынысты өзгерту',
                'Edit offering')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_creating) ...[
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: _t(context, 'Категория', 'Санат', 'Category')),
                items: [
                  for (final category in widget.categories)
                    DropdownMenuItem(
                        value: category['id'] as String,
                        child: Text(_categoryName(category))),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(
                    labelText: _t(context, 'Тип', 'Түрі', 'Type')),
                items: [
                  DropdownMenuItem(
                      value: 'PRODUCT',
                      child: Text(_t(context, 'Товар', 'Тауар', 'Product'))),
                  DropdownMenuItem(
                      value: 'SERVICE',
                      child: Text(_t(context, 'Услуга', 'Қызмет', 'Service'))),
                ],
                onChanged: (value) => setState(() => _kind = value ?? _kind),
              ),
            ],
            TextField(
              controller: _ru,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText:
                      _t(context, 'Название (RU)', 'Атауы (RU)', 'Name (RU)')),
            ),
            TextField(
              controller: _kk,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText:
                      _t(context, 'Название (KK)', 'Атауы (KK)', 'Name (KK)')),
            ),
            TextField(
              controller: _en,
              maxLength: 200,
              decoration: InputDecoration(
                  labelText: _t(context, 'Название (EN, по желанию)',
                      'Атауы (EN, қалауыңызша)', 'Name (EN, optional)')),
            ),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: _t(context, 'Итоговая цена, ₸',
                      'Түпкілікті баға, ₸', 'Final price, ₸'),
                  errorText: parseKztToTiyn(_price.text) == invalidPrice
                      ? _t(
                          context,
                          'Например 2500 или 2500,50',
                          'Мысалы 2500 немесе 2500,50',
                          'For example 2500 or 2500.50')
                      : null),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_t(context, 'В наличии', 'Қолжетімді', 'Available')),
              value: _available,
              onChanged: (value) => setState(() => _available = value),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: !_valid
                  ? null
                  : () {
                      final price = parseKztToTiyn(_price.text);
                      Navigator.pop(
                          context,
                          _OfferingDraft(
                              categoryId: _categoryId,
                              kind: _kind,
                              nameRu: _ru.text.trim(),
                              nameKk: _kk.text.trim(),
                              nameEn: _en.text.trim().isEmpty
                                  ? null
                                  : _en.text.trim(),
                              priceMinor: price,
                              available: _available));
                    },
              child: Text(_t(context, 'Сохранить', 'Сақтау', 'Save'))),
        ],
      );
}
