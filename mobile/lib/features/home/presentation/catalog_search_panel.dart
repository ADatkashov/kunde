import 'package:flutter/material.dart';

import '../../../core/localization/kunde_formats.dart';
import '../../../core/localization/kunde_localizations.dart';
import '../data/catalog_category.dart';
import '../data/catalog_offering.dart';
import '../data/kunde_api.dart';

/// Search over published categories. Shown only when the server reports the
/// marketplace as enabled; results always come from the API, never local demo data.
class CatalogSearchPanel extends StatefulWidget {
  const CatalogSearchPanel({required this.api, super.key});

  final KundeApi api;

  @override
  State<CatalogSearchPanel> createState() => _CatalogSearchPanelState();
}

enum _SearchState { idle, loading, results, empty, failed }

class _CatalogSearchPanelState extends State<CatalogSearchPanel> {
  final _controller = TextEditingController();
  _SearchState _state = _SearchState.idle;
  List<CatalogCategory> _categories = const [];
  List<CatalogOffering> _offerings = const [];
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    final generation = ++_generation;
    if (query.isEmpty) {
      setState(() {
        _state = _SearchState.idle;
        _categories = const [];
        _offerings = const [];
      });
      return;
    }
    setState(() => _state = _SearchState.loading);
    try {
      // Both lookups must succeed: a partial answer would look like "nothing else exists".
      final (categories, offerings) = await (
        widget.api.searchCategories(query),
        widget.api.searchOfferings(query),
      ).wait;
      if (!mounted || generation != _generation) return;
      setState(() {
        _categories = categories;
        _offerings = offerings;
        _state = categories.isEmpty && offerings.isEmpty
            ? _SearchState.empty
            : _SearchState.results;
      });
    } on ParallelWaitError catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _state = _SearchState.failed);
    } on KundeApiException {
      if (!mounted || generation != _generation) return;
      setState(() => _state = _SearchState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = KundeLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          maxLength: 200,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: strings.searchLabel,
            counterText: '',
            suffixIcon: IconButton(
              tooltip: strings.searchAction,
              icon: const Icon(Icons.search),
              onPressed: _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        switch (_state) {
          _SearchState.idle => const SizedBox.shrink(),
          _SearchState.loading =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          _SearchState.empty => Text(strings.searchEmpty),
          _SearchState.failed => Row(children: [
              Expanded(child: Text(strings.searchFailed)),
              TextButton(onPressed: _search, child: Text(strings.retry)),
            ]),
          _SearchState.results => Column(
              children: [
                for (final category in _categories)
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(category.localizedName(language)),
                  ),
                for (final offering in _offerings)
                  ListTile(
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(offering.localizedName(language)),
                    subtitle: _subtitle(context, offering, strings),
                  ),
              ],
            ),
        },
      ],
    );
  }

  /// Partner, the single final KZT price (D-04 DEV pilot, no added fees) and
  /// an explicit unavailable marker; null when the server sent none of them.
  Widget? _subtitle(BuildContext context, CatalogOffering offering,
      KundeLocalizations strings) {
    final price = offering.priceMinor;
    final lines = <String>[
      if (offering.partnerName != null) offering.partnerName!,
      if (price != null && offering.currency == 'KZT')
        KundeFormats.money(price, 'KZT', Localizations.localeOf(context)),
      if (!offering.available) strings.offeringUnavailable,
    ];
    return lines.isEmpty ? null : Text(lines.join(' · '));
  }
}
