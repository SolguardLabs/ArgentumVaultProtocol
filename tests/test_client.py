from client.argentum_client import ArgentumClient, BPS


class FakeVault:
    def total_assets(self): return 1_000
    def liquid_assets(self): return 400
    def free_liquidity(self): return 250
    def reserve_liquidity(self): return 150
    def strategy_assets(self): return 600
    def withdrawal_liabilities(self): return 120
    def totalSupply(self): return 900
    def price_per_share(self): return 1_111_111_111_111_111_111
    def current_epoch(self): return 7
    def epochs(self, _epoch): return (10, 14, 11, 300, 330, 120, 2, False)
    def requests(self, _request_id):
        return ("0x01", "0x02", 7, 100, 110, 10**18, 50, 0, 0, 1)


def test_client_reconciles_snapshot_and_ratios():
    snapshot = ArgentumClient(FakeVault()).snapshot()
    assert snapshot.reconciles()
    assert snapshot.liquid_ratio_bps == 4_000
    assert snapshot.reserve_ratio_bps == 1_500
    assert snapshot.strategy_ratio_bps == 6_000


def test_client_maps_epoch_and_request_state():
    client = ArgentumClient(FakeVault())
    epoch = client.epoch(7)
    request = client.request(12)
    assert epoch.remaining_items == 3
    assert request.is_mature(7)
    assert request.quoted_assets == 110


def test_epoch_plan_protects_configured_reserve_buffer():
    plan = ArgentumClient.plan_epoch(500, 250, 300, 100)
    assert plan.immediately_available == 550
    assert plan.protected_reserve == 100
    assert plan.processable_assets == 450
    assert plan.recall_required == 50
    assert plan.coverage_bps == 9_000


def test_empty_epoch_has_full_coverage():
    plan = ArgentumClient.plan_epoch(0, 0, 0, 0)
    assert plan.coverage_bps == BPS
    assert plan.processable_assets == 0


def test_batch_planning_honors_gas_and_protocol_caps():
    assert ArgentumClient.suggested_batch(200, 4_000_000, 50_000) == 80
    assert ArgentumClient.suggested_batch(200, 20_000_000, 50_000) == 128
    assert ArgentumClient.suggested_batch(12, 20_000_000, 50_000) == 12
