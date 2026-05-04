#!/usr/bin/env python3
"""Refresh the Vitis Unified IDE platform from the latest exported XSA."""

from __future__ import annotations

import shutil
from pathlib import Path

import vitis


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = REPO_ROOT / "final_project_software"
PLATFORM_NAME = "piano_detect_platform"

SOURCE_XSA = WORKSPACE / "hw" / "final_project_hardware.xsa"
PLATFORM_SOURCE_XSA = REPO_ROOT / "final_project_hardware" / "finalXSA_hardware.xsa"
PLATFORM_LOCAL_XSA = WORKSPACE / PLATFORM_NAME / "hw" / "finalXSA_hardware.xsa"


def main() -> int:
    if not SOURCE_XSA.exists():
        raise FileNotFoundError(f"Missing exported XSA: {SOURCE_XSA}")

    for destination in (PLATFORM_SOURCE_XSA, PLATFORM_LOCAL_XSA):
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE_XSA, destination)
        print(f"Copied {SOURCE_XSA} -> {destination}")

    client = vitis.create_client()
    try:
        client.set_workspace(str(WORKSPACE))
        platform = client.get_platform_component(PLATFORM_NAME)
        platform.clean()
        status = platform.build()
        print(f"Platform build status: {status}")
    finally:
        vitis.dispose()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
