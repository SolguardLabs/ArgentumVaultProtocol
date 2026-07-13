# @version ^0.4.3

"""
ArgentumVaultProtocol core vault.

The vault snapshots withdrawal requests at creation time, queues them until an
executable epoch, and settles batches from free liquidity plus reserve liquidity.
Strategy reports update NAV while pending queues remain observable through the
lens and keeper surfaces.
"""

interface ERC20Like:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MAX_BPS: constant(uint256) = 10_000
MAX_DELAY: constant(uint256) = 32
MAX_BATCH: constant(uint256) = 128

struct WithdrawalRequest:
    owner: address
    receiver: address
    epoch: uint256
    shares: uint256
    quoted_assets: uint256
    snapshot_pps: uint256
    requested_at: uint256
    processed_at: uint256
    paid_assets: uint256
    status: uint256

struct EpochState:
    first_request_id: uint256
    last_request_id: uint256
    processed_until: uint256
    pending_shares: uint256
    pending_assets: uint256
    paid_assets: uint256
    processed_count: uint256
    closed: bool

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event Deposit:
    caller: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256
    reserve_added: uint256

event WithdrawalRequested:
    request_id: indexed(uint256)
    owner: indexed(address)
    receiver: indexed(address)
    epoch: uint256
    shares: uint256
    quoted_assets: uint256
    snapshot_pps: uint256

event WithdrawalProcessed:
    request_id: indexed(uint256)
    owner: indexed(address)
    receiver: indexed(address)
    epoch: uint256
    shares: uint256
    paid_assets: uint256
    used_reserve: uint256

event EpochAdvanced:
    previous_epoch: indexed(uint256)
    new_epoch: indexed(uint256)

event LiquidityAllocated:
    strategy: indexed(address)
    amount: uint256

event LiquidityReturned:
    strategy: indexed(address)
    amount: uint256

event StrategyLossReported:
    strategy: indexed(address)
    amount: uint256
    new_strategy_assets: uint256
    new_price_per_share: uint256

event ReserveRebalanced:
    free_liquidity: uint256
    reserve_liquidity: uint256
    target_reserve: uint256

event ParameterUpdated:
    key: indexed(bytes32)
    value: uint256

event KeeperUpdated:
    keeper: indexed(address)

event StrategistUpdated:
    strategist: indexed(address)

asset: public(address)
name: public(String[64])
symbol: public(String[16])
decimals: public(uint8)

owner: public(address)
keeper: public(address)
strategist: public(address)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

free_liquidity: public(uint256)
reserve_liquidity: public(uint256)
strategy_assets: public(uint256)
withdrawal_liabilities: public(uint256)
escrowed_shares: public(uint256)

reserve_target_bps: public(uint256)
reserve_floor: public(uint256)
withdrawal_delay_epochs: public(uint256)
current_epoch: public(uint256)
next_request_id: public(uint256)

requests: public(HashMap[uint256, WithdrawalRequest])
epochs: public(HashMap[uint256, EpochState])


@deploy
def __init__(_asset: address, _owner: address, _keeper: address, _strategist: address):
    assert _asset != empty(address), "ZERO_ASSET"
    assert _owner != empty(address), "ZERO_OWNER"
    assert _keeper != empty(address), "ZERO_KEEPER"
    assert _strategist != empty(address), "ZERO_STRATEGIST"

    self.asset = _asset
    self.owner = _owner
    self.keeper = _keeper
    self.strategist = _strategist
    self.name = "Argentum Vault Share"
    self.symbol = "agUSD"
    self.decimals = 6
    self.reserve_target_bps = 2_000
    self.reserve_floor = 0
    self.withdrawal_delay_epochs = 1
    self.current_epoch = 1
    self.next_request_id = 1


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _only_keeper():
    assert msg.sender == self.keeper or msg.sender == self.owner, "ONLY_KEEPER"


@internal
def _only_strategist():
    assert msg.sender == self.strategist or msg.sender == self.owner, "ONLY_STRATEGIST"


@internal
@view
def _total_assets() -> uint256:
    return self.free_liquidity + self.reserve_liquidity + self.strategy_assets


@internal
@view
def _liquid_assets() -> uint256:
    return self.free_liquidity + self.reserve_liquidity


@internal
@view
def _pps() -> uint256:
    supply: uint256 = self.totalSupply
    if supply == 0:
        return WAD
    return self._total_assets() * WAD // supply


@internal
@view
def _convert_to_shares(assets: uint256) -> uint256:
    supply: uint256 = self.totalSupply
    if supply == 0:
        return assets
    total: uint256 = self._total_assets()
    assert total > 0, "NO_ASSETS"
    return assets * supply // total


@internal
@view
def _convert_to_assets(shares: uint256) -> uint256:
    supply: uint256 = self.totalSupply
    if supply == 0:
        return shares
    return shares * self._total_assets() // supply


@internal
@view
def _reserve_target(total_assets_value: uint256) -> uint256:
    target: uint256 = total_assets_value * self.reserve_target_bps // BPS
    if target < self.reserve_floor:
        return self.reserve_floor
    return target


@internal
def _mint(receiver: address, amount: uint256):
    assert receiver != empty(address), "ZERO_RECEIVER"
    self.totalSupply += amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=empty(address), receiver=receiver, value=amount)


@internal
def _burn_escrowed(amount: uint256):
    assert self.escrowed_shares >= amount, "ESCROW"
    assert self.totalSupply >= amount, "SUPPLY"
    self.escrowed_shares -= amount
    self.totalSupply -= amount
    log Transfer(sender=self, receiver=empty(address), value=amount)


@internal
def _move_to_escrow(owner_: address, amount: uint256):
    assert self.balanceOf[owner_] >= amount, "BALANCE"
    self.balanceOf[owner_] -= amount
    self.escrowed_shares += amount
    log Transfer(sender=owner_, receiver=self, value=amount)


@internal
def _consume_liquidity(amount: uint256) -> uint256:
    free_used: uint256 = 0
    reserve_used: uint256 = 0
    if amount <= self.free_liquidity:
        free_used = amount
        self.free_liquidity -= amount
    else:
        free_used = self.free_liquidity
        reserve_used = amount - free_used
        self.free_liquidity = 0
        assert self.reserve_liquidity >= reserve_used, "RESERVE"
        self.reserve_liquidity -= reserve_used
    return reserve_used


@internal
def _increase_liquidity(amount: uint256):
    total_after: uint256 = self._total_assets() + amount
    target: uint256 = self._reserve_target(total_after)
    if self.reserve_liquidity < target:
        reserve_gap: uint256 = target - self.reserve_liquidity
        reserve_add: uint256 = min(amount, reserve_gap)
        self.reserve_liquidity += reserve_add
        self.free_liquidity += amount - reserve_add
    else:
        self.free_liquidity += amount


@internal
def _register_epoch_request(epoch: uint256, request_id: uint256, shares: uint256, assets: uint256):
    if self.epochs[epoch].first_request_id == 0:
        self.epochs[epoch].first_request_id = request_id
        self.epochs[epoch].processed_until = request_id - 1
    self.epochs[epoch].last_request_id = request_id
    self.epochs[epoch].pending_shares += shares
    self.epochs[epoch].pending_assets += assets


@external
def transfer(receiver: address, amount: uint256) -> bool:
    assert receiver != empty(address), "ZERO_RECEIVER"
    assert self.balanceOf[msg.sender] >= amount, "BALANCE"
    self.balanceOf[msg.sender] -= amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=msg.sender, receiver=receiver, value=amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "ZERO_SPENDER"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True


@external
def transferFrom(owner_: address, receiver: address, amount: uint256) -> bool:
    assert owner_ != empty(address), "ZERO_OWNER"
    assert receiver != empty(address), "ZERO_RECEIVER"
    allowed: uint256 = self.allowance[owner_][msg.sender]
    assert allowed >= amount, "ALLOWANCE"
    assert self.balanceOf[owner_] >= amount, "BALANCE"
    if allowed != max_value(uint256):
        self.allowance[owner_][msg.sender] = allowed - amount
        log Approval(owner=owner_, spender=msg.sender, value=self.allowance[owner_][msg.sender])
    self.balanceOf[owner_] -= amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=owner_, receiver=receiver, value=amount)
    return True


@external
def deposit(assets: uint256, receiver: address) -> uint256:
    assert assets > 0, "ZERO_ASSETS"
    assert receiver != empty(address), "ZERO_RECEIVER"
    shares: uint256 = self._convert_to_shares(assets)
    assert shares > 0, "ZERO_SHARES"
    assert extcall ERC20Like(self.asset).transferFrom(msg.sender, self, assets), "TRANSFER_FROM"
    self._increase_liquidity(assets)
    self._mint(receiver, shares)
    log Deposit(
        caller=msg.sender,
        owner=receiver,
        assets=assets,
        shares=shares,
        reserve_added=min(assets, self.reserve_liquidity),
    )
    return shares


@external
def request_withdrawal(shares: uint256, receiver: address) -> uint256:
    assert shares > 0, "ZERO_SHARES"
    assert receiver != empty(address), "ZERO_RECEIVER"
    assert self.totalSupply > 0, "NO_SUPPLY"

    snapshot_pps: uint256 = self._pps()
    quoted_assets: uint256 = shares * snapshot_pps // WAD
    assert quoted_assets > 0, "ZERO_QUOTE"

    request_id: uint256 = self.next_request_id
    self.next_request_id = request_id + 1
    epoch: uint256 = self.current_epoch + self.withdrawal_delay_epochs

    self._move_to_escrow(msg.sender, shares)
    self.withdrawal_liabilities += quoted_assets
    self.requests[request_id] = WithdrawalRequest(
        owner=msg.sender,
        receiver=receiver,
        epoch=epoch,
        shares=shares,
        quoted_assets=quoted_assets,
        snapshot_pps=snapshot_pps,
        requested_at=block.timestamp,
        processed_at=0,
        paid_assets=0,
        status=1,
    )
    self._register_epoch_request(epoch, request_id, shares, quoted_assets)

    log WithdrawalRequested(
        request_id=request_id,
        owner=msg.sender,
        receiver=receiver,
        epoch=epoch,
        shares=shares,
        quoted_assets=quoted_assets,
        snapshot_pps=snapshot_pps,
    )
    return request_id


@external
def process_epoch(epoch: uint256, max_items: uint256) -> uint256:
    self._only_keeper()
    assert epoch <= self.current_epoch, "FUTURE_EPOCH"
    assert max_items > 0 and max_items <= MAX_BATCH, "BAD_BATCH"
    first_id: uint256 = self.epochs[epoch].first_request_id
    last_id: uint256 = self.epochs[epoch].last_request_id
    assert first_id != 0, "EMPTY_EPOCH"

    cursor: uint256 = self.epochs[epoch].processed_until + 1
    if cursor < first_id:
        cursor = first_id

    processed: uint256 = 0
    for _: uint256 in range(MAX_BATCH):
        if processed >= max_items:
            break
        if cursor > last_id:
            break

        req: WithdrawalRequest = self.requests[cursor]
        if req.status == 1:
            amount: uint256 = req.quoted_assets
            assert self._liquid_assets() >= amount, "INSUFFICIENT_LIQUIDITY"
            reserve_used: uint256 = self._consume_liquidity(amount)
            self._burn_escrowed(req.shares)
            assert self.withdrawal_liabilities >= amount, "LIABILITY"
            self.withdrawal_liabilities -= amount
            self.epochs[epoch].pending_shares -= req.shares
            self.epochs[epoch].pending_assets -= amount
            self.epochs[epoch].paid_assets += amount
            self.epochs[epoch].processed_count += 1

            req.status = 2
            req.processed_at = block.timestamp
            req.paid_assets = amount
            self.requests[cursor] = req
            assert extcall ERC20Like(self.asset).transfer(req.receiver, amount), "TRANSFER"
            log WithdrawalProcessed(
                request_id=cursor,
                owner=req.owner,
                receiver=req.receiver,
                epoch=epoch,
                shares=req.shares,
                paid_assets=amount,
                used_reserve=reserve_used,
            )

        self.epochs[epoch].processed_until = cursor
        cursor += 1
        processed += 1

    if self.epochs[epoch].processed_until >= last_id:
        self.epochs[epoch].closed = True
    return processed


@external
def advance_epoch():
    self._only_keeper()
    previous: uint256 = self.current_epoch
    self.current_epoch = previous + 1
    log EpochAdvanced(previous_epoch=previous, new_epoch=self.current_epoch)


@external
def allocate_to_strategy(strategy: address, amount: uint256):
    self._only_strategist()
    assert strategy != empty(address), "ZERO_STRATEGY"
    assert amount > 0, "ZERO_AMOUNT"
    assert self.free_liquidity >= amount, "FREE_LIQUIDITY"
    self.free_liquidity -= amount
    self.strategy_assets += amount
    assert extcall ERC20Like(self.asset).transfer(strategy, amount), "TRANSFER"
    log LiquidityAllocated(strategy=strategy, amount=amount)


@external
def note_strategy_return(strategy: address, amount: uint256):
    self._only_strategist()
    assert strategy != empty(address), "ZERO_STRATEGY"
    assert amount > 0, "ZERO_AMOUNT"
    assert self.strategy_assets >= amount, "STRATEGY_ASSETS"
    self.strategy_assets -= amount
    self._increase_liquidity(amount)
    log LiquidityReturned(strategy=strategy, amount=amount)


@external
def report_strategy_loss(strategy: address, amount: uint256):
    self._only_strategist()
    assert strategy != empty(address), "ZERO_STRATEGY"
    assert amount > 0, "ZERO_AMOUNT"
    assert self.strategy_assets >= amount, "STRATEGY_ASSETS"
    self.strategy_assets -= amount
    log StrategyLossReported(
        strategy=strategy,
        amount=amount,
        new_strategy_assets=self.strategy_assets,
        new_price_per_share=self._pps(),
    )


@external
def rebalance_reserve():
    self._only_keeper()
    total: uint256 = self._total_assets()
    target: uint256 = self._reserve_target(total)
    if self.reserve_liquidity < target:
        move_to_reserve: uint256 = min(target - self.reserve_liquidity, self.free_liquidity)
        self.free_liquidity -= move_to_reserve
        self.reserve_liquidity += move_to_reserve
    elif self.reserve_liquidity > target:
        move_to_free: uint256 = self.reserve_liquidity - target
        self.reserve_liquidity -= move_to_free
        self.free_liquidity += move_to_free
    log ReserveRebalanced(
        free_liquidity=self.free_liquidity,
        reserve_liquidity=self.reserve_liquidity,
        target_reserve=target,
    )


@external
def set_keeper(new_keeper: address):
    self._only_owner()
    assert new_keeper != empty(address), "ZERO_KEEPER"
    self.keeper = new_keeper
    log KeeperUpdated(keeper=new_keeper)


@external
def set_strategist(new_strategist: address):
    self._only_owner()
    assert new_strategist != empty(address), "ZERO_STRATEGIST"
    self.strategist = new_strategist
    log StrategistUpdated(strategist=new_strategist)


@external
def set_reserve_target_bps(new_bps: uint256):
    self._only_owner()
    assert new_bps <= MAX_BPS, "BPS"
    self.reserve_target_bps = new_bps
    log ParameterUpdated(key=keccak256("reserve_target_bps"), value=new_bps)


@external
def set_reserve_floor(new_floor: uint256):
    self._only_owner()
    self.reserve_floor = new_floor
    log ParameterUpdated(key=keccak256("reserve_floor"), value=new_floor)


@external
def set_withdrawal_delay_epochs(new_delay: uint256):
    self._only_owner()
    assert new_delay <= MAX_DELAY, "DELAY"
    self.withdrawal_delay_epochs = new_delay
    log ParameterUpdated(key=keccak256("withdrawal_delay_epochs"), value=new_delay)


@external
@view
def total_assets() -> uint256:
    return self._total_assets()


@external
@view
def liquid_assets() -> uint256:
    return self._liquid_assets()


@external
@view
def price_per_share() -> uint256:
    return self._pps()


@external
@view
def convert_to_shares(assets: uint256) -> uint256:
    return self._convert_to_shares(assets)


@external
@view
def convert_to_assets(shares: uint256) -> uint256:
    return self._convert_to_assets(shares)


@external
@view
def available_to_process_epoch(epoch: uint256) -> uint256:
    if self.epochs[epoch].pending_assets <= self._liquid_assets():
        return self.epochs[epoch].pending_assets
    return self._liquid_assets()


@external
@view
def request_value_at_current_pps(request_id: uint256) -> uint256:
    req: WithdrawalRequest = self.requests[request_id]
    return req.shares * self._pps() // WAD


@external
@view
def request_quote_delta(request_id: uint256) -> uint256:
    req: WithdrawalRequest = self.requests[request_id]
    current_value: uint256 = req.shares * self._pps() // WAD
    if req.quoted_assets > current_value:
        return req.quoted_assets - current_value
    return 0
