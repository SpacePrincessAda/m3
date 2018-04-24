#!/bin/sh

CXX="clang"

CXX_FLAGS="-std=c99 -fno-objc-arc"
OSX_FLAGS="-framework Foundation -framework Cocoa -framework Quartz -framework Metal -framework MetalKit"
ENTRY="src/main.m"
OUTPUT="build/app"

PCH_IN="src/mac_inc.h"
PCH_OUT="temp/mac_inc.pch"

CTIME_EXEC="utils/ctime"
CTIME_SOURCE="utils/ctime.c"
CTIME_TIMING_FILE=".build.ctm"

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

mkdir -p build
$CXX -include-pch $PCH_OUT -g $CXX_FLAGS $OSX_FLAGS $ENTRY -o $OUTPUT

# ctime end
LAST_ERROR=$?
$CTIME_EXEC -end "$CTIME_TIMING_FILE" $LAST_ERROR

