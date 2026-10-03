import '../../../services/locale_service.dart';
import '../../../utils/album_dates.dart';

/// Picks the Russian or English variant of an album string by the app's
/// interface language.
///
/// The album's copy lives here, next to the album, rather than in the ARB
/// files: `app_translations.dart` is generated from lib/l10n/*.arb by
/// tools/l10n/generate_compat_layer.py, and this feature was written
/// without the toolchain on hand to regenerate it. If the strings are
/// later moved into the ARBs, only this one function's callers change.
///
/// All copy is written lowercase on purpose — that's the app's register
/// (`.tr` lowercases everything it returns for the same reason).
String at(String ru, String en) => LocaleService.appIsRussian ? ru : en;

String yearsLabel(int n) => at(
      '$n ${ruPlural(n, 'год', 'года', 'лет')}',
      '$n ${n == 1 ? 'year' : 'years'}',
    );

String daysLabel(int n) => at(
      '$n ${ruPlural(n, 'день', 'дня', 'дней')}',
      '$n ${n == 1 ? 'day' : 'days'}',
    );

String monthsLabel(int n) => at(
      '$n ${ruPlural(n, 'месяц', 'месяца', 'месяцев')}',
      '$n ${n == 1 ? 'month' : 'months'}',
    );

/// A countdown as a person would say it: "завтра", "через 12 дней",
/// "через 3 месяца" — never a raw day count past ~two months.
String countdownLabel(int days) {
  if (days <= 0) return at('сегодня', 'today');
  if (days == 1) return at('завтра', 'tomorrow');
  if (days < 60) return at('через ${daysLabel(days)}', 'in ${daysLabel(days)}');
  final months = (days / 30.4).round();
  if (months < 24) return at('через ${monthsLabel(months)}', 'in ${monthsLabel(months)}');
  final years = (days / 365.25).round();
  return at('через ${yearsLabel(years)}', 'in ${yearsLabel(years)}');
}
