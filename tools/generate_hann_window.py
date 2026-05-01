#!/usr/bin/env python3
"""Generate fixed-point Hann-window data for the FPGA Hann window IP.

The Excel workbook uses the Hann formula:

    0.5 * (1 - cos(2*pi*n/(4096 - 1)))

This script converts that floating-point formula into a 24-bit fixed-point ROM
file that VHDL can read during simulation and synthesis. The coefficient format
is unsigned Q1.23, stored as six uppercase hexadecimal digits per line.

Q1.23 means the binary point is 23 bits from the right. A coefficient word of
0x000000 represents 0.0, and 0x7FFFFF represents the largest positive value
below 1.0 that can also be safely interpreted as a positive signed 24-bit
multiplier operand in VHDL.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path


WINDOW_LENGTH = 4096
COEFF_BITS = 24
COEFF_MAX = (1 << (COEFF_BITS - 1)) - 1
SAMPLE_BITS = 24
SAMPLE_MIN = -(1 << (SAMPLE_BITS - 1))
SAMPLE_MAX = (1 << (SAMPLE_BITS - 1)) - 1
FRACTIONAL_BITS = 23

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HANN_OUTPUT = (
    REPO_ROOT
    / "final_project_hardware"
    / "final_project_hardware.srcs"
    / "sources_1"
    / "new"
    / "hann_window.mem"
)
DEFAULT_EXPECTED_OUTPUT = (
    REPO_ROOT
    / "final_project_hardware"
    / "final_project_hardware.srcs"
    / "sim_1"
    / "new"
    / "hann_window_4096_tb_expected.mem"
)


@dataclass(frozen=True)
class TestVector:
    """One test vector shared by Python and the VHDL testbench."""

    index: int
    sample: int


TEST_VECTORS = (
    TestVector(index=0, sample=1_000_000),
    TestVector(index=1, sample=683_183),
    TestVector(index=2047, sample=8_388_607),
    TestVector(index=2048, sample=-8_388_608),
    TestVector(index=4095, sample=-1_234_567),
)


def hann_coefficient(index: int, length: int = WINDOW_LENGTH) -> float:
    """Return the floating-point Hann coefficient used by the Excel model."""
    if not 0 <= index < length:
        raise ValueError(f"index {index} is outside 0..{length - 1}")

    return 0.5 * (1.0 - math.cos((2.0 * math.pi * index) / (length - 1)))


def quantize_coefficient(coefficient: float) -> int:
    """Convert a floating-point Hann coefficient into unsigned Q1.23."""
    quantized = round(coefficient * COEFF_MAX)
    return max(0, min(COEFF_MAX, quantized))


def to_hex(value: int, bits: int) -> str:
    """Format an integer as a two's-complement hexadecimal word."""
    hex_digits = (bits + 3) // 4
    return f"{value & ((1 << bits) - 1):0{hex_digits}X}"


def clamp_sample(value: int) -> int:
    """Limit a value to the signed 24-bit range used by the Hann output."""
    return max(SAMPLE_MIN, min(SAMPLE_MAX, value))


def generate_coefficients(length: int = WINDOW_LENGTH) -> list[int]:
    """Generate every fixed-point Hann coefficient for one full frame."""
    return [quantize_coefficient(hann_coefficient(index, length)) for index in range(length)]


def write_hann_mem(coefficients: list[int], output_path: Path) -> None:
    """Write the coefficient ROM file consumed by hann_window_4096.vhd."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii", newline="\n") as mem_file:
        for coefficient in coefficients:
            mem_file.write(f"{to_hex(coefficient, COEFF_BITS)}\n")


def truncate_hann_product(sample: int, coefficient: int) -> int:
    """Apply Q1.23 coefficient and truncate back to signed 24-bit sample data.

    Hardware multiplies signed 24-bit sample data by a positive Q1.23 Hann
    coefficient. That creates a signed Q24.23 product. The revised Hann IP
    discards the 23 fractional bits with an arithmetic right shift, leaving an
    ADC-like signed 24-bit integer output.
    """
    product = sample * coefficient
    truncated = product >> FRACTIONAL_BITS
    return clamp_sample(truncated)


def write_expected_vectors(coefficients: list[int], output_path: Path) -> None:
    """Write Python-computed 24-bit Hann outputs for the VHDL testbench.

    Each line is one signed 24-bit two's-complement value. The VHDL testbench
    applies the matching hard-coded sample/index vector and checks the DUT output
    against this Python model of the truncation policy.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii", newline="\n") as expected_file:
        for vector in TEST_VECTORS:
            sample = truncate_hann_product(vector.sample, coefficients[vector.index])
            expected_file.write(f"{to_hex(sample, SAMPLE_BITS)}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate hann_window.mem for the 4096-point Hann window IP."
    )
    parser.add_argument(
        "--hann-output",
        type=Path,
        default=DEFAULT_HANN_OUTPUT,
        help=f"Hann coefficient .mem output path (default: {DEFAULT_HANN_OUTPUT})",
    )
    parser.add_argument(
        "--expected-output",
        type=Path,
        default=DEFAULT_EXPECTED_OUTPUT,
        help=f"testbench expected-product output path (default: {DEFAULT_EXPECTED_OUTPUT})",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    coefficients = generate_coefficients()

    write_hann_mem(coefficients, args.hann_output)
    write_expected_vectors(coefficients, args.expected_output)

    center_left = WINDOW_LENGTH // 2 - 1
    center_right = WINDOW_LENGTH // 2

    print(f"Wrote {len(coefficients)} Hann coefficients to {args.hann_output}")
    print(f"Wrote {len(TEST_VECTORS)} expected 24-bit outputs to {args.expected_output}")
    print(f"Coefficient[0] = {to_hex(coefficients[0], COEFF_BITS)}")
    print(f"Coefficient[{center_left}] = {to_hex(coefficients[center_left], COEFF_BITS)}")
    print(f"Coefficient[{center_right}] = {to_hex(coefficients[center_right], COEFF_BITS)}")
    print(f"Coefficient[{WINDOW_LENGTH - 1}] = {to_hex(coefficients[-1], COEFF_BITS)}")


if __name__ == "__main__":
    main()
