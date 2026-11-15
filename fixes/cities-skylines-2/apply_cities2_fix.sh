#!/bin/bash
set -euo pipefail

# Installs the Cities: Skylines II compatibility fix (Wine registry settings + JetBrains stub + IL/DLL patchers)
HERE="$(cd "$(dirname "$0")" && pwd)"
SIKARUGIR_APP="$HOME/Applications/Sikarugir/Steam.app"
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
PREFIX_DIR="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
GAME_DIR="${1:-$SIKARUGIR_APP/Contents/drive_c/Program Files (x86)/Steam/steamapps/common/Cities Skylines II}"

mkdir -p "$GAME_DIR"

echo "1. Removing any leftover version.dll proxy in $GAME_DIR (using Wine builtin version.dll)..."
rm -f "$GAME_DIR/version.dll" "$GAME_DIR/version_real.dll"

echo "2. Configuring Wine registry TMPDIR and DllOverrides for Cities2.exe..."
export WINEPREFIX="$PREFIX_DIR"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEMSYNC=1
export WINEESYNC=1

"$WINE_BIN" reg delete "HKCU\\Software\\Wine\\AppDefaults\\Cities2.exe\\DllOverrides" /v version /f >/dev/null 2>&1 || true
"$WINE_BIN" reg add "HKCU\\Environment" /v TMPDIR /t REG_SZ /d "C:\\users\\jameson\\Temp" /f
"$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Control\\Session Manager\\Environment" /v TMPDIR /t REG_SZ /d "C:\\windows\\temp" /f

TB_SETTINGS="$PREFIX_DIR/drive_c/users/jameson/AppData/Local/JetBrains/Toolbox/.settings.json"
if [ ! -f "$TB_SETTINGS" ]; then
    mkdir -p "$(dirname "$TB_SETTINGS")"
    printf '{}\n' > "$TB_SETTINGS"
fi

if [ -d "$GAME_DIR/Cities2_Data" ]; then
    echo "3. Applying IL/DLL compatibility patches (with .bak backups)..."
    python3 "$HERE/patch_colossal_io.py" "$GAME_DIR"
    python3 "$HERE/patch_asset_database.py" "$GAME_DIR"
    python3 "$HERE/patch_cohtml.py" "$GAME_DIR"
    python3 "$HERE/patch_game_upscaler.py" "$GAME_DIR"
fi

echo "Done! Cities: Skylines II runtime fix is installed."
