# AnalyticsRepo — аналитическая платформа Golden House

Монорепозиторий-сборка: шлюз с единой авторизацией плюс бизнес-сервисы,
подключённые к нему как git-сабмодули.

## Архитектура

```
                     ┌──────────────────────────────┐
   интернет ────────►│  nginx  (public_network)     │  :80 → :443
                     │  единственный вход снаружи   │
                     └───────────────┬──────────────┘
                                     │ auth_request /verify
                     ┌───────────────▼──────────────┐   ┌──────────┐
                     │  auth-service (Go)           ├───│  mongo   │ data_network
                     │  пользователи, роли, права,  │   └──────────┘
                     │  реестр сервисов, конфиг nginx│
                     └───────┬───────────────┬──────┘
                             │               │
        ┌────────────────────┼───────────────┼───────────────────┐
        │ service_network    │               │                   │
        ▼                    ▼               ▼                   ▼
  notification-service  notification-bot  monitoring-service   dozzle
   (Go + PostgreSQL)     (Telegram API)     (health-опрос)    (логи, /logs)
        │                    │                                   │
        │ SMTP               │ egress_network              docker-socket-proxy
        ▼                    ▼                                   │
     почта              Telegram                          /var/run/docker.sock

        service_network также ведёт в бизнес-сервисы:
        /referal → referal   /client-service → client_service   /finder → apartment_finder

        quiz_network (отдельно):  nginx ↔ quiz-backend / quiz-widget / quiz-admin
```

Бизнес-сервис не проверяет пароли и не видит JWT: шлюз кладёт уже проверенную
личность в заголовки `X-User-*`.

## Состав репозитория

| Каталог | Что | Сабмодуль |
|---|---|---|
| `docs/` | документация платформы: шлюз + контракт подключения сервисов | да |
| `!gateway/` | шлюз: nginx, auth-service, mongo, уведомления, мониторинг, логи | да |
| `referal/` | реферальная программа (Python/Flask) | да |
| `client_service/` | управление клиентами (Python/Flask) | да |
| `apartment_finder/` | подбор недвижимости (Python/Flask) | да |
| `auth-connector/` | Python-пакет интеграции сервиса со шлюзом | да |
| `scriptovod/` | сервис скриптов колл-центра (в разработке) | да |
| `quiz/` | квизы для сайта gh.uz (изолированный) | нет |
| `Hr_bot/` | HR-бот | нет |
| `READMEs/`, `migration_backup/`, `prod_backups/` | архивы и бэкапы | нет |

## Документация

### Шлюз

Вся документация вынесена в сабмодуль **[docs/](docs/README.md)**.
Точка входа для ИИ-агента — **[docs/AGENTS.md](docs/AGENTS.md)**.

По одному файлу на каждый сервис шлюза плюс сквозная архитектура:

| Документ | О чём |
|---|---|
| [docs/README.md](docs/gateway/README.md) | карта сервисов, порядок запуска, известные расхождения |
| [docs/architecture.md](docs/gateway/architecture.md) | сети, путь запроса, контракт `auth_request`, service discovery |
| [docs/nginx.md](docs/gateway/nginx.md) | конфиги, маршруты, rate-limit, заголовки безопасности |
| [docs/auth-service.md](docs/gateway/auth-service.md) | API, модель прав, middleware, MongoDB, переменные |
| [docs/notification-service.md](docs/gateway/notification-service.md) | очереди каналов, приоритеты, security guard |
| [docs/notification-bot.md](docs/gateway/notification-bot.md) | Telegram: уведомления, привязка, вход, лимиты |
| [docs/monitoring-service.md](docs/gateway/monitoring-service.md) | опрос health, логика алертов |
| [docs/mongo.md](docs/gateway/mongo.md) | коллекции, пользователи, бэкап |
| [docs/dozzle.md](docs/gateway/dozzle.md) | просмотр логов и права на него |
| [docs/docker-socket-proxy.md](docs/gateway/docker-socket-proxy.md) | разрешённые операции Docker API |
| [docs/guard-watchdog.md](docs/gateway/guard-watchdog.md) | авто-карантин (готов, но не запущен) |
| [docs/quiz.md](docs/gateway/quiz.md) | изолированная маршрутизация quiz |

### Подключение своего сервиса

| Документ | О чём |
|---|---|
| [GATEWAY_SERVICE_INTEGRATION_API.md](docs/integration/GATEWAY_SERVICE_INTEGRATION_API.md) | полный справочник: контракт сервиса, заголовки, HTTP API шлюза, модель прав |
| [AUTH_CONNECTOR_SETUP_AND_LOCAL_DEV.md](docs/integration/AUTH_CONNECTOR_SETUP_AND_LOCAL_DEV.md) | пакет `auth-connector`, подключение к Flask, локальная разработка |
| [TELEGRAM_NOTIFICATIONS_INTEGRATION_GUIDE.md](docs/integration/TELEGRAM_NOTIFICATIONS_INTEGRATION_GUIDE.md) | уведомления в Telegram из своего сервиса |
| [QUICKFIX_CLIENT_SERVICE_ROLES.md](QUICKFIX_CLIENT_SERVICE_ROLES.md) | восстановление ролей client-service |

## Запуск

```bash
./start_all.sh          # Linux/macOS
.\start_all.ps1         # Windows
```

Скрипт делает `git pull` по репозиториям, создаёт `egress_network`
(с `enable_icc=false`), поднимает шлюз, ждёт его healthcheck, затем
notification-service и бизнес-сервисы.

Только шлюз:

```bash
cd '!gateway' && docker compose up -d
cd notification-service && docker compose up -d
```

Порядок важен: `notification-service`, бизнес-сервисы и quiz подключаются к
сетям, которые создаёт compose шлюза.

## Точки входа

| URL | Что |
|---|---|
| `https://analytics.gh.uz/` | редирект на меню |
| `/login`, `/login/telegram` | вход по паролю или через Telegram |
| `/menu` | доступные пользователю сервисы |
| `/profile` | личный кабинет: аватар, документы, привязка Telegram |
| `/users`, `/services`, `/settings` | админка |
| `/notification-settings` | SMTP и каналы доставки |
| `/logs`, `/services/<key>/logs` | логи контейнеров (Dozzle) |
| `/referal/`, `/client-service/`, `/finder/` | бизнес-сервисы (префикс = `service_key`) |
| `/quiz/<id>`, `/quiz/admin/` | квизы и их админка |

Внутренние API портов наружу не имеют: `auth-service`,
`notification-service`, `notification-bot`, `monitoring-service` доступны
только внутри docker-сетей.

## Конфигурация

Секреты не в git. У каждого сервиса свой `.env`, рядом лежит `.env.example`.

| Файл | Ключевое |
|---|---|
| `!gateway/.env` | `MONGO_ROOT_PASSWORD`, `MONGO_APP_PASSWORD` |
| `!gateway/auth-service/.env` | `MONGO_URI`, `JWT_SECRET`, `INTERNAL_API_KEY`, `BASE_URL` |
| `!gateway/notification-service/.env` | `SERVICE_API_KEYS`, SMTP, `SERVICE_PRIORITIES` |
| `!gateway/notification-bot/.env` | `TELEGRAM_BOT_TOKEN`, `INTERNAL_API_KEY` |
| `!gateway/monitoring-service/.env` | `MONITORED_SERVICES`, `ALERT_*` |

Значения, которые обязаны совпадать между сервисами:

- `JWT_SECRET` — auth-service, `client_service`, `referal`;
- `INTERNAL_API_KEY` — auth-service, notification-bot, notification-service
  (как легаси-ключ), все вызывающие `/api/*`;
- `MONGO_APP_PASSWORD` в `!gateway/.env` = пароль внутри `MONGO_URI`.

## Уведомления

Единая очередь доставки — `notification-service`. Вызывающий сервис
**не хранит контакты**: он указывает `login` пользователя портала, а адрес
доставки (email, `chat_id`, телефон) подставляет auth-service по запросу
`POST /api/recipients/resolve`. Получателя вне портала задаёт поле
`external_recipient`.

```json
POST /api/v1/notifications
X-API-Key: <персональный ключ сервиса>

{ "type": "email", "login": "ivanov", "subject": "Тема", "content": "Текст" }
```

Каналы независимы (у каждого своя очередь, темп и повторы), у отправителей
есть приоритетная полоса. Контракт — раздел 6
[GATEWAY_SERVICE_INTEGRATION_API.md](docs/integration/GATEWAY_SERVICE_INTEGRATION_API.md),
устройство — [docs/notification-service.md](docs/gateway/notification-service.md).

Telegram-канал ведёт через `notification-bot` — **единственную** точку
обращения к Telegram Bot API в системе.

## Диагностика

```bash
docker ps                                      # что поднято
docker logs -f gateway-auth-service-1          # авторизация
docker logs -f gateway-nginx-1                 # маршрутизация
docker logs -f notification-service-notification-service-1
docker logs -f gateway-notification-bot

# health
curl -k https://localhost/health                          # auth-service через nginx
docker exec gateway-nginx-1 nginx -t                      # конфиг nginx
```

Веб-просмотр логов с разграничением по сервисам — `/logs` и
`/services/<key>/logs` (см. [docs/dozzle.md](docs/gateway/dozzle.md)).

Частые проблемы:

| Симптом | Причина |
|---|---|
| `502` на сервисе | контейнер не поднят; маршрут остаётся жив специально, чтобы не было 404 |
| `404` на сервисе | сервис ни разу не регистрировался в реестре |
| правка `.env` не подхватилась | `docker compose restart` не перечитывает `env_file` — нужен `up -d --force-recreate` |
| `401` от notification-service | ключ сервиса не заведён в `SERVICE_API_KEYS` |
| пустая страница вместо сервиса у админа | нет роли в сервисе; чинится рестартом auth-service (`EnsureServiceAdminRoles`) |
