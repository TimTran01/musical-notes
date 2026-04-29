#!/usr/bin/env python3
"""Generate signed 24-bit ADC sample memory data for adc_sample_rom.

The VHDL ROM expects a plain text file named adc_samples.mem by default. This
script creates that file with exactly 4096 hexadecimal words, one word per line.
Each word is a 24-bit two's-complement ADC sample with no "0x" prefix.

The generated waveform is a simple piano-like note model:
  - a fundamental sine wave at the selected piano-key frequency,
  - a few weaker harmonics to make the tone less ideal,
  - a short attack and exponential decay envelope,
  - small random noise to imitate analog/ADC variation.

The output is intended for early FPGA testing before the real ADC path is added.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path


ADC_BITS = 24
ADC_MASK = (1 << ADC_BITS) - 1
ADC_MAX_SIGNED = (1 << (ADC_BITS - 1)) - 1
ADC_MIN_SIGNED = -(1 << (ADC_BITS - 1))
DEFAULT_SAMPLE_COUNT = 4096
DEFAULT_SAMPLE_RATE_HZ = 48_000.0
DEFAULT_FREQUENCY_HZ = 440.0
DEFAULT_AMPLITUDE = 0.75
DEFAULT_NOISE = 0.002
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "final_project_hardware"
    / "final_project_hardware.srcs"
    / "sources_1"
    / "new"
    / "adc_samples.mem"
)


def clamp(value: int, low: int, high: int) -> int:
    """Limit an integer sample so it stays inside signed 24-bit range."""
    return max(low, min(high, value))


def signed_to_24bit_hex(value: int) -> str:
    """Convert a signed integer into a 6-character two's-complement hex word."""
    return f"{value & ADC_MASK:06X}"


def envelope(sample_index: int, sample_rate_hz: float, sample_count: int) -> float:
    """Return a simple piano-like amplitude envelope for one sample index."""
    time_s = sample_index / sample_rate_hz
    duration_s = sample_count / sample_rate_hz

    attack_s = 0.006
    attack_gain = min(1.0, time_s / attack_s)

    # Faster decay makes the sample set visibly change over the captured window
    # while still leaving enough signal energy for Goertzel testing later.
    decay_rate = 3.5 / max(duration_s, 1.0 / sample_rate_hz)
    decay_gain = math.exp(-decay_rate * time_s)

    return attack_gain * decay_gain


def piano_like_sample(
    sample_index: int,
    sample_rate_hz: float,
    frequency_hz: float,
    amplitude: float,
    noise_level: float,
    rng: random.Random,
    sample_count: int,
) -> int:
    """Generate one signed 24-bit ADC sample."""
    time_s = sample_index / sample_rate_hz
    phase = 2.0 * math.pi * frequency_hz * time_s

    waveform = (
        1.00 * math.sin(phase)
        + 0.35 * math.sin(2.0 * phase)
        + 0.18 * math.sin(3.0 * phase)
        + 0.08 * math.sin(4.0 * phase)
    )

    # Sum of harmonic weights above is 1.61, so divide by that to keep the
    # composite tone near +/-1.0 before applying amplitude and envelope.
    waveform /= 1.61

    analog_value = amplitude * envelope(sample_index, sample_rate_hz, sample_count) * waveform
    analog_value += rng.uniform(-noise_level, noise_level)

    adc_value = round(analog_value * ADC_MAX_SIGNED)
    return clamp(adc_value, ADC_MIN_SIGNED, ADC_MAX_SIGNED)


def generate_samples(
    sample_count: int,
    sample_rate_hz: float,
    frequency_hz: float,
    amplitude: float,
    noise_level: float,
    seed: int | None,
) -> list[int]:
    """Generate a complete ADC capture as signed 24-bit integers."""
    rng = random.Random(seed)
    return [
        piano_like_sample(
            sample_index=index,
            sample_rate_hz=sample_rate_hz,
            frequency_hz=frequency_hz,
            amplitude=amplitude,
            noise_level=noise_level,
            rng=rng,
            sample_count=sample_count,
        )
        for index in range(sample_count)
    ]


def write_mem_file(samples: list[int], output_path: Path) -> None:
    """Write samples in the hex format consumed by adc_sample_rom.vhd."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii", newline="\n") as mem_file:
        for sample in samples:
            mem_file.write(f"{signed_to_24bit_hex(sample)}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate adc_samples.mem for the VHDL ADC sample ROM."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"output .mem file path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--samples",
        type=int,
        default=DEFAULT_SAMPLE_COUNT,
        help="number of ADC samples to generate (default: 4096)",
    )
    parser.add_argument(
        "--sample-rate",
        type=float,
        default=DEFAULT_SAMPLE_RATE_HZ,
        help="sample rate in Hz (default: 48000)",
    )
    parser.add_argument(
        "--frequency",
        type=float,
        default=DEFAULT_FREQUENCY_HZ,
        help="note frequency in Hz (default: 440.0, A4)",
    )
    parser.add_argument(
        "--amplitude",
        type=float,
        default=DEFAULT_AMPLITUDE,
        help="normalized signal amplitude from 0.0 to 1.0 (default: 0.75)",
    )
    parser.add_argument(
        "--noise",
        type=float,
        default=DEFAULT_NOISE,
        help="uniform random noise level from 0.0 to 1.0 full scale (default: 0.002)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=615,
        help="random seed for repeatable output; change it for different random data",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    """Reject settings that would produce invalid ROM or ADC data."""
    if args.samples <= 0:
        raise ValueError("--samples must be greater than zero")
    if args.samples != DEFAULT_SAMPLE_COUNT:
        raise ValueError("adc_sample_rom currently expects exactly 4096 samples")
    if args.sample_rate <= 0.0:
        raise ValueError("--sample-rate must be greater than zero")
    if args.frequency <= 0.0:
        raise ValueError("--frequency must be greater than zero")
    if not 0.0 <= args.amplitude <= 1.0:
        raise ValueError("--amplitude must be between 0.0 and 1.0")
    if not 0.0 <= args.noise <= 0.25:
        raise ValueError("--noise must be between 0.0 and 0.25")


def main() -> None:
    args = parse_args()
    validate_args(args)

    samples = generate_samples(
        sample_count=args.samples,
        sample_rate_hz=args.sample_rate,
        frequency_hz=args.frequency,
        amplitude=args.amplitude,
        noise_level=args.noise,
        seed=args.seed,
    )
    write_mem_file(samples, args.output)

    print(f"Wrote {len(samples)} samples to {args.output}")
    print(f"Frequency: {args.frequency:.3f} Hz")
    print(f"Sample rate: {args.sample_rate:.3f} Hz")
    print(f"Signed ADC range used: {min(samples)} to {max(samples)}")


if __name__ == "__main__":
    main()
