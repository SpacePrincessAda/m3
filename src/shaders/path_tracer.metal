#include <metal_stdlib>
using namespace metal;

#include "../shader_types.h"
#include "common.metal"

typedef struct ray_t {
  float3 o;
  float3 d;
} ray_t;

typedef struct screen_vert_t {
  float4 pos [[position]];
  float2 uv;
} screen_vert_t;

typedef struct sphere_t {
  float3 p;
  float r;
} sphere_t;

typedef struct hit_t {
  float3 p;
  float3 n;
  float t;
} hit_t;

constant int sphere_count = 4;
constant sphere_t spheres[] = {
  {float3(-1,0.5,1), 0.5},
  {float3(1,1,1), 1.0},
  {float3(0,0.25,-0.5), 0.25},
  {float3(0,-1000,0), 1000.0},
};
constant float3 sphere_colors[] = {
  float3(1.0, 0.3, 0.1),
  float3(0.9),
  float3(0.2, 0.2, 1.0),
  float3(0.5),
};

#define SAMPLES_PER_PIXEL 10
constant int MAX_BOUNCES = 5;
constant float SPP_MOD = 1.0 / float(SAMPLES_PER_PIXEL);

float3 point_on_ray(float3 ro, float3 rd, float t) {
  return ro + t*rd;
}

int test_scene(float3 ro, float3 rd, thread hit_t& hit) {
  float closest_t = MAXFLOAT;
  float min_t = 0.001f;
  int hit_index = -1;

  for (int i=0; i<sphere_count; i++) {
    constant const sphere_t& s = spheres[i];
    float3 rel = ro - s.p;
    float b = dot(rel, rd);
    float c = dot(rel, rel) - s.r*s.r;
    float d = b*b - c;
    if (d > 0) {
      float sqrd = sqrt(d);
      float t = (-b - sqrd);
      if (t <= min_t) {
        t = (-b + sqrd);
      }
      if (t > min_t && t<closest_t) {
        hit_index = i;
        closest_t = t;
      }
    }
  }

  if (hit_index != -1) {
    float3 p = point_on_ray(ro, rd, closest_t);
    float3 n = normalize(p - spheres[hit_index].p);

    hit.t = closest_t;
    hit.p = p;
    hit.n = n;
  }

  return hit_index;
}

static inline bool lambertian(int id, thread hit_t& hit, thread float3& attenuation, thread ray_t& scattered, thread uint32_t& rng) {
  float3 target = hit.p + hit.n + rand_unit3(rng);
  scattered.o = hit.p;
  scattered.d = normalize(target - hit.p);
  attenuation = sphere_colors[id];
  return true;
}

float3 render(float3 _ro, float3 _rd, thread uint32_t& rng) {
  float3 color(0);
  float3 total_attenuation(1);

  float3 ro = _ro;
  float3 rd = _rd;

  for (int b=0; b < MAX_BOUNCES; b++) {
    hit_t hit;
    int id = test_scene(ro, rd, hit);
    if (id != -1) {
      ray_t scattered;
      float3 attenuation;

      lambertian(id, hit, attenuation, scattered, rng);

      // NOTE: only add to color if the surface is lit, and we don't currently have lights
      // color += total_attenuation;

      total_attenuation *= attenuation;

      ro = scattered.o;
      rd = scattered.d;
    } else {
      // Skybox
      float t = 0.5*(rd.y + 1.0);
      float3 sky_color = (1.0-t)*float3(1) + t*float3(0.5, 0.7, 1.0);
      color += total_attenuation * sky_color;
      break;
    }
  }

  return color;
}

ray_t ray_from_camera(render_camera_t c, float u, float v) {
  return {
    c.position,
    c.film_lower_left + (u*c.film_h) + (v*c.film_v) - c.position,
  };
}

// Full screen triangle
// Shamelessly taken from https://github.com/aras-p/ToyPathTracer
vertex screen_vert_t screen_vs_main(ushort vid [[vertex_id]]) {
  screen_vert_t o;
  o.uv = float2((vid << 1) & 2, vid & 2);
  o.pos = float4(o.uv * float2(2, 2) + float2(-1, -1), 0, 1);
  return o;
}

fragment float4 screen_fs_main(screen_vert_t i [[stage_in]], constant fs_params_t &rp [[buffer(0)]]) {
  render_camera_t camera = rp.camera;

  float3 color(0);
#if SAMPLES_PER_PIXEL == 1
  ray_t ray = ray_from_camera(camera, i.uv.x, i.uv.y);
  color = render(ray.o, normalize(ray.d), rng);
#else
  // Superficially, this seems like a decent source of entropy...
  uint32_t ix = (uint32_t)i.pos.x;
  uint32_t iy = (uint32_t)i.pos.y;
  uint rng = wang_hash(((ix*1973) + (iy*9277) + (rp.frame_count*26699))|1);

  // normalized pixel size
  float psx = 1/float(rp.viewport_size.x);
  float psy = 1/float(rp.viewport_size.y);

  for (int s=0; s<SAMPLES_PER_PIXEL; s++) {
    float u = (i.uv.x + (randf(rng)*psx));
    float v = (i.uv.y + (randf(rng)*psy));

    ray_t ray = ray_from_camera(camera, u, v);
    color += render(ray.o, normalize(ray.d), rng);
  }
  color *= SPP_MOD;
#endif
  return float4(linear_to_srgb(color), 1);
}

