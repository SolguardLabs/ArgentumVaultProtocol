# @version ^0.4.3

"""
Epoch queue arithmetic used for audits and off-chain previews.

These helpers describe expected reserve, queue, and payout arithmetic for
review tooling and operational dashboards.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MAX_BATCH: constant(uint256) = 128


@external
@pure
def executable_epoch(current_epoch: uint256, delay: uint256) -> uint256:
    return current_epoch + delay


@external
@pure
def is_epoch_mature(epoch: uint256, current_epoch: uint256) -> bool:
    return epoch <= current_epoch


@external
@pure
def normalize_cursor(first_request_id: uint256, processed_until: uint256) -> uint256:
    if first_request_id == 0:
        return 0
    if processed_until + 1 < first_request_id:
        return first_request_id
    return processed_until + 1


@external
@pure
def remaining_items(first_request_id: uint256, last_request_id: uint256, processed_until: uint256) -> uint256:
    if first_request_id == 0:
        return 0
    cursor: uint256 = processed_until + 1
    if cursor < first_request_id:
        cursor = first_request_id
    if cursor == 0 or cursor > last_request_id:
        return 0
    return last_request_id - cursor + 1


@external
@pure
def batch_size(first_request_id: uint256, last_request_id: uint256, processed_until: uint256, requested: uint256) -> uint256:
    assert requested <= MAX_BATCH, "BATCH"
    remaining: uint256 = 0
    if first_request_id != 0:
        cursor: uint256 = processed_until + 1
        if cursor < first_request_id:
            cursor = first_request_id
        if cursor <= last_request_id:
            remaining = last_request_id - cursor + 1
    if requested < remaining:
        return requested
    return remaining


@external
@pure
def next_processed_until(first_request_id: uint256, last_request_id: uint256, processed_until: uint256, processed: uint256) -> uint256:
    if processed == 0:
        return processed_until
    cursor: uint256 = processed_until + 1
    if cursor < first_request_id:
        cursor = first_request_id
    if cursor == 0:
        return processed_until
    candidate: uint256 = cursor + processed - 1
    if candidate > last_request_id:
        return last_request_id
    return candidate


@external
@pure
def is_epoch_closed(first_request_id: uint256, last_request_id: uint256, processed_until: uint256) -> bool:
    if first_request_id == 0:
        return True
    return processed_until >= last_request_id


@external
@pure
def quote_from_snapshot(shares: uint256, snapshot_pps: uint256) -> uint256:
    return shares * snapshot_pps // WAD


@external
@pure
def quote_from_current_nav(shares: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return shares
    return shares * total_assets // total_supply


@external
@pure
def premium_against_current_nav(shares: uint256, snapshot_pps: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    snapshot_quote: uint256 = shares * snapshot_pps // WAD
    current_quote: uint256 = shares
    if total_supply != 0:
        current_quote = shares * total_assets // total_supply
    if snapshot_quote > current_quote:
        return snapshot_quote - current_quote
    return 0


@external
@pure
def discount_against_current_nav(shares: uint256, snapshot_pps: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    snapshot_quote: uint256 = shares * snapshot_pps // WAD
    current_quote: uint256 = shares
    if total_supply != 0:
        current_quote = shares * total_assets // total_supply
    if current_quote > snapshot_quote:
        return current_quote - snapshot_quote
    return 0


@external
@pure
def available_for_epoch(free_liquidity: uint256, reserve_liquidity: uint256) -> uint256:
    return free_liquidity + reserve_liquidity


@external
@pure
def can_pay_full_epoch(free_liquidity: uint256, reserve_liquidity: uint256, pending_assets: uint256) -> bool:
    return free_liquidity + reserve_liquidity >= pending_assets


@external
@pure
def epoch_shortfall(free_liquidity: uint256, reserve_liquidity: uint256, pending_assets: uint256) -> uint256:
    liquid: uint256 = free_liquidity + reserve_liquidity
    if liquid >= pending_assets:
        return 0
    return pending_assets - liquid


@external
@pure
def reserve_needed_for_payment(free_liquidity: uint256, payment: uint256) -> uint256:
    if payment <= free_liquidity:
        return 0
    return payment - free_liquidity


@external
@pure
def free_after_payment(free_liquidity: uint256, payment: uint256) -> uint256:
    if payment >= free_liquidity:
        return 0
    return free_liquidity - payment


@external
@pure
def reserve_after_payment(free_liquidity: uint256, reserve_liquidity: uint256, payment: uint256) -> uint256:
    if payment <= free_liquidity:
        return reserve_liquidity
    needed: uint256 = payment - free_liquidity
    if needed >= reserve_liquidity:
        return 0
    return reserve_liquidity - needed


@external
@pure
def liquidity_after_payment(free_liquidity: uint256, reserve_liquidity: uint256, payment: uint256) -> uint256:
    free_after: uint256 = 0
    reserve_after: uint256 = reserve_liquidity
    if payment < free_liquidity:
        free_after = free_liquidity - payment
    elif payment > free_liquidity:
        needed: uint256 = payment - free_liquidity
        if needed >= reserve_liquidity:
            reserve_after = 0
        else:
            reserve_after = reserve_liquidity - needed
    return free_after + reserve_after


@external
@pure
def reserve_usage_bps(free_liquidity: uint256, reserve_liquidity: uint256, payment: uint256) -> uint256:
    if reserve_liquidity == 0:
        return 0
    used: uint256 = 0
    if payment > free_liquidity:
        used = payment - free_liquidity
    if used > reserve_liquidity:
        used = reserve_liquidity
    return used * BPS // reserve_liquidity


@external
@pure
def queue_coverage_bps(free_liquidity: uint256, reserve_liquidity: uint256, pending_assets: uint256) -> uint256:
    if pending_assets == 0:
        return BPS
    liquid: uint256 = free_liquidity + reserve_liquidity
    coverage: uint256 = liquid * BPS // pending_assets
    if coverage > BPS:
        return BPS
    return coverage


@external
@pure
def safe_partial_payout(quoted_assets: uint256, available_liquidity: uint256, pending_assets: uint256) -> uint256:
    if pending_assets == 0:
        return 0
    if available_liquidity >= pending_assets:
        return quoted_assets
    return quoted_assets * available_liquidity // pending_assets


@external
@pure
def safe_revalued_payout(shares: uint256, total_assets: uint256, total_supply: uint256, free_liquidity: uint256, reserve_liquidity: uint256) -> uint256:
    claim: uint256 = shares
    if total_supply != 0:
        claim = shares * total_assets // total_supply
    liquid: uint256 = free_liquidity + reserve_liquidity
    if claim > liquid:
        return liquid
    return claim


@external
@pure
def snapshot_payout(shares: uint256, snapshot_pps: uint256, free_liquidity: uint256, reserve_liquidity: uint256) -> uint256:
    claim: uint256 = shares * snapshot_pps // WAD
    liquid: uint256 = free_liquidity + reserve_liquidity
    if claim > liquid:
        return liquid
    return claim


@external
@pure
def socialized_delta_from_snapshot_payout(shares: uint256, snapshot_pps: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    snapshot: uint256 = shares * snapshot_pps // WAD
    current: uint256 = shares
    if total_supply != 0:
        current = shares * total_assets // total_supply
    if snapshot > current:
        return snapshot - current
    return 0


@external
@pure
def remaining_supply_after_burn(total_supply: uint256, burned_shares: uint256) -> uint256:
    assert total_supply >= burned_shares, "SUPPLY"
    return total_supply - burned_shares


@external
@pure
def nav_after_payout(total_assets: uint256, paid_assets: uint256) -> uint256:
    assert total_assets >= paid_assets, "ASSETS"
    return total_assets - paid_assets


@external
@pure
def pps_after_snapshot_execution(total_assets: uint256, total_supply: uint256, burned_shares: uint256, paid_assets: uint256) -> uint256:
    assert total_assets >= paid_assets, "ASSETS"
    assert total_supply >= burned_shares, "SUPPLY"
    next_assets: uint256 = total_assets - paid_assets
    next_supply: uint256 = total_supply - burned_shares
    if next_supply == 0:
        return WAD
    return next_assets * WAD // next_supply


@external
@pure
def pps_after_safe_execution(total_assets: uint256, total_supply: uint256, burned_shares: uint256) -> uint256:
    safe_paid: uint256 = burned_shares
    if total_supply != 0:
        safe_paid = burned_shares * total_assets // total_supply
    assert total_assets >= safe_paid, "ASSETS"
    assert total_supply >= burned_shares, "SUPPLY"
    next_assets: uint256 = total_assets - safe_paid
    next_supply: uint256 = total_supply - burned_shares
    if next_supply == 0:
        return WAD
    return next_assets * WAD // next_supply


@external
@pure
def pps_delta_from_snapshot_execution(total_assets: uint256, total_supply: uint256, burned_shares: uint256, snapshot_pps: uint256) -> uint256:
    assert total_supply >= burned_shares, "SUPPLY"
    snapshot_paid: uint256 = burned_shares * snapshot_pps // WAD
    safe_paid: uint256 = burned_shares
    if total_supply != 0:
        safe_paid = burned_shares * total_assets // total_supply
    assert total_assets >= snapshot_paid, "SNAPSHOT_ASSETS"
    assert total_assets >= safe_paid, "SAFE_ASSETS"
    next_supply: uint256 = total_supply - burned_shares
    if next_supply == 0:
        return 0
    snapshot_execution_pps: uint256 = (total_assets - snapshot_paid) * WAD // next_supply
    safe_pps: uint256 = (total_assets - safe_paid) * WAD // next_supply
    if safe_pps > snapshot_execution_pps:
        return safe_pps - snapshot_execution_pps
    return 0
