import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';

/// Unavailable periods (holidays, repairs) of a venue or of one post. The server refuses a period that
/// overlaps an existing booking, so a confirmed customer is never silently dropped.
class TimeOffPage extends StatefulWidget {
  const TimeOffPage(
      {required this.ops,
      required this.venueId,
      required this.masters,
      required this.canManage,
      super.key});
  final PartnerOperations ops;
  final String venueId;
  final List<Master> masters;
  final bool canManage;

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage> {
  List<TimeOff>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.ops.timeOff(widget.venueId);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _remove(TimeOff t) async {
    final s = S.of(context);
    try {
      await widget.ops.removeTimeOff(widget.venueId, t.id);
      await _load();
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    }
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AddSheet(
            ops: widget.ops, venueId: widget.venueId, masters: widget.masters));
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(s.timeOffTitle)),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(s.timeOffAdd))
          : null,
      body: items == null
          ? (_error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : const SkeletonList(count: 3))
          : items.isEmpty
              ? Center(child: Text(s.timeOffEmpty))
              : ListView(padding: const EdgeInsets.all(Gap.lg), children: [
                  for (final t in items)
                    Card(
                      child: ListTile(
                        title: Text(
                            '${formatDateTime(t.startsAt, locale)} — ${formatDateTime(t.endsAt, locale)}'),
                        subtitle: Text([
                          if (t.masterId == null)
                            s.timeOffAllPosts
                          else
                            widget.masters
                                .where((m) => m.id == t.masterId)
                                .map((m) => m.name)
                                .join(),
                          if (t.reason.isNotEmpty) t.reason,
                        ].join(' · ')),
                        trailing: widget.canManage
                            ? IconButton(
                                tooltip: s.timeOffRemove,
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _remove(t))
                            : null,
                      ),
                    ),
                ]),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet(
      {required this.ops, required this.venueId, required this.masters});
  final PartnerOperations ops;
  final String venueId;
  final List<Master> masters;
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  late DateTime _from = _roundedNow();
  late DateTime _to = _from.add(const Duration(hours: 2));
  String? _masterId;
  final _reason = TextEditingController();
  bool _busy = false;

  static DateTime _roundedNow() {
    final n = DateTime.now().add(const Duration(hours: 1));
    return DateTime(n.year, n.month, n.day, n.hour);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 366)));
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      await widget.ops.addTimeOff(widget.venueId,
          startsAt: _from,
          endsAt: _to,
          masterId: _masterId,
          reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final valid = _to.isAfter(_from);
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg,
          MediaQuery.viewInsetsOf(context).bottom + Gap.lg),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.timeOffAdd, style: context.text.titleMedium),
              const SizedBox(height: Gap.md),
              ListTile(
                  title: Text(s.timeOffFrom),
                  subtitle: Text(formatDateTime(_from, locale)),
                  onTap: () async {
                    final v = await _pick(_from);
                    if (v != null) setState(() => _from = v);
                  }),
              ListTile(
                  title: Text(s.timeOffTo),
                  subtitle: Text(formatDateTime(_to, locale)),
                  onTap: () async {
                    final v = await _pick(_to);
                    if (v != null) setState(() => _to = v);
                  }),
              if (!valid)
                Text(s.timeOffOrderInvalid,
                    style: TextStyle(color: context.colors.error)),
              const SizedBox(height: Gap.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _masterId,
                decoration: InputDecoration(labelText: s.mastersTitle),
                items: [
                  DropdownMenuItem<String?>(
                      value: null, child: Text(s.timeOffAllPosts)),
                  for (final m in widget.masters)
                    DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => setState(() => _masterId = v),
              ),
              TextField(
                  controller: _reason,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: s.timeOffReason)),
              const SizedBox(height: Gap.sm),
              FilledButton(
                  onPressed: valid && !_busy ? _save : null,
                  child: Text(s.save)),
            ]),
      ),
    );
  }
}
