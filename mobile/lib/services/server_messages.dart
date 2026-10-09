import 'app_translations.dart';
import 'locale_service.dart';

/// Server error messages (`detail`) in the language the app shows.
///
/// The backend words its errors in one language each — mostly English, some
/// Russian (the newer rooms/album/promo code) — and used to send them straight
/// to the screen, so a Russian reader met "Username already taken" and an
/// English one "Просмотр уже закончился". Translating on the phone keeps the
/// server single-language (no per-request locale to thread through ~330
/// raise sites) and means a message is one ARB pair away from being localised.
///
/// Input is already lowercased ([ApiClient._decode] does that for every
/// message), which is also how the ARB pairs are written, so a plain map
/// lookup is enough for the fixed messages. Messages with a name or a number
/// spliced in ("<name> is already in your circle") can't be looked up whole;
/// those are matched by pattern below. Anything unknown is returned untouched —
/// a message in the wrong language still beats a blank one.
String translateServerMessage(String message) {
  final text = message.trim();
  if (text.isEmpty) return message;
  final wantRussian = LocaleService.appIsRussian;
  final isRussian = _cyrillic.hasMatch(text);
  if (wantRussian == isRussian) return message; // already the right language

  final key = text.toLowerCase();
  final exact = wantRussian ? AppTranslations.ru[key] : AppTranslations.en[key];
  if (exact != null) return exact;

  for (final p in (wantRussian ? _enToRu : _ruToEn)) {
    final m = p.re.firstMatch(key);
    if (m != null) return p.build(m);
  }
  return message;
}

final _cyrillic = RegExp(r'[\u0400-\u04FF]');

class _Pattern {
  final RegExp re;
  final String Function(Match) build;
  const _Pattern(this.re, this.build);
}

final List<_Pattern> _ruToEn = [
  _Pattern(RegExp(r'^слишком длинно — не больше (\d+) символов$'),
      (m) => 'too long — no more than ${m[1]} characters'),
  _Pattern(RegExp(r'^слишком длинно: (.+) — не больше (\d+) символов$'),
      (m) => 'too long: ${m[1]} — no more than ${m[2]} characters'),
  _Pattern(RegExp(r'^пустое поле: (.+)$'), (m) => 'empty field: ${m[1]}'),
  _Pattern(RegExp(r'^одновременно можно хранить не больше (\d+) запечатанных капсул.*$'),
      (m) => 'at most ${m[1]} sealed capsules can be kept at once'),
  _Pattern(RegExp(r'^сейчас читает вслух (.+)$'), (m) => '${m[1]} is reading aloud right now'),
];

final List<_Pattern> _enToRu = [
  _Pattern(RegExp(r"^that's a lot at once — try (\d+) titles or fewer per import$"),
      (m) => 'много сразу — попробуйте не больше ${m[1]} тайтлов за раз'),
  _Pattern(RegExp(r'^(.+) is already in a co-viewing circle$'),
      (m) => '${m[1]} уже в круге совместного просмотра'),
  _Pattern(RegExp(r'^(.+) is already in your circle$'), (m) => '${m[1]} уже в вашем круге'),
  _Pattern(RegExp(r'^pin at most (\d+) badges$'), (m) => 'можно закрепить не больше ${m[1]} значков'),
  _Pattern(RegExp(r'^badge not unlocked: (.+)$'), (m) => 'значок не открыт: ${m[1]}'),
  _Pattern(
      RegExp(r'^this account is scheduled for deletion and will be erased in (\d+) day\(s\)\. you can still restore it\.$'),
      (m) => 'этот аккаунт стоит в очереди на удаление и будет стёрт через ${m[1]} дн. — его ещё можно восстановить.'),
];
