# Настройка push-уведомлений (аудит 4.4.1)

Код — и на бэкенде, и в мобильном клиенте — полностью готов и не упадёт,
если пропустить всё, что ниже: `PushNotificationManager.init()` ловит
провал `Firebase.initializeApp()`, backend отправляет через
`sentry_sdk.init(dsn="")`-подобный no-op при пустом
`FIREBASE_CREDENTIALS_JSON`. Но **сами уведомления не полетят**, пока не
пройти шаги ниже — их нельзя автоматизировать без реального аккаунта
Google/Apple.

## 1. Создать проект Firebase

1. [console.firebase.google.com](https://console.firebase.google.com) → Add project.
2. Внутри проекта добавить два приложения:
   - **Android**, package name = тот, что стоит в
     `mobile/android/app/build.gradle.kts` → `applicationId`. **Важно**:
     на момент написания это всё ещё `com.example.seenly` (см. аудит,
     пункт 2.6 — приложение и так нельзя публиковать с этим id). Смените
     `applicationId` **до** регистрации в Firebase, иначе
     `google-services.json` придётся перевыпускать после смены имени
     пакета.
   - **iOS**, Bundle ID = тот, что в Xcode-проекте
     (`ios/Runner.xcodeproj`, обычно виден как
     `PRODUCT_BUNDLE_IDENTIFIER` в настройках таргета Runner).

## 2. Android

1. Скачать `google-services.json` со страницы Android-приложения в
   консоли Firebase.
2. Положить файл в `mobile/android/app/google-services.json` (рядом с
   `build.gradle.kts`, не в `android/` и не в `android/app/src/`).
3. Больше ничего не нужно — `mobile/android/settings.gradle.kts` и
   `mobile/android/app/build.gradle.kts` уже подключают плагин
   `com.google.gms.google-services` **условно**, только если этот файл
   существует (см. комментарий прямо над `if (file("google-services.json").exists())`
   в `app/build.gradle.kts` — без этой защиты плагин уронил бы сборку
   у всех, у кого файла ещё нет).
4. `POST_NOTIFICATIONS` (обязательно для Android 13+) и
   `default_notification_channel_id` уже прописаны в
   `AndroidManifest.xml`.

## 3. iOS

Файл `GoogleService-Info.plist` и APNs-ключ — это то, что нельзя сделать
текстовым редактированием репозитория, нужен именно Xcode и аккаунт
Apple Developer:

1. Скачать `GoogleService-Info.plist` со страницы iOS-приложения в
   консоли Firebase, добавить его в Xcode-проект через
   **File → Add Files to "Runner"** (не просто скопировать файл в
   папку — тогда он не попадёт в bundle).
2. В Xcode: таргет **Runner → Signing & Capabilities → + Capability**:
   - **Push Notifications**
   - **Background Modes** → отметить **Remote notifications**
     (в `Info.plist` уже стоит `UIBackgroundModes: [remote-notification]`
     — этот пункт в Xcode добавляет реальную entitlement-запись и
     обновляет `Runner.entitlements`/`project.pbxproj`, чего простой
     правкой текстовых файлов сделать было нельзя, не рискуя сломать
     проект).
3. [Apple Developer](https://developer.apple.com/account) → Certificates,
   Identifiers & Profiles → Keys → создать **APNs Auth Key** (тип
   `.p8`, один ключ на всю команду, не привязан к конкретному App ID).
4. В Firebase Console → Project Settings → Cloud Messaging → Apple app
   configuration → загрузить этот `.p8`-ключ + Key ID + Team ID.

Без шага 3-4 Android-уведомления будут работать, а iOS — нет: FCM не
может доставить пуш на iOS-устройство, если у него нет APNs-ключа для
ретрансляции через Apple.

## 4. Backend

1. В той же консоли Firebase: **Project Settings → Service accounts →
   Generate new private key** — скачается JSON.
2. Положить **всё содержимое** этого JSON-файла (не путь к файлу) в
   переменную окружения `FIREBASE_CREDENTIALS_JSON` (см.
   `backend/.env.example`). Один типичный способ — вставить его как
   однострочный JSON:
   ```
   FIREBASE_CREDENTIALS_JSON={"type":"service_account","project_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n", ...}
   ```
3. Накатить миграцию `8d82a0fd511d_push_notifications.py` (через обычный
   `alembic upgrade head` / автоматический запуск при старте — см.
   `app/main.py`).
4. Поставить крон на `scripts/send_scheduled_push.py` — без него не
   будет напоминаний о серии и «в этот день» (мгновенные пуши — матч,
   партнёрская связь, активность друзей, левел-ап — работают и без
   этого, они вызываются прямо из запросов):
   ```
   0 * * * *  cd /path/to/backend && /path/to/venv/bin/python scripts/send_scheduled_push.py
   ```
   Безопасно запускать каждый час — скрипт сам не шлёт повторно за один
   день (см. его собственный докстринг и `models.PushLog`).
5. Тем же способом поставить крон на `scripts/send_new_episode_push.py`
   — без него не будет пушей о новых сериях/релизах игр из раздела
   «смотрю сейчас» и списка отслеживаемых игр (календарь на главном
   экране при этом всё равно работает — пуш это отдельная, необязательная
   надстройка над ним):
   ```
   0 * * * *  cd /path/to/backend && /path/to/venv/bin/python scripts/send_new_episode_push.py
   ```
   Тоже безопасно каждый час — дедуп на уровне конкретной серии/релиза,
   не «за день» (см. `models.NotifiedRelease`).

## 5. Проверка

- Backend: `GET /push/preferences` с валидным токеном должен вернуть 6
  категорий, все `enabled: true` для нового аккаунта.
- Мобильный клиент: после логина `PushNotificationManager.
  registerDeviceToken()` запрашивает разрешение и должен появиться
  реальный токен в `push_tokens` (`SELECT * FROM push_tokens;`).
- Сквозная проверка: два тестовых аккаунта, co-viewing свайп до
  совпадения — оба должны получить пуш «Совпадение! 🎉» в течение
  нескольких секунд (см. `app/push.py::notify_match`,
  `app/routers/co_view_vote.py::cast_vote`).

## Что уже сделано и не требует внимания

- Все 4 мгновенных триггера (совпадение, партнёрская связь, активность
  друзей, левел-ап) и оба запланированных (стрик, «в этот день») —
  реализованы, backend-часть проверена 410 тестами на настоящем
  Postgres.
- Экран настроек (Профиль → Настройки → Уведомления) уже дёргает
  `GET/PATCH /push/preferences` и рендерит категории с сервера — новую
  категорию можно добавить только на бэкенде, без релиза клиента.
- Deep-link по тапу на уведомление о совпадении/активности друга/
  воспоминании уже открывает `TitleDetailScreen` с нужным тайтлом.

## Известные ограничения этого захода

- Копирайтинг пушей и экран настроек — только на русском (`.tr()` не
  использовался намеренно, чтобы не трогать
  `services/app_translations.dart` без возможности прогнать компилятор
  — см. этот файл в git blame на предмет похожих решений в предыдущих
  апдейтах мобильного клиента).
- Deep-link для «партнёрская связь», «левел-ап» и «напоминание о серии»
  открывает не конкретный экран, а просто возвращает на корень
  навигации (см. `PushNotificationManager._handleTap`'s `default:`
  ветку) — для них нет отдельного экрана-назначения, куда логично вести.
- `flutter analyze`/`flutter test` не прогонялись ни разу за всё время
  этого проекта — в средах, где велась разработка, никогда не было
  Flutter SDK. Весь мобильный код в этом обновлении проверен только
  вручную (баланс скобок, разрешение импортов, построчное чтение) — см.
  `changes/CHANGES_push_notifications.md`.
