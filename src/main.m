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

// TODO: Pass this into the application delegate
static int initial_window_width = 840;
static int initial_window_height = 480;
static const char* window_title = "app";
static app_t app = {};
static world_t world = {};

const char* shader_lib_path = "build/standard.metallib";

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

@implementation MetalKitView
{
  id<MTLCommandQueue> _command_queue;
  id<MTLRenderPipelineState> _standard_pso;
  id<MTLRenderPipelineState> _dynamic_res_pso;
  id<MTLTexture> _offscreen_buffer;

  fs_params_t fs_params;
  dr_params_t dr_params;

  time_t shader_lib_ts;
}

-(nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device {
  self = [super init];
  if (self) {
    [self setDevice: device];
    [self _setupApp];
    [self _setupMetal];
  }
  return self;
}

- (void)_setupApp {
  app.render_scale = 1.0f;
  init_clocks();
  init_world(&app, &world);
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

    [library release];
    library = nil;
  }
}

- (void)_setupMetal {
  [self setPreferredFramesPerSecond:60];
  [self setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
  // [self setDepthStencilPixelFormat:MTLPixelFormatDepth32Float_Stencil8];
  [self setSampleCount:1];

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

- (void)_render {
  fs_params.frame_count = app.clocks.frame_count;
  fs_params.viewport_size.x = app.window.size_in_pixels.x;
  fs_params.viewport_size.y = app.window.size_in_pixels.y;

  dr_params.osb_to_rt_ratio.x = (app.window.size_in_pixels.x*app.render_scale) / app.display.size_in_pixels.x;
  dr_params.osb_to_rt_ratio.y = (app.window.size_in_pixels.y*app.render_scale) / app.display.size_in_pixels.y;

  id<MTLCommandBuffer> command_buffer = [_command_queue commandBuffer];

  // Render to offscreen buffer
  {
    MTLRenderPassDescriptor *pass = [self currentRenderPassDescriptor];
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
  {
    id<MTLTexture> texture = [[self currentDrawable] texture];
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

    [command_buffer presentDrawable:[self currentDrawable]];
  }

  [command_buffer commit];
}

- (void)drawRect:(CGRect)rect {
  @autoreleasepool {
    [self _updateWindowAndDisplaySize];
    [self _loadAssets];

    update_button(&app.keys[KEY_SHIFT], app.keys[KEY_LSHIFT].down || app.keys[KEY_RSHIFT].down);
    update_button(&app.keys[KEY_ALT], app.keys[KEY_LALT].down || app.keys[KEY_RALT].down);
    update_button(&app.keys[KEY_CTRL], app.keys[KEY_LCTRL].down || app.keys[KEY_RCTRL].down);
    update_button(&app.keys[KEY_META], app.keys[KEY_LMETA].down || app.keys[KEY_RMETA].down);

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

