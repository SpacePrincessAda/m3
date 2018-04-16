#include <metal_stdlib>
using namespace metal;

typedef struct vertex_src_t {
  float2 position;
  float4 color;
} vertex_src_t;

typedef struct vertex_out_t {
  float4 position [[position]];
  float4 color;
} vertex_in_out_t;

vertex vertex_in_out_t 
vs_main(uint id [[vertex_id]], constant vertex_src_t *vertices [[buffer(0)]], constant vector_int2 *vpsp [[buffer(1)]]) {
  vertex_in_out_t out;
  out.position = float4(0, 0, 0, 1.0);
  float2 src_pos = vertices[id].position.xy;
  float2 vp = float2(*vpsp);
  out.position.xy = src_pos / (vp / 2.0);
  out.color = vertices[id].color;
  return out;
}

fragment float4 
fs_main(vertex_in_out_t in [[stage_in]]) {
  return in.color;
}
 
