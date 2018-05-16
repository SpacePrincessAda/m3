#!/bin/sh

APP="app"
SRC="src"
BUILD="build"
CXX="clang"
ENTRY="main.m"

CXX_FLAGS="-std=c11 -fno-objc-arc"
OSX_FLAGS="-framework Foundation -framework Cocoa -framework Quartz -framework Metal -framework MetalKit"

PCH_IN="$SRC/mac_inc.h"
PCH_OUT="temp/mac_inc.pch"

CTIME_EXEC="utils/ctime"
CTIME_SOURCE="utils/ctime.c"
CTIME_TIMING_FILE=".build.ctm"

MTL_C="xcrun -sdk macosx metal -gline-tables-only"
MTL_C_FLAGS="-Wno-unused-variable -mmacosx-version-min=10.11 -std=osx-metal1.1 -gline-tables-only"
MTLLIB_C="xcrun -sdk macosx metallib"

# Abort on first error
set -e

# Build PCH
if [ ! -f "$PCH_OUT" ]; then
  echo "PCH not found, building PCH..."
  mkdir -p temp
  $CXX $CXX_FLAGS -x objective-c-header $PCH_IN -relocatable-pch -o $PCH_OUT
  echo "Done."
fi

# build ctime
if [ ! -f "$CTIME_EXEC" ]; then
  $CXX -O2 -Wno-unused-result "$CTIME_SOURCE" -o "$CTIME_EXEC"
fi

# ctime start
$CTIME_EXEC -begin "$CTIME_TIMING_FILE"

mkdir -p $BUILD

# compile shader library
$MTL_C $MTL_C_FLAGS $SRC/shaders/ray_marcher.metal -o $BUILD/standard.air
# $MTL_C $MTL_C_FLAGS $SRC/shaders/path_tracer.metal -o $BUILD/standard.air
# $MTL_C $MTL_C_FLAGS $SRC/shaders/ray_tracer.metal -o $BUILD/standard.air
$MTL_C $MTL_C_FLAGS $SRC/shaders/dynamic_resolution.metal -o $BUILD/dynamic_resolution.air
$MTL_C $MTL_C_FLAGS $SRC/shaders/ui.metal -o $BUILD/ui.air

# build shader library and move it into place
# the move is important, otherwise the app might try to load it while it's building
$MTLLIB_C $BUILD/*.air -o $BUILD/temp.metallib
mv $BUILD/temp.metallib $BUILD/standard.metallib

# compile executable
$CXX -include-pch $PCH_OUT -g $CXX_FLAGS $OSX_FLAGS "$SRC/$ENTRY" -o "$BUILD/$APP"

# ctime end
LAST_ERROR=$?
$CTIME_EXEC -end "$CTIME_TIMING_FILE" $LAST_ERROR

