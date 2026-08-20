// ext_android.mc; extern declarations and runtime helpers for the
// sokol Android backend.

// === EGL constants ===
// Lifted from <EGL/egl.h>. Stable values across NDK versions.
const i32 EGL_FALSE                    = 0;
const i32 EGL_TRUE                     = 1;
const i32 EGL_NONE                     = 0x3038;
const void* EGL_DEFAULT_DISPLAY        = cast(void*, 0);
const void* EGL_NO_DISPLAY             = cast(void*, 0);
const void* EGL_NO_CONTEXT             = cast(void*, 0);
const void* EGL_NO_SURFACE             = cast(void*, 0);

const i32 EGL_BUFFER_SIZE              = 0x3020;
const i32 EGL_ALPHA_SIZE               = 0x3021;
const i32 EGL_BLUE_SIZE                = 0x3022;
const i32 EGL_GREEN_SIZE               = 0x3023;
const i32 EGL_RED_SIZE                 = 0x3024;
const i32 EGL_DEPTH_SIZE               = 0x3025;
const i32 EGL_STENCIL_SIZE             = 0x3026;
const i32 EGL_CONFIG_CAVEAT            = 0x3027;
const i32 EGL_CONFIG_ID                = 0x3028;
const i32 EGL_LEVEL                    = 0x3029;
const i32 EGL_NATIVE_VISUAL_ID         = 0x302E;
const i32 EGL_NATIVE_VISUAL_TYPE       = 0x302F;
const i32 EGL_SAMPLES                  = 0x3031;
const i32 EGL_SAMPLE_BUFFERS           = 0x3032;
const i32 EGL_SURFACE_TYPE             = 0x3033;
const i32 EGL_RENDERABLE_TYPE          = 0x3040;
const i32 EGL_GL_COLORSPACE            = 0x309D;
const i32 EGL_GL_COLORSPACE_SRGB       = 0x3089;
const i32 EGL_WIDTH                    = 0x3057;
const i32 EGL_HEIGHT                   = 0x3056;

const i32 EGL_WINDOW_BIT               = 0x0004;
const i32 EGL_OPENGL_BIT               = 0x0008;
const i32 EGL_OPENGL_ES_BIT            = 0x0001;
const i32 EGL_OPENGL_ES2_BIT           = 0x0004;
const i32 EGL_OPENGL_ES3_BIT           = 0x0040;

const i32 EGL_CONTEXT_MAJOR_VERSION    = 0x3098;
const i32 EGL_CONTEXT_MINOR_VERSION    = 0x30FB;
const i32 EGL_CONTEXT_OPENGL_PROFILE_MASK = 0x30FD;
const i32 EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT = 0x00000001;

const u32 EGL_OPENGL_API               = 0x30A2;
const u32 EGL_OPENGL_ES_API            = 0x30A0;

// === ALooper constants ===
const i32 ALOOPER_PREPARE_ALLOW_NON_CALLBACKS = 1;
const i32 ALOOPER_POLL_WAKE      = -1;
const i32 ALOOPER_POLL_CALLBACK  = -2;
const i32 ALOOPER_POLL_TIMEOUT   = -3;
const i32 ALOOPER_POLL_ERROR     = -4;
const i32 ALOOPER_EVENT_INPUT    = 1;
const i32 ALOOPER_EVENT_OUTPUT   = 2;
const i32 ALOOPER_EVENT_ERROR    = 4;
const i32 ALOOPER_EVENT_HANGUP   = 8;
const i32 ALOOPER_EVENT_INVALID  = 16;

// === AMotionEvent / AKeyEvent constants ===
const i32 AMOTION_EVENT_ACTION_MASK         = 0xff;
const i32 AMOTION_EVENT_ACTION_DOWN         = 0;
const i32 AMOTION_EVENT_ACTION_UP           = 1;
const i32 AMOTION_EVENT_ACTION_MOVE         = 2;
const i32 AMOTION_EVENT_ACTION_CANCEL       = 3;
const i32 AMOTION_EVENT_ACTION_OUTSIDE      = 4;
const i32 AMOTION_EVENT_ACTION_POINTER_DOWN = 5;
const i32 AMOTION_EVENT_ACTION_POINTER_UP   = 6;
const i32 AMOTION_EVENT_ACTION_HOVER_MOVE   = 7;
const i32 AMOTION_EVENT_ACTION_SCROLL       = 8;
const i32 AMOTION_EVENT_ACTION_POINTER_INDEX_MASK  = 0xff00;
const i32 AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT = 8;

const i32 AKEYCODE_BACK = 4;

const i32 AINPUT_EVENT_TYPE_KEY     = 1;
const i32 AINPUT_EVENT_TYPE_MOTION  = 2;

// === EGL functions (libEGL) ===
extern "libEGL.so" void* eglGetDisplay(void* display_id);
extern "libEGL.so" i32   eglInitialize(void* display, i32* major, i32* minor);
extern "libEGL.so" i32   eglTerminate(void* display);
extern "libEGL.so" i32   eglBindAPI(u32 api);
extern "libEGL.so" i32   eglChooseConfig(void* display, i32* attrib_list, void* configs, i32 config_size, i32* num_config);
extern "libEGL.so" i32   eglGetConfigAttrib(void* display, void* config, i32 attribute, i32* value);
extern "libEGL.so" void* eglCreateContext(void* display, void* config, void* share_context, i32* attrib_list);
extern "libEGL.so" i32   eglDestroyContext(void* display, void* context);
extern "libEGL.so" void* eglCreateWindowSurface(void* display, void* config, ANativeWindow* window, i32* attrib_list);
extern "libEGL.so" i32   eglDestroySurface(void* display, void* surface);
extern "libEGL.so" i32   eglMakeCurrent(void* display, void* draw, void* read, void* context);
extern "libEGL.so" i32   eglSwapBuffers(void* display, void* surface);
extern "libEGL.so" i32   eglQuerySurface(void* display, void* surface, i32 attribute, i32* value);
extern "libEGL.so" i32   eglGetError();

// === native_app_glue / NDK input + window functions (libandroid) ===
extern "libandroid.so" i32 ANativeWindow_getWidth(ANativeWindow* window);
extern "libandroid.so" i32 ANativeWindow_getHeight(ANativeWindow* window);
extern "libandroid.so" i32 ANativeWindow_setBuffersGeometry(ANativeWindow* window, i32 width, i32 height, i32 format);

extern "libandroid.so" void ANativeActivity_finish(ANativeActivity* activity);
extern "libandroid.so" void ANativeActivity_showSoftInput(ANativeActivity* activity, u32 flags);
extern "libandroid.so" void ANativeActivity_hideSoftInput(ANativeActivity* activity, u32 flags);

// Soft input flags from <android/native_activity.h>
const u32 ANATIVEACTIVITY_SHOW_SOFT_INPUT_IMPLICIT  = 0x0001;
const u32 ANATIVEACTIVITY_SHOW_SOFT_INPUT_FORCED    = 0x0002;
const u32 ANATIVEACTIVITY_HIDE_SOFT_INPUT_IMPLICIT_ONLY = 0x0001;
const u32 ANATIVEACTIVITY_HIDE_SOFT_INPUT_NOT_ALWAYS    = 0x0002;

extern "libandroid.so" i32 AInputQueue_getEvent(AInputQueue* queue, AInputEvent** out_event);
extern "libandroid.so" i32 AInputQueue_preDispatchEvent(AInputQueue* queue, AInputEvent* event);
extern "libandroid.so" void AInputQueue_finishEvent(AInputQueue* queue, AInputEvent* event, i32 handled);
// AInputQueue_attachLooper(queue, looper, ident, callback_fn, data).
// `ident` is i32 in the NDK header (sokol passes ALOOPER_POLL_CALLBACK which is -2).
extern "libandroid.so" void AInputQueue_attachLooper(AInputQueue* queue, ALooper* looper, i32 ident, fn(i32, i32, void*): i32 callback, void* data);
extern "libandroid.so" void AInputQueue_detachLooper(AInputQueue* queue);

extern "libandroid.so" i32 AInputEvent_getType(AInputEvent* event);

extern "libandroid.so" i32 AMotionEvent_getAction(AInputEvent* event);
extern "libandroid.so" i64 AMotionEvent_getPointerCount(AInputEvent* event);
extern "libandroid.so" i32 AMotionEvent_getPointerId(AInputEvent* event, i64 pointer_index);
extern "libandroid.so" i32 AMotionEvent_getToolType(AInputEvent* event, i64 pointer_index);
extern "libandroid.so" f32 AMotionEvent_getX(AInputEvent* event, i64 pointer_index);
extern "libandroid.so" f32 AMotionEvent_getY(AInputEvent* event, i64 pointer_index);

extern "libandroid.so" i32 AKeyEvent_getKeyCode(AInputEvent* event);

extern "libandroid.so" ALooper* ALooper_prepare(i32 opts);
extern "libandroid.so" i32 ALooper_addFd(ALooper* looper, i32 fd, i32 ident, i32 events, fn(i32, i32, void*): i32 callback, void* data);
extern "libandroid.so" i32 ALooper_pollOnce(i32 timeout_millis, i32* out_fd, i32* out_events, void** out_data);

// === AAssetManager / AAsset (libandroid) ===
extern "libandroid.so" AAsset* AAssetManager_open(AAssetManager* mgr, u8* filename, i32 mode);
extern "libandroid.so" void AAsset_close(AAsset* asset);
extern "libandroid.so" i64 AAsset_getLength64(AAsset* asset);
extern "libandroid.so" i32 AAsset_read(AAsset* asset, void* buf, i64 count);

const i32 AASSET_MODE_BUFFER = 3;

// === Logging (liblog) ===
const i32 ANDROID_LOG_VERBOSE = 2;
const i32 ANDROID_LOG_DEBUG   = 3;
const i32 ANDROID_LOG_INFO    = 4;
const i32 ANDROID_LOG_WARN    = 5;
const i32 ANDROID_LOG_ERROR   = 6;
const i32 ANDROID_LOG_FATAL   = 7;

extern "liblog.so" i32 __android_log_write(i32 prio, u8* tag, u8* text);

// === pthread (libc); void* params mirror the Linux declarations
extern "libc.so" i32 pthread_create(void* thread, void* attr, fn(void*): void* start_routine, void* arg);
extern "libc.so" i32 pthread_join(pthread_t thread, void** retval);
extern "libc.so" i32 pthread_detach(pthread_t thread);

extern "libc.so" i32 pthread_attr_init(void* attr);
extern "libc.so" i32 pthread_attr_destroy(void* attr);
extern "libc.so" i32 pthread_attr_setdetachstate(void* attr, i32 state);

extern "libc.so" i32 pthread_mutex_init(void* mutex, void* attr);
extern "libc.so" i32 pthread_mutex_destroy(void* mutex);
extern "libc.so" i32 pthread_mutex_lock(void* mutex);
extern "libc.so" i32 pthread_mutex_unlock(void* mutex);

extern "libc.so" i32 pthread_cond_init(void* cond, void* attr);
extern "libc.so" i32 pthread_cond_destroy(void* cond);
extern "libc.so" i32 pthread_cond_wait(void* cond, void* mutex);
extern "libc.so" i32 pthread_cond_broadcast(void* cond);
extern "libc.so" i32 pthread_cond_signal(void* cond);

const i32 PTHREAD_CREATE_DETACHED = 1;

// === pipe / read / write / close (libc) ===
extern "libc.so" i32 pipe(void* fds);

// === POSIX time (libc) ===
const i32 CLOCK_MONOTONIC = 1;
extern "libc.so" i32 clock_gettime(i32 clk_id, timespec* tp);

// === dlopen / dlsym / dlclose (libdl) ===
extern "libdl.so" void* dlopen(u8* filename, i32 flags);
extern "libdl.so" void* dlsym(void* handle, u8* symbol);
extern "libdl.so" i32 dlclose(void* handle);

// === poll / stdlib helpers (libc) ===
struct pollfd {
    i32 fd;
    i16 events;
    i16 revents;
}
extern "libc.so" i32 poll(pollfd* fds, u64 nfds, i32 timeout);

// === write() -> logcat redirect (shared-library mode) ===
i64 minc_log_write(i32 fd, void* buf, i64 len) {
    if fd == 1 || fd == 2 {
        u8[1024] tmp;
        i64 n = len;
        if n > 1023 { n = 1023; }
        for i64 i = 0; i < n; i = i + 1 {
            tmp[i] = *(cast(u8*, buf) + i);
        }
        tmp[n] = 0;
        i32 prio = 4;            // ANDROID_LOG_INFO
        if fd == 2 { prio = 6; } // ANDROID_LOG_ERROR
        __android_log_write(prio, "minc", cast(u8*, &tmp));
        return len;
    }
    i32 ret = write(fd, cast(u8*, buf), cast(i32, len));
    return cast(i64, ret);
}
