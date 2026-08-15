# @version ^0.4.3

"""
Deterministic stress engine for treasury and keeper automation.

The engine evaluates liquidity, reserve and strategy-loss scenarios without
holding funds or mutating the vault. All ratios use basis points and all asset
values must use the underlying token precision.
"""

BPS: constant(uint256) = 10_000
MAX_BPS: constant(uint256) = 10_000

struct StressResult:
    assets_after_shock: uint256
    liquid_after_recall: uint256
    queue_shortfall: uint256
    reserve_after_queue: uint256
    pps_after_shock: uint256
    liquidity_bps: uint256
    reserve_bps: uint256
    severity: uint256

event OwnerUpdated:
    owner: indexed(address)

event ScenarioBoundsUpdated:
    max_loss_bps: uint256
    max_recall_bps: uint256
    warning_liquidity_bps: uint256
    critical_liquidity_bps: uint256

owner: public(address)
max_loss_bps: public(uint256)
max_recall_bps: public(uint256)
warning_liquidity_bps: public(uint256)
critical_liquidity_bps: public(uint256)


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.max_loss_bps = 5_000
    self.max_recall_bps = 10_000
    self.warning_liquidity_bps = 1_500
    self.critical_liquidity_bps = 750


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@pure
def _ratio(part: uint256, whole: uint256) -> uint256:
    if whole == 0:
        return 0
    value: uint256 = part * BPS // whole
    if value > BPS:
        return BPS
    return value


@internal
@pure
def _shortfall(available: uint256, required: uint256) -> uint256:
    if available >= required:
        return 0
    return required - available


@internal
@pure
def _severity(liquidity_bps: uint256, queue_shortfall: uint256, warning_bps: uint256, critical_bps: uint256) -> uint256:
    if queue_shortfall > 0 or liquidity_bps < critical_bps:
        return 3
    if liquidity_bps < warning_bps:
        return 2
    if liquidity_bps < warning_bps + 500:
        return 1
    return 0


@external
def transfer_ownership(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner
    log OwnerUpdated(owner=new_owner)


@external
def set_scenario_bounds(max_loss_bps_: uint256, max_recall_bps_: uint256, warning_bps: uint256, critical_bps: uint256):
    self._only_owner()
    assert max_loss_bps_ <= MAX_BPS, "LOSS_BPS"
    assert max_recall_bps_ <= MAX_BPS, "RECALL_BPS"
    assert warning_bps <= MAX_BPS, "WARNING_BPS"
    assert critical_bps <= warning_bps, "THRESHOLD_ORDER"
    self.max_loss_bps = max_loss_bps_
    self.max_recall_bps = max_recall_bps_
    self.warning_liquidity_bps = warning_bps
    self.critical_liquidity_bps = critical_bps
    log ScenarioBoundsUpdated(
        max_loss_bps=max_loss_bps_,
        max_recall_bps=max_recall_bps_,
        warning_liquidity_bps=warning_bps,
        critical_liquidity_bps=critical_bps,
    )


@external
@view
def evaluate(
    total_assets: uint256,
    total_supply: uint256,
    free_liquidity: uint256,
    reserve_liquidity: uint256,
    strategy_assets: uint256,
    pending_assets: uint256,
    strategy_loss_bps: uint256,
    recall_bps: uint256,
) -> StressResult:
    assert strategy_loss_bps <= self.max_loss_bps, "LOSS_BOUND"
    assert recall_bps <= self.max_recall_bps, "RECALL_BOUND"
    assert free_liquidity + reserve_liquidity + strategy_assets == total_assets, "ACCOUNTING"

    loss: uint256 = strategy_assets * strategy_loss_bps // BPS
    recalled: uint256 = (strategy_assets - loss) * recall_bps // BPS
    assets_after: uint256 = total_assets - loss
    liquid_after: uint256 = free_liquidity + reserve_liquidity + recalled
    queue_shortfall: uint256 = self._shortfall(liquid_after, pending_assets)

    free_with_recall: uint256 = free_liquidity + recalled
    reserve_draw: uint256 = 0
    if pending_assets > free_with_recall:
        reserve_draw = pending_assets - free_with_recall
        if reserve_draw > reserve_liquidity:
            reserve_draw = reserve_liquidity
    reserve_after: uint256 = reserve_liquidity - reserve_draw
    liquidity_ratio: uint256 = self._ratio(liquid_after, assets_after)
    reserve_ratio: uint256 = self._ratio(reserve_after, assets_after)
    pps: uint256 = 10**18
    if total_supply > 0:
        pps = assets_after * 10**18 // total_supply

    return StressResult(
        assets_after_shock=assets_after,
        liquid_after_recall=liquid_after,
        queue_shortfall=queue_shortfall,
        reserve_after_queue=reserve_after,
        pps_after_shock=pps,
        liquidity_bps=liquidity_ratio,
        reserve_bps=reserve_ratio,
        severity=self._severity(liquidity_ratio, queue_shortfall, self.warning_liquidity_bps, self.critical_liquidity_bps),
    )


@external
@pure
def loss_capacity(strategy_assets: uint256, configured_loss_bps: uint256) -> uint256:
    assert configured_loss_bps <= BPS, "BPS"
    return strategy_assets * configured_loss_bps // BPS


@external
@pure
def required_recall(free_liquidity: uint256, reserve_liquidity: uint256, pending_assets: uint256, reserve_buffer: uint256) -> uint256:
    protected_reserve: uint256 = min(reserve_liquidity, reserve_buffer)
    usable: uint256 = free_liquidity + reserve_liquidity - protected_reserve
    return self._shortfall(usable, pending_assets)


@external
@pure
def queue_coverage_bps(liquid_assets: uint256, pending_assets: uint256) -> uint256:
    if pending_assets == 0:
        return BPS
    coverage: uint256 = liquid_assets * BPS // pending_assets
    if coverage > BPS:
        return BPS
    return coverage


@external
@pure
def concentration_bps(strategy_assets: uint256, total_assets: uint256) -> uint256:
    return self._ratio(strategy_assets, total_assets)


@external
@pure
def projected_reserve_ratio_bps(total_assets: uint256, reserve_assets: uint256, planned_draw: uint256) -> uint256:
    if planned_draw >= reserve_assets:
        return 0
    return self._ratio(reserve_assets - planned_draw, total_assets)


@external
@pure
def minimum_liquid_buffer(total_assets: uint256, base_buffer_bps: uint256, queue_assets: uint256, queue_multiplier_bps: uint256) -> uint256:
    assert base_buffer_bps <= BPS, "BASE_BPS"
    assert queue_multiplier_bps <= 3 * BPS, "MULTIPLIER"
    base: uint256 = total_assets * base_buffer_bps // BPS
    queue_component: uint256 = queue_assets * queue_multiplier_bps // BPS
    return base + queue_component
