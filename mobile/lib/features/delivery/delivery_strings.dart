import 'package:flutter/material.dart';

class DeliveryStrings {
  DeliveryStrings(BuildContext context)
      : language = Localizations.localeOf(context).languageCode;

  final String language;

  String t(String ru, String kk, String en) => switch (language) {
        'ru' => ru,
        'kk' => kk,
        _ => en,
      };

  String get title => t('Доставка', 'Жеткізу', 'Delivery');
  String get pickup => t('Откуда забрать', 'Алып кету мекенжайы', 'Pickup');
  String get destination =>
      t('Куда доставить', 'Жеткізу мекенжайы', 'Destination');
  String get history =>
      t('История отправлений', 'Жөнелтілімдер тарихы', 'Shipment history');
  String get retry => t('Повторить', 'Қайталау', 'Retry');
  String get error => t(
      'Не удалось выполнить запрос. Повторите попытку.',
      'Сұрауды орындау мүмкін болмады. Қайталап көріңіз.',
      'The request failed. Try again.');
  String get testRoute => t('DEV/TEST · тестовый маршрут',
      'DEV/TEST · сынақ бағыты', 'DEV/TEST · synthetic route');
  String get required => t('Заполните поле', 'Өрісті толтырыңыз', 'Required');
  String get cancel =>
      t('Отменить доставку', 'Жеткізуден бас тарту', 'Cancel delivery');
  String get close => t('Закрыть', 'Жабу', 'Close');

  String parcel(String type) => switch (type) {
        'DOCUMENTS' => t('Документы', 'Құжаттар', 'Documents'),
        'SMALL_PARCEL' => t('Малая посылка', 'Шағын сәлемдеме', 'Small parcel'),
        'MEDIUM_PARCEL' =>
          t('Средняя посылка', 'Орташа сәлемдеме', 'Medium parcel'),
        'PERSONAL_ITEMS' => t('Личные вещи', 'Жеке заттар', 'Personal items'),
        _ => t('Другие разрешённые вещи', 'Басқа рұқсат етілген заттар',
            'Other allowed goods'),
      };

  String status(String state) => switch (state) {
        'CREATED' => t('Создано', 'Жасалды', 'Created'),
        'SEARCHING_COURIER' =>
          t('Ищем курьера', 'Курьер ізделуде', 'Finding a courier'),
        'COURIER_ASSIGNED' =>
          t('Курьер назначен', 'Курьер тағайындалды', 'Courier assigned'),
        'COURIER_ARRIVING' => t('Курьер едет за посылкой',
            'Курьер алып кетуге шықты', 'Courier on the way'),
        'COURIER_ARRIVED' =>
          t('Курьер прибыл', 'Курьер келді', 'Courier arrived'),
        'PICKED_UP' => t('Посылку забрали', 'Сәлемдеме алынды', 'Picked up'),
        'IN_TRANSIT' =>
          t('В пути к получателю', 'Алушыға бара жатыр', 'In transit'),
        'DELIVERED' =>
          t('Вручение подтверждено', 'Тапсыру расталды', 'Handoff confirmed'),
        'COMPLETED' => t('Доставка завершена', 'Жеткізу аяқталды', 'Completed'),
        'NO_COURIER_AVAILABLE' =>
          t('Курьер не найден', 'Курьер табылмады', 'No courier available'),
        'PICKUP_FAILED' =>
          t('Не удалось забрать', 'Алып кету мүмкін болмады', 'Pickup failed'),
        'DELIVERY_FAILED' =>
          t('Не удалось вручить', 'Тапсыру мүмкін болмады', 'Handoff failed'),
        'RETURN_REQUESTED' =>
          t('Назначен возврат', 'Қайтару тағайындалды', 'Return requested'),
        'RETURNING' => t('Возвращается отправителю', 'Жіберушіге қайтарылуда',
            'Returning to sender'),
        'RETURNED_TO_SENDER' => t('Возвращено отправителю',
            'Жіберушіге қайтарылды', 'Returned to sender'),
        'DISPUTED' =>
          t('Обращение на рассмотрении', 'Өтініш қаралуда', 'Under review'),
        'CANCELLED_BY_CUSTOMER' ||
        'CANCELLED_BY_COURIER' ||
        'CANCELLED_BY_SYSTEM' =>
          t('Отменено', 'Бас тартылды', 'Cancelled'),
        _ => t('Статус недоступен', 'Күйі қолжетімсіз', 'Status unavailable'),
      };
}
