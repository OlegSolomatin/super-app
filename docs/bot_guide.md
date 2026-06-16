# 🤖 Telegram Bot Guide — Super-App

## 🧬 Архитектура ботов

```
Telegram ←→ Bot API (Token) ←→ notification_bot.py  →  Redis pub/sub
                                         ↑
                                   signal_mapper.py ← channel:signal:new
                                         ↑
                              parse_telegram_signals.py (парсит каналы)
```

### 2 Telegram бота в системе

| Бот | Username | Токен | Назначение |
|-----|----------|-------|------------|
| **Trading_info** | @tradinf_info_pfumiko_bot | `8830505865:...` | Отправляет сигналы, уведомления о трейдах |
| **Coder_PRO** | @coder_pro_phumiko_bot | `8995846482:...` | Отправляет сообщения от DeepSeek V4 PRO |

Оба бота привязаны к **chat_id=218809870** (личный чат Олега).

---

## 🔄 Демоны (3 процесса)

### 1. Signal Parser (`parse_telegram_signals.py`)
- **Назначение:** Парсит Telegram-каналы скринеров каждые 5 сек
- **Источник:** Telegram публичные каналы (brushscreener, stairscreener и т.д.)
- **Действие:** Сохраняет сигналы в БД → публикует в Redis `channel:signal:new`
- **Запуск:** `--daemon` режим (бесконечный цикл)

### 2. Signal Mapper (`map_signals_daemon.py`)
- **Назначение:** Классифицирует сырые сигналы через LLM (DeepSeek Flash)
- **Вход:** Слушает Redis `channel:signal:new`
- **Выход:** Публикует в Redis `channel:signal:mapped`
- **Особенности:** Concurrent semaphore (макс 5 классификаций), dup guard через Redis lock

### 3. Signal Notifier (`notification_bot.py`)
- **Назначение:** Забирает классифицированные сигналы → отправляет в Telegram
- **Вход:** Слушает Redis `channel:signal:mapped`
- **Выход:** POST к Telegram Bot API (все боты из БД)
- **Особенности:** Буфер 3 сек (группировка), Inline-кнопки (открыть, запустить), dup guard через Redis lock

### 4. Hermes Gateway (опционально)
- **Назначение:** Шлюз Hermes для общения с ИИ через Telegram
- **Запуск:** `hermes gateway run`
- **Лог:** `~/gateway.log`

---

## 📂 Логи всех ботов

| Процесс | Файл лога |
|---------|-----------|
| Parser | `/tmp/signal_parser.log` |
| Mapper | `/tmp/signal_mapper.log` |
| Notifier | `/tmp/signal_notifier.log` |
| Hermes Gateway | `~/gateway.log` |

---

## 🧪 Проверка работы

```bash
# Проверить что процессы живые
ps aux | grep -E "parse_telegram|map_signals|notification_bot" | grep -v grep

# Проверить последние отправленные сигналы
tail -5 /tmp/signal_notifier.log

# Отправить тест напрямую через Telegram Bot API
curl -s -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=218809870" \
  -d "text=Тест" \
  -d "parse_mode=HTML"
```

---

## ⚙️ Добавление нового бота

1. Создать бота через @BotFather в Telegram
2. Получить токен
3. Пользователь пишет боту `/start` (обязательно!)
4. Добавить в БД через SettingsPage на сайте или API:

```bash
curl -X POST "http://localhost:8000/api/v1/settings/telegram-bots" \
  -H "Authorization: Bearer <токен>" \
  -H "Content-Type: application/json" \
  -d '{"name": "BotName", "bot_token": "<TOKEN>", "chat_id": "218809870"}'
```

5. Перезапустить notifier (или подождать авто-перезагрузку)
