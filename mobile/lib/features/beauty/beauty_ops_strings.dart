import '../../core/localization/kunde_localizations.dart';

/// Strings of the Beauty Partner, Executor and Admin screens (RU/KK/EN).
extension BeautyOpsStrings on KundeLocalizations {
  String _o(String ru, String kk, String en) => switch (locale.languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  // Partner
  String get boPartnerTitle => 'KUNDE Partner';
  String get boOverview => _o('Обзор', 'Шолу', 'Overview');
  String get boBookingsToday =>
      _o('Записей сегодня', 'Бүгінгі жазылулар', 'Bookings today');
  String get boRevenue => _o('Выручка', 'Түсім', 'Revenue');
  String get boManageServices =>
      _o('Управление услугами', 'Қызметтерді басқару', 'Manage services');
  String get boMasterSchedule =>
      _o('Расписание мастеров', 'Шеберлер кестесі', 'Masters schedule');
  String get boBookingsClients =>
      _o('Записи и клиенты', 'Жазылулар мен клиенттер', 'Bookings and clients');
  String get boPromos =>
      _o('Акции и скидки', 'Акциялар мен жеңілдіктер', 'Offers and discounts');
  String get boReviews => _o('Отзывы', 'Пікірлер', 'Reviews');
  String get boStaff => _o('Сотрудники', 'Қызметкерлер', 'Staff');
  String get boAnalytics => _o('Аналитика', 'Аналитика', 'Analytics');
  String get boSoon => _o('Скоро', 'Жақында', 'Soon');
  String get boSalonType =>
      _o('Салон красоты', 'Сұлулық салоны', 'Beauty salon');
  String get boNoSalons => _o(
      'К этой организации не привязан салон красоты.',
      'Бұл ұйымға сұлулық салоны байланбаған.',
      'No beauty salon is linked to this organization.');
  String get boInviteCode =>
      _o('Код приглашения', 'Шақыру коды', 'Invite code');
  String get boLinked => _o('Подключён', 'Қосылған', 'Connected');
  String get boOnline => _o('Онлайн', 'Онлайн', 'Online');
  String get boOffline => _o('Не в сети', 'Желіде емес', 'Offline');
  String get boStaffHint => _o(
      'Передайте код мастеру: он вводит его в KUNDE Executor один раз.',
      'Кодты шеберге беріңіз: ол оны KUNDE Executor-да бір рет енгізеді.',
      'Give the code to the master: they enter it once in KUNDE Executor.');
  String boDelta(int percent) => '${percent >= 0 ? '+' : ''}$percent%';

  // Executor
  String get boExecutorTitle => 'KUNDE Executor';
  String get boToday => _o('Сегодня', 'Бүгін', 'Today');
  String boBookingsCount(int n) => _o('$n записей', '$n жазылу', '$n bookings');
  String get boStartVisit =>
      _o('Начать приём', 'Қабылдауды бастау', 'Start visit');
  String get boFinishVisit =>
      _o('Завершить приём', 'Қабылдауды аяқтау', 'Finish visit');
  String get boNoShow => _o('Неявка', 'Келмеді', 'No-show');
  String get boNextBookings =>
      _o('Следующие записи', 'Келесі жазылулар', 'Next bookings');
  String get boNoAppointments =>
      _o('Записей пока нет', 'Жазылу әзірге жоқ', 'No bookings yet');
  String get boClient => _o('Клиент', 'Клиент', 'Client');
  String get boTabTasks => _o('Задачи', 'Тапсырмалар', 'Tasks');
  String get boTabSchedule => _o('Расписание', 'Кесте', 'Schedule');
  String get boTabIncome => _o('Доход', 'Табыс', 'Income');
  String get boTabProfile => _o('Профиль', 'Профиль', 'Profile');
  String get boLinkTitle =>
      _o('Подключение к салону', 'Салонға қосылу', 'Connect to a salon');
  String get boLinkBody => _o(
      'Введите код приглашения, который выдал салон.',
      'Салон берген шақыру кодын енгізіңіз.',
      'Enter the invite code the salon gave you.');
  String get boLinkAction => _o('Подключиться', 'Қосылу', 'Connect');
  String get boLinkInvalid => _o('Код неверный или уже использован.',
      'Код қате немесе қолданылған.', 'The code is invalid or already used.');
  String get boActionFailed => _o('Действие недоступно сейчас.',
      'Әрекет қазір қолжетімсіз.', 'The action is not available right now.');
  String get boIncomeNote => _o(
      'Стоимость выполненных вами услуг. Выручка салона здесь не показывается.',
      'Сіз орындаған қызметтердің құны. Салон түсімі мұнда көрсетілмейді.',
      'The value of the services you completed. Salon revenue is not shown here.');
  String get boIncomeWeek => _o('За 7 дней', '7 күн', '7 days');
  String get boIncomeMonth => _o('За 30 дней', '30 күн', '30 days');
  String boCompleted(int n) =>
      _o('Выполнено: $n', 'Орындалды: $n', 'Completed: $n');
  String get boOfflineNote => _o(
      'Вы не в сети: новые записи не поступают, подтверждённые сохраняются.',
      'Сіз желіде емессіз: жаңа жазылулар келмейді, расталғандары сақталады.',
      'You are offline: no new bookings, confirmed ones stay.');

  // Admin
  String get boAdminTitle => _o('Красота и уход — Аналитика и управление',
      'Сұлулық және күтім — Аналитика', 'Beauty & Care — Analytics');
  String get boSalons => _o('Салоны', 'Салондар', 'Salons');
  String get boBookings => _o('Записи', 'Жазылулар', 'Bookings');
  String get boAverageCheck => _o('Средний чек', 'Орташа чек', 'Average check');
  String get boBookingsByDay =>
      _o('Записи по дням', 'Күндер бойынша жазылулар', 'Bookings by day');
  String get boCategories =>
      _o('Категории услуг', 'Қызмет санаттары', 'Service categories');
  String get boRecent =>
      _o('Последние записи', 'Соңғы жазылулар', 'Recent bookings');
  String get boPeriod7 => _o('7 дней', '7 күн', '7 days');
  String get boPeriod30 => _o('30 дней', '30 күн', '30 days');
  String get boNoData =>
      _o('Данных пока нет', 'Дерек әзірге жоқ', 'No data yet');

  String boStatus(String status) => switch (status) {
        'COMPLETED' => _o('Завершена', 'Аяқталды', 'Completed'),
        'IN_PROGRESS' => _o('В работе', 'Жұмыста', 'In progress'),
        'CONFIRMED' => _o('Новая', 'Жаңа', 'New'),
        'PENDING' => _o('Ожидает', 'Күтуде', 'Pending'),
        'CANCELLED' => _o('Отменена', 'Бас тартылды', 'Cancelled'),
        'NO_SHOW' => _o('Неявка', 'Келмеді', 'No-show'),
        _ => status,
      };
}
