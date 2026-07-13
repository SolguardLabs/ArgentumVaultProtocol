# @version ^0.4.3

"""
Fixed point helpers for ArgentumVaultProtocol.

The main vault keeps critical operations inline. This standalone helper mirrors
the arithmetic reviewers would expect around NAV, shares, reserves, and epoch
payout previews.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000


@external
@pure
def wad() -> uint256:
    return WAD


@external
@pure
def bps() -> uint256:
    return BPS


@external
@pure
def min_uint(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b


@external
@pure
def max_uint(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a
    return b


@external
@pure
def clamp(input_value: uint256, low: uint256, high: uint256) -> uint256:
    assert low <= high, "BAD_RANGE"
    if input_value < low:
        return low
    if input_value > high:
        return high
    return input_value


@external
@pure
def mul_wad_down(a: uint256, b: uint256) -> uint256:
    return a * b // WAD


@external
@pure
def mul_wad_up(a: uint256, b: uint256) -> uint256:
    if a == 0 or b == 0:
        return 0
    return (a * b - 1) // WAD + 1


@external
@pure
def div_wad_down(a: uint256, b: uint256) -> uint256:
    assert b > 0, "DIV_ZERO"
    return a * WAD // b


@external
@pure
def div_wad_up(a: uint256, b: uint256) -> uint256:
    assert b > 0, "DIV_ZERO"
    if a == 0:
        return 0
    return (a * WAD - 1) // b + 1


@external
@pure
def percent_of(amount: uint256, bps_value: uint256) -> uint256:
    assert bps_value <= BPS, "BPS"
    return amount * bps_value // BPS


@external
@pure
def percent_of_up(amount: uint256, bps_value: uint256) -> uint256:
    assert bps_value <= BPS, "BPS"
    if amount == 0 or bps_value == 0:
        return 0
    return (amount * bps_value - 1) // BPS + 1


@external
@pure
def price_per_share(total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return WAD
    return total_assets * WAD // total_supply


@external
@pure
def shares_from_assets(assets: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return assets
    assert total_assets > 0, "NO_ASSETS"
    return assets * total_supply // total_assets


@external
@pure
def assets_from_shares(shares: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return shares
    return shares * total_assets // total_supply


@external
@pure
def assets_from_shares_up(shares: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return shares
    if shares == 0 or total_assets == 0:
        return 0
    return (shares * total_assets - 1) // total_supply + 1


@external
@pure
def shares_from_assets_up(assets: uint256, total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return assets
    assert total_assets > 0, "NO_ASSETS"
    if assets == 0:
        return 0
    return (assets * total_supply - 1) // total_assets + 1


@external
@pure
def reserve_target(total_assets: uint256, target_bps: uint256, reserve_floor_amount: uint256) -> uint256:
    assert target_bps <= BPS, "BPS"
    target: uint256 = total_assets * target_bps // BPS
    if target < reserve_floor_amount:
        return reserve_floor_amount
    return target


@external
@pure
def reserve_gap(total_assets: uint256, reserve_assets: uint256, target_bps: uint256, reserve_floor_amount: uint256) -> uint256:
    assert target_bps <= BPS, "BPS"
    target: uint256 = total_assets * target_bps // BPS
    if target < reserve_floor_amount:
        target = reserve_floor_amount
    if reserve_assets >= target:
        return 0
    return target - reserve_assets


@external
@pure
def reserve_surplus(total_assets: uint256, reserve_assets: uint256, target_bps: uint256, reserve_floor_amount: uint256) -> uint256:
    assert target_bps <= BPS, "BPS"
    target: uint256 = total_assets * target_bps // BPS
    if target < reserve_floor_amount:
        target = reserve_floor_amount
    if reserve_assets <= target:
        return 0
    return reserve_assets - target


@external
@pure
def liquidity_ratio_bps(liquid_assets: uint256, total_assets: uint256) -> uint256:
    if total_assets == 0:
        return 0
    return liquid_assets * BPS // total_assets


@external
@pure
def reserve_ratio_bps(reserve_assets: uint256, total_assets: uint256) -> uint256:
    if total_assets == 0:
        return 0
    return reserve_assets * BPS // total_assets


@external
@pure
def strategy_ratio_bps(strategy_assets: uint256, total_assets: uint256) -> uint256:
    if total_assets == 0:
        return 0
    return strategy_assets * BPS // total_assets


@external
@pure
def loss_bps(loss: uint256, previous_assets: uint256) -> uint256:
    if previous_assets == 0:
        return 0
    return loss * BPS // previous_assets


@external
@pure
def gain_bps(gain: uint256, previous_assets: uint256) -> uint256:
    if previous_assets == 0:
        return 0
    return gain * BPS // previous_assets


@external
@pure
def pps_after_loss(total_assets: uint256, loss: uint256, total_supply: uint256) -> uint256:
    assert total_assets >= loss, "LOSS"
    if total_supply == 0:
        return WAD
    return (total_assets - loss) * WAD // total_supply


@external
@pure
def pps_after_gain(total_assets: uint256, gain: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return WAD
    return (total_assets + gain) * WAD // total_supply


@external
@pure
def positive_quote_delta(quoted_assets: uint256, current_assets: uint256) -> uint256:
    if quoted_assets > current_assets:
        return quoted_assets - current_assets
    return 0


@external
@pure
def negative_quote_delta(quoted_assets: uint256, current_assets: uint256) -> uint256:
    if current_assets > quoted_assets:
        return current_assets - quoted_assets
    return 0


@external
@pure
def pro_rata_payout(claim_assets: uint256, available_liquidity: uint256, total_claims: uint256) -> uint256:
    if total_claims == 0:
        return 0
    if available_liquidity >= total_claims:
        return claim_assets
    return claim_assets * available_liquidity // total_claims


@external
@pure
def shortfall(required: uint256, available: uint256) -> uint256:
    if available >= required:
        return 0
    return required - available


@external
@pure
def coverage_bps(available: uint256, required: uint256) -> uint256:
    if required == 0:
        return BPS
    ratio: uint256 = available * BPS // required
    if ratio > BPS:
        return BPS
    return ratio


@external
@pure
def safe_sub(a: uint256, b: uint256) -> uint256:
    if b > a:
        return 0
    return a - b


@external
@pure
def bounded_add(a: uint256, b: uint256, ceiling: uint256) -> uint256:
    if a >= ceiling:
        return ceiling
    room: uint256 = ceiling - a
    if b >= room:
        return ceiling
    return a + b


@external
@pure
def apply_haircut(amount: uint256, haircut_bps: uint256) -> uint256:
    assert haircut_bps <= BPS, "BPS"
    return amount * (BPS - haircut_bps) // BPS


@external
@pure
def gross_up_after_haircut(net_amount: uint256, haircut_bps: uint256) -> uint256:
    assert haircut_bps < BPS, "BPS"
    denominator: uint256 = BPS - haircut_bps
    if net_amount == 0:
        return 0
    return (net_amount * BPS - 1) // denominator + 1
