import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';
import 'promotions_page.dart';

/// Ordering conditions of a restaurant for Owner/Manager: pickup on/off and preparation time, plus the promotions page.
/// The server validates and audits every change; the sheet shows the values the server returned.
class RestaurantSettingsSheet extends StatefulWidget {
  const RestaurantSettingsSheet({
    required this.store,
    required this.restaurant,
    super.key,
  });
  final OpsStore store;
  final Restaurant restaurant;
  @override
  State<RestaurantSettingsSheet> createState() =>
      _RestaurantSettingsSheetState();
}

class _RestaurantSettingsSheetState extends State<RestaurantSettingsSheet> {
  late bool _pickup = widget.restaurant.pickupEnabled;
  late int _prep = widget.restaurant.prepMinutes;
  bool _busy = false;

  Future<void> _save({bool? pickup, int? prep}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = S.of(context);
    try {
      final updated = await widget.store.ops.updateRestaurantSettings(
          widget.restaurant.id,
          pickupEnabled: pickup,
          prepMinutes: prep);
      if (mounted) {
        setState(() {
          _pickup = updated.pickupEnabled;
          _prep = updated.prepMinutes;
        });
      }
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(
          key: const Key('pickup-switch'),
          title: Text(s.pickupSetting),
          value: _pickup,
          onChanged: _busy ? null : (v) => _save(pickup: v),
        ),
        ListTile(
          title: Text(s.prepTime(_prep)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: const Key('prep-minus'),
              tooltip: '−5',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed:
                  _busy || _prep <= 5 ? null : () => _save(prep: _prep - 5),
            ),
            IconButton(
              key: const Key('prep-plus'),
              tooltip: '+5',
              icon: const Icon(Icons.add_circle_outline),
              onPressed:
                  _busy || _prep >= 240 ? null : () => _save(prep: _prep + 5),
            ),
          ]),
        ),
        ListTile(
          key: const Key('open-promotions'),
          leading: const Icon(Icons.local_offer_outlined),
          title: Text(s.promotionsTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute<void>(
                builder: (_) => PromotionsPage(
                    store: widget.store, restaurant: widget.restaurant)));
          },
        ),
      ]),
    );
  }
}
