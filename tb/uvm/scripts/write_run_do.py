#!/usr/bin/env python3
"""Write a per-case Questa do-file with final and checkpoint UCDB saves."""

from __future__ import annotations

import argparse
import re
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
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    tb_dir = Path(args.tb_dir).resolve()
    uvm_dir = tb_dir
    ip_tb_dir = uvm_dir.parent
    catalog = parse_catalog(ip_tb_dir)
    method, iteration = catalog.get(args.case_id, ("D", 1))
    final_ucdb = uvm_dir / "cov_after" / f"{args.case_id}.ucdb"
    growth_dir = uvm_dir / "cov_after" / "txn_growth"

    lines = [f"coverage save -onexit {final_ucdb}"]
    for target in checkpoint_targets(args.case_id, method, iteration):
        path = growth_dir / f"{args.case_id}_txn{target}_s{args.seed}.ucdb"
        lines.append(
            "when -label cp_{case}_{target} "
            "{{sim:/rdma_cq_pusher_tb_top/dut_if/cnt_cqe_posted == {target}}} "
            "{{coverage save {path}}}".format(
                case=args.case_id,
                target=target,
                path=path,
            )
        )
    lines.extend(["run -all", "quit -f"])

    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
