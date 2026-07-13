# @version ^0.4.3

"""
Epoch ledger for off-vault accounting.

The ledger mirrors queue information so auditors can compare what was requested
at snapshot time with execution-time liquidity and reserve conditions.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000

struct EpochRecord:
    opened: bool
    closed: bool
    first_request_id: uint256
    last_request_id: uint256
    pending_shares: uint256
    quoted_assets: uint256
    paid_assets: uint256
    quote_delta: uint256
    created_at: uint256
    closed_at: uint256

struct RequestMirror:
    owner: address
    receiver: address
    epoch: uint256
    shares: uint256
    quoted_assets: uint256
    fair_assets_at_execution: uint256
    paid_assets: uint256
    snapshot_pps: uint256
    execution_pps: uint256
    processed: bool

event OperatorUpdated:
    operator: indexed(address)

event EpochOpened:
    epoch: indexed(uint256)
    created_at: uint256

event RequestMirrored:
    epoch: indexed(uint256)
    request_id: indexed(uint256)
    owner: indexed(address)
    shares: uint256
    quoted_assets: uint256

event PaymentMirrored:
    epoch: indexed(uint256)
    request_id: indexed(uint256)
    paid_assets: uint256
    fair_assets: uint256
    quote_delta: uint256

event EpochClosed:
    epoch: indexed(uint256)
    paid_assets: uint256
    quote_delta: uint256

owner: public(address)
operator: public(address)
epochs: public(HashMap[uint256, EpochRecord])
requests: public(HashMap[uint256, RequestMirror])


@deploy
def __init__(_owner: address, _operator: address):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.owner = _owner
    self.operator = _operator


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _only_operator():
    assert msg.sender == self.operator or msg.sender == self.owner, "ONLY_OPERATOR"


@internal
@pure
def _fair_assets(shares: uint256, execution_pps: uint256) -> uint256:
    return shares * execution_pps // WAD


@internal
@pure
def _quote_delta(quoted_assets: uint256, fair_assets: uint256) -> uint256:
    if quoted_assets > fair_assets:
        return quoted_assets - fair_assets
    return 0


@external
def set_operator(new_operator: address):
    self._only_owner()
    assert new_operator != empty(address), "ZERO_OPERATOR"
    self.operator = new_operator
    log OperatorUpdated(operator=new_operator)


@external
def open_epoch(epoch: uint256):
    self._only_operator()
    record: EpochRecord = self.epochs[epoch]
    assert not record.opened, "OPENED"
    self.epochs[epoch] = EpochRecord(
        opened=True,
        closed=False,
        first_request_id=0,
        last_request_id=0,
        pending_shares=0,
        quoted_assets=0,
        paid_assets=0,
        quote_delta=0,
        created_at=block.timestamp,
        closed_at=0,
    )
    log EpochOpened(epoch=epoch, created_at=block.timestamp)


@external
def mirror_request(
    request_id: uint256,
    epoch: uint256,
    owner_: address,
    receiver: address,
    shares: uint256,
    quoted_assets: uint256,
    snapshot_pps: uint256,
):
    self._only_operator()
    assert owner_ != empty(address), "ZERO_OWNER"
    assert receiver != empty(address), "ZERO_RECEIVER"
    record: EpochRecord = self.epochs[epoch]
    if not record.opened:
        record.opened = True
        record.created_at = block.timestamp
    if record.first_request_id == 0:
        record.first_request_id = request_id
    if request_id > record.last_request_id:
        record.last_request_id = request_id
    record.pending_shares += shares
    record.quoted_assets += quoted_assets
    self.epochs[epoch] = record
    self.requests[request_id] = RequestMirror(
        owner=owner_,
        receiver=receiver,
        epoch=epoch,
        shares=shares,
        quoted_assets=quoted_assets,
        fair_assets_at_execution=0,
        paid_assets=0,
        snapshot_pps=snapshot_pps,
        execution_pps=0,
        processed=False,
    )
    log RequestMirrored(epoch=epoch, request_id=request_id, owner=owner_, shares=shares, quoted_assets=quoted_assets)


@external
def mirror_payment(request_id: uint256, execution_pps: uint256, paid_assets: uint256):
    self._only_operator()
    mirror: RequestMirror = self.requests[request_id]
    assert mirror.owner != empty(address), "NO_REQUEST"
    assert not mirror.processed, "PROCESSED"
    fair_assets: uint256 = self._fair_assets(mirror.shares, execution_pps)
    premium: uint256 = self._quote_delta(paid_assets, fair_assets)
    mirror.execution_pps = execution_pps
    mirror.fair_assets_at_execution = fair_assets
    mirror.paid_assets = paid_assets
    mirror.processed = True
    self.requests[request_id] = mirror

    record: EpochRecord = self.epochs[mirror.epoch]
    if record.pending_shares >= mirror.shares:
        record.pending_shares -= mirror.shares
    else:
        record.pending_shares = 0
    record.paid_assets += paid_assets
    record.quote_delta += premium
    self.epochs[mirror.epoch] = record
    log PaymentMirrored(
        epoch=mirror.epoch,
        request_id=request_id,
        paid_assets=paid_assets,
        fair_assets=fair_assets,
        quote_delta=premium,
    )


@external
def close_epoch(epoch: uint256):
    self._only_operator()
    record: EpochRecord = self.epochs[epoch]
    assert record.opened, "NO_EPOCH"
    assert not record.closed, "CLOSED"
    record.closed = True
    record.closed_at = block.timestamp
    self.epochs[epoch] = record
    log EpochClosed(epoch=epoch, paid_assets=record.paid_assets, quote_delta=record.quote_delta)


@external
@view
def epoch_completion_bps(epoch: uint256) -> uint256:
    record: EpochRecord = self.epochs[epoch]
    total: uint256 = record.paid_assets + record.quoted_assets
    if total == 0:
        return 0
    return record.paid_assets * BPS // total


@external
@view
def premium_bps(epoch: uint256) -> uint256:
    record: EpochRecord = self.epochs[epoch]
    if record.paid_assets == 0:
        return 0
    return record.quote_delta * BPS // record.paid_assets


@external
@view
def request_premium(request_id: uint256) -> uint256:
    mirror: RequestMirror = self.requests[request_id]
    if mirror.paid_assets > mirror.fair_assets_at_execution:
        return mirror.paid_assets - mirror.fair_assets_at_execution
    return 0


@external
@view
def request_has_positive_quote_delta(request_id: uint256) -> bool:
    mirror: RequestMirror = self.requests[request_id]
    return mirror.paid_assets > mirror.fair_assets_at_execution and mirror.processed


@external
@view
def epoch_has_quote_delta(epoch: uint256) -> bool:
    return self.epochs[epoch].quote_delta > 0
