import 'package:flutter/widgets.dart';

/// All user-visible text of KUNDE Partner (RU / KK / EN). Widgets never carry
/// literal strings; each getter lists the three translations side by side so a
/// missing translation is impossible to miss in review.
class S {
  const S(this.locale);
  final Locale locale;

  static const supported = [Locale('ru'), Locale('kk'), Locale('en')];
  static const delegate = _SDelegate();

  static S of(BuildContext context) =>
      Localizations.of<S>(context, S) ?? const S(Locale('ru'));

  String get healthTitle => _t('Здоровье и благополучие',
      'Денсаулық және әл-ауқат', 'Health & Wellness');
  String get healthSpecialists => _t('Специалисты', 'Мамандар', 'Specialists');

  String get addHealthSpecialist =>
      _t('Добавить специалиста', 'Маман қосу', 'Add specialist');
  String get healthSpecialistName =>
      _t('Имя демо-специалиста', 'Демо маманның аты', 'Demo specialist name');
  String get healthSelectSpecialist =>
      _t('Выберите специалиста', 'Маманды таңдаңыз', 'Select a specialist');
  String healthDirection(String code) => switch (code) {
        'DOCTORS' => _t('Врачи', 'Дәрігерлер', 'Doctors'),
        'CLINICS' => _t('Клиники', 'Клиникалар', 'Clinics'),
        'DENTISTRY' => _t('Стоматология', 'Стоматология', 'Dentistry'),
        'DIAGNOSTICS' => _t('Диагностика', 'Диагностика', 'Diagnostics'),
        'LABS' => _t('Анализы', 'Талдаулар', 'Lab tests'),
        'FITNESS' => _t('Фитнес', 'Фитнес', 'Fitness'),
        'SPA' => _t('SPA и массаж', 'SPA және массаж', 'Spa & massage'),
        'WELLNESS' => _t('Другие услуги', 'Басқа қызметтер', 'Other services'),
        _ => code,
      };

  String _t(String ru, String kk, String en) {
    switch (locale.languageCode) {
      case 'kk':
        return kk;
      case 'en':
        return en;
      default:
        return ru;
    }
  }

  // ── Groceries picking ─────────────────────────────────────────────
  String get pickDone => _t('Собрано', 'Жиналды', 'Picked');
  String get pickMissing => _t('Нет в наличии', 'Қолда жоқ', 'Missing');
  String get pickReplace => _t('Заменить', 'Ауыстыру', 'Replace');
  String get pickChooseReplacement =>
      _t('Выберите замену', 'Ауыстыруды таңдаңыз', 'Choose a replacement');
  String get pickNoAlternatives => _t(
      'Нет доступных замен того же вида',
      'Сол түрдегі қолжетімді ауыстыру жоқ',
      'No available replacements of the same kind');
  String get pickProgress => _t('Сборка заказа', 'Тапсырысты жинау', 'Picking');
  String get pickWaitingCustomer => _t('Ждём ответ покупателя',
      'Сатып алушының жауабын күтеміз', 'Waiting for the customer');
  String get pickMustFinish => _t(
      'Отметьте каждую позицию, чтобы передать заказ',
      'Тапсырысты беру үшін әр позицияны белгілеңіз',
      'Mark every line to hand the order over');
  String pickStatus(String status) => switch (status) {
        'PENDING' => _t('Ожидает сборки', 'Жинауды күтеді', 'To pick'),
        'PROPOSED' =>
          _t('Замена предложена', 'Ауыстыру ұсынылды', 'Replacement proposed'),
        'OK' => pickDone,
        'SUBSTITUTED' => _t('Заменено', 'Ауыстырылды', 'Replaced'),
        'REMOVED' => pickMissing,
        _ => status,
      };

  // ── Groceries product card ───────────────────────────────────────────
  String get productCard =>
      _t('Карточка товара', 'Тауар карточкасы', 'Product card');
  String get productCategory => _t('Категория', 'Санат', 'Category');
  String get productNoCategory =>
      _t('Без категории', 'Санатсыз', 'No category');
  String get productBrand => _t('Бренд', 'Бренд', 'Brand');
  String get productOrigin =>
      _t('Страна происхождения', 'Шыққан елі', 'Country of origin');
  String get productComposition => _t('Состав', 'Құрамы', 'Composition');
  String get productStorage =>
      _t('Условия хранения', 'Сақтау шарттары', 'Storage conditions');
  String get productNutrition => _t('Пищевая ценность на 100 г',
      '100 г үшін тағамдық құндылығы', 'Nutrition per 100 g');
  String get productKcal => _t('Ккал', 'Ккал', 'Kcal');
  String get productProtein => _t('Белки, г', 'Ақуыз, г', 'Protein, g');
  String get productFat => _t('Жиры, г', 'Май, г', 'Fat, g');
  String get productCarbs => _t('Углеводы, г', 'Көмірсу, г', 'Carbs, g');
  String get productOldPrice => _t(
      'Цена до скидки, ₸ (пусто — без скидки)',
      'Жеңілдікке дейінгі баға, ₸ (бос — жеңілдіксіз)',
      'Price before discount, ₸ (empty = none)');
  String get productOldPriceInvalid => _t(
      'Цена до скидки должна быть выше текущей цены',
      'Жеңілдікке дейінгі баға ағымдағыдан жоғары болуы керек',
      'The price before discount must be above the current price');
  String get productNutritionInvalid => _t(
      'Проверьте значения: ккал 0–1000, остальные 0–100',
      'Мәндерді тексеріңіз: ккал 0–1000, қалғаны 0–100',
      'Check the values: kcal 0–1000, others 0–100');
  String get productPhotos =>
      _t('Фотографии (до 6)', 'Суреттер (6-ға дейін)', 'Photos (up to 6)');
  String get productPhotoUrl => _t('Ссылка на фото (https://…)',
      'Сурет сілтемесі (https://…)', 'Photo link (https://…)');
  String get productPhotoAdd => _t('Добавить фото', 'Сурет қосу', 'Add photo');
  String get productPhotoInvalid => _t('Нужна ссылка https://',
      'https:// сілтемесі қажет', 'An https:// link is required');
  String get productPhotoHint => _t(
      'Первое фото — обложка. Загрузка файлов появится после подключения хранилища.',
      'Бірінші сурет — мұқаба. Файл жүктеу сақтау орны қосылғаннан кейін пайда болады.',
      'The first photo is the cover. File upload comes with a storage provider.');
  String get productRemovePhoto =>
      _t('Убрать фото', 'Суретті жою', 'Remove photo');
  String get productSaved =>
      _t('Карточка сохранена', 'Карточка сақталды', 'Product card saved');
  String get dishUnit => _t('Единица', 'Бірлік', 'Unit');
  String get dishUnitPiece => _t('Штуки', 'Дана', 'Pieces');
  String get dishUnitKg => _t('На вес (цена за кг)', 'Салмақпен (кг бағасы)',
      'By weight (price per kg)');
  String get dishStockGrams => _t('Остаток, г (пусто — без ограничения)',
      'Қалдық, г (бос — шектеусіз)', 'Stock, g (empty = unlimited)');
  String productCategoryName(String slug) => switch (slug) {
        'fruit_veg' =>
          _t('Овощи и фрукты', 'Көкөніс және жеміс', 'Fruit & vegetables'),
        'dairy' => _t('Молочные продукты', 'Сүт өнімдері', 'Dairy'),
        'meat' => _t('Мясо и птица', 'Ет және құс еті', 'Meat & poultry'),
        'fish' => _t('Рыба и морепродукты', 'Балық және теңіз өнімдері',
            'Fish & seafood'),
        'bakery' => _t('Хлеб и выпечка', 'Нан және тоқаш', 'Bread & bakery'),
        'drinks' => _t('Напитки', 'Сусындар', 'Drinks'),
        'pantry' => _t('Бакалея', 'Бакалея', 'Pantry'),
        'sweets' => _t('Сладости', 'Тәттілер', 'Sweets & snacks'),
        'frozen' =>
          _t('Замороженные продукты', 'Мұздатылған өнімдер', 'Frozen'),
        'ready_meals' => _t('Готовая еда', 'Дайын тағам', 'Ready meals'),
        'household' =>
          _t('Бытовая химия и дом', 'Тұрмыстық химия және үй', 'Household'),
        'kids' => _t('Детские товары', 'Балалар тауарлары', 'Kids'),
        _ => slug,
      };
  static const productCategories = [
    'fruit_veg',
    'dairy',
    'meat',
    'fish',
    'bakery',
    'drinks',
    'pantry',
    'sweets',
    'frozen',
    'ready_meals',
    'household',
    'kids'
  ];

  // ── App & navigation ────────────────────────────────────────────────
  String get appName => 'KUNDE Partner';
  String get navHome => _t('Главная', 'Басты бет', 'Home');
  String get navOrders => _t('Заказы', 'Тапсырыстар', 'Orders');
  String get navBookings => _t('Записи', 'Жазылулар', 'Bookings');
  String get navBusiness => _t('Заведение', 'Мекеме', 'Business');
  String get navProfile => _t('Профиль', 'Профиль', 'Profile');

  String get fleet => _t('Автопарк', 'Автопарк', 'Fleet');
  String get fleetApply =>
      _t('Подать заявку', 'Өтінім беру', 'Apply for fleet approval');
  String get fleetMissing => _t('Автопарк ещё не зарегистрирован',
      'Автопарк әлі тіркелмеген', 'No fleet registered');
  String get fleetDrivers => _t('Водители и автомобили',
      'Жүргізушілер мен көліктер', 'Drivers and vehicles');
  String get fleetAssign =>
      _t('Добавить водителя', 'Жүргізушіні қосу', 'Attach driver');
  String get fleetDetach =>
      _t('Отвязать водителя', 'Жүргізушіні ажырату', 'Detach driver');
  String get fleetTrips => _t('Поездки', 'Сапарлар', 'Trips');
  String get fleetTest => _t('Тестовая поездка', 'Сынақ сапары', 'Test trip');
  String fleetStats(int active, int complete) => _t(
      'Активные: $active · Завершённые: $complete',
      'Белсенді: $active · Аяқталған: $complete',
      'Active: $active · Completed: $complete');
  String fleetStatus(String status) => switch (status) {
        'APPROVED' => _t('Одобрено', 'Мақұлданды', 'Approved'),
        'PENDING' => _t('На проверке', 'Тексерілуде', 'Under review'),
        'BLOCKED' => _t('Заблокировано', 'Бұғатталды', 'Blocked'),
        'DRIVER_ASSIGNED' ||
        'DRIVER_ARRIVING' ||
        'DRIVER_ARRIVED' =>
          _t('Водитель назначен', 'Жүргізуші тағайындалды', 'Driver assigned'),
        'IN_PROGRESS' => _t('В поездке', 'Сапарда', 'In progress'),
        'COMPLETED' => _t('Завершена', 'Аяқталды', 'Completed'),
        _ => _t('Поездка завершена или отменена',
            'Сапар аяқталды немесе тоқтатылды', 'Trip ended or cancelled'),
      };
  String fleetAvailability(bool online) => online
      ? _t('На линии', 'Желіде', 'Online')
      : _t('Не на линии', 'Желіде емес', 'Offline');

  String get taxiTitle => 'KUNDE Taxi';
  String get taxiSubtitle =>
      _t('Таксомоторный парк', 'Таксі паркі', 'Taxi fleet');
  String get taxiTabService => _t('Сервис', 'Сервис', 'Service');
  String get taxiTabDrivers => _t('Водители', 'Жүргізушілер', 'Drivers');
  String get taxiTripsToday =>
      _t('Поездки сегодня', 'Бүгінгі сапарлар', 'Trips today');
  String get taxiCompleted => _t('Завершено', 'Аяқталды', 'Completed');
  String get taxiActive => _t('Активные', 'Белсенді', 'Active');
  String get taxiFareTotal =>
      _t('Сумма по тарифу', 'Тариф бойынша сома', 'Fare total');
  String get taxiFareNote => _t(
      'Сумма тарифов завершённых нетестовых поездок; оплата ещё не подключена.',
      'Аяқталған сынақ емес сапарлар тарифтерінің сомасы; төлем әлі қосылмаған.',
      'Tariff fares of completed non-test trips; payment is not connected yet.');
  String get taxiMenuFleet =>
      _t('Управление автопарком', 'Автопарқты басқару', 'Fleet management');
  String get taxiMenuDrivers => _t(
      'Водители и смены', 'Жүргізушілер мен ауысымдар', 'Drivers and shifts');
  String get taxiMenuOrders =>
      _t('Заказы и отчёты', 'Тапсырыстар мен есептер', 'Orders and reports');
  String get taxiMenuTariffs =>
      _t('Тарифы и зоны', 'Тарифтер мен аймақтар', 'Tariffs and zones');
  String get taxiMenuAnalytics => _t('Аналитика', 'Талдау', 'Analytics');
  String get taxiSoon => _t('Скоро', 'Жақында', 'Soon');
  String get taxiVehicles => _t('Автомобили', 'Көліктер', 'Vehicles');
  String get taxiNoVehicles =>
      _t('Автомобилей пока нет', 'Көліктер әлі жоқ', 'No vehicles yet');
  String get taxiNoDrivers =>
      _t('Водителей пока нет', 'Жүргізушілер әлі жоқ', 'No drivers yet');
  String get taxiNoTrips =>
      _t('Поездок пока нет', 'Сапарлар әлі жоқ', 'No trips yet');
  String get taxiCandidates =>
      _t('Можно добавить', 'Қосуға болады', 'Available to attach');
  String taxiClass(String? value) => switch (value) {
        'ECONOMY' => _t('Эконом', 'Эконом', 'Economy'),
        'COMFORT' => _t('Комфорт', 'Комфорт', 'Comfort'),
        'BUSINESS' => _t('Бизнес', 'Бизнес', 'Business'),
        _ => '',
      };

  // ── Common ──────────────────────────────────────────────────────────
  String get retry => _t('Повторить', 'Қайталау', 'Retry');
  String get refresh => _t('Обновить', 'Жаңарту', 'Refresh');
  String get back => _t('Назад', 'Артқа', 'Back');
  String get cancel => _t('Отмена', 'Бас тарту', 'Cancel');
  String get confirm => _t('Подтвердить', 'Растау', 'Confirm');
  String get save => _t('Сохранить', 'Сақтау', 'Save');
  String get close => _t('Закрыть', 'Жабу', 'Close');
  String get loadMore => _t('Показать ещё', 'Тағы көрсету', 'Show more');
  String get all => _t('Все', 'Барлығы', 'All');
  String get today => _t('Сегодня', 'Бүгін', 'Today');
  String get tomorrow => _t('Завтра', 'Ертең', 'Tomorrow');
  String get thisWeek => _t('Неделя', 'Апта', 'This week');
  String get currencyKzt => '₸';
  String get dash => '—';

  // ── Login ───────────────────────────────────────────────────────────
  String get loginTitle =>
      _t('Вход для партнёров', 'Серіктестерге кіру', 'Partner sign-in');
  String get loginSubtitle => _t(
      'Управляйте заказами и записями вашего заведения',
      'Мекемеңіздің тапсырыстары мен жазылуларын басқарыңыз',
      'Manage orders and bookings of your business');
  String get phoneLabel =>
      _t('Номер телефона', 'Телефон нөмірі', 'Phone number');
  String get phoneHint => '+7 700 000 00 00';
  String get codeLabel =>
      _t('Код подтверждения', 'Растау коды', 'Verification code');
  String codeSentTo(String phone) => _t('Код отправлен на $phone',
      'Код $phone нөміріне жіберілді', 'Code sent to $phone');
  String get getCode => _t('Получить код', 'Код алу', 'Get code');
  String get signIn => _t('Войти', 'Кіру', 'Sign in');
  String get changeNumber =>
      _t('Изменить номер', 'Нөмірді өзгерту', 'Change number');
  String get pleaseWait => _t('Подождите…', 'Күте тұрыңыз…', 'Please wait…');
  String get devCodeHint => _t(
      'Тестовая сборка: код для демо-номеров — 123456',
      'Сынақ құрастыру: демо нөмірлер коды — 123456',
      'Test build: demo numbers use code 123456');
  String get invalidPhone => _t('Введите номер в формате +7…',
      'Нөмірді +7… форматында енгізіңіз', 'Enter the number as +7…');
  String get invalidCode => _t('Введите код из сообщения',
      'Хабарламадағы кодты енгізіңіз', 'Enter the code from the message');
  String get wrongCode => _t('Неверный или просроченный код',
      'Код қате немесе мерзімі өткен', 'The code is wrong or has expired');
  String get tooManyAttempts => _t(
      'Слишком много попыток. Подождите немного и повторите.',
      'Тым көп әрекет. Біраз күтіп, қайталаңыз.',
      'Too many attempts. Please wait a moment and try again.');

  // ── Partner choice / access ─────────────────────────────────────────
  String get choosePartnerTitle =>
      _t('Выберите заведение', 'Мекемені таңдаңыз', 'Choose a business');
  String get choosePartnerSubtitle => _t(
      'За вашим номером закреплено несколько заведений.',
      'Нөміріңізге бірнеше мекеме тіркелген.',
      'Several businesses are linked to your number.');
  String get switchPartner =>
      _t('Сменить заведение', 'Мекемені ауыстыру', 'Switch business');
  String get noPartnerTitle =>
      _t('Нет доступа к кабинету', 'Кабинетке қолжетім жоқ', 'No access');
  String get noPartnerBody => _t(
      'За этим номером нет одобренного заведения. Обратитесь к владельцу или в поддержку KUNDE.',
      'Бұл нөмірде мақұлданған мекеме жоқ. Иесіне немесе KUNDE қолдауына хабарласыңыз.',
      'No approved business is linked to this number. Contact the owner or KUNDE support.');
  String get accessRevokedTitle =>
      _t('Доступ закрыт', 'Қолжетім жабылды', 'Access removed');
  String get accessRevokedBody => _t(
      'Ваш доступ к этому заведению отозван. Войдите снова или выберите другое заведение.',
      'Бұл мекемеге қолжетімділігіңіз алынды. Қайта кіріңіз немесе басқа мекеме таңдаңыз.',
      'Your access to this business was removed. Sign in again or choose another business.');
  String get sessionExpired => _t(
      'Сессия истекла. Войдите снова.',
      'Сессия аяқталды. Қайта кіріңіз.',
      'Your session expired. Sign in again.');
  String get apiNotConfigured => _t(
      'Адрес сервера не настроен. Установите актуальную сборку.',
      'Сервер мекенжайы бапталмаған. Жаңа нұсқаны орнатыңыз.',
      'Server address is not configured. Install an up-to-date build.');

  // ── Roles ───────────────────────────────────────────────────────────
  String role(String code) {
    switch (code) {
      case 'OWNER':
        return _t('Владелец', 'Иесі', 'Owner');
      case 'MANAGER':
        return _t('Менеджер', 'Менеджер', 'Manager');
      case 'OPERATOR':
        return _t('Оператор', 'Оператор', 'Operator');
      default:
        return dash;
    }
  }

  // ── Errors ──────────────────────────────────────────────────────────
  String get errNetworkTitle =>
      _t('Нет соединения', 'Байланыс жоқ', 'No connection');
  String get errNetworkBody => _t(
      'Проверьте интернет и повторите. Данные обновятся автоматически, когда связь вернётся.',
      'Интернетті тексеріп, қайталаңыз. Байланыс қайта қосылғанда деректер жаңарады.',
      'Check your internet and try again. Data will refresh when the connection returns.');
  String get errTimeout => _t(
      'Сервер отвечает слишком долго. Повторите позже.',
      'Сервер ұзақ жауап береді. Кейінірек қайталаңыз.',
      'The server is slow to respond. Try again later.');
  String get errServer => _t(
      'Сервис временно недоступен. Повторите позже.',
      'Қызмет уақытша қолжетімсіз. Кейінірек қайталаңыз.',
      'The service is temporarily unavailable. Try again later.');
  String get errForbidden => _t(
      'Для этого действия недостаточно прав.',
      'Бұл әрекет үшін құқық жеткіліксіз.',
      'You do not have permission for this action.');
  String get errNotFound => _t('Запись не найдена. Обновите список.',
      'Жазба табылмады. Тізімді жаңартыңыз.', 'Not found. Refresh the list.');
  String get errConflict => _t(
      'Статус уже изменился. Список обновлён — проверьте и повторите.',
      'Мәртебе өзгерген. Тізім жаңартылды — тексеріп, қайталаңыз.',
      'The status has already changed. The list was refreshed — check and retry.');
  String get errValidation => _t('Проверьте введённые данные.',
      'Енгізілген деректерді тексеріңіз.', 'Check the entered data.');
  String get errScheduleConflict => _t(
      'Есть записи клиентов в это время — изменить график нельзя.',
      'Осы уақытта клиент жазылулары бар — кестені өзгертуге болмайды.',
      'Customer bookings exist at that time — the schedule cannot change.');
  String get errUnknown => _t(
      'Не удалось выполнить действие. Повторите.',
      'Әрекетті орындау мүмкін болмады. Қайталаңыз.',
      'The action failed. Please try again.');
  String get errLoad => _t('Не удалось загрузить данные',
      'Деректерді жүктеу мүмкін болмады', 'Could not load data');
  String get offlineBanner => _t(
      'Нет соединения. Показаны последние данные.',
      'Байланыс жоқ. Соңғы деректер көрсетілген.',
      'Offline. Showing the latest data.');

  // ── Order statuses ──────────────────────────────────────────────────
  String orderStatus(String code) {
    switch (code) {
      case 'PLACED':
        return _t('Новый', 'Жаңа', 'New');
      case 'ACCEPTED':
        return _t('Принят', 'Қабылданды', 'Accepted');
      case 'PREPARING':
        return _t('Готовится', 'Дайындалуда', 'Preparing');
      case 'READY_FOR_PICKUP':
        return _t('Готов к выдаче', 'Беруге дайын', 'Ready for pickup');
      case 'ON_THE_WAY':
        return _t('В доставке', 'Жеткізілуде', 'On the way');
      case 'DELIVERED':
        return _t('Завершён', 'Аяқталды', 'Completed');
      case 'CANCELLED':
        return _t('Отменён', 'Бас тартылды', 'Cancelled');
      default:
        return dash;
    }
  }

  String bookingStatus(String code) {
    switch (code) {
      case 'PENDING':
      case 'REQUESTED':
        return _t('Ждёт ответа', 'Жауап күтеді', 'Awaiting reply');
      case 'CONFIRMED':
        return _t('Подтверждена', 'Расталды', 'Confirmed');
      case 'CHECKED_IN':
        return _t('Автомобиль принят', 'Көлік қабылданды', 'Car checked in');
      case 'IN_PROGRESS':
        return _t('В работе', 'Жұмыста', 'In progress');
      case 'NO_SHOW':
        return _t('Клиент не явился', 'Клиент келмеді', 'No-show');
      case 'COMPLETED':
        return _t('Завершена', 'Аяқталды', 'Completed');
      case 'CANCELLED':
      case 'REJECTED':
        return _t('Отменена', 'Бас тартылды', 'Cancelled');
      default:
        return dash;
    }
  }

  /// Button label for moving an order to [status].
  String orderAction(String status) {
    switch (status) {
      case 'ACCEPTED':
        return _t('Принять заказ', 'Тапсырысты қабылдау', 'Accept order');
      case 'PREPARING':
        return _t('Начать готовить', 'Дайындауды бастау', 'Start preparing');
      case 'READY_FOR_PICKUP':
        return _t('Заказ готов', 'Тапсырыс дайын', 'Order is ready');
      case 'ON_THE_WAY':
        return _t(
            'Передать в доставку', 'Жеткізуге беру', 'Hand over to delivery');
      case 'DELIVERED':
        return _t('Завершить заказ', 'Тапсырысты аяқтау', 'Complete order');
      case 'CANCELLED':
        return _t('Отклонить', 'Бас тарту', 'Reject');
      default:
        return dash;
    }
  }

  String orderActionConfirm(String status) {
    switch (status) {
      case 'ACCEPTED':
        return _t('Принять этот заказ?', 'Осы тапсырысты қабылдайсыз ба?',
            'Accept this order?');
      case 'PREPARING':
        return _t('Начать приготовление?', 'Дайындауды бастайсыз ба?',
            'Start preparing?');
      case 'READY_FOR_PICKUP':
        return _t(
            'Заказ собран и готов к выдаче?',
            'Тапсырыс жиналып, беруге дайын ба?',
            'Is the order packed and ready?');
      case 'ON_THE_WAY':
        return _t('Заказ передан курьеру?', 'Тапсырыс курьерге берілді ме?',
            'Handed over to the courier?');
      case 'DELIVERED':
        return _t('Заказ получен клиентом?', 'Тапсырыс клиентке жетті ме?',
            'Did the customer receive the order?');
      default:
        return confirm;
    }
  }

  String get orderConfirmedToast => _t('Статус заказа обновлён',
      'Тапсырыс мәртебесі жаңартылды', 'Order status updated');
  String get cancelOrderTitle =>
      _t('Отклонить заказ', 'Тапсырыстан бас тарту', 'Reject order');
  String get cancelReasonLabel => _t('Причина (3–300 символов)',
      'Себебі (3–300 таңба)', 'Reason (3–300 characters)');
  String get reasonQuick1 =>
      _t('Блюдо закончилось', 'Тағам таусылды', 'Item is out of stock');
  String get reasonQuick2 =>
      _t('Кухня закрыта', 'Асхана жабық', 'Kitchen is closed');
  String get reasonQuick3 =>
      _t('Слишком много заказов', 'Тапсырыс тым көп', 'Too many orders');

  // ── Bookings ────────────────────────────────────────────────────────
  String bookingAction(String code) {
    switch (code) {
      case 'CONFIRM':
        return _t('Подтвердить', 'Растау', 'Confirm');
      case 'REJECT':
        return _t('Отклонить', 'Бас тарту', 'Reject');
      case 'CANCEL':
        return _t('Отменить запись', 'Жазылудан бас тарту', 'Cancel booking');
      case 'COMPLETE':
        return _t('Услуга оказана', 'Қызмет көрсетілді', 'Service done');
      case 'CHECK_IN':
        return _t('Принять автомобиль', 'Көлікті қабылдау', 'Check in the car');
      case 'START':
        return _t('Начать работы', 'Жұмысты бастау', 'Start work');
      case 'NO_SHOW':
        return _t(
            'Клиент не явился', 'Клиент келмеді', 'Customer did not come');
      case 'PROPOSE_PRICE':
        return _t('Предложить итоговую цену', 'Түпкілікті бағаны ұсыну',
            'Propose final price');
      default:
        return dash;
    }
  }

  String bookingActionConfirm(String code) {
    switch (code) {
      case 'CONFIRM':
        return _t(
            'Подтвердить запись? Клиент увидит новый статус.',
            'Жазылуды растайсыз ба? Клиент жаңа мәртебені көреді.',
            'Confirm the booking? The customer will see the new status.');
      case 'CHECK_IN':
        return _t(
            'Принять автомобиль клиента?',
            'Клиенттің көлігін қабылдайсыз ба?',
            'Check in the customer\'s car?');
      case 'START':
        return _t('Начать выполнение работ?', 'Жұмысты бастайсыз ба?',
            'Start the work?');
      case 'NO_SHOW':
        return _t(
            'Отметить, что клиент не пришёл?',
            'Клиент келмеді деп белгілейсіз бе?',
            'Mark the customer as a no-show?');
      case 'COMPLETE':
        return _t(
            'Отметить услугу как оказанную?',
            'Қызмет көрсетілді деп белгілейсіз бе?',
            'Mark the service as done?');
      default:
        return confirm;
    }
  }

  String get vehicleLabel => _t('Автомобиль', 'Көлік', 'Car');
  String get priceKindLabel => _t('Вид цены', 'Баға түрі', 'Price type');
  String priceKind(String kind) => switch (kind) {
        'FROM' => _t(
            'От, итог после осмотра',
            'Бастап, қорытынды тексеруден кейін',
            'From, final after inspection'),
        'DIAGNOSTIC' => _t('Диагностика, работы отдельно',
            'Диагностика, жұмыс бөлек', 'Diagnostics, work separate'),
        _ => _t('Итоговая', 'Түпкілікті', 'Final'),
      };
  String get finalPriceLabel =>
      _t('Итоговая цена', 'Түпкілікті баға', 'Final price');
  String priceApproval(String code) => switch (code) {
        'PENDING' => _t('ждёт согласия клиента', 'клиенттің келісімін күтеді',
            'waiting for the customer'),
        'APPROVED' => _t('согласована клиентом', 'клиент келісті',
            'approved by the customer'),
        'DECLINED' => _t(
            'клиент отклонил', 'клиент бас тартты', 'declined by the customer'),
        _ => code,
      };
  String get proposePriceTitle =>
      _t('Итоговая цена, ₸', 'Түпкілікті баға, ₸', 'Final price, ₸');
  String get proposePriceHint => _t(
      'Клиент должен согласовать цену до завершения.',
      'Аяқтамас бұрын клиент бағамен келісуі керек.',
      'The customer must approve the price before completion.');
  String get priceInvalid => _t(
      'Введите сумму от 0 до 1 000 000 ₸',
      '0–1 000 000 ₸ сомасын енгізіңіз',
      'Enter an amount from 0 to 1,000,000 ₸');
  String get timeOffTitle =>
      _t('Недоступные периоды', 'Қолжетімсіз кезеңдер', 'Unavailable periods');
  String get timeOffEmpty => _t('Недоступных периодов нет',
      'Қолжетімсіз кезеңдер жоқ', 'No unavailable periods');
  String get timeOffAdd => _t('Добавить период', 'Кезең қосу', 'Add a period');
  String get timeOffAllPosts => _t('Все посты', 'Барлық бекеттер', 'All posts');
  String get timeOffFrom => _t('Начало', 'Басы', 'Start');
  String get timeOffTo => _t('Конец', 'Соңы', 'End');
  String get timeOffReason => _t(
      'Причина (необязательно)', 'Себебі (міндетті емес)', 'Reason (optional)');
  String get timeOffRemove =>
      _t('Удалить период', 'Кезеңді жою', 'Remove period');
  String get timeOffOrderInvalid => _t('Конец должен быть позже начала',
      'Соңы басынан кеш болуы керек', 'The end must be after the start');
  String get editService =>
      _t('Изменить услугу', 'Қызметті өзгерту', 'Edit service');
  String get addService => _t('Добавить услугу', 'Қызмет қосу', 'Add service');
  String get addPost => _t('Добавить пост', 'Бекет қосу', 'Add post');
  String get postName => _t('Название поста', 'Бекет атауы', 'Post name');
  String get serviceDuration => _t('Длительность, мин (кратно 15)',
      'Ұзақтығы, мин (15-ке еселі)', 'Duration, min (multiple of 15)');
  String get serviceDurationInvalid => _t('15–240 минут, шаг 15',
      '15–240 минут, қадамы 15', '15–240 minutes, step 15');
  String get serviceConditions => _t('Условия (необязательно)',
      'Шарттар (міндетті емес)', 'Conditions (optional)');
  String get serviceCategory => _t('Категория', 'Санат', 'Category');
  String get autoCategoriesNote => _t(
      'Изменение цены не затрагивает уже созданные записи.',
      'Бағаның өзгеруі жасалған жазылуларға әсер етпейді.',
      'A price change does not affect existing bookings.');
  String autoCategory(String code) => switch (code) {
        'CAR_WASH' => _t('Автомойка', 'Көлік жуу', 'Car wash'),
        'TIRE' => _t('Шиномонтаж', 'Шина орнату', 'Tire service'),
        'OIL_CHANGE' => _t('Замена масла', 'Май ауыстыру', 'Oil change'),
        'DIAGNOSTICS' => _t('Диагностика', 'Диагностика', 'Diagnostics'),
        'MAINTENANCE' => _t('Техобслуживание', 'Техқызмет', 'Maintenance'),
        'REPAIR' => _t('Ремонт', 'Жөндеу', 'Repair'),
        'ROADSIDE' =>
          _t('Выездная помощь', 'Жолдағы көмек', 'Roadside assistance'),
        _ => _t('Другое', 'Басқа', 'Other'),
      };

  String get rejectBookingTitle =>
      _t('Отклонить заявку', 'Өтінімнен бас тарту', 'Reject request');
  String get cancelBookingTitle =>
      _t('Отменить запись', 'Жазылудан бас тарту', 'Cancel booking');
  String get bookingToast =>
      _t('Запись обновлена', 'Жазылу жаңартылды', 'Booking updated');

  // ── Orders screen ───────────────────────────────────────────────────
  String get tabNew => _t('Новые', 'Жаңа', 'New');
  String get tabInProgress => _t('В работе', 'Орындалуда', 'In progress');
  String get tabCompleted => _t('Завершённые', 'Аяқталған', 'Completed');
  String get tabRequests => _t('Заявки', 'Өтінімдер', 'Requests');
  String get tabUpcoming => _t('Предстоящие', 'Алдағы', 'Upcoming');
  String get tabHistory => _t('История', 'Тарих', 'History');
  String get ordersEmptyNewTitle =>
      _t('Новых заказов нет', 'Жаңа тапсырыс жоқ', 'No new orders');
  String get ordersEmptyNewBody => _t(
      'Когда клиент оформит заказ, он появится здесь со звуковым сигналом.',
      'Клиент тапсырыс бергенде, ол осында дыбыспен көрсетіледі.',
      'When a customer places an order it appears here with a sound alert.');
  String get ordersEmptyProgressTitle => _t('Нет заказов в работе',
      'Орындалуда тапсырыс жоқ', 'No orders in progress');
  String get ordersEmptyProgressBody => _t(
      'Принятые заказы будут показаны здесь до завершения.',
      'Қабылданған тапсырыстар аяқталғанша осында көрсетіледі.',
      'Accepted orders stay here until they are completed.');
  String get ordersEmptyDoneTitle => _t('Завершённых заказов пока нет',
      'Аяқталған тапсырыс әзірге жоқ', 'No completed orders yet');
  String get ordersEmptyDoneBody => _t(
      'Выполненные и отклонённые заказы сохраняются в истории.',
      'Орындалған және қабылданбаған тапсырыстар тарихта сақталады.',
      'Completed and rejected orders are kept in the history.');
  String orderNumber(String ref) =>
      _t('Заказ № $ref', 'Тапсырыс № $ref', 'Order #$ref');
  String itemsCount(int n) => _t('$n поз.', '$n зат', '$n items');
  String get orderItems =>
      _t('Состав заказа', 'Тапсырыс құрамы', 'Order items');
  String get subtotal => _t('Блюда', 'Тағамдар', 'Items');
  String get delivery => _t('Доставка', 'Жеткізу', 'Delivery');
  String get total => _t('Итого', 'Барлығы', 'Total');
  String get pickupLabel =>
      _t('Самовывоз', 'Өзі алып кетеді', 'Customer pickup');
  String get discountLabel => _t('Скидка', 'Жеңілдік', 'Discount');
  String get orderAddress =>
      _t('Адрес доставки', 'Жеткізу мекенжайы', 'Delivery address');
  String get orderComment =>
      _t('Комментарий клиента', 'Клиент пікірі', 'Customer comment');
  String get orderPayment => _t('Оплата', 'Төлем', 'Payment');
  String get orderPlacedAt => _t('Поступил', 'Түсті', 'Placed');
  String get orderDetails => _t('Заказ', 'Тапсырыс', 'Order');
  String get history =>
      _t('История статусов', 'Мәртебелер тарихы', 'Status history');
  String get cancelReasonTitle =>
      _t('Причина отмены', 'Бас тарту себебі', 'Cancellation reason');
  String get noItemsInfo => _t('Состав заказа недоступен',
      'Тапсырыс құрамы қолжетімсіз', 'Order items are unavailable');
  String paymentMethod(String? code) {
    switch (code) {
      case 'CASH_ON_DELIVERY':
        return _t(
            'Оплата при получении', 'Алған кезде төлеу', 'Pay on receipt');
      case 'TEST_CARD':
        return _t('Тестовая карта (демо)', 'Сынақ картасы (демо)',
            'Test card (demo)');
      default:
        return dash;
    }
  }

  String actorName(String? code) {
    switch (code) {
      case 'CUSTOMER':
        return _t('Клиент', 'Клиент', 'Customer');
      case 'PARTNER':
        return _t('Заведение', 'Мекеме', 'Business');
      case 'SYSTEM':
        return _t('Система', 'Жүйе', 'System');
      default:
        return dash;
    }
  }

  /// Cancellation reasons written by the system are shown in plain language.
  String reasonText(String reason) =>
      reason == 'PARTNER_TIMEOUT' ? timeoutReason : reason;
  String get timeoutReason => _t('Заведение не ответило вовремя',
      'Мекеме уақытында жауап бермеді', 'The business did not respond in time');

  String replyBy(String time) =>
      _t('Ответить до $time', '$time дейін жауап беріңіз', 'Reply by $time');
  String minutesLeftText(int m) =>
      _t('осталось $m мин', '$m мин қалды', '$m min left');
  String get replyOverdue =>
      _t('Время ответа истекло', 'Жауап уақыты өтті', 'Reply time is over');
  String agoMinutes(int m) => m < 1
      ? _t('только что', 'дәл қазір', 'just now')
      : _t('$m мин назад', '$m мин бұрын', '$m min ago');
  String get orderBusy => _t('Выполняется…', 'Орындалуда…', 'Working…');

  // ── Bookings screen ─────────────────────────────────────────────────
  String get bookingsEmptyRequestsTitle =>
      _t('Новых заявок нет', 'Жаңа өтінім жоқ', 'No new requests');
  String get bookingsEmptyRequestsBody => _t(
      'Заявки клиентов на запись появятся здесь.',
      'Клиенттердің жазылу өтінімдері осында көрсетіледі.',
      'Customer booking requests appear here.');
  String get bookingsEmptyUpcomingTitle => _t(
      'Предстоящих записей нет', 'Алдағы жазылу жоқ', 'No upcoming bookings');
  String get bookingsEmptyUpcomingBody => _t(
      'Подтверждённые записи будут показаны здесь.',
      'Расталған жазылулар осында көрсетіледі.',
      'Confirmed bookings are shown here.');
  String get bookingsEmptyHistoryTitle =>
      _t('История пуста', 'Тарих бос', 'History is empty');
  String get bookingsEmptyHistoryBody => _t(
      'Завершённые и отменённые записи сохраняются здесь.',
      'Аяқталған және бас тартылған жазылулар осында сақталады.',
      'Completed and cancelled bookings are kept here.');
  String get bookingsFilterEmptyTitle => _t('Нет записей по фильтру',
      'Сүзгі бойынша жазба жоқ', 'No bookings match the filter');
  String get bookingsFilterEmptyBody => _t('Измените дату или статус.',
      'Күнді немесе мәртебені өзгертіңіз.', 'Change the date or status.');
  String get filterDate => _t('Дата', 'Күні', 'Date');
  String get filterStatus => _t('Статус', 'Мәртебе', 'Status');
  String get bookingService => _t('Услуга', 'Қызмет', 'Service');
  String get bookingMaster => _t('Мастер', 'Шебер', 'Specialist');
  String get bookingPlace => _t('Заведение', 'Мекеме', 'Venue');
  String get bookingWhen =>
      _t('Дата и время', 'Күні мен уақыты', 'Date and time');
  String get bookingAddress =>
      _t('Адрес визита', 'Келу мекенжайы', 'Visit address');
  String get bookingComment =>
      _t('Комментарий клиента', 'Клиент пікірі', 'Customer comment');
  String get bookingPrice => _t('Стоимость', 'Құны', 'Price');
  String get durationLabel => _t('Длительность', 'Ұзақтығы', 'Duration');
  String get bookingDetails => _t('Запись', 'Жазылу', 'Booking');
  String minutesShort(int m) => _t('$m мин', '$m мин', '$m min');
  String get bookingCancelReasonTitle => _t('Причина', 'Себебі', 'Reason');
  String get requestedAt =>
      _t('Заявка создана', 'Өтінім жасалды', 'Request created');

  // ── Profile & settings ──────────────────────────────────────────────
  String get profileTitle => _t('Профиль', 'Профиль', 'Profile');
  String get yourRole => _t('Ваша роль', 'Сіздің рөліңіз', 'Your role');
  String get language => _t('Язык', 'Тіл', 'Language');
  String get languageAuto =>
      _t('Как в телефоне', 'Телефондағыдай', 'Same as phone');
  String get theme => _t('Тема', 'Тақырып', 'Theme');
  String get themeSystem => _t('Системная', 'Жүйелік', 'System');
  String get themeLight => _t('Светлая', 'Жарық', 'Light');
  String get themeDark => _t('Тёмная', 'Қараңғы', 'Dark');
  String get about => _t('О приложении', 'Қолданба туралы', 'About');
  String get devBuildNote => _t(
      'Тестовая сборка DEV: данные синтетические, платежей нет.',
      'DEV сынақ құрастыруы: деректер жасанды, төлемдер жоқ.',
      'DEV test build: data is synthetic, no payments.');
  String get notificationsNote => _t(
      'Оповещения о новых заказах работают, пока приложение открыто. Push в фоне пока недоступны.',
      'Жаңа тапсырыстар туралы хабарлама қолданба ашық кезде жұмыс істейді. Фондық push әзірге жоқ.',
      'New-order alerts work while the app is open. Background push is not available yet.');
  String get notifications => _t('Оповещения', 'Хабарламалар', 'Notifications');

  // ── Business ────────────────────────────────────────────────────────
  String get businessEmptyTitle =>
      _t('Каталог пока пуст', 'Каталог әзірге бос', 'Catalog is empty');
  String get businessEmptyBody => _t(
      'К вашему заведению ещё не подключены меню или услуги.',
      'Мекемеңізге әлі мәзір не қызметтер қосылмаған.',
      'No menu or services are linked to your business yet.');
  String get openNow => _t('Открыто', 'Ашық', 'Open');
  String get closedNow => _t('Закрыто', 'Жабық', 'Closed');

  // ── Alerts ──────────────────────────────────────────────────────────
  String alertNewOrders(int n) => n == 1
      ? _t('Новый заказ', 'Жаңа тапсырыс', 'New order')
      : _t('Новых заказов: $n', 'Жаңа тапсырыстар: $n', '$n new orders');
  String alertNewBookings(int n) => n == 1
      ? _t('Новая заявка на запись', 'Жазылуға жаңа өтінім',
          'New booking request')
      : _t('Новых заявок: $n', 'Жаңа өтінімдер: $n', '$n new booking requests');
  String get open => _t('Открыть', 'Ашу', 'Open');

  // ── Dashboard ───────────────────────────────────────────────────────
  String greeting(int hour) {
    if (hour >= 5 && hour < 12) {
      return _t('Доброе утро', 'Қайырлы таң', 'Good morning');
    }
    if (hour >= 12 && hour < 18) {
      return _t('Добрый день', 'Қайырлы күн', 'Good afternoon');
    }
    if (hour >= 18 && hour < 23) {
      return _t('Добрый вечер', 'Қайырлы кеш', 'Good evening');
    }
    return _t('Доброй ночи', 'Қайырлы түн', 'Good night');
  }

  String get dashAttentionTitle =>
      _t('Требует внимания', 'Назар аударуды қажет етеді', 'Needs attention');
  String get dashAllClearTitle => _t('Всё спокойно', 'Бәрі тыныш', 'All clear');
  String get dashAllClearBody => _t('Новых заказов и заявок нет.',
      'Жаңа тапсырыс пен өтінім жоқ.', 'No new orders or requests.');
  String dashNewOrdersLine(int n) =>
      _t('Новых заказов: $n', 'Жаңа тапсырыстар: $n', 'New orders: $n');
  String dashRequestsLine(int n) => _t(
      'Заявок на запись: $n', 'Жазылу өтінімдері: $n', 'Booking requests: $n');
  String get dashToday => _t('Сегодня', 'Бүгін', 'Today');
  String get kpiNewOrders =>
      _t('Новые заказы', 'Жаңа тапсырыстар', 'New orders');
  String get kpiActiveOrders =>
      _t('Заказы в работе', 'Орындалудағы тапсырыстар', 'Orders in progress');
  String get kpiRequests =>
      _t('Заявки на запись', 'Жазылу өтінімдері', 'Booking requests');
  String get kpiUpcoming =>
      _t('Предстоящие записи', 'Алдағы жазылулар', 'Upcoming bookings');
  String get kpiCompleted =>
      _t('Завершено сегодня', 'Бүгін аяқталды', 'Completed today');
  String get kpiRevenue =>
      _t('Выручка за день', 'Күндік түсім', 'Revenue today');
  String get kpiRevenueNote => _t('по завершённым заказам',
      'аяқталған тапсырыстар бойынша', 'from completed orders');
  String get kpiRevenuePartial => _t(
      'не менее, загружена часть истории',
      'кемінде, тарихтың бір бөлігі жүктелген',
      'at least — part of the history is loaded');
  String get quickActions =>
      _t('Быстрые действия', 'Жылдам әрекеттер', 'Quick actions');
  String get recentEvents =>
      _t('Последние события', 'Соңғы оқиғалар', 'Recent events');
  String get noEvents =>
      _t('Событий пока нет', 'Оқиғалар әзірге жоқ', 'No events yet');
  String eventOrder(String ref, String status) => _t(
      'Заказ № $ref — ${orderStatus(status).toLowerCase()}',
      'Тапсырыс № $ref — ${orderStatus(status).toLowerCase()}',
      'Order #$ref — ${orderStatus(status).toLowerCase()}');
  String eventBooking(String service, String status) => _t(
      '$service — ${bookingStatus(status).toLowerCase()}',
      '$service — ${bookingStatus(status).toLowerCase()}',
      '$service — ${bookingStatus(status).toLowerCase()}');
  String get lastUpdated => _t('Обновлено', 'Жаңартылды', 'Updated');

  // ── Business management ─────────────────────────────────────────────
  String get restaurantsTitle =>
      _t('Рестораны', 'Мейрамханалар', 'Restaurants');
  String get venuesTitle =>
      _t('Услуги и записи', 'Қызметтер мен жазылулар', 'Services & bookings');
  String get openForOrders =>
      _t('Принимает заказы', 'Тапсырыс қабылдайды', 'Accepting orders');
  String get openForBookings =>
      _t('Принимает записи', 'Жазылу қабылдайды', 'Accepting bookings');
  String get menuTitle =>
      _t('Меню и цены', 'Мәзір мен бағалар', 'Menu & prices');
  String get servicesTitle => _t('Услуги', 'Қызметтер', 'Services');
  String get mastersTitle => _t('Мастера и сотрудники',
      'Шеберлер мен қызметкерлер', 'Specialists & staff');
  String get menuEmpty => _t('В меню пока нет блюд', 'Мәзірде әзірге тағам жоқ',
      'The menu has no dishes yet');
  String get servicesEmpty =>
      _t('Услуг пока нет', 'Қызметтер әзірге жоқ', 'No services yet');
  String get mastersEmpty =>
      _t('Мастеров пока нет', 'Шеберлер әзірге жоқ', 'No specialists yet');
  String get dishAvailable => _t('В наличии', 'Қолжетімді', 'Available');
  String get dishUnavailable => _t('Нет в наличии', 'Жоқ', 'Unavailable');
  String stockLeft(int n) => _t('Остаток: $n', 'Қалдық: $n', 'In stock: $n');
  String get addDish => _t('Добавить блюдо', 'Тағам қосу', 'Add dish');
  String get restaurantSettings =>
      _t('Условия заказа', 'Тапсырыс шарттары', 'Ordering settings');
  String get pickupSetting =>
      _t('Принимать самовывоз', 'Өзі алып кетуді қабылдау', 'Accept pickup');
  String prepTime(int m) => _t('Время готовности: $m мин',
      'Дайындау уақыты: $m мин', 'Preparation time: $m min');
  String get promotionsTitle => _t('Акции', 'Акциялар', 'Promotions');
  String get promotionsEmpty =>
      _t('Акций пока нет', 'Акциялар әлі жоқ', 'No promotions yet');
  String get promotionNew => _t('Новая акция', 'Жаңа акция', 'New promotion');
  String get promotionTitleLabel =>
      _t('Название акции', 'Акция атауы', 'Promotion title');
  String get promotionCodeLabel => _t('Промокод (необязательно)',
      'Промокод (міндетті емес)', 'Promo code (optional)');
  String get promotionPercent => _t('Процент', 'Пайыз', 'Percent');
  String get promotionFixed => _t('Сумма', 'Сома', 'Amount');
  String get promotionValueLabel => _t('Размер скидки (% или ₸)',
      'Жеңілдік мөлшері (% немесе ₸)', 'Discount (% or ₸)');
  String get promotionDaysLabel =>
      _t('Срок, дней (1–90)', 'Мерзімі, күн (1–90)', 'Duration, days (1–90)');
  String get promotionLimits => _t(
      'Для партнёра: скидка до 50 % или до 5 000 ₸, срок до 90 дней.',
      'Серіктес үшін: 50 %-ға дейін немесе 5 000 ₸-ге дейін, 90 күнге дейін.',
      'For partners: up to 50 % or 5,000 ₸, up to 90 days.');
  String get promotionPause => _t('Приостановить', 'Тоқтата тұру', 'Pause');
  String get promotionResume => _t('Возобновить', 'Жалғастыру', 'Resume');
  String get promotionCreate => _t('Создать', 'Жасау', 'Create');
  String get editDish => _t('Изменить блюдо', 'Тағамды өзгерту', 'Edit dish');
  String get dishName => _t('Название', 'Атауы', 'Name');
  String get dishDescription => _t('Описание (необязательно)',
      'Сипаттама (міндетті емес)', 'Description (optional)');
  String get dishPrice => _t('Цена, ₸', 'Бағасы, ₸', 'Price, ₸');
  String get dishSection => _t('Раздел меню', 'Мәзір бөлімі', 'Menu section');
  String get dishStock => _t('Остаток (пусто — без ограничения)',
      'Қалдық (бос — шектеусіз)', 'Stock (empty — unlimited)');
  String get dishNameInvalid => _t('Название: от 2 до 160 символов',
      'Атауы: 2–160 таңба', 'Name: 2 to 160 characters');
  String get dishPriceInvalid => _t('Цена: от 0 до 1 000 000 ₸',
      'Бағасы: 0–1 000 000 ₸', 'Price: 0 to 1,000,000 ₸');
  String get dishStockInvalid => _t('Остаток: целое число от 0 до 100 000',
      'Қалдық: 0–100 000 бүтін сан', 'Stock: a whole number from 0 to 100,000');
  String get dishSaved => _t('Сохранено', 'Сақталды', 'Saved');
  String get dishNoSection => _t(
      'Чтобы добавить блюдо, в меню должен быть хотя бы один раздел.',
      'Тағам қосу үшін мәзірде кемінде бір бөлім болуы керек.',
      'A menu section must exist before you can add a dish.');
  String get ownerOnlyEdit => _t(
      'Менять цены и названия могут владелец и менеджер.',
      'Баға мен атауды иесі мен менеджер өзгерте алады.',
      'Only the owner and managers can change prices and names.');
  String get scheduleTitle =>
      _t('График работы', 'Жұмыс кестесі', 'Working hours');
  String get dayOff => _t('Выходной', 'Демалыс', 'Day off');
  String get breakLabel => _t('Перерыв', 'Үзіліс', 'Break');
  String get workingDay => _t('Рабочий день', 'Жұмыс күні', 'Working day');
  String get fromLabel => _t('С', 'Бастап', 'From');
  String get toLabel => _t('До', 'Дейін', 'To');
  String get addBreak => _t('Добавить перерыв', 'Үзіліс қосу', 'Add a break');
  String get removeBreak =>
      _t('Убрать перерыв', 'Үзілісті алып тастау', 'Remove break');
  String get scheduleSaved =>
      _t('График сохранён', 'Кесте сақталды', 'Schedule saved');
  String get scheduleInvalid => _t(
      'Проверьте время: конец позже начала, перерыв внутри дня.',
      'Уақытты тексеріңіз: аяқталуы басталуынан кейін, үзіліс күн ішінде.',
      'Check the times: end after start, break inside the day.');
  String get slotsNote => _t(
      'Свободные слоты для клиентов формируются автоматически по графику мастера и существующим записям.',
      'Клиенттерге арналған бос уақыттар шебердің кестесі мен бар жазылулар бойынша автоматты түрде құрылады.',
      'Free slots for customers are generated automatically from the specialist\'s schedule and existing bookings.');
  String get editSchedule =>
      _t('Изменить график', 'Кестені өзгерту', 'Edit schedule');
  String get active => _t('Работает', 'Жұмыс істейді', 'Active');
  String get inactive => _t('Не работает', 'Жұмыс істемейді', 'Not working');
  String get toggleFailed => _t('Не удалось сохранить изменение',
      'Өзгерісті сақтау мүмкін болмады', 'Could not save the change');
  String weekday(int day) {
    const ru = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье'
    ];
    const kk = [
      'Дүйсенбі',
      'Сейсенбі',
      'Сәрсенбі',
      'Бейсенбі',
      'Жұма',
      'Сенбі',
      'Жексенбі'
    ];
    const en = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final i = (day - 1).clamp(0, 6);
    return _t(ru[i], kk[i], en[i]);
  }

  // ── Misc shared ─────────────────────────────────────────────────────
  String get logout => _t('Выйти', 'Шығу', 'Sign out');
  String get logoutConfirm => _t('Выйти из аккаунта партнёра?',
      'Серіктес аккаунтынан шығасыз ба?', 'Sign out of the partner account?');
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();
  @override
  bool isSupported(Locale locale) =>
      S.supported.any((l) => l.languageCode == locale.languageCode);
  @override
  Future<S> load(Locale locale) async => S(locale);
  @override
  bool shouldReload(covariant LocalizationsDelegate<S> old) => false;
}
