# Windows Steam on Apple Silicon (M4 Mac Mini)

This project configures and maintains a standalone **Windows Steam** environment on Apple Silicon (`arm64` + Rosetta 2) using **Sikarugir (`WS12WineSikarugir10.0_6`)** with **D3DMetal** (DirectX 11/12 $\rightarrow$ Metal translation) and **MSync**.

---

## 1. Architecture & Key Paths

| Component | Path | Description |
| :--- | :--- | :--- |
| **Primary Wrapper App** | [`~/Applications/Sikarugir/Steam.app`](file:///Users/jameson/Applications/Sikarugir/Steam.app) | Standalone Sikarugir wrapper bundling Wine 10.0 (`WS12WineSikarugir10.0_6`), `D3DMetal.framework`, `GStreamer.framework`, and the Windows 10 64-bit prefix. |
| **Shortcut Launcher App** | [`~/Applications/Steam (Windows).app`](file:///Users/jameson/Applications/Steam%20(Windows).app) | Clickable macOS `.app` launcher that delegates to `~/Applications/Sikarugir/Steam.app`. |
| **Wrapper Configuration** | [`~/Applications/Sikarugir/Steam.app/Contents/Info.plist`](file:///Users/jameson/Applications/Sikarugir/Steam.app/Contents/Info.plist) | Sets `D3DMETAL=1`, `WINEMSYNC=1`, `WINEESYNC=1`, and launches `/Program Files (x86)/Steam/Steam.exe`. |
| **Wine 10.0 Prefix (`drive_c`)** | [`~/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix`](file:///Users/jameson/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix) | 64-bit Windows 10 Wine prefix (`Contents/drive_c` symlinks to `prefix/drive_c`). |
| **Steam Installation** | [`.../drive_c/Program Files (x86)/Steam`](file:///Users/jameson/Applications/Sikarugir/Steam.app/Contents/drive_c/Program%20Files%20(x86)/Steam) | Windows Steam client and game library (`steamapps/common/`). |
| **Steam Logs** | [`.../drive_c/Program Files (x86)/Steam/logs`](file:///Users/jameson/Applications/Sikarugir/Steam.app/Contents/drive_c/Program%20Files%20(x86)/Steam/logs) | `content_log.txt` (downloads), `gameprocess_log.txt` (process tracking), `transport_client.txt` (CEF UI IPC). |
| **Cached Sikarugir Engine** | [`~/Library/Application Support/Sikarugir/Engines/WS12WineSikarugir10.0_6.tar.xz`](file:///Users/jameson/Library/Application%20Support/Sikarugir/Engines/WS12WineSikarugir10.0_6.tar.xz) | Cached Wine 10.0 revision 6 engine archive. |

---

## 2. Why Sikarugir (`WS12WineSikarugir10.0_6`) Was Required

- **Issue with Legacy GPTK Wine 7.7**:
  The older `Game Porting Toolkit.app` (CrossOver Wine 7.7) failed Steam's local WebSocket PID ownership check (`GetExtendedTcpTable` in `iphlpapi.dll`), resulting in `WebUITransport: Connection rejected` in `transport_client.txt` and an invisible Steam UI window.
- **Solution**:
  Following [`mirpo/windows-steam-on-apple-silicon`](https://github.com/mirpo/windows-steam-on-apple-silicon), we built the wrapper on **Sikarugir `Template-1.0.11`** + **`WS12WineSikarugir10.0_6` (Wine 10.0)**. Wine 10.0 natively supports the loopback TCP table lookup required by the modern 64-bit `steamwebhelper.exe` CEF UI without modifying any Steam binaries.

---

## 3. Game-Specific Fixes & Registry Settings

### A. Capcom Arcade 2nd Stadium (App ID `1755910`) — Working
- **Symptom**:
  1. Hung on a black screen at startup when `winegstreamer` was enabled (`asfdemux0:sink` / `multiqueue0` deadlock when demuxing the startup ASF video).
  2. Displayed the Capcom logo $\rightarrow$ loading circle $\rightarrow$ crashed with `ExceptionCode: C0000005` when `winegstreamer` was disabled because `MFCreateSourceReaderFromByteStream` returned `0xc00d36c4` (`MF_E_UNSUPPORTED_BYTESTREAM_TYPE`) for the `1920x1080` **VC-1** (`vc1`) + **WMA Pro** (`wmapro`) title screen video and RE Engine dereferenced the null reader.
- **Fix Applied**:
  1. Disabled `winegstreamer` for `CapcomArcade2ndStadium.exe` only:
     `HKCU\Software\Wine\AppDefaults\CapcomArcade2ndStadium.exe\DllOverrides` $\rightarrow$ `"winegstreamer"=""`
  2. Installed the FFmpeg-based ASF/VC-1/WMA Pro reader ([`mgvf-asf-reader.dll`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/re-engine-vc1/mgvf-asf-reader.dll)) and custom [`amd_ags_x64.dll`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/re-engine-vc1/amd_ags_x64.dll) proxy (built from [`mf-reader-fallback.c`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/re-engine-vc1/mf-reader-fallback.c) with SteamStub `OriginalFirstThunk == 0` and inline hook support, forwarding all 38 exports to `amd_ags_x64_real.dll`).
- **Re-applying the Fix** (if Steam verifies or updates the game files):
  ```bash
  /Users/jameson/agy-proj/mac-win-steam/fixes/re-engine-vc1/apply_capcom_fix.sh
  ```
- **Diagnostic Logs**:
  - `C:\mgvf-mf-fallback.log` (`~/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/mgvf-mf-fallback.log`)
  - `C:\mgvf-asf-reader.log` (`~/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/mgvf-asf-reader.log`)

### B. Marvel Rivals (App ID `2767030`)
- **Pre-configured Registry Environment**:
  - `HKCU\Environment` $\rightarrow$ `SteamDeck="1"`
  - `HKLM\System\CurrentControlSet\Control\Session Manager\Environment` $\rightarrow$ `SteamDeck="1"`
  - Required so Marvel Rivals' launcher/anti-cheat recognizes the Wine environment as Steam Deck compatible.
- **Helper Script**: [`open_marvel_rivals.sh`](file:///Users/jameson/agy-proj/mac-win-steam/open_marvel_rivals.sh)

### C. Cities: Skylines II (App ID `949230`)
- **Known macOS Wine / D3DMetal Issues Fixed**:
  1. **Cohtml UI Rendering Crash (`cohtml_Unity3DPlugin.dll`)**: Takes the wrong branch in `IAllocator` initialization under Wine/GPTK (`0F 84` vs `0F 85`).
  2. **Directory Enumeration Crash (`Colossal.IO.dll`)**: Checks `Marshal.GetLastWin32Error() == ERROR_NO_MORE_FILES (18)` after `FindNextFileW`.
  3. **Paradox Launcher Hang**: Bypassed by launching `Cities2.exe` directly or setting Steam Launch Options to:
     ```text
     "C:\Program Files (x86)\Steam\steamapps\common\Cities Skylines II\Cities2.exe" %command%
     ```
- **Fixes Installed ([`fixes/cities-skylines-2/`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2))**:
  - **IL / DLL Patchers** (`.bak` backups created automatically):
    - [`patch_colossal_io.py`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/patch_colossal_io.py): Patches `Colossal.IO.dll` (`EnumerateFileSystemIterator` / `EnumerateFileSystemIteratorRecursive`) to bypass `Marshal.GetLastWin32Error()` checks after `FindNextFile`, and relaxes `LongFile.OpenRead`/`OpenWrite` `FileShare` flags (`0x1D`) to prevent concurrent `.coc` file `IOException` errors.
    - [`patch_asset_database.py`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/patch_asset_database.py): Patches `Colossal.IO.AssetDatabase.dll` (`PopulateFromDirectory`) to skip `.priority` `File.Exists()` checks under Wine.
    - [`patch_cohtml.py`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/patch_cohtml.py): Patches `cohtml_unity3dplugin.dll` (`0F 84` $\rightarrow$ `0F 85`) when the legacy pattern is present.
    - [`patch_game_upscaler.py`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/patch_game_upscaler.py): Patches `Game.Rendering.UpscalerManager.GetDefaultUpscaler()` in `Game.dll` (`1.6.4f1+`) to return `Upscaler.None` (`0`) instead of `Upscaler.FSR3`, fixing the black terrain bug on macOS D3DMetal.
  - **Registry & Prefix Settings**:
    - `HKCU\Environment` $\rightarrow$ `TMPDIR="C:\users\jameson\Temp"`
    - `HKLM\System\CurrentControlSet\Control\Session Manager\Environment` $\rightarrow$ `TMPDIR="C:\windows\temp"`
    - `C:\users\jameson\AppData\Local\JetBrains\Toolbox\.settings.json` (`{}` stub to prevent `RiderPathLocator` `DirectoryNotFoundException`).
- **Installer & Direct Launcher Scripts**:
  - Apply/re-apply fix: [`fixes/cities-skylines-2/apply_cities2_fix.sh`](file:///Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/apply_cities2_fix.sh)
  - Direct game launcher (bypasses Paradox Launcher): [`open_cities_skylines_2.sh`](file:///Users/jameson/agy-proj/mac-win-steam/open_cities_skylines_2.sh)

---

## 4. Rebuilding Everything From Scratch

Yes—if you ever wipe the wrapper or set up a new Apple Silicon Mac from scratch, everything is automated in scripts inside this repository:

### Step 1: Build the Sikarugir Wrapper, Wine 10.0 Prefix, D3DMetal/MSync, and Install Windows Steam
```bash
/Users/jameson/agy-proj/mac-win-steam/setup_windows_steam.sh
```
What [`setup_windows_steam.sh`](file:///Users/jameson/agy-proj/mac-win-steam/setup_windows_steam.sh) does automatically:
1. Installs `Sikarugir Creator.app` via Homebrew if not present.
2. Downloads `WS12WineSikarugir10.0_6.tar.xz` (Wine 10.0 + D3DMetal + MSync) and `Template-1.0.11.tar.xz`.
3. Assembles [`~/Applications/Sikarugir/Steam.app`](file:///Users/jameson/Applications/Sikarugir/Steam.app) and configures [`Info.plist`](file:///Users/jameson/Applications/Sikarugir/Steam.app/Contents/Info.plist) (`D3DMETAL=1`, `WINEMSYNC=1`, `WINEESYNC=1`).
4. Initializes the 64-bit Windows 10 prefix and silently installs `SteamSetup.exe /S`.
5. Applies all Wine registry settings (`SteamDeck=1`, `TMPDIR=C:\users\jameson\Temp`, and `CapcomArcade2ndStadium.exe` `winegstreamer=""`).
6. Creates and signs [`~/Applications/Steam (Windows).app`](file:///Users/jameson/Applications/Steam%20(Windows).app).

### Step 2: Apply Game-Specific Fixes
```bash
# For Cities: Skylines II:
/Users/jameson/agy-proj/mac-win-steam/fixes/cities-skylines-2/apply_cities2_fix.sh

# For Capcom Arcade 2nd Stadium:
/Users/jameson/agy-proj/mac-win-steam/fixes/re-engine-vc1/apply_capcom_fix.sh
```

---

## 5. Useful Commands for Running `wine` Directly in Terminal

When running `wine` commands from macOS Terminal against the Sikarugir wrapper, always export `WINEPREFIX`, `DYLD_FALLBACK_LIBRARY_PATH`, `WINEMSYNC=1`, and `WINEESYNC=1`:

```bash
SIKARUGIR_APP="$HOME/Applications/Sikarugir/Steam.app"
WINE_BIN="$SIKARUGIR_APP/Contents/SharedSupport/wine/bin/wine"
export WINEPREFIX="$SIKARUGIR_APP/Contents/SharedSupport/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$SIKARUGIR_APP/Contents/Frameworks:$SIKARUGIR_APP/Contents/SharedSupport/wine/lib"
export WINEMSYNC=1
export WINEESYNC=1

# Example: Query registry or launch a Steam AppID
"$WINE_BIN" reg query "HKCU\\Environment"
"$WINE_BIN" "C:\\Program Files (x86)\\Steam\\steam.exe" -applaunch 1755910
```
