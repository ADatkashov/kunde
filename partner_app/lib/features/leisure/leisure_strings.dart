import '../../core/strings.dart';

/// Strings of the Leisure section of KUNDE Partner (RU/KK/EN).
extension LeisureS on S {
  String _l(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get lzTitle => _l('Досуг', 'Демалыс', 'Leisure');
  String get lzOverview => _l('Обзор', 'Шолу', 'Overview');
  String get lzEvents => _l('Мероприятия', 'Іс-шаралар', 'Events');
  String get lzBookings => _l('Бронирования', 'Брондаулар', 'Bookings');
  String get lzScan => _l('Проверка', 'Тексеру', 'Check-in');
  String get lzSales => _l('Продажи', 'Сатылымдар', 'Sales');
  String get lzTicketsSold => _l('Билеты', 'Билеттер', 'Tickets');
  String get lzAttendance => _l('Посещаемость', 'Келу', 'Attendance');
  String get lzOrders => _l('Брони', 'Брондар', 'Bookings');
  String get lzUpcomingSessions =>
      _l('Предстоящие сеансы', 'Алдағы сеанстар', 'Upcoming sessions');
  String lzDays(int d) => _l('за $d дн.', '$d күн ішінде', 'last $d days');
  String get lzCreateEvent =>
      _l('Создать мероприятие', 'Іс-шара құру', 'Create event');
  String get lzScanQr => _l('Сканировать QR', 'QR сканерлеу', 'Scan QR');
  String get lzNearest =>
      _l('Ближайшие сеансы', 'Жақын сеанстар', 'Next sessions');
  String get lzNothing => _l('Пока пусто', 'Әзірге бос', 'Nothing yet');
  String get lzVenues => _l('Площадки', 'Алаңдар', 'Venues');
  String get lzNewVenue => _l('Новая площадка', 'Жаңа алаң', 'New venue');
  String get lzEditVenue => _l('Площадка', 'Алаң', 'Venue');
  String get lzVenueName => _l('Название', 'Атауы', 'Name');
  String get lzAddress => _l('Адрес', 'Мекенжай', 'Address');
  String get lzDistrict => _l('Район', 'Аудан', 'District');
  String get lzDescription => _l('Описание', 'Сипаттама', 'Description');
  String get lzRules =>
      _l('Правила посещения', 'Келу ережелері', 'Visiting rules');
  String get lzPhotos => _l(
      'Фото (ссылки https, по одной в строке)',
      'Фото (https сілтемелері, әр жолға біреуден)',
      'Photos (https links, one per line)');
  String get lzPhotoNote => _l(
      'Загрузка файлов появится позже: пока принимаются только ссылки.',
      'Файл жүктеу кейін қосылады: әзірге тек сілтемелер.',
      'File upload comes later: links only for now.');
  String get lzCancelHours => _l('Бесплатная отмена за, ч',
      'Тегін бас тарту, сағ', 'Free cancellation, hours before');
  String get lzSave => _l('Сохранить', 'Сақтау', 'Save');
  String get lzSubmit =>
      _l('Отправить на проверку', 'Тексеруге жіберу', 'Submit for review');
  String get lzArchive => _l('В архив', 'Мұрағатқа', 'Archive');
  String get lzNewEvent => _l('Новое мероприятие', 'Жаңа іс-шара', 'New event');
  String get lzEventTitle => _l('Название', 'Атауы', 'Title');
  String get lzCategory => _l('Категория', 'Санат', 'Category');
  String get lzBookingType => _l('Тип брони', 'Брондау түрі', 'Booking type');
  String get lzDuration =>
      _l('Длительность, мин', 'Ұзақтығы, мин', 'Duration, min');
  String get lzMinAge => _l('Возраст от', 'Жасы', 'Minimum age');
  String get lzMaxGuests => _l('Макс. гостей', 'Ең көп қонақ', 'Max guests');
  String get lzFamily =>
      _l('Семейный формат', 'Отбасылық формат', 'Family friendly');
  String get lzManual =>
      _l('Подтверждать вручную', 'Қолмен растау', 'Confirm manually');
  String get lzNeedsExecutor => _l('Нужен исполнитель (гид, ведущий)',
      'Орындаушы керек (гид, жүргізуші)', 'Needs an executor (guide, host)');
  String get lzTicketTypes => _l('Типы билетов и цены',
      'Билет түрлері және бағалар', 'Ticket types and prices');
  String get lzAddTicketType =>
      _l('Добавить тип билета', 'Билет түрін қосу', 'Add ticket type');
  String get lzTypeName => _l('Название билета', 'Билет атауы', 'Ticket name');
  String get lzPriceTenge => _l('Цена, ₸', 'Баға, ₸', 'Price, ₸');
  String get lzZone => _l('Зона мест (VIP или пусто)',
      'Орын аймағы (VIP немесе бос)', 'Seat zone (VIP or empty)');
  String get lzSessions => _l('Сеансы', 'Сеанстар', 'Sessions');
  String get lzAddSessions =>
      _l('Добавить сеансы', 'Сеанс қосу', 'Add sessions');
  String get lzDate => _l('Дата', 'Күні', 'Date');
  String get lzTime => _l('Время', 'Уақыты', 'Time');
  String get lzAddTime => _l('Добавить время', 'Уақыт қосу', 'Add a time');
  String get lzCapacity =>
      _l('Мест / ресурсов', 'Орын / ресурс', 'Places / resources');
  String get lzRows => _l('Рядов', 'Қатар', 'Rows');
  String get lzSeatsPerRow =>
      _l('Мест в ряду', 'Қатардағы орын', 'Seats per row');
  String get lzVipRows => _l('Рядов VIP', 'VIP қатар', 'VIP rows');
  String get lzCancelSession =>
      _l('Отменить сеанс', 'Сеансты болдырмау', 'Cancel session');
  String get lzReason => _l('Причина', 'Себебі', 'Reason');
  String get lzCancelSessionNote => _l(
      'Все брони сеанса будут отменены, клиентам вернут деньги (тест).',
      'Сеанстың барлық брондары болдырылмайды, клиенттерге ақша қайтарылады (тест).',
      'All bookings of the session are cancelled and customers refunded (test).');
  String get lzAssign =>
      _l('Назначить исполнителя', 'Орындаушы тағайындау', 'Assign executor');
  String get lzPhone => _l('Телефон исполнителя (+7…)',
      'Орындаушы телефоны (+7…)', 'Executor phone (+7…)');
  String get lzRole => _l('Роль', 'Рөлі', 'Role');
  String get lzNote => _l('Заметка', 'Ескертпе', 'Note');
  String get lzSold => _l('Продано', 'Сатылды', 'Sold');
  String get lzHeld => _l('В удержании', 'Ұсталған', 'Held');
  String get lzAdmitted => _l('Вошло', 'Кірді', 'Admitted');
  String get lzRequests => _l('Запросы', 'Сұраулар', 'Requests');
  String get lzUpcoming => _l('Предстоящие', 'Алдағы', 'Upcoming');
  String get lzHistory => _l('История', 'Тарих', 'History');
  String get lzConfirm => _l('Подтвердить', 'Растау', 'Confirm');
  String get lzReject => _l('Отклонить', 'Қабылдамау', 'Reject');
  String get lzCancel =>
      _l('Отменить бронь', 'Броньнан бас тарту', 'Cancel booking');
  String get lzGuests => _l('Гостей', 'Қонақ', 'Guests');
  String get lzPaymentTest =>
      _l('Тестовая оплата', 'Тестілік төлем', 'Test payment');
  String get lzPaymentSite =>
      _l('Оплата на месте', 'Орнында төлеу', 'Pay on site');
  String get lzRefund => _l('Возврат', 'Қайтару', 'Refunded');
  String get lzAuditTitle =>
      _l('История операций', 'Операциялар тарихы', 'Operation history');
  String get lzCamera => _l(
      'Наведите камеру на QR-код билета',
      'Камераны билет QR кодына бағыттаңыз',
      'Point the camera at the ticket QR code');
  String get lzCameraDenied => _l(
      'Нет доступа к камере. Разрешите её в настройках или введите код вручную.',
      'Камераға рұқсат жоқ. Параметрлерде рұқсат беріңіз немесе кодты қолмен енгізіңіз.',
      'Camera access is off. Allow it in settings or type the code.');
  String get lzCameraRetry => _l(
      'Включить камеру снова', 'Камераны қайта қосу', 'Try the camera again');
  String get lzManualCode => _l('Код билета вручную',
      'Билет кодын қолмен енгізу', 'Enter the ticket code');
  String get lzCheck => _l('Проверить', 'Тексеру', 'Check');
  String get lzRecent =>
      _l('Последние проверки', 'Соңғы тексерулер', 'Recent checks');
  String get lzClose => _l('Закрыть', 'Жабу', 'Close');
  String get lzNext => _l('Следующий', 'Келесі', 'Next');
  String get lzRetry => _l('Повторить', 'Қайталау', 'Retry');
  String get lzNoAccess => _l(
      'Эта функция недоступна для вашей роли',
      'Бұл функция сіздің рөліңізге қолжетімсіз',
      'Not available for your role');
  String get lzDisabled => _l(
      'Досуг сейчас выключен администратором: новые мероприятия и сеансы не создаются.',
      'Демалыс әкімшімен өшірілген: жаңа іс-шара мен сеанс құрылмайды.',
      'Leisure is switched off by an administrator: no new events or sessions.');
  String get lzSeatsLabel => _l('Место', 'Орын', 'Seat');
  String get lzSavedOk => _l('Сохранено', 'Сақталды', 'Saved');

  String lzStatus(String status) => switch (status) {
        'DRAFT' => _l('Черновик', 'Жоба', 'Draft'),
        'PENDING' => _l('На проверке', 'Тексеруде', 'In review'),
        'APPROVED' => _l('Одобрено', 'Мақұлданды', 'Approved'),
        'PUBLISHED' => _l('Опубликовано', 'Жарияланды', 'Published'),
        'REJECTED' => _l('Отклонено', 'Қабылданбады', 'Rejected'),
        'BLOCKED' => _l('Заблокировано', 'Бұғатталды', 'Blocked'),
        'ARCHIVED' => _l('В архиве', 'Мұрағатта', 'Archived'),
        'CONFIRMED' => _l('Подтверждено', 'Расталды', 'Confirmed'),
        'CANCELLED' => _l('Отменено', 'Бас тартылды', 'Cancelled'),
        'SCHEDULED' => _l('Запланирован', 'Жоспарланды', 'Scheduled'),
        'VALID' => _l('Действителен', 'Жарамды', 'Valid'),
        'USED' => _l('Использован', 'Пайдаланылған', 'Used'),
        _ => status,
      };

  String lzBookingTypeName(String type) => switch (type) {
        'TIME_SLOT' => _l('По времени (дорожка, стол)',
            'Уақыт бойынша (жол, үстел)', 'Time slot (lane, table)'),
        'CAPACITY' =>
          _l('Ограниченные места', 'Шектеулі орындар', 'Limited places'),
        'SEAT_MAP' => _l('Выбор мест', 'Орын таңдау', 'Seat map'),
        'GENERAL_ADMISSION' =>
          _l('Вход по билету', 'Билетпен кіру', 'General admission'),
        _ => _l('Вся площадка или комната', 'Бүкіл алаң немесе бөлме',
            'Private room or venue'),
      };

  String lzCheckResult(String result) => switch (result) {
        'ADMITTED' => _l('Проход разрешён', 'Кіруге рұқсат', 'Admitted'),
        'DUPLICATE' =>
          _l('Билет уже использован', 'Билет пайдаланылған', 'Already used'),
        'INVALID' => _l('Недействительный код', 'Жарамсыз код', 'Invalid code'),
        'WRONG_ORGANIZATION' => _l('Билет другой площадки',
            'Басқа алаңның билеті', 'Ticket of another organiser'),
        'WRONG_SESSION' => _l('Другой сеанс', 'Басқа сеанс', 'Another session'),
        'CANCELLED' =>
          _l('Бронь отменена', 'Брон болдырылмады', 'Booking cancelled'),
        'NOT_CONFIRMED' => _l('Бронь не подтверждена', 'Брон расталмаған',
            'Booking not confirmed'),
        'EXPIRED' =>
          _l('Сеанс уже прошёл', 'Сеанс өтіп кеткен', 'The session is over'),
        'TOO_EARLY' => _l('Вход пока не открыт', 'Кіру әлі ашылмаған',
            'Entry is not open yet'),
        _ => result,
      };
}
