# XP: челленджи, просмотр вместе, шеринг карточек

Экран уровня (Profile → level detail), блок «where your xp comes from», теперь показывает три новых источника опыта. Бэкенд уже считал XP за челленджи (и за приглашённых друзей), но приложение их не разбирало — сумма строк не сходилась с итогом.

## Сколько XP

| Источник | XP | Как считается |
|---|---|---|
| Просмотр вместе | +5 | сверху к +10 за сам просмотр; вечер с `watched_together` или `watched_with_username` |
| Шеринг карточки | +12 | один раз за каждую карточку, не больше 2 карточек в сутки (UTC) |
| Челленджи | по челленджу | как и раньше, только за собранные; теперь видно на экране |

Константы: `_XP_PER_WATCHED_TOGETHER`, `_XP_PER_CARD_SHARE` (`routers/profile.py`), `MAX_REWARDED_SHARES_PER_DAY` (`routers/card_shares.py`).

Шеринг нельзя проверить на сервере (неизвестно, дошла ли карточка до кого-то), поэтому награда ограничена, а не верифицирована. Превышение суточного лимита карточку не «сжигает»: запись не создаётся, карточка принесёт XP в другой день.

Приглашённые друзья (+30) по-прежнему входят в итог, но отдельной строкой не показаны.

## Бэкенд

- `models.CardShare` + миграция `e4b2a7c91d38_card_shares.py` (единственная head).
- `POST /shares/card` (`routers/card_shares.py`): `{card_key}` → `{counted, xp_awarded, reason, total_xp, level, leveled_up}`.
- `LevelOut`: `watched_together_count`, `xp_from_together`, `card_shares_count`, `xp_from_shares`.
- `tests/test_card_shares.py` — 16 тестов, включая проверку, что все `xp_from_*` в сумме дают `xp`.

## Мобильное приложение

- `ProfileLevel` — новые поля; `level_detail_screen.dart` — три строки + подсказка про шеринг.
- `services/card_share_service.dart`, `AppState.cardShares`.
- `showShareCardSheet(rewardKey: ...)`: если шеринг не отменён, сообщает серверу, показывает «+N xp» под карточкой и празднование нового уровня. Передаётся из 4 экранов записи, дневника, `title_share`, `watched_preview_sheet`. Онбординг (`seenly-plan`) без награды.
- ARB (`app_en.arb`, `app_ru.arb`) + перегенерирован `app_translations.dart` (только добавления).

## Не проверено

Flutter SDK в среде не было — ни `flutter analyze`, ни сборки. Бэкенд прогнан на реальном Postgres.
`lib/l10n/app_localizations*.dart` перегенерируются сами при `flutter pub get`.
