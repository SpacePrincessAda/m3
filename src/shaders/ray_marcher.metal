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

#define SCENE_INDEX 0
#define RENDER_NORMALS 0
#define ENABLE_SHADOWS 1
#define ENABLE_DF_PLANE 1

//
// Distance Field Debug Plane
// Thank you Mercury: https://www.shadertoy.com/view/ldK3zD
//

float3 fusion(float x) {
	float t = clamp(x,0.0,1.0);
	return clamp(float3(sqrt(t), t*t*t, max(sin(M_PI_F*1.75*t), pow(t, 12.0))), 0.0, 1.0);
}

float3 distance_meter(float dist, float ray_length, float3 ray_dir, float cam_height) {
  float ideal_grid_distance = 20.0/ray_length*pow(abs(ray_dir.y),0.8);
  float nearest_base = floor(log(ideal_grid_distance)/log(10.));
  float relative_dist = abs(dist/cam_height);
  
  float larger_distance = pow(10.0,nearest_base+1.);
  float smaller_distance = pow(10.0,nearest_base);

 
  float3 col = fusion(log(1.+relative_dist));
  col = max(float3(0.),col);
  if (sign(dist) < 0.) {
    col = col.grb*3.;
  }

  float l0 = (pow(0.5+0.5*cos(dist*M_PI_F*2.*smaller_distance),10.0));
  float l1 = (pow(0.5+0.5*cos(dist*M_PI_F*2.*larger_distance),10.0));
  
  float x = fract(log(ideal_grid_distance)/log(10.));
  l0 = mix(l0,0.,smoothstep(0.5,1.0,x));
  l1 = mix(0.,l1,smoothstep(0.0,0.5,x));

  col.rgb *= 0.1+0.9*(1.-l0)*(1.-l1);
  return col;
}

//
//
//

float radians(float degrees) {
  return degrees * (M_PI_F / 180.0);
}

float sd_box(float3 p, float3 b) {
  float3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sd_plane(float3 p, float3 n, float dist) {
  return dot(p, n) + dist;
}

float ud_plane(float3 p) {
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
#if SCENE_INDEX == 0
  float box = sd_box(p-float3(0,1,0), float3(1,1,1));
  return box;
#elif SCENE_INDEX == 1
  float box = sd_box(p, float3(1,1,1));
  float sphere = sd_sphere(p, 1.2);
  return intersect(box, sphere);
#elif SCENE_INDEX == 2
  float box = sd_box(p, float3(1,2,1));
  float sphere = sd_sphere(p-float3(0,2.5,0), 0.3);
  float plane = sd_plane(p, float3(0,1,0), 0.5);
  return smin(plane, join(box, sphere), 1.5);
#else
  return 0;
#endif
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

float3 render(float3 ro, float3 rd, render_camera_t camera, debug_params_t debug_params) {
  float3 color = float3(0);
  float t = cast_ray(ro, rd);
  float3 p = ro + t*rd;

#if ENABLE_DF_PLANE == 1
  float df_plane_y = debug_params.scalars[0];
  if (p.y <= df_plane_y || t<-0.5) {
    float ray_length = INFINITY;
    if (rd.y < 0.0) {
      ray_length = (ro.y-df_plane_y)/-rd.y;
    }
    float dist = scene(ro+rd*ray_length);
    float3 field_color = distance_meter(dist, ray_length, rd, camera.position.y-df_plane_y);
    return field_color;
  }
#endif

  if (t>-0.5) {
    float3 n = calc_normal(p);
    
    // light
    float3 light = normalize(LIGHT_POSITION);
#if ENABLE_SHADOWS
    float shadow = calc_hard_shadow(p, light, 0.01, 3.0);
#else
    float shadow = 1;
#endif
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

  float3 color = render(ray.o, normalize(ray.d), camera, rp.debug_params);
  return float4(color, 1);
}

