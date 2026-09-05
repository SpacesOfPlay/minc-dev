// =====================================================================
// Derived from sokol_audio.h  (https://github.com/floooh/sokol)
// Copyright (c) 2018 Andre Weissflog, zlib/libpng license
//
// Altered source: transpiled to minc.
// =====================================================================
// sokol_audio: cross-platform audio. Windows WASAPI, macOS/iOS CoreAudio,
// Android AAudio, Linux ALSA, web WebAudio. Independent of the graphics modules.

@gui    // windowed app, no console window

import ext_libc;
when os(windows) { import ext_wasapi; }
when os(macos) || os(ios) { import ext_coreaudio; }
when os(android) { import ext_aaudio; }
when os(linux) { import ext_alsa; }
// =====================================================================
// Shared by every native backend arm below.
// Hoisted by scripts/sokol_dedup.py -- these were byte-identical
// in every arm below.
// =====================================================================
when (os(windows)) || (os(macos) || os(ios)) || (os(android)) || (os(linux)) {
/*
    saudio_log_item

    Log items are defined via X-Macros, and expanded to an
    enum 'saudio_log_item', and in debug mode only,
    corresponding strings.

    Used as parameter in the logging callback.
*/
enum saudio_log_item {
    SAUDIO_LOGITEM_OK = 0,
    SAUDIO_LOGITEM_MALLOC_FAILED = 1,
    SAUDIO_LOGITEM_ALSA_SND_PCM_OPEN_FAILED = 2,
    SAUDIO_LOGITEM_ALSA_FLOAT_SAMPLES_NOT_SUPPORTED = 3,
    SAUDIO_LOGITEM_ALSA_REQUESTED_BUFFER_SIZE_NOT_SUPPORTED = 4,
    SAUDIO_LOGITEM_ALSA_REQUESTED_CHANNEL_COUNT_NOT_SUPPORTED = 5,
    SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_SET_RATE_NEAR_FAILED = 6,
    SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_FAILED = 7,
    SAUDIO_LOGITEM_ALSA_PTHREAD_CREATE_FAILED = 8,
    SAUDIO_LOGITEM_WASAPI_CREATE_EVENT_FAILED = 9,
    SAUDIO_LOGITEM_WASAPI_CREATE_DEVICE_ENUMERATOR_FAILED = 10,
    SAUDIO_LOGITEM_WASAPI_GET_DEFAULT_AUDIO_ENDPOINT_FAILED = 11,
    SAUDIO_LOGITEM_WASAPI_DEVICE_ACTIVATE_FAILED = 12,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_INITIALIZE_FAILED = 13,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_BUFFER_SIZE_FAILED = 14,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_SERVICE_FAILED = 15,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_SET_EVENT_HANDLE_FAILED = 16,
    SAUDIO_LOGITEM_WASAPI_CREATE_THREAD_FAILED = 17,
    SAUDIO_LOGITEM_AAUDIO_STREAMBUILDER_OPEN_STREAM_FAILED = 18,
    SAUDIO_LOGITEM_AAUDIO_PTHREAD_CREATE_FAILED = 19,
    SAUDIO_LOGITEM_AAUDIO_RESTARTING_STREAM_AFTER_ERROR = 20,
    SAUDIO_LOGITEM_USING_AAUDIO_BACKEND = 21,
    SAUDIO_LOGITEM_AAUDIO_CREATE_STREAMBUILDER_FAILED = 22,
    SAUDIO_LOGITEM_COREAUDIO_NEW_OUTPUT_FAILED = 23,
    SAUDIO_LOGITEM_COREAUDIO_ALLOCATE_BUFFER_FAILED = 24,
    SAUDIO_LOGITEM_COREAUDIO_START_FAILED = 25,
    SAUDIO_LOGITEM_BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE = 26,
    SAUDIO_LOGITEM_VITA_SCEAUDIO_OPEN_FAILED = 27,
    SAUDIO_LOGITEM_VITA_PTHREAD_CREATE_FAILED = 28,
    SAUDIO_LOGITEM_N3DS_NDSP_OPEN_FAILED = 29,
}
enum saudio_n3ds_ndspinterptype {
    SAUDIO_N3DS_DSP_INTERP_POLYPHASE = 0,
    SAUDIO_N3DS_DSP_INTERP_LINEAR = 1,
    SAUDIO_N3DS_DSP_INTERP_NONE = 2,
}
/*
    saudio_logger

    Used in saudio_desc to provide a custom logging and error reporting
    callback to sokol-audio.
*/
struct saudio_logger {
    fn(u8*, u32, u32, u8*, u32, u8*, void*): void func;
    void* user_data;
}
/*
    saudio_allocator

    Used in saudio_desc to provide custom memory-alloc and -free functions
    to sokol_audio.h. If memory management should be overridden, both the
    alloc_fn and free_fn function must be provided (e.g. it's not valid to
    override one function but not the other).
*/
struct saudio_allocator {
    fn(u64, void*): void* alloc_fn;
    fn(void*, void*): void free_fn;
    void* user_data;
}
struct saudio_n3ds_desc {
    i32 queue_count;
    saudio_n3ds_ndspinterptype interpolation_type;
    i32 channel_id;
}
struct saudio_win32_desc {
    bool skip_coinitialize;
}
struct saudio_desc {
    i32 sample_rate;
    i32 num_channels;
    i32 buffer_frames;
    i32 packet_frames;
    i32 num_packets;
    fn(f32*, i32, i32): void stream_cb;
    fn(f32*, i32, i32, void*): void stream_userdata_cb;
    void* user_data;
    saudio_win32_desc win32;
    saudio_n3ds_desc n3ds;
    saudio_allocator allocator;
    saudio_logger logger;
}
/* a ringbuffer structure */
struct _saudio_ring_t {
    i32 head;
    i32 tail;
    i32 num;
    i32[1024] queue;
}
/* a packet FIFO structure */
struct _saudio_fifo_t {
    bool valid;
    i32 packet_size;
    i32 num_packets;
    u8* base_ptr;
    i32 cur_packet;
    i32 cur_offset;
    _saudio_mutex_t mutex;
    _saudio_ring_t read_queue;
    _saudio_ring_t write_queue;
}
/* sokol-audio state */
struct _saudio_state_t {
    bool valid;
    bool setup_called;
    fn(f32*, i32, i32): void stream_cb;
    fn(f32*, i32, i32, void*): void stream_userdata_cb;
    void* user_data;
    i32 sample_rate;
    i32 buffer_frames;
    i32 bytes_per_frame;
    i32 packet_frames;
    i32 num_packets;
    i32 num_channels;
    saudio_desc desc;
    _saudio_fifo_t fifo;
    _saudio_backend_t backend;
}
/*
    sokol_audio.h -- cross-platform audio-streaming API

    Project URL: https://github.com/floooh/sokol

    Do this:
        #define SOKOL_IMPL or
        #define SOKOL_AUDIO_IMPL
    before you include this file in *one* C or C++ file to create the
    implementation.

    Optionally provide the following defines with your own implementations:

    SOKOL_DUMMY_BACKEND - use a dummy backend
    SOKOL_ASSERT(c)     - your own assert macro (default: assert(c))
    SOKOL_AUDIO_API_DECL- public function declaration prefix (default: extern)
    SOKOL_API_DECL      - same as SOKOL_AUDIO_API_DECL
    SOKOL_API_IMPL      - public function implementation prefix (default: -)

    SAUDIO_RING_MAX_SLOTS           - max number of slots in the push-audio ring buffer (default 1024)

    If sokol_audio.h is compiled as a DLL, define the following before
    including the declaration or implementation:

    SOKOL_DLL

    On Windows, SOKOL_DLL will define SOKOL_AUDIO_API_DECL as __declspec(dllexport)
    or __declspec(dllimport) as needed.

    Link with the following libraries:

    - on macOS: AudioToolbox
    - on iOS: AudioToolbox, AVFoundation
    - on FreeBSD: asound
    - on Linux: asound
    - on Android: aaudio
    - on Windows with MSVC or Clang toolchain: no action needed, libs are defined in-source via pragma-comment-lib
    - on Windows with MINGW/MSYS2 gcc: compile with '-mwin32' and link with -lole32
    - on Vita: SceAudio
    - on 3DS: NDSP (libctru)

    FEATURE OVERVIEW
    ================
    You provide a mono- or stereo-stream of 32-bit float samples, which
    Sokol Audio feeds into platform-specific audio backends:

    - Windows: WASAPI
    - Linux: ALSA
    - FreeBSD: ALSA
    - macOS: CoreAudio
    - iOS: CoreAudio+AVAudioSession
    - emscripten: WebAudio with ScriptProcessorNode
    - Android: AAudio
    - Vita: SceAudio
    - 3DS: NDSP (libctru)

    Sokol Audio will not do any buffer mixing or volume control, if you have
    multiple independent input streams of sample data you need to perform the
    mixing yourself before forwarding the data to Sokol Audio.

    There are two mutually exclusive ways to provide the sample data:

    1. Callback model: You provide a callback function, which will be called
       when Sokol Audio needs new samples. On all platforms except emscripten,
       this function is called from a separate thread.
    2. Push model: Your code pushes small blocks of sample data from your
       main loop or a thread you created. The pushed data is stored in
       a ring buffer where it is pulled by the backend code when
       needed.

    The callback model is preferred because it is the most direct way to
    feed sample data into the audio backends and also has less moving parts
    (there is no ring buffer between your code and the audio backend).

    Sometimes it is not possible to generate the audio stream directly in a
    callback function running in a separate thread, for such cases Sokol Audio
    provides the push-model as a convenience.

    SOKOL AUDIO, SOLOUD AND MINIAUDIO
    =================================
    The WASAPI, ALSA and CoreAudio backend code has been taken from the
    SoLoud library (with some modifications, so any bugs in there are most
    likely my fault). If you need a more fully-featured audio solution, check
    out SoLoud, it's excellent:

        https://github.com/jarikomppa/soloud

    Another alternative which feature-wise is somewhere inbetween SoLoud and
    sokol-audio might be MiniAudio:

        https://github.com/mackron/miniaudio

    GLOSSARY
    ========
    - stream buffer:
        The internal audio data buffer, usually provided by the backend API. The
        size of the stream buffer defines the base latency, smaller buffers have
        lower latency but may cause audio glitches. Bigger buffers reduce or
        eliminate glitches, but have a higher base latency.

    - stream callback:
        Optional callback function which is called by Sokol Audio when it
        needs new samples. On Windows, macOS/iOS and Linux, this is called in
        a separate thread, on WebAudio, this is called per-frame in the
        browser thread.

    - channel:
        A discrete track of audio data, currently 1-channel (mono) and
        2-channel (stereo) is supported and tested.

    - sample:
        The magnitude of an audio signal on one channel at a given time. In
        Sokol Audio, samples are 32-bit float numbers in the range -1.0 to
        +1.0.

    - frame:
        The tightly packed set of samples for all channels at a given time.
        For mono 1 frame is 1 sample. For stereo, 1 frame is 2 samples.

    - packet:
        In Sokol Audio, a small chunk of audio data that is moved from the
        main thread to the audio streaming thread in order to decouple the
        rate at which the main thread provides new audio data, and the
        streaming thread consuming audio data.

    WORKING WITH SOKOL AUDIO
    ========================
    First call saudio_setup() with your preferred audio playback options.
    In most cases you can stick with the default values, these provide
    a good balance between low-latency and glitch-free playback
    on all audio backends.

    You should always provide a logging callback to be aware of any
    warnings and errors. The easiest way is to use sokol_log.h for this:

        #include "sokol_log.h"
        // ...
        saudio_setup(&(saudio_desc){
            .logger = {
                .func = slog_func,
            }
        });

    If you want to use the callback-model, you need to provide a stream
    callback function either in saudio_desc.stream_cb or saudio_desc.stream_userdata_cb,
    otherwise keep both function pointers zero-initialized.

    Use push model and default playback parameters:

        saudio_setup(&(saudio_desc){ .logger.func = slog_func });

    Use stream callback model and default playback parameters:

        saudio_setup(&(saudio_desc){
            .stream_cb = my_stream_callback
            .logger.func = slog_func,
        });

    The standard stream callback doesn't have a user data argument, if you want
    that, use the alternative stream_userdata_cb and also set the user_data pointer:

        saudio_setup(&(saudio_desc){
            .stream_userdata_cb = my_stream_callback,
            .user_data = &my_data
            .logger.func = slog_func,
        });

    The following playback parameters can be provided through the
    saudio_desc struct:

    General parameters (both for stream-callback and push-model):

        int sample_rate     -- the sample rate in Hz, default: 44100
        int num_channels    -- number of channels, default: 1 (mono)
        int buffer_frames   -- number of frames in streaming buffer, default: 2048

    The stream callback prototype (either with or without userdata):

        void (*stream_cb)(float* buffer, int num_frames, int num_channels)
        void (*stream_userdata_cb)(float* buffer, int num_frames, int num_channels, void* user_data)
            Function pointer to the user-provide stream callback.

    Push-model parameters:

        int packet_frames   -- number of frames in a packet, default: 128
        int num_packets     -- number of packets in ring buffer, default: 64

    The sample_rate and num_channels parameters are only hints for the audio
    backend, it isn't guaranteed that those are the values used for actual
    playback.

    To get the actual parameters, call the following functions after
    saudio_setup():

        int saudio_sample_rate(void)
        int saudio_channels(void);

    It's unlikely that the number of channels will be different than requested,
    but a different sample rate isn't uncommon.

    (NOTE: there's an yet unsolved issue when an audio backend might switch
    to a different sample rate when switching output devices, for instance
    plugging in a bluetooth headset, this case is currently not handled in
    Sokol Audio).

    You can check if audio initialization was successful with
    saudio_isvalid(). If backend initialization failed for some reason
    (for instance when there's no audio device in the machine), this
    will return false. Not checking for success won't do any harm, all
    Sokol Audio function will silently fail when called after initialization
    has failed, so apart from missing audio output, nothing bad will happen.

    Before your application exits, you should call

        saudio_shutdown();

    This stops the audio thread (on Linux, Windows and macOS/iOS) and
    properly shuts down the audio backend.

    THE STREAM CALLBACK MODEL
    =========================
    To use Sokol Audio in stream-callback-mode, provide a callback function
    like this in the saudio_desc struct when calling saudio_setup():

    void stream_cb(float* buffer, int num_frames, int num_channels) {
        ...
    }

    Or the alternative version with a user-data argument:

    void stream_userdata_cb(float* buffer, int num_frames, int num_channels, void* user_data) {
        my_data_t* my_data = (my_data_t*) user_data;
        ...
    }

    The job of the callback function is to fill the *buffer* with 32-bit
    float sample values.

    To output silence, fill the buffer with zeros:

        void stream_cb(float* buffer, int num_frames, int num_channels) {
            const int num_samples = num_frames * num_channels;
            for (int i = 0; i < num_samples; i++) {
                buffer[i] = 0.0f;
            }
        }

    For stereo output (num_channels == 2), the samples for the left
    and right channel are interleaved:

        void stream_cb(float* buffer, int num_frames, int num_channels) {
            assert(2 == num_channels);
            for (int i = 0; i < num_frames; i++) {
                buffer[2*i + 0] = ...;  // left channel
                buffer[2*i + 1] = ...;  // right channel
            }
        }

    Please keep in mind that the stream callback function is running in a
    separate thread, if you need to share data with the main thread you need
    to take care yourself to make the access to the shared data thread-safe!

    THE PUSH MODEL
    ==============
    To use the push-model for providing audio data, simply don't set (keep
    zero-initialized) the stream_cb field in the saudio_desc struct when
    calling saudio_setup().

    To provide sample data with the push model, call the saudio_push()
    function at regular intervals (for instance once per frame). You can
    call the saudio_expect() function to ask Sokol Audio how much room is
    in the ring buffer, but if you provide a continuous stream of data
    at the right sample rate, saudio_expect() isn't required (it's a simple
    way to sync/throttle your sample generation code with the playback
    rate though).

    With saudio_push() you may need to maintain your own intermediate sample
    buffer, since pushing individual sample values isn't very efficient.
    The following example is from the MOD player sample in
    sokol-samples (https://github.com/floooh/sokol-samples):

        const int num_frames = saudio_expect();
        if (num_frames > 0) {
            const int num_samples = num_frames * saudio_channels();
            read_samples(flt_buf, num_samples);
            saudio_push(flt_buf, num_frames);
        }

    Another option is to ignore saudio_expect(), and just push samples as they
    are generated in small batches. In this case you *need* to generate the
    samples at the right sample rate:

    The following example is taken from the Tiny Emulators project
    (https://github.com/floooh/chips-test), this is for mono playback,
    so (num_samples == num_frames):

        // tick the sound generator
        if (ay38910_tick(&sys->psg)) {
            // new sample is ready
            sys->sample_buffer[sys->sample_pos++] = sys->psg.sample;
            if (sys->sample_pos == sys->num_samples) {
                // new sample packet is ready
                saudio_push(sys->sample_buffer, sys->num_samples);
                sys->sample_pos = 0;
            }
        }

    THE WEBAUDIO BACKEND
    ====================
    The WebAudio backend is currently using a ScriptProcessorNode callback to
    feed the sample data into WebAudio. ScriptProcessorNode has been
    deprecated for a while because it is running from the main thread, with
    the default initialization parameters it works 'pretty well' though.
    Ultimately Sokol Audio will use Audio Worklets, but this requires a few
    more things to fall into place (Audio Worklets implemented everywhere,
    SharedArrayBuffers enabled again, and I need to figure out a 'low-cost'
    solution in terms of implementation effort, since Audio Worklets are
    a lot more complex than ScriptProcessorNode if the audio data needs to come
    from the main thread).

    The WebAudio backend is automatically selected when compiling for
    emscripten (__EMSCRIPTEN__ define exists).

    https://developers.google.com/web/updates/2017/12/audio-worklet
    https://developers.google.com/web/updates/2018/06/audio-worklet-design-pattern

    "Blob URLs": https://www.html5rocks.com/en/tutorials/workers/basics/

    Also see: https://blog.paul.cx/post/a-wait-free-spsc-ringbuffer-for-the-web/

    THE COREAUDIO BACKEND
    =====================
    The CoreAudio backend is selected on macOS and iOS (__APPLE__ is defined).
    Since the CoreAudio API is implemented in C (not Objective-C) on macOS the
    implementation part of Sokol Audio can be included into a C source file.

    However on iOS, Sokol Audio must be compiled as Objective-C due to it's
    reliance on the AVAudioSession object. The iOS code path support both
    being compiled with or without ARC (Automatic Reference Counting).

    For thread synchronisation, the CoreAudio backend will use the
    pthread_mutex_* functions.

    The incoming floating point samples will be directly forwarded to
    CoreAudio without further conversion.

    macOS and iOS applications that use Sokol Audio need to link with
    the AudioToolbox framework.

    THE WASAPI BACKEND
    ==================
    The WASAPI backend is automatically selected when compiling on Windows
    (_WIN32 is defined).

    For thread synchronisation a Win32 critical section is used.

    By default, the WASAPI backend calls CoInitializeEx(0, COINIT_MULTITHREADED)
    in saudio_setup() and CoUninitialize() in saudio_shutdown(). This can be
    disabled with the setup option `saudio_desc.win32.skip_coinitialize`. In that
    case the library user must make sure to initialize COM before calling
    saudio_setup() (FWIW though, at least on Win11 it looks like CoInitializeEx
    isn't needed at all for sokol_audio.h, take that info with a huge grain of salt
    though).

    WASAPI may use a different size for its own streaming buffer then requested,
    so the base latency may be slightly bigger. The current backend implementation
    converts the incoming floating point sample values to signed 16-bit
    integers.

    The required Windows system DLLs are linked with #pragma comment(lib, ...),
    so you shouldn't need to add additional linker libs in the build process
    (otherwise this is a bug which should be fixed in sokol_audio.h).

    THE ALSA BACKEND
    ================
    The ALSA backend is automatically selected when compiling on Linux
    ('linux' is defined).

    For thread synchronisation, the pthread_mutex_* functions are used.

    Samples are directly forwarded to ALSA in 32-bit float format, no
    further conversion is taking place.

    You need to link with the 'asound' library, and the <alsa/asoundlib.h>
    header must be present (usually both are installed with some sort
    of ALSA development package).

    THE VITA BACKEND
    ================
    The VITA backend is automatically selected when compiling with vitasdk
    ('PSP2_SDK_VERSION' is defined).

    For thread synchronisation, the pthread_mutex_* functions are used.

    Samples are converted from float to short (uint16_t) to maintain
    all the same interface/api as other platforms.

    You may use any supported sample rate you wish, but all audio MUST
    match the same sample rate you choose.

    This uses the "BGM" port to allow selecting the sample rate ("Main"
    port is restricted to 48000 only).

    You need to link with the 'SceAudio' library, and the <psp2/audioout.h>
    header must be present (usually both are installed with the vitasdk).

    THE 3DS BACKEND
    ================
    The 3DS backend is automatically selected when compiling with libctru
    ('__3DS__' is defined).

    Running a separate thread on the older 3ds is not a good idea and I
    was not able to get it working without slowing down the main thread
    too much (it has a single core available with cooperative threads).

    The NDSP seems to work better by using its ndspSetCallback method.

    You may use any supported sample rate you wish, but all audio MUST
    match the same sample rate you choose or it will sound slowed down
    or sped up.

    The queue size and other NDSP specific parameters can be chosen by
    the provided 'saudio_n3ds_desc' type. Defaults will be used if
    nothing is provided.

    There is a known issue of a noticeable delay when starting a new
    sound on emulators. I was not able to improve this to my liking
    and ~300ms can be expected. This can be improved by using a lower
    buffer size than the 2048 default but I would not suggest under
    1536. It may crash under 1408, and they must be in multiples of 128.
    Note: I was NOT able to reproduce this issue on a real device and
    the audio worked perfectly.


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
            saudio_setup(&(saudio_desc){
                // ...
                .allocator = {
                    .alloc_fn = my_alloc,
                    .free_fn = my_free,
                    .user_data = ...,
                }
            });
        ...

    If no overrides are provided, malloc and free will be used.

    This only affects memory allocation calls done by sokol_audio.h
    itself though, not any allocations in OS libraries.

    Memory allocation will only happen on the same thread where saudio_setup()
    was called, so you don't need to worry about thread-safety.


    ERROR REPORTING AND LOGGING
    ===========================
    To get any logging information at all you need to provide a logging callback in the setup call
    the easiest way is to use sokol_log.h:

        #include "sokol_log.h"

        saudio_setup(&(saudio_desc){ .logger.func = slog_func });

    To override logging with your own callback, first write a logging function like this:

        void my_log(const char* tag,                // e.g. 'saudio'
                    uint32_t log_level,             // 0=panic, 1=error, 2=warn, 3=info
                    uint32_t log_item_id,           // SAUDIO_LOGITEM_*
                    const char* message_or_null,    // a message string, may be nullptr in release mode
                    uint32_t line_nr,               // line number in sokol_audio.h
                    const char* filename_or_null,   // source filename, may be nullptr in release mode
                    void* user_data)
        {
            ...
        }

    ...and then setup sokol-audio like this:

        saudio_setup(&(saudio_desc){
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
// ██ ███    ███ ██████  ██      ███████ ███    ███ ███████ ███    ██ ████████  █████  ████████ ██  ██████  ███    ██
// ██ ████  ████ ██   ██ ██      ██      ████  ████ ██      ████   ██    ██    ██   ██    ██    ██ ██    ██ ████   ██
// ██ ██ ████ ██ ██████  ██      █████   ██ ████ ██ █████   ██ ██  ██    ██    ███████    ██    ██ ██    ██ ██ ██  ██
// ██ ██  ██  ██ ██      ██      ██      ██  ██  ██ ██      ██  ██ ██    ██    ██   ██    ██    ██ ██    ██ ██  ██ ██
// ██ ██      ██ ██      ███████ ███████ ██      ██ ███████ ██   ████    ██    ██   ██    ██    ██  ██████  ██   ████
//
// >>implementation
when !(defined(SOKOL_DEBUG)) {
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
u8*[30] _saudio_log_messages = {
    "OK: Ok", "MALLOC_FAILED: memory allocation failed",
    "ALSA_SND_PCM_OPEN_FAILED: snd_pcm_open() failed",
    "ALSA_FLOAT_SAMPLES_NOT_SUPPORTED: floating point sample format not supported",
    "ALSA_REQUESTED_BUFFER_SIZE_NOT_SUPPORTED: requested buffer size not supported",
    "ALSA_REQUESTED_CHANNEL_COUNT_NOT_SUPPORTED: requested channel count not supported",
    "ALSA_SND_PCM_HW_PARAMS_SET_RATE_NEAR_FAILED: snd_pcm_hw_params_set_rate_near() failed",
    "ALSA_SND_PCM_HW_PARAMS_FAILED: snd_pcm_hw_params() failed",
    "ALSA_PTHREAD_CREATE_FAILED: pthread_create() failed",
    "WASAPI_CREATE_EVENT_FAILED: CreateEvent() failed",
    "WASAPI_CREATE_DEVICE_ENUMERATOR_FAILED: CoCreateInstance() for IMMDeviceEnumerator failed",
    "WASAPI_GET_DEFAULT_AUDIO_ENDPOINT_FAILED: IMMDeviceEnumerator.GetDefaultAudioEndpoint() failed",
    "WASAPI_DEVICE_ACTIVATE_FAILED: IMMDevice.Activate() failed",
    "WASAPI_AUDIO_CLIENT_INITIALIZE_FAILED: IAudioClient.Initialize() failed",
    "WASAPI_AUDIO_CLIENT_GET_BUFFER_SIZE_FAILED: IAudioClient.GetBufferSize() failed",
    "WASAPI_AUDIO_CLIENT_GET_SERVICE_FAILED: IAudioClient.GetService() failed",
    "WASAPI_AUDIO_CLIENT_SET_EVENT_HANDLE_FAILED: IAudioClient.SetEventHandle() failed",
    "WASAPI_CREATE_THREAD_FAILED: CreateThread() failed",
    "AAUDIO_STREAMBUILDER_OPEN_STREAM_FAILED: AAudioStreamBuilder_openStream() failed",
    "AAUDIO_PTHREAD_CREATE_FAILED: pthread_create() failed after AAUDIO_ERROR_DISCONNECTED",
    "AAUDIO_RESTARTING_STREAM_AFTER_ERROR: restarting AAudio stream after error",
    "USING_AAUDIO_BACKEND: using AAudio backend",
    "AAUDIO_CREATE_STREAMBUILDER_FAILED: AAudio_createStreamBuilder() failed",
    "COREAUDIO_NEW_OUTPUT_FAILED: AudioQueueNewOutput() failed",
    "COREAUDIO_ALLOCATE_BUFFER_FAILED: AudioQueueAllocateBuffer() failed",
    "COREAUDIO_START_FAILED: AudioQueueStart() failed",
    "BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE: backend buffer size isn't multiple of packet size",
    "VITA_SCEAUDIO_OPEN_FAILED: sceAudioOutOpenPort() failed",
    "VITA_PTHREAD_CREATE_FAILED: pthread_create() failed",
    "N3DS_NDSP_OPEN_FAILED: ndspInit() failed",
};
}
}
// ██████  ██    ██ ██████  ██      ██  ██████
// ██   ██ ██    ██ ██   ██ ██      ██ ██
// ██████  ██    ██ ██████  ██      ██ ██
// ██      ██    ██ ██   ██ ██      ██ ██
// ██       ██████  ██████  ███████ ██  ██████
//
// >>public
void saudio_setup(saudio_desc* desc) {
    assert(cast(i64, !_saudio.valid));
    assert(cast(i64, !_saudio.setup_called));
    assert(cast(i64, desc));
    assert(desc.allocator.alloc_fn && desc.allocator.free_fn || !desc.allocator.alloc_fn && !desc.allocator.free_fn);
    _saudio_clear(&_saudio, cast(u64, sizeof(_saudio)));
    _saudio.setup_called = true;
    _saudio.desc = *desc;
    _saudio.stream_cb = desc.stream_cb;
    _saudio.stream_userdata_cb = desc.stream_userdata_cb;
    _saudio.user_data = desc.user_data;
    _saudio.sample_rate = _saudio.desc.sample_rate == 0 ? 44100 : _saudio.desc.sample_rate;
    _saudio.buffer_frames = _saudio.desc.buffer_frames == 0 ? 2048 : _saudio.desc.buffer_frames;
    _saudio.packet_frames = _saudio.desc.packet_frames == 0 ? 128 : _saudio.desc.packet_frames;
    _saudio.num_packets = _saudio.desc.num_packets == 0 ? 2048 / 128 * 4 : _saudio.desc.num_packets;
    _saudio.num_channels = _saudio.desc.num_channels == 0 ? 1 : _saudio.desc.num_channels;
    _saudio_fifo_init_mutex(&_saudio.fifo);
    if _saudio_backend_init() != 0 {
        if 0 != _saudio.buffer_frames % _saudio.packet_frames {
            _saudio_log(SAUDIO_LOGITEM_BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE, 1, __line__);
            _saudio_backend_shutdown();
            return;
        }
        assert(_saudio.bytes_per_frame > 0);
        _saudio_fifo_init(&_saudio.fifo, _saudio.packet_frames * _saudio.bytes_per_frame, _saudio.num_packets);
        _saudio.valid = true;
    } else {
        _saudio_fifo_destroy_mutex(&_saudio.fifo);
    }
}
void saudio_shutdown() {
    assert(cast(i64, _saudio.setup_called));
    _saudio.setup_called = false;
    if _saudio.valid != 0 {
        _saudio_backend_shutdown();
        _saudio_fifo_shutdown(&_saudio.fifo);
        _saudio_fifo_destroy_mutex(&_saudio.fifo);
        _saudio.valid = false;
    }
}
bool saudio_isvalid() {
    return _saudio.valid;
}
void* saudio_userdata() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.desc.user_data;
}
saudio_desc saudio_query_desc() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.desc;
}
i32 saudio_sample_rate() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.sample_rate;
}
i32 saudio_buffer_frames() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.buffer_frames;
}
i32 saudio_channels() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.num_channels;
}
bool saudio_suspended() {
    assert(cast(i64, _saudio.setup_called));
    return false;
}
i32 saudio_expect() {
    assert(cast(i64, _saudio.setup_called));
    if _saudio.valid != 0 {
        i32 num_frames = _saudio_fifo_writable_bytes(&_saudio.fifo) / _saudio.bytes_per_frame;
        return num_frames;
    } else {
        return 0;
    }
}
i32 saudio_push(f32* frames, i32 num_frames) {
    assert(cast(i64, _saudio.setup_called));
    assert(frames && num_frames > 0);
    if _saudio.valid != 0 {
        i32 num_bytes = num_frames * _saudio.bytes_per_frame;
        i32 num_written = _saudio_fifo_write(&_saudio.fifo, cast(u8*, frames), num_bytes);
        return num_written / _saudio.bytes_per_frame;
    } else {
        return 0;
    }
}
private {
_saudio_state_t _saudio;
bool _saudio_has_callback() {
    return _saudio.stream_cb || _saudio.stream_userdata_cb;
}
void _saudio_stream_callback(f32* buffer, i32 num_frames, i32 num_channels) {
    if _saudio.stream_cb != null {
        _saudio.stream_cb(buffer, num_frames, num_channels);
    } else if _saudio.stream_userdata_cb != null {
        _saudio.stream_userdata_cb(buffer, num_frames, num_channels, _saudio.user_data);
    }
}
void _saudio_log(saudio_log_item log_item, u32 log_level, u32 line_nr) {
    if _saudio.desc.logger.func != null {
        u8* filename;
        u8* message;
        when defined(SOKOL_DEBUG) {
            filename = __file__;
            message = _saudio_log_messages[log_item];
        } else {
            filename = null;
            message = null;
        }
        _saudio.desc.logger.func("saudio", log_level, cast(u32, log_item), message, line_nr, filename, _saudio.desc.logger.user_data);
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
void _saudio_clear(void* ptr, u64 size) {
    assert(ptr && size > 0);
    memset(ptr, 0, size);
}
void* _saudio_malloc(u64 size) {
    assert(size > 0);
    void* ptr;
    if _saudio.desc.allocator.alloc_fn != null {
        ptr = _saudio.desc.allocator.alloc_fn(size, _saudio.desc.allocator.user_data);
    } else {
        ptr = alloc(cast(i64, size));
    }
    if null == ptr {
        _saudio_log(SAUDIO_LOGITEM_MALLOC_FAILED, 0, __line__);
    }
    return ptr;
}
void* _saudio_malloc_clear(u64 size) {
    void* ptr = _saudio_malloc(size);
    _saudio_clear(ptr, size);
    return ptr;
}
void _saudio_free(void* ptr) {
    if _saudio.desc.allocator.free_fn != null {
        _saudio.desc.allocator.free_fn(ptr, _saudio.desc.allocator.user_data);
    } else {
        free(ptr);
    }
}
// ██████  ██ ███    ██  ██████  ██████  ██    ██ ███████ ███████ ███████ ██████
// ██   ██ ██ ████   ██ ██       ██   ██ ██    ██ ██      ██      ██      ██   ██
// ██████  ██ ██ ██  ██ ██   ███ ██████  ██    ██ █████   █████   █████   ██████
// ██   ██ ██ ██  ██ ██ ██    ██ ██   ██ ██    ██ ██      ██      ██      ██   ██
// ██   ██ ██ ██   ████  ██████  ██████   ██████  ██      ██      ███████ ██   ██
//
// >>ringbuffer
i32 _saudio_ring_idx(_saudio_ring_t* ring, i32 i) {
    return i % ring.num;
}
void _saudio_ring_init(_saudio_ring_t* ring, i32 num_slots) {
    assert(num_slots + 1 <= 1024);
    ring.head = 0;
    ring.tail = 0;
    ring.num = num_slots + 1;
}
bool _saudio_ring_full(_saudio_ring_t* ring) {
    return _saudio_ring_idx(ring, ring.head + 1) == ring.tail;
}
bool _saudio_ring_empty(_saudio_ring_t* ring) {
    return ring.head == ring.tail;
}
i32 _saudio_ring_count(_saudio_ring_t* ring) {
    i32 count;
    if ring.head >= ring.tail {
        count = ring.head - ring.tail;
    } else {
        count = ring.head + ring.num - ring.tail;
    }
    assert(count < ring.num);
    return count;
}
void _saudio_ring_enqueue(_saudio_ring_t* ring, i32 val) {
    assert(cast(i64, !_saudio_ring_full(ring)));
    ring.queue[ring.head] = val;
    ring.head = _saudio_ring_idx(ring, ring.head + 1);
}
i32 _saudio_ring_dequeue(_saudio_ring_t* ring) {
    assert(cast(i64, !_saudio_ring_empty(ring)));
    i32 val = ring.queue[ring.tail];
    ring.tail = _saudio_ring_idx(ring, ring.tail + 1);
    return val;
}
// ███████ ██ ███████  ██████
// ██      ██ ██      ██    ██
// █████   ██ █████   ██    ██
// ██      ██ ██      ██    ██
// ██      ██ ██       ██████
//
// >>fifo
void _saudio_fifo_init_mutex(_saudio_fifo_t* fifo) {
    _saudio_mutex_init(&fifo.mutex);
}
void _saudio_fifo_destroy_mutex(_saudio_fifo_t* fifo) {
    _saudio_mutex_destroy(&fifo.mutex);
}
void _saudio_fifo_init(_saudio_fifo_t* fifo, i32 packet_size, i32 num_packets) {
    _saudio_mutex_lock(&fifo.mutex);
    assert(packet_size > 0 && num_packets > 0);
    fifo.packet_size = packet_size;
    fifo.num_packets = num_packets;
    fifo.base_ptr = cast(u8*, _saudio_malloc(cast(u64, packet_size * num_packets)));
    fifo.cur_packet = -1;
    fifo.cur_offset = 0;
    _saudio_ring_init(&fifo.read_queue, num_packets);
    _saudio_ring_init(&fifo.write_queue, num_packets);
    for i32 i = 0; i < num_packets; i++ {
        _saudio_ring_enqueue(&fifo.write_queue, i);
    }
    assert(cast(i64, _saudio_ring_full(&fifo.write_queue)));
    assert(_saudio_ring_count(&fifo.write_queue) == num_packets);
    assert(cast(i64, _saudio_ring_empty(&fifo.read_queue)));
    assert(_saudio_ring_count(&fifo.read_queue) == 0);
    fifo.valid = true;
    _saudio_mutex_unlock(&fifo.mutex);
}
void _saudio_fifo_shutdown(_saudio_fifo_t* fifo) {
    assert(cast(i64, fifo.base_ptr));
    _saudio_free(fifo.base_ptr);
    fifo.base_ptr = null;
    fifo.valid = false;
}
i32 _saudio_fifo_writable_bytes(_saudio_fifo_t* fifo) {
    _saudio_mutex_lock(&fifo.mutex);
    i32 num_bytes = _saudio_ring_count(&fifo.write_queue) * fifo.packet_size;
    if fifo.cur_packet != -1 {
        num_bytes += fifo.packet_size - fifo.cur_offset;
    }
    _saudio_mutex_unlock(&fifo.mutex);
    assert(num_bytes >= 0 && num_bytes <= fifo.num_packets * fifo.packet_size);
    return num_bytes;
}
/* write new data to the write queue, this is called from main thread */
i32 _saudio_fifo_write(_saudio_fifo_t* fifo, u8* ptr, i32 num_bytes) {
    i32 all_to_copy = num_bytes;
    while all_to_copy > 0 {
        if fifo.cur_packet == -1 {
            _saudio_mutex_lock(&fifo.mutex);
            if _saudio_ring_empty(&fifo.write_queue) == 0 {
                fifo.cur_packet = _saudio_ring_dequeue(&fifo.write_queue);
            }
            _saudio_mutex_unlock(&fifo.mutex);
            assert(fifo.cur_offset == 0);
        }
        if fifo.cur_packet != -1 {
            i32 to_copy = all_to_copy;
            i32 max_copy = fifo.packet_size - fifo.cur_offset;
            if to_copy > max_copy {
                to_copy = max_copy;
            }
            u8* dst = fifo.base_ptr + fifo.cur_packet * fifo.packet_size + fifo.cur_offset;
            memcpy(dst, ptr, cast(u64, to_copy));
            ptr += to_copy;
            fifo.cur_offset += to_copy;
            all_to_copy -= to_copy;
            assert(fifo.cur_offset <= fifo.packet_size);
            assert(all_to_copy >= 0);
        } else {
            i32 bytes_copied = num_bytes - all_to_copy;
            assert(bytes_copied >= 0 && bytes_copied < num_bytes);
            return bytes_copied;
        }
        if fifo.cur_offset == fifo.packet_size {
            _saudio_mutex_lock(&fifo.mutex);
            _saudio_ring_enqueue(&fifo.read_queue, fifo.cur_packet);
            _saudio_mutex_unlock(&fifo.mutex);
            fifo.cur_packet = -1;
            fifo.cur_offset = 0;
        }
    }
    assert(all_to_copy == 0);
    return num_bytes;
}
/* read queued data, this is called form the stream callback (maybe separate thread) */
i32 _saudio_fifo_read(_saudio_fifo_t* fifo, u8* ptr, i32 num_bytes) {
    _saudio_mutex_lock(&fifo.mutex);
    i32 num_bytes_copied = 0;
    if fifo.valid != 0 {
        assert(0 == num_bytes % fifo.packet_size);
        assert(num_bytes <= fifo.packet_size * fifo.num_packets);
        i32 num_packets_needed = num_bytes / fifo.packet_size;
        u8* dst = ptr;
        if _saudio_ring_count(&fifo.read_queue) >= num_packets_needed {
            for i32 i = 0; i < num_packets_needed; i++ {
                i32 packet_index = _saudio_ring_dequeue(&fifo.read_queue);
                _saudio_ring_enqueue(&fifo.write_queue, packet_index);
                u8* src = fifo.base_ptr + packet_index * fifo.packet_size;
                memcpy(dst, src, cast(u64, fifo.packet_size));
                dst += fifo.packet_size;
                num_bytes_copied += fifo.packet_size;
            }
            assert(num_bytes == num_bytes_copied);
        }
    }
    _saudio_mutex_unlock(&fifo.mutex);
    return num_bytes_copied;
}
}
}

// =====================================================================
// Shared by 3 of the native backend arms below.
// Hoisted by scripts/sokol_dedup.py -- these were byte-identical
// in every arm below.
// =====================================================================
when (os(windows)) || (os(macos) || os(ios)) || (os(linux)) {
private {
// ██████  ██    ██ ███    ███ ███    ███ ██    ██
// ██   ██ ██    ██ ████  ████ ████  ████  ██  ██
// ██   ██ ██    ██ ██ ████ ██ ██ ████ ██   ████
// ██   ██ ██    ██ ██  ██  ██ ██  ██  ██    ██
// ██████   ██████  ██      ██ ██      ██    ██
//
// >>dummy
}
}

// =====================================================================
// Shared by 3 of the native backend arms below.
// Hoisted by scripts/sokol_dedup.py -- these were byte-identical
// in every arm below.
// =====================================================================
when (os(macos) || os(ios)) || (os(android)) || (os(linux)) {
// platform detection defines
// platform-specific headers and definitions
// ███████ ████████ ██████  ██    ██  ██████ ████████ ███████
// ██         ██    ██   ██ ██    ██ ██         ██    ██
// ███████    ██    ██████  ██    ██ ██         ██    ███████
//      ██    ██    ██   ██ ██    ██ ██         ██         ██
// ███████    ██    ██   ██  ██████   ██████    ██    ███████
//
// >>structs
struct _saudio_mutex_t {
    pthread_mutex_t mutex;
}
private {
// ███    ███ ██    ██ ████████ ███████ ██   ██
// ████  ████ ██    ██    ██    ██       ██ ██
// ██ ████ ██ ██    ██    ██    █████     ███
// ██  ██  ██ ██    ██    ██    ██       ██ ██
// ██      ██  ██████     ██    ███████ ██   ██
//
// >>mutex
void _saudio_mutex_init(_saudio_mutex_t* m) {
    noinit pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutex_init(&m.mutex, &attr);
}
void _saudio_mutex_destroy(_saudio_mutex_t* m) {
    pthread_mutex_destroy(&m.mutex);
}
void _saudio_mutex_lock(_saudio_mutex_t* m) {
    pthread_mutex_lock(&m.mutex);
}
void _saudio_mutex_unlock(_saudio_mutex_t* m) {
    pthread_mutex_unlock(&m.mutex);
}
}
}

// =====================================================================
// Shared by 2 of the native backend arms below.
// Hoisted by scripts/sokol_dedup.py -- these were byte-identical
// in every arm below.
// =====================================================================
when (os(macos) || os(ios)) || (os(linux)) {
type size_t = u64;
}

when os(windows) {
enum __enum_PROCESS_DPI_UNAWARE {
    PROCESS_DPI_UNAWARE = 0,
    PROCESS_SYSTEM_DPI_AWARE = 1,
    PROCESS_PER_MONITOR_DPI_AWARE = 2,
    MDT_EFFECTIVE_DPI = 0,
    MDT_ANGULAR_DPI = 1,
    MDT_RAW_DPI = 2,
}



type PROCESS_DPI_AWARENESS = i32;
type MONITOR_DPI_TYPE = i32;
type BOOL = i32;
type BYTE = u8;
type WORD = u16;
type DWORD = u32;
type UINT = u32;
type INT = i32;
type LONG = i32;
type ULONG = u32;
type LONGLONG = i64;
type ULONGLONG = u64;
type SHORT = i16;
type USHORT = u16;
type CHAR = u8;
type UCHAR = u8;
type WCHAR = u16;
type FLOAT = f32;
type HRESULT = i32;
type ATOM = u16;
type UINT_PTR = u64;
type INT_PTR = i64;
type ULONG_PTR = u64;
type LONG_PTR = i64;
type DWORD_PTR = u64;
type SIZE_T = u64;
type SSIZE_T = i64;
type WPARAM = u64;
type LPARAM = i64;
type LRESULT = i64;
type HANDLE = void*;
type HWND = void*;
type HDC = void*;
type HGLRC = void*;
type HINSTANCE = void*;
type HMODULE = void*;
type HMENU = void*;
type HICON = void*;
type HCURSOR = void*;
type HBRUSH = void*;
type HMONITOR = void*;
type HDROP = void*;
type HBITMAP = void*;
type HGDIOBJ = void*;
type HKL = void*;
type HRAWINPUT = void*;
type HLOCAL = void*;
type FARPROC = void*;
type PROC = void*;
type PVOID = void*;
type LPVOID = void*;
type LPCVOID = void*;
type LPSTR = u8*;
type LPCSTR = u8*;
type LPWSTR = WCHAR*;
type LPCWSTR = WCHAR*;
type PCWSTR = WCHAR*;
type LPBYTE = BYTE*;
type LPDWORD = DWORD*;
type LPWORD = WORD*;
type LPLONG = LONG*;
type LPINT = i32*;
type LPUINT = UINT*;
type LPUNKNOWN = void*;
type WNDPROC = fn(HWND, UINT, WPARAM, LPARAM): LRESULT;
type LPRECT = RECT*;
type errno_t = i32;
type handle_type = i64;
type DPI_AWARENESS_CONTEXT_T = void*;
type IID = GUID;
type CLSID = GUID;
type REFIID = GUID*;
type REFCLSID = GUID*;
type UINT32 = u32;
type REFERENCE_TIME = i64;
type _saudio_backend_t = _saudio_wasapi_backend_t;
struct LARGE_INTEGER {
    i64 QuadPart;
}

struct POINT {
    LONG x;
    LONG y;
}

struct POINTL {
    LONG x;
    LONG y;
}

struct RECT {
    LONG left;
    LONG top;
    LONG right;
    LONG bottom;
}

struct SIZE {
    WORD cx;
    WORD cy;
}

struct MSG {
    HWND hwnd;
    UINT message;
    WPARAM wParam;
    LPARAM lParam;
    DWORD time;
    POINT pt;
}

struct WNDCLASSW {
    UINT style;
    WNDPROC lpfnWndProc;
    i32 cbClsExtra;
    i32 cbWndExtra;
    HINSTANCE hInstance;
    HICON hIcon;
    HCURSOR hCursor;
    HBRUSH hbrBackground;
    LPCWSTR lpszMenuName;
    LPCWSTR lpszClassName;
}

struct WNDCLASSEXW {
    UINT cbSize;
    UINT style;
    WNDPROC lpfnWndProc;
    i32 cbClsExtra;
    i32 cbWndExtra;
    HINSTANCE hInstance;
    HICON hIcon;
    HCURSOR hCursor;
    HBRUSH hbrBackground;
    LPCWSTR lpszMenuName;
    LPCWSTR lpszClassName;
    HICON hIconSm;
}

struct PIXELFORMATDESCRIPTOR {
    WORD nSize;
    WORD nVersion;
    DWORD dwFlags;
    BYTE iPixelType;
    BYTE cColorBits;
    BYTE cRedBits;
    BYTE cRedShift;
    BYTE cGreenBits;
    BYTE cGreenShift;
    BYTE cBlueBits;
    BYTE cBlueShift;
    BYTE cAlphaBits;
    BYTE cAlphaShift;
    BYTE cAccumBits;
    BYTE cAccumRedBits;
    BYTE cAccumGreenBits;
    BYTE cAccumBlueBits;
    BYTE cAccumAlphaBits;
    BYTE cDepthBits;
    BYTE cStencilBits;
    BYTE cAuxBuffers;
    BYTE iLayerType;
    BYTE bReserved;
    DWORD dwLayerMask;
    DWORD dwVisibleMask;
    DWORD dwDamageMask;
}

struct TRACKMOUSEEVENT {
    DWORD cbSize;
    DWORD dwFlags;
    HWND hwndTrack;
    DWORD dwHoverTime;
}

struct CURSORINFO {
    DWORD cbSize;
    DWORD flags;
    HCURSOR hCursor;
    POINT ptScreenPos;
}

struct MONITORINFO {
    DWORD cbSize;
    RECT rcMonitor;
    RECT rcWork;
    DWORD dwFlags;
}

struct SIZEL {
    LONG cx;
    LONG cy;
}

struct WINDOWPLACEMENT_STUB {
    DWORD style;
    DWORD dwExtendedStyle;
    DWORD cdxStyle;
    LONG x;
    LONG y;
    LONG cx;
    LONG cy;
}

struct DEVMODEW {
    LONG dmType;
    DWORD dmFields;
    DWORD dmPelsWidth;
    DWORD dmPelsHeight;
    DWORD dmBitsPerPel;
    DWORD dmDisplayFrequency;
}

struct OSVERSIONINFOW {
    DWORD dwOSVersionInfoSize;
    DWORD dwMajorVersion;
    DWORD dwMinorVersion;
    DWORD dwBuildNumber;
    DWORD dwPlatformId;
}

struct RAWINPUTHEADER {
    DWORD dwType;
    DWORD dwSize;
    HANDLE hDevice;
    WPARAM wParam;
}

struct RAWINPUTDEVICE {
    USHORT usUsagePage;
    USHORT usUsage;
    DWORD dwFlags;
    HWND hwndTarget;
}

struct RAWMOUSE {
    USHORT usFlags;
    ULONG _pad_buttons;
    ULONG ulRawButtons;
    LONG lLastX;
    LONG lLastY;
    ULONG ulExtraInformation;
}

struct RAWINPUT {
    RAWINPUTHEADER header;
    struct {
        RAWMOUSE mouse;
    } data;
}

struct SYSTEM_INFO {
    DWORD dwOemId;
    DWORD dwPageSize;
    LPVOID lpMinimumApplicationAddress;
    LPVOID lpMaximumApplicationAddress;
    DWORD_PTR dwActiveProcessorMask;
    DWORD dwNumberOfProcessors;
    DWORD dwProcessorType;
    DWORD dwAllocationGranularity;
    WORD wProcessorLevel;
    WORD wProcessorRevision;
}

struct CRITICAL_SECTION {
    PVOID DebugInfo;
    LONG LockCount;
    LONG RecursionCount;
    HANDLE OwningThread;
    HANDLE LockSemaphore;
    ULONG_PTR SpinCount;
}

struct BITMAPV5HEADER {
    DWORD bV5Size;
    LONG bV5Width;
    LONG bV5Height;
    WORD bV5Planes;
    WORD bV5BitCount;
    DWORD bV5Compression;
    DWORD bV5SizeImage;
    LONG bV5XPelsPerMeter;
    LONG bV5YPelsPerMeter;
    DWORD bV5ClrUsed;
    DWORD bV5ClrImportant;
    DWORD bV5RedMask;
    DWORD bV5GreenMask;
    DWORD bV5BlueMask;
    DWORD bV5AlphaMask;
}

struct BITMAPINFO {
    DWORD _unused;
}

struct ICONINFO {
    BOOL fIcon;
    DWORD xHotspot;
    DWORD yHotspot;
    HBITMAP hbmMask;
    HBITMAP hbmColor;
}

struct GUID {
    u32 Data1;
    u16 Data2;
    u16 Data3;
    u8[8] Data4;
}

packed struct WAVEFORMATEX {
    WORD wFormatTag;
    WORD nChannels;
    DWORD nSamplesPerSec;
    DWORD nAvgBytesPerSec;
    WORD nBlockAlign;
    WORD wBitsPerSample;
    WORD cbSize;
}

struct WAVEFORMATEXTENSIBLE_Samples {
    WORD wValidBitsPerSample;
}

struct WAVEFORMATEXTENSIBLE {
    WAVEFORMATEX Format;
    WAVEFORMATEXTENSIBLE_Samples Samples;
    DWORD dwChannelMask;
    GUID SubFormat;
}

struct IMMDeviceEnumeratorVtbl {
    void* _pad0;
    fn(void*): u32 AddRef;
    fn(void*): u32 Release;
    void* _pad3;
    fn(void*, i32, i32, void**): i32 GetDefaultAudioEndpoint;
}

struct IMMDeviceEnumerator {
    IMMDeviceEnumeratorVtbl* lpVtbl;
}

struct IMMDeviceVtbl {
    void* _pad0;
    fn(void*): u32 AddRef;
    fn(void*): u32 Release;
    fn(void*, REFIID, u32, void*, void**): i32 Activate;
}

struct IMMDevice {
    IMMDeviceVtbl* lpVtbl;
}

struct IAudioClientVtbl {
    void* _pad0;
    fn(void*): u32 AddRef;
    fn(void*): u32 Release;
    fn(void*, i32, u32, REFERENCE_TIME, REFERENCE_TIME, WAVEFORMATEX*, GUID*): i32 Initialize;
    fn(void*, UINT32*): i32 GetBufferSize;
    void* _pad5;
    fn(void*, UINT32*): i32 GetCurrentPadding;
    void* _pad7;
    void* _pad8;
    void* _pad9;
    fn(void*): i32 Start;
    fn(void*): i32 Stop;
    void* _pad12;
    fn(void*, HANDLE): i32 SetEventHandle;
    fn(void*, REFIID, void**): i32 GetService;
}

struct IAudioClient {
    IAudioClientVtbl* lpVtbl;
}

struct IAudioRenderClientVtbl {
    void* _pad0;
    fn(void*): u32 AddRef;
    fn(void*): u32 Release;
    fn(void*, UINT32, BYTE**): i32 GetBuffer;
    fn(void*, UINT32, u32): i32 ReleaseBuffer;
}

struct IAudioRenderClient {
    IAudioRenderClientVtbl* lpVtbl;
}






/* fix for Visual Studio 2015 SDKs */
// ███████ ████████ ██████  ██    ██  ██████ ████████ ███████
// ██         ██    ██   ██ ██    ██ ██         ██    ██
// ███████    ██    ██████  ██    ██ ██         ██    ███████
//      ██    ██    ██   ██ ██    ██ ██         ██         ██
// ███████    ██    ██   ██  ██████   ██████    ██    ███████
//
// >>structs
struct _saudio_mutex_t {
    CRITICAL_SECTION critsec;
}

struct _saudio_wasapi_thread_data_t {
    HANDLE thread_handle;
    HANDLE buffer_end_event;
    bool stop;
    UINT32 dst_buffer_frames;
    i32 src_buffer_frames;
    i32 src_buffer_byte_size;
    i32 src_buffer_pos;
    f32* src_buffer;
}

struct _saudio_wasapi_backend_t {
    IMMDeviceEnumerator* device_enumerator;
    IMMDevice* device;
    IAudioClient* audio_client;
    IAudioRenderClient* render_client;
    _saudio_wasapi_thread_data_t thread;
}




// platform detection defines
// platform-specific headers and definitions
private {
IID _saudio_IID_IAudioClient = IID{
    0x1cb9ad4c,
    0xdbfa,
    0x4c32,
    {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2},
};
IID _saudio_IID_IMMDeviceEnumerator = IID{
    0xa95664d2,
    0x9614,
    0x4f35,
    {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6},
};
CLSID _saudio_CLSID_IMMDeviceEnumerator = CLSID{
    0xbcde0395,
    0xe52f,
    0x467c,
    {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e},
};
IID _saudio_IID_IAudioRenderClient = IID{
    0xf294acfc,
    0x3146,
    0x4483,
    {0xa7, 0xbf, 0xad, 0xdc, 0xa7, 0xc2, 0x60, 0xe2},
};
IID _saudio_IID_Devinterface_Audio_Render = IID{
    0xe6327cad,
    0xdcec,
    0x4949,
    {0xae, 0x8a, 0x99, 0x1e, 0x97, 0x6a, 0x79, 0xd2},
};
IID _saudio_IID_IActivateAudioInterface_Completion_Handler = IID{
    0x94ea2b94,
    0xe9cc,
    0x49e0,
    {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90},
};
GUID _saudio_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = GUID{
    0x00000003,
    0x0000,
    0x0010,
    {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71},
};


}

private {





// ███    ███ ██    ██ ████████ ███████ ██   ██
// ████  ████ ██    ██    ██    ██       ██ ██
// ██ ████ ██ ██    ██    ██    █████     ███
// ██  ██  ██ ██    ██    ██    ██       ██ ██
// ██      ██  ██████     ██    ███████ ██   ██
//
// >>mutex
void _saudio_mutex_init(_saudio_mutex_t* m) {
    InitializeCriticalSection(&m.critsec);
}

void _saudio_mutex_destroy(_saudio_mutex_t* m) {
    DeleteCriticalSection(&m.critsec);
}

void _saudio_mutex_lock(_saudio_mutex_t* m) {
    EnterCriticalSection(&m.critsec);
}

void _saudio_mutex_unlock(_saudio_mutex_t* m) {
    LeaveCriticalSection(&m.critsec);
}















/* fill intermediate buffer with new data and reset buffer_pos */
void _saudio_wasapi_fill_buffer() {
    if _saudio_has_callback() != 0 {
        _saudio_stream_callback(_saudio.backend.thread.src_buffer, _saudio.backend.thread.src_buffer_frames, _saudio.num_channels);
    } else {
        if 0 == _saudio_fifo_read(&_saudio.fifo, cast(u8*, _saudio.backend.thread.src_buffer), _saudio.backend.thread.src_buffer_byte_size) {
            _saudio_clear(_saudio.backend.thread.src_buffer, cast(u64, _saudio.backend.thread.src_buffer_byte_size));
        }
    }
}

i32 _saudio_wasapi_min(i32 a, i32 b) {
    return a < b ? a : b;
}

void _saudio_wasapi_submit_buffer(i32 num_frames) {
    BYTE* wasapi_buffer = null;
    if _saudio.backend.render_client.lpVtbl.GetBuffer(_saudio.backend.render_client, cast(UINT32, num_frames), &wasapi_buffer) < 0 {
        return;
    }
    assert(cast(i64, wasapi_buffer));
    i32 num_remaining_samples = num_frames * _saudio.num_channels;
    i32 buffer_pos = _saudio.backend.thread.src_buffer_pos;
    i32 buffer_size_in_samples = _saudio.backend.thread.src_buffer_byte_size / cast(i32, sizeof(f32));
    var dst = cast(f32*, wasapi_buffer);
    f32* dst_end = dst + num_remaining_samples;
    ignore dst_end;
    f32* src = _saudio.backend.thread.src_buffer;
    while num_remaining_samples > 0 {
        if 0 == buffer_pos {
            _saudio_wasapi_fill_buffer();
        }
        i32 samples_to_copy = _saudio_wasapi_min(num_remaining_samples, buffer_size_in_samples - buffer_pos);
        assert(buffer_pos + samples_to_copy <= buffer_size_in_samples);
        assert(dst + samples_to_copy <= dst_end);
        memcpy(dst, &src[buffer_pos], cast(u64, samples_to_copy) * cast(u64, sizeof(f32)));
        num_remaining_samples -= samples_to_copy;
        assert(num_remaining_samples >= 0);
        buffer_pos += samples_to_copy;
        dst += samples_to_copy;
        assert(buffer_pos <= buffer_size_in_samples);
        if buffer_pos == buffer_size_in_samples {
            buffer_pos = 0;
        }
    }
    _saudio.backend.thread.src_buffer_pos = buffer_pos;
    _saudio.backend.render_client.lpVtbl.ReleaseBuffer(_saudio.backend.render_client, cast(UINT32, num_frames), 0);
}

DWORD _saudio_wasapi_thread_fn(LPVOID param) {
    ignore param;
    _saudio_wasapi_submit_buffer(_saudio.backend.thread.src_buffer_frames);
    _saudio.backend.audio_client.lpVtbl.Start(_saudio.backend.audio_client);
    while _saudio.backend.thread.stop == 0 {
        WaitForSingleObject(_saudio.backend.thread.buffer_end_event, INFINITE);
        UINT32 padding = 0;
        if _saudio.backend.audio_client.lpVtbl.GetCurrentPadding(_saudio.backend.audio_client, &padding) < 0 {
            continue;
        }
        assert(_saudio.backend.thread.dst_buffer_frames >= padding);
        i32 num_frames = cast(i32, _saudio.backend.thread.dst_buffer_frames) - cast(i32, padding);
        if num_frames > 0 {
            _saudio_wasapi_submit_buffer(num_frames);
        }
    }
    return 0;
}

void _saudio_wasapi_release() {
    if _saudio.backend.thread.src_buffer != null {
        _saudio_free(_saudio.backend.thread.src_buffer);
        _saudio.backend.thread.src_buffer = null;
    }
    if _saudio.backend.render_client != null {
        _saudio.backend.render_client.lpVtbl.Release(_saudio.backend.render_client);
        _saudio.backend.render_client = null;
    }
    if _saudio.backend.audio_client != null {
        _saudio.backend.audio_client.lpVtbl.Release(_saudio.backend.audio_client);
        _saudio.backend.audio_client = null;
    }
    if _saudio.backend.device != null {
        _saudio.backend.device.lpVtbl.Release(_saudio.backend.device);
        _saudio.backend.device = null;
    }
    if _saudio.backend.device_enumerator != null {
        _saudio.backend.device_enumerator.lpVtbl.Release(_saudio.backend.device_enumerator);
        _saudio.backend.device_enumerator = null;
    }
    if null != _saudio.backend.thread.buffer_end_event {
        CloseHandle(_saudio.backend.thread.buffer_end_event);
        _saudio.backend.thread.buffer_end_event = null;
    }
}

bool _saudio_wasapi_backend_init() {
    REFERENCE_TIME dur;
    HRESULT hr;
    if _saudio.desc.win32.skip_coinitialize == 0 {
        hr = CoInitializeEx(null, COINIT_MULTITHREADED);
        ignore hr;
    }
    _saudio.backend.thread.buffer_end_event = CreateEvent(null, FALSE, FALSE, null);
    if null == _saudio.backend.thread.buffer_end_event {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_CREATE_EVENT_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if CoCreateInstance(&_saudio_CLSID_IMMDeviceEnumerator, null, CLSCTX_ALL, &_saudio_IID_IMMDeviceEnumerator, cast(void**, &_saudio.backend.device_enumerator)) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_CREATE_DEVICE_ENUMERATOR_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if _saudio.backend.device_enumerator.lpVtbl.GetDefaultAudioEndpoint(_saudio.backend.device_enumerator, eRender, eConsole, cast(void**, &_saudio.backend.device)) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_GET_DEFAULT_AUDIO_ENDPOINT_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if _saudio.backend.device.lpVtbl.Activate(_saudio.backend.device, &_saudio_IID_IAudioClient, CLSCTX_ALL, null, cast(void**, &_saudio.backend.audio_client)) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_DEVICE_ACTIVATE_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    noinit WAVEFORMATEXTENSIBLE fmtex;
    _saudio_clear(&fmtex, cast(u64, sizeof(fmtex)));
    fmtex.Format.nChannels = cast(WORD, _saudio.num_channels);
    fmtex.Format.nSamplesPerSec = cast(DWORD, _saudio.sample_rate);
    fmtex.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    fmtex.Format.wBitsPerSample = 32;
    fmtex.Format.nBlockAlign = cast(WORD, fmtex.Format.nChannels * fmtex.Format.wBitsPerSample / 8);
    fmtex.Format.nAvgBytesPerSec = fmtex.Format.nSamplesPerSec * fmtex.Format.nBlockAlign;
    fmtex.Format.cbSize = 22;
    fmtex.Samples.wValidBitsPerSample = 32;
    if _saudio.num_channels == 1 {
        fmtex.dwChannelMask = SPEAKER_FRONT_CENTER;
    } else {
        fmtex.dwChannelMask = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
    }
    fmtex.SubFormat = _saudio_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    dur = cast(REFERENCE_TIME, cast(f64, _saudio.buffer_frames) / (cast(f64, _saudio.sample_rate) * (1.0 / 10000000.0)));
    if _saudio.backend.audio_client.lpVtbl.Initialize(_saudio.backend.audio_client, AUDCLNT_SHAREMODE_SHARED, cast(u32, AUDCLNT_STREAMFLAGS_EVENTCALLBACK | 0x80000000 | 0x08000000), dur, 0, cast(WAVEFORMATEX*, &fmtex), null) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_INITIALIZE_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if _saudio.backend.audio_client.lpVtbl.GetBufferSize(_saudio.backend.audio_client, &_saudio.backend.thread.dst_buffer_frames) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_BUFFER_SIZE_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if _saudio.backend.audio_client.lpVtbl.GetService(_saudio.backend.audio_client, &_saudio_IID_IAudioRenderClient, cast(void**, &_saudio.backend.render_client)) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_SERVICE_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    if _saudio.backend.audio_client.lpVtbl.SetEventHandle(_saudio.backend.audio_client, _saudio.backend.thread.buffer_end_event) < 0 {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_SET_EVENT_HANDLE_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    _saudio.bytes_per_frame = _saudio.num_channels * cast(i32, sizeof(f32));
    _saudio.backend.thread.src_buffer_frames = _saudio.buffer_frames;
    _saudio.backend.thread.src_buffer_byte_size = _saudio.backend.thread.src_buffer_frames * _saudio.bytes_per_frame;
    _saudio.backend.thread.src_buffer = cast(f32*, _saudio_malloc(cast(u64, _saudio.backend.thread.src_buffer_byte_size)));
    _saudio.backend.thread.thread_handle = CreateThread(null, 0, cast(fn(void*): u32, _saudio_wasapi_thread_fn), null, 0, null);
    if null == _saudio.backend.thread.thread_handle {
        _saudio_log(SAUDIO_LOGITEM_WASAPI_CREATE_THREAD_FAILED, 1, __line__);
        {
            _saudio_wasapi_release();
            return false;
        }
    }
    return true;
}

void _saudio_wasapi_backend_shutdown() {
    if _saudio.backend.thread.thread_handle != null {
        _saudio.backend.thread.stop = true;
        SetEvent(_saudio.backend.thread.buffer_end_event);
        WaitForSingleObject(_saudio.backend.thread.thread_handle, INFINITE);
        CloseHandle(_saudio.backend.thread.thread_handle);
        _saudio.backend.thread.thread_handle = null;
    }
    if _saudio.backend.audio_client != null {
        _saudio.backend.audio_client.lpVtbl.Stop(_saudio.backend.audio_client);
    }
    _saudio_wasapi_release();
    if _saudio.desc.win32.skip_coinitialize == 0 {
        CoUninitialize();
    }
}
}

// ██     ██ ███████ ██████   █████  ██    ██ ██████  ██  ██████
// ██     ██ ██      ██   ██ ██   ██ ██    ██ ██   ██ ██ ██    ██
// ██  █  ██ █████   ██████  ███████ ██    ██ ██   ██ ██ ██    ██
// ██ ███ ██ ██      ██   ██ ██   ██ ██    ██ ██   ██ ██ ██    ██
//  ███ ███  ███████ ██████  ██   ██  ██████  ██████  ██  ██████
//
// >>webaudio
bool _saudio_backend_init() {
    return _saudio_wasapi_backend_init();
}

void _saudio_backend_shutdown() {
    _saudio_wasapi_backend_shutdown();
}












}

when os(macos) || os(ios) {


type UInt32 = u32;
type SInt32 = i32;
type Float64 = f64;
type OSStatus = SInt32;
type AudioQueueBufferRef = AudioQueueBuffer*;
type AudioQueueRef = void*;
private { type AudioTimeStamp = void; }
type _saudio_backend_t = _saudio_apple_backend_t;
struct AudioStreamBasicDescription {
    Float64 mSampleRate;
    UInt32 mFormatID;
    UInt32 mFormatFlags;
    UInt32 mBytesPerPacket;
    UInt32 mFramesPerPacket;
    UInt32 mBytesPerFrame;
    UInt32 mChannelsPerFrame;
    UInt32 mBitsPerChannel;
    UInt32 mReserved;
}

struct AudioQueueBuffer {
    UInt32 mAudioDataBytesCapacity;
    void* mAudioData;
    UInt32 mAudioDataByteSize;
    void* mUserData;
    UInt32 mPacketDescriptionCapacity;
    void* mPacketDescriptions;
    UInt32 mPacketDescriptionCount;
}

struct pthread_mutex_t {
    i64 __sig;
    u8[56] __opaque;
}

struct pthread_mutexattr_t {
    i64 __sig;
    u8[8] __opaque;
}







struct _saudio_apple_backend_t {
    AudioQueueRef ca_audio_queue;
}




private {


}

private {























/* NOTE: the buffer data callback is called on a separate thread! */
void _saudio_coreaudio_callback(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    ignore user_data;
    if _saudio_has_callback() != 0 {
        i32 num_frames = cast(i32, buffer.mAudioDataByteSize) / _saudio.bytes_per_frame;
        i32 num_channels = _saudio.num_channels;
        _saudio_stream_callback(cast(f32*, buffer.mAudioData), num_frames, num_channels);
    } else {
        var ptr = cast(u8*, buffer.mAudioData);
        var num_bytes = cast(i32, buffer.mAudioDataByteSize);
        if 0 == _saudio_fifo_read(&_saudio.fifo, ptr, num_bytes) {
            _saudio_clear(ptr, cast(u64, num_bytes));
        }
    }
    AudioQueueEnqueueBuffer(queue, buffer, 0, null);
}

void _saudio_coreaudio_backend_shutdown() {
    if _saudio.backend.ca_audio_queue != null {
        AudioQueueStop(_saudio.backend.ca_audio_queue, true);
        AudioQueueDispose(_saudio.backend.ca_audio_queue, false);
        _saudio.backend.ca_audio_queue = null;
    }
}

bool _saudio_coreaudio_backend_init() {
    assert(null == _saudio.backend.ca_audio_queue);
    noinit AudioStreamBasicDescription fmt;
    _saudio_clear(&fmt, cast(u64, sizeof(fmt)));
    fmt.mSampleRate = cast(f64, _saudio.sample_rate);
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = cast(u32, _saudio.num_channels);
    fmt.mBytesPerFrame = cast(u32, sizeof(f32)) * cast(u32, _saudio.num_channels);
    fmt.mBytesPerPacket = fmt.mBytesPerFrame;
    fmt.mBitsPerChannel = 32;
    OSStatus res = AudioQueueNewOutput(&fmt, _saudio_coreaudio_callback, 0, null, null, 0, &_saudio.backend.ca_audio_queue);
    if 0 != res {
        _saudio_log(SAUDIO_LOGITEM_COREAUDIO_NEW_OUTPUT_FAILED, 1, __line__);
        return false;
    }
    assert(cast(i64, _saudio.backend.ca_audio_queue));
    for i32 i = 0; i < 2; i++ {
        AudioQueueBufferRef buf = null;
        u32 buf_byte_size = cast(u32, _saudio.buffer_frames) * fmt.mBytesPerFrame;
        res = AudioQueueAllocateBuffer(_saudio.backend.ca_audio_queue, buf_byte_size, &buf);
        if 0 != res {
            _saudio_log(SAUDIO_LOGITEM_COREAUDIO_ALLOCATE_BUFFER_FAILED, 1, __line__);
            _saudio_coreaudio_backend_shutdown();
            return false;
        }
        buf.mAudioDataByteSize = buf_byte_size;
        _saudio_clear(buf.mAudioData, buf.mAudioDataByteSize);
        AudioQueueEnqueueBuffer(_saudio.backend.ca_audio_queue, buf, 0, null);
    }
    _saudio.bytes_per_frame = cast(i32, fmt.mBytesPerFrame);
    res = AudioQueueStart(_saudio.backend.ca_audio_queue, null);
    if 0 != res {
        _saudio_log(SAUDIO_LOGITEM_COREAUDIO_START_FAILED, 1, __line__);
        _saudio_coreaudio_backend_shutdown();
        return false;
    }
    return true;
}
}

// ██   ██ ██ ████████  █████
// ██   ██ ██    ██    ██   ██
// ██   ██ ██    ██    ███████
// ██   ██ ██    ██    ██   ██
//  █████  ██    ██    ██   ██
//
// >>vita
bool _saudio_backend_init() {
    return _saudio_coreaudio_backend_init();
}

void _saudio_backend_shutdown() {
    _saudio_coreaudio_backend_shutdown();
}












}

when os(android) {


type AAudioStreamBuilder = void;
type AAudioStream = void;
type aaudio_result_t = i32;
type aaudio_format_t = i32;
type aaudio_data_callback_result_t = i32;
type pthread_t = i64;
type _saudio_backend_t = _saudio_aaudio_backend_t;
struct pthread_mutex_t {
    i64[5] _o;
}

struct pthread_mutexattr_t {
    i32 __opaque;
}







struct _saudio_aaudio_backend_t {
    AAudioStreamBuilder* builder;
    AAudioStream* stream;
    void* thread;
    pthread_mutex_t mutex;
}




private {


}

private {























// ██████  ██    ██ ███    ███ ███    ███ ██    ██
// ██   ██ ██    ██ ████  ████ ████  ████  ██  ██
// ██   ██ ██    ██ ██ ████ ██ ██ ████ ██   ████
// ██   ██ ██    ██ ██  ██  ██ ██  ██  ██    ██
// ██████   ██████  ██      ██ ██      ██    ██
//
// >>dummy
aaudio_data_callback_result_t _saudio_aaudio_data_callback(AAudioStream* stream, void* user_data, void* audio_data, i32 num_frames) {
    ignore user_data;
    ignore stream;
    if _saudio_has_callback() != 0 {
        _saudio_stream_callback(cast(f32*, audio_data), num_frames, _saudio.num_channels);
    } else {
        var ptr = cast(u8*, audio_data);
        i32 num_bytes = _saudio.bytes_per_frame * num_frames;
        if 0 == _saudio_fifo_read(&_saudio.fifo, ptr, num_bytes) {
            memset(ptr, 0, cast(u64, num_bytes));
        }
    }
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

bool _saudio_aaudio_start_stream() {
    if AAudioStreamBuilder_openStream(_saudio.backend.builder, &_saudio.backend.stream) != AAUDIO_OK {
        _saudio_log(SAUDIO_LOGITEM_AAUDIO_STREAMBUILDER_OPEN_STREAM_FAILED, 1, __line__);
        return false;
    }
    AAudioStream_requestStart(_saudio.backend.stream);
    return true;
}

void _saudio_aaudio_stop_stream() {
    if _saudio.backend.stream != null {
        AAudioStream_requestStop(_saudio.backend.stream);
        AAudioStream_close(_saudio.backend.stream);
        _saudio.backend.stream = null;
    }
}

void* _saudio_aaudio_restart_stream_thread_fn(void* param) {
    ignore param;
    _saudio_log(SAUDIO_LOGITEM_AAUDIO_RESTARTING_STREAM_AFTER_ERROR, 2, __line__);
    pthread_mutex_lock(&_saudio.backend.mutex);
    _saudio_aaudio_stop_stream();
    _saudio_aaudio_start_stream();
    pthread_mutex_unlock(&_saudio.backend.mutex);
    return null;
}

void _saudio_aaudio_error_callback(AAudioStream* stream, void* user_data, aaudio_result_t error) {
    ignore stream;
    ignore user_data;
    if error == AAUDIO_ERROR_DISCONNECTED {
        if 0 != pthread_create(&_saudio.backend.thread, null, _saudio_aaudio_restart_stream_thread_fn, null) {
            _saudio_log(SAUDIO_LOGITEM_AAUDIO_PTHREAD_CREATE_FAILED, 1, __line__);
        }
    }
}

void _saudio_aaudio_backend_shutdown() {
    pthread_mutex_lock(&_saudio.backend.mutex);
    _saudio_aaudio_stop_stream();
    pthread_mutex_unlock(&_saudio.backend.mutex);
    if _saudio.backend.builder != null {
        AAudioStreamBuilder_delete(_saudio.backend.builder);
        _saudio.backend.builder = null;
    }
    pthread_mutex_destroy(&_saudio.backend.mutex);
}

bool _saudio_aaudio_backend_init() {
    _saudio_log(SAUDIO_LOGITEM_USING_AAUDIO_BACKEND, 3, __line__);
    _saudio.bytes_per_frame = _saudio.num_channels * cast(i32, sizeof(f32));
    noinit pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutex_init(&_saudio.backend.mutex, &attr);
    if AAudio_createStreamBuilder(&_saudio.backend.builder) != AAUDIO_OK {
        _saudio_log(SAUDIO_LOGITEM_AAUDIO_CREATE_STREAMBUILDER_FAILED, 1, __line__);
        _saudio_aaudio_backend_shutdown();
        return false;
    }
    AAudioStreamBuilder_setFormat(_saudio.backend.builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setSampleRate(_saudio.backend.builder, _saudio.sample_rate);
    AAudioStreamBuilder_setChannelCount(_saudio.backend.builder, _saudio.num_channels);
    AAudioStreamBuilder_setBufferCapacityInFrames(_saudio.backend.builder, _saudio.buffer_frames * 2);
    AAudioStreamBuilder_setFramesPerDataCallback(_saudio.backend.builder, _saudio.buffer_frames);
    AAudioStreamBuilder_setDataCallback(_saudio.backend.builder, _saudio_aaudio_data_callback, 0);
    AAudioStreamBuilder_setErrorCallback(_saudio.backend.builder, _saudio_aaudio_error_callback, 0);
    if _saudio_aaudio_start_stream() == 0 {
        _saudio_aaudio_backend_shutdown();
        return false;
    }
    _saudio.sample_rate = AAudioStream_getSampleRate(_saudio.backend.stream);
    _saudio.num_channels = AAudioStream_getChannelCount(_saudio.backend.stream);
    _saudio.bytes_per_frame = _saudio.num_channels * cast(i32, sizeof(f32));
    return true;
}
}

//  ██████  ██████  ██████  ███████  █████  ██    ██ ██████  ██  ██████
// ██      ██    ██ ██   ██ ██      ██   ██ ██    ██ ██   ██ ██ ██    ██
// ██      ██    ██ ██████  █████   ███████ ██    ██ ██   ██ ██ ██    ██
// ██      ██    ██ ██   ██ ██      ██   ██ ██    ██ ██   ██ ██ ██    ██
//  ██████  ██████  ██   ██ ███████ ██   ██  ██████  ██████  ██  ██████
//
// >>coreaudio
bool _saudio_backend_init() {
    return _saudio_aaudio_backend_init();
}

void _saudio_backend_shutdown() {
    _saudio_aaudio_backend_shutdown();
}












}

when os(linux) {


type snd_pcm_uframes_t = u64;
type pthread_t = u64;
type _saudio_backend_t = _saudio_alsa_backend_t;
struct snd_pcm_t {
    i32 _opaque;
}

struct snd_pcm_hw_params_t {
    i32 _opaque;
}

struct pthread_mutex_t {
    i64 __align;
    u8[56] __opaque;
}

struct pthread_mutexattr_t {
    i64 __align;
    u8[8] __opaque;
}







struct _saudio_alsa_backend_t {
    snd_pcm_t* device;
    f32* buffer;
    i32 buffer_byte_size;
    i32 buffer_frames;
    void* thread;
    bool thread_stop;
}




private {


}

private {























/* the streaming callback runs in a separate thread */
void* _saudio_alsa_cb(void* param) {
    ignore param;
    while _saudio.backend.thread_stop == 0 {
        i32 write_res = snd_pcm_writei(_saudio.backend.device, _saudio.backend.buffer, cast(snd_pcm_uframes_t, _saudio.backend.buffer_frames));
        if write_res < 0 {
            snd_pcm_prepare(_saudio.backend.device);
        } else {
            if _saudio_has_callback() != 0 {
                _saudio_stream_callback(_saudio.backend.buffer, _saudio.backend.buffer_frames, _saudio.num_channels);
            } else {
                if 0 == _saudio_fifo_read(&_saudio.fifo, cast(u8*, _saudio.backend.buffer), _saudio.backend.buffer_byte_size) {
                    _saudio_clear(_saudio.backend.buffer, cast(u64, _saudio.backend.buffer_byte_size));
                }
            }
        }
    }
    return null;
}

bool _saudio_alsa_backend_init() {
    bool _keep = false;
    defer {
        if !_keep {
            if _saudio.backend.device != null {
                snd_pcm_close(_saudio.backend.device);
                _saudio.backend.device = null;
            }
        }
    }
    i32 dir;
    u32 rate;
    i32 rc = snd_pcm_open(&_saudio.backend.device, "default", SND_PCM_STREAM_PLAYBACK, 0);
    if rc < 0 {
        _saudio_log(SAUDIO_LOGITEM_ALSA_SND_PCM_OPEN_FAILED, 1, __line__);
        _keep = true;
        return false;
    }
    snd_pcm_hw_params_t* params = null;
    snd_pcm_hw_params_malloc(&params);
    snd_pcm_hw_params_any(_saudio.backend.device, params);
    snd_pcm_hw_params_set_access(_saudio.backend.device, params, SND_PCM_ACCESS_RW_INTERLEAVED);
    if 0 > snd_pcm_hw_params_set_format(_saudio.backend.device, params, SND_PCM_FORMAT_FLOAT_LE) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_FLOAT_SAMPLES_NOT_SUPPORTED, 1, __line__);
        return false;
    }
    if 0 > snd_pcm_hw_params_set_buffer_size(_saudio.backend.device, params, cast(snd_pcm_uframes_t, _saudio.buffer_frames)) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_REQUESTED_BUFFER_SIZE_NOT_SUPPORTED, 1, __line__);
        return false;
    }
    if 0 > snd_pcm_hw_params_set_channels(_saudio.backend.device, params, cast(u32, _saudio.num_channels)) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_REQUESTED_CHANNEL_COUNT_NOT_SUPPORTED, 1, __line__);
        return false;
    }
    rate = cast(u32, _saudio.sample_rate);
    dir = 0;
    if 0 > snd_pcm_hw_params_set_rate_near(_saudio.backend.device, params, &rate, &dir) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_SET_RATE_NEAR_FAILED, 1, __line__);
        return false;
    }
    if 0 > snd_pcm_hw_params(_saudio.backend.device, params) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_FAILED, 1, __line__);
        return false;
    }
    _saudio.sample_rate = cast(i32, rate);
    _saudio.bytes_per_frame = _saudio.num_channels * cast(i32, sizeof(f32));
    _saudio.backend.buffer_byte_size = _saudio.buffer_frames * _saudio.bytes_per_frame;
    _saudio.backend.buffer_frames = _saudio.buffer_frames;
    _saudio.backend.buffer = cast(f32*, _saudio_malloc_clear(cast(u64, _saudio.backend.buffer_byte_size)));
    if 0 != pthread_create(&_saudio.backend.thread, 0, _saudio_alsa_cb, 0) {
        _saudio_log(SAUDIO_LOGITEM_ALSA_PTHREAD_CREATE_FAILED, 1, __line__);
        return false;
    }
    _keep = true;
    return true;
}

void _saudio_alsa_backend_shutdown() {
    assert(cast(i64, _saudio.backend.device));
    _saudio.backend.thread_stop = true;
    pthread_join(_saudio.backend.thread, 0);
    snd_pcm_drain(_saudio.backend.device);
    snd_pcm_close(_saudio.backend.device);
    _saudio_free(_saudio.backend.buffer);
}
}

// ██     ██  █████  ███████  █████  ██████  ██
// ██     ██ ██   ██ ██      ██   ██ ██   ██ ██
// ██  █  ██ ███████ ███████ ███████ ██████  ██
// ██ ███ ██ ██   ██      ██ ██   ██ ██      ██
//  ███ ███  ██   ██ ███████ ██   ██ ██      ██
//
// >>wasapi
bool _saudio_backend_init() {
    return _saudio_alsa_backend_init();
}

void _saudio_backend_shutdown() {
    _saudio_alsa_backend_shutdown();
}












}

when os(wasm) {
/*
    saudio_log_item

    Log items are defined via X-Macros, and expanded to an
    enum 'saudio_log_item', and in debug mode only,
    corresponding strings.

    Used as parameter in the logging callback.
*/
enum saudio_log_item {
    SAUDIO_LOGITEM_OK = 0,
    SAUDIO_LOGITEM_MALLOC_FAILED = 1,
    SAUDIO_LOGITEM_ALSA_SND_PCM_OPEN_FAILED = 2,
    SAUDIO_LOGITEM_ALSA_FLOAT_SAMPLES_NOT_SUPPORTED = 3,
    SAUDIO_LOGITEM_ALSA_REQUESTED_BUFFER_SIZE_NOT_SUPPORTED = 4,
    SAUDIO_LOGITEM_ALSA_REQUESTED_CHANNEL_COUNT_NOT_SUPPORTED = 5,
    SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_SET_RATE_NEAR_FAILED = 6,
    SAUDIO_LOGITEM_ALSA_SND_PCM_HW_PARAMS_FAILED = 7,
    SAUDIO_LOGITEM_ALSA_PTHREAD_CREATE_FAILED = 8,
    SAUDIO_LOGITEM_WASAPI_CREATE_EVENT_FAILED = 9,
    SAUDIO_LOGITEM_WASAPI_CREATE_DEVICE_ENUMERATOR_FAILED = 10,
    SAUDIO_LOGITEM_WASAPI_GET_DEFAULT_AUDIO_ENDPOINT_FAILED = 11,
    SAUDIO_LOGITEM_WASAPI_DEVICE_ACTIVATE_FAILED = 12,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_INITIALIZE_FAILED = 13,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_BUFFER_SIZE_FAILED = 14,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_GET_SERVICE_FAILED = 15,
    SAUDIO_LOGITEM_WASAPI_AUDIO_CLIENT_SET_EVENT_HANDLE_FAILED = 16,
    SAUDIO_LOGITEM_WASAPI_CREATE_THREAD_FAILED = 17,
    SAUDIO_LOGITEM_AAUDIO_STREAMBUILDER_OPEN_STREAM_FAILED = 18,
    SAUDIO_LOGITEM_AAUDIO_PTHREAD_CREATE_FAILED = 19,
    SAUDIO_LOGITEM_AAUDIO_RESTARTING_STREAM_AFTER_ERROR = 20,
    SAUDIO_LOGITEM_USING_AAUDIO_BACKEND = 21,
    SAUDIO_LOGITEM_AAUDIO_CREATE_STREAMBUILDER_FAILED = 22,
    SAUDIO_LOGITEM_COREAUDIO_NEW_OUTPUT_FAILED = 23,
    SAUDIO_LOGITEM_COREAUDIO_ALLOCATE_BUFFER_FAILED = 24,
    SAUDIO_LOGITEM_COREAUDIO_START_FAILED = 25,
    SAUDIO_LOGITEM_BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE = 26,
    SAUDIO_LOGITEM_VITA_SCEAUDIO_OPEN_FAILED = 27,
    SAUDIO_LOGITEM_VITA_PTHREAD_CREATE_FAILED = 28,
    SAUDIO_LOGITEM_N3DS_NDSP_OPEN_FAILED = 29,
}

enum saudio_n3ds_ndspinterptype {
    SAUDIO_N3DS_DSP_INTERP_POLYPHASE = 0,
    SAUDIO_N3DS_DSP_INTERP_LINEAR = 1,
    SAUDIO_N3DS_DSP_INTERP_NONE = 2,
}

type _saudio_backend_t = _saudio_web_backend_t;
/*
    saudio_logger

    Used in saudio_desc to provide a custom logging and error reporting
    callback to sokol-audio.
*/
struct saudio_logger {
    fn(u8*, u32, u32, u8*, u32, u8*, void*): void func;
    void* user_data;
}

/*
    saudio_allocator

    Used in saudio_desc to provide custom memory-alloc and -free functions
    to sokol_audio.h. If memory management should be overridden, both the
    alloc_fn and free_fn function must be provided (e.g. it's not valid to
    override one function but not the other).
*/
struct saudio_allocator {
    fn(u64, void*): void* alloc_fn;
    fn(void*, void*): void free_fn;
    void* user_data;
}

struct saudio_n3ds_desc {
    i32 queue_count;
    saudio_n3ds_ndspinterptype interpolation_type;
    i32 channel_id;
}

struct saudio_win32_desc {
    bool skip_coinitialize;
}

struct saudio_desc {
    i32 sample_rate;
    i32 num_channels;
    i32 buffer_frames;
    i32 packet_frames;
    i32 num_packets;
    fn(f32*, i32, i32): void stream_cb;
    fn(f32*, i32, i32, void*): void stream_userdata_cb;
    void* user_data;
    saudio_win32_desc win32;
    saudio_n3ds_desc n3ds;
    saudio_allocator allocator;
    saudio_logger logger;
}

// platform detection defines
// platform-specific headers and definitions
// ███████ ████████ ██████  ██    ██  ██████ ████████ ███████
// ██         ██    ██   ██ ██    ██ ██         ██    ██
// ███████    ██    ██████  ██    ██ ██         ██    ███████
//      ██    ██    ██   ██ ██    ██ ██         ██         ██
// ███████    ██    ██   ██  ██████   ██████    ██    ███████
//
// >>structs
struct _saudio_mutex_t {
    i32 dummy_mutex;
}

struct _saudio_web_backend_t {
    u8* buffer;
}

/* a ringbuffer structure */
struct _saudio_ring_t {
    i32 head;
    i32 tail;
    i32 num;
    i32[1024] queue;
}

/* a packet FIFO structure */
struct _saudio_fifo_t {
    bool valid;
    i32 packet_size;
    i32 num_packets;
    u8* base_ptr;
    i32 cur_packet;
    i32 cur_offset;
    _saudio_mutex_t mutex;
    _saudio_ring_t read_queue;
    _saudio_ring_t write_queue;
}

/* sokol-audio state */
struct _saudio_state_t {
    bool valid;
    bool setup_called;
    fn(f32*, i32, i32): void stream_cb;
    fn(f32*, i32, i32, void*): void stream_userdata_cb;
    void* user_data;
    i32 sample_rate;
    i32 buffer_frames;
    i32 bytes_per_frame;
    i32 packet_frames;
    i32 num_packets;
    i32 num_channels;
    saudio_desc desc;
    _saudio_fifo_t fifo;
    _saudio_backend_t backend;
}

/*
    sokol_audio.h -- cross-platform audio-streaming API

    Project URL: https://github.com/floooh/sokol

    Do this:
        #define SOKOL_IMPL or
        #define SOKOL_AUDIO_IMPL
    before you include this file in *one* C or C++ file to create the
    implementation.

    Optionally provide the following defines with your own implementations:

    SOKOL_DUMMY_BACKEND - use a dummy backend
    SOKOL_ASSERT(c)     - your own assert macro (default: assert(c))
    SOKOL_AUDIO_API_DECL- public function declaration prefix (default: extern)
    SOKOL_API_DECL      - same as SOKOL_AUDIO_API_DECL
    SOKOL_API_IMPL      - public function implementation prefix (default: -)

    SAUDIO_RING_MAX_SLOTS           - max number of slots in the push-audio ring buffer (default 1024)

    If sokol_audio.h is compiled as a DLL, define the following before
    including the declaration or implementation:

    SOKOL_DLL

    On Windows, SOKOL_DLL will define SOKOL_AUDIO_API_DECL as __declspec(dllexport)
    or __declspec(dllimport) as needed.

    Link with the following libraries:

    - on macOS: AudioToolbox
    - on iOS: AudioToolbox, AVFoundation
    - on FreeBSD: asound
    - on Linux: asound
    - on Android: aaudio
    - on Windows with MSVC or Clang toolchain: no action needed, libs are defined in-source via pragma-comment-lib
    - on Windows with MINGW/MSYS2 gcc: compile with '-mwin32' and link with -lole32
    - on Vita: SceAudio
    - on 3DS: NDSP (libctru)

    FEATURE OVERVIEW
    ================
    You provide a mono- or stereo-stream of 32-bit float samples, which
    Sokol Audio feeds into platform-specific audio backends:

    - Windows: WASAPI
    - Linux: ALSA
    - FreeBSD: ALSA
    - macOS: CoreAudio
    - iOS: CoreAudio+AVAudioSession
    - emscripten: WebAudio with ScriptProcessorNode
    - Android: AAudio
    - Vita: SceAudio
    - 3DS: NDSP (libctru)

    Sokol Audio will not do any buffer mixing or volume control, if you have
    multiple independent input streams of sample data you need to perform the
    mixing yourself before forwarding the data to Sokol Audio.

    There are two mutually exclusive ways to provide the sample data:

    1. Callback model: You provide a callback function, which will be called
       when Sokol Audio needs new samples. On all platforms except emscripten,
       this function is called from a separate thread.
    2. Push model: Your code pushes small blocks of sample data from your
       main loop or a thread you created. The pushed data is stored in
       a ring buffer where it is pulled by the backend code when
       needed.

    The callback model is preferred because it is the most direct way to
    feed sample data into the audio backends and also has less moving parts
    (there is no ring buffer between your code and the audio backend).

    Sometimes it is not possible to generate the audio stream directly in a
    callback function running in a separate thread, for such cases Sokol Audio
    provides the push-model as a convenience.

    SOKOL AUDIO, SOLOUD AND MINIAUDIO
    =================================
    The WASAPI, ALSA and CoreAudio backend code has been taken from the
    SoLoud library (with some modifications, so any bugs in there are most
    likely my fault). If you need a more fully-featured audio solution, check
    out SoLoud, it's excellent:

        https://github.com/jarikomppa/soloud

    Another alternative which feature-wise is somewhere inbetween SoLoud and
    sokol-audio might be MiniAudio:

        https://github.com/mackron/miniaudio

    GLOSSARY
    ========
    - stream buffer:
        The internal audio data buffer, usually provided by the backend API. The
        size of the stream buffer defines the base latency, smaller buffers have
        lower latency but may cause audio glitches. Bigger buffers reduce or
        eliminate glitches, but have a higher base latency.

    - stream callback:
        Optional callback function which is called by Sokol Audio when it
        needs new samples. On Windows, macOS/iOS and Linux, this is called in
        a separate thread, on WebAudio, this is called per-frame in the
        browser thread.

    - channel:
        A discrete track of audio data, currently 1-channel (mono) and
        2-channel (stereo) is supported and tested.

    - sample:
        The magnitude of an audio signal on one channel at a given time. In
        Sokol Audio, samples are 32-bit float numbers in the range -1.0 to
        +1.0.

    - frame:
        The tightly packed set of samples for all channels at a given time.
        For mono 1 frame is 1 sample. For stereo, 1 frame is 2 samples.

    - packet:
        In Sokol Audio, a small chunk of audio data that is moved from the
        main thread to the audio streaming thread in order to decouple the
        rate at which the main thread provides new audio data, and the
        streaming thread consuming audio data.

    WORKING WITH SOKOL AUDIO
    ========================
    First call saudio_setup() with your preferred audio playback options.
    In most cases you can stick with the default values, these provide
    a good balance between low-latency and glitch-free playback
    on all audio backends.

    You should always provide a logging callback to be aware of any
    warnings and errors. The easiest way is to use sokol_log.h for this:

        #include "sokol_log.h"
        // ...
        saudio_setup(&(saudio_desc){
            .logger = {
                .func = slog_func,
            }
        });

    If you want to use the callback-model, you need to provide a stream
    callback function either in saudio_desc.stream_cb or saudio_desc.stream_userdata_cb,
    otherwise keep both function pointers zero-initialized.

    Use push model and default playback parameters:

        saudio_setup(&(saudio_desc){ .logger.func = slog_func });

    Use stream callback model and default playback parameters:

        saudio_setup(&(saudio_desc){
            .stream_cb = my_stream_callback
            .logger.func = slog_func,
        });

    The standard stream callback doesn't have a user data argument, if you want
    that, use the alternative stream_userdata_cb and also set the user_data pointer:

        saudio_setup(&(saudio_desc){
            .stream_userdata_cb = my_stream_callback,
            .user_data = &my_data
            .logger.func = slog_func,
        });

    The following playback parameters can be provided through the
    saudio_desc struct:

    General parameters (both for stream-callback and push-model):

        int sample_rate     -- the sample rate in Hz, default: 44100
        int num_channels    -- number of channels, default: 1 (mono)
        int buffer_frames   -- number of frames in streaming buffer, default: 2048

    The stream callback prototype (either with or without userdata):

        void (*stream_cb)(float* buffer, int num_frames, int num_channels)
        void (*stream_userdata_cb)(float* buffer, int num_frames, int num_channels, void* user_data)
            Function pointer to the user-provide stream callback.

    Push-model parameters:

        int packet_frames   -- number of frames in a packet, default: 128
        int num_packets     -- number of packets in ring buffer, default: 64

    The sample_rate and num_channels parameters are only hints for the audio
    backend, it isn't guaranteed that those are the values used for actual
    playback.

    To get the actual parameters, call the following functions after
    saudio_setup():

        int saudio_sample_rate(void)
        int saudio_channels(void);

    It's unlikely that the number of channels will be different than requested,
    but a different sample rate isn't uncommon.

    (NOTE: there's an yet unsolved issue when an audio backend might switch
    to a different sample rate when switching output devices, for instance
    plugging in a bluetooth headset, this case is currently not handled in
    Sokol Audio).

    You can check if audio initialization was successful with
    saudio_isvalid(). If backend initialization failed for some reason
    (for instance when there's no audio device in the machine), this
    will return false. Not checking for success won't do any harm, all
    Sokol Audio function will silently fail when called after initialization
    has failed, so apart from missing audio output, nothing bad will happen.

    Before your application exits, you should call

        saudio_shutdown();

    This stops the audio thread (on Linux, Windows and macOS/iOS) and
    properly shuts down the audio backend.

    THE STREAM CALLBACK MODEL
    =========================
    To use Sokol Audio in stream-callback-mode, provide a callback function
    like this in the saudio_desc struct when calling saudio_setup():

    void stream_cb(float* buffer, int num_frames, int num_channels) {
        ...
    }

    Or the alternative version with a user-data argument:

    void stream_userdata_cb(float* buffer, int num_frames, int num_channels, void* user_data) {
        my_data_t* my_data = (my_data_t*) user_data;
        ...
    }

    The job of the callback function is to fill the *buffer* with 32-bit
    float sample values.

    To output silence, fill the buffer with zeros:

        void stream_cb(float* buffer, int num_frames, int num_channels) {
            const int num_samples = num_frames * num_channels;
            for (int i = 0; i < num_samples; i++) {
                buffer[i] = 0.0f;
            }
        }

    For stereo output (num_channels == 2), the samples for the left
    and right channel are interleaved:

        void stream_cb(float* buffer, int num_frames, int num_channels) {
            assert(2 == num_channels);
            for (int i = 0; i < num_frames; i++) {
                buffer[2*i + 0] = ...;  // left channel
                buffer[2*i + 1] = ...;  // right channel
            }
        }

    Please keep in mind that the stream callback function is running in a
    separate thread, if you need to share data with the main thread you need
    to take care yourself to make the access to the shared data thread-safe!

    THE PUSH MODEL
    ==============
    To use the push-model for providing audio data, simply don't set (keep
    zero-initialized) the stream_cb field in the saudio_desc struct when
    calling saudio_setup().

    To provide sample data with the push model, call the saudio_push()
    function at regular intervals (for instance once per frame). You can
    call the saudio_expect() function to ask Sokol Audio how much room is
    in the ring buffer, but if you provide a continuous stream of data
    at the right sample rate, saudio_expect() isn't required (it's a simple
    way to sync/throttle your sample generation code with the playback
    rate though).

    With saudio_push() you may need to maintain your own intermediate sample
    buffer, since pushing individual sample values isn't very efficient.
    The following example is from the MOD player sample in
    sokol-samples (https://github.com/floooh/sokol-samples):

        const int num_frames = saudio_expect();
        if (num_frames > 0) {
            const int num_samples = num_frames * saudio_channels();
            read_samples(flt_buf, num_samples);
            saudio_push(flt_buf, num_frames);
        }

    Another option is to ignore saudio_expect(), and just push samples as they
    are generated in small batches. In this case you *need* to generate the
    samples at the right sample rate:

    The following example is taken from the Tiny Emulators project
    (https://github.com/floooh/chips-test), this is for mono playback,
    so (num_samples == num_frames):

        // tick the sound generator
        if (ay38910_tick(&sys->psg)) {
            // new sample is ready
            sys->sample_buffer[sys->sample_pos++] = sys->psg.sample;
            if (sys->sample_pos == sys->num_samples) {
                // new sample packet is ready
                saudio_push(sys->sample_buffer, sys->num_samples);
                sys->sample_pos = 0;
            }
        }

    THE WEBAUDIO BACKEND
    ====================
    The WebAudio backend is currently using a ScriptProcessorNode callback to
    feed the sample data into WebAudio. ScriptProcessorNode has been
    deprecated for a while because it is running from the main thread, with
    the default initialization parameters it works 'pretty well' though.
    Ultimately Sokol Audio will use Audio Worklets, but this requires a few
    more things to fall into place (Audio Worklets implemented everywhere,
    SharedArrayBuffers enabled again, and I need to figure out a 'low-cost'
    solution in terms of implementation effort, since Audio Worklets are
    a lot more complex than ScriptProcessorNode if the audio data needs to come
    from the main thread).

    The WebAudio backend is automatically selected when compiling for
    emscripten (__EMSCRIPTEN__ define exists).

    https://developers.google.com/web/updates/2017/12/audio-worklet
    https://developers.google.com/web/updates/2018/06/audio-worklet-design-pattern

    "Blob URLs": https://www.html5rocks.com/en/tutorials/workers/basics/

    Also see: https://blog.paul.cx/post/a-wait-free-spsc-ringbuffer-for-the-web/

    THE COREAUDIO BACKEND
    =====================
    The CoreAudio backend is selected on macOS and iOS (__APPLE__ is defined).
    Since the CoreAudio API is implemented in C (not Objective-C) on macOS the
    implementation part of Sokol Audio can be included into a C source file.

    However on iOS, Sokol Audio must be compiled as Objective-C due to it's
    reliance on the AVAudioSession object. The iOS code path support both
    being compiled with or without ARC (Automatic Reference Counting).

    For thread synchronisation, the CoreAudio backend will use the
    pthread_mutex_* functions.

    The incoming floating point samples will be directly forwarded to
    CoreAudio without further conversion.

    macOS and iOS applications that use Sokol Audio need to link with
    the AudioToolbox framework.

    THE WASAPI BACKEND
    ==================
    The WASAPI backend is automatically selected when compiling on Windows
    (_WIN32 is defined).

    For thread synchronisation a Win32 critical section is used.

    By default, the WASAPI backend calls CoInitializeEx(0, COINIT_MULTITHREADED)
    in saudio_setup() and CoUninitialize() in saudio_shutdown(). This can be
    disabled with the setup option `saudio_desc.win32.skip_coinitialize`. In that
    case the library user must make sure to initialize COM before calling
    saudio_setup() (FWIW though, at least on Win11 it looks like CoInitializeEx
    isn't needed at all for sokol_audio.h, take that info with a huge grain of salt
    though).

    WASAPI may use a different size for its own streaming buffer then requested,
    so the base latency may be slightly bigger. The current backend implementation
    converts the incoming floating point sample values to signed 16-bit
    integers.

    The required Windows system DLLs are linked with #pragma comment(lib, ...),
    so you shouldn't need to add additional linker libs in the build process
    (otherwise this is a bug which should be fixed in sokol_audio.h).

    THE ALSA BACKEND
    ================
    The ALSA backend is automatically selected when compiling on Linux
    ('linux' is defined).

    For thread synchronisation, the pthread_mutex_* functions are used.

    Samples are directly forwarded to ALSA in 32-bit float format, no
    further conversion is taking place.

    You need to link with the 'asound' library, and the <alsa/asoundlib.h>
    header must be present (usually both are installed with some sort
    of ALSA development package).

    THE VITA BACKEND
    ================
    The VITA backend is automatically selected when compiling with vitasdk
    ('PSP2_SDK_VERSION' is defined).

    For thread synchronisation, the pthread_mutex_* functions are used.

    Samples are converted from float to short (uint16_t) to maintain
    all the same interface/api as other platforms.

    You may use any supported sample rate you wish, but all audio MUST
    match the same sample rate you choose.

    This uses the "BGM" port to allow selecting the sample rate ("Main"
    port is restricted to 48000 only).

    You need to link with the 'SceAudio' library, and the <psp2/audioout.h>
    header must be present (usually both are installed with the vitasdk).

    THE 3DS BACKEND
    ================
    The 3DS backend is automatically selected when compiling with libctru
    ('__3DS__' is defined).

    Running a separate thread on the older 3ds is not a good idea and I
    was not able to get it working without slowing down the main thread
    too much (it has a single core available with cooperative threads).

    The NDSP seems to work better by using its ndspSetCallback method.

    You may use any supported sample rate you wish, but all audio MUST
    match the same sample rate you choose or it will sound slowed down
    or sped up.

    The queue size and other NDSP specific parameters can be chosen by
    the provided 'saudio_n3ds_desc' type. Defaults will be used if
    nothing is provided.

    There is a known issue of a noticeable delay when starting a new
    sound on emulators. I was not able to improve this to my liking
    and ~300ms can be expected. This can be improved by using a lower
    buffer size than the 2048 default but I would not suggest under
    1536. It may crash under 1408, and they must be in multiples of 128.
    Note: I was NOT able to reproduce this issue on a real device and
    the audio worked perfectly.


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
            saudio_setup(&(saudio_desc){
                // ...
                .allocator = {
                    .alloc_fn = my_alloc,
                    .free_fn = my_free,
                    .user_data = ...,
                }
            });
        ...

    If no overrides are provided, malloc and free will be used.

    This only affects memory allocation calls done by sokol_audio.h
    itself though, not any allocations in OS libraries.

    Memory allocation will only happen on the same thread where saudio_setup()
    was called, so you don't need to worry about thread-safety.


    ERROR REPORTING AND LOGGING
    ===========================
    To get any logging information at all you need to provide a logging callback in the setup call
    the easiest way is to use sokol_log.h:

        #include "sokol_log.h"

        saudio_setup(&(saudio_desc){ .logger.func = slog_func });

    To override logging with your own callback, first write a logging function like this:

        void my_log(const char* tag,                // e.g. 'saudio'
                    uint32_t log_level,             // 0=panic, 1=error, 2=warn, 3=info
                    uint32_t log_item_id,           // SAUDIO_LOGITEM_*
                    const char* message_or_null,    // a message string, may be nullptr in release mode
                    uint32_t line_nr,               // line number in sokol_audio.h
                    const char* filename_or_null,   // source filename, may be nullptr in release mode
                    void* user_data)
        {
            ...
        }

    ...and then setup sokol-audio like this:

        saudio_setup(&(saudio_desc){
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
// ██ ███    ███ ██████  ██      ███████ ███    ███ ███████ ███    ██ ████████  █████  ████████ ██  ██████  ███    ██
// ██ ████  ████ ██   ██ ██      ██      ████  ████ ██      ████   ██    ██    ██   ██    ██    ██ ██    ██ ████   ██
// ██ ██ ████ ██ ██████  ██      █████   ██ ████ ██ █████   ██ ██  ██    ██    ███████    ██    ██ ██    ██ ██ ██  ██
// ██ ██  ██  ██ ██      ██      ██      ██  ██  ██ ██      ██  ██ ██    ██    ██   ██    ██    ██ ██    ██ ██  ██ ██
// ██ ██      ██ ██      ███████ ███████ ██      ██ ███████ ██   ████    ██    ██   ██    ██    ██  ██████  ██   ████
//
// >>implementation
when !(defined(SOKOL_DEBUG)) {
}
private {
_saudio_state_t _saudio;

bool _saudio_has_callback() {
    return _saudio.stream_cb || _saudio.stream_userdata_cb;
}

void _saudio_stream_callback(f32* buffer, i32 num_frames, i32 num_channels) {
    if _saudio.stream_cb != null {
        _saudio.stream_cb(buffer, num_frames, num_channels);
    } else if _saudio.stream_userdata_cb != null {
        _saudio.stream_userdata_cb(buffer, num_frames, num_channels, _saudio.user_data);
    }
}
// ██       ██████   ██████   ██████  ██ ███    ██  ██████
// ██      ██    ██ ██       ██       ██ ████   ██ ██
// ██      ██    ██ ██   ███ ██   ███ ██ ██ ██  ██ ██   ███
// ██      ██    ██ ██    ██ ██    ██ ██ ██  ██ ██ ██    ██
// ███████  ██████   ██████   ██████  ██ ██   ████  ██████
//
// >>logging
u8*[30] _saudio_log_messages = {
    "OK: Ok", "MALLOC_FAILED: memory allocation failed",
    "ALSA_SND_PCM_OPEN_FAILED: snd_pcm_open() failed",
    "ALSA_FLOAT_SAMPLES_NOT_SUPPORTED: floating point sample format not supported",
    "ALSA_REQUESTED_BUFFER_SIZE_NOT_SUPPORTED: requested buffer size not supported",
    "ALSA_REQUESTED_CHANNEL_COUNT_NOT_SUPPORTED: requested channel count not supported",
    "ALSA_SND_PCM_HW_PARAMS_SET_RATE_NEAR_FAILED: snd_pcm_hw_params_set_rate_near() failed",
    "ALSA_SND_PCM_HW_PARAMS_FAILED: snd_pcm_hw_params() failed",
    "ALSA_PTHREAD_CREATE_FAILED: pthread_create() failed",
    "WASAPI_CREATE_EVENT_FAILED: CreateEvent() failed",
    "WASAPI_CREATE_DEVICE_ENUMERATOR_FAILED: CoCreateInstance() for IMMDeviceEnumerator failed",
    "WASAPI_GET_DEFAULT_AUDIO_ENDPOINT_FAILED: IMMDeviceEnumerator.GetDefaultAudioEndpoint() failed",
    "WASAPI_DEVICE_ACTIVATE_FAILED: IMMDevice.Activate() failed",
    "WASAPI_AUDIO_CLIENT_INITIALIZE_FAILED: IAudioClient.Initialize() failed",
    "WASAPI_AUDIO_CLIENT_GET_BUFFER_SIZE_FAILED: IAudioClient.GetBufferSize() failed",
    "WASAPI_AUDIO_CLIENT_GET_SERVICE_FAILED: IAudioClient.GetService() failed",
    "WASAPI_AUDIO_CLIENT_SET_EVENT_HANDLE_FAILED: IAudioClient.SetEventHandle() failed",
    "WASAPI_CREATE_THREAD_FAILED: CreateThread() failed",
    "AAUDIO_STREAMBUILDER_OPEN_STREAM_FAILED: AAudioStreamBuilder_openStream() failed",
    "AAUDIO_PTHREAD_CREATE_FAILED: pthread_create() failed after AAUDIO_ERROR_DISCONNECTED",
    "AAUDIO_RESTARTING_STREAM_AFTER_ERROR: restarting AAudio stream after error",
    "USING_AAUDIO_BACKEND: using AAudio backend",
    "AAUDIO_CREATE_STREAMBUILDER_FAILED: AAudio_createStreamBuilder() failed",
    "COREAUDIO_NEW_OUTPUT_FAILED: AudioQueueNewOutput() failed",
    "COREAUDIO_ALLOCATE_BUFFER_FAILED: AudioQueueAllocateBuffer() failed",
    "COREAUDIO_START_FAILED: AudioQueueStart() failed",
    "BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE: backend buffer size isn't multiple of packet size",
    "VITA_SCEAUDIO_OPEN_FAILED: sceAudioOutOpenPort() failed",
    "VITA_PTHREAD_CREATE_FAILED: pthread_create() failed",
    "N3DS_NDSP_OPEN_FAILED: ndspInit() failed",
};

void _saudio_log(saudio_log_item log_item, u32 log_level, u32 line_nr) {
    if _saudio.desc.logger.func != null {
        u8* filename = __file__;
        u8* message = _saudio_log_messages[log_item];
        _saudio.desc.logger.func("saudio", log_level, cast(u32, log_item), message, line_nr, filename, _saudio.desc.logger.user_data);
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
void _saudio_clear(void* ptr, u64 size) {
    assert(ptr && size > 0);
    memset(ptr, 0, size);
}

void* _saudio_malloc(u64 size) {
    assert(size > 0);
    void* ptr;
    if _saudio.desc.allocator.alloc_fn != null {
        ptr = _saudio.desc.allocator.alloc_fn(size, _saudio.desc.allocator.user_data);
    } else {
        ptr = alloc(cast(i64, size));
    }
    if null == ptr {
        _saudio_log(SAUDIO_LOGITEM_MALLOC_FAILED, 0, __line__);
    }
    return ptr;
}

void* _saudio_malloc_clear(u64 size) {
    void* ptr = _saudio_malloc(size);
    _saudio_clear(ptr, size);
    return ptr;
}

void _saudio_free(void* ptr) {
    if _saudio.desc.allocator.free_fn != null {
        _saudio.desc.allocator.free_fn(ptr, _saudio.desc.allocator.user_data);
    } else {
        free(ptr);
    }
}

// ███    ███ ██    ██ ████████ ███████ ██   ██
// ████  ████ ██    ██    ██    ██       ██ ██
// ██ ████ ██ ██    ██    ██    █████     ███
// ██  ██  ██ ██    ██    ██    ██       ██ ██
// ██      ██  ██████     ██    ███████ ██   ██
//
// >>mutex
void _saudio_mutex_init(_saudio_mutex_t* m) {
    ignore m;
}

void _saudio_mutex_destroy(_saudio_mutex_t* m) {
    ignore m;
}

void _saudio_mutex_lock(_saudio_mutex_t* m) {
    ignore m;
}

void _saudio_mutex_unlock(_saudio_mutex_t* m) {
    ignore m;
}

// ██████  ██ ███    ██  ██████  ██████  ██    ██ ███████ ███████ ███████ ██████
// ██   ██ ██ ████   ██ ██       ██   ██ ██    ██ ██      ██      ██      ██   ██
// ██████  ██ ██ ██  ██ ██   ███ ██████  ██    ██ █████   █████   █████   ██████
// ██   ██ ██ ██  ██ ██ ██    ██ ██   ██ ██    ██ ██      ██      ██      ██   ██
// ██   ██ ██ ██   ████  ██████  ██████   ██████  ██      ██      ███████ ██   ██
//
// >>ringbuffer
i32 _saudio_ring_idx(_saudio_ring_t* ring, i32 i) {
    return i % ring.num;
}

void _saudio_ring_init(_saudio_ring_t* ring, i32 num_slots) {
    assert(num_slots + 1 <= 1024);
    ring.head = 0;
    ring.tail = 0;
    ring.num = num_slots + 1;
}

bool _saudio_ring_full(_saudio_ring_t* ring) {
    return _saudio_ring_idx(ring, ring.head + 1) == ring.tail;
}

bool _saudio_ring_empty(_saudio_ring_t* ring) {
    return ring.head == ring.tail;
}

i32 _saudio_ring_count(_saudio_ring_t* ring) {
    i32 count;
    if ring.head >= ring.tail {
        count = ring.head - ring.tail;
    } else {
        count = ring.head + ring.num - ring.tail;
    }
    assert(count < ring.num);
    return count;
}

void _saudio_ring_enqueue(_saudio_ring_t* ring, i32 val) {
    assert(cast(i64, !_saudio_ring_full(ring)));
    ring.queue[ring.head] = val;
    ring.head = _saudio_ring_idx(ring, ring.head + 1);
}

i32 _saudio_ring_dequeue(_saudio_ring_t* ring) {
    assert(cast(i64, !_saudio_ring_empty(ring)));
    i32 val = ring.queue[ring.tail];
    ring.tail = _saudio_ring_idx(ring, ring.tail + 1);
    return val;
}

// ███████ ██ ███████  ██████
// ██      ██ ██      ██    ██
// █████   ██ █████   ██    ██
// ██      ██ ██      ██    ██
// ██      ██ ██       ██████
//
// >>fifo
void _saudio_fifo_init_mutex(_saudio_fifo_t* fifo) {
    _saudio_mutex_init(&fifo.mutex);
}

void _saudio_fifo_destroy_mutex(_saudio_fifo_t* fifo) {
    _saudio_mutex_destroy(&fifo.mutex);
}

void _saudio_fifo_init(_saudio_fifo_t* fifo, i32 packet_size, i32 num_packets) {
    _saudio_mutex_lock(&fifo.mutex);
    assert(packet_size > 0 && num_packets > 0);
    fifo.packet_size = packet_size;
    fifo.num_packets = num_packets;
    fifo.base_ptr = cast(u8*, _saudio_malloc(cast(u64, packet_size * num_packets)));
    fifo.cur_packet = -1;
    fifo.cur_offset = 0;
    _saudio_ring_init(&fifo.read_queue, num_packets);
    _saudio_ring_init(&fifo.write_queue, num_packets);
    for i32 i = 0; i < num_packets; i++ {
        _saudio_ring_enqueue(&fifo.write_queue, i);
    }
    assert(cast(i64, _saudio_ring_full(&fifo.write_queue)));
    assert(_saudio_ring_count(&fifo.write_queue) == num_packets);
    assert(cast(i64, _saudio_ring_empty(&fifo.read_queue)));
    assert(_saudio_ring_count(&fifo.read_queue) == 0);
    fifo.valid = true;
    _saudio_mutex_unlock(&fifo.mutex);
}

void _saudio_fifo_shutdown(_saudio_fifo_t* fifo) {
    assert(cast(i64, fifo.base_ptr));
    _saudio_free(fifo.base_ptr);
    fifo.base_ptr = null;
    fifo.valid = false;
}

i32 _saudio_fifo_writable_bytes(_saudio_fifo_t* fifo) {
    _saudio_mutex_lock(&fifo.mutex);
    i32 num_bytes = _saudio_ring_count(&fifo.write_queue) * fifo.packet_size;
    if fifo.cur_packet != -1 {
        num_bytes += fifo.packet_size - fifo.cur_offset;
    }
    _saudio_mutex_unlock(&fifo.mutex);
    assert(num_bytes >= 0 && num_bytes <= fifo.num_packets * fifo.packet_size);
    return num_bytes;
}

/* write new data to the write queue, this is called from main thread */
i32 _saudio_fifo_write(_saudio_fifo_t* fifo, u8* ptr, i32 num_bytes) {
    i32 all_to_copy = num_bytes;
    while all_to_copy > 0 {
        if fifo.cur_packet == -1 {
            _saudio_mutex_lock(&fifo.mutex);
            if _saudio_ring_empty(&fifo.write_queue) == 0 {
                fifo.cur_packet = _saudio_ring_dequeue(&fifo.write_queue);
            }
            _saudio_mutex_unlock(&fifo.mutex);
            assert(fifo.cur_offset == 0);
        }
        if fifo.cur_packet != -1 {
            i32 to_copy = all_to_copy;
            i32 max_copy = fifo.packet_size - fifo.cur_offset;
            if to_copy > max_copy {
                to_copy = max_copy;
            }
            u8* dst = fifo.base_ptr + fifo.cur_packet * fifo.packet_size + fifo.cur_offset;
            memcpy(dst, ptr, cast(u64, to_copy));
            ptr += to_copy;
            fifo.cur_offset += to_copy;
            all_to_copy -= to_copy;
            assert(fifo.cur_offset <= fifo.packet_size);
            assert(all_to_copy >= 0);
        } else {
            i32 bytes_copied = num_bytes - all_to_copy;
            assert(bytes_copied >= 0 && bytes_copied < num_bytes);
            return bytes_copied;
        }
        if fifo.cur_offset == fifo.packet_size {
            _saudio_mutex_lock(&fifo.mutex);
            _saudio_ring_enqueue(&fifo.read_queue, fifo.cur_packet);
            _saudio_mutex_unlock(&fifo.mutex);
            fifo.cur_packet = -1;
            fifo.cur_offset = 0;
        }
    }
    assert(all_to_copy == 0);
    return num_bytes;
}

/* read queued data, this is called form the stream callback (maybe separate thread) */
i32 _saudio_fifo_read(_saudio_fifo_t* fifo, u8* ptr, i32 num_bytes) {
    _saudio_mutex_lock(&fifo.mutex);
    i32 num_bytes_copied = 0;
    if fifo.valid != 0 {
        assert(0 == num_bytes % fifo.packet_size);
        assert(num_bytes <= fifo.packet_size * fifo.num_packets);
        i32 num_packets_needed = num_bytes / fifo.packet_size;
        u8* dst = ptr;
        if _saudio_ring_count(&fifo.read_queue) >= num_packets_needed {
            for i32 i = 0; i < num_packets_needed; i++ {
                i32 packet_index = _saudio_ring_dequeue(&fifo.read_queue);
                _saudio_ring_enqueue(&fifo.write_queue, packet_index);
                u8* src = fifo.base_ptr + packet_index * fifo.packet_size;
                memcpy(dst, src, cast(u64, fifo.packet_size));
                dst += fifo.packet_size;
                num_bytes_copied += fifo.packet_size;
            }
            assert(num_bytes == num_bytes_copied);
        }
    }
    _saudio_mutex_unlock(&fifo.mutex);
    return num_bytes_copied;
}
}

// ██████  ██    ██ ███    ███ ███    ███ ██    ██
// ██   ██ ██    ██ ████  ████ ████  ████  ██  ██
// ██   ██ ██    ██ ██ ████ ██ ██ ████ ██   ████
// ██   ██ ██    ██ ██  ██  ██ ██  ██  ██    ██
// ██████   ██████  ██      ██ ██      ██    ██
//
// >>dummy
export i32 _saudio_emsc_pull(i32 num_frames) {
    assert(cast(i64, _saudio.backend.buffer));
    if num_frames == _saudio.buffer_frames {
        if _saudio_has_callback() != 0 {
            _saudio_stream_callback(cast(f32*, _saudio.backend.buffer), num_frames, _saudio.num_channels);
        } else {
            i32 num_bytes = num_frames * _saudio.bytes_per_frame;
            if 0 == _saudio_fifo_read(&_saudio.fifo, _saudio.backend.buffer, num_bytes) {
                // no data available: return null instead of a buffer of silence,
                // so the caller can hold off rather than let the stream drift
                return 0;
            }
        }
        var res = cast(i32, _saudio.backend.buffer);
        return res;
    } else {
        return 0;
    }
}

/* setup the WebAudio context and attach a ScriptProcessorNode */
/* shutdown the WebAudioContext and ScriptProcessorNode */
/* get the actual sample rate back from the WebAudio context */
/* get the actual buffer size in number of frames */
/* return 1 if the WebAudio context is currently suspended (or interrupted), else 0 */
private {
bool _saudio_webaudio_backend_init() {
    if saudio_js_init(_saudio.sample_rate, _saudio.num_channels, _saudio.buffer_frames) != 0 {
        _saudio.bytes_per_frame = cast(i32, sizeof(f32)) * _saudio.num_channels;
        _saudio.sample_rate = saudio_js_sample_rate();
        _saudio.buffer_frames = saudio_js_buffer_frames();
        var buf_size = cast(u64, _saudio.buffer_frames * _saudio.bytes_per_frame);
        _saudio.backend.buffer = cast(u8*, _saudio_malloc(buf_size));
        return true;
    } else {
        return false;
    }
}

void _saudio_webaudio_backend_shutdown() {
    saudio_js_shutdown();
    if _saudio.backend.buffer != null {
        _saudio_free(_saudio.backend.buffer);
        _saudio.backend.buffer = null;
    }
}
}

//  █████   █████  ██    ██ ██████  ██  ██████
// ██   ██ ██   ██ ██    ██ ██   ██ ██ ██    ██
// ███████ ███████ ██    ██ ██   ██ ██ ██    ██
// ██   ██ ██   ██ ██    ██ ██   ██ ██ ██    ██
// ██   ██ ██   ██  ██████  ██████  ██  ██████
//
// >>aaudio
bool _saudio_backend_init() {
    return _saudio_webaudio_backend_init();
}

void _saudio_backend_shutdown() {
    _saudio_webaudio_backend_shutdown();
}

// ██████  ██    ██ ██████  ██      ██  ██████
// ██   ██ ██    ██ ██   ██ ██      ██ ██
// ██████  ██    ██ ██████  ██      ██ ██
// ██      ██    ██ ██   ██ ██      ██ ██
// ██       ██████  ██████  ███████ ██  ██████
//
// >>public
void saudio_setup(saudio_desc* desc) {
    assert(cast(i64, !_saudio.valid));
    assert(cast(i64, !_saudio.setup_called));
    assert(cast(i64, desc));
    assert(desc.allocator.alloc_fn && desc.allocator.free_fn || !desc.allocator.alloc_fn && !desc.allocator.free_fn);
    _saudio_clear(&_saudio, cast(u64, sizeof(_saudio)));
    _saudio.setup_called = true;
    _saudio.desc = *desc;
    _saudio.stream_cb = desc.stream_cb;
    _saudio.stream_userdata_cb = desc.stream_userdata_cb;
    _saudio.user_data = desc.user_data;
    _saudio.sample_rate = _saudio.desc.sample_rate == 0 ? 44100 : _saudio.desc.sample_rate;
    _saudio.buffer_frames = _saudio.desc.buffer_frames == 0 ? 2048 : _saudio.desc.buffer_frames;
    _saudio.packet_frames = _saudio.desc.packet_frames == 0 ? 128 : _saudio.desc.packet_frames;
    _saudio.num_packets = _saudio.desc.num_packets == 0 ? 2048 / 128 * 4 : _saudio.desc.num_packets;
    _saudio.num_channels = _saudio.desc.num_channels == 0 ? 1 : _saudio.desc.num_channels;
    _saudio_fifo_init_mutex(&_saudio.fifo);
    if _saudio_backend_init() != 0 {
        if 0 != _saudio.buffer_frames % _saudio.packet_frames {
            _saudio_log(SAUDIO_LOGITEM_BACKEND_BUFFER_SIZE_ISNT_MULTIPLE_OF_PACKET_SIZE, 1, __line__);
            _saudio_backend_shutdown();
            return;
        }
        assert(_saudio.bytes_per_frame > 0);
        _saudio_fifo_init(&_saudio.fifo, _saudio.packet_frames * _saudio.bytes_per_frame, _saudio.num_packets);
        _saudio.valid = true;
    } else {
        _saudio_fifo_destroy_mutex(&_saudio.fifo);
    }
}

void saudio_shutdown() {
    assert(cast(i64, _saudio.setup_called));
    _saudio.setup_called = false;
    if _saudio.valid != 0 {
        _saudio_backend_shutdown();
        _saudio_fifo_shutdown(&_saudio.fifo);
        _saudio_fifo_destroy_mutex(&_saudio.fifo);
        _saudio.valid = false;
    }
}

bool saudio_isvalid() {
    return _saudio.valid;
}

void* saudio_userdata() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.desc.user_data;
}

saudio_desc saudio_query_desc() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.desc;
}

i32 saudio_sample_rate() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.sample_rate;
}

i32 saudio_buffer_frames() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.buffer_frames;
}

i32 saudio_channels() {
    assert(cast(i64, _saudio.setup_called));
    return _saudio.num_channels;
}

bool saudio_suspended() {
    assert(cast(i64, _saudio.setup_called));
    if _saudio.valid != 0 {
        return 1 == saudio_js_suspended();
    } else {
        return false;
    }
}

i32 saudio_expect() {
    assert(cast(i64, _saudio.setup_called));
    if _saudio.valid != 0 {
        i32 num_frames = _saudio_fifo_writable_bytes(&_saudio.fifo) / _saudio.bytes_per_frame;
        return num_frames;
    } else {
        return 0;
    }
}

i32 saudio_push(f32* frames, i32 num_frames) {
    assert(cast(i64, _saudio.setup_called));
    assert(frames && num_frames > 0);
    if _saudio.valid != 0 {
        i32 num_bytes = num_frames * _saudio.bytes_per_frame;
        i32 num_written = _saudio_fifo_write(&_saudio.fifo, cast(u8*, frames), num_bytes);
        return num_written / _saudio.bytes_per_frame;
    } else {
        return 0;
    }
}

// sokol_audio_wasm.mc: the hand-written backend for the sokol_audio
// wasm arm.
//
// WebAudio context lifecycle + state, implemented by sokol_wasm_host.js
// (module "saudio") over an AudioWorklet.
extern "saudio" i32  saudio_js_init(i32 sample_rate, i32 num_channels, i32 buffer_size);
extern "saudio" void saudio_js_shutdown();
extern "saudio" i32  saudio_js_sample_rate();
extern "saudio" i32  saudio_js_buffer_frames();
extern "saudio" i32  saudio_js_suspended();

}
