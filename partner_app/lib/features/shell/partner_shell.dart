import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/ops_store.dart';
import '../../app/settings.dart';
import '../../core/strings.dart';
import '../bookings/bookings_screen.dart';
import '../business/business_screen.dart';
import '../business/fleet_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_screen.dart';

/// Bottom-navigation shell of a signed-in partner. Also raises the foreground
/// alert (sound, haptic, banner) when the store reports new work, and keeps
/// background polling off while the app is not visible.
class PartnerShell extends StatefulWidget {
  const PartnerShell(
      {required this.controller, required this.settings, super.key});
  final AppController controller;
  final SettingsController settings;
  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  late final OpsStore _store = widget.controller.store!;

  late final _fleetEnabled =
      _store.ops.fleetEnabled().onError((_, __) => false);

  static const _ordersTab = 1;
  static const _bookingsTab = 2;
  static const _businessTab = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.newWork.addListener(_onNewWork);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.newWork.removeListener(_onNewWork);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _store.setForeground(state == AppLifecycleState.resumed);

  void _onNewWork() {
    final work = _store.newWork.value;
    if (work == null || !work.any || !mounted) return;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    final s = S.of(context);
    final text = work.orders > 0
        ? s.alertNewOrders(work.orders)
        : s.alertNewBookings(work.bookings);
    final target = work.orders > 0 ? _ordersTab : _bookingsTab;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: s.open,
          onPressed: () => setState(() => _tab = target),
        ),
      ));
    _store.acknowledgeNewWork();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final newOrders =
            _store.activeOrders.data?.where((o) => o.isNew).length ?? 0;
        final requests = _store.bookingRequests.data?.length ?? 0;
        Widget badge(int n, Widget icon) =>
            n > 0 ? Badge.count(count: n, child: icon) : icon;
        return Scaffold(
          body: IndexedStack(index: _tab, children: [
            DashboardScreen(
              controller: widget.controller,
              store: _store,
              onNavigate: (t) => setState(() => _tab = switch (t) {
                    DashboardTarget.orders => _ordersTab,
                    DashboardTarget.bookings => _bookingsTab,
                    DashboardTarget.business => _businessTab,
                  }),
            ),
            OrdersScreen(store: _store),
            BookingsScreen(store: _store),
            BusinessScreen(
                store: _store,
                canManage: widget.controller.partner?.canManage ?? false,
                fleetAction: FutureBuilder<bool>(
                  future: _fleetEnabled,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) return const SizedBox.shrink();
                    return IconButton(
                      tooltip: s.fleet,
                      icon: const Icon(Icons.local_taxi_outlined),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                            builder: (_) => FleetScreen(
                                  ops: _store.ops,
                                  canManage:
                                      widget.controller.partner?.canManage ??
                                          false,
                                  isOwner: widget.controller.partner?.isOwner ??
                                      false,
                                )),
                      ),
                    );
                  },
                )),
            ProfileScreen(
                controller: widget.controller, settings: widget.settings),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: badge(
                    newOrders + requests, const Icon(Icons.home_outlined)),
                selectedIcon:
                    badge(newOrders + requests, const Icon(Icons.home_rounded)),
                label: s.navHome,
              ),
              NavigationDestination(
                icon: badge(newOrders, const Icon(Icons.receipt_long_outlined)),
                selectedIcon:
                    badge(newOrders, const Icon(Icons.receipt_long_rounded)),
                label: s.navOrders,
              ),
              NavigationDestination(
                icon: badge(requests, const Icon(Icons.event_outlined)),
                selectedIcon: badge(requests, const Icon(Icons.event_rounded)),
                label: s.navBookings,
              ),
              NavigationDestination(
                icon: const Icon(Icons.storefront_outlined),
                selectedIcon: const Icon(Icons.storefront_rounded),
                label: s.navBusiness,
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: const Icon(Icons.person_rounded),
                label: s.navProfile,
              ),
            ],
          ),
        );
      },
    );
  }
}
