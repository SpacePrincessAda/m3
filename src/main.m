#include <stdio.h>
#include <stdalign.h>
#include <sys/stat.h>
#include <time.h>

#include "mac_inc.h" // PCH

#include "types.h"
#include "cave_math.h"
#include "app.h"
#include "game.h"
#include "game.c"
#include "shader_types.h"

// Not sure if this is a good scale factor. Docs don't say.
#define PRECISE_SCROLLING_SCALE 0.1
#define MAX_BUFFERS_IN_FLIGHT 1

// TODO: Pass this into the application delegate
static int initial_window_width = 840;
static int initial_window_height = 480;
static const char* window_title = "app";
static app_t app = {};
static world_t world = {};

const char* shader_lib_path = "build/standard.metallib";

#define kilobytes(value) ((value)*1024LL)
#define megabytes(value) (kilobytes(value)*1024LL)
#define gigabytes(value) (megabytes(value)*1024LL)

typedef struct memory_arena_t {
  size_t size;
  size_t alignment;
  u8 *base;
  size_t used;
} memory_arena_t;

static void 
init_arena(memory_arena_t* arena, size_t size, void* base) {
  arena->size = size;
  arena->base = (u8*)base;
  arena->used = 0;
}

static void 
reset_arena(memory_arena_t* arena) {
  arena->used = 0;
}

static void* 
push_size(memory_arena_t* arena, size_t size) {
  assert((arena->used + size) <= arena->size);

  void* result = arena->base + arena->used;
  arena->used += size;

  return result;
}

static void update_button(button_t* button, bool down) {
  bool was_down = button->down;
  button->down = down;
  button->pressed += down && !was_down;
  button->released += !down && was_down;
}

static void update_mouse_button(mouse_button_type_t button_type, bool down) {
  button_t* button;
  switch (button_type) {
    case MOUSE_BUTTON_LEFT:
      button = &app.mouse.left_button; break;
    case MOUSE_BUTTON_MIDDLE:
      button = &app.mouse.middle_button; break;
    case MOUSE_BUTTON_RIGHT:
      button = &app.mouse.right_button; break;
    default: return;
  }
  update_button(button, down);
}

static void reset_button(button_t* button) {
  button->pressed = 0;
  button->released = 0;
}

static void init_clocks(void) {
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);

  u64 freq = info.denom;
  freq *= 1000000000;
  freq /= info.numer;
  app.clocks.ticks_per_sec = freq;
  app.clocks.start_ticks = mach_absolute_time();

  app.clocks.frame_count = 0;
}

static void update_clocks(void) {
  u64 ticks = mach_absolute_time() - app.clocks.start_ticks;
  app.clocks.delta_ticks = (int)(ticks - app.clocks.ticks);
  app.clocks.ticks = ticks;

  app.clocks.delta_secs = (f32)app.clocks.delta_ticks / (f32)app.clocks.ticks_per_sec;

  app.clocks.frame_count++;
}

vector_float3 v3_to_float3(v3 a) {
  return (vector_float3){a.x, a.y, a.z};
}

static void update_render_camera(camera_t* c, f32 aspect, render_camera_t* r) {
  f32 theta = c->vfov * M_PI / 180;
  f32 half_height = tanf(theta/2);
  f32 half_width = aspect * half_height;
  v3 w = unit3(sub3(c->target, c->position));
  v3 u = unit3(cross3(c->up, w));
  v3 v = cross3(w, u);

  v3 ll1 = sub3(c->position, mul3(u, half_width));
  v3 ll2 = sub3(ll1, mul3(v, half_height));
  v3 ll3 = add3(ll2, w);

  r->position = v3_to_float3(c->position);
  r->film_h = v3_to_float3(mul3(u, 2*half_width));
  r->film_v = v3_to_float3(mul3(v, 2*half_height));
  r->film_lower_left = v3_to_float3(ll3);
}

typedef struct ui_context_t {
  u32 v_count;
  u32 i_count;
  memory_arena_t varena;
  memory_arena_t iarena;
} ui_context_t;

static void
reset_ui_context(ui_context_t* rs) {
  reset_arena(&rs->varena);
  reset_arena(&rs->iarena);
  rs->v_count = 0;
  rs->i_count = 0;
}

static void 
push_ui_rect(ui_context_t* rs, v2 pos, v2 size, v4 color) {
  render_vert_t* verts = push_size(&rs->varena, sizeof(render_vert_t)*4);
  u16* indices = push_size(&rs->iarena, sizeof(u16)*6);

  verts[0].position = (vector_float2){pos.x, pos.y};
  verts[1].position = (vector_float2){pos.x + size.x, pos.y};
  verts[2].position = (vector_float2){pos.x + size.x, pos.y + size.y};
  verts[3].position = (vector_float2){pos.x, pos.y + size.y};

  verts[0].color = (vector_float4){color.r, color.g, color.b, color.a};
  verts[1].color = (vector_float4){color.r, color.g, color.b, color.a};
  verts[2].color = (vector_float4){color.r, color.g, color.b, color.a};
  verts[3].color = (vector_float4){color.r, color.g, color.b, color.a};

  indices[0] = rs->v_count;
  indices[1] = rs->v_count+1;
  indices[2] = rs->v_count+2;
  indices[3] = rs->v_count;
  indices[4] = rs->v_count+2;
  indices[5] = rs->v_count+3;

  rs->v_count += 4;
  rs->i_count += 6;
}

static int aligned_size(int sz) {
  return (sz + 0xFF) & ~0xFF;
}

typedef struct {
  long size;
  char* contents;
} file_t;

file_t read_file(const char* path) {
  file_t result = {};

  FILE *f = fopen(path, "rb");
  if (f) {
    fseek(f, 0, SEEK_END);
    result.size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    result.contents = (char*)malloc(result.size + 1);
    fread(result.contents, result.size + 1, 1, f);
    fclose(f);
    result.contents[result.size] = 0;
  } else {
    printf("ERROR: Cannot open file %s.\n", path);
  }
  
  return(result);
}

time_t get_last_write_time(const char *filename) {
  time_t last_write_time = 0;

  struct stat status;
  if (stat(filename, &status) == 0) {
    last_write_time = status.st_mtime;
  }

  return (last_write_time);
}

// TODO: better error handling
id<MTLLibrary> compile_shaders_from_source(id<MTLDevice> device, const char* src) {
  NSError* err = NULL;
  id<MTLLibrary> library = [
    device newLibraryWithSource:[NSString stringWithUTF8String:src]
                        options:nil
                          error:&err
  ];
  if (err) {
    puts([err.localizedDescription UTF8String]);
  }
  return library;
}

// TODO: better error handling
id<MTLLibrary> load_shader_library(id<MTLDevice> device, const char* src) {
  NSError* err = NULL;
  id<MTLLibrary> library = [
    device newLibraryWithFile:[NSString stringWithUTF8String:src]
                        error:&err
  ];
  if (err) {
    puts([err.localizedDescription UTF8String]);
  }
  return library;
}

// Interface

@interface App : NSApplication
@end

@interface AppDelegate<NSApplicationDelegate> : NSObject
@end

@interface WindowDelegate<NSWindowDelegate> : NSObject
@end

@interface MetalKitView : MTKView
-(nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device;
@end

// Implementations

// NOTE: Not sure if I even need this
@implementation App
@end

@implementation AppDelegate
{
  id window_delegate;
  id window;

  MTKView* mtk_view;
  id<MTLDevice> mtl_device;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  window_delegate = [[WindowDelegate alloc] init];
  NSUInteger window_style = NSWindowStyleMaskTitled
                          | NSWindowStyleMaskClosable
                          | NSWindowStyleMaskMiniaturizable
                          | NSWindowStyleMaskResizable;

  window = [[NSWindow alloc] 
    initWithContentRect:NSMakeRect(0, 0, initial_window_width, initial_window_height)
              styleMask:window_style
                backing:NSBackingStoreBuffered
                  defer:NO
  ];

  [window setTitle:[NSString stringWithUTF8String:window_title]];
  [window setAcceptsMouseMovedEvents:YES];
  [window center];
  [window setRestorable:YES];
  [window setDelegate:window_delegate];

  mtl_device = MTLCreateSystemDefaultDevice();
  mtk_view = [[MetalKitView alloc] initWithDevice:mtl_device];

  [window setContentView:mtk_view];

  [window makeKeyAndOrderFront:nil];
  
  NSAppearance* appearance = [NSAppearance appearanceNamed: 
         [NSUserDefaults.standardUserDefaults stringForKey:@"AppleInterfaceStyle"] ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight];
  [window setAppearance:appearance];
  [appearance release];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  return YES;
}
@end

@implementation WindowDelegate
- (BOOL)windowShouldClose:(id)sender {
  return YES;
}
@end

#define MAX_FRAME_TIMES 128

@implementation MetalKitView
{
  id<MTLCommandQueue> _command_queue;
  id<MTLRenderPipelineState> _standard_pso;
  id<MTLRenderPipelineState> _dynamic_res_pso;
  id<MTLRenderPipelineState> _ui_pso;
  id<MTLTexture> _offscreen_buffer;

  id<MTLBuffer> _ui_vbuffer;
  id<MTLBuffer> _ui_ibuffer;

  ui_context_t _ui_context;

  fs_params_t fs_params;
  dr_params_t dr_params;
  ui_vs_params_t ui_vs_params;

  bool _capture_mouse;
  u64 cmd_start_time;

  f32 _frame_times[MAX_FRAME_TIMES];
  int _frame_time_ordinal;

  NSUInteger _max_buffers_in_flight;
  dispatch_semaphore_t _frame_boundary_semaphore;

  time_t shader_lib_ts;

  void* _app_memory;
}

-(nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device {
  self = [super init];
  if (self) {
    [self setDevice: device];
    [self _setupApp];
    [self _setupMetal];
    [self _createBuffers];
  }
  return self;
}

- (void)_setupApp {
  app.render_scale = 0.5f;
  init_clocks();
  init_world(&app, &world);
}

- (void)_createBuffers {
  size_t ui_vbuffer_size = aligned_size(sizeof(render_vert_t) * UINT16_MAX);
  size_t ui_ibuffer_size = aligned_size(sizeof(u16) * UINT16_MAX);
  size_t total_size = ui_vbuffer_size + ui_ibuffer_size;

  size_t page_size = getpagesize();
  posix_memalign(&_app_memory, page_size, total_size);

  init_arena(&_ui_context.varena, ui_vbuffer_size, _app_memory);
  init_arena(&_ui_context.iarena, ui_ibuffer_size, 
      (u8*)_app_memory + ui_vbuffer_size);

  _ui_vbuffer = [self.device
     newBufferWithBytesNoCopy:_ui_context.varena.base 
                       length:_ui_context.varena.size
                      options:MTLResourceStorageModeShared
                  deallocator:nil
  ];

  _ui_ibuffer = [self.device
     newBufferWithBytesNoCopy:_ui_context.iarena.base 
                       length:_ui_context.iarena.size
                      options:MTLResourceStorageModeShared
                  deallocator:nil
  ];
}

- (void)_createOffscreenBuffer {
  if (_offscreen_buffer) {
    [_offscreen_buffer release];
  }

  MTLTextureDescriptor *td = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat: self.colorPixelFormat
                                 width: app.display.size_in_pixels.x
                                height: app.display.size_in_pixels.y
                             mipmapped: NO
  ];
  [td setUsage: MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead];
  [td setStorageMode: MTLStorageModePrivate];

  _offscreen_buffer = [self.device newTextureWithDescriptor:td];
}

- (void)_createPSO {
  @autoreleasepool {
    if (_standard_pso) {
      // NOTE: Make sure to release all PSOs that used the library here
      [_standard_pso release];
      [_dynamic_res_pso release];
      [_ui_pso release];
    }

    // Load shaders
    id<MTLLibrary> library = load_shader_library(self.device, shader_lib_path);

    // Standard PSO
    {
      id<MTLFunction> vertex_func = [library newFunctionWithName:@"screen_vs_main"];
      id<MTLFunction> fragment_func = [library newFunctionWithName:@"screen_fs_main"];

      MTLRenderPipelineDescriptor *psd = [MTLRenderPipelineDescriptor new];
      psd.label = @"Offscreen Pipeline";
      psd.vertexFunction = vertex_func;
      psd.fragmentFunction = fragment_func;
      psd.colorAttachments[0].pixelFormat = self.colorPixelFormat;
      // psd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
      // psd.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

      NSError *error = nil;
      _standard_pso = [self.device newRenderPipelineStateWithDescriptor:psd error:&error];
      if (!_standard_pso) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
      }
      [vertex_func release];
      [fragment_func release];
      [psd release];
    }

    // Dynamic Resolution PSO
    {
      id<MTLFunction> vertex_func = [library newFunctionWithName:@"dr_vs_main"];
      id<MTLFunction> fragment_func = [library newFunctionWithName:@"dr_fs_main"];

      MTLRenderPipelineDescriptor *psd = [MTLRenderPipelineDescriptor new];
      psd.label = @"Dynamic Resolution Pipeline";
      psd.vertexFunction = vertex_func;
      psd.fragmentFunction = fragment_func;
      psd.colorAttachments[0].pixelFormat = self.colorPixelFormat;

      NSError *error = nil;
      _dynamic_res_pso = [self.device newRenderPipelineStateWithDescriptor:psd error:&error];
      if (!_dynamic_res_pso) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
      }
      [vertex_func release];
      [fragment_func release];
      [psd release];
    }

    // UI PSO
    {
      id<MTLFunction> vertex_func = [library newFunctionWithName:@"ui_vs_main"];
      id<MTLFunction> fragment_func = [library newFunctionWithName:@"ui_fs_main"];

      MTLVertexDescriptor* vd = [[MTLVertexDescriptor alloc] init];
      vd.attributes[0].format = MTLVertexFormatFloat2;
      vd.attributes[0].bufferIndex = 0;
      vd.attributes[0].offset = 0;

      vd.attributes[1].format = MTLVertexFormatFloat4;
      vd.attributes[1].bufferIndex = 0;
      vd.attributes[1].offset = 2 * 4;

      vd.layouts[0].stride = 6 * 4;
      vd.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

      MTLRenderPipelineDescriptor *psd = [MTLRenderPipelineDescriptor new];
      psd.label = @"UI Pipeline";
      psd.vertexFunction = vertex_func;
      psd.fragmentFunction = fragment_func;
      psd.colorAttachments[0].pixelFormat = self.colorPixelFormat;
      psd.vertexDescriptor = vd;

      NSError *error = nil;
      _ui_pso = [self.device newRenderPipelineStateWithDescriptor:psd error:&error];
      if (!_ui_pso) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
      }
      [vd release];
      [vertex_func release];
      [fragment_func release];
      [psd release];
    }

    [library release];
    library = nil;
  }
}

- (void)_setupMetal {
  [self setPreferredFramesPerSecond:60];
  [self setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
  // [self setDepthStencilPixelFormat:MTLPixelFormatDepth32Float_Stencil8];
  [self setSampleCount:1];

  _frame_boundary_semaphore = dispatch_semaphore_create(MAX_BUFFERS_IN_FLIGHT);

  _command_queue = [self.device newCommandQueue];
  [self _updateWindowAndDisplaySize];
}

- (BOOL)isOpaque {
  return YES;
}

- (BOOL)canBecomeKeyView {
  return YES;
}

- (BOOL)canBecomeKey {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

// TODO: Mouse support via IO/Kit.
// The deltaX and deltaY properties here only give per pixel precision.
// The OS has sub-pixel mouse input precision available and it uses it for
// locationInWindow. However, that doesn't actually work out if you need to capture
// mouse input for FPS style controls. So, for now, first person mouse look will
// just be kinda low precision.
- (void)mouseMoved:(NSEvent*)event {
  app.mouse.moved = true;
  NSPoint location = [event locationInWindow];
  app.mouse.delta_position.x = [event deltaX];
  app.mouse.delta_position.y = [event deltaY];
  app.mouse.position.x = location.x;
  app.mouse.position.y = app.window.size_in_points.y - location.y;
}

- (void)mouseDown:(NSEvent*)event {
  update_mouse_button(MOUSE_BUTTON_LEFT, true);
}

- (void)mouseUp:(NSEvent*)event {
  update_mouse_button(MOUSE_BUTTON_LEFT, false);
}

- (void)rightMouseDown:(NSEvent*)event {
  update_mouse_button(MOUSE_BUTTON_RIGHT, true);
}

- (void)rightMouseUp:(NSEvent*)event {
  update_mouse_button(MOUSE_BUTTON_RIGHT, false);
}

- (void)scrollWheel:(NSEvent*)event {
  v2 delta_scroll = {
    [event scrollingDeltaX],
    [event scrollingDeltaY],
  };
  app.mouse.delta_scroll = [event hasPreciseScrollingDeltas] ? 
    mul2(delta_scroll, PRECISE_SCROLLING_SCALE) : delta_scroll;
  app.mouse.scrolled = true;
}

- (void)keyDown:(NSEvent*)event {
  u8 code = [event keyCode];
  update_button(&app.keys[code], true);
}

- (void)keyUp:(NSEvent*)event {
  u8 code = [event keyCode];
  update_button(&app.keys[code], false);
}

- (void)flagsChanged:(NSEvent*)event {
  u8 code = [event keyCode];
  // NOTE: Is there a better way to do this, since there's no way to get up/down state here?
  update_button(&app.keys[code], !app.keys[code].down);
}

- (void)_updateWindowAndDisplaySize {
  NSWindow *window = [self window];

  {
    NSScreen *screen = [window screen];
    NSRect frame = [screen frame];
    f32 bsf = [screen backingScaleFactor];
    v2 screen_size = {
      .x = frame.size.width,
      .y = frame.size.height,
    };

    if (!eq2(screen_size, app.display.size_in_points) || bsf != app.display.scale) {
      app.display.scale = bsf;
      app.display.size_in_points = screen_size;
      app.display.size_in_pixels = mul2(screen_size, bsf);
      // printf("creating offscreen buffer for %0.0fx%0.0f\n", 
      //   app.display.size_in_pixels.x, 
      //   app.display.size_in_pixels.y
      // );
      [self _createOffscreenBuffer];
    }
  }

  {
    // NOTE: This is size of the drawable. Do I actually want size of the window (including titlebar)?
    CGSize s = [self drawableSize];
    f32 bsf = [window backingScaleFactor];
    app.window.scale = bsf;
    app.window.size_in_pixels = (v2){
      s.width,
      s.height,
    };
    app.window.size_in_points = (v2){
      s.width / bsf,
      s.height / bsf,
    };
  }
}

- (void)_loadAssets {
  time_t new_shader_lib_ts = get_last_write_time(shader_lib_path);
  if (new_shader_lib_ts != shader_lib_ts) {
    [self _createPSO];
    shader_lib_ts = new_shader_lib_ts;
    printf("shader library loaded\n");
  }
}

// TODO: move this responsibility into the game code once it can handle render ops
- (void)_drawFrameTimes {
  v4 color = V4(0.67f, 0.69f, 0.75f, 1);
  f32 height_mod = 2.0f;
  f32 gutter_total = 2.0f * (MAX_FRAME_TIMES-2);
  f32 bar_width = (app.window.size_in_pixels.x - gutter_total) / MAX_FRAME_TIMES;
  f32 bar_spacing = 2.0f;

  push_ui_rect(&_ui_context, 
    V2(0,0), 
    V2(app.window.size_in_pixels.x, 33.333f * height_mod), 
    V4(0.16f, 0.17f, 0.2f, 1.0f)
  );

  push_ui_rect(&_ui_context, 
    V2(0, 16.666f * height_mod), 
    V2(app.window.size_in_pixels.x, 2.0f), 
    V4(0.596f, 0.764f, 0.474f, 1)
  );

  push_ui_rect(&_ui_context, 
    V2(0, 33.333f * height_mod), 
    V2(app.window.size_in_pixels.x, 2.0f), 
    V4(0.88f, 0.42f, 0.46f, 1)
  );

  for (int i=0; i < MAX_FRAME_TIMES; i++) {
    int index = (i + (_frame_time_ordinal+1)) % MAX_FRAME_TIMES;
    f32 x = ((f32)i) * (bar_width + bar_spacing);
    f32 h = _frame_times[index] * height_mod;
    push_ui_rect(&_ui_context, V2(x,0), V2(bar_width,h), color);
  }
}

- (void)_render {
  fs_params.frame_count = app.clocks.frame_count;
  fs_params.viewport_size.x = app.window.size_in_pixels.x;
  fs_params.viewport_size.y = app.window.size_in_pixels.y;

  dr_params.osb_to_rt_ratio.x = (app.window.size_in_pixels.x*app.render_scale) / app.display.size_in_pixels.x;
  dr_params.osb_to_rt_ratio.y = (app.window.size_in_pixels.y*app.render_scale) / app.display.size_in_pixels.y;

  v2 viewport_size = {app.window.size_in_pixels.x, app.window.size_in_pixels.y};

  ui_vs_params.view_matrix = (matrix_float4x4){
    (vector_float4){ 2.0f/viewport_size.x,  0.0f,                   0.0f, 0.0f },
    (vector_float4){ 0.0f,                  2.0f/-viewport_size.y,  0.0f, 0.0f },
    (vector_float4){ 0.0f,                  0.0f,                  -1.0f, 0.0f },
    (vector_float4){-1.0f,                  1.0f,                   0.0f, 1.0f },
  };

  id<MTLCommandBuffer> command_buffer = [_command_queue commandBuffer];

  [command_buffer addScheduledHandler:^(id<MTLCommandBuffer> buffer) {
    cmd_start_time = mach_absolute_time();
  }];

#if 1

  // Render to offscreen buffer
  {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = _offscreen_buffer;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.16f, 0.17f, 0.2f, 1.0f);

    id<MTLRenderCommandEncoder> enc = [command_buffer 
      renderCommandEncoderWithDescriptor:pass];
    MTLViewport vp = {
      .width = app.window.size_in_pixels.x*app.render_scale,
      .height = app.window.size_in_pixels.y*app.render_scale,
      .zfar = 1.0,
    };
    [enc setViewport:vp];
    [enc setRenderPipelineState:_standard_pso];
    [enc setFragmentBytes:&fs_params
                       length:sizeof(fs_params_t)
                      atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
  }

  // Display from offscreen buffer
  id<MTLTexture> texture = [[self currentDrawable] texture];
  {
    MTLRenderPassDescriptor *pass = [self currentRenderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.16f, 0.17f, 0.2f, 1.0f);
    id<MTLRenderCommandEncoder> enc = [command_buffer 
      renderCommandEncoderWithDescriptor:pass];
    MTLViewport vp = {
      .width = app.window.size_in_pixels.x,
      .height = app.window.size_in_pixels.y,
      .zfar = 1.0,
    };
    [enc setViewport:vp];
    [enc setRenderPipelineState:_dynamic_res_pso];
    [enc setFragmentTexture:_offscreen_buffer atIndex:0];
    [enc setFragmentBytes:&dr_params
                       length:sizeof(dr_params_t)
                      atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
  }
#endif

  // UI
  {
    MTLRenderPassDescriptor *pass = [self currentRenderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    // pass.colorAttachments[0].clearColor = MTLClearColorMake(0.16f, 0.17f, 0.2f, 1.0f);
    id<MTLRenderCommandEncoder> enc = [command_buffer 
      renderCommandEncoderWithDescriptor:pass];
    MTLViewport vp = {
      .width = app.window.size_in_pixels.x,
      .height = app.window.size_in_pixels.y,
      .zfar = 1.0,
    };
    [enc setViewport:vp];
    [enc setRenderPipelineState:_ui_pso];
    [enc setVertexBuffer:_ui_vbuffer
                  offset:0
                 atIndex:0
    ];
    [enc setVertexBytes:&ui_vs_params
                       length:sizeof(ui_vs_params_t)
                      atIndex:1];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:_ui_context.i_count
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:_ui_ibuffer
             indexBufferOffset:0
    ];
    [enc endEncoding];
  }
  [command_buffer presentDrawable:[self currentDrawable]];

  dispatch_semaphore_t semaphore = _frame_boundary_semaphore;
  [command_buffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
    // GPU work is complete
    // Signal the semaphore to start the CPU work
    dispatch_semaphore_signal(semaphore);
    u64 cmd_end_time = mach_absolute_time();
    u64 total_time = cmd_end_time - cmd_start_time;
    f32 t = (f64)(total_time * 1000) / (f64)(app.clocks.ticks_per_sec);
    _frame_time_ordinal = app.clocks.frame_count % MAX_FRAME_TIMES;
    _frame_times[_frame_time_ordinal] = t;
  }];

  [command_buffer commit];
}

- (void)_captureMouse {
  CGDisplayHideCursor(kCGDirectMainDisplay);
  CGAssociateMouseAndMouseCursorPosition(false);
}

- (void)_releaseMouse {
  CGDisplayShowCursor(kCGDirectMainDisplay);
  CGAssociateMouseAndMouseCursorPosition(true);
}

- (void)drawRect:(CGRect)rect {
  @autoreleasepool {
    [self _updateWindowAndDisplaySize];
    [self _loadAssets];

    dispatch_semaphore_wait(_frame_boundary_semaphore, DISPATCH_TIME_FOREVER);

    if (_capture_mouse != app.mouse.capture) {
      app.mouse.capture ? [self _captureMouse] : [self _releaseMouse];
      _capture_mouse = app.mouse.capture;
    }

    update_button(&app.keys[KEY_SHIFT], app.keys[KEY_LSHIFT].down || app.keys[KEY_RSHIFT].down);
    update_button(&app.keys[KEY_ALT], app.keys[KEY_LALT].down || app.keys[KEY_RALT].down);
    update_button(&app.keys[KEY_CTRL], app.keys[KEY_LCTRL].down || app.keys[KEY_RCTRL].down);
    update_button(&app.keys[KEY_META], app.keys[KEY_LMETA].down || app.keys[KEY_RMETA].down);

    reset_ui_context(&_ui_context);

    if (app.keys[KEY_F].pressed) {
      app.show_frame_times = !app.show_frame_times;
    }

    if (app.show_frame_times) {
      [self _drawFrameTimes];
    }

    update_clocks();
    update_and_render(&app, &world, &fs_params.debug_params);
    update_render_camera(&world.camera, aspect2(app.window.size_in_pixels), &fs_params.camera);

    [self _render];

    // Reset keys
    for (int i=0; i < NUMBER_OF_KEYS; i++) {
      reset_button(&app.keys[i]);
    }

    // Reset mouse
    app.mouse.moved = false;
    app.mouse.scrolled = false;
    app.mouse.delta_position.x = 0;
    app.mouse.delta_position.y = 0;
    app.mouse.delta_scroll.x = 0;
    app.mouse.delta_scroll.y = 0;
    reset_button(&app.mouse.left_button);
    reset_button(&app.mouse.middle_button);
    reset_button(&app.mouse.right_button);
  }
}
@end

void macos_create_menu(void) {
  NSMenu* menu_bar = [NSMenu new];
  [NSApp setMainMenu:menu_bar];

  // App menu
  NSMenuItem* app_menu_item = [NSMenuItem new];
  [menu_bar addItem:app_menu_item];
  NSMenuItem* quit_item = [[NSMenuItem alloc] 
    initWithTitle:@"Quit"
           action:@selector(terminate:)
    keyEquivalent:@"q"
  ];

  NSMenu* app_menu = [NSMenu new];
  [app_menu addItem:quit_item];
  [app_menu_item setSubmenu:app_menu];
}

int main(int argc, char **argv) {
  [App sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  macos_create_menu();
  id delegate = [[AppDelegate alloc] init];
  [NSApp setDelegate:delegate];
  [NSApp activateIgnoringOtherApps:YES];
  [NSApp run];
  return 0;
}

