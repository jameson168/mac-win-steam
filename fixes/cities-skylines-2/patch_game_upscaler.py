#!/usr/bin/env python3
"""
patch_game_upscaler.py — Patch Game.dll for Wine/D3DMetal compatibility (CS2 1.6.4f1+).

In Cities: Skylines II 1.6.4f1 (Seasonal Shift update), Game.Settings.GraphicsSettings
initializes `upscaler` in `SetDefaults()` via `UpscalerManager.GetDefaultUpscaler()`.
Under D3DMetal on macOS (`Vendor: ATI`), `GetDefaultUpscaler()` selects `Upscaler.FSR3`,
which breaks HDRP terrain/city rendering and causes black terrain.

This script patches `UpscalerManager.GetDefaultUpscaler()` in `Game.dll` to immediately
return `Upscaler.None` (0) (`ldc.i4.0; ret`).
"""

import os
import shutil
import sys

# Unique 20-byte signature at the start of UpscalerManager.GetDefaultUpscaler() IL body:
# 20 f8 00 00 00 (ldc.i4 248)
# 28 26 06 00 0a (call ...)
# 16             (ldc.i4.0)
# 28 91 06 00 0a (call ...)
# 2c 02 16 2a    (brfalse.s +2; ldc.i4.0; ret)
ORIG_PATTERN = bytes([
    0x20, 0xF8, 0x00, 0x00, 0x00,
    0x28, 0x26, 0x06, 0x00, 0x0A,
    0x16,
    0x28, 0x91, 0x06, 0x00, 0x0A,
    0x2C, 0x02, 0x16, 0x2A,
])

# Replace `2c 02` (brfalse.s +2) with `26 00` (pop; nop) so execution always
# falls through to `16 2a` (ldc.i4.0; ret) with valid IL stack state.
PATCHED_PATTERN = bytes([
    0x20, 0xF8, 0x00, 0x00, 0x00,
    0x28, 0x26, 0x06, 0x00, 0x0A,
    0x16,
    0x28, 0x91, 0x06, 0x00, 0x0A,
    0x26, 0x00, 0x16, 0x2A,
])


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    game_root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(script_dir)
    dll_path = os.path.join(game_root, "Cities2_Data", "Managed", "Game.dll")
    backup_path = dll_path + ".bak"

    if not os.path.exists(dll_path):
        print(f"ERROR: Cannot find {dll_path}", file=sys.stderr)
        sys.exit(1)

    with open(dll_path, "rb") as f:
        data = bytearray(f.read())

    if PATCHED_PATTERN in data:
        print(f"Game.dll already patched ({dll_path}).")
        return

    idx = data.find(ORIG_PATTERN)
    if idx == -1:
        print("WARNING: UpscalerManager.GetDefaultUpscaler pattern not found in Game.dll.")
        return

    if not os.path.exists(backup_path):
        shutil.copy2(dll_path, backup_path)
        print(f"Backup created: {backup_path}")

    print(f"Patching UpscalerManager.GetDefaultUpscaler at file offset 0x{idx:X} -> return Upscaler.None (0)")
    data[idx:idx + len(ORIG_PATTERN)] = PATCHED_PATTERN

    with open(dll_path, "wb") as f:
        f.write(data)
    print("Success! Game.dll has been patched.")


if __name__ == "__main__":
    main()
