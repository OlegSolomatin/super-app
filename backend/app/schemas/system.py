from pydantic import BaseModel


class SystemLoadResponse(BaseModel):
    cpu_percent: float
    ram_gb: float
    api_usage_percent: float
    active_ob_runs: int
    active_trading_runs: int
    warnings: list[str] = []
