# Overview

This is a testbed for learning the Metal API and for developing a MacOS platform layer from scratch for a game written in C. It's designed to compile from the command line, with Xcode only used for debugging.

Currently the project has no third-party dependencies and will build on MacOS if the Xcode command line tools are installed.

# Running

```sh
# Build
./m

# Run
./build/app
```

Run the build script to live-reload the shaders.

# Controls

- Press `o` to switch between orbit and first person cameras.
- Press `[` or `]` to change the rendering resolution.

__Orbit Camera__

Rotate around the center point with the arrow keys.

__First Person__

Move and strafe with WASD. Use the arrow keys to look around.

