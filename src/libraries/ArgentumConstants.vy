# @version ^0.4.3

"""
Shared constants and key helpers for ArgentumVaultProtocol.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000

REQUEST_NONE: constant(uint256) = 0
REQUEST_PENDING: constant(uint256) = 1
REQUEST_PROCESSED: constant(uint256) = 2
REQUEST_CANCELLED: constant(uint256) = 3

RESERVE_HEALTHY: constant(uint256) = 0
RESERVE_UNDER_TARGET: constant(uint256) = 1
RESERVE_SOFT_BREACH: constant(uint256) = 2
RESERVE_HARD_BREACH: constant(uint256) = 3


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
def request_none() -> uint256:
    return REQUEST_NONE


@external
@pure
def request_pending() -> uint256:
    return REQUEST_PENDING


@external
@pure
def request_processed() -> uint256:
    return REQUEST_PROCESSED


@external
@pure
def request_cancelled() -> uint256:
    return REQUEST_CANCELLED


@external
@pure
def reserve_healthy() -> uint256:
    return RESERVE_HEALTHY


@external
@pure
def reserve_under_target() -> uint256:
    return RESERVE_UNDER_TARGET


@external
@pure
def reserve_soft_breach() -> uint256:
    return RESERVE_SOFT_BREACH


@external
@pure
def reserve_hard_breach() -> uint256:
    return RESERVE_HARD_BREACH


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
def keeper_key() -> bytes32:
    return keccak256("keeper")


@external
@pure
def strategist_key() -> bytes32:
    return keccak256("strategist")


@external
@pure
def status_is_terminal(status: uint256) -> bool:
    return status == REQUEST_PROCESSED or status == REQUEST_CANCELLED


@external
@pure
def status_is_active(status: uint256) -> bool:
    return status == REQUEST_PENDING


@external
@pure
def reserve_status_is_breach(status: uint256) -> bool:
    return status == RESERVE_SOFT_BREACH or status == RESERVE_HARD_BREACH


@external
@pure
def reserve_status_blocks_draw(status: uint256) -> bool:
    return status == RESERVE_HARD_BREACH

