#pragma once

typedef struct camera_t {
  vector_float3 position;
  vector_float3 film_h;
  vector_float3 film_v;
  vector_float3 film_lower_left;
} camera_t;

typedef struct fs_params_t {
  vector_float2 viewport;
} fs_params_t;

