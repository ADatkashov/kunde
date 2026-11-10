import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/kunde_api.dart';
import '../data/platform_snapshot.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, super.key});

  final KundeApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<PlatformSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.api.loadPlatformSnapshot();
  }

  void _retry() {
    setState(() => _snapshot = widget.api.loadPlatformSnapshot());
  }

  @override
  Widget build(BuildContext context) {
    final strings = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                _BrandHeader(tagline: strings.tagline),
                const SizedBox(height: 40),
                Text(strings.foundationTitle,
                    style: theme.textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text(strings.connectionLabel,
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                FutureBuilder<PlatformSnapshot>(
                  future: _snapshot,
                  builder: (context, state) {
                    if (state.connectionState != ConnectionState.done) {
                      return const _StatusCard(
                        icon: Icons.sync_rounded,
                        message: ' ',
                        busy: true,
                      );
                    }
                    if (state.hasError || !state.hasData) {
                      return _OfflineCard(
                        title: strings.offline,
                        hint: strings.retryHint,
                        retryLabel: strings.retry,
                        onRetry: _retry,
                      );
                    }
                    return _ReadyState(snapshot: state.data!, strings: strings);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'KUNDE',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.tagline});

  final String tagline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('K',
              style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KUNDE',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(letterSpacing: 1.2)),
            Text(tagline, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.snapshot, required this.strings});

  final PlatformSnapshot snapshot;
  final KundeLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
            icon: Icons.check_circle_outline, message: strings.connected),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.marketplaceEnabled
                      ? strings.marketplaceReadyTitle
                      : strings.servicesUnavailableTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(snapshot.marketplaceEnabled
                    ? strings.marketplaceReadyBody
                    : strings.servicesUnavailableBody),
                const SizedBox(height: 16),
                _CapabilityLine(
                  icon: Icons.storefront_outlined,
                  label: strings.marketplaceLabel,
                  enabled: snapshot.marketplaceEnabled,
                ),
                _CapabilityLine(
                  icon: Icons.lock_outline,
                  label: snapshot.oidcIssuerConfigured
                      ? strings.signInEnabled
                      : strings.oidcIssuerLabel,
                  enabled: snapshot.oidcIssuerConfigured,
                ),
                _CapabilityLine(
                  icon: Icons.auto_awesome_outlined,
                  label: snapshot.aiEnabled
                      ? strings.aiEnabled
                      : strings.aiUnavailable,
                  enabled: snapshot.aiEnabled,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(
      {required this.icon, required this.message, this.busy = false});

  final IconData icon;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(message, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard(
      {required this.title,
      required this.hint,
      required this.retryLabel,
      required this.onRetry});

  final String title;
  final String hint;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(hint),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      );
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine(
      {required this.icon, required this.label, required this.enabled});

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Semantics(
          label:
              '$label: ${enabled ? KundeLocalizations.of(context).available : KundeLocalizations.of(context).notAvailable}',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(enabled ? Icons.check_circle : icon,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        style: Theme.of(context).textTheme.bodyMedium)),
                Text(enabled
                    ? KundeLocalizations.of(context).available
                    : KundeLocalizations.of(context).notAvailable),
              ],
            ),
          ),
        ),
      );
}
