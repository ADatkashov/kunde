import 'package:flutter/material.dart';

class RideStrings {
  RideStrings(BuildContext context)
      : language = Localizations.localeOf(context).languageCode;

  final String language;

  String t(String ru, String kk, String en) => switch (language) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  String get rides => t('Поездки', 'Сапарлар', 'Rides');
  String get pickup => t('Откуда', 'Қайдан', 'Pickup');
  String get destination => t('Куда', 'Қайда', 'Destination');
  String get synthetic => t('Тестовый маршрут', 'Сынақ бағыты', 'Test route');
  String get history => t('История', 'Тарих', 'History');
  String get search => t('Найти адрес', 'Мекенжайды іздеу', 'Find address');
  String get quote => t('Узнать стоимость', 'Бағасын білу', 'Get fare');
  String get confirm =>
      t('Заказать поездку', 'Сапарға тапсырыс беру', 'Request ride');
  String get error => t(
        'Не удалось выполнить запрос. Попробуйте ещё раз.',
        'Сұрау орындалмады. Қайталап көріңіз.',
        'The request failed. Try again.',
      );
  String get unavailable => t(
        'Маршруты сейчас недоступны.',
        'Бағыттар қазір қолжетімсіз.',
        'Routing is currently unavailable.',
      );
  String get retry => t('Повторить', 'Қайталау', 'Retry');
  String get noAddresses =>
      t('Адресов не найдено', 'Мекенжай табылмады', 'No addresses found');
  String get noRides =>
      t('Поездок пока нет', 'Сапарлар әлі жоқ', 'No rides yet');
  String get cancel =>
      t('Отменить поездку', 'Сапардан бас тарту', 'Cancel ride');
  String get back => t('Назад', 'Артқа', 'Back');

  String get hubTagline => t(
        'Быстро, удобно и безопасно по Алматы',
        'Алматы бойынша жылдам, ыңғайлы әрі қауіпсіз',
        'Fast, convenient and safe across Almaty',
      );
  String get soon => t('Скоро', 'Жақында', 'Soon');
  String get fareLabel => t('Стоимость', 'Құны', 'Fare');
  String get tariffLabel => t('Тариф', 'Тариф', 'Fare class');
  String get driverLabel => t('Водитель', 'Жүргізуші', 'Driver');
  String get done => t('Готово', 'Дайын', 'Done');
  String get support => t('Поддержка', 'Қолдау', 'Support');
  String get searchingTitle =>
      t('Ищем водителя...', 'Жүргізуші ізделуде...', 'Finding a driver...');
  String get searchingHint => t(
        'Обычно это занимает до 1 минуты',
        'Әдетте бұл 1 минутқа дейін созылады',
        'This usually takes up to 1 minute',
      );
  String get stepSend => t(
        'Отправляем ваш заказ водителям',
        'Тапсырысыңызды жүргізушілерге жібереміз',
        'Sending your request to drivers',
      );
  String get stepMatch => t(
        'Подбираем ближайшего',
        'Ең жақынын таңдаймыз',
        'Matching the nearest driver',
      );
  String get stepConfirm => t(
        'Подтверждаем поездку',
        'Сапарды растаймыз',
        'Confirming the ride',
      );
  String get completedTitle =>
      t('Поездка завершена!', 'Сапар аяқталды!', 'Ride complete!');
  String get tripDate => t('Дата', 'Күні', 'Date');

  String hubTitle(String key) => switch (key) {
        'city' => t('По городу', 'Қала бойынша', 'City rides'),
        'airport' => t('В аэропорт', 'Әуежайға', 'To the airport'),
        'intercity' => t('Межгород', 'Қалааралық', 'Intercity'),
        'rental' => t('Аренда авто', 'Көлік жалдау', 'Car rental'),
        _ => t('Курьер', 'Курьер', 'Courier'),
      };

  String hubSubtitle(String key) => switch (key) {
        'city' => t(
            'Поездки в пределах города',
            'Қала ішіндегі сапарлар',
            'Trips within the city',
          ),
        'airport' => t(
            'Трансфер в/из аэропорта',
            'Әуежайға/әуежайдан трансфер',
            'Airport transfer',
          ),
        'intercity' => t(
            'Поездки между городами',
            'Қалалар арасындағы сапарлар',
            'Trips between cities',
          ),
        'rental' => t(
            'Краткосрочная и долгосрочная',
            'Қысқа және ұзақ мерзімді',
            'Short and long term',
          ),
        _ => t(
            'Доставка посылок и документов',
            'Сәрмен мен құжат жеткізу',
            'Parcels and documents',
          ),
      };

  String tariffHint(String value) => switch (value) {
        'ECONOMY' => t('Недорогая поездка', 'Үнемді сапар', 'Affordable ride'),
        'COMFORT' => t('Больше места и комфорта', 'Көбірек орын мен жайлылық',
            'More room'),
        _ => t('Премиальный автомобиль', 'Премиум көлік', 'Premium car'),
      };

  String rideClass(String value) => switch (value) {
        'ECONOMY' => t('Эконом', 'Эконом', 'Economy'),
        'COMFORT' => t('Комфорт', 'Комфорт', 'Comfort'),
        _ => t('Бизнес', 'Бизнес', 'Business'),
      };

  String status(String value) => switch (value) {
        'REQUESTED' => t('Заявка создана', 'Өтінім жасалды', 'Ride requested'),
        'SEARCHING_DRIVER' => t(
            'Ищем водителя',
            'Жүргізуші ізделуде',
            'Finding a driver',
          ),
        'DRIVER_ASSIGNED' => t(
            'Водитель назначен',
            'Жүргізуші тағайындалды',
            'Driver assigned',
          ),
        'DRIVER_ARRIVING' => t(
            'Водитель в пути',
            'Жүргізуші жолда',
            'Driver is on the way',
          ),
        'DRIVER_ARRIVED' => t(
            'Водитель прибыл',
            'Жүргізуші келді',
            'Driver arrived',
          ),
        'IN_PROGRESS' =>
          t('Вы в поездке', 'Сапар жүріп жатыр', 'Ride in progress'),
        'COMPLETED' =>
          t('Поездка завершена', 'Сапар аяқталды', 'Ride complete'),
        'NO_DRIVER_AVAILABLE' => t(
            'Нет свободных водителей',
            'Бос жүргізуші жоқ',
            'No drivers available',
          ),
        'CANCELLED_BY_CUSTOMER' ||
        'CANCELLED_BY_DRIVER' ||
        'CANCELLED_BY_SYSTEM' =>
          t('Поездка отменена', 'Сапар тоқтатылды', 'Ride cancelled'),
        _ => t('Поездка недоступна', 'Сапар қолжетімсіз', 'Ride unavailable'),
      };
}
