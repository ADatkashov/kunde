import 'package:flutter/widgets.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/leisure_api.dart';

/// Strings of KUNDE Leisure (RU/KK/EN) plus locale-aware date helpers (the shared helpers are Russian only).
extension LeisureStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get lzTitle => _t('Досуг и развлечения', 'Демалыс және ойын-сауық',
      'Leisure and entertainment');
  String get lzSubtitle => _t(
      'Кино, мероприятия, активный отдых и развлечения для всей семьи',
      'Кино, іс-шаралар, белсенді демалыс және бүкіл отбасыға арналған ойын-сауық',
      'Cinema, events, outdoor fun and entertainment for the whole family');
  String get lzSearchHint =>
      _t('Найти развлечение', 'Ойын-сауық іздеу', 'Search entertainment');
  // ---- KUNDE Events & Tickets (same screens, other product) ----------------------------------------------------------------
  String get evTitle => _t('События', 'Іс-шаралар', 'Events');
  String get evSubtitle => _t(
      'Концерты, кино, театр, спорт и фестивали Алматы',
      'Алматыдағы концерттер, кино, театр, спорт және фестивальдер',
      'Concerts, cinema, theatre, sports and festivals in Almaty');
  String get evSearchHint =>
      _t('Найти событие', 'Іс-шара іздеу', 'Search events');
  String get gsHint => _t(
      'События и досуг: концерт, квест, боулинг…',
      'Іс-шаралар және демалыс: концерт, квест…',
      'Events & leisure: concert, quest, bowling…');
  String get gsBoth => _t('Найдено в двух разделах', 'Екі бөлімнен табылды',
      'Found in two sections');
  String get gsNone => _t(
      'Ничего не найдено в «События» и «Досуг»',
      '«Іс-шаралар» және «Демалыс» бөлімдерінен ештеңе табылмады',
      'Nothing found in Events or Leisure');
  String get lzCity => _t('Алматы', 'Алматы', 'Almaty');
  String get lzCityMore => _t('Другие города появятся позже',
      'Басқа қалалар кейінірек қосылады', 'More cities are coming later');
  String get lzAll => _t('Все', 'Барлығы', 'All');
  String get lzToday => _t('Сегодня', 'Бүгін', 'Today');
  String get lzWeekend => _t('На выходные', 'Демалыс күндері', 'This weekend');
  String get lzFamily => _t('Для всей семьи', 'Бүкіл отбасыға', 'For families');
  String get lzPopular => _t('Популярное', 'Танымал', 'Popular');
  String get lzNearby => _t('Рядом с вами', 'Жақын маңда', 'Near you');
  String get lzFavorites => _t('Избранное', 'Таңдаулылар', 'Favourites');
  String get lzSeeAll => _t('Смотреть все', 'Барлығын көру', 'See all');
  String get lzMyTickets => _t('Мои билеты', 'Менің билеттерім', 'My tickets');
  String get lzNearbyAsk => _t(
      'Показать рядом со мной', 'Маған жақынын көрсету', 'Show places near me');
  String get lzNearbyDenied => _t(
      'Нет доступа к геолокации. Разрешите её в настройках, чтобы увидеть ближайшие места.',
      'Геолокацияға рұқсат жоқ. Жақын орындарды көру үшін параметрлерде рұқсат беріңіз.',
      'Location access is off. Allow it in settings to see nearby places.');
  String get lzFilters => _t('Фильтры', 'Сүзгілер', 'Filters');
  String get lzDistrict => _t('Район', 'Аудан', 'District');
  String get lzAnyDistrict =>
      _t('Любой район', 'Кез келген аудан', 'Any district');
  String get lzSort => _t('Сортировка', 'Сұрыптау', 'Sort');
  String get lzSortTime => _t('По времени', 'Уақыт бойынша', 'By time');
  String get lzSortPrice => _t('По цене', 'Баға бойынша', 'By price');
  String get lzSortPopular =>
      _t('По популярности', 'Танымалдығы бойынша', 'By popularity');
  String get lzSortDistance =>
      _t('По расстоянию', 'Қашықтық бойынша', 'By distance');
  String lzFound(int n) => _t('Найдено: $n', 'Табылды: $n', 'Found: $n');
  String get lzReset => _t('Сбросить', 'Тастау', 'Reset');
  String get lzApply => _t('Применить', 'Қолдану', 'Apply');
  String get lzDate => _t('Дата', 'Күні', 'Date');
  String get lzAnyDate => _t('Любая дата', 'Кез келген күн', 'Any date');
  String get lzPrice => _t('Цена, ₸', 'Баға, ₸', 'Price, ₸');
  String get lzPriceFrom => _t('от', 'бастап', 'from');
  String get lzPriceTo => _t('до', 'дейін', 'to');
  String get lzAge => _t('Возраст гостя', 'Қонақ жасы', 'Guest age');
  String get lzGuests => _t('Гостей', 'Қонақ', 'Guests');
  String get lzOnlyAvailable => _t('Только со свободными местами',
      'Тек бос орындары бар', 'Only with free places');
  String get lzFamilyOnly =>
      _t('Семейный формат', 'Отбасылық формат', 'Family friendly');
  String get lzRatingFrom =>
      _t('Рейтинг от 4', 'Рейтинг 4-тен', 'Rating 4 and up');
  String get lzRadius =>
      _t('Не дальше 10 км', '10 км-ден алыс емес', 'Within 10 km');
  String get lzNothing =>
      _t('Ничего не найдено', 'Ештеңе табылмады', 'Nothing found');
  String get lzNothingBody => _t(
      'Измените фильтры или запрос. Площадки появляются после проверки администратором.',
      'Сүзгілерді немесе сұранысты өзгертіңіз. Алаңдар әкімші тексергеннен кейін шығады.',
      'Change the filters or the query. Venues appear after an administrator review.');
  String get lzUnavailable => _t('Досуг временно недоступен',
      'Демалыс уақытша қолжетімсіз', 'Leisure is temporarily unavailable');
  String get lzUnavailableBody => _t(
      'Новые бронирования сейчас не принимаются. Уже купленные билеты можно открыть в разделе «Мои билеты».',
      'Жаңа брондау қазір қабылданбайды. Сатып алынған билеттерді «Менің билеттерім» бөлімінен ашыңыз.',
      'New bookings are paused. Tickets you already bought stay available in My tickets.');
  String get lzRetry => _t('Повторить', 'Қайталау', 'Retry');
  String get lzLoadError => _t('Не удалось загрузить данные',
      'Деректерді жүктеу мүмкін болмады', 'Could not load data');
  String get lzDemoNote => _t(
      'DEV-режим: площадки, цены и места синтетические. Реальных платежей нет.',
      'DEV режимі: алаңдар, бағалар және орындар синтетикалық. Нақты төлем жоқ.',
      'DEV mode: venues, prices and places are synthetic. No real payments.');
  String get lzNoPhoto =>
      _t('Фото появится позже', 'Фото кейін шығады', 'Photo coming later');

  // event
  String get lzSchedule => _t('Расписание', 'Кесте', 'Schedule');
  String get lzAbout => _t('О месте', 'Орын туралы', 'About');
  String get lzReviews => _t('Отзывы', 'Пікірлер', 'Reviews');
  String lzReviewsCount(int n) => _t('$n отзывов', '$n пікір', '$n reviews');
  String get lzNoReviews =>
      _t('Отзывов пока нет', 'Әзірге пікір жоқ', 'No reviews yet');
  String get lzAddress => _t('Адрес', 'Мекенжай', 'Address');
  String get lzRules =>
      _t('Правила посещения', 'Келу ережелері', 'Visiting rules');
  String get lzCancelTerms =>
      _t('Условия отмены', 'Бас тарту шарттары', 'Cancellation terms');
  String get lzOrganizer => _t('Организатор', 'Ұйымдастырушы', 'Organiser');
  String get lzDuration => _t('Длительность', 'Ұзақтығы', 'Duration');
  String get lzTickets => _t('Билеты', 'Билеттер', 'Tickets');
  String lzAgeLimit(int age) => '$age+';
  String lzFree(int n) => n <= 0
      ? _t('Мест нет', 'Орын жоқ', 'Sold out')
      : _t('Свободно: $n', 'Бос: $n', 'Free: $n');
  String get lzNoSessions => _t('На выбранные дни нет сеансов',
      'Таңдалған күндерге сеанс жоқ', 'No sessions on the chosen days');
  String lzFromPrice(String price) =>
      _t('от $price', '$price бастап', 'from $price');
  String get lzManualConfirm => _t(
      'Бронь подтверждает организатор. До подтверждения деньги только резервируются, билет появится после подтверждения.',
      'Броньды ұйымдастырушы растайды. Растағанға дейін ақша тек резервте, билет растаудан кейін шығады.',
      'The organiser confirms the booking. Money is only reserved until then and the ticket appears after confirmation.');
  String get lzChooseSeats =>
      _t('Выбрать места', 'Орын таңдау', 'Choose seats');
  String get lzBook => _t('Забронировать', 'Брондау', 'Book');
  String get lzChooseTickets =>
      _t('Выбрать билеты', 'Билет таңдау', 'Choose tickets');
  String get lzMap => _t('Карта', 'Карта', 'Map');
  String get lzMapSoon => _t(
      'Карта появится после подключения картографического сервиса.',
      'Карта картографиялық қызмет қосылғаннан кейін шығады.',
      'The map appears once a map provider is connected.');
  String get lzFavorite => _t('В избранное', 'Таңдаулыға', 'Favourite');
  String get lzSignIn => _t('Войдите, чтобы продолжить',
      'Жалғастыру үшін кіріңіз', 'Sign in to continue');
  String get lzDay => _t('День', 'Күн', 'Day');
  String get lzSessionTime => _t('Время', 'Уақыт', 'Time');
  String get lzTicketsFor =>
      _t('Билеты на сеанс', 'Сеансқа билеттер', 'Tickets for the session');
  String get lzPerBooking => _t('за бронь', 'брон үшін', 'per booking');
  String get lzPerPerson => _t('за человека', 'адамға', 'per person');
  String get lzGuestsInGroup =>
      _t('Сколько гостей', 'Қанша қонақ', 'How many guests');

  // seats
  String get lzSeatsTitle => _t('Выбор мест', 'Орын таңдау', 'Choose seats');
  String get lzSeatFree => _t('Свободно', 'Бос', 'Free');
  String get lzSeatSelected => _t('Выбрано', 'Таңдалды', 'Selected');
  String get lzSeatTaken => _t('Занято', 'Бос емес', 'Taken');
  String get lzScreen => _t('Экран', 'Экран', 'Screen');
  String lzSelectedSeats(int n) =>
      _t('Выбрано: $n мест', 'Таңдалды: $n орын', 'Selected: $n seats');
  String get lzNoneSelected => _t('Выберите места на схеме',
      'Схемадан орындарды таңдаңыз', 'Choose seats on the plan');
  String get lzContinue => _t('Продолжить', 'Жалғастыру', 'Continue');
  String lzSeatSemantics(
          String label, String zone, String state, String price) =>
      _t(
          'Место $label, $zone, $state, $price',
          'Орын $label, $zone, $state, $price',
          'Seat $label, $zone, $state, $price');
  String lzZone(String zone) =>
      zone == 'VIP' ? 'VIP' : _t('стандарт', 'стандарт', 'standard');
  String get lzMaxSeats => _t('Не больше 8 мест за раз',
      'Бір рет 8 орыннан артық емес', 'No more than 8 seats at a time');

  // booking
  String get lzBooking => _t('Бронирование', 'Брондау', 'Booking');
  String get lzStepSession => _t('Сеанс', 'Сеанс', 'Session');
  String get lzStepSeats => _t('Места', 'Орындар', 'Seats');
  String get lzStepPurchase => _t('Покупка', 'Сатып алу', 'Purchase');
  String get lzYourOrder => _t('Ваш заказ', 'Тапсырысыңыз', 'Your order');
  String get lzCost => _t('Стоимость', 'Құны', 'Cost');
  String get lzTotal => _t('Итого', 'Барлығы', 'Total');
  String lzTicketsLine(int n, String unit, String sum) => '$n × $unit = $sum';
  String get lzHoldLeft => _t('Места закреплены за вами на',
      'Орындар сізге бекітілген', 'Places are held for you for');
  String get lzHoldExpired => _t(
      'Время удержания истекло. Выберите места заново.',
      'Ұстау уақыты аяқталды. Орындарды қайта таңдаңыз.',
      'The hold has expired. Choose places again.');
  String lzAgeConfirm(int age) => _t(
      'Подтверждаю, что всем гостям не меньше $age лет',
      'Барлық қонақтардың жасы кемінде $age екенін растаймын',
      'I confirm every guest is at least $age years old');
  String lzPay(String sum) => _t('Оплатить $sum', '$sum төлеу', 'Pay $sum');
  String lzReserve(String sum) =>
      _t('Забронировать · $sum', 'Брондау · $sum', 'Reserve · $sum');
  String get lzSafeNote => _t('Тестовая оплата: деньги не списываются',
      'Тестілік төлем: ақша алынбайды', 'Test payment: no money is charged');
  String get lzPaymentTitle => _t('Оплата', 'Төлем', 'Payment');
  String get lzTestCard =>
      _t('Тестовая карта (DEV)', 'Тестілік карта (DEV)', 'Test card (DEV)');
  String get lzTestCardNote => _t(
      'Без реальных списаний и без ввода данных карты',
      'Нақты есептен шығару жоқ, карта деректері керек емес',
      'No real charge and no card details');
  String get lzPayOnSite =>
      _t('Оплата на месте', 'Орнында төлеу', 'Pay on site');
  String get lzPayOnSiteNote => _t(
      'Оплатите на входе, деньги сейчас не списываются',
      'Кіреберісте төлеңіз, қазір ақша алынбайды',
      'Pay at the entrance, nothing is charged now');
  String get lzNoRealPayments => _t(
      'Банковские карты и кошельки подключатся только после согласования платёжного провайдера.',
      'Банк карталары мен әмияндар төлем провайдері келісілгеннен кейін қосылады.',
      'Bank cards and wallets will be added once a payment provider is approved.');

  // ticket
  String get lzTicketTitle => _t('Мой билет', 'Менің билетім', 'My ticket');
  String get lzTicketNo => _t('Билет №', 'Билет №', 'Ticket no.');
  String get lzGuestsCount => _t('Гостей', 'Қонақ', 'Guests');
  String get lzSeats => _t('Места', 'Орындар', 'Seats');
  String get lzTicketStatus => _t('Статус', 'Мәртебе', 'Status');
  String get lzQrHint => _t('Покажите код на входе',
      'Кодты кіреберісте көрсетіңіз', 'Show this code at the entrance');
  String get lzNoQrYet => _t(
      'QR появится после подтверждения брони организатором',
      'QR броньды ұйымдастырушы растағаннан кейін шығады',
      'The QR appears once the organiser confirms');
  String get lzCopyNo =>
      _t('Скопировать номер', 'Нөмірді көшіру', 'Copy number');
  String get lzCopied =>
      _t('Номер скопирован', 'Нөмір көшірілді', 'Number copied');
  String get lzCancelBooking =>
      _t('Отменить бронь', 'Броньнан бас тарту', 'Cancel booking');
  String get lzCancelConfirm => _t(
      'Отменить бронь? Тестовый платёж будет возвращён полностью.',
      'Броньнан бас тарту керек пе? Тестілік төлем толық қайтарылады.',
      'Cancel the booking? The test payment is refunded in full.');
  String get lzKeep => _t('Оставить', 'Қалдыру', 'Keep');
  String lzFreeUntil(String when) => _t('Бесплатная отмена до $when',
      '$when дейін тегін бас тарту', 'Free cancellation until $when');
  String get lzCancelClosed => _t('Бесплатная отмена уже закрыта',
      'Тегін бас тарту жабылды', 'Free cancellation is closed');
  String get lzRefunded =>
      _t('Возврат оформлен', 'Қайтару жасалды', 'Refund issued');
  String get lzWriteReview =>
      _t('Оставить отзыв', 'Пікір қалдыру', 'Write a review');
  String get lzReviewThanks =>
      _t('Спасибо за отзыв', 'Пікір үшін рақмет', 'Thanks for your review');
  String get lzReviewHint => _t('Что понравилось? (необязательно)',
      'Не ұнады? (міндетті емес)', 'What did you like? (optional)');
  String get lzSend => _t('Отправить', 'Жіберу', 'Send');
  String get lzComplain => _t('Пожаловаться', 'Шағымдану', 'Report a problem');
  String get lzComplainHint =>
      _t('Опишите проблему', 'Мәселені сипаттаңыз', 'Describe the problem');
  String get lzComplainSent =>
      _t('Жалоба отправлена', 'Шағым жіберілді', 'Report sent');
  String get lzTicketTestNote => _t(
      'Тестовый билет DEV: данные синтетические.',
      'DEV тестілік билеті: деректер синтетикалық.',
      'DEV test ticket: data is synthetic.');
  String lzStatus(String status) => switch (status) {
        'VALID' => _t('Действителен', 'Жарамды', 'Valid'),
        'USED' => _t('Использован', 'Пайдаланылған', 'Used'),
        'CANCELLED' => _t('Отменён', 'Бас тартылды', 'Cancelled'),
        'PENDING' =>
          _t('Ждёт подтверждения', 'Растауды күтуде', 'Awaiting confirmation'),
        'CONFIRMED' => _t('Подтверждено', 'Расталды', 'Confirmed'),
        _ => status,
      };

  // orders
  String get lzOrdersTitle =>
      _t('Мои развлечения', 'Менің ойын-сауығым', 'My entertainment');
  String get lzUpcoming => _t('Предстоящие', 'Алдағы', 'Upcoming');
  String get lzCompleted => _t('Завершённые', 'Аяқталған', 'Completed');
  String get lzCancelled => _t('Отменённые', 'Бас тартылған', 'Cancelled');
  String get lzNoOrders =>
      _t('Здесь пока пусто', 'Әзірге бос', 'Nothing here yet');
  String get lzNoOrdersBody => _t(
      'Найдите развлечение и забронируйте билеты — они появятся здесь.',
      'Ойын-сауық тауып, билет брондаңыз — олар осында шығады.',
      'Find something to do and book tickets — they will show up here.');
  String get lzRebook =>
      _t('Забронировать снова', 'Қайта брондау', 'Book again');
  String get lzOpenTicket => _t('Открыть билет', 'Билетті ашу', 'Open ticket');
  String get lzSignInOrders => _t('Войдите, чтобы увидеть свои билеты',
      'Билеттеріңізді көру үшін кіріңіз', 'Sign in to see your tickets');

  String lzError(LeisureFailure f) => switch (f) {
        LeisureFailure.offline => _t(
            'Нет соединения. Данные сохранены, повторите попытку.',
            'Байланыс жоқ. Деректер сақталды, қайталап көріңіз.',
            'No connection. Your choice is kept, try again.'),
        LeisureFailure.sessionExpired => _t(
            'Сессия истекла. Войдите снова.',
            'Сессия аяқталды. Қайта кіріңіз.',
            'Session expired. Sign in again.'),
        LeisureFailure.disabled => lzUnavailableBody,
        LeisureFailure.seatTaken => _t(
            'Это место только что заняли. Выберите другое.',
            'Бұл орынды жаңа ғана алды. Басқасын таңдаңыз.',
            'That seat was just taken. Choose another.'),
        LeisureFailure.notEnoughPlaces => _t('Свободных мест не хватает.',
            'Бос орын жеткіліксіз.', 'Not enough free places.'),
        LeisureFailure.holdExpired => lzHoldExpired,
        LeisureFailure.sessionClosed => _t('Сеанс уже недоступен.',
            'Сеанс енді қолжетімсіз.', 'The session is no longer available.'),
        LeisureFailure.paymentUnsupported => _t(
            'Этот способ оплаты недоступен.',
            'Бұл төлем әдісі қолжетімсіз.',
            'This payment method is unavailable.'),
        LeisureFailure.ageRequired => _t('Подтвердите возраст гостей.',
            'Қонақтардың жасын растаңыз.', 'Confirm the age of the guests.'),
        LeisureFailure.guestsLimit => _t(
            'Слишком много гостей для этого события.',
            'Бұл іс-шара үшін қонақ тым көп.',
            'Too many guests for this event.'),
        LeisureFailure.tooManyBookings => _t(
            'Слишком много предстоящих броней.',
            'Алдағы брондар тым көп.',
            'Too many upcoming bookings.'),
        LeisureFailure.cancellationClosed => lzCancelClosed,
        LeisureFailure.ticketUsed => _t('Билет уже использован.',
            'Билет пайдаланылған.', 'The ticket was already used.'),
        LeisureFailure.alreadyDone =>
          _t('Это уже отправлено.', 'Бұл бұрын жіберілген.', 'Already sent.'),
        LeisureFailure.notAllowed => _t(
            'Отзыв возможен после сеанса.',
            'Пікір сеанстан кейін мүмкін.',
            'A review is possible after the session.'),
        LeisureFailure.invalid => _t(
            'Проверьте выбор и повторите.',
            'Таңдауды тексеріп, қайталаңыз.',
            'Check your choice and try again.'),
        LeisureFailure.notFound =>
          _t('Не найдено.', 'Табылмады.', 'Not found.'),
        LeisureFailure.other => _t(
            'Не удалось выполнить действие. Попробуйте позже.',
            'Әрекетті орындау мүмкін болмады. Кейінірек қайталаңыз.',
            'The action failed. Try again later.'),
      };

  // dates
  static const _wdRu = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  static const _wdKk = ['дс', 'сс', 'ср', 'бс', 'жм', 'сб', 'жс'];
  static const _wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _moRu = [
    'янв',
    'фев',
    'мар',
    'апр',
    'мая',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек'
  ];
  static const _moKk = [
    'қаң',
    'ақп',
    'нау',
    'сәу',
    'мам',
    'мау',
    'шіл',
    'там',
    'қыр',
    'қаз',
    'қар',
    'жел'
  ];
  static const _moEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String weekday(DateTime d) => switch (locale.languageCode) {
        'kk' => _wdKk[d.weekday - 1],
        'en' => _wdEn[d.weekday - 1],
        _ => _wdRu[d.weekday - 1],
      };

  String month(DateTime d) => switch (locale.languageCode) {
        'kk' => _moKk[d.month - 1],
        'en' => _moEn[d.month - 1],
        _ => _moRu[d.month - 1],
      };

  String lzDayMonth(DateTime d) => '${d.day} ${month(d)}';
  String lzWeekdayDay(DateTime d) => '${weekday(d)}, ${d.day} ${month(d)}';
  String lzClock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String lzWhen(DateTime d) => '${lzWeekdayDay(d)} · ${lzClock(d)}';
  String lzMinutes(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    final hu = _t('ч', 'сағ', 'h');
    final mu = _t('мин', 'мин', 'min');
    if (h == 0) return '$m $mu';
    return r == 0 ? '$h $hu' : '$h $hu $r $mu';
  }
}

KundeLocalizations lzL10n(BuildContext context) =>
    Localizations.of<KundeLocalizations>(context, KundeLocalizations) ??
    const KundeLocalizations(Locale('ru'));
