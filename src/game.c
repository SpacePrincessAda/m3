#include "app.h"
#include "game.h"
#include "types.h"
#include "cave_math.h"

void init_world(app_t* app, world_t *world) {
  world->orbit_cam.position = V3(10,3,-10);
  world->orbit_cam.target = V3(0,1,0);
  world->orbit_cam.vfov = 45;
  world->orbit_cam.yaw = M_PI * 1.25;
  world->orbit_cam.pitch = M_PI * 0.1;

  world->fp_cam.position = V3(0,1,-10);
  world->fp_cam.vfov = 45;

  world->camera.up = V3(0,1,0);
}

void update_and_render(app_t* app, world_t *world) {
  // printf("%f\n", app->clocks.delta_secs);
  float dt = app->clocks.delta_secs;

  float yaw = 0;
  float pitch = 0;

  if (app->keys[KEY_O].pressed) {
    world->enable_fp_cam = !world->enable_fp_cam;
    printf("switched to %s camera\n", world->enable_fp_cam ? "fp" : "orbit");
  }

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

  // Apply new camera values
  camera_state_t *cs;
  if (world->enable_fp_cam) {
    cs = &world->fp_cam;
    cs->pitch += pitch;
    cs->yaw += yaw;
    m3x3 rm = rot3xy(-cs->pitch, cs->yaw);
    cs->position = add3(cs->position, mul3x3(rm, move));
    cs->target = add3(cs->position, mul3x3(rm, V3(0, 0, 1)));
  } else {
    cs = &world->orbit_cam;
    cs->pitch += pitch;
    cs->yaw += yaw;
    m3x3 rm = rot3xy(-cs->pitch, -cs->yaw);
    cs->position = mul3x3(rm, V3(0,0,10));
  }
  world->camera.position = cs->position;
  world->camera.target = cs->target;
  world->camera.vfov = cs->vfov;
}

