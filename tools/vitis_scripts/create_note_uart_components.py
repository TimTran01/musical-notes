#!/usr/bin/env python3
"""Create the Vitis Unified IDE components for the piano note detector app."""

from __future__ import annotations

import glob
import os
import shutil
import time
from pathlib import Path
from typing import Optional

import vitis


PLATFORM_NAME = "piano_detect_platform"
DOMAIN_NAME = "standalone_ps7_cortexa9_0"
APP_NAME = "piano_detect_application"


def remove_path(path: Path) -> None:
    for attempt in range(10):
        try:
            if path.is_dir():
                shutil.rmtree(path)
            elif path.exists():
                path.unlink()
            return
        except PermissionError:
            if attempt == 9:
                print(f"Warning: could not remove locked path: {path}")
                return
            time.sleep(0.5)


def clean_workspace(workspace: Path) -> None:
    for path in (
        workspace / ".metadata",
        workspace / ".analytics",
        workspace / ".lock",
        workspace / ".peers.ini",
        workspace / ".repo.yaml",
        workspace / "IDE.log",
        workspace / "logs",
        workspace / PLATFORM_NAME,
        workspace / APP_NAME,
        workspace / f"{APP_NAME}_system",
    ):
        remove_path(path)


def find_platform_xpfm(workspace: Path, client: vitis._Vitis) -> str:
    platform_xpfm = client.get_platform(PLATFORM_NAME)
    if platform_xpfm:
        return platform_xpfm

    matches = glob.glob(str(workspace / PLATFORM_NAME / "**" / "*.xpfm"), recursive=True)
    if not matches:
        raise RuntimeError(f"Could not find generated XPFM for {PLATFORM_NAME}")
    return matches[0]


def find_app_elf(workspace: Path) -> Optional[str]:
    app_dir = workspace / APP_NAME
    matches = glob.glob(str(app_dir / "**" / f"{APP_NAME}.elf"), recursive=True)
    if not matches:
        matches = glob.glob(str(app_dir / "**" / "*.elf"), recursive=True)
    return matches[0] if matches else None


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[1]
    project_software = repo_root / "final_project_software"
    workspace = Path(os.environ.get("NOTE_VITIS_WORKSPACE", project_software)).resolve()
    hw_xsa = project_software / "hw" / "final_project_hardware.xsa"
    source_dir = project_software / APP_NAME / "src"
    app_source = source_dir / "main.c"

    if not hw_xsa.exists():
        raise FileNotFoundError(f"Missing hardware XSA: {hw_xsa}")
    if not app_source.exists():
        raise FileNotFoundError(f"Missing app source: {app_source}")

    clean_workspace(workspace)

    client = vitis.create_client()
    try:
        client.set_workspace(str(workspace))

        platform = client.create_platform_component(
            name=PLATFORM_NAME,
            hw=str(hw_xsa),
            os="standalone",
            cpu="ps7_cortexa9_0",
            domain_name=DOMAIN_NAME,
        )
        platform.build()

        platform_xpfm = find_platform_xpfm(workspace, client)
        app_component = client.create_app_component(
            name=APP_NAME,
            platform=platform_xpfm,
            domain=DOMAIN_NAME,
            template="empty_application",
        )
        app_component.import_files(
            from_loc=str(source_dir),
            files=["main.c"],
            dest_dir_in_cmp="src",
        )
        build_result = app_component.build()
        app_elf = find_app_elf(workspace)
        if app_elf is None:
            raise RuntimeError(f"{APP_NAME} build did not produce an ELF. Build result: {build_result}")

        print(f"Built {APP_NAME}: {app_elf}")
        print(f"Using platform: {platform_xpfm}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
