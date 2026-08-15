"""Typed, dependency-free read client for Argentum vault integrations."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


BPS = 10_000


class VaultContract(Protocol):
    def total_assets(self) -> int: ...
    def liquid_assets(self) -> int: ...
    def free_liquidity(self) -> int: ...
    def reserve_liquidity(self) -> int: ...
    def strategy_assets(self) -> int: ...
    def withdrawal_liabilities(self) -> int: ...
    def totalSupply(self) -> int: ...
    def price_per_share(self) -> int: ...
    def current_epoch(self) -> int: ...
    def epochs(self, epoch: int) -> Any: ...
    def requests(self, request_id: int) -> Any: ...


@dataclass(frozen=True, slots=True)
class VaultSnapshot:
    total_assets: int
    liquid_assets: int
    free_liquidity: int
    reserve_liquidity: int
    strategy_assets: int
    withdrawal_liabilities: int
    total_supply: int
    price_per_share: int
    current_epoch: int

    @property
    def liquid_ratio_bps(self) -> int:
        return _ratio_bps(self.liquid_assets, self.total_assets)

    @property
    def reserve_ratio_bps(self) -> int:
        return _ratio_bps(self.reserve_liquidity, self.total_assets)

    @property
    def strategy_ratio_bps(self) -> int:
        return _ratio_bps(self.strategy_assets, self.total_assets)

    def reconciles(self) -> bool:
        return self.total_assets == (
            self.free_liquidity + self.reserve_liquidity + self.strategy_assets
        )


@dataclass(frozen=True, slots=True)
class EpochSnapshot:
    epoch: int
    first_request_id: int
    last_request_id: int
    processed_until: int
    pending_shares: int
    pending_assets: int
    paid_assets: int
    processed_count: int
    closed: bool

    @property
    def remaining_items(self) -> int:
        if self.first_request_id == 0 or self.processed_until >= self.last_request_id:
            return 0
        cursor = max(self.first_request_id, self.processed_until + 1)
        return self.last_request_id - cursor + 1


@dataclass(frozen=True, slots=True)
class RequestSnapshot:
    request_id: int
    owner: str
    receiver: str
    epoch: int
    shares: int
    quoted_assets: int
    snapshot_pps: int
    requested_at: int
    processed_at: int
    paid_assets: int
    status: int

    def is_mature(self, current_epoch: int) -> bool:
        return self.status == 1 and self.epoch <= current_epoch


@dataclass(frozen=True, slots=True)
class LiquidityPlan:
    pending_assets: int
    immediately_available: int
    protected_reserve: int
    processable_assets: int
    recall_required: int
    coverage_bps: int


def _ratio_bps(part: int, whole: int) -> int:
    if part < 0 or whole < 0:
        raise ValueError("asset values cannot be negative")
    if whole == 0:
        return 0
    return min(BPS, part * BPS // whole)


class ArgentumClient:
    """Read adapter plus deterministic keeper planning helpers."""

    def __init__(self, vault: VaultContract):
        self._vault = vault

    def snapshot(self) -> VaultSnapshot:
        result = VaultSnapshot(
            total_assets=int(self._vault.total_assets()),
            liquid_assets=int(self._vault.liquid_assets()),
            free_liquidity=int(self._vault.free_liquidity()),
            reserve_liquidity=int(self._vault.reserve_liquidity()),
            strategy_assets=int(self._vault.strategy_assets()),
            withdrawal_liabilities=int(self._vault.withdrawal_liabilities()),
            total_supply=int(self._vault.totalSupply()),
            price_per_share=int(self._vault.price_per_share()),
            current_epoch=int(self._vault.current_epoch()),
        )
        if not result.reconciles():
            raise ValueError("vault accounting does not reconcile")
        return result

    def epoch(self, epoch: int) -> EpochSnapshot:
        if epoch < 0:
            raise ValueError("epoch cannot be negative")
        raw = self._vault.epochs(epoch)
        return EpochSnapshot(
            epoch=epoch,
            first_request_id=int(raw[0]),
            last_request_id=int(raw[1]),
            processed_until=int(raw[2]),
            pending_shares=int(raw[3]),
            pending_assets=int(raw[4]),
            paid_assets=int(raw[5]),
            processed_count=int(raw[6]),
            closed=bool(raw[7]),
        )

    def request(self, request_id: int) -> RequestSnapshot:
        if request_id <= 0:
            raise ValueError("request_id must be positive")
        raw = self._vault.requests(request_id)
        return RequestSnapshot(
            request_id=request_id,
            owner=str(raw[0]),
            receiver=str(raw[1]),
            epoch=int(raw[2]),
            shares=int(raw[3]),
            quoted_assets=int(raw[4]),
            snapshot_pps=int(raw[5]),
            requested_at=int(raw[6]),
            processed_at=int(raw[7]),
            paid_assets=int(raw[8]),
            status=int(raw[9]),
        )

    @staticmethod
    def plan_epoch(
        pending_assets: int,
        free_liquidity: int,
        reserve_liquidity: int,
        reserve_buffer: int,
    ) -> LiquidityPlan:
        values = (pending_assets, free_liquidity, reserve_liquidity, reserve_buffer)
        if any(value < 0 for value in values):
            raise ValueError("planning values cannot be negative")
        protected = min(reserve_liquidity, reserve_buffer)
        available = free_liquidity + reserve_liquidity
        usable = available - protected
        processable = min(pending_assets, usable)
        recall = max(0, pending_assets - usable)
        return LiquidityPlan(
            pending_assets=pending_assets,
            immediately_available=available,
            protected_reserve=protected,
            processable_assets=processable,
            recall_required=recall,
            coverage_bps=BPS if pending_assets == 0 else min(BPS, usable * BPS // pending_assets),
        )

    @staticmethod
    def suggested_batch(remaining_items: int, gas_budget: int, gas_per_item: int, protocol_cap: int = 128) -> int:
        if remaining_items < 0 or gas_budget < 0:
            raise ValueError("batch inputs cannot be negative")
        if gas_per_item <= 0 or protocol_cap <= 0:
            raise ValueError("gas_per_item and protocol_cap must be positive")
        return min(remaining_items, protocol_cap, gas_budget // gas_per_item)
