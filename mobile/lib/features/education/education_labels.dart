import 'package:flutter/material.dart';

String educationLabel(BuildContext context, String ru, String kk, String en) {
  return switch (Localizations.localeOf(context).languageCode) {
    'ru' => ru,
    'kk' => kk,
    _ => en,
  };
}

String educationFormat(BuildContext context, String code) => switch (code) {
      'ONLINE_RECORDED' =>
        educationLabel(context, 'В записи', 'Жазба', 'Recorded'),
      'ONLINE_LIVE' => educationLabel(
          context,
          'Онлайн с преподавателем',
          'Оқытушымен онлайн',
          'Live online',
        ),
      'OFFLINE_GROUP' => educationLabel(
          context,
          'Очно в группе',
          'Топпен офлайн',
          'In-person group',
        ),
      'OFFLINE_INDIVIDUAL' => educationLabel(
          context,
          'Очно индивидуально',
          'Жеке офлайн',
          'In-person one-to-one',
        ),
      'HYBRID' => educationLabel(context, 'Смешанный', 'Аралас', 'Hybrid'),
      _ =>
        educationLabel(context, 'Все форматы', 'Барлық формат', 'All formats'),
    };

String educationPrice(BuildContext context, int minor) {
  final whole = MaterialLocalizations.of(context).formatDecimal(minor ~/ 100);
  final fraction = minor % 100;
  if (fraction == 0) return '$whole ₸';
  final separator =
      Localizations.localeOf(context).languageCode == 'en' ? '.' : ',';
  return '$whole$separator${fraction.toString().padLeft(2, '0')} ₸';
}
