#pragma once
#include "debug_params.h"

typedef struct render_camera_t {
  vector_float3 position;
  vector_float3 film_h;
  vector_float3 film_v;
  vector_float3 film_lower_left;
} render_camera_t;

typedef struct fs_params_t {
  render_camera_t camera;
  uint32_t frame_count;
  vector_float2 viewport_size;
  debug_params_t debug_params;
} fs_params_t;

typedef struct dr_params_t {
  vector_float2 osb_to_rt_ratio;
} dr_params_t;

typedef struct ui_vs_params_t {
  matrix_float4x4 view_matrix;
} ui_vs_params_t;

typedef struct render_rect_t {
  vector_float2 position;
  vector_float2 size;
} render_rect_t;

typedef struct render_vert_t {
  vector_float2 position;
  vector_float4 color; // TODO: store this in a more clever way
} render_vert_t;

