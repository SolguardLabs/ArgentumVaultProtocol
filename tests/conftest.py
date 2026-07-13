from pathlib import Path

import boa
import pytest


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
USDC = 10**6
WAD = 10**18


def amount(units: int) -> int:
    return units * USDC


@pytest.fixture(autouse=True)
def isolated_chain():
    with boa.env.anchor():
        yield


@pytest.fixture
def actors():
    return {
        "owner": boa.env.generate_address("owner"),
        "keeper": boa.env.generate_address("keeper"),
        "strategist": boa.env.generate_address("strategist"),
        "alice": boa.env.generate_address("alice"),
        "bob": boa.env.generate_address("bob"),
        "carol": boa.env.generate_address("carol"),
        "redeemer": boa.env.generate_address("redeemer"),
        "receiver": boa.env.generate_address("receiver"),
    }


@pytest.fixture
def deployment(actors):
    token_blueprint = boa.load_partial(str(SRC / "mocks" / "MockStablecoin.vy"))
    vault_blueprint = boa.load_partial(str(SRC / "core" / "ArgentumVault.vy"))
    strategy_blueprint = boa.load_partial(str(SRC / "mocks" / "MockStrategy.vy"))

    token = token_blueprint.deploy()
    vault = vault_blueprint.deploy(
        token.address,
        actors["owner"],
        actors["keeper"],
        actors["strategist"],
    )
    strategy = strategy_blueprint.deploy(token.address, vault.address, actors["keeper"])

    return token, vault, strategy, actors


@pytest.fixture
def funded(deployment):
    token, vault, strategy, actors = deployment
    for key in ["alice", "bob", "carol", "redeemer"]:
        user = actors[key]
        token.mint(user, amount(2_000_000))
        token.approve(vault.address, 2**256 - 1, sender=user)
    return token, vault, strategy, actors


def deposit(vault, user, units: int) -> int:
    return vault.deposit(amount(units), user, sender=user)


def advance_to_epoch(vault, keeper, epoch: int) -> None:
    while vault.current_epoch() < epoch:
        vault.advance_epoch(sender=keeper)
