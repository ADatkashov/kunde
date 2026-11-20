import 'package:flutter/widgets.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/auto_api.dart';

/// Strings of the KUNDE Auto section (RU/KK/EN).
extension AutoStrings on KundeLocalizations {
  String _t(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get auTitle => _t('Авто', 'Авто', 'Auto');
  String get auIntro => _t(
      'Автомойки, шиномонтаж, СТО: выберите услугу, автомобиль и время.',
      'Көлік жуу, шина орнату, СТО: қызметті, көлікті және уақытты таңдаңыз.',
      'Car wash, tires, service stations: choose a service, your car and a time.');
  String get auMyVehicles =>
      _t('Мои автомобили', 'Менің көліктерім', 'My cars');
  String get auMyBookings =>
      _t('Мои записи', 'Менің жазылуларым', 'My bookings');
  String get auSearchHint => _t('Поиск СТО или автомойки',
      'СТО немесе көлік жуу іздеу', 'Search service station or car wash');
  String get auAllCategories => _t('Все', 'Барлығы', 'All');
  String get auNoVenues =>
      _t('Ничего не найдено', 'Ештеңе табылмады', 'Nothing found');
  String get auNoVenuesBody => _t(
      'Измените запрос или категорию. Организации появятся после модерации.',
      'Сұранысты немесе санатты өзгертіңіз. Ұйымдар модерациядан кейін шығады.',
      'Change the query or category. Organisations appear after moderation.');
  String get auLoadError => _t('Не удалось загрузить данные',
      'Деректерді жүктеу мүмкін болмады', 'Could not load data');
  String get auRetry => _t('Повторить', 'Қайталау', 'Retry');
  String get auDemoNote => _t(
      'DEV-режим: организации и цены синтетические, реальных платежей нет, оплата на месте.',
      'DEV режимі: ұйымдар мен бағалар синтетикалық, нақты төлем жоқ, төлем орнында.',
      'DEV mode: organisations and prices are synthetic, no real payments, pay on site.');
  String get auPayment => _t('Оплата', 'Төлем', 'Payment');
  String get auPayOnSite => _t('На месте', 'Орнында', 'Pay on site');
  String get auPayTestCard => _t('Тестовая карта', 'Тест картасы', 'Test card');
  String get auPayTestNote => _t(
      'DEV/TEST: сумма только резервируется в учёте. Реальных списаний нет.',
      'DEV/TEST: сома тек есепте резервтеледі. Нақты есептен шығару жоқ.',
      'DEV/TEST: the amount is only held in a ledger. No real charges.');
  String auPaymentStatus(String s) => switch (s) {
        'PAY_ON_SITE' => _t('Оплата на месте', 'Орнында төлеу', 'Pay on site'),
        'TEST_HELD' => _t('Тест: сумма зарезервирована',
            'Тест: сома резервтелді', 'Test: amount held'),
        'TEST_CAPTURED' => _t('Тест: оплачено', 'Тест: төленді', 'Test: paid'),
        'TEST_VOIDED' =>
          _t('Тест: резерв снят', 'Тест: резерв алынды', 'Test: hold released'),
        'TEST_REFUNDED' =>
          _t('Тест: возвращено', 'Тест: қайтарылды', 'Test: refunded'),
        'TEST_PART_REFUNDED' => _t('Тест: возвращено частично',
            'Тест: ішінара қайтарылды', 'Test: partly refunded'),
        _ => s,
      };
  String get auClosed => _t('Закрыто', 'Жабық', 'Closed');
  String auFrom(String price) =>
      _t('от $price', '$price бастап', 'from $price');
  String get auServices => _t('Услуги', 'Қызметтер', 'Services');
  String get auNoServices => _t('Нет доступных услуг',
      'Қолжетімді қызметтер жоқ', 'No services available');
  String auDuration(String d) =>
      _t('Длительность: $d', 'Ұзақтығы: $d', 'Duration: $d');
  String get auBook => _t('Записаться', 'Жазылу', 'Book');

  String get auPriceFixed =>
      _t('Итоговая цена', 'Түпкілікті баға', 'Final price');
  String get auPriceFrom => _t(
      'Цена от, итог после осмотра',
      'Баға бастап, қорытынды тексеруден кейін',
      'From price, final after inspection');
  String get auPriceDiagnostic => _t(
      'Диагностика, ремонт согласуется отдельно',
      'Диагностика, жөндеу бөлек келісіледі',
      'Diagnostics, repair agreed separately');
  String auPriceKind(String kind) => switch (kind) {
        'FROM' => auPriceFrom,
        'DIAGNOSTIC' => auPriceDiagnostic,
        _ => auPriceFixed,
      };

  // Vehicles
  String get auNoVehicles =>
      _t('Автомобилей пока нет', 'Көліктер әзірге жоқ', 'No cars yet');
  String get auNoVehiclesBody => _t('Добавьте автомобиль, чтобы записаться.',
      'Жазылу үшін көлік қосыңыз.', 'Add a car to make a booking.');
  String get auAddVehicle =>
      _t('Добавить автомобиль', 'Көлік қосу', 'Add a car');
  String get auEditVehicle =>
      _t('Изменить автомобиль', 'Көлікті өзгерту', 'Edit car');
  String get auMake => _t('Марка', 'Маркасы', 'Make');
  String get auModel => _t('Модель', 'Моделі', 'Model');
  String get auYear => _t('Год выпуска', 'Шығарылған жылы', 'Year');
  String get auPlate => _t('Госномер (необязательно)',
      'Мемлекеттік нөмір (міндетті емес)', 'Plate number (optional)');
  String get auSave => _t('Сохранить', 'Сақтау', 'Save');
  String get auDelete => _t('Удалить', 'Жою', 'Delete');
  String get auDeleteQuestion => _t(
      'Удалить автомобиль? История записей сохранится.',
      'Көлікті жою керек пе? Жазылулар тарихы сақталады.',
      'Delete the car? Booking history is kept.');
  String get auCancelAction => _t('Отмена', 'Бас тарту', 'Cancel');
  String get auFieldRequired =>
      _t('Обязательное поле', 'Міндетті өріс', 'Required field');
  String get auYearInvalid => _t(
      'Укажите год от 1950 до следующего года',
      '1950 жылдан келесі жылға дейінгі жылды көрсетіңіз',
      'Enter a year from 1950 to next year');
  String get auPlateInvalid => _t(
      '3–12 букв или цифр', '3–12 әріп немесе сан', '3–12 letters or digits');
  String get auChooseVehicle =>
      _t('Выберите автомобиль', 'Көлікті таңдаңыз', 'Choose a car');

  // Flow
  String get auChooseDate => _t('Дата', 'Күні', 'Date');
  String get auChooseTime => _t('Свободное время', 'Бос уақыт', 'Free time');
  String get auNoSlots => _t(
      'На этот день нет свободного времени. Выберите другой день.',
      'Бұл күнге бос уақыт жоқ. Басқа күнді таңдаңыз.',
      'No free time on this day. Choose another day.');
  String get auQuoteTitle =>
      _t('Предварительная стоимость', 'Алдын ала құны', 'Estimated cost');
  String auQuoteValid(String time) => _t('Расчёт действует до $time',
      'Есептеу $time дейін жарамды', 'Quote valid until $time');
  String get auConfirmBooking =>
      _t('Подтвердить запись', 'Жазылуды растау', 'Confirm booking');
  String get auBooked =>
      _t('Запись создана', 'Жазылу жасалды', 'Booking created');
  String get auBookedPending => _t('Ожидает подтверждения организации',
      'Ұйымның растауын күтуде', 'Waiting for the organisation to confirm');

  // Bookings
  String get auNoBookings =>
      _t('Записей пока нет', 'Жазылулар әзірге жоқ', 'No bookings yet');
  String get auActive => _t('Активные', 'Белсенді', 'Active');
  String get auHistory =>
      _t('История обслуживания', 'Қызмет көрсету тарихы', 'Service history');
  String get auDetails => _t('Запись', 'Жазылу', 'Booking');
  String get auCancelBooking =>
      _t('Отменить запись', 'Жазылудан бас тарту', 'Cancel booking');
  String get auCancelQuestion => _t(
      'Отменить запись? Оплаты нет, отмена бесплатна до начала.',
      'Жазылудан бас тарту керек пе? Төлем жоқ, басталғанға дейін тегін.',
      'Cancel the booking? No payment is taken; free until the start.');
  String get auKeep => _t('Оставить', 'Қалдыру', 'Keep');
  String get auReschedule => _t('Перенести', 'Көшіру', 'Reschedule');
  String get auRebook => _t('Записаться снова', 'Қайта жазылу', 'Book again');
  String get auFinalPrice =>
      _t('Итоговая стоимость', 'Түпкілікті құны', 'Final cost');
  String auProposedPrice(String price) => _t(
      'Организация предлагает итоговую стоимость $price',
      'Ұйым түпкілікті құнын ұсынады: $price',
      'The organisation proposes a final cost of $price');
  String get auApprove => _t('Согласовать', 'Келісу', 'Approve');
  String get auDecline => _t('Отклонить', 'Бас тарту', 'Decline');
  String get auLateCancel => _t(
      'Поздняя отмена (менее 2 часов до начала)',
      'Кеш бас тарту (басталуына 2 сағаттан аз)',
      'Late cancellation (under 2 hours before start)');
  String auStatus(String status) => switch (status) {
        'PENDING' => _t('Ожидает подтверждения', 'Растауды күтуде',
            'Waiting for confirmation'),
        'CONFIRMED' => _t('Подтверждена', 'Расталды', 'Confirmed'),
        'CHECKED_IN' =>
          _t('Автомобиль принят', 'Көлік қабылданды', 'Car checked in'),
        'IN_PROGRESS' => _t('Выполняется', 'Орындалуда', 'In progress'),
        'COMPLETED' => _t('Завершена', 'Аяқталды', 'Completed'),
        'CANCELLED' => _t('Отменена', 'Бас тартылды', 'Cancelled'),
        'NO_SHOW' => _t('Не явились', 'Келмеді', 'No-show'),
        _ => status,
      };

  String get auReview => _t('Оценить', 'Бағалау', 'Rate');
  String get auReviewTitle =>
      _t('Оценка обслуживания', 'Қызмет көрсетуді бағалау', 'Rate the service');
  String get auReviewText => _t('Комментарий (необязательно)',
      'Пікір (міндетті емес)', 'Comment (optional)');
  String get auReviewThanks => _t('Спасибо за отзыв!', 'Пікіріңіз үшін рахмет!',
      'Thank you for your review!');
  String get auSend => _t('Отправить', 'Жіберу', 'Send');
  String get auComplain => _t('Пожаловаться', 'Шағымдану', 'Report a problem');
  String get auComplaintTitle => _t('Жалоба', 'Шағым', 'Complaint');
  String get auComplaintText => _t(
      'Опишите проблему (от 5 символов)',
      'Мәселені сипаттаңыз (5 таңбадан)',
      'Describe the problem (5+ characters)');
  String get auComplaintSent => _t(
      'Жалоба отправлена, мы разберёмся.',
      'Шағым жіберілді, қарастырамыз.',
      'Complaint sent, we will look into it.');
  String auComplaintKind(String k) => switch (k) {
        'QUALITY' => _t('Качество', 'Сапа', 'Quality'),
        'PRICE' => _t('Цена', 'Баға', 'Price'),
        'BEHAVIOR' => _t('Поведение', 'Мінез-құлық', 'Behaviour'),
        'NO_SHOW' => _t('Не явились', 'Келмеді', 'No-show'),
        _ => _t('Другое', 'Басқа', 'Other'),
      };
  String auRating(String value, int count) => '★ $value ($count)';

  String auError(AutoFailure f) => switch (f) {
        AutoFailure.offline => _t(
            'Нет связи с сервером. Проверьте интернет и повторите.',
            'Сервермен байланыс жоқ. Интернетті тексеріп, қайталаңыз.',
            'No connection. Check your internet and retry.'),
        AutoFailure.sessionExpired => _t(
            'Сессия истекла. Войдите снова.',
            'Сессия аяқталды. Қайта кіріңіз.',
            'Session expired. Sign in again.'),
        AutoFailure.slotTaken => _t(
            'Это время только что заняли. Выберите другое.',
            'Бұл уақытты жаңа ғана алды. Басқасын таңдаңыз.',
            'This time was just taken. Choose another.'),
        AutoFailure.quoteExpired => _t(
            'Расчёт устарел. Выберите время снова.',
            'Есептеу ескірді. Уақытты қайта таңдаңыз.',
            'The quote expired. Choose the time again.'),
        AutoFailure.vehicleBooked => _t(
            'Этот автомобиль уже записан на это время.',
            'Бұл көлік осы уақытқа жазылған.',
            'This car is already booked at this time.'),
        AutoFailure.tooManyBookings => _t('Слишком много активных записей.',
            'Белсенді жазылулар тым көп.', 'Too many active bookings.'),
        AutoFailure.tooManyVehicles => _t(
            'Можно добавить не более 5 автомобилей.',
            '5 көліктен артық қосуға болмайды.',
            'At most 5 cars can be added.'),
        AutoFailure.notCancellable => _t(
            'Запись уже нельзя отменить.',
            'Жазылудан бас тартуға болмайды.',
            'The booking can no longer be cancelled.'),
        AutoFailure.notReschedulable => _t(
            'Запись нельзя перенести: до начала меньше 2 часов или статус изменился.',
            'Жазылуды көшіруге болмайды: басталуына 2 сағаттан аз немесе мәртебе өзгерді.',
            'Cannot reschedule: under 2 hours to start or status changed.'),
        AutoFailure.paymentUnsupported => _t(
            'Тестовая оплата доступна только в DEV/TEST. Выберите оплату на месте.',
            'Тестілік төлем тек DEV/TEST ортасында. Орнында төлемді таңдаңыз.',
            'Test payment exists only in DEV/TEST. Choose pay on site.'),
        AutoFailure.rescheduleLimit => _t(
            'Запись уже переносили дважды.',
            'Жазылу екі рет көшірілген.',
            'The booking was already moved twice.'),
        AutoFailure.unavailable => _t(
            'Авто-сервис временно недоступен для новых записей.',
            'Авто қызметі жаңа жазылулар үшін уақытша қолжетімсіз.',
            'Auto is temporarily unavailable for new bookings.'),
        AutoFailure.versionConflict => _t(
            'Данные изменились. Обновите и повторите.',
            'Деректер өзгерді. Жаңартып, қайталаңыз.',
            'Data changed. Refresh and retry.'),
        AutoFailure.alreadyDone => _t('Это уже отправлено.',
            'Бұл бұрын жіберілген.', 'This was already sent.'),
        AutoFailure.invalid => _t('Проверьте введённые данные.',
            'Енгізілген деректерді тексеріңіз.', 'Check the entered data.'),
        AutoFailure.notFound => _t('Не найдено.', 'Табылмады.', 'Not found.'),
        AutoFailure.other => _t(
            'Не удалось выполнить действие. Попробуйте позже.',
            'Әрекетті орындау мүмкін болмады. Кейінірек қайталаңыз.',
            'The action failed. Try again later.'),
      };
}

KundeLocalizations auL10n(BuildContext context) =>
    Localizations.of<KundeLocalizations>(context, KundeLocalizations) ??
    const KundeLocalizations(Locale('ru'));
