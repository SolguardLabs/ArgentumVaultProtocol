from pathlib import Path

import boa


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def test_stress_engine_models_loss_recall_and_queue_pressure(actors):
    engine = boa.load(str(SRC / "risk" / "ArgentumStressEngine.vy"), actors["owner"])
    result = engine.evaluate(
        1_000_000,
        1_000_000,
        200_000,
        200_000,
        600_000,
        500_000,
        2_000,
        5_000,
    )
    assert result.assets_after_shock == 880_000
    assert result.liquid_after_recall == 640_000
    assert result.queue_shortfall == 0
    assert result.reserve_after_queue == 140_000
    assert result.pps_after_shock == 880_000_000_000_000_000
    assert result.liquidity_bps == 7_272


def test_stress_engine_rejects_inconsistent_accounting(actors):
    engine = boa.load(str(SRC / "risk" / "ArgentumStressEngine.vy"), actors["owner"])
    with boa.reverts("ACCOUNTING"):
        engine.evaluate(999, 1_000, 200, 200, 600, 100, 100, 100)


def test_stress_engine_buffer_and_recall_math(actors):
    engine = boa.load(str(SRC / "risk" / "ArgentumStressEngine.vy"), actors["owner"])
    assert engine.loss_capacity(800_000, 1_250) == 100_000
    assert engine.required_recall(100_000, 250_000, 400_000, 100_000) == 150_000
    assert engine.queue_coverage_bps(300_000, 600_000) == 5_000
    assert engine.concentration_bps(600_000, 1_000_000) == 6_000
    assert engine.minimum_liquid_buffer(1_000_000, 1_000, 200_000, 15_000) == 400_000


def test_checkpoint_registry_requires_quorum_and_preserves_hash_chain(actors):
    owner = actors["owner"]
    reporter_a = actors["alice"]
    reporter_b = actors["bob"]
    registry = boa.load(str(SRC / "security" / "ArgentumCheckpointRegistry.vy"), owner, 2)
    registry.set_reporter(reporter_a, True, sender=owner)
    registry.set_reporter(reporter_b, True, sender=owner)

    payload_one = boa.eval('keccak256("epoch-one")')
    digest_one = registry.submit_checkpoint(
        1, 1_000_000, 900_000, 400_000, 100_000, payload_one, sender=reporter_a
    )
    assert registry.pending_approvals(1) == 1
    assert not registry.is_finalized(1)
    registry.approve_checkpoint(1, sender=reporter_b)
    assert registry.is_finalized(1)
    assert registry.latest_finalized_hash() == digest_one
    assert registry.verifies(1)

    payload_two = boa.eval('keccak256("epoch-two")')
    digest_two = registry.submit_checkpoint(
        2, 980_000, 900_000, 350_000, 80_000, payload_two, sender=reporter_b
    )
    checkpoint_two = registry.checkpoints(2)
    assert checkpoint_two.previous_hash == digest_one
    registry.approve_checkpoint(2, sender=reporter_a)
    assert registry.latest_finalized_hash() == digest_two


def test_checkpoint_registry_rejects_duplicate_approval(actors):
    owner = actors["owner"]
    reporter_a = actors["alice"]
    reporter_b = actors["bob"]
    registry = boa.load(str(SRC / "security" / "ArgentumCheckpointRegistry.vy"), owner, 2)
    registry.set_reporter(reporter_a, True, sender=owner)
    registry.set_reporter(reporter_b, True, sender=owner)
    payload = boa.eval('keccak256("payload")')
    registry.submit_checkpoint(1, 100, 100, 50, 10, payload, sender=reporter_a)
    with boa.reverts("ALREADY_APPROVED"):
        registry.approve_checkpoint(1, sender=reporter_a)


def test_parameter_store_enforces_bounds_and_timelock(actors):
    owner = actors["owner"]
    store = boa.load(str(SRC / "governance" / "ArgentumParameterStore.vy"), owner, 3_600)
    key = store.reserve_target_key()
    store.initialize_parameter(key, 2_000, 500, 4_000, sender=owner)
    assert store.current_value(key) == 2_000
    assert store.within_bounds(key, 3_000)
    assert not store.within_bounds(key, 4_001)
    store.stage_parameter(key, 2_500, sender=owner)
    with boa.reverts("TIMELOCK"):
        store.commit_parameter(key, sender=owner)
    boa.env.time_travel(seconds=3_600)
    store.commit_parameter(key, sender=owner)
    assert store.current_value(key) == 2_500
