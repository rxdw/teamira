# Полноэкранный календарь релизов

> Перенесено на актуальный `seenly-full-updated-11`: изменения накладывались
> точечно (см. ниже), а не файлами целиком — присланные `home_screen.dart`,
> ARB и `app_translations.dart` были сняты со старой версии проекта.

Ничего из этого не запускалось на Flutter: в песочнице нет SDK. Проверено
только: синтаксис изменённых `.dart` (парсер tree-sitter, ошибок нет),
`tools/l10n/check_missing_translations.py` (чисто), `tools/analytics/list_screens.py
--check` (83 экрана). **Обязательно** `flutter analyze`, `flutter test` и один
прогон экрана руками.

## Что появилось

Секция «release calendar» на Home получила «see all →» (как у остальных секций).
Оно открывает `ReleaseCalendarScreen` — полный экран, собранный по образцу
`CollectionFullScreen`, но с датами. Экран получает ровно те элементы, что
сейчас показывает Home (то есть уже с учётом фильтра из иконки tune);
вкладки типов на самом экране сужают список только локально и сохранённый
фильтр не меняют.

- **Шапка**: сворачивающаяся, с размытой мозаикой постеров, выбранных по всему
  календарю. При входе мозаика «оседает» с зума 1.16→1.0, затем очень медленно
  дрейфует (≈26 с на проход). При «уменьшить движение» — статична.
- **Сводка**: «N релизов» (счётчик считает вверх и пересчитывается при смене
  вкладки) и диапазон дат.
- **«Ближайший релиз»**: карточка с самым близким невышедшим релизом.
- **Вкладки типов**: `ScrollableUnderlineTabs`, как в Collections. Смена вкладки
  перерисовывает календарь (новый ключ у каждого дня — replay reveal, как у
  shuffle в коллекции).
- **Дни**: каждый день — `SliverMainAxisGroup` из липкого заголовка и ленивой
  `SliverGrid` в две колонки. Заголовок: номер дня, месяц, день недели,
  плашка «сегодня» (дышит) / «завтра» / «уже вышло», число релизов. При
  прилипании — линия, тень, номер дня чуть уменьшается. Появляется от
  прокрутки (`ScrollRevealEntrance`), а не по таймеру, поэтому не спорит с
  прилипанием.
- **Плитки**: `TiltPosterTile` + `MosaicParallaxPoster` + `ThemedPosterTile`
  (тема постеров из настроек). Бейдж: иконка типа или «E5» для серий аниме.
  Долгое нажатие — то же меню, что в коллекциях (для тайтлов с `MediaItem`).

## Что затронуто

- `mobile/lib/screens/home/home_screen.dart`: «see all →» в заголовке секции;
  `_openCalendarItem` теперь делегирует в общую `openReleaseCalendarItem`;
  бейдж даты на плитке считается по `releaseDay` (локальный день), чтобы совпадать
  с заголовком дня на полном экране; убран ставший ненужным импорт `url_launcher`.
- `mobile/lib/screens/collections/collection_full_screen.dart`:
  `_showQuickActions` → публичный `showMediaQuickActions`.
- `mobile/lib/models/release_calendar_item.dart`: геттер `releaseDay`
  (локальная полночь дня релиза; Shikimori-время с оффсетом переводится в
  локальную зону).
- `mobile/lib/l10n/app_{en,ru}.arb`: `nReleases` (плюраль), `nextUpRelease`.
  В `app_translations.dart` добавлены ровно три строки вручную (`'next up'`,
  `'ближайший релиз'`, `'nReleases'`), без перегенерации: в базовом проекте этот
  файл слегка расходится с ARB (строка `'random, reel or swipe'` есть только
  в нём), и генератор её бы выкинул.
- `backend/app/analytics_screens.json`: +`ReleaseCalendarScreen` (83 экрана).

## Новые файлы

- `mobile/lib/screens/calendar/release_calendar_screen.dart`
- `mobile/lib/utils/release_day_groups.dart` (`groupReleasesByDay`, `daysFromToday`)
- `mobile/test/utils/release_day_groups_test.dart`

## На что смотреть при проверке

- Липкие заголовки внутри `SliverMainAxisGroup` (порядок отрисовки/тень).
- Скин Cozy: заголовки набираются крупным рукописным шрифтом — высота
  заголовка дня 62 px может оказаться тесной.
- Мозаика шапки: `ClipRect` вокруг зума/дрейфа, чтобы не вылезала на контент.
