#!/bin/bash
set -euo pipefail

# ==============================================================================
# Standalone Windows Steam Setup for Apple Silicon (M4 Mac Mini)
# Uses Sikarugir (WS12WineSikarugir10.0_6 + Template-1.0.11) with D3DMetal & MSync
# ==============================================================================

SIKARUGIR_SUPPORT="$HOME/Library/Application Support/Sikarugir"
ENGINES_DIR="$SIKARUGIR_SUPPORT/Engines"
TEMPLATE_DIR="$SIKARUGIR_SUPPORT/Template"

ENGINE_ARCHIVE="$ENGINES_DIR/WS12WineSikarugir10.0_6.tar.xz"
TEMPLATE_ARCHIVE="$TEMPLATE_DIR/Template-1.0.11.tar.xz"

ENGINE_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz"
TEMPLATE_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz"

WRAPPER_DIR="$HOME/Applications/Sikarugir"
SIKARUGIR_APP="$WRAPPER_DIR/Steam.app"
SHORTCUT_APP="$HOME/Applications/Steam (Windows).app"
INSTALLER_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
INSTALLER_PATH="/Users/jameson/agy-proj/win-stem/SteamSetup.exe"

echo "==> 1. Ensuring Sikarugir Creator.app is installed..."
if [ ! -d "/Applications/Sikarugir Creator.app" ]; then
    brew tap Sikarugir-App/sikarugir
    brew install --cask sikarugir
fi

echo "==> 2. Downloading Sikarugir Engine (WS12WineSikarugir10.0_6) and Template (Template-1.0.11)..."
mkdir -p "$ENGINES_DIR" "$TEMPLATE_DIR" "$WRAPPER_DIR"
if [ ! -f "$ENGINE_ARCHIVE" ]; then
    curl -L "$ENGINE_URL" -o "$ENGINE_ARCHIVE"
fi
if [ ! -f "$TEMPLATE_ARCHIVE" ]; then
    curl -L "$TEMPLATE_URL" -o "$TEMPLATE_ARCHIVE"
fi

echo "==> 3. Assembling Sikarugir wrapper at $SIKARUGIR_APP..."
if [ ! -d "$SIKARUGIR_APP" ]; then
    tar -xf "$TEMPLATE_ARCHIVE" -C "$WRAPPER_DIR"
    mv "$WRAPPER_DIR/Template-1.0.11.app" "$SIKARUGIR_APP"
    mkdir -p "$SIKARUGIR_APP/Contents/SharedSupport"
    tar -xf "$ENGINE_ARCHIVE" -C "$SIKARUGIR_APP/Contents/SharedSupport"
    mv "$SIKARUGIR_APP/Contents/SharedSupport/wswine.bundle" "$SIKARUGIR_APP/Contents/SharedSupport/wine"
fi

echo "==> 4. Configuring D3DMetal, MSync, and Steam executable in $SIKARUGIR_APP/Contents/Info.plist..."
/usr/libexec/PlistBuddy -c "Set ':Program Name and Path' '/Program Files (x86)/Steam/Steam.exe'" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':D3DMETAL' 1" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':WINEMSYNC' 1" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':WINEESYNC' 1" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':Skip Gecko' 1" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':Skip Mono' 1" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':CFBundleName' 'Steam'" "$SIKARUGIR_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set ':CFBundleIdentifier' 'com.Sikarugir.Steam'" "$SIKARUGIR_APP/Contents/Info.plist"

echo "==> 5. Initializing 64-bit Windows 10 Wine prefix and installing Windows Steam..."
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
WINESERVER_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wineserver"
export WINEPREFIX="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEMSYNC=1
export WINEESYNC=1
export D3DMETAL=1

mkdir -p "$WINEPREFIX"
ln -sfn "SharedSupport/prefix/drive_c" "$SIKARUGIR_APP/Contents/drive_c"

"$WINE_BIN" wineboot -u
"$WINE_BIN" winecfg -v win10

if [ ! -f "$INSTALLER_PATH" ]; then
    curl -L "$INSTALLER_URL" -o "$INSTALLER_PATH"
fi

if [ ! -f "$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe" ]; then
    "$WINE_BIN" "$INSTALLER_PATH" /S
    "$WINESERVER_BIN" -w
fi

echo "==> 6. Applying Wine Registry Game Compatibility Settings..."
# Marvel Rivals: SteamDeck=1
"$WINE_BIN" reg add "HKCU\\Environment" /v SteamDeck /t REG_SZ /d "1" /f
"$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Control\\Session Manager\\Environment" /v SteamDeck /t REG_SZ /d "1" /f

# Cities: Skylines II: Windows TMPDIR
"$WINE_BIN" reg add "HKCU\\Environment" /v TMPDIR /t REG_SZ /d "C:\\users\\jameson\\Temp" /f
"$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Control\\Session Manager\\Environment" /v TMPDIR /t REG_SZ /d "C:\\windows\\temp" /f

# Capcom Arcade 2nd Stadium: Disable winegstreamer (uses mgvf-asf-reader.dll fallback)
"$WINE_BIN" reg add "HKCU\\Software\\Wine\\AppDefaults\\CapcomArcade2ndStadium.exe\\DllOverrides" /v winegstreamer /t REG_SZ /d "" /f

echo "==> 7. Re-signing wrapper and creating shortcut app at $SHORTCUT_APP..."
xattr -cr "$SIKARUGIR_APP"
codesign --force --deep --sign - "$SIKARUGIR_APP"

mkdir -p "$SHORTCUT_APP/Contents/MacOS" "$SHORTCUT_APP/Contents/Resources"
cat << 'EOF' > "$SHORTCUT_APP/Contents/MacOS/steam-launcher.sh"
#!/bin/bash
exec open "$HOME/Applications/Sikarugir/Steam.app" "$@"
EOF
chmod +x "$SHORTCUT_APP/Contents/MacOS/steam-launcher.sh"
codesign --force --deep --sign - "$SHORTCUT_APP"

echo "==> Done! Launch Windows Steam via:"
echo "    open \"$SIKARUGIR_APP\""
