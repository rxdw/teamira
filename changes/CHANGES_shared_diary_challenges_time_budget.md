# Что добавлено: совместный дневник, челленджи, «умный вечер по времени»

Коротко — что где искать, если возвращаетесь к этому через месяц.

## 1. Совместный дневник пары (co-viewing hub)

**Backend**
- `app/models.py` — `DiaryEntry.shared_link_id` / `.watched_together` / `.country`, новые модели `PartnerPrefs`, `ChallengeProgress`.
- `app/routers/shared_diary.py` — новый роутер: `/partner/shared/diary`, `/planned`, `/stats`, `/prefs`.
- `app/routers/partner.py` — `CO_VIEW_FREE_LIMIT = 5`, `_assert_coview_room`, проверка лимита в `add_coview_entries`; отметка «посмотрели вместе» теперь помечает `watched_together=True`.
- `app/routers/diary.py` — `log_watched` принимает `watched_together`, резолвит страну (`_resolve_country`) и решает, шарить ли вечер (`shared_link_id_for_log`, живёт в `shared_diary.py`).
- `app/routers/premium.py` — `is_premium_account()`, переиспользуемый хелпер.

**Mobile**
- `lib/models/shared_diary.dart`, `lib/services/shared_diary_service.dart`
- `lib/screens/partner/co_view_hub_screen.dart` — три вкладки: вместе / дневник / мы
- `lib/screens/shell/home_mode_shell.dart` — переключалка «вы / вы и \<партнёр\>» над Home, подключена в `root_shell.dart`
- Настройки шаринга — новый раздел «наш дневник» в `screens/profile/settings_screen.dart`

Ключевое решение: общий дневник — это НЕ вторая копия записей, а `shared_link_id` на личной записи в `DiaryEntry`. Правка/удаление у себя сразу отражается у партнёра.

## 2. Челленджи (еженедельные + годовые)

**Backend**
- `app/challenges.py` — каталог (8 еженедельных, 6 годовых, включая «12 стран за год»), вычисление прогресса на лету.
- `app/routers/challenges.py` — `/challenges`, `/challenges/{id}/claim`, `/challenges/seen`.
- `app/routers/profile.py` — XP от собранных челленджей добавлен в общий уровень (`compute_level_for_user`).

**Mobile**
- `lib/models/challenge.dart`, `lib/services/challenges_service.dart`
- `lib/widgets/challenge_card.dart` — карточка + `SoftProgressBar`
- `lib/screens/profile/challenges_screen.dart` — полный экран
- Карточка-споттлайт на Home (`_ChallengesHomeCard` в конце `home_screen.dart`)
- Ссылка «челленджи» в `profile_screen.dart`, рядом с достижениями

## 3. «Умный вечер по времени» в Ask tanè

**Backend**
- `app/routers/ai.py` — парсинг бюджета из текста («есть часа полтора», «минут сорок»), `_time_fit_bonus` (сигнал ранжирования, не фильтр — заголовки без runtime не выбрасываются).
- `app/schemas.py` — `AiAskRequest.minutes_available`, `TimeBudgetOut`, поля в `AiAskResponse`.

**Mobile**
- `lib/models/ai_response.dart` — `AiTimeBudget`
- `lib/screens/home/home_screen.dart` — чипы времени (`_TimeBudgetChips`) под полем Ask
- `lib/screens/home/ask_teamira_results_screen.dart` — баннер «у тебя 40 минут» / «поняла: у тебя ...»

## Миграция

`backend/migrations/versions/f3a91d4c7e20_shared_diary_challenges.py` — одна миграция на все три фичи. Она же **сливает две головы Alembic**, которые уже разошлись в проекте до этих изменений (`a1c4e7f9b2d6` и `e58a2c71b4f3` от общего предка `c2ce9a945958`) — без этого `alembic upgrade head` падал бы с «Multiple head revisions are present» на любой базе, ещё не смигрированной вручную. Накатывается как обычно:

```
docker compose exec api alembic upgrade head
```

## Что не сделано (честно)

- `dart analyze` / `flutter test` не прогонялись — в песочнице нет Flutter-тулчейна. Все правки проверены вручную: баланс скобок в изменённых блоках, соответствие сигнатур существующим виджетам (`PillChip`, `UnderlineTabRow`, `PartnerStatus.linked` и т.д.), сверка путей импортов.
- Backend прогнан через `python -c "import app.main"` с реальными `fastapi`/`sqlalchemy`/`psycopg2` — роуты регистрируются, парсер времени и ротация челленджей проверены отдельными вызовами. Живой Postgres в песочнице не поднимался.
- Иконки/переводы для новых экранов — на русском по умолчанию (проект и так предпочитает русский в свежих экранах, см. `wrapped_screen.dart`). Английская локализация не добавлена — как и для остального нового кода в проекте, это отдельная работа поверх основного аудита.
