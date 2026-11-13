import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/features/identity/consent_presentation.dart';

Map<String, dynamic> _policy(
  String purpose,
  String version,
  String locale, {
  bool granted = false,
}) =>
    {
      'policyId': '$purpose-$version-$locale',
      'purpose': purpose,
      'policyVersion': version,
      'locale': locale,
      'granted': granted,
    };

void main() {
  group('presentConsents', () {
    test('shows one row in the reader language', () {
      final entries = presentConsents([
        _policy('marketing', '1', 'en'),
        _policy('marketing', '1', 'kk'),
        _policy('marketing', '1', 'ru'),
      ], 'en');
      expect(entries, hasLength(1));
      expect(entries.single.policy['locale'], 'en');
      expect(entries.single.languageFallback, isFalse);
    });

    test('falls back to another language and flags it', () {
      final entries = presentConsents([
        _policy('marketing', '1', 'ru'),
        _policy('marketing', '1', 'en'),
      ], 'kk');
      expect(entries.single.policy['locale'], 'ru');
      expect(entries.single.languageFallback, isTrue);
      final onlyEnglish =
          presentConsents([_policy('marketing', '1', 'en')], 'ru');
      expect(onlyEnglish.single.policy['locale'], 'en');
      expect(onlyEnglish.single.languageFallback, isTrue);
    });

    test('never hides a recorded grant in another language', () {
      final entries = presentConsents([
        _policy('marketing', '1', 'ru', granted: true),
        _policy('marketing', '1', 'en'),
      ], 'en');
      expect(entries, hasLength(1));
      expect(entries.single.policy['locale'], 'ru');
      expect(entries.single.policy['granted'], isTrue);
      expect(entries.single.languageFallback, isTrue);
    });

    test('keeps purposes and versions separate', () {
      final entries = presentConsents([
        _policy('a', '1', 'ru'),
        _policy('a', '2', 'ru'),
        _policy('b', '1', 'ru'),
      ], 'ru');
      expect(entries, hasLength(3));
      expect(presentConsents([], 'ru'), isEmpty);
    });

    test('names languages natively and passes unknown codes through', () {
      expect(languageName('kk'), 'Қазақша');
      expect(languageName('xx'), 'xx');
    });
  });
}
