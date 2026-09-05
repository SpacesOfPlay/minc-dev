import ext_libc;

// Win32 / WGL bindings (Windows).

// --- Win32 constants ---
const u32 CP_UTF8 = 65001;

const u32 WM_CLOSE = 16;
const u32 WM_SYSCOMMAND = 274;
const u32 WM_ERASEBKGND = 20;
const u32 WM_SIZE = 5;
const u32 WM_SETCURSOR = 32;
const u32 WM_LBUTTONDOWN = 513;
const u32 WM_RBUTTONDOWN = 516;
const u32 WM_MBUTTONDOWN = 519;
const u32 WM_LBUTTONUP = 514;
const u32 WM_RBUTTONUP = 517;
const u32 WM_MBUTTONUP = 520;
const u32 WM_MOUSEMOVE = 512;
const u32 WM_MOUSELEAVE = 675;
const u32 WM_MOUSEWHEEL = 522;
const u32 WM_MOUSEHWHEEL = 526;
const u32 WM_CHAR = 258;
const u32 WM_KEYDOWN = 256;
const u32 WM_SYSKEYDOWN = 260;
const u32 WM_KEYUP = 257;
const u32 WM_SYSKEYUP = 261;
const u32 WM_QUIT = 18;

const u32 WS_CAPTION = 12582912;
const u32 WS_SYSMENU = 524288;
const u32 WS_CLIPCHILDREN = 33554432;
const u32 WS_CLIPSIBLINGS = 67108864;
const u32 WS_EX_APPWINDOW = 262144;
const u32 WS_EX_WINDOWEDGE = 256;
const u32 WS_POPUP = 2147483648;
const u32 WS_VISIBLE = 268435456;
const u32 WS_MAXIMIZEBOX = 65536;
const u32 WS_MINIMIZEBOX = 131072;
const u32 WS_SIZEBOX = 262144;

const u32 SWP_FRAMECHANGED = 32;
const u32 SWP_SHOWWINDOW = 64;

const i32 GWL_STYLE = 0 - 16;

const u32 CS_HREDRAW = 1;
const u32 CS_VREDRAW = 2;
const u32 CS_OWNDC = 32;

const u32 MONITOR_DEFAULTTONEAREST = 2;

const i32 CW_USEDEFAULT = cast(i32, 2147483648);
const i32 SW_SHOW = 5;
const u32 PM_REMOVE = 1;

const i32 VK_SHIFT = 16;
const i32 VK_CONTROL = 17;
const i32 VK_MENU = 18;
const i32 VK_LWIN = 91;
const i32 VK_RWIN = 92;

const i32 SM_CXSCREEN = 0;
const i32 SM_CYSCREEN = 1;

const u32 CF_UNICODETEXT = 13;
const u32 GMEM_MOVEABLE = 2;
const u32 TME_LEAVE = 2;
const i32 SIZE_MINIMIZED = 1;
const u32 SC_SCREENSAVE = 61760;
const u32 SC_MONITORPOWER = 61808;
const u32 SC_KEYMENU = 61696;
const i32 HTCLIENT = 1;
const u32 CURSOR_SHOWING = 1;

const i32 FALSE = 0;
const i32 TRUE = 1;

const i32 SW_HIDE = 0;
const u32 WS_EX_WINDOWEDGE_BIT = 256;
const u32 WS_EX_CLIENTEDGE     = 512;
const u32 WS_EX_OVERLAPPEDWINDOW = 768;
const u32 PFD_TYPE_RGBA        = 0;
const u32 PFD_DOUBLEBUFFER     = 1;
const u32 PFD_DRAW_TO_WINDOW   = 4;
const u32 PFD_SUPPORT_OPENGL   = 32;

const void* HWND_TOP = null;
const void* IDC_ARROW = cast(void*, 32512);
const void* IDI_WINLOGO = cast(void*, 32517);

// --- Win32 word/result macros (pure bit math) ---
i32 LOWORD(i64 v) { return cast(i32, v & 65535); }
i32 HIWORD(i64 v) { return cast(i32, (v >> 16) & 65535); }
i32 GET_X_LPARAM(i64 lp) { return cast(i32, cast(i16, cast(u16, lp & 65535))); }
i32 GET_Y_LPARAM(i64 lp) { return cast(i32, cast(i16, cast(u16, (lp >> 16) & 65535))); }
bool SUCCEEDED(i32 hr) { return hr >= 0; }

// --- Win32 entry points (extern bindings) ---
// Many Win32 functions exist only as `NameA` (ANSI) / `NameW` (Unicode);
// the bare `Name` is provided as a thin wrapper to the real symbol.
//
// kernel32.dll
extern "kernel32.dll" {
    void* LoadLibraryA(u8* name);
    void* GetProcAddress(void* mod, u8* name);
    i32 FreeLibrary(void* mod);
    void Sleep(u32 ms);
}
extern "user32.dll" i32 IsIconic(void* hWnd);
extern "kernel32.dll" {
    void* GetModuleHandleA(u8* name);
    void* GetModuleHandleW(u16* name);
}
void* GetModuleHandle(u8* name) { return GetModuleHandleA(name); }
extern "kernel32.dll" i32 MultiByteToWideChar(u32 cp, u32 flags, u8* src, i32 srclen, u16* dst, i32 dstlen);
// Read back a window's title and class.
extern "user32.dll" {
    i32 GetWindowTextW(void* hWnd, u16* buf, i32 maxCount);
    i32 GetWindowTextLengthW(void* hWnd);
}
extern "kernel32.dll" {
    i32 WideCharToMultiByte(u32 cp, u32 flags, u16* src, i32 srclen, u8* dst, i32 dstlen, u8* defchar, i32* useddef);
    void* GlobalAlloc(u32 flags, i64 bytes);
    void* GlobalFree(void* h);
    void* GlobalLock(void* h);
    i32 GlobalUnlock(void* h);
    void* LocalFree(void* h);
}
extern "shell32.dll" u16** CommandLineToArgvW(u16* cmdline, i32* o_argc);
extern "kernel32.dll" {
    u32 GetLastError();
    i32 SetConsoleOutputCP(u32 codepage);
}

// user32.dll
extern "user32.dll" {
    i32 GetClientRect(void* hWnd, RECT* rect);
    i32 GetWindowRect(void* hWnd, RECT* rect);
}
// LoadImageW + MAKEINTRESOURCEW pair; load system cursors (IDC_ARROW
// etc.) by id. MAKEINTRESOURCEW in windows.h is just a cast.
extern "user32.dll" void* LoadImageW(void* hInst, u16* name, u32 type, i32 cx, i32 cy, u32 fuLoad);
u16* MAKEINTRESOURCEW(u32 id) { return cast(u16*, cast(u64, id)); }
// QueryPerformanceCounter / QueryPerformanceFrequency: defined in
// (ext_libc) over minc's qpc/qpf builtins. 
extern "user32.dll" {
    void* WindowFromPoint(POINT pt);
    i32 PtInRect(RECT* lprc, POINT pt);
    void* GetForegroundWindow();
}
// LoadImage flags (winuser.h).
const u32 IMAGE_CURSOR = 2;
const u32 LR_DEFAULTSIZE = 64;
const u32 LR_SHARED = 32768;
extern "user32.dll" {
    void* MonitorFromWindow(void* hWnd, u32 flags);
    void* MonitorFromPoint(POINT pt, u32 flags);
    i32 GetMonitorInfoW(void* hMon, MONITORINFO* mi);
}
i32 GetMonitorInfo(void* hMon, MONITORINFO* mi) { return GetMonitorInfoW(hMon, mi); }
extern "user32.dll" {
    i32 AdjustWindowRectEx(RECT* rect, u32 style, i32 menu, u32 exStyle);
    i64 SetWindowLongPtrW(void* hWnd, i32 index, i64 newVal);
}
i64 SetWindowLongPtr(void* hWnd, i32 index, i64 newVal) { return SetWindowLongPtrW(hWnd, index, newVal); }
extern "user32.dll" {
    i32 SetWindowPos(void* hWnd, void* after, i32 x, i32 y, i32 cx, i32 cy, u32 flags);
    void* GetDC(void* hWnd);
    i32 GetSystemMetrics(i32 idx);
    u16 RegisterClassW(WNDCLASSW* cls);
    void* CreateWindowExW(u32 exStyle, u16* cls, u16* title, u32 style, i32 x, i32 y, i32 w, i32 h, void* parent, void* menu, void* inst, void* param);
    i32 ShowWindow(void* hWnd, i32 cmd);
    i32 DestroyWindow(void* hWnd);
    i32 UnregisterClassW(u16* cls, void* inst);
    i32 PeekMessageW(MSG* msg, void* hWnd, u32 min, u32 max, u32 remove);
    i32 TranslateMessage(MSG* msg);
}
extern "user32.dll" i64 DispatchMessageW(MSG* msg);
i64 DispatchMessage(MSG* msg) { return DispatchMessageW(msg); }
extern "user32.dll" {
    i32 ReleaseDC(void* hWnd, void* hDC);
    i32 ClientToScreen(void* hWnd, POINT* pt);
    i32 ScreenToClient(void* hWnd, POINT* pt);
    i32 GetCursorPos(POINT* pt);
    i32 SetCursorPos(i32 x, i32 y);
    void* SetCursor(void* hCursor);
    void* SetCapture(void* hWnd);
    i32 ReleaseCapture();
    i32 ClipCursor(RECT* r);
    i64 DefWindowProcW(void* hWnd, u32 msg, u64 wParam, i64 lParam);
    void PostQuitMessage(i32 code);
    i32 PostMessageW(void* hWnd, u32 msg, u64 wParam, i64 lParam);
}
i32 PostMessage(void* hWnd, u32 msg, u64 wParam, i64 lParam) { return PostMessageW(hWnd, msg, wParam, lParam); }
extern "user32.dll" {
    i32 TrackMouseEvent(TRACKMOUSEEVENT* tme);
    i32 ShowCursor(i32 show);
    i32 GetCursorInfo(CURSORINFO* ci);
    i32 GetKeyState(i32 vk);
    void* LoadCursorW(void* inst, void* name);
}
void* LoadCursor(void* inst, void* name) { return LoadCursorW(inst, name); }
extern "user32.dll" void* LoadIconW(void* inst, void* name);
void* LoadIcon(void* inst, void* name) { return LoadIconW(inst, name); }
extern "user32.dll" {
    i32 OpenClipboard(void* hWnd);
    i32 CloseClipboard();
    i32 EmptyClipboard();
    void* GetClipboardData(u32 fmt);
    void* SetClipboardData(u32 fmt, void* hMem);
}

// gdi32.dll
extern "gdi32.dll" {
    i32 ChoosePixelFormat(void* hdc, PIXELFORMATDESCRIPTOR* pfd);
    i32 SetPixelFormat(void* hdc, i32 fmt, PIXELFORMATDESCRIPTOR* pfd);
    i32 DescribePixelFormat(void* hdc, i32 fmt, u32 size, PIXELFORMATDESCRIPTOR* pfd);
    i32 GetPixelFormat(void* hdc);
    i32 SwapBuffers(void* hdc);
    void* GetStockObject(i32 i);
}
// used as default background to avoid white flash on launch
const i32 BLACK_BRUSH = 4;

// opengl32.dll; WGL context API
extern "opengl32.dll" {
    void* wglCreateContext(void* hdc);
    i32 wglMakeCurrent(void* hdc, void* ctx);
    i32 wglDeleteContext(void* ctx);
    void* wglGetProcAddress(u8* name);
    void* wglGetCurrentDC();
    void* wglGetCurrentContext();
}

// msvcrt.dll; wide strlen
extern "msvcrt.dll" u64 wcslen(u16* s);

// --- additional Win32 surface (raw input, GDI icons, console
// attachment, etc.) ---

// Window messages.
const u32 WM_SETFOCUS = 7;
const u32 WM_KILLFOCUS = 8;
const u32 WM_ENTERSIZEMOVE = 561;
const u32 WM_EXITSIZEMOVE = 562;
const u32 WM_TIMER = 275;
const u32 WM_DROPFILES = 563;
const u32 WM_DISPLAYCHANGE = 126;
const u32 WM_NCHITTEST = 132;
const u32 WM_NCLBUTTONDOWN = 161;
const u32 WM_INPUT = 255;
const u32 WM_SETICON = 128;

// SetWindowPos / SWP flags.
const u32 SWP_HIDEWINDOW = 128;
const u32 SWP_NOZORDER = 4;
const u32 SWP_NOACTIVATE = 16;

// Hit-test / timer / wheel / icon / RawInput constants.
const i32 HTCAPTION = 2;
const u32 USER_TIMER_MINIMUM = 10;
const i32 WHEEL_DELTA = 120;
const u32 RIDEV_REMOVE = 1;
const u32 RID_INPUT = 0x10000003;
const u32 MOUSE_MOVE_ABSOLUTE = 1;
const u32 ICON_BIG = 1;
const u32 ICON_SMALL = 0;
const u32 BI_BITFIELDS = 3;
const u32 DIB_RGB_COLORS = 0;

// GetSystemMetrics indices.
const i32 SM_CXICON = 11;
const i32 SM_CYICON = 12;
const i32 SM_CXSMICON = 49;
const i32 SM_CYSMICON = 50;
const i32 SM_SWAPBUTTON = 23;

// Virtual key codes.
const i32 VK_LBUTTON = 1;
const i32 VK_RBUTTON = 2;
const i32 VK_MBUTTON = 4;

// MonitorFromPoint flags.
const u32 MONITOR_DEFAULTTONULL = 0;
const u32 MONITOR_DEFAULTTOPRIMARY = 1;
const u32 MONITOR_DEFAULTTONEAREST = 2;

// Console attach.
const u32 ATTACH_PARENT_PROCESS = 0xFFFFFFFF;

// kernel32; console + threads + timing.
extern "kernel32.dll" {
    i32 AllocConsole();
    i32 AttachConsole(u32 dwProcessId);
    u32 GetConsoleOutputCP();
}

// user32; windowing entries.
extern "user32.dll" {
    i32 SetWindowTextW(void* hWnd, u16* lpString);
    u64 SetTimer(void* hWnd, u64 nIDEvent, u32 uElapse, void* lpTimerFunc);
    i32 KillTimer(void* hWnd, u64 uIDEvent);
    i16 GetAsyncKeyState(i32 vKey);
    i64 SendMessageW(void* hWnd, u32 msg, u64 wParam, i64 lParam);
}
i64 SendMessage(void* hWnd, u32 msg, u64 wParam, i64 lParam) { return SendMessageW(hWnd, msg, wParam, lParam); }
extern "user32.dll" {
    i32 GetSystemMetrics(i32 nIndex);
    void* MonitorFromPoint(POINT pt, u32 dwFlags);
    void* GetDC(void* hWnd);
    i32 ReleaseDC(void* hWnd, void* hDc);
    void* LoadCursorW(void* hInst, u16* name);
    void* CreateIconIndirect(ICONINFO* piconinfo);
    i32 DestroyIcon(void* hIcon);
}

// gdi32; DIB + bitmap entries for the icon path.
extern "gdi32.dll" {
    void* CreateDIBSection(void* hdc, BITMAPINFO* bmi, u32 usage, void** ppvBits, void* hSection, u32 offset);
    void* CreateBitmap(i32 nWidth, i32 nHeight, u32 nPlanes, u32 nBitCount, void* lpBits);
    i32 DeleteObject(void* obj);
}

// user32; raw input + drag-and-drop.
extern "user32.dll" {
    i32 RegisterRawInputDevices(RAWINPUTDEVICE* devs, u32 num, u32 cbSize);
    u32 GetRawInputData(void* hRawInput, u32 uiCommand, void* pData, u32* pcbSize, u32 cbSizeHeader);
}
extern "shell32.dll" {
    u32 DragQueryFileW(void* hDrop, u32 iFile, u16* lpszFile, u32 cch);
    void DragFinish(void* hDrop);
    void DragAcceptFiles(void* hWnd, i32 fAccept);
}

// Wheel-delta extractor (a macro in windowsx.h; modelled as a function).
i16 GET_WHEEL_DELTA_WPARAM(u64 wParam) { return cast(i16, cast(i32, (wParam >> 16) & 0xFFFF)); }
