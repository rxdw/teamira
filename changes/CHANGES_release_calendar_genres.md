# Release calendar: фильтр по жанрам

Не запускалось на Flutter (в песочнице нет SDK) и не гонялся pytest целиком.
Проверено: синтаксис всех изменённых `.dart` (tree-sitter), `py_compile` для
бэкенда, а `_normalize_genres` и схема `ReleaseCalendarItem` прогнаны руками.
**Обязательно**: `flutter analyze`, `flutter test`, `pytest backend/tests/test_calendar.py`,
и один прогон экрана глазами.

## Что появилось

В полноэкранном календаре под вкладками типов — кнопка «genres». Открывает
шторку с теми же разбросанными чипами и счётчиками, что и шаг «genre» в
«Не могу выбрать». Жанры в шторке — это жанры текущей вкладки (тип → жанр),
выбирать можно несколько, релиз проходит, если у него есть **любой** из выбранных.
Выбор запоминается на устройстве, и полоска на Home его тоже учитывает.

## Как работает

- Жанр, которого нет в текущей вкладке, ничего не ломает: он просто не действует
  (`activeReleaseGenres`), а при возврате на вкладку снова включается.
- Релизы без жанров пропадают, пока фильтр включён (как в decide).
- Экран получает элементы, отфильтрованные только по типу; жанры применяет сам —
  иначе шторка не могла бы предложить остальные жанры.

## Бэкенд

- `schemas.ReleaseCalendarItem.genres: List[str]`.
- `calendar.py`: для tmdb/igdb копируется из `item.genres`; кэш `calendar:releases-v1` → `v2`.
- `ShikimoriAdapter.genres_for` + `calendar()`: у аниме жанров не было вовсе
  (`item = null`, а `/api/calendar` жанров не отдаёт). Добираются одним GraphQL-запросом
  на 50 тайтлов, названия приводятся к словарю TMDB (`Sci-Fi` → `Science Fiction`),
  демографии (Shounen/Seinen) отбрасываются. При любой ошибке — пустой список.
  **GraphQL-запрос не проверялся против живого Shikimori** (сеть в песочнице закрыта).

## Файлы

Новые: `widgets/genre_field.dart` (вынесено из decide без изменений логики,
`ScatteredGenreField`/`GenreTag`), `utils/release_genres.dart`,
`test/utils/release_genres_test.dart`.
Изменены: `release_calendar_screen.dart`, `home_screen.dart`,
`decide_filters_screen.dart` (теперь импортирует общий виджет),
`release_calendar_item.dart`, `calendar_filters_prefs_service.dart`,
`schemas.py`, `routers/calendar.py`, `adapters/shikimori.py`, `tests/test_calendar.py`.
Новых строк перевода нет — использованы `genres`, `clear`, `done`, `nGenres`.
