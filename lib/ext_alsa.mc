// ALSA (libasound) entry points + constants, pthreads (Linux).
//
// The runtime sidecar for sokol_audio's transpiled ALSA backend;
// analogous to coreaudio_consts.mc for macOS. snd_pcm_t /
// snd_pcm_hw_params_t / pthread_mutex_t are defined in the
// sokol_audio body (transpiled from alsa_types.h); this module only
// supplies the extern bindings + the snd_pcm enum selectors.

when os(linux) {

// libasound PCM playback API. The hw_params object is heap-allocated
// via snd_pcm_hw_params_malloc (the alloca macro routes here).
extern "libasound.so.2" {
    i32 snd_pcm_open(snd_pcm_t** pcm, u8* name, i32 stream, i32 mode);
    i32 snd_pcm_close(snd_pcm_t* pcm);
    i32 snd_pcm_drain(snd_pcm_t* pcm);
    i32 snd_pcm_prepare(snd_pcm_t* pcm);
    i32 snd_pcm_writei(snd_pcm_t* pcm, void* buffer, u64 frames);
    i32 snd_pcm_hw_params_malloc(snd_pcm_hw_params_t** ptr);
    i32 snd_pcm_hw_params_any(snd_pcm_t* pcm, snd_pcm_hw_params_t* params);
    i32 snd_pcm_hw_params_set_access(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, i32 access);
    i32 snd_pcm_hw_params_set_format(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, i32 format);
    i32 snd_pcm_hw_params_set_buffer_size(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, u64 val);
    i32 snd_pcm_hw_params_set_channels(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, u32 val);
    i32 snd_pcm_hw_params_set_rate_near(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, u32* val, i32* dir);
    i32 snd_pcm_hw_params(snd_pcm_t* pcm, snd_pcm_hw_params_t* params);
}

// snd_pcm enum selectors used by the backend (snd_pcm_stream_t /
// _access_t / _format_t). Values from <alsa/pcm.h>.
const i32 SND_PCM_STREAM_PLAYBACK     = 0;
const i32 SND_PCM_ACCESS_RW_INTERLEAVED = 3;
const i32 SND_PCM_FORMAT_FLOAT_LE     = 14;

// pthread C API (glibc, pthreads merged into libc). The audio thread
// must be a real libc-registered pthread because libasound (and the
// alsa-pulse plugin → libpulse it may resolve through) reads its own
// pthread TCB. snd_pcm_writei runs on this thread.
// attr / arg / retval are typed i64; sokol always passes a literal 0
// there (ABI-identical to a null pointer), and the transpiled body
// emits it as 0, not null.
extern "libc.so.6" {
    i32 pthread_create(void** thread, i64 attr, fn(void*): void* start_routine, i64 arg);
    i32 pthread_join(void* thread, i64 retval);
    i32 pthread_mutex_init(pthread_mutex_t* m, pthread_mutexattr_t* attr);
    i32 pthread_mutex_destroy(pthread_mutex_t* m);
    i32 pthread_mutex_lock(pthread_mutex_t* m);
    i32 pthread_mutex_unlock(pthread_mutex_t* m);
    i32 pthread_mutexattr_init(pthread_mutexattr_t* attr);
    i32 pthread_mutexattr_destroy(pthread_mutexattr_t* attr);
}

}
