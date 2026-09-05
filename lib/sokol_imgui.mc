// =====================================================================
// Derived from sokol_imgui.h  (https://github.com/floooh/sokol)
// Copyright (c) 2018 Andre Weissflog, zlib/libpng license
//
// Altered source: transpiled to minc (the simgui_* glue only).
// =====================================================================
// sokol + Dear ImGui (native): the simgui_* glue only; the sokol core and
// Dear ImGui come from import sokol_all + import imgui. One body for
// every OS and backend: the shaders are minc @shader functions.

@gui    // windowed app, no console window

import sokol_all;
import imgui;
// sokol_imgui.h shader as minc @shader functions, replacing the
// upstream header's per-backend source text and bytecode blobs.
//
// Interface mirrors the upstream sokol-shdc program:
//   attrs: position(0) f2, texcoord0(1) f2, color0(2) f4
//   uniform block 0 (vertex): disp_size + gamma, matching
//   _simgui_vs_params_t
//   fragment: texture(0) + sampler(0); a second fragment variant
//   declares the pair unfilterable/nonfiltering for textures that
//   cannot be filtered (R32F etc.), mirroring the upstream
//   def_shd / shd_unfilterable split.

struct SimguiVsOut {
    float4 pos;
    float2 uv;
    float4 color;
}

@gpu_layout
struct Ub_simgui_vs_params {
    float2 disp_size;
    f32 gamma;
}

@shader vertex
SimguiVsOut simgui_vs(
    @attr(0) float2 position,
    @attr(1) float2 texcoord0,
    @attr(2) float4 color0,
    @uniform(0) Ub_simgui_vs_params p
) {
    SimguiVsOut o;
    o.pos = float4{
        (position.x / p.disp_size.x - 0.5f) * 2.0f,
        (position.y / p.disp_size.y - 0.5f) * -2.0f,
        0.5f, 1.0f};
    o.uv = texcoord0;
    // abs() is a no-op on unorm vertex colors; it silences the HLSL
    // negative-base pow warning (X3571) on runtime compiles.
    o.color = float4{
        pow(abs(color0.x), p.gamma),
        pow(abs(color0.y), p.gamma),
        pow(abs(color0.z), p.gamma),
        color0.w};
    return o;
}

@shader fragment
float4 simgui_fs(
    SimguiVsOut input,
    @texture(0) Texture2D tex,
    @sampler(0) Sampler smp
) {
    return sample(tex, smp, input.uv) * input.color;
}

@shader fragment
float4 simgui_fs_unfilterable(
    SimguiVsOut input,
    @texture(0, unfilterable) Texture2D tex,
    @sampler(0, nonfiltering) Sampler smp
) {
    return sample(tex, smp, input.uv) * input.color;
}

// Shader constructors for sokol_imgui.h. The header's setup calls
// these instead of building per-backend descriptors.

sg_shader _simgui_minc_shader() {
    return sokol_make_shader(&simgui_vs_shader, &simgui_fs_shader);
}

sg_shader _simgui_minc_shader_unfilterable() {
    return sokol_make_shader(&simgui_vs_shader, &simgui_fs_unfilterable_shader);
}

// OS answer for ImGuiConfigFlags MacOSXBehaviors (Cmd vs Ctrl
// shortcuts). The web build reports false, same as the shipped
// emscripten stub.
bool _simgui_minc_is_osx() {
    when os(macos) || os(ios) {
        return true;
    }
    when !(os(macos) || os(ios)) {
        return false;
    }
}

when !os(wasm) {
/*
    simgui_log_item

    An enum with a unique item for each log message, warning, error
    and validation layer message.
*/
enum simgui_log_item_t {
    SIMGUI_LOGITEM_OK = 0,
    SIMGUI_LOGITEM_MALLOC_FAILED = 1,
    SIMGUI_LOGITEM_BUFFER_OVERFLOW = 2,
}

/*
    simgui_allocator_t

    Used in simgui_desc_t to provide custom memory-alloc and -free functions
    to sokol_imgui.h. If memory management should be overridden, both the
    alloc_fn and free_fn function must be provided (e.g. it's not valid to
    override one function but not the other).
*/
struct simgui_allocator_t {
    fn(u64, void*): void* alloc_fn;
    fn(void*, void*): void free_fn;
    void* user_data;
}

/*
    simgui_logger

    Used in simgui_desc_t to provide a logging function. Please be aware
    that without logging function, sokol-imgui will be completely
    silent, e.g. it will not report errors, warnings and
    validation layer messages. For maximum error verbosity,
    compile in debug mode (e.g. NDEBUG *not* defined) and install
    a logger (for instance the standard logging function from sokol_log.h).
*/
struct simgui_logger_t {
    fn(u8*, u32, u32, u8*, u32, u8*, void*): void func;
    void* user_data;
}

struct simgui_desc_t {
    i32 max_vertices;
    sg_pixel_format color_format;
    sg_pixel_format depth_format;
    i32 sample_count;
    u8* ini_filename;
    bool no_default_font;
    bool disable_paste_override;
    bool disable_set_mouse_cursor;
    bool disable_windows_resize_from_edges;
    bool write_alpha_channel;
    simgui_allocator_t allocator;
    simgui_logger_t logger;
}

struct simgui_frame_desc_t {
    i32 width;
    i32 height;
    f64 delta_time;
    f32 dpi_scale;
}

struct simgui_font_tex_desc_t {
    sg_filter min_filter;
    sg_filter mag_filter;
}

struct _simgui_vs_params_t {
    ImVec2 disp_size;
    f32 gamma;
    u8[4] _pad_12;
}

struct _simgui_state_t {
    u32 init_cookie;
    simgui_desc_t desc;
    f32 cur_dpi_scale;
    f32 gamma;
    sg_buffer vbuf;
    sg_buffer ibuf;
    sg_sampler def_smp;
    sg_shader def_shd;
    sg_pipeline def_pip;
    sg_shader shd_unfilterable;
    sg_pipeline pip_unfilterable;
    sg_range vertices;
    sg_range indices;
    bool is_osx;
}

/*
    sokol_imgui.h -- drop-in Dear ImGui renderer/event-handler for sokol_gfx.h

    Project URL: https://github.com/floooh/sokol

    Do this:
        #define SOKOL_IMPL or
        #define SOKOL_IMGUI_IMPL

    before you include this file in *one* C or C++ file to create the
    implementation.

    NOTE that the implementation can be compiled either as C++ or as C.
    When compiled as C++, sokol_imgui.h will directly call into the
    Dear ImGui C++ API. When compiled as C, sokol_imgui.h will call
    cimgui.h functions instead.

    NOTE that the formerly separate header sokol_cimgui.h has been
    merged into sokol_imgui.h

    The following defines are used by the implementation to select the
    platform-specific embedded shader code (these are the same defines as
    used by sokol_gfx.h and sokol_app.h):

    SOKOL_GLCORE
    SOKOL_GLES3
    SOKOL_D3D11
    SOKOL_METAL
    SOKOL_WGPU
    SOKOL_VULKAN

    Optionally provide the following configuration define both before including the
    the declaration and implementation:

    SOKOL_IMGUI_NO_SOKOL_APP    - don't depend on sokol_app.h (see below for details)

    Optionally provide the following macros before including the implementation
    to override defaults:

    SOKOL_ASSERT(c)     - your own assert macro (default: assert(c))
    SOKOL_IMGUI_API_DECL- public function declaration prefix (default: extern)
    SOKOL_API_DECL      - same as SOKOL_IMGUI_API_DECL
    SOKOL_API_IMPL      - public function implementation prefix (default: -)

    If sokol_imgui.h is compiled as a DLL, define the following before
    including the declaration or implementation:

    SOKOL_DLL

    On Windows, SOKOL_DLL will define SOKOL_IMGUI_API_DECL as __declspec(dllexport)
    or __declspec(dllimport) as needed.

    Include the following headers before sokol_imgui.h (both before including
    the declaration and implementation):

        sokol_gfx.h
        sokol_app.h     (except SOKOL_IMGUI_NO_SOKOL_APP)

    Additionally, include the following headers before including the
    implementation:

    If the implementation is compiled as C++:
        imgui.h

    If the implementation is compiled as C:
        cimgui.h

    When compiling as C, you can override the Dear ImGui C bindings prefix
    via the define SOKOL_IMGUI_CPREFIX before including the sokol_imgui.h
    implementation:

        #define SOKOL_IMGUI_IMPL
        #define SOKOL_IMGUI_CPREFIX ImGui_
        #include "sokol_imgui.h"

    Note that the default prefix is 'ig'.


    FEATURE OVERVIEW:
    =================
    sokol_imgui.h implements the initialization, rendering and event-handling
    code for Dear ImGui (https://github.com/ocornut/imgui) on top of
    sokol_gfx.h and (optionally) sokol_app.h.

    The sokol_app.h dependency is optional and used for input event handling.
    If you only use sokol_gfx.h but not sokol_app.h in your application,
    define SOKOL_IMGUI_NO_SOKOL_APP before including the implementation
    of sokol_imgui.h, this will remove any dependency to sokol_app.h, but
    you must feed input events into Dear ImGui yourself.

    sokol_imgui.h is not thread-safe, all calls must be made from the
    same thread where sokol_gfx.h is running.

    HOWTO:
    ======

    --- To initialize sokol-imgui, call:

        simgui_setup(const simgui_desc_t* desc)

        This will initialize Dear ImGui and create sokol-gfx resources
        (two buffers for vertices and indices, a font texture and a pipeline-
        state-object).

        Use the following simgui_desc_t members to configure behaviour:

            int max_vertices
                The maximum number of vertices used for UI rendering, default is 65536.
                sokol-imgui will use this to compute the size of the vertex-
                and index-buffers allocated via sokol_gfx.h

            sg_pixel_format color_format
                The color pixel format of the render pass where the UI
                will be rendered. The default (0) matches sokol_gfx.h's
                default pass.

            sg_pixel_format depth_format
                The depth-buffer pixel format of the render pass where
                the UI will be rendered. The default (0) matches
                sokol_gfx.h's default pass depth format.

            int sample_count
                The MSAA sample-count of the render pass where the UI
                will be rendered. The default (0) matches sokol_gfx.h's
                default pass sample count.

            const char* ini_filename
                Sets this path as ImGui::GetIO().IniFilename where ImGui will store
                and load UI persistency data. By default this is 0, so that Dear ImGui
                will not preserve state between sessions (and also won't do
                any filesystem calls). Also see the ImGui functions:
                    - LoadIniSettingsFromMemory()
                    - SaveIniSettingsFromMemory()
                These functions give you explicit control over loading and saving
                UI state while using your own filesystem wrapper functions (in this
                case keep simgui_desc.ini_filename zero)

            bool no_default_font
                Set this to true if you don't want to use ImGui's default
                font. In this case you need to initialize the font
                yourself after simgui_setup() is called.

            bool disable_paste_override
                If set to true, sokol_imgui.h will not 'emulate' a Dear Imgui
                clipboard paste action on SAPP_EVENTTYPE_CLIPBOARD_PASTED event.
                This is mainly a hack/workaround to allow external workarounds
                for making copy/paste work on the web platform. In general,
                copy/paste support isn't properly fleshed out in sokol_imgui.h yet.

            bool disable_set_mouse_cursor
                If true, sokol_imgui.h will not control the mouse cursor type
                by calling sapp_set_mouse_cursor().

            bool disable_windows_resize_from_edges
                If true, windows can only be resized from the bottom right corner.
                The default is false, meaning windows can be resized from edges.

            bool write_alpha_channel
                Set this to true if you want alpha values written to the
                framebuffer. By default this behavior is disabled to prevent
                undesired behavior on platforms like the web where the canvas is
                always alpha-blended with the background.

            simgui_allocator_t allocator
                Used to override memory allocation functions. See further below
                for details.

            simgui_logger_t logger
                A user-provided logging callback. Note that without logging
                callback, sokol-imgui will be completely silent!
                See the section about ERROR REPORTING AND LOGGING below
                for more details.

    --- At the start of a frame, call:

        simgui_new_frame(&(simgui_frame_desc_t){
            .width = ...,
            .height = ...,
            .delta_time = ...,
            .dpi_scale = ...
        });

        'width' and 'height' are the dimensions of the rendering surface,
        passed to ImGui::GetIO().DisplaySize.

        'delta_time' is the frame duration passed to ImGui::GetIO().DeltaTime.

        'dpi_scale' is the current DPI scale factor, if this is left zero-initialized,
        1.0f will be used instead. Typical values for dpi_scale are >= 1.0f.

        For example, if you're using sokol_app.h and render to the default framebuffer:

        simgui_new_frame(&(simgui_frame_desc_t){
            .width = sapp_width(),
            .height = sapp_height(),
            .delta_time = sapp_frame_duration(),
            .dpi_scale = sapp_dpi_scale()
        });

    --- at the end of the frame, before the sg_end_pass() where you
        want to render the UI, call:

        simgui_render()

        This will first call ImGui::Render(), and then render ImGui's draw list
        through sokol_gfx.h

    --- if you're using sokol_app.h, from inside the sokol_app.h event callback,
        call:

        bool simgui_handle_event(const sapp_event* ev);

        The return value is the value of ImGui::GetIO().WantCaptureKeyboard,
        if this is true, you might want to skip keyboard input handling
        in your own event handler.

        If you want to use the ImGui functions for checking if a key is pressed
        (e.g. ImGui::IsKeyPressed()) the following helper function to map
        an sapp_keycode to an ImGuiKey value may be useful:

        int simgui_map_keycode(sapp_keycode c);

        Note that simgui_map_keycode() can be called outside simgui_setup()/simgui_shutdown().

    --- finally, on application shutdown, call

        simgui_shutdown()

    ON ATTACHING YOUR OWN FONTS
    ===========================
    Since Dear ImGui 1.92.0 using non-default fonts has been greatly simplified:

    First, call `simgui_setup()` with the `.no_default_font` so that
    sokol_imgui.h skips adding the default font.

    ...then simply call `AddFontDefault()` or `AddFontFromMemoryTTF()` on
    the Dear ImGui IO object, everything else is taken care of automatically.

    Specifically, do *NOT*:
        - call the deprecated `GetTexDataAsRGBA32()` function
        - create a sokol-gfx image object for the font atlas
        - set the `Font->TexID` on the ImGui IO object

    All those things are now handled inside sokol_imgui.h via a new 'texture update'
    callback which is called by Dear ImGui whenever the state of the font atlas
    texture changes.

    ON USER-PROVIDED IMAGES AND SAMPLERS
    ====================================
    To render your own images via ImGui::Image() you need to create a Dear ImGui
    compatible texture handle (ImTextureID) from a sokol-gfx texture view handle
    or optionally a texture view handle and a compatible sampler handle.

    To create a ImTextureID from a sokol-gfx image handle, call:

        sg_view tex_view = sg_make_view(&(sg_view_desc){ .texture_binding.image = img });
        ImTextureID imtex_id = simgui_imtextureid(tex_view);

    Since no sampler is provided, such a texture handle will use a default
    sampler with nearest filtering and clamp-to-edge.

    If you need to render with a different sampler, do this instead:

        sg_view tex_view = ...;
        sg_sampler smp = ...;
        ImTextureID imtex_id = simgui_imtextureid_with_sampler(tex_img, smp);

    You don't need to 'release' the ImTextureID handle, the ImTextureID
    bits is simply a combination of the sg_view and sg_sampler bits.

    Once you have constructed an ImTextureID handle via simgui_imtextureid()
    or simgui_imtextureid_with_sampler(), it used in the ImGui::Image()
    call like this:

        ImGui::Image(imtex_id, ...);

    To extract the sg_view and sg_sampler handle from an ImTextureID:

        sg_view tex_view = simgui_texture_view_from_imtextureid(imtex_id);
        sg_sampler smp = simgui_sampler_from_imtextureid(imtex_id);

    ...use the sokol-gfx function sg_query_view_image() if you need to
    extract the texture view's image object:

        sg_image img = sg_query_view_image(tex_view);

    NOTE on C bindings since Dear ImGui 1.92.0:

        Since Dear ImGui v1.92.0 the ImGui::Image function takes an
        ImTextureRef object instead of ImTextureID. In C++ this doesn't
        require a code change since the ImTextureRef is automatically constructed
        from the ImTextureID.

        In C this doesn't work and you need to explicitly create an
        ImTextureRef struct, for instance:

            igImage((ImTextureRef){ ._TexID = my_tex_id }, ...);

        Currently Dear Bindings is missing a wrapper function for this,
        also see: https://github.com/dearimgui/dear_bindings/issues/99


    MEMORY ALLOCATION OVERRIDE
    ==========================
    You can override the memory allocation functions at initialization time
    like this:

        void* my_alloc(size_t size, void* user_data) {
            return malloc(size);
        }

        void my_free(void* ptr, void* user_data) {
            free(ptr);
        }

        ...
            simgui_setup(&(simgui_desc_t){
                // ...
                .allocator = {
                    .alloc_fn = my_alloc,
                    .free_fn = my_free,
                    .user_data = ...;
                }
            });
        ...

    If no overrides are provided, malloc and free will be used.

    This only affects memory allocation calls done by sokol_imgui.h
    itself though, not any allocations in Dear ImGui.


    ERROR REPORTING AND LOGGING
    ===========================
    To get any logging information at all you need to provide a logging callback in the setup call
    the easiest way is to use sokol_log.h:

        #include "sokol_log.h"

        simgui_setup(&(simgui_desc_t){
            .logger.func = slog_func
        });

    To override logging with your own callback, first write a logging function like this:

        void my_log(const char* tag,                // e.g. 'simgui'
                    uint32_t log_level,             // 0=panic, 1=error, 2=warn, 3=info
                    uint32_t log_item_id,           // SIMGUI_LOGITEM_*
                    const char* message_or_null,    // a message string, may be nullptr in release mode
                    uint32_t line_nr,               // line number in sokol_imgui.h
                    const char* filename_or_null,   // source filename, may be nullptr in release mode
                    void* user_data)
        {
            ...
        }

    ...and then setup sokol-imgui like this:

        simgui_setup(&(simgui_desc_t){
            .logger = {
                .func = my_log,
                .user_data = my_user_data,
            }
        });

    The provided logging function must be reentrant (e.g. be callable from
    different threads).

    If you don't want to provide your own custom logger it is highly recommended to use
    the standard logger in sokol_log.h instead, otherwise you won't see any warnings or
    errors.


    IMGUI EVENT HANDLING
    ====================
    You can call these functions from your platform's events to handle ImGui events
    when SOKOL_IMGUI_NO_SOKOL_APP is defined.

    E.g. mouse position events can be dispatched like this:

        simgui_add_mouse_pos_event(100, 200);

    For adding key events, you're responsible to map your own key codes to ImGuiKey
    values and pass those as int:

        simgui_add_key_event(imgui_key, true);

    Take note that modifiers (shift, ctrl, etc.) must be updated manually.

    If sokol_app is being used, ImGui events are handled for you.


    LICENSE
    =======

    zlib/libpng license

    Copyright (c) 2018 Andre Weissflog

    This software is provided 'as-is', without any express or implied warranty.
    In no event will the authors be held liable for any damages arising from the
    use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:

        1. The origin of this software must not be misrepresented; you must not
        claim that you wrote the original software. If you use this software in a
        product, an acknowledgment in the product documentation would be
        appreciated but is not required.

        2. Altered source versions must be plainly marked as such, and must not
        be misrepresented as being the original software.

        3. This notice may not be removed or altered from any source
        distribution.
*/
//-- IMPLEMENTATION ------------------------------------------------------------
when !(defined(SOKOL_DEBUG)) {
}
// helper macros and constants
// collisions with X11 headers
private { _simgui_state_t _simgui; }

//<#shdgen
private {
void _simgui_set_clipboard(ImGuiContext* ctx, u8* text) {
    ignore ctx;
    sapp_set_clipboard_string(text);
}

u8* _simgui_get_clipboard(ImGuiContext* ctx) {
    ignore ctx;
    return sapp_get_clipboard_string();
}
}
// ██       ██████   ██████   ██████  ██ ███    ██  ██████
// ██      ██    ██ ██       ██       ██ ████   ██ ██
// ██      ██    ██ ██   ███ ██   ███ ██ ██ ██  ██ ██   ███
// ██      ██    ██ ██    ██ ██    ██ ██ ██  ██ ██ ██    ██
// ███████  ██████   ██████   ██████  ██ ██   ████  ██████
//
// >>logging
when defined(SOKOL_DEBUG) {
private {
u8*[3] _simgui_log_messages = {
    "OK: Ok", "MALLOC_FAILED: memory allocation failed",
    "BUFFER_OVERFLOW: internal vertex/index buffer overflow (increase simgui_desc_t.max_vertices)",
};
}
}

private {
void _simgui_log(simgui_log_item_t log_item, u32 log_level, u8* msg, u32 line_nr) {
    if _simgui.desc.logger.func != null {
        u8* filename = null;
        when defined(SOKOL_DEBUG) {
            filename = __file__;
            if null == msg {
                msg = _simgui_log_messages[log_item];
            }
        }
        _simgui.desc.logger.func("simgui", log_level, cast(u32, log_item), msg, line_nr, filename, _simgui.desc.logger.user_data);
    } else {
        if log_level == 0 {
            abort();
        }
    }
}

// ███    ███ ███████ ███    ███  ██████  ██████  ██    ██
// ████  ████ ██      ████  ████ ██    ██ ██   ██  ██  ██
// ██ ████ ██ █████   ██ ████ ██ ██    ██ ██████    ████
// ██  ██  ██ ██      ██  ██  ██ ██    ██ ██   ██    ██
// ██      ██ ███████ ██      ██  ██████  ██   ██    ██
//
// >>memory
void _simgui_clear(void* ptr, u64 size) {
    assert(ptr && size > 0);
    memset(ptr, 0, size);
}

void* _simgui_malloc(u64 size) {
    assert(size > 0);
    void* ptr;
    if _simgui.desc.allocator.alloc_fn != null {
        ptr = _simgui.desc.allocator.alloc_fn(size, _simgui.desc.allocator.user_data);
    } else {
        ptr = alloc(cast(i64, size));
    }
    if null == ptr {
        _simgui_log(SIMGUI_LOGITEM_MALLOC_FAILED, 0, null, __line__);
    }
    return ptr;
}

void _simgui_free(void* ptr) {
    if _simgui.desc.allocator.free_fn != null {
        _simgui.desc.allocator.free_fn(ptr, _simgui.desc.allocator.user_data);
    } else {
        free(ptr);
    }
}

bool _simgui_is_osx() {
    return _simgui_minc_is_osx();
}

simgui_desc_t _simgui_desc_defaults(simgui_desc_t* desc) {
    assert(desc.allocator.alloc_fn && desc.allocator.free_fn || !desc.allocator.alloc_fn && !desc.allocator.free_fn);
    simgui_desc_t res = *desc;
    res.max_vertices = res.max_vertices == 0 ? 65536 : res.max_vertices;
    return res;
}

ImGuiPlatformIO* _simgui_imgui_get_platform_io() {
    return igGetPlatformIO();
}

ImGuiIO* _simgui_imgui_get_io() {
    return igGetIO();
}

void _simgui_imgui_newframe() {
    igNewFrame();
}

void _simgui_imgui_create_context() {
    igCreateContext(null);
}

void _simgui_imgui_destroy_context() {
    igDestroyContext(null);
}

void _simgui_imgui_style_colors_dark() {
    igStyleColorsDark(igGetStyle());
}

void _simgui_io_add_font_default(ImGuiIO* io) {
    ImFontAtlas_AddFontDefault(io.Fonts, null);
}

void _simgui_io_add_focus_event(ImGuiIO* io, bool focus) {
    ImGuiIO_AddFocusEvent(io, focus);
}

void _simgui_io_add_mouse_source_event(ImGuiIO* io, ImGuiMouseSource source) {
    ImGuiIO_AddMouseSourceEvent(io, source);
}

void _simgui_io_add_mouse_pos_event(ImGuiIO* io, f32 x, f32 y) {
    ImGuiIO_AddMousePosEvent(io, x, y);
}

void _simgui_io_add_mouse_button_event(ImGuiIO* io, i32 mouse_button, bool down) {
    ImGuiIO_AddMouseButtonEvent(io, mouse_button, down);
}

void _simgui_io_add_mouse_wheel_event(ImGuiIO* io, f32 x, f32 y) {
    ImGuiIO_AddMouseWheelEvent(io, x, y);
}

void _simgui_io_add_key_event(ImGuiIO* io, ImGuiKey imgui_key, bool down) {
    ImGuiIO_AddKeyEvent(io, imgui_key, down);
}

void _simgui_io_add_input_character(ImGuiIO* io, u32 c) {
    ImGuiIO_AddInputCharacter(io, c);
}

void _simgui_io_add_input_characters_utf8(ImGuiIO* io, u8* c) {
    ImGuiIO_AddInputCharactersUTF8(io, c);
}

ImGuiMouseCursor _simgui_imgui_get_mouse_cursor() {
    return igGetMouseCursor();
}

ImDrawList* _simgui_imdrawlist_at(ImDrawData* draw_data, i32 cl_index) {
    return draw_data.CmdLists.Data[cl_index];
}

ImTextureID _simgui_imtexturedata_gettexid(ImTextureData* tex) {
    return ImTextureData_GetTexID(tex);
}

void _simgui_imtexturedata_settexid(ImTextureData* tex, ImTextureID tex_id) {
    ImTextureData_SetTexID(tex, tex_id);
}

void _simgui_imtexturedata_setstatus(ImTextureData* tex, ImTextureStatus status) {
    ImTextureData_SetStatus(tex, status);
}

void* _simgui_imtexturedata_getpixels(ImTextureData* tex) {
    return ImTextureData_GetPixels(tex);
}

i32 _simgui_imtexturedata_getsizeinbytes(ImTextureData* tex) {
    return ImTextureData_GetSizeInBytes(tex);
}

ImTextureID _simgui_imdrawcmd_gettexid(ImDrawCmd* cmd) {
    return ImDrawCmd_GetTexID(cmd);
}

i32 _simgui_imdrawlist_cmd_buffer_size(ImDrawList* cl) {
    return cl.CmdBuffer.Size;
}

i32 _simgui_imdrawlist_vtx_buffer_size(ImDrawList* cl) {
    return cl.VtxBuffer.Size;
}

i32 _simgui_imdrawlist_idx_buffer_size(ImDrawList* cl) {
    return cl.IdxBuffer.Size;
}

void _simgui_imgui_render() {
    igRender();
}

ImDrawData* _simgui_imgui_get_draw_data() {
    return igGetDrawData();
}

void _simgui_destroy_texture(ImTextureData* tex) {
    assert(cast(i64, tex));
    sg_view view = simgui_texture_view_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
    sg_image img = sg_query_view_image(view);
    assert(img.id != cast(u32, SG_INVALID_ID));
    sg_sampler smp = simgui_sampler_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
    sg_destroy_view(view);
    sg_destroy_image(img);
    sg_destroy_sampler(smp);
    _simgui_imtexturedata_settexid(tex, cast(ImTextureID, 0));
    _simgui_imtexturedata_setstatus(tex, ImTextureStatus_Destroyed);
}

void _simgui_update_texture(ImTextureData* tex) {
    assert(cast(i64, tex));
    assert(tex.Format == ImTextureFormat_RGBA32);
    if tex.Status == ImTextureStatus_WantCreate {
        assert(tex.TexID == 0);
        noinit sg_image_desc img_desc;
        _simgui_clear(&img_desc, cast(u64, sizeof(img_desc)));
        img_desc.usage.dynamic_update = true;
        img_desc.width = tex.Width;
        img_desc.height = tex.Height;
        img_desc.pixel_format = SG_PIXELFORMAT_RGBA8;
        img_desc.label = "sokol-imgui-texture";
        sg_image img = sg_make_image(&img_desc);
        noinit sg_view_desc view_desc;
        _simgui_clear(&view_desc, cast(u64, sizeof(view_desc)));
        view_desc.texture.image = img;
        view_desc.label = "sokol-imgui-texture-view";
        sg_view view = sg_make_view(&view_desc);
        noinit sg_sampler_desc smp_desc;
        _simgui_clear(&smp_desc, cast(u64, sizeof(smp_desc)));
        smp_desc.wrap_u = SG_WRAP_CLAMP_TO_EDGE;
        smp_desc.wrap_v = SG_WRAP_CLAMP_TO_EDGE;
        smp_desc.min_filter = SG_FILTER_LINEAR;
        smp_desc.mag_filter = SG_FILTER_LINEAR;
        smp_desc.label = "sokol-imgui-sampler";
        sg_sampler smp = sg_make_sampler(&smp_desc);
        _simgui_imtexturedata_settexid(tex, simgui_imtextureid_with_sampler(view, smp));
    }
    if tex.Status == ImTextureStatus_WantCreate || tex.Status == ImTextureStatus_WantUpdates {
        assert(tex.TexID != 0);
        sg_view view = simgui_texture_view_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
        sg_image img = sg_query_view_image(view);
        assert(img.id != cast(u32, SG_INVALID_ID));
        noinit sg_image_data img_data;
        _simgui_clear(&img_data, cast(u64, sizeof(img_data)));
        img_data.mip_levels[0].ptr = _simgui_imtexturedata_getpixels(tex);
        img_data.mip_levels[0].size = cast(u64, _simgui_imtexturedata_getsizeinbytes(tex));
        sg_update_image(img, &img_data);
        _simgui_imtexturedata_setstatus(tex, ImTextureStatus_OK);
    }
    if tex.Status == ImTextureStatus_WantDestroy && tex.UnusedFrames > 0 {
        assert(tex.TexID != 0);
        _simgui_destroy_texture(tex);
    }
}
}

// ██████  ██    ██ ██████  ██      ██  ██████
// ██   ██ ██    ██ ██   ██ ██      ██ ██
// ██████  ██    ██ ██████  ██      ██ ██
// ██      ██    ██ ██   ██ ██      ██ ██
// ██       ██████  ██████  ███████ ██  ██████
//
// >>public
void simgui_setup(simgui_desc_t* desc) {
    assert(cast(i64, desc));
    _simgui_clear(&_simgui, cast(u64, sizeof(_simgui)));
    _simgui.init_cookie = 0xBABEBABE;
    _simgui.desc = _simgui_desc_defaults(desc);
    _simgui.cur_dpi_scale = 1.0f;
    _simgui.is_osx = _simgui_is_osx();
    sg_pixel_format fmt = _simgui.desc.color_format;
    if fmt == _SG_PIXELFORMAT_DEFAULT {
        fmt = sg_query_desc().environment.defaults.color_format;
    }
    if fmt == SG_PIXELFORMAT_SRGB8A8 || fmt == SG_PIXELFORMAT_SBGR8A8 {
        _simgui.gamma = 2.2f;
    } else {
        _simgui.gamma = 1.0f;
    }
    assert(_simgui.desc.max_vertices > 0);
    _simgui.vertices.size = cast(u64, _simgui.desc.max_vertices) * cast(u64, sizeof(ImDrawVert));
    _simgui.vertices.ptr = _simgui_malloc(_simgui.vertices.size);
    _simgui.indices.size = cast(u64, _simgui.desc.max_vertices) * 3 * cast(u64, sizeof(ImDrawIdx));
    _simgui.indices.ptr = _simgui_malloc(_simgui.indices.size);
    _simgui_imgui_create_context();
    _simgui_imgui_style_colors_dark();
    ImGuiIO* io = _simgui_imgui_get_io();
    if _simgui.desc.no_default_font == 0 {
        _simgui_io_add_font_default(io);
    }
    io.IniFilename = _simgui.desc.ini_filename;
    io.ConfigMacOSXBehaviors = _simgui_is_osx();
    io.BackendRendererName = "sokol-imgui";
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset | ImGuiBackendFlags_RendererHasTextures;
    if _simgui.desc.disable_set_mouse_cursor == 0 {
        io.BackendFlags |= ImGuiBackendFlags_HasMouseCursors;
    }
    ImGuiPlatformIO* pio = _simgui_imgui_get_platform_io();
    pio.Platform_SetClipboardTextFn = _simgui_set_clipboard;
    pio.Platform_GetClipboardTextFn = _simgui_get_clipboard;
    io.ConfigWindowsResizeFromEdges = !_simgui.desc.disable_windows_resize_from_edges;
    sg_push_debug_group("sokol-imgui");
    _simgui.def_shd = _simgui_minc_shader();
    noinit sg_pipeline_desc pip_desc;
    _simgui_clear(&pip_desc, cast(u64, sizeof(pip_desc)));
    pip_desc.layout.buffers[0].stride = cast(i32, sizeof(ImDrawVert));
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[0];
        attr.offset = cast(i32, cast(u32, &cast(ImDrawVert*, 0).pos));
        attr.format = SG_VERTEXFORMAT_FLOAT2;
    }
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[1];
        attr.offset = cast(i32, cast(u32, &cast(ImDrawVert*, 0).uv));
        attr.format = SG_VERTEXFORMAT_FLOAT2;
    }
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[2];
        attr.offset = cast(i32, cast(u32, &cast(ImDrawVert*, 0).col));
        attr.format = SG_VERTEXFORMAT_UBYTE4N;
    }
    pip_desc.shader = _simgui.def_shd;
    pip_desc.index_type = SG_INDEXTYPE_UINT16;
    pip_desc.sample_count = _simgui.desc.sample_count;
    pip_desc.depth.pixel_format = _simgui.desc.depth_format;
    pip_desc.colors[0].pixel_format = _simgui.desc.color_format;
    pip_desc.colors[0].write_mask = _simgui.desc.write_alpha_channel != 0 ? SG_COLORMASK_RGBA : SG_COLORMASK_RGB;
    pip_desc.colors[0].blend.enabled = true;
    pip_desc.colors[0].blend.src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA;
    pip_desc.colors[0].blend.dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    if _simgui.desc.write_alpha_channel != 0 {
        pip_desc.colors[0].blend.src_factor_alpha = SG_BLENDFACTOR_ONE;
        pip_desc.colors[0].blend.dst_factor_alpha = SG_BLENDFACTOR_ONE;
    }
    pip_desc.label = "sokol-imgui-pipeline";
    _simgui.def_pip = sg_make_pipeline(&pip_desc);
    _simgui.shd_unfilterable = _simgui_minc_shader_unfilterable();
    pip_desc.shader = _simgui.shd_unfilterable;
    pip_desc.label = "sokol-imgui-pipeline-unfilterable";
    _simgui.pip_unfilterable = sg_make_pipeline(&pip_desc);
    noinit sg_buffer_desc vb_desc;
    _simgui_clear(&vb_desc, cast(u64, sizeof(vb_desc)));
    vb_desc.usage.stream_update = true;
    vb_desc.size = _simgui.vertices.size;
    vb_desc.label = "sokol-imgui-vertices";
    _simgui.vbuf = sg_make_buffer(&vb_desc);
    noinit sg_buffer_desc ib_desc;
    _simgui_clear(&ib_desc, cast(u64, sizeof(ib_desc)));
    ib_desc.usage.index_buffer = true;
    ib_desc.usage.stream_update = true;
    ib_desc.size = _simgui.indices.size;
    ib_desc.label = "sokol-imgui-indices";
    _simgui.ibuf = sg_make_buffer(&ib_desc);
    noinit sg_sampler_desc def_sampler_desc;
    _simgui_clear(&def_sampler_desc, cast(u64, sizeof(def_sampler_desc)));
    def_sampler_desc.min_filter = SG_FILTER_NEAREST;
    def_sampler_desc.mag_filter = SG_FILTER_NEAREST;
    def_sampler_desc.wrap_u = SG_WRAP_CLAMP_TO_EDGE;
    def_sampler_desc.wrap_v = SG_WRAP_CLAMP_TO_EDGE;
    def_sampler_desc.label = "sokol-imgui-default-sampler";
    _simgui.def_smp = sg_make_sampler(&def_sampler_desc);
    sg_pop_debug_group();
}

void simgui_shutdown() {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiPlatformIO* pio = _simgui_imgui_get_platform_io();
    for u64 i = 0; i < cast(u64, pio.Textures.Size); i++ {
        ImTextureData* tex = pio.Textures.Data[i];
        if tex.RefCount == 1 {
            _simgui_destroy_texture(tex);
        }
    }
    _simgui_imgui_destroy_context();
    sg_push_debug_group("sokol-imgui");
    sg_destroy_pipeline(_simgui.pip_unfilterable);
    sg_destroy_shader(_simgui.shd_unfilterable);
    sg_destroy_pipeline(_simgui.def_pip);
    sg_destroy_shader(_simgui.def_shd);
    sg_destroy_sampler(_simgui.def_smp);
    sg_destroy_buffer(_simgui.ibuf);
    sg_destroy_buffer(_simgui.vbuf);
    sg_pop_debug_group();
    assert(cast(i64, _simgui.vertices.ptr));
    _simgui_free(_simgui.vertices.ptr);
    assert(cast(i64, _simgui.indices.ptr));
    _simgui_free(_simgui.indices.ptr);
    _simgui.init_cookie = 0;
}

u64 simgui_imtextureid_with_sampler(sg_view tex_view, sg_sampler smp) {
    u32 view_id = tex_view.id;
    u32 smp_id = smp.id;
    return cast(u64, smp_id) << 32 | view_id;
}

u64 simgui_imtextureid(sg_view tex_view) {
    return simgui_imtextureid_with_sampler(tex_view, _simgui.def_smp);
}

sg_view simgui_texture_view_from_imtextureid(u64 imtex_id) {
    var view = sg_view{cast(u32, imtex_id)};
    return view;
}

sg_sampler simgui_sampler_from_imtextureid(u64 imtex_id) {
    var smp = sg_sampler{cast(u32, imtex_id >> 32)};
    return smp;
}

void simgui_new_frame(simgui_frame_desc_t* desc) {
    assert(0xBABEBABE == _simgui.init_cookie);
    assert(cast(i64, desc));
    assert(desc.width > 0);
    assert(desc.height > 0);
    _simgui.cur_dpi_scale = desc.dpi_scale == 0.0f ? 1.0f : desc.dpi_scale;
    ImGuiIO* io = _simgui_imgui_get_io();
    io.DisplaySize.x = cast(f32, desc.width) / _simgui.cur_dpi_scale;
    io.DisplaySize.y = cast(f32, desc.height) / _simgui.cur_dpi_scale;
    io.DisplayFramebufferScale.x = _simgui.cur_dpi_scale;
    io.DisplayFramebufferScale.y = _simgui.cur_dpi_scale;
    io.DeltaTime = cast(f32, desc.delta_time);
    if io.WantTextInput && !sapp_keyboard_shown() {
        sapp_show_keyboard(true);
    }
    if !io.WantTextInput && sapp_keyboard_shown() {
        sapp_show_keyboard(false);
    }
    if _simgui.desc.disable_set_mouse_cursor == 0 {
        ImGuiMouseCursor imgui_cursor = _simgui_imgui_get_mouse_cursor();
        sapp_mouse_cursor cursor = sapp_get_mouse_cursor();
        switch imgui_cursor {
            case ImGuiMouseCursor_Arrow: {
                cursor = SAPP_MOUSECURSOR_ARROW;
            }
            case ImGuiMouseCursor_TextInput: {
                cursor = SAPP_MOUSECURSOR_IBEAM;
            }
            case ImGuiMouseCursor_ResizeAll: {
                cursor = SAPP_MOUSECURSOR_RESIZE_ALL;
            }
            case ImGuiMouseCursor_ResizeNS: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NS;
            }
            case ImGuiMouseCursor_ResizeEW: {
                cursor = SAPP_MOUSECURSOR_RESIZE_EW;
            }
            case ImGuiMouseCursor_ResizeNESW: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NESW;
            }
            case ImGuiMouseCursor_ResizeNWSE: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NWSE;
            }
            case ImGuiMouseCursor_Hand: {
                cursor = SAPP_MOUSECURSOR_POINTING_HAND;
            }
            case ImGuiMouseCursor_NotAllowed: {
                cursor = SAPP_MOUSECURSOR_NOT_ALLOWED;
            }
            default: {
            }
        }
        sapp_set_mouse_cursor(cursor);
    }
    _simgui_imgui_newframe();
}

private {
sg_pipeline _simgui_bind_texture_sampler(sg_bindings* bindings, ImTextureID imtex_id) {
    sg_view tex_view = simgui_texture_view_from_imtextureid(cast(u64, imtex_id));
    assert(tex_view.id != cast(u32, SG_INVALID_ID));
    sg_image img = sg_query_view_image(tex_view);
    assert(img.id != cast(u32, SG_INVALID_ID));
    bindings.views[0] = tex_view;
    bindings.samplers[0] = simgui_sampler_from_imtextureid(cast(u64, imtex_id));
    assert(bindings.samplers[0].id != cast(u32, SG_INVALID_ID));
    if sg_query_pixelformat(sg_query_image_pixelformat(img)).filter != 0 {
        return _simgui.def_pip;
    } else {
        return _simgui.pip_unfilterable;
    }
}
}

void simgui_render() {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_imgui_render();
    ImDrawData* draw_data = _simgui_imgui_get_draw_data();
    if null == draw_data {
        return;
    }
    if draw_data.Textures != null {
        for u64 i = 0; i < cast(u64, draw_data.Textures.Size); i++ {
            ImTextureData* tex = draw_data.Textures.Data[i];
            if tex.Status != ImTextureStatus_OK {
                _simgui_update_texture(tex);
            }
        }
    }
    if draw_data.CmdLists.Size == 0 {
        return;
    }
    u64 all_vtx_size = 0;
    u64 all_idx_size = 0;
    i32 cmd_list_count = 0;
    for i32 cl_index = 0; cl_index < draw_data.CmdLists.Size; cl_index++ {
        ImDrawList* cl = _simgui_imdrawlist_at(draw_data, cl_index);
        u64 vtx_size = cast(u64, cl.VtxBuffer.Size) * cast(u64, sizeof(ImDrawVert));
        u64 idx_size = cast(u64, cl.IdxBuffer.Size) * cast(u64, sizeof(ImDrawIdx));
        if all_vtx_size + vtx_size > _simgui.vertices.size || all_idx_size + idx_size > _simgui.indices.size {
            _simgui_log(SIMGUI_LOGITEM_BUFFER_OVERFLOW, 1, null, __line__);
            break;
        }
        if vtx_size > 0 {
            ImDrawVert* src_vtx_ptr = cl.VtxBuffer.Data;
            var dst_vtx_ptr = cast(void*, cast(u8*, _simgui.vertices.ptr) + all_vtx_size);
            memcpy(dst_vtx_ptr, src_vtx_ptr, vtx_size);
        }
        if idx_size > 0 {
            ImDrawIdx* src_idx_ptr = cl.IdxBuffer.Data;
            var dst_idx_ptr = cast(void*, cast(u8*, _simgui.indices.ptr) + all_idx_size);
            memcpy(dst_idx_ptr, src_idx_ptr, idx_size);
        }
        all_vtx_size += vtx_size;
        all_idx_size += idx_size;
        cmd_list_count++;
    }
    if 0 == cmd_list_count {
        return;
    }
    sg_push_debug_group("sokol-imgui");
    if all_vtx_size > 0 {
        sg_range vtx_data = _simgui.vertices;
        vtx_data.size = all_vtx_size;
        sg_update_buffer(_simgui.vbuf, &vtx_data);
    }
    if all_idx_size > 0 {
        sg_range idx_data = _simgui.indices;
        idx_data.size = all_idx_size;
        sg_update_buffer(_simgui.ibuf, &idx_data);
    }
    var fb_width = cast(i32, io.DisplaySize.x * draw_data.FramebufferScale.x);
    var fb_height = cast(i32, io.DisplaySize.y * draw_data.FramebufferScale.y);
    sg_apply_viewport(0, 0, fb_width, fb_height, true);
    sg_apply_scissor_rect(0, 0, fb_width, fb_height, true);
    sg_apply_pipeline(_simgui.def_pip);
    noinit _simgui_vs_params_t vs_params;
    _simgui_clear(cast(void*, &vs_params), cast(u64, sizeof(vs_params)));
    vs_params.disp_size.x = io.DisplaySize.x;
    vs_params.disp_size.y = io.DisplaySize.y;
    vs_params.gamma = _simgui.gamma;
    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
    noinit sg_bindings bind;
    _simgui_clear(cast(void*, &bind), cast(u64, sizeof(bind)));
    bind.vertex_buffers[0] = _simgui.vbuf;
    bind.index_buffer = _simgui.ibuf;
    ImTextureID tex_id = 0;
    i32 vb_offset = 0;
    i32 ib_offset = 0;
    for i32 cl_index = 0; cl_index < cmd_list_count; cl_index++ {
        ImDrawList* cl = _simgui_imdrawlist_at(draw_data, cl_index);
        bind.vertex_buffer_offsets[0] = vb_offset;
        bind.index_buffer_offset = ib_offset;
        if tex_id != 0 {
            sg_apply_bindings(&bind);
        }
        i32 num_cmds = _simgui_imdrawlist_cmd_buffer_size(cl);
        u32 vtx_offset = 0;
        for i32 cmd_index = 0; cmd_index < num_cmds; cmd_index++ {
            ImDrawCmd* pcmd = &cl.CmdBuffer.Data[cmd_index];
            if pcmd.UserCallback != null {
                i64 deprecated_ImDrawCallback_ResetRenderState_magic_value = -8;
                if cast(i64, pcmd.UserCallback) != deprecated_ImDrawCallback_ResetRenderState_magic_value {
                    pcmd.UserCallback(cl, pcmd);
                    sg_reset_state_cache();
                    sg_apply_viewport(0, 0, fb_width, fb_height, true);
                    sg_apply_pipeline(_simgui.def_pip);
                    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
                    sg_apply_bindings(&bind);
                }
            } else {
                ImTextureID cmd_tex_id = _simgui_imdrawcmd_gettexid(pcmd);
                if tex_id != cmd_tex_id || vtx_offset != pcmd.VtxOffset {
                    tex_id = cmd_tex_id;
                    vtx_offset = pcmd.VtxOffset;
                    sg_pipeline pip = _simgui_bind_texture_sampler(&bind, tex_id);
                    sg_apply_pipeline(pip);
                    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
                    bind.vertex_buffer_offsets[0] = vb_offset + cast(i32, pcmd.VtxOffset * sizeof(ImDrawVert));
                    sg_apply_bindings(&bind);
                }
                var scissor_x = cast(i32, pcmd.ClipRect.x * draw_data.FramebufferScale.x);
                var scissor_y = cast(i32, pcmd.ClipRect.y * draw_data.FramebufferScale.y);
                var scissor_w = cast(i32, (pcmd.ClipRect.z - pcmd.ClipRect.x) * draw_data.FramebufferScale.x);
                var scissor_h = cast(i32, (pcmd.ClipRect.w - pcmd.ClipRect.y) * draw_data.FramebufferScale.y);
                sg_apply_scissor_rect(scissor_x, scissor_y, scissor_w, scissor_h, true);
                sg_draw(cast(i32, pcmd.IdxOffset), cast(i32, pcmd.ElemCount), 1);
            }
        }
        vb_offset += _simgui_imdrawlist_vtx_buffer_size(cl) * cast(i32, sizeof(ImDrawVert));
        ib_offset += _simgui_imdrawlist_idx_buffer_size(cl) * cast(i32, sizeof(ImDrawIdx));
    }
    sg_apply_viewport(0, 0, fb_width, fb_height, true);
    sg_apply_scissor_rect(0, 0, fb_width, fb_height, true);
    sg_pop_debug_group();
}

void simgui_add_focus_event(bool focus) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_focus_event(io, focus);
}

void simgui_add_mouse_pos_event(f32 x, f32 y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_pos_event(io, x, y);
}

void simgui_add_touch_pos_event(f32 x, f32 y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_TouchScreen);
    _simgui_io_add_mouse_pos_event(io, x, y);
}

void simgui_add_mouse_button_event(i32 mouse_button, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_button_event(io, mouse_button, down);
}

void simgui_add_touch_button_event(i32 mouse_button, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_TouchScreen);
    _simgui_io_add_mouse_button_event(io, mouse_button, down);
}

void simgui_add_mouse_wheel_event(f32 wheel_x, f32 wheel_y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_wheel_event(io, wheel_x, wheel_y);
}

void simgui_add_key_event(i32 imgui_key, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_key_event(io, cast(ImGuiKey, imgui_key), down);
}

void simgui_add_input_character(u32 c) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_input_character(io, c);
}

void simgui_add_input_characters_utf8(u8* c) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_input_characters_utf8(io, c);
}

private {
bool _simgui_is_ctrl(u32 modifiers) {
    if _simgui.is_osx != 0 {
        return 0 != (modifiers & cast(u32, SAPP_MODIFIER_SUPER));
    } else {
        return 0 != (modifiers & cast(u32, SAPP_MODIFIER_CTRL));
    }
}

ImGuiKey _simgui_map_keycode(sapp_keycode key) {
    switch key {
        case SAPP_KEYCODE_SPACE: {
            return ImGuiKey_Space;
        }
        case SAPP_KEYCODE_APOSTROPHE: {
            return ImGuiKey_Apostrophe;
        }
        case SAPP_KEYCODE_COMMA: {
            return ImGuiKey_Comma;
        }
        case SAPP_KEYCODE_MINUS: {
            return ImGuiKey_Minus;
        }
        case SAPP_KEYCODE_PERIOD: {
            return ImGuiKey_Period;
        }
        case SAPP_KEYCODE_SLASH: {
            return ImGuiKey_Slash;
        }
        case SAPP_KEYCODE_0: {
            return ImGuiKey_0;
        }
        case SAPP_KEYCODE_1: {
            return ImGuiKey_1;
        }
        case SAPP_KEYCODE_2: {
            return ImGuiKey_2;
        }
        case SAPP_KEYCODE_3: {
            return ImGuiKey_3;
        }
        case SAPP_KEYCODE_4: {
            return ImGuiKey_4;
        }
        case SAPP_KEYCODE_5: {
            return ImGuiKey_5;
        }
        case SAPP_KEYCODE_6: {
            return ImGuiKey_6;
        }
        case SAPP_KEYCODE_7: {
            return ImGuiKey_7;
        }
        case SAPP_KEYCODE_8: {
            return ImGuiKey_8;
        }
        case SAPP_KEYCODE_9: {
            return ImGuiKey_9;
        }
        case SAPP_KEYCODE_SEMICOLON: {
            return ImGuiKey_Semicolon;
        }
        case SAPP_KEYCODE_EQUAL: {
            return ImGuiKey_Equal;
        }
        case SAPP_KEYCODE_A: {
            return ImGuiKey_A;
        }
        case SAPP_KEYCODE_B: {
            return ImGuiKey_B;
        }
        case SAPP_KEYCODE_C: {
            return ImGuiKey_C;
        }
        case SAPP_KEYCODE_D: {
            return ImGuiKey_D;
        }
        case SAPP_KEYCODE_E: {
            return ImGuiKey_E;
        }
        case SAPP_KEYCODE_F: {
            return ImGuiKey_F;
        }
        case SAPP_KEYCODE_G: {
            return ImGuiKey_G;
        }
        case SAPP_KEYCODE_H: {
            return ImGuiKey_H;
        }
        case SAPP_KEYCODE_I: {
            return ImGuiKey_I;
        }
        case SAPP_KEYCODE_J: {
            return ImGuiKey_J;
        }
        case SAPP_KEYCODE_K: {
            return ImGuiKey_K;
        }
        case SAPP_KEYCODE_L: {
            return ImGuiKey_L;
        }
        case SAPP_KEYCODE_M: {
            return ImGuiKey_M;
        }
        case SAPP_KEYCODE_N: {
            return ImGuiKey_N;
        }
        case SAPP_KEYCODE_O: {
            return ImGuiKey_O;
        }
        case SAPP_KEYCODE_P: {
            return ImGuiKey_P;
        }
        case SAPP_KEYCODE_Q: {
            return ImGuiKey_Q;
        }
        case SAPP_KEYCODE_R: {
            return ImGuiKey_R;
        }
        case SAPP_KEYCODE_S: {
            return ImGuiKey_S;
        }
        case SAPP_KEYCODE_T: {
            return ImGuiKey_T;
        }
        case SAPP_KEYCODE_U: {
            return ImGuiKey_U;
        }
        case SAPP_KEYCODE_V: {
            return ImGuiKey_V;
        }
        case SAPP_KEYCODE_W: {
            return ImGuiKey_W;
        }
        case SAPP_KEYCODE_X: {
            return ImGuiKey_X;
        }
        case SAPP_KEYCODE_Y: {
            return ImGuiKey_Y;
        }
        case SAPP_KEYCODE_Z: {
            return ImGuiKey_Z;
        }
        case SAPP_KEYCODE_LEFT_BRACKET: {
            return ImGuiKey_LeftBracket;
        }
        case SAPP_KEYCODE_BACKSLASH: {
            return ImGuiKey_Backslash;
        }
        case SAPP_KEYCODE_RIGHT_BRACKET: {
            return ImGuiKey_RightBracket;
        }
        case SAPP_KEYCODE_GRAVE_ACCENT: {
            return ImGuiKey_GraveAccent;
        }
        case SAPP_KEYCODE_ESCAPE: {
            return ImGuiKey_Escape;
        }
        case SAPP_KEYCODE_ENTER: {
            return ImGuiKey_Enter;
        }
        case SAPP_KEYCODE_TAB: {
            return ImGuiKey_Tab;
        }
        case SAPP_KEYCODE_BACKSPACE: {
            return ImGuiKey_Backspace;
        }
        case SAPP_KEYCODE_INSERT: {
            return ImGuiKey_Insert;
        }
        case SAPP_KEYCODE_DELETE: {
            return ImGuiKey_Delete;
        }
        case SAPP_KEYCODE_RIGHT: {
            return ImGuiKey_RightArrow;
        }
        case SAPP_KEYCODE_LEFT: {
            return ImGuiKey_LeftArrow;
        }
        case SAPP_KEYCODE_DOWN: {
            return ImGuiKey_DownArrow;
        }
        case SAPP_KEYCODE_UP: {
            return ImGuiKey_UpArrow;
        }
        case SAPP_KEYCODE_PAGE_UP: {
            return ImGuiKey_PageUp;
        }
        case SAPP_KEYCODE_PAGE_DOWN: {
            return ImGuiKey_PageDown;
        }
        case SAPP_KEYCODE_HOME: {
            return ImGuiKey_Home;
        }
        case SAPP_KEYCODE_END: {
            return ImGuiKey_End;
        }
        case SAPP_KEYCODE_CAPS_LOCK: {
            return ImGuiKey_CapsLock;
        }
        case SAPP_KEYCODE_SCROLL_LOCK: {
            return ImGuiKey_ScrollLock;
        }
        case SAPP_KEYCODE_NUM_LOCK: {
            return ImGuiKey_NumLock;
        }
        case SAPP_KEYCODE_PRINT_SCREEN: {
            return ImGuiKey_PrintScreen;
        }
        case SAPP_KEYCODE_PAUSE: {
            return ImGuiKey_Pause;
        }
        case SAPP_KEYCODE_F1: {
            return ImGuiKey_F1;
        }
        case SAPP_KEYCODE_F2: {
            return ImGuiKey_F2;
        }
        case SAPP_KEYCODE_F3: {
            return ImGuiKey_F3;
        }
        case SAPP_KEYCODE_F4: {
            return ImGuiKey_F4;
        }
        case SAPP_KEYCODE_F5: {
            return ImGuiKey_F5;
        }
        case SAPP_KEYCODE_F6: {
            return ImGuiKey_F6;
        }
        case SAPP_KEYCODE_F7: {
            return ImGuiKey_F7;
        }
        case SAPP_KEYCODE_F8: {
            return ImGuiKey_F8;
        }
        case SAPP_KEYCODE_F9: {
            return ImGuiKey_F9;
        }
        case SAPP_KEYCODE_F10: {
            return ImGuiKey_F10;
        }
        case SAPP_KEYCODE_F11: {
            return ImGuiKey_F11;
        }
        case SAPP_KEYCODE_F12: {
            return ImGuiKey_F12;
        }
        case SAPP_KEYCODE_KP_0: {
            return ImGuiKey_Keypad0;
        }
        case SAPP_KEYCODE_KP_1: {
            return ImGuiKey_Keypad1;
        }
        case SAPP_KEYCODE_KP_2: {
            return ImGuiKey_Keypad2;
        }
        case SAPP_KEYCODE_KP_3: {
            return ImGuiKey_Keypad3;
        }
        case SAPP_KEYCODE_KP_4: {
            return ImGuiKey_Keypad4;
        }
        case SAPP_KEYCODE_KP_5: {
            return ImGuiKey_Keypad5;
        }
        case SAPP_KEYCODE_KP_6: {
            return ImGuiKey_Keypad6;
        }
        case SAPP_KEYCODE_KP_7: {
            return ImGuiKey_Keypad7;
        }
        case SAPP_KEYCODE_KP_8: {
            return ImGuiKey_Keypad8;
        }
        case SAPP_KEYCODE_KP_9: {
            return ImGuiKey_Keypad9;
        }
        case SAPP_KEYCODE_KP_DECIMAL: {
            return ImGuiKey_KeypadDecimal;
        }
        case SAPP_KEYCODE_KP_DIVIDE: {
            return ImGuiKey_KeypadDivide;
        }
        case SAPP_KEYCODE_KP_MULTIPLY: {
            return ImGuiKey_KeypadMultiply;
        }
        case SAPP_KEYCODE_KP_SUBTRACT: {
            return ImGuiKey_KeypadSubtract;
        }
        case SAPP_KEYCODE_KP_ADD: {
            return ImGuiKey_KeypadAdd;
        }
        case SAPP_KEYCODE_KP_ENTER: {
            return ImGuiKey_KeypadEnter;
        }
        case SAPP_KEYCODE_KP_EQUAL: {
            return ImGuiKey_KeypadEqual;
        }
        case SAPP_KEYCODE_LEFT_SHIFT: {
            return ImGuiKey_LeftShift;
        }
        case SAPP_KEYCODE_LEFT_CONTROL: {
            return ImGuiKey_LeftCtrl;
        }
        case SAPP_KEYCODE_LEFT_ALT: {
            return ImGuiKey_LeftAlt;
        }
        case SAPP_KEYCODE_LEFT_SUPER: {
            return ImGuiKey_LeftSuper;
        }
        case SAPP_KEYCODE_RIGHT_SHIFT: {
            return ImGuiKey_RightShift;
        }
        case SAPP_KEYCODE_RIGHT_CONTROL: {
            return ImGuiKey_RightCtrl;
        }
        case SAPP_KEYCODE_RIGHT_ALT: {
            return ImGuiKey_RightAlt;
        }
        case SAPP_KEYCODE_RIGHT_SUPER: {
            return ImGuiKey_RightSuper;
        }
        case SAPP_KEYCODE_MENU: {
            return ImGuiKey_Menu;
        }
        default: {
            return ImGuiKey_None;
        }
    }
}

void _simgui_add_sapp_key_event(ImGuiIO* io, sapp_keycode sapp_key, bool down) {
    ImGuiKey imgui_key = _simgui_map_keycode(sapp_key);
    _simgui_io_add_key_event(io, imgui_key, down);
}

void _simgui_update_modifiers(ImGuiIO* io, u32 mods) {
    _simgui_io_add_key_event(io, ImGuiMod_Ctrl, (mods & cast(u32, SAPP_MODIFIER_CTRL)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Shift, (mods & cast(u32, SAPP_MODIFIER_SHIFT)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Alt, (mods & cast(u32, SAPP_MODIFIER_ALT)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Super, (mods & cast(u32, SAPP_MODIFIER_SUPER)) != 0);
}

// returns Ctrl or Super, depending on platform
ImGuiKey _simgui_copypaste_modifier() {
    return _simgui.is_osx != 0 ? ImGuiMod_Super : ImGuiMod_Ctrl;
}
}

i32 simgui_map_keycode(sapp_keycode keycode) {
    assert(0xBABEBABE == _simgui.init_cookie);
    return cast(i32, _simgui_map_keycode(keycode));
}

bool simgui_handle_event(sapp_event* ev) {
    assert(0xBABEBABE == _simgui.init_cookie);
    f32 dpi_scale = _simgui.cur_dpi_scale;
    ImGuiIO* io = _simgui_imgui_get_io();
    switch ev.type {
        case SAPP_EVENTTYPE_FOCUSED: {
            simgui_add_focus_event(true);
        }
        case SAPP_EVENTTYPE_UNFOCUSED: {
            simgui_add_focus_event(false);
        }
        case SAPP_EVENTTYPE_MOUSE_DOWN: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
            simgui_add_mouse_button_event(cast(i32, ev.mouse_button), true);
            _simgui_update_modifiers(io, ev.modifiers);
        }
        case SAPP_EVENTTYPE_MOUSE_UP: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
            simgui_add_mouse_button_event(cast(i32, ev.mouse_button), false);
            _simgui_update_modifiers(io, ev.modifiers);
        }
        case SAPP_EVENTTYPE_MOUSE_MOVE: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
        }
        case SAPP_EVENTTYPE_MOUSE_ENTER, SAPP_EVENTTYPE_MOUSE_LEAVE: {
        }
        case SAPP_EVENTTYPE_MOUSE_SCROLL: {
            simgui_add_mouse_wheel_event(ev.scroll_x, ev.scroll_y);
        }
        case SAPP_EVENTTYPE_TOUCHES_BEGAN: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
            simgui_add_touch_button_event(0, true);
        }
        case SAPP_EVENTTYPE_TOUCHES_MOVED: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
        }
        case SAPP_EVENTTYPE_TOUCHES_ENDED: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
            simgui_add_touch_button_event(0, false);
        }
        case SAPP_EVENTTYPE_TOUCHES_CANCELLED: {
            simgui_add_touch_button_event(0, false);
        }
        case SAPP_EVENTTYPE_KEY_DOWN: {
            _simgui_update_modifiers(io, ev.modifiers);
            if _simgui.desc.disable_paste_override == 0 {
                if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_V {
                    break case;
                }
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_X {
                sapp_consume_event();
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_C {
                sapp_consume_event();
            }
            _simgui_add_sapp_key_event(io, ev.key_code, true);
        }
        case SAPP_EVENTTYPE_KEY_UP: {
            _simgui_update_modifiers(io, ev.modifiers);
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_V {
                break case;
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_X {
                sapp_consume_event();
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_C {
                sapp_consume_event();
            }
            _simgui_add_sapp_key_event(io, ev.key_code, false);
        }
        case SAPP_EVENTTYPE_CHAR: {
            _simgui_update_modifiers(io, ev.modifiers);
            if ev.char_code >= 32 && ev.char_code != 127 && 0 == (ev.modifiers & cast(u32, SAPP_MODIFIER_ALT | SAPP_MODIFIER_CTRL | SAPP_MODIFIER_SUPER)) {
                simgui_add_input_character(ev.char_code);
            }
        }
        case SAPP_EVENTTYPE_CLIPBOARD_PASTED: {
            if _simgui.desc.disable_paste_override == 0 {
                _simgui_io_add_key_event(io, _simgui_copypaste_modifier(), true);
                _simgui_io_add_key_event(io, ImGuiKey_V, true);
                _simgui_io_add_key_event(io, ImGuiKey_V, false);
                _simgui_io_add_key_event(io, _simgui_copypaste_modifier(), false);
            }
        }
        default: {
        }
    }
    return io.WantCaptureKeyboard || io.WantCaptureMouse;
}

}

when os(wasm) {
/*
    simgui_log_item

    An enum with a unique item for each log message, warning, error
    and validation layer message.
*/
enum simgui_log_item_t {
    SIMGUI_LOGITEM_OK = 0,
    SIMGUI_LOGITEM_MALLOC_FAILED = 1,
    SIMGUI_LOGITEM_BUFFER_OVERFLOW = 2,
}

/*
    simgui_allocator_t

    Used in simgui_desc_t to provide custom memory-alloc and -free functions
    to sokol_imgui.h. If memory management should be overridden, both the
    alloc_fn and free_fn function must be provided (e.g. it's not valid to
    override one function but not the other).
*/
struct simgui_allocator_t {
    fn(u64, void*): void* alloc_fn;
    fn(void*, void*): void free_fn;
    void* user_data;
}

/*
    simgui_logger

    Used in simgui_desc_t to provide a logging function. Please be aware
    that without logging function, sokol-imgui will be completely
    silent, e.g. it will not report errors, warnings and
    validation layer messages. For maximum error verbosity,
    compile in debug mode (e.g. NDEBUG *not* defined) and install
    a logger (for instance the standard logging function from sokol_log.h).
*/
struct simgui_logger_t {
    fn(u8*, u32, u32, u8*, u32, u8*, void*): void func;
    void* user_data;
}

struct simgui_desc_t {
    i32 max_vertices;
    sg_pixel_format color_format;
    sg_pixel_format depth_format;
    i32 sample_count;
    u8* ini_filename;
    bool no_default_font;
    bool disable_paste_override;
    bool disable_set_mouse_cursor;
    bool disable_windows_resize_from_edges;
    bool write_alpha_channel;
    simgui_allocator_t allocator;
    simgui_logger_t logger;
}

struct simgui_frame_desc_t {
    i32 width;
    i32 height;
    f64 delta_time;
    f32 dpi_scale;
}

struct simgui_font_tex_desc_t {
    sg_filter min_filter;
    sg_filter mag_filter;
}

struct _simgui_vs_params_t {
    ImVec2 disp_size;
    f32 gamma;
    u8[4] _pad_12;
}

struct _simgui_state_t {
    u32 init_cookie;
    simgui_desc_t desc;
    f32 cur_dpi_scale;
    f32 gamma;
    sg_buffer vbuf;
    sg_buffer ibuf;
    sg_sampler def_smp;
    sg_shader def_shd;
    sg_pipeline def_pip;
    sg_shader shd_unfilterable;
    sg_pipeline pip_unfilterable;
    sg_range vertices;
    sg_range indices;
    bool is_osx;
}

/*
    sokol_imgui.h -- drop-in Dear ImGui renderer/event-handler for sokol_gfx.h

    Project URL: https://github.com/floooh/sokol

    Do this:
        #define SOKOL_IMPL or
        #define SOKOL_IMGUI_IMPL

    before you include this file in *one* C or C++ file to create the
    implementation.

    NOTE that the implementation can be compiled either as C++ or as C.
    When compiled as C++, sokol_imgui.h will directly call into the
    Dear ImGui C++ API. When compiled as C, sokol_imgui.h will call
    cimgui.h functions instead.

    NOTE that the formerly separate header sokol_cimgui.h has been
    merged into sokol_imgui.h

    The following defines are used by the implementation to select the
    platform-specific embedded shader code (these are the same defines as
    used by sokol_gfx.h and sokol_app.h):

    SOKOL_GLCORE
    SOKOL_GLES3
    SOKOL_D3D11
    SOKOL_METAL
    SOKOL_WGPU
    SOKOL_VULKAN

    Optionally provide the following configuration define both before including the
    the declaration and implementation:

    SOKOL_IMGUI_NO_SOKOL_APP    - don't depend on sokol_app.h (see below for details)

    Optionally provide the following macros before including the implementation
    to override defaults:

    SOKOL_ASSERT(c)     - your own assert macro (default: assert(c))
    SOKOL_IMGUI_API_DECL- public function declaration prefix (default: extern)
    SOKOL_API_DECL      - same as SOKOL_IMGUI_API_DECL
    SOKOL_API_IMPL      - public function implementation prefix (default: -)

    If sokol_imgui.h is compiled as a DLL, define the following before
    including the declaration or implementation:

    SOKOL_DLL

    On Windows, SOKOL_DLL will define SOKOL_IMGUI_API_DECL as __declspec(dllexport)
    or __declspec(dllimport) as needed.

    Include the following headers before sokol_imgui.h (both before including
    the declaration and implementation):

        sokol_gfx.h
        sokol_app.h     (except SOKOL_IMGUI_NO_SOKOL_APP)

    Additionally, include the following headers before including the
    implementation:

    If the implementation is compiled as C++:
        imgui.h

    If the implementation is compiled as C:
        cimgui.h

    When compiling as C, you can override the Dear ImGui C bindings prefix
    via the define SOKOL_IMGUI_CPREFIX before including the sokol_imgui.h
    implementation:

        #define SOKOL_IMGUI_IMPL
        #define SOKOL_IMGUI_CPREFIX ImGui_
        #include "sokol_imgui.h"

    Note that the default prefix is 'ig'.


    FEATURE OVERVIEW:
    =================
    sokol_imgui.h implements the initialization, rendering and event-handling
    code for Dear ImGui (https://github.com/ocornut/imgui) on top of
    sokol_gfx.h and (optionally) sokol_app.h.

    The sokol_app.h dependency is optional and used for input event handling.
    If you only use sokol_gfx.h but not sokol_app.h in your application,
    define SOKOL_IMGUI_NO_SOKOL_APP before including the implementation
    of sokol_imgui.h, this will remove any dependency to sokol_app.h, but
    you must feed input events into Dear ImGui yourself.

    sokol_imgui.h is not thread-safe, all calls must be made from the
    same thread where sokol_gfx.h is running.

    HOWTO:
    ======

    --- To initialize sokol-imgui, call:

        simgui_setup(const simgui_desc_t* desc)

        This will initialize Dear ImGui and create sokol-gfx resources
        (two buffers for vertices and indices, a font texture and a pipeline-
        state-object).

        Use the following simgui_desc_t members to configure behaviour:

            int max_vertices
                The maximum number of vertices used for UI rendering, default is 65536.
                sokol-imgui will use this to compute the size of the vertex-
                and index-buffers allocated via sokol_gfx.h

            sg_pixel_format color_format
                The color pixel format of the render pass where the UI
                will be rendered. The default (0) matches sokol_gfx.h's
                default pass.

            sg_pixel_format depth_format
                The depth-buffer pixel format of the render pass where
                the UI will be rendered. The default (0) matches
                sokol_gfx.h's default pass depth format.

            int sample_count
                The MSAA sample-count of the render pass where the UI
                will be rendered. The default (0) matches sokol_gfx.h's
                default pass sample count.

            const char* ini_filename
                Sets this path as ImGui::GetIO().IniFilename where ImGui will store
                and load UI persistency data. By default this is 0, so that Dear ImGui
                will not preserve state between sessions (and also won't do
                any filesystem calls). Also see the ImGui functions:
                    - LoadIniSettingsFromMemory()
                    - SaveIniSettingsFromMemory()
                These functions give you explicit control over loading and saving
                UI state while using your own filesystem wrapper functions (in this
                case keep simgui_desc.ini_filename zero)

            bool no_default_font
                Set this to true if you don't want to use ImGui's default
                font. In this case you need to initialize the font
                yourself after simgui_setup() is called.

            bool disable_paste_override
                If set to true, sokol_imgui.h will not 'emulate' a Dear Imgui
                clipboard paste action on SAPP_EVENTTYPE_CLIPBOARD_PASTED event.
                This is mainly a hack/workaround to allow external workarounds
                for making copy/paste work on the web platform. In general,
                copy/paste support isn't properly fleshed out in sokol_imgui.h yet.

            bool disable_set_mouse_cursor
                If true, sokol_imgui.h will not control the mouse cursor type
                by calling sapp_set_mouse_cursor().

            bool disable_windows_resize_from_edges
                If true, windows can only be resized from the bottom right corner.
                The default is false, meaning windows can be resized from edges.

            bool write_alpha_channel
                Set this to true if you want alpha values written to the
                framebuffer. By default this behavior is disabled to prevent
                undesired behavior on platforms like the web where the canvas is
                always alpha-blended with the background.

            simgui_allocator_t allocator
                Used to override memory allocation functions. See further below
                for details.

            simgui_logger_t logger
                A user-provided logging callback. Note that without logging
                callback, sokol-imgui will be completely silent!
                See the section about ERROR REPORTING AND LOGGING below
                for more details.

    --- At the start of a frame, call:

        simgui_new_frame(&(simgui_frame_desc_t){
            .width = ...,
            .height = ...,
            .delta_time = ...,
            .dpi_scale = ...
        });

        'width' and 'height' are the dimensions of the rendering surface,
        passed to ImGui::GetIO().DisplaySize.

        'delta_time' is the frame duration passed to ImGui::GetIO().DeltaTime.

        'dpi_scale' is the current DPI scale factor, if this is left zero-initialized,
        1.0f will be used instead. Typical values for dpi_scale are >= 1.0f.

        For example, if you're using sokol_app.h and render to the default framebuffer:

        simgui_new_frame(&(simgui_frame_desc_t){
            .width = sapp_width(),
            .height = sapp_height(),
            .delta_time = sapp_frame_duration(),
            .dpi_scale = sapp_dpi_scale()
        });

    --- at the end of the frame, before the sg_end_pass() where you
        want to render the UI, call:

        simgui_render()

        This will first call ImGui::Render(), and then render ImGui's draw list
        through sokol_gfx.h

    --- if you're using sokol_app.h, from inside the sokol_app.h event callback,
        call:

        bool simgui_handle_event(const sapp_event* ev);

        The return value is the value of ImGui::GetIO().WantCaptureKeyboard,
        if this is true, you might want to skip keyboard input handling
        in your own event handler.

        If you want to use the ImGui functions for checking if a key is pressed
        (e.g. ImGui::IsKeyPressed()) the following helper function to map
        an sapp_keycode to an ImGuiKey value may be useful:

        int simgui_map_keycode(sapp_keycode c);

        Note that simgui_map_keycode() can be called outside simgui_setup()/simgui_shutdown().

    --- finally, on application shutdown, call

        simgui_shutdown()

    ON ATTACHING YOUR OWN FONTS
    ===========================
    Since Dear ImGui 1.92.0 using non-default fonts has been greatly simplified:

    First, call `simgui_setup()` with the `.no_default_font` so that
    sokol_imgui.h skips adding the default font.

    ...then simply call `AddFontDefault()` or `AddFontFromMemoryTTF()` on
    the Dear ImGui IO object, everything else is taken care of automatically.

    Specifically, do *NOT*:
        - call the deprecated `GetTexDataAsRGBA32()` function
        - create a sokol-gfx image object for the font atlas
        - set the `Font->TexID` on the ImGui IO object

    All those things are now handled inside sokol_imgui.h via a new 'texture update'
    callback which is called by Dear ImGui whenever the state of the font atlas
    texture changes.

    ON USER-PROVIDED IMAGES AND SAMPLERS
    ====================================
    To render your own images via ImGui::Image() you need to create a Dear ImGui
    compatible texture handle (ImTextureID) from a sokol-gfx texture view handle
    or optionally a texture view handle and a compatible sampler handle.

    To create a ImTextureID from a sokol-gfx image handle, call:

        sg_view tex_view = sg_make_view(&(sg_view_desc){ .texture_binding.image = img });
        ImTextureID imtex_id = simgui_imtextureid(tex_view);

    Since no sampler is provided, such a texture handle will use a default
    sampler with nearest filtering and clamp-to-edge.

    If you need to render with a different sampler, do this instead:

        sg_view tex_view = ...;
        sg_sampler smp = ...;
        ImTextureID imtex_id = simgui_imtextureid_with_sampler(tex_img, smp);

    You don't need to 'release' the ImTextureID handle, the ImTextureID
    bits is simply a combination of the sg_view and sg_sampler bits.

    Once you have constructed an ImTextureID handle via simgui_imtextureid()
    or simgui_imtextureid_with_sampler(), it used in the ImGui::Image()
    call like this:

        ImGui::Image(imtex_id, ...);

    To extract the sg_view and sg_sampler handle from an ImTextureID:

        sg_view tex_view = simgui_texture_view_from_imtextureid(imtex_id);
        sg_sampler smp = simgui_sampler_from_imtextureid(imtex_id);

    ...use the sokol-gfx function sg_query_view_image() if you need to
    extract the texture view's image object:

        sg_image img = sg_query_view_image(tex_view);

    NOTE on C bindings since Dear ImGui 1.92.0:

        Since Dear ImGui v1.92.0 the ImGui::Image function takes an
        ImTextureRef object instead of ImTextureID. In C++ this doesn't
        require a code change since the ImTextureRef is automatically constructed
        from the ImTextureID.

        In C this doesn't work and you need to explicitly create an
        ImTextureRef struct, for instance:

            igImage((ImTextureRef){ ._TexID = my_tex_id }, ...);

        Currently Dear Bindings is missing a wrapper function for this,
        also see: https://github.com/dearimgui/dear_bindings/issues/99


    MEMORY ALLOCATION OVERRIDE
    ==========================
    You can override the memory allocation functions at initialization time
    like this:

        void* my_alloc(size_t size, void* user_data) {
            return malloc(size);
        }

        void my_free(void* ptr, void* user_data) {
            free(ptr);
        }

        ...
            simgui_setup(&(simgui_desc_t){
                // ...
                .allocator = {
                    .alloc_fn = my_alloc,
                    .free_fn = my_free,
                    .user_data = ...;
                }
            });
        ...

    If no overrides are provided, malloc and free will be used.

    This only affects memory allocation calls done by sokol_imgui.h
    itself though, not any allocations in Dear ImGui.


    ERROR REPORTING AND LOGGING
    ===========================
    To get any logging information at all you need to provide a logging callback in the setup call
    the easiest way is to use sokol_log.h:

        #include "sokol_log.h"

        simgui_setup(&(simgui_desc_t){
            .logger.func = slog_func
        });

    To override logging with your own callback, first write a logging function like this:

        void my_log(const char* tag,                // e.g. 'simgui'
                    uint32_t log_level,             // 0=panic, 1=error, 2=warn, 3=info
                    uint32_t log_item_id,           // SIMGUI_LOGITEM_*
                    const char* message_or_null,    // a message string, may be nullptr in release mode
                    uint32_t line_nr,               // line number in sokol_imgui.h
                    const char* filename_or_null,   // source filename, may be nullptr in release mode
                    void* user_data)
        {
            ...
        }

    ...and then setup sokol-imgui like this:

        simgui_setup(&(simgui_desc_t){
            .logger = {
                .func = my_log,
                .user_data = my_user_data,
            }
        });

    The provided logging function must be reentrant (e.g. be callable from
    different threads).

    If you don't want to provide your own custom logger it is highly recommended to use
    the standard logger in sokol_log.h instead, otherwise you won't see any warnings or
    errors.


    IMGUI EVENT HANDLING
    ====================
    You can call these functions from your platform's events to handle ImGui events
    when SOKOL_IMGUI_NO_SOKOL_APP is defined.

    E.g. mouse position events can be dispatched like this:

        simgui_add_mouse_pos_event(100, 200);

    For adding key events, you're responsible to map your own key codes to ImGuiKey
    values and pass those as int:

        simgui_add_key_event(imgui_key, true);

    Take note that modifiers (shift, ctrl, etc.) must be updated manually.

    If sokol_app is being used, ImGui events are handled for you.


    LICENSE
    =======

    zlib/libpng license

    Copyright (c) 2018 Andre Weissflog

    This software is provided 'as-is', without any express or implied warranty.
    In no event will the authors be held liable for any damages arising from the
    use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:

        1. The origin of this software must not be misrepresented; you must not
        claim that you wrote the original software. If you use this software in a
        product, an acknowledgment in the product documentation would be
        appreciated but is not required.

        2. Altered source versions must be plainly marked as such, and must not
        be misrepresented as being the original software.

        3. This notice may not be removed or altered from any source
        distribution.
*/
//-- IMPLEMENTATION ------------------------------------------------------------
when !(defined(SOKOL_DEBUG)) {
}
// helper macros and constants
// collisions with X11 headers
private { _simgui_state_t _simgui; }

//<#shdgen
private {
void _simgui_set_clipboard(ImGuiContext* ctx, u8* text) {
    ignore ctx;
    sapp_set_clipboard_string(text);
}

u8* _simgui_get_clipboard(ImGuiContext* ctx) {
    ignore ctx;
    return sapp_get_clipboard_string();
}
// ██       ██████   ██████   ██████  ██ ███    ██  ██████
// ██      ██    ██ ██       ██       ██ ████   ██ ██
// ██      ██    ██ ██   ███ ██   ███ ██ ██ ██  ██ ██   ███
// ██      ██    ██ ██    ██ ██    ██ ██ ██  ██ ██ ██    ██
// ███████  ██████   ██████   ██████  ██ ██   ████  ██████
//
// >>logging
u8*[3] _simgui_log_messages = {
    "OK: Ok", "MALLOC_FAILED: memory allocation failed",
    "BUFFER_OVERFLOW: internal vertex/index buffer overflow (increase simgui_desc_t.max_vertices)",
};

void _simgui_log(simgui_log_item_t log_item, u32 log_level, u8* msg, u32 line_nr) {
    if _simgui.desc.logger.func != null {
        u8* filename = null;
        filename = __file__;
        if null == msg {
            msg = _simgui_log_messages[log_item];
        }
        _simgui.desc.logger.func("simgui", log_level, cast(u32, log_item), msg, line_nr, filename, _simgui.desc.logger.user_data);
    } else {
        if log_level == 0 {
            abort();
        }
    }
}

// ███    ███ ███████ ███    ███  ██████  ██████  ██    ██
// ████  ████ ██      ████  ████ ██    ██ ██   ██  ██  ██
// ██ ████ ██ █████   ██ ████ ██ ██    ██ ██████    ████
// ██  ██  ██ ██      ██  ██  ██ ██    ██ ██   ██    ██
// ██      ██ ███████ ██      ██  ██████  ██   ██    ██
//
// >>memory
void _simgui_clear(void* ptr, u64 size) {
    assert(ptr && size > 0);
    memset(ptr, 0, size);
}

void* _simgui_malloc(u64 size) {
    assert(size > 0);
    void* ptr;
    if _simgui.desc.allocator.alloc_fn != null {
        ptr = _simgui.desc.allocator.alloc_fn(size, _simgui.desc.allocator.user_data);
    } else {
        ptr = alloc(cast(i64, size));
    }
    if null == ptr {
        _simgui_log(SIMGUI_LOGITEM_MALLOC_FAILED, 0, null, __line__);
    }
    return ptr;
}

void _simgui_free(void* ptr) {
    if _simgui.desc.allocator.free_fn != null {
        _simgui.desc.allocator.free_fn(ptr, _simgui.desc.allocator.user_data);
    } else {
        free(ptr);
    }
}

bool _simgui_is_osx() {
    return _simgui_minc_is_osx();
}

simgui_desc_t _simgui_desc_defaults(simgui_desc_t* desc) {
    assert(desc.allocator.alloc_fn && desc.allocator.free_fn || !desc.allocator.alloc_fn && !desc.allocator.free_fn);
    simgui_desc_t res = *desc;
    res.max_vertices = res.max_vertices == 0 ? 65536 : res.max_vertices;
    return res;
}

ImGuiPlatformIO* _simgui_imgui_get_platform_io() {
    return igGetPlatformIO();
}

ImGuiIO* _simgui_imgui_get_io() {
    return igGetIO();
}

void _simgui_imgui_newframe() {
    igNewFrame();
}

void _simgui_imgui_create_context() {
    igCreateContext(null);
}

void _simgui_imgui_destroy_context() {
    igDestroyContext(null);
}

void _simgui_imgui_style_colors_dark() {
    igStyleColorsDark(igGetStyle());
}

void _simgui_io_add_font_default(ImGuiIO* io) {
    ImFontAtlas_AddFontDefault(io.Fonts, null);
}

void _simgui_io_add_focus_event(ImGuiIO* io, bool focus) {
    ImGuiIO_AddFocusEvent(io, focus);
}

void _simgui_io_add_mouse_source_event(ImGuiIO* io, ImGuiMouseSource source) {
    ImGuiIO_AddMouseSourceEvent(io, source);
}

void _simgui_io_add_mouse_pos_event(ImGuiIO* io, f32 x, f32 y) {
    ImGuiIO_AddMousePosEvent(io, x, y);
}

void _simgui_io_add_mouse_button_event(ImGuiIO* io, i32 mouse_button, bool down) {
    ImGuiIO_AddMouseButtonEvent(io, mouse_button, down);
}

void _simgui_io_add_mouse_wheel_event(ImGuiIO* io, f32 x, f32 y) {
    ImGuiIO_AddMouseWheelEvent(io, x, y);
}

void _simgui_io_add_key_event(ImGuiIO* io, ImGuiKey imgui_key, bool down) {
    ImGuiIO_AddKeyEvent(io, imgui_key, down);
}

void _simgui_io_add_input_character(ImGuiIO* io, u32 c) {
    ImGuiIO_AddInputCharacter(io, c);
}

void _simgui_io_add_input_characters_utf8(ImGuiIO* io, u8* c) {
    ImGuiIO_AddInputCharactersUTF8(io, c);
}

ImGuiMouseCursor _simgui_imgui_get_mouse_cursor() {
    return igGetMouseCursor();
}

ImDrawList* _simgui_imdrawlist_at(ImDrawData* draw_data, i32 cl_index) {
    return draw_data.CmdLists.Data[cl_index];
}

ImTextureID _simgui_imtexturedata_gettexid(ImTextureData* tex) {
    return ImTextureData_GetTexID(tex);
}

void _simgui_imtexturedata_settexid(ImTextureData* tex, ImTextureID tex_id) {
    ImTextureData_SetTexID(tex, tex_id);
}

void _simgui_imtexturedata_setstatus(ImTextureData* tex, ImTextureStatus status) {
    ImTextureData_SetStatus(tex, status);
}

void* _simgui_imtexturedata_getpixels(ImTextureData* tex) {
    return ImTextureData_GetPixels(tex);
}

i32 _simgui_imtexturedata_getsizeinbytes(ImTextureData* tex) {
    return ImTextureData_GetSizeInBytes(tex);
}

ImTextureID _simgui_imdrawcmd_gettexid(ImDrawCmd* cmd) {
    return ImDrawCmd_GetTexID(cmd);
}

i32 _simgui_imdrawlist_cmd_buffer_size(ImDrawList* cl) {
    return cl.CmdBuffer.Size;
}

i32 _simgui_imdrawlist_vtx_buffer_size(ImDrawList* cl) {
    return cl.VtxBuffer.Size;
}

i32 _simgui_imdrawlist_idx_buffer_size(ImDrawList* cl) {
    return cl.IdxBuffer.Size;
}

void _simgui_imgui_render() {
    igRender();
}

ImDrawData* _simgui_imgui_get_draw_data() {
    return igGetDrawData();
}

void _simgui_destroy_texture(ImTextureData* tex) {
    assert(cast(i64, tex));
    sg_view view = simgui_texture_view_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
    sg_image img = sg_query_view_image(view);
    assert(img.id != cast(u32, SG_INVALID_ID));
    sg_sampler smp = simgui_sampler_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
    sg_destroy_view(view);
    sg_destroy_image(img);
    sg_destroy_sampler(smp);
    _simgui_imtexturedata_settexid(tex, cast(ImTextureID, 0));
    _simgui_imtexturedata_setstatus(tex, ImTextureStatus_Destroyed);
}

void _simgui_update_texture(ImTextureData* tex) {
    assert(cast(i64, tex));
    assert(tex.Format == ImTextureFormat_RGBA32);
    if tex.Status == ImTextureStatus_WantCreate {
        assert(tex.TexID == 0);
        noinit sg_image_desc img_desc;
        _simgui_clear(&img_desc, cast(u64, sizeof(img_desc)));
        img_desc.usage.dynamic_update = true;
        img_desc.width = tex.Width;
        img_desc.height = tex.Height;
        img_desc.pixel_format = SG_PIXELFORMAT_RGBA8;
        img_desc.label = "sokol-imgui-texture";
        sg_image img = sg_make_image(&img_desc);
        noinit sg_view_desc view_desc;
        _simgui_clear(&view_desc, cast(u64, sizeof(view_desc)));
        view_desc.texture.image = img;
        view_desc.label = "sokol-imgui-texture-view";
        sg_view view = sg_make_view(&view_desc);
        noinit sg_sampler_desc smp_desc;
        _simgui_clear(&smp_desc, cast(u64, sizeof(smp_desc)));
        smp_desc.wrap_u = SG_WRAP_CLAMP_TO_EDGE;
        smp_desc.wrap_v = SG_WRAP_CLAMP_TO_EDGE;
        smp_desc.min_filter = SG_FILTER_LINEAR;
        smp_desc.mag_filter = SG_FILTER_LINEAR;
        smp_desc.label = "sokol-imgui-sampler";
        sg_sampler smp = sg_make_sampler(&smp_desc);
        _simgui_imtexturedata_settexid(tex, simgui_imtextureid_with_sampler(view, smp));
    }
    if tex.Status == ImTextureStatus_WantCreate || tex.Status == ImTextureStatus_WantUpdates {
        assert(tex.TexID != 0);
        sg_view view = simgui_texture_view_from_imtextureid(cast(u64, _simgui_imtexturedata_gettexid(tex)));
        sg_image img = sg_query_view_image(view);
        assert(img.id != cast(u32, SG_INVALID_ID));
        noinit sg_image_data img_data;
        _simgui_clear(&img_data, cast(u64, sizeof(img_data)));
        img_data.mip_levels[0].ptr = _simgui_imtexturedata_getpixels(tex);
        img_data.mip_levels[0].size = cast(u64, _simgui_imtexturedata_getsizeinbytes(tex));
        sg_update_image(img, &img_data);
        _simgui_imtexturedata_setstatus(tex, ImTextureStatus_OK);
    }
    if tex.Status == ImTextureStatus_WantDestroy && tex.UnusedFrames > 0 {
        assert(tex.TexID != 0);
        _simgui_destroy_texture(tex);
    }
}
}

// ██████  ██    ██ ██████  ██      ██  ██████
// ██   ██ ██    ██ ██   ██ ██      ██ ██
// ██████  ██    ██ ██████  ██      ██ ██
// ██      ██    ██ ██   ██ ██      ██ ██
// ██       ██████  ██████  ███████ ██  ██████
//
// >>public
void simgui_setup(simgui_desc_t* desc) {
    assert(cast(i64, desc));
    _simgui_clear(&_simgui, cast(u64, sizeof(_simgui)));
    _simgui.init_cookie = 0xBABEBABE;
    _simgui.desc = _simgui_desc_defaults(desc);
    _simgui.cur_dpi_scale = 1.0f;
    _simgui.is_osx = _simgui_is_osx();
    sg_pixel_format fmt = _simgui.desc.color_format;
    if fmt == _SG_PIXELFORMAT_DEFAULT {
        fmt = sg_query_desc().environment.defaults.color_format;
    }
    if fmt == SG_PIXELFORMAT_SRGB8A8 || fmt == SG_PIXELFORMAT_SBGR8A8 {
        _simgui.gamma = 2.2f;
    } else {
        _simgui.gamma = 1.0f;
    }
    assert(_simgui.desc.max_vertices > 0);
    _simgui.vertices.size = cast(u64, _simgui.desc.max_vertices) * cast(u64, sizeof(ImDrawVert));
    _simgui.vertices.ptr = _simgui_malloc(_simgui.vertices.size);
    _simgui.indices.size = cast(u64, _simgui.desc.max_vertices) * 3 * cast(u64, sizeof(ImDrawIdx));
    _simgui.indices.ptr = _simgui_malloc(_simgui.indices.size);
    _simgui_imgui_create_context();
    _simgui_imgui_style_colors_dark();
    ImGuiIO* io = _simgui_imgui_get_io();
    if _simgui.desc.no_default_font == 0 {
        _simgui_io_add_font_default(io);
    }
    io.IniFilename = _simgui.desc.ini_filename;
    io.ConfigMacOSXBehaviors = _simgui_is_osx();
    io.BackendRendererName = "sokol-imgui";
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset | ImGuiBackendFlags_RendererHasTextures;
    if _simgui.desc.disable_set_mouse_cursor == 0 {
        io.BackendFlags |= ImGuiBackendFlags_HasMouseCursors;
    }
    ImGuiPlatformIO* pio = _simgui_imgui_get_platform_io();
    pio.Platform_SetClipboardTextFn = _simgui_set_clipboard;
    pio.Platform_GetClipboardTextFn = _simgui_get_clipboard;
    io.ConfigWindowsResizeFromEdges = !_simgui.desc.disable_windows_resize_from_edges;
    sg_push_debug_group("sokol-imgui");
    _simgui.def_shd = _simgui_minc_shader();
    noinit sg_pipeline_desc pip_desc;
    _simgui_clear(&pip_desc, cast(u64, sizeof(pip_desc)));
    pip_desc.layout.buffers[0].stride = cast(i32, sizeof(ImDrawVert));
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[0];
        attr.offset = cast(i32, cast(u64, &cast(ImDrawVert*, 0).pos));
        attr.format = SG_VERTEXFORMAT_FLOAT2;
    }
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[1];
        attr.offset = cast(i32, cast(u64, &cast(ImDrawVert*, 0).uv));
        attr.format = SG_VERTEXFORMAT_FLOAT2;
    }
    {
        sg_vertex_attr_state* attr = &pip_desc.layout.attrs[2];
        attr.offset = cast(i32, cast(u64, &cast(ImDrawVert*, 0).col));
        attr.format = SG_VERTEXFORMAT_UBYTE4N;
    }
    pip_desc.shader = _simgui.def_shd;
    pip_desc.index_type = SG_INDEXTYPE_UINT16;
    pip_desc.sample_count = _simgui.desc.sample_count;
    pip_desc.depth.pixel_format = _simgui.desc.depth_format;
    pip_desc.colors[0].pixel_format = _simgui.desc.color_format;
    pip_desc.colors[0].write_mask = _simgui.desc.write_alpha_channel != 0 ? SG_COLORMASK_RGBA : SG_COLORMASK_RGB;
    pip_desc.colors[0].blend.enabled = true;
    pip_desc.colors[0].blend.src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA;
    pip_desc.colors[0].blend.dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    if _simgui.desc.write_alpha_channel != 0 {
        pip_desc.colors[0].blend.src_factor_alpha = SG_BLENDFACTOR_ONE;
        pip_desc.colors[0].blend.dst_factor_alpha = SG_BLENDFACTOR_ONE;
    }
    pip_desc.label = "sokol-imgui-pipeline";
    _simgui.def_pip = sg_make_pipeline(&pip_desc);
    _simgui.shd_unfilterable = _simgui_minc_shader_unfilterable();
    pip_desc.shader = _simgui.shd_unfilterable;
    pip_desc.label = "sokol-imgui-pipeline-unfilterable";
    _simgui.pip_unfilterable = sg_make_pipeline(&pip_desc);
    noinit sg_buffer_desc vb_desc;
    _simgui_clear(&vb_desc, cast(u64, sizeof(vb_desc)));
    vb_desc.usage.stream_update = true;
    vb_desc.size = _simgui.vertices.size;
    vb_desc.label = "sokol-imgui-vertices";
    _simgui.vbuf = sg_make_buffer(&vb_desc);
    noinit sg_buffer_desc ib_desc;
    _simgui_clear(&ib_desc, cast(u64, sizeof(ib_desc)));
    ib_desc.usage.index_buffer = true;
    ib_desc.usage.stream_update = true;
    ib_desc.size = _simgui.indices.size;
    ib_desc.label = "sokol-imgui-indices";
    _simgui.ibuf = sg_make_buffer(&ib_desc);
    noinit sg_sampler_desc def_sampler_desc;
    _simgui_clear(&def_sampler_desc, cast(u64, sizeof(def_sampler_desc)));
    def_sampler_desc.min_filter = SG_FILTER_NEAREST;
    def_sampler_desc.mag_filter = SG_FILTER_NEAREST;
    def_sampler_desc.wrap_u = SG_WRAP_CLAMP_TO_EDGE;
    def_sampler_desc.wrap_v = SG_WRAP_CLAMP_TO_EDGE;
    def_sampler_desc.label = "sokol-imgui-default-sampler";
    _simgui.def_smp = sg_make_sampler(&def_sampler_desc);
    sg_pop_debug_group();
}

void simgui_shutdown() {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiPlatformIO* pio = _simgui_imgui_get_platform_io();
    for u64 i = 0; i < cast(u64, pio.Textures.Size); i++ {
        ImTextureData* tex = pio.Textures.Data[i];
        if tex.RefCount == 1 {
            _simgui_destroy_texture(tex);
        }
    }
    _simgui_imgui_destroy_context();
    sg_push_debug_group("sokol-imgui");
    sg_destroy_pipeline(_simgui.pip_unfilterable);
    sg_destroy_shader(_simgui.shd_unfilterable);
    sg_destroy_pipeline(_simgui.def_pip);
    sg_destroy_shader(_simgui.def_shd);
    sg_destroy_sampler(_simgui.def_smp);
    sg_destroy_buffer(_simgui.ibuf);
    sg_destroy_buffer(_simgui.vbuf);
    sg_pop_debug_group();
    assert(cast(i64, _simgui.vertices.ptr));
    _simgui_free(_simgui.vertices.ptr);
    assert(cast(i64, _simgui.indices.ptr));
    _simgui_free(_simgui.indices.ptr);
    _simgui.init_cookie = 0;
}

u64 simgui_imtextureid_with_sampler(sg_view tex_view, sg_sampler smp) {
    u32 view_id = tex_view.id;
    u32 smp_id = smp.id;
    return cast(u64, smp_id) << 32 | view_id;
}

u64 simgui_imtextureid(sg_view tex_view) {
    return simgui_imtextureid_with_sampler(tex_view, _simgui.def_smp);
}

sg_view simgui_texture_view_from_imtextureid(u64 imtex_id) {
    var view = sg_view{cast(u32, imtex_id)};
    return view;
}

sg_sampler simgui_sampler_from_imtextureid(u64 imtex_id) {
    var smp = sg_sampler{cast(u32, imtex_id >> 32)};
    return smp;
}

void simgui_new_frame(simgui_frame_desc_t* desc) {
    assert(0xBABEBABE == _simgui.init_cookie);
    assert(cast(i64, desc));
    assert(desc.width > 0);
    assert(desc.height > 0);
    _simgui.cur_dpi_scale = desc.dpi_scale == 0.0f ? 1.0f : desc.dpi_scale;
    ImGuiIO* io = _simgui_imgui_get_io();
    io.DisplaySize.x = cast(f32, desc.width) / _simgui.cur_dpi_scale;
    io.DisplaySize.y = cast(f32, desc.height) / _simgui.cur_dpi_scale;
    io.DisplayFramebufferScale.x = _simgui.cur_dpi_scale;
    io.DisplayFramebufferScale.y = _simgui.cur_dpi_scale;
    io.DeltaTime = cast(f32, desc.delta_time);
    if io.WantTextInput && !sapp_keyboard_shown() {
        sapp_show_keyboard(true);
    }
    if !io.WantTextInput && sapp_keyboard_shown() {
        sapp_show_keyboard(false);
    }
    if _simgui.desc.disable_set_mouse_cursor == 0 {
        ImGuiMouseCursor imgui_cursor = _simgui_imgui_get_mouse_cursor();
        sapp_mouse_cursor cursor = sapp_get_mouse_cursor();
        switch imgui_cursor {
            case ImGuiMouseCursor_Arrow: {
                cursor = SAPP_MOUSECURSOR_ARROW;
            }
            case ImGuiMouseCursor_TextInput: {
                cursor = SAPP_MOUSECURSOR_IBEAM;
            }
            case ImGuiMouseCursor_ResizeAll: {
                cursor = SAPP_MOUSECURSOR_RESIZE_ALL;
            }
            case ImGuiMouseCursor_ResizeNS: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NS;
            }
            case ImGuiMouseCursor_ResizeEW: {
                cursor = SAPP_MOUSECURSOR_RESIZE_EW;
            }
            case ImGuiMouseCursor_ResizeNESW: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NESW;
            }
            case ImGuiMouseCursor_ResizeNWSE: {
                cursor = SAPP_MOUSECURSOR_RESIZE_NWSE;
            }
            case ImGuiMouseCursor_Hand: {
                cursor = SAPP_MOUSECURSOR_POINTING_HAND;
            }
            case ImGuiMouseCursor_NotAllowed: {
                cursor = SAPP_MOUSECURSOR_NOT_ALLOWED;
            }
            default: {
            }
        }
        sapp_set_mouse_cursor(cursor);
    }
    _simgui_imgui_newframe();
}

private {
sg_pipeline _simgui_bind_texture_sampler(sg_bindings* bindings, ImTextureID imtex_id) {
    sg_view tex_view = simgui_texture_view_from_imtextureid(cast(u64, imtex_id));
    assert(tex_view.id != cast(u32, SG_INVALID_ID));
    sg_image img = sg_query_view_image(tex_view);
    assert(img.id != cast(u32, SG_INVALID_ID));
    bindings.views[0] = tex_view;
    bindings.samplers[0] = simgui_sampler_from_imtextureid(cast(u64, imtex_id));
    assert(bindings.samplers[0].id != cast(u32, SG_INVALID_ID));
    if sg_query_pixelformat(sg_query_image_pixelformat(img)).filter != 0 {
        return _simgui.def_pip;
    } else {
        return _simgui.pip_unfilterable;
    }
}
}

void simgui_render() {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_imgui_render();
    ImDrawData* draw_data = _simgui_imgui_get_draw_data();
    if null == draw_data {
        return;
    }
    if draw_data.Textures != null {
        for u64 i = 0; i < cast(u64, draw_data.Textures.Size); i++ {
            ImTextureData* tex = draw_data.Textures.Data[i];
            if tex.Status != ImTextureStatus_OK {
                _simgui_update_texture(tex);
            }
        }
    }
    if draw_data.CmdLists.Size == 0 {
        return;
    }
    u64 all_vtx_size = 0;
    u64 all_idx_size = 0;
    i32 cmd_list_count = 0;
    for i32 cl_index = 0; cl_index < draw_data.CmdLists.Size; cl_index++ {
        ImDrawList* cl = _simgui_imdrawlist_at(draw_data, cl_index);
        u64 vtx_size = cast(u64, cl.VtxBuffer.Size) * cast(u64, sizeof(ImDrawVert));
        u64 idx_size = cast(u64, cl.IdxBuffer.Size) * cast(u64, sizeof(ImDrawIdx));
        if all_vtx_size + vtx_size > _simgui.vertices.size || all_idx_size + idx_size > _simgui.indices.size {
            _simgui_log(SIMGUI_LOGITEM_BUFFER_OVERFLOW, 1, null, __line__);
            break;
        }
        if vtx_size > 0 {
            ImDrawVert* src_vtx_ptr = cl.VtxBuffer.Data;
            var dst_vtx_ptr = cast(void*, cast(u8*, _simgui.vertices.ptr) + all_vtx_size);
            memcpy(dst_vtx_ptr, src_vtx_ptr, vtx_size);
        }
        if idx_size > 0 {
            ImDrawIdx* src_idx_ptr = cl.IdxBuffer.Data;
            var dst_idx_ptr = cast(void*, cast(u8*, _simgui.indices.ptr) + all_idx_size);
            memcpy(dst_idx_ptr, src_idx_ptr, idx_size);
        }
        all_vtx_size += vtx_size;
        all_idx_size += idx_size;
        cmd_list_count++;
    }
    if 0 == cmd_list_count {
        return;
    }
    sg_push_debug_group("sokol-imgui");
    if all_vtx_size > 0 {
        sg_range vtx_data = _simgui.vertices;
        vtx_data.size = all_vtx_size;
        sg_update_buffer(_simgui.vbuf, &vtx_data);
    }
    if all_idx_size > 0 {
        sg_range idx_data = _simgui.indices;
        idx_data.size = all_idx_size;
        sg_update_buffer(_simgui.ibuf, &idx_data);
    }
    var fb_width = cast(i32, io.DisplaySize.x * draw_data.FramebufferScale.x);
    var fb_height = cast(i32, io.DisplaySize.y * draw_data.FramebufferScale.y);
    sg_apply_viewport(0, 0, fb_width, fb_height, true);
    sg_apply_scissor_rect(0, 0, fb_width, fb_height, true);
    sg_apply_pipeline(_simgui.def_pip);
    noinit _simgui_vs_params_t vs_params;
    _simgui_clear(cast(void*, &vs_params), cast(u64, sizeof(vs_params)));
    vs_params.disp_size.x = io.DisplaySize.x;
    vs_params.disp_size.y = io.DisplaySize.y;
    vs_params.gamma = _simgui.gamma;
    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
    noinit sg_bindings bind;
    _simgui_clear(cast(void*, &bind), cast(u64, sizeof(bind)));
    bind.vertex_buffers[0] = _simgui.vbuf;
    bind.index_buffer = _simgui.ibuf;
    ImTextureID tex_id = 0;
    i32 vb_offset = 0;
    i32 ib_offset = 0;
    for i32 cl_index = 0; cl_index < cmd_list_count; cl_index++ {
        ImDrawList* cl = _simgui_imdrawlist_at(draw_data, cl_index);
        bind.vertex_buffer_offsets[0] = vb_offset;
        bind.index_buffer_offset = ib_offset;
        if tex_id != 0 {
            sg_apply_bindings(&bind);
        }
        i32 num_cmds = _simgui_imdrawlist_cmd_buffer_size(cl);
        u32 vtx_offset = 0;
        for i32 cmd_index = 0; cmd_index < num_cmds; cmd_index++ {
            ImDrawCmd* pcmd = &cl.CmdBuffer.Data[cmd_index];
            if pcmd.UserCallback != null {
                i64 deprecated_ImDrawCallback_ResetRenderState_magic_value = -8;
                if cast(i64, pcmd.UserCallback) != deprecated_ImDrawCallback_ResetRenderState_magic_value {
                    pcmd.UserCallback(cl, pcmd);
                    sg_reset_state_cache();
                    sg_apply_viewport(0, 0, fb_width, fb_height, true);
                    sg_apply_pipeline(_simgui.def_pip);
                    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
                    sg_apply_bindings(&bind);
                }
            } else {
                ImTextureID cmd_tex_id = _simgui_imdrawcmd_gettexid(pcmd);
                if tex_id != cmd_tex_id || vtx_offset != pcmd.VtxOffset {
                    tex_id = cmd_tex_id;
                    vtx_offset = pcmd.VtxOffset;
                    sg_pipeline pip = _simgui_bind_texture_sampler(&bind, tex_id);
                    sg_apply_pipeline(pip);
                    sg_apply_uniforms(0, &sg_range{&vs_params, sizeof(vs_params)});
                    bind.vertex_buffer_offsets[0] = vb_offset + cast(i32, pcmd.VtxOffset * sizeof(ImDrawVert));
                    sg_apply_bindings(&bind);
                }
                var scissor_x = cast(i32, pcmd.ClipRect.x * draw_data.FramebufferScale.x);
                var scissor_y = cast(i32, pcmd.ClipRect.y * draw_data.FramebufferScale.y);
                var scissor_w = cast(i32, (pcmd.ClipRect.z - pcmd.ClipRect.x) * draw_data.FramebufferScale.x);
                var scissor_h = cast(i32, (pcmd.ClipRect.w - pcmd.ClipRect.y) * draw_data.FramebufferScale.y);
                sg_apply_scissor_rect(scissor_x, scissor_y, scissor_w, scissor_h, true);
                sg_draw(cast(i32, pcmd.IdxOffset), cast(i32, pcmd.ElemCount), 1);
            }
        }
        vb_offset += _simgui_imdrawlist_vtx_buffer_size(cl) * cast(i32, sizeof(ImDrawVert));
        ib_offset += _simgui_imdrawlist_idx_buffer_size(cl) * cast(i32, sizeof(ImDrawIdx));
    }
    sg_apply_viewport(0, 0, fb_width, fb_height, true);
    sg_apply_scissor_rect(0, 0, fb_width, fb_height, true);
    sg_pop_debug_group();
}

void simgui_add_focus_event(bool focus) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_focus_event(io, focus);
}

void simgui_add_mouse_pos_event(f32 x, f32 y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_pos_event(io, x, y);
}

void simgui_add_touch_pos_event(f32 x, f32 y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_TouchScreen);
    _simgui_io_add_mouse_pos_event(io, x, y);
}

void simgui_add_mouse_button_event(i32 mouse_button, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_button_event(io, mouse_button, down);
}

void simgui_add_touch_button_event(i32 mouse_button, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_TouchScreen);
    _simgui_io_add_mouse_button_event(io, mouse_button, down);
}

void simgui_add_mouse_wheel_event(f32 wheel_x, f32 wheel_y) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_mouse_source_event(io, ImGuiMouseSource_Mouse);
    _simgui_io_add_mouse_wheel_event(io, wheel_x, wheel_y);
}

void simgui_add_key_event(i32 imgui_key, bool down) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_key_event(io, cast(ImGuiKey, imgui_key), down);
}

void simgui_add_input_character(u32 c) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_input_character(io, c);
}

void simgui_add_input_characters_utf8(u8* c) {
    assert(0xBABEBABE == _simgui.init_cookie);
    ImGuiIO* io = _simgui_imgui_get_io();
    _simgui_io_add_input_characters_utf8(io, c);
}

private {
bool _simgui_is_ctrl(u32 modifiers) {
    if _simgui.is_osx != 0 {
        return 0 != (modifiers & cast(u32, SAPP_MODIFIER_SUPER));
    } else {
        return 0 != (modifiers & cast(u32, SAPP_MODIFIER_CTRL));
    }
}

ImGuiKey _simgui_map_keycode(sapp_keycode key) {
    switch key {
        case SAPP_KEYCODE_SPACE: {
            return ImGuiKey_Space;
        }
        case SAPP_KEYCODE_APOSTROPHE: {
            return ImGuiKey_Apostrophe;
        }
        case SAPP_KEYCODE_COMMA: {
            return ImGuiKey_Comma;
        }
        case SAPP_KEYCODE_MINUS: {
            return ImGuiKey_Minus;
        }
        case SAPP_KEYCODE_PERIOD: {
            return ImGuiKey_Period;
        }
        case SAPP_KEYCODE_SLASH: {
            return ImGuiKey_Slash;
        }
        case SAPP_KEYCODE_0: {
            return ImGuiKey_0;
        }
        case SAPP_KEYCODE_1: {
            return ImGuiKey_1;
        }
        case SAPP_KEYCODE_2: {
            return ImGuiKey_2;
        }
        case SAPP_KEYCODE_3: {
            return ImGuiKey_3;
        }
        case SAPP_KEYCODE_4: {
            return ImGuiKey_4;
        }
        case SAPP_KEYCODE_5: {
            return ImGuiKey_5;
        }
        case SAPP_KEYCODE_6: {
            return ImGuiKey_6;
        }
        case SAPP_KEYCODE_7: {
            return ImGuiKey_7;
        }
        case SAPP_KEYCODE_8: {
            return ImGuiKey_8;
        }
        case SAPP_KEYCODE_9: {
            return ImGuiKey_9;
        }
        case SAPP_KEYCODE_SEMICOLON: {
            return ImGuiKey_Semicolon;
        }
        case SAPP_KEYCODE_EQUAL: {
            return ImGuiKey_Equal;
        }
        case SAPP_KEYCODE_A: {
            return ImGuiKey_A;
        }
        case SAPP_KEYCODE_B: {
            return ImGuiKey_B;
        }
        case SAPP_KEYCODE_C: {
            return ImGuiKey_C;
        }
        case SAPP_KEYCODE_D: {
            return ImGuiKey_D;
        }
        case SAPP_KEYCODE_E: {
            return ImGuiKey_E;
        }
        case SAPP_KEYCODE_F: {
            return ImGuiKey_F;
        }
        case SAPP_KEYCODE_G: {
            return ImGuiKey_G;
        }
        case SAPP_KEYCODE_H: {
            return ImGuiKey_H;
        }
        case SAPP_KEYCODE_I: {
            return ImGuiKey_I;
        }
        case SAPP_KEYCODE_J: {
            return ImGuiKey_J;
        }
        case SAPP_KEYCODE_K: {
            return ImGuiKey_K;
        }
        case SAPP_KEYCODE_L: {
            return ImGuiKey_L;
        }
        case SAPP_KEYCODE_M: {
            return ImGuiKey_M;
        }
        case SAPP_KEYCODE_N: {
            return ImGuiKey_N;
        }
        case SAPP_KEYCODE_O: {
            return ImGuiKey_O;
        }
        case SAPP_KEYCODE_P: {
            return ImGuiKey_P;
        }
        case SAPP_KEYCODE_Q: {
            return ImGuiKey_Q;
        }
        case SAPP_KEYCODE_R: {
            return ImGuiKey_R;
        }
        case SAPP_KEYCODE_S: {
            return ImGuiKey_S;
        }
        case SAPP_KEYCODE_T: {
            return ImGuiKey_T;
        }
        case SAPP_KEYCODE_U: {
            return ImGuiKey_U;
        }
        case SAPP_KEYCODE_V: {
            return ImGuiKey_V;
        }
        case SAPP_KEYCODE_W: {
            return ImGuiKey_W;
        }
        case SAPP_KEYCODE_X: {
            return ImGuiKey_X;
        }
        case SAPP_KEYCODE_Y: {
            return ImGuiKey_Y;
        }
        case SAPP_KEYCODE_Z: {
            return ImGuiKey_Z;
        }
        case SAPP_KEYCODE_LEFT_BRACKET: {
            return ImGuiKey_LeftBracket;
        }
        case SAPP_KEYCODE_BACKSLASH: {
            return ImGuiKey_Backslash;
        }
        case SAPP_KEYCODE_RIGHT_BRACKET: {
            return ImGuiKey_RightBracket;
        }
        case SAPP_KEYCODE_GRAVE_ACCENT: {
            return ImGuiKey_GraveAccent;
        }
        case SAPP_KEYCODE_ESCAPE: {
            return ImGuiKey_Escape;
        }
        case SAPP_KEYCODE_ENTER: {
            return ImGuiKey_Enter;
        }
        case SAPP_KEYCODE_TAB: {
            return ImGuiKey_Tab;
        }
        case SAPP_KEYCODE_BACKSPACE: {
            return ImGuiKey_Backspace;
        }
        case SAPP_KEYCODE_INSERT: {
            return ImGuiKey_Insert;
        }
        case SAPP_KEYCODE_DELETE: {
            return ImGuiKey_Delete;
        }
        case SAPP_KEYCODE_RIGHT: {
            return ImGuiKey_RightArrow;
        }
        case SAPP_KEYCODE_LEFT: {
            return ImGuiKey_LeftArrow;
        }
        case SAPP_KEYCODE_DOWN: {
            return ImGuiKey_DownArrow;
        }
        case SAPP_KEYCODE_UP: {
            return ImGuiKey_UpArrow;
        }
        case SAPP_KEYCODE_PAGE_UP: {
            return ImGuiKey_PageUp;
        }
        case SAPP_KEYCODE_PAGE_DOWN: {
            return ImGuiKey_PageDown;
        }
        case SAPP_KEYCODE_HOME: {
            return ImGuiKey_Home;
        }
        case SAPP_KEYCODE_END: {
            return ImGuiKey_End;
        }
        case SAPP_KEYCODE_CAPS_LOCK: {
            return ImGuiKey_CapsLock;
        }
        case SAPP_KEYCODE_SCROLL_LOCK: {
            return ImGuiKey_ScrollLock;
        }
        case SAPP_KEYCODE_NUM_LOCK: {
            return ImGuiKey_NumLock;
        }
        case SAPP_KEYCODE_PRINT_SCREEN: {
            return ImGuiKey_PrintScreen;
        }
        case SAPP_KEYCODE_PAUSE: {
            return ImGuiKey_Pause;
        }
        case SAPP_KEYCODE_F1: {
            return ImGuiKey_F1;
        }
        case SAPP_KEYCODE_F2: {
            return ImGuiKey_F2;
        }
        case SAPP_KEYCODE_F3: {
            return ImGuiKey_F3;
        }
        case SAPP_KEYCODE_F4: {
            return ImGuiKey_F4;
        }
        case SAPP_KEYCODE_F5: {
            return ImGuiKey_F5;
        }
        case SAPP_KEYCODE_F6: {
            return ImGuiKey_F6;
        }
        case SAPP_KEYCODE_F7: {
            return ImGuiKey_F7;
        }
        case SAPP_KEYCODE_F8: {
            return ImGuiKey_F8;
        }
        case SAPP_KEYCODE_F9: {
            return ImGuiKey_F9;
        }
        case SAPP_KEYCODE_F10: {
            return ImGuiKey_F10;
        }
        case SAPP_KEYCODE_F11: {
            return ImGuiKey_F11;
        }
        case SAPP_KEYCODE_F12: {
            return ImGuiKey_F12;
        }
        case SAPP_KEYCODE_KP_0: {
            return ImGuiKey_Keypad0;
        }
        case SAPP_KEYCODE_KP_1: {
            return ImGuiKey_Keypad1;
        }
        case SAPP_KEYCODE_KP_2: {
            return ImGuiKey_Keypad2;
        }
        case SAPP_KEYCODE_KP_3: {
            return ImGuiKey_Keypad3;
        }
        case SAPP_KEYCODE_KP_4: {
            return ImGuiKey_Keypad4;
        }
        case SAPP_KEYCODE_KP_5: {
            return ImGuiKey_Keypad5;
        }
        case SAPP_KEYCODE_KP_6: {
            return ImGuiKey_Keypad6;
        }
        case SAPP_KEYCODE_KP_7: {
            return ImGuiKey_Keypad7;
        }
        case SAPP_KEYCODE_KP_8: {
            return ImGuiKey_Keypad8;
        }
        case SAPP_KEYCODE_KP_9: {
            return ImGuiKey_Keypad9;
        }
        case SAPP_KEYCODE_KP_DECIMAL: {
            return ImGuiKey_KeypadDecimal;
        }
        case SAPP_KEYCODE_KP_DIVIDE: {
            return ImGuiKey_KeypadDivide;
        }
        case SAPP_KEYCODE_KP_MULTIPLY: {
            return ImGuiKey_KeypadMultiply;
        }
        case SAPP_KEYCODE_KP_SUBTRACT: {
            return ImGuiKey_KeypadSubtract;
        }
        case SAPP_KEYCODE_KP_ADD: {
            return ImGuiKey_KeypadAdd;
        }
        case SAPP_KEYCODE_KP_ENTER: {
            return ImGuiKey_KeypadEnter;
        }
        case SAPP_KEYCODE_KP_EQUAL: {
            return ImGuiKey_KeypadEqual;
        }
        case SAPP_KEYCODE_LEFT_SHIFT: {
            return ImGuiKey_LeftShift;
        }
        case SAPP_KEYCODE_LEFT_CONTROL: {
            return ImGuiKey_LeftCtrl;
        }
        case SAPP_KEYCODE_LEFT_ALT: {
            return ImGuiKey_LeftAlt;
        }
        case SAPP_KEYCODE_LEFT_SUPER: {
            return ImGuiKey_LeftSuper;
        }
        case SAPP_KEYCODE_RIGHT_SHIFT: {
            return ImGuiKey_RightShift;
        }
        case SAPP_KEYCODE_RIGHT_CONTROL: {
            return ImGuiKey_RightCtrl;
        }
        case SAPP_KEYCODE_RIGHT_ALT: {
            return ImGuiKey_RightAlt;
        }
        case SAPP_KEYCODE_RIGHT_SUPER: {
            return ImGuiKey_RightSuper;
        }
        case SAPP_KEYCODE_MENU: {
            return ImGuiKey_Menu;
        }
        default: {
            return ImGuiKey_None;
        }
    }
}

void _simgui_add_sapp_key_event(ImGuiIO* io, sapp_keycode sapp_key, bool down) {
    ImGuiKey imgui_key = _simgui_map_keycode(sapp_key);
    _simgui_io_add_key_event(io, imgui_key, down);
}

void _simgui_update_modifiers(ImGuiIO* io, u32 mods) {
    _simgui_io_add_key_event(io, ImGuiMod_Ctrl, (mods & cast(u32, SAPP_MODIFIER_CTRL)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Shift, (mods & cast(u32, SAPP_MODIFIER_SHIFT)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Alt, (mods & cast(u32, SAPP_MODIFIER_ALT)) != 0);
    _simgui_io_add_key_event(io, ImGuiMod_Super, (mods & cast(u32, SAPP_MODIFIER_SUPER)) != 0);
}

// returns Ctrl or Super, depending on platform
ImGuiKey _simgui_copypaste_modifier() {
    return _simgui.is_osx != 0 ? ImGuiMod_Super : ImGuiMod_Ctrl;
}
}

i32 simgui_map_keycode(sapp_keycode keycode) {
    assert(0xBABEBABE == _simgui.init_cookie);
    return cast(i32, _simgui_map_keycode(keycode));
}

bool simgui_handle_event(sapp_event* ev) {
    assert(0xBABEBABE == _simgui.init_cookie);
    f32 dpi_scale = _simgui.cur_dpi_scale;
    ImGuiIO* io = _simgui_imgui_get_io();
    switch ev.type {
        case SAPP_EVENTTYPE_FOCUSED: {
            simgui_add_focus_event(true);
        }
        case SAPP_EVENTTYPE_UNFOCUSED: {
            simgui_add_focus_event(false);
        }
        case SAPP_EVENTTYPE_MOUSE_DOWN: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
            simgui_add_mouse_button_event(cast(i32, ev.mouse_button), true);
            _simgui_update_modifiers(io, ev.modifiers);
        }
        case SAPP_EVENTTYPE_MOUSE_UP: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
            simgui_add_mouse_button_event(cast(i32, ev.mouse_button), false);
            _simgui_update_modifiers(io, ev.modifiers);
        }
        case SAPP_EVENTTYPE_MOUSE_MOVE: {
            simgui_add_mouse_pos_event(ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale);
        }
        case SAPP_EVENTTYPE_MOUSE_ENTER, SAPP_EVENTTYPE_MOUSE_LEAVE: {
            for i32 i = 0; i < SAPP_MAX_MOUSEBUTTONS; i++ {
                simgui_add_mouse_button_event(i, false);
            }
        }
        case SAPP_EVENTTYPE_MOUSE_SCROLL: {
            simgui_add_mouse_wheel_event(ev.scroll_x, ev.scroll_y);
        }
        case SAPP_EVENTTYPE_TOUCHES_BEGAN: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
            simgui_add_touch_button_event(0, true);
        }
        case SAPP_EVENTTYPE_TOUCHES_MOVED: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
        }
        case SAPP_EVENTTYPE_TOUCHES_ENDED: {
            simgui_add_touch_pos_event(ev.touches[0].pos_x / dpi_scale, ev.touches[0].pos_y / dpi_scale);
            simgui_add_touch_button_event(0, false);
        }
        case SAPP_EVENTTYPE_TOUCHES_CANCELLED: {
            simgui_add_touch_button_event(0, false);
        }
        case SAPP_EVENTTYPE_KEY_DOWN: {
            _simgui_update_modifiers(io, ev.modifiers);
            if _simgui.desc.disable_paste_override == 0 {
                if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_V {
                    break case;
                }
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_X {
                sapp_consume_event();
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_C {
                sapp_consume_event();
            }
            _simgui_add_sapp_key_event(io, ev.key_code, true);
        }
        case SAPP_EVENTTYPE_KEY_UP: {
            _simgui_update_modifiers(io, ev.modifiers);
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_V {
                break case;
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_X {
                sapp_consume_event();
            }
            if _simgui_is_ctrl(ev.modifiers) && ev.key_code == SAPP_KEYCODE_C {
                sapp_consume_event();
            }
            _simgui_add_sapp_key_event(io, ev.key_code, false);
        }
        case SAPP_EVENTTYPE_CHAR: {
            _simgui_update_modifiers(io, ev.modifiers);
            if ev.char_code >= 32 && ev.char_code != 127 && 0 == (ev.modifiers & cast(u32, SAPP_MODIFIER_ALT | SAPP_MODIFIER_CTRL | SAPP_MODIFIER_SUPER)) {
                simgui_add_input_character(ev.char_code);
            }
        }
        case SAPP_EVENTTYPE_CLIPBOARD_PASTED: {
            if _simgui.desc.disable_paste_override == 0 {
                _simgui_io_add_key_event(io, _simgui_copypaste_modifier(), true);
                _simgui_io_add_key_event(io, ImGuiKey_V, true);
                _simgui_io_add_key_event(io, ImGuiKey_V, false);
                _simgui_io_add_key_event(io, _simgui_copypaste_modifier(), false);
            }
        }
        default: {
        }
    }
    return io.WantCaptureKeyboard || io.WantCaptureMouse;
}

}
