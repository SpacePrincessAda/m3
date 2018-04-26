#include "app.h"
#include "game.h"
#include "types.h"
#include "cave_math.h"

/*
TODO:

Platform:
  - mouse inputs
  - shader reloading
*/

#define CAMERA_DEFAULT_FP_POS V3(0,1,-5)
#define CAMERA_DEFAULT_ORBIT_POS V3(5,3,-5)

// TODO: Put these somewhere else
static float yaw = 0.0f;
static float pitch = 0.0f;

void init_world(app_t* app, world_t *world) {
  world->camera.position = CAMERA_DEFAULT_ORBIT_POS;
  world->camera.target = V3(0,1,0);
  world->camera.up = V3(0,1,0);
  world->camera.vfov = 45.0f;

  // defaults for orbit cam
  yaw = M_PI * 1.25;
  pitch = M_PI * 0.1;
}

void update_and_render(app_t* app, world_t *world) {
  // printf("%f\n", app->clocks.delta_secs);
  float dt = app->clocks.delta_secs;

  // Strafe
  v3 move = {0};
  if (app->keys[KEY_A].down) {
    move.x -= 2.0f * dt;
  }
  if (app->keys[KEY_D].down) {
    move.x += 2.0f * dt;
  }

  // Forward/Back
  if (app->keys[KEY_S].down) {
    move.z -= 2.0f * dt;
  }
  if (app->keys[KEY_W].down) {
    move.z += 2.0f * dt;
  }

  // Look horizontal
  if (app->keys[KEY_LEFT].down) {
    yaw -= 2.0f * dt;
  }
  if (app->keys[KEY_RIGHT].down) {
    yaw += 2.0f * dt;
  }

  // Look vertical
  if (app->keys[KEY_DOWN].down) {
    pitch -= 2.0f * dt;
  }
  if (app->keys[KEY_UP].down) {
    pitch += 2.0f * dt;
  }

  // Orbit the center
  m3x3 rm = rot3xy(-pitch, -yaw);
  world->camera.position = mul3x3(rm, V3(0,0,10));

  // First person camera
  // m3x3 rm = rot3xy(pitch, yaw);
  // world->camera.position = add3(world->camera.position, mul3x3(rm, move));
  // world->camera.target = add3(world->camera.position, mul3x3(rm, V3(0, 0, 1)));
}

