#!/bin/bash
# Builds everything the port ships that is not game data, inside build/Dockerfile (Ubuntu 20.04):
#   box64 (aarch64, dynarec on)           -> port/20minutestilldawn/box64/box64
#   box64's x86_64 libgcc_s               -> port/20minutestilldawn/box64/box64-x86_64-linux-gnu/
#   glespass libGL.so.1 (aarch64)         -> port/20minutestilldawn/glespass/libGL.so.1
# Usage: build/build.sh [box64 git tag]
set -e
TAG="${1:-v0.4.4}"
R="$(cd "$(dirname "$0")/.." && pwd)"
P=port/20minutestilldawn
docker build -q -t 20mtd-portmaster-build "$R/build" >/dev/null
mkdir -p "$R/build/src"
[ -d "$R/build/src/box64" ] || git clone -q --depth 1 --branch "$TAG" https://github.com/ptitSeb/box64.git "$R/build/src/box64"
docker run --rm -u "$(id -u):$(id -g)" -v "$R:/repo" 20mtd-portmaster-build bash -c '
  set -e
  cd /repo/build/src/box64 && mkdir -p build-aarch64 && cd build-aarch64
  cmake .. -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_ASM_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 >/dev/null
  make -j"$(nproc)" >/dev/null
  aarch64-linux-gnu-strip -o /repo/'"$P"'/box64/box64 box64
  cp /repo/build/src/box64/x64lib/libgcc_s.so.1 /repo/'"$P"'/box64/box64-x86_64-linux-gnu/
  cd /repo/glespass && bash build.sh >/dev/null && cp out/libGL.so.1 /repo/'"$P"'/glespass/
'
