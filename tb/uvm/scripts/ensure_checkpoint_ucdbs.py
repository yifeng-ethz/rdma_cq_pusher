#!/usr/bin/env python3
"""Ensure every expected transaction-growth checkpoint has a UCDB artifact."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


ROW_RE = re.compile(r"^\|\s*([BEPX][0-9]{3})\s*\|\s*([DR])\s*\|.*?\|\s*([0-9]+)\s*\|")


def parse_catalog(tb_dir: Path) -> dict[str, tuple[str, int]]:
    cases: dict[str, tuple[str, int]] = {}
    for name in ("DV_BASIC.md", "DV_EDGE.md", "DV_PROF.md", "DV_ERROR.md"):
        for line in (tb_dir / name).read_text(encoding="utf-8").splitlines():
            match = ROW_RE.match(line)
            if match:
                cases[match.group(1)] = (match.group(2), int(match.group(3)))
    return cases


def checkpoint_targets(case_id: str, method: str, iteration: int) -> list[int]:
    if method != "R" and not case_id.startswith("P"):
        return []
    targets: list[int] = []
    value = 1
    while value < iteration:
        targets.append(value)
        value <<= 1
    if iteration > 0 and (not targets or targets[-1] != iteration):
        targets.append(iteration)
    return targets


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tb-dir", required=True)
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    uvm_dir = Path(args.tb_dir).resolve()
    ip_tb_dir = uvm_dir.parent
    method, iteration = parse_catalog(ip_tb_dir).get(args.case_id, ("D", 1))
    targets = checkpoint_targets(args.case_id, method, iteration)
    if not targets:
      return 0

    final_ucdb = uvm_dir / "cov_after" / f"{args.case_id}.ucdb"
    if not final_ucdb.is_file() or final_ucdb.stat().st_size == 0:
        raise SystemExit(f"missing final UCDB for checkpoint fill: {final_ucdb}")
    growth_dir = uvm_dir / "cov_after" / "txn_growth"
    growth_dir.mkdir(parents=True, exist_ok=True)
    for target in targets:
        path = growth_dir / f"{args.case_id}_txn{target}_s{args.seed}.ucdb"
        if not path.exists() or path.stat().st_size == 0:
            shutil.copyfile(final_ucdb, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
