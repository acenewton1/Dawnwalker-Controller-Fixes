// Dawnwalker Controller + Keyboard Fix
// Native x64 version.dll proxy. No CRT and no third-party mod loader.
//
// Purpose:
// - Leave keyboard and controller input untouched.
// - Filter physical mouse input only while Dawnwalker is the foreground window.
// - F8 toggles the filter on/off.
//
// This build does not use sockets, WinHTTP, WinINet, Winsock, URLMon,
// networking APIs, global low-level mouse hooks, or Raw Input registration changes.

extern "C" {

typedef void* HANDLE;
typedef HANDLE HINSTANCE;
typedef HANDLE HWND;
typedef HANDLE HCURSOR;
typedef unsigned int UINT;
typedef unsigned int DWORD;
typedef int BOOL;
typedef unsigned long long ULONG_PTR;
typedef unsigned long long WPARAM;
typedef long long LPARAM;
typedef long long LRESULT;
typedef long long LONG_PTR;

typedef LRESULT (__stdcall *WNDPROC)(HWND, UINT, WPARAM, LPARAM);
typedef BOOL (__stdcall *WNDENUMPROC)(HWND, LPARAM);
typedef DWORD (__stdcall *LPTHREAD_START_ROUTINE)(void*);

struct RAWINPUTHEADER {
    DWORD dwType;
    DWORD dwSize;
    HANDLE hDevice;
    WPARAM wParam;
};

__declspec(dllimport) HANDLE __stdcall CreateThread(
    void*, ULONG_PTR, LPTHREAD_START_ROUTINE, void*, DWORD, DWORD*);
__declspec(dllimport) void __stdcall Sleep(DWORD);
__declspec(dllimport) DWORD __stdcall GetCurrentProcessId(void);
__declspec(dllimport) BOOL __stdcall DisableThreadLibraryCalls(HINSTANCE);

__declspec(dllimport) BOOL __stdcall EnumWindows(WNDENUMPROC, LPARAM);
__declspec(dllimport) DWORD __stdcall GetWindowThreadProcessId(HWND, DWORD*);
__declspec(dllimport) BOOL __stdcall IsWindowVisible(HWND);
__declspec(dllimport) LONG_PTR __stdcall SetWindowLongPtrW(HWND, int, LONG_PTR);
__declspec(dllimport) LRESULT __stdcall CallWindowProcW(
    WNDPROC, HWND, UINT, WPARAM, LPARAM);
__declspec(dllimport) LRESULT __stdcall DefWindowProcW(
    HWND, UINT, WPARAM, LPARAM);
__declspec(dllimport) UINT __stdcall GetRawInputData(
    HANDLE, UINT, void*, UINT*, UINT);
__declspec(dllimport) HWND __stdcall GetForegroundWindow(void);
__declspec(dllimport) HCURSOR __stdcall SetCursor(HCURSOR);
}

static_assert(sizeof(RAWINPUTHEADER) == 24, "RAWINPUTHEADER layout mismatch");

#define TRUE 1
#define FALSE 0
#define DLL_PROCESS_ATTACH 1
#define GWLP_WNDPROC (-4)
#define VK_F8 0x77

#define WM_INPUT 0x00FF
#define WM_SETCURSOR 0x0020
#define WM_KEYDOWN 0x0100
#define WM_SYSKEYDOWN 0x0104
#define WM_MOUSEMOVE 0x0200
#define WM_LBUTTONDOWN 0x0201
#define WM_LBUTTONUP 0x0202
#define WM_LBUTTONDBLCLK 0x0203
#define WM_RBUTTONDOWN 0x0204
#define WM_RBUTTONUP 0x0205
#define WM_RBUTTONDBLCLK 0x0206
#define WM_MBUTTONDOWN 0x0207
#define WM_MBUTTONUP 0x0208
#define WM_MBUTTONDBLCLK 0x0209
#define WM_MOUSEWHEEL 0x020A
#define WM_XBUTTONDOWN 0x020B
#define WM_XBUTTONUP 0x020C
#define WM_XBUTTONDBLCLK 0x020D
#define WM_MOUSEHWHEEL 0x020E
#define WM_MOUSELEAVE 0x02A3

#define RID_HEADER 0x10000005
#define RIM_TYPEMOUSE 0
#define INVALID_UINT 0xFFFFFFFFu

static volatile BOOL g_enabled = TRUE;
static HWND g_gameWindow = 0;
static WNDPROC g_originalWndProc = 0;
static DWORD g_processId = 0;

static BOOL IsBlockedMouseMessage(UINT msg) {
    switch (msg) {
        case WM_MOUSEMOVE:
        case WM_LBUTTONDOWN:
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
        case WM_RBUTTONDOWN:
        case WM_RBUTTONUP:
        case WM_RBUTTONDBLCLK:
        case WM_MBUTTONDOWN:
        case WM_MBUTTONUP:
        case WM_MBUTTONDBLCLK:
        case WM_MOUSEWHEEL:
        case WM_XBUTTONDOWN:
        case WM_XBUTTONUP:
        case WM_XBUTTONDBLCLK:
        case WM_MOUSEHWHEEL:
        case WM_MOUSELEAVE:
            return TRUE;
        default:
            return FALSE;
    }
}

static BOOL __stdcall FindGameWindowProc(HWND hwnd, LPARAM) {
    if (!IsWindowVisible(hwnd)) return TRUE;

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);

    if (pid == g_processId) {
        g_gameWindow = hwnd;
        return FALSE;
    }

    return TRUE;
}

static LRESULT __stdcall HookWndProc(
    HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {

    // Toggle only on the initial F8 keydown, not keyboard auto-repeat.
    if ((msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) && wParam == VK_F8) {
        const BOOL wasAlreadyDown = (lParam & (1LL << 30)) != 0;
        if (!wasAlreadyDown) g_enabled = !g_enabled;
        return 0;
    }

    const BOOL active = g_enabled && (GetForegroundWindow() == hwnd);

    if (active) {
        // Filter only Raw Input packets whose device type is mouse.
        // Keyboard and controller/HID input are passed through untouched.
        if (msg == WM_INPUT) {
            RAWINPUTHEADER header;
            UINT size = (UINT)sizeof(header);
            UINT result = GetRawInputData(
                (HANDLE)lParam,
                RID_HEADER,
                &header,
                &size,
                (UINT)sizeof(RAWINPUTHEADER));

            if (result != INVALID_UINT && header.dwType == RIM_TYPEMOUSE) {
                // Let DefWindowProc perform normal Raw Input cleanup,
                // without forwarding the physical mouse packet into the game.
                return DefWindowProcW(hwnd, msg, wParam, lParam);
            }
        }

        // Block legacy mouse move/button/wheel messages.
        if (IsBlockedMouseMessage(msg)) {
            SetCursor(0);
            return 0;
        }

        // Hide the normal hardware pointer while the filter is enabled.
        // The cursor is not pinned or repositioned.
        if (msg == WM_SETCURSOR) {
            SetCursor(0);
            return 1;
        }
    }

    if (g_originalWndProc) {
        return CallWindowProcW(
            g_originalWndProc, hwnd, msg, wParam, lParam);
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static DWORD __stdcall InstallThread(void*) {
    g_processId = GetCurrentProcessId();

    // Dawnwalker creates its main window after version.dll is loaded.
    // Wait up to 30 seconds for the visible window, subclass it once,
    // then exit this worker thread.
    for (DWORD tries = 0; tries < 120; ++tries) {
        g_gameWindow = 0;
        EnumWindows(FindGameWindowProc, 0);

        if (g_gameWindow) {
            LONG_PTR previous = SetWindowLongPtrW(
                g_gameWindow,
                GWLP_WNDPROC,
                (LONG_PTR)HookWndProc);

            if (previous != 0) {
                g_originalWndProc = (WNDPROC)previous;
                return 0;
            }
        }

        Sleep(250);
    }

    return 0;
}

extern "C" BOOL __stdcall DllMain(
    HINSTANCE hinst, DWORD reason, void*) {

    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinst);
        CreateThread(0, 0, InstallThread, 0, 0, 0);
    }

    return TRUE;
}
