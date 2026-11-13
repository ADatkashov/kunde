import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/catalog_category.dart';
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
  List<CatalogCategory> _results = const [];
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
        _results = const [];
      });
      return;
    }
    setState(() => _state = _SearchState.loading);
    try {
      final results = await widget.api.searchCategories(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _state = results.isEmpty ? _SearchState.empty : _SearchState.results;
      });
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
                for (final category in _results)
                  ListTile(title: Text(category.localizedName(language))),
              ],
            ),
        },
      ],
    );
  }
}
