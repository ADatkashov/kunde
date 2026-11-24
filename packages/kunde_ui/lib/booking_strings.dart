import 'package:flutter/widgets.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_api/booking_api.dart';

/// Strings of the Beauty / Home services categories and the shared booking mechanism (RU/KK/EN).
extension BookingStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String healthText(String ru, String kk, String en) => _t(ru, kk, en);

  String get healthSpecialist => _t('Специалист', 'Маман', 'Specialist');
  String get anyHealthSpecialist =>
      _t('Любой специалист', 'Кез келген маман', 'Any specialist');
  String healthSpecialistLine(String name) => '$healthSpecialist · $name';

  // Categories and services
  String get bkBeautyTitle => _t('Красота', 'Сұлулық', 'Beauty');
  String get bkBeautySubtitle => _t(
      'Выберите заведение, услугу, мастера и время.',
      'Мекемені, қызметті, шеберді және уақытты таңдаңыз.',
      'Choose a venue, service, master and time.');
  String get bkBarbers => _t('Барбершопы', 'Барбершоптар', 'Barbershops');
  String get bkBarbersSub => _t('Стрижки, борода, бритьё',
      'Шаш қию, сақал, қырыну', 'Haircuts, beard, shave');
  String get bkBeautySoon => _t(
      'Скоро: парикмахерская, маникюр, косметология.',
      'Жақында: шаштараз, маникюр, косметология.',
      'Coming soon: hair salon, manicure, cosmetology.');
  String get bkHomeTitle => _t('Дом и быт', 'Үй және тұрмыс', 'Home services');
  String get bkHomeSubtitle => _t(
      'Выберите услугу, адрес и удобное время.',
      'Қызметті, мекенжайды және ыңғайлы уақытты таңдаңыз.',
      'Choose a service, address and a convenient time.');
  String get bkCleaning => _t('Уборка', 'Жинау', 'Cleaning');
  String get bkCleaningSub => _t('Поддерживающая, генеральная, после ремонта',
      'Күнделікті, жалпы, жөндеуден кейін', 'Regular, deep, post-renovation');
  String get bkHomeSoon => _t(
      'Скоро: сантехник, электрик, ремонт, сборка мебели.',
      'Жақында: сантехник, электрик, жөндеу, жиһаз құрастыру.',
      'Coming soon: plumber, electrician, repairs, furniture assembly.');
  String get bkAllServicesIntro => _t(
      'Все сервисы KUNDE по категориям. Доступные сейчас отмечены.',
      'KUNDE қызметтері санаттар бойынша. Қазір қолжетімділері белгіленген.',
      'All KUNDE services by category. Available ones are marked.');
  String get bkSoon => _t('Скоро', 'Жақында', 'Soon');
  String get bkDemoNote => _t(
      'DEV-режим: заведения, исполнители и цены синтетические (демо), запись подтверждается автоматически, оплата на месте.',
      'DEV режимі: мекемелер, орындаушылар және бағалар синтетикалық (демо), жазылу автоматты түрде расталады, төлем орнында.',
      'DEV mode: venues, providers and prices are synthetic (demo), bookings are confirmed automatically, pay on site.');

  // Barbershop list / venue
  String get bkBarbersLoadError => _t('Не удалось загрузить барбершопы',
      'Барбершоптарды жүктеу мүмкін болмады', 'Could not load barbershops');
  String get bkNoBarbers => _t(
      'Пока нет барбершопов', 'Әзірге барбершоптар жоқ', 'No barbershops yet');
  String get bkNoVenuesBody => _t(
      'Заведения появятся здесь, когда будут добавлены.',
      'Мекемелер қосылғанда осында шығады.',
      'Venues will appear here once added.');
  String get bkVenueLoadError => _t('Не удалось загрузить заведение',
      'Мекемені жүктеу мүмкін болмады', 'Could not load the venue');
  String get bkClosed => _t('Закрыто', 'Жабық', 'Closed');
  String bkServicesFrom(String price) =>
      _t('Услуги от $price', 'Қызметтер $price бастап', 'Services from $price');
  String get bkServices => _t('Услуги', 'Қызметтер', 'Services');
  String get bkMasters => _t('Мастера', 'Шеберлер', 'Masters');
  String get bkBookAction => _t('Записаться', 'Жазылу', 'Book');
  String get bkUnavailable => _t('Недоступно', 'Қолжетімсіз', 'Unavailable');

  // Booking form
  String get bkBookingTitle => _t('Запись', 'Жазылу', 'Booking');
  String get bkMaster => _t('Мастер', 'Шебер', 'Master');
  String get bkAnyMaster =>
      _t('Любой мастер', 'Кез келген шебер', 'Any master');
  String get bkDate => _t('Дата', 'Күні', 'Date');
  String get bkTime => _t('Время', 'Уақыт', 'Time');
  String get bkYourBooking =>
      _t('Ваша запись', 'Сіздің жазылуыңыз', 'Your booking');
  String bkMasterLine(String name) =>
      _t('Мастер: $name', 'Шебер: $name', 'Master: $name');
  String bkCostOnSite(String price) => _t('Стоимость: $price (оплата на месте)',
      'Құны: $price (төлем орнында)', 'Price: $price (pay on site)');
  String get bkCommentLabel => _t('Комментарий (необязательно)',
      'Пікір (міндетті емес)', 'Comment (optional)');
  String get bkCommentHint => _t(
      'Например: фейд, 3 мм', 'Мысалы: фейд, 3 мм', 'For example: fade, 3 mm');
  String get bkPickTime =>
      _t('Выберите время', 'Уақытты таңдаңыз', 'Choose a time');
  String bkConfirmBook(String price) =>
      _t('Записаться · $price', 'Жазылу · $price', 'Book · $price');
  String get bkNoSlots => _t(
      'На эту дату нет свободного времени. Выберите другой день или мастера.',
      'Бұл күні бос уақыт жоқ. Басқа күнді немесе шеберді таңдаңыз.',
      'No free time on this date. Choose another day or master.');
  String get bkSlotsError => _t('Не удалось загрузить время.',
      'Уақытты жүктеу мүмкін болмады.', 'Could not load times.');
  String get bkRetry => _t('Повторить', 'Қайталау', 'Retry');
  String get bkFormDevNote => _t(
      'DEV-режим: запись подтверждается автоматически, мастер уведомление не получает. Бесплатная отмена до начала услуги.',
      'DEV режимі: жазылу автоматты түрде расталады, шебер хабарлама алмайды. Қызмет басталғанға дейін тегін бас тарту.',
      'DEV mode: the booking is confirmed automatically, the master is not notified. Free cancellation before the service starts.');

  // Cleaning form
  String get bkCleaningTitle => _t('Уборка', 'Жинау', 'Cleaning');
  String get bkCleaningType => _t('Тип уборки', 'Жинау түрі', 'Cleaning type');
  String get bkAddress => _t('Адрес', 'Мекенжай', 'Address');
  String get bkAddressHint => _t('Город, улица, дом, квартира',
      'Қала, көше, үй, пәтер', 'City, street, building, apartment');
  String get bkAddressError => _t(
      'Укажите адрес (не короче 5 символов)',
      'Мекенжайды көрсетіңіз (кемінде 5 таңба)',
      'Enter the address (at least 5 characters)');
  String get bkArea => _t('Площадь, м²', 'Ауданы, м²', 'Area, m²');
  String bkAreaError(int min, int max) => _t(
      'Укажите площадь от $min до $max м²',
      'Ауданды $min–$max м² аралығында көрсетіңіз',
      'Enter an area from $min to $max m²');
  String get bkEstimate =>
      _t('Предварительная стоимость', 'Алдын ала құны', 'Estimated price');
  String get bkEstimateNote => _t(
      'Демонстрационная цена, не является реальным предложением. Итог рассчитывает сервер.',
      'Демонстрациялық баға, нақты ұсыныс емес. Қорытындыны сервер есептейді.',
      'Demo price, not a real offer. The final amount is calculated by the server.');
  String bkEstimateFormula(String base, String perSqm) => _t(
      '$base + $perSqm за м²',
      '$base + 1 м² үшін $perSqm',
      '$base + $perSqm per m²');
  String get bkSubmitRequest =>
      _t('Оформить заявку', 'Өтінім беру', 'Place request');
  String bkSubmitRequestPrice(String price) => _t('Оформить заявку · $price',
      'Өтінім беру · $price', 'Place request · $price');
  String get bkCleaningLoadError => _t(
      'Не удалось загрузить услугу «Уборка»',
      '«Жинау» қызметін жүктеу мүмкін болмады',
      'Could not load the cleaning service');
  String get bkCleaningNone => _t('Уборка пока недоступна',
      'Жинау әзірге қолжетімсіз', 'Cleaning is not available yet');
  String get bkCrew => _t('Исполнитель', 'Орындаушы', 'Crew');
  String get bkCrewSynthetic => _t(
      '(синтетическая бригада)', '(синтетикалық бригада)', '(synthetic crew)');
  String get bkAnyCrew => _t('Любая бригада', 'Кез келген бригада', 'Any crew');
  String get bkCleaningDevNote => _t(
      'DEV-режим: исполнители и цены синтетические, оплата не подключена, заявка подтверждается автоматически. Бесплатная отмена до начала услуги.',
      'DEV режимі: орындаушылар мен бағалар синтетикалық, төлем қосылмаған, өтінім автоматты түрде расталады. Қызмет басталғанға дейін тегін бас тарту.',
      'DEV mode: crews and prices are synthetic, no payment is connected, the request is confirmed automatically. Free cancellation before the service starts.');

  // History, details, cancellation
  String get bkSegmentOrders => _t('Заказы', 'Тапсырыстар', 'Orders');
  String get bkSegmentBookings => _t('Записи', 'Жазылулар', 'Bookings');
  String get bkLoadListError => _t('Не удалось загрузить записи',
      'Жазылуларды жүктеу мүмкін болмады', 'Could not load bookings');
  String get bkEmptyTitle =>
      _t('Записей пока нет', 'Жазылулар әзірге жоқ', 'No bookings yet');
  String get bkEmptyBody => _t(
      'Запишитесь в барбершоп или закажите уборку — запись появится здесь.',
      'Барбершопқа жазылыңыз немесе жинауға тапсырыс беріңіз — жазылу осында шығады.',
      'Book a barbershop or order cleaning — it will appear here.');
  String get bkChooseService =>
      _t('Выбрать услугу', 'Қызметті таңдау', 'Choose a service');
  String get bkUpcoming => _t('Предстоящие', 'Алдағы', 'Upcoming');
  String get bkHistory => _t('История', 'Тарих', 'History');
  String get bkKindBarber => _t('Барбершоп', 'Барбершоп', 'Barbershop');
  String get bkKindCleaning => _t('Уборка', 'Жинау', 'Cleaning');
  String get bkDetailLoadError => _t('Не удалось загрузить запись',
      'Жазылуды жүктеу мүмкін болмады', 'Could not load the booking');
  String get bkBookedTitle =>
      _t('Вы записаны!', 'Сіз жазылдыңыз!', 'You are booked!');
  String get bkBookedBody => _t(
      'Запись сохранена и появится в разделе «Заказы» → «Записи».',
      'Жазылу сақталды және «Тапсырыстар» → «Жазылулар» бөлімінде көрсетіледі.',
      'The booking is saved and appears in Orders → Bookings.');
  String get bkRequestPlacedTitle =>
      _t('Заявка оформлена!', 'Өтінім рәсімделді!', 'Request placed!');
  String get bkRequestPlacedBody => _t(
      'Заявка сохранена и появится в разделе «Заказы» → «Записи».',
      'Өтінім сақталды және «Тапсырыстар» → «Жазылулар» бөлімінде көрсетіледі.',
      'The request is saved and appears in Orders → Bookings.');
  String bkStatus(String status) => switch (status) {
        'PENDING' => _t('Ожидает подтверждения', 'Растауды күтуде',
            'Awaiting confirmation'),
        'CONFIRMED' => _t('Подтверждена', 'Расталды', 'Confirmed'),
        'COMPLETED' => _t('Состоялась', 'Өтті', 'Completed'),
        'CANCELLED' => _t('Отменена', 'Бас тартылды', 'Cancelled'),
        _ => status,
      };
  String get bkStatusPendingHint => _t(
      'Заведение подтвердит запись. Время за вами, пока ждём ответ.',
      'Мекеме жазылуды растайды. Жауап күткенше уақыт сізде.',
      'The venue will confirm. The time is held for you while we wait.');
  String bkCancelReason(String reason) =>
      _t('Причина: $reason', 'Себебі: $reason', 'Reason: $reason');
  String get bkStatusConfirmedHint => _t('Ждём вас в назначенное время.',
      'Белгіленген уақытта күтеміз.', 'See you at the scheduled time.');
  String get bkStatusConfirmedHome => _t(
      'Исполнитель приедет в назначенное время.',
      'Орындаушы белгіленген уақытта келеді.',
      'The crew will arrive at the scheduled time.');
  String get bkStatusCompletedHint =>
      _t('Услуга оказана.', 'Қызмет көрсетілді.', 'The service was provided.');
  String get bkStatusCancelledHint => _t(
      'Время освобождено.', 'Уақыт босатылды.', 'The time slot was released.');
  String bkPaidOnSite(String price) => _t('$price · оплата на месте',
      '$price · төлем орнында', '$price · pay on site');
  String bkAreaLine(int area) =>
      _t('Площадь: $area м²', 'Ауданы: $area м²', 'Area: $area m²');
  String get bkCancelBooking =>
      _t('Отменить запись', 'Жазылудан бас тарту', 'Cancel booking');
  String get bkCancelRequest =>
      _t('Отменить заявку', 'Өтінімнен бас тарту', 'Cancel request');
  String get bkCancelQuestion => _t('Отменить запись?',
      'Жазылудан бас тарту керек пе?', 'Cancel the booking?');
  String get bkCancelBody => _t(
      'Отмена бесплатна до начала услуги. Время освободится для других клиентов.',
      'Қызмет басталғанға дейін бас тарту тегін. Уақыт басқа клиенттерге босайды.',
      'Cancellation is free until the service starts. The time will be freed for others.');
  String get bkNo => _t('Нет', 'Жоқ', 'No');
  String get bkDetailDevNote => _t(
      'DEV-режим: запись подтверждена автоматически, заведение и исполнитель не получают уведомление.',
      'DEV режимі: жазылу автоматты түрде расталды, мекеме мен орындаушы хабарлама алмайды.',
      'DEV mode: the booking was confirmed automatically; the venue and provider are not notified.');

  // Errors
  String bkError(BookingFailure failure) => switch (failure) {
        BookingFailure.offline => _t(
            'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
            'Серверпен байланыс жоқ. Интернетті тексеріп, қайта көріңіз.',
            'No connection to the server. Check your internet and try again.'),
        BookingFailure.sessionExpired => _t(
            'Сессия истекла. Войдите снова.',
            'Сессия аяқталды. Қайта кіріңіз.',
            'Session expired. Sign in again.'),
        BookingFailure.slotTaken => _t(
            'Это время только что заняли. Выберите другое.',
            'Бұл уақытты жаңа ғана алды. Басқасын таңдаңыз.',
            'This time was just taken. Choose another.'),
        BookingFailure.overlaps => _t(
            'У вас уже есть запись на это время.',
            'Бұл уақытқа сізде жазылу бар.',
            'You already have a booking at this time.'),
        BookingFailure.tooMany => _t(
            'Слишком много предстоящих записей. Отмените одну из них.',
            'Алдағы жазылулар тым көп. Біреуінен бас тартыңыз.',
            'Too many upcoming bookings. Cancel one of them.'),
        BookingFailure.notCancellable => _t(
            'Запись уже нельзя отменить: услуга началась или запись отменена.',
            'Жазылудан бас тартуға болмайды: қызмет басталды немесе жазылу тоқтатылған.',
            'The booking cannot be cancelled: the service has started or it is already cancelled.'),
        BookingFailure.notFound =>
          _t('Не найдено.', 'Табылмады.', 'Not found.'),
        BookingFailure.addressRequired => _t(
            'Укажите адрес, где нужна услуга.',
            'Қызмет қажет мекенжайды көрсетіңіз.',
            'Enter the address where the service is needed.'),
        BookingFailure.areaInvalid => _t(
            'Площадь вне допустимого диапазона для этой услуги.',
            'Ауданы бұл қызмет үшін рұқсат етілген аралықтан тыс.',
            'The area is outside the allowed range for this service.'),
        BookingFailure.priceChanged => _t(
            'Цена изменилась. Проверьте сумму и подтвердите снова.',
            'Баға өзгерді. Соманы тексеріп, қайта растаңыз.',
            'The price has changed. Check the amount and confirm again.'),
        BookingFailure.other => _t(
            'Не удалось выполнить действие. Попробуйте позже.',
            'Әрекетті орындау мүмкін болмады. Кейінірек көріңіз.',
            'The action failed. Please try again later.'),
      };
}

/// Localized text of the fixed synthetic DEV catalog. Unknown (future, real) names are shown as the server sent them.
const _catalogKk = <String, String>{
  'Поддерживающая уборка': 'Күнделікті жинау',
  'Генеральная уборка': 'Жалпы жинау',
  'Уборка после ремонта': 'Жөндеуден кейінгі жинау',
  'Мужская стрижка': 'Ерлер шаш қиюы',
  'Стрижка машинкой': 'Машинкамен қию',
  'Оформление бороды': 'Сақал пішімдеу',
  'Стрижка + борода': 'Шаш қию + сақал',
  'Королевское бритьё': 'Корольдік қырыну',
  'Детская стрижка': 'Балалар шаш қиюы',
};
const _catalogEn = <String, String>{
  'Поддерживающая уборка': 'Regular cleaning',
  'Генеральная уборка': 'Deep cleaning',
  'Уборка после ремонта': 'Post-renovation cleaning',
  'Мужская стрижка': "Men's haircut",
  'Стрижка машинкой': 'Clipper cut',
  'Оформление бороды': 'Beard trim',
  'Стрижка + борода': 'Haircut + beard',
  'Королевское бритьё': 'Royal shave',
  'Детская стрижка': "Kid's haircut",
};

extension BookingCatalogText on KundeLocalizations {
  /// Name of a demo service in the user's language (falls back to the server text).
  String bkCatalogName(String serverName) => switch (locale.languageCode) {
        'kk' => _catalogKk[serverName] ?? serverName,
        'en' => _catalogEn[serverName] ?? serverName,
        _ => serverName,
      };
}

/// Localizations of the app, or Russian when the widget tree has no KUNDE delegate (isolated widget tests).
KundeLocalizations bkL10n(BuildContext context) =>
    Localizations.of<KundeLocalizations>(context, KundeLocalizations) ??
    const KundeLocalizations(Locale('ru'));
