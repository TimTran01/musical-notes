#!/usr/bin/env python3
"""Generate pure sine note samples, load them over UART, and check decoding."""

from __future__ import annotations

import argparse
import math
import random
import sys
import time
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from generate_adc_samples import (  # noqa: E402
    ADC_MAX_SIGNED,
    ADC_MIN_SIGNED,
    DEFAULT_AMPLITUDE,
    DEFAULT_SAMPLE_COUNT,
    DEFAULT_SAMPLE_RATE_HZ,
    clamp,
    signed_to_24bit_hex,
)
from note_gui import (  # noqa: E402
    GeneratedSampleSet,
    NoteEvent,
    SAMPLE_LOAD_HEADER_DELAY_S,
    SAMPLE_LOAD_LINE_DELAY_S,
    generate_sample_set_for_key,
    parse_key_selection,
    parse_load_response,
    parse_note_line,
    piano_key_frequency_hz,
    piano_key_name,
    sample_checksum,
)


def pure_sine_samples(
    sample_count: int,
    sample_rate_hz: float,
    frequency_hz: float,
    amplitude: float,
    phase_radians: float = 0.0,
) -> list[int]:
    if sample_count <= 0:
        raise ValueError("sample_count must be greater than zero")
    if sample_rate_hz <= 0.0:
        raise ValueError("sample_rate_hz must be greater than zero")
    if frequency_hz <= 0.0:
        raise ValueError("frequency_hz must be greater than zero")
    if not 0.0 < amplitude <= 1.0:
        raise ValueError("amplitude must be in range 0.0..1.0")

    return [
        clamp(
            round(
                amplitude
                * ADC_MAX_SIGNED
                * math.sin((2.0 * math.pi * frequency_hz * index / sample_rate_hz) + phase_radians)
            ),
            ADC_MIN_SIGNED,
            ADC_MAX_SIGNED,
        )
        for index in range(sample_count)
    ]


def generate_pure_sine_sample_set(
    key: int,
    sample_count: int = DEFAULT_SAMPLE_COUNT,
    sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ,
    amplitude: float = DEFAULT_AMPLITUDE,
    phase_radians: float = 0.0,
) -> GeneratedSampleSet:
    frequency_hz = piano_key_frequency_hz(key)
    samples = pure_sine_samples(
        sample_count=sample_count,
        sample_rate_hz=sample_rate_hz,
        frequency_hz=frequency_hz,
        amplitude=amplitude,
        phase_radians=phase_radians,
    )
    words = tuple(signed_to_24bit_hex(sample) for sample in samples)
    return GeneratedSampleSet(
        key=key,
        note=piano_key_name(key),
        frequency_hz=frequency_hz,
        seed=0,
        words=words,
        checksum=sample_checksum(words),
    )


def send_load_command(connection: object, sample_set: GeneratedSampleSet, line_delay_s: float) -> float:
    start_time = time.perf_counter()
    header = f"LOAD,{len(sample_set.words)},{sample_set.checksum:08X}\n"
    connection.write(header.encode("ascii"))
    connection.flush()
    time.sleep(SAMPLE_LOAD_HEADER_DELAY_S)

    for word in sample_set.words:
        connection.write(f"{word}\n".encode("ascii"))
        connection.flush()
        time.sleep(line_delay_s)

    return time.perf_counter() - start_time


def read_load_result(connection: object, timeout_s: float) -> tuple[bool, NoteEvent | None, list[str]]:
    loaded = False
    decoded: NoteEvent | None = None
    lines: list[str] = []
    deadline = time.time() + timeout_s

    while time.time() < deadline:
        raw = connection.readline()
        if not raw:
            continue

        line = raw.decode("ascii", errors="replace").strip()
        if not line:
            continue

        lines.append(line)
        load_response = parse_load_response(line)
        if load_response is not None:
            if not load_response.ok:
                return False, None, lines
            loaded = True
            continue

        note = parse_note_line(line)
        if note is not None:
            decoded = note
            break

    return loaded, decoded, lines


def run_one_key(
    connection: object,
    key: int,
    amplitude: float,
    line_delay_s: float,
    timeout_s: float,
    waveform: str,
    rng: random.Random,
) -> bool:
    if waveform == "piano":
        sample_set = generate_sample_set_for_key(key=key, rng=rng)
    else:
        sample_set = generate_pure_sine_sample_set(key=key, amplitude=amplitude)

    if hasattr(connection, "reset_input_buffer"):
        connection.reset_input_buffer()

    send_seconds = send_load_command(connection, sample_set, line_delay_s)
    loaded, decoded, lines = read_load_result(connection, timeout_s)
    ok = loaded and decoded is not None and decoded.key == sample_set.key

    decoded_text = "none" if decoded is None else f"{decoded.key},{decoded.note},{decoded.frequency_hz:.2f}"
    status = "PASS" if ok else "FAIL"
    print(
        f"{status},generated={sample_set.key},{sample_set.note},{sample_set.frequency_hz:.2f},"
        f"decoded={decoded_text},send_seconds={send_seconds:.3f}"
    )
    for line in lines:
        print(f"  UART,{line}")
    return ok


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Load pure sine piano-note samples over UART and report decoded notes."
    )
    parser.add_argument("--port", default="COM6", help="Serial port, for example COM6.")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate.")
    parser.add_argument(
        "--keys",
        default="1-35",
        help="Comma-separated piano keys or ranges to test, for example 5 or 1-35.",
    )
    parser.add_argument("--amplitude", type=float, default=DEFAULT_AMPLITUDE, help="Sine amplitude 0.0..1.0.")
    parser.add_argument(
        "--waveform",
        choices=("pure", "piano"),
        default="pure",
        help="Sample generator to test. 'piano' matches the GUI generator.",
    )
    parser.add_argument("--seed", type=int, default=615, help="Random seed used for --waveform piano.")
    parser.add_argument(
        "--line-delay",
        type=float,
        default=SAMPLE_LOAD_LINE_DELAY_S,
        help="Delay between transmitted sample lines.",
    )
    parser.add_argument("--timeout", type=float, default=8.0, help="Seconds to wait for LOADED and note CSV.")
    parser.add_argument("--repeats", type=int, default=1, help="Number of times to test each key.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    keys = parse_key_selection(args.keys)
    if args.repeats <= 0:
        raise ValueError("--repeats must be greater than zero")

    try:
        import serial
    except ImportError:
        print("ERROR,pyserial_not_installed")
        return 2

    failures = 0
    rng = random.Random(args.seed)
    try:
        with serial.Serial(args.port, args.baud, timeout=0.25) as connection:
            for _repeat in range(args.repeats):
                for key in keys:
                    if not run_one_key(
                        connection=connection,
                        key=key,
                        amplitude=args.amplitude,
                        line_delay_s=args.line_delay,
                        timeout_s=args.timeout,
                        waveform=args.waveform,
                        rng=rng,
                    ):
                        failures += 1
    except serial.SerialException as exc:
        print(f"ERROR,serial,{exc}")
        return 2

    print(f"SUMMARY,keys={len(keys)},repeats={args.repeats},failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
