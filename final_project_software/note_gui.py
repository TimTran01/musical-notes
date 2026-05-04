#!/usr/bin/env python3
"""Serial GUI for the Vitis piano-note UART stream."""

from __future__ import annotations

import argparse
import queue
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from tkinter import ttk


@dataclass(frozen=True)
class NoteEvent:
    key: int
    note: str
    frequency_hz: float


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


class SerialReader(threading.Thread):
    def __init__(self, port: str, baud: int, events: queue.Queue[tuple[str, object]]) -> None:
        super().__init__(daemon=True)
        self._port = port
        self._baud = baud
        self._events = events
        self._stop_event = threading.Event()

    def stop(self) -> None:
        self._stop_event.set()

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
                        raw = connection.readline()
                        if not raw:
                            continue
                        line = raw.decode("ascii", errors="replace")
                        event = parse_note_line(line)
                        if event is not None:
                            self._events.put(("note", event))
            except Exception as exc:  # noqa: BLE001 - show serial errors in GUI
                self._events.put(("status", f"Disconnected: {exc}"))
                time.sleep(1.0)


class NoteGui(tk.Tk):
    def __init__(self, port: str, baud: int) -> None:
        super().__init__()
        self.title("Piano Note UART")
        self.geometry("440x300")
        self.minsize(360, 260)

        self._events: queue.Queue[tuple[str, object]] = queue.Queue()
        self._reader = SerialReader(port, baud, self._events)

        self._note_var = tk.StringVar(value="--")
        self._key_var = tk.StringVar(value="Key --")
        self._freq_var = tk.StringVar(value="-- Hz")
        self._status_var = tk.StringVar(value="Connecting...")
        self._time_var = tk.StringVar(value="No note received")

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
        note_label.configure(font=("Segoe UI", 72, "bold"))

        key_label = ttk.Label(root, textvariable=self._key_var, anchor="center")
        key_label.grid(row=1, column=0, sticky="ew")
        key_label.configure(font=("Segoe UI", 20))

        freq_label = ttk.Label(root, textvariable=self._freq_var, anchor="center")
        freq_label.grid(row=2, column=0, sticky="ew", pady=(2, 24))
        freq_label.configure(font=("Segoe UI", 18))

        status_label = ttk.Label(root, textvariable=self._status_var, anchor="center")
        status_label.grid(row=3, column=0, sticky="ew", pady=(8, 2))

        time_label = ttk.Label(root, textvariable=self._time_var, anchor="center")
        time_label.grid(row=4, column=0, sticky="ew")

    def _drain_events(self) -> None:
        while True:
            try:
                event_type, payload = self._events.get_nowait()
            except queue.Empty:
                break

            if event_type == "status":
                self._status_var.set(str(payload))
            elif event_type == "note" and isinstance(payload, NoteEvent):
                self._note_var.set(payload.note)
                self._key_var.set(f"Key {payload.key}")
                self._freq_var.set(f"{payload.frequency_hz:.2f} Hz")
                self._time_var.set(time.strftime("Last note: %H:%M:%S"))

        self.after(50, self._drain_events)

    def _on_close(self) -> None:
        self._reader.stop()
        self.destroy()


def main() -> None:
    parser = argparse.ArgumentParser(description="Display piano notes received from Vitis UART CSV.")
    parser.add_argument("--port", required=True, help="Serial port, for example COM5 or /dev/ttyUSB1.")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate.")
    args = parser.parse_args()

    app = NoteGui(args.port, args.baud)
    app.mainloop()


if __name__ == "__main__":
    main()
