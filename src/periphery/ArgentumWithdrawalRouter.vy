# @version ^0.4.3

"""
Delegated withdrawal router.

Users may approve vault shares to this router, which pulls shares, creates the
vault withdrawal request, and routes payment to a chosen receiver. Requests are
still executed by the underlying vault so integrations preserve the same epoch
and batch accounting semantics as direct calls.
"""

interface ShareVault:
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def request_withdrawal(shares: uint256, receiver: address) -> uint256: nonpayable
    def process_epoch(epoch: uint256, max_items: uint256) -> uint256: nonpayable
    def current_epoch() -> uint256: view
    def requests(request_id: uint256) -> (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256): view

event OwnerUpdated:
    owner: indexed(address)

event VaultTrustUpdated:
    vault: indexed(address)
    trusted: bool

event RoutedWithdrawalRequested:
    vault: indexed(address)
    request_id: indexed(uint256)
    requester: indexed(address)
    receiver: address
    shares: uint256

event RoutedEpochProcessed:
    vault: indexed(address)
    epoch: indexed(uint256)
    caller: indexed(address)
    processed: uint256

event ReceiverUpdated:
    requester: indexed(address)
    receiver: indexed(address)

owner: public(address)
trusted_vault: public(HashMap[address, bool])
requester_for: public(HashMap[address, HashMap[uint256, address]])
receiver_for: public(HashMap[address, HashMap[uint256, address]])
default_receiver: public(HashMap[address, address])


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
@view
def _receiver_or_default(requester: address, receiver: address) -> address:
    if receiver != empty(address):
        return receiver
    configured: address = self.default_receiver[requester]
    if configured != empty(address):
        return configured
    return requester


@external
def set_owner(new_owner: address):
    self._only_owner()
    assert new_owner != empty(address), "ZERO_OWNER"
    self.owner = new_owner
    log OwnerUpdated(owner=new_owner)


@external
def set_trusted_vault(vault: address, trusted: bool):
    self._only_owner()
    assert vault != empty(address), "ZERO_VAULT"
    self.trusted_vault[vault] = trusted
    log VaultTrustUpdated(vault=vault, trusted=trusted)


@external
def set_default_receiver(receiver: address):
    assert receiver != empty(address), "ZERO_RECEIVER"
    self.default_receiver[msg.sender] = receiver
    log ReceiverUpdated(requester=msg.sender, receiver=receiver)


@external
def clear_default_receiver():
    self.default_receiver[msg.sender] = empty(address)
    log ReceiverUpdated(requester=msg.sender, receiver=empty(address))


@external
def request(vault: address, shares: uint256, receiver: address) -> uint256:
    assert self.trusted_vault[vault], "UNTRUSTED_VAULT"
    assert shares > 0, "ZERO_SHARES"
    resolved_receiver: address = self._receiver_or_default(msg.sender, receiver)
    assert extcall ShareVault(vault).transferFrom(msg.sender, self, shares), "TRANSFER_FROM"
    request_id: uint256 = extcall ShareVault(vault).request_withdrawal(shares, resolved_receiver)
    self.requester_for[vault][request_id] = msg.sender
    self.receiver_for[vault][request_id] = resolved_receiver
    log RoutedWithdrawalRequested(
        vault=vault,
        request_id=request_id,
        requester=msg.sender,
        receiver=resolved_receiver,
        shares=shares,
    )
    return request_id


@external
def request_to_default(vault: address, shares: uint256) -> uint256:
    assert self.trusted_vault[vault], "UNTRUSTED_VAULT"
    assert shares > 0, "ZERO_SHARES"
    resolved_receiver: address = self._receiver_or_default(msg.sender, empty(address))
    assert extcall ShareVault(vault).transferFrom(msg.sender, self, shares), "TRANSFER_FROM"
    request_id: uint256 = extcall ShareVault(vault).request_withdrawal(shares, resolved_receiver)
    self.requester_for[vault][request_id] = msg.sender
    self.receiver_for[vault][request_id] = resolved_receiver
    log RoutedWithdrawalRequested(
        vault=vault,
        request_id=request_id,
        requester=msg.sender,
        receiver=resolved_receiver,
        shares=shares,
    )
    return request_id


@external
def process(vault: address, epoch: uint256, max_items: uint256) -> uint256:
    assert self.trusted_vault[vault], "UNTRUSTED_VAULT"
    processed: uint256 = extcall ShareVault(vault).process_epoch(epoch, max_items)
    log RoutedEpochProcessed(vault=vault, epoch=epoch, caller=msg.sender, processed=processed)
    return processed


@external
@view
def is_mature(vault: address, request_id: uint256) -> bool:
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
    owner, receiver, epoch, shares, quoted_assets, snapshot_pps, requested_at, processed_at, paid_assets, status = staticcall ShareVault(vault).requests(request_id)
    return epoch <= staticcall ShareVault(vault).current_epoch()


@external
@view
def request_owner(vault: address, request_id: uint256) -> address:
    return self.requester_for[vault][request_id]


@external
@view
def request_receiver(vault: address, request_id: uint256) -> address:
    return self.receiver_for[vault][request_id]


@external
@view
def request_status(vault: address, request_id: uint256) -> (uint256, uint256, uint256, uint256):
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
    owner, receiver, epoch, shares, quoted_assets, snapshot_pps, requested_at, processed_at, paid_assets, status = staticcall ShareVault(vault).requests(request_id)
    return epoch, shares, quoted_assets, status
