import ext_libc;

// D3D11 import-linked entry points (Windows).

when os(windows) {
    extern "d3d11.dll" i32 D3D11CreateDeviceAndSwapChain(void* adapter, i32 driverType, void* software, u32 flags, void* featureLevels, u32 numFeatureLevels, u32 sdkVersion, void* swapChainDesc, void** swapChain, void** device, i32* featureLevel, void** deviceContext);
    // Runtime HLSL compiler (d3dcompiler_47.dll).
    extern "d3dcompiler_47.dll" i32 D3DCompile(void* src, u64 srcLen, u8* name, void* defs, void* inc, u8* entry, u8* target, u32 flags1, u32 flags2, void** code, void** errmsgs);
    extern "kernel32.dll" void* LoadLibraryA(u8* name);
    extern "kernel32.dll" void* GetProcAddress(void* hModule, u8* lpProcName);
}
// HRESULT E_FAIL (winerror.h, severity-failure + facility 4).
const i32 E_FAIL = 0x80004005;
// D3D_COMPILE_STANDARD_FILE_INCLUDE; sentinel pD3DInclude that tells
// D3DCompile to use the standard #include handler. d3dcompiler.h
// defines it as `((ID3DInclude*)(UINT_PTR)1)`; modelled as a typed
// pointer of value 1 (it's never dereferenced by user code).
const void* D3D_COMPILE_STANDARD_FILE_INCLUDE = cast(void*, 1);
