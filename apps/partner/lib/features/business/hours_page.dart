import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import '../../widgets/dialogs.dart';

/// Validates a weekly schedule exactly like the backend does, so mistakes are
/// caught before a request is sent (the server still has the final say).
bool hoursValid(List<WorkingHours> hours) {
  int? minutes(String? t) {
    if (t == null) return null;
    final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(t);
    return m == null
        ? null
        : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  final days = <int>{};
  for (final h in hours) {
    final from = minutes(h.from);
    final to = minutes(h.to);
    if (h.day < 1 ||
        h.day > 7 ||
        !days.add(h.day) ||
        from == null ||
        to == null ||
        to <= from) {
      return false;
    }
    final bf = minutes(h.breakFrom);
    final bt = minutes(h.breakTo);
    if ((h.breakFrom == null) != (h.breakTo == null)) return false;
    if (h.breakFrom != null) {
      if (bf == null || bt == null || bt <= bf || bf < from || bt > to) {
        return false;
      }
    }
  }
  return true;
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _parse(String t) => TimeOfDay(
    hour: int.parse(t.substring(0, 2)), minute: int.parse(t.substring(3, 5)));

class _Day {
  _Day(this.day, WorkingHours? h)
      : on = h != null,
        from = h?.from ?? '10:00',
        to = h?.to ?? '19:00',
        breakFrom = h?.breakFrom,
        breakTo = h?.breakTo;
  final int day;
  bool on;
  String from;
  String to;
  String? breakFrom;
  String? breakTo;

  WorkingHours? toHours() => on
      ? WorkingHours(
          day: day, from: from, to: to, breakFrom: breakFrom, breakTo: breakTo)
      : null;
}

/// Weekly schedule editor of one specialist (Owner/Manager).
class HoursPage extends StatefulWidget {
  const HoursPage(
      {required this.ops,
      required this.venueId,
      required this.master,
      super.key});
  final PartnerOperations ops;
  final String venueId;
  final Master master;
  @override
  State<HoursPage> createState() => _HoursPageState();
}

class _HoursPageState extends State<HoursPage> {
  late final List<_Day> _days = [
    for (var d = 1; d <= 7; d++)
      _Day(d, widget.master.hours.where((h) => h.day == d).firstOrNull),
  ];
  bool _busy = false;

  Future<void> _pick(
      _Day day, String current, void Function(String) set) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(current),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => set(_fmt(picked)));
  }

  Future<void> _save() async {
    final s = S.of(context);
    final hours = _days.where((d) => d.on).map((d) => d.toHours()!).toList();
    if (!hoursValid(hours)) {
      showToast(context, s.scheduleInvalid, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.ops
          .setMasterHours(widget.venueId, widget.master.id, hours);
      if (!mounted) return;
      showToast(context, s.scheduleSaved);
      Navigator.pop(context, updated);
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.master.name} · ${s.scheduleTitle}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? s.pleaseWait : s.save),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        for (final d in _days)
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
                        title: Text(s.weekday(d.day),
                            style: context.text.titleSmall),
                        subtitle: Text(d.on ? s.workingDay : s.dayOff),
                        value: d.on,
                        onChanged: (v) => setState(() => d.on = v),
                      ),
                      if (d.on) ...[
                        Wrap(spacing: Gap.md, runSpacing: Gap.sm, children: [
                          OutlinedButton(
                            onPressed: () =>
                                _pick(d, d.from, (v) => d.from = v),
                            child: Text('${s.fromLabel} ${d.from}'),
                          ),
                          OutlinedButton(
                            onPressed: () => _pick(d, d.to, (v) => d.to = v),
                            child: Text('${s.toLabel} ${d.to}'),
                          ),
                        ]),
                        const SizedBox(height: Gap.sm),
                        if (d.breakFrom == null)
                          TextButton.icon(
                            onPressed: () => setState(() {
                              d.breakFrom = '13:00';
                              d.breakTo = '14:00';
                            }),
                            icon: const Icon(Icons.free_breakfast_outlined),
                            label: Text(s.addBreak),
                          )
                        else
                          Wrap(
                              spacing: Gap.md,
                              runSpacing: Gap.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _pick(
                                      d, d.breakFrom!, (v) => d.breakFrom = v),
                                  child: Text('${s.breakLabel} ${d.breakFrom}'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _pick(
                                      d, d.breakTo!, (v) => d.breakTo = v),
                                  child: Text('— ${d.breakTo}'),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    d.breakFrom = null;
                                    d.breakTo = null;
                                  }),
                                  child: Text(s.removeBreak),
                                ),
                              ]),
                      ],
                    ]),
              ),
            ),
          ),
      ]),
    );
  }
}
