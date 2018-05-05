#pragma once
#include "types.h"
#include "cave_math.h"

enum key_t {
  KEY_A = 0,
  KEY_S = 1,
  KEY_D = 2,
  KEY_F = 3,
  KEY_H = 4,
  KEY_G = 5,
  KEY_Z = 6,
  KEY_X = 7,
  KEY_C = 8,
  KEY_V = 9,
  KEY_NONUSBACKSLASH = 10,
  KEY_B = 11,
  KEY_Q = 12,
  KEY_W = 13,
  KEY_E = 14,
  KEY_R = 15,
  KEY_Y = 16,
  KEY_T = 17,
  KEY_1 = 18,
  KEY_2 = 19,
  KEY_3 = 20,
  KEY_4 = 21,
  KEY_6 = 22,
  KEY_5 = 23,
  KEY_EQUALS = 24,
  KEY_9 = 25,
  KEY_7 = 26,
  KEY_MINUS = 27,
  KEY_8 = 28,
  KEY_0 = 29,
  KEY_RIGHTBRACKET = 30,
  KEY_O = 31,
  KEY_U = 32,
  KEY_LEFTBRACKET = 33,
  KEY_I = 34,
  KEY_P = 35,
  KEY_RETURN = 36,
  KEY_L = 37,
  KEY_J = 38,
  KEY_APOSTROPHE = 39,
  KEY_K = 40,
  KEY_SEMICOLON = 41,
  KEY_BACKSLASH = 42,
  KEY_COMMA = 43,
  KEY_SLASH = 44,
  KEY_N = 45,
  KEY_M = 46,
  KEY_PERIOD = 47,
  KEY_TAB = 48,
  KEY_SPACE = 49,
  KEY_GRAVE = 50,
  KEY_BACKSPACE = 51,
  KEY_KP_ENTER = 52,
  KEY_ESCAPE = 53,
  KEY_RMETA = 54,
  KEY_LMETA = 55,
  KEY_LSHIFT = 56,
  KEY_CAPSLOCK = 57,
  KEY_LALT = 58,
  KEY_LCTRL = 59,
  KEY_RSHIFT = 60,
  KEY_RALT = 61,
  KEY_RCTRL = 62,
  // KEY_RGUI = 63,
  KEY_F17 = 64,
  KEY_KP_PERIOD = 65,
  // KEY_UNKNOWN = 66,
  KEY_KP_MULTIPLY = 67,
  // KEY_UNKNOWN = 68,
  KEY_KP_PLUS = 69,
  // KEY_UNKNOWN = 70,
  KEY_NUMLOCKCLEAR = 71,
  KEY_VOLUMEUP = 72,
  KEY_VOLUMEDOWN = 73,
  KEY_MUTE = 74,
  KEY_KP_DIVIDE = 75,
  // KEY_KP_ENTER = 76,
  // KEY_UNKNOWN = 77,
  KEY_KP_MINUS = 78,
  KEY_F18 = 79,
  KEY_F19 = 80,
  KEY_KP_EQUALS = 81,
  KEY_KP_0 = 82,
  KEY_KP_1 = 83,
  KEY_KP_2 = 84,
  KEY_KP_3 = 85,
  KEY_KP_4 = 86,
  KEY_KP_5 = 87,
  KEY_KP_6 = 88,
  KEY_KP_7 = 89,
  // KEY_UNKNOWN = 90,
  KEY_KP_8 = 91,
  KEY_KP_9 = 92,
  KEY_INTERNATIONAL3 = 93,
  KEY_INTERNATIONAL1 = 94,
  KEY_KP_COMMA = 95,
  KEY_F5 = 96,
  KEY_F6 = 97,
  KEY_F7 = 98,
  KEY_F3 = 99,
  KEY_F8 = 100,
  KEY_F9 = 101,
  KEY_LANG2 = 102,
  KEY_F11 = 103,
  KEY_LANG1 = 104,
  KEY_PRINTSCREEN = 105,
  KEY_F16 = 106,
  KEY_SCROLLLOCK = 107,
  // KEY_UNKNOWN = 108,
  KEY_F10 = 109,
  KEY_APPLICATION = 110,
  KEY_F12 = 111,
  // KEY_UNKNOWN = 112,
  KEY_PAUSE = 113,
  KEY_INSERT = 114,
  KEY_HOME = 115,
  KEY_PAGEUP = 116,
  KEY_DELETE = 117,
  KEY_F4 = 118,
  KEY_END = 119,
  KEY_F2 = 120,
  KEY_PAGEDOWN = 121,
  KEY_F1 = 122,
  KEY_LEFT = 123,
  KEY_RIGHT = 124,
  KEY_DOWN = 125,
  KEY_UP = 126,

  // Combination Keys
  KEY_SHIFT = 128,
  KEY_CTRL,
  KEY_ALT,
  KEY_META,
  NUMBER_OF_KEYS,
};

typedef enum mouse_button_type_t {
  MOUSE_BUTTON_NONE,
  MOUSE_BUTTON_LEFT,
  MOUSE_BUTTON_MIDDLE,
  MOUSE_BUTTON_RIGHT,
} mouse_button_type_t;

typedef struct button_t {
  bool down;
  int pressed;
  int released;
} button_t;

typedef struct clocks_t {
  int delta_ticks;
  f32 delta_secs;

  u64 ticks;
  u32 frame_count;

  u64 ticks_per_sec;
  u64 start_ticks;
} clocks_t;

typedef struct mouse_t {
  bool moved;
  v2 position;
  v2 delta_position;

  bool scrolled;
  v2 delta_scroll;

  bool capture;

  button_t left_button;
  button_t middle_button; // TODO: Figure out how to handle this in macOS
  button_t right_button;
} mouse_t;

typedef struct window_t {
  v2 size_in_pixels;
  v2 size_in_points;
  f32 scale;
} window_t;

typedef struct display_t {
  v2 size_in_pixels;
  v2 size_in_points;
  f32 scale;
} display_t;

typedef struct app_t {
  window_t window;
  display_t display;
  clocks_t clocks;
  button_t keys[NUMBER_OF_KEYS];
  mouse_t mouse;
  f32 render_scale;
} app_t;

