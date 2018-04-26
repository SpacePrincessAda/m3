#pragma once
#include "types.h"

typedef struct camera_t {
  v3 position;
  v3 target;
  v3 up;
  float vfov;
} camera_t;

typedef struct world_t {
  camera_t camera;
} world_t;

