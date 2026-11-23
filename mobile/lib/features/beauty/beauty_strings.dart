import '../../core/localization/kunde_formats.dart';
import '../../core/localization/kunde_localizations.dart';

/// Strings of Beauty & Care (RU/KK/EN) and locale-aware formatting of money, durations and dates.
extension BeautyStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get bHomeTitle =>
      _t('Красота и уход', 'Сұлулық және күтім', 'Beauty & Care');
  String get bHomeSubtitle => _t(
      'Салоны, мастера и уходовые услуги',
      'Салондар, шеберлер және күтім қызметтері',
      'Salons, masters and care services');
  String get bCityAlmaty => _t('Алматы', 'Алматы', 'Almaty');
  String get bSearchHint => _t('Найти салон, мастера или услугу',
      'Салон, шебер немесе қызмет іздеу', 'Find a salon, master or service');
  String get bMore => _t('Ещё', 'Тағы', 'More');
  String get bAllCategories =>
      _t('Все категории', 'Барлық санаттар', 'All categories');
  String bPromoBanner(int percent) => _t(
      'Уход за собой\nсо скидкой до $percent%',
      'Күтімге $percent%-ға\nдейін жеңілдік',
      'Self-care with\nup to $percent% off');
  String get bTabHome => _t('Главная', 'Басты', 'Home');
  String get bTabCatalog => _t('Каталог', 'Каталог', 'Catalog');
  String get bTabPromos => _t('Акции', 'Акциялар', 'Offers');
  String get bTabProfile => _t('Профиль', 'Профиль', 'Profile');

  String get bSalonsTitle =>
      _t('Салоны красоты', 'Сұлулық салондары', 'Beauty salons');
  String get bFilterAll => _t('Все', 'Барлығы', 'All');
  String get bFilterNearby => _t('Рядом', 'Жақын', 'Nearby');
  String get bFilterRating => _t('Рейтинг', 'Рейтинг', 'Top rated');
  String get bFilterPromo => _t('Акции', 'Акциялар', 'Offers');
  String bFound(int n) => _t('Найдено: $n', 'Табылды: $n', 'Found: $n');
  String get bFilters => _t('Фильтры', 'Сүзгілер', 'Filters');
  String get bPrice => _t('Цена, ₸', 'Бағасы, ₸', 'Price, ₸');
  String get bFrom => _t('от', 'бастап', 'from');
  String get bTo => _t('до', 'дейін', 'to');
  String get bVerifiedOnly => _t('Только проверенные организации',
      'Тек тексерілген ұйымдар', 'Verified organizations only');
  String get bDistance => _t('Расстояние', 'Қашықтық', 'Distance');
  String get bDistanceNeedsLocation => _t(
      'Включите геолокацию, чтобы фильтровать по расстоянию.',
      'Қашықтық бойынша сүзу үшін геолокацияны қосыңыз.',
      'Turn on location to filter by distance.');
  String bKm(int meters) => meters < 1000
      ? _t('$meters м', '$meters м', '$meters m')
      : _t(
          '${(meters / 1000).toStringAsFixed(1)} км',
          '${(meters / 1000).toStringAsFixed(1)} км',
          '${(meters / 1000).toStringAsFixed(1)} km');
  String get bApply => _t('Применить', 'Қолдану', 'Apply');
  String get bReset => _t('Сбросить', 'Тастау', 'Reset');
  String get bSearchSalons => _t('Поиск салонов', 'Салондарды іздеу', 'Search');
  String get bNothingFound =>
      _t('Ничего не найдено', 'Ештеңе табылмады', 'Nothing found');
  String get bNothingFoundHint => _t(
      'Измените запрос или фильтры.',
      'Сұрауды немесе сүзгілерді өзгертіңіз.',
      'Change the query or the filters.');
  String get bLoadFailed =>
      _t('Не удалось загрузить', 'Жүктеу мүмкін болмады', 'Could not load');
  String get bFavoriteNeedsLogin => _t('Войдите, чтобы пользоваться избранным.',
      'Таңдаулыны пайдалану үшін кіріңіз.', 'Sign in to use favorites.');

  String get bServicesTitle => _t('Услуги', 'Қызметтер', 'Services');
  String get bMastersTitle => _t('Мастера', 'Шеберлер', 'Masters');
  String get bReviewsTitle => _t('Отзывы', 'Пікірлер', 'Reviews');
  String get bNoReviews =>
      _t('Отзывов пока нет', 'Пікір әлі жоқ', 'No reviews yet');
  String get bAbout => _t('О салоне', 'Салон туралы', 'About');
  String get bAddress => _t('Адрес', 'Мекенжай', 'Address');
  String get bCancelPolicy =>
      _t('Условия отмены', 'Бас тарту шарттары', 'Cancellation terms');
  String get bIncluded => _t('Что входит', 'Не кіреді', 'What is included');
  String get bPreparation => _t('Подготовка', 'Дайындық', 'Preparation');
  String get bBook => _t('Записаться', 'Жазылу', 'Book');
  String get bShare => _t('Поделиться', 'Бөлісу', 'Share');
  String get bExperienced =>
      _t('Опытные мастера', 'Тәжірибелі шеберлер', 'Experienced masters');
  String get bVerifiedSalon =>
      _t('Проверенный салон', 'Тексерілген салон', 'Verified salon');
  String bReviewsCount(int n) {
    switch (KundeFormats.plural(n, locale)) {
      case PluralCategory.one:
        return _t('$n отзыв', '$n пікір', '$n review');
      case PluralCategory.few:
        return _t('$n отзыва', '$n пікір', '$n reviews');
      case PluralCategory.many:
      case PluralCategory.other:
        return _t('$n отзывов', '$n пікір', '$n reviews');
    }
  }

  String bExperienceYears(int years) =>
      _t('Стаж: $years лет', 'Тәжірибе: $years жыл', '$years years experience');

  String bDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return _t('$m мин', '$m мин', '$m min');
    if (m == 0) return _t('$h ч', '$h сағ', '$h h');
    return _t('$h ч $m мин', '$h сағ $m мин', '$h h $m min');
  }

  String get bPickMaster =>
      _t('Выберите мастера', 'Шеберді таңдаңыз', 'Choose a master');
  String get bAnyMaster => _t('Любой мастер', 'Кез келген шебер', 'Any master');
  String get bAnyMasterSub => _t('Ближайшее свободное время',
      'Ең жақын бос уақыт', 'The earliest free time');
  String bNearest(String when) =>
      _t('Ближайшее: $when', 'Ең жақыны: $when', 'Nearest: $when');
  String get bNoFreeTime =>
      _t('Нет свободного времени', 'Бос уақыт жоқ', 'No free time');

  String get bPickDateTime =>
      _t('Выбор даты и времени', 'Күн мен уақытты таңдау', 'Date and time');
  String get bAvailableTime =>
      _t('Доступное время', 'Қолжетімді уақыт', 'Available time');
  String get bContinue => _t('Продолжить', 'Жалғастыру', 'Continue');
  String get bNoSlots => _t('На этот день нет свободного времени',
      'Бұл күні бос уақыт жоқ', 'No free time on this day');

  String get bCheckoutTitle =>
      _t('Оформление записи', 'Жазылуды рәсімдеу', 'Booking summary');
  String get bStepService => _t('Услуга', 'Қызмет', 'Service');
  String get bStepTime => _t('Время', 'Уақыт', 'Time');
  String get bStepPayment => _t('Оплата', 'Төлем', 'Payment');
  String get bStepDone => _t('Готово', 'Дайын', 'Done');
  String get bSalon => _t('Салон', 'Салон', 'Salon');
  String get bDateTimeRow =>
      _t('Дата и время', 'Күні мен уақыты', 'Date & time');
  String get bMaster => _t('Мастер', 'Шебер', 'Master');
  String get bPaymentMethod => _t('Способ оплаты', 'Төлем тәсілі', 'Payment');
  String get bPayOnSite => _t('В салоне', 'Салонда', 'At the salon');
  String get bPayDevNote => _t(
      'Демо-режим: онлайн-оплата пока не подключена, оплата в салоне после визита.',
      'Демо режим: онлайн төлем әлі қосылмаған, төлем салонда визиттен кейін.',
      'Demo mode: online payment is not connected yet; you pay at the salon after the visit.');
  String get bTotal => _t('Итого', 'Барлығы', 'Total');
  String bDiscountLine(int percent) =>
      _t('Скидка $percent%', 'Жеңілдік $percent%', 'Discount $percent%');
  String bConfirm(String price) =>
      _t('Записаться · $price', 'Жазылу · $price', 'Book · $price');
  String get bPriceChanged => _t(
      'Цена изменилась. Проверьте сумму и подтвердите снова.',
      'Баға өзгерді. Соманы тексеріп, қайта растаңыз.',
      'The price has changed. Check the amount and confirm again.');

  String get bConfirmedTitle =>
      _t('Запись подтверждена!', 'Жазылу расталды!', 'Booking confirmed!');
  String get bAddToCalendar =>
      _t('Добавить в календарь', 'Күнтізбеге қосу', 'Add to calendar');
  String get bRoute => _t('Построить маршрут', 'Бағыт салу', 'Get directions');
  String get bDone => _t('Готово', 'Дайын', 'Done');
  String get bCannotOpen => _t('Не удалось открыть приложение',
      'Қолданбаны ашу мүмкін болмады', 'Could not open the app');

  String get bPromosTitle =>
      _t('Акции и скидки', 'Акциялар мен жеңілдіктер', 'Offers and discounts');
  String get bNoPromos => _t('Сейчас нет активных акций',
      'Қазір белсенді акциялар жоқ', 'No active offers right now');
  String bPromoUntil(String date) =>
      _t('до $date', '$date дейін', 'until $date');
  String get bMyBookings =>
      _t('Мои записи', 'Менің жазылуларым', 'My bookings');
  String get bFavorites => _t('Избранное', 'Таңдаулы', 'Favorites');
  String get bFavoritesEmpty =>
      _t('В избранном пока пусто', 'Таңдаулы әзірше бос', 'No favorites yet');

  static const _weekdaysRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _weekdaysKk = ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сн', 'Жк'];
  static const _weekdaysEn = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  /// Short weekday names, Monday first.
  List<String> get bWeekdays => switch (locale.languageCode) {
        'kk' => _weekdaysKk,
        'en' => _weekdaysEn,
        _ => _weekdaysRu,
      };

  static const _monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь'
  ];
  static const _monthsRuGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря'
  ];
  static const _monthsKk = [
    'Қаңтар',
    'Ақпан',
    'Наурыз',
    'Сәуір',
    'Мамыр',
    'Маусым',
    'Шілде',
    'Тамыз',
    'Қыркүйек',
    'Қазан',
    'Қараша',
    'Желтоқсан'
  ];
  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  /// «Ноябрь 2026».
  String bMonthYear(DateTime month) {
    final names = switch (locale.languageCode) {
      'kk' => _monthsKk,
      'en' => _monthsEn,
      _ => _monthsRu,
    };
    return '${names[month.month - 1]} ${month.year}';
  }

  /// «20 ноября» / «20 қараша» / «Nov 20».
  String bDay(DateTime day) => switch (locale.languageCode) {
        'kk' => '${day.day} ${_monthsKk[day.month - 1].toLowerCase()}',
        'en' => '${_monthsEn[day.month - 1].substring(0, 3)} ${day.day}',
        _ => '${day.day} ${_monthsRuGenitive[day.month - 1]}',
      };

  String bTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// «20 ноября, 14:00».
  String bDayTime(DateTime t) => '${bDay(t)}, ${bTime(t)}';

  /// Whole tenge without a trailing «,00» («25 000 ₸»).
  String bMoney(int minor) {
    final text = KundeFormats.money(minor, 'KZT', locale);
    return text.replaceFirst(RegExp(r'[.,]00(?=\D*$)'), '');
  }

  String bFromPrice(int minor, {bool from = true}) =>
      from ? '$bFrom ${bMoney(minor)}' : bMoney(minor);
}
