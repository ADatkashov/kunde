import '../../../core/localization/kunde_localizations.dart';

/// Strings of the Super App home screen (RU/KK/EN). Kept next to the screen so
/// the shared localization file stays small.
extension HomeStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get homeCity => _t('Алматы', 'Алматы', 'Almaty');
  String get homeTagline => _t(
      'Ваше суперприложение для жизни каждый день',
      'Күнделікті өмірге арналған суперқосымша',
      'Your super app for everyday life');
  String get homeLocationLabel =>
      _t('Город: Алматы', 'Қала: Алматы', 'City: Almaty');
  String get homeSearchHint => _t('Что хотите сделать сегодня?',
      'Бүгін не істегіңіз келеді?', 'What do you want to do today?');
  String get homeSoon => _t('Скоро', 'Жақында', 'Soon');
  String get homeAiTitle => 'KUNDE AI';
  String get homeAiSubtitle => _t('Ваш умный помощник в повседневной жизни',
      'Күнделікті өмірдегі ақылды көмекшіңіз', 'Your smart everyday assistant');
  String get homeAiAsk => _t('Спросить', 'Сұрау', 'Ask');
  String get homeAiUnavailable => _t(
      'KUNDE AI пока недоступен. Он появится после утверждения.',
      'KUNDE AI әзірге қолжетімсіз. Бекітілгеннен кейін шығады.',
      'KUNDE AI is not available yet. It will appear once approved.');
  String get catFood => _t('Еда', 'Тамақ', 'Food');
  String get catGroceries => _t('Продукты', 'Азық-түлік', 'Groceries');
  String get catRides => _t('Поездки', 'Сапарлар', 'Rides');
  String get catDelivery => _t('Доставка', 'Жеткізу', 'Delivery');
  String get catHome => _t('Дом и быт', 'Үй және тұрмыс', 'Home services');
  String get catBeauty => _t('Красота', 'Сұлулық', 'Beauty');
  String get catHealth => _t('Здоровье', 'Денсаулық', 'Health');
  String get catAuto => _t('Авто', 'Авто', 'Auto');
  String get catLeisure => _t('Досуг', 'Демалыс', 'Leisure');
  String get catAll => _t('Все сервисы', 'Барлық қызметтер', 'All services');
  String get allServicesTitle =>
      _t('Все сервисы KUNDE', 'KUNDE қызметтері', 'All KUNDE services');
  String get categoryAvailable => _t('Доступно', 'Қолжетімді', 'Available');
  String get comingSoonTitle =>
      _t('Скоро в KUNDE', 'KUNDE-де жақында', 'Coming soon to KUNDE');
  String get comingSoonBody => _t(
      'Этот сервис ещё не подключён, заказы в нём недоступны. Первым запускается заказ еды в Алматы.',
      'Бұл қызмет әлі қосылмаған, тапсырыс беру мүмкін емес. Алғашқы болып Алматыда тамақ тапсырысы іске қосылады.',
      'This service is not connected yet and orders are unavailable. Food ordering in Almaty launches first.');
  String get foodPreparingBody => _t(
      'Заказ еды в Алматы готовится к запуску. Рестораны появятся здесь после подключения.',
      'Алматыда тамақ тапсырысы іске қосуға дайындалуда. Мейрамханалар қосылғаннан кейін осында шығады.',
      'Food ordering in Almaty is being prepared. Restaurants will appear here once connected.');
  String get searchUnavailable => _t(
      'Поиск заработает, когда сервисы будут запущены.',
      'Қызметтер іске қосылғанда іздеу жұмыс істейді.',
      'Search will work once services are launched.');
  String get bannerBadge =>
      _t('Старт в Алматы', 'Алматыда бастау', 'Starting in Almaty');
  String get bannerTitle => _t('Заказ еды в KUNDE', 'KUNDE-де тамақ тапсырысы',
      'Food ordering in KUNDE');
  String get bannerBody => _t(
      'Рестораны Алматы в одном приложении. Запуск готовится.',
      'Алматы мейрамханалары бір қосымшада. Іске қосу дайындалуда.',
      'Almaty restaurants in one app. Launch in preparation.');
  String get bannerCta => _t('Найти', 'Іздеу', 'Search');
  String get quickOrders => _t('Мои заказы', 'Тапсырыстарым', 'My orders');
  String get quickFavorites => _t('Избранное', 'Таңдаулылар', 'Favorites');
  String get quickPromo => _t('Скидки и промо', 'Жеңілдіктер', 'Deals & promo');
  String get quickPay => 'KUNDE Pay';
  String get nearbyTitle => _t('Рядом с вами', 'Жаныңызда', 'Near you');
  String get nearbyEmptyTitle => _t(
      'Пока нет ресторанов', 'Әзірге мейрамханалар жоқ', 'No restaurants yet');
  String get nearbyEmptyBody => _t(
      'Партнёры в Алматы ещё не подключены. Мы покажем их здесь, когда они будут опубликованы.',
      'Алматыдағы серіктестер әлі қосылмаған. Жарияланғанда осында көрсетеміз.',
      'Partners in Almaty are not connected yet. We will show them here once published.');
  String get close => _t('Закрыть', 'Жабу', 'Close');
}
