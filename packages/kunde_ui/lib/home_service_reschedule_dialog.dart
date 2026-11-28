import 'package:flutter/material.dart';

import 'ride_strings.dart';

typedef HomeServiceScheduleProposal = ({String startsAt, String reason});

class HomeServiceRescheduleDialog extends StatefulWidget {
  const HomeServiceRescheduleDialog({super.key});

  @override
  State<HomeServiceRescheduleDialog> createState() =>
      _HomeServiceRescheduleDialogState();
}

class _HomeServiceRescheduleDialogState
    extends State<HomeServiceRescheduleDialog> {
  final _form = GlobalKey<FormState>();
  DateTime? _date;
  TimeOfDay? _time;
  String _reason = '';

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final labels = MaterialLocalizations.of(context);
    final date = _date;
    final time = _time;
    return AlertDialog(
      title: Text(s.t('Предложить перенос', 'Уақытты ауыстыруды ұсыну',
          'Propose a change')),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(date == null
                    ? s.t('Выбрать дату', 'Күнді таңдау', 'Choose date')
                    : labels.formatMediumDate(date)),
                onPressed: () async {
                  final now =
                      DateTime.now().toUtc().add(const Duration(hours: 5));
                  final today = DateTime(now.year, now.month, now.day);
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _date ?? today,
                    firstDate: today,
                    lastDate: DateTime(today.year, today.month, today.day + 13),
                  );
                  if (selected != null && mounted) {
                    setState(() => _date = selected);
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: Text(time == null
                    ? s.t('Выбрать время (UTC+5)', 'Уақытты таңдау (UTC+5)',
                        'Choose time (UTC+5)')
                    : '${labels.formatTimeOfDay(time)} (UTC+5)'),
                onPressed: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
                  );
                  if (selected != null && mounted) {
                    setState(() => _time = selected);
                  }
                },
              ),
              TextFormField(
                maxLength: 200,
                decoration: InputDecoration(
                    labelText: s.t('Причина', 'Себеп', 'Reason')),
                onChanged: (value) => _reason = value.trim(),
                validator: (_) => _reason.isEmpty
                    ? s.t('Укажите причину', 'Себебін көрсетіңіз',
                        'Enter a reason')
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.back),
        ),
        FilledButton(
          onPressed: date == null || time == null
              ? null
              : () {
                  if (!_form.currentState!.validate()) return;
                  final start = DateTime.utc(date.year, date.month, date.day,
                          time.hour, time.minute)
                      .subtract(const Duration(hours: 5));
                  Navigator.pop(
                    context,
                    (startsAt: start.toIso8601String(), reason: _reason),
                  );
                },
          child: Text(s.t('Отправить', 'Жіберу', 'Send')),
        ),
      ],
    );
  }
}
