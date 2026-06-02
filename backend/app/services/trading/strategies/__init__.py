"""Strategies package — trading strategy implementations."""

from app.services.trading.strategies.all_pairs_hammer import AllPairsHammerStrategy
from app.services.trading.strategies.all_pairs_inverse_hammer import AllPairsInverseHammerStrategy
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.strategies.hammer import HammerStrategy
from app.services.trading.strategies.inverse_hammer import InverseHammerStrategy
from app.services.trading.strategies.ma_crossover import MaCrossoverStrategy
from app.services.trading.strategies.triple_ma import TripleMaStrategy
from app.services.trading.strategies.macd_crossover import MacdCrossoverStrategy
from app.services.trading.strategies.parabolic_sar import ParabolicSarStrategy
from app.services.trading.strategies.adx import AdxStrategy
from app.services.trading.strategies.supertrend import SupertrendStrategy
from app.services.trading.strategies.rsi_oversold import RsiOversoldStrategy
from app.services.trading.strategies.stochastic import StochasticStrategy
from app.services.trading.strategies.engulfing import EngulfingStrategy
from app.services.trading.strategies.doji import DojiStrategy
from app.services.trading.strategies.three_soldiers import ThreeSoldiersStrategy
from app.services.trading.strategies.bollinger_bands import BollingerBandsStrategy
from app.services.trading.strategies.keltner_channels import KeltnerChannels
from app.services.trading.strategies.atr_breakout import ATRBreakout
from app.services.trading.strategies.donchian import Donchian
from app.services.trading.strategies.vwap import VWAPStrategy
from app.services.trading.strategies.obv import OBVStrategy
from app.services.trading.strategies.rsi_ma_combo import RSIMACombo

__all__ = [
    "AllPairsHammerStrategy",
    "AllPairsInverseHammerStrategy",
    "AbstractStrategy",
    "HammerStrategy",
    "InverseHammerStrategy",
    "MaCrossoverStrategy",
    "TripleMaStrategy",
    "MacdCrossoverStrategy",
    "ParabolicSarStrategy",
    "AdxStrategy",
    "SupertrendStrategy",
    "RsiOversoldStrategy",
    "StochasticStrategy",
    "EngulfingStrategy",
    "DojiStrategy",
    "ThreeSoldiersStrategy",
    "BollingerBandsStrategy",
    "KeltnerChannels",
    "ATRBreakout",
    "Donchian",
    "VWAPStrategy",
    "OBVStrategy",
    "RSIMACombo",
]
