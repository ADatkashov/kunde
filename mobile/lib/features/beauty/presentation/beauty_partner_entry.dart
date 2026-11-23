import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../identity/auth_repository.dart';
import '../beauty_ops_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_ops_api.dart';
import 'beauty_partner_screen.dart';

/// App-bar button of the partner hub, shown only when the organization owns a beauty salon and Beauty is enabled.
class BeautyPartnerEntry extends StatefulWidget {
  const BeautyPartnerEntry({
    required this.auth,
    required this.partnerId,
    super.key,
  });

  final AuthRepository auth;
  final String partnerId;

  @override
  State<BeautyPartnerEntry> createState() => _BeautyPartnerEntryState();
}

class _BeautyPartnerEntryState extends State<BeautyPartnerEntry> {
  bool _available = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final overview =
          await BeautyOpsApi(widget.auth).overview(widget.partnerId);
      if (mounted) setState(() => _available = overview.salons.isNotEmpty);
    } catch (_) {
      // Beauty disabled, not a member or offline: the entry stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final s = KundeLocalizations.of(context);
    final tabs = DefaultTabController.maybeOf(context);
    return IconButton(
      icon: const Icon(Icons.spa_outlined),
      tooltip: s.boSalonType,
      onPressed: () => Navigator.of(context).push<void>(beautyRoute(
        Builder(
          builder: (inner) => BeautyPartnerScreen(
            auth: widget.auth,
            partnerId: widget.partnerId,
            onOpenBookings: () {
              Navigator.of(inner).pop();
              tabs?.animateTo(1);
            },
          ),
        ),
      )),
    );
  }
}
