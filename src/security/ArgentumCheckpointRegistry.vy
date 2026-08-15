# @version ^0.4.3

"""
Hash-linked accounting checkpoint registry.

Authorized reporters publish compact commitments for epoch accounting. The
registry enforces ordering, a previous-checkpoint link and an optional quorum
before a checkpoint becomes final.
"""

MAX_REPORTERS: constant(uint256) = 16

struct Checkpoint:
    epoch: uint256
    total_assets: uint256
    total_supply: uint256
    liquid_assets: uint256
    pending_assets: uint256
    payload_hash: bytes32
    previous_hash: bytes32
    checkpoint_hash: bytes32
    approvals: uint256
    submitted_at: uint256
    finalized_at: uint256
    finalized: bool

event ReporterUpdated:
    reporter: indexed(address)
    authorized: bool

event QuorumUpdated:
    quorum: uint256

event CheckpointSubmitted:
    epoch: indexed(uint256)
    checkpoint_hash: indexed(bytes32)
    previous_hash: bytes32
    reporter: indexed(address)

event CheckpointApproved:
    epoch: indexed(uint256)
    reporter: indexed(address)
    approvals: uint256

event CheckpointFinalized:
    epoch: indexed(uint256)
    checkpoint_hash: indexed(bytes32)
    approvals: uint256

owner: public(address)
reporter_count: public(uint256)
quorum: public(uint256)
latest_epoch: public(uint256)
latest_finalized_hash: public(bytes32)
authorized_reporter: public(HashMap[address, bool])
checkpoints: public(HashMap[uint256, Checkpoint])
approved_by: public(HashMap[uint256, HashMap[address, bool]])


@deploy
def __init__(_owner: address, _quorum: uint256):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _quorum > 0 and _quorum <= MAX_REPORTERS, "QUORUM"
    self.owner = _owner
    self.quorum = _quorum


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@view
def _only_reporter():
    assert self.authorized_reporter[msg.sender], "ONLY_REPORTER"


@internal
@pure
def _build_hash(
    epoch: uint256,
    total_assets: uint256,
    total_supply: uint256,
    liquid_assets: uint256,
    pending_assets: uint256,
    payload_hash: bytes32,
    previous_hash: bytes32,
) -> bytes32:
    return keccak256(concat(
        convert(epoch, bytes32),
        convert(total_assets, bytes32),
        convert(total_supply, bytes32),
        convert(liquid_assets, bytes32),
        convert(pending_assets, bytes32),
        payload_hash,
        previous_hash,
    ))


@external
def transfer_ownership(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner


@external
def set_reporter(reporter: address, authorized: bool):
    self._only_owner()
    assert reporter != empty(address), "ZERO_REPORTER"
    current: bool = self.authorized_reporter[reporter]
    if current == authorized:
        return
    if authorized:
        assert self.reporter_count < MAX_REPORTERS, "REPORTER_LIMIT"
        self.reporter_count += 1
    else:
        assert self.reporter_count > 0, "REPORTER_COUNT"
        self.reporter_count -= 1
        assert self.quorum <= self.reporter_count, "QUORUM_EXCEEDS_REPORTERS"
    self.authorized_reporter[reporter] = authorized
    log ReporterUpdated(reporter=reporter, authorized=authorized)


@external
def set_quorum(new_quorum: uint256):
    self._only_owner()
    assert new_quorum > 0, "ZERO_QUORUM"
    assert new_quorum <= self.reporter_count, "QUORUM_EXCEEDS_REPORTERS"
    self.quorum = new_quorum
    log QuorumUpdated(quorum=new_quorum)


@external
def submit_checkpoint(
    epoch: uint256,
    total_assets: uint256,
    total_supply: uint256,
    liquid_assets: uint256,
    pending_assets: uint256,
    payload_hash: bytes32,
) -> bytes32:
    self._only_reporter()
    assert epoch > self.latest_epoch, "EPOCH_ORDER"
    assert self.checkpoints[epoch].submitted_at == 0, "CHECKPOINT_EXISTS"
    assert liquid_assets <= total_assets, "LIQUID_ASSETS"
    assert payload_hash != empty(bytes32), "EMPTY_PAYLOAD"

    previous: bytes32 = self.latest_finalized_hash
    digest: bytes32 = self._build_hash(
        epoch,
        total_assets,
        total_supply,
        liquid_assets,
        pending_assets,
        payload_hash,
        previous,
    )
    self.checkpoints[epoch] = Checkpoint(
        epoch=epoch,
        total_assets=total_assets,
        total_supply=total_supply,
        liquid_assets=liquid_assets,
        pending_assets=pending_assets,
        payload_hash=payload_hash,
        previous_hash=previous,
        checkpoint_hash=digest,
        approvals=1,
        submitted_at=block.timestamp,
        finalized_at=0,
        finalized=False,
    )
    self.approved_by[epoch][msg.sender] = True
    self.latest_epoch = epoch
    log CheckpointSubmitted(epoch=epoch, checkpoint_hash=digest, previous_hash=previous, reporter=msg.sender)
    if self.quorum == 1:
        self.checkpoints[epoch].finalized = True
        self.checkpoints[epoch].finalized_at = block.timestamp
        self.latest_finalized_hash = digest
        log CheckpointFinalized(epoch=epoch, checkpoint_hash=digest, approvals=1)
    return digest


@external
def approve_checkpoint(epoch: uint256):
    self._only_reporter()
    checkpoint: Checkpoint = self.checkpoints[epoch]
    assert checkpoint.submitted_at != 0, "NO_CHECKPOINT"
    assert not checkpoint.finalized, "FINALIZED"
    assert not self.approved_by[epoch][msg.sender], "ALREADY_APPROVED"
    assert checkpoint.previous_hash == self.latest_finalized_hash, "STALE_PARENT"
    self.approved_by[epoch][msg.sender] = True
    checkpoint.approvals += 1
    log CheckpointApproved(epoch=epoch, reporter=msg.sender, approvals=checkpoint.approvals)
    if checkpoint.approvals >= self.quorum:
        checkpoint.finalized = True
        checkpoint.finalized_at = block.timestamp
        self.latest_finalized_hash = checkpoint.checkpoint_hash
        log CheckpointFinalized(epoch=epoch, checkpoint_hash=checkpoint.checkpoint_hash, approvals=checkpoint.approvals)
    self.checkpoints[epoch] = checkpoint


@external
@view
def compute_checkpoint_hash(
    epoch: uint256,
    total_assets: uint256,
    total_supply: uint256,
    liquid_assets: uint256,
    pending_assets: uint256,
    payload_hash: bytes32,
    previous_hash: bytes32,
) -> bytes32:
    return self._build_hash(epoch, total_assets, total_supply, liquid_assets, pending_assets, payload_hash, previous_hash)


@external
@view
def is_finalized(epoch: uint256) -> bool:
    return self.checkpoints[epoch].finalized


@external
@view
def pending_approvals(epoch: uint256) -> uint256:
    checkpoint: Checkpoint = self.checkpoints[epoch]
    if checkpoint.finalized or checkpoint.submitted_at == 0:
        return 0
    if checkpoint.approvals >= self.quorum:
        return 0
    return self.quorum - checkpoint.approvals


@external
@view
def verifies(epoch: uint256) -> bool:
    checkpoint: Checkpoint = self.checkpoints[epoch]
    if checkpoint.submitted_at == 0:
        return False
    return checkpoint.checkpoint_hash == self._build_hash(
        checkpoint.epoch,
        checkpoint.total_assets,
        checkpoint.total_supply,
        checkpoint.liquid_assets,
        checkpoint.pending_assets,
        checkpoint.payload_hash,
        checkpoint.previous_hash,
    )
