#!/usr/bin/env python3
"""Check the 88-note Goertzel wrapper simulation results."""

from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SIM_SRC_DIR = ROOT / "final_project_hardware.srcs" / "sim_1" / "new"
XSIM_DIR = ROOT / "final_project_hardware.sim" / "sim_1" / "behav" / "xsim"
EXPECTED_PATH = SIM_SRC_DIR / "all88_expected.csv"
SIM_LOG_PATH = XSIM_DIR / "all88_simulate.log"


def read_expected() -> list[tuple[int, int, int]]:
    rows: list[tuple[int, int, int]] = []
    with EXPECTED_PATH.open("r", encoding="ascii", newline="") as handle:
        for row in csv.DictReader(handle):
            rows.append(
                (
                    int(row["target_key"]),
                    int(row["expected_key"]),
                    int(row["expected_power"], 16),
                )
            )
    return rows


def main() -> None:
    expected = read_expected()
    text = SIM_LOG_PATH.read_text(encoding="ascii", errors="replace")

    hw_decisions = [
        (int(key), int(power, 16))
        for key, power in re.findall(r"HW_NOTE_DECISION key=(\d+) power=0x([0-9A-Fa-f]+)", text)
    ]
    observed_notes = [
        (int(target), int(observed))
        for target, observed in re.findall(r"ALL88_NOTE target=(\d+) observed=(\d+)", text)
    ]

    if len(expected) != 88:
        raise RuntimeError(f"Expected CSV has {len(expected)} rows, expected 88")
    if len(hw_decisions) != 88:
        raise RuntimeError(f"Simulation emitted {len(hw_decisions)} hardware decisions, expected 88")
    if len(observed_notes) != 88:
        raise RuntimeError(f"Simulation emitted {len(observed_notes)} observed-note reports, expected 88")

    mismatches: list[str] = []
    for index, ((target, expected_key, expected_power), (hw_key, hw_power), (reported_target, observed_key)) in enumerate(
        zip(expected, hw_decisions, observed_notes),
        start=1,
    ):
        if reported_target != target:
            mismatches.append(f"row {index}: report target {reported_target}, expected target {target}")
        if observed_key != hw_key:
            mismatches.append(f"target {target}: NOTE_KEY {observed_key}, HW report key {hw_key}")
        if hw_key != expected_key:
            mismatches.append(f"target {target}: hardware key {hw_key}, expected key {expected_key}")
        if hw_power != expected_power:
            mismatches.append(
                f"target {target}: hardware power 0x{hw_power:028X}, expected 0x{expected_power:028X}"
            )

    if mismatches:
        print("ALL88_MISMATCH")
        for mismatch in mismatches:
            print(mismatch)
        raise SystemExit(1)

    print("ALL88_TARGET_PASS count=88")
    print("ALL88_THEORY_MATCH decisions=88")


if __name__ == "__main__":
    main()
