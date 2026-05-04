#!/usr/bin/env python3
"""Compare full-path simulation output against an independent Goertzel model."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SRC_DIR = ROOT / "final_project_hardware.srcs" / "sources_1" / "new"
XSIM_DIR = ROOT / "final_project_hardware.sim" / "sim_1" / "behav" / "xsim"
TRACE_PATH = XSIM_DIR / "full_note_detector_trace.log"
SIM_LOG_PATH = XSIM_DIR / "full_design_simulate.log"

SAMPLE_BITS = 24
COEFF_BITS = 32
COEFF_FRAC_BITS = 30
STATE_BITS = 56
POWER_BITS = 112
BLOCK_SIZE = 128

BANKS = {
    3: ("goertzel_bank1_coeff.mem", 24, 1),
    12: ("goertzel_bank2_coeff.mem", 24, 25),
    48: ("goertzel_bank3_coeff.mem", 40, 49),
}


def mask(bits: int) -> int:
    return (1 << bits) - 1


def to_signed(value: int, bits: int) -> int:
    value &= mask(bits)
    sign_bit = 1 << (bits - 1)
    if value & sign_bit:
        value -= 1 << bits
    return value


def read_hex_file(path: Path, bits: int, signed: bool) -> list[int]:
    values: list[int] = []
    with path.open("r", encoding="ascii") as handle:
        for line in handle:
            word = line.strip()
            if not word:
                continue
            value = int(word, 16)
            values.append(to_signed(value, bits) if signed else value & mask(bits))
    return values


def simulate_goertzel_block(samples: list[int], coefficients: list[int]) -> list[int]:
    powers: list[int] = []

    for coefficient in coefficients:
        q1 = 0
        q2 = 0

        for sample in samples:
            coeff_term = to_signed((q1 * coefficient) >> COEFF_FRAC_BITS, STATE_BITS)
            q0 = to_signed(to_signed(sample, STATE_BITS) + coeff_term - q2, STATE_BITS)
            q2 = q1
            q1 = q0

        q1_square = q1 * q1
        q2_square = q2 * q2
        cross_term = (q1 * q2 * coefficient) >> COEFF_FRAC_BITS
        power = q1_square + q2_square - cross_term
        if power < 0:
            power = 0
        powers.append(power & mask(POWER_BITS))

    return powers


def best_candidate(samples: list[int], bank: int) -> tuple[int, int]:
    coeff_file, bin_count, first_key = BANKS[bank]
    coefficients = read_hex_file(SRC_DIR / coeff_file, COEFF_BITS, signed=True)
    if len(coefficients) != bin_count:
        raise RuntimeError(f"{coeff_file} has {len(coefficients)} coefficients, expected {bin_count}")

    powers = simulate_goertzel_block(samples, coefficients)
    best_bin = 0
    best_power = powers[0]
    for bin_index, power in enumerate(powers[1:], start=1):
        if power > best_power:
            best_bin = bin_index
            best_power = power
    return first_key + best_bin, best_power


def parse_hw_decision() -> tuple[int, int]:
    log_path = SIM_LOG_PATH if SIM_LOG_PATH.exists() else XSIM_DIR / "simulate.log"
    text = log_path.read_text(encoding="ascii", errors="replace")
    match = re.search(r"HW_NOTE_DECISION key=(\d+) power=0x([0-9A-Fa-f]+)", text)
    if not match:
        raise RuntimeError(f"No HW_NOTE_DECISION line found in {log_path}")
    return int(match.group(1)), int(match.group(2), 16)


def main() -> None:
    if not TRACE_PATH.exists():
        raise SystemExit(f"Missing trace file: {TRACE_PATH}")

    ram: dict[int, list[int | None]] = {3: [None] * 4096, 12: [None] * 4096, 48: [None] * 4096}
    done_count = {3: 0, 12: 0, 48: 0}
    latest: dict[int, tuple[int, int] | None] = {3: None, 12: None, 48: None}
    expected_decisions: list[tuple[int, int]] = []
    observed_notes: list[int] = []

    with TRACE_PATH.open("r", encoding="ascii") as trace:
        for line in trace:
            parts = line.split()
            if not parts:
                continue

            if parts[0] == "WRITE":
                bank = int(parts[1])
                address = int(parts[3], 16)
                data = to_signed(int(parts[4], 16), SAMPLE_BITS)
                ram[bank][address] = data
            elif parts[0] == "GDONE":
                bank = int(parts[1])
                block_index = done_count[bank]
                start = block_index * BLOCK_SIZE
                stop = start + BLOCK_SIZE
                block = ram[bank][start:stop]
                if any(sample is None for sample in block):
                    raise RuntimeError(f"Bank {bank} block {block_index} completed before all samples were written")

                latest[bank] = best_candidate([int(sample) for sample in block], bank)
                done_count[bank] += 1
            elif parts[0] == "NOTE":
                observed_notes.append(int(parts[2]))
                if any(value is None for value in latest.values()):
                    raise RuntimeError("NOTE emitted before all theoretical bank candidates were available")

                winner_key, winner_power = latest[3]  # type: ignore[index]
                for bank in (12, 48):
                    candidate_key, candidate_power = latest[bank]  # type: ignore[index]
                    if candidate_power > winner_power:
                        winner_key = candidate_key
                        winner_power = candidate_power
                expected_decisions.append((winner_key, winner_power))

    if not expected_decisions:
        raise RuntimeError("Trace contained no NOTE decision")

    expected_key, expected_power = expected_decisions[0]
    observed_key = observed_notes[0]
    hw_key, hw_power = parse_hw_decision()

    if observed_key != expected_key:
        raise RuntimeError(f"NOTE_KEY mismatch: observed {observed_key}, expected {expected_key}")
    if hw_key != expected_key:
        raise RuntimeError(f"HW decision key mismatch: hardware {hw_key}, expected {expected_key}")
    if hw_power != expected_power:
        raise RuntimeError(
            f"HW winner power mismatch: hardware 0x{hw_power:028X}, expected 0x{expected_power:028X}"
        )

    print(f"THEORY_MATCH key={expected_key} power=0x{expected_power:028X}")


if __name__ == "__main__":
    main()
