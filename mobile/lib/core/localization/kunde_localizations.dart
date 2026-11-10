import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class KundeLocalizations {
  const KundeLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('ru'),
    Locale('kk'),
    Locale('en')
  ];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    _KundeLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static KundeLocalizations of(BuildContext context) =>
      Localizations.of<KundeLocalizations>(context, KundeLocalizations)!;

  bool get _isKazakh => locale.languageCode == 'kk';
  bool get _isEnglish => locale.languageCode == 'en';

  String get tagline => _isKazakh
      ? 'Күнделікті өмір — оңайырақ.'
      : _isEnglish
          ? 'Everyday, made easier.'
          : 'Каждый день проще.';
  String get foundationTitle => _isKazakh
      ? 'KUNDE негізі дайындалуда'
      : _isEnglish
          ? 'KUNDE foundation is being prepared'
          : 'KUNDE готовит основу';
  String get connectionLabel => _isKazakh
      ? 'Платформа күйі'
      : _isEnglish
          ? 'Platform status'
          : 'Состояние платформы';
  String get connected => _isKazakh
      ? 'Сервер қолжетімді'
      : _isEnglish
          ? 'Server connected'
          : 'Сервер доступен';
  String get offline => _isKazakh
      ? 'Серверге қосылу мүмкін болмады'
      : _isEnglish
          ? 'Could not reach the server'
          : 'Не удалось связаться с сервером';
  String get retry => _isKazakh
      ? 'Қайталау'
      : _isEnglish
          ? 'Retry'
          : 'Повторить';
  String get servicesUnavailableTitle => _isKazakh
      ? 'Қызметтер әлі іске қосылған жоқ'
      : _isEnglish
          ? 'Services are not available yet'
          : 'Сервисы пока не запущены';
  String get marketplaceLabel => _isKazakh
      ? 'Нарық'
      : _isEnglish
          ? 'Marketplace'
          : 'Маркетплейс';
  String get marketplaceReadyTitle => _isKazakh
      ? 'Қызметтер қолжетімді'
      : _isEnglish
          ? 'Services are available'
          : 'Сервисы доступны';
  String get marketplaceReadyBody => _isKazakh
      ? 'Сервер мақұлданған қызметтерді ұсынады.'
      : _isEnglish
          ? 'The server reports approved services are enabled.'
          : 'Сервер сообщает, что утверждённые сервисы включены.';
  String get signInEnabled => _isKazakh
      ? 'Кіру қызметі бапталған'
      : _isEnglish
          ? 'Sign-in integration is configured'
          : 'Интеграция входа настроена';
  String get aiEnabled => _isKazakh
      ? 'KUNDE AI қосылған'
      : _isEnglish
          ? 'KUNDE AI is enabled'
          : 'KUNDE AI включён';
  String get available => _isKazakh
      ? 'Қолжетімді'
      : _isEnglish
          ? 'Enabled'
          : 'Включено';
  String get notAvailable => _isKazakh
      ? 'Қосылмаған'
      : _isEnglish
          ? 'Not enabled'
          : 'Не включено';
  String get servicesUnavailableBody => _isKazakh
      ? 'Қолжетімділік расталғанда, қызметтер осы жерде көрсетіледі.'
      : _isEnglish
          ? 'Services will appear here after launch readiness is confirmed.'
          : 'Здесь появятся сервисы после подтверждения готовности к запуску.';
  String get oidcIssuerLabel => _isKazakh
      ? 'OIDC провайдері көрсетілген'
      : _isEnglish
          ? 'OIDC issuer configured'
          : 'OIDC issuer настроен';
  String get aiUnavailable => _isKazakh
      ? 'KUNDE AI әзірге қолжетімсіз'
      : _isEnglish
          ? 'KUNDE AI is not enabled yet'
          : 'KUNDE AI пока недоступен';
  String get retryHint => _isKazakh
      ? 'Интернет байланысын тексеріп, қайталап көріңіз.'
      : _isEnglish
          ? 'Check your connection and try again.'
          : 'Проверьте подключение и попробуйте снова.';
}

class _KundeLocalizationsDelegate
    extends LocalizationsDelegate<KundeLocalizations> {
  const _KundeLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => KundeLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<KundeLocalizations> load(Locale locale) =>
      SynchronousFuture<KundeLocalizations>(KundeLocalizations(locale));

  @override
  bool shouldReload(_KundeLocalizationsDelegate old) => false;
}
