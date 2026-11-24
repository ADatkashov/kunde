import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/beauty_ops_strings.dart';
import 'package:kunde_ui/beauty_strings.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_api/beauty_ops_api.dart';
import 'package:kunde_ui/beauty_support.dart';
import 'package:kunde_ui/beauty_widgets.dart';

/// KUNDE Executor for a beauty master: online switch, today's appointments, start/finish/no-show, schedule and income.
class BeautyExecutorScreen extends StatefulWidget {
  const BeautyExecutorScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<BeautyExecutorScreen> createState() => _BeautyExecutorScreenState();
}

class _BeautyExecutorScreenState extends State<BeautyExecutorScreen> {
  late final BeautyOpsApi _api = BeautyOpsApi(widget.auth);
  late Future<BeautyToday?> _today = _api.today();
  int _tab = 0;
  bool _busy = false;
  String? _message;

  void _reload() => setState(() {
        _today = _api.today();
      });

  Future<void> _run(Future<void> Function() action) async {
    final s = KundeLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      _reload();
    } on IdentityApiError {
      _message = s.boActionFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.boExecutorTitle)),
      body: FutureBuilder<BeautyToday?>(
        future: _today,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const BeautySkeleton();
          }
          if (snapshot.hasError) {
            return BeautyErrorView(error: snapshot.error, onRetry: _reload);
          }
          final today = snapshot.data;
          if (today == null) return _LinkView(api: _api, onLinked: _reload);
          return Column(
            children: [
              Expanded(
                child: switch (_tab) {
                  1 => _ScheduleTab(today: today),
                  2 => _IncomeTab(api: _api),
                  3 => _ProfileTab(today: today),
                  _ => _TasksTab(
                      today: today,
                      busy: _busy,
                      message: _message,
                      onOnline: (value) => _run(() => _api.setOnline(value)),
                      onStep: (id, step) => _run(() => _api.step(id, step)),
                    ),
                },
              ),
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.checklist_outlined),
                      label: s.boTabTasks),
                  NavigationDestination(
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: s.boTabSchedule),
                  NavigationDestination(
                      icon: const Icon(Icons.payments_outlined),
                      label: s.boTabIncome),
                  NavigationDestination(
                      icon: const Icon(Icons.person_outline),
                      label: s.boTabProfile),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.today,
    required this.busy,
    required this.message,
    required this.onOnline,
    required this.onStep,
  });

  final BeautyToday today;
  final bool busy;
  final String? message;
  final ValueChanged<bool> onOnline;
  final void Function(String id, String step) onStep;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final main = today.appointments.isEmpty ? null : today.appointments.first;
    final next = today.appointments.skip(1).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color:
                today.online ? const Color(0xFFE6F6EE) : BeautyColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle,
                  color:
                      today.online ? BeautyColors.success : BeautyColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(today.online ? s.boOnline : s.boOffline,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: today.online,
                activeThumbColor: BeautyColors.success,
                onChanged: busy ? null : onOnline,
              ),
            ],
          ),
        ),
        if (!today.online)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.boOfflineNote,
                style:
                    const TextStyle(color: BeautyColors.muted, fontSize: 12.5)),
          ),
        const SizedBox(height: 18),
        Text(s.boToday, style: const TextStyle(color: BeautyColors.muted)),
        Text(s.boBookingsCount(today.todayCount),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (main == null)
          BeautyEmptyView(
              icon: Icons.event_available_outlined, title: s.boNoAppointments)
        else
          _MainCard(appointment: main, busy: busy, onStep: onStep),
        if (message != null) ...[
          const SizedBox(height: 10),
          Text(message!, style: const TextStyle(color: BeautyColors.error)),
        ],
        if (next.isNotEmpty) ...[
          BeautySectionHeader(s.boNextBookings),
          for (final a in next)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(s.bTime(a.start),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              title: Text(a.serviceName),
              subtitle: Text(s.bDay(a.start)),
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  const _MainCard(
      {required this.appointment, required this.busy, required this.onStep});

  final BeautyAppointment appointment;
  final bool busy;
  final void Function(String id, String step) onStep;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final a = appointment;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BeautyColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BeautyColors.line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.event, color: BeautyColors.primary),
              Text('${s.bTime(a.start)} – ${s.bTime(a.end)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              BeautyBookingStatus(
                  status: a.status, label: s.boStatus(a.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.serviceName,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (a.clientName.isNotEmpty)
            Row(children: [
              const Icon(Icons.person_outline,
                  size: 18, color: BeautyColors.muted),
              const SizedBox(width: 6),
              Text('${s.boClient}: ${a.clientName}'),
            ]),
          Row(children: [
            const Icon(Icons.place_outlined,
                size: 18, color: BeautyColors.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(a.venueName)),
          ]),
          const SizedBox(height: 14),
          if (a.canStart)
            BeautyPrimaryButton(
                label: s.boStartVisit,
                loading: busy,
                onPressed: () => onStep(a.id, 'start')),
          if (a.canComplete)
            BeautyPrimaryButton(
                label: s.boFinishVisit,
                loading: busy,
                onPressed: () => onStep(a.id, 'complete')),
          if (a.canMarkNoShow)
            TextButton(
              onPressed: busy ? null : () => onStep(a.id, 'no-show'),
              child: Text(s.boNoShow),
            ),
        ],
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.today});

  final BeautyToday today;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    if (today.appointments.isEmpty) {
      return BeautyEmptyView(
          icon: Icons.event_available_outlined, title: s.boNoAppointments);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final a in today.appointments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.serviceName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${s.bDayTime(a.start)} · ${a.bookingNumber}'),
            trailing: BeautyBookingStatus(
                status: a.status, label: s.boStatus(a.status)),
          ),
      ],
    );
  }
}

class _IncomeTab extends StatelessWidget {
  const _IncomeTab({required this.api});

  final BeautyOpsApi api;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return BeautyAsync<BeautyEarnings>(
      load: api.earnings,
      builder: (context, e) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.boIncomeNote,
              style: const TextStyle(color: BeautyColors.muted)),
          const SizedBox(height: 14),
          _IncomeCard(
              label: s.boToday,
              value: s.bMoney(e.todayMinor),
              sub: s.boCompleted(e.completedToday)),
          _IncomeCard(label: s.boIncomeWeek, value: s.bMoney(e.weekMinor)),
          _IncomeCard(
              label: s.boIncomeMonth,
              value: s.bMoney(e.monthMinor),
              sub: s.boCompleted(e.completedMonth)),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BeautyColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: BeautyColors.muted)),
                  if (sub != null) Text(sub!),
                ],
              ),
            ),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.today});

  final BeautyToday today;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: BeautyColors.lavender,
              child: Icon(Icons.person, color: BeautyColors.primary),
            ),
            title: Text(today.masterName,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(today.venueName),
          ),
        ],
      );
}

class _LinkView extends StatefulWidget {
  const _LinkView({required this.api, required this.onLinked});

  final BeautyOpsApi api;
  final VoidCallback onLinked;

  @override
  State<_LinkView> createState() => _LinkViewState();
}

class _LinkViewState extends State<_LinkView> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _invalid = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _invalid = false;
    });
    try {
      await widget.api.link(_code.text);
      widget.onLinked();
    } on IdentityApiError {
      if (mounted) setState(() => _invalid = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.badge_outlined, size: 56, color: BeautyColors.primary),
        const SizedBox(height: 12),
        Text(s.boLinkTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(s.boLinkBody, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: s.boInviteCode,
            border: const OutlineInputBorder(),
            errorText: _invalid ? s.boLinkInvalid : null,
          ),
        ),
        const SizedBox(height: 16),
        BeautyPrimaryButton(
          label: s.boLinkAction,
          loading: _busy,
          onPressed: _link,
        ),
      ],
    );
  }
}
