#include <metal_stdlib>
#import <simd/simd.h>
using namespace metal;

#include "../shader_types.h"

typedef struct ui_vert_t {
  float4 pos [[position]];
  float4 color;
} ui_vert_t;

vertex ui_vert_t ui_vs_main(ushort vid [[vertex_id]], 
                            constant render_vert_t *verts [[buffer(0)]], 
                            constant ui_vs_params_t &vp [[buffer(1)]])
{
  ui_vert_t o;
  render_vert_t vert = verts[vid];
  o.pos = vp.view_matrix * float4(vert.position, 0, 1);
  o.color = vert.color;
  return o;
}

fragment float4 ui_fs_main(ui_vert_t i [[stage_in]]) {
  return i.color;
}

