# @version ^0.4.3

"""
Keeper coordination registry for epoch work.

This contract models scheduling, windows, and accountability around epoch
execution without changing vault settlement math.
"""

MAX_WINDOW: constant(uint256) = 7 * 24 * 60 * 60
MAX_BATCH: constant(uint256) = 128

struct EpochJob:
    vault: address
    epoch: uint256
    earliest_time: uint256
    latest_time: uint256
    max_items: uint256
    assigned_keeper: address
    completed: bool
    completed_at: uint256

event OwnerUpdated:
    owner: indexed(address)

event KeeperAuthorizationUpdated:
    keeper: indexed(address)
    authorized: bool

event JobScheduled:
    job_id: indexed(uint256)
    vault: indexed(address)
    epoch: uint256
    assigned_keeper: indexed(address)
    earliest_time: uint256
    latest_time: uint256
    max_items: uint256

event JobCompleted:
    job_id: indexed(uint256)
    keeper: indexed(address)
    completed_at: uint256

owner: public(address)
next_job_id: public(uint256)
authorized_keeper: public(HashMap[address, bool])
jobs: public(HashMap[uint256, EpochJob])
latest_job_for_epoch: public(HashMap[address, HashMap[uint256, uint256]])


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.next_job_id = 1


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@view
def _is_keeper(keeper: address) -> bool:
    return keeper == self.owner or self.authorized_keeper[keeper]


@external
def set_owner(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner
    log OwnerUpdated(owner=new_owner)


@external
def set_keeper(keeper: address, authorized: bool):
    self._only_owner()
    assert keeper != empty(address), "ZERO_KEEPER"
    self.authorized_keeper[keeper] = authorized
    log KeeperAuthorizationUpdated(keeper=keeper, authorized=authorized)


@external
def schedule_epoch_job(
    vault: address,
    epoch: uint256,
    assigned_keeper: address,
    earliest_time: uint256,
    latest_time: uint256,
    max_items: uint256,
) -> uint256:
    self._only_owner()
    assert vault != empty(address), "ZERO_VAULT"
    assert self._is_keeper(assigned_keeper), "KEEPER"
    assert latest_time >= earliest_time, "WINDOW"
    assert latest_time - earliest_time <= MAX_WINDOW, "LONG_WINDOW"
    assert max_items > 0 and max_items <= MAX_BATCH, "BATCH"

    job_id: uint256 = self.next_job_id
    self.next_job_id = job_id + 1
    self.jobs[job_id] = EpochJob(
        vault=vault,
        epoch=epoch,
        earliest_time=earliest_time,
        latest_time=latest_time,
        max_items=max_items,
        assigned_keeper=assigned_keeper,
        completed=False,
        completed_at=0,
    )
    self.latest_job_for_epoch[vault][epoch] = job_id
    log JobScheduled(
        job_id=job_id,
        vault=vault,
        epoch=epoch,
        assigned_keeper=assigned_keeper,
        earliest_time=earliest_time,
        latest_time=latest_time,
        max_items=max_items,
    )
    return job_id


@external
def complete_job(job_id: uint256):
    job: EpochJob = self.jobs[job_id]
    assert job.vault != empty(address), "NO_JOB"
    assert not job.completed, "DONE"
    assert msg.sender == job.assigned_keeper or msg.sender == self.owner, "KEEPER"
    assert block.timestamp >= job.earliest_time, "EARLY"
    assert block.timestamp <= job.latest_time, "LATE"
    job.completed = True
    job.completed_at = block.timestamp
    self.jobs[job_id] = job
    log JobCompleted(job_id=job_id, keeper=msg.sender, completed_at=block.timestamp)


@external
def cancel_job(job_id: uint256):
    self._only_owner()
    job: EpochJob = self.jobs[job_id]
    assert job.vault != empty(address), "NO_JOB"
    assert not job.completed, "DONE"
    job.completed = True
    job.completed_at = block.timestamp
    self.jobs[job_id] = job
    log JobCompleted(job_id=job_id, keeper=msg.sender, completed_at=block.timestamp)


@external
@view
def can_execute(job_id: uint256, keeper: address) -> bool:
    job: EpochJob = self.jobs[job_id]
    if job.vault == empty(address):
        return False
    if job.completed:
        return False
    if keeper != job.assigned_keeper and keeper != self.owner:
        return False
    if block.timestamp < job.earliest_time:
        return False
    if block.timestamp > job.latest_time:
        return False
    return True


@external
@view
def job_window_status(job_id: uint256) -> uint256:
    job: EpochJob = self.jobs[job_id]
    if job.vault == empty(address):
        return 0
    if job.completed:
        return 4
    if block.timestamp < job.earliest_time:
        return 1
    if block.timestamp > job.latest_time:
        return 3
    return 2


@external
@view
def seconds_until_start(job_id: uint256) -> uint256:
    job: EpochJob = self.jobs[job_id]
    if job.vault == empty(address):
        return 0
    if block.timestamp >= job.earliest_time:
        return 0
    return job.earliest_time - block.timestamp


@external
@view
def seconds_until_deadline(job_id: uint256) -> uint256:
    job: EpochJob = self.jobs[job_id]
    if job.vault == empty(address):
        return 0
    if block.timestamp >= job.latest_time:
        return 0
    return job.latest_time - block.timestamp


@external
@view
def latest_job(vault: address, epoch: uint256) -> uint256:
    return self.latest_job_for_epoch[vault][epoch]
