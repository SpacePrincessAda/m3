// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
uint wang_hash(uint seed) {
  seed = (seed ^ 61) ^ (seed >> 16);
  seed *= 9;
  seed = seed ^ (seed >> 4);
  seed *= 0x27d4eb2d;
  seed = seed ^ (seed >> 15);
  return seed;
}

inline uint32_t xorshift32(thread uint32_t& state) {
  uint32_t x = state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  state = x;
  return x;
}

float randf(thread uint32_t& state) {
  return (xorshift32(state) & 0xFFFFFF) / 16777216.0f;
}

float3 rand_unit3(thread uint32_t& state) {
  float z = randf(state) * 2.0f - 1.0f;
  float a = randf(state) * 2.0f * M_PI_F;
  float r = sqrt(1.0f - z * z);
  float x = r * cos(a);
  float y = r * sin(a);
  return float3(x, y, z);
}

float3 linear_to_srgb(float3 rgb) {
  rgb = max(rgb, float3(0,0,0));
  return max(1.055 * pow(rgb, 0.416666667) - 0.055, 0.0);
}

