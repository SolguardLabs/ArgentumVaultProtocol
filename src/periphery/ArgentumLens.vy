# @version ^0.4.3

"""
Read-only lens for ArgentumVaultProtocol.

Dashboards and auditors can use this contract to pull normalized vault, epoch,
and request information. The lens exposes queue pressure, reserve coverage, and
settlement previews without mutating core accounting.
"""

interface VaultLike:
    def total_assets() -> uint256: view
    def liquid_assets() -> uint256: view
    def price_per_share() -> uint256: view
    def totalSupply() -> uint256: view
    def balanceOf(owner: address) -> uint256: view
    def free_liquidity() -> uint256: view
    def reserve_liquidity() -> uint256: view
    def strategy_assets() -> uint256: view
    def withdrawal_liabilities() -> uint256: view
    def escrowed_shares() -> uint256: view
    def current_epoch() -> uint256: view
    def next_request_id() -> uint256: view
    def request_value_at_current_pps(request_id: uint256) -> uint256: view
    def request_quote_delta(request_id: uint256) -> uint256: view
    def available_to_process_epoch(epoch: uint256) -> uint256: view
    def convert_to_assets(shares: uint256) -> uint256: view
    def convert_to_shares(assets: uint256) -> uint256: view
    def requests(request_id: uint256) -> (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256): view
    def epochs(epoch: uint256) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool): view

interface ERC20Like:
    def balanceOf(owner: address) -> uint256: view
    def totalSupply() -> uint256: view
    def decimals() -> uint8: view

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000


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
@view
def vault_accounting(vault: address) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256):
    total_assets: uint256 = staticcall VaultLike(vault).total_assets()
    liquid_assets: uint256 = staticcall VaultLike(vault).liquid_assets()
    free_liquidity: uint256 = staticcall VaultLike(vault).free_liquidity()
    reserve_liquidity: uint256 = staticcall VaultLike(vault).reserve_liquidity()
    strategy_assets: uint256 = staticcall VaultLike(vault).strategy_assets()
    liabilities: uint256 = staticcall VaultLike(vault).withdrawal_liabilities()
    pps: uint256 = staticcall VaultLike(vault).price_per_share()
    return total_assets, liquid_assets, free_liquidity, reserve_liquidity, strategy_assets, liabilities, pps


@external
@view
def vault_supply(vault: address) -> (uint256, uint256, uint256):
    supply: uint256 = staticcall VaultLike(vault).totalSupply()
    escrowed: uint256 = staticcall VaultLike(vault).escrowed_shares()
    active: uint256 = 0
    if supply > escrowed:
        active = supply - escrowed
    return supply, escrowed, active


@external
@view
def user_position(vault: address, user: address) -> (uint256, uint256, uint256):
    shares: uint256 = staticcall VaultLike(vault).balanceOf(user)
    assets: uint256 = staticcall VaultLike(vault).convert_to_assets(shares)
    supply: uint256 = staticcall VaultLike(vault).totalSupply()
    ownership_bps: uint256 = self._ratio_bps(shares, supply)
    return shares, assets, ownership_bps


@external
@view
def liquidity_ratios(vault: address) -> (uint256, uint256, uint256):
    total_assets: uint256 = staticcall VaultLike(vault).total_assets()
    liquid_assets: uint256 = staticcall VaultLike(vault).liquid_assets()
    reserve_liquidity: uint256 = staticcall VaultLike(vault).reserve_liquidity()
    strategy_assets: uint256 = staticcall VaultLike(vault).strategy_assets()
    liquid_bps: uint256 = self._ratio_bps(liquid_assets, total_assets)
    reserve_bps: uint256 = self._ratio_bps(reserve_liquidity, total_assets)
    strategy_bps: uint256 = self._ratio_bps(strategy_assets, total_assets)
    return liquid_bps, reserve_bps, strategy_bps


@external
@view
def epoch_summary(vault: address, epoch: uint256) -> (uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256):
    first_id: uint256 = 0
    last_id: uint256 = 0
    processed_until: uint256 = 0
    pending_shares: uint256 = 0
    pending_assets: uint256 = 0
    paid_assets: uint256 = 0
    processed_count: uint256 = 0
    closed: bool = False
    first_id, last_id, processed_until, pending_shares, pending_assets, paid_assets, processed_count, closed = staticcall VaultLike(vault).epochs(epoch)
    available: uint256 = staticcall VaultLike(vault).available_to_process_epoch(epoch)
    coverage: uint256 = self._coverage_bps(available, pending_assets)
    return first_id, last_id, processed_until, pending_assets, paid_assets, processed_count, closed, coverage


@external
@view
def request_summary(vault: address, request_id: uint256) -> (address, address, uint256, uint256, uint256, uint256, uint256, uint256):
    owner: address = empty(address)
    receiver: address = empty(address)
    epoch: uint256 = 0
    shares: uint256 = 0
    quoted_assets: uint256 = 0
    snapshot_pps: uint256 = 0
    requested_at: uint256 = 0
    processed_at: uint256 = 0
    paid_assets: uint256 = 0
    status: uint256 = 0
    owner, receiver, epoch, shares, quoted_assets, snapshot_pps, requested_at, processed_at, paid_assets, status = staticcall VaultLike(vault).requests(request_id)
    current_value: uint256 = staticcall VaultLike(vault).request_value_at_current_pps(request_id)
    quote_delta: uint256 = staticcall VaultLike(vault).request_quote_delta(request_id)
    return owner, receiver, epoch, shares, quoted_assets, current_value, quote_delta, status


@external
@view
def request_timing(vault: address, request_id: uint256) -> (uint256, uint256, uint256, bool):
    owner: address = empty(address)
    receiver: address = empty(address)
    epoch: uint256 = 0
    shares: uint256 = 0
    quoted_assets: uint256 = 0
    snapshot_pps: uint256 = 0
    requested_at: uint256 = 0
    processed_at: uint256 = 0
    paid_assets: uint256 = 0
    status: uint256 = 0
    owner, receiver, epoch, shares, quoted_assets, snapshot_pps, requested_at, processed_at, paid_assets, status = staticcall VaultLike(vault).requests(request_id)
    current_epoch: uint256 = staticcall VaultLike(vault).current_epoch()
    return requested_at, processed_at, epoch, epoch <= current_epoch


@external
@view
def unsafe_premium_bps(vault: address, request_id: uint256) -> uint256:
    premium: uint256 = staticcall VaultLike(vault).request_quote_delta(request_id)
    current_value: uint256 = staticcall VaultLike(vault).request_value_at_current_pps(request_id)
    if current_value == 0:
        if premium == 0:
            return 0
        return max_value(uint256)
    return premium * BPS // current_value


@external
@view
def next_request_id(vault: address) -> uint256:
    return staticcall VaultLike(vault).next_request_id()


@external
@view
def current_epoch(vault: address) -> uint256:
    return staticcall VaultLike(vault).current_epoch()


@external
@view
def token_balance(token: address, holder: address) -> uint256:
    return staticcall ERC20Like(token).balanceOf(holder)


@external
@view
def token_supply(token: address) -> uint256:
    return staticcall ERC20Like(token).totalSupply()


@external
@view
def token_decimals(token: address) -> uint8:
    return staticcall ERC20Like(token).decimals()


@external
@view
def insolvency_gap(vault: address, token: address) -> uint256:
    accounted_liquid: uint256 = staticcall VaultLike(vault).liquid_assets()
    actual_balance: uint256 = staticcall ERC20Like(token).balanceOf(vault)
    if accounted_liquid <= actual_balance:
        return 0
    return accounted_liquid - actual_balance


@external
@view
def dashboard(vault: address) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256):
    total_assets: uint256 = staticcall VaultLike(vault).total_assets()
    liquid_assets: uint256 = staticcall VaultLike(vault).liquid_assets()
    reserve_liquidity: uint256 = staticcall VaultLike(vault).reserve_liquidity()
    strategy_assets: uint256 = staticcall VaultLike(vault).strategy_assets()
    liabilities: uint256 = staticcall VaultLike(vault).withdrawal_liabilities()
    supply: uint256 = staticcall VaultLike(vault).totalSupply()
    pps: uint256 = staticcall VaultLike(vault).price_per_share()
    current_epoch: uint256 = staticcall VaultLike(vault).current_epoch()
    reserve_bps: uint256 = self._ratio_bps(reserve_liquidity, total_assets)
    return total_assets, liquid_assets, reserve_liquidity, strategy_assets, liabilities, supply, pps, current_epoch, reserve_bps
