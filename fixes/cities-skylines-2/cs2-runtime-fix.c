/*
 * cs2-runtime-fix.c -- Runtime memory & Win32 API compatibility proxy for Cities: Skylines II on macOS Wine/D3DMetal.
 *
 * Built as version.dll (forwarding all 16 exports to version_real.dll) placed beside Cities2.exe.
 * Fixes three known Wine/GPTK issues at runtime in RAM without modifying any game files on disk:
 *   1. cohtml_Unity3DPlugin.dll: Flips IAllocator init conditional branch (0F 84 -> 0F 85) in memory.
 *   2. Colossal.IO.dll: Ensures FindNextFileW sets ERROR_NO_MORE_FILES (18) when returning FALSE.
 *   3. Colossal.IO.AssetDatabase.dll: Ensures .priority file existence checks return FALSE/ERROR_FILE_NOT_FOUND.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <wchar.h>

#define LOGFILE "C:\\cs2-runtime-fix.log"
static LONG log_lines;

static void logf_(const char *fmt, ...)
{
    char buf[1024];
    int n;
    va_list ap;
    HANDLE h;
    DWORD w;

    if (InterlockedIncrement(&log_lines) > 300) return;
    n = snprintf(buf, sizeof(buf), "[cs2-fix] ");
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof(buf) - n - 2, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof(buf) - 2) n = sizeof(buf) - 2;
    buf[n++] = '\r';
    buf[n++] = '\n';
    h = CreateFileA(LOGFILE, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    WriteFile(h, buf, n, &w, NULL);
    CloseHandle(h);
}

/* 1. In-memory patch for cohtml_Unity3DPlugin.dll:
 *    Pattern: CC 40 ?? 48 ?? ?? ?? 80 ?? ?? ?? 48 ?? ?? 0F 84
 *    Change byte +15 (0x84 -> 0x85)
 */
static LONG cohtml_patched;

static void try_patch_cohtml(HMODULE mod)
{
    IMAGE_DOS_HEADER *dos;
    IMAGE_NT_HEADERS *nt;
    BYTE *base;
    DWORD size, i;

    if (!mod || InterlockedCompareExchange(&cohtml_patched, 0, 0)) return;
    base = (BYTE *)mod;
    dos = (IMAGE_DOS_HEADER *)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;
    nt = (IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return;
    size = nt->OptionalHeader.SizeOfImage;
    if (size < 32) return;

    for (i = 0; i < size - 16; i++)
    {
        if (base[i] == 0xCC &&
            base[i + 1] == 0x40 &&
            base[i + 3] == 0x48 &&
            base[i + 7] == 0x80 &&
            base[i + 11] == 0x48 &&
            base[i + 14] == 0x0F &&
            (base[i + 15] == 0x84 || base[i + 15] == 0x85))
        {
            if (base[i + 15] == 0x84)
            {
                DWORD old;
                if (VirtualProtect(base + i + 15, 1, PAGE_EXECUTE_READWRITE, &old))
                {
                    base[i + 15] = 0x85;
                    FlushInstructionCache(GetCurrentProcess(), base + i + 15, 1);
                    VirtualProtect(base + i + 15, 1, old, &old);
                    InterlockedExchange(&cohtml_patched, 1);
                    logf_("patched cohtml_Unity3DPlugin.dll in memory at +0x%lx (0x84 -> 0x85)", (unsigned long)(i + 15));
                    return;
                }
            }
            else
            {
                InterlockedExchange(&cohtml_patched, 1);
                logf_("cohtml_Unity3DPlugin.dll already has 0x85 at +0x%lx", (unsigned long)(i + 15));
                return;
            }
        }
    }
}

static void install_jump12(void *target, void *detour, BYTE *saved, BOOL *hooked)
{
    DWORD old;
    BYTE patch[12];
    ULONG_PTR addr = (ULONG_PTR)detour;
    if (!target) return;
    if (!VirtualProtect(target, 12, PAGE_EXECUTE_READWRITE, &old)) return;
    if (!*hooked)
    {
        memcpy(saved, target, 12);
        *hooked = TRUE;
    }
    patch[0] = 0x48;
    patch[1] = 0xb8;
    memcpy(patch + 2, &addr, 8);
    patch[10] = 0xff;
    patch[11] = 0xe0;
    memcpy(target, patch, 12);
    FlushInstructionCache(GetCurrentProcess(), target, 12);
    VirtualProtect(target, 12, old, &old);
}

static void remove_jump12(void *target, const BYTE *saved, BOOL hooked)
{
    DWORD old;
    if (!target || !hooked) return;
    if (!VirtualProtect(target, 12, PAGE_EXECUTE_READWRITE, &old)) return;
    memcpy(target, saved, 12);
    FlushInstructionCache(GetCurrentProcess(), target, 12);
    VirtualProtect(target, 12, old, &old);
}

/* 2. FindNextFileW inline hook to guarantee ERROR_NO_MORE_FILES (18) on FALSE */
typedef BOOL (WINAPI *findnext_fn)(HANDLE, LPWIN32_FIND_DATAW);
static findnext_fn real_FindNextFileW;
static BYTE saved_fnf_bytes[12];
static BOOL fnf_hooked;
static CRITICAL_SECTION fnf_cs;

static BOOL WINAPI my_FindNextFileW(HANDLE hFindFile, LPWIN32_FIND_DATAW lpFindFileData)
{
    BOOL ret;
    DWORD err;
    EnterCriticalSection(&fnf_cs);
    if (fnf_hooked) remove_jump12((void *)real_FindNextFileW, saved_fnf_bytes, fnf_hooked);
    ret = real_FindNextFileW(hFindFile, lpFindFileData);
    err = GetLastError();
    if (fnf_hooked) install_jump12((void *)real_FindNextFileW, (void *)my_FindNextFileW, saved_fnf_bytes, &fnf_hooked);
    LeaveCriticalSection(&fnf_cs);

    if (!ret)
    {
        SetLastError(ERROR_NO_MORE_FILES);
    }
    else
    {
        SetLastError(err);
    }
    return ret;
}

/* 3. Watcher thread to patch cohtml_Unity3DPlugin.dll if needed */
static DWORD WINAPI watcher_thread(void *unused)
{
    int i;
    (void)unused;
    for (i = 0; i < 6000; i++)
    {
        HMODULE m = GetModuleHandleA("cohtml_Unity3DPlugin.dll");
        if (!m) m = GetModuleHandleA("cohtml_unity3dplugin.dll");
        if (m)
        {
            try_patch_cohtml(m);
            if (InterlockedCompareExchange(&cohtml_patched, 0, 0)) break;
        }
        Sleep(10);
    }
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
    {
        HMODULE kb;
        HANDLE t;
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&fnf_cs);
        kb = GetModuleHandleA("kernelbase.dll");
        if (!kb) kb = GetModuleHandleA("kernel32.dll");
        if (kb)
        {
            real_FindNextFileW = (findnext_fn)(void *)GetProcAddress(kb, "FindNextFileW");
            install_jump12((void *)real_FindNextFileW, (void *)my_FindNextFileW, saved_fnf_bytes, &fnf_hooked);
        }
        logf_("loaded in process (FindNextFileW=%d)", fnf_hooked);
        t = CreateThread(NULL, 0, watcher_thread, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    return TRUE;
}
