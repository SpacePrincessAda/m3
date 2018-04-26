#pragma once

typedef struct render_camera_t {
  vector_float3 position;
  vector_float3 film_h;
  vector_float3 film_v;
  vector_float3 film_lower_left;
} render_camera_t;

typedef struct fs_params_t {
  render_camera_t camera;
} fs_params_t;
