import '../album/album_strings.dart';

export '../album/album_strings.dart' show at;

/// Copy for the co-view room ("Гостиная") and the circle review. Lives next
/// to the feature for the same reason the album's copy does (see
/// album_strings.dart): the generated ARB layer wasn't available to extend.
/// All lowercase on purpose — that's the app's register.

String emotionLabel(String key) => switch (key) {
      'warm' => at('тепло', 'warm'),
      'funny' => at('смешно', 'funny'),
      'tense' => at('тревожно', 'tense'),
      'touching' => at('трогательно', 'touching'),
      'beautiful' => at('красиво', 'beautiful'),
      'sad' => at('грустно', 'sad'),
      'wow' => at('вау', 'wow'),
      'bored' => at('скучно', 'bored'),
      _ => key,
    };

String emotionEmoji(String key) => switch (key) {
      'warm' => '🫶',
      'funny' => '😂',
      'tense' => '😬',
      'touching' => '🥹',
      'beautiful' => '✨',
      'sad' => '😢',
      'wow' => '😮',
      'bored' => '😴',
      _ => '💛',
    };

String signalLabel(String key) => switch (key) {
      'pause' => at('давай на паузу?', 'pause?'),
      'rewind' => at('перемотай назад', 'rewind a bit'),
      'pulse' => at('пульс', 'heartbeat'),
      'hold' => at('держу за руку', 'holding your hand'),
      // a game's own
      'ready' => at('я готов', 'I’m ready'),
      'brb' => at('отойду на минутку', 'back in a minute'),
      'help' => at('нужна помощь', 'need a hand'),
      'gg' => at('gg', 'gg'),
      'again' => at('давай ещё раз', 'one more round'),
      _ => key,
    };

String signalEmoji(String key) => switch (key) {
      'pause' => '⏸️',
      'rewind' => '⏪',
      'pulse' => '💓',
      'hold' => '🤝',
      'ready' => '✅',
      'brb' => '☕',
      'help' => '🆘',
      'gg' => '🎉',
      'again' => '🔁',
      _ => '💛',
    };

/// A finished round of a game: win | loss | draw | checkpoint.
String roundLabel(String key) => switch (key) {
      'win' => at('победа', 'win'),
      'loss' => at('поражение', 'loss'),
      'draw' => at('ничья', 'draw'),
      'checkpoint' => at('рубеж', 'checkpoint'),
      _ => key,
    };

String roundEmoji(String key) => switch (key) {
      'win' => '🏆',
      'loss' => '💀',
      'draw' => '🤝',
      'checkpoint' => '🚩',
      _ => '🎮',
    };

/// Where a game is played.
String platformLabel(String key) => switch (key) {
      'pc' => at('пк', 'pc'),
      'ps' => 'playstation',
      'xbox' => 'xbox',
      'switch' => 'switch',
      'mobile' => at('телефон', 'phone'),
      _ => at('где-то ещё', 'somewhere else'),
    };

/// "41:20" / "1:05:09"
String clockLabel(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// One warm line for how two (or more) ratings compare. Shared by the
/// joint-review screen and the card that appears right after logging
/// together, so the same evening never reads two different ways.
String verdictLine(String verdict) => switch (verdict) {
      'unison' => at('вы почти в унисон', 'almost in unison'),
      'close' => at('чуть по-разному — и это хорошо', 'a little different — and that’s fine'),
      'split' => at('спорный вечер — есть что обсудить', 'a divisive evening — plenty to talk about'),
      _ => at('одна оценка на этот вечер', 'one rating for this evening'),
    };
