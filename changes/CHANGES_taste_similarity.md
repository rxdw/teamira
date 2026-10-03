# Слияние: система «похожести вкуса»

Архив `seenly-taste-similarity.zip` был собран на более старом снимке
проекта, чем этот (до sincerity/trailer_reels и остального анимационного
прохода). Как и в `CHANGES_motion_pass.md`: «отличается от исходника» там
не всегда значит «изменили» — часть отличий это просто чужая устаревшая
копия. Продиффил каждый из 16 изменённых файлов против этого архива
построчно: во всех случаях разница оказалась ровно тем, что описано в
README присланного архива (новые поля/эндпоинты/виджеты), без потери
чего-либо из анимационного слоя — конфликтов по существу не было,
слияние прямое, вручную сверенное по каждому хансу диффа.

## Что добавилось

Один общий движок схожести (`backend/app/similarity.py`) на локальной
embedding-модели (переиспользует кэш Ask Teamira, без стороннего AI),
строит вектор вкуса из watched/watching/wishlist/избранного одной шкалой
и даёт 0–100 плюс расшифровку (общий тайтл, который оба сейчас смотрят —
самый сильный сигнал; общие жанры; конкретные общие тайтлы). Нет данных
для сравнения — `None`, а не выдуманный «0% совпадения» (см. докстринг
`similarity.compare`).

Подключено в трёх местах:
- **Экран друзей** — бейдж-кольцо на карточках (друзья + «возможно, вы
  знакомы»), подробная карточка на профиле друга, ранжирование
  «похожих» по вкусу вместо «кто недавно зарегистрировался».
- **Онбординг** — новый шаг `_PeopleLikeYouStep` сразу после выбора
  любимых фильмов (10 → 11 шагов).
- **Вкладка «мы» в co-view** — секция совместимости, видна даже до
  первого совместного вечера.

Значок-уведомление вынесен в `NotificationCountPill` (переиспользует
существующий `BreathingGlow`, поведение 1:1 со старой инлайновой версией
на профиле) и подключён к заявкам в друзья и приглашениям в co-view —
раньше оба пути не пушились вообще.

## Файлы

Новые: `backend/app/similarity.py`, `mobile/lib/models/taste_match.dart`,
`mobile/lib/widgets/taste_match_card.dart`,
`mobile/lib/widgets/notification_count_pill.dart`.

Изменённые: `backend/app/schemas.py`, `backend/app/routers/friends.py`,
`backend/app/routers/partner.py`, `backend/app/push.py`,
`mobile/lib/models/friend.dart`, `mobile/lib/models/partner_status.dart`,
`mobile/lib/services/friends_service.dart`,
`mobile/lib/services/partner_service.dart`,
`mobile/lib/services/push_notification_manager.dart`,
`mobile/lib/widgets/match_ring.dart`,
`mobile/lib/screens/friends/friends_screen.dart`,
`mobile/lib/screens/friends/friend_profile_screen.dart`,
`mobile/lib/screens/onboarding/onboarding_screen.dart`,
`mobile/lib/screens/partner/co_view_hub_screen.dart`,
`mobile/lib/screens/profile/profile_screen.dart`,
`mobile/lib/screens/home/home_screen.dart`.

Плюс два новых ключа переводов (`peopleSimilarTaste`,
`basedWhatJustPickedSayHi`, `notEnoughGoYetPickFavorite` — три, если
точно) в `lib/l10n/app_en.arb`/`app_ru.arb` для текста нового шага
онбординга, которого не было в присланном архиве;
`lib/services/app_translations.dart` перегенерирован через
`tools/l10n/generate_compat_layer.py`.

## Что проверено

- `python3 -m py_compile` / `compileall` по всему `backend/app` — чисто.
- `python -m pytest --collect-only` в `backend/` — 467 тестов собираются
  без единой ошибки импорта (значит `app.main` со всеми роутерами,
  `app.similarity`, новые схемы и модели друг с другом действительно
  совместимы, а не только текстуально похожи).
- `python -m pytest tests/test_friends.py::TestFriendRequestLifecycle`
  (весь жизненный цикл заявок — ровно то, что трогает изменённый
  `_friend_out`) — проходит.
- Дальше в `test_friends.py`/`test_partner.py`/`test_push.py` тестовый
  раннер в этой песочнице периодически падает с
  `DuplicateColumn: trial_started_at already exists` — **воспроизвёл то
  же самое на чистом, немодифицированном базовом архиве** тем же
  прогоном, так что это дефект тестовой инфраструктуры в этой песочнице
  (похоже, `on_startup`'а `run_migrations()` через `TestClient`
  где-то в сьюте пересекается с сессионным фикстурой `_schema`,
  которая должна отрабатывать только один раз — см. её докстринг в
  `tests/conftest.py`), не что-то, что внесло это слияние. На реальном
  Postgres/docker-compose стоит прогнать `pytest tests/ -v` целиком ещё
  раз самостоятельно.
- `tools/l10n/check_missing_translations.py` — чисто (0 непереведённых
  `.tr`-литералов).
- `tools/analytics/list_screens.py --check` — 82 экрана, как и было
  (новый шаг онбординга не `*Screen`, поэтому не считается отдельным
  экраном).
- Собственный скрипт проверки баланса скобок (понимает `//`/`/* */`,
  строки, тройные кавычки, `${...}`-интерполяцию) — все 318 `.dart`
  файлов в `mobile/lib` сбалансированы.
- Все относительные импорты (1643 штук) по `mobile/lib` резолвятся в
  реально существующие файлы.
- Flutter SDK в песочнице по-прежнему нет — `flutter analyze`/`flutter
  test`/сама сборка не запускались. Каждый новый виджет и его параметры
  (`MatchRing.trackColor`, `PosterTile`, `PillChip`, `Entrance`,
  `BreathingGlow`, `PressScale`) сверены построчно с реальными
  сигнатурами в этой версии проекта — обязательно прогони `flutter
  analyze` у себя перед сборкой.
