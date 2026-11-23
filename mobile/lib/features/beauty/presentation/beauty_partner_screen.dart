import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../identity/auth_repository.dart';
import '../beauty_ops_strings.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_ops_api.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// KUNDE Partner for a beauty salon: today's bookings and revenue (real numbers from the server) and the salon menu.
class BeautyPartnerScreen extends StatelessWidget {
  const BeautyPartnerScreen({
    required this.auth,
    required this.partnerId,
    required this.onOpenBookings,
    super.key,
  });

  final AuthRepository auth;
  final String partnerId;

  /// Opens the existing bookings inbox and availability of the partner.
  final VoidCallback onOpenBookings;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final api = BeautyOpsApi(auth);
    return Scaffold(
      appBar: AppBar(title: Text(s.boPartnerTitle)),
      body: BeautyAsync<BeautyOverview>(
        load: () => api.overview(partnerId),
        builder: (context, overview) {
          if (overview.salons.isEmpty) {
            return BeautyEmptyView(
                icon: Icons.storefront_outlined, title: s.boNoSalons);
          }
          final salon = overview.salons.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const BeautyPhoto(
                      imageUrl: null, icon: Icons.spa_outlined, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(salon.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        Text(s.boSalonType,
                            style: const TextStyle(color: BeautyColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: s.boBookingsToday,
                      value: '${overview.bookingsToday}',
                      delta: overview.bookingsDeltaPercent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Stat(
                      label: s.boRevenue,
                      value: s.bMoney(overview.revenueTodayMinor),
                      delta: overview.revenueDeltaPercent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MenuRow(
                icon: Icons.design_services_outlined,
                label: s.boManageServices,
                soon: true,
              ),
              _MenuRow(
                icon: Icons.event_note_outlined,
                label: s.boMasterSchedule,
                onTap: onOpenBookings,
              ),
              _MenuRow(
                icon: Icons.people_alt_outlined,
                label: s.boBookingsClients,
                badge: overview.pendingRequests,
                onTap: onOpenBookings,
              ),
              _MenuRow(
                icon: Icons.local_offer_outlined,
                label: s.boPromos,
                soon: true,
              ),
              _MenuRow(
                icon: Icons.star_outline,
                label: s.boReviews,
                soon: true,
              ),
              _MenuRow(
                icon: Icons.badge_outlined,
                label: s.boStaff,
                onTap: () => Navigator.of(context).push(beautyRoute(
                  _StaffScreen(api: api, partnerId: partnerId),
                )),
              ),
              _MenuRow(
                icon: Icons.bar_chart_outlined,
                label: s.boAnalytics,
                soon: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.delta});

  final String label;
  final String value;
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BeautyColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BeautyColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: BeautyColors.muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          if (delta != null)
            Text(s.boDelta(delta!),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: delta! >= 0
                        ? BeautyColors.success
                        : BeautyColors.error)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.badge = 0,
    this.soon = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return ListTile(
      enabled: !soon,
      leading:
          Icon(icon, color: soon ? BeautyColors.muted : BeautyColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: soon
          ? Text(s.boSoon, style: const TextStyle(color: BeautyColors.muted))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: BeautyColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$badge',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: soon ? null : onTap,
    );
  }
}

class _StaffScreen extends StatelessWidget {
  const _StaffScreen({required this.api, required this.partnerId});

  final BeautyOpsApi api;
  final String partnerId;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.boStaff)),
      body: BeautyAsync<List<BeautyMasterRow>>(
        load: () => api.masters(partnerId),
        builder: (context, masters) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.boStaffHint,
                style: const TextStyle(color: BeautyColors.muted)),
            const SizedBox(height: 8),
            for (final master in masters)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: BeautyColors.lavender,
                  child: Icon(Icons.person, color: BeautyColors.primary),
                ),
                title: Text(master.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  if (master.specialty.isNotEmpty) master.specialty,
                  master.online ? s.boOnline : s.boOffline,
                ].join(' · ')),
                trailing: master.linked
                    ? Text(s.boLinked,
                        style: const TextStyle(color: BeautyColors.success))
                    : SelectableText(master.inviteCode ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: BeautyColors.primary)),
              ),
          ],
        ),
      ),
    );
  }
}
