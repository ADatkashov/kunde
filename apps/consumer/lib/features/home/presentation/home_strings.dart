import 'package:kunde_localization/kunde_localizations.dart';

/// Strings of the Super App home screen (RU/KK/EN). Kept next to the screen so
/// the shared localization file stays small.
extension HomeStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get homeCity => _t('Алматы', 'Алматы', 'Almaty');
  String get homeGreeting => _t('Добро пожаловать', 'Қош келдіңіз', 'Welcome');
  String get assistantPrompt =>
      _t('Чем помочь?', 'Қалай көмектесемін?', 'How can I help?');
  String get assistantMessage => _t('Сообщение', 'Хабарлама', 'Message');
  String get assistantSend => _t('Отправить', 'Жіберу', 'Send');
  List<String> get assistantSuggestions => [
        _t('Найти ресторан', 'Мейрамхана табу', 'Find a restaurant'),
        _t('Найти услугу', 'Қызмет табу', 'Find a service'),
        _t('Записаться на услугу', 'Қызметке жазылу', 'Book a service'),
        _t('Получить рекомендации', 'Ұсыныс алу', 'Get recommendations'),
      ];
  String get orderDetails => _t('Заказ', 'Тапсырыс', 'Order');
  String get appearance => _t('Тема', 'Тақырып', 'Appearance');
  String get lightAppearance => _t('Светлая', 'Ашық', 'Light');
  String get darkAppearance => _t('Тёмная', 'Күңгірт', 'Dark');

  String get homeTagline => _t(
        'Ваше суперприложение для жизни каждый день',
        'Күнделікті өмірге арналған суперқосымша',
        'Your super app for everyday life',
      );
  String get homeLocationLabel =>
      _t('Город: Алматы', 'Қала: Алматы', 'City: Almaty');
  String get homeSearchHint => _t(
        'Найти сервис, услугу или товар',
        'Қызметті немесе тауарды табу',
        'Find a service or product',
      );
  String get homeNotifications =>
      _t('Уведомления', 'Хабарландырулар', 'Notifications');
  String get homeNotificationsUnavailable => _t(
        'Уведомления пока недоступны.',
        'Хабарландырулар әзірге қолжетімсіз.',
        'Notifications are not available yet.',
      );
  String get homeRewards =>
      _t('Акции и бонусы', 'Науқандар мен бонустар', 'Offers and rewards');
  String get nearbyRestaurants =>
      _t('Рестораны', 'Мейрамханалар', 'Restaurants');
  String get nearbyStores => _t('Магазины', 'Дүкендер', 'Groceries');
  String get homeSoon => _t('Скоро', 'Жақында', 'Soon');
  String get homeAiTitle => 'KUNDE AI';
  String get homeAiSubtitle => _t(
        'Ваш умный помощник в повседневной жизни',
        'Күнделікті өмірдегі ақылды көмекшіңіз',
        'Your smart everyday assistant',
      );
  String get homeAiAsk => _t('Спросить', 'Сұрау', 'Ask');
  String get homeAiUnavailable => _t(
        'KUNDE AI пока недоступен. Он появится после утверждения.',
        'KUNDE AI әзірге қолжетімсіз. Бекітілгеннен кейін шығады.',
        'KUNDE AI is not available yet. It will appear once approved.',
      );
  String get catFood => _t('Еда', 'Тамақ', 'Food');
  String get catServices => _t('Услуги', 'Қызметтер', 'Services');
  String get catGroceries => _t('Продукты', 'Азық-түлік', 'Groceries');
  String get catFlowers =>
      _t('Цветы и подарки', 'Гүлдер мен сыйлықтар', 'Flowers & gifts');
  String get catRides => _t('Поездки', 'Сапарлар', 'Rides');
  String get catDelivery => _t('Доставка', 'Жеткізу', 'Delivery');
  String get catHome => _t('Дом и быт', 'Үй және тұрмыс', 'Home services');
  String get catBeauty => _t('Красота', 'Сұлулық', 'Beauty');
  String get catHealth => _t('Здоровье', 'Денсаулық', 'Health');
  String get catAuto => _t('Авто', 'Авто', 'Auto');
  String get catEducation => _t('Обучение', 'Білім', 'Education');
  String get catEvents => _t('События', 'Іс-шаралар', 'Events');
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
        'This service is not connected yet and orders are unavailable. Food ordering in Almaty launches first.',
      );
  String get foodPreparingBody => _t(
        'Заказ еды в Алматы готовится к запуску. Рестораны появятся здесь после подключения.',
        'Алматыда тамақ тапсырысы іске қосуға дайындалуда. Мейрамханалар қосылғаннан кейін осында шығады.',
        'Food ordering in Almaty is being prepared. Restaurants will appear here once connected.',
      );
  String get searchUnavailable => _t(
        'Поиск заработает, когда сервисы будут запущены.',
        'Қызметтер іске қосылғанда іздеу жұмыс істейді.',
        'Search will work once services are launched.',
      );
  String get bannerBadge =>
      _t('Старт в Алматы', 'Алматыда бастау', 'Starting in Almaty');
  String get bannerTitle => _t(
        'Заказ еды\nв KUNDE',
        'KUNDE-де тамақ тапсырысы',
        'Food ordering in KUNDE',
      );
  String get bannerBody => _t(
        'Рестораны Алматы в одном приложении. Запуск готовится.',
        'Алматы мейрамханалары бір қосымшада. Іске қосу дайындалуда.',
        'Almaty restaurants in one app. Launch in preparation.',
      );
  String get bannerBodyLive => _t(
        'Рестораны Алматы в одном приложении. Демо-режим: тестовые рестораны, оплата и доставка имитируются.',
        'Алматы мейрамханалары бір қосымшада. Демо режим: сынақ мейрамханалары, төлем мен жеткізу имитацияланады.',
        'Almaty restaurants in one app. Demo mode: test restaurants, mock payment and simulated delivery.',
      );
  String get bannerSubtitle => _t(
        'Любимые рестораны Алматы с доставкой',
        'Алматының сүйікті мейрамханаларынан жеткізу',
        'Delivery from your favourite Almaty restaurants',
      );
  String get catalogTitle =>
      _t('Еда и услуги', 'Тамақ және қызметтер', 'Food and services');
  String get catalogSearchHint => _t(
      'Найти ресторан, блюдо или услугу',
      'Мейрамхана, тағам немесе қызмет табу',
      'Find a restaurant, dish or service');
  String get catalogClosed => _t('Закрыто', 'Жабық', 'Closed');
  String catalogEta(int min, int max) =>
      _t('$min–$max мин', '$min–$max мин', '$min–$max min');
  String catalogMinOrder(String amount) =>
      _t('Мин. заказ $amount', 'Мин. тапсырыс $amount', 'Min. order $amount');
  String get catalogRestaurantsError => _t('Не удалось загрузить рестораны',
      'Мейрамханаларды жүктеу мүмкін болмады', 'Could not load restaurants');
  String get catalogOpenOnly => _t('Открыто сейчас', 'Қазір ашық', 'Open now');
  String get catalogSubtitle => _t(
        'Рестораны, доставка и услуги в Алматы',
        'Алматыдағы мейрамханалар, жеткізу және қызметтер',
        'Restaurants, delivery and services in Almaty',
      );
  String get ordersAll => _t('Все', 'Барлығы', 'All');
  String get ordersActive => _t('Активные', 'Белсенді', 'Active');
  String get ordersCompleted => _t('Завершённые', 'Аяқталған', 'Completed');
  String get ordersFilterEmpty => _t(
        'В этой категории заказов пока нет',
        'Бұл санатта тапсырыс жоқ',
        'No orders in this category',
      );
  String get bannerCtaLive => _t('Заказать', 'Тапсырыс беру', 'Order');
  String get bannerCta => _t('Найти', 'Іздеу', 'Search');
  String get quickOrders => _t('Мои заказы', 'Тапсырыстарым', 'My orders');
  String get quickFavorites => _t('Избранное', 'Таңдаулылар', 'Favorites');
  String get quickPromo => _t('Скидки и промо', 'Жеңілдіктер', 'Deals & promo');
  String get quickPay => 'KUNDE Pay';
  String get nearbySeeAll => _t('Смотреть все', 'Барлығын көру', 'See all');
  String get nearbyTitle => _t('Рядом с вами', 'Жаныңызда', 'Near you');
  String get nearbyEmptyTitle => _t(
        'Пока нет ресторанов',
        'Әзірге мейрамханалар жоқ',
        'No restaurants yet',
      );
  String get nearbyEmptyBody => _t(
        'Партнёры в Алматы ещё не подключены. Мы покажем их здесь, когда они будут опубликованы.',
        'Алматыдағы серіктестер әлі қосылмаған. Жарияланғанда осында көрсетеміз.',
        'Partners in Almaty are not connected yet. We will show them here once published.',
      );
  String get close => _t('Закрыть', 'Жабу', 'Close');
}
