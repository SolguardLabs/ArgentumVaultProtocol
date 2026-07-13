# @version ^0.4.3

interface ERC20Like:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def burn(amount: uint256): nonpayable
    def balanceOf(owner: address) -> uint256: view

event VaultUpdated:
    vault: indexed(address)

event AssetsReturned:
    vault: indexed(address)
    amount: uint256

event LossRealized:
    amount: uint256

asset: public(address)
vault: public(address)
keeper: public(address)


@deploy
def __init__(_asset: address, _vault: address, _keeper: address):
    assert _asset != empty(address), "ZERO_ASSET"
    assert _keeper != empty(address), "ZERO_KEEPER"
    self.asset = _asset
    self.vault = _vault
    self.keeper = _keeper
    log VaultUpdated(vault=_vault)


@external
def set_vault(_vault: address):
    assert msg.sender == self.keeper, "ONLY_KEEPER"
    self.vault = _vault
    log VaultUpdated(vault=_vault)


@external
def return_to_vault(amount: uint256):
    assert msg.sender == self.keeper or msg.sender == self.vault, "ONLY_KEEPER"
    assert self.vault != empty(address), "NO_VAULT"
    assert staticcall ERC20Like(self.asset).balanceOf(self) >= amount, "BALANCE"
    assert extcall ERC20Like(self.asset).transfer(self.vault, amount), "TRANSFER"
    log AssetsReturned(vault=self.vault, amount=amount)


@external
def realize_loss(amount: uint256):
    assert msg.sender == self.keeper or msg.sender == self.vault, "ONLY_KEEPER"
    assert staticcall ERC20Like(self.asset).balanceOf(self) >= amount, "BALANCE"
    extcall ERC20Like(self.asset).burn(amount)
    log LossRealized(amount=amount)
