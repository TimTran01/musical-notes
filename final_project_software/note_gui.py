#!/usr/bin/env python3
"""Serial GUI for the Vitis piano-note UART stream."""

from __future__ import annotations

import argparse
import queue
import random
import sys
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import ttk


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from generate_adc_samples import (  # noqa: E402
    ADC_MASK,
    DEFAULT_AMPLITUDE,
    DEFAULT_NOISE,
    DEFAULT_SAMPLE_COUNT,
    DEFAULT_SAMPLE_RATE_HZ,
    generate_samples,
    signed_to_24bit_hex,
)


NOTE_NAMES = [
    "", "A0", "A#0", "B0", "C1", "C#1", "D1", "D#1", "E1", "F1", "F#1",
    "G1", "G#1", "A1", "A#1", "B1", "C2", "C#2", "D2", "D#2", "E2",
    "F2", "F#2", "G2", "G#2", "A2", "A#2", "B2", "C3", "C#3", "D3",
    "D#3", "E3", "F3", "F#3", "G3", "G#3", "A3", "A#3", "B3", "C4",
    "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4",
    "B4", "C5", "C#5", "D5", "D#5", "E5", "F5", "F#5", "G5", "G#5",
    "A5", "A#5", "B5", "C6", "C#6", "D6", "D#6", "E6", "F6", "F#6",
    "G6", "G#6", "A6", "A#6", "B6", "C7", "C#7", "D7", "D#7", "E7",
    "F7", "F#7", "G7", "G#7", "A7", "A#7", "B7", "C8",
]

SAMPLE_LOAD_HEADER_DELAY_S = 0.05
SAMPLE_LOAD_LINE_DELAY_S = 0.0005
DEFAULT_RANDOM_KEYS = tuple(range(1, 89))


@dataclass(frozen=True)
class NoteEvent:
    key: int
    note: str
    frequency_hz: float


@dataclass(frozen=True)
class GeneratedSampleSet:
    key: int
    note: str
    frequency_hz: float
    seed: int
    words: tuple[str, ...]
    checksum: int


@dataclass(frozen=True)
class LoadResponse:
    ok: bool
    text: str


def piano_key_frequency_hz(key: int) -> float:
    if not 1 <= key <= 88:
        raise ValueError("piano key must be in range 1..88")
    return 440.0 * (2.0 ** ((key - 49) / 12.0))


def piano_key_name(key: int) -> str:
    if not 1 <= key <= 88:
        raise ValueError("piano key must be in range 1..88")
    return NOTE_NAMES[key]


def sample_checksum(words: tuple[str, ...]) -> int:
    checksum = 0
    for word in words:
        checksum = (checksum + (int(word, 16) & ADC_MASK)) & 0xFFFFFFFF
    return checksum


def parse_key_selection(text: str) -> tuple[int, ...]:
    keys: list[int] = []
    seen: set[int] = set()
    for raw_part in text.split(","):
        part = raw_part.strip()
        if not part:
            raise ValueError("key selection cannot contain empty entries")

        if "-" in part:
            raw_start, raw_end = part.split("-", 1)
            start = int(raw_start.strip())
            end = int(raw_end.strip())
            if start > end:
                raise ValueError("key ranges must be ascending")
            candidates = range(start, end + 1)
        else:
            candidates = (int(part),)

        for key in candidates:
            if not 1 <= key <= 88:
                raise ValueError("piano keys must be in range 1..88")
            if key not in seen:
                keys.append(key)
                seen.add(key)

    if not keys:
        raise ValueError("at least one piano key is required")
    return tuple(keys)


def generate_random_sample_set(
    rng: random.Random | None = None,
    allowed_keys: tuple[int, ...] = DEFAULT_RANDOM_KEYS,
) -> GeneratedSampleSet:
    source = rng if rng is not None else random.SystemRandom()
    if not allowed_keys:
        raise ValueError("at least one piano key is required")
    key = source.choice(allowed_keys)
    return generate_sample_set_for_key(key, source)


def generate_sample_set_for_key(key: int, rng: random.Random | None = None) -> GeneratedSampleSet:
    source = rng if rng is not None else random.SystemRandom()
    frequency_hz = piano_key_frequency_hz(key)
    seed = source.randrange(0, 2**32)
    samples = generate_samples(
        sample_count=DEFAULT_SAMPLE_COUNT,
        sample_rate_hz=DEFAULT_SAMPLE_RATE_HZ,
        frequency_hz=frequency_hz,
        amplitude=DEFAULT_AMPLITUDE,
        noise_level=DEFAULT_NOISE,
        seed=seed,
    )
    words = tuple(signed_to_24bit_hex(sample) for sample in samples)
    return GeneratedSampleSet(
        key=key,
        note=piano_key_name(key),
        frequency_hz=frequency_hz,
        seed=seed,
        words=words,
        checksum=sample_checksum(words),
    )


def parse_note_line(line: str) -> NoteEvent | None:
    text = line.strip()
    if not text or text.startswith("READY") or text.startswith("ERROR"):
        return None

    parts = [part.strip() for part in text.split(",")]
    if len(parts) != 3:
        return None

    try:
        key = int(parts[0])
        frequency_hz = float(parts[2])
    except ValueError:
        return None

    note = parts[1]
    if not 1 <= key <= 88 or not note or frequency_hz <= 0.0:
        return None

    return NoteEvent(key=key, note=note, frequency_hz=frequency_hz)


def parse_load_response(line: str) -> LoadResponse | None:
    text = line.strip()
    if text.startswith("LOADED,"):
        return LoadResponse(ok=True, text=text)
    if text.startswith("ERROR,"):
        return LoadResponse(ok=False, text=text)
    return None


class SerialReader(threading.Thread):
    def __init__(self, port: str, baud: int, events: queue.Queue[tuple[str, object]]) -> None:
        super().__init__(daemon=True)
        self._port = port
        self._baud = baud
        self._events = events
        self._commands: queue.Queue[GeneratedSampleSet] = queue.Queue()
        self._stop_event = threading.Event()

    def stop(self) -> None:
        self._stop_event.set()

    def load_samples(self, sample_set: GeneratedSampleSet) -> None:
        self._commands.put(sample_set)

    def _send_load_command(self, connection: object, sample_set: GeneratedSampleSet) -> None:
        self._events.put(("load_started", sample_set))
        header = f"LOAD,{len(sample_set.words)},{sample_set.checksum:08X}\n"
        connection.write(header.encode("ascii"))
        connection.flush()
        time.sleep(SAMPLE_LOAD_HEADER_DELAY_S)
        for word in sample_set.words:
            connection.write(f"{word}\n".encode("ascii"))
            connection.flush()
            time.sleep(SAMPLE_LOAD_LINE_DELAY_S)
        self._events.put(("status", f"Sent {len(sample_set.words)} samples for {sample_set.note}"))

    def _drain_commands(self, connection: object) -> None:
        while not self._stop_event.is_set():
            try:
                sample_set = self._commands.get_nowait()
            except queue.Empty:
                return
            self._send_load_command(connection, sample_set)

    def run(self) -> None:
        try:
            import serial
        except ImportError:
            self._events.put(("status", "pyserial not installed"))
            return

        while not self._stop_event.is_set():
            try:
                with serial.Serial(self._port, self._baud, timeout=0.25) as connection:
                    self._events.put(("status", f"Connected: {self._port} @ {self._baud}"))
                    while not self._stop_event.is_set():
                        self._drain_commands(connection)
                        raw = connection.readline()
                        if not raw:
                            continue
                        line = raw.decode("ascii", errors="replace")
                        load_response = parse_load_response(line)
                        if load_response is not None:
                            self._events.put(("load_response", load_response))
                            continue
                        event = parse_note_line(line)
                        if event is not None:
                            self._events.put(("note", event))
            except Exception as exc:  # noqa: BLE001 - show serial errors in GUI
                self._events.put(("status", f"Disconnected: {exc}"))
                time.sleep(1.0)


class NoteGui(tk.Tk):
    def __init__(self, port: str, baud: int, random_keys: tuple[int, ...]) -> None:
        super().__init__()
        self.title("Piano Note UART")
        self.geometry("460x410")
        self.minsize(380, 360)

        self._events: queue.Queue[tuple[str, object]] = queue.Queue()
        self._reader = SerialReader(port, baud, self._events)
        self._random_keys = random_keys
        self._pending_generated: GeneratedSampleSet | None = None
        self._note_locked = False

        self._note_var = tk.StringVar(value="--")
        self._key_var = tk.StringVar(value="Key --")
        self._freq_var = tk.StringVar(value="-- Hz")
        self._status_var = tk.StringVar(value="Connecting...")
        self._time_var = tk.StringVar(value="No note received")
        self._generated_var = tk.StringVar(value="Generated: --")
        self._selected_key_var = tk.StringVar(value="49")
        self._random_button: ttk.Button | None = None
        self._selected_button: ttk.Button | None = None

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

        self._reader.start()
        self.after(50, self._drain_events)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=24)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=1)

        note_label = ttk.Label(root, textvariable=self._note_var, anchor="center")
        note_label.grid(row=0, column=0, sticky="ew", pady=(10, 4))
        note_label.configure(font=("Segoe UI", 64, "bold"))

        key_label = ttk.Label(root, textvariable=self._key_var, anchor="center")
        key_label.grid(row=1, column=0, sticky="ew")
        key_label.configure(font=("Segoe UI", 20))

        freq_label = ttk.Label(root, textvariable=self._freq_var, anchor="center")
        freq_label.grid(row=2, column=0, sticky="ew", pady=(2, 18))
        freq_label.configure(font=("Segoe UI", 18))

        self._random_button = ttk.Button(
            root,
            text="Generate Random Note",
            command=self._generate_random_note,
        )
        self._random_button.grid(row=3, column=0, sticky="ew", pady=(4, 10))

        selector_frame = ttk.Frame(root)
        selector_frame.grid(row=4, column=0, sticky="ew", pady=(0, 10))
        selector_frame.columnconfigure(1, weight=1)

        ttk.Label(selector_frame, text="Key").grid(row=0, column=0, sticky="w", padx=(0, 8))
        selected_key_spinbox = tk.Spinbox(
            selector_frame,
            from_=1,
            to=88,
            textvariable=self._selected_key_var,
            width=6,
            justify="center",
        )
        selected_key_spinbox.grid(row=0, column=1, sticky="ew", padx=(0, 8))

        self._selected_button = ttk.Button(
            selector_frame,
            text="Generate Selected Note",
            command=self._generate_selected_note,
        )
        self._selected_button.grid(row=0, column=2, sticky="e")

        generated_label = ttk.Label(root, textvariable=self._generated_var, anchor="center")
        generated_label.grid(row=5, column=0, sticky="ew", pady=(0, 8))

        status_label = ttk.Label(root, textvariable=self._status_var, anchor="center")
        status_label.grid(row=6, column=0, sticky="ew", pady=(8, 2))

        time_label = ttk.Label(root, textvariable=self._time_var, anchor="center")
        time_label.grid(row=7, column=0, sticky="ew")

    def _set_load_buttons_disabled(self, disabled: bool) -> None:
        state = ["disabled"] if disabled else ["!disabled"]
        if self._random_button is not None:
            self._random_button.state(state)
        if self._selected_button is not None:
            self._selected_button.state(state)

    def _queue_sample_set(self, sample_set: GeneratedSampleSet) -> None:
        self._pending_generated = sample_set
        self._note_locked = False
        self._note_var.set("--")
        self._key_var.set("Waiting for decode")
        self._freq_var.set("-- Hz")
        self._time_var.set("No decoded note for current load")
        self._generated_var.set(
            f"Generated: {sample_set.note} / Key {sample_set.key} / {sample_set.frequency_hz:.2f} Hz"
        )
        self._status_var.set(f"Loading {sample_set.note} samples...")
        self._reader.load_samples(sample_set)

    def _generate_random_note(self) -> None:
        self._set_load_buttons_disabled(True)

        try:
            sample_set = generate_random_sample_set(allowed_keys=self._random_keys)
        except Exception as exc:  # noqa: BLE001 - surface generation failure in GUI
            self._status_var.set(f"Generate failed: {exc}")
            self._set_load_buttons_disabled(False)
            return

        self._queue_sample_set(sample_set)

    def _generate_selected_note(self) -> None:
        self._set_load_buttons_disabled(True)

        try:
            key = int(self._selected_key_var.get().strip())
            sample_set = generate_sample_set_for_key(key)
        except Exception as exc:  # noqa: BLE001 - surface generation failure in GUI
            self._status_var.set(f"Generate failed: {exc}")
            self._set_load_buttons_disabled(False)
            return

        self._selected_key_var.set(str(sample_set.key))
        self._queue_sample_set(sample_set)

    def _drain_events(self) -> None:
        while True:
            try:
                event_type, payload = self._events.get_nowait()
            except queue.Empty:
                break

            if event_type == "status":
                self._status_var.set(str(payload))
            elif event_type == "load_started" and isinstance(payload, GeneratedSampleSet):
                self._status_var.set(f"Sending {payload.note} samples...")
            elif event_type == "load_response" and isinstance(payload, LoadResponse):
                self._status_var.set(payload.text)
                if not payload.ok:
                    self._pending_generated = None
                    self._note_locked = False
                self._set_load_buttons_disabled(False)
            elif event_type == "note" and isinstance(payload, NoteEvent):
                if self._pending_generated is None and self._note_locked:
                    continue
                self._note_var.set(payload.note)
                self._key_var.set(f"Key {payload.key}")
                self._freq_var.set(f"{payload.frequency_hz:.2f} Hz")
                self._time_var.set(time.strftime("Last note: %H:%M:%S"))
                if self._pending_generated is not None:
                    generated = self._pending_generated
                    if payload.key == generated.key:
                        self._status_var.set(f"Matched generated {generated.note}")
                        self._pending_generated = None
                        self._note_locked = True
                    else:
                        self._status_var.set(
                            f"Mismatch: generated {generated.note}/Key {generated.key}, "
                            f"decoded {payload.note}/Key {payload.key}"
                        )

        self.after(50, self._drain_events)

    def _on_close(self) -> None:
        self._reader.stop()
        self.destroy()


def main() -> None:
    parser = argparse.ArgumentParser(description="Display piano notes received from Vitis UART CSV.")
    parser.add_argument("--port", default="COM6", help="Serial port, for example COM6 or /dev/ttyUSB1.")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate.")
    parser.add_argument(
        "--keys",
        default="1-88",
        help="Comma-separated piano keys or ranges to choose from, for example 49,80 or 1-88.",
    )
    args = parser.parse_args()

    app = NoteGui(args.port, args.baud, parse_key_selection(args.keys))
    app.mainloop()


if __name__ == "__main__":
    main()
