# «мы»: кто чаще предлагает + наши вехи + вход в «наш враппед»

Правки наложены на архив `seenly-clay-kawaii-full-project` (не заменой
файлов, а точечно — в нём уже были sincerity/`ratingHidden`, clay-скин,
клиентская часть couple-wrapped и `TogetherWrappedTeaser`).

## Бэкенд
- `schemas.py` — `SharedStatsOut.added_by_counts`.
- `routers/shared_diary.py`
  - `/stats`: `added_by_counts` по `CoViewEntry` (planned+watched) с тем же
    `period`-окном; намеренно не из shared-diary строк.
  - `GET /partner/shared/achievements` — `compute_couple_achievements_for_link`
    (вечера 1/10/25/50/100, 5+ жанров, стрик 3/7, дней в связке 30/100/365),
    отдаёт существующий `AchievementsOut`.
  - `GET /partner/shared/wrapped/periods` и `/wrapped/summary` — то, что
    клиент (`SharedDiaryService.wrappedSummary/wrappedPeriods`) уже вызывал,
    но на бэке роутов не было (404). Отдельная функция, `get_wrapped_summary`
    в `profile.py` не тронут. Один ряд на общий вечер для счётчиков,
    рейтинги/рецензии — оба ряда. `_group()` вызывается с `db` (сигнатура
    в этом архиве изменилась).

## Клиент
- `models/shared_diary.dart` — `SharedStats.addedByCounts`.
- `services/shared_diary_service.dart` — `achievements()`.
- `screens/partner/co_view_hub_screen.dart` — карточка «наш враппед» наверху
  вкладки «мы» (`WrappedScreen(isCouple: true, initialScope: 'all')`),
  `_CoupleBadgesSection`, `_ProposerSplitBar`, загрузка вех и
  `checkAndCelebrateNewCoupleAchievements` после загрузки.
- `services/app_translations.dart` — переводы вех и 7 «вы/ваш»-подписей.
- Уже лежавшие в архиве `widgets/couple_achievement_unlock.dart` и
  `services/couple_achievement_seen_service.dart` (идентичны моим) теперь
  подключены; сами файлы не менялись.
- `wrapped_screen.dart` не менялся: `isCouple` и «вы/ваш» там уже были.

## Исправлено относительно прошлого архива
- В `_ProposerSplitBar` цвета были `static const` из `SeenlyPalette.*` — это
  геттеры темы, так не компилируется. Теперь `static List<Color> get`.

## Не проверено
- `flutter analyze` / `pytest` не запускались (нет SDK и зависимостей);
  проверены только `ast.parse`, статический поиск неопределённых имён в
  роутере и баланс скобок. Тестов на новые эндпоинты нет.
