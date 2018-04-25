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
xcrun -sdk macosx metal -Wno-unused-variable $SRC/shaders/standard.metal -o $BUILD/standard.air
xcrun -sdk macosx metallib $BUILD/standard.air -o $BUILD/standard.metallib

# compile executable
$CXX -include-pch $PCH_OUT -g $CXX_FLAGS $OSX_FLAGS "$SRC/$ENTRY" -o "$BUILD/$APP"

# ctime end
LAST_ERROR=$?
$CTIME_EXEC -end "$CTIME_TIMING_FILE" $LAST_ERROR

