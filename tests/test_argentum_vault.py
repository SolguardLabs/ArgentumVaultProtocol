import boa

from conftest import USDC, WAD, advance_to_epoch, amount, deposit


def test_deposits_mint_shares_and_seed_internal_reserve(funded):
    token, vault, _strategy, actors = funded
    alice = actors["alice"]
    bob = actors["bob"]

    alice_shares = deposit(vault, alice, 1_000_000)
    bob_shares = deposit(vault, bob, 1_000_000)

    assert alice_shares == amount(1_000_000)
    assert bob_shares == amount(1_000_000)
    assert vault.balanceOf(alice) == amount(1_000_000)
    assert vault.balanceOf(bob) == amount(1_000_000)
    assert vault.totalSupply() == amount(2_000_000)
    assert vault.total_assets() == amount(2_000_000)
    assert vault.reserve_liquidity() == amount(400_000)
    assert vault.free_liquidity() == amount(1_600_000)
    assert vault.price_per_share() == WAD
    assert token.balanceOf(vault.address) == amount(2_000_000)


def test_withdrawal_request_executes_after_epoch_delay(funded):
    token, vault, _strategy, actors = funded
    alice = actors["alice"]
    bob = actors["bob"]
    keeper = actors["keeper"]

    deposit(vault, alice, 1_000_000)
    deposit(vault, bob, 1_000_000)

    request_id = vault.request_withdrawal(amount(100_000), alice, sender=alice)
    req = vault.requests(request_id)

    assert request_id == 1
    assert req.owner == alice
    assert req.receiver == alice
    assert req.epoch == 2
    assert req.shares == amount(100_000)
    assert req.quoted_assets == amount(100_000)
    assert req.snapshot_pps == WAD
    assert vault.balanceOf(alice) == amount(900_000)
    assert vault.escrowed_shares() == amount(100_000)
    assert vault.withdrawal_liabilities() == amount(100_000)

    with boa.reverts("FUTURE_EPOCH"):
        vault.process_epoch(2, 1, sender=keeper)

    vault.advance_epoch(sender=keeper)
    processed = vault.process_epoch(2, 1, sender=keeper)
    req_after = vault.requests(request_id)

    assert processed == 1
    assert req_after.status == 2
    assert req_after.paid_assets == amount(100_000)
    assert token.balanceOf(alice) == amount(1_100_000)
    assert vault.totalSupply() == amount(1_900_000)
    assert vault.escrowed_shares() == 0
    assert vault.withdrawal_liabilities() == 0
    assert vault.free_liquidity() == amount(1_500_000)
    assert vault.reserve_liquidity() == amount(400_000)


def test_batch_execution_processes_epoch_cursor_in_chunks(funded):
    token, vault, _strategy, actors = funded
    keeper = actors["keeper"]
    alice = actors["alice"]
    bob = actors["bob"]
    carol = actors["carol"]

    deposit(vault, alice, 600_000)
    deposit(vault, bob, 600_000)
    deposit(vault, carol, 600_000)

    first = vault.request_withdrawal(amount(50_000), alice, sender=alice)
    second = vault.request_withdrawal(amount(80_000), bob, sender=bob)
    third = vault.request_withdrawal(amount(120_000), carol, sender=carol)

    vault.advance_epoch(sender=keeper)
    assert vault.process_epoch(2, 2, sender=keeper) == 2

    epoch_state = vault.epochs(2)
    assert epoch_state.first_request_id == first
    assert epoch_state.last_request_id == third
    assert epoch_state.processed_until == second
    assert epoch_state.pending_assets == amount(120_000)
    assert epoch_state.processed_count == 2
    assert not epoch_state.closed
    assert token.balanceOf(alice) == amount(1_450_000)
    assert token.balanceOf(bob) == amount(1_480_000)
    assert token.balanceOf(carol) == amount(1_400_000)

    assert vault.process_epoch(2, 2, sender=keeper) == 1
    final_epoch = vault.epochs(2)
    assert final_epoch.processed_until == third
    assert final_epoch.pending_assets == 0
    assert final_epoch.processed_count == 3
    assert final_epoch.closed
    assert token.balanceOf(carol) == amount(1_520_000)


def test_liquidity_allocation_return_and_loss_update_nav(funded):
    token, vault, strategy, actors = funded
    strategist = actors["strategist"]
    keeper = actors["keeper"]
    alice = actors["alice"]
    bob = actors["bob"]

    deposit(vault, alice, 1_000_000)
    deposit(vault, bob, 1_000_000)

    vault.allocate_to_strategy(strategy.address, amount(1_000_000), sender=strategist)
    assert vault.free_liquidity() == amount(600_000)
    assert vault.reserve_liquidity() == amount(400_000)
    assert vault.strategy_assets() == amount(1_000_000)
    assert token.balanceOf(strategy.address) == amount(1_000_000)
    assert token.balanceOf(vault.address) == amount(1_000_000)

    strategy.return_to_vault(amount(100_000), sender=keeper)
    vault.note_strategy_return(strategy.address, amount(100_000), sender=strategist)
    assert vault.strategy_assets() == amount(900_000)
    assert vault.total_assets() == amount(2_000_000)
    assert vault.price_per_share() == WAD
    assert token.balanceOf(vault.address) == amount(1_100_000)

    strategy.realize_loss(amount(250_000), sender=keeper)
    vault.report_strategy_loss(strategy.address, amount(250_000), sender=strategist)
    assert vault.strategy_assets() == amount(650_000)
    assert vault.total_assets() == amount(1_750_000)
    assert vault.price_per_share() == 875_000_000_000_000_000


def test_snapshot_epoch_quote_uses_reserve_after_intervening_loss(funded):
    token, vault, strategy, actors = funded
    victim = actors["alice"]
    redeemer = actors["redeemer"]
    keeper = actors["keeper"]
    strategist = actors["strategist"]

    deposit(vault, victim, 1_000_000)
    deposit(vault, redeemer, 100_000)
    vault.allocate_to_strategy(strategy.address, amount(850_000), sender=strategist)

    assert vault.free_liquidity() == amount(30_000)
    assert vault.reserve_liquidity() == amount(220_000)
    assert vault.strategy_assets() == amount(850_000)
    assert vault.price_per_share() == WAD

    request_id = vault.request_withdrawal(amount(100_000), redeemer, sender=redeemer)
    queued = vault.requests(request_id)
    assert queued.quoted_assets == amount(100_000)
    assert queued.snapshot_pps == WAD

    strategy.realize_loss(amount(550_000), sender=keeper)
    vault.report_strategy_loss(strategy.address, amount(550_000), sender=strategist)
    assert vault.total_assets() == amount(550_000)
    assert vault.price_per_share() == 500_000_000_000_000_000

    current_value = vault.request_value_at_current_pps(request_id)
    premium = vault.request_quote_delta(request_id)
    assert current_value == amount(50_000)
    assert premium == amount(50_000)

    vault.advance_epoch(sender=keeper)
    before_redeemer = token.balanceOf(redeemer)
    processed = vault.process_epoch(2, 1, sender=keeper)

    assert processed == 1
    assert token.balanceOf(redeemer) - before_redeemer == amount(100_000)
    assert vault.reserve_liquidity() == amount(150_000)
    assert vault.free_liquidity() == 0
    assert vault.total_assets() == amount(450_000)
    assert vault.totalSupply() == amount(1_000_000)
    assert vault.convert_to_assets(vault.balanceOf(victim)) == amount(450_000)
    assert vault.requests(request_id).paid_assets == amount(100_000)
    assert vault.requests(request_id).paid_assets - current_value == amount(50_000)
