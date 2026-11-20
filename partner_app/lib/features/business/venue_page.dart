import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';
import 'hours_page.dart';
import 'service_sheet.dart';
import 'time_off_page.dart';

/// Services (availability, price, duration), specialists (active state) and
/// their weekly schedule for one booking venue.
class VenuePage extends StatefulWidget {
  const VenuePage({
    required this.store,
    required this.venue,
    required this.canManage,
    super.key,
  });
  final OpsStore store;
  final Venue venue;
  final bool canManage;
  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  List<VenueService>? _services;
  List<Master>? _masters;
  Object? _error;
  final Set<String> _busy = {};

  PartnerOperations get _ops => widget.store.ops;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _ops.services(widget.venue.id),
        _ops.masters(widget.venue.id),
      ]);
      if (mounted) {
        setState(() {
          _services = results[0] as List<VenueService>;
          _masters = results[1] as List<Master>;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return;
    setState(() {});
    final s = S.of(context);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleService(VenueService x, bool v) =>
      _run('s${x.id}', () async {
        final u = await _ops.setServiceAvailable(widget.venue.id, x.id, v);
        if (!mounted) return;
        setState(
          () => _services = [for (final e in _services!) e.id == x.id ? u : e],
        );
      });

  Future<void> _toggleMaster(Master m, bool v) => _run('m${m.id}', () async {
    final u = await _ops.setMasterActive(widget.venue.id, m.id, v);
    if (!mounted) return;
    setState(
      () => _masters = [for (final e in _masters!) e.id == m.id ? u : e],
    );
  });

  Future<void> _editHours(Master m) async {
    final updated = await Navigator.of(context).push<Master>(
      MaterialPageRoute(
        builder: (_) =>
            HoursPage(ops: _ops, venueId: widget.venue.id, master: m),
      ),
    );
    if (updated != null && mounted) {
      setState(
        () =>
            _masters = [for (final e in _masters!) e.id == m.id ? updated : e],
      );
    }
  }

  Future<void> _editService(VenueService x) async {
    final saved = await showModalBottomSheet<VenueService>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ServiceSheet(
        ops: _ops,
        venueId: widget.venue.id,
        service: x,
        health: widget.venue.isHealth,
      ),
    );
    if (saved != null && mounted) {
      setState(
        () =>
            _services = [for (final e in _services!) e.id == x.id ? saved : e],
      );
    }
  }

  Future<void> _addService() async {
    final saved = await showModalBottomSheet<VenueService>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ServiceSheet(
        ops: _ops,
        venueId: widget.venue.id,
        health: widget.venue.isHealth,
        specialists: _masters ?? const [],
      ),
    );
    if (saved != null && mounted) {
      setState(() => _services = [..._services!, saved]);
    }
  }

  Future<void> _addPost() async {
    final s = S.of(context);
    final name = await reasonDialog(
      context,
      title: widget.venue.isHealth ? s.healthSpecialistName : s.postName,
    );
    if (name == null || !mounted) return;
    await _run('post', () async {
      final m = widget.venue.isHealth
          ? await _ops.createHealthSpecialist(widget.venue.id, name)
          : await _ops.createPost(widget.venue.id, name);
      if (mounted) setState(() => _masters = [..._masters!, m]);
    });
  }

  void _openTimeOff() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimeOffPage(
          ops: _ops,
          venueId: widget.venue.id,
          masters: _masters ?? const [],
          canManage: widget.canManage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final services = _services;
    final masters = _masters;
    return Scaffold(
      appBar: AppBar(title: Text(widget.venue.name)),
      body: services == null || masters == null
          ? (_error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : const SkeletonList(count: 4))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gap.lg),
                children: [
                  _heading(context, s.servicesTitle),
                  if (services.isEmpty) Text(s.servicesEmpty),
                  for (final x in services)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: Card(
                        child: SwitchListTile(
                          title: Text(x.name),
                          subtitle: Text(
                            '${formatMoney(x.priceMinor)} · ${s.minutesShort(x.durationMinutes)} · ${x.available ? s.dishAvailable : s.dishUnavailable}',
                          ),
                          value: x.available,
                          secondary: widget.canManage
                              ? IconButton(
                                  tooltip: s.editService,
                                  icon: const Icon(Icons.edit_rounded),
                                  onPressed: () => _editService(x),
                                )
                              : null,
                          onChanged: _busy.contains('s${x.id}')
                              ? null
                              : (v) => _toggleService(x, v),
                        ),
                      ),
                    ),
                  if (widget.canManage &&
                      (widget.venue.isAuto || widget.venue.isHealth))
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: widget.venue.isHealth && masters.isEmpty
                            ? null
                            : _addService,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(s.addService),
                      ),
                    ),
                  const SizedBox(height: Gap.lg),
                  _heading(
                    context,
                    widget.venue.isHealth
                        ? s.healthSpecialists
                        : s.mastersTitle,
                  ),
                  if (masters.isEmpty) Text(s.mastersEmpty),
                  for (final m in masters)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.md),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(Gap.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  m.name,
                                  style: context.text.titleSmall,
                                ),
                                subtitle: Text(
                                  m.active ? s.active : s.inactive,
                                ),
                                value: m.active,
                                onChanged: _busy.contains('m${m.id}')
                                    ? null
                                    : (v) => _toggleMaster(m, v),
                              ),
                              const Divider(),
                              const SizedBox(height: Gap.sm),
                              Text(
                                s.scheduleTitle,
                                style: context.text.labelLarge,
                              ),
                              const SizedBox(height: Gap.xs),
                              ScheduleSummary(hours: m.hours),
                              if (widget.canManage) ...[
                                const SizedBox(height: Gap.sm),
                                OutlinedButton.icon(
                                  onPressed: () => _editHours(m),
                                  icon: const Icon(Icons.schedule_rounded),
                                  label: Text(s.editSchedule),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (widget.canManage &&
                      (widget.venue.isAuto || widget.venue.isHealth))
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _busy.contains('post') ? null : _addPost,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          widget.venue.isHealth
                              ? s.addHealthSpecialist
                              : s.addPost,
                        ),
                      ),
                    ),
                  const SizedBox(height: Gap.sm),
                  OutlinedButton.icon(
                    onPressed: _openTimeOff,
                    icon: const Icon(Icons.event_busy_rounded),
                    label: Text(s.timeOffTitle),
                  ),
                  const SizedBox(height: Gap.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          s.slotsNote,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Semantics(
      header: true,
      child: Text(text, style: context.text.titleMedium),
    ),
  );
}

/// Seven-line weekly summary; missing weekdays are shown as days off.
class ScheduleSummary extends StatelessWidget {
  const ScheduleSummary({required this.hours, super.key});
  final List<WorkingHours> hours;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final byDay = {for (final h in hours) h.day: h};
    return Column(
      children: [
        for (var day = 1; day <= 7; day++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(s.weekday(day), style: context.text.bodyMedium),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    byDay[day] == null
                        ? s.dayOff
                        : '${byDay[day]!.from}–${byDay[day]!.to}${byDay[day]!.breakFrom == null ? '' : ' (${s.breakLabel} ${byDay[day]!.breakFrom}–${byDay[day]!.breakTo})'}',
                    textAlign: TextAlign.end,
                    style: context.text.bodyMedium?.copyWith(
                      color: byDay[day] == null
                          ? context.colors.onSurfaceVariant
                          : context.colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
