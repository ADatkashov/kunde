import 'package:flutter/widgets.dart';

/// RU / KK / EN texts of the Groceries screens. Server data (product and category names) is shown as the server
/// returns it; categories carry their own RU/KK/EN names.
class GStr {
  GStr(this.language);

  factory GStr.of(BuildContext context) =>
      GStr(Localizations.localeOf(context).languageCode);

  final String language;

  String _t(String key) {
    final entry = _texts[key];
    if (entry == null) return key;
    return switch (language) {
      'kk' => entry.$2,
      'en' => entry.$3,
      _ => entry.$1,
    };
  }

  String get title => _t('title');
  String get subtitle => _t('subtitle');
  String get city => _t('city');
  String get searchHint => _t('searchHint');
  String get promos => _t('promos');
  String get newItems => _t('newItems');
  String get myLists => _t('myLists');
  String get favorites => _t('favorites');
  String get categories => _t('categories');
  String get all => _t('all');
  String get popular => _t('popular');
  String get discounts => _t('discounts');
  String get seeAll => _t('seeAll');
  String get sortLabel => _t('sortLabel');
  String get filters => _t('filters');
  String get inStock => _t('inStock');
  String get onSale => _t('onSale');
  String get newOnly => _t('newOnly');
  String get store => _t('store');
  String get brand => _t('brand');
  String get price => _t('price');
  String get priceFrom => _t('priceFrom');
  String get priceTo => _t('priceTo');
  String get reset => _t('reset');
  String get apply => _t('apply');
  String get nothingFound => _t('nothingFound');
  String get nothingFoundHint => _t('nothingFoundHint');
  String get retry => _t('retry');
  String get loadMore => _t('loadMore');
  String get unavailable => _t('unavailable');
  String get outOfStock => _t('outOfStock');
  String get storeClosed => _t('storeClosed');
  String get add => _t('add');
  String get addToCart => _t('addToCart');
  String get added => _t('added');
  String get toCart => _t('toCart');
  String get description => _t('description');
  String get composition => _t('composition');
  String get nutrition => _t('nutrition');
  String get per100 => _t('per100');
  String get kcal => _t('kcal');
  String get protein => _t('protein');
  String get fat => _t('fat');
  String get carbs => _t('carbs');
  String get storage => _t('storage');
  String get origin => _t('origin');
  String get related => _t('related');
  String get weighedNote => _t('weighedNote');
  String get share => _t('share');
  String get linkCopied => _t('linkCopied');
  String get favAdded => _t('favAdded');
  String get favRemoved => _t('favRemoved');
  String get newBadge => _t('newBadge');
  String get cartConflictTitle => _t('cartConflictTitle');
  String get cartConflictBody => _t('cartConflictBody');
  String get replaceCart => _t('replaceCart');
  String get cancel => _t('cancel');
  String get emptyFavorites => _t('emptyFavorites');
  String get emptyFavoritesHint => _t('emptyFavoritesHint');
  String get emptyLists => _t('emptyLists');
  String get emptyListsHint => _t('emptyListsHint');
  String get newList => _t('newList');
  String get listName => _t('listName');
  String get create => _t('create');
  String get rename => _t('rename');
  String get delete => _t('delete');
  String get listEmpty => _t('listEmpty');
  String get addListToCart => _t('addListToCart');
  String get addToList => _t('addToList');
  String get itemsWord => _t('itemsWord');
  String get skippedTitle => _t('skippedTitle');
  String get reasonUnavailable => _t('reasonUnavailable');
  String get reasonBought => _t('reasonBought');
  String get reasonOtherStore => _t('reasonOtherStore');
  String get reasonCartFull => _t('reasonCartFull');
  String get signInNeeded => _t('signInNeeded');
  String get disabledTitle => _t('disabledTitle');
  String get disabledBody => _t('disabledBody');
  String get cartNotSynced => _t('cartNotSynced');
  String get sortPopularity => _t('sortPopularity');
  String get sortPriceAsc => _t('sortPriceAsc');
  String get sortPriceDesc => _t('sortPriceDesc');
  String get sortNew => _t('sortNew');
  String get sortDiscount => _t('sortDiscount');
  String get fromStore => _t('fromStore');
  String get requiredLabel => _t('required');
  String get quantity => _t('quantity');
  String get total => _t('total');

  String productsCount(int n) => switch (language) {
        'kk' => '$n тауар',
        'en' => n == 1 ? '1 product' : '$n products',
        _ => '$n ${_plural(n, 'товар', 'товара', 'товаров')}',
      };

  String listItems(int n, int checked) => switch (language) {
        'kk' => '$n тауар · $checked сатып алынды',
        'en' => '$n items · $checked bought',
        _ =>
          '$n ${_plural(n, 'товар', 'товара', 'товаров')} · куплено $checked',
      };

  String sortName(String sort) => switch (sort) {
        'price_asc' => sortPriceAsc,
        'price_desc' => sortPriceDesc,
        'new' => sortNew,
        'discount' => sortDiscount,
        _ => sortPopularity,
      };

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  static const _texts = <String, (String, String, String)>{
    'title': ('Продукты', 'Азық-түлік', 'Groceries'),
    'subtitle': (
      'Свежие продукты, напитки и товары для дома',
      'Балғын өнімдер, сусындар және үй тауарлары',
      'Fresh food, drinks and home essentials'
    ),
    'city': ('Алматы', 'Алматы', 'Almaty'),
    'searchHint': (
      'Найти продукт или категорию',
      'Тауар немесе санат іздеу',
      'Search products or categories'
    ),
    'promos': ('Акции', 'Акциялар', 'Deals'),
    'newItems': ('Новинки', 'Жаңалықтар', 'New'),
    'myLists': ('Мои списки', 'Тізімдерім', 'My lists'),
    'favorites': ('Избранное', 'Таңдаулылар', 'Favorites'),
    'categories': ('Категории', 'Санаттар', 'Categories'),
    'all': ('Все', 'Барлығы', 'All'),
    'popular': ('Популярное', 'Танымал', 'Popular'),
    'discounts': ('Скидки', 'Жеңілдіктер', 'Discounts'),
    'seeAll': ('Все', 'Барлығы', 'See all'),
    'sortLabel': ('Сортировка', 'Сұрыптау', 'Sort'),
    'filters': ('Фильтры', 'Сүзгілер', 'Filters'),
    'inStock': ('В наличии', 'Қолда бар', 'In stock'),
    'onSale': ('Со скидкой', 'Жеңілдікпен', 'On sale'),
    'newOnly': ('Новинки', 'Жаңалықтар', 'New'),
    'store': ('Магазин', 'Дүкен', 'Store'),
    'brand': ('Бренд', 'Бренд', 'Brand'),
    'price': ('Цена, ₸', 'Бағасы, ₸', 'Price, ₸'),
    'priceFrom': ('от', 'бастап', 'from'),
    'priceTo': ('до', 'дейін', 'to'),
    'reset': ('Сбросить', 'Тазалау', 'Reset'),
    'apply': ('Применить', 'Қолдану', 'Apply'),
    'nothingFound': ('Ничего не найдено', 'Ештеңе табылмады', 'Nothing found'),
    'nothingFoundHint': (
      'Измените запрос или сбросьте фильтры',
      'Сұранысты өзгертіңіз немесе сүзгілерді тазалаңыз',
      'Change the query or reset the filters'
    ),
    'retry': ('Повторить', 'Қайталау', 'Retry'),
    'loadMore': ('Показать ещё', 'Тағы көрсету', 'Show more'),
    'unavailable': ('Недоступен', 'Қолжетімсіз', 'Unavailable'),
    'outOfStock': ('Нет в наличии', 'Қолда жоқ', 'Out of stock'),
    'storeClosed': ('Магазин закрыт', 'Дүкен жабық', 'Store closed'),
    'add': ('Добавить', 'Қосу', 'Add'),
    'addToCart': ('Добавить в корзину', 'Себетке қосу', 'Add to cart'),
    'added': ('Добавлено в корзину', 'Себетке қосылды', 'Added to cart'),
    'toCart': ('В корзину', 'Себетке', 'Cart'),
    'description': ('Описание', 'Сипаттама', 'Description'),
    'composition': ('Состав', 'Құрамы', 'Composition'),
    'nutrition': ('Пищевая ценность', 'Тағамдық құндылығы', 'Nutrition'),
    'per100': ('на 100 г', '100 г үшін', 'per 100 g'),
    'kcal': ('ккал', 'ккал', 'kcal'),
    'protein': ('Белки', 'Ақуыз', 'Protein'),
    'fat': ('Жиры', 'Май', 'Fat'),
    'carbs': ('Углеводы', 'Көмірсу', 'Carbs'),
    'storage': ('Условия хранения', 'Сақтау шарттары', 'Storage'),
    'origin': ('Страна происхождения', 'Шыққан елі', 'Country of origin'),
    'related': ('Похожие товары', 'Ұқсас тауарлар', 'Related products'),
    'weighedNote': (
      'Окончательная цена фиксируется при заказе; изменения веса согласуются с вами.',
      'Түпкілікті баға тапсырыста бекітіледі; салмақ өзгерісі сізбен келісіледі.',
      'The final price is fixed at checkout; weight changes are agreed with you.'
    ),
    'share': ('Поделиться', 'Бөлісу', 'Share'),
    'linkCopied': (
      'Описание товара скопировано',
      'Тауар сипаттамасы көшірілді',
      'Product details copied'
    ),
    'favAdded': (
      'Добавлено в избранное',
      'Таңдаулыларға қосылды',
      'Added to favorites'
    ),
    'favRemoved': (
      'Удалено из избранного',
      'Таңдаулылардан жойылды',
      'Removed from favorites'
    ),
    'newBadge': ('Новинка', 'Жаңа', 'New'),
    'cartConflictTitle': (
      'Заменить корзину?',
      'Себетті ауыстыру керек пе?',
      'Replace the cart?'
    ),
    'cartConflictBody': (
      'В корзине товары другого магазина. Чтобы добавить этот товар, корзину нужно очистить.',
      'Себетте басқа дүкеннің тауарлары бар. Бұл тауарды қосу үшін себетті тазарту керек.',
      'Your cart has items from another store. Clear it to add this product.'
    ),
    'replaceCart': ('Очистить и добавить', 'Тазалап қосу', 'Clear and add'),
    'cancel': ('Отмена', 'Бас тарту', 'Cancel'),
    'emptyFavorites': ('Пока пусто', 'Әзірге бос', 'Nothing here yet'),
    'emptyFavoritesHint': (
      'Нажмите на сердечко у товара, чтобы сохранить его',
      'Тауарды сақтау үшін жүрекшені басыңыз',
      'Tap the heart on a product to save it'
    ),
    'emptyLists': ('Списков пока нет', 'Тізімдер әзірге жоқ', 'No lists yet'),
    'emptyListsHint': (
      'Создайте список покупок и добавляйте в него товары',
      'Сатып алу тізімін жасап, тауар қосыңыз',
      'Create a shopping list and add products to it'
    ),
    'newList': ('Новый список', 'Жаңа тізім', 'New list'),
    'listName': ('Название списка', 'Тізім атауы', 'List name'),
    'create': ('Создать', 'Жасау', 'Create'),
    'rename': ('Переименовать', 'Атауын өзгерту', 'Rename'),
    'delete': ('Удалить', 'Жою', 'Delete'),
    'listEmpty': ('Список пуст', 'Тізім бос', 'The list is empty'),
    'addListToCart': ('Добавить в корзину', 'Себетке қосу', 'Add to cart'),
    'addToList': ('В список', 'Тізімге', 'Add to list'),
    'itemsWord': ('товаров', 'тауар', 'items'),
    'skippedTitle': ('Не добавлено', 'Қосылмады', 'Not added'),
    'reasonUnavailable': ('нет в наличии', 'қолда жоқ', 'unavailable'),
    'reasonBought': ('уже куплено', 'сатып алынған', 'already bought'),
    'reasonOtherStore': ('другой магазин', 'басқа дүкен', 'other store'),
    'reasonCartFull': ('корзина заполнена', 'себет толы', 'cart is full'),
    'signInNeeded': (
      'Войдите, чтобы продолжить',
      'Жалғастыру үшін кіріңіз',
      'Sign in to continue'
    ),
    'disabledTitle': (
      'Продукты временно недоступны',
      'Азық-түлік уақытша қолжетімсіз',
      'Groceries is temporarily unavailable'
    ),
    'disabledBody': (
      'Новые заказы сейчас не принимаются. Ваши прошлые заказы доступны в разделе «Заказы».',
      'Жаңа тапсырыстар қабылданбайды. Бұрынғы тапсырыстар «Тапсырыстар» бөлімінде.',
      'New orders are paused. Your past orders stay available under Orders.'
    ),
    'cartNotSynced': (
      'Корзина пока не сохранена на сервере',
      'Себет серверде әлі сақталмаған',
      'The cart is not saved to the server yet'
    ),
    'sortPopularity': ('Популярные', 'Танымал', 'Popular'),
    'sortPriceAsc': ('Сначала дешёвые', 'Алдымен арзан', 'Price: low to high'),
    'sortPriceDesc': (
      'Сначала дорогие',
      'Алдымен қымбат',
      'Price: high to low'
    ),
    'sortNew': ('Новинки', 'Жаңалықтар', 'Newest'),
    'sortDiscount': ('Больше скидка', 'Жеңілдік көбірек', 'Biggest discount'),
    'fromStore': ('Магазин', 'Дүкен', 'Store'),
    'required': ('Обязательно', 'Міндетті', 'Required'),
    'quantity': ('Количество', 'Саны', 'Quantity'),
    'total': ('Итого', 'Барлығы', 'Total'),
  };
}
