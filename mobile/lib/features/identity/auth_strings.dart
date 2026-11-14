import 'package:flutter/widgets.dart';

class AuthStrings {
  AuthStrings(BuildContext context)
      : code = Localizations.localeOf(context).languageCode;
  final String code;
  String pick(String ru, String kk, String en) => code == 'kk'
      ? kk
      : code == 'en'
          ? en
          : ru;
  String get welcome => pick('Ваш день начинается здесь',
      'Күніңіз осы жерден басталады', 'Your day starts here');
  String get intro => pick(
      'Один профиль для повседневной жизни в Алматы.',
      'Алматыдағы күнделікті өмірге арналған бір профиль.',
      'One profile for everyday life in Almaty.');
  String get login => pick('Войти', 'Кіру', 'Sign in');
  String get register =>
      pick('Создать аккаунт', 'Тіркелгі жасау', 'Create account');
  String get browser => pick(
      'Вход и регистрация откроются в защищённом браузере.',
      'Кіру және тіркелу қауіпсіз браузерде ашылады.',
      'Sign in and registration open in your secure browser.');
  String get loading => pick(
      'Проверяем сессию…', 'Сессия тексерілуде…', 'Checking your session…');
  String get profile => pick('Профиль', 'Профиль', 'Profile');
  String get home => pick('Главная', 'Басты бет', 'Home');
  String get name => pick('Имя', 'Аты', 'Name');
  String get language =>
      pick('Язык приложения', 'Қолданба тілі', 'App language');
  String get save => pick('Сохранить', 'Сақтау', 'Save changes');
  String get saved =>
      pick('Профиль сохранён', 'Профиль сақталды', 'Profile saved');
  String get cancel => pick('Отмена', 'Бас тарту', 'Cancel');
  String get logout => pick('Выйти', 'Шығу', 'Sign out');
  String get retry => pick('Повторить', 'Қайталау', 'Try again');
  String get reload => pick('Загрузить актуальный профиль',
      'Өзекті профильді жүктеу', 'Reload latest profile');
  String get offline => pick(
      'Нет связи. Проверьте интернет и повторите попытку.',
      'Байланыс жоқ. Интернетті тексеріп, қайталаңыз.',
      'Cannot connect. Check your connection and try again.');
  String get expired => pick(
      'Сессия истекла. Войдите снова.',
      'Сессия аяқталды. Қайта кіріңіз.',
      'Your session expired. Sign in again.');
  String get denied => pick(
      'Доступ к аккаунту ограничен. Обратитесь в поддержку.',
      'Тіркелгіге кіру шектелген. Қолдау қызметіне хабарласыңыз.',
      'Account access is restricted. Contact support.');
  String get conflict => pick(
      'Профиль изменён в другой сессии. Загрузите актуальную версию перед сохранением.',
      'Профиль басқа сессияда өзгертілді. Сақтау алдында өзекті нұсқаны жүктеңіз.',
      'Your profile changed in another session. Reload the latest version before saving.');
  String get invalid => pick(
      'Введите имя от 1 до 80 символов без управляющих символов.',
      'Басқару таңбаларынсыз 1–80 таңбадан тұратын атты енгізіңіз.',
      'Enter a name of 1–80 characters without control characters.');
  String get loginFailed => pick(
      'Вход не завершён. Попробуйте снова.',
      'Кіру аяқталмады. Қайталап көріңіз.',
      'Sign in did not complete. Try again.');
  String get logoutPartial => pick(
      'Вы вышли из приложения. Сессия в браузере могла сохраниться.',
      'Қолданбадан шықтыңыз. Браузердегі сессия сақталуы мүмкін.',
      'Signed out of the app. Your browser session may still be active.');
  String get logoutPartialPhone => pick(
      'Вы вышли из приложения. Завершить сессию на сервере не удалось — она истечёт сама.',
      'Қолданбадан шықтыңыз. Серверде сессияны аяқтау мүмкін болмады — ол өзі аяқталады.',
      'Signed out of the app. The server session could not be ended and will expire on its own.');
  String get discard => pick('Отменить изменения?',
      'Өзгерістерден бас тарту керек пе?', 'Discard changes?');
  String get discardBody => pick('Несохранённые изменения будут потеряны.',
      'Сақталмаған өзгерістер жоғалады.', 'Unsaved changes will be lost.');
  String get discardAction => pick('Не сохранять', 'Сақтамау', 'Discard');
  String get edit =>
      pick('Редактировать профиль', 'Профильді өңдеу', 'Edit profile');
}
