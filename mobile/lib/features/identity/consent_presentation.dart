/// One consent row to show: the server policy plus whether its language differs
/// from the language the user is reading the app in.
class ConsentEntry {
  const ConsentEntry(this.policy, {required this.languageFallback});

  final Map<String, dynamic> policy;
  final bool languageFallback;
}

/// Collapses the per-language rows of one policy (same purpose and version)
/// into a single entry (PRD 1.1 §18: no silent language mixing in consent).
///
/// A recorded grant is never hidden, so it can always be withdrawn: if any
/// language version of the policy is granted, those rows are shown. Otherwise
/// the version in [language] is shown, falling back to ru, kk, en and flagging
/// the fallback so the UI can say which language the document is in.
List<ConsentEntry> presentConsents(
  List<Map<String, dynamic>> policies,
  String language,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final policy in policies) {
    final key = '${policy['purpose']}|${policy['policyVersion']}';
    groups.putIfAbsent(key, () => []).add(policy);
  }
  final entries = <ConsentEntry>[];
  for (final group in groups.values) {
    final granted = group.where((p) => p['granted'] == true).toList();
    if (granted.isNotEmpty) {
      for (final policy in granted) {
        entries.add(ConsentEntry(policy,
            languageFallback: policy['locale'] != language));
      }
      continue;
    }
    var chosen = group.first;
    for (final locale in [language, 'ru', 'kk', 'en']) {
      final match = group.where((p) => p['locale'] == locale);
      if (match.isNotEmpty) {
        chosen = match.first;
        break;
      }
    }
    entries.add(
        ConsentEntry(chosen, languageFallback: chosen['locale'] != language));
  }
  return entries;
}

/// Native name of a policy language; unknown codes are shown as given.
String languageName(String code) => switch (code) {
      'ru' => 'Русский',
      'kk' => 'Қазақша',
      'en' => 'English',
      _ => code,
    };
