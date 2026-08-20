// CoreAudio (AudioQueue) entry points + constants (macOS/iOS).

when os(macos) || os(ios) {

// AudioToolbox AudioQueue C API. The callback is
//   void cb(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buf)
extern "AudioToolbox" {
    // user_data is typed i64 (0 is ABI-identical to a null pointer here).
    i32 AudioQueueNewOutput(AudioStreamBasicDescription* fmt,
                            fn(void*, AudioQueueRef, AudioQueueBufferRef): void cb,
                            i64 user_data, void* run_loop, void* run_loop_mode,
                            u32 flags, AudioQueueRef* out_aq);
    i32 AudioQueueAllocateBuffer(AudioQueueRef aq, u32 byte_size, AudioQueueBufferRef* out_buf);
    i32 AudioQueueEnqueueBuffer(AudioQueueRef aq, AudioQueueBufferRef buf,
                                u32 num_packet_descs, void* packet_descs);
    i32 AudioQueueStart(AudioQueueRef aq, void* start_time);
    i32 AudioQueueStop(AudioQueueRef aq, bool immediate);
    i32 AudioQueueDispose(AudioQueueRef aq, bool immediate);
}

// CoreAudioBaseTypes format selectors / flags (the fp32 PCM setup).
const u32 kAudioFormatLinearPCM       = 1819304813;   // 'lpcm'
const u32 kLinearPCMFormatFlagIsFloat = 1;            // 1 << 0
const u32 kAudioFormatFlagIsPacked    = 8;            // 1 << 3

// pthread mutex C API (libSystem); sokol_audio's _saudio_mutex_* wrappers.
extern "libSystem.B.dylib" {
    i32 pthread_mutex_init(pthread_mutex_t* m, pthread_mutexattr_t* attr);
    i32 pthread_mutex_destroy(pthread_mutex_t* m);
    i32 pthread_mutex_lock(pthread_mutex_t* m);
    i32 pthread_mutex_unlock(pthread_mutex_t* m);
    i32 pthread_mutexattr_init(pthread_mutexattr_t* attr);
    i32 pthread_mutexattr_destroy(pthread_mutexattr_t* attr);
    i32 usleep(u32 usec);
}

}
