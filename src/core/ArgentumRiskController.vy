# @version ^0.4.3

"""
Risk controller for strategy allocation and epoch settlement.

This component models the control layer a production vault would place around
strategies and keepers. It focuses on allocation pressure, reported losses, and
keeper throttles around epoch settlement.
"""

BPS: constant(uint256) = 10_000
MAX_BPS: constant(uint256) = 10_000

struct StrategyLimit:
    enabled: bool
    max_debt_bps: uint256
    max_loss_bps: uint256
    min_liquidity_bps: uint256
    cooldown: uint256
    last_report: uint256
    cumulative_loss: uint256

event OwnerUpdated:
    owner: indexed(address)

event KeeperUpdated:
    keeper: indexed(address)

event StrategyLimitUpdated:
    strategy: indexed(address)
    enabled: bool
    max_debt_bps: uint256
    max_loss_bps: uint256
    min_liquidity_bps: uint256
    cooldown: uint256

event GlobalLimitUpdated:
    key: indexed(bytes32)
    new_value: uint256

event LossRegistered:
    strategy: indexed(address)
    loss_amount: uint256
    cumulative_loss: uint256

event QueuePressureRegistered:
    epoch: indexed(uint256)
    pending_assets: uint256
    coverage_bps: uint256

owner: public(address)
keeper: public(address)

max_total_strategy_bps: public(uint256)
max_epoch_pending_bps: public(uint256)
min_global_liquidity_bps: public(uint256)
paused: public(bool)

strategy_limits: public(HashMap[address, StrategyLimit])
epoch_pending_assets: public(HashMap[uint256, uint256])
epoch_coverage_bps: public(HashMap[uint256, uint256])


@deploy
def __init__(_owner: address, _keeper: address):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _keeper != empty(address), "ZERO_KEEPER"
    self.owner = _owner
    self.keeper = _keeper
    self.max_total_strategy_bps = 8_000
    self.max_epoch_pending_bps = 3_500
    self.min_global_liquidity_bps = 1_000


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _only_keeper():
    assert msg.sender == self.keeper or msg.sender == self.owner, "ONLY_KEEPER"


@internal
@pure
def _ratio_bps(part: uint256, whole: uint256) -> uint256:
    if whole == 0:
        return 0
    return part * BPS // whole


@internal
@pure
def _coverage_bps(available: uint256, required: uint256) -> uint256:
    if required == 0:
        return BPS
    coverage: uint256 = available * BPS // required
    if coverage > BPS:
        return BPS
    return coverage


@external
def set_owner(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner
    log OwnerUpdated(owner=new_owner)


@external
def set_keeper(new_keeper: address):
    self._only_owner()
    assert new_keeper != empty(address), "ZERO_KEEPER"
    self.keeper = new_keeper
    log KeeperUpdated(keeper=new_keeper)


@external
def set_paused(paused_: bool):
    self._only_owner()
    self.paused = paused_


@external
def set_global_limits(max_strategy_bps: uint256, max_pending_bps: uint256, min_liquidity_bps: uint256):
    self._only_owner()
    assert max_strategy_bps <= MAX_BPS, "STRATEGY_BPS"
    assert max_pending_bps <= MAX_BPS, "PENDING_BPS"
    assert min_liquidity_bps <= MAX_BPS, "LIQUIDITY_BPS"
    self.max_total_strategy_bps = max_strategy_bps
    self.max_epoch_pending_bps = max_pending_bps
    self.min_global_liquidity_bps = min_liquidity_bps
    log GlobalLimitUpdated(key=keccak256("max_total_strategy_bps"), new_value=max_strategy_bps)
    log GlobalLimitUpdated(key=keccak256("max_epoch_pending_bps"), new_value=max_pending_bps)
    log GlobalLimitUpdated(key=keccak256("min_global_liquidity_bps"), new_value=min_liquidity_bps)


@external
def set_strategy_limit(
    strategy: address,
    enabled: bool,
    max_debt_bps: uint256,
    max_loss_bps: uint256,
    min_liquidity_bps: uint256,
    cooldown: uint256,
):
    self._only_owner()
    assert strategy != empty(address), "ZERO_STRATEGY"
    assert max_debt_bps <= MAX_BPS, "DEBT_BPS"
    assert max_loss_bps <= MAX_BPS, "LOSS_BPS"
    assert min_liquidity_bps <= MAX_BPS, "LIQUIDITY_BPS"
    previous: StrategyLimit = self.strategy_limits[strategy]
    self.strategy_limits[strategy] = StrategyLimit(
        enabled=enabled,
        max_debt_bps=max_debt_bps,
        max_loss_bps=max_loss_bps,
        min_liquidity_bps=min_liquidity_bps,
        cooldown=cooldown,
        last_report=previous.last_report,
        cumulative_loss=previous.cumulative_loss,
    )
    log StrategyLimitUpdated(
        strategy=strategy,
        enabled=enabled,
        max_debt_bps=max_debt_bps,
        max_loss_bps=max_loss_bps,
        min_liquidity_bps=min_liquidity_bps,
        cooldown=cooldown,
    )


@external
def register_loss(strategy: address, loss_amount: uint256):
    self._only_keeper()
    limit: StrategyLimit = self.strategy_limits[strategy]
    assert limit.enabled, "STRATEGY_DISABLED"
    limit.cumulative_loss += loss_amount
    limit.last_report = block.timestamp
    self.strategy_limits[strategy] = limit
    log LossRegistered(strategy=strategy, loss_amount=loss_amount, cumulative_loss=limit.cumulative_loss)


@external
def register_queue_pressure(epoch: uint256, pending_assets: uint256, liquid_assets: uint256):
    self._only_keeper()
    coverage: uint256 = self._coverage_bps(liquid_assets, pending_assets)
    self.epoch_pending_assets[epoch] = pending_assets
    self.epoch_coverage_bps[epoch] = coverage
    log QueuePressureRegistered(epoch=epoch, pending_assets=pending_assets, coverage_bps=coverage)


@external
@view
def check_allocation(
    strategy: address,
    total_assets: uint256,
    strategy_assets_before: uint256,
    total_strategy_assets_before: uint256,
    allocation_amount: uint256,
) -> bool:
    if self.paused:
        return False
    limit: StrategyLimit = self.strategy_limits[strategy]
    if not limit.enabled:
        return False
    next_strategy_assets: uint256 = strategy_assets_before + allocation_amount
    next_total_strategy: uint256 = total_strategy_assets_before + allocation_amount
    if self._ratio_bps(next_strategy_assets, total_assets) > limit.max_debt_bps:
        return False
    if self._ratio_bps(next_total_strategy, total_assets) > self.max_total_strategy_bps:
        return False
    return True


@external
@view
def check_liquidity_after_allocation(total_assets: uint256, liquid_assets_before: uint256, allocation_amount: uint256) -> bool:
    if liquid_assets_before < allocation_amount:
        return False
    next_liquid: uint256 = liquid_assets_before - allocation_amount
    return self._ratio_bps(next_liquid, total_assets) >= self.min_global_liquidity_bps


@external
@view
def check_loss_report(strategy: address, strategy_assets_before: uint256, loss_amount: uint256) -> bool:
    limit: StrategyLimit = self.strategy_limits[strategy]
    if not limit.enabled:
        return False
    if strategy_assets_before == 0:
        return loss_amount == 0
    return self._ratio_bps(loss_amount, strategy_assets_before) <= limit.max_loss_bps


@external
@view
def check_epoch_pending(total_assets: uint256, pending_assets: uint256) -> bool:
    if total_assets == 0:
        return pending_assets == 0
    return self._ratio_bps(pending_assets, total_assets) <= self.max_epoch_pending_bps


@external
@view
def check_epoch_processing(total_assets: uint256, liquid_assets: uint256, pending_assets: uint256) -> bool:
    if self.paused:
        return False
    if total_assets == 0:
        if pending_assets != 0:
            return False
    elif self._ratio_bps(pending_assets, total_assets) > self.max_epoch_pending_bps:
        return False
    if total_assets == 0:
        return pending_assets == 0
    if self._ratio_bps(liquid_assets, total_assets) < self.min_global_liquidity_bps:
        return False
    return liquid_assets >= pending_assets


@external
@view
def cooldown_elapsed(strategy: address) -> bool:
    limit: StrategyLimit = self.strategy_limits[strategy]
    if limit.cooldown == 0:
        return True
    return block.timestamp >= limit.last_report + limit.cooldown


@external
@view
def strategy_loss_bps(strategy: address, base_assets: uint256) -> uint256:
    if base_assets == 0:
        return 0
    return self.strategy_limits[strategy].cumulative_loss * BPS // base_assets


@external
@view
def queue_status(epoch: uint256, total_assets: uint256) -> (uint256, uint256, bool):
    pending: uint256 = self.epoch_pending_assets[epoch]
    pressure: uint256 = self._ratio_bps(pending, total_assets)
    return pending, pressure, pressure <= self.max_epoch_pending_bps


@external
@view
def liquidity_status(total_assets: uint256, liquid_assets: uint256) -> (uint256, bool):
    ratio: uint256 = self._ratio_bps(liquid_assets, total_assets)
    return ratio, ratio >= self.min_global_liquidity_bps
