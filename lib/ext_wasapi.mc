import ext_libc;

// WASAPI audio constants + DLL-linked entry points (Windows).

when os(windows) {

// Win32 / WASAPI named integer constants.
const i32 FALSE = 0;
const i32 TRUE  = 1;
const u32 INFINITE = 0xFFFFFFFF;
const u32 COINIT_MULTITHREADED = 0;
const u32 CLSCTX_INPROC_SERVER = 0x1;
const u32 CLSCTX_ALL           = 0x17;
const i32 eRender = 0;
const i32 eCapture = 1;
const i32 eAll = 2;
const i32 eConsole = 0;
const i32 eMultimedia = 1;
const i32 eCommunications = 2;
const u16 WAVE_FORMAT_PCM        = 0x0001;
const u16 WAVE_FORMAT_IEEE_FLOAT = 0x0003;
const u16 WAVE_FORMAT_EXTENSIBLE = 0xFFFE;
const u32 SPEAKER_FRONT_LEFT   = 0x00000001;
const u32 SPEAKER_FRONT_RIGHT  = 0x00000002;
const u32 SPEAKER_FRONT_CENTER = 0x00000004;
const i32 AUDCLNT_SHAREMODE_SHARED              = 0;
const i32 AUDCLNT_SHAREMODE_EXCLUSIVE           = 1;
const u32 AUDCLNT_STREAMFLAGS_EVENTCALLBACK     = 0x00040000;
const u32 AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM    = 0x80000000;
const u32 AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;

// ole32.dll; COM apartment + class-instance creation. sokol calls:
//   CoInitializeEx(NULL, COINIT_MULTITHREADED)       on backend_init
//   CoCreateInstance(CLSID, NULL, CLSCTX_ALL,
//                    IID, &device_enumerator)        for the enumerator
//   CoUninitialize()                                 on backend_shutdown
//   CoTaskMemFree(p)                                 frees Activate-allocated buffers
extern "ole32.dll" {
    i32  CoInitializeEx(void* reserved, u32 dwCoInit);
    void CoUninitialize();
    // rclsid / riid are GUID* (typed strictly to match the call sites).
    i32  CoCreateInstance(GUID* rclsid, void* pUnkOuter, u32 dwClsContext,
                          GUID* riid, void** ppv);
    void CoTaskMemFree(void* pv);
}

// kernel32.dll; event + handle primitives + the audio thread.
//   CreateEvent(NULL, FALSE, FALSE, NULL) → manual-reset event
//   WaitForSingleObject(h, INFINITE)      block until WASAPI signals buffer-end
//   CloseHandle(h)                        teardown
//   CreateThread(NULL, 0, fn, arg, 0, &id) start the audio thread
//   SetEvent(h)                           signal from main → thread shutdown
extern "kernel32.dll" {
    void* CreateEventW(void* lpEventAttributes, i32 bManualReset,
                       i32 bInitialState, void* lpName);
    i32   CloseHandle(void* hObject);
    u32   WaitForSingleObject(void* hHandle, u32 dwMilliseconds);
    i32   SetEvent(void* hEvent);
    // Thread API. lpStartAddress is a function pointer
    // (DWORD WINAPI fn(LPVOID)); LPVOID is void*; lpThreadId can
    // be NULL when the caller doesn't need the thread id.
    void* CreateThread(void* lpThreadAttributes, u64 dwStackSize,
                       fn(void*): u32 lpStartAddress, void* lpParameter,
                       u32 dwCreationFlags, u32* lpThreadId);

    // CRITICAL_SECTION primitives. sokol_audio uses these for the
    // push-mode FIFO mutex (one CRITICAL_SECTION per saudio app).
    void InitializeCriticalSection(void* lpCriticalSection);
    void EnterCriticalSection(void* lpCriticalSection);
    void LeaveCriticalSection(void* lpCriticalSection);
    void DeleteCriticalSection(void* lpCriticalSection);

    // Frame-pacing helper, e.g. to let push-mode buffers drain
    // before saudio_shutdown.
    void Sleep(u32 dwMilliseconds);
}

// CreateEvent; the unsuffixed name aliased to CreateEventW (which
// the Windows macro resolves to with a NULL name).
void* CreateEvent(void* sa, i32 manual_reset, i32 initial_state, void* name) {
    return CreateEventW(sa, manual_reset, initial_state, name);
}

// COM identifiers as 16-byte mixed-endian arrays. MSFT GUIDs
// serialize with the first three fields little-endian and the
// last 8 bytes big-endian; the byte arrays below already encode
// that conversion from the GUID dotted form.
//
//   CLSID_MMDeviceEnumerator   {BCDE0395-E52F-467C-8E3D-C4579291692E}
//   IID_IMMDeviceEnumerator    {A95664D2-9614-4F35-A746-DE8DB63617E6}
//   IID_IAudioClient           {1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}
//   IID_IAudioRenderClient     {F294ACFC-3146-4483-A7BF-ADDCA7C260E2}
//   KSDATAFORMAT_SUBTYPE_IEEE_FLOAT {00000003-0000-0010-8000-00AA00389B71}
u8[16] _SAUDIO_CLSID_MMDeviceEnumerator = {
    0x95, 0x03, 0xDE, 0xBC, 0x2F, 0xE5, 0x7C, 0x46,
    0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E
};
u8[16] _SAUDIO_IID_IMMDeviceEnumerator = {
    0xD2, 0x64, 0x56, 0xA9, 0x14, 0x96, 0x35, 0x4F,
    0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6
};
u8[16] _SAUDIO_IID_IAudioClient = {
    0x4C, 0xAD, 0xB9, 0x1C, 0xFA, 0xDB, 0x32, 0x4C,
    0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2
};
u8[16] _SAUDIO_IID_IAudioRenderClient = {
    0xFC, 0xAC, 0x94, 0xF2, 0x46, 0x31, 0x83, 0x44,
    0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2
};
u8[16] _SAUDIO_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = {
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};

}  // when os(windows)
