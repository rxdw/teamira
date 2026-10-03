# Голос в комнате совместного просмотра («Гостиная»)

Голос в комнатах бесплатный для всех и идёт через **LiveKit**, развёрнутый на
вашем сервере. Только аудио, ничего не записывается: бэкенд лишь выдаёт
короткоживущий токен (`POST /partner/rooms/{id}/voice-token`), а звук ходит
между телефонами и LiveKit.

Пока `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` пусты, комнаты
работают как обычно (видео, чат, реакции), а кнопка микрофона отвечает
«голос на этом сервере пока не включён».

## Сколько это ест

LiveKit на Go и ничего не перекодирует (только пересылает аудиопакеты).
Порядок величин, по памяти (проверьте `docker stats` после запуска): пустой
сервер — десятки мегабайт, несколько десятков одновременных комнат — сотни
мегабайт ОЗУ. Узкое место — сеть и процессор, а не память. Для вашего
масштаба хватит 1–2 vCPU и ~1 ГБ запаса.

## Что открыть и настроить

- поддомен с TLS, например `rtc.example.com` (клиенты подключаются по `wss://`);
- TCP `7881` и UDP-порт `7882` (в `livekit.yaml` ниже включён один UDP-порт
  вместо диапазона — так проще файрволу);
- TURN встроен в тот же процесс; для мобильных сетей и жёстких NAT его стоит
  включить (в конфиге ниже включён);
- если Docker стоит за обратным прокси, контейнеру LiveKit нужен
  `network_mode: host`, иначе проброс UDP получается хрупким.

## docker-compose (добавить рядом с бэкендом)

```yaml
  livekit:
    image: livekit/livekit-server:latest
    command: --config /etc/livekit.yaml
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml:ro
```

## livekit.yaml

```yaml
port: 7880
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
keys:
  # ключ: секрет — те же значения, что в .env бэкенда
  seenly: CHANGE_ME_to_a_long_random_string_at_least_32_chars
turn:
  enabled: true
  domain: rtc.example.com
  tls_port: 5349
  udp_port: 3478
```

TLS для `rtc.example.com` терминируйте обратным прокси (caddy/nginx) на порт
`7880` либо выдайте сертификат самому LiveKit по их документации.

## .env бэкенда

```
LIVEKIT_URL=wss://rtc.example.com
LIVEKIT_API_KEY=seenly
LIVEKIT_API_SECRET=CHANGE_ME_to_a_long_random_string_at_least_32_chars
```

Токен подписан HS256 тем же секретом, живёт два часа, даёт право зайти только
в комнату `co-view-<id комнаты>`: публиковать и слушать звук, без data-каналов.
