import 'package:flutter/widgets.dart';

import 'phone_auth_gateway.dart';

class PhoneAuthStrings {
  PhoneAuthStrings(BuildContext context)
      : code = Localizations.localeOf(context).languageCode;
  final String code;
  String pick(String ru, String kk, String en) => code == 'kk'
      ? kk
      : code == 'en'
          ? en
          : ru;

  String get phoneTitle => pick('Войдите по номеру телефона',
      'Телефон нөмірімен кіріңіз', 'Sign in with your phone');
  String get phoneBody => pick(
      'Мы отправим одноразовый код подтверждения.',
      'Біз бір реттік растау кодын жібереміз.',
      "We'll send you a one-time confirmation code.");
  String get phoneLabel =>
      pick('Номер телефона', 'Телефон нөмірі', 'Phone number');
  String get phoneHint => '700 000 00 01';
  String get getCode => pick('Получить код', 'Код алу', 'Get code');
  String get codeTitle =>
      pick('Введите код', 'Кодты енгізіңіз', 'Enter the code');
  String sentTo(String phone) => pick('Код отправлен на $phone',
      'Код $phone нөміріне жіберілді', 'Code sent to $phone');
  String get devHint => pick('Тестовый код: 123456 (только DEV)',
      'Сынақ коды: 123456 (тек DEV)', 'Test code: 123456 (DEV only)');
  String get changeNumber =>
      pick('Изменить номер', 'Нөмірді өзгерту', 'Change number');
  String resendIn(int seconds) => pick('Отправить код ещё раз через $seconds с',
      'Кодты $seconds с кейін қайта жіберу', 'Resend code in ${seconds}s');
  String get resend =>
      pick('Отправить код ещё раз', 'Кодты қайта жіберу', 'Resend code');
  String get verifying =>
      pick('Проверяем код…', 'Код тексерілуде…', 'Checking the code…');
  String get terms => pick(
      'Продолжая, вы входите в тестовую среду KUNDE.',
      'Жалғастыру арқылы KUNDE сынақ ортасына кіресіз.',
      'By continuing you enter the KUNDE test environment.');

  String error(PhoneAuthFailure failure) => switch (failure) {
        PhoneAuthFailure.invalidPhone => pick(
            'Введите 10 цифр номера после +7.',
            '+7 кейін нөмірдің 10 санын енгізіңіз.',
            'Enter the 10 digits that follow +7.'),
        PhoneAuthFailure.invalidCode => pick(
            'Неверный или просроченный код. Проверьте код или запросите новый.',
            'Код қате немесе мерзімі өткен. Кодты тексеріңіз немесе жаңасын сұраңыз.',
            'The code is wrong or expired. Check it or request a new one.'),
        PhoneAuthFailure.rateLimited => pick(
            'Слишком много попыток. Подождите немного и повторите.',
            'Әрекет тым көп. Біраз күтіп, қайталаңыз.',
            'Too many attempts. Wait a little and try again.'),
        PhoneAuthFailure.unavailable => pick(
            'Отправка кодов сейчас недоступна. Попробуйте позже.',
            'Кодтарды жіберу қазір қолжетімсіз. Кейінірек қайталаңыз.',
            'Code delivery is unavailable right now. Try again later.'),
        PhoneAuthFailure.network => pick(
            'Нет связи с сервером. Сервер мог «просыпаться» — повторите через минуту.',
            'Сервермен байланыс жоқ. Сервер оянып жатқан болуы мүмкін — бір минуттан кейін қайталаңыз.',
            'Cannot reach the server. It may be waking up — try again in a minute.'),
      };
}
