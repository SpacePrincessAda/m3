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

