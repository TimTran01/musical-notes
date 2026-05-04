#!/usr/bin/env python3
"""Generate deterministic 88-note stimulus blocks for the Goertzel wrapper."""

from __future__ import annotations

import csv
import math
from pathlib import Path

from check_full_note_theory import (
    BANKS,
    BLOCK_SIZE,
    COEFF_BITS,
    POWER_BITS,
    SAMPLE_BITS,
    SRC_DIR,
    mask,
    read_hex_file,
    simulate_goertzel_block,
)


ROOT = Path(__file__).resolve().parent
SIM_SRC_DIR = ROOT / "final_project_hardware.srcs" / "sim_1" / "new"

SAMPLE_AMPLITUDE = 200_000
PHASE_STEPS = 512
BANK_SAMPLE_RATES = {
    3: 3_000.0,
    12: 12_000.0,
    48: 48_000.0,
}


def key_frequency(key: int) -> float:
    return 27.5 * (2.0 ** ((key - 1) / 12.0))


def bank_for_key(key: int) -> int:
    if key <= 24:
        return 3
    if key <= 52:
        return 12
    return 48


def to_hex24(value: int) -> str:
    return f"{value & mask(SAMPLE_BITS):06X}"


def read_coefficients() -> dict[int, list[int]]:
    coefficients: dict[int, list[int]] = {}
    for bank, (coeff_file, bin_count, _first_key) in BANKS.items():
        coeffs = read_hex_file(SRC_DIR / coeff_file, COEFF_BITS, signed=True)
        if len(coeffs) != bin_count:
            raise RuntimeError(f"{coeff_file} has {len(coeffs)} coefficients, expected {bin_count}")
        coefficients[bank] = coeffs
    return coefficients


def best_candidate(samples: list[int], bank: int, coefficients: dict[int, list[int]]) -> tuple[int, int]:
    _coeff_file, _bin_count, first_key = BANKS[bank]
    powers = simulate_goertzel_block(samples, coefficients[bank])
    best_bin = 0
    best_power = powers[0]
    for bin_index, power in enumerate(powers[1:], start=1):
        if power > best_power:
            best_bin = bin_index
            best_power = power
    return first_key + best_bin, best_power


def sine_block(key: int, phase: float) -> list[int]:
    bank = bank_for_key(key)
    rate = BANK_SAMPLE_RATES[bank]
    frequency = key_frequency(key)
    return [
        round(SAMPLE_AMPLITUDE * math.sin((2.0 * math.pi * frequency * sample_index / rate) + phase))
        for sample_index in range(BLOCK_SIZE)
    ]


def choose_phase(key: int, coefficients: dict[int, list[int]]) -> tuple[float, list[int], int]:
    bank = bank_for_key(key)
    best_seen: tuple[int, int, float, list[int]] | None = None

    for phase_step in range(PHASE_STEPS):
        phase = (2.0 * math.pi * phase_step) / PHASE_STEPS
        samples = sine_block(key, phase)
        candidate_key, candidate_power = best_candidate(samples, bank, coefficients)

        if best_seen is None or candidate_power > best_seen[1]:
            best_seen = (candidate_key, candidate_power, phase, samples)

        if candidate_key == key:
            return phase, samples, candidate_power

    assert best_seen is not None
    raise RuntimeError(
        f"No {PHASE_STEPS}-step phase produced key {key}; "
        f"best was key {best_seen[0]} with power 0x{best_seen[1]:0{POWER_BITS // 4}X}"
    )


def main() -> None:
    SIM_SRC_DIR.mkdir(parents=True, exist_ok=True)
    coefficients = read_coefficients()

    bank_samples: dict[int, list[list[int]]] = {3: [], 12: [], 48: []}
    expected_rows: list[dict[str, str]] = []

    for key in range(1, 89):
        active_bank = bank_for_key(key)
        phase, samples, power = choose_phase(key, coefficients)

        for bank in (3, 12, 48):
            bank_samples[bank].append(samples if bank == active_bank else [0] * BLOCK_SIZE)

        expected_rows.append(
            {
                "target_key": str(key),
                "bank": str(active_bank),
                "phase_radians": f"{phase:.12f}",
                "expected_key": str(key),
                "expected_power": f"{power:0{POWER_BITS // 4}X}",
            }
        )

    for bank, filename in (
        (3, "all88_bank3_samples.mem"),
        (12, "all88_bank12_samples.mem"),
        (48, "all88_bank48_samples.mem"),
    ):
        with (SIM_SRC_DIR / filename).open("w", encoding="ascii") as handle:
            for note_blocks in bank_samples[bank]:
                for sample in note_blocks:
                    handle.write(f"{to_hex24(sample)}\n")

    with (SIM_SRC_DIR / "all88_expected.csv").open("w", newline="", encoding="ascii") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["target_key", "bank", "phase_radians", "expected_key", "expected_power"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(expected_rows)

    print("Generated 88 note stimulus blocks")


if __name__ == "__main__":
    main()
