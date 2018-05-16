#include "app.h"
#include "game.h"
#include "types.h"
#include "cave_math.h"
#include "debug_params.h"


//
// TODO: Move as much of the UI setup/layout as possible sit outside of the platform layer
//

void init_world(app_t* app, world_t* world) {
  world->orbit_cam.target = V3(0,1,0);
  world->orbit_cam.zoom = 10;
  world->orbit_cam.vfov = 45;
  world->orbit_cam.yaw = M_PI * 1.25;
  world->orbit_cam.pitch = M_PI * 0.1;

  world->fp_cam.position = V3(0,3,-10);
  world->fp_cam.vfov = 45;

  world->camera.up = V3(0,1,0);
}

void update_and_render(app_t* app, world_t* world, debug_params_t* debug_params) {
  // printf("%f\n", app->clocks.delta_secs);
  f32 dt = app->clocks.delta_secs;

  int width = app->display.size_in_points.x;

  if (app->keys[KEY_L].pressed) {
    app->mouse.capture = !app->mouse.capture;
  }

  // DEBUG PARAMS
  if (app->keys[KEY_MINUS].down) {
    debug_params->scalars[0] -= 1.0f*dt;
  }
  if (app->keys[KEY_EQUALS].down) {
    debug_params->scalars[0] += 1.0f*dt;
  }
  if (app->keys[KEY_0].pressed) {
    debug_params->scalars[0] = 0;
  }

  // Render scale
  f32 render_scale = app->render_scale;
  if (app->keys[KEY_LEFTBRACKET].pressed) {
    render_scale *= 0.5f;
  }
  if (app->keys[KEY_RIGHTBRACKET].pressed) {
    render_scale *= 2.0f;
  }
  render_scale = clamp(0.0625, render_scale, 1.0);
  if (render_scale != app->render_scale) {
    app->render_scale = render_scale;
    printf("render scale: %0.02f%%\n", 100.0*app->render_scale);
  }

  if (app->keys[KEY_O].pressed) {
    world->enable_fp_cam = !world->enable_fp_cam;
    printf("switched to %s camera\n", world->enable_fp_cam ? "fp" : "orbit");
  }

  // Strafe
  v3 move = {0};
  if (app->keys[KEY_A].down) {
    move.x -= 3.0f * dt;
  }
  if (app->keys[KEY_D].down) {
    move.x += 3.0f * dt;
  }

  // Forward/Back
  if (app->keys[KEY_S].down) {
    move.z -= 3.0f * dt;
  }
  if (app->keys[KEY_W].down) {
    move.z += 3.0f * dt;
  }

  // Look horizontal
  f32 yaw = 0;
  f32 pitch = 0;
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

  if (app->mouse.capture && app->mouse.moved) {
    yaw += app->mouse.delta_position.x * dt;
    pitch -= app->mouse.delta_position.y * dt;
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
    cs->zoom -= move.z;
    cs->position = mul3x3(rm, V3(0,0,cs->zoom));
  }
  world->camera.position = cs->position;
  world->camera.target = cs->target;
  world->camera.vfov = cs->vfov;
}

