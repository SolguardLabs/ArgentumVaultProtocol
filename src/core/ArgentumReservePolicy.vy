# @version ^0.4.3

"""
Reserve policy contract for ArgentumVaultProtocol.

The policy is intentionally separated from the core vault. It computes target
buffers, liquidity pressure, and suggested throttles for operational review.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MAX_POLICY_BPS: constant(uint256) = 10_000

event OwnerUpdated:
    owner: indexed(address)

event VaultUpdated:
    vault: indexed(address)

event PolicyUpdated:
    key: indexed(bytes32)
    new_value: uint256

event ReserveUseRecorded:
    epoch: indexed(uint256)
    amount: uint256
    cumulative_epoch_use: uint256

event EmergencyModeUpdated:
    enabled: bool

owner: public(address)
vault: public(address)

target_bps: public(uint256)
floor_assets: public(uint256)
soft_min_bps: public(uint256)
hard_min_bps: public(uint256)
max_epoch_draw_bps: public(uint256)
max_single_draw_bps: public(uint256)
recall_buffer_bps: public(uint256)
emergency_mode: public(bool)

epoch_reserve_used: public(HashMap[uint256, uint256])


@deploy
def __init__(_owner: address, _vault: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.vault = _vault
    self.target_bps = 2_000
    self.floor_assets = 0
    self.soft_min_bps = 1_000
    self.hard_min_bps = 500
    self.max_epoch_draw_bps = 3_000
    self.max_single_draw_bps = 1_500
    self.recall_buffer_bps = 500


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@pure
def _target(total_assets: uint256, target_bps_value: uint256, floor_assets_value: uint256) -> uint256:
    target: uint256 = total_assets * target_bps_value // BPS
    if target < floor_assets_value:
        return floor_assets_value
    return target


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
    ratio: uint256 = available * BPS // required
    if ratio > BPS:
        return BPS
    return ratio


@external
def set_owner(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner
    log OwnerUpdated(owner=new_owner)


@external
def set_vault(new_vault: address):
    self._only_owner()
    assert new_vault != empty(address), "ZERO_VAULT"
    self.vault = new_vault
    log VaultUpdated(vault=new_vault)


@external
def set_target_bps(new_target_bps: uint256):
    self._only_owner()
    assert new_target_bps <= MAX_POLICY_BPS, "BPS"
    self.target_bps = new_target_bps
    log PolicyUpdated(key=keccak256("target_bps"), new_value=new_target_bps)


@external
def set_floor_assets(new_floor_assets: uint256):
    self._only_owner()
    self.floor_assets = new_floor_assets
    log PolicyUpdated(key=keccak256("floor_assets"), new_value=new_floor_assets)


@external
def set_soft_min_bps(new_soft_min_bps: uint256):
    self._only_owner()
    assert new_soft_min_bps <= MAX_POLICY_BPS, "BPS"
    self.soft_min_bps = new_soft_min_bps
    log PolicyUpdated(key=keccak256("soft_min_bps"), new_value=new_soft_min_bps)


@external
def set_hard_min_bps(new_hard_min_bps: uint256):
    self._only_owner()
    assert new_hard_min_bps <= MAX_POLICY_BPS, "BPS"
    self.hard_min_bps = new_hard_min_bps
    log PolicyUpdated(key=keccak256("hard_min_bps"), new_value=new_hard_min_bps)


@external
def set_draw_limits(new_epoch_draw_bps: uint256, new_single_draw_bps: uint256):
    self._only_owner()
    assert new_epoch_draw_bps <= MAX_POLICY_BPS, "EPOCH_BPS"
    assert new_single_draw_bps <= MAX_POLICY_BPS, "SINGLE_BPS"
    self.max_epoch_draw_bps = new_epoch_draw_bps
    self.max_single_draw_bps = new_single_draw_bps
    log PolicyUpdated(key=keccak256("max_epoch_draw_bps"), new_value=new_epoch_draw_bps)
    log PolicyUpdated(key=keccak256("max_single_draw_bps"), new_value=new_single_draw_bps)


@external
def set_recall_buffer_bps(new_recall_buffer_bps: uint256):
    self._only_owner()
    assert new_recall_buffer_bps <= MAX_POLICY_BPS, "BPS"
    self.recall_buffer_bps = new_recall_buffer_bps
    log PolicyUpdated(key=keccak256("recall_buffer_bps"), new_value=new_recall_buffer_bps)


@external
def set_emergency_mode(enabled: bool):
    self._only_owner()
    self.emergency_mode = enabled
    log EmergencyModeUpdated(enabled=enabled)


@external
def record_reserve_use(epoch: uint256, amount: uint256):
    self._only_owner()
    self.epoch_reserve_used[epoch] += amount
    log ReserveUseRecorded(epoch=epoch, amount=amount, cumulative_epoch_use=self.epoch_reserve_used[epoch])


@external
@view
def target_reserve(total_assets: uint256) -> uint256:
    return self._target(total_assets, self.target_bps, self.floor_assets)


@external
@view
def reserve_gap(total_assets: uint256, reserve_assets: uint256) -> uint256:
    target: uint256 = self._target(total_assets, self.target_bps, self.floor_assets)
    if reserve_assets >= target:
        return 0
    return target - reserve_assets


@external
@view
def reserve_surplus(total_assets: uint256, reserve_assets: uint256) -> uint256:
    target: uint256 = self._target(total_assets, self.target_bps, self.floor_assets)
    if reserve_assets <= target:
        return 0
    return reserve_assets - target


@external
@view
def reserve_ratio_bps(total_assets: uint256, reserve_assets: uint256) -> uint256:
    return self._ratio_bps(reserve_assets, total_assets)


@external
@view
def classify_reserve(total_assets: uint256, reserve_assets: uint256) -> uint256:
    ratio: uint256 = self._ratio_bps(reserve_assets, total_assets)
    if ratio < self.hard_min_bps:
        return 3
    if ratio < self.soft_min_bps:
        return 2
    if reserve_assets < self._target(total_assets, self.target_bps, self.floor_assets):
        return 1
    return 0


@external
@view
def can_draw_reserve(total_assets: uint256, reserve_assets: uint256, draw_amount: uint256) -> bool:
    if self.emergency_mode:
        return False
    if reserve_assets < draw_amount:
        return False
    single_limit: uint256 = total_assets * self.max_single_draw_bps // BPS
    if draw_amount > single_limit:
        return False
    after_reserve: uint256 = reserve_assets - draw_amount
    after_ratio: uint256 = self._ratio_bps(after_reserve, total_assets)
    return after_ratio >= self.hard_min_bps


@external
@view
def can_draw_for_epoch(epoch: uint256, total_assets: uint256, reserve_assets: uint256, draw_amount: uint256) -> bool:
    if self.emergency_mode:
        return False
    if reserve_assets < draw_amount:
        return False
    single_limit: uint256 = total_assets * self.max_single_draw_bps // BPS
    if draw_amount > single_limit:
        return False
    after_reserve: uint256 = reserve_assets - draw_amount
    after_ratio: uint256 = self._ratio_bps(after_reserve, total_assets)
    if after_ratio < self.hard_min_bps:
        return False
    epoch_limit: uint256 = total_assets * self.max_epoch_draw_bps // BPS
    return self.epoch_reserve_used[epoch] + draw_amount <= epoch_limit


@external
@view
def max_single_draw(total_assets: uint256, reserve_assets: uint256) -> uint256:
    by_policy: uint256 = total_assets * self.max_single_draw_bps // BPS
    if by_policy > reserve_assets:
        return reserve_assets
    return by_policy


@external
@view
def max_epoch_draw_remaining(epoch: uint256, total_assets: uint256, reserve_assets: uint256) -> uint256:
    limit: uint256 = total_assets * self.max_epoch_draw_bps // BPS
    used: uint256 = self.epoch_reserve_used[epoch]
    if used >= limit:
        return 0
    remaining: uint256 = limit - used
    if remaining > reserve_assets:
        return reserve_assets
    return remaining


@external
@view
def recall_needed_for_epoch(total_assets: uint256, free_liquidity: uint256, reserve_assets: uint256, pending_assets: uint256) -> uint256:
    desired_buffer: uint256 = total_assets * self.recall_buffer_bps // BPS
    available_without_buffer: uint256 = 0
    liquid: uint256 = free_liquidity + reserve_assets
    if liquid > desired_buffer:
        available_without_buffer = liquid - desired_buffer
    if available_without_buffer >= pending_assets:
        return 0
    return pending_assets - available_without_buffer


@external
@view
def preview_deposit_allocation(total_assets_before: uint256, reserve_assets_before: uint256, deposit_assets: uint256) -> (uint256, uint256):
    total_after: uint256 = total_assets_before + deposit_assets
    target_after: uint256 = self._target(total_after, self.target_bps, self.floor_assets)
    reserve_add: uint256 = 0
    if reserve_assets_before < target_after:
        gap: uint256 = target_after - reserve_assets_before
        if gap < deposit_assets:
            reserve_add = gap
        else:
            reserve_add = deposit_assets
    return deposit_assets - reserve_add, reserve_add


@external
@view
def preview_loss_state(total_assets: uint256, reserve_assets: uint256, loss_amount: uint256) -> (uint256, uint256, uint256):
    assert total_assets >= loss_amount, "LOSS"
    next_total: uint256 = total_assets - loss_amount
    target: uint256 = self._target(next_total, self.target_bps, self.floor_assets)
    status: uint256 = 0
    ratio: uint256 = self._ratio_bps(reserve_assets, next_total)
    if ratio < self.hard_min_bps:
        status = 3
    elif ratio < self.soft_min_bps:
        status = 2
    elif reserve_assets < target:
        status = 1
    return next_total, target, status


@external
@view
def withdrawal_coverage_bps(free_liquidity: uint256, reserve_assets: uint256, pending_assets: uint256) -> uint256:
    return self._coverage_bps(free_liquidity + reserve_assets, pending_assets)


@external
@view
def reserve_health_score(total_assets: uint256, reserve_assets: uint256, pending_assets: uint256) -> uint256:
    if total_assets == 0:
        return 0
    ratio: uint256 = self._ratio_bps(reserve_assets, total_assets)
    coverage: uint256 = self._coverage_bps(reserve_assets, pending_assets)
    score: uint256 = ratio
    if coverage < score:
        score = coverage
    if score > BPS:
        return BPS
    return score
