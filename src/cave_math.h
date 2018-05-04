#pragma once

//
// Types
//

typedef union v2 {
  struct {
    f32 x;
    f32 y;
  };
  f32 e[2];
} v2;

typedef union v3 {
  struct {
    f32 x;
    f32 y;
    f32 z;
  };
  struct {
    f32 r;
    f32 g;
    f32 b;
  };
  struct {
    v2 xy;
    f32 __ignored_0;
  };
  f32 e[3];
} v3;

typedef union v4 {
  struct {
    union {
      v3 xyz;
      struct {
        f32 x;
        f32 y;
        f32 z;
      };
    };
    f32 w;
  };
  struct {
    union {
      v3 rgb;
      struct {
        f32 r;
        f32 g;
        f32 b;
      };
    };
    f32 a;
  };
  f32 e[4];
} v4;

typedef union quat {
  struct {
    union {
      v3 xyz;
      struct {
        f32 x;
        f32 y;
        f32 z;
      };
    };

    f32 w;
  };
  f32 e[4];
} quat;

// column major
typedef union m3x3 {
  f32 e[3][3];
} m3x3;

typedef union m4x4 {
  f32 e[4][4];
} m4x4;


//
// constructors
//

static inline v2 
V2(f32 x, f32 y) {
  v2 r;
  r.x = x;
  r.y = y;
  return r;
}

static inline v3 
V3(f32 x, f32 y, f32 z) {
  v3 r;
  r.x = x;
  r.y = y;
  r.z = z;
  return r;
}

#define v3_zero     V3(0, 0, 0)
#define v3_one      V3(1, 1, 1)
#define v3_right    V3(1, 0, 0)
#define v3_up       V3(0, 1, 0)
#define v3_forward  V3(0, 0, 1)

static inline quat
Q(f32 x, f32 y, f32 z, f32 w) {
  quat r;
  r.x = x;
  r.y = y;
  r.z = z;
  r.w = w;
  return r;
}

#define quat_identity Q(0, 0, 0, 1);

//
// scalar operations
//

static inline f32 
square(f32 a) {
  return a * a;
}

static inline f32 
square_root(f32 a) {
  f32 r = (f32)sqrt(a);
  return r;
}

static inline f32
clamp(f32 min, f32 value, f32 max) {
  f32 r = value;

  if (r < min) {
    r = min;
  } else if (r > max) {
    r = max;
  }

  return r;
}

static inline f32 
clamp01(f32 value) {
  return clamp(0.0f, value, 1.0f);
}

//
// V2 operations
//

static inline bool 
eq2(v2 a, v2 b) {
  return a.x == b.x && a.y == b.y;
}

static inline v2
mul2(v2 a, f32 f) {
  v2 r = {};
  r.x = a.x * f;
  r.y = a.y * f;
  return r;
}

static inline f32
aspect2(v2 a) {
  return a.x / a.y;
}

//
// V3 operations
//

static inline v3 
add3(v3 a, v3 b) {
  v3 r = {};
  r.x = a.x + b.x;
  r.y = a.y + b.y;
  r.z = a.z + b.z;
  return r;
}

static inline v3 
sub3(v3 a, v3 b) {
  v3 r = {};
  r.x = a.x - b.x;
  r.y = a.y - b.y;
  r.z = a.z - b.z;
  return r;
}

static inline v3 
mul3(v3 a, f32 f) {
  v3 r = {};
  r.x = a.x * f;
  r.y = a.y * f;
  r.z = a.z * f;
  return r;
}

static inline v3 
div3(v3 a, f32 f) {
  v3 r = {};
  r.x = a.x / f;
  r.y = a.y / f;
  r.z = a.z / f;
  return r;
}

static inline v3 
neg3(v3 a) {
  v3 r = {};
  r.x = -a.x;
  r.y = -a.y;
  r.z = -a.z;
  return r;
}

static inline v3 
cross3(v3 a, v3 b) {
  v3 r = {};
  r.x = a.y*b.z - a.z*b.y;
  r.y = a.z*b.x - a.x*b.z;
  r.z = a.x*b.y - a.y*b.x;
  return r;
}

static inline f32 
dot3(v3 a, v3 b) {
  return a.x*b.x + a.y*b.y + a.z*b.z;
}

static inline f32 
magnitude_sqr3(v3 a) {
  return dot3(a, a);
}

static inline f32 
magnitude3(v3 a) {
  return square_root(magnitude_sqr3(a));
}

static inline v3 
unit3(v3 a) {
  return mul3(a, (1.0f / magnitude3(a)));
}

static inline v3 
NOZ3(v3 a) {
  v3 r = {};
  f32 magnitude_squared = magnitude_sqr3(a);
  if (magnitude_squared > square(0.0001f)) {
    r = mul3(a, (1.0f / square_root(magnitude_squared)));
  }
  return r;
}

static inline v3
hadamard3(v3 a, v3 b) {
  v3 r = {a.x*b.x, a.y*b.y, a.z*b.z};
  return r;
}

static inline v3 
lerp3(v3 a, f32 t, v3 b) {
  v3 r = add3(mul3(a, (1.0f - t)), mul3(b, t));
  return r;
}

//
// quaternion operations
//

static inline quat 
angle_axis(f32 angle, v3 axis) {
  quat q = {};
  f32 s = sinf(angle * 0.5f);
  q.x = axis.x * s;
  q.y = axis.y * s;
  q.z = axis.z * s;
  q.w = cosf(angle * 0.5f);
  return q;
}

//
// m3x3 operations
//

// TODO: Make this fast!
static inline v3
mul3x3(m3x3 m, v3 v) {
  v3 r;
  for (int col=0; col < 3; col++) {
    f32 sum = 0;
    for (int row=0; row < 3; row++) {
      sum += m.e[row][col] * v.e[row];
    }
    r.e[col] = sum;
  }
  return r;
}

m3x3 rot3xy(f32 pitch, f32 yaw) {
  v2 c = V2(cosf(pitch), cosf(yaw));
  v2 s = V2(sinf(pitch), sinf(yaw));

  return (m3x3){
		c.y      ,  0.0, -s.y      ,
		s.y * s.x,  c.x,  c.y * s.x,
		s.y * c.x, -s.x,  c.y * c.x,
  };
}

//
// color operations
//

static inline u32 
round_f32_to_u32(f32 f) {
  return (u32)(f + 0.5f);
}

static inline u32 
bgra_pack3(v3 unpacked) {
  u32 r = (
    0xFF000000 |
    (round_f32_to_u32(unpacked.r) << 16) |
    (round_f32_to_u32(unpacked.g) << 8) |
    (round_f32_to_u32(unpacked.b) << 0)
  );
  return r;
}

