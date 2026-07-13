# @version ^0.4.3

"""
Parameter store with bounded timelock updates.

This contract provides governance context for reserve targets, withdrawal delay,
batch sizes, and risk limits. It is conservative and separate from the core
vault so operators can distinguish parameter governance from accounting logic.
"""

BPS: constant(uint256) = 10_000
MAX_DELAY: constant(uint256) = 30 * 24 * 60 * 60
MIN_DELAY: constant(uint256) = 60 * 60

struct Parameter:
    exists: bool
    current_value: uint256
    pending_value: uint256
    lower_bound: uint256
    upper_bound: uint256
    eta: uint256
    updated_at: uint256

event OwnerUpdated:
    owner: indexed(address)

event PendingOwnerUpdated:
    pending_owner: indexed(address)

event DelayUpdated:
    delay: uint256

event ParameterInitialized:
    key: indexed(bytes32)
    current_value: uint256
    lower_bound: uint256
    upper_bound: uint256

event ParameterStaged:
    key: indexed(bytes32)
    pending_value: uint256
    eta: uint256

event ParameterCommitted:
    key: indexed(bytes32)
    current_value: uint256

event ParameterCancelled:
    key: indexed(bytes32)

owner: public(address)
pending_owner: public(address)
delay: public(uint256)
parameters: public(HashMap[bytes32, Parameter])


@deploy
def __init__(_owner: address, _delay: uint256):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _delay >= MIN_DELAY and _delay <= MAX_DELAY, "DELAY"
    self.owner = _owner
    self.delay = _delay


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@view
def _within_bounds(key: bytes32, proposed_value: uint256) -> bool:
    param: Parameter = self.parameters[key]
    if not param.exists:
        return False
    if proposed_value < param.lower_bound:
        return False
    if proposed_value > param.upper_bound:
        return False
    return True


@external
def transfer_ownership(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.pending_owner = new_owner
    log PendingOwnerUpdated(pending_owner=new_owner)


@external
def accept_ownership():
    assert msg.sender == self.pending_owner, "PENDING_OWNER"
    self.owner = msg.sender
    self.pending_owner = empty(address)
    log OwnerUpdated(owner=msg.sender)


@external
def set_delay(new_delay: uint256):
    self._only_owner()
    assert new_delay >= MIN_DELAY and new_delay <= MAX_DELAY, "DELAY"
    self.delay = new_delay
    log DelayUpdated(delay=new_delay)


@external
def initialize_parameter(key: bytes32, current_value: uint256, lower_bound: uint256, upper_bound: uint256):
    self._only_owner()
    assert key != empty(bytes32), "KEY"
    assert lower_bound <= current_value and current_value <= upper_bound, "BOUNDS"
    param: Parameter = self.parameters[key]
    assert not param.exists, "EXISTS"
    self.parameters[key] = Parameter(
        exists=True,
        current_value=current_value,
        pending_value=0,
        lower_bound=lower_bound,
        upper_bound=upper_bound,
        eta=0,
        updated_at=block.timestamp,
    )
    log ParameterInitialized(key=key, current_value=current_value, lower_bound=lower_bound, upper_bound=upper_bound)


@external
def stage_parameter(key: bytes32, pending_value: uint256):
    self._only_owner()
    assert self._within_bounds(key, pending_value), "BOUNDS"
    param: Parameter = self.parameters[key]
    param.pending_value = pending_value
    param.eta = block.timestamp + self.delay
    self.parameters[key] = param
    log ParameterStaged(key=key, pending_value=pending_value, eta=param.eta)


@external
def commit_parameter(key: bytes32):
    self._only_owner()
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    assert param.eta != 0, "NO_PENDING"
    assert block.timestamp >= param.eta, "TIMELOCK"
    param.current_value = param.pending_value
    param.pending_value = 0
    param.eta = 0
    param.updated_at = block.timestamp
    self.parameters[key] = param
    log ParameterCommitted(key=key, current_value=param.current_value)


@external
def cancel_parameter(key: bytes32):
    self._only_owner()
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    assert param.eta != 0, "NO_PENDING"
    param.pending_value = 0
    param.eta = 0
    self.parameters[key] = param
    log ParameterCancelled(key=key)


@external
def update_bounds(key: bytes32, lower_bound: uint256, upper_bound: uint256):
    self._only_owner()
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    assert lower_bound <= param.current_value and param.current_value <= upper_bound, "BOUNDS"
    param.lower_bound = lower_bound
    param.upper_bound = upper_bound
    self.parameters[key] = param
    log ParameterInitialized(key=key, current_value=param.current_value, lower_bound=lower_bound, upper_bound=upper_bound)


@external
@view
def current_value(key: bytes32) -> uint256:
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    return param.current_value


@external
@view
def pending_value(key: bytes32) -> uint256:
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    return param.pending_value


@external
@view
def has_pending(key: bytes32) -> bool:
    param: Parameter = self.parameters[key]
    return param.exists and param.eta != 0


@external
@view
def time_to_commit(key: bytes32) -> uint256:
    param: Parameter = self.parameters[key]
    if not param.exists or param.eta == 0:
        return 0
    if block.timestamp >= param.eta:
        return 0
    return param.eta - block.timestamp


@external
@view
def within_bounds(key: bytes32, proposed_value: uint256) -> bool:
    return self._within_bounds(key, proposed_value)


@external
@view
def can_commit(key: bytes32) -> bool:
    param: Parameter = self.parameters[key]
    if not param.exists:
        return False
    if param.eta == 0:
        return False
    return block.timestamp >= param.eta


@external
@pure
def reserve_target_key() -> bytes32:
    return keccak256("reserve_target_bps")


@external
@pure
def reserve_floor_key() -> bytes32:
    return keccak256("reserve_floor")


@external
@pure
def withdrawal_delay_key() -> bytes32:
    return keccak256("withdrawal_delay_epochs")


@external
@pure
def max_batch_key() -> bytes32:
    return keccak256("max_batch")


@external
@pure
def strategy_cap_key(strategy: address) -> bytes32:
    return keccak256(convert(strategy, bytes32))


@external
@view
def preview_reserve_target(total_assets: uint256, reserve_target_key_: bytes32) -> uint256:
    param: Parameter = self.parameters[reserve_target_key_]
    assert param.exists, "NO_PARAM"
    assert param.current_value <= BPS, "BPS"
    return total_assets * param.current_value // BPS


@external
@view
def preview_after_pending_reserve_target(total_assets: uint256, reserve_target_key_: bytes32) -> uint256:
    param: Parameter = self.parameters[reserve_target_key_]
    assert param.exists, "NO_PARAM"
    candidate: uint256 = param.current_value
    if param.eta != 0:
        candidate = param.pending_value
    assert candidate <= BPS, "BPS"
    return total_assets * candidate // BPS


@external
@view
def parameter_tuple(key: bytes32) -> (uint256, uint256, uint256, uint256, uint256):
    param: Parameter = self.parameters[key]
    assert param.exists, "NO_PARAM"
    return param.current_value, param.pending_value, param.lower_bound, param.upper_bound, param.eta
