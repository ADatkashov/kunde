import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/data/booking_api.dart';
import '../../booking/presentation/booking_strings.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_api.dart';

/// Loads once, shows a skeleton while waiting and an error with retry when the request fails.
class BeautyAsync<T> extends StatefulWidget {
  const BeautyAsync({required this.load, required this.builder, super.key});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<BeautyAsync<T>> createState() => _BeautyAsyncState<T>();
}

class _BeautyAsyncState<T> extends State<BeautyAsync<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const BeautySkeleton();
          }
          if (snapshot.hasError) {
            return BeautyErrorView(
              error: snapshot.error,
              onRetry: () => setState(() => _future = widget.load()),
            );
          }
          return widget.builder(context, snapshot.data as T);
        },
      );
}

class BeautySkeleton extends StatelessWidget {
  const BeautySkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              height: 88,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: BeautyColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      );
}

class BeautyErrorView extends StatelessWidget {
  const BeautyErrorView(
      {required this.error, required this.onRetry, super.key});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final message = error is BookingException
        ? s.bkError((error as BookingException).failure)
        : s.bLoadFailed;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: BeautyColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(s.retry)),
          ],
        ),
      ),
    );
  }
}

class BeautyEmptyView extends StatelessWidget {
  const BeautyEmptyView({
    required this.icon,
    required this.title,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: BeautyColors.primary),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              if (hint != null) ...[
                const SizedBox(height: 6),
                Text(hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: BeautyColors.muted)),
              ],
            ],
          ),
        ),
      );
}

/// Favorite salons of the signed-in customer, shared by every Beauty screen.
class BeautyFavorites extends ChangeNotifier {
  BeautyFavorites(this._api);

  final BeautyApi _api;
  Set<String> _ids = const {};

  Set<String> get ids => _ids;

  bool contains(String id) => _ids.contains(id);

  /// Silent when the customer is not signed in or offline: the heart simply stays empty.
  Future<void> load() async {
    try {
      _ids = await _api.favorites();
      notifyListeners();
    } on BookingException {
      // Not signed in or offline.
    }
  }

  /// Returns the failure when the change could not be saved, null on success.
  Future<BookingFailure?> toggle(String id) async {
    final saved = !_ids.contains(id);
    try {
      await _api.setFavorite(id, saved);
    } on BookingException catch (error) {
      return error.failure;
    }
    _ids = saved ? {..._ids, id} : ({..._ids}..remove(id));
    notifyListeners();
    return null;
  }
}

/// Runs a favorite toggle and tells the customer when they must sign in.
Future<void> toggleFavorite(
    BuildContext context, BeautyFavorites favorites, String id) async {
  final s = KundeLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final failure = await favorites.toggle(id);
  if (failure == null) return;
  messenger.showSnackBar(SnackBar(
    content: Text(failure == BookingFailure.sessionExpired
        ? s.bFavoriteNeedsLogin
        : s.bkError(failure)),
  ));
}
