"""The end-user licence agreement, in both languages the app ships in.

Apple's Guideline 1.2 asks for an agreement in which the user
acknowledges that there is no tolerance for objectionable content or
abusive behaviour, and 5.1.1 asks for a privacy policy covering what
data is collected and how it can be deleted. This module is the
single source of both texts; routers/legal.py serves them, the mobile
sign-up screen shows them, and models.User.eula_version records which
version an account accepted.

Kept as a Python module rather than a static file so the version
constant, the text, and the code that serves it can never drift out of
sync — and so a deployment that mounts no static volume still has them.

This is plain-language boilerplate written to satisfy the review
requirement and to be honest with the person reading it. It is not legal
advice, and a real launch should have a lawyer read it against the
jurisdictions it's distributed in.
"""

from app.config import settings

EULA_EN = f"""# tanè — Terms of Use

_Version {settings.eula_version}_

## 1. What tanè is

tanè is a personal diary of the films, series, games and books you spend
your evenings with. You can keep it entirely to yourself, or share parts
of it with people you choose.

## 2. Your account

You need a username and password. Adding an email address is optional,
but it is the only way to get back into your account if you forget your
password — without one, a forgotten password means the diary is gone.

You are responsible for keeping your password to yourself. Tell us
(see section 8) if you think someone else has it.

## 3. Content you write

Your diary entries, notes, lists, nickname, avatar and status line are
yours. You keep every right you had in them. You give us only the
permission we need to store them and show them to the people you have
chosen to show them to.

## 4. There is no tolerance for objectionable content or abusive behaviour

By using tanè you agree not to post, send, or display content that:

- harasses, threatens, bullies or intimidates anyone;
- attacks people on the basis of race, ethnicity, national origin,
  religion, disability, gender, gender identity or sexual orientation;
- is sexually explicit, or sexualises a minor in any way whatsoever;
- depicts or glorifies violence, cruelty, or self-harm;
- impersonates another person, or misrepresents your affiliation with
  anyone;
- advertises, solicits, or moves people to other services;
- is unlawful where you are, or where the person reading it is.

This applies to everything another person can see — including your
nickname, your avatar, your status line, the names of your lists, and
any note on an evening you share.

**We enforce this.** You can report content or a person from inside the
app, at any time, in one tap. We act on reports within 24 hours. Content
that breaks these rules is removed, and accounts that break them are
suspended or terminated.

You can also block any account at any time. A block is immediate, needs
no explanation, and is never disclosed to the person blocked.

## 5. What we may do about a violation

Depending on what happened, we may remove the content, hide it, suspend
the account for a period, or terminate it. A suspended account can still
read and export its own diary — we take away the ability to reach other
people, not your own archive.

## 6. Deleting your account

You can delete your account from inside the app, at any time, with no
correspondence required: Settings → Account → Delete account.

Your account becomes invisible to everyone immediately. Everything in it
is permanently erased after {settings.account_purge_after_days} days —
until that date, signing in restores it. After that date it is gone and
we cannot recover it.

You can download everything in your account at any time, as one file,
from the same screen.

## 7. What we don't promise

tanè is provided as it is. Catalogue information about films, series,
games and books comes from third-party sources and may be wrong or
incomplete. We do our best to keep your diary safe, but you should
export a copy of anything you would be upset to lose.

## 8. Contact

{settings.moderation_contact_email or "Use the in-app report flow — Profile → Settings → Report a problem."}
"""


EULA_RU = f"""# tanè — Пользовательское соглашение

_Версия {settings.eula_version}_

## 1. Что такое tanè

tanè — личный дневник фильмов, сериалов, игр и книг, с которыми вы
проводите вечера. Вы можете вести его только для себя или делиться
частью записей с теми, кого выберете сами.

## 2. Ваш аккаунт

Нужны имя пользователя и пароль. Электронная почта необязательна, но это
единственный способ вернуть доступ, если вы забудете пароль — без неё
забытый пароль означает, что дневник потерян навсегда.

Вы отвечаете за сохранность пароля. Сообщите нам (раздел 8), если
считаете, что он попал к кому-то ещё.

## 3. Ваши записи

Записи, заметки, списки, ник, аватар и статус принадлежат вам. Все права
на них остаются у вас. Вы даёте нам только то разрешение, которое нужно,
чтобы хранить их и показывать тем, кому вы сами решили их показать.

## 4. Недопустимый контент и поведение не допускаются

Пользуясь tanè, вы соглашаетесь не публиковать, не отправлять и не
показывать материалы, которые:

- преследуют, угрожают, травят или запугивают кого-либо;
- нападают на людей по признаку расы, этнического или национального
  происхождения, религии, инвалидности, пола, гендерной идентичности или
  сексуальной ориентации;
- имеют откровенно сексуальный характер или каким бы то ни было образом
  сексуализируют несовершеннолетних;
- изображают или прославляют насилие, жестокость либо самоповреждение;
- выдают вас за другого человека или искажают вашу связь с кем-либо;
- рекламируют сторонние сервисы или уводят на них пользователей;
- нарушают закон там, где находитесь вы или тот, кто их читает.

Это относится ко всему, что может увидеть другой человек: к нику,
аватару, статусу, названиям списков и к заметкам о вечере, которыми вы
делитесь.

**Мы это соблюдаем.** Пожаловаться на материал или на человека можно
прямо в приложении, в одно касание, в любой момент. Мы реагируем на
жалобы в течение 24 часов. Материалы, нарушающие эти правила, удаляются,
а аккаунты нарушителей приостанавливаются или удаляются.

Вы также можете заблокировать любой аккаунт в любой момент. Блокировка
срабатывает сразу, не требует объяснений и никогда не раскрывается тому,
кого заблокировали.

## 5. Что мы можем сделать при нарушении

В зависимости от произошедшего мы можем удалить материал, скрыть его,
приостановить аккаунт на время или удалить его. Приостановленный аккаунт
по-прежнему может читать и выгружать собственный дневник — мы забираем
возможность связаться с другими людьми, а не ваш личный архив.

## 6. Удаление аккаунта

Удалить аккаунт можно прямо в приложении, в любой момент, без переписки:
Настройки → Аккаунт → Удалить аккаунт.

Аккаунт сразу становится невидимым для всех. Всё его содержимое
безвозвратно удаляется через {settings.account_purge_after_days} дней —
до этой даты достаточно войти, чтобы всё вернуть. После неё
восстановление невозможно.

Выгрузить всё содержимое аккаунта одним файлом можно в любой момент на
том же экране.

## 7. Чего мы не обещаем

tanè предоставляется «как есть». Сведения о фильмах, сериалах, играх и
книгах поступают из сторонних источников и могут быть неточными или
неполными. Мы делаем всё, чтобы сохранить ваш дневник, но копию того,
что дорого, стоит выгрузить себе.

## 8. Связь с нами

{settings.moderation_contact_email or "Через форму жалобы в приложении: Профиль → Настройки → Сообщить о проблеме."}
"""


PRIVACY_POLICY_EN = f"""# tanè — Privacy Policy

_Version {settings.privacy_policy_version}_

## 1. What we collect

- **Account info**: username, password (stored hashed, never in plain
  text), and an email address only if you choose to add one.
- **What you write**: your diary entries, notes, lists, ratings, and
  anything else you type into the app.
- **What you watch/play/read**: titles you log, mark as favorites, or
  add to a list — plus which catalog they came from (a third-party
  film/show/game/book database — see section 3).
- **Premium status**: whether your account is premium, which plan, and
  when it was purchased or granted. See section 4 — there is no
  payment card or billing information to collect in the first place.
- **Basic usage events**: small, closed-vocabulary facts like which
  screens get opened and which features get used — never the text you
  typed, search terms, or your email address. A random per-install id,
  not your account, identifies these unless you're signed in.
- **Notifications** (only if you allow them): a device token that lets
  us send you push notifications, your device's time zone (so a
  reminder arrives in the evening, not at 3 a.m.), and which
  notification categories you switched off. The notification text
  passes through Google Firebase Cloud Messaging and, on iPhone,
  Apple's push service.
- **Crash reports**: if the version of the app you installed was built
  with crash reporting turned on, a crash sends a technical report
  (the error trace, your device model and OS version) — never your
  diary text.

## 2. What we don't collect

We don't sell your data to anyone, and we don't share your diary
entries or notes with anyone except the people you explicitly choose
to share them with inside the app.

## 3. Third-party catalog data

Film, series, game and book information (posters, summaries, cast,
release dates) comes from third-party catalog providers, not from you
— looking something up on tanè doesn't send your query to them tied to
your identity beyond what's needed to fetch that one piece of
information.

## 4. Premium and "restoring purchases"

**tanè premium is not yet backed by a real payment processor.** Nothing
here asks for or stores a card number, a billing address, or any other
payment detail, because right now nothing here charges you one. What
"go premium" and "restore purchases" both do is read and write one
flag on your account, on our own server — which is exactly why restore
purchases works the way it does: it re-checks that same account-level
flag, rather than replaying a receipt with a store.

## 5. Where your data lives, and for how long

Everything in this section stays tied to your account until you delete
it. Deleting your account (Settings → Account → Delete account) makes
it invisible immediately and permanently erases everything in it after
{settings.account_purge_after_days} days. You can download a full copy
of your account, as one file, at any time from the same screen — see
the Terms of Use for the full detail on both.

## 6. Children

tanè is not directed at children, and we don't knowingly collect data
from anyone below the age most relevant app stores set for unsupervised
accounts.

## 7. Changes to this policy

If this document changes in a way that matters, the version line at
the top changes with it — there's no separate notification list to
sign up for; check back here.

## 8. Contact

{settings.moderation_contact_email or "Use the in-app report flow — Profile → Settings → Report a problem."}
"""


PRIVACY_POLICY_RU = f"""# tanè — Политика конфиденциальности

_Версия {settings.privacy_policy_version}_

## 1. Что мы собираем

- **Данные аккаунта**: имя пользователя, пароль (хранится только в
  хэшированном виде, никогда открытым текстом), и адрес электронной
  почты — только если вы сами решите его добавить.
- **То, что вы пишете**: записи дневника, заметки, списки, оценки и
  всё остальное, что вы вводите в приложении.
- **То, что вы смотрите/играете/читаете**: тайтлы, которые вы
  логируете, добавляете в избранное или в список, — и из какого
  каталога они взяты (сторонняя база фильмов/сериалов/игр/книг, см.
  раздел 3).
- **Статус премиума**: премиум ли ваш аккаунт, какой план и когда он
  был куплен или предоставлен. См. раздел 4 — данные банковской карты
  или оплаты здесь попросту нечего собирать.
- **Базовые события использования**: небольшие факты из закрытого
  словаря — какие экраны открываются, какие функции используются, —
  никогда не сам введённый текст, не поисковые запросы и не ваш email.
  Их идентифицирует случайный id устройства, а не аккаунт, если вы не
  вошли в систему.
- **Уведомления** (только если вы их разрешили): токен устройства, по
  которому мы можем присылать push-уведомления, часовой пояс
  устройства (чтобы напоминание приходило вечером, а не в три часа
  ночи) и какие категории уведомлений вы отключили. Текст уведомления
  проходит через Google Firebase Cloud Messaging, а на iPhone ещё и
  через push-сервис Apple.
- **Отчёты о сбоях**: если установленная вами версия приложения
  собрана с включённой отправкой отчётов о сбоях, при падении уходит
  технический отчёт (трассировка ошибки, модель устройства и версия
  ОС) — но никогда не текст ваших записей.

## 2. Чего мы не собираем

Мы не продаём ваши данные никому и не передаём записи дневника или
заметки никому, кроме тех, с кем вы сами решили ими поделиться внутри
приложения.

## 3. Данные сторонних каталогов

Информация о фильмах, сериалах, играх и книгах (постеры, описания,
актёры, даты выхода) берётся из сторонних каталогов, а не от вас —
поиск в tanè не передаёт им ваш запрос, привязанный к вашей личности,
сверх того, что нужно для получения этой информации.

## 4. Премиум и «восстановление покупок»

**Подписка tanè premium пока не подключена к реальному платёжному
процессору.** Здесь нигде не запрашивается и не хранится номер карты,
платёжный адрес или любые другие платёжные данные — потому что прямо
сейчас здесь ничего не списывает с вас деньги. И «оформить премиум», и
«восстановить покупки» на деле читают и записывают один и тот же флаг
на вашем аккаунте, на нашем сервере, — именно поэтому восстановление
покупок работает именно так: оно заново проверяет тот же флаг на
уровне аккаунта, а не повторяет чек перед магазином приложений.

## 5. Где хранятся ваши данные и как долго

Всё из этого раздела остаётся привязанным к вашему аккаунту до тех
пор, пока вы его не удалите. Удаление аккаунта (Настройки → Аккаунт →
Удалить аккаунт) делает его невидимым сразу же и безвозвратно стирает
всё содержимое через {settings.account_purge_after_days} дней. Полную
копию аккаунта одним файлом можно выгрузить в любой момент на том же
экране — подробности в Пользовательском соглашении.

## 6. Дети

tanè не предназначен для детей, и мы сознательно не собираем данные
от людей младше возраста, который большинство магазинов приложений
устанавливают для аккаунтов без родительского контроля.

## 7. Изменения в этой политике

Если этот документ меняется существенно, строка версии наверху
меняется вместе с ним — отдельной рассылки для подписки нет; загляните
сюда снова.

## 8. Связь с нами

{settings.moderation_contact_email or "Через форму жалобы в приложении: Профиль → Настройки → Сообщить о проблеме."}
"""


def eula_for(lang: str) -> str:
    return EULA_RU if (lang or "").lower().startswith("ru") else EULA_EN


def privacy_policy_for(lang: str) -> str:
    return PRIVACY_POLICY_RU if (lang or "").lower().startswith("ru") else PRIVACY_POLICY_EN
