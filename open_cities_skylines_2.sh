#!/bin/bash
set -euo pipefail

# Launch Cities: Skylines II (App ID 949230) directly (bypassing Paradox Launcher)
# Uses Sikarugir Wine 10.0 + D3DMetal + MSync + version.dll runtime fix
SIKARUGIR_APP="$HOME/Applications/Sikarugir/Steam.app"
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
GAME_DIR="$SIKARUGIR_APP/Contents/drive_c/Program Files (x86)/Steam/steamapps/common/Cities Skylines II"
CITIES2_EXE="$GAME_DIR/Cities2.exe"
STEAM_EXE="$SIKARUGIR_APP/Contents/drive_c/Program Files (x86)/Steam/steam.exe"

export WINEPREFIX="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks/renderer/d3dmetal/external:$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEDLLPATH_PREPEND="$SIKARUGIR_APP/Contents/Frameworks/renderer/d3dmetal/wine"
export WINEDLLPATH="$SIKARUGIR_APP/Contents/Frameworks/renderer/d3dmetal/wine:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib/wine"
export CX_D3DMETALPATH="$SIKARUGIR_APP/Contents/Frameworks/renderer/d3dmetal/external"
export WINEDLLOVERRIDES="d3d11,dxgi,d3d12,atidxx64,nvapi64,nvngx=b"
export WINEMSYNC=1
export WINEESYNC=1
export D3DMETAL=1
export D3DM_ENABLE_METALFX=0
export ROSETTA_ADVERTISE_AVX=1
export SteamAppId=949230
export SteamGameId=949230

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Ensure compatibility patches are applied (only on first run or after game update)
if [ -d "$GAME_DIR/Cities2_Data" ] && [ ! -f "$GAME_DIR/Cities2_Data/Managed/Game.dll.bak" ]; then
    "$SCRIPT_DIR/fixes/cities-skylines-2/apply_cities2_fix.sh" >/dev/null
fi

if [ -f "$CITIES2_EXE" ]; then
    if ! pgrep -f "Cities2.exe" >/dev/null 2>&1; then
        ps aux | grep -i "crashpad_handler" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true
    fi
    echo "Launching Cities2.exe directly (bypassing Paradox Launcher)..."
    cd "$GAME_DIR"
    "$WINE_BIN" "$CITIES2_EXE" </dev/null >/dev/null 2>&1 &
    disown
else
    echo "Cities2.exe not yet installed; opening App ID 949230 in Windows Steam..."
    "$WINE_BIN" "$STEAM_EXE" "steam://store/949230" </dev/null >/dev/null 2>&1 &
    disown
fi
