#pragma once
#include "types.h"

typedef struct camera_t {
  v3 position;
  v3 target;
  v3 up;
  float vfov;
} camera_t;

typedef struct camera_state_t {
  v3 position;
  v3 target;
  float yaw;
  float pitch;
  float zoom;
  float vfov;
} camera_state_t;

typedef struct world_t {
  camera_t camera;

  camera_state_t orbit_cam;
  camera_state_t fp_cam;

  bool enable_fp_cam;
} world_t;

