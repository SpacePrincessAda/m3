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

static void update_render_camera(camera_t* c, float aspect, render_camera_t* r) {
  float theta = c->vfov * M_PI / 180;
  float half_height = tanf(theta/2);
  float half_width = aspect * half_height;
  v3 w = unit3(sub3(c->target, c->position));
  // v3 w = unit3(sub3(c->position, c->target));
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
  // [[mtk_view layer] setMagnificationFilter:kCAFilterNearest];

  [window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  return YES;
}
@end

@implementation WindowDelegate
- (BOOL)windowShouldClose:(id)sender {
  return YES;
}

// TODO: Implement these!
// - (void)windowDidResize:(NSNotification*)notification {}
// - (void)windowDidMove:(NSNotification*)notification {}
// - (void)windowDidMiniaturize:(NSNotification*)notification {}
// - (void)windowDidDeminiaturize:(NSNotification*)notification {}
// - (void)windowDidBecomeKey:(NSNotification*)notification {}
// - (void)windowDidResignKey:(NSNotification*)notification {}
@end

@implementation MetalKitView
{
  id<MTLCommandQueue> _command_queue;
  id<MTLRenderPipelineState> _standard_pso;

  fs_params_t fs_params;

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
  init_clocks();
  init_world(&app, &world);
}

- (void)_createPSO {
  if (_standard_pso) {
    [_standard_pso release];
  }

  // Load shaders
  id<MTLLibrary> library = load_shader_library(self.device, shader_lib_path);
  id<MTLFunction> vertex_func = [library newFunctionWithName:@"screen_vs_main"];
  id<MTLFunction> fragment_func = [library newFunctionWithName:@"screen_fs_main"];

  // PSO
  MTLRenderPipelineDescriptor *psd = [MTLRenderPipelineDescriptor new];
  psd.label = @"Standard Pipeline";
  psd.vertexFunction = vertex_func;
  psd.fragmentFunction = fragment_func;
  psd.colorAttachments[0].pixelFormat = self.colorPixelFormat;
  psd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
  psd.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

  NSError *error = nil;
  _standard_pso = [self.device newRenderPipelineStateWithDescriptor:psd error:&error];
  if (!_standard_pso) {
    NSLog(@"Error occurred when creating render pipeline state: %@", error);
  }
  [psd release];
  [vertex_func release];
  [fragment_func release];
  [library release];
}

- (void)_setupMetal {
  [self setPreferredFramesPerSecond:60];
  [self setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
  [self setDepthStencilPixelFormat:MTLPixelFormatDepth32Float_Stencil8];
  [self setSampleCount:1];

  _command_queue = [self.device newCommandQueue];
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

- (void)keyDown:(NSEvent*)event {
  u8 code = [event keyCode];
  update_button(&app.keys[code], true);
}

- (void)keyUp:(NSEvent*)event {
  u8 code = [event keyCode];
  update_button(&app.keys[code], false);
}

- (void)_loadAssets {
  time_t new_shader_lib_ts = get_last_write_time(shader_lib_path);
  if (new_shader_lib_ts != shader_lib_ts) {
    [self _createPSO];
    shader_lib_ts = new_shader_lib_ts;
    printf("shader library loaded\n");
  }
}

- (void)drawRect:(CGRect)rect {
  [self _loadAssets];

  CGSize s = [self drawableSize];
  float aspect = s.width/s.height;

  update_clocks();
  update_and_render(&app, &world, &fs_params.debug_params);
  update_render_camera(&world.camera, aspect, &fs_params.camera);

  fs_params.frame_count = app.clocks.frame_count;
  fs_params.viewport_size.x = s.width;
  fs_params.viewport_size.y = s.height;

  id<MTLTexture> texture = [[self currentDrawable] texture];
  MTLRenderPassDescriptor *pass = [self currentRenderPassDescriptor];

  pass.colorAttachments[0].texture = texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(0.16f, 0.17f, 0.2f, 1.0f);

  id<MTLCommandBuffer> command_buffer = [_command_queue commandBuffer];
  id<MTLRenderCommandEncoder> enc = [
    command_buffer renderCommandEncoderWithDescriptor:pass
  ];

  [enc setRenderPipelineState:_standard_pso];
  
  [enc setFragmentBytes:&fs_params
                     length:sizeof(fs_params_t)
                    atIndex:0];

  // Full screen triangle
  [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [enc endEncoding];

  [command_buffer presentDrawable:[self currentDrawable]];
  [command_buffer commit];

  // Reset keys
  for (int i=0; i < NUMBER_OF_KEYS; i++) {
    reset_button(&app.keys[i]);
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

