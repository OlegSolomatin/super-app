# 🔑 Exchange API Keys — TODO (будущая реализация)

## Когда делать
После того как заработает MVP (исторические + виртуальные данные).

## Что нужно сделать

### Backend
1. Таблица `trading_exchange_keys`:
   - user_id (FK), exchange, api_key (шифрованный), api_secret (шифрованный)
   - is_active, last_used, created_at
2. Шифрование ключей при хранении (Fernet или AES)
3. API эндпоинты:
   - `POST /api/v1/trading/keys` — добавить ключ
   - `GET /api/v1/trading/keys` — список подключённых бирж (без самих ключей)
   - `DELETE /api/v1/trading/keys/{id}` — удалить
   - `POST /api/v1/trading/keys/{id}/test` — проверить валидность
4. Валидация ключей при сохранении (тестовый запрос к бирже)

### Flutter
1. Страница в настройках профиля: «API ключи бирж»
2. Форма добавления: выбор биржи → поля API Key + Secret → проверить → сохранить
3. Отображение статуса: ✅ подключено / ❌ ошибка
4. Индикатор последнего успешного запроса

### Список бирж для интеграции
| Биржа | Документация по API ключам |
|-------|---------------------------|
| **Bybit** | https://www.bybit.com/en/app/user/api-management |
| **Binance** | https://www.binance.com/en/support/faq/how-to-create-api-keys-on-binance-360002502072 |
| **OKX** | https://www.okx.com/account/my-api |
| **Gate.io** | https://www.gate.io/user/center/api |
| **KuCoin** | https://www.kucoin.com/account/api |
| **HTX (Huobi)** | https://www.htx.com/en-us/apikey/ |
| **MEXC** | https://www.mexc.com/api-setting |
| **Bitget** | https://www.bitget.com/profile/account/api |

### Требования к безопасности
- Ключи никогда не возвращаются в API ответах (только статус)
- Хранить зашифрованными в БД
- Расшифровывать только в момент отправки запроса к бирже
- Возможность отозвать ключи (DELETE)
- Логирование всех действий с ключами

### Связанные файлы
- `backend/app/services/trading/exchange/base.py` — AbstractExchange
- `backend/app/services/trading/exchange/bybit.py` — реализация
- `backend/app/services/trading/exchange/binance.py` — реализация
- `backend/app/api/v1/trading.py` — эндпоинты для ключей
- `backend/app/schemas/trading.py` — схемы ключей
