#!/usr/bin/env python3
"""Validate rdma_cq_pusher DEBUG scorecards from Phase B regressions."""

import argparse
import json
import pathlib
import sys


INT_KEYS = (
    "accepted_cqes",
    "host_writes",
    "b_okay",
    "lineage_expected",
    "lineage_actual",
    "mismatch_count",
)


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scorecards", nargs="+", required=True)
    parser.add_argument("--require-lineage", action="append", default=[])
    return parser.parse_args()


def load_scorecard(path):
    scorecard_path = pathlib.Path(path)
    if not scorecard_path.is_file():
        raise ValueError(f"missing scorecard {scorecard_path}")
    if scorecard_path.stat().st_size == 0:
        raise ValueError(f"empty scorecard {scorecard_path}")
    with scorecard_path.open("r", encoding="ascii") as handle:
        data = json.load(handle)
    if "case_id" not in data:
        raise ValueError(f"{scorecard_path}: missing case_id")
    for key in INT_KEYS:
        if key not in data or not isinstance(data[key], int):
            raise ValueError(f"{scorecard_path}: missing integer key {key}")
    if "lineage" not in data or not isinstance(data["lineage"], list):
        raise ValueError(f"{scorecard_path}: missing lineage list")
    return scorecard_path, data


def validate_lineage(scorecard_path, data):
    for idx, entry in enumerate(data["lineage"]):
        for key in ("slot", "sqe_id", "retire_seq", "meta"):
            if key not in entry:
                raise ValueError(f"{scorecard_path}: lineage[{idx}] missing {key}")
        meta = entry["meta"]
        if not isinstance(meta, str) or len(meta) != 16:
            raise ValueError(f"{scorecard_path}: lineage[{idx}] has bad meta {meta!r}")
        int(meta, 16)


def validate_scorecard(scorecard_path, data, require_lineage):
    case_id = data["case_id"]
    if data["mismatch_count"] != 0:
        raise ValueError(
            f"{scorecard_path}: mismatch_count={data['mismatch_count']}"
        )
    if data["accepted_cqes"] > data["host_writes"]:
        raise ValueError(
            f"{scorecard_path}: accepted_cqes={data['accepted_cqes']} "
            f"host_writes={data['host_writes']}"
        )
    if data["host_writes"] < data["b_okay"]:
        raise ValueError(
            f"{scorecard_path}: host_writes={data['host_writes']} "
            f"b_okay={data['b_okay']}"
        )
    if data["lineage_expected"] != data["lineage_actual"]:
        raise ValueError(
            f"{scorecard_path}: lineage_expected={data['lineage_expected']} "
            f"lineage_actual={data['lineage_actual']}"
        )
    if case_id in require_lineage and data["lineage_expected"] == 0:
        raise ValueError(f"{scorecard_path}: required lineage is empty")
    if len(data["lineage"]) != data["lineage_expected"]:
        raise ValueError(
            f"{scorecard_path}: lineage list length={len(data['lineage'])} "
            f"expected={data['lineage_expected']}"
        )
    validate_lineage(scorecard_path, data)


def main():
    args = parse_args()
    require_lineage = set(args.require_lineage)
    seen_cases = set()

    try:
        for path in args.scorecards:
            scorecard_path, data = load_scorecard(path)
            case_id = data["case_id"]
            if case_id in seen_cases:
                raise ValueError(f"duplicate case_id {case_id}")
            seen_cases.add(case_id)
            validate_scorecard(scorecard_path, data, require_lineage)
            print(
                "PASS {case}: accepted={accepted} host_writes={host} "
                "lineage={lineage} mismatches=0".format(
                    case=case_id,
                    accepted=data["accepted_cqes"],
                    host=data["host_writes"],
                    lineage=data["lineage_expected"],
                )
            )
    except (OSError, ValueError, json.JSONDecodeError) as err:
        return fail(str(err))

    missing = require_lineage - seen_cases
    if missing:
        return fail("missing required lineage cases: " + " ".join(sorted(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
