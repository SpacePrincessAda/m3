#include <stdio.h>

#include "mac_inc.h" // PCH

#include "types.h"
#include "cave_math.h"

// TODO: Pass this into the application delegate
static int initial_window_width = 840;
static int initial_window_height = 480;
static const char* window_title = "app";

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
    initWithContentRect:NSMakeRect(
        0, 0, initial_window_width, initial_window_height)
    styleMask:window_style
    backing:NSBackingStoreBuffered
    defer:NO];

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
- (void)windowDidResize:(NSNotification*)notification {}
- (void)windowDidMove:(NSNotification*)notification {}
- (void)windowDidMiniaturize:(NSNotification*)notification {}
- (void)windowDidDeminiaturize:(NSNotification*)notification {}
- (void)windowDidBecomeKey:(NSNotification*)notification {}
- (void)windowDidResignKey:(NSNotification*)notification {}
@end

@implementation MetalKitView
{
  id<MTLCommandQueue> _command_queue;
  f64 mach_to_ms;
  u64 last_time;
  f64 delta_time;
}

-(nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device {
  self = [super init];
  if (self) {
    [self setDevice: device];
    [self _setupTimer];
    [self _setupMetal];
  }
  return self;
}

- (void)_setupTimer {
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  mach_to_ms = (f64)info.numer / (f64)info.denom * 1e-6;
  last_time = mach_absolute_time();
  delta_time = 1.0f/60.0f;
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

- (BOOL)canBecomeKey {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)keyDown:(NSEvent*)event {
  // TODO: Input handling 
}

- (void)drawRect:(CGRect)rect {
  // v2 window_size = {
  //   rect.size.width,
  //   rect.size.height,
  // };

  id<MTLTexture> texture = [[self currentDrawable] texture];
  MTLRenderPassDescriptor *pass = [self currentRenderPassDescriptor];

  pass.colorAttachments[0].texture = texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(0.16f, 0.17f, 0.2f, 1.0f);

  id<MTLCommandBuffer> command_buffer = [_command_queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [
    command_buffer renderCommandEncoderWithDescriptor:pass
  ];
  [encoder endEncoding];

  [command_buffer presentDrawable:[self currentDrawable]];
  [command_buffer commit];

  // Update timer
  u64 new_time = mach_absolute_time();
  delta_time = (new_time - last_time) * mach_to_ms;
  last_time = mach_absolute_time();
  // printf("time: %f\n", delta_time);
}
@end

void macos_create_menu(void) {
  NSMenu* menu_bar = [NSMenu new];
  [NSApp setMainMenu:menu_bar];

  // App menu
  NSMenuItem* app_menu_item = [NSMenuItem new];
  [menu_bar addItem:app_menu_item];
  NSMenuItem* quit_item = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                              action:@selector(terminate:)
                                              keyEquivalent:@"q"];

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

