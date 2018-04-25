#include <metal_stdlib>
using namespace metal;

#include "../shader_types.h"

typedef struct ray_t {
  float3 o;
  float3 d;
} ray_t;

typedef struct screen_vert_t {
  float4 pos [[position]];
  float2 uv;
} screen_vert_t;

constant int MAX_STEPS = 255;
constant float MIN_DIST = 0.0;
constant float MAX_DIST = 100.0;
constant float EPSILON = 0.0001;

float radians(float degrees) {
  return degrees * (M_PI_F / 180.0);
}

float sd_box(float3 p, float3 b) {
  float3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sd_plane(float3 p, float4 n) {
  // n must be normalized
  return dot(p, n.xyz) + n.w;
}

float sd_sphere(float3 p, float r) {
  return length(p) - r;
}

float intersect(float a, float b) {
  return max(a, b);
}

float subtract(float a, float b) {
  return max(-a, b);
}

float meld(float a, float b) {
  return min(a, b);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
  return mix(b, a, h) - k*h*(1.0-h);
}

float sd_torus(float3 p, float2 t) {
  float2 q = float2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

float3 mod(float3 x, float y) {
  return x - y * floor(x/y);
}

float scene(float3 p) {
  // float displacement = sin(5.0 * p.x) * sin(5.0 * p.y) * sin(5.0 * p.z) * 0.25;
  float box = sd_box(p, float3(1,2,1));
  float sphere = sd_sphere(p, 1.2);
  float plane = sd_plane(p, normalize(float4(0,1,0,0)));
  // return max(box, -sphere);
  // float torus = sd_torus(p, float2(2, 0.3));
  return meld(plane, intersect(box, sphere));
  // return smin(plane, intersect(box, sphere), 1);
}

float3 calc_normal(float3 p) {
  const float3 small_step = float3(0.001, 0.0, 0.0);

  float gradient_x = scene(p + small_step.xyy) - scene(p - small_step.xyy);
  float gradient_y = scene(p + small_step.yxy) - scene(p - small_step.yxy);
  float gradient_z = scene(p + small_step.yyx) - scene(p - small_step.yyx);

  float3 normal = float3(gradient_x, gradient_y, gradient_z);
  return normalize(normal);
}

float shadow(float3 ro, float3 rd, float mint, float maxt) {
  for(float t=mint; t < maxt;) {
    float h = scene(ro + rd*t);
    if (h<0.001) {
      return 0.0;
    }
    t += h;
  }
  return 1.0;
}

float3 march(float3 ro, float3 rd) {
  float depth = 0;
  for (int i=0; i<MAX_STEPS; i++) {
    float3 p = ro + depth * rd;
    float dist = scene(p);
    if (dist < EPSILON) {
      float3 nor = calc_normal(p);
      float3 mate = float3(1,0,0);
      float3 lig = normalize(float3(2.0, 5.0, 3.0)); 
      float3 ligp = normalize(float3(2.0, 5.0, 3.0) - p); 
      float3 d_to_l = normalize(p - ligp);
      float shad = shadow(p, lig, 0.1, 30.0);
      float diff = clamp(dot(nor, ligp), 0.0, 1.0);
      return mate*diff*shad;
      // return (nor * 0.5 + 0.5)*shad; // render normal
#if 0
      float3 n = calc_normal(p);
      float3 light_p = float3(2.0, 5.0, 3.0);
      float3 d = normalize(light_p - p);
      float s = shadow(p, light_p, EPSILON, 20.0);
      float diffuse = clamp(dot(n, d), 0.0, 1.0);
      return float3(1,0,0) * diffuse;
#endif
    }
    if (depth >= MAX_DIST) {
      return float3(0);
    }
    depth += dist;
  }
  return float3(0);
}

camera_t create_camera(float3 from, float3 to, float3 up, float vfov, float aspect) {
  float theta = vfov * M_PI_F / 180.0f;
  float half_height = tan(theta/2);
  float half_width = aspect * half_height;
  float3 w = normalize(from - to);
  float3 u = normalize(cross(up, w));
  float3 v = cross(w, u);
  camera_t c = {
    from,
    2*half_width*u,
    2*half_height*v,
    from - (half_width*u) - (half_height*v) - w,
  };
  return c;
}

ray_t ray_from_camera(camera_t c, float u, float v) {
  return {
    c.position,
    c.film_lower_left + (u*c.film_h) + (v*c.film_v) - c.position,
  };
}

vertex screen_vert_t screen_vs_main(ushort vid [[vertex_id]]) {
  screen_vert_t o;
  o.uv = float2((vid << 1) & 2, vid & 2);
  o.pos = float4(o.uv * float2(2, 2) + float2(-1, -1), 0, 1);
  return o;
}

fragment float4 screen_fs_main(screen_vert_t i [[stage_in]], constant fs_params_t &rp [[buffer(0)]]) {
  camera_t camera = create_camera(float3(5,3,-5), float3(0,1,0), float3(0,1,0), 45.0f, rp.viewport.x/rp.viewport.y);
  ray_t ray = ray_from_camera(camera, i.uv.x, i.uv.y);

  float3 color = march(ray.o, ray.d);
  return float4(color, 1);
}

