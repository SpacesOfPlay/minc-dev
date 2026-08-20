// shader.mc — @shader metadata layout.

// Each @shader function gets a global named <funcname>_shader of
// type ShaderMeta. ShaderMeta, ShaderUniformDesc, and ShaderBinding
// are built-in struct types — no include needed. The struct layouts
// below are reference only.

// struct ShaderMeta {
//     u8* source;             // compiled shader text (HLSL / GLSL / MSL)
//     u8* entry;              // entry-point name, or null
//     i32 stage;              // 1=vertex, 2=fragment, 3=compute
//     i32 group_size_x, y, z; // compute thread-group dims
//     i32 uniform_size;       // total uniform bytes across all blocks
//     i32 num_uniforms;       // @uniform parameter count
//     i32 num_bindings;       // @storage / @texture / @sampler count
//     i32 num_attrs;          // @attr parameter count (VS only)
//     i32 num_uniform_blocks;
//     i32 ub_size0..3;        // bytes per block
//     u8* ub_name0..3;        // first uniform's name in each block
//     ShaderUniformDesc* uniforms;
//     i32 uniforms_count;
//     ShaderBinding* bindings;
//     i32 bindings_count;
//     u8* name;               // the @shader function's name
//     u64 iface_hash;         // hash over the pipeline-visible interface
//                             // (attrs/uniforms/bindings/return shape —
//                             // body edits don't change it)
//     u8* error_source;       // pink error-fallback fragment source;
//                             // only set under -DSHADER_LIVE, null for
//                             // vertex/compute and in normal builds
//     i32 ub_flat_mask;       // GLSL targets: bit b set = block b was
//                             // emitted flattened (one vec4 array named
//                             // _mcub<b>_vs/_fs/_cs); the runtime desc
//                             // must declare it as a single FLOAT4
//                             // member with array_count =
//                             // ceil(ub_sizeN/16). 0 on other targets.
//     i32 ub_std140_mask;     // bit b set = block b is an @gpu_layout
//                             // struct: its client data follows the GPU
//                             // (std140) layout, so the runtime desc
//                             // must declare SG_UNIFORMLAYOUT_STD140
//                             // for GL's per-member upload path.
// }

// struct ShaderUniformDesc {
//     u8* name;        // uniform or struct-field name
//     i32 type_kind;   // ShaderUType value
//     i32 array_count; // 1 for scalars, N for arrays
//     i32 offset;      // byte offset within the block
//     i32 block;       // block index (0..3)
// }

// uniforms is one descriptor per field, flat across all blocks:
//
//   @uniform float4x4 mvp        →  1 entry  (mvp,    MAT4,   off 0)
//   @uniform float4 params       →  1 entry  (params, FLOAT4, off 0)
//   @uniform(0) PerFrame frame   →  N entries, one per struct field
//
// A runtime groups by block to build its per-block uniform table.

// struct ShaderBinding {
//     u8* name;           // declared param name (used for GLSL combined-sampler symbols)
//     i32 kind;           // ShaderBindingKind value
//     i32 slot;           // logical binding slot, as written in @texture(N) / @sampler(N) / @storage(...)
//     i32 image_type;     // ShaderImageType — meaningful for textures and storage images
//     u8* format;         // pixel-format string for storage images (e.g. "rgba8"), null otherwise
//     i32 format_len;
//     i32 access;         // ShaderBindingAccess — meaningful for storage images / buffers
//     i32 struct_size;    // element size in bytes (storage buffers)
//     i32 stage;          // 0=vertex, 1=fragment, 3=compute (matches the @shader function's stage)
//     i32 sample_kind;    // ShaderSampleKind — meaningful for textures
//     i32 sampler_kind;   // ShaderSamplerKind — meaningful for samplers
//     i32 multisampled;   // 1 when the bound image is multisample (Texture2DMS)
// }

// bindings is one entry per @texture / @sampler / @storage / @buffer /
// @rwbuffer parameter, in declaration order:
//
//   @texture(0) Texture2D tex          →  kind=TEXTURE,        slot=0, image_type=2D
//   @sampler(0) Sampler smp            →  kind=SAMPLER,        slot=0
//   @storage(rgba8)     RWTexture2D im →  kind=STORAGE_IMAGE,  slot=0, image_type=2D,
//                                          format="rgba8", access=WRITEONLY
//   @storage(rgba8, rw) RWTexture2D im →  kind=STORAGE_IMAGE,  slot=0, image_type=2D,
//                                          format="rgba8", access=READWRITE
//   @buffer(0)   []Particle particles  →  kind=STORAGE_BUFFER, slot=0, access=READONLY,
//                                          struct_size=sizeof(Particle)
//   @rwbuffer(0) []Particle particles  →  kind=STORAGE_BUFFER, slot=0, access=READWRITE,
//                                          struct_size=sizeof(Particle)
//
// sokol's storage-image access is binary (writeonly OR readwrite —
// never readonly; for readonly use a regular @texture binding) and
// storage-buffer access is binary (readonly OR readwrite — never
// writeonly). The READONLY / WRITEONLY / READWRITE enum below covers
// both shapes so a single ShaderBinding layout serves all kinds.
//

// ShaderUType — values used by ShaderUniformDesc.type_kind.
// The compiler writes these numbers into the metadata.
enum ShaderUType {
    INVALID,    // 0
    FLOAT,      // 1   f32
    FLOAT2,     // 2   float2
    FLOAT3,     // 3   float3
    FLOAT4,     // 4   float4
    INT,        // 5   i32
    INT2,       // 6   int2
    INT3,       // 7   int3
    INT4,       // 8   int4
    MAT4,       // 9   float4x4
    UINT,       // 10  u32
    UINT2,      // 11  uint2
    UINT3,      // 12  uint3
    UINT4,      // 13  uint4
}

// ShaderBindingKind — values used by ShaderBinding.kind.
// Storage buffers are reserved; the compiler doesn't yet emit them.
enum ShaderBindingKind {
    TEXTURE,        // 0  Texture2D / Texture3D / TextureCube / Texture2DArray
    SAMPLER,        // 1  Sampler / ComparisonSampler
    STORAGE_IMAGE,  // 2  RWTexture2D — compute write target
    STORAGE_BUFFER, // 3  RWStructuredBuffer / StructuredBuffer (reserved)
}

// ShaderSampleKind — values used by ShaderBinding.sample_kind.
// A texture sampled through sample_cmp() is a depth texture; a runtime
// adapter has to say so when it describes the binding (sokol wants
// SG_IMAGESAMPLETYPE_DEPTH rather than _FLOAT).
enum ShaderSampleKind {
    SAMPLE_FLOAT,          // 0  ordinary colour texture
    SAMPLE_DEPTH,          // 1  sampled for depth comparison
    SAMPLE_UNFILTERABLE,   // 2  @texture(N, unfilterable) — the bound
                           //    format can't be filtered (a depth image
                           //    read as data, a 32-bit float target, …)
    SAMPLE_SINT,           // 3  Texture2D<i32> — read with tex[coord]
    SAMPLE_UINT,           // 4  Texture2D<u32>
}

// ShaderSamplerKind — values used by ShaderBinding.sampler_kind. The
// sampler paired with a depth texture in a sample_cmp() call does the
// comparison (sokol: SG_SAMPLERTYPE_COMPARISON rather than _FILTERING).
enum ShaderSamplerKind {
    SAMPLER_FILTERING,    // 0
    SAMPLER_COMPARISON,   // 1
    SAMPLER_NONFILTERING, // 2  @sampler(N, nonfiltering) — pairs with an
                          //    unfilterable texture
}

// ShaderImageType — values used by ShaderBinding.image_type.
enum ShaderImageType {
    IMAGE_2D,        // 0
    IMAGE_3D,        // 1
    IMAGE_CUBE,      // 2
    IMAGE_2D_ARRAY,  // 3
}

// ShaderBindingAccess — values used by ShaderBinding.access.
// RWTexture2D is writeonly today; the language has no syntax for the
// other variants yet but the metadata has room for them.
enum ShaderBindingAccess {
    READONLY,    // 0
    WRITEONLY,   // 1
    READWRITE,   // 2
}
