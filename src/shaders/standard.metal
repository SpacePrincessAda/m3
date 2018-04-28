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

constant int MAX_STEPS = 64;
constant float MIN_DIST = 1.0;
constant float MAX_DIST = 40.0;
constant float3 LIGHT_POSITION = float3(2.0, 5.0, 3.0);

#define RENDER_NORMALS 0

float radians(float degrees) {
  return degrees * (M_PI_F / 180.0);
}

float sd_box(float3 p, float3 b) {
  float3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sd_plane(float3 p) {
  return p.y;
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

float join(float a, float b) {
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
  float3 qos = float3(fract(p.x+0.5)-0.5, p.yz);
  float plane = sd_plane(p);
  float sphere = sd_sphere(p-float3(0,2.5,0), 0.3);
  float box = sd_box(p-float3(0,1,0), float3(1,1,1));
  return smin(plane, join(box, sphere), 1.5);
}

float3 calc_normal(float3 p) {
  float2 e = float2(1.0,-1.0)*0.5773*0.0005;
  return normalize(e.xyy*scene(p + e.xyy) + 
                   e.yyx*scene(p + e.yyx) + 
                   e.yxy*scene(p + e.yxy) + 
                   e.xxx*scene(p + e.xxx));
}

float calc_hard_shadow(float3 ro, float3 rd, float tmin, float tmax) {
  for (float t=tmin; t<tmax;) {
    float h = scene(ro + rd*t);
    if (h<0.001) {
      return 0.0;
    }
    t += h;
  }
  return 1.0;
}

// https://www.shadertoy.com/view/lsKcDD
float calc_soft_shadow(float3 ro, float3 rd, float tmin, float tmax) {
	float r = 1.0;
  float t = tmin;
  float ph = 1e10; // big, such that y = 0 on the first iteration

  for (int i=0; i<32; i++) {
    float h = scene(ro + rd*t);

    // Two techniques for soft shadows.
    // http://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
#if 0
    r = min(r, 10.0*h/t);
#else
    float y = h*h/(2.0*ph);
    float d = sqrt(h*h-y*y);
    r = min(r, 10.0*d/max(0.0,t-y));
    ph = h;
#endif
    t += h;
    if (r<0.0001 || t>tmax) break;
  }
  return clamp(r, 0.0, 1.0);
}

float cast_ray(float3 ro, float3 rd) {
  float tmin = MIN_DIST;
  float tmax = MAX_DIST;

  float t = tmin;
  for (int i=0; i<MAX_STEPS; i++) {
    float precis = 0.0005*t;
    float res = scene(ro+rd*t);
    if (res<precis || t>tmax) break;
    t += res;
  }

  if (t>tmax) t=-1.0;
  return t;
}

float3 render(float3 ro, float3 rd) {
  float3 color = float3(0);
  float t = cast_ray(ro, rd);

  if (t>-0.5) {
    float3 p = ro + t*rd;
    float3 n = calc_normal(p);
    
    // light
    float3 light = normalize(LIGHT_POSITION);
    float shadow = calc_hard_shadow(p, light, 0.01, 3.0);
    // float shadow = calc_soft_shadow(p, light, 0.01, 3.0);
#if RENDER_NORMALS
    color = (n * 0.5 + 0.5) * shadow;
#else
    float3 material = float3(1, 0, 0);
    float diffuse = clamp(dot(n, light), 0.0, 1.0);
    color = material * diffuse * shadow;

    // fog
    color *= exp(-0.00005*t*t*t);
#endif
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
  ray_t ray = ray_from_camera(camera, i.uv.x, i.uv.y);

  float3 color = render(ray.o, normalize(ray.d));
  return float4(color, 1);
}

