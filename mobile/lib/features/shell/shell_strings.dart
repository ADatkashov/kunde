import '../../core/localization/kunde_localizations.dart';

/// Strings of the bottom navigation and its not-yet-built tabs (RU/KK/EN).
extension ShellStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get navHome => _t('Главная', 'Басты бет', 'Home');
  String get navSearch => _t('Поиск', 'Іздеу', 'Search');
  String get navOrders => _t('Заказы', 'Тапсырыстар', 'Orders');
  String get navProfile => _t('Профиль', 'Профиль', 'Profile');
  String get navLabel =>
      _t('Основная навигация', 'Негізгі навигация', 'Main navigation');
  String get searchTabUnavailableTitle => _t('Поиск пока недоступен',
      'Іздеу әзірге қолжетімсіз', 'Search is not available yet');
  String get searchTabUnavailableBody => _t(
      'Поиск заработает, когда сервисы в Алматы будут запущены.',
      'Алматыдағы қызметтер іске қосылғанда іздеу жұмыс істейді.',
      'Search will work once services in Almaty are launched.');
  String get ordersEmptyTitle =>
      _t('Заказов пока нет', 'Тапсырыстар әзірге жоқ', 'No orders yet');
  String get ordersEmptyBody => _t(
      'Здесь появятся ваши заказы, когда запустится заказ еды в Алматы. Сейчас оформить заказ нельзя.',
      'Алматыда тамақ тапсырысы іске қосылғанда, тапсырыстарыңыз осында шығады. Қазір тапсырыс беру мүмкін емес.',
      'Your orders will appear here once food ordering launches in Almaty. Ordering is not available yet.');
  String get profileNotConfiguredTitle => _t('Вход пока не настроен',
      'Кіру әзірге бапталмаған', 'Sign-in is not set up yet');
  String get profileNotConfiguredBody => _t(
      'Профиль, адреса и согласия станут доступны после настройки входа.',
      'Профиль, мекенжайлар және келісімдер кіру бапталғаннан кейін қолжетімді болады.',
      'Profile, addresses and consents become available once sign-in is set up.');
}
