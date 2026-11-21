import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/states.dart';
import 'leisure_ops.dart';
import 'leisure_screen.dart' show shortWhen, statusColor;
import 'leisure_strings.dart';

/// Venues and events of the partner with the whole lifecycle: create, edit, price, schedule, submit for moderation, archive.
class LeisureCatalog extends StatefulWidget {
  const LeisureCatalog({required this.ops, required this.canManage, super.key});

  final LeisureOps ops;
  final bool canManage;

  @override
  State<LeisureCatalog> createState() => _LeisureCatalogState();
}

class _LeisureCatalogState extends State<LeisureCatalog> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data =
      _load();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>
      _load() async => (await widget.ops.venues(), await widget.ops.events());

  void _reload() => setState(() {
        _data = _load();
      });

  Future<void> _run(Future<void> Function() action) async {
    final s = S.of(context);
    try {
      await action();
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(s, e))));
      }
    }
  }

  Future<void> _venueForm([Map<String, dynamic>? venue]) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _VenueDialog(venue: venue));
    if (result == null) return;
    await _run(() async {
      if (venue == null) {
        await widget.ops.createVenue(result);
      } else {
        await widget.ops.updateVenue(
            '${venue['id']}', result, (venue['version'] as num).toInt());
      }
    });
  }

  Future<void> _eventForm(String venueId) async {
    final categories = await widget.ops.categories();
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _EventDialog(categories: categories));
    if (result == null) return;
    await _run(() async {
      await widget.ops.createEvent(venueId, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<
        (List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonList(count: 3);
        }
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: _reload);
        }
        final (venues, events) = snap.data!;
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _data;
          },
          child: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
            if (widget.canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                    onPressed: () => _venueForm(),
                    icon: const Icon(Icons.add_business_outlined),
                    label: Text(s.lzNewVenue)),
              ),
            const SizedBox(height: Gap.md),
            if (venues.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Center(child: Text(s.lzNothing))),
            for (final v in venues)
              Card(
                margin: const EdgeInsets.only(bottom: Gap.md),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text('${v['name']}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800))),
                          _StatusChip('${v['status']}'),
                        ]),
                        if ('${v['address']}'.isNotEmpty)
                          Text('${v['address']}',
                              style: theme.textTheme.bodySmall),
                        if (v['moderationNote'] != null)
                          Text('${v['moderationNote']}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error)),
                        const SizedBox(height: Gap.sm),
                        Wrap(spacing: Gap.sm, children: [
                          if (widget.canManage)
                            OutlinedButton(
                                onPressed: () => _venueForm(v),
                                child: Text(s.lzEditVenue)),
                          if (widget.canManage &&
                              (v['status'] == 'DRAFT' ||
                                  v['status'] == 'REJECTED'))
                            FilledButton.tonal(
                                onPressed: () => _run(() async {
                                      await widget.ops
                                          .submitVenue('${v['id']}');
                                    }),
                                child: Text(s.lzSubmit)),
                          if (widget.canManage)
                            FilledButton.tonalIcon(
                                onPressed: () => _eventForm('${v['id']}'),
                                icon: const Icon(Icons.add_rounded),
                                label: Text(s.lzNewEvent)),
                        ]),
                        const Divider(height: Gap.xl),
                        for (final e
                            in events.where((e) => e['venueId'] == v['id']))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${e['title']}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${s.lzBookingTypeName('${e['bookingType']}')} · ${s.lzUpcomingSessions}: ${e['upcomingSessions']}'),
                            trailing: _StatusChip('${e['status']}'),
                            onTap: () async {
                              await Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                      builder: (_) => EventManagePage(
                                          ops: widget.ops,
                                          event: e,
                                          canManage: widget.canManage)));
                              if (mounted) _reload();
                            },
                          ),
                      ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(Radii.chip)),
      child: Text(S.of(context).lzStatus(status),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _VenueDialog extends StatefulWidget {
  const _VenueDialog({this.venue});

  final Map<String, dynamic>? venue;

  @override
  State<_VenueDialog> createState() => _VenueDialogState();
}

class _VenueDialogState extends State<_VenueDialog> {
  late final _name =
      TextEditingController(text: '${widget.venue?['name'] ?? ''}');
  late final _address =
      TextEditingController(text: '${widget.venue?['address'] ?? ''}');
  late final _district =
      TextEditingController(text: '${widget.venue?['district'] ?? ''}');
  late final _description =
      TextEditingController(text: '${widget.venue?['description'] ?? ''}');
  late final _rules =
      TextEditingController(text: '${widget.venue?['rules'] ?? ''}');
  late final _photos = TextEditingController(
      text: ((widget.venue?['photoUrls'] as List?) ?? const []).join('\n'));
  late final _hours =
      TextEditingController(text: '${widget.venue?['cancellationHours'] ?? 2}');

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _district,
      _description,
      _rules,
      _photos,
      _hours
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget field(TextEditingController c, String label,
            {int lines = 1, TextInputType? type}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: TextField(
              controller: c,
              maxLines: lines,
              keyboardType: type,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())),
        );
    return AlertDialog(
      title: Text(widget.venue == null ? s.lzNewVenue : s.lzEditVenue),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(_name, s.lzVenueName),
          field(_address, s.lzAddress),
          field(_district, s.lzDistrict),
          field(_description, s.lzDescription, lines: 3),
          field(_rules, s.lzRules, lines: 2),
          field(_photos, s.lzPhotos, lines: 3),
          Text(s.lzPhotoNote, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Gap.md),
          field(_hours, s.lzCancelHours, type: TextInputType.number),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.lzClose)),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'name': _name.text.trim(),
            'address': _address.text.trim(),
            'district': _district.text.trim(),
            'description': _description.text.trim(),
            'rules': _rules.text.trim(),
            'photoUrls': _photos.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            'cancellationHours': int.tryParse(_hours.text.trim()) ?? 2,
          }),
          child: Text(s.lzSave),
        ),
      ],
    );
  }
}

class _EventDialog extends StatefulWidget {
  const _EventDialog({required this.categories, this.event});

  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic>? event;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late final _title =
      TextEditingController(text: '${widget.event?['title'] ?? ''}');
  late final _description =
      TextEditingController(text: '${widget.event?['description'] ?? ''}');
  late final _photos = TextEditingController(
      text: ((widget.event?['photoUrls'] as List?) ?? const []).join('\n'));
  late final _duration =
      TextEditingController(text: '${widget.event?['durationMinutes'] ?? 90}');
  late final _age =
      TextEditingController(text: '${widget.event?['minAge'] ?? 0}');
  late final _guests =
      TextEditingController(text: '${widget.event?['maxGuests'] ?? 10}');
  late String? _category = widget.event?['categoryCode'] as String? ??
      (widget.categories.isEmpty
          ? null
          : widget.categories.first['code'] as String);
  late String? _type = widget.event?['bookingType'] as String?;
  late bool _family = widget.event?['familyFriendly'] == true;
  late bool _manual = widget.event?['confirmation'] == 'MANUAL';
  late bool _executor = widget.event?['needsExecutor'] == true;

  @override
  void dispose() {
    for (final c in [_title, _description, _photos, _duration, _age, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lang = s.locale.languageCode;
    Widget field(TextEditingController c, String label,
            {int lines = 1, TextInputType? type}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: TextField(
              controller: c,
              maxLines: lines,
              keyboardType: type,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())),
        );
    final editing = widget.event != null;
    return AlertDialog(
      title: Text(editing ? s.lzEvents : s.lzNewEvent),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(_title, s.lzEventTitle),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: s.lzCategory,
                    border: const OutlineInputBorder()),
                items: [
                  for (final c in widget.categories)
                    DropdownMenuItem(
                        value: c['code'] as String,
                        child: Text(
                            '${c[lang == 'kk' ? 'nameKk' : lang == 'en' ? 'nameEn' : 'nameRu']}',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _category = v;
                  _type = null;
                }),
              ),
              const SizedBox(height: Gap.md),
              if (!editing)
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: s.lzBookingType,
                      border: const OutlineInputBorder()),
                  items: [
                    for (final t in [
                      'TIME_SLOT',
                      'CAPACITY',
                      'SEAT_MAP',
                      'GENERAL_ADMISSION',
                      'PRIVATE_SESSION'
                    ])
                      DropdownMenuItem(
                          value: t,
                          child: Text(s.lzBookingTypeName(t),
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
              if (!editing) const SizedBox(height: Gap.md),
              field(_description, s.lzDescription, lines: 3),
              field(_photos, s.lzPhotos, lines: 2),
              field(_duration, s.lzDuration, type: TextInputType.number),
              field(_age, s.lzMinAge, type: TextInputType.number),
              field(_guests, s.lzMaxGuests, type: TextInputType.number),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _family,
                  onChanged: (v) => setState(() => _family = v),
                  title: Text(s.lzFamily)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _manual,
                  onChanged: (v) => setState(() => _manual = v),
                  title: Text(s.lzManual)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _executor,
                  onChanged: (v) => setState(() => _executor = v),
                  title: Text(s.lzNeedsExecutor)),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.lzClose)),
        FilledButton(
          onPressed: _category == null
              ? null
              : () => Navigator.pop(context, {
                    'categoryCode': _category,
                    if (_type != null) 'bookingType': _type,
                    'title': _title.text.trim(),
                    'description': _description.text.trim(),
                    'photoUrls': _photos.text
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    'durationMinutes':
                        int.tryParse(_duration.text.trim()) ?? 90,
                    'minAge': int.tryParse(_age.text.trim()) ?? 0,
                    'maxGuests': int.tryParse(_guests.text.trim()) ?? 10,
                    'familyFriendly': _family,
                    'confirmation': _manual ? 'MANUAL' : 'AUTO',
                    'needsExecutor': _executor,
                  }),
          child: Text(s.lzSave),
        ),
      ],
    );
  }
}

/// One event: ticket types and prices, sessions with sales and attendance, executors, moderation and archive.
class EventManagePage extends StatefulWidget {
  const EventManagePage(
      {required this.ops,
      required this.event,
      required this.canManage,
      super.key});

  final LeisureOps ops;
  final Map<String, dynamic> event;
  final bool canManage;

  @override
  State<EventManagePage> createState() => _EventManagePageState();
}

class _EventManagePageState extends State<EventManagePage> {
  late Map<String, dynamic> _event = widget.event;
  late Future<List<Map<String, dynamic>>> _types =
      widget.ops.ticketTypes('${_event['id']}');
  late Future<List<Map<String, dynamic>>> _sessions =
      widget.ops.sessions('${_event['id']}');

  void _reload() => setState(() {
        _types = widget.ops.ticketTypes('${_event['id']}');
        _sessions = widget.ops.sessions('${_event['id']}');
      });

  Future<void> _run(Future<Object?> Function() action) async {
    final s = S.of(context);
    try {
      final r = await action();
      if (mounted) {
        if (r is Map<String, dynamic> && r.containsKey('title')) _event = r;
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(s, e))));
      }
    }
  }

  Future<void> _editEvent() async {
    final categories = await widget.ops.categories();
    if (!mounted) return;
    final r = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _EventDialog(categories: categories, event: _event));
    if (r == null) return;
    r['bookingType'] = _event['bookingType'];
    await _run(() => widget.ops
        .updateEvent('${_event['id']}', r, (_event['version'] as num).toInt()));
  }

  Future<void> _ticketType([Map<String, dynamic>? type]) async {
    final s = S.of(context);
    final name = TextEditingController(text: '${type?['name'] ?? ''}');
    final price = TextEditingController(
        text: type == null ? '' : '${(type['priceMinor'] as num) ~/ 100}');
    final zone = TextEditingController(text: '${type?['seatZone'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.lzAddTicketType),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: s.lzTypeName)),
          TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.lzPriceTenge)),
          if (_event['bookingType'] == 'SEAT_MAP')
            TextField(
                controller: zone,
                decoration: InputDecoration(labelText: s.lzZone)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.lzClose)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.lzSave)),
        ],
      ),
    );
    final body = {
      'name': name.text.trim(),
      'priceMinor': (int.tryParse(price.text.trim()) ?? 0) * 100,
      if (zone.text.trim().isNotEmpty) 'seatZone': zone.text.trim()
    };
    name.dispose();
    price.dispose();
    zone.dispose();
    if (ok != true) return;
    await _run(() => widget.ops.saveTicketType(
        '${_event['id']}', type == null ? null : '${type['id']}', body));
  }

  Future<void> _addSessions() async {
    final s = S.of(context);
    final seatMap = _event['bookingType'] == 'SEAT_MAP';
    final private = _event['bookingType'] == 'PRIVATE_SESSION';
    var day = DateTime.now().add(const Duration(days: 1));
    final times = <TimeOfDay>[const TimeOfDay(hour: 18, minute: 0)];
    final capacity = TextEditingController(text: '10');
    final rows = TextEditingController(text: '6');
    final perRow = TextEditingController(text: '10');
    final vip = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(s.lzAddSessions),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded),
                    label: Text(
                        '${s.lzDate}: ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setLocal(() => day = d);
                    },
                  ),
                  const SizedBox(height: Gap.sm),
                  Wrap(spacing: Gap.sm, children: [
                    for (final t in times)
                      InputChip(
                          label: Text(t.format(context)),
                          onDeleted: times.length > 1
                              ? () => setLocal(() => times.remove(t))
                              : null),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: Text(s.lzAddTime),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 12, minute: 0));
                        if (t != null) setLocal(() => times.add(t));
                      },
                    ),
                  ]),
                  const SizedBox(height: Gap.md),
                  if (seatMap) ...[
                    TextField(
                        controller: rows,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: s.lzRows)),
                    TextField(
                        controller: perRow,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: s.lzSeatsPerRow)),
                    TextField(
                        controller: vip,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: s.lzVipRows)),
                  ] else if (!private)
                    TextField(
                        controller: capacity,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: s.lzCapacity)),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.lzClose)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.lzSave)),
          ],
        ),
      ),
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final body = {
      'startsAt': [
        for (final t in times)
          '${day.year}-${two(day.month)}-${two(day.day)}T${two(t.hour)}:${two(t.minute)}:00+05:00'
      ],
      if (seatMap) ...{
        'rows': int.tryParse(rows.text) ?? 6,
        'seatsPerRow': int.tryParse(perRow.text) ?? 10,
        'vipRows': int.tryParse(vip.text) ?? 0
      } else if (!private)
        'capacity': int.tryParse(capacity.text) ?? 10,
    };
    for (final c in [capacity, rows, perRow, vip]) {
      c.dispose();
    }
    if (ok != true) return;
    await _run(() => widget.ops.createSessions('${_event['id']}', body));
  }

  Future<void> _cancelSession(Map<String, dynamic> session) async {
    final s = S.of(context);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.lzCancelSession),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.lzCancelSessionNote),
          TextField(
              controller: reason,
              decoration: InputDecoration(labelText: s.lzReason)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.lzClose)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.lzCancelSession)),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || text.isEmpty) return;
    await _run(() => widget.ops.cancelSession('${session['id']}', text));
  }

  Future<void> _assign(Map<String, dynamic> session) async {
    final s = S.of(context);
    final phone = TextEditingController();
    final note = TextEditingController();
    // Events: the executor is a gate controller scanning tickets of this session; Leisure: guide, host, instructor...
    var role = widget.ops.isEvents ? 'GATE' : 'GUIDE';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(s.lzAssign),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.lzPhone)),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: InputDecoration(labelText: s.lzRole),
              items: [
                for (final r in widget.ops.isEvents
                    ? const ['GATE']
                    : const [
                        'GUIDE',
                        'HOST',
                        'INSTRUCTOR',
                        'ANIMATOR',
                        'ORGANIZER'
                      ])
                  DropdownMenuItem(value: r, child: Text(r))
              ],
              onChanged: (v) => setLocal(() => role = v ?? role),
            ),
            TextField(
                controller: note,
                decoration: InputDecoration(labelText: s.lzNote)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.lzClose)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.lzAssign)),
          ],
        ),
      ),
    );
    final body = {
      'phone': phone.text.trim(),
      'role': role,
      if (note.text.trim().isNotEmpty) 'note': note.text.trim()
    };
    phone.dispose();
    note.dispose();
    if (ok != true) return;
    await _run(() => widget.ops.assign('${session['id']}', body));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final status = '${_event['status']}';
    return Scaffold(
      appBar: AppBar(
          title: Text('${_event['title']}',
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        Row(children: [
          _StatusChip(status),
          const SizedBox(width: Gap.sm),
          Expanded(
              child: Text(s.lzBookingTypeName('${_event['bookingType']}'),
                  style: theme.textTheme.bodySmall)),
        ]),
        if (_event['moderationNote'] != null)
          Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text('${_event['moderationNote']}',
                  style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: Gap.md),
        if (widget.canManage)
          Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
            OutlinedButton.icon(
                onPressed: _editEvent,
                icon: const Icon(Icons.edit_outlined),
                label: Text(s.lzEvents)),
            if (status == 'DRAFT' ||
                status == 'REJECTED' ||
                status == 'ARCHIVED')
              FilledButton.tonalIcon(
                  onPressed: () =>
                      _run(() => widget.ops.submitEvent('${_event['id']}')),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(s.lzSubmit)),
            if (status != 'ARCHIVED' && status != 'BLOCKED')
              OutlinedButton.icon(
                  onPressed: () =>
                      _run(() => widget.ops.archiveEvent('${_event['id']}')),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(s.lzArchive)),
          ]),
        const SizedBox(height: Gap.lg),
        Text(s.lzTicketTypes,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _types,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonBox(height: 60, radius: 12);
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: _reload);
            }
            return Column(children: [
              for (final t in snap.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${t['name']}${t['seatZone'] != null ? ' · ${t['seatZone']}' : ''}'),
                  trailing: Text(formatMoney((t['priceMinor'] as num).toInt()),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: widget.canManage ? () => _ticketType(t) : null,
                ),
              if (widget.canManage)
                TextButton.icon(
                    onPressed: () => _ticketType(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(s.lzAddTicketType)),
            ]);
          },
        ),
        const SizedBox(height: Gap.lg),
        Text(s.lzSessions,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _sessions,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonBox(height: 90, radius: 12);
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: _reload);
            }
            return Column(children: [
              for (final x in snap.data!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(shortWhen('${x['startsAt']}'),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800))),
                            _StatusChip('${x['status']}'),
                          ]),
                          Text(
                              '${s.lzSold}: ${x['sold']} / ${x['capacity']} · ${s.lzHeld}: ${x['held']} · ${s.lzAdmitted}: ${x['admitted']}',
                              style: theme.textTheme.bodySmall),
                          if (widget.canManage && x['status'] == 'SCHEDULED')
                            Wrap(spacing: Gap.sm, children: [
                              TextButton(
                                  onPressed: () => _cancelSession(x),
                                  child: Text(s.lzCancelSession)),
                              if (_event['needsExecutor'] == true ||
                                  widget.ops.isEvents)
                                TextButton(
                                    onPressed: () => _assign(x),
                                    child: Text(s.lzAssign)),
                            ]),
                        ]),
                  ),
                ),
              if (snap.data!.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Text(s.lzNothing)),
              if (widget.canManage)
                TextButton.icon(
                    onPressed: _addSessions,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(s.lzAddSessions)),
            ]);
          },
        ),
      ]),
    );
  }
}
