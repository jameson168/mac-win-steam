#!/bin/bash
set -euo pipefail

# Open Marvel Rivals (App ID 2767030, Free-to-Play) inside Windows Steam (Sikarugir Wine 10.0 + D3DMetal + MSync)
SIKARUGIR_APP="$HOME/Applications/Sikarugir/Steam.app"
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
STEAM_EXE="$SIKARUGIR_APP/Contents/drive_c/Program Files (x86)/Steam/steam.exe"

export WINEPREFIX="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEMSYNC=1
export WINEESYNC=1
export D3DMETAL=1
export ROSETTA_ADVERTISE_AVX=1

echo "Opening Marvel Rivals (App ID 2767030) in Windows Steam..."
"$WINE_BIN" "$STEAM_EXE" "steam://store/2767030" >/dev/null 2>&1 &
