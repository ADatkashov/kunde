import 'package:flutter/material.dart';

import '../data/auto_api.dart';
import 'auto_strings.dart';

/// Loading / error-with-retry / empty states shared by the Auto screens.
class AutoStateView extends StatelessWidget {
  const AutoStateView.loading({super.key})
      : error = null,
        onRetry = null,
        emptyTitle = null,
        emptyBody = null;

  const AutoStateView.error(
      {required AutoFailure this.error, required this.onRetry, super.key})
      : emptyTitle = null,
        emptyBody = null;

  const AutoStateView.empty(
      {required String this.emptyTitle, this.emptyBody, super.key})
      : error = null,
        onRetry = null;

  final AutoFailure? error;
  final VoidCallback? onRetry;
  final String? emptyTitle;
  final String? emptyBody;

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    if (error == null && emptyTitle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error != null ? s.auError(error!) : emptyTitle!,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (emptyBody != null) ...[
            const SizedBox(height: 8),
            Text(emptyBody!,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
          if (error != null && onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(s.auRetry)),
          ],
        ]),
      ),
    );
  }
}

/// Inline error banner for failed actions; announced to screen readers.
class AutoErrorBanner extends StatelessWidget {
  const AutoErrorBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

/// Today in Almaty (UTC+5, no DST), independent of the phone's zone.
DateTime almatyToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime(now.year, now.month, now.day);
}
