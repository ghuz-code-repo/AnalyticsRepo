# Analytics Repository - Система авторизации и микросервисов

Это многосервисная система для управления аналитическими сервисами с единой системой авторизации.

## Архитектура

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│     Nginx       │────│   Auth-Service   │────│ Notification-Service│
│   (Gateway)     │    │   (Go/MongoDB)   │    │   (Go/PostgreSQL)   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
         │
         ├─── /referal ──────► Referal Service (Python/Flask)
         ├─── /client ───────► Client Service (Python/Flask)
         └─── /apartment ────► Apartment Finder (Python/Flask)
```

## Компоненты

### 1. Gateway (!gateway/)
- **Auth Service** - Центральная авторизация (Go + MongoDB)
- **Notification Service** - Отправка уведомлений (Go + PostgreSQL) 
- **Nginx** - Обратный прокси с auth_request

### 2. Business Services
- **Referal** - Реферальная программа (Python/Flask)
- **Client Service** - Управление клиентами (Python/Flask)
- **Apartment Finder** - Поиск недвижимости (Python/Flask)

## Новые возможности

### ✅ Микросервис уведомлений
- Гарантированная доставка email с повторными попытками
- Поддержка пачковой отправки для оптимизации производительности
- Отслеживание статусов отправки в PostgreSQL
- Fallback на прямую отправку при недоступности сервиса
- Готовность к добавлению SMS и push-уведомлений

### 🔄 Обновленная система авторизации
- Все сервисы получают контекст пользователя через HTTP заголовки
- Auth-service проверяет JWT токены через nginx auth_request
- Единая точка управления пользователями и ролями

## Быстрый запуск

### Все сервисы с уведомлениями:
```powershell
# Windows
.\start_all_with_notifications.ps1

# Linux/Mac  
./start_all_with_notifications.sh
```

### Только gateway (auth + notifications):
```bash
cd !gateway
docker-compose up -d
```

## Endpoints

### Главные сервисы:
- **Главная страница**: http://localhost/
- **Авторизация**: http://localhost/login
- **Админ-панель**: http://localhost/admin-menu

### Business Services:
- **Referal**: http://localhost/referal
- **Client Service**: http://localhost/client (если настроен)
- **Apartment Finder**: http://localhost/apartment (если настроен)

### API:
- **Notification API**: http://localhost:8082/api/v1/health
- **Auth API**: http://localhost/api/

## Конфигурация

### Переменные окружения Gateway:
```env
# MongoDB (Auth)
MONGO_URI=mongodb://mongo:27017
MONGO_DB=authdb

# SMTP для уведомлений  
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
SMTP_USE_TLS=true
SMTP_USE_AUTH=true

# JWT
JWT_SECRET=your-jwt-secret

# Notification Service
NOTIFICATION_SERVICE_URL=http://notification-service:8082
```

### Переменные окружения Notification Service:
```env
# PostgreSQL
DB_HOST=notification-postgres
DB_USER=postgres
DB_PASSWORD=notification_password
DB_NAME=notifications

# Processing settings
MAX_RETRY_ATTEMPTS=3
BATCH_SIZE=10
DELAY_BETWEEN_BATCHES_MS=1000
```

## Структура проекта

```
├── !gateway/                   # Gateway с авторизацией
│   ├── auth-service/          # Основной сервис авторизации
│   ├── nginx/                 # Nginx конфигурация
│   └── docker-compose.yaml    # Контейнеры gateway
│
├── notification-service/       # NEW! Микросервис уведомлений
│   ├── main.go               # HTTP API
│   ├── processors.go         # Email/SMS/Push процессоры
│   └── docker-compose.yml    # Standalone контейнеры
│
├── referal/                   # Реферальная программа
├── client-service/            # Управление клиентами  
├── apartment-finder/          # Поиск недвижимости
│
├── start_all_with_notifications.ps1  # Запуск всех сервисов
└── NOTIFICATION_SERVICE_MIGRATION.md # Документация миграции
```

## Миграция к новой системе уведомлений

Подробную документацию по миграции см. в [NOTIFICATION_SERVICE_MIGRATION.md](NOTIFICATION_SERVICE_MIGRATION.md)

### Основные изменения:
1. **Новый сервис**: notification-service для централизованной отправки
2. **Fallback**: автоматический переход к старому методу при недоступности
3. **Статистика**: отслеживание всех отправленных уведомлений
4. **Масштабируемость**: поддержка пачковой отправки

## Мониторинг

### Проверка статуса сервисов:
```bash
# Все контейнеры
docker ps

# Логи уведомлений
docker logs gateway_notification-service_1

# Логи авторизации
docker logs gateway_auth-service_1
```

### API health checks:
```bash
# Notification service
curl http://localhost:8082/api/v1/health

# Auth service (через nginx)
curl http://localhost/api/health
```

## Troubleshooting

### Notification Service недоступен:
- Автоматический fallback на прямую отправку SMTP
- Проверить логи: `docker logs gateway_notification-service_1`

### Проблемы с авторизацией:
- Проверить MongoDB: `docker logs gateway_mongo_1`
- Проверить JWT настройки в .env

### Проблемы с SMTP:
- Проверить настройки в !gateway/auth-service/.env
- Проверить статусы уведомлений в PostgreSQL

## Разработка

### Локальная разработка notification-service:
```bash
cd notification-service
go run . # требует PostgreSQL
```

### Локальная разработка auth-service:
```bash
cd !gateway/auth-service  
go run . # требует MongoDB
```

### Тестирование:
```bash
# Сборка notification service
.\test_notification_build.ps1

# Тестирование API
curl -X POST http://localhost:8082/api/v1/notifications \
  -H "Content-Type: application/json" \
  -d '{"type":"email","recipient":"test@example.com","subject":"Test","content":"Hello"}'
```

## Следующие шаги

1. **Адаптация referal сервиса** к новой системе авторизации
2. **SMS уведомления** - интеграция с SMS провайдерами
3. **Push уведомления** - мобильные уведомления
4. **Метрики** - Prometheus/Grafana мониторинг
5. **Шаблоны** - централизованное управление шаблонами уведомлений