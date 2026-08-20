// vec.mc - Generic dynamic array
//
// Usage:
//   Vec<i32> nums = vec_new<i32>(16);
//   vec_push(&nums, 42);
//   vec_push(&nums, 99);
//   i32 x = vec_get(&nums, 0);  // 42
//   vec_set(&nums, 0, 100);
//   vec_free(&nums);
//

struct Vec<T> {
    T* data;
    i32 len;
    i32 cap;
}

Vec<T> vec_new<T>(i32 cap) {
    Vec<T> v;
    v.data = alloc<T>(cap);
    v.len = 0;
    v.cap = cap;
    return v;
}

void vec_init<T>(Vec<T>* v, i32 cap) {
    v.data = alloc<T>(cap);
    v.len = 0;
    v.cap = cap;
    return;
}

void vec_push<T>(Vec<T>* v, T val) {
    if v.len >= v.cap {
        i32 new_cap = v.cap * 2;
        if new_cap < 8 { new_cap = 8; }
        T* nd = alloc<T>(new_cap);
        memcpy(nd, v.data, v.len * sizeof(T));
        free(v.data);
        v.data = nd;
        v.cap = new_cap;
    }
    *(v.data + v.len) = val;
    v.len = v.len + 1;
    return;
}

T vec_get<T>(Vec<T>* v, i32 i) {
    return *(v.data + i);
}

void vec_set<T>(Vec<T>* v, i32 i, T val) {
    *(v.data + i) = val;
    return;
}

T vec_pop<T>(Vec<T>* v) {
    v.len = v.len - 1;
    return *(v.data + v.len);
}

void vec_free<T>(Vec<T>* v) {
    free(v.data);
    v.data = null;
    v.len = 0;
    v.cap = 0;
    return;
}
