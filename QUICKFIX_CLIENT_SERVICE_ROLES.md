# 🔧 БЫСТРОЕ ВОССТАНОВЛЕНИЕ РОЛЕЙ CLIENT-SERVICE

## ЧТО СЛУЧИЛОСЬ

На сервере пропали роли для client-service. Должно быть 4 роли:

- admin, call-center, manager_dcs, temporary

## ЧТО ДЕЛАТЬ НА СЕРВЕРЕ

### 1️⃣ Подключиться к серверу
```bash
ssh user@176.126.166.84
```

### 2️⃣ Перейти в директорию
```bash
cd /path/to/AnalyticsRepo
git pull origin migration
cd !gateway/auth-service
```

### 3️⃣ Проверить текущее состояние
```bash
docker exec gateway-mongo-1 mongosh authdb --eval "db.roles.countDocuments({service_key: 'client-service'})"
```

### 4️⃣ Запустить скрипт восстановления
```bash
cat restore_client_service_roles.js | docker exec -i gateway-mongo-1 mongosh authdb
```

### 5️⃣ Проверить результат

```bash
docker exec gateway-mongo-1 mongosh authdb --eval "db.roles.countDocuments({service_key: 'client-service'})"
```

Должно показать: 4

### 6️⃣ Перезапустить сервисы
```bash
cd /path/to/AnalyticsRepo/!gateway
docker compose restart auth-service nginx
```

## ✅ ГОТОВО

Роли восстановлены. Проверьте в админ-панели: http://server-ip/admin
