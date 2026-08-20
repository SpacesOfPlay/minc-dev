// AAudio (Android) entry points + constants for the transpiled
// sokol_audio Android backend.

when os(android) {

// Real NDK enum values (<aaudio/AAudio.h>)
const i32 AAUDIO_OK                       = 0;     // aaudio_result_t
const i32 AAUDIO_ERROR_DISCONNECTED       = -899;  // AAUDIO_ERROR_BASE(-900)+1
const i32 AAUDIO_FORMAT_PCM_FLOAT         = 2;     // aaudio_format_t
const i32 AAUDIO_CALLBACK_RESULT_CONTINUE = 0;     // aaudio_data_callback_result_t

// AAudio C API (libaaudio.so, NDK API 26+). The data callback is
//   aaudio_data_callback_result_t cb(AAudioStream*, void* user, void* data, i32 frames)
// and the error callback
//   void cb(AAudioStream*, void* user, aaudio_result_t error).
extern "libaaudio.so" {
    i32  AAudio_createStreamBuilder(AAudioStreamBuilder** out_builder);
    void AAudioStreamBuilder_setFormat(AAudioStreamBuilder* builder, aaudio_format_t format);
    void AAudioStreamBuilder_setSampleRate(AAudioStreamBuilder* builder, i32 sample_rate);
    void AAudioStreamBuilder_setChannelCount(AAudioStreamBuilder* builder, i32 channel_count);
    void AAudioStreamBuilder_setBufferCapacityInFrames(AAudioStreamBuilder* builder, i32 num_frames);
    void AAudioStreamBuilder_setFramesPerDataCallback(AAudioStreamBuilder* builder, i32 num_frames);
    // user_data is typed i64 (the body passes literal 0; 0 is ABI-identical
    // to a null pointer on arm64; minc won't coerce an int literal to void*).
    void AAudioStreamBuilder_setDataCallback(AAudioStreamBuilder* builder,
        fn(AAudioStream*, void*, void*, i32): aaudio_data_callback_result_t callback, i64 user_data);
    void AAudioStreamBuilder_setErrorCallback(AAudioStreamBuilder* builder,
        fn(AAudioStream*, void*, aaudio_result_t): void callback, i64 user_data);
    i32  AAudioStreamBuilder_openStream(AAudioStreamBuilder* builder, AAudioStream** out_stream);
    i32  AAudioStreamBuilder_delete(AAudioStreamBuilder* builder);
    i32  AAudioStream_requestStart(AAudioStream* stream);
    i32  AAudioStream_requestStop(AAudioStream* stream);
    i32  AAudioStream_close(AAudioStream* stream);
    // Read back the format AAudio actually granted (the builder values are only
    // hints); the publish syncs saudio's reported rate/channels to these.
    i32  AAudioStream_getSampleRate(AAudioStream* stream);
    i32  AAudioStream_getChannelCount(AAudioStream* stream);
}

// pthread surface the AAudio backend uses (Bionic libc.so)
extern "libc.so" {
    i32 pthread_create(void* thread, void* attr, fn(void*): void* start_routine, void* arg);
    i32 pthread_mutex_init(void* mutex, void* attr);
    i32 pthread_mutex_destroy(void* mutex);
    i32 pthread_mutex_lock(void* mutex);
    i32 pthread_mutex_unlock(void* mutex);
    i32 pthread_mutexattr_init(void* attr);
}

}
