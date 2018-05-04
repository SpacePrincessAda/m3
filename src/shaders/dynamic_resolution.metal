#include <metal_stdlib>
using namespace metal;

#include "../shader_types.h"

typedef struct screen_vert_t {
  float4 pos [[position]];
  float2 uv;
} screen_vert_t;

// Full screen triangle
// Shamelessly taken from https://github.com/aras-p/ToyPathTracer
vertex screen_vert_t dr_vs_main(ushort vid [[vertex_id]]) {
  screen_vert_t o;
  o.uv = float2((vid << 1) & 2, vid & 2);
  o.pos = float4(o.uv * float2(2, 2) + float2(-1, -1), 0, 1);
  return o;
}

fragment float4 dr_fs_main(screen_vert_t i [[stage_in]], 
                           constant dr_params_t &rp [[buffer(0)]],
                           texture2d<float> tex [[texture(0)]])
{
  float2 ratio = rp.osb_to_rt_ratio;
  float u = ratio.x * i.uv.x;
  float v = -ratio.y * (i.uv.y - 1.0);
  constexpr sampler smp(mip_filter::none, mag_filter::nearest, min_filter::nearest);
  return float4(tex.sample(smp, float2(u, v)).rgb, 1);
}

