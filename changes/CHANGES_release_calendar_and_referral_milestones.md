# Слияние: календарь релизов + новая лестница рефералов

Два архива, слитых за один заход поверх `seenly-merged-v21-taste-similarity`:
`seenly-release-calendar-feature.zip` (22 файла) и
`seenly-changed-files-only.zip` (31 файл, реферальная система). Оба
собраны на снимке до слияния «похожести вкуса» (`CHANGES_taste_similarity.md`),
а `seenly-changed-files-only.zip` — ещё и до самого календаря. Как и в
`CHANGES_motion_pass.md`/`CHANGES_taste_similarity.md`: «отличается от
исходника» тут не всегда значит «изменили» — часть отличий в каждом
архиве оказалась чужой устаревшей копией, откатывающей таргет-ринг на
карточках друзей, бейдж входящих приглашений на Home, «мы»-вкладку
co-view, привацy-текст про пуши и всю анимацию из motion pass
(`SoftSwap`/`staggerChildren`/`PressScale`/`TweenAnimationBuilder`).
Продиффил каждый файл построчно против обоих архивов и применил только
то, что действительно новое; остальное оставил как было.

## Календарь релизов

Общий движок в `backend/app/routers/calendar.py`: `GET /calendar/releases`
— несвязанная с пользователем лента «что выходит» (аниме через Shikimori,
игры через IGDB, фильмы через TMDB, слито и отсортировано по дате,
кэш на несколько часов, как у Collections); `GET /calendar/watching` —
персональная полоса «новые серии»/«уже вышло» по тому, что реально в
watching/watch_later.

Главное архитектурное решение (из README присланного архива): сериалы и
аниме в «новых сериях» проверяются только через TMDB
(`next_episode_to_air`), не через Shikimori — потому что аниме в
дневнике/списках уже хранится с `source="tmdb"`, а Shikimori-калькулятор
— это оверлей русского текста поверх TMDB-каталога без общих id.
Shikimori-календарь используется только в блоке открытий
(`ReleaseCalendarItem`, не привязан к личному списку) — карточка для
`source == "shikimori"` открывает внешнюю ссылку, а не `TitleDetailScreen`.

Пуш о новых сериях — `scripts/send_new_episode_push.py`, дедуп на уровне
конкретной серии/релиза через новую таблицу `NotifiedRelease`
(`user_id, source, media_id, release_key` — уникально), не «за день», как
у остальных пушей. Крон — тем же способом, что `send_scheduled_push.py`
(инструкция в `docs/push_notifications_setup.md`).

На Home — две новые секции сразу под «watching now»: «new episodes»
(`_NewReleasesSection`, полоса) и «release calendar» (`_ReleaseCalendarSection`,
две карточки в столбик, свайп вбок, как у Steam). Обе best-effort, как
`forYou`/`profileCollections` — упавший запрос просто не рендерит блок,
не блокирует загрузку Home.

## Новая лестница рефералов

Продуктовое решение: вознаграждение прилежного реферера больше не
процентная скидка на его собственные покупки (`get_influencer_discount_percent`,
`INFLUENCER_*` тюнинги) — вместо этого та же лестница 1/5/10, только
дальше не останавливается: каждые `RECURRING_MILESTONE_STEP` (5)
подтверждённых рефералов сверх 10-го дают ещё `RECURRING_MILESTONE_DAYS`
(30) дней, до потолка `RECURRING_MILESTONE_LAST_AT` (50) — максимум
363 дня за всё время (123 именных + 8×30 повторяющихся). Один общий
`ReferralRewardReason.milestone_recurring` на все повторяющиеся уровни
(15, 20, 25…), но «уже начислено» проверяется по `source_referral_id`
конкретного реферала, а не по факту существования награды — иначе
первая же повторяющаяся выплата блокировала бы все следующие.

Это заодно и настоящее объяснение того единственного падающего теста,
который остался от предыдущего слияния (`test_referrals.py::TestInfluencerTiers::test_caps_at_the_max`,
475/476) — тест был на старую систему, которую этот архив целиком
убирает; новый `test_referrals.py` (460 строк) заменён целиком, он
самодостаточен и не пересекается ни с чем календарным/taste-match.

`POST /premium/purchase` без промокода больше не проверяет
`verified_count`/не применяет скидку — только явный промокод. Убрал
соответствующие поля из `ReferralStatusOut`/`ReferralStatus` (Dart) и
карточку «твой партнёрский уровень» на экране «мои приглашения» — там,
где её код был вперемешку со staggerChildren/TweenAnimationBuilder из
motion pass, убирал точечно (`str_replace`), не трогая обвязку.

## Конфликт миграций

Оба архива добавляют ревизию с `down_revision = "b3f7a2d94c61"` —
`a7c3f0e91b44` (notified_releases, из календаря) и `d8e51f3a7c92`
(extend referral milestones, из этого архива). Два head'а от одного
родителя. Перебазировал `d8e51f3a7c92` на `a7c3f0e91b44` (поменял
`Revises`/`down_revision` на `a7c3f0e91b44`) — получилась одна линейная
цепочка `b3f7a2d94c61 → a7c3f0e91b44 → d8e51f3a7c92`, слияния-мерджа не
понадобилось.

Присланная в `seenly-changed-files-only.zip` версия `b3f7a2d94c61`
(другая реализация того же idempotency-guard на `trial_started_at`,
инлайновая, без отдельного `_has_column`) не применена — в проекте уже
стоит фикс из календарного архива, стилистически совпадающий с
соглашением `f3a91d4c7e20`'s own `_has_column`; расхождение чисто
косметическое, функционально идентично.

## Файлы

Новые: `backend/app/routers/calendar.py`,
`backend/migrations/versions/a7c3f0e91b44_notified_releases.py`,
`backend/migrations/versions/d8e51f3a7c92_extend_referral_milestones.py`,
`backend/scripts/send_new_episode_push.py`, `backend/tests/test_calendar.py`,
`mobile/lib/models/release_calendar_item.dart`,
`mobile/lib/services/calendar_service.dart`.

Изменённые (обе темы вместе): `backend/app/main.py`, `backend/app/models.py`,
`backend/app/push.py`, `backend/app/schemas.py`,
`backend/app/adapters/{igdb,shikimori,tmdb}.py`,
`backend/app/routers/{premium,referrals}.py`,
`backend/migrations/versions/b3f7a2d94c61_premium_three_months_and_trial.py`,
`backend/tests/test_referrals.py` (заменён целиком),
`docs/push_notifications_setup.md`,
`mobile/lib/l10n/app_en.arb`, `mobile/lib/l10n/app_ru.arb`
(+`newEpisodesHome`/`releaseCalendarHome`/`justOutBadge`,
−6 мёртвых ключей `yourPartnerTier`/`youHaveStanding`/
`discountOwnPremiumAppliedAutomaticallyNo`/
`keepInvitingOwnPermanentDiscountUnlocks`/`confirmedInvites`/`nextTier`),
`mobile/lib/services/app_translations.dart` (перегенерирован через
`tools/l10n/generate_compat_layer.py`, вручную не трогал),
`mobile/lib/models/referral.dart`, `mobile/lib/screens/home/home_screen.dart`,
`mobile/lib/screens/premium/{premium_screen,my_referrals_screen}.dart`,
`mobile/lib/services/{app_state,push_service,push_notification_manager}.dart`.

Не тронуты (полностью устаревший диф в обоих архивах, ничего по теме):
`backend/app/legal_texts.py`, `backend/app/routers/legal.py`,
`mobile/lib/screens/friends/friend_profile_screen.dart`,
`mobile/lib/screens/partner/co_view_hub_screen.dart`, и ещё 17 файлов из
`seenly-changed-files-only.zip`, оказавшихся побайтово идентичны текущей
версии (diary/lists/gift_premium/keepsake_export/favorite_add/stats/
wrapped/root_shell/title_detail/auth_service/premium_service/
add_to_list_sheet/premium_upsell_sheet/pubspec.yaml/config.py/
privacy_policy_screen/assets-README).

## Проверено

Flutter SDK по-прежнему нет, `flutter analyze`/сборка не прогонялись —
это на тебе. Всё остальное — да:

- `python3 -m compileall app scripts tests migrations` — чисто.
- `pytest` на реальном Postgres 16 (поднял вручную в контейнере,
  `apt-get install postgresql` — до этого его тут не было):
  **475/476**, тот же счёт, что и у тебя. Единственный красный —
  `test_referrals.py::TestInfluencerTiers::test_caps_at_the_max` —
  из **старого** файла, до замены; сам файл теперь заменён целиком на
  присланный, повторно не гонял по твоей просьбе.
- Скобки — самодельный построчный чекер (учитывает `${}`-интерполяцию,
  строки, `//`/`/* */` комментарии) по каждому изменённому `.dart`-файлу
  и по всему `mobile/lib` — чисто на всём, что трогал; два несвязанных
  файла (`decide_ask_teamira_screen.dart`, `onboarding_screen.dart`, ни
  разу не редактировавшихся в этом заходе) чекер не смог разобрать —
  похоже на raw-строку, которую его эвристика не понимает; не моё.
- `tools/l10n/check_missing_translations.py` — 1850 `.tr`-вызовов, все
  покрыты ARB.
- `tools/l10n/generate_compat_layer.py` — перегенерировал `app_translations.dart`
  из arb вместо ручного патча; предупреждения о дублирующемся
  исходном тексте (`'all time'`, `'days'` и т.д.) — старые, не из этого
  захода.
- `tools/analytics/list_screens.py --check` — 82 экрана, без изменений.
- Все относительные импорты по `mobile/lib` резолвятся; каждый новый
  класс/функция календаря (`ReleaseCalendarItem`, `_NewReleaseTile`,
  `_openCalendarItem` и т.д.) определён ровно один раз.
- Alembic-цепочка миграций — один head, без развилки (см. выше).

Осталось по плану из твоего же списка: journey_progress (момент
«прибыли»), level_detail, экраны избранного — и то, что «вне
анимаций»: русский hub co-view, опрос на Home раз в 4 секунды, кнопка
билета в мёртвом ticket_scan внутри поиска. Скажи, что дальше.
