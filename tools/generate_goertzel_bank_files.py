#!/usr/bin/env python3
"""Generate Goertzel coefficient and simulation files for all three banks."""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "final_project_hardware" / "final_project_hardware.srcs" / "sources_1" / "new"
SIM_DIR = ROOT / "final_project_hardware" / "final_project_hardware.srcs" / "sim_1" / "new"

SAMPLE_BITS = 24
COEFF_BITS = 32
COEFF_FRAC_BITS = 30
STATE_BITS = 56
POWER_BITS = 112
BLOCK_SIZE = 128
TEST_BLOCK_COUNT = 3


@dataclass(frozen=True)
class BankConfig:
    bank_id: int
    first_key: int
    last_key: int
    sample_rate_hz: float

    @property
    def bin_count(self) -> int:
        return self.last_key - self.first_key + 1


BANKS = (
    BankConfig(bank_id=1, first_key=1, last_key=24, sample_rate_hz=3000.0),
    BankConfig(bank_id=2, first_key=25, last_key=48, sample_rate_hz=12000.0),
    BankConfig(bank_id=3, first_key=49, last_key=88, sample_rate_hz=48000.0),
)


def mask(bits: int) -> int:
    return (1 << bits) - 1


def to_signed_range(value: int, bits: int) -> int:
    value &= mask(bits)
    sign_bit = 1 << (bits - 1)
    if value & sign_bit:
        value -= 1 << bits
    return value


def to_hex(value: int, bits: int) -> str:
    return f"{value & mask(bits):0{bits // 4}X}"


def piano_frequency_hz(piano_key: int) -> float:
    return 440.0 * (2.0 ** ((piano_key - 49) / 12.0))


def coefficient_q2_30(frequency_hz: float, sample_rate_hz: float) -> int:
    coefficient = 2.0 * math.cos(2.0 * math.pi * frequency_hz / sample_rate_hz)
    return to_signed_range(round(coefficient * (1 << COEFF_FRAC_BITS)), COEFF_BITS)


def coefficients_for_bank(bank: BankConfig) -> list[int]:
    return [
        coefficient_q2_30(piano_frequency_hz(key), bank.sample_rate_hz)
        for key in range(bank.first_key, bank.last_key + 1)
    ]


def sine_block(frequency_hz: float, sample_rate_hz: float, amplitude: int) -> list[int]:
    samples: list[int] = []
    for sample_index in range(BLOCK_SIZE):
        phase = 2.0 * math.pi * frequency_hz * sample_index / sample_rate_hz
        samples.append(to_signed_range(round(amplitude * math.sin(phase)), SAMPLE_BITS))
    return samples


def mixed_block(bank: BankConfig) -> list[int]:
    samples: list[int] = []
    f_low = piano_frequency_hz(bank.first_key + min(4, bank.bin_count - 1))
    f_high = piano_frequency_hz(bank.first_key + min(11, bank.bin_count - 1))

    for sample_index in range(BLOCK_SIZE):
        t = sample_index / bank.sample_rate_hz
        value = (
            90000.0 * math.sin(2.0 * math.pi * f_low * t)
            - 45000.0 * math.sin(2.0 * math.pi * f_high * t)
            + ((sample_index % 17) - 8) * 1200.0
        )
        samples.append(to_signed_range(round(value), SAMPLE_BITS))

    return samples


def sample_blocks_for_bank(bank: BankConfig) -> list[list[int]]:
    return [
        sine_block(piano_frequency_hz(bank.first_key), bank.sample_rate_hz, 120000),
        sine_block(piano_frequency_hz(bank.last_key), bank.sample_rate_hz, 120000),
        mixed_block(bank),
    ]


def simulate_goertzel_block(samples: list[int], coefficients: list[int]) -> list[int]:
    powers: list[int] = []

    for coefficient in coefficients:
        q1 = 0
        q2 = 0

        for sample in samples:
            coeff_term = to_signed_range((q1 * coefficient) >> COEFF_FRAC_BITS, STATE_BITS)
            q0 = to_signed_range(to_signed_range(sample, STATE_BITS) + coeff_term - q2, STATE_BITS)
            q2 = q1
            q1 = q0

        square_sum = q1 * q1 + q2 * q2
        cross_term = (q1 * q2 * coefficient) >> COEFF_FRAC_BITS
        power = square_sum - cross_term

        if power < 0:
            power = 0

        powers.append(power & mask(POWER_BITS))

    return powers


def write_coefficients(bank: BankConfig, coefficients: list[int]) -> Path:
    path = SOURCE_DIR / f"goertzel_bank{bank.bank_id}_coeff.mem"
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="ascii") as mem_file:
        for coefficient in coefficients:
            mem_file.write(f"{to_hex(coefficient, COEFF_BITS)}\n")

    return path


def write_samples(bank: BankConfig, blocks: list[list[int]]) -> Path:
    path = SIM_DIR / f"goertzel_bank{bank.bank_id}_samples.mem"
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="ascii") as mem_file:
        for block in blocks:
            for sample in block:
                mem_file.write(f"{to_hex(sample, SAMPLE_BITS)}\n")

    return path


def write_expected(bank: BankConfig, blocks: list[list[int]], coefficients: list[int]) -> Path:
    path = SIM_DIR / f"goertzel_bank{bank.bank_id}_expected_power.mem"
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="ascii") as mem_file:
        for block in blocks:
            for power in simulate_goertzel_block(block, coefficients):
                mem_file.write(f"{to_hex(power, POWER_BITS)}\n")

    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()

    for bank in BANKS:
        coefficients = coefficients_for_bank(bank)
        sample_blocks = sample_blocks_for_bank(bank)
        coeff_path = write_coefficients(bank, coefficients)
        sample_path = write_samples(bank, sample_blocks)
        expected_path = write_expected(bank, sample_blocks, coefficients)

        print(
            f"Bank{bank.bank_id}: keys {bank.first_key}-{bank.last_key}, "
            f"Fs={bank.sample_rate_hz:.0f} Hz, bins={bank.bin_count}"
        )
        print(f"  coefficients: {coeff_path}")
        print(f"  samples:      {sample_path}")
        print(f"  expected:     {expected_path}")
        print(
            f"  first coeff:  key {bank.first_key} "
            f"{piano_frequency_hz(bank.first_key):.6f} Hz -> {to_hex(coefficients[0], COEFF_BITS)}"
        )
        print(
            f"  last coeff:   key {bank.last_key} "
            f"{piano_frequency_hz(bank.last_key):.6f} Hz -> {to_hex(coefficients[-1], COEFF_BITS)}"
        )


if __name__ == "__main__":
    main()
