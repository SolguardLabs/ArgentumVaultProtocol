# @version ^0.4.3

"""
Accounting reporter for NAV checkpoints.

Reports are descriptive so operators can compare expected NAV, reserve buffers,
and queue pressure before keeper execution.
"""

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000

struct NavReport:
    exists: bool
    reporter: address
    total_assets: uint256
    free_liquidity: uint256
    reserve_liquidity: uint256
    strategy_assets: uint256
    withdrawal_liabilities: uint256
    total_supply: uint256
    price_per_share: uint256
    reported_at: uint256

event ReporterUpdated:
    reporter: indexed(address)
    authorized: bool

event ReportSubmitted:
    epoch: indexed(uint256)
    reporter: indexed(address)
    total_assets: uint256
    price_per_share: uint256

event ReportInvalidated:
    epoch: indexed(uint256)

owner: public(address)
authorized_reporter: public(HashMap[address, bool])
reports: public(HashMap[uint256, NavReport])
latest_epoch: public(uint256)


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.authorized_reporter[_owner] = True


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _only_reporter():
    assert self.authorized_reporter[msg.sender] or msg.sender == self.owner, "REPORTER"


@internal
@pure
def _pps(total_assets: uint256, total_supply: uint256) -> uint256:
    if total_supply == 0:
        return WAD
    return total_assets * WAD // total_supply


@internal
@pure
def _ratio_bps(part: uint256, whole: uint256) -> uint256:
    if whole == 0:
        return 0
    return part * BPS // whole


@external
def set_reporter(reporter: address, authorized: bool):
    self._only_owner()
    assert reporter != empty(address), "ZERO_REPORTER"
    self.authorized_reporter[reporter] = authorized
    log ReporterUpdated(reporter=reporter, authorized=authorized)


@external
def submit_report(
    epoch: uint256,
    total_assets: uint256,
    free_liquidity: uint256,
    reserve_liquidity: uint256,
    strategy_assets: uint256,
    withdrawal_liabilities: uint256,
    total_supply: uint256,
):
    self._only_reporter()
    assert total_assets == free_liquidity + reserve_liquidity + strategy_assets, "ASSET_SUM"
    pps: uint256 = self._pps(total_assets, total_supply)
    self.reports[epoch] = NavReport(
        exists=True,
        reporter=msg.sender,
        total_assets=total_assets,
        free_liquidity=free_liquidity,
        reserve_liquidity=reserve_liquidity,
        strategy_assets=strategy_assets,
        withdrawal_liabilities=withdrawal_liabilities,
        total_supply=total_supply,
        price_per_share=pps,
        reported_at=block.timestamp,
    )
    if epoch > self.latest_epoch:
        self.latest_epoch = epoch
    log ReportSubmitted(epoch=epoch, reporter=msg.sender, total_assets=total_assets, price_per_share=pps)


@external
def invalidate_report(epoch: uint256):
    self._only_owner()
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    report.exists = False
    self.reports[epoch] = report
    log ReportInvalidated(epoch=epoch)


@external
@view
def report_exists(epoch: uint256) -> bool:
    return self.reports[epoch].exists


@external
@view
def asset_delta(from_epoch: uint256, to_epoch: uint256) -> int256:
    start: NavReport = self.reports[from_epoch]
    end: NavReport = self.reports[to_epoch]
    assert start.exists and end.exists, "NO_REPORT"
    if end.total_assets >= start.total_assets:
        return convert(end.total_assets - start.total_assets, int256)
    return -convert(start.total_assets - end.total_assets, int256)


@external
@view
def pps_delta(from_epoch: uint256, to_epoch: uint256) -> int256:
    start: NavReport = self.reports[from_epoch]
    end: NavReport = self.reports[to_epoch]
    assert start.exists and end.exists, "NO_REPORT"
    if end.price_per_share >= start.price_per_share:
        return convert(end.price_per_share - start.price_per_share, int256)
    return -convert(start.price_per_share - end.price_per_share, int256)


@external
@view
def loss_between(from_epoch: uint256, to_epoch: uint256) -> uint256:
    start: NavReport = self.reports[from_epoch]
    end: NavReport = self.reports[to_epoch]
    assert start.exists and end.exists, "NO_REPORT"
    if start.total_assets > end.total_assets:
        return start.total_assets - end.total_assets
    return 0


@external
@view
def reserve_ratio(epoch: uint256) -> uint256:
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    return self._ratio_bps(report.reserve_liquidity, report.total_assets)


@external
@view
def strategy_ratio(epoch: uint256) -> uint256:
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    return self._ratio_bps(report.strategy_assets, report.total_assets)


@external
@view
def liability_ratio(epoch: uint256) -> uint256:
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    return self._ratio_bps(report.withdrawal_liabilities, report.total_assets)


@external
@view
def liquid_coverage(epoch: uint256) -> uint256:
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    if report.withdrawal_liabilities == 0:
        return BPS
    coverage: uint256 = (report.free_liquidity + report.reserve_liquidity) * BPS // report.withdrawal_liabilities
    if coverage > BPS:
        return BPS
    return coverage


@external
@view
def report_tuple(epoch: uint256) -> (uint256, uint256, uint256, uint256, uint256, uint256):
    report: NavReport = self.reports[epoch]
    assert report.exists, "NO_REPORT"
    return (
        report.total_assets,
        report.free_liquidity,
        report.reserve_liquidity,
        report.strategy_assets,
        report.withdrawal_liabilities,
        report.price_per_share,
    )
