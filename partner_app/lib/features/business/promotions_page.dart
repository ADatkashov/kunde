import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';

/// Promotions of the partner's own restaurant. The server applies the discount and enforces the partner limits
/// (at most 50 %, 5 000 ₸ and 90 days); an administrator can disable a promotion and a partner cannot re-enable it.
class PromotionsPage extends StatefulWidget {
  const PromotionsPage({
    required this.store,
    required this.restaurant,
    super.key,
  });
  final OpsStore store;
  final Restaurant restaurant;
  @override
  State<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage> {
  List<FoodPromotion>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.store.ops.promotions();
      if (mounted) {
        setState(() {
          _items = rows;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(FoodPromotion p) async {
    final s = S.of(context);
    try {
      await widget.store.ops
          .setPromotionStatus(p.id, p.status == 'ACTIVE' ? 'PAUSED' : 'ACTIVE');
      await _load();
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewPromotionSheet(
          store: widget.store, restaurantId: widget.restaurant.id),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(
          title: Text('${s.promotionsTitle} · ${widget.restaurant.name}')),
      floatingActionButton: items == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-promotion'),
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text(s.promotionNew),
            ),
      body: items == null
          ? (_error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : const SkeletonList(count: 3))
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? LayoutBuilder(
                      builder: (context, c) => ListView(children: [
                        SizedBox(
                          height: c.maxHeight,
                          child: MessageView(
                              icon: Icons.local_offer_outlined,
                              title: s.promotionsEmpty,
                              body: s.promotionLimits),
                        ),
                      ]),
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 96),
                      children: [
                        for (final p in items)
                          Card(
                            child: ListTile(
                              title: Text(p.title),
                              subtitle: Text([
                                p.kind == 'PERCENT'
                                    ? '${p.value}%'
                                    : formatMoney(p.value),
                                if (p.code != null) p.code!,
                                p.status,
                                '× ${p.redeemed}',
                              ].join(' · ')),
                              trailing: p.status == 'DISABLED'
                                  ? null
                                  : TextButton(
                                      key: Key('promotion-toggle-${p.id}'),
                                      onPressed: () => _toggle(p),
                                      child: Text(p.status == 'ACTIVE'
                                          ? s.promotionPause
                                          : s.promotionResume)),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}

class _NewPromotionSheet extends StatefulWidget {
  const _NewPromotionSheet({required this.store, required this.restaurantId});
  final OpsStore store;
  final String restaurantId;
  @override
  State<_NewPromotionSheet> createState() => _NewPromotionSheetState();
}

class _NewPromotionSheetState extends State<_NewPromotionSheet> {
  final _title = TextEditingController();
  final _code = TextEditingController();
  final _value = TextEditingController(text: '10');
  final _days = TextEditingController(text: '14');
  String _kind = 'PERCENT';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _value.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    final value = int.tryParse(_value.text.trim());
    final days = int.tryParse(_days.text.trim());
    if (_title.text.trim().isEmpty ||
        value == null ||
        value < 1 ||
        days == null ||
        days < 1 ||
        days > 90) {
      showToast(context, s.promotionLimits, error: true);
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.store.ops.createPromotion(
        restaurantId: widget.restaurantId,
        title: _title.text.trim(),
        kind: _kind,
        // Percent is sent as is; an amount is typed in tenge and sent in tiyn.
        value: _kind == 'PERCENT' ? value : value * 100,
        endsAt: DateTime.now().add(Duration(days: days)),
        code: _code.text.trim().toUpperCase(),
      );
      nav.pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, errorText(s, e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Gap.lg, 0, Gap.lg, Gap.lg + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.promotionNew, style: context.text.titleLarge),
              const SizedBox(height: Gap.md),
              TextField(
                  key: const Key('promo-title'),
                  controller: _title,
                  maxLength: 120,
                  decoration:
                      InputDecoration(labelText: s.promotionTitleLabel)),
              TextField(
                  key: const Key('promo-code'),
                  controller: _code,
                  maxLength: 32,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: s.promotionCodeLabel)),
              const SizedBox(height: Gap.sm),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'PERCENT', label: Text(s.promotionPercent)),
                  ButtonSegment(value: 'FIXED', label: Text(s.promotionFixed)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              TextField(
                  key: const Key('promo-value'),
                  controller: _value,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: s.promotionValueLabel)),
              TextField(
                  key: const Key('promo-days'),
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.promotionDaysLabel)),
              const SizedBox(height: Gap.sm),
              Text(s.promotionLimits, style: context.text.bodySmall),
              const SizedBox(height: Gap.md),
              FilledButton(
                key: const Key('promo-submit'),
                onPressed: _busy ? null : _submit,
                child: Text(s.promotionCreate),
              ),
            ]),
      ),
    );
  }
}
