#!/bin/bash
set -euo pipefail

# Re-applies the RE Engine VC-1 / WMA Pro ASF video fix to Capcom Arcade 2nd Stadium
# (Useful if Steam "Verify integrity of game files" or a game update overwrites amd_ags_x64.dll)

HERE="$(cd "$(dirname "$0")" && pwd)"
SIKARUGIR_APP="$HOME/Applications/Sikarugir/Steam.app"
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
GAME_DIR="${1:-$SIKARUGIR_APP/Contents/drive_c/Program Files (x86)/Steam/steamapps/common/Capcom Arcade 2nd Stadium}"

if [ ! -d "$GAME_DIR" ]; then
  echo "Error: Game directory not found: $GAME_DIR" >&2
  exit 1
fi

if [ ! -f "$GAME_DIR/amd_ags_x64_real.dll" ]; then
  echo "Backing up original amd_ags_x64.dll -> amd_ags_x64_real.dll..."
  mv "$GAME_DIR/amd_ags_x64.dll" "$GAME_DIR/amd_ags_x64_real.dll"
fi

echo "Installing amd_ags_x64.dll proxy and mgvf-asf-reader.dll..."
cp "$HERE/amd_ags_x64.dll" "$GAME_DIR/amd_ags_x64.dll"
cp "$HERE/mgvf-asf-reader.dll" "$GAME_DIR/mgvf-asf-reader.dll"
cp "$HERE/mgvf-asf-reader-LICENCES.md" "$GAME_DIR/mgvf-asf-reader-LICENCES.md"

echo "Ensuring winegstreamer is disabled for CapcomArcade2ndStadium.exe in Wine registry..."
export WINEPREFIX="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEMSYNC=1
export WINEESYNC=1

"$WINE_BIN" reg add "HKCU\\Software\\Wine\\AppDefaults\\CapcomArcade2ndStadium.exe\\DllOverrides" /v winegstreamer /t REG_SZ /d "" /f

echo "Done! Capcom Arcade 2nd Stadium RE Engine VC-1 fix is installed."
