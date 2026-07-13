# @version ^0.4.3

"""
Mock stablecoin used by the ArgentumVaultProtocol tests.

The token is intentionally simple so local scenarios can focus on vault
accounting rather than token permissions. Decimals are six to match a USDC-like
asset and to make withdrawal queue arithmetic easy to inspect.
"""

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

name: public(String[64])
symbol: public(String[16])
decimals: public(uint8)
totalSupply: public(uint256)

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])


@deploy
def __init__():
    self.name = "Argentum Mock USD"
    self.symbol = "aUSD"
    self.decimals = 6


@external
def mint(receiver: address, amount: uint256):
    assert receiver != empty(address), "ZERO_RECEIVER"
    self.totalSupply += amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=empty(address), receiver=receiver, value=amount)


@external
def burn(amount: uint256):
    assert self.balanceOf[msg.sender] >= amount, "BALANCE"
    self.balanceOf[msg.sender] -= amount
    self.totalSupply -= amount
    log Transfer(sender=msg.sender, receiver=empty(address), value=amount)


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
def transferFrom(owner: address, receiver: address, amount: uint256) -> bool:
    assert owner != empty(address), "ZERO_OWNER"
    assert receiver != empty(address), "ZERO_RECEIVER"
    allowed: uint256 = self.allowance[owner][msg.sender]
    assert allowed >= amount, "ALLOWANCE"
    assert self.balanceOf[owner] >= amount, "BALANCE"

    if allowed != max_value(uint256):
        self.allowance[owner][msg.sender] = allowed - amount
        log Approval(owner=owner, spender=msg.sender, value=self.allowance[owner][msg.sender])

    self.balanceOf[owner] -= amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=owner, receiver=receiver, value=amount)
    return True
