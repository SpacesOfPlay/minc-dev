// Cocoa / AppKit / Metal support (macOS/iOS): constants, menu bar, block ABI.
import objc_runtime;

// Cocoa / AppKit / Foundation constants + data globals (macOS/iOS).
// The data globals (NSApp, etc.) are declared null here and must be
// initialised at runtime from the frameworks (dlsym / sharedApplication)
// before sapp_run.

when os(macos) || os(ios) {

// NSApplication
void* NSApp;
const i64 NSApplicationActivationPolicyRegular = 0;

// NSWindow style mask (NSUInteger bitset)
const u64 NSWindowStyleMaskBorderless     = 0;
const u64 NSWindowStyleMaskTitled         = 1;
const u64 NSWindowStyleMaskClosable       = 2;
const u64 NSWindowStyleMaskMiniaturizable = 4;
const u64 NSWindowStyleMaskResizable      = 8;

const u64 NSBackingStoreBuffered = 2;

// NSEvent modifier flags (NSUInteger bitset)
const u64 NSEventModifierFlagCapsLock   = 65536;
const u64 NSEventModifierFlagShift      = 131072;
const u64 NSEventModifierFlagControl    = 262144;
const u64 NSEventModifierFlagOption     = 524288;
const u64 NSEventModifierFlagCommand    = 1048576;

// NSEvent type / subtype (used to synthesize an app-activation event)
const u64 NSEventTypeAppKitDefined            = 13;
const i32 NSEventSubtypeApplicationActivated  = 1;
// Foundation's zero point ({0,0}); a plain zero-init global.
NSPoint NSZeroPoint;
// NSEventMask = 1 << NSEventType. KeyUp type is 11.
const u64 NSEventMaskKeyUp                     = 2048;

// NSTrackingArea options (NSUInteger bitset)
const u64 NSTrackingMouseEnteredAndExited   = 1;
const u64 NSTrackingCursorUpdate            = 4;
const u64 NSTrackingActiveInKeyWindow       = 32;
const u64 NSTrackingInVisibleRect           = 512;
const u64 NSTrackingEnabledDuringMouseDrag  = 1024;
const u64 NSTrackingAssumeInside            = 256;

// NSOpenGLPixelFormatAttribute
const u32 NSOpenGLPFADoubleBuffer  = 5;
const u32 NSOpenGLPFAStereo        = 6;
const u32 NSOpenGLPFAColorSize     = 8;
const u32 NSOpenGLPFAAlphaSize     = 11;
const u32 NSOpenGLPFADepthSize     = 12;
const u32 NSOpenGLPFAStencilSize   = 13;
const u32 NSOpenGLPFASampleBuffers = 55;
const u32 NSOpenGLPFASamples       = 56;
const u32 NSOpenGLPFAMultisample   = 59;
const u32 NSOpenGLPFAAccelerated   = 73;
const u32 NSOpenGLPFAOpenGLProfile = 99;
const u32 NSOpenGLProfileVersionLegacy  = 4096;
const u32 NSOpenGLProfileVersion3_2Core = 12800;
const u32 NSOpenGLProfileVersion4_1Core = 16640;
const i32 NSOpenGLContextParameterSwapInterval = 222;
const i32 NSOpenGLContextParameterSurfaceOpacity = 236;

// Run-loop mode + pasteboard type; Cocoa NSString* globals, linked at
// load. The run-loop modes are CoreFoundation symbols (toll-free bridged,
// not Foundation); the pasteboard type is AppKit.
extern "CoreFoundation" void* NSDefaultRunLoopMode;
extern "CoreFoundation" void* NSRunLoopCommonModes;
// AppKit: used by the macOS clipboard path.
when os(macos) { extern "AppKit" void* NSPasteboardTypeString; }

const u64 NSStringEncodingUTF8 = 4;

// NSViewLayerContentsPlacement (NSInteger); used to pin the layer's
// contents corner while the window resizes.
const i64 NSViewLayerContentsPlacementScaleAxesIndependently  = 0;
const i64 NSViewLayerContentsPlacementScaleProportionallyToFit = 1;
const i64 NSViewLayerContentsPlacementScaleProportionallyToFill = 2;
const i64 NSViewLayerContentsPlacementCenter                  = 3;
const i64 NSViewLayerContentsPlacementTop                     = 4;
const i64 NSViewLayerContentsPlacementTopRight                = 5;
const i64 NSViewLayerContentsPlacementRight                   = 6;
const i64 NSViewLayerContentsPlacementBottomRight             = 7;
const i64 NSViewLayerContentsPlacementBottom                  = 8;
const i64 NSViewLayerContentsPlacementBottomLeft              = 9;
const i64 NSViewLayerContentsPlacementLeft                    = 10;
const i64 NSViewLayerContentsPlacementTopLeft                 = 11;

// NSBitmapImageRep (window-icon construction)
const u64 NSBitmapFormatAlphaNonpremultiplied = 2;   // 1 << 1

// NSWindow occlusion state (NSUInteger bitset)
const u64 NSWindowOcclusionStateVisible = 2;   // 1 << 1

// NSDragOperation (NSUInteger bitset); drag-and-drop result codes
const u64 NSDragOperationNone    = 0;
const u64 NSDragOperationCopy    = 1;
const u64 NSDragOperationLink    = 2;
const u64 NSDragOperationGeneric = 4;
const u64 NSDragOperationPrivate = 8;
const u64 NSDragOperationMove    = 16;
const u64 NSDragOperationDelete  = 32;
const u64 NSDragOperationEvery   = 18446744073709551615;   // NSUIntegerMax
// NSColorSpaceName (an NSString* global): 
// used by the macOS window-icon path.
when os(macos) { extern "AppKit" void* NSCalibratedRGBColorSpace; }

// --- Metal / MetalKit -----------------------------------------
// The one Metal C entry point (the rest of Metal is Objective-C, sent
// through the runtime bridge). Metal enum constants are in
// cocoa_metal_consts.mc.
extern "Metal" void* MTLCreateSystemDefaultDevice();
const u64 MTLCPUCacheModeDefaultCache = 0;
const u64 MTLCPUCacheModeWriteCombined = 1;

// QuartzCore CALayer filter name (an NSString* global); linked at load.
extern "QuartzCore" void* kCAFilterNearest;

// CoreGraphics colour-space name globals; the CAMetalLayer colorspace
// for sapp_desc.srgb / sapp_desc.hdr (sokol 02-Jul-2026 swapchain update).
extern "CoreGraphics" {
    void* kCGColorSpaceSRGB;
    void* kCGColorSpaceExtendedLinearDisplayP3;
}

// --- mach absolute time ---------------------------------------
// sokol_app.h's Apple frame-timing clock.
struct mach_timebase_info_data_t {
    u32 numer;
    u32 denom;
}
extern "libSystem.B.dylib" {
    u64 mach_absolute_time();
    i32 mach_timebase_info(mach_timebase_info_data_t* info);
}

// --- libdispatch (GCD) ----------------------------------------
// C entry points (in libSystem) for the frame semaphore and the
// shader-library data buffer.
extern "libSystem.B.dylib" {
    void* dispatch_semaphore_create(i64 value);
    i64   dispatch_semaphore_wait(void* sema, u64 timeout);
    i64   dispatch_semaphore_signal(void* sema);
    void* dispatch_data_create(void* buffer, i64 size, void* queue, void* destructor);
}
const u64 DISPATCH_TIME_FOREVER = 18446744073709551615;
void* DISPATCH_DATA_DESTRUCTOR_DEFAULT = null;

// --- CoreFoundation / CoreGraphics ----------------------------
// C entry points for the window-icon (CGImage from pixels) and
// cursor show/hide paths.
extern "CoreFoundation" {
    void* CFDataCreate(void* allocator, void* bytes, i64 length);
    void  CFRelease(void* cf);
}
extern "CoreGraphics" {
    void* CGColorSpaceCreateDeviceRGB();
    void* CGColorSpaceCreateWithName(void* name);
    void  CGColorSpaceRelease(void* space);
    void* CGDataProviderCreateWithCFData(void* data);
    void  CGDataProviderRelease(void* provider);
    void* CGImageCreate(u64 width, u64 height, u64 bits_per_component,
                        u64 bits_per_pixel, u64 bytes_per_row, void* space,
                        u32 bitmap_info, void* provider, void* decode,
                        bool should_interpolate, u32 intent);
    void  CGImageRelease(void* image);
    i32   CGDisplayHideCursor(u32 display);
    i32   CGDisplayShowCursor(u32 display);
    i32   CGAssociateMouseAndMouseCursorPosition(bool connected);
}
void* kCFAllocatorDefault = null;          // NULL = default allocator
const u32 kCGDirectMainDisplay      = 0;   // ignored by show/hide cursor
const u32 kCGImageAlphaLast          = 3;
const u32 kCGImageByteOrderDefault   = 0;
const u32 kCGRenderingIntentDefault  = 0;

}

// Metal enum constants (MTLPixelFormat, MTLVertexFormat, blend/
// stencil/sampler/texture/resource enums, ...) for the sokol_gfx
// Metal backend. Values are the Metal framework registry constants.

when os(macos) || os(ios) {
    const i32 MTLBlendFactorBlendAlpha = 13;
    const i32 MTLBlendFactorBlendColor = 11;
    const i32 MTLBlendFactorDestinationAlpha = 8;
    const i32 MTLBlendFactorDestinationColor = 6;
    const i32 MTLBlendFactorOne = 1;
    const i32 MTLBlendFactorOneMinusBlendAlpha = 14;
    const i32 MTLBlendFactorOneMinusBlendColor = 12;
    const i32 MTLBlendFactorOneMinusDestinationAlpha = 9;
    const i32 MTLBlendFactorOneMinusDestinationColor = 7;
    const i32 MTLBlendFactorOneMinusSource1Alpha = 18;
    const i32 MTLBlendFactorOneMinusSource1Color = 16;
    const i32 MTLBlendFactorOneMinusSourceAlpha = 5;
    const i32 MTLBlendFactorOneMinusSourceColor = 3;
    const i32 MTLBlendFactorSource1Alpha = 17;
    const i32 MTLBlendFactorSource1Color = 15;
    const i32 MTLBlendFactorSourceAlpha = 4;
    const i32 MTLBlendFactorSourceAlphaSaturated = 10;
    const i32 MTLBlendFactorSourceColor = 2;
    const i32 MTLBlendFactorZero = 0;
    const i32 MTLBlendOperationAdd = 0;
    const i32 MTLBlendOperationMax = 4;
    const i32 MTLBlendOperationMin = 3;
    const i32 MTLBlendOperationReverseSubtract = 2;
    const i32 MTLBlendOperationSubtract = 1;
    const i32 MTLCompareFunctionAlways = 7;
    const i32 MTLCompareFunctionEqual = 2;
    const i32 MTLCompareFunctionGreater = 4;
    const i32 MTLCompareFunctionGreaterEqual = 6;
    const i32 MTLCompareFunctionLess = 1;
    const i32 MTLCompareFunctionLessEqual = 3;
    const i32 MTLCompareFunctionNever = 0;
    const i32 MTLCompareFunctionNotEqual = 5;
    const i32 MTLCullModeBack = 2;
    const i32 MTLCullModeFront = 1;
    const i32 MTLCullModeNone = 0;
    const i32 MTLIndexTypeUInt16 = 0;
    const i32 MTLIndexTypeUInt32 = 1;
    const i32 MTLLoadActionClear = 2;
    const i32 MTLLoadActionDontCare = 0;
    const i32 MTLLoadActionLoad = 1;
    const i32 MTLPixelFormatASTC_10x10_LDR = 216;
    const i32 MTLPixelFormatASTC_10x10_sRGB = 198;
    const i32 MTLPixelFormatASTC_10x5_LDR = 213;
    const i32 MTLPixelFormatASTC_10x5_sRGB = 195;
    const i32 MTLPixelFormatASTC_10x6_LDR = 214;
    const i32 MTLPixelFormatASTC_10x6_sRGB = 196;
    const i32 MTLPixelFormatASTC_10x8_LDR = 215;
    const i32 MTLPixelFormatASTC_10x8_sRGB = 197;
    const i32 MTLPixelFormatASTC_12x10_LDR = 217;
    const i32 MTLPixelFormatASTC_12x10_sRGB = 199;
    const i32 MTLPixelFormatASTC_12x12_LDR = 218;
    const i32 MTLPixelFormatASTC_12x12_sRGB = 200;
    const i32 MTLPixelFormatASTC_4x4_LDR = 204;
    const i32 MTLPixelFormatASTC_4x4_sRGB = 186;
    const i32 MTLPixelFormatASTC_5x4_LDR = 205;
    const i32 MTLPixelFormatASTC_5x4_sRGB = 187;
    const i32 MTLPixelFormatASTC_5x5_LDR = 206;
    const i32 MTLPixelFormatASTC_5x5_sRGB = 188;
    const i32 MTLPixelFormatASTC_6x5_LDR = 207;
    const i32 MTLPixelFormatASTC_6x5_sRGB = 189;
    const i32 MTLPixelFormatASTC_6x6_LDR = 208;
    const i32 MTLPixelFormatASTC_6x6_sRGB = 190;
    const i32 MTLPixelFormatASTC_8x5_LDR = 210;
    const i32 MTLPixelFormatASTC_8x5_sRGB = 192;
    const i32 MTLPixelFormatASTC_8x6_LDR = 211;
    const i32 MTLPixelFormatASTC_8x6_sRGB = 193;
    const i32 MTLPixelFormatASTC_8x8_LDR = 212;
    const i32 MTLPixelFormatASTC_8x8_sRGB = 194;
    const i32 MTLPixelFormatBC1_RGBA = 130;
    const i32 MTLPixelFormatBC2_RGBA = 132;
    const i32 MTLPixelFormatBC3_RGBA = 134;
    const i32 MTLPixelFormatBC3_RGBA_sRGB = 135;
    const i32 MTLPixelFormatBC4_RSnorm = 141;
    const i32 MTLPixelFormatBC4_RUnorm = 140;
    const i32 MTLPixelFormatBC5_RGSnorm = 143;
    const i32 MTLPixelFormatBC5_RGUnorm = 142;
    const i32 MTLPixelFormatBC6H_RGBFloat = 150;
    const i32 MTLPixelFormatBC6H_RGBUfloat = 151;
    const i32 MTLPixelFormatBC7_RGBAUnorm = 152;
    const i32 MTLPixelFormatBC7_RGBAUnorm_sRGB = 153;
    const i32 MTLPixelFormatBGRA8Unorm = 80;
    const i32 MTLPixelFormatBGRA8Unorm_sRGB = 81;
    const i32 MTLPixelFormatDepth32Float = 252;
    const i32 MTLPixelFormatDepth32Float_Stencil8 = 260;
    const i32 MTLPixelFormatEAC_R11Snorm = 172;
    const i32 MTLPixelFormatEAC_R11Unorm = 170;
    const i32 MTLPixelFormatEAC_RG11Snorm = 176;
    const i32 MTLPixelFormatEAC_RG11Unorm = 174;
    const i32 MTLPixelFormatEAC_RGBA8 = 178;
    const i32 MTLPixelFormatEAC_RGBA8_sRGB = 179;
    const i32 MTLPixelFormatETC2_RGB8 = 180;
    const i32 MTLPixelFormatETC2_RGB8A1 = 182;
    const i32 MTLPixelFormatETC2_RGB8A1_sRGB = 183;
    const i32 MTLPixelFormatETC2_RGB8_sRGB = 181;
    const i32 MTLPixelFormatInvalid = 0;
    const i32 MTLPixelFormatPVRTC_RGBA_2BPP = 164;
    const i32 MTLPixelFormatPVRTC_RGBA_2BPP_sRGB = 165;
    const i32 MTLPixelFormatPVRTC_RGBA_4BPP = 166;
    const i32 MTLPixelFormatPVRTC_RGBA_4BPP_sRGB = 167;
    const i32 MTLPixelFormatPVRTC_RGB_2BPP = 160;
    const i32 MTLPixelFormatPVRTC_RGB_2BPP_sRGB = 161;
    const i32 MTLPixelFormatPVRTC_RGB_4BPP = 162;
    const i32 MTLPixelFormatPVRTC_RGB_4BPP_sRGB = 163;
    const i32 MTLPixelFormatR16Float = 25;
    const i32 MTLPixelFormatR16Sint = 24;
    const i32 MTLPixelFormatR16Snorm = 22;
    const i32 MTLPixelFormatR16Uint = 23;
    const i32 MTLPixelFormatR16Unorm = 20;
    const i32 MTLPixelFormatR32Float = 55;
    const i32 MTLPixelFormatR32Sint = 54;
    const i32 MTLPixelFormatR32Uint = 53;
    const i32 MTLPixelFormatR8Sint = 14;
    const i32 MTLPixelFormatR8Snorm = 12;
    const i32 MTLPixelFormatR8Uint = 13;
    const i32 MTLPixelFormatR8Unorm = 10;
    const i32 MTLPixelFormatRG11B10Float = 92;
    const i32 MTLPixelFormatRG16Float = 65;
    const i32 MTLPixelFormatRG16Sint = 64;
    const i32 MTLPixelFormatRG16Snorm = 62;
    const i32 MTLPixelFormatRG16Uint = 63;
    const i32 MTLPixelFormatRG16Unorm = 60;
    const i32 MTLPixelFormatRG32Float = 105;
    const i32 MTLPixelFormatRG32Sint = 104;
    const i32 MTLPixelFormatRG32Uint = 103;
    const i32 MTLPixelFormatRG8Sint = 34;
    const i32 MTLPixelFormatRG8Snorm = 32;
    const i32 MTLPixelFormatRG8Uint = 33;
    const i32 MTLPixelFormatRG8Unorm = 30;
    const i32 MTLPixelFormatRGB10A2Unorm = 90;
    const i32 MTLPixelFormatRGB9E5Float = 93;
    const i32 MTLPixelFormatRGBA16Float = 115;
    const i32 MTLPixelFormatRGBA16Sint = 114;
    const i32 MTLPixelFormatRGBA16Snorm = 112;
    const i32 MTLPixelFormatRGBA16Uint = 113;
    const i32 MTLPixelFormatRGBA16Unorm = 110;
    const i32 MTLPixelFormatRGBA32Float = 125;
    const i32 MTLPixelFormatRGBA32Sint = 124;
    const i32 MTLPixelFormatRGBA32Uint = 123;
    const i32 MTLPixelFormatRGBA8Sint = 74;
    const i32 MTLPixelFormatRGBA8Snorm = 72;
    const i32 MTLPixelFormatRGBA8Uint = 73;
    const i32 MTLPixelFormatRGBA8Unorm = 70;
    const i32 MTLPixelFormatRGBA8Unorm_sRGB = 71;
    const i32 MTLPrimitiveTypeLine = 1;
    const i32 MTLPrimitiveTypeLineStrip = 2;
    const i32 MTLPrimitiveTypePoint = 0;
    const i32 MTLPrimitiveTypeTriangle = 3;
    const i32 MTLPrimitiveTypeTriangleStrip = 4;
    const i32 MTLSamplerAddressModeClampToBorderColor = 5;
    const i32 MTLSamplerAddressModeClampToEdge = 0;
    const i32 MTLSamplerAddressModeClampToZero = 4;
    const i32 MTLSamplerAddressModeMirrorClampToEdge = 1;
    const i32 MTLSamplerAddressModeMirrorRepeat = 3;
    const i32 MTLSamplerAddressModeRepeat = 2;
    const i32 MTLSamplerBorderColorOpaqueBlack = 1;
    const i32 MTLSamplerBorderColorOpaqueWhite = 2;
    const i32 MTLSamplerBorderColorTransparentBlack = 0;
    const i32 MTLSamplerMinMagFilterLinear = 1;
    const i32 MTLSamplerMinMagFilterNearest = 0;
    const i32 MTLSamplerMipFilterLinear = 2;
    const i32 MTLSamplerMipFilterNearest = 1;
    const i32 MTLSamplerMipFilterNotMipmapped = 0;
    const i32 MTLStencilOperationDecrementClamp = 4;
    const i32 MTLStencilOperationDecrementWrap = 7;
    const i32 MTLStencilOperationIncrementClamp = 3;
    const i32 MTLStencilOperationIncrementWrap = 6;
    const i32 MTLStencilOperationInvert = 5;
    const i32 MTLStencilOperationKeep = 0;
    const i32 MTLStencilOperationReplace = 2;
    const i32 MTLStencilOperationZero = 1;
    const i32 MTLStoreActionDontCare = 0;
    const i32 MTLStoreActionMultisampleResolve = 2;
    const i32 MTLStoreActionStore = 1;
    const i32 MTLStoreActionStoreAndMultisampleResolve = 3;
    // MTLTextureType is NS_ENUM(NSUInteger); u64.
    const u64 MTLTextureType1D = 0;
    const u64 MTLTextureType1DArray = 1;
    const u64 MTLTextureType2D = 2;
    const u64 MTLTextureType2DArray = 3;
    const u64 MTLTextureType2DMultisample = 4;
    const u64 MTLTextureType3D = 7;
    const u64 MTLTextureTypeCube = 5;
    const u64 MTLTextureTypeCubeArray = 6;
    const i32 MTLVertexFormatChar2 = 4;
    const i32 MTLVertexFormatChar2Normalized = 10;
    const i32 MTLVertexFormatChar3 = 5;
    const i32 MTLVertexFormatChar3Normalized = 11;
    const i32 MTLVertexFormatChar4 = 6;
    const i32 MTLVertexFormatChar4Normalized = 12;
    const i32 MTLVertexFormatFloat = 28;
    const i32 MTLVertexFormatFloat2 = 29;
    const i32 MTLVertexFormatFloat3 = 30;
    const i32 MTLVertexFormatFloat4 = 31;
    const i32 MTLVertexFormatHalf2 = 25;
    const i32 MTLVertexFormatHalf3 = 26;
    const i32 MTLVertexFormatHalf4 = 27;
    const i32 MTLVertexFormatInt = 32;
    const i32 MTLVertexFormatInt1010102Normalized = 40;
    const i32 MTLVertexFormatInt2 = 33;
    const i32 MTLVertexFormatInt3 = 34;
    const i32 MTLVertexFormatInt4 = 35;
    const i32 MTLVertexFormatInvalid = 0;
    const i32 MTLVertexFormatShort2 = 16;
    const i32 MTLVertexFormatShort2Normalized = 22;
    const i32 MTLVertexFormatShort3 = 17;
    const i32 MTLVertexFormatShort3Normalized = 23;
    const i32 MTLVertexFormatShort4 = 18;
    const i32 MTLVertexFormatShort4Normalized = 24;
    const i32 MTLVertexFormatUChar2 = 1;
    const i32 MTLVertexFormatUChar2Normalized = 7;
    const i32 MTLVertexFormatUChar3 = 2;
    const i32 MTLVertexFormatUChar3Normalized = 8;
    const i32 MTLVertexFormatUChar4 = 3;
    const i32 MTLVertexFormatUChar4Normalized = 9;
    const i32 MTLVertexFormatUInt = 36;
    const i32 MTLVertexFormatUInt1010102Normalized = 41;
    const i32 MTLVertexFormatUInt2 = 37;
    const i32 MTLVertexFormatUInt3 = 38;
    const i32 MTLVertexFormatUInt4 = 39;
    const i32 MTLVertexFormatUShort2 = 13;
    const i32 MTLVertexFormatUShort2Normalized = 19;
    const i32 MTLVertexFormatUShort3 = 14;
    const i32 MTLVertexFormatUShort3Normalized = 20;
    const i32 MTLVertexFormatUShort4 = 15;
    const i32 MTLVertexFormatUShort4Normalized = 21;
    const i32 MTLVertexStepFunctionConstant = 0;
    const i32 MTLVertexStepFunctionPerInstance = 2;
    const i32 MTLVertexStepFunctionPerPatch = 3;
    const i32 MTLVertexStepFunctionPerVertex = 1;
    const i32 MTLWindingClockwise = 0;
    const i32 MTLWindingCounterClockwise = 1;
    const i64 MTLGPUFamilyApple1 = 1001;
    const i64 MTLGPUFamilyApple2 = 1002;
    const i64 MTLGPUFamilyApple3 = 1003;
    const i64 MTLGPUFamilyApple4 = 1004;
    const i64 MTLGPUFamilyApple5 = 1005;
    const i64 MTLGPUFamilyApple6 = 1006;
    const i64 MTLGPUFamilyApple7 = 1007;
    const i64 MTLGPUFamilyApple8 = 1008;
    const i64 MTLGPUFamilyCommon1 = 3001;
    const i64 MTLGPUFamilyCommon2 = 3002;
    const i64 MTLGPUFamilyCommon3 = 3003;
    const i64 MTLGPUFamilyMac1 = 2001;
    const i64 MTLGPUFamilyMac2 = 2002;
    const i64 MTLGPUFamilyMetal3 = 5001;
    const u32 MTLColorWriteMaskAll = 15;
    const u32 MTLColorWriteMaskAlpha = 1;
    const u32 MTLColorWriteMaskBlue = 2;
    const u32 MTLColorWriteMaskGreen = 4;
    const u32 MTLColorWriteMaskNone = 0;
    const u32 MTLColorWriteMaskRed = 8;
    const u64 MTLMutabilityDefault = 0;
    const u64 MTLMutabilityImmutable = 2;
    const u64 MTLMutabilityMutable = 1;
    const u64 MTLPipelineOptionArgumentInfo = 1;
    const u64 MTLPipelineOptionBufferTypeInfo = 2;
    const u64 MTLPipelineOptionNone = 0;
    const u64 MTLResourceCPUCacheModeDefaultCache = 0;
    const u64 MTLResourceCPUCacheModeWriteCombined = 1;
    const u64 MTLResourceHazardTrackingModeDefault = 0;
    const u64 MTLResourceHazardTrackingModeTracked = 512;
    const u64 MTLResourceHazardTrackingModeUntracked = 256;
    const u64 MTLResourceStorageModeManaged = 16;
    const u64 MTLResourceStorageModeMemoryless = 48;
    const u64 MTLResourceStorageModePrivate = 32;
    const u64 MTLResourceStorageModeShared = 0;
    const u64 MTLStorageModeShared = 0;
    const u64 MTLStorageModeManaged = 1;
    const u64 MTLStorageModePrivate = 2;
    const u64 MTLStorageModeMemoryless = 3;
    const u64 MTLTextureUsageRenderTarget = 4;
    const u64 MTLTextureUsageShaderRead = 1;
    const u64 MTLTextureUsageShaderWrite = 2;
    const u64 MTLTextureUsageUnknown = 0;
}

// Default macOS menu + foreground activation for Cocoa apps.
//
// _sapp_macos_install_default_menu() installs the standard App/Window
// menus; _sapp_macos_bring_to_front() forces a terminal-launched binary
// to the foreground. The default menu provides:
//
//   App menu       About <name>
//                  Hide <name>          Cmd+H
//                  Hide Others          Cmd+Opt+H
//                  Show All
//                  Quit <name>          Cmd+Q
//
//   Window menu    Minimize             Cmd+M
//                  Zoom
//                  Toggle Full Screen   Cmd+Ctrl+F
//
// Call _sapp_macos_install_default_menu() once at startup (after NSApp
// exists). Apps that want their own menu set NSApp.mainMenu instead.

when os(macos) && !defined(ios) {

    // Concatenate prefix + NSString. Used for "Hide <name>" etc.
    void* _sapp_macos_menu_concat(u8* prefix, void* nsstr) {
        void* prefix_str = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), prefix);
        return objc.msg_id_i(prefix_str,
            sel_registerName("stringByAppendingString:"), nsstr);
    }

    // Add a menu item. Returns the NSMenuItem so the caller can
    // adjust its modifier mask.
    void* _sapp_macos_menu_add(void* menu, void* title, void* action, void* keq) {
        return cast(fn(void*, void*, void*, void*, void*): void*, objc.raw)(
            menu, sel_registerName("addItemWithTitle:action:keyEquivalent:"),
            title, action, keq);
    }

    void _sapp_macos_install_default_menu() {
        // Process name. Used in About, Hide, and Quit titles.
        void* app_name = objc.msg_id_v(
            objc.msg_id_v(objc_getClass("NSProcessInfo"),
                sel_registerName("processInfo")),
            sel_registerName("processName"));

        // Reusable NSStrings.
        void* empty = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "");
        void* h_key = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "h");
        void* m_key = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "m");
        void* q_key = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "q");
        void* f_key = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "f");

        void* main_menu = objc.msg_id_v(
            objc.msg_id_v(objc_getClass("NSMenu"), sel_registerName("alloc")),
            sel_registerName("init"));

        // App menu. Cocoa shows the process name in bold as the first
        // menu, no matter what title the anchor item carries.
        void* app_menu_item = objc.msg_id_v(
            objc.msg_id_v(objc_getClass("NSMenuItem"), sel_registerName("alloc")),
            sel_registerName("init"));
        objc.msg_void_i(main_menu, sel_registerName("addItem:"), app_menu_item);

        void* app_menu = objc.msg_id_v(
            objc.msg_id_v(objc_getClass("NSMenu"), sel_registerName("alloc")),
            sel_registerName("init"));
        objc.msg_void_i(app_menu_item, sel_registerName("setSubmenu:"), app_menu);

        _sapp_macos_menu_add(app_menu, _sapp_macos_menu_concat("About ", app_name),
            sel_registerName("orderFrontStandardAboutPanel:"), empty);
        objc.msg_void_i(app_menu, sel_registerName("addItem:"),
            objc.msg_id_v(objc_getClass("NSMenuItem"), sel_registerName("separatorItem")));

        _sapp_macos_menu_add(app_menu, _sapp_macos_menu_concat("Hide ", app_name),
            sel_registerName("hide:"), h_key);

        // Hide Others; Cmd+Opt+H. Default key-equivalent modifier is
        // Cmd alone; override to Cmd+Option = (1<<20) | (1<<19).
        void* hide_others = _sapp_macos_menu_add(app_menu,
            objc.msg_id_i(objc_getClass("NSString"),
                sel_registerName("stringWithUTF8String:"), "Hide Others"),
            sel_registerName("hideOtherApplications:"), h_key);
        cast(fn(void*, void*, u64): void, objc.raw)(
            hide_others, sel_registerName("setKeyEquivalentModifierMask:"),
            cast(u64, 0x180000));

        _sapp_macos_menu_add(app_menu,
            objc.msg_id_i(objc_getClass("NSString"),
                sel_registerName("stringWithUTF8String:"), "Show All"),
            sel_registerName("unhideAllApplications:"), empty);

        objc.msg_void_i(app_menu, sel_registerName("addItem:"),
            objc.msg_id_v(objc_getClass("NSMenuItem"), sel_registerName("separatorItem")));

        _sapp_macos_menu_add(app_menu, _sapp_macos_menu_concat("Quit ", app_name),
            sel_registerName("terminate:"), q_key);

        // Window menu.
        void* window_menu_item = objc.msg_id_v(
            objc.msg_id_v(objc_getClass("NSMenuItem"), sel_registerName("alloc")),
            sel_registerName("init"));
        objc.msg_void_i(main_menu, sel_registerName("addItem:"), window_menu_item);

        void* window_title = objc.msg_id_i(objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "Window");
        void* window_menu = objc.msg_id_i(
            objc.msg_id_v(objc_getClass("NSMenu"), sel_registerName("alloc")),
            sel_registerName("initWithTitle:"), window_title);
        objc.msg_void_i(window_menu_item, sel_registerName("setSubmenu:"), window_menu);

        _sapp_macos_menu_add(window_menu,
            objc.msg_id_i(objc_getClass("NSString"),
                sel_registerName("stringWithUTF8String:"), "Minimize"),
            sel_registerName("performMiniaturize:"), m_key);

        _sapp_macos_menu_add(window_menu,
            objc.msg_id_i(objc_getClass("NSString"),
                sel_registerName("stringWithUTF8String:"), "Zoom"),
            sel_registerName("performZoom:"), empty);

        objc.msg_void_i(window_menu, sel_registerName("addItem:"),
            objc.msg_id_v(objc_getClass("NSMenuItem"), sel_registerName("separatorItem")));

        // Toggle Full Screen; Cmd+Ctrl+F. Cocoa toggles the item
        // title between "Enter" and "Exit" on its own. Modifier
        // override: Cmd+Control = (1<<20) | (1<<18).
        void* fs_item = _sapp_macos_menu_add(window_menu,
            objc.msg_id_i(objc_getClass("NSString"),
                sel_registerName("stringWithUTF8String:"), "Toggle Full Screen"),
            sel_registerName("toggleFullScreen:"), f_key);
        cast(fn(void*, void*, u64): void, objc.raw)(
            fs_item, sel_registerName("setKeyEquivalentModifierMask:"),
            cast(u64, 0x140000));

        // Install. setWindowsMenu lets Cocoa append the open-window
        // list under the Window menu.
        cast(fn(void*, void*, void*): void, objc.raw)(NSApp,
            sel_registerName("setMainMenu:"), main_menu);
        cast(fn(void*, void*, void*): void, objc.raw)(NSApp,
            sel_registerName("setWindowsMenu:"), window_menu);
    }

    // Force a terminal-launched (non .app) binary to the foreground.
    // The activation policy + activateIgnoringOtherApps: are not enough on
    // their own; posting an AppKit-defined application-activated event at
    // the front of the queue. Call once at startup after the window is up.
    void _sapp_macos_bring_to_front() {
        cast(fn(void*, void*, u64): void, objc.raw)(NSApp,
            sel_registerName("setActivationPolicy:"),
            cast(u64, NSApplicationActivationPolicyRegular));
        cast(fn(void*, void*, bool): void, objc.raw)(NSApp,
            sel_registerName("activateIgnoringOtherApps:"), true);

        var origin = NSPoint{ 0.0, 0.0 };
        void* ev = cast(fn(void*, void*, u64, NSPoint, u64, f64, i64, void*, i32, i64, i64): void*, objc.raw)(
            objc_getClass("NSEvent"),
            sel_registerName("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"),
            NSEventTypeAppKitDefined,
            origin,
            cast(u64, 0x40),
            cast(f64, 0.0),
            cast(i64, 0),
            null,
            NSEventSubtypeApplicationActivated,
            cast(i64, 0),
            cast(i64, 0));
        cast(fn(void*, void*, void*, bool): void, objc.raw)(NSApp,
            sel_registerName("postEvent:atStart:"), ev, true);
    }

}

when os(ios) {
    // no-op on iOS
    void _sapp_macos_install_default_menu() { }
}

// Objective-C global (no-capture) block support (macOS/iOS).
// Capturing blocks are not supported.

when os(macos) || os(ios) {

// The Apple Block ABI layout for a global, no-capture block.
struct ObjcBlockLiteral {
    void* isa;
    i32   flags;
    i32   reserved;
    void* invoke;
    void* descriptor;
}
struct ObjcBlockDescriptor {
    u64 reserved;
    u64 size;
}

ObjcBlockDescriptor _objc_block_descriptor;
void* _objc_NSConcreteGlobalBlock = null;

// Wire a static literal as a global Block that calls `invoke`, resolving
// _NSConcreteGlobalBlock from libSystem once. Returns the literal as an id,
// ready to hand to an ObjC method.
void* _objc_block_setup(ObjcBlockLiteral* lit, void* invoke) {
    if _objc_NSConcreteGlobalBlock == null {
        void* h = dlopen("/usr/lib/libSystem.B.dylib", 2);
        _objc_NSConcreteGlobalBlock = dlsym(h, "_NSConcreteGlobalBlock");
    }
    _objc_block_descriptor.reserved = 0;
    _objc_block_descriptor.size = cast(u64, sizeof(ObjcBlockLiteral));
    lit.isa = _objc_NSConcreteGlobalBlock;
    lit.flags = 268435456;   // BLOCK_IS_GLOBAL (1 << 28)
    lit.reserved = 0;
    lit.invoke = invoke;
    lit.descriptor = cast(void*, &_objc_block_descriptor);
    return cast(void*, lit);
}

}

// Cocoa / Foundation application helpers (macOS / iOS).

when os(macos) || os(ios) {

// Native bundle-path lookup: `[[NSBundle mainBundle] resourcePath].UTF8String`.
// Returns an autoreleased C string; copy it if you need it past the next 
// autorelease-pool drain.
u8* minc_get_bundle_path() {
    void* bundle = objc.msg_id_v(objc_getClass("NSBundle"), sel_registerName("mainBundle"));
    if bundle == null { return cast(u8*, ""); }
    void* res_path = objc.msg_id_v(bundle, sel_registerName("resourcePath"));
    if res_path == null { return cast(u8*, ""); }
    return cast(u8*, objc.msg_id_v(res_path, sel_registerName("UTF8String")));
}

}

// UIKit / Foundation symbols
// UIKit SDK entry points + enum constants. iOS-only.

when os(ios) {

extern "UIKit" i32 UIApplicationMain(i32 argc, u8** argv, void* principalClassName, void* delegateClassName);
extern "Foundation" void* NSStringFromClass(void* cls);
// NSString* globals: the keyboard-notification names + the userInfo key
// used to read the keyboard end frame.
extern "UIKit" void* UIKeyboardFrameEndUserInfoKey;
extern "UIKit" void* UIKeyboardDidShowNotification;
extern "UIKit" void* UIKeyboardWillHideNotification;
extern "UIKit" void* UIKeyboardDidChangeFrameNotification;

// UIPressType (tvOS remote / hardware keys): the values UIKit assigns.
const i64 UIPressTypeUpArrow    = 0;
const i64 UIPressTypeDownArrow  = 1;
const i64 UIPressTypeLeftArrow  = 2;
const i64 UIPressTypeRightArrow = 3;
const i64 UIPressTypeSelect     = 4;
const i64 UIPressTypeMenu       = 5;
const i64 UIPressTypePlayPause  = 6;
// View-controller / text-field enums the iOS backend sets.
const i64 UIModalPresentationFullScreen    = 0;
const i64 UIKeyboardTypeDefault            = 0;
const i64 UIReturnKeyDefault               = 0;
const i64 UITextAutocapitalizationTypeNone = 0;
const i64 UITextAutocorrectionTypeNo       = 1;
const i64 UITextSpellCheckingTypeNo        = 1;

}
