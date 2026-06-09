"""System load monitoring endpoint — CPU, RAM, API usage."""

import psutil

from fastapi import APIRouter

from app.schemas.system import SystemLoadResponse

router = APIRouter(tags=["system"])


@router.get("/system/load", response_model=SystemLoadResponse)
async def system_load():
    """Return current system load: CPU, RAM, API usage."""
    # CPU: 85% от реальной загрузки (оставляем 15% запаса для ОС)
    raw_cpu = psutil.cpu_percent(interval=None)
    cpu_percent = round(raw_cpu * 0.85, 1)

    # RAM: текущее использование в GB, шкала до 10GB (из 16)
    mem = psutil.virtual_memory()
    ram_gb = round(mem.used / (1024**3), 2)

    # API: считаем активные engine
    from app.services.trading.scheduler import scheduler

    active_ob = scheduler.get_active_ob_count()
    active_trading = scheduler.get_active_count() - active_ob
    total_active = active_ob + active_trading
    max_ws = 5  # Binance лимит WS-соединений на IP
    api_usage_percent = round(min(total_active / max_ws * 100, 100), 1)

    # Предупреждения
    warnings: list[str] = []
    if cpu_percent > 80:
        warnings.append(f"Высокая загрузка CPU ({cpu_percent}%). Возможны задержки при запуске новых стратегий.")
    if ram_gb > 8:
        warnings.append(f"Использовано {ram_gb:.1f} GB RAM. Закройте неиспользуемые приложения.")
    if api_usage_percent > 80:
        warnings.append(f"Достигнут лимит API ({api_usage_percent}%). Новые запуски могут быть ограничены.")

    return SystemLoadResponse(
        cpu_percent=cpu_percent,
        ram_gb=ram_gb,
        api_usage_percent=api_usage_percent,
        active_ob_runs=active_ob,
        active_trading_runs=max(active_trading, 0),
        warnings=warnings,
    )
