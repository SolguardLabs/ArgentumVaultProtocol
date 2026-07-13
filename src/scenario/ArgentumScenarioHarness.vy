# @version ^0.4.3

"""
Pure scenario harness for Argentum review scenarios.

The functions below are deterministic formulas for withdrawal and reserve
economics. They are not imported by tests; they exist as source-level review
material for reasoning about settlement behavior.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000


@internal
@pure
def _pps(total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return WAD
    return total_assets * WAD // total_supply


@internal
@pure
def _claim(shares: uint256, pps: uint256) -> uint256:
    return shares * pps // WAD


@internal
@pure
def _ratio(part: uint256, whole: uint256) -> uint256:
    if whole == 0:
        return 0
    return part * BPS // whole


@external
@pure
def initial_reserve(total_deposits: uint256, reserve_bps: uint256) -> uint256:
    assert reserve_bps <= BPS, "BPS"
    return total_deposits * reserve_bps // BPS


@external
@pure
def initial_free(total_deposits: uint256, reserve_bps: uint256) -> uint256:
    assert reserve_bps <= BPS, "BPS"
    reserve: uint256 = total_deposits * reserve_bps // BPS
    return total_deposits - reserve


@external
@pure
def free_after_allocation(total_deposits: uint256, reserve_bps: uint256, allocation: uint256) -> uint256:
    reserve: uint256 = total_deposits * reserve_bps // BPS
    free: uint256 = total_deposits - reserve
    assert free >= allocation, "ALLOCATION"
    return free - allocation


@external
@pure
def total_after_loss(total_deposits: uint256, loss_amount: uint256) -> uint256:
    assert total_deposits >= loss_amount, "LOSS"
    return total_deposits - loss_amount


@external
@pure
def pps_before_loss(total_deposits: uint256, total_supply: uint256) -> uint256:
    return self._pps(total_deposits, total_supply)


@external
@pure
def pps_after_loss(total_deposits: uint256, loss_amount: uint256, total_supply: uint256) -> uint256:
    assert total_deposits >= loss_amount, "LOSS"
    return self._pps(total_deposits - loss_amount, total_supply)


@external
@pure
def snapshot_quote(request_shares: uint256, snapshot_pps: uint256) -> uint256:
    return self._claim(request_shares, snapshot_pps)


@external
@pure
def quote_after_loss(request_shares: uint256, total_deposits: uint256, loss_amount: uint256, total_supply: uint256) -> uint256:
    assert total_deposits >= loss_amount, "LOSS"
    pps: uint256 = self._pps(total_deposits - loss_amount, total_supply)
    return self._claim(request_shares, pps)


@external
@pure
def quote_delta_after_loss(request_shares: uint256, snapshot_pps: uint256, total_deposits: uint256, loss_amount: uint256, total_supply: uint256) -> uint256:
    snapshot: uint256 = self._claim(request_shares, snapshot_pps)
    assert total_deposits >= loss_amount, "LOSS"
    fair_pps: uint256 = self._pps(total_deposits - loss_amount, total_supply)
    fair: uint256 = self._claim(request_shares, fair_pps)
    if snapshot > fair:
        return snapshot - fair
    return 0


@external
@pure
def reserve_used_by_snapshot_payment(free_liquidity: uint256, reserve_liquidity: uint256, snapshot_payment: uint256) -> uint256:
    if snapshot_payment <= free_liquidity:
        return 0
    needed: uint256 = snapshot_payment - free_liquidity
    if needed > reserve_liquidity:
        return reserve_liquidity
    return needed


@external
@pure
def reserve_after_snapshot_payment(free_liquidity: uint256, reserve_liquidity: uint256, snapshot_payment: uint256) -> uint256:
    used: uint256 = 0
    if snapshot_payment > free_liquidity:
        used = snapshot_payment - free_liquidity
    if used >= reserve_liquidity:
        return 0
    return reserve_liquidity - used


@external
@pure
def free_after_snapshot_payment(free_liquidity: uint256, snapshot_payment: uint256) -> uint256:
    if snapshot_payment >= free_liquidity:
        return 0
    return free_liquidity - snapshot_payment


@external
@pure
def account_assets_after_snapshot_exit(total_deposits: uint256, loss_amount: uint256, snapshot_payment: uint256, remaining_supply: uint256, account_shares: uint256) -> uint256:
    assert total_deposits >= loss_amount + snapshot_payment, "ASSETS"
    if remaining_supply == 0:
        return 0
    remaining_assets: uint256 = total_deposits - loss_amount - snapshot_payment
    return account_shares * remaining_assets // remaining_supply


@external
@pure
def account_assets_after_fair_exit(total_deposits: uint256, loss_amount: uint256, fair_payment: uint256, remaining_supply: uint256, account_shares: uint256) -> uint256:
    assert total_deposits >= loss_amount + fair_payment, "ASSETS"
    if remaining_supply == 0:
        return 0
    remaining_assets: uint256 = total_deposits - loss_amount - fair_payment
    return account_shares * remaining_assets // remaining_supply


@external
@pure
def account_value_delta(
    total_deposits: uint256,
    loss_amount: uint256,
    snapshot_payment: uint256,
    fair_payment: uint256,
    remaining_supply: uint256,
    account_shares: uint256,
) -> uint256:
    assert total_deposits >= loss_amount + snapshot_payment, "SNAPSHOT_ASSETS"
    assert total_deposits >= loss_amount + fair_payment, "FAIR_ASSETS"
    snapshot_assets: uint256 = 0
    fair_assets: uint256 = 0
    if remaining_supply != 0:
        snapshot_assets = account_shares * (total_deposits - loss_amount - snapshot_payment) // remaining_supply
        fair_assets = account_shares * (total_deposits - loss_amount - fair_payment) // remaining_supply
    if fair_assets > snapshot_assets:
        return fair_assets - snapshot_assets
    return 0


@external
@pure
def quote_delta_bps(snapshot_payment: uint256, fair_payment: uint256) -> uint256:
    if fair_payment == 0:
        if snapshot_payment == 0:
            return 0
        return max_value(uint256)
    if snapshot_payment <= fair_payment:
        return 0
    return (snapshot_payment - fair_payment) * BPS // fair_payment


@external
@pure
def reserve_damage_bps(reserve_before: uint256, reserve_after: uint256) -> uint256:
    if reserve_before == 0:
        return 0
    if reserve_after >= reserve_before:
        return 0
    return (reserve_before - reserve_after) * BPS // reserve_before
