import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../data/leisure_api.dart';
import 'package:kunde_models/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_strings.dart';
import 'leisure_ticket_screen.dart';
import 'leisure_widgets.dart';

/// Payment step. Only what the backend really supports is offered: the DEV test card (a labelled ledger entry, no card data, no charge)
/// and pay on site. Bank cards and wallets of the design reference stay out until an approved payment provider exists.
class LeisurePaymentScreen extends StatefulWidget {
  const LeisurePaymentScreen(
      {required this.services,
      required this.event,
      required this.session,
      required this.hold,
      required this.ageConfirmed,
      super.key});

  final LeisureServices services;
  final EventDetail event;
  final SessionInfo session;
  final Hold hold;
  final bool ageConfirmed;

  @override
  State<LeisurePaymentScreen> createState() => _LeisurePaymentScreenState();
}

class _LeisurePaymentScreenState extends State<LeisurePaymentScreen> {
  String _method = 'TEST_CARD';
  bool _busy = false;
  String? _error;
  // One key for this purchase: a retry after a lost connection can never create a second order.
  final String _key = LeisureApi.newKey();

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await widget.services.api.place(
        holdId: widget.hold.id,
        paymentMethod: _method,
        ageConfirmed: widget.ageConfirmed,
        idempotencyKey: _key,
      );
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
            builder: (_) => LeisureTicketScreen(
                services: widget.services,
                orderId: order.id,
                initial: order,
                justBooked: true)),
        (route) => route.settings.name == '/leisure' || route.isFirst,
      );
    } on LeisureException catch (ex) {
      if (mounted) setState(() => _error = lzL10n(context).lzError(ex.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final total = formatTenge(widget.hold.totalMinor);
    Widget option(String value, IconData icon, String title, String note) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _method = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: _method == value
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: _method == value ? 2 : 1),
                ),
                child: Row(children: [
                  Icon(
                      _method == value
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color:
                          _method == value ? theme.colorScheme.primary : null),
                  const SizedBox(width: 12),
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(note, style: theme.textTheme.bodySmall),
                      ])),
                ]),
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.lzPaymentTitle), centerTitle: true),
      bottomNavigationBar: PrimaryBar(
        label: _method == 'TEST_CARD' ? s.lzPay(total) : s.lzReserve(total),
        busy: _busy,
        onPressed: _pay,
        top: _error == null ? null : LeisureErrorBanner(_error!),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Semantics(
          inMutuallyExclusiveGroup: true,
          child: Column(children: [
            option('TEST_CARD', Icons.credit_card_rounded, s.lzTestCard,
                s.lzTestCardNote),
            option('PAY_ON_SITE', Icons.storefront_rounded, s.lzPayOnSite,
                s.lzPayOnSiteNote),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: .5),
              borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded,
                size: 20, color: KundePalette.violet),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(s.lzNoRealPayments, style: theme.textTheme.bodySmall)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.verified_user_outlined,
              size: 18, color: KundePalette.violet),
          const SizedBox(width: 8),
          Expanded(child: Text(s.lzSafeNote, style: theme.textTheme.bodySmall)),
        ]),
      ]),
    );
  }
}
